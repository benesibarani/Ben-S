<?php
/**
 * RTS Panel API - Periksa Sesi Tersimpan
 * Endpoint : /api/session_check.php
 *
 * Dipakai aplikasi Android saat dibuka kembali dalam keadaan "Ingat saya".
 * Aplikasi mengirim token yang tersimpan, lalu endpoint ini memastikan token
 * masih berlaku dan mengembalikan identitas akun serta cakupan datanya.
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Balasan sukses:
 * {
 *   "success": true,
 *   "message": "Sesi masih berlaku.",
 *   "user": { id, username, nama_lengkap, email, role, salesman, sales_district },
 *   "scope": { mode, label, all_area, can_approve }
 * }
 *
 * Token tidak berlaku / kedaluwarsa -> 401
 * Akun tidak aktif                   -> 403
 *
 * Endpoint ini ringan: hanya membaca satu baris api_tokens join sales_users.
 */

require_once __DIR__ . '/api_bootstrap.php';

/* Aturan langganan PRO (masa berlaku 30 hari + uji coba 7 hari). */
if (is_file(__DIR__ . '/langganan_inti.php')) {
    require_once __DIR__ . '/langganan_inti.php';
}

rts_api_headers();
rts_api_handle_preflight();

$metode = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($metode !== 'GET' && $metode !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan GET atau POST.', 405);
}

/* rts_api_require_user() otomatis menolak token kosong, token tidak dikenal,
   token kedaluwarsa (401), dan akun tidak aktif (403). */
$user = rts_api_require_user();
$scope = rts_api_scope($user);

/* Koneksi database dipakai untuk membaca keadaan langganan PRO. */
$conn = rts_api_db();

/* Keadaan langganan dihitung ulang setiap aplikasi dibuka, sehingga masa
   PRO yang sudah berakhir langsung terlihat dan iklan kembali tampil. */
$langganan = [
    'pro' => false,
    'akun_pro' => (int) ($user['akun_pro'] ?? 0),
    'sumber' => 'GRATIS',
    'label' => 'GRATIS',
];

$fotoProfil = '';

if (function_exists('rts_lg_baris')) {
    try {
        $barisLangganan = rts_lg_baris($conn, (int) $user['id']);

        if (is_array($barisLangganan)) {
            $langganan = rts_lg_status($barisLangganan);
            $fotoProfil = (string) ($barisLangganan['foto_profil'] ?? '');
        }
    } catch (Throwable $galatLangganan) {
        error_log('RTS session: langganan gagal - ' . $galatLangganan->getMessage());
    }
}

$skemaSesi = (!empty($_SERVER['HTTP_X_FORWARDED_PROTO'])
    ? trim(explode(',', (string) $_SERVER['HTTP_X_FORWARDED_PROTO'])[0])
    : ((!empty($_SERVER['HTTPS']) && strtolower((string) $_SERVER['HTTPS']) !== 'off') ? 'https' : 'http'));

if ($skemaSesi !== 'https') {
    $skemaSesi = 'http';
}

if ($fotoProfil !== '' && substr($fotoProfil, 0, 4) !== 'http') {
    $fotoProfil = $skemaSesi . '://' . (string) ($_SERVER['HTTP_HOST'] ?? 'rts.benedic-s.com')
        . '/' . ltrim($fotoProfil, '/');
}

rts_api_response(true, 'Sesi masih berlaku.', [
    'user' => [
        'id' => (int) $user['id'],
        'username' => (string) $user['username'],
        'nama_lengkap' => (string) $user['nama_lengkap'],
        'email' => (string) ($user['email'] ?? ''),
        'role' => (string) $user['role'],
        'salesman' => (string) ($user['salesman'] ?? ''),
        'sales_district' => (string) ($user['sales_district'] ?? ''),
        'akun_pro' => (int) ($langganan['akun_pro'] ?? 0),
        'foto_profil' => $fotoProfil,
        'pro_selesai' => (string) ($langganan['pro_selesai'] ?? ''),
        'trial_selesai' => (string) ($langganan['trial_selesai'] ?? ''),
        'trial_aktif' => (bool) ($langganan['trial_aktif'] ?? false),
        'trial_tersedia' => (bool) ($langganan['trial_tersedia'] ?? false),
        'sisa_hari' => (int) ($langganan['sisa_hari'] ?? 0),
        'sumber_langganan' => (string) ($langganan['sumber'] ?? 'GRATIS'),
        'berlaku_sampai' => (string) ($langganan['berlaku_sampai'] ?? ''),
    ],
    'langganan' => $langganan,
    'scope' => [
        'mode' => (string) ($scope['mode'] ?? ''),
        'label' => (string) ($scope['label'] ?? ''),
        'all_area' => (bool) ($scope['all_area'] ?? false),
        'can_approve' => (bool) ($scope['can_approve'] ?? false),
    ],
]);
