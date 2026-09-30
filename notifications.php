<?php
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();
$email = $_SESSION['email'] ?? '';
if (isset($_GET['read'])) {
    $id = (int)$_GET['read'];
    $stmt = $conn->prepare('UPDATE notifications SET is_read=1 WHERE id=? AND recipient_email=?');
    $stmt->bind_param('is', $id, $email); $stmt->execute();
}
if (isset($_GET['read_all'])) {
    $stmt = $conn->prepare('UPDATE notifications SET is_read=1 WHERE recipient_email=?');
    $stmt->bind_param('s', $email); $stmt->execute();
}
$stmt = $conn->prepare('SELECT id, title, message, type, reference_type, reference_id, is_read, created_at FROM notifications WHERE recipient_email=? ORDER BY created_at DESC LIMIT 100');
$stmt->bind_param('s', $email); $stmt->execute(); $notifications = $stmt->get_result();
function n_e($v) { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); }
require_once __DIR__ . '/header.php';
?>
?>
<main class="container py-4" style="max-width:900px"><div class="d-flex justify-content-between align-items-center mb-3"><div><h3 class="mb-1">Notifikasi</h3><p class="text-muted mb-0">Informasi terbaru tentang pengajuan Anda.</p></div><a href="notifications.php?read_all=1" class="btn btn-outline-primary btn-sm">Tandai semua dibaca</a></div><div class="card border-0 shadow-sm"><div class="list-group list-group-flush"><?php if ($notifications->num_rows === 0): ?><div class="p-5 text-center text-muted">Belum ada notifikasi.</div><?php endif; ?><?php while ($n = $notifications->fetch_assoc()): ?><a href="notifications.php?read=<?= (int)$n['id'] ?>" class="list-group-item list-group-item-action p-3 <?= $n['is_read'] ? '' : 'bg-primary-subtle' ?>"><div class="d-flex justify-content-between"><strong><?= n_e($n['title']) ?></strong><small class="text-muted"><?= n_e(date('d/m/Y H:i', strtotime($n['created_at']))) ?></small></div><div class="small mt-1"><?= n_e($n['message']) ?></div><?php if (!$n['is_read']): ?><span class="badge text-bg-primary mt-2">Baru</span><?php endif; ?></a><?php endwhile; ?></div></div></main><?php require_once __DIR__ . '/footer.php'; ?>
