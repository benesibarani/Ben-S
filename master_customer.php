<?php
// RTS Panel - Master Customer
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();

$role = rts_current_role();
$all_area = rts_can_see_all_customers();
$search = trim($_GET['q'] ?? '');
$tipe = strtoupper(trim($_GET['tipe'] ?? ''));
$status = trim($_GET['status'] ?? '');
$district = trim($_GET['district'] ?? '');
$page = max(1, (int)($_GET['page'] ?? 1));
$limit = 25;
$offset = ($page - 1) * $limit;

$where = [];
$params = [];
$types = '';
if ($search !== '') {
    $where[] = '(nama_toko LIKE ? OR id_customer LIKE ? OR salesman LIKE ?)';
    $like = "%{$search}%";
    $params[] = $like; $params[] = $like; $params[] = $like;
    $types .= 'sss';
}
if (in_array($tipe, ['REGULER', 'GSP'], true)) { $where[] = 'tipe_customer = ?'; $params[] = $tipe; $types .= 's'; }
if ($status !== '') { $where[] = 'status_aktif = ?'; $params[] = $status; $types .= 's'; }
if ($district !== '') { $where[] = 'sales_district = ?'; $params[] = $district; $types .= 's'; }
if (!$all_area) {
    $where[] = 'salesman = ?';
    $params[] = rts_current_salesman();
    $types .= 's';
}
$where_sql = $where ? ' WHERE ' . implode(' AND ', $where) : '';

// Download CSV mengikuti filter dan hak akses user yang sedang login.
if (($_GET['export'] ?? '') === 'csv') {
    $export = $conn->prepare("SELECT id_customer, nama_toko, tipe_customer, salesman, sales_district, alamat, kunjungan, hari, latitude, longitude, status_aktif FROM master_toko{$where_sql} ORDER BY nama_toko ASC");
    if ($types !== '') $export->bind_param($types, ...$params);
    $export->execute();
    $result = $export->get_result();
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="master_customer_' . date('Ymd_His') . '.csv"');
    $out = fopen('php://output', 'w');
    fputcsv($out, ['ID Customer', 'Nama Toko', 'Tipe Customer', 'Salesman', 'District', 'Alamat', 'Kunjungan', 'Hari', 'Latitude', 'Longitude', 'Status']);
    while ($row = $result->fetch_assoc()) fputcsv($out, $row);
    fclose($out);
    exit;
}

$count = $conn->prepare("SELECT COUNT(*) total FROM master_toko{$where_sql}");
if ($types !== '') $count->bind_param($types, ...$params);
$count->execute();
$total = (int)$count->get_result()->fetch_assoc()['total'];

$sql = "SELECT id, nama_toko, id_customer, tipe_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif FROM master_toko{$where_sql} ORDER BY nama_toko ASC LIMIT ? OFFSET ?";
$stmt = $conn->prepare($sql);
$list_params = $params; $list_types = $types . 'ii';
$list_params[] = $limit; $list_params[] = $offset;
$stmt->bind_param($list_types, ...$list_params);
$stmt->execute();
$customers = $stmt->get_result();
$pages = max(1, (int)ceil($total / $limit));

function master_url(array $extra = []): string {
    return 'master_customer.php?' . http_build_query(array_merge($_GET, $extra));
}
require_once __DIR__ . '/header.php';
?>

<nav class="navbar bg-white border-bottom"><div class="container-fluid"><strong class="text-primary">RTS PANEL</strong><span class="small text-muted"><?= htmlspecialchars($role) ?> · <?= htmlspecialchars($_SESSION['nama'] ?? '') ?></span></div></nav>
<main class="container-fluid py-4"><div class="d-flex justify-content-between align-items-center mb-3"><div><h3 class="mb-1">Master Customer</h3><p class="text-muted mb-0">Total data: <?= number_format($total) ?></p></div><a class="btn btn-outline-success" href="<?= htmlspecialchars(master_url(['export' => 'csv'])) ?>">Download CSV</a></div>
<form class="card card-body border-0 shadow-sm mb-3"><div class="row g-2"><div class="col-lg-4"><input class="form-control" name="q" value="<?= htmlspecialchars($search) ?>" placeholder="Cari nama toko, ID, atau salesman"></div><div class="col-md-3 col-lg-2"><select name="tipe" class="form-select"><option value="">Semua Tipe</option><option value="REGULER" <?= $tipe==='REGULER'?'selected':'' ?>>Reguler</option><option value="GSP" <?= $tipe==='GSP'?'selected':'' ?>>GSP</option></select></div><div class="col-md-3 col-lg-2"><select name="status" class="form-select"><option value="">Semua Status</option><option value="Aktif" <?= $status==='Aktif'?'selected':'' ?>>Aktif</option><option value="Nonaktif" <?= $status==='Nonaktif'?'selected':'' ?>>Nonaktif</option></select></div><div class="col-md-3 col-lg-2"><input class="form-control" name="district" value="<?= htmlspecialchars($district) ?>" placeholder="District"></div><div class="col-md-3 col-lg-2 d-grid"><button class="btn btn-primary">Tampilkan</button></div></div></form>
<div class="card border-0 shadow-sm"><div class="table-responsive"><table class="table table-hover align-middle mb-0"><thead class="table-light"><tr><th>ID</th><th>Toko</th><th>Tipe</th><th>Salesman</th><th>District</th><th>Alamat</th><th>Status</th><th>Maps</th><?php if (rts_is_approver()): ?><th>Aksi</th><?php endif; ?></tr></thead><tbody>
<?php if ($customers->num_rows === 0): ?><tr><td colspan="<?= rts_is_approver() ? 9 : 8 ?>" class="text-center text-muted py-5">Data customer tidak ditemukan.</td></tr><?php endif; while ($row = $customers->fetch_assoc()): ?><tr><td><?= htmlspecialchars($row['id_customer'] ?? '') ?></td><td><strong><?= htmlspecialchars($row['nama_toko'] ?? '') ?></strong><br><small class="text-muted"><?= htmlspecialchars($row['hari'] ?? '') ?></small></td><td><span class="badge <?= ($row['tipe_customer'] ?? '') === 'GSP' ? 'text-bg-warning' : 'text-bg-secondary' ?>"><?= htmlspecialchars($row['tipe_customer'] ?? 'REGULER') ?></span></td><td><?= htmlspecialchars($row['salesman'] ?? '') ?></td><td><?= htmlspecialchars($row['sales_district'] ?? '') ?></td><td><?= htmlspecialchars($row['alamat'] ?? '') ?></td><td><span class="badge <?= ($row['status_aktif'] ?? '') === 'Aktif' ? 'text-bg-success' : 'text-bg-danger' ?>"><?= htmlspecialchars($row['status_aktif'] ?? '') ?></span></td><td><?php if ($row['latitude'] !== null && $row['longitude'] !== null && $row['latitude'] !== '' && $row['longitude'] !== ''): ?><a target="_blank" href="https://www.openstreetmap.org/?mlat=<?= rawurlencode($row['latitude']) ?>&mlon=<?= rawurlencode($row['longitude']) ?>#map=18/<?= rawurlencode($row['latitude']) ?>/<?= rawurlencode($row['longitude']) ?>" class="btn btn-sm btn-outline-primary">Buka</a><?php else: ?>-<?php endif; ?></td><?php if (rts_is_approver()): ?><td><a href="edit_customer.php?id=<?= rawurlencode($row['id_customer']) ?>" class="btn btn-sm btn-outline-secondary">Edit</a></td><?php endif; ?></tr><?php endwhile; ?></tbody></table></div></div>
<?php if ($pages > 1): ?><nav class="mt-3"><ul class="pagination"><li class="page-item <?= $page<=1?'disabled':'' ?>"><a class="page-link" href="<?= htmlspecialchars(master_url(['page'=>max(1,$page-1)])) ?>">Sebelumnya</a></li><li class="page-item disabled"><span class="page-link">Halaman <?= $page ?> dari <?= $pages ?></span></li><li class="page-item <?= $page>=$pages?'disabled':'' ?>"><a class="page-link" href="<?= htmlspecialchars(master_url(['page'=>min($pages,$page+1)])) ?>">Berikutnya</a></li></ul></nav><?php endif; ?></main><?php require_once __DIR__ . '/footer.php'; ?>
