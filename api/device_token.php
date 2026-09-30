<?php
/**
 * RTS Panel API - Pendaftaran Token Perangkat (Pemberitahuan HP)
 * Endpoint : /api/device_token.php
 *
 * Dipakai aplikasi Android untuk memberi tahu server "HP ini milik akun ini",
 * supaya server dapat mengirim pemberitahuan ke layar HP walaupun aplikasi
 * sedang ditutup sepenuhnya (lewat Firebase Cloud Messaging).
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Cara pakai:
 *   Simpan / perbarui token
 *     POST { "token": "<token FCM>", "platform": "android", "perangkat": "CPH1937" }
 *
 *   Hapus token (dipakai saat Keluar, supaya HP tidak lagi menerima
 *   pemberitahuan milik akun tersebut)
 *     POST { "action": "hapus", "token": "<token FCM>" }
 *
 * Balasan sukses:
 *   { "success": true, "message": "...", "tersimpan": 1, "jumlah_perangkat": 1 }
 *
 * Catatan: bila tabel rts_device_tokens belum dibuat, endpoint ini menjawab
 * dengan pesan yang jelas dan aplikasi tetap berjalan seperti biasa.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($metode !== 'POST' && $metode !== 'GET') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$email = trim((string) ($user['email'] ?? ''));

if ($email === '') {
    rts_api_fail('Akun ini belum memiliki alamat email. Hubungi Admin.', 422);
}

/* ------------------------------------------------------------- tabel tersedia */

$tabelAda = false;
$hasilTabel = $conn->query(
    "SELECT COUNT(*) AS total FROM information_schema.TABLES
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'rts_device_tokens'"
);

if ($hasilTabel && ($barisTabel = $hasilTabel->fetch_assoc())) {
    $tabelAda = (int) $barisTabel['total'] > 0;
}

if (!$tabelAda) {
    rts_api_fail(
        'Tabel rts_device_tokens belum dibuat. Jalankan berkas SQL '
        . 'RTS_PANEL_TABEL_DEVICE_TOKENS.sql pada database.',
        503
    );
}

/* ---------------------------------------------------------------- parameter */

$aksi = strtolower(rts_api_param('action', 'simpan'));
$token = rts_api_param('token');
$platform = strtolower(rts_api_param('platform', 'android'));
$perangkat = rts_api_param('perangkat');

if ($token === '') {
    // Bila token tidak dikirim, aplikasi tetap boleh membuka layar Pengaturan.
    rts_api_response(true, 'Tidak ada token perangkat yang dikirim.', [
        'tersimpan' => 0,
        'jumlah_perangkat' => 0,
    ]);
}

if (strlen($token) > 255) {
    rts_api_fail('Token perangkat terlalu panjang.', 422);
}

/* ------------------------------------------------------------------- hapus */

if ($aksi === 'hapus' || $aksi === 'delete' || $aksi === 'remove') {
    $hapus = $conn->prepare('DELETE FROM rts_device_tokens WHERE token=? AND user_email=?');

    if (!$hapus) {
        rts_api_fail('Gagal menyiapkan penghapusan token.', 500);
    }

    $hapus->bind_param('ss', $token, $email);
    $hapus->execute();
    $terhapus = $hapus->affected_rows;
    $hapus->close();

    rts_api_response(true, 'Token perangkat dihapus. HP ini tidak lagi menerima pemberitahuan.', [
        'terhapus' => (int) $terhapus,
        'jumlah_perangkat' => rts_device_jumlah($conn, $email),
    ]);
}

/* --------------------------------------------------------------- token kosong */

if ($platform === '' || $platform === 'unknown') {
    $platform = 'android';
}

/* ---------------------------------------------------- simpan / perbarui token */

$sudahAda = $conn->prepare('SELECT id FROM rts_device_tokens WHERE token=? LIMIT 1');

if (!$sudahAda) {
    rts_api_fail('Gagal memeriksa token perangkat.', 500);
}

$sudahAda->bind_param('s', $token);
$sudahAda->execute();
$barisToken = $sudahAda->get_result()->fetch_assoc();
$sudahAda->close();

if ($barisToken) {
    $perbarui = $conn->prepare(
        'UPDATE rts_device_tokens
         SET user_email=?, platform=?, perangkat=?, diperbarui_pada=CURRENT_TIMESTAMP
         WHERE id=?'
    );

    if (!$perbarui) {
        rts_api_fail('Gagal memperbarui token perangkat.', 500);
    }

    $idToken = (int) $barisToken['id'];
    $perbarui->bind_param('sssi', $email, $platform, $perangkat, $idToken);
    $perbarui->execute();
    $perbarui->close();

    rts_api_response(true, 'Token perangkat diperbarui.', [
        'tersimpan' => 1,
        'diperbarui' => 1,
        'jumlah_perangkat' => rts_device_jumlah($conn, $email),
    ]);
}

$simpan = $conn->prepare(
    'INSERT INTO rts_device_tokens (user_email, token, platform, perangkat)
     VALUES (?, ?, ?, ?)'
);

if (!$simpan) {
    rts_api_fail('Gagal menyiapkan penyimpanan token.', 500);
}

$simpan->bind_param('ssss', $email, $token, $platform, $perangkat);

if (!$simpan->execute()) {
    rts_api_fail('Token perangkat gagal disimpan.', 500);
}

$simpan->close();

rts_api_response(true, 'HP ini sudah terdaftar untuk menerima pemberitahuan.', [
    'tersimpan' => 1,
    'diperbarui' => 0,
    'jumlah_perangkat' => rts_device_jumlah($conn, $email),
]);

/* ------------------------------------------------------------------ bantuan */

/**
 * Menghitung jumlah perangkat terdaftar milik satu akun.
 */
function rts_device_jumlah(mysqli $conn, string $email): int
{
    $hitung = $conn->prepare('SELECT COUNT(*) AS total FROM rts_device_tokens WHERE user_email=?');

    if (!$hitung) {
        return 0;
    }

    $hitung->bind_param('s', $email);
    $hitung->execute();
    $baris = $hitung->get_result()->fetch_assoc();
    $hitung->close();

    return $baris ? (int) $baris['total'] : 0;
}
