<?php
/**
 * RTS Panel API - Reset Password dengan PIN (lupa password)
 * Endpoint : /api/reset_password_pin.php
 *
 * Tanpa login (karena pengguna memang lupa password). Body JSON:
 *   username     : username akun
 *   pin          : PIN 6 digit yang sudah diatur sebelumnya
 *   password_baru: password baru (paling sedikit 6 karakter)
 *
 * Perlindungan:
 *   - 5 kali PIN salah berturut-turut -> akun dikunci reset selama 15 menit
 *   - pesan galat dibuat sama untuk username salah dan PIN salah,
 *     supaya tidak bisa dipakai untuk menebak username yang terdaftar
 *   - setelah berhasil, SEMUA sesi login akun ini dihapus
 */

require_once __DIR__ . '/api_bootstrap.php';

const RTS_PIN_MAKS_SALAH = 5;
const RTS_PIN_KUNCI_MENIT = 15;

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

$kolomLogin = rts_api_has_column('sales_users', 'username') ? 'username' : 'email';

$stmt = $conn->prepare(
    'SELECT id, status_aktif, pin_hash, pin_gagal, pin_terkunci_sampai
     FROM sales_users
     WHERE ' . $kolomLogin . ' = ?
     LIMIT 1'
);

if (!$stmt) {
    error_log('RTS API reset_pin prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$stmt->bind_param('s', $username);
$stmt->execute();
$hasil = $stmt->get_result();
$akun = $hasil ? $hasil->fetch_assoc() : null;
$stmt->close();

$galatSalah = 'Username atau PIN salah.';

if (!$akun) {
    rts_api_fail($galatSalah, 401);
}

$idUser = (int) $akun['id'];

if (strcasecmp((string) ($akun['status_aktif'] ?? 'Aktif'), 'Aktif') !== 0) {
    rts_api_fail('Akun tidak aktif. Hubungi Admin.', 403);
}

if (trim((string) ($akun['pin_hash'] ?? '')) === '') {
    rts_api_fail('PIN belum pernah diatur untuk akun ini. Hubungi Admin untuk reset password.', 422);
}

/* ---------------------------------------------------- cek kunci sementara */

$kunciSampai = (string) ($akun['pin_terkunci_sampai'] ?? '');

if ($kunciSampai !== '' && strtotime($kunciSampai) > time()) {
    $sisaMenit = (int) ceil((strtotime($kunciSampai) - time()) / 60);

    rts_api_fail(
        'Terlalu banyak PIN salah. Coba lagi dalam ' . $sisaMenit . ' menit.',
        429
    );
}

/* ----------------------------------------------------------- periksa PIN */

if (!password_verify($pin, (string) $akun['pin_hash'])) {
    $gagal = ((int) ($akun['pin_gagal'] ?? 0)) + 1;

    if ($gagal >= RTS_PIN_MAKS_SALAH) {
        $kunci = date('Y-m-d H:i:s', time() + (RTS_PIN_KUNCI_MENIT * 60));

        $catat = $conn->prepare(
            'UPDATE sales_users SET pin_gagal = 0, pin_terkunci_sampai = ? WHERE id = ?'
        );

        if ($catat) {
            $catat->bind_param('si', $kunci, $idUser);
            $catat->execute();
            $catat->close();
        }

        rts_api_fail(
            'Terlalu banyak PIN salah. Reset dikunci ' . RTS_PIN_KUNCI_MENIT . ' menit.',
            429
        );
    }

    $catat = $conn->prepare('UPDATE sales_users SET pin_gagal = ? WHERE id = ?');

    if ($catat) {
        $catat->bind_param('ii', $gagal, $idUser);
        $catat->execute();
        $catat->close();
    }

    rts_api_fail($galatSalah . ' Sisa percobaan: ' . (RTS_PIN_MAKS_SALAH - $gagal) . '.', 401);
}

/* ------------------------------------------------------- simpan password baru */

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
