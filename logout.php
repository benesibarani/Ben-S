<?php
// --- LOGOUT.PHP (VERSI ANTI BLANK PAGE) ---

session_start();

// 1. Kosongkan semua variabel sesi
$_SESSION = array();

// 2. Hapus cookie sesi dari browser (Pembersihan Total)
if (ini_get("session.use_cookies")) {
    $params = session_get_cookie_params();
    setcookie(session_name(), '', time() - 42000,
        $params["path"], $params["domain"],
        $params["secure"], $params["httponly"]
    );
}

// 3. Hancurkan Sesi di Server
session_destroy();

// 4. METODE REDIRECT GANDA (PHP + JAVASCRIPT)
// Ini triknya: Kita cetak script JS dulu, baru header PHP.
// Jika header PHP gagal (blank page), script JS akan otomatis menendang user ke dashboard.

echo "<script>window.location.href = 'dashboard.php';</script>";

// Redirect PHP Standar
header("Location: dashboard.php");
exit();
?>
