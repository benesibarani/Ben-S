<?php
require_once 'config.php';
require_once 'header.php';

// Cek Login
if (!isset($_SESSION['is_logged_in'])) {
    header("Location: index.php");
    exit();
}

$user_id = $_SESSION['user_id'];
$message = "";
$message_type = "";

// --- 1. AMBIL DATA USER SAAT INI ---
// Jika Super Admin Hardcoded (ID 0), set data dummy/static
if ($user_id == 0) {
    $current_data = [
        'nama_lengkap' => 'Super Admin (System)',
        'email' => 'admin@system.local',
        'role' => 'super_admin'
    ];
} else {
    // Ambil dari Database
    $stmt = $conn->prepare("SELECT * FROM sales_users WHERE id = ?");
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $current_data = $result->fetch_assoc();
}

// --- 2. PROSES UPDATE ---
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['update_profile'])) {
    
    // Cegah Super Admin Hardcoded mengedit diri sendiri via DB
    if ($user_id == 0) {
        $message = "Akun Super Admin Sistem (Config) tidak dapat diedit melalui halaman ini.";
        $message_type = "danger";
    } else {
        $nama = trim($_POST['nama']);
        $email = trim($_POST['email']);
        $password = trim($_POST['password']);
        
        // Validasi Email Duplikat (Kecuali punya sendiri)
        $cek_email = $conn->query("SELECT id FROM sales_users WHERE email = '$email' AND id != $user_id");
        
        if ($cek_email && $cek_email->num_rows > 0) {
            $message = "Gagal: Email '$email' sudah digunakan pengguna lain.";
            $message_type = "danger";
        } else {
            // Logika Update
            if (!empty($password)) {
                // Jika Password Diisi -> Update Password juga
                $hash = password_hash($password, PASSWORD_DEFAULT);
                $stmt = $conn->prepare("UPDATE sales_users SET nama_lengkap = ?, email = ?, password = ? WHERE id = ?");
                $stmt->bind_param("sssi", $nama, $email, $hash, $user_id);
            } else {
                // Jika Password Kosong -> Update Nama & Email saja
                $stmt = $conn->prepare("UPDATE sales_users SET nama_lengkap = ?, email = ? WHERE id = ?");
                $stmt->bind_param("ssi", $nama, $email, $user_id);
            }

            if ($stmt->execute()) {
                // Update Session agar nama di pojok kanan atas langsung berubah
                $_SESSION['nama'] = $nama;
                $_SESSION['email'] = $email;
                
                $message = "Profil berhasil diperbarui!";
                $message_type = "success";
                
                // Refresh data tampilan
                $current_data['nama_lengkap'] = $nama;
                $current_data['email'] = $email;
            } else {
                $message = "Terjadi kesalahan database: " . $conn->error;
                $message_type = "danger";
            }
        }
    }
}
?>

<div class="container mt-4">
    <div class="row justify-content-center">
        <div class="col-md-8 col-lg-6">
            
            <div class="d-flex align-items-center mb-4">
                <div class="bg-primary text-white rounded-circle d-flex align-items-center justify-content-center me-3" style="width: 60px; height: 60px; font-size: 24px;">
                    <i class="fas fa-user"></i>
                </div>
                <div>
                    <h4 class="mb-0 fw-bold">Pengaturan Akun</h4>
                    <p class="text-muted mb-0">Kelola informasi profil dan keamanan akun Anda.</p>
                </div>
            </div>

            <?php if ($message): ?>
                <div class="alert alert-<?= $message_type ?> alert-dismissible fade show shadow-sm" role="alert">
                    <?php if($message_type == 'success'): ?><i class="fas fa-check-circle me-2"></i><?php else: ?><i class="fas fa-exclamation-circle me-2"></i><?php endif; ?>
                    <?= $message ?>
                    <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
                </div>
            <?php endif; ?>

            <div class="card shadow-sm border-0">
                <div class="card-header bg-white py-3">
                    <h6 class="mb-0 fw-bold text-primary">Edit Profil</h6>
                </div>
                <div class="card-body p-4">
                    
                    <?php if ($user_id == 0): ?>
                        <div class="alert alert-warning border-warning">
                            <i class="fas fa-lock me-2"></i> Anda login sebagai <strong>Super Admin Sistem</strong>. Akun ini dikonfigurasi langsung di server dan tidak dapat diubah melalui menu ini.
                        </div>
                    <?php else: ?>

                    <form method="POST" action="">
                        <input type="hidden" name="update_profile" value="1">
                        
                        <div class="mb-3">
                            <label class="form-label small fw-bold text-muted">Peran / Role</label>
                            <input type="text" class="form-control bg-light" value="<?= ucfirst($current_data['role']) ?>" readonly disabled>
                            <div class="form-text">Role akun tidak dapat diubah sendiri.</div>
                        </div>

                        <div class="mb-3">
                            <label for="nama" class="form-label small fw-bold">Nama Lengkap</label>
                            <div class="input-group">
                                <span class="input-group-text bg-light"><i class="fas fa-id-card text-muted"></i></span>
                                <input type="text" class="form-control" id="nama" name="nama" value="<?= htmlspecialchars($current_data['nama_lengkap']) ?>" required>
                            </div>
                        </div>

                        <div class="mb-3">
                            <label for="email" class="form-label small fw-bold">Alamat Email</label>
                            <div class="input-group">
                                <span class="input-group-text bg-light"><i class="fas fa-envelope text-muted"></i></span>
                                <input type="email" class="form-control" id="email" name="email" value="<?= htmlspecialchars($current_data['email']) ?>" required>
                            </div>
                        </div>

                        <hr class="my-4">

                        <h6 class="fw-bold text-danger mb-3"><i class="fas fa-key me-2"></i>Ganti Password</h6>
                        <div class="alert alert-light border small text-muted">
                            Kosongkan kolom di bawah ini jika Anda <strong>tidak ingin</strong> mengubah password saat ini.
                        </div>

                        <div class="mb-4">
                            <label for="password" class="form-label small fw-bold">Password Baru</label>
                            <div class="input-group">
                                <span class="input-group-text bg-light"><i class="fas fa-lock text-muted"></i></span>
                                <input type="password" class="form-control" id="password" name="password" placeholder="Masukkan password baru...">
                            </div>
                        </div>

                        <div class="d-flex justify-content-between align-items-center">
                            <a href="dashboard.php" class="btn btn-outline-secondary">
                                <i class="fas fa-arrow-left me-1"></i> Kembali
                            </a>
                            <button type="submit" class="btn btn-primary fw-bold px-4">
                                <i class="fas fa-save me-1"></i> Simpan Perubahan
                            </button>
                        </div>
                    </form>
                    
                    <?php endif; ?>

                </div>
            </div>
        </div>
    </div>
</div>

<?php require_once 'footer.php'; ?>