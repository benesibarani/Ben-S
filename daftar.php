<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PENDAFTARAN TIM SALES
 *  Berkas : daftar.php   (letakkan di public_html, satu folder dengan
 *                         index.php, config.php, dan district.php)
 *
 *  KEGUNAAN
 *  --------
 *  Formulir pendaftaran akun untuk tim Sales, dibuka dari tombol "Mendaftar"
 *  di bawah tombol "Masuk" pada halaman index.php.
 *
 *  Isi formulir disesuaikan dengan tabel sales_users:
 *    nama_lengkap, email, username, password, role, salesman,
 *    sales_district, status_aktif
 *
 *  CATATAN PENTING
 *  ---------------
 *  1. Password disimpan dengan password_hash(..., PASSWORD_DEFAULT) - sama
 *     seperti Kelola User dan halaman masuk. Tidak ada password yang
 *     dituliskan pada berkas ini atau dikirim ke mana pun.
 *  2. Role yang boleh dipilih hanya role tim Sales: RTS, TF, SMST, WSS.
 *     Role ADMIN dan ASS tidak dapat dibuat dari halaman ini - supaya tidak
 *     ada yang dapat memberi dirinya sendiri hak istimewa.
 *  3. Sales District diambil dari district.php, yang membaca daftar
 *     sesungguhnya pada kolom sales_users.sales_district lalu menggabungkannya
 *     dengan 12 district bawaan. District WAJIB diisi untuk role RTS dan TF
 *     (sebab data mereka dibatasi per district), sedangkan WSS dan SMST boleh
 *     dikosongkan (semua district).
 *  4. Bila DAFTAR_PERLU_PERSETUJUAN di bawah diubah menjadi true, akun baru
 *     berstatus "Pending" sehingga belum dapat masuk sampai ADMIN mengaktifkan
 *     lewat halaman Kelola User. Bawaannya false: akun langsung Aktif supaya
 *     tim Sales dapat segera masuk.
 * ============================================================================
 */

define('DAFTAR_VERSI_BERKAS', 1);

/** Ubah menjadi true bila akun baru harus disetujui ADMIN lebih dahulu. */
define('DAFTAR_PERLU_PERSETUJUAN', false);

/** Role yang boleh mendaftar sendiri (ADMIN/ASS tidak termasuk). */
define('DAFTAR_ROLE_DIIZINKAN', 'RTS,TF,SMST,WSS');

/** Role yang WAJIB memilih district. */
define('DAFTAR_ROLE_WAJIB_DISTRICT', 'RTS,TF');

require_once __DIR__ . '/config.php';

if (is_file(__DIR__ . '/district.php')) {
    require_once __DIR__ . '/district.php';
}

$daftar_kabar = '';
$daftar_kabar_jenis = 'galat';
$daftar_berhasil = false;
$daftar_nilai = [
    'nama_lengkap' => '',
    'email' => '',
    'username' => '',
    'role' => 'RTS',
    'salesman' => '',
    'sales_district' => '',
];

if (!function_exists('daftar_ada_kolom')) {
    /**
     * Memeriksa keberadaan kolom pada sales_users.
     *
     * Memakai district.php bila sudah diunggah. Bila belum, kolom dianggap ada
     * supaya pendaftaran tetap dapat berjalan pada susunan tabel yang biasa
     * dipakai (kesalahan yang sebenarnya akan tetap tampil sebagai pesan dari
     * database, bukan halaman putih).
     */
    function daftar_ada_kolom($conn, string $kolom): bool
    {
        if (function_exists('rts_district_kolom_ada')) {
            return rts_district_kolom_ada($conn, 'sales_users', $kolom);
        }

        return in_array($kolom, [
            'nama_lengkap', 'email', 'username', 'password', 'role',
            'salesman', 'sales_district', 'status_aktif',
        ], true);
    }
}

$role_diizinkan = array_values(array_filter(array_map('trim', explode(',', DAFTAR_ROLE_DIIZINKAN))));
$role_wajib_district = array_values(array_filter(array_map('trim', explode(',', DAFTAR_ROLE_WAJIB_DISTRICT))));

$pilihan_district = function_exists('rts_district_pilihan') ? rts_district_pilihan($conn ?? null) : [];

/* ---------------------------------------------------------------- diagnostik */
if (isset($_GET['periksa'])) {
    header('Content-Type: text/plain; charset=utf-8');

    echo "PEMERIKSAAN HALAMAN PENDAFTARAN TIM SALES\n";
    echo "=========================================\n";
    echo 'Versi berkas          : ' . DAFTAR_VERSI_BERKAS . "\n";
    echo 'Berkas district.php   : ' . (function_exists('rts_district_pilihan') ? 'ADA' : 'TIDAK ADA') . "\n";
    echo 'Koneksi database      : ' . (isset($conn) && $conn instanceof mysqli ? 'ADA' : 'TIDAK ADA') . "\n";
    echo 'Waktu server          : ' . date('d-m-Y H:i:s') . "\n";
    echo 'Akun baru langsung    : ' . (DAFTAR_PERLU_PERSETUJUAN ? 'PERLU PERSETUJUAN ADMIN' : 'AKTIF') . "\n";
    echo 'Role yang boleh daftar: ' . DAFTAR_ROLE_DIIZINKAN . "\n";

    echo "\nKOLOM TABEL sales_users\n";

    if (isset($conn) && $conn instanceof mysqli) {
        foreach (['username', 'nama_lengkap', 'email', 'password', 'role', 'salesman', 'sales_district', 'status_aktif'] as $kolom) {
            echo '  ' . str_pad($kolom, 15, ' ') . ': '
                . (daftar_ada_kolom($conn, $kolom) ? 'ADA' : 'BELUM ADA') . "\n";
        }
    }

    echo "\nDAFTAR DISTRICT PADA KOTAK PILIHAN\n";

    foreach ($pilihan_district as $butir) {
        echo '  - ' . str_pad((string) $butir['nilai'], 22, ' ')
            . ($butir['dari_db'] ? 'ADA di database (' . (int) $butir['jumlah'] . ' akun)' : 'bawaan saja') . "\n";
    }

    echo "\nHalaman ini tidak mengubah data apa pun.\n";

    exit;
}

/* ------------------------------------------------------------------ pendaftaran */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST') {
    $daftar_nilai['nama_lengkap'] = trim((string) ($_POST['nama_lengkap'] ?? ''));
    $daftar_nilai['email'] = trim((string) ($_POST['email'] ?? ''));
    $daftar_nilai['username'] = trim((string) ($_POST['username'] ?? ''));
    $daftar_nilai['role'] = strtoupper(trim((string) ($_POST['role'] ?? 'RTS')));
    $daftar_nilai['salesman'] = trim((string) ($_POST['salesman'] ?? ''));
    $daftar_nilai['sales_district'] = trim((string) ($_POST['sales_district'] ?? ''));

    $sandi = (string) ($_POST['password'] ?? '');
    $sandi_ulang = (string) ($_POST['password_ulang'] ?? '');
    $jebakan = trim((string) ($_POST['website'] ?? ''));

    if (!isset($conn) || !($conn instanceof mysqli)) {
        $daftar_kabar = 'Koneksi database tidak ditemukan. Hubungi Admin - periksa berkas config.php pada hosting.';
    } elseif ($jebakan !== '') {
        // Kolom jebakan diisi robot pengirim spam.
        $daftar_kabar = 'Pendaftaran tidak dapat diproses. Muat ulang halaman lalu coba lagi.';
    } elseif ($daftar_nilai['nama_lengkap'] === '' || (function_exists('mb_strlen') ? mb_strlen($daftar_nilai['nama_lengkap']) : strlen($daftar_nilai['nama_lengkap'])) < 3) {
        $daftar_kabar = 'Nama lengkap wajib diisi (minimal 3 huruf).';
    } elseif ($daftar_nilai['email'] === '' || filter_var($daftar_nilai['email'], FILTER_VALIDATE_EMAIL) === false) {
        $daftar_kabar = 'Alamat email belum benar. Contoh: nama@email.com';
    } elseif (preg_match('/^[A-Za-z0-9._-]{4,30}$/', $daftar_nilai['username']) !== 1) {
        $daftar_kabar = 'Username hanya boleh huruf, angka, titik, garis bawah, dan strip - panjang 4 sampai 30.';
    } elseif (!in_array($daftar_nilai['role'], $role_diizinkan, true)) {
        $daftar_kabar = 'Role yang dipilih tidak dikenal. Pilih salah satu: ' . implode(', ', $role_diizinkan) . '.';
    } elseif (strlen($sandi) < 8) {
        $daftar_kabar = 'Password minimal 8 karakter.';
    } elseif ($sandi !== $sandi_ulang) {
        $daftar_kabar = 'Password dan ulangi password tidak sama.';
    } elseif (in_array($daftar_nilai['role'], $role_wajib_district, true) && $daftar_nilai['sales_district'] === '') {
        $daftar_kabar = 'Sales District wajib dipilih untuk role ' . implode(' dan ', $role_wajib_district)
            . ', sebab data yang terlihat dibatasi per district.';
    } elseif ($daftar_nilai['sales_district'] !== ''
        && function_exists('rts_district_sah') && !rts_district_sah($conn, $daftar_nilai['sales_district'])) {
        $daftar_kabar = 'Sales District yang dipilih tidak ada pada daftar. Pilih dari pilihan yang tersedia.';
    } else {
        if ($daftar_nilai['sales_district'] !== '' && function_exists('rts_district_rapikan')) {
            $daftar_nilai['sales_district'] = rts_district_rapikan($conn, $daftar_nilai['sales_district']);
        }

        if ($daftar_nilai['salesman'] === '') {
            $daftar_nilai['salesman'] = $daftar_nilai['nama_lengkap'];
        }

        /* ---------------------------------------------------- cek kembar */
        $kembar = '';

        foreach ([['username', $daftar_nilai['username']], ['email', $daftar_nilai['email']]] as $periksa) {
            if (!daftar_ada_kolom($conn, $periksa[0])) {
                continue;
            }

            $stmt_kembar = $conn->prepare('SELECT id FROM sales_users WHERE ' . $periksa[0] . ' = ? LIMIT 1');

            if ($stmt_kembar) {
                $stmt_kembar->bind_param('s', $periksa[1]);
                $stmt_kembar->execute();
                $hasil_kembar = $stmt_kembar->get_result();

                if ($hasil_kembar && $hasil_kembar->num_rows > 0) {
                    $kembar = $periksa[0];
                }

                $stmt_kembar->close();
            }

            if ($kembar !== '') {
                break;
            }
        }

        if ($kembar === 'username') {
            $daftar_kabar = 'Username "' . $daftar_nilai['username'] . '" sudah dipakai. Pilih username lain.';
        } elseif ($kembar === 'email') {
            $daftar_kabar = 'Email "' . $daftar_nilai['email'] . '" sudah terdaftar. Gunakan email lain atau minta Admin mengatur ulang akun lama.';
        } else {
            /* ------------------------------------------- simpan ke database */
            $status_baru = DAFTAR_PERLU_PERSETUJUAN ? 'Pending' : 'Aktif';
            $sandi_hash = password_hash($sandi, PASSWORD_DEFAULT);

            $kolom_isi = [];
            $nilai_isi = [];
            $jenis_isi = '';

            $calon = [
                'nama_lengkap' => [$daftar_nilai['nama_lengkap'], 's'],
                'email' => [$daftar_nilai['email'], 's'],
                'username' => [$daftar_nilai['username'], 's'],
                'password' => [$sandi_hash, 's'],
                'role' => [$daftar_nilai['role'], 's'],
                'salesman' => [$daftar_nilai['salesman'], 's'],
                'sales_district' => [$daftar_nilai['sales_district'], 's'],
                'status_aktif' => [$status_baru, 's'],
            ];

            foreach ($calon as $nama_kolom => $isinya) {
                // Hanya kolom yang benar-benar ada pada tabel yang dipakai,
                // supaya halaman ini tetap bekerja walau susunan tabel berbeda.
                if (!daftar_ada_kolom($conn, $nama_kolom)) {
                    continue;
                }

                $kolom_isi[] = $nama_kolom;
                $nilai_isi[] = $isinya[0];
                $jenis_isi .= $isinya[1];
            }

            if (count($kolom_isi) < 5) {
                $daftar_kabar = 'Tabel sales_users pada hosting belum lengkap. Hubungi Admin untuk memeriksanya.';
            } else {
                $sql = 'INSERT INTO sales_users (' . implode(', ', $kolom_isi) . ') VALUES ('
                    . implode(', ', array_fill(0, count($kolom_isi), '?')) . ')';

                $stmt_simpan = $conn->prepare($sql);

                if (!$stmt_simpan) {
                    $daftar_kabar = 'Pendaftaran gagal disiapkan. Hubungi Admin.';
                } else {
                    $stmt_simpan->bind_param($jenis_isi, ...$nilai_isi);
                    $berhasil = $stmt_simpan->execute();
                    $galat_db = $conn->error;
                    $id_baru = (int) $conn->insert_id;
                    $stmt_simpan->close();

                    if (!$berhasil) {
                        $daftar_kabar = 'Pendaftaran gagal disimpan: ' . $galat_db;

                        if (stripos($galat_db, 'Duplicate') !== false) {
                            $daftar_kabar = 'Username atau email itu sudah dipakai. Silakan pilih yang lain.';
                        }
                    } else {
                        $daftar_berhasil = true;

                        $daftar_kabar = DAFTAR_PERLU_PERSETUJUAN
                            ? 'Pendaftaran berhasil dikirim. Akun Anda menunggu persetujuan ADMIN sebelum dapat dipakai masuk.'
                            : 'Pendaftaran berhasil. Sekarang Anda dapat masuk memakai username dan password tadi.';

                        /* Pemberitahuan kepada ADMIN/ASS (aman gagal). */
                        if (is_file(__DIR__ . '/api/notif_otomatis.php')) {
                            try {
                                require_once __DIR__ . '/api/notif_otomatis.php';

                                if (function_exists('rts_notif_kirim') && function_exists('rts_notif_daftar_penerima')) {
                                    $penerima = rts_notif_daftar_penerima($conn, 'ADMIN');

                                    if (!$penerima) {
                                        $penerima = [];
                                    }

                                    $penerima[] = (string) ($_SESSION['email'] ?? '');

                                    $penerima = array_values(array_filter(array_unique($penerima)));

                                    if ($penerima) {
                                        rts_notif_kirim(
                                            $conn,
                                            $penerima,
                                            'Pendaftaran Akun Sales Baru',
                                            $daftar_nilai['nama_lengkap'] . ' (' . $daftar_nilai['username'] . ')'
                                                . ' mendaftar sebagai ' . $daftar_nilai['role']
                                                . ($daftar_nilai['sales_district'] !== ''
                                                    ? ' district ' . $daftar_nilai['sales_district'] : ' (semua district)')
                                                . '. Status akun: ' . $status_baru
                                                . '. Periksa pada halaman Kelola User.',
                                            'PENDAFTARAN',
                                            [
                                                'tipe' => 'daftar',
                                                'halaman' => 'pengguna',
                                                'user_id' => $id_baru,
                                            ],
                                            'pengguna',
                                            $id_baru
                                        );
                                    }
                                }
                            } catch (Throwable $galat_notif) {
                                error_log('RTS daftar: pemberitahuan pendaftaran gagal - ' . $galat_notif->getMessage());
                            }
                        }
                    }
                }
            }
        }
    }
}
?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mendaftar - RTS Panel By Bene</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body class="bg-light">

<main class="min-vh-100 d-flex align-items-center justify-content-center p-3">
<div class="card border-0 shadow-sm p-4" style="max-width:520px;width:100%">

  <div class="text-center mb-4">
    <img src="assets/brand/rts-panel-logo.png" alt="RTS Panel By Bene" style="max-width:220px;width:100%;height:auto">
    <p class="text-muted mb-0 mt-2">Pendaftaran Akun Tim Sales</p>
  </div>

  <?php if ($daftar_kabar !== ''): ?>
    <div class="alert <?= $daftar_berhasil ? 'alert-success' : 'alert-danger' ?> py-2">
      <?= htmlspecialchars($daftar_kabar) ?>
    </div>
  <?php endif; ?>

  <?php if ($daftar_berhasil): ?>

    <div class="d-grid gap-2">
      <a href="index.php" class="btn btn-primary btn-lg">Buka Halaman Masuk</a>
    </div>

    <p class="text-muted small mt-3 mb-0">
      Simpan username dan password Anda. Bila ada kesalahan penulisan nama atau district,
      minta Admin memperbaikinya pada halaman Kelola User.
    </p>

  <?php else: ?>

    <form method="post" autocomplete="off">
      <input type="text" name="website" class="d-none" tabindex="-1" autocomplete="off" aria-hidden="true">

      <div class="mb-3">
        <label class="form-label">Nama Lengkap</label>
        <input name="nama_lengkap" class="form-control" required autofocus
               value="<?= htmlspecialchars($daftar_nilai['nama_lengkap']) ?>">
      </div>

      <div class="mb-3">
        <label class="form-label">Username</label>
        <input name="username" class="form-control" required minlength="4" maxlength="30"
               value="<?= htmlspecialchars($daftar_nilai['username']) ?>">
        <div class="form-text">Dipakai untuk masuk. Huruf, angka, titik, garis bawah, strip (4-30).</div>
      </div>

      <div class="mb-3">
        <label class="form-label">Email</label>
        <input type="email" name="email" class="form-control" required
               value="<?= htmlspecialchars($daftar_nilai['email']) ?>">
        <div class="form-text">Dipakai untuk pemberitahuan dari Admin.</div>
      </div>

      <div class="row g-3">
        <div class="col-sm-6">
          <label class="form-label">Role</label>
          <select name="role" class="form-select" id="rtsRole" required>
            <?php foreach ($role_diizinkan as $role_satu): ?>
              <option value="<?= htmlspecialchars($role_satu) ?>"<?= $daftar_nilai['role'] === $role_satu ? ' selected' : '' ?>>
                <?= htmlspecialchars($role_satu) ?>
              </option>
            <?php endforeach; ?>
          </select>
          <div class="form-text">RTS/TF = per district, WSS/SMST = semua district.</div>
        </div>

        <div class="col-sm-6">
          <label class="form-label">Sales District</label>
          <select name="sales_district" class="form-select" id="rtsDistrict">
            <option value="">-- Semua District --</option>
            <?php foreach ($pilihan_district as $butir_district): ?>
              <option value="<?= htmlspecialchars((string) $butir_district['nilai']) ?>"
                <?= $daftar_nilai['sales_district'] === (string) $butir_district['nilai'] ? 'selected' : '' ?>>
                <?= htmlspecialchars((string) $butir_district['nilai']) ?>
              </option>
            <?php endforeach; ?>
          </select>
          <div class="form-text">
            Wajib untuk RTS dan TF. Boleh dikosongkan untuk WSS/SMST.
          </div>
        </div>
      </div>

      <div class="mb-3 mt-3">
        <label class="form-label">Nama Salesman (opsional)</label>
        <input name="salesman" class="form-control"
               value="<?= htmlspecialchars($daftar_nilai['salesman']) ?>">
        <div class="form-text">Kosongkan bila sama dengan nama lengkap.</div>
      </div>

      <div class="row g-3">
        <div class="col-sm-6">
          <label class="form-label">Password</label>
          <input type="password" name="password" class="form-control" required minlength="8">
          <div class="form-text">Minimal 8 karakter.</div>
        </div>

        <div class="col-sm-6">
          <label class="form-label">Ulangi Password</label>
          <input type="password" name="password_ulang" class="form-control" required minlength="8">
        </div>
      </div>

      <button class="btn btn-primary btn-lg w-100 mt-4">Daftar</button>

      <p class="text-center text-muted small mt-3 mb-0">
        Sudah punya akun?
        <a href="index.php" class="text-decoration-none">Masuk di sini</a>
      </p>
    </form>

  <?php endif; ?>

</div>
</main>

<script>
(function () {
  var role = document.getElementById('rtsRole');
  var district = document.getElementById('rtsDistrict');

  if (!role || !district) return;

  function atur() {
    var wajib = (role.value === 'RTS' || role.value === 'TF');
    district.required = wajib;

    var label = district.previousElementSibling;

    if (label) {
      label.innerHTML = 'Sales District' + (wajib ? ' <span class="text-danger">*</span>' : '');
    }
  }

  role.addEventListener('change', atur);
  atur();
})();
</script>

</body>
</html>
