<?php
// =============================================================================
// RTS Panel - Master Customer
//
// Aturan cakupan data (disamakan dengan aplikasi Android):
//   ADMIN, ASS, WSS, SMST : semua district
//   RTS, TF               : sesuai Sales District akun
//   RTS/TF tanpa district : memakai salesman sebagai pengaman
//   RTS/TF tanpa keduanya : tidak menampilkan data
//
// Perbandingan district memakai UPPER(TRIM(...)) agar tidak terpengaruh
// huruf besar/kecil antara master_toko dan sales_users.
// =============================================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();

$role = strtoupper((string) rts_current_role());

// --- Penentuan cakupan data ------------------------------------------------
$role_semua_district = ['ADMIN', 'ASS', 'WSS', 'SMST'];
$all_area = in_array($role, $role_semua_district, true);

$my_district = trim((string) ($_SESSION['sales_district'] ?? ''));
$my_salesman = trim((string) rts_current_salesman());

// Keterangan cakupan untuk ditampilkan di halaman.
if ($all_area) {
    $cakupan_label = 'Semua district';
    $cakupan_jenis = 'semua';
} elseif ($my_district !== '') {
    $cakupan_label = 'Sales District: ' . $my_district;
    $cakupan_jenis = 'district';
} elseif ($my_salesman !== '') {
    $cakupan_label = 'Salesman: ' . $my_salesman;
    $cakupan_jenis = 'salesman';
} else {
    $cakupan_label = 'Belum ada penugasan district';
    $cakupan_jenis = 'kosong';
}

// --- Filter dari pengguna --------------------------------------------------
$search = trim($_GET['q'] ?? '');
$tipe = strtoupper(trim($_GET['tipe'] ?? ''));
$status = trim($_GET['status'] ?? '');
$district = trim($_GET['district'] ?? '');
$page = max(1, (int) ($_GET['page'] ?? 1));
$limit = 25;
$offset = ($page - 1) * $limit;

$where = [];
$params = [];
$types = '';

if ($search !== '') {
    $where[] = '(nama_toko LIKE ? OR id_customer LIKE ? OR salesman LIKE ?)';
    $like = "%{$search}%";
    $params[] = $like;
    $params[] = $like;
    $params[] = $like;
    $types .= 'sss';
}

if (in_array($tipe, ['REGULER', 'GSP'], true)) {
    $where[] = 'tipe_customer = ?';
    $params[] = $tipe;
    $types .= 's';
}

if ($status !== '') {
    $where[] = 'status_aktif = ?';
    $params[] = $status;
    $types .= 's';
}

// Filter district dari form. Untuk RTS/TF, pilihan ini hanya mempersempit
// district miliknya sendiri, karena batas utamanya dipasang di bawah.
if ($district !== '') {
    $where[] = 'UPPER(TRIM(sales_district)) = ?';
    $params[] = strtoupper($district);
    $types .= 's';
}

// --- Batas akses sesuai role ----------------------------------------------
if ($cakupan_jenis === 'district') {
    $where[] = 'UPPER(TRIM(sales_district)) = ?';
    $params[] = strtoupper($my_district);
    $types .= 's';
} elseif ($cakupan_jenis === 'salesman') {
    $where[] = 'salesman = ?';
    $params[] = $my_salesman;
    $types .= 's';
} elseif ($cakupan_jenis === 'kosong') {
    $where[] = '1 = 0';
}

$where_sql = $where ? ' WHERE ' . implode(' AND ', $where) : '';

// --- Download CSV mengikuti filter dan hak akses ---------------------------
if (($_GET['export'] ?? '') === 'csv') {
    $export = $conn->prepare("SELECT id_customer, nama_toko, tipe_customer, salesman, sales_district, alamat, kunjungan, hari, latitude, longitude, status_aktif FROM master_toko{$where_sql} ORDER BY nama_toko ASC");
    if ($types !== '') {
        $export->bind_param($types, ...$params);
    }
    $export->execute();
    $result = $export->get_result();
    header('Content-Type: text/csv; charset=utf-8');
    header('Content-Disposition: attachment; filename="master_customer_' . date('Ymd_His') . '.csv"');
    $out = fopen('php://output', 'w');
    fputcsv($out, ['ID Customer', 'Nama Toko', 'Tipe Customer', 'Salesman', 'District', 'Alamat', 'Kunjungan', 'Hari', 'Latitude', 'Longitude', 'Status']);
    while ($row = $result->fetch_assoc()) {
        fputcsv($out, $row);
    }
    fclose($out);
    exit;
}

$count = $conn->prepare("SELECT COUNT(*) total FROM master_toko{$where_sql}");
if ($types !== '') {
    $count->bind_param($types, ...$params);
}
$count->execute();
$total = (int) $count->get_result()->fetch_assoc()['total'];

$sql = "SELECT id, nama_toko, id_customer, tipe_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif FROM master_toko{$where_sql} ORDER BY nama_toko ASC LIMIT ? OFFSET ?";
$stmt = $conn->prepare($sql);
$list_params = $params;
$list_types = $types . 'ii';
$list_params[] = $limit;
$list_params[] = $offset;
$stmt->bind_param($list_types, ...$list_params);
$stmt->execute();
$customers = $stmt->get_result();
$pages = max(1, (int) ceil($total / $limit));

function master_url(array $extra = []): string
{
    return 'master_customer.php?' . http_build_query(array_merge($_GET, $extra));
}

require_once __DIR__ . '/header.php';
?>

<nav class="navbar bg-white border-bottom">
    <div class="container-fluid">
        <strong class="text-primary">RTS PANEL</strong>
        <span class="small text-muted"><?= htmlspecialchars($role) ?> · <?= htmlspecialchars($_SESSION['nama'] ?? '') ?></span>
    </div>
</nav>

<main class="container-fluid py-4">
    <div class="d-flex justify-content-between align-items-center mb-3">
        <div>
            <h3 class="mb-1">Master Customer</h3>
            <p class="text-muted mb-0">
                Total data: <?= number_format($total) ?>
                · Cakupan: <strong><?= htmlspecialchars($cakupan_label) ?></strong>
            </p>
        </div>
        <a class="btn btn-outline-success" href="<?= htmlspecialchars(master_url(['export' => 'csv'])) ?>">Download CSV</a>
    </div>

    <?php if ($cakupan_jenis === 'district'): ?>
        <div class="alert alert-primary d-flex align-items-center py-2" role="alert">
            <i class="bi bi-map me-2"></i>
            <div class="small">
                Anda melihat customer pada <strong><?= htmlspecialchars($my_district) ?></strong>.
                Hubungi Admin bila ada customer yang belum terlihat.
            </div>
        </div>
    <?php elseif ($cakupan_jenis === 'salesman'): ?>
        <div class="alert alert-primary d-flex align-items-center py-2" role="alert">
            <i class="bi bi-person me-2"></i>
            <div class="small">
                Sales District belum diisi pada akun Anda, sehingga sementara data dibatasi
                ke salesman <strong><?= htmlspecialchars($my_salesman) ?></strong>.
            </div>
        </div>
    <?php elseif ($cakupan_jenis === 'kosong'): ?>
        <div class="alert alert-warning py-2" role="alert">
            <div class="small">
                Akun Anda belum memiliki Sales District maupun Salesman.
                Hubungi Admin agar data customer dapat ditampilkan.
            </div>
        </div>
    <?php endif; ?>

    <form class="card card-body border-0 shadow-sm mb-3">
        <div class="row g-2">
            <div class="col-lg-4">
                <input class="form-control" name="q" value="<?= htmlspecialchars($search) ?>" placeholder="Cari nama toko, ID, atau salesman">
            </div>
            <div class="col-md-3 col-lg-2">
                <select name="tipe" class="form-select">
                    <option value="">Semua Tipe</option>
                    <option value="REGULER" <?= $tipe === 'REGULER' ? 'selected' : '' ?>>Reguler</option>
                    <option value="GSP" <?= $tipe === 'GSP' ? 'selected' : '' ?>>GSP</option>
                </select>
            </div>
            <div class="col-md-3 col-lg-2">
                <select name="status" class="form-select">
                    <option value="">Semua Status</option>
                    <option value="Aktif" <?= $status === 'Aktif' ? 'selected' : '' ?>>Aktif</option>
                    <option value="Nonaktif" <?= $status === 'Nonaktif' ? 'selected' : '' ?>>Nonaktif</option>
                </select>
            </div>

            <?php if ($all_area): ?>
                <div class="col-md-3 col-lg-2">
                    <input class="form-control" name="district" value="<?= htmlspecialchars($district) ?>" placeholder="District">
                </div>
            <?php else: ?>
                <div class="col-md-3 col-lg-2">
                    <input class="form-control" value="<?= htmlspecialchars($cakupan_label) ?>" readonly title="Cakupan data mengikuti akun Anda">
                </div>
            <?php endif; ?>

            <div class="col-md-3 col-lg-2 d-grid">
                <button class="btn btn-primary">Tampilkan</button>
            </div>
        </div>
    </form>

    <div class="card border-0 shadow-sm">
        <div class="table-responsive">
            <table class="table table-hover align-middle mb-0">
                <thead class="table-light">
                    <tr>
                        <th>ID</th>
                        <th>Toko</th>
                        <th>Tipe</th>
                        <th>Salesman</th>
                        <th>District</th>
                        <th>Alamat</th>
                        <th>Status</th>
                        <th>Maps</th>
                        <?php if (rts_is_approver()): ?><th>Aksi</th><?php endif; ?>
                    </tr>
                </thead>
                <tbody>
                <?php if ($customers->num_rows === 0): ?>
                    <tr>
                        <td colspan="<?= rts_is_approver() ? 9 : 8 ?>" class="text-center text-muted py-5">
                            Data customer tidak ditemukan.
                        </td>
                    </tr>
                <?php endif; ?>
                <?php while ($row = $customers->fetch_assoc()): ?>
                    <tr>
                        <td><?= htmlspecialchars($row['id_customer'] ?? '') ?></td>
                        <td>
                            <strong><?= htmlspecialchars($row['nama_toko'] ?? '') ?></strong><br>
                            <small class="text-muted"><?= htmlspecialchars($row['hari'] ?? '') ?></small>
                        </td>
                        <td>
                            <span class="badge <?= ($row['tipe_customer'] ?? '') === 'GSP' ? 'text-bg-warning' : 'text-bg-secondary' ?>">
                                <?= htmlspecialchars($row['tipe_customer'] ?? 'REGULER') ?>
                            </span>
                        </td>
                        <td><?= htmlspecialchars($row['salesman'] ?? '') ?></td>
                        <td><?= htmlspecialchars($row['sales_district'] ?? '') ?></td>
                        <td><?= htmlspecialchars($row['alamat'] ?? '') ?></td>
                        <td>
                            <span class="badge <?= ($row['status_aktif'] ?? '') === 'Aktif' ? 'text-bg-success' : 'text-bg-danger' ?>">
                                <?= htmlspecialchars($row['status_aktif'] ?? '') ?>
                            </span>
                        </td>
                        <td>
                            <?php if (($row['latitude'] ?? '') !== '' && ($row['longitude'] ?? '') !== '' && $row['latitude'] !== null && $row['longitude'] !== null): ?>
                                <a target="_blank"
                                   href="https://www.google.com/maps/search/?api=1&query=<?= rawurlencode($row['latitude']) ?>,<?= rawurlencode($row['longitude']) ?>"
                                   class="btn btn-sm btn-outline-primary">Buka</a>
                            <?php else: ?>
                                -
                            <?php endif; ?>
                        </td>
                        <?php if (rts_is_approver()): ?>
                            <td>
                                <a href="edit_customer.php?id=<?= rawurlencode($row['id_customer']) ?>" class="btn btn-sm btn-outline-secondary">Edit</a>
                            </td>
                        <?php endif; ?>
                    </tr>
                <?php endwhile; ?>
                </tbody>
            </table>
        </div>
    </div>

    <?php if ($pages > 1): ?>
        <nav class="mt-3">
            <ul class="pagination">
                <li class="page-item <?= $page <= 1 ? 'disabled' : '' ?>">
                    <a class="page-link" href="<?= htmlspecialchars(master_url(['page' => max(1, $page - 1)])) ?>">Sebelumnya</a>
                </li>
                <li class="page-item disabled">
                    <span class="page-link">Halaman <?= $page ?> dari <?= $pages ?></span>
                </li>
                <li class="page-item <?= $page >= $pages ? 'disabled' : '' ?>">
                    <a class="page-link" href="<?= htmlspecialchars(master_url(['page' => min($pages, $page + 1)])) ?>">Berikutnya</a>
                </li>
            </ul>
        </nav>
    <?php endif; ?>
</main>

<?php require_once __DIR__ . '/footer.php'; ?>
