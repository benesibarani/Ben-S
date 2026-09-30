<?php
/**
 * RTS Panel API - Ganti Password Sendiri
 * Endpoint : /api/change_password.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Body JSON:
 *   password_lama  : password yang sedang dipakai
 *   password_baru  : password baru
 *
 * Aturan password baru:
 *   - paling sedikit 6 karakter
 *   - tidak boleh sama dengan password lama
 *   - harus sama dengan isian ulangi_password pada aplikasi (diperiksa di HP)
 *
 * Setelah berhasil:
 *   - password disimpan dengan cara yang sama seperti login (password_hash)
 *   - SELURUH token lain milik akun ini dihapus, sehingga HP atau perangkat lain
 *     yang masih login harus masuk kembali. Token yang sedang dipakai di HP ini
 *     TETAP berlaku, jadi pengguna tidak terlempar keluar.
 *
 * Balasan sukses:
 *   { success: true, message: "...", token_lain_dihapus: 2 }
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$passwordLama = (string) rts_api_param('password_lama');
$passwordBaru = (string) rts_api_param('password_baru');

if ($passwordLama === '' || $passwordBaru === '') {
    rts_api_fail('Password lama dan password baru wajib diisi.', 422);
}

if (strlen($passwordBaru) < 6) {
    rts_api_fail('Password baru paling sedikit 6 karakter.', 422);
}

if (strlen($passwordBaru) > 72) {
    rts_api_fail('Password baru terlalu panjang. Maksimal 72 karakter.', 422);
}

if ($passwordLama === $passwordBaru) {
    rts_api_fail('Password baru tidak boleh sama dengan password lama.', 422);
}

$idUser = (int) ($user['id'] ?? 0);

if ($idUser <= 0) {
    rts_api_fail('Akun tidak dikenali. Silakan login kembali.', 401);
}

if (!rts_api_has_column('sales_users', 'password')) {
    rts_api_fail('Kolom password belum tersedia pada tabel sales_users.', 500);
}

/* ------------------------------------------------------ password lama benar? */

$stmt = $conn->prepare(
    'SELECT password FROM sales_users WHERE id = ? LIMIT 1'
);

if (!$stmt) {
    error_log('RTS API change_password prepare error: ' . $conn->error);
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

$hashLama = (string) ($baris['password'] ?? '');

if (!password_verify($passwordLama, $hashLama)) {
    rts_api_fail('Password lama tidak sesuai.', 422);
}

/* --------------------------------------------------------------- simpan baru */

$hashBaru = password_hash($passwordBaru, PASSWORD_DEFAULT);

$update = $conn->prepare(
    'UPDATE sales_users SET password = ? WHERE id = ?'
);

if (!$update) {
    error_log('RTS API change_password update error: ' . $conn->error);
    rts_api_fail('Password gagal disimpan. Coba lagi.', 500);
}

$update->bind_param('si', $hashBaru, $idUser);

if (!$update->execute()) {
    error_log('RTS API change_password execute error: ' . $update->error);
    $update->close();
    rts_api_fail('Password gagal disimpan. Coba lagi.', 500);
}

$update->close();

/* ------------------------------------------- putuskan sesi pada perangkat lain */

$tokenLainDihapus = 0;

if (rts_api_has_column('api_tokens', 'token_hash')) {
    $tokenSekarang = rts_api_bearer_token();
    $hashSekarang = hash('sha256', $tokenSekarang);

    $hapus = $conn->prepare(
        'DELETE FROM api_tokens WHERE user_id = ? AND token_hash <> ?'
    );

    if ($hapus) {
        $hapus->bind_param('is', $idUser, $hashSekarang);

        if ($hapus->execute()) {
            $tokenLainDihapus = (int) $hapus->affected_rows;
        }

        $hapus->close();
    }
}

/* ------------------------------------------------------------------ balasan */

$pesan = 'Password berhasil diganti.';

if ($tokenLainDihapus > 0) {
    $pesan .= ' ' . $tokenLainDihapus
        . ' sesi pada perangkat lain sudah diputus dan perlu login kembali.';
}

rts_api_response(true, $pesan, [
    'token_lain_dihapus' => $tokenLainDihapus,
]);
