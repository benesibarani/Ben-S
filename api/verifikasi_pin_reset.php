<?php
/**
 * RTS Panel API - Langkah 1 lupa password: cek PIN
 * Endpoint : /api/verifikasi_pin_reset.php
 *
 * Tanpa login. Body JSON:
 *   username : username akun
 *   pin      : PIN 6 digit
 *
 * Balasan sukses hanya menandakan PIN benar. Password belum diubah.
 * Langkah berikutnya: reset_password_pin.php (membawa username dan PIN).
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

if ($username === '' || $pin === '') {
    rts_api_fail('Username dan PIN wajib diisi.', 422);
}

if (preg_match('/^\d{6}$/', $pin) !== 1) {
    rts_api_fail('PIN harus tepat 6 angka.', 422);
}

$hasil = rts_pin_periksa($conn, $username, $pin);

if (!$hasil['ok']) {
    rts_api_fail($hasil['message'], $hasil['status']);
}

rts_pin_bersihkan_gagal($conn, (int) $hasil['id']);

rts_api_response(true, 'PIN benar. Silakan buat password baru.');
