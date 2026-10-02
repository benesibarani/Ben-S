<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API LOKASI KANTOR / MITRA
 *  Berkas : api/kantor.php
 *  Versi  : 1   (3 Oktober 2026)
 *
 *  Dipanggil aplikasi Android dengan token login (Authorization: Bearer ...).
 *
 *  Tabel database yang dipakai: `rts_kantor`
 *  (dibuat oleh berkas database/migrations/RTS_PANEL_KANTOR.sql, atau otomatis
 *   oleh berkas ini bila belum ada)
 *
 *  KEGUNAAN
 *  --------
 *  Titik lokasi kantor / mitra dipakai menu RUTE PLAN pada aplikasi sebagai
 *  AWAL perhitungan urutan kunjungan (toko nomor 1 = toko terdekat dari
 *  kantor). ADMIN menitikkan kantor lewat aplikasi (menu Rute Plan -> tombol
 *  gedung -> TAMBAH KANTOR -> AMBIL TITIK DARI LOKASI SAYA).
 *
 *  Titik dari server disalin ke dalam HP sales, sehingga urutan rute tetap
 *  dapat dihitung walaupun HP sedang tidak ada internet.
 *
 *  DAFTAR PERINTAH (parameter "aksi")
 *  ---------------------------------
 *    daftar   seluruh titik kantor (semua user yang sudah login boleh baca)
 *    simpan   menambah / mengubah satu titik kantor  (ADMIN & ASS)
 *    hapus    menghapus satu titik kantor            (ADMIN & ASS)
 *    hitung   jumlah titik kantor (pemeriksaan cepat)
 *
 *  CATATAN ATURAN
 *  --------------
 *    - Membaca daftar boleh semua user (sales perlu titik kantor untuk rute).
 *    - Mengubah / menghapus hanya ADMIN dan ASS.
 *    - Aman dijalankan berkali-kali; tidak ada perintah yang menghapus tabel.
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (!in_array($metode, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$masukan = rts_api_input();
$aksi = strtolower(rts_api_param('aksi', 'daftar'));

$role = strtoupper((string) ($user['role'] ?? ''));
$namaUser = trim((string) ($user['nama_lengkap'] ?? ''));

if ($namaUser === '') {
    $namaUser = (string) ($user['username'] ?? 'USER');
}

$pengelola = in_array($role, ['ADMIN', 'ASS'], true);

/* ------------------------------------------------------------------ tabel */

/**
 * Perintah pembuatan tabel rts_kantor (sama persis dengan berkas SQL migrasi).
 * Dipakai untuk memastikan tabel ada, sehingga API tetap jalan walaupun
 * berkas SQL belum sempat dijalankan di phpMyAdmin.
 */
function rts_kt_sql_tabel(): string
{
    return 'CREATE TABLE IF NOT EXISTS `rts_kantor` (
      `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `nama`        VARCHAR(120) NOT NULL,
      `alamat`      VARCHAR(255) NOT NULL DEFAULT \'\',
      `district`    VARCHAR(120) NOT NULL DEFAULT \'\',
      `latitude`    DECIMAL(11,7) NOT NULL DEFAULT 0,
      `longitude`   DECIMAL(11,7) NOT NULL DEFAULT 0,
      `catatan`     VARCHAR(255) NOT NULL DEFAULT \'\',
      `dibuat_oleh` VARCHAR(100) NOT NULL DEFAULT \'\',
      `dibuat_pada` DATETIME NULL DEFAULT NULL,
      `diubah_oleh` VARCHAR(100) NOT NULL DEFAULT \'\',
      `diubah_pada` DATETIME NULL DEFAULT NULL,
      PRIMARY KEY (`id`),
      KEY `idx_nama` (`nama`),
      KEY `idx_district` (`district`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci';
}

function rts_kt_ada_tabel(mysqli $conn): bool
{
    $hasil = $conn->query("SHOW TABLES LIKE 'rts_kantor'");

    if ($hasil instanceof mysqli_result) {
        $ada = $hasil->num_rows > 0;
        $hasil->free();

        return $ada;
    }

    return false;
}

/** Membuat tabel bila belum ada. Mengembalikan pesan kesalahan bila gagal. */
function rts_kt_pastikan_tabel(mysqli $conn): string
{
    if (rts_kt_ada_tabel($conn)) {
        return '';
    }

    if ($conn->query(rts_kt_sql_tabel())) {
        return '';
    }

    return 'Tabel rts_kantor belum ada dan tidak dapat dibuat otomatis. '
        . 'Jalankan berkas RTS_PANEL_KANTOR.sql lewat phpMyAdmin. '
        . 'Keterangan server: ' . $conn->error;
}

/* ---------------------------------------------------------------- bantuan */

function rts_kt_teks($nilai, int $maks = 150): string
{
    $teks = trim((string) $nilai);
    $teks = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/u', '', $teks);
    $teks = is_string($teks) ? $teks : '';

    if (function_exists('mb_substr')) {
        return mb_substr($teks, 0, $maks, 'UTF-8');
    }

    return substr($teks, 0, $maks);
}

function rts_kt_angka($nilai): float
{
    if (is_string($nilai)) {
        $nilai = str_replace([' ', "\xc2\xa0"], '', $nilai);
        $nilai = str_replace(',', '.', $nilai);
    }

    return (float) $nilai;
}

/** Menyusun satu baris titik kantor menjadi bentuk yang dipakai aplikasi. */
function rts_kt_bentuk(array $b): array
{
    return [
        'id' => (int) ($b['id'] ?? 0),
        'nama' => (string) ($b['nama'] ?? ''),
        'alamat' => (string) ($b['alamat'] ?? ''),
        'district' => (string) ($b['district'] ?? ''),
        'latitude' => (float) ($b['latitude'] ?? 0),
        'longitude' => (float) ($b['longitude'] ?? 0),
        'catatan' => (string) ($b['catatan'] ?? ''),
        'diubah_oleh' => (string) ($b['diubah_oleh'] ?? ''),
        'diubah_pada' => (string) ($b['diubah_pada'] ?? ''),
    ];
}

/** Membaca seluruh titik kantor (urut nama). */
function rts_kt_daftar(mysqli $conn): array
{
    $items = [];

    $hasil = $conn->query(
        'SELECT id, nama, alamat, district, latitude, longitude, catatan, '
        . 'diubah_oleh, diubah_pada FROM `rts_kantor` ORDER BY nama ASC'
    );

    if ($hasil instanceof mysqli_result) {
        while ($baris = $hasil->fetch_assoc()) {
            $items[] = rts_kt_bentuk($baris);
        }

        $hasil->free();
    }

    return $items;
}

/* ------------------------------------------------------- pemastian tabel */

$galatTabel = rts_kt_pastikan_tabel($conn);

if ($galatTabel !== '' && $aksi !== 'hitung') {
    rts_api_fail($galatTabel, 500, ['tabel' => 'rts_kantor', 'aksi' => $aksi]);
}

/* ================================================================ 1. HITUNG */

if ($aksi === 'hitung') {
    $jumlah = 0;

    $hasil = $conn->query('SELECT COUNT(*) AS jumlah FROM `rts_kantor`');

    if ($hasil instanceof mysqli_result) {
        $baris = $hasil->fetch_assoc();
        $jumlah = (int) ($baris['jumlah'] ?? 0);
        $hasil->free();
    }

    rts_api_response(true, "Jumlah titik kantor: $jumlah.", [
        'jumlah' => $jumlah,
        'ada_tabel' => $galatTabel === '',
        'pengelola' => $pengelola,
    ]);
}

/* ================================================================ 2. DAFTAR */

if ($aksi === 'daftar') {
    $items = rts_kt_daftar($conn);

    rts_api_response(true, 'Daftar titik lokasi kantor / mitra berhasil dibaca.', [
        'items' => $items,
        'jumlah' => count($items),
        'waktu_server' => date('Y-m-d H:i:s'),
        'pengelola' => $pengelola,
    ]);
}

/* ================================================================ 3. SIMPAN */

if ($aksi === 'simpan') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN / ASS yang dapat menitikkan lokasi kantor.', 403);
    }

    $id = (int) ($masukan['id'] ?? 0);
    $nama = rts_kt_teks($masukan['nama'] ?? '', 120);
    $alamat = rts_kt_teks($masukan['alamat'] ?? '', 255);
    $district = rts_kt_teks($masukan['district'] ?? '', 120);
    $catatan = rts_kt_teks($masukan['catatan'] ?? '', 255);
    $latitude = rts_kt_angka($masukan['latitude'] ?? 0);
    $longitude = rts_kt_angka($masukan['longitude'] ?? 0);

    if ($nama === '') {
        rts_api_fail('Nama kantor / mitra belum diisi.', 400);
    }

    if ($latitude < -90 || $latitude > 90 || $longitude < -180 || $longitude > 180) {
        rts_api_fail('Titik lokasi tidak masuk akal (lintang -90..90, bujur -180..180).', 400);
    }

    if (abs($latitude) < 0.0000001 && abs($longitude) < 0.0000001) {
        rts_api_fail('Titik lokasi belum diambil. Tekan AMBIL TITIK DARI LOKASI SAYA.', 400);
    }

    if ($id > 0) {
        $stmt = $conn->prepare(
            'UPDATE `rts_kantor` SET `nama` = ?, `alamat` = ?, `district` = ?, '
            . '`latitude` = ?, `longitude` = ?, `catatan` = ?, `diubah_oleh` = ?, '
            . '`diubah_pada` = NOW() WHERE `id` = ?'
        );

        if (!$stmt) {
            rts_api_fail('Titik kantor tidak dapat disimpan: ' . $conn->error, 500);
        }

        $stmt->bind_param(
            'sssddssi',
            $nama,
            $alamat,
            $district,
            $latitude,
            $longitude,
            $catatan,
            $namaUser,
            $id
        );
        $stmt->execute();
        $stmt->close();

        $items = rts_kt_daftar($conn);

        rts_api_response(true, 'Titik lokasi "' . $nama . '" diperbarui.', [
            'id' => $id,
            'kantor' => rts_kt_bentuk([
                'id' => $id,
                'nama' => $nama,
                'alamat' => $alamat,
                'district' => $district,
                'latitude' => $latitude,
                'longitude' => $longitude,
                'catatan' => $catatan,
                'diubah_oleh' => $namaUser,
                'diubah_pada' => date('Y-m-d H:i:s'),
            ]),
            'items' => $items,
            'jumlah' => count($items),
        ]);
    }

    $stmt = $conn->prepare(
        'INSERT INTO `rts_kantor` (`nama`, `alamat`, `district`, `latitude`, '
        . '`longitude`, `catatan`, `dibuat_oleh`, `dibuat_pada`, `diubah_oleh`, '
        . '`diubah_pada`) VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), ?, NOW())'
    );

    if (!$stmt) {
        rts_api_fail('Titik kantor tidak dapat disimpan: ' . $conn->error, 500);
    }

    $stmt->bind_param(
        'sssddsss',
        $nama,
        $alamat,
        $district,
        $latitude,
        $longitude,
        $catatan,
        $namaUser,
        $namaUser
    );
    $stmt->execute();
    $idBaru = (int) $conn->insert_id;
    $stmt->close();

    $items = rts_kt_daftar($conn);

    rts_api_response(true, 'Titik lokasi "' . $nama . '" tersimpan di server.', [
        'id' => $idBaru,
        'kantor' => rts_kt_bentuk([
            'id' => $idBaru,
            'nama' => $nama,
            'alamat' => $alamat,
            'district' => $district,
            'latitude' => $latitude,
            'longitude' => $longitude,
            'catatan' => $catatan,
            'diubah_oleh' => $namaUser,
            'diubah_pada' => date('Y-m-d H:i:s'),
        ]),
        'items' => $items,
        'jumlah' => count($items),
    ]);
}

/* ================================================================= 4. HAPUS */

if ($aksi === 'hapus') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN / ASS yang dapat menghapus titik kantor.', 403);
    }

    $id = (int) ($masukan['id'] ?? 0);

    if ($id <= 0) {
        rts_api_fail('Titik kantor yang akan dihapus belum dipilih.', 400);
    }

    $stmt = $conn->prepare('DELETE FROM `rts_kantor` WHERE `id` = ?');

    if (!$stmt) {
        rts_api_fail('Titik kantor tidak dapat dihapus: ' . $conn->error, 500);
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $terhapus = $stmt->affected_rows;
    $stmt->close();

    $items = rts_kt_daftar($conn);

    rts_api_response(
        true,
        $terhapus > 0
            ? 'Titik lokasi kantor dihapus.'
            : 'Titik lokasi kantor tidak ditemukan.',
        [
            'id' => $id,
            'dihapus' => $terhapus > 0,
            'items' => $items,
            'jumlah' => count($items),
        ]
    );
}

/* ------------------------------------------------------------- tak dikenal */

rts_api_fail('Perintah "' . $aksi . '" tidak dikenal pada API kantor.', 400, [
    'aksi_dikenal' => ['daftar', 'simpan', 'hapus', 'hitung'],
]);
