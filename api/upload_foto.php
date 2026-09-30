<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - UNGGAH FOTO PRIBADI
 *  Berkas : api/upload_foto.php
 *
 *  KEGUNAAN
 *  --------
 *  Setiap petugas dapat memasang foto dirinya sendiri. Foto ditampilkan pada
 *  kartu akun di aplikasi (halaman Beranda dan Profil) serta pada website.
 *
 *  CARA PAKAI (aplikasi mengirim token login pada header Authorization)
 *     POST upload_foto.php   (form-data)
 *        foto  = berkas gambar (JPG / PNG / WEBP), paling besar 2 MB
 *     POST upload_foto.php   aksi=hapus     -> menghapus foto yang sedang dipakai
 *
 *  HASIL
 *     { success, message, foto_url, foto_profil }
 *
 *  PENYIMPANAN
 *     Berkas gambar disimpan pada folder  uploads/foto_profil/  di hosting,
 *     sedangkan nama berkasnya dicatat pada kolom sales_users.foto_profil.
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/langganan_inti.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($metode !== 'POST') {
    rts_api_fail('Gunakan POST untuk mengunggah foto.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$userId = (int) $user['id'];

/* ------------------------------------------------------------- pengaman */

if (!rts_lg_ada_kolom($conn, 'foto_profil')) {
    rts_api_fail(
        'Kolom foto_profil belum ada di database. Buka halaman Akun PRO / '
        . 'Langganan pada website lalu tekan tombol "Perbarui Database".',
        409
    );
}

/**
 * Alamat dasar website, dipakai untuk menyusun alamat gambar yang lengkap.
 */
function rts_foto_alamat_dasar(): string
{
    $skema = 'http';

    if (!empty($_SERVER['HTTP_X_FORWARDED_PROTO'])) {
        $skema = trim(explode(',', (string) $_SERVER['HTTP_X_FORWARDED_PROTO'])[0]);
    } elseif (!empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off') {
        $skema = 'https';
    } elseif ((string) ($_SERVER['SERVER_PORT'] ?? '') === '443') {
        $skema = 'https';
    }

    if ($skema !== 'https') {
        $skema = 'http';
    }

    $host = (string) ($_SERVER['HTTP_HOST'] ?? '');

    if ($host === '') {
        $host = 'rts.benedic-s.com';
    }

    return $skema . '://' . $host;
}

/**
 * Folder penyimpanan gambar.
 */
function rts_foto_folder(): string
{
    return dirname(__DIR__) . '/uploads/foto_profil';
}

/**
 * Menghapus berkas gambar lama milik pengguna (bila ada).
 */
function rts_foto_hapus_lama(mysqli $conn, int $userId): void
{
    $nama = '';

    $hasil = @$conn->query('SELECT foto_profil FROM sales_users WHERE id = ' . $userId . ' LIMIT 1');

    if ($hasil instanceof mysqli_result) {
        $nama = (string) (($hasil->fetch_assoc()['foto_profil'] ?? ''));
        $hasil->free();
    }

    $nama = basename(trim($nama));

    if ($nama === '' || $nama === '.') {
        return;
    }

    $jalur = rts_foto_folder() . '/' . $nama;

    if (is_file($jalur)) {
        @unlink($jalur);
    }
}

/* ------------------------------------------------------- hapus foto lama */

$aksi = strtolower(trim((string) ($_POST['aksi'] ?? $_GET['aksi'] ?? '')));

if ($aksi === 'hapus') {
    rts_foto_hapus_lama($conn, $userId);

    if (!@$conn->query("UPDATE sales_users SET foto_profil = '' WHERE id = " . $userId)) {
        rts_api_fail('Foto gagal dihapus dari database.', 500);
    }

    rts_api_response(true, 'Foto pribadi berhasil dihapus.', [
        'foto_url' => '',
        'foto_profil' => '',
    ]);
}

/* ------------------------------------------------------------ unggah baru */

if (!isset($_FILES['foto'])) {
    rts_api_fail('Berkas foto belum dikirim.', 422);
}

$berkas = $_FILES['foto'];

if (!is_array($berkas) || !isset($berkas['tmp_name'])) {
    rts_api_fail('Berkas foto tidak dikenali.', 422);
}

if ((int) ($berkas['error'] ?? 1) !== 0) {
    $pesan = 'Berkas foto gagal diunggah.';

    switch ((int) $berkas['error']) {
        case UPLOAD_ERR_INI_SIZE:
        case UPLOAD_ERR_FORM_SIZE:
            $pesan = 'Ukuran foto terlalu besar. Gunakan foto di bawah 2 MB.';
            break;
        case UPLOAD_ERR_NO_FILE:
            $pesan = 'Belum ada berkas foto yang dipilih.';
            break;
    }

    rts_api_fail($pesan, 422);
}

$ukuran = (int) ($berkas['size'] ?? 0);

if ($ukuran <= 0) {
    rts_api_fail('Berkas foto kosong.', 422);
}

if ($ukuran > 2 * 1024 * 1024) {
    rts_api_fail('Ukuran foto terlalu besar (maksimal 2 MB). Kompres foto lebih dahulu.', 422);
}

$sementara = (string) $berkas['tmp_name'];

$ukuranGambar = @getimagesize($sementara);

if (!is_array($ukuranGambar)) {
    rts_api_fail('Berkas yang dikirim bukan gambar. Gunakan foto JPG atau PNG.', 422);
}

$jenis = (int) ($ukuranGambar[2] ?? 0);

$akhiran = '';

switch ($jenis) {
    case IMAGETYPE_JPEG:
        $akhiran = 'jpg';
        break;
    case IMAGETYPE_PNG:
        $akhiran = 'png';
        break;
    case IMAGETYPE_WEBP:
        $akhiran = 'webp';
        break;
    default:
        rts_api_fail('Jenis gambar belum didukung. Gunakan JPG, PNG, atau WEBP.', 422);
}

$folder = rts_foto_folder();

if (!is_dir($folder) && !@mkdir($folder, 0755, true) && !is_dir($folder)) {
    rts_api_fail('Folder penyimpanan foto tidak dapat dibuat. Hubungi Admin hosting.', 500);
}

$penjaga = $folder . '/index.html';

if (!is_file($penjaga)) {
    @file_put_contents($penjaga, 'Akses langsung tidak diizinkan.');
}

$namaBaru = 'u' . $userId . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3)) . '.' . $akhiran;
$jalurBaru = $folder . '/' . $namaBaru;

if (!@move_uploaded_file($sementara, $jalurBaru)) {
    if (!@rename($sementara, $jalurBaru)) {
        rts_api_fail('Foto gagal disimpan di server. Coba lagi.', 500);
    }
}

@chmod($jalurBaru, 0644);

rts_foto_hapus_lama($conn, $userId);

$relatif = 'uploads/foto_profil/' . $namaBaru;

$stmt = $conn->prepare('UPDATE sales_users SET foto_profil = ? WHERE id = ?');

if (!$stmt) {
    @unlink($jalurBaru);

    rts_api_fail('Gagal menyimpan keterangan foto: ' . $conn->error, 500);
}

$stmt->bind_param('si', $relatif, $userId);

if (!$stmt->execute()) {
    $stmt->close();
    @unlink($jalurBaru);

    rts_api_fail('Gagal menyimpan keterangan foto.', 500);
}

$stmt->close();

rts_api_response(true, 'Foto pribadi berhasil diganti.', [
    'foto_profil' => $relatif,
    'foto_url' => rts_foto_alamat_dasar() . '/' . $relatif,
]);
