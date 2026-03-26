<?php 
require_once 'config.php';

require_once 'header.php'; 
$message = "";

// LOGIC SUBMIT
if (isset($_POST['submit_request'])) {
    $s_email = $_SESSION['email']; 
    $s_man = $_POST['salesman']; 
    $dist = $_POST['sales_distric'];
    $jenis = $_POST['jenis_request'];
    
    // Inisialisasi Variabel
    $id_c = NULL; 
    $nm_l = ''; $nm_b = ''; 
    $al_l = ''; $al_b = ''; 
    $tp = ''; $vd = '';
    
    // PEMETAAN DATA
    if ($jenis == 'Tambah Baru') {
        $nm_b = $_POST['nama_toko_baru'];
        $al_b = $_POST['alamat_baru'];
        $tp   = $_POST['tipe'];
        $vd   = $_POST['visit_day_baru'];
    } 
    elseif ($jenis == 'Ganti Nama') {
        $id_c = $_POST['id_customer_gn'];
        $nm_l = $_POST['nama_lama_gn'];
        $nm_b = $_POST['nama_baru_gn'];
    } 
    elseif ($jenis == 'Ganti Alamat') {
        $id_c = $_POST['id_customer_ga'];
        $nm_l = $_POST['nama_toko_ga'];
        $al_l = $_POST['alamat_lama_ga'];
        $al_b = $_POST['alamat_baru_ga'];
    } 
    elseif ($jenis == 'Hapus Toko') {
        $id_c = $_POST['id_customer_hp'];
        $nm_l = $_POST['nama_toko_hp'];
        $al_l = $_POST['alamat_hp'];
    }

    $stmt = $conn->prepare("INSERT INTO pengajuan_sales (sales_email, sales_distric, salesman, jenis_request, id_customer, pic, rute_kunjungan, week, nama_toko_lama, nama_toko_baru, alamat_lama, alamat_baru, tipe_baru, visit_day_baru, alasan) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
    
    $stmt->bind_param("ssssissssssssss", 
        $s_email, $dist, $s_man, $jenis, $id_c, 
        $_POST['pic'], $_POST['rute_kunjungan'], $_POST['week'], 
        $nm_l, $nm_b, $al_l, $al_b, $tp, $vd, $_POST['alasan']
    );
    
    if($stmt->execute()) {
        $message = "Permintaan $jenis Berhasil Dikirim!";
    } else {
        $message = "Gagal: " . $stmt->error;
    }
}
?>

<div class="card shadow-sm border-0 mb-4">
    <div class="card-header bg-success text-white fw-bold">
        <i class="fas fa-store me-2"></i> Formulir Pengajuan Toko Reguler
    </div>
    <div class="card-body">
        
        <?php if($message): ?>
            <div class="alert alert-success alert-dismissible fade show">
                <?= $message ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>

        <form method="POST" id="formToko">
             <input type="hidden" name="submit_request" value="1">
             
             <div class="row g-3">
                 <!-- IDENTITAS SALES -->
                 <div class="col-md-6">
                     <label class="small fw-bold text-muted">Salesman</label>
                     <input type="text" name="salesman" class="form-control bg-light" value="<?= $_SESSION['nama'] ?>" readonly>
                 </div>
                 
                 <!-- UPDATE: SALES DISTRICT JADI DROPDOWN -->
                 <div class="col-md-6">
                     <label class="small fw-bold text-muted">Sales District</label>
                     <select name="sales_distric" class="form-select" required>
                         <option value="">-- Pilih District --</option>
                         <option value="Medan Amplas">Medan Amplas</option>
                         <option value="Medan Helvetia">Medan Helvetia</option>
                         <option value="Medan Johor">Medan Johor</option>
                         <option value="Medan Kota">Medan Kota</option>
                         <option value="Medan Perjuangan">Medan Perjuangan</option>
                         <option value="Medan Petisah">Medan Petisah</option>
                         <option value="Medan Marelan">Medan Marelan</option>
                         <option value="Medan Selayang">Medan Selayang</option>
                         <option value="Hamparan Perak">Hamparan Perak</option>
                         <option value="Sunggal Deli">Sunggal Deli</option>
                         <option value="Pancur Batu">Pancur Batu</option>
                         <option value="Modren Trade">Modren Trade</option>
                         
                     </select>
                 </div>

                 <div class="col-12"><hr class="my-1"></div>

                 <!-- PILIH JENIS REQUEST -->
                 <div class="col-12">
                     <label class="fw-bold text-success">Jenis Permintaan</label>
                     <select name="jenis_request" id="jenisRequest" class="form-select bg-success-subtle" required onchange="toggleForm(this.value)">
                         <option value="">-- Pilih Jenis --</option>
                         <option value="Tambah Baru">Tambah Toko Baru</option>
                         <option value="Ganti Nama">Permintaan Ganti Nama Toko</option>
                         <option value="Ganti Alamat">Permintaan Ganti Alamat Toko</option>
                         <option value="Hapus Toko">Permintaan Hapus Toko</option>
                     </select>
                 </div>
                 
                 <!-- 1. GROUP: TAMBAH BARU -->
                 <div class="col-12 group-form" id="grp-tambah" style="display:none;">
                     <div class="p-3 border rounded bg-light">
                        <h6 class="fw-bold text-success border-bottom pb-2 mb-3">Data Toko Baru</h6>
                        <div class="mb-2">
                            <label class="small fw-bold">Nama Toko Baru</label>
                            <input name="nama_toko_baru" class="form-control" placeholder="Contoh: Toko Maju Jaya">
                        </div>
                        <div class="mb-2">
                            <label class="small fw-bold">Alamat Lengkap</label>
                            <input name="alamat_baru" class="form-control" placeholder="Jalan, Nomor, Kelurahan...">
                        </div>
                        <div class="row g-2">
                            <div class="col-6">
                                <label class="small fw-bold">Tipe Outlet</label>
                                <select name="tipe" class="form-select">
                                    <option>Retail</option><option>Grosir</option><option>Star Outlet</option>
                                </select>
                            </div>
                            <div class="col-6">
                                <label class="small fw-bold">Jadwal Visit</label>
                                <select name="visit_day_baru" class="form-select">
                                    <option>Senin</option><option>Selasa</option><option>Rabu</option><option>Kamis</option><option>Jumat</option><option>Sabtu</option>
                                </select>
                            </div>
                        </div>
                     </div>
                 </div>

                 <!-- 2. GROUP: GANTI NAMA -->
                 <div class="col-12 group-form" id="grp-ganti-nama" style="display:none;">
                     <div class="p-3 border rounded bg-light">
                        <h6 class="fw-bold text-primary border-bottom pb-2 mb-3">Perubahan Nama Toko</h6>
                        <div class="row g-2 mb-2">
                            <div class="col-4">
                                <label class="small fw-bold text-muted">ID Customer</label>
                                <input type="number" name="id_customer_gn" class="form-control" placeholder="32XXXXX">
                            </div>
                            <div class="col-8">
                                <label class="small fw-bold text-muted">Nama Toko Lama</label>
                                <input name="nama_lama_gn" class="form-control" placeholder="Sesuai di SFA/HH">
                            </div>
                        </div>
                        <div class="mb-2">
                            <label class="small fw-bold text-primary">Nama Toko Baru</label>
                            <input name="nama_baru_gn" class="form-control border-primary" placeholder="Nama Baru yang diajukan">
                        </div>
                     </div>
                 </div>

                 <!-- 3. GROUP: GANTI ALAMAT -->
                 <div class="col-12 group-form" id="grp-ganti-alamat" style="display:none;">
                     <div class="p-3 border rounded bg-light">
                        <h6 class="fw-bold text-warning border-bottom pb-2 mb-3">Perubahan Alamat Toko</h6>
                        <div class="row g-2 mb-2">
                            <div class="col-4">
                                <label class="small fw-bold text-muted">ID Customer</label>
                                <input type="number" name="id_customer_ga" class="form-control" placeholder="32XXXXX">
                            </div>
                            <div class="col-8">
                                <label class="small fw-bold text-muted">Nama Toko</label>
                                <input name="nama_toko_ga" class="form-control" placeholder="Sesuai di SFA/HH">
                            </div>
                        </div>
                        <div class="mb-2">
                            <label class="small fw-bold text-muted">Alamat Lama</label>
                            <input name="alamat_lama_ga" class="form-control" placeholder="Sesuai di SFA/HH">
                        </div>
                        <div class="mb-2">
                            <label class="small fw-bold text-warning">Alamat Baru</label>
                            <textarea name="alamat_baru_ga" class="form-control border-warning" rows="2" placeholder="Alamat lengkap baru..."></textarea>
                        </div>
                     </div>
                 </div>

                 <!-- 4. GROUP: HAPUS TOKO -->
                 <div class="col-12 group-form" id="grp-hapus" style="display:none;">
                     <div class="p-3 border rounded bg-danger-subtle">
                        <h6 class="fw-bold text-danger border-bottom border-danger pb-2 mb-3">Permintaan Hapus Toko</h6>
                        <div class="row g-2 mb-2">
                            <div class="col-4">
                                <label class="small fw-bold text-muted">ID Customer</label>
                                <input type="number" name="id_customer_hp" class="form-control" placeholder="32XXXXX">
                            </div>
                            <div class="col-8">
                                <label class="small fw-bold text-muted">Nama Toko</label>
                                <input name="nama_toko_hp" class="form-control" placeholder="Sesuai di SFA/HH">
                            </div>
                        </div>
                        <div class="mb-2">
                            <label class="small fw-bold text-muted">Alamat</label>
                            <input name="alamat_hp" class="form-control" placeholder="Sesuai di SFA/HH">
                        </div>
                     </div>
                 </div>

                 <!-- DATA PELENGKAP (SELALU MUNCUL) -->
                 <div class="col-md-4">
                     <label class="small fw-bold">Nama PIC</label>
                     <input name="pic" class="form-control" required placeholder="Pak Budi">
                 </div>
                 <div class="col-md-4">
                     <label class="small fw-bold">Rute Kunjungan</label>
                     <select name="rute_kunjungan" class="form-select" required>
                         <option value="">-- Pilih Hari --</option>
                         <option>Senin</option>
                         <option>Selasa</option>
                         <option>Rabu</option>
                         <option>Kamis</option>
                         <option>Jumat</option>
                         <option>Sabtu</option>
                     </select>
                 </div>
                 <div class="col-md-4">
                     <label class="small fw-bold">Week (Minggu)</label>
                     <select name="week" class="form-select" required>
                         <option value="">-- Pilih --</option>
                         <option>Ganjil</option>
                         <option>Genap</option>
                     </select>
                 </div>
                 
                 <div class="col-12">
                     <label class="small fw-bold text-danger">Alasan (Reason)</label>
                     <textarea name="alasan" class="form-control" required placeholder="Alasan dihapus / diganti, Contoh: Permintaan PIC / Toko Tutup"></textarea>
                 </div>
                 
                 <div class="col-12 mt-4">
                     <button class="btn btn-success w-100 fw-bold py-3 shadow-sm">
                        <i class="fas fa-paper-plane me-2"></i> KIRIM PERMINTAAN
                     </button>
                 </div>
             </div>
        </form>
    </div>
</div>

<script>
function toggleForm(val) {
    // Sembunyikan semua group dulu
    document.querySelectorAll('.group-form').forEach(el => el.style.display = 'none');
    
    // Hapus atribut required dari input yang tersembunyi
    document.querySelectorAll('.group-form input, .group-form textarea').forEach(el => el.required = false);

    // Tampilkan yang dipilih dan set required
    if (val === 'Tambah Baru') {
        const el = document.getElementById('grp-tambah');
        el.style.display = 'block';
        el.querySelectorAll('input').forEach(i => i.required = true);
    } 
    else if (val === 'Ganti Nama') {
        const el = document.getElementById('grp-ganti-nama');
        el.style.display = 'block';
        el.querySelectorAll('input').forEach(i => i.required = true);
    }
    else if (val === 'Ganti Alamat') {
        const el = document.getElementById('grp-ganti-alamat');
        el.style.display = 'block';
        el.querySelectorAll('input, textarea').forEach(i => i.required = true);
    }
    else if (val === 'Hapus Toko') {
        const el = document.getElementById('grp-hapus');
        el.style.display = 'block';
        el.querySelectorAll('input').forEach(i => i.required = true);
    }
}
</script>

<?php require_once 'footer.php'; ?>