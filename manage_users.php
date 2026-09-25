<?php
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();
if (!rts_is_admin()) { http_response_code(403); exit('Akses hanya untuk ADMIN.'); }
$message = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $id = (int)($_POST['id'] ?? 0); $username = trim($_POST['username'] ?? ''); $role = strtoupper(trim($_POST['role'] ?? 'RTS')); $salesman = trim($_POST['salesman'] ?? ''); $district = trim($_POST['sales_district'] ?? ''); $status = $_POST['status_aktif'] === 'Nonaktif' ? 'Nonaktif' : 'Aktif'; $password = (string)($_POST['password'] ?? '');
    $roles = ['ADMIN','ASS','WSS','SMST','RTS','TF'];
    if ($username === '' || !in_array($role, $roles, true)) $message = 'Username dan role wajib diisi dengan benar.';
    else {
        $duplicate = $conn->prepare('SELECT id FROM sales_users WHERE username=? AND id<>? LIMIT 1'); $duplicate->bind_param('si', $username, $id); $duplicate->execute();
        if ($duplicate->get_result()->num_rows) $message = 'Username sudah digunakan.';
        else {
            if ($password !== '') { $hash = password_hash($password, PASSWORD_DEFAULT); $stmt = $conn->prepare('UPDATE sales_users SET username=?, role=?, salesman=?, sales_district=?, status_aktif=?, password=? WHERE id=?'); $stmt->bind_param('ssssssi', $username, $role, $salesman, $district, $status, $hash, $id); }
            else { $stmt = $conn->prepare('UPDATE sales_users SET username=?, role=?, salesman=?, sales_district=?, status_aktif=? WHERE id=?'); $stmt->bind_param('sssssi', $username, $role, $salesman, $district, $status, $id); }
            $message = $stmt->execute() ? 'User berhasil diperbarui.' : 'User gagal diperbarui.';
        }
    }
}
$users = $conn->query('SELECT id, username, nama_lengkap, email, role, salesman, sales_district, status_aktif FROM sales_users ORDER BY nama_lengkap');
function u_e($v) { return htmlspecialchars((string)$v, ENT_QUOTES, 'UTF-8'); }
?>require_once __DIR__ . '/header.php';
?>
<main class="container-fluid py-4"><h3>Kelola User</h3><p class="text-muted">ADMIN mengatur username, role, salesman, district, dan status akun.</p><?php if ($message): ?><div class="alert alert-info"><?= u_e($message) ?></div><?php endif; ?><div class="card border-0 shadow-sm"><div class="table-responsive"><table class="table table-hover align-middle mb-0"><thead class="table-light"><tr><th>Nama</th><th>Username</th><th>Email</th><th>Role</th><th>Salesman</th><th>District</th><th>Status</th><th>Aksi</th></tr></thead><tbody><?php while ($u=$users->fetch_assoc()): ?><tr><td><?= u_e($u['nama_lengkap']) ?></td><td><?= u_e($u['username'] ?: '-') ?></td><td><?= u_e($u['email']) ?></td><td><span class="badge text-bg-primary"><?= u_e(strtoupper($u['role'])) ?></span></td><td><?= u_e($u['salesman']) ?></td><td><?= u_e($u['sales_district'] ?: 'Semua') ?></td><td><?= u_e($u['status_aktif']) ?></td><td><button class="btn btn-sm btn-outline-primary" data-bs-toggle="modal" data-bs-target="#edit<?= (int)$u['id'] ?>">Edit</button></td></tr><div class="modal fade" id="edit<?= (int)$u['id'] ?>" tabindex="-1"><div class="modal-dialog"><div class="modal-content"><form method="post"><div class="modal-header"><h5 class="modal-title">Edit <?= u_e($u['nama_lengkap']) ?></h5><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div><div class="modal-body"><input type="hidden" name="id" value="<?= (int)$u['id'] ?>"><label class="form-label">Username</label><input name="username" class="form-control mb-2" value="<?= u_e($u['username']) ?>" required><label class="form-label">Role</label><select name="role" class="form-select mb-2"><?php foreach(['ADMIN','ASS','WSS','SMST','RTS','TF'] as $r): ?><option <?= strtoupper($u['role'])===$r?'selected':'' ?>><?= $r ?></option><?php endforeach; ?></select><label class="form-label">Salesman</label><input name="salesman" class="form-control mb-2" value="<?= u_e($u['salesman']) ?>"><label class="form-label">Sales District</label><input name="sales_district" class="form-control mb-2" value="<?= u_e($u['sales_district']) ?>" placeholder="Kosongkan untuk semua district"><label class="form-label">Status</label><select name="status_aktif" class="form-select mb-2"><option <?= $u['status_aktif']==='Aktif'?'selected':'' ?>>Aktif</option><option <?= $u['status_aktif']==='Nonaktif'?'selected':'' ?>>Nonaktif</option></select><label class="form-label">Password Baru</label><input type="password" name="password" class="form-control" placeholder="Kosongkan jika tidak diganti"></div><div class="modal-footer"><button class="btn btn-primary">Simpan</button></div></form></div></div></div><?php endwhile; ?></tbody></table></div></div></main><script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script><?php require_once __DIR__ . '/footer.php'; ?>
