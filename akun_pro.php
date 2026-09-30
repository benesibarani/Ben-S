<?php
/*
 * ============================================================================
 *  RTS PANEL BY BENE - HALAMAN PENGATURAN AKUN PRO
 *  Berkas : akun_pro.php   (letakkan di public_html, satu folder dengan
 *                           dashboard.php dan akun pengguna lainnya)
 *
 *  KEGUNAAN
 *  --------
 *  Menandai akun mana yang berstatus PRO (berlangganan) dan mana yang GRATIS.
 *
 *  AKIBATNYA PADA APLIKASI ANDROID (pilihan Bapak - pilihan b):
 *     - Akun GRATIS : iklan tampil pada beranda dan pada setiap menu
 *     - Akun PRO    : iklan tidak tampil sama sekali
 *
 *  CATATAN
 *  -------
 *  - Hanya akun dengan role ADMIN yang dapat membuka halaman ini.
 *  - Halaman ini mengubah SATU kolom saja: sales_users.akun_pro
 *    (1 = PRO, 0 = GRATIS). Kolom lain tidak disentuh.
 *  - Sebelum kolomnya ada, halaman ini akan meminta Anda menjalankan
 *    RTS_PANEL_AKUN_PRO.sql lebih dahulu (tombol tersedia di bawah).
 *  - Tidak ada password atau data pribadi yang ditampilkan pada halaman ini.
 * ============================================================================
 */

/* --------------------------------------------------------------------------
 * VERSI BERKAS: 3  (30 September 2026 - 15:00)
 * ------------------------------------------------------------------------ */
define('AP_VERSI_BERKAS', 3);

require_once __DIR__ . '/config.php';

/* --------------------------------------------------------------------------
 * MEMULAI SESSION
 *
 * Sama seperti app_versi.php: halaman ini TIDAK boleh bergantung pada
 * config.php untuk memulai session. Bila session tidak aktif, $_SESSION
 * kosong, halaman mengira pengunjung belum login, lalu mengalihkannya ke
 * index.php - dan index.php mengalihkannya lagi ke dashboard.php. Akibatnya
 * halaman ini seolah-olah tidak dapat dibuka.
 * ------------------------------------------------------------------------ */
if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}

/* --------------------------------------------------------------------------
 * HALAMAN PEMERIKSA - ?diagnosa=1
 * Diletakkan SEBELUM semua pengalihan supaya hasilnya selalu dapat dilihat.
 * ------------------------------------------------------------------------ */
if (isset($_GET['diagnosa'])) {
    header('Content-Type: text/plain; charset=utf-8');

    $ap_samar = static function (string $nilai): string {
        $nilai = trim($nilai);

        if ($nilai === '') {
            return '(kosong)';
        }

        if (strlen($nilai) <= 4) {
            return str_repeat('*', strlen($nilai));
        }

        return substr($nilai, 0, 3) . '*** (' . strlen($nilai) . ' huruf)';
    };

    echo "PEMERIKSAAN HALAMAN AKUN PRO\n";
    echo "============================\n";
    echo 'VERSI BERKAS  : ' . AP_VERSI_BERKAS . "\n";
    echo 'Waktu server  : ' . date('d-m-Y H:i:s') . "\n";
    echo 'PHP           : ' . PHP_VERSION . "\n\n";

    echo "SESSION\n";
    echo '  status aktif : ' . (session_status() === PHP_SESSION_ACTIVE ? 'YA' : 'TIDAK') . "\n";
    echo '  jumlah kunci : ' . count($_SESSION) . "\n";

    foreach (array_keys($_SESSION) as $ap_kunci_ada) {
        echo '  - ' . $ap_kunci_ada . "\n";
    }

    echo "\nKoneksi database: "
        . (isset($conn) && $conn instanceof mysqli ? 'ADA' : 'TIDAK ADA') . "\n";

    echo "\nHalaman ini tidak mengubah data apa pun.\n";

    exit;
}

/* --------------------------------------------------------------------------
 * PENJAGA HALAMAN - hanya ADMIN
 *
 * PERBAIKAN (30 September 2026 - sama seperti app_versi.php):
 * Penjagaan TIDAK boleh hanya memakai $_SESSION['email']. Bila kunci itu
 * kosong (misalnya akun yang kolom emailnya kosong pada tabel sales_users),
 * halaman ini mengalihkan pengunjung ke index.php; halaman login itu melihat
 * session masih aktif lalu mengalihkan lagi ke dashboard.php. Akibatnya Admin
 * yang sah seolah-olah tidak dapat membuka halaman ini.
 *
 * Pemeriksaan sekarang berlapis:
 *   - login : salah satu penanda sudah ada (is_logged_in, user_id, username,
 *             nama, email)
 *   - peran : session (role / user_role); bila kosong dibaca dari
 *             sales_users memakai username
 * ------------------------------------------------------------------------ */

$ap_penanda_login = ['is_logged_in', 'user_id', 'username', 'nama', 'email'];
$ap_sudah_login = false;

foreach ($ap_penanda_login as $ap_kunci_login) {
    if (!empty($_SESSION[$ap_kunci_login])) {
        $ap_sudah_login = true;
        break;
    }
}

if (!$ap_sudah_login) {
    header('Location: index.php');
    exit;
}

$ap_role = '';

foreach (['role', 'user_role'] as $ap_kunci_role) {
    $ap_nilai_role = strtoupper(trim((string) ($_SESSION[$ap_kunci_role] ?? '')));

    if ($ap_nilai_role !== '') {
        $ap_role = $ap_nilai_role;
        break;
    }
}

if ($ap_role === '' && isset($conn) && $conn instanceof mysqli) {
    $ap_username = '';

    foreach (['username', 'user', 'username_login'] as $ap_kunci_user) {
        $ap_nilai_user = trim((string) ($_SESSION[$ap_kunci_user] ?? ''));

        if ($ap_nilai_user !== '') {
            $ap_username = $ap_nilai_user;
            break;
        }
    }

    if ($ap_username !== '') {
        $ap_stmt_peran = @$conn->prepare(
            'SELECT role FROM sales_users WHERE username = ? LIMIT 1'
        );

        if ($ap_stmt_peran) {
            $ap_stmt_peran->bind_param('s', $ap_username);
            $ap_stmt_peran->execute();
            $ap_hasil_peran = $ap_stmt_peran->get_result();
            $ap_baris_peran = $ap_hasil_peran ? $ap_hasil_peran->fetch_assoc() : null;
            $ap_stmt_peran->close();

            if ($ap_baris_peran) {
                $ap_role = strtoupper(trim((string) ($ap_baris_peran['role'] ?? '')));
            }
        }
    }
}

/* "SUPER ADMIN" dan "SUPER_ADMIN" diperlakukan sama dengan ADMIN. */
if (str_replace([' ', '_'], '', $ap_role) === 'SUPERADMIN') {
    $ap_role = 'ADMIN';
}

if ($ap_role !== 'ADMIN') {
    header('Location: dashboard.php');
    exit;
}

require_once __DIR__ . '/header.php';

/* --------------------------------------------------------------------------
 * PEMERIKSAAN KOLOM
 * -------------------------------------------------------------------------- */
$ap_pesan = '';
$ap_galat = '';

$ap_kolom_siap = false;

/* Pemeriksaan memakai SHOW COLUMNS, BUKAN information_schema.
   Sebabnya: akun database cPanel (cpses_...) tidak diberi izin membaca
   information_schema, sehingga muncul kesalahan:
      #1044 - Access denied for user 'cpses_...'@'localhost'
              to database 'information_schema'
   SHOW COLUMNS selalu tersedia dan hasilnya sama. */
$ap_hasil_kolom = @$conn->query("SHOW COLUMNS FROM sales_users LIKE 'akun_pro'");

if ($ap_hasil_kolom instanceof mysqli_result) {
    $ap_kolom_siap = $ap_hasil_kolom->num_rows > 0;
    $ap_hasil_kolom->free();
}

/* --------------------------------------------------------------------------
 * PROSES SIMPAN / UBAH STATUS
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['ap_simpan']) && $ap_kolom_siap) {
    $ap_id = (int)($_POST['ap_id'] ?? 0);
    $ap_nilai = (int)($_POST['ap_nilai'] ?? 0) === 1 ? 1 : 0;

    if ($ap_id < 1) {
        $ap_galat = 'Data akun tidak dikenali.';
    } else {
        /* Akun sendiri tidak boleh diturunkan menjadi GRATIS, supaya ADMIN
           tidak terkunci dari halaman ini karena keliru menekan tombol. */
        $ap_id_sendiri = 0;

        $ap_cari = $conn->prepare('SELECT id FROM sales_users WHERE email = ? LIMIT 1');

        if ($ap_cari) {
            $ap_email = (string)$_SESSION['email'];
            $ap_cari->bind_param('s', $ap_email);
            $ap_cari->execute();
            $ap_baris = $ap_cari->get_result()->fetch_assoc();
            $ap_cari->close();

            $ap_id_sendiri = (int)($ap_baris['id'] ?? 0);
        }

        if ($ap_id === $ap_id_sendiri && $ap_nilai === 0) {
            $ap_galat = 'Akun Anda sendiri tidak dapat diubah menjadi GRATIS. '
                . 'Ubah akun lain terlebih dahulu.';
        } else {
            $ap_ubah = $conn->prepare('UPDATE sales_users SET akun_pro = ? WHERE id = ?');

            if ($ap_ubah) {
                $ap_ubah->bind_param('ii', $ap_nilai, $ap_id);

                if ($ap_ubah->execute()) {
                    $ap_pesan = 'Status akun berhasil diubah menjadi '
                        . ($ap_nilai === 1 ? 'PRO (bebas iklan)' : 'GRATIS (dengan iklan)')
                        . '. Perubahan ini terlihat pada aplikasi setelah pengguna '
                        . 'login kembali atau membuka aplikasi lagi.';
                } else {
                    $ap_galat = 'Gagal menyimpan perubahan: ' . $ap_ubah->error;
                }

                $ap_ubah->close();
            } else {
                $ap_galat = 'Gagal menyiapkan perintah perubahan data.';
            }
        }
    }
}

/* --------------------------------------------------------------------------
 * DATA AKUN UNTUK TAMPILAN
 * -------------------------------------------------------------------------- */
$ap_daftar = [];
$ap_ringkas = ['total' => 0, 'pro' => 0, 'gratis' => 0];

if ($ap_kolom_siap) {
    $ap_sql = 'SELECT id, username, nama_lengkap, email, role, salesman, sales_district, '
        . 'status_aktif, akun_pro FROM sales_users ORDER BY akun_pro DESC, role ASC, username ASC';

    $ap_ambil = $conn->query($ap_sql);

    if ($ap_ambil) {
        while ($ap_row = $ap_ambil->fetch_assoc()) {
            $ap_daftar[] = $ap_row;

            $ap_ringkas['total']++;

            if ((int)$ap_row['akun_pro'] === 1) {
                $ap_ringkas['pro']++;
            } else {
                $ap_ringkas['gratis']++;
            }
        }
    }
}

/* Alamat halaman ini sendiri, untuk ditampilkan pada kotak petunjuk. */
$ap_skema = (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off')
    ? 'https' : 'http';
$ap_alamat = $ap_skema . '://' . (string)($_SERVER['HTTP_HOST'] ?? '') . '/akun_pro.php';

?>

<style>
.ap-card{background:#fff;border:1px solid #eadfd6;border-radius:16px;box-shadow:0 6px 18px rgba(74,44,34,.06)}
.ap-kotak{border:1px solid #eadfd6;border-radius:14px;padding:14px 16px;background:#fff}
.ap-kotak .label{font-size:12px;color:#8a7d76}
.ap-kotak .nilai{font-weight:800;color:#3a2a24;font-size:20px}
.ap-pro{background:#e8f5ec;color:#2f6b45;border:1px solid #d5e6d9;border-radius:30px;padding:3px 10px;font-size:11px;font-weight:800}
.ap-gratis{background:#faecee;color:#7b1113;border:1px solid #f0d5da;border-radius:30px;padding:3px 10px;font-size:11px;font-weight:800}
.ap-petunjuk{background:#fdf6ec;border:1px solid #f0e2cf;border-radius:14px;padding:14px 16px;font-size:13px;color:#7a5a26}
</style>

<div class="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
  <div>
    <h4 class="mb-1"><i class="fa-solid fa-workspace-premium text-danger me-2"></i>Akun GRATIS &amp; Akun PRO</h4>
    <div class="text-muted small">
      Akun GRATIS melihat iklan. Akun PRO bebas iklan.
    </div>
  </div>
  <a class="btn btn-outline-secondary btn-sm" href="dashboard.php">
    <i class="fa-solid fa-arrow-left me-1"></i>Kembali ke Dashboard
  </a>
</div>

<?php if ($ap_pesan !== ''): ?>
  <div class="alert alert-success"><i class="fa-solid fa-circle-check me-2"></i><?= htmlspecialchars($ap_pesan) ?></div>
<?php endif; ?>

<?php if ($ap_galat !== ''): ?>
  <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation me-2"></i><?= htmlspecialchars($ap_galat) ?></div>
<?php endif; ?>

<?php if (!$ap_kolom_siap): ?>
  <div class="ap-card p-3 p-md-4">
    <h6 class="mb-3"><i class="fa-solid fa-triangle-exclamation text-warning me-2"></i>Kolom database belum ada</h6>

    <p class="mb-3">
      Halaman ini membutuhkan satu kolom tambahan bernama <code>akun_pro</code> pada tabel
      <code>sales_users</code>. Kolom itu belum ada pada database ini, jadi halaman belum dapat
      menampilkan daftar akun.
    </p>

    <div class="ap-petunjuk mb-3">
      <strong>Cara membuat kolomnya (aman - tidak mengubah data yang sudah ada):</strong>
      <ol class="mb-0 ps-3 mt-2">
        <li>Buka <strong>phpMyAdmin</strong> pada cPanel.</li>
        <li>Pilih database yang sedang dipakai (untuk produksi: <code>benedics_bene_sales</code>).</li>
        <li>Buka tab <strong>SQL</strong>, tempel perintah berikut, lalu tekan <strong>Kirim</strong>:</li>
      </ol>
      <div class="mt-2 p-2 bg-white border rounded" style="font-family:monospace;font-size:12px">
        ALTER TABLE sales_users ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;
      </div>
      <div class="mt-2">
        Bila muncul pesan <code>#1060 - Duplicate column name 'akun_pro'</code>,
        artinya kolomnya sudah ada - tidak ada yang rusak. Muat ulang halaman ini.
      </div>
      <div class="mt-2">
        Perintah itu hanya <strong>menambah satu kolom</strong> dan mengisinya dengan 0 (GRATIS)
        untuk seluruh akun. Data akun, password, dan penjualan tidak berubah sama sekali.
      </div>
    </div>

    <div class="ap-petunjuk">
      Disarankan: coba lebih dahulu pada database <strong>uji coba</strong>
      (<code>benedics_coba</code>), pastikan berjalan, baru dikerjakan pada produksi
      setelah backup database.
    </div>
  </div>

<?php else: ?>
  <div class="row g-3 mb-3">
    <div class="col-4">
      <div class="ap-kotak h-100"><div class="label">Tidak berlangganan</div><div class="nilai"><?= (int)$ap_ringkas['total'] ?></div><div class="label">Seluruh akun</div></div>
    </div>
    <div class="col-4">
      <div class="ap-kotak h-100"><div class="label">Akun PRO</div><div class="nilai text-success"><?= (int)$ap_ringkas['pro'] ?></div><div class="label">Bebas iklan</div></div>
    </div>
    <div class="col-4">
      <div class="ap-kotak h-100"><div class="label">Akun GRATIS</div><div class="nilai text-danger"><?= (int)$ap_ringkas['gratis'] ?></div><div class="label">Dengan iklan</div></div>
    </div>
  </div>

  <div class="ap-card p-3 p-md-4">
    <div class="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
      <h6 class="mb-0"><i class="fa-solid fa-users text-danger me-2"></i>Daftar Akun</h6>
      <input type="text" class="form-control form-control-sm" style="max-width:260px"
             placeholder="Cari nama, username, atau email..." oninput="apSaring(this.value)">
    </div>

    <div class="table-responsive">
      <table class="table table-hover align-middle mb-0" id="apTabel">
        <thead>
          <tr>
            <th>Nama</th>
            <th>Username</th>
            <th>Role</th>
            <th>District / Salesman</th>
            <th>Status</th>
            <th class="text-end">Tingkat Akun</th>
            <th class="text-end">Ubah</th>
          </tr>
        </thead>
        <tbody>
          <?php foreach ($ap_daftar as $ap_akun): ?>
            <?php $ap_pro = (int)$ap_akun['akun_pro'] === 1; ?>
            <tr>
              <td>
                <strong><?= htmlspecialchars((string)($ap_akun['nama_lengkap'] ?? '')) ?></strong>
                <div class="text-muted small"><?= htmlspecialchars((string)($ap_akun['email'] ?? '')) ?></div>
              </td>
              <td class="small"><?= htmlspecialchars((string)($ap_akun['username'] ?? '')) ?></td>
              <td class="small"><span class="badge bg-light text-dark border"><?= htmlspecialchars(strtoupper((string)($ap_akun['role'] ?? ''))) ?></span></td>
              <td class="small text-muted">
                <?= htmlspecialchars((string)($ap_akun['sales_district'] ?? '')) ?>
                <?php if (!empty($ap_akun['salesman'])): ?>
                  <div><?= htmlspecialchars((string)$ap_akun['salesman']) ?></div>
                <?php endif; ?>
              </td>
              <td class="small">
                <?= strcasecmp((string)($ap_akun['status_aktif'] ?? 'Aktif'), 'Aktif') === 0
                    ? '<span class="text-success">Aktif</span>'
                    : '<span class="text-danger">Tidak aktif</span>' ?>
              </td>
              <td class="text-end">
                <span class="<?= $ap_pro ? 'ap-pro' : 'ap-gratis' ?>">
                  <?= $ap_pro ? 'PRO - bebas iklan' : 'GRATIS - dengan iklan' ?>
                </span>
              </td>
              <td class="text-end">
                <form method="post" class="d-inline">
                  <input type="hidden" name="ap_simpan" value="1">
                  <input type="hidden" name="ap_id" value="<?= (int)$ap_akun['id'] ?>">
                  <input type="hidden" name="ap_nilai" value="<?= $ap_pro ? 0 : 1 ?>">
                  <button type="submit" class="btn btn-sm <?= $ap_pro ? 'btn-outline-secondary' : 'btn-outline-success' ?>">
                    <?= $ap_pro ? 'Jadikan GRATIS' : 'Jadikan PRO' ?>
                  </button>
                </form>
              </td>
            </tr>
          <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>

  <script>
  function apSaring(kata) {
    const cari = (kata || '').toLowerCase();
    const baris = document.querySelectorAll('#apTabel tbody tr');

    baris.forEach(function (tr) {
      tr.style.display = tr.innerText.toLowerCase().indexOf(cari) >= 0 ? '' : 'none';
    });
  }
  </script>

  <div class="ap-petunjuk mt-3">
    <strong><i class="fa-solid fa-circle-info me-1"></i>Yang perlu diketahui</strong>
    <ul class="mb-0 ps-3 mt-2">
      <li>Perubahan tingkat akun terlihat pada aplikasi HP setelah pengguna <strong>login kembali</strong>
          atau membuka aplikasi lagi (aplikasi membaca data akun saat login).</li>
      <li>Akun Anda sendiri tidak dapat diubah menjadi GRATIS, agar tidak terkunci dari halaman ini.</li>
      <li>Untuk melihat halaman ini langsung, buka: <code><?= htmlspecialchars($ap_alamat) ?></code></li>
      <li>Pembayaran/langganan belum ditangani pada tahap ini. Halaman ini hanya menandai akun;
          pencatatan pembayaran dapat ditambahkan kemudian bila diperlukan.</li>
    </ul>
  </div>
<?php endif; ?>

<?php require_once __DIR__ . '/footer.php'; ?>
