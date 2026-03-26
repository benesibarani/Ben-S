<?php require_once 'config.php'; require_once 'header.php'; 
$message = "";

// LOGIC SUBMIT GSP
if (isset($_POST['submit_gsp'])) {
    $s_email = $_SESSION['email']; 
    $s_man = $_POST['salesman']; 
    $s_dist = $_POST['sales_district'];
    
    // Upload File (Ke Hosting Langsung)
    $f_ktp = uploadImage("foto_ktp"); 
    $f_luar = uploadImage("foto_luar"); 
    $f_dalam = uploadImage("foto_dalam");
    
    // Logic Insert
    if ($f_ktp && $f_luar && $f_dalam) {
        $stmt = $conn->prepare("INSERT INTO pengajuan_gsp (sales_email, sales_district, salesman, toko_lama_nama, toko_lama_id, toko_baru_nama, toko_baru_id, alamat_lengkap, pic_nama, nomor_hp, koordinat, link_foto_ktp, link_foto_luar, link_foto_dalam) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("ssssssssssssss", 
            $s_email, $s_dist, $s_man, 
            $_POST['toko_lama_nama'], $_POST['toko_lama_id'], 
            $_POST['toko_baru_nama'], $_POST['toko_baru_id'], 
            $_POST['alamat_lengkap'], $_POST['pic_nama'], 
            $_POST['nomor_hp'], $_POST['koordinat'], 
            $f_ktp, $f_luar, $f_dalam
        );
        
        if ($stmt->execute()) {
            $message = "Pengajuan GSP Berhasil Dikirim!";
        } else {
            $message = "Gagal DB: " . $stmt->error;
        }
    } else { 
        $message = "Gagal: Semua Foto Wajib Diisi!"; 
    }
}
?>

<div class="card shadow-sm border-0 mb-4">
    <div class="card-header bg-primary text-white fw-bold">
        <i class="fas fa-handshake me-2"></i> Formulir GSP Baru
    </div>
    <div class="card-body">
        <?php if($message): ?>
            <div class="alert alert-info alert-dismissible fade show">
                <?= $message ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            </div>
        <?php endif; ?>

        <!-- FORM HTML -->
        <form method="POST" enctype="multipart/form-data">
            <input type="hidden" name="submit_gsp" value="1">
            
            <div class="row g-3">
                <!-- SALESMAN -->
                <div class="col-md-6">
                    <label class="small fw-bold text-muted">Salesman</label>
                    <input type="text" name="salesman" class="form-control bg-light" value="<?= $_SESSION['nama'] ?>" readonly>
                </div>
                
                <!-- UPDATE: DISTRICT JADI DROPDOWN -->
                <div class="col-md-6">
                    <label class="small fw-bold text-muted">Sales District</label>
                    <select name="sales_district" class="form-select" required>
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
                    </select>
                </div>
                
                <div class="col-12"><hr class="my-1"></div>

                <!-- GSP LAMA -->
                <div class="col-md-6">
                    <div class="p-3 bg-light border rounded h-100">
                        <h6 class="small fw-bold text-danger border-bottom pb-2 mb-3">Data GSP Lama (Diputus)</h6>
                        <div class="mb-2">
                            <label class="small text-muted">Nama Outlet</label>
                            <input name="toko_lama_nama" class="form-control" required placeholder="Nama Toko Lama">
                        </div>
                        <div>
                            <label class="small text-muted">ID Customer</label>
                            <input name="toko_lama_id" class="form-control" required placeholder="ID Lama">
                        </div>
                    </div>
                </div>

                <!-- GSP BARU -->
                <div class="col-md-6">
                    <div class="p-3 bg-light border rounded h-100">
                        <h6 class="small fw-bold text-success border-bottom pb-2 mb-3">Data GSP Baru (Pengganti)</h6>
                        <div class="mb-2">
                            <label class="small text-muted">Nama Outlet</label>
                            <input name="toko_baru_nama" class="form-control" required placeholder="Nama Toko Baru">
                        </div>
                        <div>
                            <label class="small text-muted">ID Customer</label>
                            <input name="toko_baru_id" class="form-control" required placeholder="ID Baru">
                        </div>
                    </div>
                </div>

                <!-- DETAIL LOKASI -->
                <div class="col-12">
                    <label class="small fw-bold">Alamat Lengkap</label>
                    <textarea name="alamat_lengkap" class="form-control" rows="2" required placeholder="Jalan, No, Kelurahan..."></textarea>
                </div>
                <div class="col-md-6">
                    <label class="small fw-bold">Nama PIC</label>
                    <input name="pic_nama" class="form-control" required placeholder="Penanggung Jawab">
                </div>
                <div class="col-md-6">
                    <label class="small fw-bold">Nomor HP</label>
                    <input type="number" name="nomor_hp" class="form-control" required placeholder="08xxxxx">
                </div>
                <div class="col-12">
                    <label class="small fw-bold">Titik Koordinat</label>
                    <div class="input-group">
                        <input name="koordinat" id="koordinat" class="form-control" required placeholder="-6.2000, 106.81666">
                        <button type="button" onclick="getLocation()" class="btn btn-secondary">
                            <i class="fas fa-map-marker-alt"></i> Ambil Lokasi
                        </button>
                    </div>
                </div>
                
                <!-- DOKUMENTASI -->
                <div class="col-12 mt-4">
                    <h6 class="small fw-bold text-muted border-bottom pb-2">Upload Dokumentasi</h6>
                </div>
                <div class="col-md-4">
                    <label class="small">Foto KTP</label>
                    <input type="file" name="foto_ktp" class="form-control" required accept="image/*">
                </div>
                <div class="col-md-4">
                    <label class="small">Foto Luar Toko</label>
                    <input type="file" name="foto_luar" class="form-control" required accept="image/*">
                </div>
                <div class="col-md-4">
                    <label class="small">Foto Dalam Toko</label>
                    <input type="file" name="foto_dalam" class="form-control" required accept="image/*">
                </div>
                
                <div class="col-12 mt-4">
                    <button class="btn btn-primary w-100 fw-bold py-3 shadow-sm">
                        <i class="fas fa-paper-plane me-2"></i> KIRIM PENGAJUAN GSP
                    </button>
                </div>
            </div>
        </form>
    </div>
</div>

<div class="card shadow-sm border-0">
    <div class="card-header bg-white fw-bold">
        <i class="fas fa-history me-2"></i> Riwayat GSP Saya
    </div>
    <div class="card-body p-0 table-responsive">
        <table class="table table-hover small mb-0 align-middle">
            <thead class="table-light">
                <tr>
                    <th>Tgl</th>
                    <th>Sales</th>
                    <th>GSP Lama</th>
                    <th>GSP Baru</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                <?php 
                $filter = ($_SESSION['role']=='admin' || $_SESSION['role']=='super_admin') ? "" : "WHERE sales_email='".$_SESSION['email']."'";
                $q = $conn->query("SELECT * FROM pengajuan_gsp $filter ORDER BY tanggal_request DESC LIMIT 20");
                
                if($q && $q->num_rows > 0):
                    while($row = $q->fetch_assoc()): 
                        $badge = 'warning';
                        if($row['status_approval'] == 'Disetujui') $badge = 'success';
                        if($row['status_approval'] == 'Ditolak') $badge = 'danger';
                ?>
                <tr>
                    <td><?= date('d/m', strtotime($row['tanggal_request'])) ?></td>
                    <td><?= $row['salesman'] ?></td>
                    <td class="text-danger"><?= $row['toko_lama_nama'] ?></td>
                    <td class="text-success"><?= $row['toko_baru_nama'] ?></td>
                    <td><span class="badge bg-<?= $badge ?>"><?= $row['status_approval'] ?></span></td>
                </tr>
                <?php endwhile; else: ?>
                    <tr><td colspan="5" class="text-center py-4 text-muted">Belum ada riwayat pengajuan.</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</div>

<?php require_once 'footer.php'; ?>