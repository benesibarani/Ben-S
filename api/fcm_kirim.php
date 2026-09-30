<?php
/**
 * RTS Panel By Bene - Pengirim Pemberitahuan HP (Firebase Cloud Messaging)
 *
 * Berkas ini BUKAN endpoint yang dipanggil aplikasi. Berkas ini hanya berisi
 * fungsi bantuan yang dipakai berkas lain:
 *
 *   - public_html/api/request_create.php  (pengajuan baru -> ADMIN & ASS)
 *   - public_html/api/request_action.php  (disetujui / ditolak -> pengirim)
 *   - public_html/inbox.php               (disetujui / ditolak dari website)
 *
 * Cara kerja singkat:
 *   1. Aplikasi di HP mengirim "token perangkat" ke server melalui
 *      api/device_token.php, dan token itu disimpan di tabel rts_device_tokens.
 *   2. Berkas ini membaca token perangkat milik penerima, lalu meminta Google
 *      mengirim pemberitahuan ke HP tersebut.
 *
 * Bila Firebase belum disiapkan (berkas kunci belum ada), seluruh fungsi di
 * berkas ini diam dan mengembalikan 0 - tidak ada yang error, pemberitahuan
 * di dalam aplikasi tetap berjalan seperti biasa.
 */

// Blokir bila berkas ini dibuka langsung dari browser.
if (basename((string) ($_SERVER['SCRIPT_FILENAME'] ?? '')) === basename(__FILE__)) {
    http_response_code(403);
    exit('Akses langsung tidak diizinkan.');
}

/* =============================================================================
 * 1. LOKASI BERKAS KUNCI
 * ========================================================================== */

if (!function_exists('rts_fcm_berkas_kunci')) {
    /**
     * Berkas kunci Firebase (service account) SENGAJA diletakkan DI LUAR
     * public_html supaya tidak dapat diunduh dari internet.
     *
     * Susunan folder hosting:
     *   /home/<akun>/rts_fcm_service_account.json      <- berkas kunci
     *   /home/<akun>/public_html/api/fcm_kirim.php     <- berkas ini
     */
    function rts_fcm_berkas_kunci(): string
    {
        $luar = dirname(__DIR__, 2) . '/rts_fcm_service_account.json';

        if (is_file($luar)) {
            return $luar;
        }

        // Cadangan: bila berkas diletakkan di dalam folder api.
        // (Kurang aman karena bisa diunduh; sebaiknya pindahkan ke luar.)
        $dalam = __DIR__ . '/rts_fcm_service_account.json';

        return is_file($dalam) ? $dalam : $luar;
    }
}

if (!function_exists('rts_fcm_siap')) {
    /** Apakah Firebase sudah disiapkan dan siap dipakai? */
    function rts_fcm_siap(): bool
    {
        static $siap = null;

        if ($siap !== null) {
            return $siap;
        }

        $siap = false;
        $berkas = rts_fcm_berkas_kunci();

        if (!is_file($berkas)) {
            return $siap;
        }

        $isi = @file_get_contents($berkas);

        if ($isi === false) {
            return $siap;
        }

        $kunci = json_decode($isi, true);

        if (!is_array($kunci)) {
            return $siap;
        }

        $siap = !empty($kunci['client_email'])
            && !empty($kunci['private_key'])
            && !empty($kunci['project_id']);

        return $siap;
    }
}

/* =============================================================================
 * 2. PERMINTAAN HTTP (tanpa pustaka tambahan)
 * ========================================================================== */

if (!function_exists('rts_fcm_http')) {
    /**
     * Mengirim permintaan HTTP sederhana.
     * Memakai cURL bila tersedia; bila tidak, memakai file_get_contents.
     *
     * @return array{kode: int, isi: string, galat: string}
     */
    function rts_fcm_http(string $url, array $headers, ?string $body = null, string $metode = 'POST'): array
    {
        $hasil = ['kode' => 0, 'isi' => '', 'galat' => ''];

        if (function_exists('curl_init')) {
            $ch = curl_init($url);

            curl_setopt_array($ch, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => $headers,
                CURLOPT_CUSTOMREQUEST => $metode,
                CURLOPT_TIMEOUT => 15,
                CURLOPT_CONNECTTIMEOUT => 8,
                CURLOPT_SSL_VERIFYPEER => true,
            ]);

            if ($body !== null) {
                curl_setopt($ch, CURLOPT_POSTFIELDS, $body);
            }

            $isi = curl_exec($ch);
            $kode = (int) curl_getinfo($ch, CURLINFO_RESPONSE_CODE);

            if ($isi === false) {
                $hasil['galat'] = (string) curl_error($ch);
            } else {
                $hasil['isi'] = (string) $isi;
                $hasil['kode'] = $kode;
            }

            curl_close($ch);

            return $hasil;
        }

        // Cadangan tanpa cURL.
        $susun = [
            'method' => $metode,
            'header' => implode("\r\n", $headers),
            'timeout' => 15,
            'ignore_errors' => true,
        ];

        if ($body !== null) {
            $susun['content'] = $body;
        }

        $isi = @file_get_contents($url, false, stream_context_create(['http' => $susun]));

        if ($isi === false) {
            $hasil['galat'] = 'Permintaan HTTP gagal.';
            return $hasil;
        }

        $hasil['isi'] = (string) $isi;

        foreach ($http_response_header ?? [] as $baris) {
            if (preg_match('#^HTTP/\S+\s+(\d{3})#', $baris, $cocok)) {
                $hasil['kode'] = (int) $cocok[1];
            }
        }

        return $hasil;
    }
}

/* =============================================================================
 * 3. TIKET AKSES GOOGLE (JWT -> access token)
 * ========================================================================== */

if (!function_exists('rts_fcm_base64url')) {
    function rts_fcm_base64url(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }
}

if (!function_exists('rts_fcm_akses_token')) {
    /**
     * Mengambil access token Google (berlaku 1 jam) dengan menandatangani JWT
     * memakai kunci pribadi dari berkas service account. Hasilnya disimpan
     * sementara di berkas cache supaya tidak meminta ulang setiap kali kirim.
     */
    function rts_fcm_akses_token(): ?string
    {
        static $token = null;
        static $sudahDicoba = false;

        if ($sudahDicoba) {
            return $token;
        }

        $sudahDicoba = true;

        if (!rts_fcm_siap()) {
            return null;
        }

        $berkasKunci = rts_fcm_berkas_kunci();
        $kunci = json_decode((string) @file_get_contents($berkasKunci), true);

        if (!is_array($kunci)) {
            return null;
        }

        /* ---------------------------------------------- 1. Cek berkas cache */
        $berkasCache = dirname($berkasKunci) . '/rts_fcm_token_cache.json';
        $dirCache = @dirname($berkasCache);

        if (!is_dir($dirCache) || !is_writable($dirCache)) {
            $berkasCache = sys_get_temp_dir() . '/rts_fcm_token_cache.json';
        }

        if (is_file($berkasCache)) {
            $cache = json_decode((string) @file_get_contents($berkasCache), true);

            if (
                is_array($cache)
                && !empty($cache['token'])
                && !empty($cache['kedaluwarsa'])
                && (int) $cache['kedaluwarsa'] > (time() + 90)
            ) {
                $token = (string) $cache['token'];
                return $token;
            }
        }

        /* --------------------------------------------------- 2. Buat JWT baru */
        $waktu = time();
        $kepala = ['alg' => 'RS256', 'typ' => 'JWT'];
        $isi = [
            'iss' => (string) $kunci['client_email'],
            'scope' => 'https://www.googleapis.com/auth/firebase.messaging',
            'aud' => (string) ($kunci['token_uri'] ?? 'https://oauth2.googleapis.com/token'),
            'iat' => $waktu,
            'exp' => $waktu + 3600,
        ];

        $tanda = rts_fcm_base64url((string) json_encode($kepala)) . '.'
            . rts_fcm_base64url((string) json_encode($isi));

        $kunciPribadi = openssl_pkey_get_private((string) $kunci['private_key']);

        if ($kunciPribadi === false) {
            error_log('RTS FCM: kunci pribadi pada berkas service account tidak terbaca.');
            return null;
        }

        $tangan = '';
        $berhasil = openssl_sign($tanda, $tangan, $kunciPribadi, OPENSSL_ALGO_SHA256);
        @openssl_free_key($kunciPribadi);

        if (!$berhasil) {
            error_log('RTS FCM: gagal menandatangani JWT.');
            return null;
        }

        $jwt = $tanda . '.' . rts_fcm_base64url($tangan);

        /* ----------------------------------- 3. Tukar JWT menjadi access token */
        $alamatToken = (string) ($kunci['token_uri'] ?? 'https://oauth2.googleapis.com/token');
        $body = http_build_query([
            'grant_type' => 'urn:ietf:params:oauth:grant-type:jwt-bearer',
            'assertion' => $jwt,
        ]);

        $balasan = rts_fcm_http(
            $alamatToken,
            ['Content-Type: application/x-www-form-urlencoded'],
            $body
        );

        $data = json_decode($balasan['isi'], true);

        if (!is_array($data) || empty($data['access_token'])) {
            error_log('RTS FCM: gagal mengambil access token. ' . substr($balasan['isi'], 0, 300));
            return null;
        }

        $token = (string) $data['access_token'];
        $masa = (int) ($data['expires_in'] ?? 3600);

        @file_put_contents(
            $berkasCache,
            (string) json_encode([
                'token' => $token,
                'kedaluwarsa' => time() + max(60, $masa - 120),
            ]),
            LOCK_EX
        );

        return $token;
    }
}

/* =============================================================================
 * 4. MENGIRIM SATU PEMBERITAHUAN KE SATU HP
 * ========================================================================== */

if (!function_exists('rts_fcm_kirim_token')) {
    /**
     * @return array{kode: int, ok: bool, token_mati: bool, keterangan: string}
     */
    function rts_fcm_kirim_token(string $tokenHp, string $judul, string $pesan, array $data = []): array
    {
        $kosong = ['kode' => 0, 'ok' => false, 'token_mati' => false, 'keterangan' => ''];

        if (!rts_fcm_siap()) {
            return $kosong;
        }

        $tiket = rts_fcm_akses_token();

        if ($tiket === null) {
            return $kosong;
        }

        $kunci = json_decode((string) @file_get_contents(rts_fcm_berkas_kunci()), true);
        $idProyek = (string) ($kunci['project_id'] ?? '');

        if ($idProyek === '') {
            return $kosong;
        }

        // Nilai pada data FCM wajib berupa teks.
        $dataBersih = [];
        foreach ($data as $nama => $nilai) {
            $dataBersih[(string) $nama] = (string) $nilai;
        }

        $pesanFcm = [
            'message' => [
                'token' => $tokenHp,
                'notification' => [
                    'title' => $judul,
                    'body' => $pesan,
                ],
                'data' => $dataBersih,
                'android' => [
                    // prioritas tinggi: dikirim segera, termasuk saat aplikasi
                    // sedang ditutup / tidak dipakai
                    'priority' => 'high',
                    'notification' => [
                        'channel_id' => 'rts_panel_pemberitahuan',
                        'sound' => 'default',
                    ],
                ],
            ],
        ];

        $balasan = rts_fcm_http(
            'https://fcm.googleapis.com/v1/projects/' . rawurlencode($idProyek) . '/messages:send',
            [
                'Authorization: Bearer ' . $tiket,
                'Content-Type: application/json; charset=utf-8',
            ],
            (string) json_encode($pesanFcm)
        );

        $data = json_decode($balasan['isi'], true);
        $kode = $balasan['kode'];

        if ($kode >= 200 && $kode < 300) {
            return ['kode' => $kode, 'ok' => true, 'token_mati' => false, 'keterangan' => ''];
        }

        $alasan = '';

        if (is_array($data) && isset($data['error'])) {
            $alasan = (string) ($data['error']['status'] ?? '');

            if ($alasan === '') {
                $alasan = (string) ($data['error']['message'] ?? '');
            }
        }

        // Token yang sudah tidak dipakai lagi harus dibuang, agar tidak dicoba
        // terus setiap kali ada pemberitahuan.
        $tokenMati = ($kode === 404)
            || ($alasan === 'UNREGISTERED')
            || ($alasan === 'NOT_FOUND')
            || ($alasan === 'INVALID_ARGUMENT');

        return [
            'kode' => $kode,
            'ok' => false,
            'token_mati' => $tokenMati,
            'keterangan' => $alasan !== '' ? $alasan : substr((string) $balasan['galat'], 0, 200),
        ];
    }
}

/* =============================================================================
 * 5. MENGIRIM KE SELURUH HP MILIK SATU AKUN
 * ========================================================================== */

if (!function_exists('rts_fcm_tabel_ada')) {
    function rts_fcm_tabel_ada(mysqli $conn): bool
    {
        static $ada = null;

        if ($ada !== null) {
            return $ada;
        }

        /* Memakai SHOW TABLES, BUKAN information_schema.
           Sebabnya: akun database cPanel (cpses_...) tidak diberi izin membaca
           information_schema, sehingga muncul kesalahan:
              #1044 - Access denied for user 'cpses_...'@'localhost'
                      to database 'information_schema'
           SHOW TABLES selalu tersedia dan hasilnya sama. */
        $hasil = @$conn->query("SHOW TABLES LIKE 'rts_device_tokens'");

        $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

        if ($hasil instanceof mysqli_result) {
            $hasil->free();
        }

        return $ada;
    }
}

if (!function_exists('rts_push_kirim')) {
    /**
     * Mengirim pemberitahuan HP ke semua perangkat milik satu alamat email.
     *
     * Aman dipanggil walaupun Firebase belum disiapkan: bila belum siap, fungsi
     * ini langsung berhenti tanpa mengubah apa pun.
     *
     * @return int jumlah HP yang berhasil dikirimi
     */
    function rts_push_kirim(
        mysqli $conn,
        string $email,
        string $judul,
        string $pesan,
        array $data = []
    ): int {
        try {
            $email = trim($email);

            if ($email === '' || !rts_fcm_siap()) {
                return 0;
            }

            if (!rts_fcm_tabel_ada($conn)) {
                return 0;
            }

            /* -----------------------------------------------------------------
             * Kunci pemberitahuan.
             *
             * Aplikasi memakai kunci ini untuk menandai pemberitahuan yang
             * sudah muncul di layar HP, supaya pemeriksaan berkala di dalam
             * aplikasi tidak menampilkan pemberitahuan yang sama dua kali.
             * Bila pemanggil belum menyertakan kunci, kunci dicari dari tabel
             * notifications (baris terbaru untuk penerima ini).
             * -------------------------------------------------------------- */

            if (empty($data['kunci'])) {
                $refTipe = (string) ($data['ref_tipe'] ?? '');
                $refId = (int) ($data['ref_id'] ?? 0);

                if ($refTipe !== '' && $refId > 0) {
                    $cari = $conn->prepare(
                        'SELECT id FROM notifications
                         WHERE recipient_email=? AND reference_type=? AND reference_id=?
                         ORDER BY id DESC LIMIT 1'
                    );

                    if ($cari) {
                        $cari->bind_param('ssi', $email, $refTipe, $refId);
                        $cari->execute();
                        $barisKunci = $cari->get_result()->fetch_assoc();
                        $cari->close();

                        if ($barisKunci && !empty($barisKunci['id'])) {
                            $data['kunci'] = 'SISTEM|' . (int) $barisKunci['id'];
                        }
                    }
                }
            }

            /* ------------------------------------------- daftar token perangkat */

            $ambil = $conn->prepare('SELECT id, token FROM rts_device_tokens WHERE user_email=?');
            if (!$ambil) {
                return 0;
            }

            $ambil->bind_param('s', $email);
            $ambil->execute();
            $hasilToken = $ambil->get_result();

            $daftar = [];

            if ($hasilToken) {
                while ($baris = $hasilToken->fetch_assoc()) {
                    $daftar[] = ['id' => (int) $baris['id'], 'token' => (string) $baris['token']];
                }
            }

            $ambil->close();

            if (!$daftar) {
                return 0;
            }

            /* --------------------------------------------------------- kirim */

            $berhasil = 0;
            $mati = [];

            foreach ($daftar as $satu) {
                if ($satu['token'] === '') {
                    continue;
                }

                $kabar = rts_fcm_kirim_token($satu['token'], $judul, $pesan, $data);

                if ($kabar['ok']) {
                    $berhasil++;
                    continue;
                }

                if ($kabar['token_mati']) {
                    $mati[] = $satu['id'];
                    error_log('RTS FCM: token perangkat dibuang (' . $kabar['kode'] . ' ' . $kabar['keterangan'] . ').');
                }
            }

            /* ----------------------------------------- bersihkan token yang mati */

            if ($mati) {
                $daftarId = implode(',', array_map('intval', $mati));
                $conn->query('DELETE FROM rts_device_tokens WHERE id IN (' . $daftarId . ')');
            }

            return $berhasil;
        } catch (Throwable $galat) {
            // Pemberitahuan HP tidak boleh sampai mengganggu proses utama.
            error_log('RTS FCM: ' . $galat->getMessage());

            return 0;
        }
    }
}

if (!function_exists('rts_push_kirim_semua')) {
    /**
     * Mengirim pemberitahuan HP ke SELURUH perangkat yang terdaftar.
     *
     * Dipakai untuk pengumuman yang berlaku bagi semua petugas, misalnya
     * "versi aplikasi baru tersedia" dan "data customer diperbarui".
     *
     * Aman dipanggil walaupun Firebase belum disiapkan atau daftar token
     * masih kosong: fungsi ini langsung berhenti tanpa mengubah apa pun.
     *
     * @param array<string,mixed> $data    keterangan tambahan untuk aplikasi
     * @param array<int,string>   $kecuali daftar email yang TIDAK dikirimi
     *
     * @return int jumlah HP yang berhasil dikirimi
     */
    function rts_push_kirim_semua(
        mysqli $conn,
        string $judul,
        string $pesan,
        array $data = [],
        array $kecuali = []
    ): int {
        try {
            if (!rts_fcm_siap() || !rts_fcm_tabel_ada($conn)) {
                return 0;
            }

            $ambil = $conn->query('SELECT id, token, user_email FROM rts_device_tokens');

            if (!$ambil) {
                return 0;
            }

            $daftar = [];

            while ($baris = $ambil->fetch_assoc()) {
                $email = trim((string) ($baris['user_email'] ?? ''));

                if ($email !== '' && in_array($email, $kecuali, true)) {
                    continue;
                }

                $daftar[] = ['id' => (int) $baris['id'], 'token' => (string) $baris['token']];
            }

            $ambil->free();

            if (!$daftar) {
                return 0;
            }

            /* Kunci pemberitahuan: dipakai aplikasi supaya tidak menampilkan
               pemberitahuan yang sama dua kali ketika diperiksa berkala. */
            if (empty($data['kunci'])) {
                $data['kunci'] = 'UMUM|' . substr(md5($judul . '|' . $pesan . '|' . date('YmdH')), 0, 16);
            }

            $berhasil = 0;
            $mati = [];

            foreach ($daftar as $satu) {
                if ($satu['token'] === '') {
                    continue;
                }

                $kabar = rts_fcm_kirim_token($satu['token'], $judul, $pesan, $data);

                if ($kabar['ok']) {
                    $berhasil++;
                    continue;
                }

                if ($kabar['token_mati']) {
                    $mati[] = $satu['id'];
                }
            }

            if ($mati) {
                $daftarId = implode(',', array_map('intval', $mati));
                $conn->query('DELETE FROM rts_device_tokens WHERE id IN (' . $daftarId . ')');
            }

            return $berhasil;
        } catch (Throwable $galat) {
            error_log('RTS FCM semua: ' . $galat->getMessage());

            return 0;
        }
    }
}
