<?php
// --- 1. KONFIGURASI & KONEKSI ---
ini_set('display_errors', 0); 
ini_set('log_errors', 1); 
error_reporting(E_ALL);

session_start();
ob_start();

$host = "localhost";
$user = "benescom_benes_admin";     
$pass = "yuppike0ngku";    
$db   = "benescom_benes_sales"; 

try {
    mysqli_report(MYSQLI_REPORT_OFF);
    $conn = @new mysqli($host, $user, $pass, $db);
    if ($conn->connect_error) throw new Exception("Gagal Koneksi Database.");
} catch (Exception $e) {
    die("<div style='color:red; padding:20px; border:1px solid red;'>System Error.</div>");
}

// --- 2. LOGIC LOGIN ---
$error_login = '';
if (isset($_POST['login'])) {
    $u = trim($_POST['username']);
    $p = trim($_POST['password']);
    
    // Login Admin
    if ($u == 'admin' && $p == 'admin123') {
        $_SESSION['user_id'] = 0; $_SESSION['nama'] = 'Super Admin'; $_SESSION['email'] = 'admin@sys'; $_SESSION['role'] = 'super_admin'; $_SESSION['is_logged_in'] = true;
        header("Location: dashboard.php"); exit();
    } 
    // Login User
    else {
        $stmt = $conn->prepare("SELECT id, nama_lengkap, email, password, role FROM sales_users WHERE email = ?");
        if ($stmt) {
            $stmt->bind_param("s", $u); $stmt->execute(); $res = $stmt->get_result();
            if ($res->num_rows > 0) {
                $row = $res->fetch_assoc();
                if (password_verify($p, $row['password'])) {
                    $_SESSION['user_id'] = $row['id']; $_SESSION['nama'] = $row['nama_lengkap']; $_SESSION['email'] = $row['email']; $_SESSION['role'] = $row['role']; $_SESSION['is_logged_in'] = true;
                    header("Location: dashboard.php"); exit();
                } else { $error_login = "Password Salah."; }
            } else { $error_login = "Email tidak ditemukan."; }
        }
    }
}
if (isset($_GET['logout'])) { session_destroy(); header("Location: dashboard.php"); exit(); }

$is_logged_in = isset($_SESSION['is_logged_in']) && $_SESSION['is_logged_in'] === true;
$is_admin = (isset($_SESSION['role']) && ($_SESSION['role'] === 'admin' || $_SESSION['role'] === 'super_admin'));
$curr_email = $_SESSION['email'] ?? ''; 
$curr_nama = $_SESSION['nama'] ?? '';

// --- 3. LOGIC HITUNG STOK KRITIS (GLOBAL VIEW) ---
// Bagian ini diubah agar SEMUA user bisa melihat
$stok_warning = [];
if ($is_logged_in) {
    $minggu_sekarang = (int)date('W');
    
    // SELECT SEMUA DATA (TIDAK ADA FILTER SALES)
    $sql_stok = "SELECT * FROM stok_gsp ORDER BY nama_toko ASC";
    
    $q_stok = $conn->query($sql_stok);
    if ($q_stok) {
        while ($row = $q_stok->fetch_assoc()) {
            $prod_week = (int)$row['minggu_produksi'];
            $max_week = (int)$row['maksimal_minggu'];
            $umur = $minggu_sekarang - $prod_week;
            if ($umur < 0) $umur += 52;
            $sisa = $max_week - $umur;
            
            if ($umur >= $max_week || $sisa <= 2) {
                $kategori = ($umur >= $max_week) ? 'BS' : 'WARNING';
                $key = $row['nama_toko'] . '|' . $row['zona'] . '|' . $row['id_customer'] . '|' . $row['salesman'];
                if (!isset($stok_warning[$key])) $stok_warning[$key] = ['bs' => [], 'warning' => []];
                
                $item = $row['nama_produk'] . " (" . $row['jumlah_stok'] . ")";
                if ($kategori == 'BS') $stok_warning[$key]['bs'][] = $item;
                else $stok_warning[$key]['warning'][] = $item . " [Sisa $sisa Mg]";
            }
        }
    }
}

// --- 4. HITUNG PENDING REQUEST ---
$total_pending = 0;
if ($is_admin) {
    $q_s = $conn->query("SELECT COUNT(*) as total FROM pengajuan_sales WHERE status_approval = 'Pending'");
    $t1 = $q_s ? $q_s->fetch_assoc()['total'] : 0;
    $q_g = $conn->query("SELECT COUNT(*) as total FROM pengajuan_gsp WHERE status_approval = 'Pending'");
    $t2 = $q_g ? $q_g->fetch_assoc()['total'] : 0;
    $total_pending = $t1 + $t2;
}

require_once 'header.php'; 
?>

<?php if (!$is_logged_in): ?>
<div class="d-flex justify-content-center align-items-center vh-100 bg-light">
    <div class="card shadow p-4 border-0" style="width:100%; max-width:400px; border-radius:15px;">
        <div class="text-center mb-4"><i class="fas fa-cubes fa-3x text-primary mb-2"></i><h3 class="fw-bold text-dark">RTS <span class="text-primary">PANEL</span></h3></div>
        <?php if($error_login): ?><div class="alert alert-danger py-2 small"><?= $error_login ?></div><?php endif; ?>
        <form method="POST">
            <div class="form-floating mb-3"><input type="text" name="username" class="form-control" id="floatingInput" required placeholder="User"><label>Username / Email</label></div>
            <div class="form-floating mb-3"><input type="password" name="password" class="form-control" id="floatingPassword" required placeholder="Pass"><label>Password</label></div>
            <button type="submit" name="login" class="btn btn-primary w-100 py-2 fw-bold">MASUK SISTEM</button>
        </form>
    </div>
</div>
<?php else: ?>

<div class="container-fluid p-0">
    <div class="row">
        <div class="col-12">
            <div class="alert alert-primary shadow-sm border-0 d-flex align-items-center mb-4">
                <div class="me-3 display-6"><i class="fas fa-user-circle"></i></div>
                <div>
                    <h4 class="alert-heading mb-0">Selamat Datang, <?= $_SESSION['nama'] ?>!</h4>
                    <p class="mb-0 text-primary-emphasis">Login sebagai <strong><?= ucfirst($_SESSION['role']) ?></strong>.</p>
                </div>
            </div>
        </div>
    </div>
    
    <?php if($is_admin && $total_pending > 0): ?>
    <div class="row mb-4">
        <div class="col-12">
            <div class="card border-start border-5 border-warning shadow-sm">
                <div class="card-body d-flex align-items-center">
                    <div class="display-4 text-warning me-3"><i class="fas fa-exclamation-triangle"></i></div>
                    <div class="flex-grow-1">
                        <h5 class="fw-bold text-dark mb-1">PENTING: <?= $total_pending ?> Pengajuan Pending</h5>
                        <p class="mb-0 text-muted small">Segera proses. Data lama > 30 hari dihapus otomatis.</p>
                    </div>
                    <div><a href="inbox.php" class="btn btn-warning text-dark fw-bold shadow-sm">PROSES</a></div>
                </div>
            </div>
        </div>
    </div>
    <?php endif; ?>

    <!-- MONITORING STOK KRITIS (VISIBLE TO ALL) -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card shadow-sm border-danger">
                <div class="card-header bg-danger text-white d-flex justify-content-between align-items-center">
                    <h6 class="mb-0 fw-bold"><i class="fas fa-fire me-2"></i> Global Monitoring Stok Kritis (GSP)</h6>
                    <a href="stokgsp.php" class="btn btn-sm btn-light text-danger fw-bold">Input Data</a>
                </div>
                <?php if (empty($stok_warning)): ?>
                    <div class="card-body text-center text-muted py-4">
                        <i class="fas fa-check-circle fa-3x mb-3 text-success"></i>
                        <p class="mb-0">Aman! Tidak ada produk BS atau Warning saat ini.</p>
                    </div>
                <?php else: ?>
                    <div class="card-body p-0 table-responsive" style="max-height: 400px;">
                        <table class="table table-striped table-hover mb-0 small">
                            <thead class="table-light sticky-top">
                                <tr>
                                    <th>Outlet</th>
                                    <th>Salesman</th>
                                    <th class="text-warning">⚠️ Warning</th>
                                    <th class="text-danger">⛔ BS (Expired)</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php foreach ($stok_warning as $key => $data): 
                                    list($nama_toko, $zona, $id_cust, $nm_sales) = explode('|', $key);
                                ?>
                                <tr>
                                    <td class="fw-bold"><?= $nama_toko ?> <br><span class="badge bg-light text-dark border">ID: <?= $id_cust ?></span><br><span class="text-muted text-xs"><?= $zona ?></span></td>
                                    <td><?= $nm_sales ?></td>
                                    <td>
                                        <?php if(empty($data['warning'])): echo "-"; else: ?>
                                            <ul class="mb-0 ps-3 text-warning fw-bold"><?php foreach($data['warning'] as $item) echo "<li>$item</li>"; ?></ul>
                                        <?php endif; ?>
                                    </td>
                                    <td>
                                        <?php if(empty($data['bs'])): echo "-"; else: ?>
                                            <ul class="mb-0 ps-3 text-danger fw-bold"><?php foreach($data['bs'] as $item) echo "<li>$item</li>"; ?></ul>
                                        <?php endif; ?>
                                    </td>
                                </tr>
                                <?php endforeach; ?>
                            </tbody>
                        </table>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <!-- MENU -->
    <div class="row g-3">
        <div class="col-md-3 col-6"><div class="card bg-white border-0 shadow-sm h-100 text-center p-3 hover-scale"><div class="display-6 text-primary mb-2"><i class="fas fa-handshake"></i></div><h6 class="fw-bold">GSP Baru</h6><a href="gsp.php" class="stretched-link"></a></div></div>
        <div class="col-md-3 col-6"><div class="card bg-white border-0 shadow-sm h-100 text-center p-3 hover-scale"><div class="display-6 text-success mb-2"><i class="fas fa-store"></i></div><h6 class="fw-bold">Request Toko</h6><a href="pengajuan_toko.php" class="stretched-link"></a></div></div>
        <div class="col-md-3 col-6"><div class="card bg-white border-0 shadow-sm h-100 text-center p-3 hover-scale"><div class="display-6 text-danger mb-2"><i class="fas fa-boxes"></i></div><h6 class="fw-bold">Cek Stok</h6><a href="stokgsp.php" class="stretched-link"></a></div></div>
        <div class="col-md-3 col-6"><div class="card bg-white border-0 shadow-sm h-100 text-center p-3 hover-scale"><div class="display-6 text-warning mb-2"><i class="fas fa-inbox"></i></div><h6 class="fw-bold">Inbox</h6><a href="inbox.php" class="stretched-link"></a></div></div>
    </div>
</div>
<?php endif; ?>

<?php require_once 'footer.php'; ?>