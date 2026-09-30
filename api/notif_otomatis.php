<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PEMBERITAHUAN OTOMATIS
 *  Berkas : api/notif_otomatis.php
 *
 *  KEGUNAAN
 *  --------
 *  Satu pintu untuk mengirim pemberitahuan ke seluruh petugas ataupun kepada
 *  petugas tertentu. Setiap pemberitahuan dikerjakan DUA kali sekaligus:
 *
 *     1. Dicatat pada tabel `notifications` (muncul di menu Pemberitahuan
 *        di dalam aplikasi dan website)
 *     2. Dikirim ke layar HP lewat Firebase Cloud Messaging (muncul walaupun
 *        aplikasi sedang TIDAK dibuka)
 *
 *  Dipakai oleh:
 *     - app_versi.php      : mengumumkan versi aplikasi baru ke seluruh HP
 *     - upload_customer.php: memberi tahu bahwa data customer diperbarui
 *     - pengajuan_toko.php : memberi tahu ADMIN/ASS ada pengajuan baru
 *
 *  SIFATNYA AMAN GAGAL
 *  -------------------
 *  Bila tabel `notifications` belum ada, atau Firebase belum disiapkan, atau
 *  token HP belum terdaftar - SELURUH fungsi di berkas ini berhenti dengan
 *  tenang tanpa mengganggu proses utama. Jadi halaman tempat pemanggilnya
 *  tetap bekerja seperti biasa.
 *
 *  CATATAN: berkas ini TIDAK memakai tabel information_schema, karena akun
 *  database cPanel tidak diberi izin membacanya (kesalahan #1044).
 * ============================================================================
 */

if (!function_exists('rts_notif_ada_tabel')) {
    /**
     * Memeriksa keberadaan sebuah tabel memakai SHOW TABLES.
     */
    function rts_notif_ada_tabel(mysqli $conn, string $nama): bool
    {
        static $simpan = [];

        if (isset($simpan[$nama])) {
            return $simpan[$nama];
        }

        if (preg_match('/^[A-Za-z0-9_]+$/', $nama) !== 1) {
            $simpan[$nama] = false;

            return false;
        }

        $hasil = @$conn->query("SHOW TABLES LIKE '" . $conn->real_escape_string($nama) . "'");

        $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

        if ($hasil instanceof mysqli_result) {
            $hasil->free();
        }

        $simpan[$nama] = $ada;

        return $ada;
    }
}

if (!function_exists('rts_notif_catat')) {
    /**
     * Mencatat satu baris pemberitahuan pada tabel `notifications`.
     *
     * @param array<string,mixed> $data keterangan tambahan (tidak wajib)
     *
     * @return int nomor baris pemberitahuan yang baru (0 bila gagal)
     */
    function rts_notif_catat(
        mysqli $conn,
        string $email,
        string $judul,
        string $pesan,
        string $tipe = 'SISTEM',
        string $refTipe = '',
        int $refId = 0
    ): int {
        try {
            $email = trim($email);

            if ($email === '' || !rts_notif_ada_tabel($conn, 'notifications')) {
                return 0;
            }

            $stmt = @$conn->prepare(
                'INSERT INTO notifications
                 (recipient_email, title, message, type, reference_type, reference_id)
                 VALUES (?, ?, ?, ?, ?, ?)'
            );

            if (!$stmt) {
                return 0;
            }

            $stmt->bind_param('sssssi', $email, $judul, $pesan, $tipe, $refTipe, $refId);

            $berhasil = $stmt->execute();
            $idBaru = $berhasil ? (int) $conn->insert_id : 0;

            $stmt->close();

            return $idBaru;
        } catch (Throwable $galat) {
            error_log('RTS notif catat: ' . $galat->getMessage());

            return 0;
        }
    }
}

if (!function_exists('rts_notif_daftar_penerima')) {
    /**
     * Menyusun daftar email penerima.
     *
     * @param string $peran  '' = semua peran, atau mis. 'ADMIN,ASS'
     * @param string $kecuali email yang tidak ikut dikirimi (pelaku perubahan)
     *
     * @return array<int,string>
     */
    function rts_notif_daftar_penerima(mysqli $conn, string $peran = '', string $kecuali = ''): array
    {
        $daftar = [];

        try {
            $sql = 'SELECT email, role, status_aktif FROM sales_users';
            $syarat = [];

            /* Hanya akun aktif yang dikirimi (kolom status_aktif boleh kosong). */
            $syarat[] = "(status_aktif IS NULL OR status_aktif = '' OR UPPER(status_aktif) IN ('AKTIF','AKTIVE','1','YES','YA'))";

            if (trim($peran) !== '') {
                $potongan = array_filter(array_map('trim', explode(',', strtoupper($peran))));

                if ($potongan) {
                    $aman = array_map(
                        static function (string $satu) use ($conn): string {
                            return "'" . $conn->real_escape_string($satu) . "'";
                        },
                        $potongan
                    );

                    $syarat[] = 'UPPER(role) IN (' . implode(',', $aman) . ')';
                }
            }

            $sql .= ' WHERE ' . implode(' AND ', $syarat);

            $hasil = @$conn->query($sql);

            if ($hasil instanceof mysqli_result) {
                while ($baris = $hasil->fetch_assoc()) {
                    $email = trim((string) ($baris['email'] ?? ''));

                    if ($email === '' || strcasecmp($email, trim($kecuali)) === 0) {
                        continue;
                    }

                    if (in_array($email, $daftar, true)) {
                        continue;
                    }

                    $daftar[] = $email;
                }

                $hasil->free();
            }
        } catch (Throwable $galat) {
            error_log('RTS notif penerima: ' . $galat->getMessage());
        }

        return $daftar;
    }
}

if (!function_exists('rts_notif_kirim')) {
    /**
     * Mengirim pemberitahuan kepada sekelompok penerima: dicatat ke tabel
     * `notifications` lalu didorong ke layar HP lewat Firebase.
     *
     * @param array<int,string>   $penerima daftar email penerima
     * @param array<string,mixed> $data     keterangan tambahan untuk aplikasi
     *
     * @return array<string,int> jumlah catatan dan jumlah HP yang dikirimi
     */
    function rts_notif_kirim(
        mysqli $conn,
        array $penerima,
        string $judul,
        string $pesan,
        string $tipe = 'SISTEM',
        array $data = [],
        string $refTipe = '',
        int $refId = 0
    ): array {
        $jumlahCatat = 0;
        $jumlahHp = 0;

        if (!$penerima) {
            return ['catat' => 0, 'hp' => 0];
        }

        $adaPush = false;

        if (is_file(__DIR__ . '/fcm_kirim.php')) {
            require_once __DIR__ . '/fcm_kirim.php';

            $adaPush = function_exists('rts_push_kirim');
        }

        foreach ($penerima as $email) {
            $idBaris = rts_notif_catat($conn, $email, $judul, $pesan, $tipe, $refTipe, $refId);

            if ($idBaris > 0) {
                $jumlahCatat++;
            }

            if (!$adaPush) {
                continue;
            }

            $keterangan = $data;

            if (empty($keterangan['kunci']) && $idBaris > 0) {
                $keterangan['kunci'] = $tipe . '|' . $idBaris;
            }

            if (!empty($refTipe) && $refId > 0) {
                $keterangan['ref_tipe'] = $refTipe;
                $keterangan['ref_id'] = $refId;
            }

            $jumlahHp += (int) rts_push_kirim($conn, $email, $judul, $pesan, $keterangan);
        }

        return ['catat' => $jumlahCatat, 'hp' => $jumlahHp];
    }
}

if (!function_exists('rts_notif_semua')) {
    /**
     * Mengirim pemberitahuan kepada SELURUH akun aktif (semua peran).
     *
     * @param array<string,mixed> $data keterangan tambahan untuk aplikasi
     *
     * @return array<string,int> jumlah catatan dan jumlah HP yang dikirimi
     */
    function rts_notif_semua(
        mysqli $conn,
        string $judul,
        string $pesan,
        string $tipe = 'SISTEM',
        array $data = [],
        string $kecuali = ''
    ): array {
        $penerima = rts_notif_daftar_penerima($conn, '', $kecuali);

        return rts_notif_kirim($conn, $penerima, $judul, $pesan, $tipe, $data);
    }
}

if (!function_exists('rts_notif_versi_baru')) {
    /**
     * Mengumumkan versi aplikasi baru ke SELURUH HP.
     *
     * Judul dan isi pesan disusun di sini supaya sama pada semua HP, dan
     * keterangan versi ikut dikirim sebagai data - sehingga aplikasi dapat
     * langsung membuka kotak pembaruan beserta tombol unduh ketika
     * pemberitahuan itu ditekan.
     *
     * @param array<string,mixed> $versi keterangan versi (version_code,
     *                                    version_name, wajib, catatan, apk,
     *                                    ukuran_mb, dipublikasikan)
     *
     * @return array<string,int>
     */
    function rts_notif_versi_baru(mysqli $conn, array $versi, string $kecuali = ''): array
    {
        $kode = (int) ($versi['version_code'] ?? 0);
        $nama = trim((string) ($versi['version_name'] ?? ''));
        $wajib = !empty($versi['wajib']);
        $catatan = trim((string) ($versi['catatan'] ?? ''));

        if ($kode < 1) {
            return ['catat' => 0, 'hp' => 0];
        }

        $judul = $wajib
            ? 'Pembaruan WAJIB RTS Panel ' . ($nama === '' ? $kode : $nama)
            : 'Versi baru RTS Panel tersedia ' . ($nama === '' ? $kode : $nama);

        $pesan = 'Aplikasi RTS Panel versi ' . ($nama === '' ? $kode : $nama)
            . ' (kode ' . $kode . ') sudah tersedia. '
            . ($wajib
                ? 'Pembaruan ini WAJIB dipasang sebelum melanjutkan pekerjaan. '
                : 'Pembaruan ini disarankan segera dipasang. ')
            . 'Ketuk tombol UPDATE untuk memperbarui aplikasi.';

        if ($catatan !== '') {
            $pesan .= "\n\n" . $catatan;
        }

        $data = [
            'tipe' => 'versi',
            'kode' => $kode,
            'version_code' => $kode,
            'version_name' => $nama,
            'wajib' => $wajib ? '1' : '0',
            'catatan' => $catatan,
            'apk' => (string) ($versi['apk'] ?? ''),
            'ukuran_mb' => (string) ($versi['ukuran_mb'] ?? '0'),
            'dipublikasikan' => (string) ($versi['dipublikasikan'] ?? ''),
        ];

        return rts_notif_semua($conn, $judul, $pesan, 'VERSI_BARU', $data, $kecuali);
    }
}

if (!function_exists('rts_notif_aktivitas')) {
    /**
     * Pemberitahuan aktivitas ADMIN (mis. data customer diperbarui).
     *
     * @param array<string,mixed> $data keterangan tambahan untuk aplikasi
     *
     * @return array<string,int>
     */
    function rts_notif_aktivitas(
        mysqli $conn,
        string $judul,
        string $pesan,
        string $tipe = 'AKTIVITAS',
        array $data = [],
        string $pelaku = ''
    ): array {
        $data['tipe'] = $data['tipe'] ?? strtolower($tipe);

        return rts_notif_semua($conn, $judul, $pesan, $tipe, $data, $pelaku);
    }
}
