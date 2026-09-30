<?php
/*
 * ============================================================================
 *  RTS PANEL BY BENE - HALAMAN PENGELOLAAN LANGGANAN PRO
 *  Berkas : langganan_admin.php  (letakkan di public_html, satu folder dengan
 *                                  akun_pro.php dan dashboard.php)
 *
 *  KEGUNAAN
 *  --------
 *  1. Memberikan masa langganan PRO kepada petugas:
 *        + 30 hari (1 bulan)  - masa lama DITAMBAHKAN, tidak hangus
 *        + 90 hari (3 bulan)
 *        + uji coba 7 hari    - bila petugas belum pernah mencobanya
 *        + hentikan langganan - akun kembali GRATIS (iklan tampil kembali)
 *
 *  2. Memeriksa pernyataan pembayaran QRIS dari aplikasi:
 *        petugas menekan "SAYA SUDAH BAYAR" pada aplikasi -> muncul di sini ->
 *        Admin menekan SETUJUI -> masa PRO 30 hari langsung diberikan.
 *
 *  3. Menyimpan gambar QRIS milik Bapak untuk dipakai website/aplikasi.
 *
 *  4. Tombol PERBARUI DATABASE untuk membuat kolom-kolom baru
 *     (foto_profil, pro_mulai, pro_selesai, trial_mulai, trial_selesai)
 *     beserta tabel pembayaran_pro - tanpa perlu menyentuh phpMyAdmin.
 *
 *  CATATAN
 *  -------
 *  - Hanya akun dengan role ADMIN yang dapat membuka halaman ini.
 *  - Halaman ini TIDAK memuat password siapa pun.
 *  - Berkas inti aturannya ada pada api/langganan_inti.php, sehingga aplikasi
 *    Android dan halaman ini memakai aturan yang sama (30 hari, uji coba 7 hari).
 * ============================================================================
 */

/* --------------------------------------------------------------------------
 * VERSI BERKAS: 1  (30 September 2026 - 23:55)
 * ------------------------------------------------------------------------ */
define('LG_VERSI_BERKAS', 1);

require_once __DIR__ . '/config.php';

if (is_file(__DIR__ . '/api/langganan_inti.php')) {
    require_once __DIR__ . '/api/langganan_inti.php';
}

if (session_status() !== PHP_SESSION_ACTIVE) {
    @session_start();
}

/* --------------------------------------------------------------- diagnostik */
if (isset($_GET['diagnosa'])) {
    header('Content-Type: text/plain; charset=utf-8');

    echo "PEMERIKSAAN HALAMAN LANGGANAN PRO\n";
    echo "=================================\n";
    echo 'VERSI BERKAS   : ' . LG_VERSI_BERKAS . "\n";
    echo 'Waktu server   : ' . date('d-m-Y H:i:s') . "\n";
    echo 'PHP            : ' . PHP_VERSION . "\n";
    echo 'Koneksi DB     : ' . (isset($conn) && $conn instanceof mysqli ? 'ADA' : 'TIDAK ADA') . "\n";
    echo 'Berkas inti    : ' . (function_exists('rts_lg_status') ? 'ADA' : 'TIDAK ADA') . "\n";
    echo 'Session aktif  : ' . (session_status() === PHP_SESSION_ACTIVE ? 'YA' : 'TIDAK') . "\n";
    echo 'Kunci session  : ' . implode(', ', array_keys($_SESSION)) . "\n";

    if (isset($conn) && $conn instanceof mysqli && function_exists('rts_lg_kolom_tersedia')) {
        echo "\nKOLOM LANGGANAN\n";

        foreach (rts_lg_kolom_tersedia($conn) as $nama => $ada) {
            echo '  ' . str_pad($nama, 16, ' ') . ': ' . ($ada ? 'ADA' : 'BELUM ADA') . "\n";
        }

        echo "\nTabel pembayaran_pro : "
            . (function_exists('rts_lg_tabel_pembayaran') && rts_lg_tabel_pembayaran($conn) ? 'ADA' : 'BELUM ADA') . "\n";
    }

    echo "\nHalaman ini tidak mengubah data apa pun.\n";

    exit;
}

/* ------------------------------------------------------------------ penjaga */
$lg_penanda_login = ['is_logged_in', 'user_id', 'username', 'nama', 'email'];
$lg_sudah_login = false;

foreach ($lg_penanda_login as $lg_kunci) {
    if (!empty($_SESSION[$lg_kunci])) {
        $lg_sudah_login = true;
        break;
    }
}

if (!$lg_sudah_login) {
    header('Location: index.php');
    exit;
}

$lg_peran = strtoupper(trim((string) ($_SESSION['role'] ?? $_SESSION['user_role'] ?? '')));

if ($lg_peran === '' && isset($conn) && $conn instanceof mysqli && !empty($_SESSION['username'])) {
    $lg_stmt = $conn->prepare('SELECT role FROM sales_users WHERE username = ? LIMIT 1');

    if ($lg_stmt) {
        $lg_stmt->bind_param('s', $_SESSION['username']);
        $lg_stmt->execute();
        $lg_hasil = $lg_stmt->get_result();

        if ($lg_hasil && ($lg_baris_peran = $lg_hasil->fetch_assoc())) {
            $lg_peran = strtoupper(trim((string) $lg_baris_peran['role']));
        }

        $lg_stmt->close();
    }
}

if ($lg_peran !== 'ADMIN') {
    http_response_code(403);
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="id"><head><meta charset="utf-8">'
        . '<title>Akses ditolak</title></head><body style="font-family:Segoe UI,Arial;padding:40px">'
        . '<h2 style="color:#8c1c25">Akses ditolak</h2>'
        . '<p>Halaman pengelolaan langganan hanya dapat dibuka oleh akun <b>ADMIN</b>.</p>'
        . '<p>Peran yang terbaca: <b>' . htmlspecialchars($lg_peran === '' ? '(kosong)' : $lg_peran) . '</b></p>'
        . '<p><a href="index.php">Kembali ke beranda</a></p></body></html>';
    exit;
}

if (!isset($conn) || !($conn instanceof mysqli)) {
    header('Content-Type: text/html; charset=utf-8');
    echo '<!doctype html><html lang="id"><head><meta charset="utf-8"><title>Database</title></head>'
        . '<body style="font-family:Segoe UI,Arial;padding:40px">'
        . '<h2 style="color:#8c1c25">Koneksi database tidak ditemukan</h2>'
        . '<p>Periksa berkas <code>config.php</code> pada hosting.</p></body></html>';
    exit;
}

$lg_pelaku = (string) ($_SESSION['username'] ?? $_SESSION['email'] ?? 'ADMIN');
$lg_kabar = [];
$lg_kabar_jenis = 'ok';

/* ------------------------------------------------------------------- aksi */
$lg_aksi = trim((string) ($_POST['aksi'] ?? $_GET['aksi'] ?? ''));

if ($lg_aksi !== '') {
    if ($lg_aksi === 'perbarui_database') {
        if (function_exists('rts_lg_siapkan_database')) {
            $lg_kabar = rts_lg_siapkan_database($conn);
        } else {
            $lg_kabar = ['Berkas api/langganan_inti.php belum ada di hosting.'];
            $lg_kabar_jenis = 'galat';
        }
    } elseif ($lg_aksi === 'aktifkan' || $lg_aksi === 'trial' || $lg_aksi === 'hentikan') {
        $lg_id = (int) ($_POST['user_id'] ?? 0);
        $lg_hari = (int) ($_POST['hari'] ?? 0);

        if ($lg_id <= 0) {
            $lg_kabar = ['Pengguna tidak dipilih.'];
            $lg_kabar_jenis = 'galat';
        } elseif ($lg_aksi === 'trial') {
            $lg_hasil = rts_lg_mulai_trial($conn, $lg_id);
            $lg_kabar = [(string) $lg_hasil['pesan']];
            $lg_kabar_jenis = !empty($lg_hasil['berhasil']) ? 'ok' : 'galat';
        } elseif ($lg_aksi === 'hentikan') {
            $lg_bagian = [];

            foreach (['akun_pro' => 'akun_pro = 0', 'pro_selesai' => 'pro_selesai = NOW()'] as $lg_kolom => $lg_sql) {
                if (rts_lg_ada_kolom($conn, $lg_kolom)) {
                    $lg_bagian[] = $lg_sql;
                }
            }

            if (rts_lg_ada_kolom($conn, 'trial_mulai')) {
                $lg_bagian[] = "trial_mulai = IF(trial_mulai IS NULL OR trial_mulai = '', NOW(), trial_mulai)";
            }

            if (rts_lg_ada_kolom($conn, 'trial_selesai')) {
                $lg_bagian[] = 'trial_selesai = NOW()';
            }

            if ($lg_bagian && @$conn->query('UPDATE sales_users SET ' . implode(', ', $lg_bagian) . ' WHERE id = ' . $lg_id)) {
                $lg_kabar = ['Langganan dan uji coba dihentikan. Akun kembali GRATIS (iklan tampil kembali).'];
            } else {
                $lg_kabar = ['Gagal menghentikan langganan: ' . $conn->error];
                $lg_kabar_jenis = 'galat';
            }
        } else {
            $lg_hasil = rts_lg_beri($conn, $lg_id, $lg_hari > 0 ? $lg_hari : rts_lg_durasi(), 'ADMIN ' . $lg_pelaku);
            $lg_kabar = [(string) $lg_hasil['pesan']];
            $lg_kabar_jenis = !empty($lg_hasil['berhasil']) ? 'ok' : 'galat';
        }
    } elseif ($lg_aksi === 'setujui_klaim' || $lg_aksi === 'tolak_klaim') {
        $lg_bayar_id = (int) ($_POST['bayar_id'] ?? 0);

        if ($lg_bayar_id > 0) {
            $lg_hasil_bayar = @$conn->query(
                'SELECT user_id, jumlah, hari FROM pembayaran_pro WHERE id = ' . $lg_bayar_id . ' LIMIT 1'
            );

            if ($lg_hasil_bayar instanceof mysqli_result && ($lg_klaim = $lg_hasil_bayar->fetch_assoc())) {
                $lg_id_pemilik = (int) $lg_klaim['user_id'];
                $lg_hasil_bayar->free();

                if ($lg_aksi === 'setujui_klaim') {
                    $lg_hari_klaim = (int) $lg_klaim['hari'] > 0 ? (int) $lg_klaim['hari'] : rts_lg_durasi();
                    $lg_hasil = rts_lg_beri($conn, $lg_id_pemilik, $lg_hari_klaim, 'PEMBAYARAN QRIS');
                    $lg_kabar = ['Pembayaran disetujui. ' . (string) $lg_hasil['pesan']];
                    $lg_kabar_jenis = !empty($lg_hasil['berhasil']) ? 'ok' : 'galat';

                    if (!empty($lg_hasil['berhasil']) && is_file(__DIR__ . '/api/notif_otomatis.php')) {
                        require_once __DIR__ . '/api/notif_otomatis.php';

                        if (function_exists('rts_notif_kirim')) {
                            $lg_email = '';

                            $lg_cari = @$conn->query('SELECT email FROM sales_users WHERE id = ' . $lg_id_pemilik . ' LIMIT 1');

                            if ($lg_cari instanceof mysqli_result) {
                                $lg_email = (string) ($lg_cari->fetch_assoc()['email'] ?? '');
                                $lg_cari->free();
                            }

                            if ($lg_email !== '') {
                                rts_notif_kirim(
                                    $conn,
                                    [$lg_email],
                                    'Akun PRO Anda Sudah Aktif',
                                    'Pembayaran Anda sudah diperiksa. Akun PRO aktif '
                                        . $lg_hari_klaim . ' hari ke depan. Terima kasih.',
                                    'LANGGANAN',
                                    ['tipe' => 'langganan', 'halaman' => 'langganan'],
                                    'pengguna',
                                    $lg_id_pemilik
                                );
                            }
                        }
                    }
                } else {
                    @$conn->query("UPDATE pembayaran_pro SET status = 'DITOLAK', diproses_pada = NOW() WHERE id = " . $lg_bayar_id);
                    $lg_kabar = ['Pernyataan pembayaran ditolak. Petugas tetap GRATIS sampai pembayaran diterima.'];
                }
            } else {
                $lg_kabar = ['Data pembayaran tidak ditemukan.'];
                $lg_kabar_jenis = 'galat';
            }
        }
    } elseif ($lg_aksi === 'unggah_qris') {
        if (isset($_FILES['qris']) && (int) ($_FILES['qris']['error'] ?? 1) === 0) {
            $lg_info_gambar = @getimagesize((string) $_FILES['qris']['tmp_name']);

            if (!is_array($lg_info_gambar)) {
                $lg_kabar = ['Berkas yang diunggah bukan gambar.'];
                $lg_kabar_jenis = 'galat';
            } else {
                $lg_folder = __DIR__ . '/uploads';

                if (!is_dir($lg_folder)) {
                    @mkdir($lg_folder, 0755, true);
                }

                if (@move_uploaded_file((string) $_FILES['qris']['tmp_name'], $lg_folder . '/qris_bene_s.jpg')) {
                    $lg_kabar = ['Gambar QRIS tersimpan. Aplikasi dapat menampilkan gambar ini.'];
                } else {
                    $lg_kabar = ['Gambar QRIS gagal disimpan.'];
                    $lg_kabar_jenis = 'galat';
                }
            }
        } else {
            $lg_kabar = ['Belum ada berkas QRIS yang dipilih.'];
            $lg_kabar_jenis = 'galat';
        }
    }
}

/* -------------------------------------------------------------------- data */
$lg_punya_kolom = function_exists('rts_lg_kolom_tersedia')
    ? rts_lg_kolom_tersedia($conn)
    : ['akun_pro' => false, 'pro_mulai' => false, 'pro_selesai' => false, 'trial_mulai' => false, 'trial_selesai' => false, 'foto_profil' => false];

$lg_daftar = [];

$lg_hasil_user = @$conn->query(
    'SELECT id, username, nama_lengkap, email, role, status_aktif'
    . ($lg_punya_kolom['akun_pro'] ? ', akun_pro' : ", '0' AS akun_pro")
    . ($lg_punya_kolom['pro_mulai'] ? ', pro_mulai' : ", '' AS pro_mulai")
    . ($lg_punya_kolom['pro_selesai'] ? ', pro_selesai' : ", '' AS pro_selesai")
    . ($lg_punya_kolom['trial_mulai'] ? ', trial_mulai' : ", '' AS trial_mulai")
    . ($lg_punya_kolom['trial_selesai'] ? ', trial_selesai' : ", '' AS trial_selesai")
    . ($lg_punya_kolom['foto_profil'] ? ', foto_profil' : ", '' AS foto_profil")
    . ' FROM sales_users ORDER BY akun_pro DESC, role ASC, username ASC'
);

if ($lg_hasil_user instanceof mysqli_result) {
    while ($lg_baris = $lg_hasil_user->fetch_assoc()) {
        $lg_baris['status'] = rts_lg_status($lg_baris);
        $lg_daftar[] = $lg_baris;
    }

    $lg_hasil_user->free();
}

$lg_daftar_bayar = [];

if (function_exists('rts_lg_tabel_pembayaran') && rts_lg_tabel_pembayaran($conn)) {
    $lg_hasil_bayar = @$conn->query(
        "SELECT p.id, p.user_id, p.jumlah, p.hari, p.catatan, p.status, p.dibuat, p.diproses_pada,
                u.nama_lengkap, u.username, u.role
         FROM pembayaran_pro p
         LEFT JOIN sales_users u ON u.id = p.user_id
         ORDER BY (p.status = 'MENUNGGU') DESC, p.dibuat DESC
         LIMIT 60"
    );

    if ($lg_hasil_bayar instanceof mysqli_result) {
        while ($lg_baris_bayar = $lg_hasil_bayar->fetch_assoc()) {
            $lg_daftar_bayar[] = $lg_baris_bayar;
        }

        $lg_hasil_bayar->free();
    }
}

$lg_jumlah_menunggu = 0;

foreach ($lg_daftar_bayar as $lg_b) {
    if (strtoupper((string) $lg_b['status']) === 'MENUNGGU') {
        $lg_jumlah_menunggu++;
    }
}

$lg_rupiah = static function ($angka): string {
    return 'Rp' . number_format((float) $angka, 0, ',', '.');
};

$lg_qris_ada = is_file(__DIR__ . '/uploads/qris_bene_s.jpg');
?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Langganan PRO - RTS Panel</title>
<style>
  * { box-sizing: border-box; }
  body {
    margin: 0; padding: 0 0 60px;
    font-family: "Segoe UI", Tahoma, Arial, sans-serif;
    background: #f6f4f2; color: #2b2523;
  }
  .top {
    background: linear-gradient(135deg, #6d1017, #a52430);
    color: #fff; padding: 20px 24px;
  }
  .top h1 { margin: 0; font-size: 20px; letter-spacing: .3px; }
  .top p { margin: 6px 0 0; font-size: 13px; opacity: .92; }
  .bungkus { max-width: 1080px; margin: 20px auto; padding: 0 16px; }
  .kartu {
    background: #fff; border-radius: 16px; padding: 18px 20px;
    box-shadow: 0 6px 18px rgba(43, 37, 35, .08); margin-bottom: 18px;
  }
  .kartu h2 { margin: 0 0 12px; font-size: 16px; color: #6d1017; }
  .kabar {
    border-radius: 12px; padding: 12px 14px; margin-bottom: 14px;
    font-size: 13.5px; border: 1px solid #cfe7d6; background: #eef8f1; color: #1d5c35;
  }
  .kabar.galat { border-color: #f0c9c9; background: #fdeeee; color: #8c1c25; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 9px 8px; border-bottom: 1px solid #eee7e2; vertical-align: middle; }
  th { background: #faf7f5; font-size: 12px; text-transform: uppercase; letter-spacing: .4px; color: #6f625d; }
  .lencana {
    display: inline-block; padding: 3px 9px; border-radius: 999px;
    font-size: 11.5px; font-weight: 700;
  }
  .pro { background: #e8f5ec; color: #1d7a45; }
  .trial { background: #fff4e0; color: #9a6206; }
  .gratis { background: #faecee; color: #8c1c25; }
  .tunggu { background: #fff4e0; color: #9a6206; }
  .dibayar { background: #e8f5ec; color: #1d7a45; }
  .ditolak { background: #eee; color: #666; }
  .tombol {
    display: inline-block; border: 0; cursor: pointer; padding: 7px 12px;
    border-radius: 9px; font-size: 12.5px; font-weight: 700; color: #fff;
    background: #a52430; margin: 2px 3px 2px 0;
  }
  .tombol.kecil { padding: 6px 10px; font-size: 12px; }
  .tombol.hijau { background: #1d7a45; }
  .tombol.abu { background: #6f625d; }
  .tombol.biru { background: #1b4d8f; }
  .foto {
    width: 38px; height: 38px; border-radius: 50%; object-fit: cover;
    border: 2px solid #f0e3de; background: #f6f4f2;
  }
  .kecil-teks { font-size: 12px; color: #6f625d; }
  .baris { display: flex; gap: 20px; flex-wrap: wrap; }
  .baris > div { flex: 1 1 300px; }
  .qris { max-width: 220px; border-radius: 12px; border: 1px solid #eee7e2; }
  input[type=file] { font-size: 13px; }
  .kotak-info {
    background: #faf7f5; border: 1px solid #eee7e2; border-radius: 12px;
    padding: 12px 14px; font-size: 13px; line-height: 1.6;
  }
</style>
</head>
<body>

<div class="top">
  <h1>Langganan PRO - RTS Panel By Bene</h1>
  <p>Masa berlaku 30 hari &middot; uji coba gratis 7 hari &middot; pembayaran QRIS <?php echo $lg_rupiah(rts_lg_harga()); ?></p>
</div>

<div class="bungkus">

<?php if ($lg_kabar) { ?>
  <div class="kabar <?php echo $lg_kabar_jenis === 'galat' ? 'galat' : ''; ?>">
    <?php foreach ($lg_kabar as $lg_pesan_kabar) { ?>
      <div><?php echo htmlspecialchars((string) $lg_pesan_kabar); ?></div>
    <?php } ?>
  </div>
<?php } ?>

<?php if (!$lg_punya_kolom['pro_selesai'] || !$lg_punya_kolom['foto_profil']) { ?>
  <div class="kartu">
    <h2>Langkah 1 - Perbarui Database</h2>
    <div class="kotak-info">
      Kolom baru belum lengkap pada database. Tekan tombol di bawah sekali saja.
      Proses ini hanya MENAMBAH kolom yang belum ada dan tidak menghapus data.
    </div>
    <form method="post" style="margin-top:12px">
      <input type="hidden" name="aksi" value="perbarui_database">
      <button class="tombol" type="submit">PERBARUI DATABASE</button>
    </form>
  </div>
<?php } ?>

<div class="kartu">
  <h2>Pernyataan Pembayaran QRIS <?php echo $lg_jumlah_menunggu > 0 ? '(' . $lg_jumlah_menunggu . ' menunggu diperiksa)' : ''; ?></h2>

  <?php if (!$lg_daftar_bayar) { ?>
    <div class="kotak-info">
      Belum ada pernyataan pembayaran. Petugas menekan tombol
      <b>SAYA SUDAH BAYAR</b> pada halaman Langganan PRO di aplikasi, lalu
      pernyataannya muncul di sini.
    </div>
  <?php } else { ?>
    <table>
      <tr>
        <th>Waktu</th><th>Petugas</th><th>Jumlah</th><th>Catatan</th>
        <th>Keadaan</th><th>Tindakan</th>
      </tr>
      <?php foreach ($lg_daftar_bayar as $lg_b) {
          $lg_status_bayar = strtoupper((string) $lg_b['status']);
          $lg_kelas = $lg_status_bayar === 'MENUNGGU' ? 'tunggu' : ($lg_status_bayar === 'DIBAYAR' ? 'dibayar' : 'ditolak');
      ?>
      <tr>
        <td class="kecil-teks"><?php echo htmlspecialchars((string) ($lg_b['dibuat'] ?? '-')); ?></td>
        <td>
          <b><?php echo htmlspecialchars((string) ($lg_b['nama_lengkap'] ?? '-')); ?></b><br>
          <span class="kecil-teks"><?php echo htmlspecialchars((string) ($lg_b['username'] ?? '')); ?>
            &middot; <?php echo htmlspecialchars((string) ($lg_b['role'] ?? '')); ?></span>
        </td>
        <td><?php echo $lg_rupiah($lg_b['jumlah']); ?><br>
          <span class="kecil-teks"><?php echo (int) $lg_b['hari']; ?> hari</span></td>
        <td class="kecil-teks"><?php echo htmlspecialchars((string) ($lg_b['catatan'] ?? '-')); ?></td>
        <td><span class="lencana <?php echo $lg_kelas; ?>"><?php echo htmlspecialchars($lg_status_bayar); ?></span></td>
        <td>
          <?php if ($lg_status_bayar === 'MENUNGGU') { ?>
            <form method="post" style="display:inline">
              <input type="hidden" name="aksi" value="setujui_klaim">
              <input type="hidden" name="bayar_id" value="<?php echo (int) $lg_b['id']; ?>">
              <button class="tombol hijau kecil" type="submit">SETUJUI + <?php echo (int) $lg_b['hari']; ?> HARI</button>
            </form>
            <form method="post" style="display:inline">
              <input type="hidden" name="aksi" value="tolak_klaim">
              <input type="hidden" name="bayar_id" value="<?php echo (int) $lg_b['id']; ?>">
              <button class="tombol abu kecil" type="submit">TOLAK</button>
            </form>
          <?php } else { ?>
            <span class="kecil-teks"><?php echo htmlspecialchars((string) ($lg_b['diproses_pada'] ?? '-')); ?></span>
          <?php } ?>
        </td>
      </tr>
      <?php } ?>
    </table>
  <?php } ?>
</div>

<div class="kartu">
  <h2>Daftar Akun (<?php echo count($lg_daftar); ?> pengguna)</h2>
  <table>
    <tr>
      <th>Foto</th><th>Petugas</th><th>Keadaan</th><th>Berlaku sampai</th>
      <th>Sisa</th><th>Tindakan</th>
    </tr>
    <?php foreach ($lg_daftar as $lg_u) {
        $lg_s = $lg_u['status'];
        $lg_kelas_status = $lg_s['pro_aktif'] ? 'pro' : ($lg_s['trial_aktif'] ? 'trial' : 'gratis');
    ?>
    <tr>
      <td>
        <?php if (!empty($lg_u['foto_profil'])) { ?>
          <img class="foto" src="<?php echo htmlspecialchars((string) $lg_u['foto_profil']); ?>" alt="Foto">
        <?php } else { ?>
          <span class="kecil-teks">-</span>
        <?php } ?>
      </td>
      <td>
        <b><?php echo htmlspecialchars((string) ($lg_u['nama_lengkap'] ?? '-')); ?></b><br>
        <span class="kecil-teks"><?php echo htmlspecialchars((string) ($lg_u['username'] ?? '')); ?>
          &middot; <?php echo htmlspecialchars((string) ($lg_u['role'] ?? '')); ?></span>
      </td>
      <td>
        <span class="lencana <?php echo $lg_kelas_status; ?>"><?php echo htmlspecialchars((string) $lg_s['label']); ?></span>
        <?php if ($lg_s['trial_aktif']) { ?>
          <br><span class="kecil-teks">uji coba</span>
        <?php } elseif ($lg_s['pro_tanpa_batas']) { ?>
          <br><span class="kecil-teks">tanpa batas waktu</span>
        <?php } ?>
      </td>
      <td class="kecil-teks"><?php echo htmlspecialchars($lg_s['berlaku_sampai'] === '' ? '-' : (string) $lg_s['berlaku_sampai']); ?></td>
      <td class="kecil-teks">
        <?php
          if ($lg_s['pro_aktif']) {
              echo $lg_s['pro_tanpa_batas'] ? '-' : ((int) $lg_s['sisa_hari'] . ' hari');
          } elseif ($lg_s['trial_aktif']) {
              echo (int) $lg_s['sisa_trial_hari'] . ' hari';
          } else {
              echo '-';
          }
        ?>
      </td>
      <td>
        <form method="post" style="display:inline">
          <input type="hidden" name="aksi" value="aktifkan">
          <input type="hidden" name="user_id" value="<?php echo (int) $lg_u['id']; ?>">
          <input type="hidden" name="hari" value="<?php echo rts_lg_durasi(); ?>">
          <button class="tombol hijau kecil" type="submit">+<?php echo rts_lg_durasi(); ?> HARI</button>
        </form>
        <form method="post" style="display:inline">
          <input type="hidden" name="aksi" value="aktifkan">
          <input type="hidden" name="user_id" value="<?php echo (int) $lg_u['id']; ?>">
          <input type="hidden" name="hari" value="90">
          <button class="tombol biru kecil" type="submit">+90 HARI</button>
        </form>
        <?php if ($lg_s['trial_tersedia']) { ?>
          <form method="post" style="display:inline">
            <input type="hidden" name="aksi" value="trial">
            <input type="hidden" name="user_id" value="<?php echo (int) $lg_u['id']; ?>">
            <button class="tombol abu kecil" type="submit">TRIAL <?php echo rts_lg_trial(); ?> HARI</button>
          </form>
        <?php } ?>
        <?php if ($lg_s['pro'] || $lg_s['trial_aktif']) { ?>
          <form method="post" style="display:inline">
            <input type="hidden" name="aksi" value="hentikan">
            <input type="hidden" name="user_id" value="<?php echo (int) $lg_u['id']; ?>">
            <button class="tombol abu kecil" type="submit">HENTIKAN</button>
          </form>
        <?php } ?>
      </td>
    </tr>
    <?php } ?>
  </table>
</div>

<div class="kartu">
  <h2>Gambar QRIS untuk Aplikasi</h2>
  <div class="baris">
    <div>
      <div class="kotak-info">
        Simpan gambar QRIS milik Bapak di sini supaya dapat dipakai halaman
        pembayaran pada website. Pada aplikasi Android, gambar QRIS diletakkan
        pada folder <code>assets/images/qris_bene_s.jpg</code> di proyek Flutter
        (bukan di hosting).
      </div>
      <form method="post" enctype="multipart/form-data" style="margin-top:12px">
        <input type="hidden" name="aksi" value="unggah_qris">
        <input type="file" name="qris" accept="image/*"><br><br>
        <button class="tombol" type="submit">UNGGAH GAMBAR QRIS</button>
      </form>
      <p class="kecil-teks">
        NMID: <?php echo htmlspecialchars((string) rts_lg_qris()['nmid']); ?> &middot;
        Nama: <?php echo htmlspecialchars((string) rts_lg_qris()['nama']); ?>
      </p>
    </div>
    <div>
      <?php if ($lg_qris_ada) { ?>
        <img class="qris" src="uploads/qris_bene_s.jpg" alt="QRIS">
      <?php } else { ?>
        <div class="kotak-info">Belum ada gambar QRIS di hosting.</div>
      <?php } ?>
    </div>
  </div>
</div>

<div class="kartu">
  <h2>Keterangan</h2>
  <div class="kotak-info">
    <b>Akun GRATIS</b> : iklan tampil pada beranda dan pada setiap menu.<br>
    <b>Akun PRO</b> : bebas iklan selama masa berlaku (<?php echo rts_lg_durasi(); ?> hari setiap pembayaran).<br>
    <b>Uji coba</b> : <?php echo rts_lg_trial(); ?> hari, diberikan otomatis satu kali saat petugas
    masuk ke aplikasi untuk pertama kali setelah fitur ini dipasang.<br><br>
    Masa langganan yang masih berjalan <b>ditambahkan</b>, jadi pembayaran yang lebih awal tidak hangus.
  </div>
</div>

<p class="kecil-teks" style="text-align:center">
  Versi halaman <?php echo LG_VERSI_BERKAS; ?> &middot;
  <a href="?diagnosa=1">periksa halaman</a> &middot;
  <a href="akun_pro.php">halaman Akun PRO lama</a> &middot;
  <a href="index.php">beranda</a>
</p>

</div>
</body>
</html>
