<?php
/*
 * ============================================================================
 *  RTS PANEL BY BENE - HALAMAN KELOLA VERSI APLIKASI
 *  Berkas : app_versi.php      (letakkan di public_html, satu folder dengan
 *                               dashboard.php dan pengajuan_toko.php)
 *
 *  KEGUNAAN
 *  --------
 *  Halaman ini dipakai ADMIN untuk mengunggah berkas APK versi terbaru dan
 *  mengatur keterangannya. Setelah diunggah, aplikasi RTS Panel di HP seluruh
 *  tim akan otomatis mengetahui ada versi baru saat aplikasi dibuka.
 *
 *  CARA KERJA
 *  ----------
 *  1. Admin mengunggah berkas APK dan mengisi versi (misalnya 1.2.0, kode 3)
 *  2. Halaman ini menyimpan APK ke folder   : apk/
 *  3. Halaman ini menulis berkas keterangan : apk/app_versi.json
 *  4. Bila tabel rts_app_versi sudah ada, keterangan yang sama juga DICATAT
 *     pada database sebagai riwayat, sehingga seluruh unggahan sebelumnya
 *     tetap terekam
 *  5. Aplikasi memeriksa pembaruan lewat dua jalur, berurutan:
 *        a. API  : https://rts.benedic-s.com/api/app_versi.php  (dari database)
 *        b. berkas : https://rts.benedic-s.com/apk/app_versi.json (cadangan)
 *     Bila kode versi di server lebih besar dari versi di HP, muncul
 *     pemberitahuan pembaruan beserta tombol unduh.
 *
 *  Tabel rts_app_versi dibuat dengan menjalankan RTS_PANEL_APP_VERSI.sql.
 *  Bila tabel itu belum ada, halaman ini tetap bekerja seperti biasa - hanya
 *  riwayat pada database yang belum terisi.
 *
 *  CATATAN PENTING
 *  ---------------
 *  - Angka "kode versi" harus SAMA dengan angka sesudah tanda + pada baris
 *    "version:" di pubspec.yaml saat APK itu dibangun, dan selalu bertambah
 *    (1, 2, 3, ...). Contoh: version: 1.2.0+3  ->  kode versi = 3
 *  - Halaman ini hanya dapat dibuka oleh akun dengan role ADMIN.
 *  - Tidak ada data database yang diubah oleh halaman ini.
 * ============================================================================
 */

/* --------------------------------------------------------------------------
 * VERSI BERKAS: 6  (1 Oktober 2026 - 01:10)
 *
 *   - Tombol hapus kini bekerja untuk SEMUA berkas APK di folder apk/, termasuk
 *     berkas yang diunggah lewat FTP (namanya bebas, misalnya app-release.apk).
 *     Berkas yang sedang dipublikasikan dilindungi supaya tautan unduhan
 *     aplikasi tidak menunjuk ke berkas yang sudah hilang.
 *   - Sebelum dipublikasikan, isi berkas diperiksa: harus berukuran wajar dan
 *     benar-benar berkas APK (berkas APK selalu diawali tanda PK, karena APK
 *     adalah berkas ZIP). Salah pilih berkas langsung diberi tahu.
 *
 * VERSI BERKAS: 5  - kartu "Publikasikan Berkas yang Sudah Ada di Folder apk/"
 *
 * Bila halaman pemeriksa ?diagnosa=1 menampilkan tulisan "VERSI BERKAS  : 6",
 * berarti berkas ini sudah terunggah dengan benar.
 * ------------------------------------------------------------------------ */
define('APP_VERSI_BERKAS', 6);

require_once __DIR__ . '/config.php';

/* --------------------------------------------------------------------------
 * MEMULAI SESSION
 *
 * PERBAIKAN PENTING (laporan 30 September 2026 - kedua):
 * Halaman ini sebelumnya TIDAK memanggil session_start() sendiri, tetapi
 * bergantung pada config.php. Bila config.php tidak memulainya, $_SESSION
 * kosong, sehingga halaman:
 *     - menganggap pengunjung belum login, lalu mengalihkan ke index.php;
 *       index.php melihat sesinya masih aktif, lalu mengalihkannya lagi ke
 *       dashboard.php. Itulah sebabnya menu "Versi Aplikasi" SELALU kembali
 *       ke dashboard, termasuk pada alamat ?diagnosa=1.
 * Sekarang session dipastikan aktif lebih dahulu, sebelum apa pun dibaca.
 * ------------------------------------------------------------------------ */
if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}

/* --------------------------------------------------------------------------
 * KONEKSI DATABASE
 *
 * Berkas config.php pada server dapat memakai nama variabel yang berbeda-beda
 * untuk koneksi database. Di sini dicari salah satunya - dipakai oleh penjaga
 * halaman (membaca peran dari tabel sales_users bila session tidak menyimpan
 * peran) dan oleh riwayat versi.
 *
 * Bila tidak ada koneksi, halaman TETAP bekerja - hanya riwayat versi pada
 * database yang belum terisi.
 * ------------------------------------------------------------------------ */
$app_conn = null;
$app_nama_koneksi_ditemukan = '(tidak ditemukan)';

foreach (['conn', 'mysqli', 'koneksi', 'db', 'link'] as $app_nama_koneksi) {
    if (isset($GLOBALS[$app_nama_koneksi]) && $GLOBALS[$app_nama_koneksi] instanceof mysqli) {
        $app_conn = $GLOBALS[$app_nama_koneksi];
        $app_nama_koneksi_ditemukan = $app_nama_koneksi;
        break;
    }

    if (isset($$app_nama_koneksi) && $$app_nama_koneksi instanceof mysqli) {
        $app_conn = $$app_nama_koneksi;
        $app_nama_koneksi_ditemukan = $app_nama_koneksi;
        break;
    }
}

/* --------------------------------------------------------------------------
 * HALAMAN PEMERIKSA - ?diagnosa=1
 *
 * SENGAJA diletakkan SEBELUM semua pengalihan, supaya hasil pemeriksaan tetap
 * dapat dilihat walaupun halaman ini menolak pengunjung. Tanpa ini, alamat
 * pemeriksa pun ikut teralihkan ke dashboard.php dan tidak ada gunanya.
 *
 * Isi laporan ini aman dikirimkan: nilai session hanya ditampilkan sebentar
 * (beberapa huruf pertama), bukan seluruhnya.
 * ------------------------------------------------------------------------ */
if (isset($_GET['diagnosa'])) {
    header('Content-Type: text/plain; charset=utf-8');

    /** Menampilkan sebagian nilai saja, supaya aman dikirim lewat pesan. */
    $app_samar = static function (string $nilai): string {
        $nilai = trim($nilai);

        if ($nilai === '') {
            return '(kosong)';
        }

        if (strlen($nilai) <= 4) {
            return str_repeat('*', strlen($nilai));
        }

        return substr($nilai, 0, 3) . '***' . substr($nilai, -1) . ' (' . strlen($nilai) . ' huruf)';
    };

    echo "PEMERIKSAAN HALAMAN VERSI APLIKASI\n";
    echo "==================================\n";
    echo 'VERSI BERKAS  : ' . APP_VERSI_BERKAS . "\n";
    echo 'Waktu server  : ' . date('d-m-Y H:i:s') . "\n";
    echo 'Nama berkas   : ' . basename(__FILE__) . "\n";
    echo 'Folder        : ' . __DIR__ . "\n";
    echo 'PHP           : ' . PHP_VERSION . "\n\n";

    /* --- Session --- */
    echo "SESSION\n";
    echo '  status aktif : ' . (session_status() === PHP_SESSION_ACTIVE ? 'YA' : 'TIDAK') . "\n";
    echo '  nama session : ' . session_name() . "\n";
    echo '  id session   : ' . $app_samar((string) session_id()) . "\n";
    echo '  jumlah kunci : ' . count($_SESSION) . "\n\n";

    echo "KUNCI SESSION YANG TERSEDIA\n";

    if (empty($_SESSION)) {
        echo "  (tidak ada - session kosong)\n";
    } else {
        foreach (array_keys($_SESSION) as $app_kunci_ada) {
            echo '  - ' . $app_kunci_ada . "\n";
        }
    }

    echo "\nNILAI SESSION YANG DIPAKAI PEMERIKSAAN\n";

    foreach (['is_logged_in', 'user_id', 'username', 'user', 'email', 'nama',
              'nama_lengkap', 'role', 'user_role'] as $app_kunci_penting) {
        $app_ada_kunci = array_key_exists($app_kunci_penting, $_SESSION) ? 'ada' : 'tidak ada';
        $app_nilai_kunci = array_key_exists($app_kunci_penting, $_SESSION)
            ? $app_samar((string) $_SESSION[$app_kunci_penting])
            : '-';

        echo '  ' . str_pad($app_kunci_penting, 14) . ': ' . $app_ada_kunci
            . ' / ' . $app_nilai_kunci . "\n";
    }

    /* --- Koneksi database --- */
    echo "\nDATABASE\n";

    echo '  koneksi      : ' . $app_nama_koneksi_ditemukan . "\n";

    if ($app_conn instanceof mysqli && !$app_conn->connect_errno) {
        echo '  status       : terhubung' . "\n";

        $app_user_db = '';

        foreach (['username', 'user', 'username_login'] as $app_kunci_db) {
            $app_nilai_db = trim((string) ($_SESSION[$app_kunci_db] ?? ''));

            if ($app_nilai_db !== '') {
                $app_user_db = $app_nilai_db;
                break;
            }
        }

        echo '  username sesi: ' . $app_samar($app_user_db) . "\n";

        if ($app_user_db !== '') {
            $app_st = @$app_conn->prepare('SELECT role, nama_lengkap, email FROM sales_users WHERE username = ? LIMIT 1');

            if ($app_st) {
                $app_st->bind_param('s', $app_user_db);
                $app_st->execute();
                $app_hasil = $app_st->get_result();
                $app_baris = $app_hasil ? $app_hasil->fetch_assoc() : null;
                $app_st->close();

                if ($app_baris) {
                    echo '  role di DB   : ' . strtoupper(trim((string) ($app_baris['role'] ?? ''))) . "\n";
                    echo '  nama di DB   : ' . $app_samar((string) ($app_baris['nama_lengkap'] ?? '')) . "\n";
                } else {
                    echo "  role di DB   : (username tidak ditemukan pada sales_users)\n";
                }
            } else {
                echo '  role di DB   : (permintaan gagal: ' . $app_conn->error . ")\n";
            }
        }
    } elseif (isset($app_conn) && $app_conn instanceof mysqli) {
        echo '  status       : GAGAL - ' . $app_conn->connect_error . "\n";
    } else {
        echo "  status       : tidak ada koneksi database di halaman ini\n";
    }

    /* --- Berkas pendukung --- */
    echo "\nBERKAS\n";

    foreach (['config.php', 'auth.php', 'header.php', 'footer.php', 'sidebar.php',
              'api/app_versi.php', 'apk/app_versi.json', 'apk'] as $app_cek_berkas) {
        echo '  ' . str_pad($app_cek_berkas, 20) . ': '
            . (file_exists(__DIR__ . '/' . $app_cek_berkas) ? 'ADA' : 'TIDAK ADA') . "\n";
    }

    /* --- Simulasi penjaga halaman --------------------------------------- */
    echo "\nSIMULASI PENJAGA HALAMAN\n";
    echo "  (menjawab langsung: apakah halaman ini akan mengalihkan pengunjung)\n\n";

    $app_uji_penanda = ['is_logged_in', 'user_id', 'username', 'nama', 'email'];
    $app_uji_login = false;
    $app_uji_login_kunci = '-';

    foreach ($app_uji_penanda as $app_uji_satu) {
        if (!empty($_SESSION[$app_uji_satu])) {
            $app_uji_login = true;
            $app_uji_login_kunci = $app_uji_satu;
            break;
        }
    }

    echo '  penanda login dipakai : ' . $app_uji_login_kunci . "\n";

    $app_uji_role = '';

    foreach (['role', 'user_role'] as $app_uji_kunci_role) {
        $app_uji_nilai = strtoupper(trim((string) ($_SESSION[$app_uji_kunci_role] ?? '')));

        if ($app_uji_nilai !== '') {
            $app_uji_role = $app_uji_nilai;
            break;
        }
    }

    echo '  peran dari session    : ' . ($app_uji_role === '' ? '(kosong)' : $app_uji_role) . "\n";

    if (str_replace([' ', '_'], '', $app_uji_role) === 'SUPERADMIN') {
        $app_uji_role = 'ADMIN';
    }

    echo '  peran setelah disamakan: ' . ($app_uji_role === '' ? '(kosong)' : $app_uji_role) . "\n\n";

    if (!$app_uji_login) {
        echo "  HASIL: pengunjung akan dialihkan ke index.php (belum login).\n";
    } elseif ($app_uji_role !== 'ADMIN') {
        echo "  HASIL: pengunjung akan dialihkan ke dashboard.php (peran bukan ADMIN).\n";
        echo "  Tindakan: isi kolom role akun ini dengan ADMIN pada tabel sales_users.\n";
    } else {
        echo "  HASIL: penjaga LOLOS - halaman tidak mengalihkan pengunjung.\n";
        echo "  Halaman ini akan menampilkan formulir unggah APK seperti biasa.\n";
    }

    echo "\nHalaman ini tidak mengubah data apa pun.\n";

    exit;
}

/* --------------------------------------------------------------------------
 * PENJAGA HALAMAN - hanya ADMIN
 *
 * PERBAIKAN PENTING (dilaporkan 30 September 2026):
 * Sebelumnya halaman ini hanya memakai $_SESSION['email'] untuk mengetahui
 * apakah pengunjung sudah login, dan $_SESSION['role'] untuk memeriksa peran.
 * Akibatnya Admin yang sah dapat terlempar kembali ke dashboard.php, karena:
 *
 *   1. Tidak semua halaman login mengisi kunci 'email' pada session (misalnya
 *      akun yang kolom emailnya kosong pada tabel sales_users). Bila 'email'
 *      kosong, halaman ini mengalihkan pengunjung ke index.php; halaman login
 *      itu melihat session masih aktif, lalu mengalihkannya lagi ke
 *      dashboard.php. Dari sisi pengguna: menekan menu "Versi Aplikasi"
 *      seolah-olah tidak terjadi apa-apa, hanya kembali ke dashboard.
 *   2. Nama kunci session dapat berbeda antar halaman (role / user_role),
 *      dan ejaan perannya dapat berupa "admin", "Admin", atau "Super Admin".
 *
 * Karena itu sekarang dipakai pemeriksaan berlapis:
 *   - login  : salah satu penanda sudah ada (is_logged_in, user_id, username,
 *              nama, email)
 *   - peran  : dibaca dari session (role / user_role); bila belum ada, dibaca
 *              dari tabel sales_users memakai username; ejaan diseragamkan
 *              dan "SUPER ADMIN" diperlakukan sama dengan "ADMIN"
 *
 * Bila tetap bukan ADMIN, pengunjung dialihkan ke dashboard.php seperti
 * semula. Untuk memeriksa sebabnya, tambahkan ?diagnosa=1 pada alamat.
 * ------------------------------------------------------------------------ */

$app_penanda_login = ['is_logged_in', 'user_id', 'username', 'nama', 'email'];
$app_sudah_login = false;

foreach ($app_penanda_login as $app_kunci_login) {
    if (!empty($_SESSION[$app_kunci_login])) {
        $app_sudah_login = true;
        break;
    }
}

if (!$app_sudah_login) {
    header('Location: index.php');
    exit;
}

/* --- Membaca peran dari session --------------------------------------- */
$app_role = '';

foreach (['role', 'user_role'] as $app_kunci_role) {
    $app_nilai_role = strtoupper(trim((string) ($_SESSION[$app_kunci_role] ?? '')));

    if ($app_nilai_role !== '') {
        $app_role = $app_nilai_role;
        break;
    }
}

/* --- Bila session tidak menyimpan peran, dibaca dari database ---------- */
if ($app_role === '' && isset($app_conn) && $app_conn instanceof mysqli) {
    $app_username = '';

    foreach (['username', 'user', 'username_login'] as $app_kunci_user) {
        $app_nilai_user = trim((string) ($_SESSION[$app_kunci_user] ?? ''));

        if ($app_nilai_user !== '') {
            $app_username = $app_nilai_user;
            break;
        }
    }

    if ($app_username !== '') {
        $app_stmt_peran = @$app_conn->prepare(
            'SELECT role FROM sales_users WHERE username = ? LIMIT 1'
        );

        if ($app_stmt_peran) {
            $app_stmt_peran->bind_param('s', $app_username);
            $app_stmt_peran->execute();
            $app_hasil_peran = $app_stmt_peran->get_result();
            $app_baris_peran = $app_hasil_peran ? $app_hasil_peran->fetch_assoc() : null;
            $app_stmt_peran->close();

            if ($app_baris_peran) {
                $app_role = strtoupper(trim((string) ($app_baris_peran['role'] ?? '')));
            }
        }
    }
}

/* "SUPER ADMIN" dan "SUPER_ADMIN" diperlakukan sama dengan ADMIN. */
if (str_replace([' ', '_'], '', $app_role) === 'SUPERADMIN') {
    $app_role = 'ADMIN';
}

if ($app_role !== 'ADMIN') {
    header('Location: dashboard.php');
    exit;
}

require_once __DIR__ . '/header.php';

/* --------------------------------------------------------------------------
 * PERSIAPAN FOLDER
 * -------------------------------------------------------------------------- */
$app_folder = __DIR__ . '/apk';
$app_berkas_json = $app_folder . '/app_versi.json';

if (!is_dir($app_folder)) {
    @mkdir($app_folder, 0755, true);
}

$app_pesan = '';
$app_galat = '';

/* Batas unggah dari pengaturan PHP (ditampilkan sebagai informasi). */
$app_batas_unggah = ini_get('upload_max_filesize');
$app_batas_post = ini_get('post_max_size');

/* --------------------------------------------------------------------------
 * BATAS UKURAN UNGGUH YANG DIIZINKAN HALAMAN INI (100 MB)
 * -------------------------------------------------------------------------- */
define('APP_BATAS_BITA', 104857600);

/**
 * Membaca berkas keterangan versi yang tersimpan.
 *
 * @return array<string,mixed>
 */
function app_baca_versi(string $jalur): array
{
    if (!is_file($jalur)) {
        return [];
    }

    $isi = @file_get_contents($jalur);

    if ($isi === false || trim($isi) === '') {
        return [];
    }

    $data = json_decode($isi, true);

    return is_array($data) ? $data : [];
}

/**
 * Menulis berkas keterangan versi.
 *
 * @param array<string,mixed> $data
 */
function app_tulis_versi(string $jalur, array $data): bool
{
    $teks = json_encode(
        $data,
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );

    if ($teks === false) {
        return false;
    }

    return @file_put_contents($jalur, $teks . "\n") !== false;
}

/**
 * Memeriksa keberadaan sebuah tabel pada database yang aktif.
 *
 * Memakai SHOW TABLES, BUKAN information_schema - akun database cPanel tidak
 * diberi izin membaca information_schema (kesalahan #1044).
 */
function app_ada_tabel(mysqli $conn, string $nama): bool
{
    if (preg_match('/^[A-Za-z0-9_]+$/', $nama) !== 1) {
        return false;
    }

    $hasil = @$conn->query("SHOW TABLES LIKE '" . $conn->real_escape_string($nama) . "'");

    $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

    if ($hasil instanceof mysqli_result) {
        $hasil->free();
    }

    return $ada;
}

/**
 * Alamat dasar website ini, dipakai untuk menyusun tautan unduhan.
 */
function app_alamat_dasar(): string
{
    $skema = 'http';

    if (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off') {
        $skema = 'https';
    }

    $host = (string)($_SERVER['HTTP_HOST'] ?? '');

    return $skema . '://' . $host;
}

/**
 * Memeriksa apakah sebuah berkas benar-benar berisi berkas APK.
 *
 * Berkas APK dibungkus sebagai berkas ZIP, jadi dua bita pertamanya selalu
 * "PK". Pemeriksaan ini menangkap kesalahan yang sering terjadi: berkas lain
 * (misalnya halaman galat atau berkas gambar) diubah namanya menjadi .apk.
 */
function app_isi_apk_benar(string $jalur): bool
{
    $pegang = @fopen($jalur, 'rb');

    if (!$pegang) {
        return false;
    }

    $tanda = (string) @fread($pegang, 2);
    @fclose($pegang);

    return $tanda === 'PK';
}

/**
 * Membersihkan nama berkas APK.
 */
function app_nama_aman(string $teks): string
{
    $bersih = preg_replace('/[^A-Za-z0-9._-]/', '_', $teks);
    $bersih = trim((string)$bersih, '._-');

    return $bersih === '' ? 'rts_panel' : $bersih;
}

/* --------------------------------------------------------------------------
 * MENYIMPAN SATU VERSI BARU (DIPAKAI DUA JALUR)
 *
 *   1. Unggahan lewat formulir halaman ini (batasnya mengikuti batas PHP)
 *   2. PUBLIKASI berkas APK yang SUDAH ADA di folder apk/ - hasil unggahan
 *      lewat FTP atau cPanel File Manager, yang TIDAK dibatasi PHP
 *
 * Karena keduanya memakai satu fungsi ini, hasilnya sama: keterangan versi
 * ditulis, riwayat database dicatat, dan SELURUH HP menerima pemberitahuan
 * pembaruan lewat Firebase Cloud Messaging (tetap otomatis).
 * -------------------------------------------------------------------------- */
function app_simpan_versi(
    string $folder_apk,
    string $berkas_json,
    $conn,
    string $nama_berkas,
    string $nama_versi,
    int $kode_versi,
    bool $wajib,
    string $catatan,
    int $ukuran
): array {
    $data = [
        'version_code' => $kode_versi,
        'version_name' => $nama_versi,
        'wajib' => $wajib,
        'catatan' => $catatan,
        'apk' => app_alamat_dasar() . '/apk/' . $nama_berkas,
        'ukuran_mb' => round($ukuran / 1048576, 2),
        'dipublikasikan' => date('d-m-Y H:i'),
    ];

    if (!app_tulis_versi($berkas_json, $data)) {
        return [
            'berhasil' => false,
            'pesan' => 'Berkas keterangan versi (app_versi.json) gagal ditulis. '
                . 'Periksa izin folder apk/.',
            'data' => $data,
        ];
    }

    $pesan = 'Versi ' . $nama_versi . ' (kode ' . $kode_versi . ') sudah '
        . 'dipublikasikan dari berkas ' . $nama_berkas . '. '
        . 'Seluruh tim akan menerima pemberitahuan pembaruan.';

    /* Pemberitahuan otomatis ke seluruh HP - muncul walau aplikasi tidak dibuka. */
    if (is_file(__DIR__ . '/api/notif_otomatis.php')) {
        require_once __DIR__ . '/api/notif_otomatis.php';

        if (function_exists('rts_notif_versi_baru') && $conn instanceof mysqli) {
            try {
                $kabar = rts_notif_versi_baru(
                    $conn,
                    $data,
                    (string) ($_SESSION['email'] ?? '')
                );

                if ((int) $kabar['hp'] > 0) {
                    $pesan .= ' Pemberitahuan sudah dikirim ke '
                        . (int) $kabar['hp'] . ' HP petugas.';
                }
            } catch (Throwable $galat_notif) {
                error_log('RTS notif versi: ' . $galat_notif->getMessage());
            }
        }
    }

    /* Riwayat pada tabel rts_app_versi (bila tabelnya sudah ada). */
    if (app_ada_tabel($conn, 'rts_app_versi')) {
        $simpanDb = $conn->prepare(
            'INSERT INTO rts_app_versi
             (version_code, version_name, wajib, catatan, apk,
              ukuran_mb, diunggah_oleh, aktif)
             VALUES (?, ?, ?, ?, ?, ?, ?, 1)'
        );

        if ($simpanDb) {
            $kodeDb = $kode_versi;
            $namaDb = $nama_versi;
            $wajibDb = $wajib ? 1 : 0;
            $catatanDb = $catatan;
            $apkDb = $data['apk'];
            $ukuranDb = $data['ukuran_mb'];
            $olehDb = (string) ($_SESSION['email'] ?? '');

            $simpanDb->bind_param(
                'isissds',
                $kodeDb,
                $namaDb,
                $wajibDb,
                $catatanDb,
                $apkDb,
                $ukuranDb,
                $olehDb
            );

            if (!$simpanDb->execute()) {
                $pesan .= ' Catatan: riwayat database gagal ditulis - '
                    . $simpanDb->error;
            }

            $simpanDb->close();
        }
    }

    /* Riwayat.txt supaya admin tahu apa yang terakhir dipublikasikan. */
    @file_put_contents(
        $folder_apk . '/riwayat.txt',
        date('d-m-Y H:i') . ' | versi ' . $nama_versi . ' (kode ' . $kode_versi
        . ') | ' . $nama_berkas . ' | wajib: ' . ($wajib ? 'ya' : 'tidak')
        . ' | oleh ' . (string) ($_SESSION['email'] ?? '') . "\n",
        FILE_APPEND
    );

    return ['berhasil' => true, 'pesan' => $pesan, 'data' => $data];
}

/* --------------------------------------------------------------------------
 * PROSES UNGGAH BERKAS APK
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['app_unggah'])) {
    $nama_versi = trim((string)($_POST['version_name'] ?? ''));
    $kode_versi = (int)($_POST['version_code'] ?? 0);
    $wajib = isset($_POST['wajib']) ? true : false;
    $catatan = trim((string)($_POST['catatan'] ?? ''));

    if ($nama_versi === '') {
        $app_galat = 'Kolom "Versi aplikasi" wajib diisi, contoh: 1.2.0';
    } elseif ($kode_versi < 1) {
        $app_galat = 'Kolom "Kode versi" wajib diisi dengan angka 1 atau lebih besar.';
    } elseif (preg_match('/^[0-9]+(\.[0-9]+){0,3}$/', $nama_versi) !== 1) {
        $app_galat = 'Versi aplikasi hanya boleh berisi angka dan titik, contoh: 1.2.0';
    } elseif (!isset($_FILES['berkas_apk']) || (int)$_FILES['berkas_apk']['error'] === UPLOAD_ERR_NO_FILE) {
        $app_galat = 'Berkas APK belum dipilih.';
    } elseif ((int)$_FILES['berkas_apk']['error'] !== UPLOAD_ERR_OK) {
        $kode = (int)$_FILES['berkas_apk']['error'];

        $keterangan = [
            UPLOAD_ERR_INI_SIZE => 'Ukuran berkas melebihi batas server (' . $app_batas_unggah . ').',
            UPLOAD_ERR_FORM_SIZE => 'Ukuran berkas melebihi batas yang diizinkan halaman ini.',
            UPLOAD_ERR_PARTIAL => 'Unggahan terputus di tengah jalan. Coba lagi.',
            UPLOAD_ERR_NO_TMP_DIR => 'Server tidak menyediakan folder sementara.',
            UPLOAD_ERR_CANT_WRITE => 'Server gagal menulis berkas. Periksa izin folder apk/.',
            UPLOAD_ERR_EXTENSION => 'Unggahan dihentikan oleh pengaturan server.',
        ];

        $app_galat = $keterangan[$kode] ?? ('Unggahan gagal dengan kode ' . $kode . '.');
    } else {
        $berkas = $_FILES['berkas_apk'];
        $ukuran = (int)$berkas['size'];
        $nama_asli = (string)$berkas['name'];
        $akhiran = strtolower((string)pathinfo($nama_asli, PATHINFO_EXTENSION));

        if ($akhiran !== 'apk') {
            $app_galat = 'Berkas yang diunggah harus berakhiran .apk';
        } elseif ($ukuran > APP_BATAS_BITA) {
            $app_galat = 'Ukuran APK melebihi 100 MB.';
        } elseif (!is_uploaded_file((string)$berkas['tmp_name'])) {
            $app_galat = 'Berkas unggahan tidak sah.';
        } else {
            $nama_simpan = app_nama_aman('rts_panel_v' . $kode_versi);
            $nama_berkas = $nama_simpan . '.apk';
            $tujuan = $app_folder . '/' . $nama_berkas;

            if (!@move_uploaded_file((string)$berkas['tmp_name'], $tujuan)) {
                $app_galat = 'Gagal menyimpan berkas ke folder apk/. Periksa izin folder.';
            } else {
                @chmod($tujuan, 0644);

                /* Seluruh pekerjaan (keterangan versi, pemberitahuan ke seluruh
                   HP, riwayat database, dan riwayat.txt) dikerjakan oleh satu
                   fungsi yang sama dengan jalur "publikasi berkas yang sudah
                   ada" - sehingga hasilnya selalu sama. */
                $app_hasil = app_simpan_versi(
                    $app_folder,
                    $app_berkas_json,
                    $app_conn,
                    $nama_berkas,
                    $nama_versi,
                    $kode_versi,
                    $wajib,
                    $catatan,
                    $ukuran
                );

                if ($app_hasil['berhasil']) {
                    $app_pesan = $app_hasil['pesan'];
                } else {
                    $app_galat = $app_hasil['pesan'];
                }
            }
        }
    }
}

/* --------------------------------------------------------------------------
 * PROSES PUBLIKASI BERKAS APK YANG SUDAH ADA DI FOLDER apk/
 *
 * KEGUNAAN
 * --------
 * Berkas APK yang besar (misalnya di atas 50 MB) sering gagal diunggah lewat
 * formulir web karena batas PHP (upload_max_filesize / post_max_size).
 *
 * Jalan keluarnya: unggah berkas APK itu lewat FTP (FileZilla) atau cPanel
 * File Manager - keduanya TIDAK dibatasi PHP - langsung ke dalam folder apk/
 * pada hosting. Setelah berkasnya ada di sana, cukup pilih berkasnya pada
 * halaman ini, isi keterangan versi, lalu tekan PUBLIKASIKAN.
 *
 * Hasilnya SAMA dengan unggahan biasa: keterangan versi ditulis ke
 * app_versi.json, riwayat dicatat ke database, dan SELURUH HP menerima
 * pemberitahuan pembaruan lewat Firebase Cloud Messaging (tombol UPDATE).
 * Jadi pembaruan OTOMATIS tetap berjalan tanpa memakai layanan pihak ketiga.
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['app_publikasi'])) {
    $nama_publikasi = basename((string)($_POST['nama_berkas'] ?? ''));
    $nama_versi_pub = trim((string)($_POST['version_name'] ?? ''));
    $kode_versi_pub = (int)($_POST['version_code'] ?? 0);
    $wajib_pub = isset($_POST['wajib']) ? true : false;
    $catatan_pub = trim((string)($_POST['catatan'] ?? ''));

    $jalur_publikasi = $app_folder . '/' . $nama_publikasi;

    if ($nama_publikasi === '' || strtolower((string)pathinfo($nama_publikasi, PATHINFO_EXTENSION)) !== 'apk') {
        $app_galat = 'Berkas yang dipilih bukan berkas APK.';
    } elseif (!is_file($jalur_publikasi)) {
        $app_galat = 'Berkas ' . htmlspecialchars($nama_publikasi) . ' tidak ditemukan di folder apk/.';
    } elseif (($app_ukuran_pub = (int) @filesize($jalur_publikasi)) < 1048576) {
        $app_galat = 'Berkas ' . htmlspecialchars($nama_publikasi) . ' ukurannya hanya '
            . number_format($app_ukuran_pub / 1024, 0, ',', '.') . ' KB. Berkas APK yang benar '
            . 'berukuran puluhan MB - kemungkinan berkas ini bukan APK (misalnya halaman galat '
            . 'yang tersimpan dengan akhiran .apk).';
    } elseif (!app_isi_apk_benar($jalur_publikasi)) {
        $app_galat = 'Isi berkas ' . htmlspecialchars($nama_publikasi) . ' bukan berkas APK '
            . '(berkas APK selalu diawali tanda PK). Pastikan berkas yang diunggah lewat FTP '
            . 'benar-benar app-release.apk hasil flutter build apk, bukan berkas lain.';
    } elseif ($nama_versi_pub === '') {
        $app_galat = 'Kolom "Versi aplikasi" wajib diisi, contoh: 1.2.1';
    } elseif (preg_match('/^[0-9]+(\.[0-9]+){0,3}$/', $nama_versi_pub) !== 1) {
        $app_galat = 'Versi aplikasi hanya boleh berisi angka dan titik, contoh: 1.2.1';
    } elseif ($kode_versi_pub < 1) {
        $app_galat = 'Kolom "Kode versi" wajib diisi dengan angka 1 atau lebih besar.';
    } else {
        $app_hasil = app_simpan_versi(
            $app_folder,
            $app_berkas_json,
            $app_conn,
            $nama_publikasi,
            $nama_versi_pub,
            $kode_versi_pub,
            $wajib_pub,
            $catatan_pub,
            (int)@filesize($jalur_publikasi)
        );

        if ($app_hasil['berhasil']) {
            $app_pesan = $app_hasil['pesan'];
        } else {
            $app_galat = $app_hasil['pesan'];
        }
    }
}

/* --------------------------------------------------------------------------
 * PROSES HAPUS BERKAS APK LAMA
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['app_hapus'])) {
    $nama = basename((string)($_POST['nama_berkas'] ?? ''));

    if ($nama !== '' && strtolower((string)pathinfo($nama, PATHINFO_EXTENSION)) === 'apk') {
        $jalur = $app_folder . '/' . $nama;

        $app_versi_hapus = app_baca_versi($app_berkas_json);
        $app_terbit_hapus = basename((string) ($app_versi_hapus['apk'] ?? ''));

        if (!is_file($jalur)) {
            $app_galat = 'Berkas tidak ditemukan.';
        } elseif ($nama === $app_terbit_hapus) {
            $app_galat = 'Berkas ' . htmlspecialchars($nama) . ' sedang DIPUBLIKASIKAN, jadi belum '
                . 'dapat dihapus - tautan unduhan pada aplikasi menunjuk ke berkas ini. '
                . 'Publikasikan berkas APK yang lain lebih dahulu, lalu berkas ini dapat dihapus.';
        } elseif (@unlink($jalur)) {
            $app_pesan = 'Berkas ' . htmlspecialchars($nama) . ' dihapus.';
        } else {
            $app_galat = 'Gagal menghapus berkas. Periksa izin folder apk/.';
        }
    }
}

/* --------------------------------------------------------------------------
 * DATA UNTUK TAMPILAN
 * -------------------------------------------------------------------------- */
$app_versi = app_baca_versi($app_berkas_json);

$app_daftar_apk = [];

if (is_dir($app_folder)) {
    $isi_folder = scandir($app_folder);

    if (is_array($isi_folder)) {
        foreach ($isi_folder as $nama) {
            if (strtolower((string)pathinfo($nama, PATHINFO_EXTENSION)) !== 'apk') {
                continue;
            }

            $jalur = $app_folder . '/' . $nama;

            $app_daftar_apk[] = [
                'nama' => $nama,
                'ukuran' => (int)@filesize($jalur),
                'waktu' => (int)@filemtime($jalur),
            ];
        }
    }
}

usort($app_daftar_apk, static function (array $a, array $b): int {
    return $b['waktu'] <=> $a['waktu'];
});

$app_alamat_json = app_alamat_dasar() . '/apk/app_versi.json';

/* Berkas APK yang SUDAH ADA di folder apk/ tetapi BELUM dipublikasikan.
   Berkas seperti ini muncul bila diunggah lewat FTP atau cPanel File Manager
   (tidak dibatasi PHP), sehingga berguna untuk APK berukuran besar. */
$app_nama_terbit = basename((string)($app_versi['apk'] ?? ''));
$app_belum_publikasi = [];

foreach ($app_daftar_apk as $app_satu) {
    if ($app_satu['nama'] === $app_nama_terbit) {
        continue;
    }

    $app_belum_publikasi[] = $app_satu;
}

$app_kode_saran = (int)($app_versi['version_code'] ?? 0) + 1;
$app_json_siap = is_file($app_berkas_json);

/* Riwayat versi pada database (bila tabelnya sudah ada). */
$app_tabel_db = app_ada_tabel($app_conn, 'rts_app_versi');

$app_riwayat_db = [];

if ($app_tabel_db) {
    $ambilRiwayat = @$app_conn->query(
        'SELECT id, version_code, version_name, wajib, apk, ukuran_mb,
                diunggah_oleh, dibuat_pada
         FROM rts_app_versi
         ORDER BY version_code DESC, id DESC
         LIMIT 15'
    );

    if ($ambilRiwayat instanceof mysqli_result) {
        while ($barisRiwayat = $ambilRiwayat->fetch_assoc()) {
            $app_riwayat_db[] = $barisRiwayat;
        }

        $ambilRiwayat->free();
    }
}

?>

<style>
.rts-card{background:#fff;border:1px solid #eadfd6;border-radius:16px;box-shadow:0 6px 18px rgba(74,44,34,.06)}
.rts-aksi{display:flex;gap:8px;flex-wrap:wrap}
.rts-versi-kotak{border:1px solid #eadfd6;border-radius:14px;padding:14px 16px;background:#fff}
.rts-versi-kotak .label{font-size:12px;color:#8a7d76}
.rts-versi-kotak .nilai{font-weight:700;color:#3a2a24}
.rts-kode{background:#f7f3f2;border:1px solid #eadfd6;border-radius:12px;padding:12px;font-size:12px;overflow:auto;max-height:230px}
.rts-petunjuk{background:#fdf6ec;border:1px solid #f0e2cf;border-radius:14px;padding:14px 16px;font-size:13px;color:#7a5a26}
</style>

<div class="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
  <div>
    <h4 class="mb-1"><i class="fa-solid fa-mobile-screen-button text-danger me-2"></i>Versi Aplikasi Android</h4>
    <div class="text-muted small">Unggah APK terbaru agar seluruh tim ikut memperbarui otomatis.</div>
  </div>
  <a class="btn btn-outline-secondary btn-sm" href="dashboard.php">
    <i class="fa-solid fa-arrow-left me-1"></i>Kembali ke Dashboard
  </a>
</div>

<?php if ($app_pesan !== ''): ?>
  <div class="alert alert-success"><i class="fa-solid fa-circle-check me-2"></i><?= $app_pesan ?></div>
<?php endif; ?>

<?php if ($app_galat !== ''): ?>
  <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation me-2"></i><?= htmlspecialchars($app_galat) ?></div>
<?php endif; ?>

<div class="row g-3">
  <div class="col-lg-7">
    <div class="rts-card p-3 p-md-4">
      <h6 class="mb-3"><i class="fa-solid fa-cloud-arrow-up text-danger me-2"></i>Unggah APK Baru</h6>

      <form method="post" enctype="multipart/form-data" autocomplete="off">
        <input type="hidden" name="app_unggah" value="1">

        <div class="row g-3">
          <div class="col-sm-6">
            <label class="form-label">Versi aplikasi <span class="text-danger">*</span></label>
            <input type="text" name="version_name" class="form-control" placeholder="1.2.0" required
                   value="<?= htmlspecialchars((string)($app_versi['version_name'] ?? '')) ?>">
            <div class="form-text">Harus sama dengan baris <code>version:</code> di pubspec.yaml sebelum tanda +.</div>
          </div>

          <div class="col-sm-6">
            <label class="form-label">Kode versi <span class="text-danger">*</span></label>
            <input type="number" name="version_code" class="form-control" min="1" placeholder="3" required
                   value="<?= (int)($app_versi['version_code'] ?? 0) > 0 ? (int)$app_versi['version_code'] + 1 : '' ?>">
            <div class="form-text">Angka sesudah tanda + pada pubspec.yaml. WAJIB selalu bertambah.</div>
          </div>

          <div class="col-12">
            <label class="form-label">Berkas APK <span class="text-danger">*</span></label>
            <input type="file" name="berkas_apk" class="form-control" accept=".apk" required>
            <div class="form-text">
              Diambil dari <code>build\app\outputs\flutter-apk\app-release.apk</code> setelah
              menjalankan <code>flutter build apk --release</code>.
              Batas server saat ini: <strong><?= htmlspecialchars((string)$app_batas_unggah) ?></strong>
              (post: <?= htmlspecialchars((string)$app_batas_post) ?>).
            </div>
          </div>

          <div class="col-12">
            <label class="form-label">Catatan pembaruan</label>
            <textarea name="catatan" class="form-control" rows="3"
                      placeholder="Contoh: perbaikan filter GSP dan tampilan beranda baru."><?= htmlspecialchars((string)($app_versi['catatan'] ?? '')) ?></textarea>
          </div>

          <div class="col-12">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="wajib" id="wajib" value="1">
              <label class="form-check-label" for="wajib">
                Pembaruan WAJIB (petugas tidak dapat menutup pemberitahuan sebelum memperbarui)
              </label>
            </div>
          </div>

          <div class="col-12">
            <button type="submit" class="btn btn-danger">
              <i class="fa-solid fa-cloud-arrow-up me-1"></i>Unggah &amp; Umumkan Versi Ini
            </button>
          </div>
        </div>
      </form>
    </div>

    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3"><i class="fa-solid fa-clock-rotate-left text-danger me-2"></i>Berkas APK di Server</h6>

      <?php if (empty($app_daftar_apk)): ?>
        <div class="text-muted small">Belum ada berkas APK di folder <code>apk/</code>.</div>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm align-middle mb-0">
            <thead>
              <tr>
                <th>Nama berkas</th>
                <th class="text-end">Ukuran</th>
                <th>Diunggah</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($app_daftar_apk as $berkas): ?>
                <tr>
                  <td class="small">
                    <a href="apk/<?= htmlspecialchars($berkas['nama']) ?>" target="_blank">
                      <?= htmlspecialchars($berkas['nama']) ?>
                    </a>
                    <?php if (($app_versi['apk'] ?? '') !== '' && basename((string)$app_versi['apk']) === $berkas['nama']): ?>
                      <span class="badge bg-success ms-1">Dipublikasikan</span>
                    <?php endif; ?>
                  </td>
                  <td class="text-end small"><?= number_format($berkas['ukuran'] / 1048576, 1, ',', '.') ?> MB</td>
                  <td class="small"><?= date('d-m-Y H:i', $berkas['waktu']) ?></td>
                  <td class="text-end">
                    <form method="post" onsubmit="return confirm('Hapus berkas ini?');" class="d-inline">
                      <input type="hidden" name="app_hapus" value="1">
                      <input type="hidden" name="nama_berkas" value="<?= htmlspecialchars($berkas['nama']) ?>">
                      <button type="submit" class="btn btn-sm btn-outline-danger">
                        <i class="fa-solid fa-trash"></i>
                      </button>
                    </form>
                  </td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3">
        <i class="fa-solid fa-box-open text-danger me-2"></i>Publikasikan Berkas yang Sudah Ada di Folder apk/
      </h6>

      <p class="small text-muted mb-3">
        Berguna untuk <strong>berkas APK berukuran besar</strong> (misalnya di atas 50 MB)
        yang gagal diunggah lewat formulir karena batas PHP pada hosting.
        Caranya:
        <strong>1.</strong> unggah berkas APK lewat FTP (FileZilla) atau
        <strong>cPanel &rarr; File Manager</strong> langsung ke folder
        <code>apk/</code> &mdash; keduanya tidak dibatasi PHP;
        <strong>2.</strong> berkasnya akan muncul pada daftar di bawah ini;
        <strong>3.</strong> isi keterangan versi lalu tekan
        <strong>PUBLIKASIKAN</strong>.
        Hasilnya <strong>sama</strong> dengan unggahan biasa: seluruh HP menerima
        pemberitahuan pembaruan (tombol UPDATE) secara otomatis.
      </p>

      <?php if (empty($app_belum_publikasi)): ?>
        <div class="alert alert-light border mb-0 small">
          Tidak ada berkas APK yang menunggu dipublikasikan. Seluruh berkas pada
          folder <code>apk/</code> sudah pernah dipublikasikan, atau belum ada
          berkas tambahan di sana.
        </div>
      <?php else: ?>
        <?php foreach ($app_belum_publikasi as $app_pub): ?>
          <form method="post" class="border rounded p-3 mb-3 bg-light-subtle" autocomplete="off">
            <input type="hidden" name="app_publikasi" value="1">
            <input type="hidden" name="nama_berkas" value="<?= htmlspecialchars((string)$app_pub['nama']) ?>">

            <div class="d-flex flex-wrap align-items-center gap-2 mb-2">
              <i class="fa-solid fa-file-zipper text-danger"></i>
              <span class="fw-semibold small"><?= htmlspecialchars((string)$app_pub['nama']) ?></span>
              <span class="badge bg-light text-dark border">
                <?= number_format((float)$app_pub['ukuran'] / 1048576, 1, ',', '.') ?> MB
              </span>
              <span class="badge bg-light text-dark border">
                <?= date('d-m-Y H:i', (int)$app_pub['waktu']) ?>
              </span>
              <a class="small ms-auto" href="apk/<?= htmlspecialchars((string)$app_pub['nama']) ?>"
                 target="_blank" rel="noopener">
                <i class="fa-solid fa-download me-1"></i>periksa berkas
              </a>
            </div>

            <div class="row g-2">
              <div class="col-sm-4">
                <label class="form-label small mb-1">Versi aplikasi <span class="text-danger">*</span></label>
                <input type="text" name="version_name" class="form-control form-control-sm"
                       placeholder="1.2.1" required
                       value="<?= htmlspecialchars((string)($app_versi['version_name'] ?? '')) ?>">
              </div>

              <div class="col-sm-4">
                <label class="form-label small mb-1">Kode versi <span class="text-danger">*</span></label>
                <input type="number" name="version_code" class="form-control form-control-sm"
                       min="1" required value="<?= (int)$app_kode_saran ?>">
                <div class="form-text mb-0">
                  Angka sesudah tanda + pada pubspec.yaml. Wajib lebih besar dari
                  kode versi yang sedang dipakai (<?= (int)($app_versi['version_code'] ?? 0) ?>).
                </div>
              </div>

              <div class="col-sm-4">
                <label class="form-label small mb-1">Sifat pembaruan</label>
                <div class="form-check mt-1">
                  <input class="form-check-input" type="checkbox" name="wajib"
                         id="wajib_pub_<?= htmlspecialchars((string)$app_pub['nama']) ?>" value="1">
                  <label class="form-check-label small"
                         for="wajib_pub_<?= htmlspecialchars((string)$app_pub['nama']) ?>">
                    WAJIB (petugas tidak dapat menutup pemberitahuan)
                  </label>
                </div>
              </div>

              <div class="col-12">
                <label class="form-label small mb-1">Catatan pembaruan</label>
                <textarea name="catatan" class="form-control form-control-sm" rows="2"
                          placeholder="Contoh: nama aplikasi menjadi RTS Panel; halaman Kelola Akun PRO."></textarea>
              </div>

              <div class="col-12 d-flex justify-content-end">
                <button type="submit" class="btn btn-sm btn-danger">
                  <i class="fa-solid fa-cloud-arrow-up me-1"></i>Publikasikan Berkas Ini
                </button>
              </div>
            </div>
          </form>
        <?php endforeach; ?>
      <?php endif; ?>
    </div>

    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3">
        <i class="fa-solid fa-clock-rotate-left text-danger me-2"></i>Riwayat Versi
      </h6>

      <?php if (!$app_tabel_db): ?>
        <div class="alert alert-warning mb-0 small">
          Tabel <code>rts_app_versi</code> belum ada pada database, sehingga
          riwayat versi belum dapat disimpan. Jalankan
          <code>RTS_PANEL_APP_VERSI.sql</code> lewat phpMyAdmin (tab SQL) untuk
          mengaktifkannya. Halaman ini tetap berfungsi seperti biasa sebelum
          tabelnya dibuat - hanya riwayat ini yang belum terisi.
        </div>
      <?php elseif (empty($app_riwayat_db)): ?>
        <div class="text-muted small">
          Tabel sudah ada, tetapi belum ada versi yang tercatat. Riwayat akan
          terisi otomatis setiap kali Anda mengunggah APK pada formulir di atas.
        </div>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm align-middle mb-0">
            <thead>
              <tr>
                <th>Versi</th>
                <th>Kode</th>
                <th>Sifat</th>
                <th class="text-end">Ukuran</th>
                <th>Diunggah</th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($app_riwayat_db as $riwayat): ?>
                <tr>
                  <td class="small">
                    <a href="<?= htmlspecialchars((string)$riwayat['apk']) ?>" target="_blank">
                      <?= htmlspecialchars((string)$riwayat['version_name']) ?>
                    </a>
                  </td>
                  <td class="small"><?= (int)$riwayat['version_code'] ?></td>
                  <td class="small">
                    <?= ((int)$riwayat['wajib'] === 1)
                        ? '<span class="badge bg-danger">WAJIB</span>'
                        : '<span class="badge bg-light text-dark border">Pilihan</span>' ?>
                  </td>
                  <td class="text-end small">
                    <?= number_format((float)$riwayat['ukuran_mb'], 1, ',', '.') ?> MB
                  </td>
                  <td class="small">
                    <?= htmlspecialchars((string)$riwayat['dibuat_pada']) ?>
                    <?php if (!empty($riwayat['diunggah_oleh'])): ?>
                      <div class="text-muted"><?= htmlspecialchars((string)$riwayat['diunggah_oleh']) ?></div>
                    <?php endif; ?>
                  </td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <div class="col-lg-5">
    <div class="rts-card p-3">
      <h6 class="mb-3"><i class="fa-solid fa-circle-info text-danger me-2"></i>Versi yang Diumumkan</h6>

      <?php if (empty($app_versi)): ?>
        <div class="alert alert-warning mb-0 small">
          Belum ada versi yang diumumkan. Aplikasi belum akan menampilkan pemberitahuan
          pembaruan sebelum Anda mengunggah APK pada formulir di sebelah.
        </div>
      <?php else: ?>
        <div class="row g-2">
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Versi</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['version_name'] ?? '-')) ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Kode versi</div>
              <div class="nilai"><?= (int)($app_versi['version_code'] ?? 0) ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Sifat</div>
              <div class="nilai"><?= !empty($app_versi['wajib']) ? 'WAJIB' : 'Pilihan' ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Ukuran</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['ukuran_mb'] ?? '0')) ?> MB</div>
            </div>
          </div>
          <div class="col-12">
            <div class="rts-versi-kotak">
              <div class="label">Dipublikasikan</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['dipublikasikan'] ?? '-')) ?></div>
            </div>
          </div>
        </div>

        <div class="mt-3 small">
          <div class="text-muted mb-1">Tautan unduhan yang dibaca aplikasi:</div>
          <div class="rts-kode"><?= htmlspecialchars((string)($app_versi['apk'] ?? '-')) ?></div>
        </div>

        <?php if (!empty($app_versi['catatan'])): ?>
          <div class="mt-3 small">
            <div class="text-muted mb-1">Catatan pembaruan:</div>
            <div class="rts-versi-kotak"><?= nl2br(htmlspecialchars((string)$app_versi['catatan'])) ?></div>
          </div>
        <?php endif; ?>
      <?php endif; ?>
    </div>

    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3"><i class="fa-solid fa-satellite-dish text-danger me-2"></i>Berkas Keterangan Versi</h6>

      <div class="small mb-2">
        Aplikasi membaca berkas berikut setiap kali dibuka:
        <div class="rts-kode mt-1"><?= htmlspecialchars($app_alamat_json) ?></div>
      </div>

      <div class="d-flex gap-2 mb-3">
        <a class="btn btn-sm btn-outline-secondary" href="apk/app_versi.json" target="_blank">
          <i class="fa-solid fa-up-right-from-square me-1"></i>Buka berkas
        </a>
        <a class="btn btn-sm btn-outline-secondary" href="apk/app_versi.json?t=<?= time() ?>" target="_blank">
          <i class="fa-solid fa-rotate me-1"></i>Muat ulang
        </a>
      </div>

      <?php if ($app_json_siap): ?>
        <div class="rts-kode"><?= htmlspecialchars((string)@file_get_contents($app_berkas_json)) ?></div>
      <?php else: ?>
        <div class="text-muted small">Berkas belum ada.</div>
      <?php endif; ?>
    </div>

    <div class="rts-petunjuk mt-3">
      <strong><i class="fa-solid fa-lightbulb me-1"></i>Alur pembaruan aplikasi</strong>
      <ol class="mb-0 ps-3 mt-2">
        <li>Ubah <code>version:</code> di <code>pubspec.yaml</code>, contoh <code>1.2.0+3</code> (kode versi 3).</li>
        <li>Jalankan <code>flutter build apk --release</code>.</li>
        <li>Unggah <code>app-release.apk</code> pada formulir ini dengan kode versi yang sama (3).</li>
        <li>Aplikasi seluruh tim menampilkan pemberitahuan pembaruan pada pembukaan berikutnya.</li>
      </ol>
      <div class="mt-2 small">
        Catatan: Android selalu meminta persetujuan saat memasang aplikasi dari luar Play Store.
        Petugas cukup menekan tombol unduh, lalu memilih <strong>Pasang</strong> pada berkas yang terunduh.
      </div>
    </div>
  </div>
</div>

<?php require_once __DIR__ . '/footer.php'; ?>
