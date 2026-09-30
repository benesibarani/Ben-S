<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API LANGGANAN PRO
 *  Berkas : api/langganan.php
 *
 *  Dipakai oleh halaman "Langganan PRO" di dalam aplikasi Android.
 *
 *  CARA PAKAI (aplikasi mengirim token login pada header Authorization)
 *     GET  langganan.php                  -> keadaan langganan + keterangan QRIS
 *     POST langganan.php  aksi=trial      -> memulai uji coba 7 hari
 *     POST langganan.php  aksi=klaim      -> "saya sudah bayar" (menunggu periksa)
 *
 *  Aturan masa berlaku:
 *     Uji coba (TRIAL) : 7 hari, sekali saja, otomatis saat login pertama
 *     Langganan (PRO)  : 30 hari setiap pembayaran diterima Admin
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/langganan_inti.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($metode !== 'GET' && $metode !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan GET atau POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

/* ------------------------------------------------------------- baca kiriman */

$masukan = $_POST;

if ($metode === 'POST') {
    $mentah = file_get_contents('php://input');

    if (is_string($mentah) && trim($mentah) !== '') {
        $terurai = json_decode($mentah, true);

        if (is_array($terurai)) {
            $masukan = array_merge($masukan, $terurai);
        }
    }
}

$aksi = strtolower(trim((string) ($masukan['aksi'] ?? $_GET['aksi'] ?? '')));

if ($aksi === 'trial') {
    $hasil = rts_lg_mulai_trial($conn, (int) $user['id']);

    $baris = rts_lg_baris($conn, (int) $user['id']);

    rts_api_response(
        (bool) $hasil['berhasil'],
        (string) $hasil['pesan'],
        [
            'langganan' => $baris ? rts_lg_status($baris) : ($hasil['status'] ?? []),
            'qris' => rts_lg_qris(),
        ],
        $hasil['berhasil'] ? 200 : 400
    );
}

if ($aksi === 'klaim') {
    $catatan = trim((string) ($masukan['catatan'] ?? ''));

    if (strlen($catatan) > 200) {
        $catatan = substr($catatan, 0, 200);
    }

    $hasil = rts_lg_tambah_bayar($conn, (int) $user['id'], 0, $catatan);

    // Memberi tahu ADMIN bahwa ada pernyataan pembayaran baru. Aman gagal:
    // bila pemberitahuan belum siap, pencatatan pembayaran tetap berhasil.
    if (!empty($hasil['berhasil']) && empty($hasil['sudah_ada'])) {
        try {
            if (is_file(__DIR__ . '/notif_otomatis.php')) {
                require_once __DIR__ . '/notif_otomatis.php';

                if (function_exists('rts_notif_kirim') && function_exists('rts_notif_daftar_penerima')) {
                    $penerima = rts_notif_daftar_penerima($conn, 'ADMIN');
                    $penerima[] = (string) ($user['email'] ?? '');

                    rts_notif_kirim(
                        $conn,
                        array_values(array_filter($penerima)),
                        'Pembayaran Akun PRO',
                        strtoupper((string) ($user['nama_lengkap'] ?? $user['username']))
                            . ' menyatakan sudah membayar Akun PRO. Mohon diperiksa '
                            . 'pada halaman Akun PRO di website.',
                        'PEMBAYARAN',
                        [
                            'tipe' => 'pembayaran',
                            'halaman' => 'langganan',
                            'user_id' => (int) $user['id'],
                        ],
                        'pengguna',
                        (int) $user['id']
                    );
                }
            }
        } catch (Throwable $galat) {
            error_log('RTS langganan: pemberitahuan pembayaran gagal - ' . $galat->getMessage());
        }
    }

    $baris = rts_lg_baris($conn, (int) $user['id']);

    rts_api_response(
        (bool) $hasil['berhasil'],
        (string) $hasil['pesan'],
        [
            'langganan' => $baris ? rts_lg_status($baris) : [],
            'qris' => rts_lg_qris(),
            'sudah_ada' => !empty($hasil['sudah_ada']),
        ],
        $hasil['berhasil'] ? 200 : 400
    );
}

/* --------------------------------------------------------------- keadaan */

$baris = rts_lg_baris($conn, (int) $user['id']);

if (!$baris) {
    rts_api_fail('Data pengguna tidak ditemukan.', 404);
}

$status = rts_lg_status($baris);

rts_api_response(true, 'Keadaan langganan.', [
    'langganan' => $status,
    'qris' => rts_lg_qris(),
    'user' => [
        'id' => (int) $baris['id'],
        'username' => (string) ($baris['username'] ?? ''),
        'nama_lengkap' => (string) ($baris['nama_lengkap'] ?? ''),
        'role' => strtoupper((string) ($baris['role'] ?? '')),
        'foto_profil' => (string) ($baris['foto_profil'] ?? ''),
        'akun_pro' => (int) $status['akun_pro'],
    ],
    'kolom' => rts_lg_kolom_tersedia($conn),
]);
