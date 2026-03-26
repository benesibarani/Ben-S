<?php
require_once 'config.php';
require_once 'header.php';

// --- CONFIG ---
$minggu_sekarang = (int)date('W'); 
$tahun_sekarang = (int)date('Y');
$curr_nama = $_SESSION['nama']; 
$message = "";

// --- LOGIC ACTIONS (SAMA SEPERTI SEBELUMNYA) ---
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // 1. TAMBAH STOK (MULTI ITEM)
    if (isset($_POST['action']) && $_POST['action'] === 'add_bulk') {
        $toko = $_POST['nama_toko']; $id_cust = $_POST['id_customer']; $sales = $_POST['salesman']; $zona = $_POST['zona'];
        $produk_list = $_POST['nama_produk']; $kode_list = $_POST['kode_produk']; $stok_list = $_POST['jumlah_stok']; $minggu_list = $_POST['minggu_produksi']; $max_list = $_POST['maksimal_minggu'];
        $sukses_count = 0;
        $stmt = $conn->prepare("INSERT INTO stok_gsp (nama_toko, id_customer, salesman, zona, nama_produk, kode_produk, jumlah_stok, minggu_produksi, maksimal_minggu) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)");
        for ($i = 0; $i < count($produk_list); $i++) {
            if (!empty($produk_list[$i])) {
                $nm = $produk_list[$i]; $kd = $kode_list[$i]; $st = (int)$stok_list[$i]; $mg = (int)$minggu_list[$i]; $mx = (int)$max_list[$i];
                $stmt->bind_param("ssssssiii", $toko, $id_cust, $sales, $zona, $nm, $kd, $st, $mg, $mx);
                if ($stmt->execute()) $sukses_count++;
            }
        }
        if ($sukses_count > 0) $message = "Berhasil menambahkan $sukses_count item.";
        else $message = "Gagal menyimpan data.";
    }
    // 2. EDIT STOK
    if (isset($_POST['action']) && $_POST['action'] === 'edit') {
        $id = (int)$_POST['id_stok'];
        $stmt = $conn->prepare("UPDATE stok_gsp SET nama_toko=?, id_customer=?, salesman=?, zona=?, nama_produk=?, kode_produk=?, jumlah_stok=?, minggu_produksi=?, maksimal_minggu=? WHERE id=?");
        $stmt->bind_param("ssssssiiii", $_POST['nama_toko'], $_POST['id_customer'], $_POST['salesman'], $_POST['zona'], $_POST['nama_produk'], $_POST['kode_produk'], $_POST['jumlah_stok'], $_POST['minggu_produksi'], $_POST['maksimal_minggu'], $id);
        if ($stmt->execute()) $message = "Item berhasil diupdate.";
    }
    // 3. HAPUS STOK
    if (isset($_POST['action']) && $_POST['action'] === 'delete') {
        $id = (int)$_POST['id_stok'];
        $conn->query("DELETE FROM stok_gsp WHERE id=$id");
        $message = "Item dihapus.";
    }
}
?>

<!-- MODAL TAMBAH BULK -->
<div class="modal fade" id="addBulkModal" tabindex="-1" data-bs-backdrop="static">
    <div class="modal-dialog modal-xl">
        <div class="modal-content">
            <div class="modal-header bg-danger text-white">
                <h5 class="modal-title fw-bold" id="modalTitleBulk"><i class="fas fa-cart-plus me-2"></i> Input Stok GSP</h5>
                <button type="button" class="btn-close btn-close-white" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form method="POST" id="formBulk">
                    <input type="hidden" name="action" value="add_bulk">
                    <div class="bg-light p-3 rounded border mb-3">
                        <div class="row g-3">
                            <div class="col-md-6"><label class="small fw-bold text-muted">Salesman</label><input type="text" name="salesman" id="b_sales" class="form-control fw-bold" value="<?= $curr_nama ?>" readonly></div>
                            <div class="col-md-6"><label class="small fw-bold text-muted">Zona Wilayah</label><select name="zona" id="b_zona" class="form-select fw-bold" required><option value="">-- Pilih Zona --</option><option value="Medan Amplas">Medan Amplas</option><option value="Medan Johor">Medan Johor</option><option value="Medan Halvetia">Medan Halvetia</option><option value="Medan Kota">Medan Kota</option><option value="Medan Marelan">Medan Marelan</option><option value="Medan Selayang">Medan Selayang</option><option value="Medan Petisah">Medan Petisah</option><option value="Hamparan Perak">Hamparan Perak</option><option value="Pancur Batu">Pancur Batu</option><option value="Sunggal Deli">Sunggal Deli</option></select></div>
                            <div class="col-md-6"><label class="small fw-bold text-muted">Nama Toko / GSP</label><input type="text" name="nama_toko" id="b_toko" class="form-control" required placeholder="Contoh: Toko Putra Tamiang"></div>
                            <div class="col-md-6"><label class="small fw-bold text-muted">ID Customer</label><input type="text" name="id_customer" id="b_cust" class="form-control" required placeholder="ID..."></div>
                        </div>
                    </div>
                    <div class="table-responsive">
                        <table class="table table-bordered table-sm">
                            <thead class="table-light text-center"><tr><th width="35%">Nama Produk</th><th width="15%">Kode</th><th width="15%">Minggu Prod.</th><th width="15%">Batas Max</th><th width="15%">Stok</th><th width="5%"></th></tr></thead>
                            <tbody id="productRows"></tbody>
                        </table>
                    </div>
                    <button type="button" class="btn btn-sm btn-success mb-3" onclick="addRow()"><i class="fas fa-plus-circle"></i> Tambah Baris</button>
                    <div class="d-grid"><button type="submit" class="btn btn-danger fw-bold py-2">SIMPAN DATA</button></div>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- MODAL EDIT SATUAN -->
<div class="modal fade" id="editModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header bg-warning">
                <h5 class="modal-title fw-bold">Edit Item Stok</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <div class="modal-body">
                <form method="POST">
                    <input type="hidden" name="action" value="edit"><input type="hidden" name="id_stok" id="e_id">
                    <div class="mb-2"><label class="small fw-bold">Salesman</label><input name="salesman" id="e_sales" class="form-control" readonly></div>
                    <div class="mb-2"><label class="small fw-bold">Zona</label><select name="zona" id="e_zona" class="form-select"><option value="Medan Amplas">Medan Amplas</option><option value="Medan Johor">Medan Johor</option><option value="Medan Halvetia">Medan Halvetia</option><option value="Medan Kota">Medan Kota</option><option value="Medan Marelan">Medan Marelan</option><option value="Medan Selayang">Medan Selayang</option><option value="Medan Petisah">Medan Petisah</option><option value="Hamparan Perak">Hamparan Perak</option><option value="Pancur Batu">Pancur Batu</option><option value="Sunggal Deli">Sunggal Deli</option></select></div>
                    <div class="mb-2"><label class="small">Toko</label><input name="nama_toko" id="e_toko" class="form-control" required></div>
                    <div class="mb-2"><label class="small">ID Cust</label><input name="id_customer" id="e_cust" class="form-control" required></div>
                    <div class="mb-2"><label class="small">Produk</label><select name="nama_produk" id="e_nama" class="form-select product-select-edit" onchange="autoFillEdit()"></select></div>
                    <div class="row g-2"><div class="col-6"><label class="small">Kode</label><input name="kode_produk" id="e_kode" class="form-control bg-light" readonly></div><div class="col-6"><label class="small">Max Week</label><input name="maksimal_minggu" id="e_max" class="form-control bg-light" readonly></div><div class="col-6"><label class="small text-danger">Prod Week</label><input type="number" name="minggu_produksi" id="e_minggu" class="form-control border-danger"></div><div class="col-6"><label class="small fw-bold">Stok</label><input type="number" name="jumlah_stok" id="e_stok" class="form-control fw-bold"></div></div>
                    <button class="btn btn-warning w-100 mt-3 fw-bold">Update Item</button>
                </form>
            </div>
        </div>
    </div>
</div>

<div class="container-fluid p-0">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div><h4 class="fw-bold text-danger mb-0"><i class="fas fa-boxes me-2"></i> Stok GSP</h4><small class="text-muted">Minggu Berjalan: <strong>Ke-<?= $minggu_sekarang ?></strong></small></div>
        <button class="btn btn-danger shadow-sm" onclick="openBulkModal()"><i class="fas fa-cart-plus me-2"></i> Input Stok</button>
    </div>

    <?php if($message): ?><div class="alert alert-success alert-dismissible fade show"><?= $message ?><button type="button" class="btn-close" data-bs-dismiss="alert"></button></div><?php endif; ?>

    <!-- TAMPILAN DATA (GROUPING ZONA & TOKO) -->
    <?php
    // 1. Ambil Data dan Grouping di PHP
    $q = $conn->query("SELECT * FROM stok_gsp ORDER BY zona ASC, nama_toko ASC, minggu_produksi ASC");
    $data_grouped = [];
    if ($q && $q->num_rows > 0) {
        while ($row = $q->fetch_assoc()) {
            $data_grouped[$row['zona']][$row['nama_toko']][] = $row;
        }
    }
    ?>

    <?php if (empty($data_grouped)): ?>
        <div class="text-center py-5 text-muted border rounded bg-light">Belum ada data stok.</div>
    <?php else: ?>
        <div class="accordion" id="accordionZona">
            <?php 
            $i = 0;
            foreach ($data_grouped as $zona => $tokos): 
                $i++;
            ?>
            <div class="mb-4">
                <!-- HEADER ZONA -->
                <h6 class="text-uppercase fw-bold text-secondary border-bottom pb-2 mb-3">
                    <i class="fas fa-map-marker-alt me-2"></i> <?= htmlspecialchars($zona) ?>
                </h6>

                <!-- DAFTAR TOKO (ACCORDION) -->
                <?php foreach ($tokos as $toko_nama => $items): 
                    $toko_id_clean = preg_replace('/[^A-Za-z0-9]/', '', $toko_nama) . rand(100,999); // ID unik untuk accordion
                    $sales_name = $items[0]['salesman'];
                    $cust_id = $items[0]['id_customer'];
                    
                    // Cek jika ada item BS/Warning di toko ini untuk pewarnaan header
                    $has_bs = false; $has_warning = false;
                    foreach($items as $item) {
                        $umur = $minggu_sekarang - $item['minggu_produksi']; if ($umur < 0) $umur += 52;
                        $sisa = $item['maksimal_minggu'] - $umur;
                        if ($umur >= $item['maksimal_minggu']) $has_bs = true;
                        elseif ($sisa <= 2) $has_warning = true;
                    }
                    $border_class = $has_bs ? "border-danger" : ($has_warning ? "border-warning" : "border-0");
                    $bg_header = $has_bs ? "bg-danger-subtle" : ($has_warning ? "bg-warning-subtle" : "bg-white");
                ?>
                <div class="card shadow-sm mb-2 <?= $border_class ?>">
                    <div class="card-header <?= $bg_header ?> py-3" id="heading<?= $toko_id_clean ?>" style="cursor: pointer;" data-bs-toggle="collapse" data-bs-target="#collapse<?= $toko_id_clean ?>">
                        <div class="d-flex justify-content-between align-items-center">
                            <div>
                                <h6 class="mb-0 fw-bold text-dark"><i class="fas fa-store me-2 text-secondary"></i><?= htmlspecialchars($toko_nama) ?></h6>
                                <small class="text-muted">Sales: <?= $sales_name ?> | ID: <?= $cust_id ?></small>
                                <?php if($has_bs): ?><span class="badge bg-danger ms-2">Ada BS</span><?php endif; ?>
                            </div>
                            <i class="fas fa-chevron-down text-muted"></i>
                        </div>
                    </div>

                    <div id="collapse<?= $toko_id_clean ?>" class="accordion-collapse collapse" data-bs-parent="#accordionZona">
                        <div class="card-body p-0">
                            <!-- TOMBOL TAMBAH PRODUK KHUSUS TOKO INI -->
                            <div class="p-2 bg-light text-end border-bottom">
                                <button onclick='tambahItemToko(<?= json_encode($items[0], JSON_HEX_APOS|JSON_HEX_QUOT) ?>)' class="btn btn-sm btn-success fw-bold">
                                    <i class="fas fa-plus-circle me-1"></i> Tambah Produk
                                </button>
                            </div>

                            <div class="table-responsive">
                                <table class="table table-hover mb-0 small align-middle">
                                    <thead class="table-light">
                                        <tr>
                                            <th class="ps-3">Produk</th>
                                            <th class="text-center">Prod. Week</th>
                                            <th class="text-center">Umur</th>
                                            <th class="text-center">Stok</th>
                                            <th class="text-center">Status</th>
                                            <th class="text-end pe-3">Aksi</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($items as $row): 
                                            $prod_week = (int)$row['minggu_produksi'];
                                            $max_week  = (int)$row['maksimal_minggu'];
                                            $umur = $minggu_sekarang - $prod_week;
                                            if ($umur < 0) $umur += 52; 
                                            $sisa = $max_week - $umur;

                                            $status = "Aman"; $bg = "success"; $row_style = "";
                                            if ($umur >= $max_week) { $status = "BS"; $bg = "danger"; $row_style = "background:#ffe6e6"; } 
                                            elseif ($sisa <= 2) { $status = "TARIK"; $bg = "warning text-dark"; $row_style = "background:#fff3cd"; }
                                        ?>
                                        <tr style="<?= $row_style ?>">
                                            <td class="ps-3 fw-bold"><?= htmlspecialchars($row['nama_produk']) ?></td>
                                            <td class="text-center text-muted">Mk-<?= $prod_week ?></td>
                                            <td class="text-center"><?= $umur ?> Mg</td>
                                            <td class="text-center fw-bold fs-6"><?= number_format($row['jumlah_stok']) ?></td>
                                            <td class="text-center"><span class="badge bg-<?= $bg ?>"><?= $status ?></span></td>
                                            <td class="text-end pe-3">
                                                <button onclick='editStok(<?= json_encode($row, JSON_HEX_APOS|JSON_HEX_QUOT) ?>)' class="btn btn-xs btn-outline-dark me-1"><i class="fas fa-edit"></i></button>
                                                <form method="POST" class="d-inline" onsubmit="return confirm('Hapus item ini?');">
                                                    <input type="hidden" name="action" value="delete"><input type="hidden" name="id_stok" value="<?= $row['id'] ?>">
                                                    <button class="btn btn-xs btn-outline-danger"><i class="fas fa-trash"></i></button>
                                                </form>
                                            </td>
                                        </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>
                <?php endforeach; ?>
            </div>
            <?php endforeach; ?>
        </div>
    <?php endif; ?>
</div>

<?php require_once 'footer.php'; ?>

<script>
document.addEventListener('DOMContentLoaded', function() {
    var bulkModal = new bootstrap.Modal(document.getElementById('addBulkModal'));
    var editModal = new bootstrap.Modal(document.getElementById('editModal'));

    const produkData = [
        {name: "GALAN KRETEK 10",      kode: "GK 10",    max: 20},
        {name: "GALAN KRETEK 12",      kode: "GK 12",    max: 20},
        {name: "GALAN EDISI KAWAN 12", kode: "GK EK",    max: 20},
        {name: "GALAN PRIMA",          kode: "GAPRI",    max: 20},
        {name: "DIPLOMAT EVO 16",      kode: "DEV 16",   max: 13},
        {name: "DIPLOMAT EVO 12",      kode: "DEV 12",   max: 13},
        {name: "DIPLOMAT MILD 16",     kode: "DM 16",    max: 14},
        {name: "ACTIF MIL 16",         kode: "AM 16",    max: 13},
        {name: "WISMILAK DIPLOMAT 16", kode: "WD 16",    max: 16},
        {name: "WISMILAK DIPLOMAT 12", kode: "WD 12",    max: 16},
        {name: "WISMILAK KRETEK 12",   kode: "WKHP",     max: 20},
        {name: "MODEN WHITE",          kode: "MDW",      max: 52},
        {name: "MODEN ICE BERRY",      kode: "MDIB",     max: 52}
    ];

    function populateSelects() {
        const options = '<option value="">-- Pilih --</option>' + produkData.map(p => `<option value="${p.name}">${p.name}</option>`).join('');
        document.querySelectorAll('.product-select').forEach(sel => { if(sel.children.length <= 1) sel.innerHTML = options; });
        document.querySelectorAll('.product-select-edit').forEach(sel => { sel.innerHTML = options; });
    }
    populateSelects();

    window.autoFillRow = function(selectEl) {
        const row = selectEl.closest('tr');
        const selected = produkData.find(p => p.name === selectEl.value);
        if (selected) {
            row.querySelector('.code-input').value = selected.kode;
            row.querySelector('.max-input').value = selected.max;
        }
    };
    
    window.autoFillEdit = function() {
        const val = document.getElementById('e_nama').value;
        const selected = produkData.find(p => p.name === val);
        if (selected) {
            document.getElementById('e_kode').value = selected.kode;
            document.getElementById('e_max').value = selected.max;
        }
    };

    window.openBulkModal = function() {
        document.getElementById('formBulk').reset();
        document.getElementById('modalTitleBulk').innerHTML = '<i class="fas fa-cart-plus me-2"></i> Input Stok GSP (Baru)';
        document.getElementById('b_sales').value = '<?= $curr_nama ?>';
        document.getElementById('productRows').innerHTML = ''; 
        window.addRow(); populateSelects();
        bulkModal.show();
    };

    // FITUR: Tambah Produk ke Toko Existing
    window.tambahItemToko = function(data) {
        document.getElementById('formBulk').reset();
        document.getElementById('productRows').innerHTML = ''; 
        window.addRow(); populateSelects();
        
        document.getElementById('modalTitleBulk').innerHTML = '<i class="fas fa-plus-circle me-2"></i> Tambah Produk: ' + data.nama_toko;
        document.getElementById('b_sales').value = data.salesman;
        document.getElementById('b_zona').value = data.zona;
        document.getElementById('b_toko').value = data.nama_toko;
        document.getElementById('b_cust').value = data.id_customer;
        
        bulkModal.show();
    };

    window.addRow = function() {
        const tbody = document.getElementById('productRows');
        const tr = document.createElement('tr');
        tr.innerHTML = `<td><select name="nama_produk[]" class="form-select form-select-sm product-select" required onchange="autoFillRow(this)"></select></td><td><input type="text" name="kode_produk[]" class="form-control form-control-sm bg-light code-input" readonly></td><td><input type="number" name="minggu_produksi[]" class="form-control form-control-sm border-danger" required placeholder="Minggu"></td><td><input type="number" name="maksimal_minggu[]" class="form-control form-control-sm bg-light max-input" readonly></td><td><input type="number" name="jumlah_stok[]" class="form-control form-control-sm fw-bold" required placeholder="Qty"></td><td class="text-center"><button type="button" class="btn btn-sm btn-outline-danger" onclick="removeRow(this)"><i class="fas fa-times"></i></button></td>`;
        tbody.appendChild(tr);
        populateSelects(); checkRows();
    };

    window.removeRow = function(btn) { btn.closest('tr').remove(); checkRows(); };
    function checkRows() { const rows = document.querySelectorAll('#productRows tr'); const dis = rows.length <= 1; rows.forEach(r => r.querySelector('.btn-outline-danger').disabled = dis); }

    window.editStok = function(data) {
        populateSelects();
        document.getElementById('e_id').value = data.id;
        document.getElementById('e_sales').value = data.salesman;
        document.getElementById('e_zona').value = data.zona;
        document.getElementById('e_toko').value = data.nama_toko;
        document.getElementById('e_cust').value = data.id_customer;
        document.getElementById('e_nama').value = data.nama_produk;
        document.getElementById('e_kode').value = data.kode_produk;
        document.getElementById('e_minggu').value = data.minggu_produksi;
        document.getElementById('e_max').value = data.maksimal_minggu;
        document.getElementById('e_stok').value = data.jumlah_stok;
        editModal.show();
    };
});
</script>

<?php require_once 'footer.php'; ?>