<?php
/**
 * RTS Panel API - Langkah 2 lupa password: simpan password baru
 * Endpoint : /api/reset_password_pin.php
 *
 * Tanpa login. Body JSON:
 *   username      : username akun
 *   pin           : PIN 6 digit (diperiksa ulang di sini)
 *   password_baru : paling sedikit 6 karakter
 *
 * Setelah berhasil, SEMUA sesi login akun ini dihapus.
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/pin_pemulihan_inti.php';

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$conn = rts_api_db();

if (!rts_api_has_column('sales_users', 'pin_hash')) {
    rts_api_fail('Fitur PIN belum aktif di server. Hubungi Admin.', 500);
}

$username = rts_api_param('username');
$pin = (string) rts_api_param('pin');
$passwordBaru = (string) rts_api_param('password_baru');

if ($username === '' || $pin === '' || $passwordBaru === '') {
    rts_api_fail('Username, PIN, dan password baru wajib diisi.', 422);
}

if (preg_match('/^\d{6}$/', $pin) !== 1) {
    rts_api_fail('PIN harus tepat 6 angka.', 422);
}

if (strlen($passwordBaru) < 6) {
    rts_api_fail('Password baru paling sedikit 6 karakter.', 422);
}

if (strlen($passwordBaru) > 72) {
    rts_api_fail('Password baru terlalu panjang. Maksimal 72 karakter.', 422);
}

$hasil = rts_pin_periksa($conn, $username, $pin);

if (!$hasil['ok']) {
    rts_api_fail($hasil['message'], $hasil['status']);
}

$idUser = (int) $hasil['id'];
$hashBaru = password_hash($passwordBaru, PASSWORD_DEFAULT);

$update = $conn->prepare(
    'UPDATE sales_users
     SET password = ?, pin_gagal = 0, pin_terkunci_sampai = NULL
     WHERE id = ?'
);

if (!$update) {
    error_log('RTS API reset_pin update error: ' . $conn->error);
    rts_api_fail('Password gagal disimpan. Coba lagi.', 500);
}

$update->bind_param('si', $hashBaru, $idUser);

if (!$update->execute()) {
    error_log('RTS API reset_pin execute error: ' . $update->error);
    $update->close();
    rts_api_fail('Password gagal disimpan. Coba lagi.', 500);
}

$update->close();

/* Putuskan semua sesi lama: pemulihan berarti akun mungkin sudah diakses orang lain. */
if (rts_api_has_column('api_tokens', 'token_hash')) {
    $hapus = $conn->prepare('DELETE FROM api_tokens WHERE user_id = ?');

    if ($hapus) {
        $hapus->bind_param('i', $idUser);
        $hapus->execute();
        $hapus->close();
    }
}

rts_api_response(true, 'Password berhasil direset. Silakan login dengan password baru.');
