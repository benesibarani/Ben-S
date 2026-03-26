<?php
require_once 'config.php';
require_once 'header.php';

// --- CEK LOGIN ---
if (!isset($_SESSION['is_logged_in'])) {
    echo "<script>window.location='index.php';</script>";
    exit();
}

$my_email = $_SESSION['email'];
$my_nama  = $_SESSION['nama'];
$is_admin = ($_SESSION['role'] === 'admin' || $_SESSION['role'] === 'super_admin');
$message  = "";

// Set Timezone agar perhitungan hari akurat
date_default_timezone_set('Asia/Jakarta');

// --- CEK NOTIFIKASI REDIRECT ---
if (isset($_GET['msg'])) {
    if ($_GET['msg'] == 'success_add') $message = "<div class='alert alert-success shadow-sm alert-dismissible fade show'><i class='fas fa-check-circle me-2'></i>Laporan hari ini berhasil ditambahkan ke Total Pencapaian!<button type='button' class='btn-close' data-bs-dismiss='alert'></button></div>";
    if ($_GET['msg'] == 'success_update') $message = "<div class='alert alert-info shadow-sm alert-dismissible fade show'><i class='fas fa-check-circle me-2'></i>Pengaturan Target / Koreksi Data berhasil disimpan!<button type='button' class='btn-close' data-bs-dismiss='alert'></button></div>";
    if ($_GET['msg'] == 'success_reset') $message = "<div class='alert alert-danger shadow-sm alert-dismissible fade show'><i class='fas fa-trash me-2'></i>Data Target Cycle berhasil Direset/Dikosongkan.<button type='button' class='btn-close' data-bs-dismiss='alert'></button></div>";
}

// --- FUNGSI HITUNG HARI KERJA CANGGIH ---
function getWorkingDays($startDate, $endDate, $holidays = []) {
    $begin = strtotime($startDate);
    $end   = strtotime($endDate);
    if ($begin > $end) return 0;
    $no_days  = 0;
    while ($begin <= $end) {
        $what_day = date("N", $begin); 
        $current_date = date("Y-m-d", $begin); 
        if ($what_day != 7 && !in_array($current_date, $holidays)) $no_days++;
        $begin += 86400; 
    }
    return $no_days;
}

// --- FUNGSI FORMAT TANGGAL INDONESIA ---
function formatTanggalIndonesia($datetime) {
    if (empty($datetime)) return "-";
    
    $hari = array('Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu');
    $bulan = array(1 => 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember');
    
    $waktu = strtotime($datetime);
    $h = $hari[date('w', $waktu)];
    $t = date('j', $waktu);
    $b = $bulan[date('n', $waktu)];
    $th = date('Y', $waktu);
    $jam = date('H:i', $waktu);
    
    return "$h, $t $b $th - $jam WIB";
}

// ==========================================
// LOGIC 1: INPUT LAPORAN HARIAN (AKUMULASI)
// ==========================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['tambah_harian'])) {
    $tambah_nota = (int)$_POST['tambah_nota'];
    
    // Ambil Input Pack
    $wkhp12 = (int)$_POST['wkhp12'];
    $gk10   = (int)$_POST['gk10'];
    $gk12   = (int)$_POST['gk12'];
    $gkek12 = (int)$_POST['gkek12'];
    $gp12   = (int)$_POST['gp12'];
    $am16   = (int)$_POST['am16'];
    $alva12 = (int)$_POST['alva12'];

    // Hitung Konversi ke Batang
    $tambah_batang = ($wkhp12 * 12) + ($gk10 * 10) + ($gk12 * 12) + ($gkek12 * 12) + ($gp12 * 12) + ($am16 * 16) + ($alva12 * 12);

    // Update (Tambahkan ke pencapaian yang sudah ada)
    $stmt = $conn->prepare("UPDATE target_insentif SET pencapaian_batang = pencapaian_batang + ?, pencapaian_nota = pencapaian_nota + ? WHERE sales_email=?");
    $stmt->bind_param("iis", $tambah_batang, $tambah_nota, $my_email);
    $stmt->execute();

    header("Location: insentif.php?msg=success_add");
    exit();
}

// ==========================================
// LOGIC 2: SIMPAN / KOREKSI DATA MASTER
// ==========================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['simpan_target'])) {
    $nama_cycle = $_POST['nama_cycle'];
    $tgl_mulai = $_POST['tanggal_mulai'];
    $tgl_selesai = $_POST['tanggal_selesai'];
    $tgl_libur = $_POST['tanggal_libur'];
    
    $t_batang = (int)$_POST['target_batang'];
    $p_batang = (int)$_POST['pencapaian_batang'];
    $t_nota = (int)$_POST['target_nota'];
    $p_nota = (int)$_POST['pencapaian_nota'];

    $cek_data = $conn->query("SELECT id FROM target_insentif WHERE sales_email='$my_email'");

    if ($cek_data->num_rows > 0) {
        $stmt = $conn->prepare("UPDATE target_insentif SET nama_cycle=?, tanggal_mulai=?, tanggal_selesai=?, tanggal_libur=?, target_batang=?, pencapaian_batang=?, target_nota=?, pencapaian_nota=? WHERE sales_email=?");
        $stmt->bind_param("ssssiiiis", $nama_cycle, $tgl_mulai, $tgl_selesai, $tgl_libur, $t_batang, $p_batang, $t_nota, $p_nota, $my_email);
        $stmt->execute();
    } else {
        $stmt = $conn->prepare("INSERT INTO target_insentif (sales_email, sales_nama, nama_cycle, tanggal_mulai, tanggal_selesai, tanggal_libur, target_batang, pencapaian_batang, target_nota, pencapaian_nota) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("ssssssiiii", $my_email, $my_nama, $nama_cycle, $tgl_mulai, $tgl_selesai, $tgl_libur, $t_batang, $p_batang, $t_nota, $p_nota);
        $stmt->execute();
    }
    header("Location: insentif.php?msg=success_update");
    exit();
}

// ==========================================
// LOGIC 3: HAPUS / RESET DATA
// ==========================================
if (isset($_POST['hapus_target'])) {
    $conn->query("DELETE FROM target_insentif WHERE sales_email='$my_email'");
    header("Location: insentif.php?msg=success_reset");
    exit();
}

// --- AMBIL DATA CYCLE TERAKTIF ---
$active_data = null;
$q_active = $conn->query("SELECT * FROM target_insentif WHERE sales_email='$my_email' LIMIT 1");
if ($q_active && $q_active->num_rows > 0) {
    $active_data = $q_active->fetch_assoc();
}
?>

<div class="container-fluid p-0">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <div>
            <h4 class="fw-bold text-success mb-0"><i class="fas fa-calculator me-2"></i> Laporan & Insentif</h4>
            <small class="text-muted">Fokus Target: <strong>SKT GD & PLT (Aturan Multi-Item Baru)</strong></small>
        </div>
    </div>

    <?= $message ?>

    <!-- PAPAN INFORMASI ATURAN BARU -->
    <div class="alert alert-info shadow-sm border-info mb-4">
        <h6 class="fw-bold text-dark mb-2"><i class="fas fa-bullhorn me-2 text-primary"></i> INFO ATURAN INSENTIF TERBARU</h6>
        <div class="row small text-dark">
            <div class="col-md-6">
                <ul class="mb-1">
                    <li><strong>SKT GD:</strong> WKHP 12, GK 10, GK 12, GKEK 12, GP 12</li>
                    <li><strong>PLT:</strong> AM 16, ALVA 12</li>
                    <li><span class="text-muted">SKM & SPM (DEV, WD, MDW, MDIB) tidak dihitung dalam target ini.</span></li>
                </ul>
            </div>
            <div class="col-md-6">
                <div class="bg-white p-2 rounded border border-info">
                    <strong>Syarat Nota Valid (Multi-Item):</strong><br>
                    1 Nota minimal <strong>5 Pack</strong> kombinasi dari <strong>SKT GD + PLT</strong>.<br>
                    <em>Contoh: 4 Pack GK 10 + 1 Pack AM 16 = 1 Nota Valid.</em>
                </div>
            </div>
        </div>
    </div>

    <div class="row g-4">
        <!-- KOLOM KIRI: STATUS & TAKTIK -->
        <div class="col-lg-6">
            <div class="card shadow-sm border-0 border-top border-success border-4 mb-4">
                <div class="card-header bg-white py-3">
                    <h5 class="fw-bold mb-0 text-success"><i class="fas fa-chart-pie me-2"></i> Status Pencapaian Cycle Ini</h5>
                </div>
                <div class="card-body">
                    <?php if ($active_data): 
                        $tgl_hari_ini = date('Y-m-d');
                        
                        $holidays_array = [];
                        if (!empty($active_data['tanggal_libur'])) {
                            $raw_dates = explode(',', $active_data['tanggal_libur']);
                            foreach($raw_dates as $d) {
                                $clean_date = trim($d);
                                if (!empty($clean_date)) $holidays_array[] = $clean_date;
                            }
                        }
                        
                        $total_hk_cycle = getWorkingDays($active_data['tanggal_mulai'], $active_data['tanggal_selesai'], $holidays_array);
                        $tgl_mulai_hitung = ($tgl_hari_ini > $active_data['tanggal_mulai']) ? $tgl_hari_ini : $active_data['tanggal_mulai'];

                        if ($tgl_hari_ini > $active_data['tanggal_selesai']) {
                            $sisa_hk = 0; 
                        } else {
                            $sisa_hk = getWorkingDays($tgl_mulai_hitung, $active_data['tanggal_selesai'], $holidays_array);
                        }

                        // --- HITUNGAN BATANG ---
                        $target_batang = (int)$active_data['target_batang'];
                        $pencapaian_batang = (int)$active_data['pencapaian_batang'];
                        $kurang_batang = max(0, $target_batang - $pencapaian_batang);
                        $harian_batang = ($sisa_hk > 0) ? ceil($kurang_batang / $sisa_hk) : 0;
                        $persen_batang = ($target_batang > 0) ? round(($pencapaian_batang / $target_batang) * 100, 1) : 0;
                        $cb_batang = $persen_batang >= 100 ? 'success' : ($persen_batang >= 80 ? 'info' : ($persen_batang >= 50 ? 'warning' : 'danger'));

                        // --- HITUNGAN NOTA ---
                        $target_nota = (int)$active_data['target_nota'];
                        $pencapaian_nota = (int)$active_data['pencapaian_nota'];
                        $kurang_nota = max(0, $target_nota - $pencapaian_nota);
                        $harian_nota = ($sisa_hk > 0) ? ceil($kurang_nota / $sisa_hk) : 0;
                        $persen_nota = ($target_nota > 0) ? round(($pencapaian_nota / $target_nota) * 100, 1) : 0;
                        $cb_nota = $persen_nota >= 100 ? 'success' : ($persen_nota >= 80 ? 'info' : ($persen_nota >= 50 ? 'warning' : 'danger'));
                        
                        // --- LOGIKA SIMULASI BUNDLING MULTI-ITEM (SKT + PLT) ---
                        // Formasi 1: 4 Pack GK 10 (40) + 1 Pack AM 16 (16) = 56 Btg
                        $bundleA_btg = 56; 
                        $req_bundleA = max($harian_nota, ($sisa_hk > 0 ? ceil($harian_batang / $bundleA_btg) : 0));

                        // Formasi 2: 3 Pack GK 12 (36) + 2 Pack AM 16 (32) = 68 Btg
                        $bundleB_btg = 68;
                        $req_bundleB = max($harian_nota, ($sisa_hk > 0 ? ceil($harian_batang / $bundleB_btg) : 0));
                        
                        // Formasi 3: 4 Pack ALVA 12 (48) + 1 Pack GK 10 (10) = 58 Btg
                        $bundleC_btg = 58;
                        $req_bundleC = max($harian_nota, ($sisa_hk > 0 ? ceil($harian_batang / $bundleC_btg) : 0));
                    ?>
                        <div class="text-center mb-3">
                            <h6 class="text-muted text-uppercase fw-bold mb-1"><?= htmlspecialchars($active_data['nama_cycle']) ?></h6>
                            <div class="d-inline-block">
                                <span class="badge bg-light text-dark border">
                                    <i class="fas fa-calendar-alt me-1"></i> <?= date('d M Y', strtotime($active_data['tanggal_mulai'])) ?> - <?= date('d M Y', strtotime($active_data['tanggal_selesai'])) ?>
                                </span>
                                <span class="badge bg-danger ms-1 shadow-sm"><i class="fas fa-hourglass-half me-1"></i> Sisa: <?= $sisa_hk ?> HK</span>
                            </div>
                            
                            <!-- INFO TERAKHIR UPDATE -->
                            <div class="mt-2 small">
                                <span class="text-muted"><i class="fas fa-history text-warning me-1"></i> Update Laporan Terakhir:</span><br>
                                <strong class="text-primary"><?= formatTanggalIndonesia($active_data['updated_at'] ?? '') ?></strong>
                            </div>
                        </div>

                        <div class="row g-2 mb-3 mt-3">
                            <!-- KARTU PROGRESS BATANG -->
                            <div class="col-md-6">
                                <div class="border rounded-3 p-2 bg-light h-100">
                                    <h6 class="fw-bold text-primary border-bottom pb-1 mb-2 small"><i class="fas fa-box-open me-1"></i>Target Batang (SKT+PLT)</h6>
                                    <div class="d-flex justify-content-between text-center mb-2">
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Target</small><span class="fw-bold fs-6"><?= number_format($target_batang, 0, ',', '.') ?></span></div>
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Tercapai</small><span class="fw-bold fs-6 text-success"><?= number_format($pencapaian_batang, 0, ',', '.') ?></span></div>
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Kurang</small><span class="fw-bold fs-6 text-danger"><?= number_format($kurang_batang, 0, ',', '.') ?></span></div>
                                    </div>
                                    <div class="progress" style="height: 6px;"><div class="progress-bar bg-<?= $cb_batang ?>" style="width: <?= $persen_batang ?>%;"></div></div>
                                </div>
                            </div>
                            <!-- KARTU PROGRESS NOTA -->
                            <div class="col-md-6">
                                <div class="border rounded-3 p-2 bg-light h-100">
                                    <h6 class="fw-bold text-info border-bottom pb-1 mb-2 small"><i class="fas fa-receipt me-1"></i>Target Nota (Multi-Item)</h6>
                                    <div class="d-flex justify-content-between text-center mb-2">
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Target</small><span class="fw-bold fs-6"><?= number_format($target_nota, 0, ',', '.') ?></span></div>
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Tercapai</small><span class="fw-bold fs-6 text-success"><?= number_format($pencapaian_nota, 0, ',', '.') ?></span></div>
                                        <div><small class="text-muted d-block" style="font-size:0.7em">Kurang</small><span class="fw-bold fs-6 text-danger"><?= number_format($kurang_nota, 0, ',', '.') ?></span></div>
                                    </div>
                                    <div class="progress" style="height: 6px;"><div class="progress-bar bg-<?= $cb_nota ?>" style="width: <?= $persen_nota ?>%;"></div></div>
                                </div>
                            </div>
                        </div>

                        <!-- TARGET HARIAN (YANG HARUS DIKEJAR HARI INI) -->
                        <?php if ($sisa_hk == 0 && ($kurang_batang > 0 || $kurang_nota > 0)): ?>
                            <div class="alert alert-danger text-center py-3 shadow-sm">
                                <i class="fas fa-exclamation-triangle fa-2x mb-2"></i><h5 class="fw-bold mb-0">Waktu Habis</h5>
                                <p class="small mb-0">Hari kerja untuk cycle ini sudah berakhir.</p>
                            </div>
                        <?php else: ?>
                            
                            <!-- SUMMARY HARIAN MURNI -->
                            <div class="d-flex justify-content-center gap-3 mb-3">
                                <div class="text-center bg-primary text-white rounded p-2 shadow-sm flex-fill">
                                    <small class="d-block text-white fw-bold">Kekurangan Batang/Hari</small>
                                    <h3 class="fw-bold mb-0"><?= number_format($harian_batang, 0, ',', '.') ?></h3>
                                </div>
                                <div class="text-center bg-danger text-white rounded p-2 shadow-sm flex-fill">
                                    <small class="d-block text-white fw-bold">Kekurangan Nota/Hari</small>
                                    <h3 class="fw-bold mb-0"><?= number_format($harian_nota, 0, ',', '.') ?></h3>
                                </div>
                            </div>

                            <!-- KARTU STRATEGI BUNDLING MULTI-ITEM -->
                            <div class="card border-warning shadow-sm">
                                <div class="card-header bg-warning text-dark fw-bold py-2">
                                    <i class="fas fa-lightbulb me-1"></i> Taktik Formasi Bundling HARI INI
                                </div>
                                <div class="card-body p-2 bg-light">
                                    <p class="small text-muted text-center mb-2 fw-bold border-bottom pb-1">Tawarkan paket ini ke Toko untuk kejar Batang & Nota sekaligus:</p>
                                    
                                    <div class="border rounded bg-white p-2 mb-2 d-flex align-items-center justify-content-between">
                                        <div>
                                            <span class="badge bg-danger mb-1">Formasi 1 (56 Btg)</span><br>
                                            <small class="text-muted fw-bold">4 Pack GK 10 <span class="text-primary">+ 1 Pack AM 16</span></small>
                                        </div>
                                        <div class="text-end">
                                            <span class="small text-muted d-block">Target Closing/Hari</span>
                                            <h4 class="fw-bold text-success mb-0"><?= $req_bundleA ?> <span class="fs-6">Toko</span></h4>
                                        </div>
                                    </div>

                                    <div class="border rounded bg-white p-2 mb-2 d-flex align-items-center justify-content-between">
                                        <div>
                                            <span class="badge bg-danger mb-1">Formasi 2 (68 Btg)</span><br>
                                            <small class="text-muted fw-bold">3 Pack GK 12 <span class="text-primary">+ 2 Pack AM 16</span></small>
                                        </div>
                                        <div class="text-end">
                                            <span class="small text-muted d-block">Target Closing/Hari</span>
                                            <h4 class="fw-bold text-success mb-0"><?= $req_bundleB ?> <span class="fs-6">Toko</span></h4>
                                        </div>
                                    </div>
                                    
                                    <div class="border rounded bg-white p-2 d-flex align-items-center justify-content-between">
                                        <div>
                                            <span class="badge bg-danger mb-1">Formasi 3 (58 Btg)</span><br>
                                            <small class="text-muted fw-bold">4 Pack ALVA 12 <span class="text-primary">+ 1 Pack GK 10</span></small>
                                        </div>
                                        <div class="text-end">
                                            <span class="small text-muted d-block">Target Closing/Hari</span>
                                            <h4 class="fw-bold text-success mb-0"><?= $req_bundleC ?> <span class="fs-6">Toko</span></h4>
                                        </div>
                                    </div>
                                </div>
                            </div>

                        <?php endif; ?>

                    <?php else: ?>
                        <div class="text-center py-5 text-muted">
                            <i class="fas fa-clipboard-list fa-3x mb-3 text-light"></i>
                            <h6>Belum ada data Cycle yang diset.</h6>
                            <p class="small">Silakan buka pengaturan Target Master di panel sebelah kanan.</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>

        <!-- KOLOM KANAN: FORM INPUT & MASTER -->
        <div class="col-lg-6">
            
            <?php if($active_data): ?>
            <!-- 1. FORM INPUT LAPORAN HARIAN (AKUMULASI) -->
            <div class="card shadow-sm border-0 border-top border-primary border-4 mb-4">
                <div class="card-header bg-white py-3">
                    <h6 class="fw-bold mb-0 text-primary"><i class="fas fa-cart-plus me-2"></i> Input Laporan Penjualan Hari Ini</h6>
                </div>
                <div class="card-body bg-light">
                    <form method="POST">
                        <input type="hidden" name="tambah_harian" value="1">
                        
                        <div class="row g-2 mb-3">
                            <!-- HEADER SKT GD CERAH -->
                            <div class="col-12">
                                <div class="p-2 bg-primary text-white fw-bold rounded shadow-sm mb-2 mt-1">
                                    <i class="fas fa-box me-1"></i> PRODUK SKT GD 
                                    <span class="fw-normal ms-1" style="font-size: 0.85em;">(Input jumlah Pack/Bungkus)</span>
                                </div>
                            </div>
                            
                            <div class="col-4 col-md-4">
                                <label class="small text-dark fw-bold">WKHP 12</label>
                                <input type="number" name="wkhp12" id="wkhp12" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                            <div class="col-4 col-md-4">
                                <label class="small text-dark fw-bold">GK 10</label>
                                <input type="number" name="gk10" id="gk10" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                            <div class="col-4 col-md-4">
                                <label class="small text-dark fw-bold">GK 12</label>
                                <input type="number" name="gk12" id="gk12" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                            <div class="col-6 col-md-6 mt-2">
                                <label class="small text-dark fw-bold">GKEK 12</label>
                                <input type="number" name="gkek12" id="gkek12" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                            <div class="col-6 col-md-6 mt-2">
                                <label class="small text-dark fw-bold">GP 12</label>
                                <input type="number" name="gp12" id="gp12" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>

                            <!-- HEADER PLT CERAH -->
                            <div class="col-12 mt-4">
                                <div class="p-2 bg-info text-white fw-bold rounded shadow-sm mb-2">
                                    <i class="fas fa-box-open me-1"></i> PRODUK PLT 
                                    <span class="fw-normal ms-1" style="font-size: 0.85em;">(Input jumlah Pack/Bungkus)</span>
                                </div>
                            </div>
                            
                            <div class="col-6 col-md-6">
                                <label class="small text-dark fw-bold">AM 16</label>
                                <input type="number" name="am16" id="am16" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                            <div class="col-6 col-md-6">
                                <label class="small text-dark fw-bold">ALVA 12</label>
                                <input type="number" name="alva12" id="alva12" class="form-control form-control-sm text-center" min="0" onkeyup="hitungBatangHarian()" placeholder="Pack">
                            </div>
                        </div>

                        <!-- KALKULATOR OTOMATIS -->
                        <div class="p-3 bg-white border border-primary rounded text-center mb-3 shadow-inner mt-4">
                            <span class="small text-muted d-block fw-bold">Konversi Otomatis Penjualan Hari Ini:</span>
                            <h3 class="fw-bold text-primary mb-0 mt-1"><span id="tampil_total_batang">0</span> <span class="fs-6 fw-normal text-muted">Batang</span></h3>
                        </div>

                        <!-- INPUT NOTA VALID -->
                        <div class="mb-4 p-3 bg-info-subtle border border-info rounded">
                            <label class="small fw-bold text-info-emphasis mb-1">Nota Multi-Item Baru Hari Ini</label>
                            <div class="input-group">
                                <input type="number" name="tambah_nota" class="form-control fw-bold" min="0" required placeholder="Contoh: 5">
                                <span class="input-group-text bg-info text-white fw-bold">Nota</span>
                            </div>
                            <small class="text-muted" style="font-size: 0.75em;">*Hanya masukkan Nota yang tembus syarat (Min 5 Pack kombinasi).</small>
                        </div>

                        <button type="submit" class="btn btn-primary w-100 py-3 fw-bold shadow-sm">
                            <i class="fas fa-plus-circle me-2"></i> TAMBAHKAN KE TOTAL PENCAPAIAN
                        </button>
                    </form>
                </div>
            </div>
            <?php endif; ?>

            <!-- 2. PENGATURAN TARGET MASTER (BISA DISEMBUNYIKAN/ACCORDION) -->
            <div class="accordion mb-4" id="accordionSettings">
                <div class="accordion-item border-0 shadow-sm">
                    <h2 class="accordion-header">
                        <!-- Jika data target sudah ada, defaultnya di-collapse (tutup). Jika belum ada, otomatis terbuka -->
                        <button class="accordion-button <?= $active_data ? 'collapsed' : '' ?> bg-white fw-bold text-secondary border" type="button" data-bs-toggle="collapse" data-bs-target="#collapseSettings">
                            <i class="fas fa-cog me-2"></i> <?= $active_data ? 'Pengaturan Target & Koreksi Data' : 'Buat Target Cycle Baru' ?>
                        </button>
                    </h2>
                    <div id="collapseSettings" class="accordion-collapse collapse <?= $active_data ? '' : 'show' ?>" data-bs-parent="#accordionSettings">
                        <div class="accordion-body p-4 border border-top-0 rounded-bottom bg-white">
                            
                            <?php if($active_data): ?>
                            <form method="POST" onsubmit="return confirm('Yakin ingin MERESET SEMUA data target Anda? Semua pencapaian akan kembali menjadi 0.');" class="mb-3 text-end">
                                <button type="submit" name="hapus_target" class="btn btn-sm btn-outline-danger"><i class="fas fa-trash"></i> Reset Data Cycle</button>
                            </form>
                            <?php endif; ?>
                            
                            <form method="POST">
                                <div class="mb-3">
                                    <label class="form-label small fw-bold">Nama Cycle</label>
                                    <input type="text" name="nama_cycle" class="form-control" required placeholder="Contoh: Cycle 3 (Maret 2026)" value="<?= $active_data['nama_cycle'] ?? '' ?>">
                                </div>

                                <div class="row g-3 mb-3">
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-secondary">Tanggal Mulai</label>
                                        <input type="date" name="tanggal_mulai" class="form-control" required value="<?= $active_data['tanggal_mulai'] ?? '' ?>">
                                    </div>
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-secondary">Tanggal Selesai</label>
                                        <input type="date" name="tanggal_selesai" class="form-control" required value="<?= $active_data['tanggal_selesai'] ?? '' ?>">
                                    </div>
                                </div>

                                <div class="mb-4 p-3 bg-danger-subtle border border-danger-subtle rounded">
                                    <label class="form-label small fw-bold text-danger"><i class="fas fa-calendar-times me-1"></i> Tanggal Merah / Libur (Opsional)</label>
                                    <div class="input-group mb-2">
                                        <input type="date" id="tambah_libur" class="form-control form-control-sm">
                                        <button type="button" class="btn btn-danger btn-sm fw-bold" onclick="addLibur()">+ Tambah</button>
                                    </div>
                                    <textarea name="tanggal_libur" id="tanggal_libur_list" class="form-control text-danger fw-bold" rows="2" placeholder="Daftar tanggal libur akan muncul di sini..."><?= $active_data['tanggal_libur'] ?? '' ?></textarea>
                                    <div class="form-text small mt-1 text-danger">*) Hari Minggu otomatis diabaikan. Masukkan tanggal libur Nasional saja.</div>
                                </div>

                                <div class="row g-3 mb-4">
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-primary border-bottom pb-1 w-100">TARGET BATANG (Master)</label>
                                        <div class="mb-2">
                                            <label class="small text-muted">Total Target (Btg)</label>
                                            <input type="number" name="target_batang" class="form-control fw-bold text-primary" required value="<?= $active_data['target_batang'] ?? '' ?>">
                                        </div>
                                        <div>
                                            <label class="small text-success fw-bold">Pencapaian (Btg)</label>
                                            <input type="number" name="pencapaian_batang" class="form-control fw-bold text-success border-success" required value="<?= $active_data['pencapaian_batang'] ?? 0 ?>">
                                            <small class="text-muted" style="font-size:0.7em">*Edit manual ini jika Anda salah input di form harian.</small>
                                        </div>
                                    </div>
                                    
                                    <div class="col-md-6">
                                        <label class="form-label small fw-bold text-info border-bottom pb-1 w-100">TARGET NOTA (Master)</label>
                                        <div class="mb-2">
                                            <label class="small text-muted">Total Target (Nota)</label>
                                            <input type="number" name="target_nota" class="form-control fw-bold text-info" required value="<?= $active_data['target_nota'] ?? '' ?>">
                                        </div>
                                        <div>
                                            <label class="small text-success fw-bold">Pencapaian (Nota)</label>
                                            <input type="number" name="pencapaian_nota" class="form-control fw-bold text-success border-success" required value="<?= $active_data['pencapaian_nota'] ?? 0 ?>">
                                        </div>
                                    </div>
                                </div>

                                <button type="submit" name="simpan_target" class="btn btn-secondary w-100 py-2 fw-bold shadow-sm">
                                    <i class="fas fa-save me-2"></i> SIMPAN PENGATURAN MASTER
                                </button>
                            </form>
                        </div>
                    </div>
                </div>
            </div>
            
        </div>
    </div>
</div>

<script>
// Fungsi JavaScript untuk menambah daftar tanggal libur
function addLibur() {
    let dateVal = document.getElementById('tambah_libur').value;
    if (dateVal) {
        let list = document.getElementById('tanggal_libur_list');
        if (list.value.trim() === '') {
            list.value = dateVal;
        } else {
            if (!list.value.includes(dateVal)) {
                list.value += ", " + dateVal;
            } else {
                alert('Tanggal tersebut sudah ada di daftar.');
            }
        }
        document.getElementById('tambah_libur').value = '';
    } else {
        alert('Pilih tanggal terlebih dahulu!');
    }
}

// Fungsi Konversi Pack ke Batang Real-Time
function hitungBatangHarian() {
    let w12 = (parseInt(document.getElementById('wkhp12').value) || 0) * 12;
    let g10 = (parseInt(document.getElementById('gk10').value) || 0) * 10;
    let g12 = (parseInt(document.getElementById('gk12').value) || 0) * 12;
    let gek = (parseInt(document.getElementById('gkek12').value) || 0) * 12;
    let gp12 = (parseInt(document.getElementById('gp12').value) || 0) * 12;
    let am16 = (parseInt(document.getElementById('am16').value) || 0) * 16;
    let al12 = (parseInt(document.getElementById('alva12').value) || 0) * 12;

    let total = w12 + g10 + g12 + gek + gp12 + am16 + al12;
    
    // Tampilkan dengan format ribuan (titik)
    document.getElementById('tampil_total_batang').innerText = total.toLocaleString('id-ID');
}
</script>

<?php require_once 'footer.php'; ?>