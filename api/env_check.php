<?php
/**
 * RTS Panel - Pemeriksaan Lingkungan (file sementara)
 *
 * Fungsi: menunjukkan database mana yang sedang dipakai oleh domain tempat
 * file ini di-upload. Berguna untuk memastikan domain staging dan produksi
 * memakai database yang berbeda.
 *
 * Cara pakai:
 *   1. Upload ke public_html/api/env_check.php pada tiap domain:
 *        - https://coba.benedic-s.com/api/env_check.php  (staging)
 *        - https://rts.benedic-s.com/api/env_check.php   (produksi)
 *   2. Buka alamatnya di browser, catat hasilnya.
 *   3. HAPUS file ini dari kedua domain setelah selesai.
 *
 * File ini hanya membaca. Tidak mengubah data apa pun.
 */

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');

require_once dirname(__DIR__) . '/config.php';

$kandidat = [];
foreach (['conn', 'mysqli', 'koneksi', 'db', 'link'] as $nama) {
    if (isset($$nama) && $$nama instanceof mysqli) {
        $kandidat[] = $$nama;
    }
}

if (!$kandidat || $kandidat[0]->connect_errno) {
    echo json_encode([
        'success' => false,
        'message' => 'Koneksi database tidak berhasil dibaca dari config.php',
    ]);
    exit;
}

$db = $kandidat[0];

/* ------------------------------------------------------------ nama database */

$namaDatabase = '';
$hasilNama = $db->query('SELECT DATABASE() AS db');
if ($hasilNama && ($barisNama = $hasilNama->fetch_assoc())) {
    $namaDatabase = (string) $barisNama['db'];
}

/* --------------------------------------------------------------- daftar tabel */

$tabelTarget = [
    'api_tokens',
    'master_toko',
    'master_toko_deleted',
    'sales_users',
    'pengajuan_sales',
    'pengajuan_gsp',
    'riwayat_aksi',
];

$tabelAda = [];
$hasilTabel = $db->query(
    'SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = DATABASE()'
);

if ($hasilTabel) {
    while ($baris = $hasilTabel->fetch_assoc()) {
        $tabelAda[(string) $baris['TABLE_NAME']] = true;
    }
}

$tabel = [];
foreach ($tabelTarget as $nama) {
    $tabel[$nama] = isset($tabelAda[$nama]);
}

/* --------------------------------------------------------------- daftar kolom */

$kolomTarget = [
    'sales_users' => ['username', 'status_aktif', 'salesman', 'sales_district'],
    'master_toko' => ['tipe_customer'],
    'pengajuan_sales' => ['processed_by', 'processed_at', 'approval_note'],
    'pengajuan_gsp' => ['jenis_request', 'processed_by', 'processed_at', 'approval_note'],
];

$kolomAda = [];
$hasilKolom = $db->query(
    'SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE()'
);

if ($hasilKolom) {
    while ($baris = $hasilKolom->fetch_assoc()) {
        $kolomAda[$baris['TABLE_NAME'] . '.' . $baris['COLUMN_NAME']] = true;
    }
}

$kolom = [];
foreach ($kolomTarget as $tabelNama => $daftarKolom) {
    foreach ($daftarKolom as $namaKolom) {
        $kolom[$tabelNama . '.' . $namaKolom] = isset($kolomAda[$tabelNama . '.' . $namaKolom]);
    }
}

/* -------------------------------------------------------------------- jumlah */

function rts_env_count(mysqli $db, string $tabel, string $syarat = ''): ?int
{
    $sql = 'SELECT COUNT(*) AS total FROM `' . $tabel . '`' . ($syarat !== '' ? ' WHERE ' . $syarat : '');
    $hasil = $db->query($sql);

    if (!$hasil) {
        return null;
    }

    $baris = $hasil->fetch_assoc();

    return $baris ? (int) $baris['total'] : null;
}

$jumlah = [];

if ($tabel['master_toko']) {
    $jumlah['customer'] = rts_env_count($db, 'master_toko');
    $jumlah['customer_gsp'] = isset($kolomAda['master_toko.tipe_customer'])
        ? rts_env_count($db, 'master_toko', "tipe_customer = 'GSP'")
        : null;
}

if ($tabel['sales_users']) {
    $jumlah['pengguna'] = rts_env_count($db, 'sales_users');
}

if ($tabel['pengajuan_sales']) {
    $jumlah['pengajuan_toko_pending'] = rts_env_count($db, 'pengajuan_sales', "status_approval = 'Pending'");
    $jumlah['pengajuan_toko_total'] = rts_env_count($db, 'pengajuan_sales');
}

if ($tabel['api_tokens']) {
    $jumlah['token_aktif'] = rts_env_count($db, 'api_tokens');
}

/* ------------------------------------------------- berkas API di folder ini */

$berkasTarget = [
    'login.php',
    'api_bootstrap.php',
    'customers.php',
    'customer_detail.php',
    'requests.php',
    'request_action.php',
    'request_apply.php',
    'request_create.php',
    'notifications.php',
    'session_check.php',
    'scope_check.php',
    'change_password.php',
];

$berkas = [];
foreach ($berkasTarget as $nama) {
    $berkas[$nama] = is_file(__DIR__ . '/' . $nama);
}


/* ---------------------------------------- berkas halaman website (folder induk) */

/* Pemeriksaan ini sengaja ditambahkan karena pengalaman sebelumnya: berkas yang
   disalin dari tampilan "Diff" (yang menyembunyikan baris tidak berubah dengan
   tulisan "N unmodified lines") menjadi tidak lengkap, sehingga halaman error
   HTTP 500. Angka di bawah menunjukkan jumlah baris yang benar. */

$berkasWebsiteTarget = [
    'inbox.php'          => ['baris' => 535, 'ukuran' => 42401],
    'pengajuan_toko.php' => ['baris' => 288, 'ukuran' => 14425],
    'header.php'         => ['baris' => 6,   'ukuran' => 2465],
    'sidebar.php'        => ['baris' => 5,   'ukuran' => 2191],
    'notifications.php'  => ['baris' => 21,  'ukuran' => 2106],
];

$berkasWebsite = [];
foreach ($berkasWebsiteTarget as $nama => $acuan) {
    $jalur = dirname(__DIR__) . '/' . $nama;

    if (!is_file($jalur)) {
        $berkasWebsite[$nama] = [
            'ada' => false,
            'catatan' => 'Berkas tidak ditemukan di public_html',
        ];
        continue;
    }

    $isi = (string) @file_get_contents($jalur);
    $baris = substr_count($isi, "\n") + 1;

    $berkasWebsite[$nama] = [
        'ada' => true,
        'baris' => $baris,
        'harusnya' => $acuan['baris'],
        'ukuran' => (int) @filesize($jalur),
        'ukuran_harusnya' => $acuan['ukuran'],
        'status' => ($baris === $acuan['baris']) ? 'COCOK' : 'PERIKSA (jumlah baris tidak sama)',
    ];
}

/* ------------------------------------------------------------------ balasan */


echo json_encode([
    'success' => true,
    'versi_env_check' => 4,
    'pesan' => 'Hapus file ini dari server setelah selesai diperiksa.',
    'domain' => (string) ($_SERVER['HTTP_HOST'] ?? ''),
    'database' => $namaDatabase,
    'php' => PHP_VERSION,
    'berkas_api' => $berkas,
    'berkas_website' => $berkasWebsite,
    'tabel' => $tabel,
    'kolom' => $kolom,
    'jumlah' => $jumlah,
    'catatan' => 'Berkas yang bernilai false pada berkas_api belum di-upload ke folder ini. Berkas di atas adalah berkas di dalam folder api (public_html/api).',
    'catatan_berkas_website' => 'Bagian ini memeriksa halaman website di public_html (satu folder di atas folder api). Bila status bukan COCOK, berkas di server TIDAK LENGKAP - biasanya karena disalin dari tampilan Diff yang menyembunyikan baris tidak berubah. Ganti dengan isi berkas yang lengkap.',
], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
