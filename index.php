<?php
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
if (rts_is_logged_in()) { header('Location: dashboard.php'); exit; }
$error = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $username = trim($_POST['username'] ?? '');
    $password = (string)($_POST['password'] ?? '');
    $stmt = $conn->prepare('SELECT id, username, nama_lengkap, email, password, role, salesman, sales_district, status_aktif FROM sales_users WHERE username=? LIMIT 1');
    $stmt->bind_param('s', $username); $stmt->execute(); $user = $stmt->get_result()->fetch_assoc();
    if (!$user || !password_verify($password, $user['password'])) $error = 'Username atau password salah.';
    elseif (($user['status_aktif'] ?? 'Aktif') !== 'Aktif') $error = 'Akun tidak aktif. Hubungi Admin.';
    else {
        session_regenerate_id(true);
        $_SESSION['user_id'] = $user['id']; $_SESSION['username'] = $user['username']; $_SESSION['nama'] = $user['nama_lengkap']; $_SESSION['email'] = $user['email']; $_SESSION['role'] = strtoupper($user['role']); $_SESSION['salesman'] = $user['salesman'] ?? ''; $_SESSION['sales_district'] = $user['sales_district'] ?? ''; $_SESSION['is_logged_in'] = true;
        header('Location: dashboard.php'); exit;
    }
}
?><!doctype html><html lang="id"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Login - RTS Panel By Bene</title><link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet"></head><body class="bg-light"><main class="min-vh-100 d-flex align-items-center justify-content-center p-3"><div class="card border-0 shadow-sm p-4" style="max-width:420px;width:100%"><div class="text-center mb-4"><img src="assets/brand/rts-panel-logo.png" alt="RTS Panel By Bene" style="max-width:260px;width:100%;height:auto"><p class="text-muted mb-0 mt-2">By Bene</p></div><?php if ($error): ?><div class="alert alert-danger py-2"><?= htmlspecialchars($error) ?></div><?php endif; ?><form method="post"><div class="mb-3"><label class="form-label">Username</label><input name="username" class="form-control form-control-lg" autocomplete="username" required autofocus></div><div class="mb-4"><label class="form-label">Password</label><input type="password" name="password" class="form-control form-control-lg" autocomplete="current-password" required></div><button class="btn btn-primary btn-lg w-100">Masuk</button></form></div></main></body></html>
