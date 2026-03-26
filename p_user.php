<?php
require_once 'config.php';
require_once 'header.php';

// --- CEK PERMISSION ---
// Hanya Admin dan Super Admin yang boleh akses halaman ini
if (!isset($_SESSION['role']) || ($_SESSION['role'] !== 'admin' && $_SESSION['role'] !== 'super_admin')) {
    echo "<div class='container mt-5'><div class='alert alert-danger shadow-sm border-danger'>
            <h4 class='alert-heading'><i class='fas fa-exclamation-triangle'></i> Akses Ditolak!</h4>
            <p>Halaman ini khusus untuk Administrator.</p>
            <a href='dashboard.php' class='btn btn-danger btn-sm'>Kembali ke Dashboard</a>
          </div></div>";
    require_once 'footer.php';
    exit();
}

$is_super = ($_SESSION['role'] === 'super_admin');
$my_id = $_SESSION['user_id'];
$message = "";
$new_user_data = null;

// --- LOGIC ACTIONS ---
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    
    // 1. TAMBAH USER
    if (isset($_POST['action']) && $_POST['action'] === 'add') {
        $nama = trim($_POST['nama']);
        $email = trim($_POST['email']);
        $pass_raw = trim($_POST['password']);
        $role = $_POST['role'];

        // Validasi Role untuk Admin Biasa
        if (!$is_super && $role !== 'sales') {
            $message = "<div class='alert alert-danger shadow-sm'>Admin hanya boleh membuat akun Sales!</div>";
        } else {
            // Cek Email Duplikat
            $cek = $conn->query("SELECT id FROM sales_users WHERE email = '$email'");
            if ($cek->num_rows > 0) {
                $message = "<div class='alert alert-danger shadow-sm'>Gagal: Email sudah terdaftar!</div>";
            } else {
                $pass_hash = password_hash($pass_raw, PASSWORD_DEFAULT);
                $stmt = $conn->prepare("INSERT INTO sales_users (nama_lengkap, email, password, role) VALUES (?, ?, ?, ?)");
                $stmt->bind_param("ssss", $nama, $email, $pass_hash, $role);
                
                if ($stmt->execute()) {
                    $message = "<div class='alert alert-success shadow-sm'>User berhasil ditambahkan!</div>";
                    $new_user_data = ['nama' => $nama, 'email' => $email, 'pass' => $pass_raw, 'role' => $role];
                } else {
                    $message = "<div class='alert alert-danger shadow-sm'>Database Error: " . $stmt->error . "</div>";
                }
            }
        }
    }

    // 2. EDIT USER
    if (isset($_POST['action']) && $_POST['action'] === 'edit') {
        $id = (int)$_POST['user_id'];
        $nama = trim($_POST['nama']);
        $email = trim($_POST['email']);
        $pass_raw = trim($_POST['password']);
        
        // Handle Role (Jika form mengirim role, pakai itu. Jika tidak/hidden, ambil dari DB atau default)
        $role = isset($_POST['role']) ? $_POST['role'] : 'sales';

        // Cek Level Target (Admin tidak boleh edit Admin/Super)
        $target = $conn->query("SELECT role FROM sales_users WHERE id = $id")->fetch_assoc();
        
        if (!$is_super && ($target['role'] === 'admin' || $target['role'] === 'super_admin')) {
            $message = "<div class='alert alert-danger shadow-sm'>Anda tidak memiliki izin mengedit atasan/sesama admin.</div>";
        } elseif (!$is_super && $role !== 'sales') {
            // Jika Admin biasa mencoba mengubah role (misal lewat inspect element)
            $message = "<div class='alert alert-danger shadow-sm'>Anda tidak bisa menaikkan pangkat user menjadi Admin.</div>";
        } else {
            // Cek Email Duplikat (Kecuali punya sendiri)
            $cek = $conn->query("SELECT id FROM sales_users WHERE email = '$email' AND id != $id");
            if ($cek->num_rows > 0) {
                $message = "<div class='alert alert-danger shadow-sm'>Email sudah digunakan user lain!</div>";
            } else {
                // Logic Update dengan atau tanpa password
                if (!empty($pass_raw)) {
                    $pass_hash = password_hash($pass_raw, PASSWORD_DEFAULT);
                    $stmt = $conn->prepare("UPDATE sales_users SET nama_lengkap=?, email=?, password=?, role=? WHERE id=?");
                    $stmt->bind_param("ssssi", $nama, $email, $pass_hash, $role, $id);
                } else {
                    $stmt = $conn->prepare("UPDATE sales_users SET nama_lengkap=?, email=?, role=? WHERE id=?");
                    $stmt->bind_param("sssi", $nama, $email, $role, $id);
                }
                
                if ($stmt->execute()) {
                    $message = "<div class='alert alert-success shadow-sm'>Data user diperbarui!</div>";
                } else {
                    $message = "<div class='alert alert-danger shadow-sm'>Gagal Update: " . $stmt->error . "</div>";
                }
            }
        }
    }

    // 3. HAPUS USER
    if (isset($_POST['action']) && $_POST['action'] === 'delete') {
        $id = (int)$_POST['user_id'];
        
        // Cek Level Target
        $target = $conn->query("SELECT role FROM sales_users WHERE id = $id")->fetch_assoc();
        
        if ($id == $my_id) {
            $message = "<div class='alert alert-danger shadow-sm'>Tidak bisa menghapus akun sendiri!</div>";
        } elseif (!$is_super && ($target['role'] === 'admin' || $target['role'] === 'super_admin')) {
            $message = "<div class='alert alert-danger shadow-sm'>Akses Ditolak: Anda hanya bisa menghapus Sales.</div>";
        } else {
            $conn->query("DELETE FROM sales_users WHERE id = $id");
            $message = "<div class='alert alert-success shadow-sm'>User berhasil dihapus permanen.</div>";
        }
    }
}
?>

<div class="container-fluid p-0">
    
    <div class="d-flex justify-content-between align-items-center mb-4">
        <h4 class="fw-bold text-primary mb-0"><i class="fas fa-users-cog me-2"></i> Manajemen Pengguna</h4>
        <!-- TOMBOL TAMBAH USER (PEMICU MODAL) -->
        <button type="button" class="btn btn-primary shadow-sm" onclick="openAddModal()">
            <i class="fas fa-user-plus me-2"></i> Tambah User Baru
        </button>
    </div>

    <?= $message ?>

    <!-- INFO USER BARU (KARTU KREDENSIAL) -->
    <?php if ($new_user_data): ?>
    <div class="card bg-success text-white mb-4 shadow border-0">
        <div class="card-body">
            <h5 class="fw-bold"><i class="fas fa-check-circle me-2"></i> Akun Berhasil Dibuat!</h5>
            <p>Silakan copy data berikut untuk diberikan kepada yang bersangkutan:</p>
            <div class="bg-white text-dark p-3 rounded mb-3" style="font-family: monospace;">
                <strong>Nama:</strong> <?= $new_user_data['nama'] ?><br>
                <strong>Role:</strong> <?= ucfirst($new_user_data['role']) ?><br>
                <strong>Email:</strong> <?= $new_user_data['email'] ?><br>
                <strong>Password:</strong> <?= $new_user_data['pass'] ?><br>
                <strong>Login:</strong> https://rts.bene-s.com
            </div>
            <button class="btn btn-light btn-sm text-success fw-bold" onclick="copyCredential('<?= $new_user_data['email'] ?>', '<?= $new_user_data['pass'] ?>')">
                <i class="fas fa-copy"></i> Salin ke Clipboard
            </button>
        </div>
    </div>
    <?php endif; ?>

    <!-- TABEL USER -->
    <div class="card shadow-sm border-0">
        <div class="card-body p-0 table-responsive">
            <table class="table table-hover align-middle mb-0">
                <thead class="table-light">
                    <tr>
                        <th class="ps-4">Nama Lengkap</th>
                        <th>Email</th>
                        <th>Role</th>
                        <th>Terdaftar</th>
                        <th class="text-end pe-4">Aksi</th>
                    </tr>
                </thead>
                <tbody>
                    <?php
                    $q = $conn->query("SELECT * FROM sales_users ORDER BY role ASC, nama_lengkap ASC");
                    while ($row = $q->fetch_assoc()):
                        // Tentukan Label Role
                        $badge = 'secondary';
                        if ($row['role'] == 'super_admin') $badge = 'danger';
                        elseif ($row['role'] == 'admin') $badge = 'primary';
                        elseif ($row['role'] == 'sales') $badge = 'info';
                    ?>
                    <tr>
                        <td class="fw-bold ps-4"><?= htmlspecialchars($row['nama_lengkap']) ?></td>
                        <td><?= htmlspecialchars($row['email']) ?></td>
                        <td><span class="badge bg-<?= $badge ?>"><?= strtoupper(str_replace('_', ' ', $row['role'])) ?></span></td>
                        <td class="small text-muted"><?= date('d M Y', strtotime($row['created_at'])) ?></td>
                        <td class="text-end pe-4">
                            <!-- TOMBOL EDIT -->
                            <button type="button" onclick='editUser(<?= json_encode($row) ?>)' class="btn btn-sm btn-warning text-dark me-1" title="Edit"><i class="fas fa-edit"></i></button>
                            
                            <?php if ($row['id'] != $my_id): ?>
                                <!-- TOMBOL HAPUS -->
                                <form method="POST" class="d-inline" onsubmit="return confirm('Hapus user <?= $row['nama_lengkap'] ?> secara permanen?');">
                                    <input type="hidden" name="action" value="delete">
                                    <input type="hidden" name="user_id" value="<?= $row['id'] ?>">
                                    <button class="btn btn-sm btn-danger" title="Hapus"><i class="fas fa-trash"></i></button>
                                </form>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endwhile; ?>
                </tbody>
            </table>
        </div>
    </div>
</div>

<!-- MODAL POPUP TAMBAH/EDIT USER (WAJIB ADA) -->
<div class="modal fade" id="userModal" tabindex="-1" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header bg-primary text-white">
                <h5 class="modal-title fw-bold" id="modalTitle">Tambah User</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                <form method="POST" id="userForm">
                    <input type="hidden" name="action" id="formAction" value="add">
                    <input type="hidden" name="user_id" id="userId" value="">

                    <div class="mb-3">
                        <label class="form-label fw-bold small">Nama Lengkap</label>
                        <input type="text" name="nama" id="u_nama" class="form-control" required placeholder="Contoh: Budi Santoso">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label fw-bold small">Email Login</label>
                        <input type="email" name="email" id="u_email" class="form-control" required placeholder="nama@gawih.com">
                    </div>
                    
                    <div class="mb-3">
                        <label class="form-label fw-bold small" id="lblPass">Password</label>
                        <input type="text" name="password" id="u_pass" class="form-control" placeholder="Minimal 6 Karakter" required>
                        <small class="text-muted d-none" id="hintPass">*Kosongkan jika tidak ingin mengubah password.</small>
                    </div>

                    <div class="mb-3">
                        <label class="form-label fw-bold small">Level Akses (Role)</label>
                        <select name="role" id="u_role" class="form-select">
                            <option value="sales">Sales (Lapangan)</option>
                            <?php if ($is_super): ?>
                            <option value="admin">Admin (Kantor)</option>
                            <option value="super_admin">Super Admin (Full Akses)</option>
                            <?php endif; ?>
                        </select>
                        <?php if (!$is_super): ?>
                            <small class="text-muted">Admin hanya bisa membuat Sales.</small>
                        <?php endif; ?>
                    </div>

                    <div class="d-grid">
                        <button type="submit" class="btn btn-primary fw-bold" id="btnSave">SIMPAN USER</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

<?php require_once 'footer.php'; ?>

<!-- SCRIPT JAVASCRIPT DIPINDAHKAN KE BAWAH FOOTER AGAR LIBRARY BOOTSTRAP SUDAH SIAP -->
<script>
document.addEventListener('DOMContentLoaded', function() {
    // Inisialisasi Modal
    var userModalEl = document.getElementById('userModal');
    var myModal = new bootstrap.Modal(userModalEl);

    // Fungsi Global agar bisa dipanggil tombol onclick
    window.openAddModal = function() {
        document.getElementById('userForm').reset();
        document.getElementById('formAction').value = 'add';
        document.getElementById('userId').value = '';
        
        document.getElementById('modalTitle').innerText = 'Tambah User Baru';
        document.getElementById('btnSave').innerText = 'BUAT USER';
        
        // Password Wajib saat Add
        document.getElementById('u_pass').required = true;
        document.getElementById('hintPass').classList.add('d-none');
        
        // Reset Role Default
        document.getElementById('u_role').value = 'sales';
        
        myModal.show();
    };

    window.editUser = function(data) {
        document.getElementById('formAction').value = 'edit';
        document.getElementById('userId').value = data.id;
        
        document.getElementById('modalTitle').innerText = 'Edit User: ' + data.nama_lengkap;
        document.getElementById('btnSave').innerText = 'SIMPAN PERUBAHAN';

        document.getElementById('u_nama').value = data.nama_lengkap;
        document.getElementById('u_email').value = data.email;
        
        // Password Optional saat Edit
        document.getElementById('u_pass').value = '';
        document.getElementById('u_pass').required = false;
        document.getElementById('hintPass').classList.remove('d-none');

        // Handle Role Logic
        const roleSelect = document.getElementById('u_role');
        
        <?php if ($is_super): ?>
            // Super Admin bebas ganti role
            roleSelect.value = data.role;
        <?php else: ?>
            // Admin hanya bisa edit sales
            if(data.role === 'sales') {
                roleSelect.value = 'sales';
            } else {
                alert('Anda tidak memiliki izin mengedit level Admin/Super Admin.');
                return;
            }
        <?php endif; ?>

        myModal.show();
    };

    window.copyCredential = function(email, pass) {
        const text = `Akun RTS Panel\nLogin: https://rts.bene-s.com\nEmail: ${email}\nPass: ${pass}`;
        navigator.clipboard.writeText(text).then(() => {
            alert('Kredensial berhasil disalin!');
        });
    };
});
</script>