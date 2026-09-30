<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PEMBARUAN DATABASE LANGGANAN
 *  Berkas : api/siapkan_langganan.php
 *
 *  KEGUNAAN
 *  --------
 *  Menambahkan kolom dan tabel yang dibutuhkan fitur langganan:
 *      kolom : akun_pro, foto_profil, pro_mulai, pro_selesai,
 *              trial_mulai, trial_selesai  (pada tabel sales_users)
 *      tabel : pembayaran_pro
 *
 *  HANYA ADMIN. Dipanggil dengan token login pada header Authorization:
 *      POST /api/siapkan_langganan.php
 *
 *  Proses ini hanya MENAMBAH yang belum ada dan tidak menghapus data apa pun.
 *  Cara termudah: buka halaman langganan_admin.php di website lalu tekan
 *  tombol "PERBARUI DATABASE".
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/langganan_inti.php';

rts_api_headers();
rts_api_handle_preflight();

if ((string) ($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    rts_api_fail('Gunakan POST untuk menjalankan pembaruan database.', 405);
}

$user = rts_api_require_user();

if (strtoupper((string) ($user['role'] ?? '')) !== 'ADMIN') {
    rts_api_fail('Pembaruan database hanya dapat dijalankan oleh ADMIN.', 403);
}

$conn = rts_api_db();

$catatan = rts_lg_siapkan_database($conn);

rts_api_response(true, 'Pembaruan database selesai diperiksa.', [
    'catatan' => $catatan,
    'kolom' => rts_lg_kolom_tersedia($conn),
    'tabel_pembayaran_pro' => rts_lg_tabel_pembayaran($conn),
]);
