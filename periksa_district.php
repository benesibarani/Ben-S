<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PEMERIKSA ISI SALES DISTRICT
 *  Berkas : periksa_district.php   (letakkan di public_html sementara saja)
 *
 *  KEGUNAAN
 *  --------
 *  Menjawab pertanyaan: "isi kolom sales_district pada tabel sales_users
 *  sebenarnya apa saja?" Halaman ini membacanya langsung dari database dan
 *  menampilkannya dalam bentuk tabel yang mudah dibaca.
 *
 *  Yang ditampilkan:
 *    1. Nama database yang sedang dipakai (memastikan produksi/staging)
 *    2. Ada/tidaknya kolom sales_district
 *    3. DAFTAR NILAI sales_district pada tabel sales_users + jumlah akun
 *    4. Daftar district pada tabel master_toko + jumlah customer
 *    5. Sebaran role dan status akun
 *    6. Akun RTS/TF yang sales_district-nya masih KOSONG (perlu dilengkapi
 *       supaya data customer mereka tampil pada aplikasi)
 *    7. Hasil kotak pilihan pada halaman pendaftaran (daftar.php)
 *
 *  HANYA MEMBACA. Tidak ada satu pun data yang diubah atau dihapus.
 *  Sesudah diperiksa, berkas ini boleh dihapus dari hosting.
 * ============================================================================
 */

define('PERIKSA_DISTRICT_VERSI', 1);

require_once __DIR__ . '/config.php';

if (is_file(__DIR__ . '/district.php')) {
    require_once __DIR__ . '/district.php';
}

$pd_db = (isset($conn) && $conn instanceof mysqli) ? $conn : null;

$pd_nama_db = '';

if ($pd_db) {
    $pd_hasil_db = @$pd_db->query('SELECT DATABASE() AS db');

    if ($pd_hasil_db instanceof mysqli_result) {
        $pd_nama_db = (string) (($pd_hasil_db->fetch_assoc()['db']) ?? '');
        $pd_hasil_db->free();
    }
}

/** Menjalankan SELECT dan mengembalikan seluruh barisnya. */
function pd_ambil($db, string $sql): array
{
    if (!($db instanceof mysqli)) {
        return [];
    }

    $hasil = @$db->query($sql);

    if (!($hasil instanceof mysqli_result)) {
        return [];
    }

    $baris = [];

    while ($satu = $hasil->fetch_assoc()) {
        $baris[] = $satu;
    }

    $hasil->free();

    return $baris;
}

$pd_ada_district_user = $pd_db && function_exists('rts_district_kolom_ada')
    && rts_district_kolom_ada($pd_db, 'sales_users', 'sales_district');

$pd_district_user = $pd_ada_district_user
    ? pd_ambil($pd_db, "SELECT TRIM(sales_district) AS district, COUNT(*) AS jumlah,
              GROUP_CONCAT(DISTINCT role ORDER BY role SEPARATOR ', ') AS role
        FROM sales_users
        WHERE TRIM(COALESCE(sales_district, '')) <> ''
        GROUP BY TRIM(sales_district)
        ORDER BY jumlah DESC, district ASC")
    : [];

$pd_kosong = $pd_ada_district_user
    ? pd_ambil($pd_db, "SELECT username, nama_lengkap, role
        FROM sales_users
        WHERE (sales_district IS NULL OR TRIM(sales_district) = '')
          AND UPPER(role) IN ('RTS','TF')
        ORDER BY nama_lengkap ASC")
    : [];

$pd_role = pd_ambil($pd_db, 'SELECT UPPER(role) AS role, status_aktif, COUNT(*) AS jumlah
    FROM sales_users GROUP BY UPPER(role), status_aktif ORDER BY role ASC, status_aktif ASC');

$pd_admin = pd_ambil($pd_db, "SELECT username, nama_lengkap, role, sales_district, status_aktif
    FROM sales_users WHERE UPPER(role) IN ('ADMIN','ASS') ORDER BY role ASC");

$pd_pilihan = function_exists('rts_district_pilihan') ? rts_district_pilihan($pd_db) : [];

$pd_toko_ada = function_exists('rts_district_kolom_ada')
    && rts_district_kolom_ada($pd_db, 'master_toko', 'district');

$pd_toko = $pd_toko_ada
    ? pd_ambil($pd_db, "SELECT TRIM(district) AS district, COUNT(*) AS jumlah
        FROM master_toko
        WHERE TRIM(COALESCE(district, '')) <> ''
        GROUP BY TRIM(district)
        ORDER BY jumlah DESC, district ASC
        LIMIT 60")
    : [];
?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Periksa Sales District - RTS Panel</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">
<main class="container py-4" style="max-width:1000px">

  <h3 class="mb-1">Periksa Isi Sales District</h3>
  <p class="text-muted">
    Halaman ini hanya MEMBACA database. Tidak ada data yang diubah. Versi <?= PERIKSA_DISTRICT_VERSI ?>.
  </p>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <div class="row g-3">
        <div class="col-md-6">
          <div class="small text-muted">Database yang sedang dipakai</div>
          <div class="fw-bold"><?= htmlspecialchars($pd_nama_db === '' ? '(tidak terbaca)' : $pd_nama_db) ?></div>
        </div>
        <div class="col-md-3">
          <div class="small text-muted">Kolom sales_users.sales_district</div>
          <div class="fw-bold"><?= $pd_ada_district_user ? 'ADA' : 'TIDAK ADA' ?></div>
        </div>
        <div class="col-md-3">
          <div class="small text-muted">Berkas district.php</div>
          <div class="fw-bold"><?= function_exists('rts_district_pilihan') ? 'ADA' : 'TIDAK ADA' ?></div>
        </div>
      </div>
    </div>
  </div>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <h5 class="card-title">1. Isi kolom sales_district pada tabel sales_users</h5>
      <p class="text-muted small mb-2">
        Inilah daftar yang Bapak tanyakan. Daftar ini juga otomatis dipakai
        sebagai pilihan pada formulir pendaftaran tim Sales.
      </p>

      <?php if (!$pd_district_user): ?>
        <div class="alert alert-warning mb-0">
          Tidak ada nilai sales_district yang terisi, atau kolomnya belum ada.
          Semua akun yang ada saat ini mungkin belum diisi districtnya.
        </div>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm table-striped align-middle mb-0">
            <thead class="table-light">
              <tr><th>Sales District</th><th class="text-end">Jumlah akun</th><th>Role akun</th></tr>
            </thead>
            <tbody>
              <?php foreach ($pd_district_user as $baris): ?>
                <tr>
                  <td class="fw-semibold"><?= htmlspecialchars((string) $baris['district']) ?></td>
                  <td class="text-end"><?= (int) $baris['jumlah'] ?></td>
                  <td class="small text-muted"><?= htmlspecialchars((string) ($baris['role'] ?? '')) ?></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <h5 class="card-title">2. Pilihan district pada formulir pendaftaran (daftar.php)</h5>
      <p class="text-muted small mb-2">
        Ditandai "ADA di database" berarti district itu benar-benar dipakai akun yang sudah terdaftar.
      </p>
      <div class="row g-2">
        <?php foreach ($pd_pilihan as $butir): ?>
          <div class="col-md-4">
            <div class="border rounded px-3 py-2 small d-flex justify-content-between align-items-center">
              <span><?= htmlspecialchars((string) $butir['nilai']) ?></span>
              <span class="badge <?= $butir['dari_db'] ? 'text-bg-success' : 'text-bg-secondary' ?>">
                <?= $butir['dari_db'] ? (int) $butir['jumlah'] . ' akun' : 'bawaan' ?>
              </span>
            </div>
          </div>
        <?php endforeach; ?>
      </div>
    </div>
  </div>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <h5 class="card-title">3. Akun RTS / TF yang sales_district-nya masih KOSONG</h5>
      <p class="text-muted small mb-2">
        Akun ini tidak akan melihat data customer pada aplikasi, sebab cakupan
        datanya dibatasi per district. Isi districtnya pada halaman Kelola User.
      </p>

      <?php if (!$pd_kosong): ?>
        <div class="alert alert-success mb-0">Tidak ada. Seluruh akun RTS/TF sudah berdistrict.</div>
      <?php else: ?>
        <ul class="mb-0">
          <?php foreach ($pd_kosong as $baris): ?>
            <li>
              <b><?= htmlspecialchars((string) $baris['nama_lengkap']) ?></b>
              &middot; <?= htmlspecialchars((string) $baris['username']) ?>
              &middot; <?= htmlspecialchars((string) $baris['role']) ?>
            </li>
          <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </div>
  </div>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <h5 class="card-title">4. Sebaran role dan status akun</h5>
      <?php if (!$pd_role): ?>
        <div class="text-muted small">Tidak terbaca.</div>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm table-striped mb-0">
            <thead class="table-light">
              <tr><th>Role</th><th>Status</th><th class="text-end">Jumlah</th></tr>
            </thead>
            <tbody>
              <?php foreach ($pd_role as $baris): ?>
                <tr>
                  <td class="fw-semibold"><?= htmlspecialchars((string) $baris['role']) ?></td>
                  <td><?= htmlspecialchars((string) $baris['status_aktif']) ?></td>
                  <td class="text-end"><?= (int) $baris['jumlah'] ?></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>

      <?php if ($pd_admin): ?>
        <p class="text-muted small mt-3 mb-1">Akun ADMIN / ASS yang ada:</p>
        <ul class="small mb-0">
          <?php foreach ($pd_admin as $baris): ?>
            <li>
              <?= htmlspecialchars((string) $baris['role']) ?> &middot;
              <b><?= htmlspecialchars((string) $baris['nama_lengkap']) ?></b>
              (<?= htmlspecialchars((string) $baris['username']) ?>)
              &middot; district: <?= htmlspecialchars((string) ($baris['sales_district'] !== '' ? $baris['sales_district'] : '-')) ?>
            </li>
          <?php endforeach; ?>
        </ul>
      <?php endif; ?>
    </div>
  </div>

  <div class="card border-0 shadow-sm mb-3">
    <div class="card-body">
      <h5 class="card-title">5. District pada tabel master_toko (data customer)</h5>
      <p class="text-muted small mb-2">
        Dipakai sebagai pembanding. Bila ada district pada daftar ini yang belum
        ada pada sales_users, berarti belum ada petugas yang ditugaskan di sana.
      </p>

      <?php if (!$pd_toko_ada): ?>
        <div class="alert alert-light border mb-0">Kolom district pada master_toko tidak ditemukan.</div>
      <?php elseif (!$pd_toko): ?>
        <div class="alert alert-light border mb-0">Belum ada nilai district pada master_toko.</div>
      <?php else: ?>
        <div class="table-responsive" style="max-height:360px;overflow:auto">
          <table class="table table-sm table-striped mb-0">
            <thead class="table-light"><tr><th>District customer</th><th class="text-end">Jumlah customer</th></tr></thead>
            <tbody>
              <?php foreach ($pd_toko as $baris): ?>
                <tr>
                  <td><?= htmlspecialchars((string) $baris['district']) ?></td>
                  <td class="text-end"><?= (int) $baris['jumlah'] ?></td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <p class="text-muted small">
    Sesudah selesai diperiksa, berkas <code>periksa_district.php</code> boleh dihapus dari hosting.
    &middot; <a href="daftar.php">Buka halaman pendaftaran</a>
    &middot; <a href="index.php">Halaman masuk</a>
  </p>

</main>
</body>
</html>
