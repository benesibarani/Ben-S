<?php
// =============================================================================
// RTS Panel - Dashboard
//
// Perbaikan: kartu ringkasan (Total Customer, Customer Aktif, Total GSP,
// Pengajuan Pending) kini dihitung mengikuti cakupan role:
//
//   ADMIN, ASS, WSS, SMST : semua district
//   RTS, TF               : sesuai Sales District akun
//   RTS/TF tanpa district : memakai salesman sebagai pengaman
//   RTS/TF tanpa keduanya : angka ditampilkan 0 dan ada peringatan
//
// Monitoring Stok Kritis juga mengikuti cakupan yang sama supaya konsisten
// dengan Master Customer.
//
// Perbaikan ERR_TOO_MANY_REDIRECTS: penjagaan sesi tidak lagi memakai
// rts_require_login() dari auth.php (fungsi itu mengalihkan ke dashboard.php
// sehingga berputar), tetapi mengalihkan pengunjung yang belum login ke
// halaman login index.php. Lihat PENGAMAN 1 di bawah.
// =============================================================================

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';

/* ---------------------------------------------------------------------------
 * PENGAMAN 1: penjagaan sesi  (perbaikan ERR_TOO_MANY_REDIRECTS)
 *
 * Halaman ini SENGAJA TIDAK memakai rts_require_login() dari auth.php.
 *
 * Sebabnya: fungsi tersebut mengarahkan pengunjung yang belum login ke
 * dashboard.php, padahal halaman inilah (dashboard.php) yang sedang diperiksa.
 * Akibatnya browser mengikuti pengalihan yang berputar tanpa henti:
 *
 *     dashboard.php -> dashboard.php -> dashboard.php -> ...
 *     yang di browser muncul: ERR_TOO_MANY_REDIRECTS
 *
 * Gejala ini paling mudah terlihat setelah tombol Keluar ditekan, karena pada
 * saat itu sesi sudah dihapus sehingga dashboard.php menolak menampilkan apa
 * pun dan mengalihkan lagi.
 *
 * Sekarang pengunjung yang belum login diarahkan ke index.php (halaman login
 * website), sehingga alurnya berakhir normal: halaman login tampil.
 * ------------------------------------------------------------------------ */

if (session_status() !== PHP_SESSION_ACTIVE) {
    session_start();
}

if (!function_exists('rts_dashboard_sudah_login')) {
    /**
     * Dianggap sudah login bila salah satu penanda sesi berikut ada.
     * Daftar ini mencakup penanda dari halaman login index.php (user_id,
     * username, nama, is_logged_in) maupun dari login lama dashboard.php
     * (user_id, nama, is_logged_in), jadi cocok untuk semua akun.
     */
    function rts_dashboard_sudah_login(): bool
    {
        foreach (['is_logged_in', 'user_id', 'username', 'nama'] as $kunci) {
            if (!empty($_SESSION[$kunci])) {
                return true;
            }
        }

        return false;
    }
}

if (!function_exists('rts_dashboard_jaga_sesi')) {
    /**
     * Mengalihkan ke halaman login index.php bila belum login.
     * TIDAK boleh mengarah ke dashboard.php sendiri, karena akan berputar.
     */
    function rts_dashboard_jaga_sesi(): void
    {
        if (rts_dashboard_sudah_login()) {
            return;
        }

        header('Location: index.php');
        exit;
    }
}

if (!function_exists('rts_current_role')) {
    function rts_current_role(): string
    {
        return (string) ($_SESSION['role'] ?? '');
    }
}

if (!function_exists('rts_current_salesman')) {
    function rts_current_salesman(): string
    {
        return (string) ($_SESSION['salesman'] ?? '');
    }
}

if (!function_exists('rts_is_approver')) {
    function rts_is_approver(): bool
    {
        return in_array(strtoupper(rts_current_role()), ['ADMIN', 'ASS'], true);
    }
}

/**
 * Membaca nilai pertama yang terisi dari beberapa kemungkinan nama kunci
 * session, karena setiap halaman website bisa memakai nama yang berbeda.
 */
function rts_dash_nilai(array $kunci, string $bawaan = ''): string
{
    foreach ($kunci as $satu) {
        if (isset($_SESSION[$satu])) {
            $nilai = trim((string) $_SESSION[$satu]);

            if ($nilai !== '') {
                return $nilai;
            }
        }
    }

    return $bawaan;
}

rts_dashboard_jaga_sesi();

$nama_user = rts_dash_nilai(['nama', 'nama_lengkap', 'username', 'name']);
$my_district = rts_dash_nilai(['sales_district', 'sales_distric', 'district', 'zona']);
$my_salesman = trim((string) rts_current_salesman());
$my_email = rts_dash_nilai(['email', 'sales_email', 'username']);
$role = strtoupper(rts_dash_nilai(['role', 'user_role']));

/* ---------------------------------------------------------------------------
 * PENGAMAN 2: identitas dari database
 *
 * Bila session tidak menyimpan role / salesman / district, data akun diambil
 * langsung dari tabel sales_users memakai username. Bila tidak berhasil,
 * halaman tetap tampil dengan angka 0 dan kotak peringatan.
 * ------------------------------------------------------------------------ */

if ($role === '' || $my_salesman === '' || $my_district === '') {
    $username_session = rts_dash_nilai(['username', 'user', 'username_login']);

    if ($username_session !== '' && isset($conn) && $conn instanceof mysqli) {
        try {
            $stmt_akun = $conn->prepare(
                'SELECT role, nama_lengkap, salesman, sales_district
                 FROM sales_users WHERE username = ? LIMIT 1'
            );

            if ($stmt_akun) {
                $stmt_akun->bind_param('s', $username_session);
                $stmt_akun->execute();
                $hasil_akun = $stmt_akun->get_result();
                $akun = $hasil_akun ? $hasil_akun->fetch_assoc() : null;
                $stmt_akun->close();

                if ($akun) {
                    if ($role === '') {
                        $role = strtoupper(trim((string) ($akun['role'] ?? '')));
                    }
                    if ($nama_user === '') {
                        $nama_user = trim((string) ($akun['nama_lengkap'] ?? ''));
                    }
                    if ($my_salesman === '') {
                        $my_salesman = trim((string) ($akun['salesman'] ?? ''));
                    }
                    if ($my_district === '') {
                        $my_district = trim((string) ($akun['sales_district'] ?? ''));
                    }
                }
            }
        } catch (\Throwable $e) {
            // struktur tabel berbeda, cukup diabaikan
        }
    }
}

$is_approver = in_array($role, ['ADMIN', 'ASS'], true);

/* ---------------------------------------------------- penentuan cakupan data */

$role_semua_district = ['ADMIN', 'ASS', 'WSS', 'SMST'];
$all_area = in_array($role, $role_semua_district, true);

if ($all_area) {
    $cakupan_jenis = 'semua';
    $cakupan_label = 'Semua district';
} elseif ($my_district !== '') {
    $cakupan_jenis = 'district';
    $cakupan_label = 'Sales District: ' . $my_district;
} elseif ($my_salesman !== '') {
    $cakupan_jenis = 'salesman';
    $cakupan_label = 'Salesman: ' . $my_salesman;
} else {
    $cakupan_jenis = 'kosong';
    $cakupan_label = 'Belum ada penugasan district';
}

/**
 * Menghitung jumlah baris master_toko sesuai cakupan.
 */
function rts_hitung_customer(mysqli $conn, string $cakupan_jenis, string $district, string $salesman, string $syarat_tambahan = ''): int
{
    $where = [];
    $params = [];
    $types = '';

    if ($syarat_tambahan !== '') {
        $where[] = $syarat_tambahan;
    }

    if ($cakupan_jenis === 'district') {
        $where[] = 'UPPER(TRIM(sales_district)) = ?';
        $params[] = strtoupper($district);
        $types .= 's';
    } elseif ($cakupan_jenis === 'salesman') {
        $where[] = 'salesman = ?';
        $params[] = $salesman;
        $types .= 's';
    } elseif ($cakupan_jenis === 'kosong') {
        $where[] = '1 = 0';
    }

    $sql = 'SELECT COUNT(*) AS total FROM master_toko'
        . ($where ? (' WHERE ' . implode(' AND ', $where)) : '');

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return 0;
    }

    if ($params) {
        $stmt->bind_param($types, ...$params);
    }

    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    return $baris ? (int) $baris['total'] : 0;
}

$total_customer = rts_hitung_customer($conn, $cakupan_jenis, $my_district, $my_salesman);
$total_aktif = rts_hitung_customer($conn, $cakupan_jenis, $my_district, $my_salesman, "status_aktif = 'Aktif'");
$total_gsp = rts_hitung_customer($conn, $cakupan_jenis, $my_district, $my_salesman, "tipe_customer = 'GSP'");

/* ------------------------------------------------------- pengajuan pending */

$pending_toko = 0;
$pending_gsp = 0;

if ($all_area) {
    // ADMIN, ASS, WSS, SMST melihat seluruh pengajuan.
    $q1 = $conn->query("SELECT COUNT(*) AS total FROM pengajuan_sales WHERE status_approval = 'Pending'");
    $pending_toko = $q1 ? (int) $q1->fetch_assoc()['total'] : 0;

    $q2 = $conn->query("SELECT COUNT(*) AS total FROM pengajuan_gsp WHERE status_approval = 'Pending'");
    $pending_gsp = $q2 ? (int) $q2->fetch_assoc()['total'] : 0;
} else {
    // RTS dan TF hanya melihat pengajuan miliknya sendiri.
    $s1 = $conn->prepare("SELECT COUNT(*) AS total FROM pengajuan_sales WHERE status_approval = 'Pending' AND sales_email = ?");
    if ($s1) {
        $s1->bind_param('s', $my_email);
        $s1->execute();
        $pending_toko = (int) $s1->get_result()->fetch_assoc()['total'];
        $s1->close();
    }

    $s2 = $conn->prepare("SELECT COUNT(*) AS total FROM pengajuan_gsp WHERE status_approval = 'Pending' AND sales_email = ?");
    if ($s2) {
        $s2->bind_param('s', $my_email);
        $s2->execute();
        $pending_gsp = (int) $s2->get_result()->fetch_assoc()['total'];
        $s2->close();
    }
}

$total_pending = $pending_toko + $pending_gsp;

/* ------------------------------------------------- monitoring stok kritis */

$stok_warning = [];
$sql_stok = 'SELECT * FROM stok_gsp';

if ($cakupan_jenis === 'district') {
    $sql_stok .= ' WHERE UPPER(TRIM(zona)) = ?';
} elseif ($cakupan_jenis === 'salesman') {
    $sql_stok .= ' WHERE salesman = ?';
} elseif ($cakupan_jenis === 'kosong') {
    // Tanpa penugasan: tidak ada data yang boleh tampil.
    $sql_stok .= ' WHERE 1 = 0';
}

$sql_stok .= ' ORDER BY nama_toko ASC';

$q_stok = null;

if ($cakupan_jenis === 'district') {
    $stmt_stok = $conn->prepare($sql_stok);
    if ($stmt_stok) {
        $district_upper = strtoupper($my_district);
        $stmt_stok->bind_param('s', $district_upper);
        $stmt_stok->execute();
        $q_stok = $stmt_stok->get_result();
    }
} elseif ($cakupan_jenis === 'salesman') {
    $stmt_stok = $conn->prepare($sql_stok);
    if ($stmt_stok) {
        $stmt_stok->bind_param('s', $my_salesman);
        $stmt_stok->execute();
        $q_stok = $stmt_stok->get_result();
    }
} elseif ($cakupan_jenis === 'semua') {
    $q_stok = $conn->query($sql_stok);
}

$minggu_sekarang = (int) date('W');

if ($q_stok) {
    while ($row = $q_stok->fetch_assoc()) {
        $prod_week = (int) $row['minggu_produksi'];
        $max_week = (int) $row['maksimal_minggu'];
        $umur = $minggu_sekarang - $prod_week;

        if ($umur < 0) {
            $umur += 52;
        }

        $sisa = $max_week - $umur;

        if ($umur >= $max_week || $sisa <= 2) {
            $kategori = ($umur >= $max_week) ? 'BS' : 'WARNING';
            $key = ($row['nama_toko'] ?? '') . '|' . ($row['zona'] ?? '') . '|' . ($row['id_customer'] ?? '') . '|' . ($row['salesman'] ?? '');

            if (!isset($stok_warning[$key])) {
                $stok_warning[$key] = ['bs' => [], 'warning' => []];
            }

            $item = ($row['nama_produk'] ?? '') . ' (' . ($row['jumlah_stok'] ?? 0) . ')';

            if ($kategori === 'BS') {
                $stok_warning[$key]['bs'][] = $item;
            } else {
                $stok_warning[$key]['warning'][] = $item . ' [Sisa ' . $sisa . ' Mg]';
            }
        }
    }
}

require_once __DIR__ . '/header.php';
?>

<!-- KEPALA HALAMAN -->
<div class="card border-0 shadow-sm rounded-4 mb-4" style="background:linear-gradient(135deg,#eaf2ff,#dce9ff);">
    <div class="card-body d-flex align-items-center">
        <div class="me-3 display-6 text-primary"><i class="fa-solid fa-user-circle"></i></div>
        <div class="flex-grow-1">
            <h4 class="mb-1 fw-bold text-dark">Selamat Datang, <?= htmlspecialchars($nama_user) ?>!</h4>
            <p class="mb-0 text-muted small">
                Login sebagai <strong><?= htmlspecialchars($role) ?></strong>
                · Cakupan data: <strong><?= htmlspecialchars($cakupan_label) ?></strong>
            </p>
        </div>
        <a href="master_customer.php" class="btn btn-primary btn-sm d-none d-md-inline-block">
            <i class="fa-solid fa-store me-1"></i> Master Customer
        </a>
    </div>
</div>

<?php if ($cakupan_jenis === 'kosong'): ?>
    <div class="alert alert-warning rounded-4 border-0 shadow-sm">
        <div class="small mb-0">
            Akun Anda belum memiliki <strong>Sales District</strong> maupun <strong>Salesman</strong>.
            Karena itu seluruh angka di bawah ini bernilai 0. Hubungi Admin agar data customer
            dapat ditampilkan.
        </div>
    </div>
<?php elseif ($cakupan_jenis === 'salesman'): ?>
    <div class="alert alert-primary rounded-4 border-0 shadow-sm">
        <div class="small mb-0">
            Sales District belum diisi pada akun Anda, sehingga sementara data dibatasi ke salesman
            <strong><?= htmlspecialchars($my_salesman) ?></strong>.
        </div>
    </div>
<?php endif; ?>

<?php if ($is_approver && $total_pending > 0): ?>
    <div class="card border-0 border-start border-5 border-warning shadow-sm rounded-4 mb-4">
        <div class="card-body d-flex align-items-center">
            <div class="display-6 text-warning me-3"><i class="fa-solid fa-triangle-exclamation"></i></div>
            <div class="flex-grow-1">
                <h5 class="fw-bold text-dark mb-1"><?= number_format($total_pending) ?> Pengajuan Pending</h5>
                <p class="mb-0 text-muted small">
                    Pengajuan toko: <?= number_format($pending_toko) ?> ·
                    Pengajuan GSP: <?= number_format($pending_gsp) ?>.
                    Data lama lebih dari 30 hari dihapus otomatis.
                </p>
            </div>
            <a href="inbox.php" class="btn btn-warning text-dark fw-bold shadow-sm">PROSES</a>
        </div>
    </div>
<?php endif; ?>

<!-- KARTU RINGKASAN -->
<div class="row g-3 mb-4">
    <div class="col-6 col-lg-3">
        <div class="card border-0 shadow-sm rounded-4 h-100">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between mb-2">
                    <span class="text-muted small">Total Customer</span>
                    <span class="text-primary"><i class="fa-solid fa-store"></i></span>
                </div>
                <div class="display-6 fw-bold text-primary"><?= number_format($total_customer) ?></div>
                <div class="small text-muted mt-1"><?= htmlspecialchars($cakupan_label) ?></div>
            </div>
        </div>
    </div>
    <div class="col-6 col-lg-3">
        <div class="card border-0 shadow-sm rounded-4 h-100">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between mb-2">
                    <span class="text-muted small">Customer Aktif</span>
                    <span class="text-success"><i class="fa-solid fa-circle-check"></i></span>
                </div>
                <div class="display-6 fw-bold text-success"><?= number_format($total_aktif) ?></div>
                <div class="small text-muted mt-1">Status aktif pada cakupan ini</div>
            </div>
        </div>
    </div>
    <div class="col-6 col-lg-3">
        <div class="card border-0 shadow-sm rounded-4 h-100">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between mb-2">
                    <span class="text-muted small">Total GSP</span>
                    <span class="text-warning"><i class="fa-solid fa-handshake"></i></span>
                </div>
                <div class="display-6 fw-bold text-warning"><?= number_format($total_gsp) ?></div>
                <div class="small text-muted mt-1">Kategori GSP</div>
            </div>
        </div>
    </div>
    <div class="col-6 col-lg-3">
        <div class="card border-0 shadow-sm rounded-4 h-100">
            <div class="card-body">
                <div class="d-flex align-items-center justify-content-between mb-2">
                    <span class="text-muted small">Pengajuan Pending</span>
                    <span class="text-danger"><i class="fa-solid fa-inbox"></i></span>
                </div>
                <div class="display-6 fw-bold text-danger"><?= number_format($total_pending) ?></div>
                <div class="small text-muted mt-1">
                    <?= $is_approver ? 'Perlu diperiksa' : 'Pengajuan Anda' ?>
                </div>
            </div>
        </div>
    </div>
</div>

<?php
/* ---------------------------------------------------------------------------
 * KARTU PINTASAN ADMIN: VERSI APLIKASI ANDROID
 *
 * Hanya tampil untuk role ADMIN. Kartu ini membaca berkas apk/app_versi.json
 * bila ada, sehingga Admin langsung mengetahui versi mana yang sedang
 * diumumkan ke seluruh tim tanpa membuka halaman app_versi.php lebih dahulu.
 *
 * Halaman pengunggahan APK: app_versi.php (menu "Versi Aplikasi").
 * ------------------------------------------------------------------------ */
if ($role === 'ADMIN'):

    $dash_versi_berkas = __DIR__ . '/apk/app_versi.json';
    $dash_versi = [];

    if (is_file($dash_versi_berkas)) {
        $dash_isi = @file_get_contents($dash_versi_berkas);

        if ($dash_isi !== false) {
            $dash_baca = json_decode($dash_isi, true);

            if (is_array($dash_baca)) {
                $dash_versi = $dash_baca;
            }
        }
    }

    $dash_ada_versi = !empty($dash_versi['version_code']);
?>
<div class="card border-0 shadow-sm rounded-4 mb-4">
    <div class="card-body d-flex align-items-center flex-wrap gap-3">
        <div class="display-6 text-danger"><i class="fa-solid fa-mobile-screen-button"></i></div>
        <div class="flex-grow-1">
            <h6 class="fw-bold text-dark mb-1">Versi Aplikasi Android</h6>
            <?php if ($dash_ada_versi): ?>
                <p class="mb-0 text-muted small">
                    Sedang diumumkan:
                    <strong>versi <?= htmlspecialchars((string)($dash_versi['version_name'] ?? '-')) ?></strong>
                    (kode <?= (int)$dash_versi['version_code'] ?>)
                    &middot; <?= !empty($dash_versi['wajib']) ? 'WAJIB diperbarui' : 'pembaruan pilihan' ?>
                    <?php if (!empty($dash_versi['dipublikasikan'])): ?>
                        &middot; <?= htmlspecialchars((string)$dash_versi['dipublikasikan']) ?>
                    <?php endif; ?>
                </p>
            <?php else: ?>
                <p class="mb-0 text-muted small">
                    Belum ada versi yang diumumkan. Unggah berkas APK terbaru agar
                    aplikasi seluruh tim menawarkan pembaruan otomatis saat dibuka.
                </p>
            <?php endif; ?>
        </div>
        <a href="app_versi.php" class="btn btn-danger btn-sm fw-bold">
            <i class="fa-solid fa-cloud-arrow-up me-1"></i> Kelola Versi Aplikasi
        </a>
    </div>
</div>
<?php endif; ?>

<!-- MONITORING STOK KRITIS -->
<div class="card border-0 shadow-sm rounded-4 mb-4">
    <div class="card-header bg-danger text-white d-flex justify-content-between align-items-center rounded-top-4">
        <h6 class="mb-0 fw-bold"><i class="fa-solid fa-fire me-2"></i> Monitoring Stok Kritis (GSP)</h6>
        <div class="d-flex align-items-center gap-2">
            <span class="badge bg-light text-danger"><?= htmlspecialchars($cakupan_label) ?></span>
            <a href="stokgsp.php" class="btn btn-sm btn-light text-danger fw-bold">Input Data</a>
        </div>
    </div>
    <?php if (empty($stok_warning)): ?>
        <div class="card-body text-center text-muted py-4">
            <i class="fa-solid fa-circle-check fa-3x mb-3 text-success"></i>
            <p class="mb-0">Aman. Tidak ada produk BS atau Warning pada cakupan ini.</p>
        </div>
    <?php else: ?>
        <div class="card-body p-0 table-responsive" style="max-height:400px;">
            <table class="table table-striped table-hover mb-0 small align-middle">
                <thead class="table-light sticky-top">
                    <tr>
                        <th>Outlet</th>
                        <th>Salesman</th>
                        <th class="text-warning">Warning</th>
                        <th class="text-danger">BS (Expired)</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($stok_warning as $key => $data): ?>
                        <?php list($nama_toko, $zona, $id_cust, $nm_sales) = array_pad(explode('|', $key), 4, ''); ?>
                        <tr>
                            <td class="fw-bold">
                                <?= htmlspecialchars($nama_toko) ?><br>
                                <span class="badge bg-light text-dark border">ID: <?= htmlspecialchars($id_cust) ?></span><br>
                                <span class="text-muted"><?= htmlspecialchars($zona) ?></span>
                            </td>
                            <td><?= htmlspecialchars($nm_sales) ?></td>
                            <td>
                                <?php if (empty($data['warning'])): ?>
                                    -
                                <?php else: ?>
                                    <ul class="mb-0 ps-3 text-warning fw-bold">
                                        <?php foreach ($data['warning'] as $item): ?>
                                            <li><?= htmlspecialchars($item) ?></li>
                                        <?php endforeach; ?>
                                    </ul>
                                <?php endif; ?>
                            </td>
                            <td>
                                <?php if (empty($data['bs'])): ?>
                                    -
                                <?php else: ?>
                                    <ul class="mb-0 ps-3 text-danger fw-bold">
                                        <?php foreach ($data['bs'] as $item): ?>
                                            <li><?= htmlspecialchars($item) ?></li>
                                        <?php endforeach; ?>
                                    </ul>
                                <?php endif; ?>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
    <?php endif; ?>
</div>

<!-- PINTASAN MENU -->
<div class="row g-3">
    <div class="col-md-3 col-6">
        <div class="card border-0 shadow-sm rounded-4 h-100 text-center p-3">
            <div class="display-6 text-primary mb-2"><i class="fa-solid fa-handshake"></i></div>
            <h6 class="fw-bold mb-0">GSP Baru</h6>
            <a href="gsp.php" class="stretched-link"></a>
        </div>
    </div>
    <div class="col-md-3 col-6">
        <div class="card border-0 shadow-sm rounded-4 h-100 text-center p-3">
            <div class="display-6 text-success mb-2"><i class="fa-solid fa-store"></i></div>
            <h6 class="fw-bold mb-0">Pengajuan Toko</h6>
            <a href="pengajuan_toko.php" class="stretched-link"></a>
        </div>
    </div>
    <div class="col-md-3 col-6">
        <div class="card border-0 shadow-sm rounded-4 h-100 text-center p-3">
            <div class="display-6 text-danger mb-2"><i class="fa-solid fa-boxes"></i></div>
            <h6 class="fw-bold mb-0">Cek Stok</h6>
            <a href="stokgsp.php" class="stretched-link"></a>
        </div>
    </div>
    <div class="col-md-3 col-6">
        <div class="card border-0 shadow-sm rounded-4 h-100 text-center p-3">
            <div class="display-6 text-warning mb-2"><i class="fa-solid fa-inbox"></i></div>
            <h6 class="fw-bold mb-0">Inbox</h6>
            <a href="inbox.php" class="stretched-link"></a>
        </div>
    </div>
    <?php if ($role === 'ADMIN'): ?>
        <div class="col-md-3 col-6">
            <div class="card border-0 shadow-sm rounded-4 h-100 text-center p-3">
                <div class="display-6 text-danger mb-2"><i class="fa-solid fa-mobile-screen-button"></i></div>
                <h6 class="fw-bold mb-0">Versi APK</h6>
                <a href="app_versi.php" class="stretched-link"></a>
            </div>
        </div>
    <?php endif; ?>
</div>

<?php require_once __DIR__ . '/footer.php'; ?>
