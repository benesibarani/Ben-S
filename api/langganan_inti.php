<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - INTI LANGGANAN PRO
 *  Berkas : api/langganan_inti.php
 *
 *  KEGUNAAN
 *  --------
 *  Berisi seluruh aturan tentang Akun PRO, dipakai bersama oleh:
 *     - api/login.php           (saat petugas masuk, uji coba 7 hari diberikan)
 *     - api/session_check.php   (saat aplikasi dibuka dengan sesi tersimpan)
 *     - api/langganan.php       (halaman Langganan di dalam aplikasi)
 *     - langganan_admin.php     (halaman pengelolaan di website)
 *
 *  PENGATURAN HARGA & DURASI
 *  -------------------------
 *  Harga langganan, lama masa PRO, dan lama uji coba dapat diubah oleh ADMIN
 *  langsung dari halaman langganan_admin.php (menu "Langganan PRO" pada
 *  sidebar). Nilainya disimpan pada tabel rts_lg_pengaturan, sehingga tidak
 *  perlu menyunting berkas PHP. Bila tabel belum ada, seluruh fungsi di bawah
 *  memakai nilai bawaan.
 *
 *  ATURAN LANGGANAN
 *  ----------------
 *      Uji coba (TRIAL) : 7 hari, diberikan SEKALI untuk setiap akun, otomatis
 *                         pada saat petugas masuk pertama kali setelah fitur
 *                         ini dipasang.
 *      Langganan (PRO)  : 30 hari, dihitung sejak hari pembayaran diterima
 *                         Admin. Bila masa PRO masih berjalan dan petugas
 *                         membayar lagi, masa barunya DITAMBAHKAN dari tanggal
 *                         berakhir yang lama (tidak hangus).
 *      Akun PRO bebas iklan. Akun GRATIS melihat iklan.
 *
 *  SIFATNYA AMAN GAGAL
 *  -------------------
 *  Bila kolom-kolom baru belum ada di database, SELURUH fungsi di berkas ini
 *  tetap bekerja dengan nilai bawaan - aplikasi dan API tidak ikut gagal.
 *  Kolom baru dapat dibuat melalui halaman langganan_admin.php atau dengan
 *  menjalankan berkas database/migrations/RTS_PANEL_LANGGANAN_PRO.sql.
 *
 *  CATATAN: berkas ini TIDAK memakai tabel information_schema, karena akun
 *  database cPanel tidak diberi izin membacanya (kesalahan #1044). Pemeriksaan
 *  kolom dan tabel memakai SHOW COLUMNS / SHOW TABLES.
 * ============================================================================
 */

if (!defined('LG_INTI_VERSI_BERKAS')) {
    /* Ditampilkan pada ?diagnosa=1 di halaman langganan_admin.php */
    define('LG_INTI_VERSI_BERKAS', 2);
}

/* ==========================================================================
 *  HARGA, DURASI, DAN UJI COBA (DAPAT DIUBAH ADMIN DARI HALAMAN WEB)
 * ========================================================================== */

if (!function_exists('rts_lg_bawaan')) {
    /**
     * Nilai bawaan bila tabel pengaturan belum ada / belum diisi.
     *
     * @return array<string,int>
     */
    function rts_lg_bawaan(): array
    {
        return ['harga' => 5000, 'durasi' => 30, 'trial' => 7];
    }
}

if (!function_exists('rts_lg_pengaturan_baca')) {
    /**
     * Membaca pengaturan harga/durasi dari tabel rts_lg_pengaturan.
     *
     * Aman gagal: bila tabel belum ada, koneksi tidak tersedia, atau nilai di
     * database tidak masuk akal, nilai bawaan yang dipakai. Hasilnya disimpan
     * di memori (static) sehingga hanya satu kali membaca per permintaan.
     *
     * @param bool $paksa paksa membaca ulang dari database
     *
     * @return array<string,int> kunci: harga, durasi, trial
     */
    function rts_lg_pengaturan_baca(bool $paksa = false, ?mysqli $conn = null): array
    {
        static $simpan = null;

        if ($simpan !== null && !$paksa) {
            return $simpan;
        }

        $nilai = rts_lg_bawaan();

        if (!$conn instanceof mysqli) {
            $calon = $GLOBALS['conn'] ?? null;

            if ($calon instanceof mysqli) {
                $conn = $calon;
            } elseif (function_exists('rts_api_db')) {
                $calon = rts_api_db();

                if ($calon instanceof mysqli) {
                    $conn = $calon;
                }
            }
        }

        if ($conn instanceof mysqli && rts_lg_ada_tabel($conn, 'rts_lg_pengaturan')) {
            $hasil = @$conn->query('SELECT kunci, nilai FROM rts_lg_pengaturan');

            if ($hasil instanceof mysqli_result) {
                while ($baris = $hasil->fetch_assoc()) {
                    $kunci = strtolower(trim((string) ($baris['kunci'] ?? '')));
                    $angka = (int) ($baris['nilai'] ?? 0);

                    if ($kunci === 'harga' && $angka >= 1000 && $angka <= 1000000) {
                        $nilai['harga'] = $angka;
                    } elseif ($kunci === 'durasi' && $angka >= 1 && $angka <= 365) {
                        $nilai['durasi'] = $angka;
                    } elseif ($kunci === 'trial' && $angka >= 0 && $angka <= 90) {
                        $nilai['trial'] = $angka;
                    }
                }

                $hasil->free();
            }
        }

        $simpan = $nilai;

        return $simpan;
    }
}

if (!function_exists('rts_lg_pengaturan_siapkan')) {
    /**
     * Membuat tabel rts_lg_pengaturan bila belum ada.
     */
    function rts_lg_pengaturan_siapkan(mysqli $conn): bool
    {
        if (rts_lg_ada_tabel($conn, 'rts_lg_pengaturan')) {
            return true;
        }

        $sql = "CREATE TABLE IF NOT EXISTS rts_lg_pengaturan (
            kunci VARCHAR(40) NOT NULL PRIMARY KEY,
            nilai VARCHAR(190) NOT NULL DEFAULT '',
            diperbarui DATETIME NULL DEFAULT NULL
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";

        return (bool) @$conn->query($sql);
    }
}

if (!function_exists('rts_lg_pengaturan_simpan')) {
    /**
     * Menyimpan harga, lama masa PRO, dan lama uji coba.
     *
     * @return array<string,mixed> berhasil / pesan / pengaturan
     */
    function rts_lg_pengaturan_simpan(mysqli $conn, int $harga, int $durasi, int $trial): array
    {
        if ($harga < 1000 || $harga > 1000000) {
            return ['berhasil' => false, 'pesan' => 'Harga harus antara Rp1.000 sampai Rp1.000.000.'];
        }

        if ($durasi < 1 || $durasi > 365) {
            return ['berhasil' => false, 'pesan' => 'Lama langganan PRO harus antara 1 sampai 365 hari.'];
        }

        if ($trial < 0 || $trial > 90) {
            return ['berhasil' => false, 'pesan' => 'Lama uji coba harus antara 0 sampai 90 hari (0 = dimatikan).'];
        }

        if (!rts_lg_pengaturan_siapkan($conn)) {
            return ['berhasil' => false, 'pesan' => 'Tabel pengaturan gagal dibuat: ' . $conn->error];
        }

        $stmt = $conn->prepare(
            'INSERT INTO rts_lg_pengaturan (kunci, nilai, diperbarui) VALUES (?, ?, NOW())
             ON DUPLICATE KEY UPDATE nilai = ?, diperbarui = NOW()'
        );

        if (!$stmt) {
            return ['berhasil' => false, 'pesan' => 'Gagal menyiapkan penyimpanan pengaturan.'];
        }

        $gagal = '';

        foreach (['harga' => $harga, 'durasi' => $durasi, 'trial' => $trial] as $kunci => $angka) {
            $teks = (string) $angka;

            $stmt->bind_param('sis', $kunci, $teks, $teks);

            if (!$stmt->execute()) {
                $gagal = $kunci . ' (' . $conn->error . ')';
                break;
            }
        }

        $stmt->close();

        if ($gagal !== '') {
            return ['berhasil' => false, 'pesan' => 'Gagal menyimpan ' . $gagal];
        }

        $pengaturan = rts_lg_pengaturan_baca(true, $conn);

        return [
            'berhasil' => true,
            'pesan' => 'Pengaturan tersimpan. Harga Rp' . number_format($pengaturan['harga'], 0, ',', '.')
                . ' - masa PRO ' . $pengaturan['durasi'] . ' hari - uji coba '
                . ($pengaturan['trial'] > 0 ? $pengaturan['trial'] . ' hari' : 'dimatikan')
                . '. Aplikasi dan website langsung memakai nilai baru ini.',
            'pengaturan' => $pengaturan,
        ];
    }
}

if (!function_exists('rts_lg_harga')) {
    /**
     * Harga langganan PRO dalam rupiah.
     *
     * Diubah oleh ADMIN dari halaman Langganan PRO (tersimpan di database).
     */
    function rts_lg_harga(): int
    {
        $pengaturan = rts_lg_pengaturan_baca();

        return (int) ($pengaturan['harga'] ?? 5000);
    }
}

if (!function_exists('rts_lg_durasi')) {
    /**
     * Lama langganan PRO (hari) setiap kali pembayaran diterima.
     *
     * Diubah oleh ADMIN dari halaman Langganan PRO (tersimpan di database).
     */
    function rts_lg_durasi(): int
    {
        $pengaturan = rts_lg_pengaturan_baca();

        return (int) ($pengaturan['durasi'] ?? 30);
    }
}

if (!function_exists('rts_lg_trial')) {
    /**
     * Lama uji coba (hari) untuk setiap akun baru. 0 = uji coba dimatikan.
     *
     * Diubah oleh ADMIN dari halaman Langganan PRO (tersimpan di database).
     */
    function rts_lg_trial(): int
    {
        $pengaturan = rts_lg_pengaturan_baca();

        return (int) ($pengaturan['trial'] ?? 7);
    }
}

if (!function_exists('rts_lg_qris')) {
    /**
     * Keterangan pembayaran QRIS yang ditampilkan pada aplikasi.
     *
     * GAMBAR QRIS-NYA TIDAK DIAMBIL DARI SINI, melainkan dari berkas gambar
     * milik Bapak pada aplikasi Android (assets/images/qris_bene_s.jpg).
     * Data di bawah hanya keterangan pendamping.
     */
    function rts_lg_qris(): array
    {
        return [
            'nama' => 'BENE-S',
            'nmid' => 'ID1026519749489',
            'harga' => rts_lg_harga(),
            'durasi_hari' => rts_lg_durasi(),
            'trial_hari' => rts_lg_trial(),
            'catatan' => 'Pindai QRIS, bayar sesuai nominal, lalu tekan '
                . '"SAYA SUDAH BAYAR" pada aplikasi. Admin akan mengaktifkan '
                . 'Akun PRO setelah pembayaran diperiksa.',
        ];
    }
}

if (!function_exists('rts_lg_ada_tabel')) {
    /**
     * Memeriksa keberadaan sebuah tabel memakai SHOW TABLES.
     */
    function rts_lg_ada_tabel(mysqli $conn, string $nama): bool
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

if (!function_exists('rts_lg_ada_kolom')) {
    /**
     * Memeriksa keberadaan sebuah kolom pada tabel sales_users.
     */
    function rts_lg_ada_kolom(mysqli $conn, string $kolom): bool
    {
        static $simpan = [];

        if (isset($simpan[$kolom])) {
            return $simpan[$kolom];
        }

        if (preg_match('/^[A-Za-z0-9_]+$/', $kolom) !== 1) {
            $simpan[$kolom] = false;

            return false;
        }

        $hasil = @$conn->query(
            "SHOW COLUMNS FROM sales_users LIKE '" . $conn->real_escape_string($kolom) . "'"
        );

        $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

        if ($hasil instanceof mysqli_result) {
            $hasil->free();
        }

        $simpan[$kolom] = $ada;

        return $ada;
    }
}

if (!function_exists('rts_lg_kolom_tersedia')) {
    /**
     * Daftar kolom langganan yang benar-benar ada di database.
     *
     * @return array<string,bool>
     */
    function rts_lg_kolom_tersedia(mysqli $conn): array
    {
        $daftar = ['akun_pro', 'pro_mulai', 'pro_selesai', 'trial_mulai', 'trial_selesai', 'foto_profil'];
        $hasil = [];

        foreach ($daftar as $kolom) {
            $hasil[$kolom] = rts_lg_ada_kolom($conn, $kolom);
        }

        return $hasil;
    }
}

if (!function_exists('rts_lg_baris')) {
    /**
     * Membaca baris pengguna beserta kolom langganan yang tersedia.
     *
     * @return array<string,mixed>|null
     */
    function rts_lg_baris(mysqli $conn, int $userId): ?array
    {
        if ($userId <= 0) {
            return null;
        }

        $punya = rts_lg_kolom_tersedia($conn);

        $kolom = ['id', 'username', 'nama_lengkap', 'email', 'role'];

        // Nilai bawaan dipakai bila kolomnya belum ada di database. Kolom
        // angka memakai '0', kolom tulisan/tanggal memakai petik kosong.
        $bawaan = [
            'akun_pro' => "'0' AS akun_pro",
            'pro_mulai' => "'' AS pro_mulai",
            'pro_selesai' => "'' AS pro_selesai",
            'trial_mulai' => "'' AS trial_mulai",
            'trial_selesai' => "'' AS trial_selesai",
            'foto_profil' => "'' AS foto_profil",
        ];

        foreach ($punya as $nama => $ada) {
            if ($ada) {
                $kolom[] = $nama;
                continue;
            }

            $kolom[] = $bawaan[$nama] ?? ("'' AS " . $nama);
        }

        $stmt = $conn->prepare(
            'SELECT ' . implode(', ', $kolom) . ' FROM sales_users WHERE id = ? LIMIT 1'
        );

        if (!$stmt) {
            return null;
        }

        $stmt->bind_param('i', $userId);
        $stmt->execute();
        $hasil = $stmt->get_result();
        $baris = $hasil ? $hasil->fetch_assoc() : null;
        $stmt->close();

        return $baris ?: null;
    }
}

if (!function_exists('rts_lg_sisa_hari')) {
    /**
     * Menghitung sisa hari sampai sebuah tanggal. 0 bila tanggal sudah lewat.
     */
    function rts_lg_sisa_hari($waktu): int
    {
        $sampai = is_numeric($waktu) ? (int) $waktu : (int) strtotime((string) $waktu);

        if ($sampai <= 0) {
            return 0;
        }

        $selisih = $sampai - time();

        if ($selisih <= 0) {
            return 0;
        }

        return (int) ceil($selisih / 86400);
    }
}

if (!function_exists('rts_lg_status')) {
    /**
     * Menghitung keadaan langganan dari sebuah baris pengguna.
     *
     * @param array<string,mixed> $baris
     * @return array<string,mixed>
     */
    function rts_lg_status(array $baris): array
    {
        $flagPro = (int) ($baris['akun_pro'] ?? 0) === 1;

        $proMulai = trim((string) ($baris['pro_mulai'] ?? ''));
        $proSelesai = trim((string) ($baris['pro_selesai'] ?? ''));
        $trialMulai = trim((string) ($baris['trial_mulai'] ?? ''));
        $trialSelesai = trim((string) ($baris['trial_selesai'] ?? ''));

        $proWaktu = $proSelesai === '' ? 0 : (int) strtotime($proSelesai);
        $trialWaktu = $trialSelesai === '' ? 0 : (int) strtotime($trialSelesai);

        // Akun dianggap BERHAK PRO bila:
        //   a. kolom penanda `akun_pro` bernilai 1, ATAU
        //   b. ada tanggal `pro_selesai` (bukti masa langganan pernah dibeli).
        // Bagian (b) sangat penting: bila kolom `akun_pro` belum ada / belum
        // berisi 1 di database, pembayaran yang SUDAH disetujui ADMIN tetap
        // terbaca PRO dan tidak membuat akun sales terkunci.
        $akunPro = $flagPro || $proWaktu > 0;

        // Langganan tanpa tanggal berakhir (diberikan manual oleh Admin lewat
        // halaman akun_pro.php) dianggap berlaku terus.
        $proTanpaBatas = $flagPro && $proWaktu === 0;

        $proAktif = $proTanpaBatas || $proWaktu > time();

        $trialAktif = (!$proAktif) && $trialWaktu > time();

        $sisaPro = $proTanpaBatas ? 0 : rts_lg_sisa_hari($proWaktu);
        $sisaTrial = rts_lg_sisa_hari($trialWaktu);

        $trialTersedia = ($trialMulai === '') && !$proAktif;

        if ($proAktif) {
            $sumber = 'PRO';
        } elseif ($trialAktif) {
            $sumber = 'TRIAL';
        } else {
            $sumber = 'GRATIS';
        }

        $berlakuSampai = '';

        if ($proAktif && $proWaktu > 0) {
            $berlakuSampai = date('d-m-Y', $proWaktu);
        } elseif ($trialAktif) {
            $berlakuSampai = date('d-m-Y', $trialWaktu);
        }

        return [
            'pro' => $proAktif || $trialAktif,
            'akun_pro' => ($proAktif || $trialAktif) ? 1 : 0,
            'penanda_akun_pro' => $flagPro ? 1 : 0,
            'sumber' => $sumber,
            'label' => ($proAktif || $trialAktif) ? 'PRO' : 'GRATIS',
            'pro_aktif' => $proAktif,
            'pro_tanpa_batas' => $proTanpaBatas,
            'pro_mulai' => $proMulai,
            'pro_selesai' => $proSelesai,
            'sisa_hari' => $proAktif ? $sisaPro : 0,
            'trial_aktif' => $trialAktif,
            'trial_mulai' => $trialMulai,
            'trial_selesai' => $trialSelesai,
            'sisa_trial_hari' => $trialAktif ? $sisaTrial : 0,
            'trial_tersedia' => $trialTersedia,
            'trial_pernah_dipakai' => $trialMulai !== '',
            'berlaku_sampai' => $berlakuSampai,
            'kadaluarsa' => $akunPro && !$proAktif && !$trialAktif,
            'harga' => rts_lg_harga(),
            'durasi_hari' => rts_lg_durasi(),
            'trial_hari' => rts_lg_trial(),
        ];
    }
}

if (!function_exists('rts_lg_beri')) {
    /**
     * Memberikan (atau menambah) masa langganan PRO kepada seorang pengguna.
     *
     * Bila masa PRO masih berjalan, hari barunya DITAMBAHKAN dari tanggal
     * berakhir yang lama sehingga pembayaran tidak hangus.
     *
     * @return array<string,mixed> keadaan langganan sesudah perubahan
     */
    function rts_lg_beri(mysqli $conn, int $userId, int $hari = 0, string $sebab = 'ADMIN'): array
    {
        if ($hari <= 0) {
            $hari = rts_lg_durasi();
        }

        $punya = rts_lg_kolom_tersedia($conn);
        $baris = rts_lg_baris($conn, $userId);

        if (!$baris) {
            return ['berhasil' => false, 'pesan' => 'Pengguna tidak ditemukan.'];
        }

        $lama = trim((string) ($baris['pro_selesai'] ?? ''));
        $sisaLama = $lama === '' ? 0 : (int) strtotime($lama);

        $mulai = time();
        $dasar = $sisaLama > time() ? $sisaLama : time();
        $selesai = $dasar + ($hari * 86400);

        $bagian = [];

        if ($punya['akun_pro']) {
            $bagian[] = 'akun_pro = 1';
        }

        if ($punya['pro_mulai']) {
            $proMulaiLama = trim((string) ($baris['pro_mulai'] ?? ''));

            if ($proMulaiLama === '') {
                $bagian[] = "pro_mulai = '" . date('Y-m-d H:i:s', $mulai) . "'";
            }
        }

        if ($punya['pro_selesai']) {
            $bagian[] = "pro_selesai = '" . date('Y-m-d H:i:s', $selesai) . "'";
        }

        if ($punya['trial_selesai'] && !$punya['pro_selesai']) {
            // Tanpa kolom pro_selesai, masa PRO ditulis pada trial_selesai
            // supaya tetap ada tanggal berakhirnya.
            $bagian[] = "trial_selesai = '" . date('Y-m-d H:i:s', $selesai) . "'";
        }

        if ($bagian) {
            $sql = 'UPDATE sales_users SET ' . implode(', ', $bagian) . ' WHERE id = ' . (int) $userId;

            if (!@$conn->query($sql)) {
                return [
                    'berhasil' => false,
                    'pesan' => 'Gagal menyimpan masa langganan: ' . $conn->error,
                ];
            }
        }

        $punyaBayar = rts_lg_ada_tabel($conn, 'pembayaran_pro');

        if ($punyaBayar) {
            @$conn->query(
                "UPDATE pembayaran_pro SET status = 'DIBAYAR', sebab = '"
                . $conn->real_escape_string($sebab)
                . "', diproses_pada = NOW() WHERE user_id = " . (int) $userId
                . " AND status = 'MENUNGGU'"
            );
        }

        $baru = rts_lg_baris($conn, $userId);

        return [
            'berhasil' => true,
            'pesan' => 'Masa langganan PRO ditambahkan ' . $hari . ' hari.',
            'tambahan_hari' => $hari,
            'status' => $baru ? rts_lg_status($baru) : [],
        ];
    }
}

if (!function_exists('rts_lg_mulai_trial')) {
    /**
     * Memulai uji coba (trial) untuk seorang pengguna. Hanya sekali seumur akun.
     *
     * @return array<string,mixed>
     */
    function rts_lg_mulai_trial(mysqli $conn, int $userId): array
    {
        $punya = rts_lg_kolom_tersedia($conn);
        $baris = rts_lg_baris($conn, $userId);

        if (!$baris) {
            return ['berhasil' => false, 'pesan' => 'Pengguna tidak ditemukan.'];
        }

        $status = rts_lg_status($baris);

        if ($status['pro_aktif']) {
            return [
                'berhasil' => false,
                'pesan' => 'Akun ini sedang berlangganan PRO.',
                'status' => $status,
            ];
        }

        if ($status['trial_aktif']) {
            return [
                'berhasil' => true,
                'pesan' => 'Uji coba masih berjalan, sisa ' . $status['sisa_trial_hari'] . ' hari.',
                'status' => $status,
            ];
        }

        if (!$punya['trial_mulai'] || !$punya['trial_selesai']) {
            return [
                'berhasil' => false,
                'pesan' => 'Kolom uji coba belum ada di database. Jalankan pembaruan '
                    . 'database lebih dahulu (lihat langganan_admin.php).',
                'status' => $status,
            ];
        }

        if ((string) ($baris['trial_mulai'] ?? '') !== '') {
            return [
                'berhasil' => false,
                'pesan' => 'Uji coba gratis sudah pernah dipakai akun ini.',
                'status' => $status,
            ];
        }

        $mulai = date('Y-m-d H:i:s');
        $selesai = date('Y-m-d H:i:s', time() + (rts_lg_trial() * 86400));

        $sql = "UPDATE sales_users SET trial_mulai = '" . $mulai . "', trial_selesai = '"
            . $selesai . "' WHERE id = " . (int) $userId . " AND (trial_mulai IS NULL OR trial_mulai = '')";

        if (!@$conn->query($sql) || $conn->affected_rows === 0) {
            return [
                'berhasil' => false,
                'pesan' => 'Uji coba tidak dapat dimulai. Coba lagi sebentar lagi.',
                'status' => $status,
            ];
        }

        $baru = rts_lg_baris($conn, $userId);

        return [
            'berhasil' => true,
            'pesan' => 'Uji coba gratis ' . rts_lg_trial() . ' hari dimulai. Selamat mencoba Akun PRO!',
            'status' => $baru ? rts_lg_status($baru) : $status,
        ];
    }
}

if (!function_exists('rts_lg_otomatis')) {
    /**
     * Dijalankan setiap petugas berhasil masuk (login).
     *
     * - Bila akun sedang PRO           : tidak ada yang diubah
     * - Bila uji coba belum pernah     : uji coba 7 hari dimulai otomatis
     * - Bila uji coba sudah habis      : akun kembali GRATIS (dengan iklan)
     *
     * @param array<string,mixed> $user baris pengguna (minimal berisi id)
     * @return array<string,mixed> keadaan langganan
     */
    function rts_lg_otomatis(mysqli $conn, array $user): array
    {
        $userId = (int) ($user['id'] ?? 0);

        if ($userId <= 0) {
            return ['pro' => false, 'sumber' => 'GRATIS', 'trial_baru' => false];
        }

        $baris = rts_lg_baris($conn, $userId);

        if (!$baris) {
            return ['pro' => false, 'sumber' => 'GRATIS', 'trial_baru' => false];
        }

        $status = rts_lg_status($baris);

        if ($status['pro_aktif'] || $status['trial_aktif']) {
            $status['trial_baru'] = false;

            return $status;
        }

        if ($status['trial_tersedia']) {
            $hasil = rts_lg_mulai_trial($conn, $userId);

            if (!empty($hasil['berhasil'])) {
                $status = $hasil['status'];
                $status['trial_baru'] = true;

                return $status;
            }
        }

        // Sudah tidak PRO dan uji coba tidak tersedia: pastikan penanda akun_pro
        // dimatikan supaya iklan kembali tampil.
        if (rts_lg_ada_kolom($conn, 'akun_pro')) {
            @$conn->query('UPDATE sales_users SET akun_pro = 0 WHERE id = ' . $userId . ' AND akun_pro = 1');
        }

        // Masa PRO yang sudah lewat ditandai pada status.
        $status['trial_baru'] = false;
        $status['kadaluarsa'] = true;

        return $status;
    }
}

if (!function_exists('rts_lg_tambah_bayar')) {
    /**
     * Mencatat pernyataan "saya sudah bayar" dari petugas (menunggu diperiksa).
     *
     * @return array<string,mixed>
     */
    function rts_lg_tambah_bayar(mysqli $conn, int $userId, int $jumlah = 0, string $catatan = ''): array
    {
        if (!rts_lg_tabel_pembayaran($conn)) {
            return [
                'berhasil' => false,
                'pesan' => 'Tabel pembayaran belum ada di database. Hubungi Admin.',
            ];
        }

        if ($jumlah <= 0) {
            $jumlah = rts_lg_harga();
        }

        $menunggu = @$conn->query(
            "SELECT COUNT(*) AS n FROM pembayaran_pro WHERE user_id = " . (int) $userId
            . " AND status = 'MENUNGGU'"
        );

        if ($menunggu instanceof mysqli_result) {
            $n = (int) (($menunggu->fetch_assoc()['n'] ?? 0));
            $menunggu->free();

            if ($n > 0) {
                return [
                    'berhasil' => true,
                    'pesan' => 'Pernyataan pembayaran Anda sudah tercatat dan sedang '
                        . 'diperiksa Admin. Mohon ditunggu.',
                    'sudah_ada' => true,
                ];
            }
        }

        $stmt = $conn->prepare(
            'INSERT INTO pembayaran_pro (user_id, jumlah, hari, catatan, status, dibuat)
             VALUES (?, ?, ?, ?, ?, NOW())'
        );

        if (!$stmt) {
            return ['berhasil' => false, 'pesan' => 'Gagal mencatat pembayaran.'];
        }

        $hari = rts_lg_durasi();
        $status = 'MENUNGGU';

        $stmt->bind_param('iiiss', $userId, $jumlah, $hari, $catatan, $status);

        if (!$stmt->execute()) {
            $stmt->close();

            return ['berhasil' => false, 'pesan' => 'Gagal mencatat pembayaran.'];
        }

        $stmt->close();

        return [
            'berhasil' => true,
            'pesan' => 'Terima kasih. Pembayaran Anda tercatat dan akan diperiksa '
                . 'Admin. Akun PRO aktif setelah pembayaran diterima.',
            'sudah_ada' => false,
        ];
    }
}

if (!function_exists('rts_lg_tabel_pembayaran')) {
    /**
     * Memeriksa keberadaan tabel pembayaran_pro.
     */
    function rts_lg_tabel_pembayaran(mysqli $conn): bool
    {
        return rts_lg_ada_tabel($conn, 'pembayaran_pro');
    }
}

if (!function_exists('rts_lg_siapkan_database')) {
    /**
     * Membuat kolom dan tabel yang diperlukan bila belum ada.
     * Dipakai oleh halaman langganan_admin.php (tombol pembaruan database).
     *
     * @return array<int,string> daftar kegiatan yang dikerjakan
     */
    function rts_lg_siapkan_database(mysqli $conn): array
    {
        $catatan = [];

        $tambahan = [
            'akun_pro' => "ALTER TABLE sales_users ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0",
            'foto_profil' => "ALTER TABLE sales_users ADD COLUMN foto_profil VARCHAR(255) NOT NULL DEFAULT ''",
            'pro_mulai' => 'ALTER TABLE sales_users ADD COLUMN pro_mulai DATETIME NULL DEFAULT NULL',
            'pro_selesai' => 'ALTER TABLE sales_users ADD COLUMN pro_selesai DATETIME NULL DEFAULT NULL',
            'trial_mulai' => 'ALTER TABLE sales_users ADD COLUMN trial_mulai DATETIME NULL DEFAULT NULL',
            'trial_selesai' => 'ALTER TABLE sales_users ADD COLUMN trial_selesai DATETIME NULL DEFAULT NULL',
        ];

        foreach ($tambahan as $kolom => $sql) {
            if (rts_lg_ada_kolom($conn, $kolom)) {
                $catatan[] = 'Kolom ' . $kolom . ': sudah ada.';

                continue;
            }

            if (@$conn->query($sql)) {
                $catatan[] = 'Kolom ' . $kolom . ': BERHASIL dibuat.';
            } else {
                $catatan[] = 'Kolom ' . $kolom . ': GAGAL - ' . $conn->error;
            }
        }

        if (rts_lg_ada_tabel($conn, 'pembayaran_pro')) {
            $catatan[] = 'Tabel pembayaran_pro: sudah ada.';
        } else {
            $sql = 'CREATE TABLE IF NOT EXISTS pembayaran_pro (
                id INT AUTO_INCREMENT PRIMARY KEY,
                user_id INT NOT NULL,
                jumlah INT NOT NULL DEFAULT 0,
                hari INT NOT NULL DEFAULT 30,
                catatan VARCHAR(255) NOT NULL DEFAULT \'\',
                sebab VARCHAR(40) NOT NULL DEFAULT \'\',
                status VARCHAR(20) NOT NULL DEFAULT \'MENUNGGU\',
                dibuat DATETIME NULL DEFAULT NULL,
                diproses_pada DATETIME NULL DEFAULT NULL,
                KEY idx_user (user_id),
                KEY idx_status (status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';

            if (@$conn->query($sql)) {
                $catatan[] = 'Tabel pembayaran_pro: BERHASIL dibuat.';
            } else {
                $catatan[] = 'Tabel pembayaran_pro: GAGAL - ' . $conn->error;
            }
        }

        if (rts_lg_pengaturan_siapkan($conn)) {
            $catatan[] = 'Tabel rts_lg_pengaturan (harga & durasi): siap.';
        } else {
            $catatan[] = 'Tabel rts_lg_pengaturan: GAGAL - ' . $conn->error;
        }

        return $catatan;
    }
}
