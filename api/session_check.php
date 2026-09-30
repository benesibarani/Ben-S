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

rts_api_response(true, 'Sesi masih berlaku.', [
    'user' => [
        'id' => (int) $user['id'],
        'username' => (string) $user['username'],
        'nama_lengkap' => (string) $user['nama_lengkap'],
        'email' => (string) ($user['email'] ?? ''),
        'role' => (string) $user['role'],
        'salesman' => (string) ($user['salesman'] ?? ''),
        'sales_district' => (string) ($user['sales_district'] ?? ''),
    ],
    'scope' => [
        'mode' => (string) ($scope['mode'] ?? ''),
        'label' => (string) ($scope['label'] ?? ''),
        'all_area' => (bool) ($scope['all_area'] ?? false),
        'can_approve' => (bool) ($scope['can_approve'] ?? false),
    ],
]);
