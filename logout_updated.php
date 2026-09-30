<?php
// =============================================================================
// RTS Panel By Bene - LOGOUT
//
// Perbaikan tombol "Keluar" pada sidebar.
//
// Masalah sebelumnya: berkas ini mengalihkan ke dashboard.php. Setelah sesi
// dihapus, dashboard.php menolak menampilkan apa pun dan mengalihkan lagi,
// sehingga browser mengikuti pengalihan berputar tanpa henti dan menampilkan:
//
//     ERR_TOO_MANY_REDIRECTS
//
// Sekarang pengalihan diarahkan ke index.php, yaitu halaman login website.
// Setelah keluar, halaman login langsung tampil seperti seharusnya.
//
// Berkas ini hanya mengubah pengalihan. Cara menghapus sesi tidak diubah.
// =============================================================================

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

// 1. Kosongkan semua variabel sesi
$_SESSION = array();

// 2. Hapus cookie sesi dari browser (pembersihan total)
if (ini_get('session.use_cookies')) {
    $params = session_get_cookie_params();

    setcookie(
        session_name(),
        '',
        time() - 42000,
        $params['path'],
        $params['domain'],
        $params['secure'],
        $params['httponly']
    );
}

// 3. Hancurkan sesi di server
session_destroy();

// 4. Pengalihan ke halaman login (index.php)
//    Header dikirim lebih dahulu; baris JavaScript di bawahnya menjadi cadangan
//    apabila header tidak dapat dikirim (misalnya karena sudah ada keluaran).
header('Location: index.php');
echo "<script>window.location.href = 'index.php';</script>";
exit();
