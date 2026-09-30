<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - BERKAS PEMERIKSA SESSION
 *  Berkas : cek_session.php
 *
 *  KEGUNAAN
 *  --------
 *  Menampilkan isi session pada server, untuk memeriksa mengapa sebuah halaman
 *  mengalihkan pengunjung kembali ke dashboard.php.
 *
 *  Berkas ini SENGAJA tidak memakai penjagaan login apa pun, supaya hasil
 *  pemeriksaan tetap dapat dilihat walaupun halaman yang diperiksa menolak
 *  pengunjung. Berkas ini TIDAK menampilkan password dan tidak mengubah data
 *  apa pun - nilai session hanya ditampilkan sebagian (3 huruf pertama).
 *
 *  CARA PAKAI
 *  ----------
 *  1. Unggah berkas ini ke dalam public_html
 *  2. Buka: https://rts.benedic-s.com/cek_session.php
 *  3. Kirimkan tulisan yang muncul kepada pengembang (aman dikirim)
 *  4. HAPUS berkas ini setelah masalahnya selesai
 * ============================================================================
 */

if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}

header('Content-Type: text/plain; charset=utf-8');
header('Cache-Control: no-store');

/** Menampilkan sebagian nilai saja supaya aman dikirim lewat pesan. */
function rts_cek_samar($nilai)
{
    $nilai = trim((string) $nilai);

    if ($nilai === '') {
        return '(kosong)';
    }

    if (strlen($nilai) <= 4) {
        return str_repeat('*', strlen($nilai));
    }

    return substr($nilai, 0, 3) . '*** (' . strlen($nilai) . ' huruf)';
}

echo "PEMERIKSAAN SESSION - RTS PANEL BY BENE\n";
echo "=======================================\n";
echo 'VERSI BERKAS   : 1 (30 September 2026)' . "\n";
echo 'Waktu server   : ' . date('d-m-Y H:i:s') . "\n";
echo 'Alamat berkas  : ' . (isset($_SERVER['HTTP_HOST']) ? $_SERVER['HTTP_HOST'] : '?')
    . (isset($_SERVER['REQUEST_URI']) ? $_SERVER['REQUEST_URI'] : '') . "\n";
echo 'Folder         : ' . __DIR__ . "\n";
echo 'PHP            : ' . PHP_VERSION . "\n\n";

/* --- SESSION ------------------------------------------------------------ */
echo "SESSION\n";
echo '  status aktif   : ' . (session_status() === PHP_SESSION_ACTIVE ? 'YA' : 'TIDAK') . "\n";
echo '  nama session   : ' . session_name() . "\n";
echo '  id session     : ' . rts_cek_samar(session_id()) . "\n";
echo '  kunci tersimpan: ' . count($_SESSION) . "\n\n";

if (empty($_SESSION)) {
    echo "  (session ini kosong)\n\n";
    echo "  ARTI: server tidak melihat cookie session apa pun pada permintaan ini.\n";
    echo "  Bila dashboard.php tetap dapat dibuka, kemungkinan besar\n";
    echo "  cookie session tidak terkirim karena halaman ini berbeda jalur.\n";
} else {
    echo "  DAFTAR KUNCI SESSION:\n";

    foreach (array_keys($_SESSION) as $kunci) {
        echo '    - ' . $kunci . "\n";
    }

    echo "\n  NILAI PENTING:\n";

    $penting = array(
        'is_logged_in', 'user_id', 'username', 'user', 'email',
        'nama', 'nama_lengkap', 'role', 'user_role',
    );

    foreach ($penting as $kunci) {
        if (array_key_exists($kunci, $_SESSION)) {
            echo '    ' . str_pad($kunci, 15) . ': ' . rts_cek_samar($_SESSION[$kunci]) . "\n";
        } else {
            echo '    ' . str_pad($kunci, 15) . ": tidak ada\n";
        }
    }
}

/* --- COOKIE ------------------------------------------------------------- */
echo "\nCOOKIE YANG DITERIMA SERVER\n";

if (empty($_COOKIE)) {
    echo "  (tidak ada cookie)\n";
} else {
    foreach (array_keys($_COOKIE) as $nama_cookie) {
        echo '  - ' . $nama_cookie . "\n";
    }
}

/* --- PHP SESSION CONFIG ------------------------------------------------- */
echo "\nPENGATURAN SESSION PADA PHP\n";
echo '  session.save_path  : ' . ini_get('session.save_path') . "\n";
echo '  session.cookie_path: ' . ini_get('session.cookie_path') . "\n";
echo '  session.name       : ' . ini_get('session.name') . "\n";

/* --- BERKAS PENTING ----------------------------------------------------- */
echo "\nBERKAS DI FOLDER INI\n";

$daftar = array(
    'config.php', 'auth.php', 'header.php', 'footer.php', 'sidebar.php',
    'dashboard.php', 'dashboard_updated.php', 'index.php', 'app_versi.php',
    'api/app_versi.php', 'apk', 'apk/app_versi.json',
);

foreach ($daftar as $nama) {
    echo '  ' . str_pad($nama, 22) . ': ' . (file_exists(__DIR__ . '/' . $nama) ? 'ADA' : 'TIDAK ADA') . "\n";
}

/* --- VERSI BERKAS app_versi.php ---------------------------------------- */
$berkas_app = __DIR__ . '/app_versi.php';

if (is_file($berkas_app)) {
    $isi_app = @file_get_contents($berkas_app);

    if ($isi_app !== false) {
        if (preg_match("/APP_VERSI_BERKAS',\s*(\d+)/", $isi_app, $cocok) === 1) {
            echo "\napp_versi.php  : versi berkas " . $cocok[1] . "\n";
        } else {
            echo "\napp_versi.php  : versi berkas 1 (belum ada penanda versi)\n";
        }

        echo 'ukuran         : ' . number_format(strlen($isi_app)) . " bita\n";
        echo 'terakhir diubah: ' . date('d-m-Y H:i:s', (int) filemtime($berkas_app)) . "\n";
    }
} else {
    echo "\napp_versi.php  : TIDAK ADA pada folder ini\n";
}

echo "\nSELESAI. Berkas ini tidak mengubah data apa pun.\n";
echo "Hapus berkas ini setelah masalahnya selesai.\n";
