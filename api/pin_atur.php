<?php
/**
 * RTS Panel API - Atur / Ganti PIN Pemulihan
 * Endpoint : /api/pin_atur.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Body JSON:
 *   password_lama : password yang sedang dipakai (wajib, untuk keamanan)
 *   pin_baru      : 6 digit angka
 *
 * Aturan PIN:
 *   - tepat 6 digit angka
 *   - tidak boleh pola mudah (000000, 111111, 123456, 654321, dst.)
 *   - tidak boleh sama dengan password
 *
 * PIN disimpan dengan password_hash. Setelah berhasil, penghitung salah PIN
 * dan kunci sementara direset.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$idUser = (int) ($user['id'] ?? 0);

if ($idUser <= 0) {
    rts_api_fail('Akun tidak dikenali. Silakan login kembali.', 401);
}

if (!rts_api_has_column('sales_users', 'pin_hash')) {
    rts_api_fail('Fitur PIN belum aktif di server. Hubungi Admin.', 500);
}

$passwordLama = (string) rts_api_param('password_lama');
$pinBaru = (string) rts_api_param('pin_baru');

if ($passwordLama === '' || $pinBaru === '') {
    rts_api_fail('Password dan PIN baru wajib diisi.', 422);
}

if (preg_match('/^\d{6}$/', $pinBaru) !== 1) {
    rts_api_fail('PIN harus tepat 6 angka.', 422);
}

$polaMudah = ['000000', '111111', '222222', '333333', '444444', '555555',
    '666666', '777777', '888888', '999999', '123456', '654321', '012345'];

if (in_array($pinBaru, $polaMudah, true)) {
    rts_api_fail('PIN terlalu mudah ditebak. Pilih angka lain.', 422);
}

/* ------------------------------------------------- verifikasi password lama */

$stmt = $conn->prepare('SELECT password FROM sales_users WHERE id = ? LIMIT 1');

if (!$stmt) {
    error_log('RTS API pin_atur prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$stmt->bind_param('i', $idUser);
$stmt->execute();
$hasil = $stmt->get_result();
$baris = $hasil ? $hasil->fetch_assoc() : null;
$stmt->close();

if (!$baris) {
    rts_api_fail('Akun tidak ditemukan. Silakan login kembali.', 404);
}

if (!password_verify($passwordLama, (string) $baris['password'])) {
    rts_api_fail('Password tidak sesuai.', 422);
}

if ($passwordLama === $pinBaru) {
    rts_api_fail('PIN tidak boleh sama dengan password.', 422);
}

/* ------------------------------------------------------------------ simpan */

$hashPin = password_hash($pinBaru, PASSWORD_DEFAULT);

$update = $conn->prepare(
    'UPDATE sales_users
     SET pin_hash = ?, pin_gagal = 0, pin_terkunci_sampai = NULL
     WHERE id = ?'
);

if (!$update) {
    error_log('RTS API pin_atur update error: ' . $conn->error);
    rts_api_fail('PIN gagal disimpan. Coba lagi.', 500);
}

$update->bind_param('si', $hashPin, $idUser);

if (!$update->execute()) {
    error_log('RTS API pin_atur execute error: ' . $update->error);
    $update->close();
    rts_api_fail('PIN gagal disimpan. Coba lagi.', 500);
}

$update->close();

rts_api_response(true, 'PIN pemulihan berhasil disimpan.', [
    'pin_aktif' => true,
]);
