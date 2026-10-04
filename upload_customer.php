<?php
/**
 * ============================================================================
 * RTS PANEL BY BENE
 * HALAMAN : Upload Data Customer  (upload_customer.php)
 * PUTARAN : 18 - 4 Oktober 2026
 *
 * Perubahan pada putaran ini:
 *   1. Kotak centang "HAPUS SEMUA DATA CUSTOMER LAMA SEBELUM UPLOAD" kini
 *      tampil untuk ADMIN dan ASS. Bila TIDAK dicentang, data dengan
 *      id_customer yang sudah ada akan DITIMPA dengan data baru dari berkas
 *      yang diunggah; bila belum ada, data akan DITAMBAHKAN.
 *      Sebelum dihapus, SELURUH data lama disalin lebih dahulu ke tabel arsip
 *      master_toko_deleted, jadi masih dapat dikembalikan.
 *   2. Pembaca CSV diperbaiki: pemisah koma atau titik koma (dideteksi
 *      otomatis), urutan kolom bebas, nama kolom boleh memakai huruf besar /
 *      spasi / singkatan yang lazim, kolom tambahan diabaikan, angka desimal
 *      bergaya Indonesia (98,4522) ikut dibaca.
 *   3. Tersedia tombol: Download Template dari Database (10 contoh nyata),
 *      Download Template Kosong, dan Download SEMUA Data Customer (backup).
 *      Contoh isi CSV juga ditampilkan langsung di halaman (diambil dari
 *      database Bapak sendiri).
 *
 * Aman gagal: seluruh proses memakai transaksi dan prepared statement.
 * ============================================================================
 */

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();

if (!rts_is_approver()) {
    http_response_code(403);
    exit('Akses hanya untuk ADMIN atau ASS.');
}

/* --------------------------------------------------------------- pengaturan */

/** Nama kolom CSV yang wajib ada pada baris pertama berkas. */
function rts_uc_kolom_wajib(): array
{
    return [
        'id_customer', 'nama_toko', 'tipe_customer', 'salesman', 'alamat',
        'kunjungan', 'hari', 'sales_district', 'longitude', 'latitude', 'status_aktif',
    ];
}

/** Keterangan tiap kolom untuk tabel panduan di halaman. */
function rts_uc_keterangan_kolom(): array
{
    return [
        'id_customer'   => ['wajib' => 'Ya (tidak boleh kosong)', 'contoh' => '3000032344',
                            'ket' => 'Nomor/kode unik customer. Bila nomornya SUDAH ADA di database, datanya DITIMPA dengan isi berkas baru. Bila belum ada, ditambahkan.'],
        'nama_toko'     => ['wajib' => 'Ya', 'contoh' => 'YASIR',
                            'ket' => 'Nama toko/customer.'],
        'tipe_customer' => ['wajib' => 'Boleh kosong', 'contoh' => 'REGULER',
                            'ket' => 'Hanya REGULER atau GSP. Bila dikosongkan, otomatis REGULER.'],
        'salesman'      => ['wajib' => 'Ya', 'contoh' => 'DONNY NOEGROHO / SMST',
                            'ket' => 'Nama sales penanggung jawab (sama seperti pada menu Kelola Akun Tim).'],
        'alamat'        => ['wajib' => 'Ya', 'contoh' => 'JL. PROKLAMASI NO 11',
                            'ket' => 'Alamat toko. Bila alamat memuat koma, tulis di dalam tanda kutip: "JL. A, NO 5".'],
        'kunjungan'     => ['wajib' => 'Ya', 'contoh' => 'Bi-Weekly Ganjil',
                            'ket' => 'Frekuensi kunjungan, misalnya: Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap (samakan dengan yang dipakai aplikasi).'],
        'hari'          => ['wajib' => 'Ya', 'contoh' => 'Rabu',
                            'ket' => 'Hari kunjungan, misalnya: Senin ... Sabtu.'],
        'sales_district'=> ['wajib' => 'Ya', 'contoh' => 'STABAT',
                            'ket' => 'Nama district/sales. Sebaiknya sama dengan nama district yang ada di aplikasi.'],
        'longitude'     => ['wajib' => 'Ya', 'contoh' => '98.4522605',
                            'ket' => 'Titik peta (bujur). Bila angkanya memakai koma desimal gaya Indonesia, apit dengan tanda kutip: "98,4522605" (Excel melakukannya sendiri).'],
        'latitude'      => ['wajib' => 'Ya', 'contoh' => '3.7500542',
                            'ket' => 'Titik peta (lintang). Sama seperti longitude - koma desimal diapit tanda kutip.'],
        'status_aktif'  => ['wajib' => 'Boleh kosong', 'contoh' => 'Aktif',
                            'ket' => 'Aktif atau Nonaktif. Bila dikosongkan, otomatis Aktif.'],
    ];
}

/** Nama kolom lain yang tetap dimengerti (singkatan yang lazim dipakai). */
function rts_uc_alias_kolom(): array
{
    return [
        'toko'               => 'nama_toko',
        'nama'               => 'nama_toko',
        'nama_outlet'        => 'nama_toko',
        'outlet'             => 'nama_toko',
        'customer'           => 'nama_toko',
        'kode_customer'      => 'id_customer',
        'kode_toko'          => 'id_customer',
        'id_toko'            => 'id_customer',
        'customer_id'        => 'id_customer',
        'kode'               => 'id_customer',
        'tipe'               => 'tipe_customer',
        'jenis'              => 'tipe_customer',
        'jenis_customer'     => 'tipe_customer',
        'sales'              => 'salesman',
        'nama_sales'         => 'salesman',
        'nama_salesman'      => 'salesman',
        'alamat_toko'        => 'alamat',
        'alamat_lengkap'     => 'alamat',
        'address'            => 'alamat',
        'frekuensi'          => 'kunjungan',
        'frekuensi_kunjungan'=> 'kunjungan',
        'hari_kunjungan'     => 'hari',
        'day'                => 'hari',
        'district'           => 'sales_district',
        'distrik'            => 'sales_district',
        'wilayah'            => 'sales_district',
        'long'               => 'longitude',
        'bujur'              => 'longitude',
        'lng'                => 'longitude',
        'lat'                => 'latitude',
        'lintang'            => 'latitude',
        'status'             => 'status_aktif',
    ];
}

/* ------------------------------------------------------------ alat database */

function rts_uc_kolom_tabel($conn, string $tabel): array
{
    $kolom = [];

    if (!($conn instanceof mysqli) || preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1) {
        return $kolom;
    }

    $hasil = @$conn->query('SHOW COLUMNS FROM `' . $tabel . '`');

    if ($hasil instanceof mysqli_result) {
        while ($baris = $hasil->fetch_assoc()) {
            $nama = (string) ($baris['Field'] ?? '');

            if ($nama !== '') {
                $kolom[] = $nama;
            }
        }

        $hasil->free();
    }

    return $kolom;
}

function rts_uc_tabel_ada($conn, string $tabel): bool
{
    if (!($conn instanceof mysqli) || preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1) {
        return false;
    }

    $hasil = @$conn->query("SHOW TABLES LIKE '" . $conn->real_escape_string($tabel) . "'");

    return $hasil instanceof mysqli_result && $hasil->num_rows > 0;
}

/** Jumlah baris sebuah tabel (0 bila tabel tidak ada). */
function rts_uc_jumlah_baris($conn, string $tabel, string $syarat = ''): int
{
    if (!rts_uc_tabel_ada($conn, $tabel)) {
        return 0;
    }

    $sql = 'SELECT COUNT(*) AS n FROM `' . $tabel . '`';

    if ($syarat !== '') {
        $sql .= ' WHERE ' . $syarat;
    }

    $hasil = @$conn->query($sql);

    if (!($hasil instanceof mysqli_result)) {
        return 0;
    }

    $n = (int) ($hasil->fetch_assoc()['n'] ?? 0);
    $hasil->free();

    return $n;
}

/**
 * Menyalin SELURUH isi master_toko ke tabel arsip master_toko_deleted.
 * Dipakai sebelum "hapus semua data customer", supaya data lama masih dapat
 * dilihat/dikembalikan. Penyalinan dikerjakan oleh database sendiri
 * (INSERT ... SELECT), sehingga seluruh kolom yang sama ikut tersalin.
 *
 * @return int  jumlah baris yang disalin, atau -1 bila gagal/arsip tidak ada
 */
function rts_uc_arsipkan_semua($conn, string $alasan, string $oleh): int
{
    if (!rts_uc_tabel_ada($conn, 'master_toko_deleted')) {
        return -1;
    }

    $k_asal = rts_uc_kolom_tabel($conn, 'master_toko');
    $k_arsip = rts_uc_kolom_tabel($conn, 'master_toko_deleted');

    if (!$k_asal || !$k_arsip) {
        return -1;
    }

    $kolom = [];
    $nilai = [];

    foreach ($k_asal as $satu) {
        /* Kolom `id` dilewati: pada tabel arsip, id dibuat sendiri oleh
           database supaya tidak bertabrakan dengan arsip yang sudah ada. */
        if (strtolower($satu) === 'id') {
            continue;
        }

        if (in_array($satu, $k_arsip, true)) {
            $kolom[] = '`' . $satu . '`';
            $nilai[] = '`' . $satu . '`';
        }
    }

    /* Simpan juga id aslinya supaya mudah ditelusuri. */
    if (in_array('original_id', $k_arsip, true) && in_array('id', $k_asal, true)) {
        $kolom[] = '`original_id`';
        $nilai[] = '`id`';
    }

    if (!$kolom) {
        return -1;
    }

    $pakai_oleh = in_array('dihapus_oleh', $k_arsip, true);
    $pakai_alasan = in_array('alasan_penghapusan', $k_arsip, true);

    if ($pakai_alasan) {
        $kolom[] = '`alasan_penghapusan`';
        $nilai[] = '?';
    }

    if ($pakai_oleh) {
        $kolom[] = '`dihapus_oleh`';
        $nilai[] = '?';
    }

    $sql = 'INSERT INTO `master_toko_deleted` (' . implode(', ', $kolom) . ') '
        . 'SELECT ' . implode(', ', $nilai) . ' FROM `master_toko`';

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return -1;
    }

    if ($pakai_alasan && $pakai_oleh) {
        $stmt->bind_param('ss', $alasan, $oleh);
    } elseif ($pakai_alasan) {
        $stmt->bind_param('s', $alasan);
    } elseif ($pakai_oleh) {
        $stmt->bind_param('s', $oleh);
    }

    if (!$stmt->execute()) {
        return -1;
    }

    return (int) $conn->affected_rows;
}

/** Membuat tabel arsip master_toko_deleted bila belum ada. */
function rts_uc_siapkan_arsip($conn): array
{
    $laporan = [];

    if (!($conn instanceof mysqli)) {
        return ['Koneksi database tidak tersedia.'];
    }

    if (!rts_uc_tabel_ada($conn, 'master_toko_deleted')) {
        if (@$conn->query('CREATE TABLE IF NOT EXISTS `master_toko_deleted` LIKE `master_toko`')) {
            $laporan[] = 'Tabel master_toko_deleted dibuat.';
        } else {
            $laporan[] = 'Gagal membuat tabel arsip: ' . $conn->error;
            return $laporan;
        }
    } else {
        $laporan[] = 'Tabel master_toko_deleted sudah ada.';
    }

    $tambahan = [
        'original_id'        => "ADD COLUMN `original_id` INT NULL AFTER `id`",
        'alasan_penghapusan' => "ADD COLUMN `alasan_penghapusan` TEXT NULL",
        'dihapus_oleh'       => "ADD COLUMN `dihapus_oleh` VARCHAR(150) NULL",
        'dihapus_at'         => "ADD COLUMN `dihapus_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP",
    ];

    $ada = rts_uc_kolom_tabel($conn, 'master_toko_deleted');

    foreach ($tambahan as $kolom => $perintah) {
        if (in_array($kolom, $ada, true)) {
            continue;
        }

        if (@$conn->query('ALTER TABLE `master_toko_deleted` ' . $perintah)) {
            $laporan[] = 'Kolom ' . $kolom . ' ditambahkan.';
        } else {
            $laporan[] = 'Kolom ' . $kolom . ' gagal ditambahkan: ' . $conn->error;
        }
    }

    return $laporan;
}

/* ------------------------------------------------------------- alat CSV */

/** Merapikan nama kolom dari berkas CSV. */
function rts_uc_norm_kolom(string $nama): string
{
    $nama = preg_replace('/^\xEF\xBB\xBF/', '', $nama);
    $nama = strtolower(trim((string) $nama));
    $nama = str_replace(['"', "'", '(', ')'], '', $nama);
    $nama = preg_replace('/[\s\-.]+/', '_', $nama);
    $nama = preg_replace('/_+/', '_', $nama);

    return trim((string) $nama, '_');
}

/** Menebak pemisah kolom: koma, titik koma, tab, atau garis tegak. */
function rts_uc_tebak_pemisah(string $baris): string
{
    $kandidat = [',', ';', "\t", '|'];
    $kenal = array_merge(rts_uc_kolom_wajib(), array_keys(rts_uc_alias_kolom()));
    $terbaik = ',';
    $nilai_terbaik = -1;

    foreach ($kandidat as $satu) {
        $bagian = str_getcsv($baris, $satu);
        $cocok = 0;

        foreach ($bagian as $kolom) {
            if (in_array(rts_uc_norm_kolom((string) $kolom), $kenal, true)) {
                $cocok++;
            }
        }

        if ($cocok > $nilai_terbaik) {
            $nilai_terbaik = $cocok;
            $terbaik = $satu;
        }
    }

    return $terbaik;
}

/** Angka desimal gaya Indonesia (98,4522) -> 98.4522 */
function rts_uc_angka(string $nilai): string
{
    $nilai = trim($nilai);

    if ($nilai === '') {
        return '';
    }

    if (strpos($nilai, ',') !== false && strpos($nilai, '.') === false) {
        $nilai = str_replace(',', '.', $nilai);
    }

    return $nilai;
}

/** Status aktif: kosong = Aktif. */
function rts_uc_status(string $nilai): string
{
    $nilai = strtolower(trim($nilai));

    if ($nilai === '') {
        return 'Aktif';
    }

    if (strpos($nilai, 'non') !== false || $nilai === '0' || strpos($nilai, 'tidak') !== false) {
        return 'Nonaktif';
    }

    return 'Aktif';
}

/** ID customer: buang spasi dan ekor ".0" dari Excel. */
function rts_uc_id(string $nilai): string
{
    $nilai = trim($nilai);
    $nilai = preg_replace('/\.0+$/', '', $nilai);

    return trim((string) $nilai);
}

/* --------------------------------------------------------- unduh berkas CSV */

/** Menyusun daftar kolom SELECT yang selalu 11 kolom walau ada kolom hilang. */
function rts_uc_pilih_kolom($conn): string
{
    $ada = rts_uc_kolom_tabel($conn, 'master_toko');
    $pilih = [];

    foreach (rts_uc_kolom_wajib() as $kolom) {
        if (in_array($kolom, $ada, true)) {
            $pilih[] = '`' . $kolom . '`';
        } else {
            $pilih[] = "'' AS `" . $kolom . "`";
        }
    }

    return implode(', ', $pilih);
}

/**
 * Mengirim berkas CSV ke peramban.
 *
 * @param int  $batas  0 = seluruh data, >0 = ambil sekian baris pertama
 * @param bool $contoh true = berkas contoh (hanya keterangan di kepala)
 */
function rts_uc_kirim_csv($conn, string $nama_berkas, int $batas): void
{
    @set_time_limit(0);

    while (ob_get_level() > 0) {
        ob_end_clean();
    }

    $sql = 'SELECT ' . rts_uc_pilih_kolom($conn) . ' FROM `master_toko` ORDER BY `id`';

    if ($batas > 0) {
        $sql .= ' LIMIT ' . (int) $batas;
    }

    $hasil = @$conn->query($sql, MYSQLI_USE_RESULT);

    header('Content-Type: text/csv; charset=UTF-8');
    header('Content-Disposition: attachment; filename="' . str_replace('"', '', $nama_berkas) . '"');
    header('Cache-Control: no-store, no-cache, must-revalidate');
    header('Pragma: no-cache');

    /* BOM UTF-8 supaya Excel membaca huruf beraksen dengan benar. */
    echo "\xEF\xBB\xBF";

    $keluar = fopen('php://output', 'w');

    if (!$keluar) {
        exit;
    }

    /* Pemisah koma + kutip hanya bila perlu (aman untuk alamat yang memuat koma). */
    fputcsv($keluar, rts_uc_kolom_wajib(), ',', '"');

    if ($hasil instanceof mysqli_result) {
        while ($baris = $hasil->fetch_assoc()) {
            $isi = [];

            foreach (rts_uc_kolom_wajib() as $kolom) {
                $isi[] = (string) ($baris[$kolom] ?? '');
            }

            fputcsv($keluar, $isi, ',', '"');
        }

        $hasil->free();
    }

    fclose($keluar);
    exit;
}

/* ---------------------------------------------------------- siapkan halaman */

$conn = isset($conn) && $conn instanceof mysqli ? $conn : null;

if (!$conn) {
    http_response_code(500);
    exit('Koneksi database tidak tersedia. Periksa config.php.');
}

if (empty($_SESSION['uc_token'])) {
    $_SESSION['uc_token'] = bin2hex(random_bytes(16));
}

$uc_token = (string) $_SESSION['uc_token'];
$message = '';
$error = '';

/* Tombol unduh: template dari database, template kosong, dan backup. */
if (($_GET['unduh'] ?? '') !== '') {
    $jenis = (string) $_GET['unduh'];
    $jumlah = rts_uc_jumlah_baris($conn, 'master_toko');

    if ($jenis === 'template' && $jumlah > 0) {
        /* 10 contoh NYATA dari database - sekaligus jadi contoh bentuk CSV. */
        rts_uc_kirim_csv($conn, 'template_customer_dari_database.csv', 10);
    } elseif ($jenis === 'backup' && $jumlah > 0) {
        /* Seluruh data - untuk disimpan lebih dahulu sebelum data diganti. */
        rts_uc_kirim_csv($conn, 'backup_customer_' . date('Y-m-d_Hi') . '.csv', 0);
    }

    /* Template kosong / database masih kosong: satu baris contoh aman. */
    rts_uc_kirim_csv($conn, 'template_customer_kosong.csv', 1);
}

/* ---------------------------------------------------------------- POST */

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $aksi = (string) ($_POST['uc_aksi'] ?? 'unggah');
    $token_kirim = (string) ($_POST['uc_token'] ?? '');

    if ($token_kirim === '' || !hash_equals($uc_token, $token_kirim)) {
        $error = 'Halaman sudah kadaluarsa. Muat ulang halaman ini (Ctrl + F5) lalu coba lagi.';
    } elseif ($aksi === 'siapkan_arsip') {
        /* Membuat tabel arsip master_toko_deleted (aman dijalankan berulang). */
        $laporan = rts_uc_siapkan_arsip($conn);
        $message = 'Pemeriksaan tabel arsip selesai. ' . implode(' ', array_map('htmlspecialchars', $laporan));
    } elseif ($aksi === 'unggah') {
        @set_time_limit(0);

        $file = $_FILES['file_customer'] ?? null;
        $replace = !empty($_POST['replace_all']);
        $konfirmasi = strtoupper(trim((string) ($_POST['konfirmasi'] ?? '')));

        if (!$file || !isset($file['error'])) {
            $error = 'Berkas belum dipilih.';
        } elseif ($file['error'] === UPLOAD_ERR_INI_SIZE || $file['error'] === UPLOAD_ERR_FORM_SIZE) {
            $error = 'Ukuran berkas melebihi batas server. Maksimal 20 MB.';
        } elseif ($file['error'] !== UPLOAD_ERR_OK) {
            $error = 'Berkas gagal diunggah. Kode galat: ' . (int) $file['error'];
        } elseif ((int) $file['size'] > 20 * 1024 * 1024) {
            $error = 'Ukuran berkas maksimal 20 MB.';
        } elseif ($replace && $konfirmasi !== 'HAPUS') {
            $error = 'Kotak "Hapus semua data customer lama" dicentang, jadi Bapak harus '
                . 'mengetik kata HAPUS pada kotak konfirmasi. Penghapusan dibatalkan.';
        } elseif ($replace && !rts_uc_tabel_ada($conn, 'master_toko_deleted')) {
            $error = 'Tabel arsip `master_toko_deleted` belum ada, jadi penghapusan DIBATALKAN '
                . 'supaya data lama tidak hilang tanpa salinan. Tekan tombol '
                . '"BUAT / PERIKSA TABEL ARSIP" di halaman ini lebih dahulu.';
        } else {
            $handle = fopen($file['tmp_name'], 'rb');

            if (!$handle) {
                $error = 'Berkas CSV tidak dapat dibaca.';
            } else {
                $baris_kepala = fgets($handle);

                if ($baris_kepala === false || trim($baris_kepala) === '') {
                    $error = 'Berkas CSV kosong atau tidak ada baris nama kolom.';
                } else {
                    $pemisah = rts_uc_tebak_pemisah($baris_kepala);
                    $kolom_wajib = rts_uc_kolom_wajib();
                    $alias = rts_uc_alias_kolom();

                    $kepala = str_getcsv($baris_kepala, $pemisah);
                    $posisi = [];
                    $tambahan = [];
                    $kembar = [];

                    foreach ($kepala as $urutan => $nama_kolom) {
                        $bersih = rts_uc_norm_kolom((string) $nama_kolom);
                        $kunci = $alias[$bersih] ?? $bersih;

                        if (!in_array($kunci, $kolom_wajib, true)) {
                            if ($bersih !== '') {
                                $tambahan[] = $bersih;
                            }
                            continue;
                        }

                        if (isset($posisi[$kunci])) {
                            $kembar[] = $kunci;
                            continue;
                        }

                        $posisi[$kunci] = (int) $urutan;
                    }

                    $kurang = array_values(array_diff($kolom_wajib, array_keys($posisi)));

                    if ($kembar) {
                        $error = 'Nama kolom berikut muncul lebih dari sekali pada baris pertama: '
                            . htmlspecialchars(implode(', ', array_unique($kembar))) . '.';
                    } elseif ($kurang) {
                        $error = 'Kolom berikut belum ada pada baris pertama berkas: '
                            . htmlspecialchars(implode(', ', $kurang))
                            . '. Yang diminta: ' . htmlspecialchars(implode(', ', $kolom_wajib))
                            . '. Pemisah kolom yang terbaca: '
                            . ($pemisah === "\t" ? 'TAB' : $pemisah) . '.';
                    } else {
                        try {
                            $conn->begin_transaction();

                            /* 1. Bila dicentang: salin dulu ke arsip, baru hapus. */
                            $jumlah_lama = 0;
                            $jumlah_arsip = 0;

                            if ($replace) {
                                $jumlah_lama = rts_uc_jumlah_baris($conn, 'master_toko');
                                $jumlah_arsip = rts_uc_arsipkan_semua(
                                    $conn,
                                    'HAPUS SEMUA SEBELUM UPLOAD CSV ' . date('d-m-Y H:i'),
                                    (string) ($_SESSION['username'] ?? $_SESSION['email'] ?? '')
                                );

                                if ($jumlah_arsip < 0) {
                                    throw new RuntimeException(
                                        'Data lama gagal disalin ke tabel arsip, jadi penghapusan dibatalkan.'
                                    );
                                }

                                if (!$conn->query('DELETE FROM master_toko')) {
                                    throw new RuntimeException('Data customer lama gagal dihapus: ' . $conn->error);
                                }
                            }

                            /* 2. Data yang sudah ada dibaca sekali saja. */
                            $sudah_ada = [];
                            $hasil = $conn->query('SELECT id_customer FROM master_toko');

                            if (!$hasil) {
                                throw new RuntimeException('Gagal membaca data customer: ' . $conn->error);
                            }

                            while ($item = $hasil->fetch_assoc()) {
                                $sudah_ada[(string) $item['id_customer']] = true;
                            }

                            $hasil->free();

                            $insert = $conn->prepare(
                                'INSERT INTO master_toko
                                (id_customer, nama_toko, tipe_customer, salesman, alamat, kunjungan, hari,
                                 sales_district, longitude, latitude, status_aktif)
                                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
                            );
                            $update = $conn->prepare(
                                'UPDATE master_toko SET nama_toko=?, tipe_customer=?, salesman=?, alamat=?,
                                 kunjungan=?, hari=?, sales_district=?, longitude=?, latitude=?, status_aktif=?
                                 WHERE id_customer=?'
                            );

                            if (!$insert || !$update) {
                                throw new RuntimeException('Statement database gagal dibuat: ' . $conn->error);
                            }

                            $baru = 0;
                            $ditimpa = 0;
                            $dilewati = 0;
                            $baris_csv = 1;
                            $contoh_ditimpa = [];
                            $contoh_baru = [];

                            /* Buang baris nama kolom, ulangi dari awal berkas. */
                            rewind($handle);
                            fgets($handle);

                            while (($row = fgetcsv($handle, 0, $pemisah)) !== false) {
                                $baris_csv++;

                                if (count($row) === 1 && trim((string) $row[0]) === '') {
                                    continue;
                                }

                                if (count($row) !== count($kepala)) {
                                    $lebih = count($row) > count($kepala);

                                    throw new RuntimeException(
                                        'Baris CSV ke-' . $baris_csv . ' jumlah kolomnya '
                                        . ($lebih ? 'KELEBIHAN' : 'KURANG') . ': ada ' . count($row)
                                        . ' kolom, seharusnya ' . count($kepala) . '. '
                                        . ($lebih
                                            ? 'Biasanya karena ada tanda koma di dalam isi kolom - '
                                              . 'umpamanya angka desimal 98,4522 yang ditulis tanpa tanda '
                                              . 'kutip, atau ada tanda koma berlebih di akhir baris. '
                                              . 'Tulis angka seperti itu di dalam tanda kutip: "98,4522" '
                                              . '(Excel melakukannya sendiri bila berkas disimpan dari Excel).'
                                            : 'Periksa apakah ada kolom yang belum diisi pada baris itu, '
                                              . 'atau tanda koma/kutipnya kurang.')
                                    );
                                }

                                $ambil = [];

                                foreach ($kolom_wajib as $kolom) {
                                    $isi = $row[$posisi[$kolom]] ?? '';
                                    $ambil[$kolom] = trim((string) $isi);
                                }

                                if (implode('', $ambil) === '') {
                                    continue;
                                }

                                $id = rts_uc_id($ambil['id_customer']);

                                if ($id === '') {
                                    $dilewati++;
                                    continue;
                                }

                                $tipe = strtoupper($ambil['tipe_customer']);

                                if ($tipe === '') {
                                    $tipe = 'REGULER';
                                }

                                if (!in_array($tipe, ['REGULER', 'GSP'], true)) {
                                    throw new RuntimeException(
                                        'tipe_customer hanya boleh REGULER atau GSP. Salah pada baris CSV '
                                        . $baris_csv . ' (ID ' . $id . '): ' . $tipe
                                    );
                                }

                                $nama = $ambil['nama_toko'];
                                $salesman = $ambil['salesman'];
                                $alamat = $ambil['alamat'];
                                $kunjungan = $ambil['kunjungan'];
                                $hari = $ambil['hari'];
                                $district = $ambil['sales_district'];
                                $longitude = rts_uc_angka($ambil['longitude']);
                                $latitude = rts_uc_angka($ambil['latitude']);
                                $status = rts_uc_status($ambil['status_aktif']);

                                if (isset($sudah_ada[$id])) {
                                    $update->bind_param('sssssssssss', $nama, $tipe, $salesman, $alamat,
                                        $kunjungan, $hari, $district, $longitude, $latitude, $status, $id);
                                    $ok = $update->execute();

                                    if ($ok) {
                                        $ditimpa++;

                                        if (count($contoh_ditimpa) < 5) {
                                            $contoh_ditimpa[] = $id;
                                        }
                                    }
                                } else {
                                    $insert->bind_param('sssssssssss', $id, $nama, $tipe, $salesman, $alamat,
                                        $kunjungan, $hari, $district, $longitude, $latitude, $status);
                                    $ok = $insert->execute();

                                    if ($ok) {
                                        $sudah_ada[$id] = true;
                                        $baru++;

                                        if (count($contoh_baru) < 5) {
                                            $contoh_baru[] = $id;
                                        }
                                    }
                                }

                                if (!$ok) {
                                    throw new RuntimeException(
                                        'Gagal menyimpan baris CSV ke-' . $baris_csv . ', ID ' . $id
                                        . ': ' . $conn->error
                                    );
                                }
                            }

                            if (($baru + $ditimpa) === 0) {
                                throw new RuntimeException(
                                    'Tidak ada satu pun data yang sah di dalam berkas, jadi '
                                    . 'tidak ada yang disimpan' . ($replace ? ' dan data lama TIDAK dihapus.' : '.')
                                );
                            }

                            $conn->commit();

                            $message = 'Selesai. ' . $baru . ' data BARU ditambahkan, '
                                . $ditimpa . ' data lama DITIMPA dengan isi berkas baru'
                                . ($dilewati ? ', ' . $dilewati . ' baris tanpa id_customer dilewati' : '')
                                . ($replace ? '. ' . $jumlah_arsip . ' dari ' . $jumlah_lama
                                    . ' data lama disalin ke arsip master_toko_deleted lalu dihapus.' : '.');

                            if ($contoh_ditimpa) {
                                $message .= ' Contoh ID yang ditimpa: '
                                    . htmlspecialchars(implode(', ', $contoh_ditimpa))
                                    . ($ditimpa > count($contoh_ditimpa) ? ' (dan lainnya)' : '') . '.';
                            }

                            if ($contoh_baru) {
                                $message .= ' Contoh ID baru: '
                                    . htmlspecialchars(implode(', ', $contoh_baru))
                                    . ($baru > count($contoh_baru) ? ' (dan lainnya)' : '') . '.';
                            }

                            if ($tambahan) {
                                $message .= ' Kolom tambahan yang diabaikan: '
                                    . htmlspecialchars(implode(', ', array_unique($tambahan))) . '.';
                            }

                            /* -----------------------------------------------------
                             * PEMBERITAHUAN OTOMATIS: DATA CUSTOMER DIPERBARUI
                             * Aman gagal - bila tabel pemberitahuan atau Firebase
                             * belum ada, bagian ini berhenti dengan tenang.
                             * -------------------------------------------------- */
                            if (is_file(__DIR__ . '/api/notif_otomatis.php')) {
                                require_once __DIR__ . '/api/notif_otomatis.php';

                                if (function_exists('rts_notif_aktivitas') && isset($conn) && $conn instanceof mysqli) {
                                    try {
                                        $judulNotif = 'Data Customer Diperbarui';
                                        $pesanNotif = (string) ($baru + $ditimpa) . ' data customer baru saja '
                                            . 'diperbarui oleh '
                                            . (string) ($_SESSION['username'] ?? 'ADMIN')
                                            . ' pada ' . date('d-m-Y H:i') . '. '
                                            . 'Buka menu Sinkronisasi untuk mengambil data terbaru.';

                                        rts_notif_aktivitas(
                                            $conn,
                                            $judulNotif,
                                            $pesanNotif,
                                            'AKTIVITAS',
                                            ['halaman' => 'master_customer'],
                                            (string) ($_SESSION['email'] ?? '')
                                        );
                                    } catch (Throwable $galatNotif) {
                                        error_log('RTS notif customer: ' . $galatNotif->getMessage());
                                    }
                                }
                            }
                        } catch (Throwable $exception) {
                            $conn->rollback();
                            $error = 'Upload dibatalkan: ' . $exception->getMessage();
                        }
                    }
                }

                fclose($handle);
            }
        }
    }
}

/* ------------------------------------------------------------ data halaman */

$uc_ada_arsip = rts_uc_tabel_ada($conn, 'master_toko_deleted');
$uc_jumlah = rts_uc_jumlah_baris($conn, 'master_toko');
$uc_jumlah_reguler = rts_uc_jumlah_baris($conn, 'master_toko', "tipe_customer = 'REGULER'");
$uc_jumlah_gsp = rts_uc_jumlah_baris($conn, 'master_toko', "tipe_customer = 'GSP'");
$uc_jumlah_arsip = $uc_ada_arsip ? rts_uc_jumlah_baris($conn, 'master_toko_deleted') : 0;

/* Beberapa contoh NYATA dari database untuk ditampilkan di halaman. */
$uc_contoh = [];

$hasil_contoh = @$conn->query('SELECT ' . rts_uc_pilih_kolom($conn)
    . ' FROM `master_toko` ORDER BY `id` DESC LIMIT 3');

if ($hasil_contoh instanceof mysqli_result) {
    while ($baris_contoh = $hasil_contoh->fetch_assoc()) {
        $uc_contoh[] = $baris_contoh;
    }

    $hasil_contoh->free();
}

$uc_keterangan = rts_uc_keterangan_kolom();

require_once __DIR__ . '/header.php';
?>
<div class="card border-0 shadow-sm mb-3" style="max-width:1100px">
    <div class="card-body p-4">
        <h3 class="mb-1">Upload Data Customer</h3>
        <p class="text-muted mb-3">
            Halaman ini untuk <b>ADMIN</b> dan <b>ASS</b>. Berkas yang diunggah ber-ekstensi
            <b>.csv</b> (teks biasa) berisi data customer.
            Berkas dibaca dengan pemisah <b>koma (,)</b> maupun <b>titik koma (;)</b>.
        </p>

        <div class="d-flex flex-wrap gap-2">
            <span class="badge text-bg-secondary">Jumlah customer sekarang: <?= (int) $uc_jumlah ?></span>
            <span class="badge text-bg-primary">REGULER: <?= (int) $uc_jumlah_reguler ?></span>
            <span class="badge text-bg-info">GSP: <?= (int) $uc_jumlah_gsp ?></span>
            <span class="badge text-bg-light text-muted">Arsip terhapus: <?= (int) $uc_jumlah_arsip ?></span>
        </div>

        <?php if ($message): ?>
            <div class="alert alert-success mt-3 mb-0"><?= $message ?></div>
        <?php endif; ?>
        <?php if ($error): ?>
            <div class="alert alert-danger mt-3 mb-0"><?= htmlspecialchars($error) ?></div>
        <?php endif; ?>
    </div>
</div>

<div class="card border-0 shadow-sm mb-3" style="max-width:1100px">
    <div class="card-header bg-white"><strong>1. Bentuk berkas CSV yang diterima</strong></div>
    <div class="card-body p-4">
        <ol class="mb-3">
            <li>Baris <b>pertama</b> harus berisi <b>nama kolom</b> (judul). Baris berikutnya berisi data.</li>
            <li>Pemisah kolom boleh <b>koma (,)</b> atau <b>titik koma (;)</b> - terbaca otomatis.</li>
            <li>Urutan kolom <b>bebas</b>. Nama kolom boleh memakai huruf besar/kecil, spasi, atau
                singkatan yang lazim (contoh: <code>NAMA TOKO</code>, <code>Toko</code>,
                <code>district</code>, <code>status</code>).</li>
            <li>Kolom tambahan (misalnya <code>id</code>, <code>created_at</code>, <code>no</code>)
                <b>diabaikan</b> - tidak perlu dihapus, tetapi tidak ikut tersimpan.</li>
            <li>Simpan dari Excel dengan pilihan <b>CSV UTF-8 (Comma delimited)</b> supaya huruf
                beraksen dan tanda baca tidak rusak. Berkas bergaya UTF-8 dengan BOM juga diterima.</li>
            <li>Ukuran berkas maksimal <b>20 MB</b>. Baris kosong dilewati.</li>
            <li>Bila sebuah alamat memuat koma, tulis di dalam tanda kutip:
                <code>"JL. SUDIRMAN, NO 10"</code>.</li>
            <li>Angka desimal boleh memakai koma gaya Indonesia (<code>"98,4522605"</code>) -
                otomatis diperbaiki menjadi titik. PENTING: tanda koma di dalam isi kolom
                <b>wajib diapit tanda kutip</b>, karena koma adalah pemisah kolom. Excel
                mengapitnya sendiri bila berkas disimpan dari Excel.</li>
            <li>Jumlah kolom pada setiap baris <b>harus sama</b> dengan baris nama kolom.
                Bila berbeda, halaman menampilkan galat yang menyebutkan barisnya -
                jadi tidak ada data yang salah tempat.</li>
            <li>Bila <b>id_customer sudah ada</b> di database, datanya <b>DITIMPA</b> dengan isi berkas
                baru. Bila belum ada, datanya <b>DITAMBAHKAN</b>.</li>
        </ol>

        <div class="table-responsive">
            <table class="table table-sm table-bordered align-middle">
                <thead class="table-light">
                    <tr>
                        <th style="width:150px">Nama kolom</th>
                        <th style="width:150px">Isi</th>
                        <th style="width:180px">Contoh</th>
                        <th>Keterangan</th>
                    </tr>
                </thead>
                <tbody>
                <?php foreach (rts_uc_kolom_wajib() as $uc_kolom): ?>
                    <?php $uc_ket = $uc_keterangan[$uc_kolom] ?? ['wajib' => '', 'contoh' => '', 'ket' => '']; ?>
                    <tr>
                        <td><code><?= htmlspecialchars($uc_kolom) ?></code></td>
                        <td><?= htmlspecialchars($uc_ket['wajib']) ?></td>
                        <td><code><?= htmlspecialchars($uc_ket['contoh']) ?></code></td>
                        <td class="small"><?= htmlspecialchars($uc_ket['ket']) ?></td>
                    </tr>
                <?php endforeach; ?>
                </tbody>
            </table>
        </div>

        <div class="alert alert-secondary small mb-0">
            <b>Cara cepat membuat berkas dari Excel:</b>
            <ol class="mb-0 mt-1">
                <li>Tekan <b>Download Template dari Database</b> di bawah, buka berkasnya dengan Excel.</li>
                <li>Ganti isinya dengan data Bapak, tetapi <b>jangan mengubah baris pertama (nama kolom)</b>.</li>
                <li>Simpan sebagai <b>CSV UTF-8 (Comma delimited) (*.csv)</b>, lalu unggah pada bagian nomor 2.</li>
            </ol>
        </div>
    </div>
</div>

<div class="card border-0 shadow-sm mb-3" style="max-width:1100px">
    <div class="card-header bg-white"><strong>Contoh isi CSV - diambil langsung dari database Bapak</strong></div>
    <div class="card-body p-4">
        <?php if ($uc_contoh): ?>
            <p class="text-muted small">
                Tiga baris terakhir yang ada di <code>master_toko</code>. Baris pertama tabel ini
                (yang dicetak tebal) adalah baris <b>nama kolom</b> yang wajib ada di berkas CSV.
            </p>
            <div class="table-responsive">
                <table class="table table-sm table-bordered table-striped align-middle small">
                    <thead class="table-dark">
                        <tr>
                            <?php foreach (rts_uc_kolom_wajib() as $uc_kolom): ?>
                                <th class="text-nowrap"><?= htmlspecialchars($uc_kolom) ?></th>
                            <?php endforeach; ?>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($uc_contoh as $uc_baris): ?>
                            <tr>
                                <?php foreach (rts_uc_kolom_wajib() as $uc_kolom): ?>
                                    <td class="text-nowrap"><?= htmlspecialchars((string) ($uc_baris[$uc_kolom] ?? '')) ?></td>
                                <?php endforeach; ?>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
            <p class="text-muted small mb-0">
                Bentuk aslinya di dalam berkas CSV (satu baris = satu customer):
            </p>
            <pre class="bg-light border rounded p-2 small mb-0" style="overflow-x:auto"><?php
                foreach ($uc_contoh as $uc_baris) {
                    $uc_isi = [];

                    foreach (rts_uc_kolom_wajib() as $uc_kolom) {
                        $uc_isi[] = (string) ($uc_baris[$uc_kolom] ?? '');
                    }

                    echo htmlspecialchars(implode(',', $uc_isi)) . "\n";
                }
            ?></pre>
        <?php else: ?>
            <div class="alert alert-warning mb-0">
                Belum ada data customer di database, jadi belum ada contoh yang dapat ditampilkan.
                Silakan unduh <b>Template Kosong</b> di bawah untuk melihat bentuk berkasnya.
            </div>
        <?php endif; ?>

        <hr>
        <div class="d-flex flex-wrap gap-2">
            <a class="btn btn-outline-success"
               href="?unduh=template">
                <i class="fa-solid fa-file-csv"></i> Download Template dari Database (10 contoh)
            </a>
            <a class="btn btn-outline-secondary"
               href="?unduh=template_kosong">
                Template Kosong (1 contoh kosong)
            </a>
            <a class="btn btn-outline-primary"
               href="?unduh=backup">
                <i class="fa-solid fa-download"></i> Download SEMUA Data Customer (backup)
            </a>
        </div>
        <div class="form-text mt-2">
            Tombol <b>Download SEMUA Data</b> gunanya untuk menyimpan data lama lebih dahulu
            (misalnya sebelum mencentang kotak hapus di bawah). Berkas hasilnya berbentuk sama,
            jadi dapat langsung diunggah kembali.<br>
            Berkas bawaan (tanpa perlu database):
            <a href="template_customer.csv" download>template_customer.csv</a> -
            berisi 1 baris contoh. Ganti isinya dengan data Bapak sebelum diunggah.
        </div>
    </div>
</div>

<div class="card border-0 shadow-sm" style="max-width:1100px">
    <div class="card-header bg-white"><strong>2. Unggah berkas</strong></div>
    <div class="card-body p-4">
        <?php if (!$uc_ada_arsip): ?>
            <div class="alert alert-warning">
                <b>Tabel arsip <code>master_toko_deleted</code> belum ada.</b>
                Tanpa tabel itu, tombol hapus semua data tidak dapat dipakai (supaya data lama
                tidak hilang tanpa salinan). Tekan tombol di bawah untuk membuatnya -
                aman ditekan berulang kali.
                <form method="post" class="mt-2">
                    <input type="hidden" name="uc_aksi" value="siapkan_arsip">
                    <input type="hidden" name="uc_token" value="<?= htmlspecialchars($uc_token) ?>">
                    <button class="btn btn-sm btn-warning">
                        <i class="fa-solid fa-screwdriver-wrench"></i> BUAT / PERIKSA TABEL ARSIP
                    </button>
                </form>
            </div>
        <?php endif; ?>

        <form method="post" enctype="multipart/form-data" id="ucForm">
            <input type="hidden" name="uc_aksi" value="unggah">
            <input type="hidden" name="uc_token" value="<?= htmlspecialchars($uc_token) ?>">

            <label class="form-label fw-bold">Berkas CSV</label>
            <input type="file" name="file_customer" class="form-control mb-3"
                   accept=".csv,text/csv" required>

            <div class="form-check border border-danger rounded p-3 mb-3">
                <input class="form-check-input" type="checkbox" name="replace_all"
                       value="1" id="replaceAll" onchange="ucGantiHapus()">
                <label class="form-check-label text-danger fw-bold" for="replaceAll">
                    HAPUS SEMUA DATA CUSTOMER LAMA SEBELUM UPLOAD
                </label>
                <div class="small text-muted">
                    Bila <b>tidak dicentang</b>: data dengan id_customer yang sudah ada akan
                    <b>DITIMPA</b> dengan data baru, dan yang belum ada akan <b>DITAMBAHKAN</b>.
                    Data lain yang tidak ada di berkas tetap aman.<br>
                    Bila <b>dicentang</b>: <?= (int) $uc_jumlah ?> data lama disalin lebih dahulu
                    <?= $uc_ada_arsip ? 'ke tabel arsip <code>master_toko_deleted</code>' : '(TABEL ARSIP BELUM ADA - tombol hapus belum dapat dipakai)' ?>,
                    lalu seluruh tabel dikosongkan, baru data dari berkas dimasukkan.
                </div>
            </div>

            <div class="alert alert-danger d-none" id="ucKonfirmasiBox">
                <label class="form-label fw-bold">Ketik kata <code>HAPUS</code> untuk menegaskan</label>
                <input type="text" name="konfirmasi" id="konfirmasi" class="form-control"
                       style="max-width:220px" autocomplete="off" placeholder="HAPUS">
                <div class="small mt-1">
                    Langkah ini mencegah data customer terhapus karena kekeliruan.
                </div>
            </div>

            <button class="btn btn-primary">
                <i class="fa-solid fa-upload"></i> Upload dan Update Data
            </button>
        </form>

        <hr>
        <small class="text-muted">
            Proses memakai transaksi: bila ada satu baris yang bermasalah, seluruh unggahan
            dibatalkan dan data lama tetap utuh (termasuk saat kotak hapus dicentang).
        </small>
    </div>
</div>

<script>
function ucGantiHapus() {
    var kotak = document.getElementById('replaceAll');
    var box = document.getElementById('ucKonfirmasiBox');
    var isian = document.getElementById('konfirmasi');

    if (!kotak || !box || !isian) return;

    if (kotak.checked) {
        box.classList.remove('d-none');
        isian.setAttribute('required', 'required');
    } else {
        box.classList.add('d-none');
        isian.removeAttribute('required');
        isian.value = '';
    }
}

(function () {
    var bentuk = document.getElementById('ucForm');

    if (bentuk) {
        bentuk.addEventListener('submit', function (kejadian) {
            var kotak = document.getElementById('replaceAll');
            var isian = document.getElementById('konfirmasi');

            if (kotak && kotak.checked) {
                if (!isian || isian.value.trim().toUpperCase() !== 'HAPUS') {
                    kejadian.preventDefault();
                    alert('Ketik HAPUS pada kotak konfirmasi lebih dahulu.');
                    return;
                }

                if (!confirm('SEMUA data customer lama akan disalin ke arsip lalu DIHAPUS, '
                        + 'lalu diganti dengan isi berkas. Lanjutkan?')) {
                    kejadian.preventDefault();
                }
            }
        });
    }

    ucGantiHapus();
})();
</script>

<?php require_once __DIR__ . '/footer.php'; ?>
