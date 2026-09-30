<?php
/*
 * ============================================================================
 *  RTS PANEL BY BENE - HALAMAN KELOLA VERSI APLIKASI
 *  Berkas : app_versi.php      (letakkan di public_html, satu folder dengan
 *                               dashboard.php dan pengajuan_toko.php)
 *
 *  KEGUNAAN
 *  --------
 *  Halaman ini dipakai ADMIN untuk mengunggah berkas APK versi terbaru dan
 *  mengatur keterangannya. Setelah diunggah, aplikasi RTS Panel di HP seluruh
 *  tim akan otomatis mengetahui ada versi baru saat aplikasi dibuka.
 *
 *  CARA KERJA
 *  ----------
 *  1. Admin mengunggah berkas APK dan mengisi versi (misalnya 1.2.0, kode 3)
 *  2. Halaman ini menyimpan APK ke folder   : apk/
 *  3. Halaman ini menulis berkas keterangan : apk/app_versi.json
 *  4. Aplikasi membaca berkas JSON itu setiap kali dibuka:
 *        https://rts.benedic-s.com/apk/app_versi.json
 *     Bila kode versi di server lebih besar dari versi di HP, muncul
 *     pemberitahuan pembaruan beserta tombol unduh.
 *
 *  CATATAN PENTING
 *  ---------------
 *  - Angka "kode versi" harus SAMA dengan angka sesudah tanda + pada baris
 *    "version:" di pubspec.yaml saat APK itu dibangun, dan selalu bertambah
 *    (1, 2, 3, ...). Contoh: version: 1.2.0+3  ->  kode versi = 3
 *  - Halaman ini hanya dapat dibuka oleh akun dengan role ADMIN.
 *  - Tidak ada data database yang diubah oleh halaman ini.
 * ============================================================================
 */

require_once 'config.php';

/* --------------------------------------------------------------------------
 * PENJAGA HALAMAN - hanya ADMIN
 * -------------------------------------------------------------------------- */
if (empty($_SESSION['email'])) {
    header('Location: index.php');
    exit;
}

$app_role = strtoupper((string)($_SESSION['role'] ?? ''));

if ($app_role !== 'ADMIN') {
    header('Location: dashboard.php');
    exit;
}

require_once 'header.php';

/* --------------------------------------------------------------------------
 * PERSIAPAN FOLDER
 * -------------------------------------------------------------------------- */
$app_folder = __DIR__ . '/apk';
$app_berkas_json = $app_folder . '/app_versi.json';

if (!is_dir($app_folder)) {
    @mkdir($app_folder, 0755, true);
}

$app_pesan = '';
$app_galat = '';

/* Batas unggah dari pengaturan PHP (ditampilkan sebagai informasi). */
$app_batas_unggah = ini_get('upload_max_filesize');
$app_batas_post = ini_get('post_max_size');

/* --------------------------------------------------------------------------
 * BATAS UKURAN UNGGUH YANG DIIZINKAN HALAMAN INI (100 MB)
 * -------------------------------------------------------------------------- */
define('APP_BATAS_BITA', 104857600);

/**
 * Membaca berkas keterangan versi yang tersimpan.
 *
 * @return array<string,mixed>
 */
function app_baca_versi(string $jalur): array
{
    if (!is_file($jalur)) {
        return [];
    }

    $isi = @file_get_contents($jalur);

    if ($isi === false || trim($isi) === '') {
        return [];
    }

    $data = json_decode($isi, true);

    return is_array($data) ? $data : [];
}

/**
 * Menulis berkas keterangan versi.
 *
 * @param array<string,mixed> $data
 */
function app_tulis_versi(string $jalur, array $data): bool
{
    $teks = json_encode(
        $data,
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
    );

    if ($teks === false) {
        return false;
    }

    return @file_put_contents($jalur, $teks . "\n") !== false;
}

/**
 * Alamat dasar website ini, dipakai untuk menyusun tautan unduhan.
 */
function app_alamat_dasar(): string
{
    $skema = 'http';

    if (!empty($_SERVER['HTTPS']) && strtolower((string)$_SERVER['HTTPS']) !== 'off') {
        $skema = 'https';
    }

    $host = (string)($_SERVER['HTTP_HOST'] ?? '');

    return $skema . '://' . $host;
}

/**
 * Membersihkan nama berkas APK.
 */
function app_nama_aman(string $teks): string
{
    $bersih = preg_replace('/[^A-Za-z0-9._-]/', '_', $teks);
    $bersih = trim((string)$bersih, '._-');

    return $bersih === '' ? 'rts_panel' : $bersih;
}

/* --------------------------------------------------------------------------
 * PROSES UNGGAH BERKAS APK
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['app_unggah'])) {
    $nama_versi = trim((string)($_POST['version_name'] ?? ''));
    $kode_versi = (int)($_POST['version_code'] ?? 0);
    $wajib = isset($_POST['wajib']) ? true : false;
    $catatan = trim((string)($_POST['catatan'] ?? ''));

    if ($nama_versi === '') {
        $app_galat = 'Kolom "Versi aplikasi" wajib diisi, contoh: 1.2.0';
    } elseif ($kode_versi < 1) {
        $app_galat = 'Kolom "Kode versi" wajib diisi dengan angka 1 atau lebih besar.';
    } elseif (preg_match('/^[0-9]+(\.[0-9]+){0,3}$/', $nama_versi) !== 1) {
        $app_galat = 'Versi aplikasi hanya boleh berisi angka dan titik, contoh: 1.2.0';
    } elseif (!isset($_FILES['berkas_apk']) || (int)$_FILES['berkas_apk']['error'] === UPLOAD_ERR_NO_FILE) {
        $app_galat = 'Berkas APK belum dipilih.';
    } elseif ((int)$_FILES['berkas_apk']['error'] !== UPLOAD_ERR_OK) {
        $kode = (int)$_FILES['berkas_apk']['error'];

        $keterangan = [
            UPLOAD_ERR_INI_SIZE => 'Ukuran berkas melebihi batas server (' . $app_batas_unggah . ').',
            UPLOAD_ERR_FORM_SIZE => 'Ukuran berkas melebihi batas yang diizinkan halaman ini.',
            UPLOAD_ERR_PARTIAL => 'Unggahan terputus di tengah jalan. Coba lagi.',
            UPLOAD_ERR_NO_TMP_DIR => 'Server tidak menyediakan folder sementara.',
            UPLOAD_ERR_CANT_WRITE => 'Server gagal menulis berkas. Periksa izin folder apk/.',
            UPLOAD_ERR_EXTENSION => 'Unggahan dihentikan oleh pengaturan server.',
        ];

        $app_galat = $keterangan[$kode] ?? ('Unggahan gagal dengan kode ' . $kode . '.');
    } else {
        $berkas = $_FILES['berkas_apk'];
        $ukuran = (int)$berkas['size'];
        $nama_asli = (string)$berkas['name'];
        $akhiran = strtolower((string)pathinfo($nama_asli, PATHINFO_EXTENSION));

        if ($akhiran !== 'apk') {
            $app_galat = 'Berkas yang diunggah harus berakhiran .apk';
        } elseif ($ukuran > APP_BATAS_BITA) {
            $app_galat = 'Ukuran APK melebihi 100 MB.';
        } elseif (!is_uploaded_file((string)$berkas['tmp_name'])) {
            $app_galat = 'Berkas unggahan tidak sah.';
        } else {
            $nama_simpan = app_nama_aman('rts_panel_v' . $kode_versi);
            $nama_berkas = $nama_simpan . '.apk';
            $tujuan = $app_folder . '/' . $nama_berkas;

            if (!@move_uploaded_file((string)$berkas['tmp_name'], $tujuan)) {
                $app_galat = 'Gagal menyimpan berkas ke folder apk/. Periksa izin folder.';
            } else {
                @chmod($tujuan, 0644);

                $data = [
                    'version_code' => $kode_versi,
                    'version_name' => $nama_versi,
                    'wajib' => $wajib,
                    'catatan' => $catatan,
                    'apk' => app_alamat_dasar() . '/apk/' . $nama_berkas,
                    'ukuran_mb' => round($ukuran / 1048576, 2),
                    'dipublikasikan' => date('d-m-Y H:i'),
                ];

                if (app_tulis_versi($app_berkas_json, $data)) {
                    $app_pesan = 'APK versi ' . $nama_versi . ' (kode ' . $kode_versi
                        . ') berhasil diunggah. Aplikasi seluruh tim akan melihat '
                        . 'pemberitahuan pembaruan pada pembukaan berikutnya.';

                    /* Catatan riwayat kecil, supaya admin tahu apa yang terakhir
                       diunggah tanpa membuka folder apk/. */
                    @file_put_contents(
                        $app_folder . '/riwayat.txt',
                        date('d-m-Y H:i') . ' | versi ' . $nama_versi . ' (kode '
                        . $kode_versi . ') | ' . $nama_berkas . ' | wajib: '
                        . ($wajib ? 'ya' : 'tidak') . ' | oleh '
                        . (string)($_SESSION['email'] ?? '') . "\n",
                        FILE_APPEND
                    );
                } else {
                    $app_galat = 'APK tersimpan, tetapi berkas keterangan versi '
                        . '(app_versi.json) gagal ditulis. Periksa izin folder apk/.';
                }
            }
        }
    }
}

/* --------------------------------------------------------------------------
 * PROSES HAPUS BERKAS APK LAMA
 * -------------------------------------------------------------------------- */
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'POST' && isset($_POST['app_hapus'])) {
    $nama = basename((string)($_POST['nama_berkas'] ?? ''));

    if ($nama !== '' && strtolower((string)pathinfo($nama, PATHINFO_EXTENSION)) === 'apk') {
        $jalur = $app_folder . '/' . $nama;

        if (is_file($jalur) && strpos($nama, 'rts_panel') === 0) {
            if (@unlink($jalur)) {
                $app_pesan = 'Berkas ' . htmlspecialchars($nama) . ' dihapus.';
            } else {
                $app_galat = 'Gagal menghapus berkas. Periksa izin folder apk/.';
            }
        } else {
            $app_galat = 'Berkas tidak ditemukan.';
        }
    }
}

/* --------------------------------------------------------------------------
 * DATA UNTUK TAMPILAN
 * -------------------------------------------------------------------------- */
$app_versi = app_baca_versi($app_berkas_json);

$app_daftar_apk = [];

if (is_dir($app_folder)) {
    $isi_folder = scandir($app_folder);

    if (is_array($isi_folder)) {
        foreach ($isi_folder as $nama) {
            if (strtolower((string)pathinfo($nama, PATHINFO_EXTENSION)) !== 'apk') {
                continue;
            }

            $jalur = $app_folder . '/' . $nama;

            $app_daftar_apk[] = [
                'nama' => $nama,
                'ukuran' => (int)@filesize($jalur),
                'waktu' => (int)@filemtime($jalur),
            ];
        }
    }
}

usort($app_daftar_apk, static function (array $a, array $b): int {
    return $b['waktu'] <=> $a['waktu'];
});

$app_alamat_json = app_alamat_dasar() . '/apk/app_versi.json';
$app_json_siap = is_file($app_berkas_json);

?>

<style>
.rts-card{background:#fff;border:1px solid #eadfd6;border-radius:16px;box-shadow:0 6px 18px rgba(74,44,34,.06)}
.rts-aksi{display:flex;gap:8px;flex-wrap:wrap}
.rts-versi-kotak{border:1px solid #eadfd6;border-radius:14px;padding:14px 16px;background:#fff}
.rts-versi-kotak .label{font-size:12px;color:#8a7d76}
.rts-versi-kotak .nilai{font-weight:700;color:#3a2a24}
.rts-kode{background:#f7f3f2;border:1px solid #eadfd6;border-radius:12px;padding:12px;font-size:12px;overflow:auto;max-height:230px}
.rts-petunjuk{background:#fdf6ec;border:1px solid #f0e2cf;border-radius:14px;padding:14px 16px;font-size:13px;color:#7a5a26}
</style>

<div class="d-flex justify-content-between align-items-center mb-3 flex-wrap gap-2">
  <div>
    <h4 class="mb-1"><i class="fa-solid fa-mobile-screen-button text-danger me-2"></i>Versi Aplikasi Android</h4>
    <div class="text-muted small">Unggah APK terbaru agar seluruh tim ikut memperbarui otomatis.</div>
  </div>
  <a class="btn btn-outline-secondary btn-sm" href="dashboard.php">
    <i class="fa-solid fa-arrow-left me-1"></i>Kembali ke Dashboard
  </a>
</div>

<?php if ($app_pesan !== ''): ?>
  <div class="alert alert-success"><i class="fa-solid fa-circle-check me-2"></i><?= $app_pesan ?></div>
<?php endif; ?>

<?php if ($app_galat !== ''): ?>
  <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation me-2"></i><?= htmlspecialchars($app_galat) ?></div>
<?php endif; ?>

<div class="row g-3">
  <div class="col-lg-7">
    <div class="rts-card p-3 p-md-4">
      <h6 class="mb-3"><i class="fa-solid fa-cloud-arrow-up text-danger me-2"></i>Unggah APK Baru</h6>

      <form method="post" enctype="multipart/form-data" autocomplete="off">
        <input type="hidden" name="app_unggah" value="1">

        <div class="row g-3">
          <div class="col-sm-6">
            <label class="form-label">Versi aplikasi <span class="text-danger">*</span></label>
            <input type="text" name="version_name" class="form-control" placeholder="1.2.0" required
                   value="<?= htmlspecialchars((string)($app_versi['version_name'] ?? '')) ?>">
            <div class="form-text">Harus sama dengan baris <code>version:</code> di pubspec.yaml sebelum tanda +.</div>
          </div>

          <div class="col-sm-6">
            <label class="form-label">Kode versi <span class="text-danger">*</span></label>
            <input type="number" name="version_code" class="form-control" min="1" placeholder="3" required
                   value="<?= (int)($app_versi['version_code'] ?? 0) > 0 ? (int)$app_versi['version_code'] + 1 : '' ?>">
            <div class="form-text">Angka sesudah tanda + pada pubspec.yaml. WAJIB selalu bertambah.</div>
          </div>

          <div class="col-12">
            <label class="form-label">Berkas APK <span class="text-danger">*</span></label>
            <input type="file" name="berkas_apk" class="form-control" accept=".apk" required>
            <div class="form-text">
              Diambil dari <code>build\app\outputs\flutter-apk\app-release.apk</code> setelah
              menjalankan <code>flutter build apk --release</code>.
              Batas server saat ini: <strong><?= htmlspecialchars((string)$app_batas_unggah) ?></strong>
              (post: <?= htmlspecialchars((string)$app_batas_post) ?>).
            </div>
          </div>

          <div class="col-12">
            <label class="form-label">Catatan pembaruan</label>
            <textarea name="catatan" class="form-control" rows="3"
                      placeholder="Contoh: perbaikan filter GSP dan tampilan beranda baru."><?= htmlspecialchars((string)($app_versi['catatan'] ?? '')) ?></textarea>
          </div>

          <div class="col-12">
            <div class="form-check">
              <input class="form-check-input" type="checkbox" name="wajib" id="wajib" value="1">
              <label class="form-check-label" for="wajib">
                Pembaruan WAJIB (petugas tidak dapat menutup pemberitahuan sebelum memperbarui)
              </label>
            </div>
          </div>

          <div class="col-12">
            <button type="submit" class="btn btn-danger">
              <i class="fa-solid fa-cloud-arrow-up me-1"></i>Unggah &amp; Umumkan Versi Ini
            </button>
          </div>
        </div>
      </form>
    </div>

    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3"><i class="fa-solid fa-clock-rotate-left text-danger me-2"></i>Berkas APK di Server</h6>

      <?php if (empty($app_daftar_apk)): ?>
        <div class="text-muted small">Belum ada berkas APK di folder <code>apk/</code>.</div>
      <?php else: ?>
        <div class="table-responsive">
          <table class="table table-sm align-middle mb-0">
            <thead>
              <tr>
                <th>Nama berkas</th>
                <th class="text-end">Ukuran</th>
                <th>Diunggah</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <?php foreach ($app_daftar_apk as $berkas): ?>
                <tr>
                  <td class="small">
                    <a href="apk/<?= htmlspecialchars($berkas['nama']) ?>" target="_blank">
                      <?= htmlspecialchars($berkas['nama']) ?>
                    </a>
                    <?php if (($app_versi['apk'] ?? '') !== '' && basename((string)$app_versi['apk']) === $berkas['nama']): ?>
                      <span class="badge bg-success ms-1">Dipublikasikan</span>
                    <?php endif; ?>
                  </td>
                  <td class="text-end small"><?= number_format($berkas['ukuran'] / 1048576, 1, ',', '.') ?> MB</td>
                  <td class="small"><?= date('d-m-Y H:i', $berkas['waktu']) ?></td>
                  <td class="text-end">
                    <form method="post" onsubmit="return confirm('Hapus berkas ini?');" class="d-inline">
                      <input type="hidden" name="app_hapus" value="1">
                      <input type="hidden" name="nama_berkas" value="<?= htmlspecialchars($berkas['nama']) ?>">
                      <button type="submit" class="btn btn-sm btn-outline-danger">
                        <i class="fa-solid fa-trash"></i>
                      </button>
                    </form>
                  </td>
                </tr>
              <?php endforeach; ?>
            </tbody>
          </table>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <div class="col-lg-5">
    <div class="rts-card p-3">
      <h6 class="mb-3"><i class="fa-solid fa-circle-info text-danger me-2"></i>Versi yang Diumumkan</h6>

      <?php if (empty($app_versi)): ?>
        <div class="alert alert-warning mb-0 small">
          Belum ada versi yang diumumkan. Aplikasi belum akan menampilkan pemberitahuan
          pembaruan sebelum Anda mengunggah APK pada formulir di sebelah.
        </div>
      <?php else: ?>
        <div class="row g-2">
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Versi</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['version_name'] ?? '-')) ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Kode versi</div>
              <div class="nilai"><?= (int)($app_versi['version_code'] ?? 0) ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Sifat</div>
              <div class="nilai"><?= !empty($app_versi['wajib']) ? 'WAJIB' : 'Pilihan' ?></div>
            </div>
          </div>
          <div class="col-6">
            <div class="rts-versi-kotak">
              <div class="label">Ukuran</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['ukuran_mb'] ?? '0')) ?> MB</div>
            </div>
          </div>
          <div class="col-12">
            <div class="rts-versi-kotak">
              <div class="label">Dipublikasikan</div>
              <div class="nilai"><?= htmlspecialchars((string)($app_versi['dipublikasikan'] ?? '-')) ?></div>
            </div>
          </div>
        </div>

        <div class="mt-3 small">
          <div class="text-muted mb-1">Tautan unduhan yang dibaca aplikasi:</div>
          <div class="rts-kode"><?= htmlspecialchars((string)($app_versi['apk'] ?? '-')) ?></div>
        </div>

        <?php if (!empty($app_versi['catatan'])): ?>
          <div class="mt-3 small">
            <div class="text-muted mb-1">Catatan pembaruan:</div>
            <div class="rts-versi-kotak"><?= nl2br(htmlspecialchars((string)$app_versi['catatan'])) ?></div>
          </div>
        <?php endif; ?>
      <?php endif; ?>
    </div>

    <div class="rts-card p-3 mt-3">
      <h6 class="mb-3"><i class="fa-solid fa-satellite-dish text-danger me-2"></i>Berkas Keterangan Versi</h6>

      <div class="small mb-2">
        Aplikasi membaca berkas berikut setiap kali dibuka:
        <div class="rts-kode mt-1"><?= htmlspecialchars($app_alamat_json) ?></div>
      </div>

      <div class="d-flex gap-2 mb-3">
        <a class="btn btn-sm btn-outline-secondary" href="apk/app_versi.json" target="_blank">
          <i class="fa-solid fa-up-right-from-square me-1"></i>Buka berkas
        </a>
        <a class="btn btn-sm btn-outline-secondary" href="apk/app_versi.json?t=<?= time() ?>" target="_blank">
          <i class="fa-solid fa-rotate me-1"></i>Muat ulang
        </a>
      </div>

      <?php if ($app_json_siap): ?>
        <div class="rts-kode"><?= htmlspecialchars((string)@file_get_contents($app_berkas_json)) ?></div>
      <?php else: ?>
        <div class="text-muted small">Berkas belum ada.</div>
      <?php endif; ?>
    </div>

    <div class="rts-petunjuk mt-3">
      <strong><i class="fa-solid fa-lightbulb me-1"></i>Alur pembaruan aplikasi</strong>
      <ol class="mb-0 ps-3 mt-2">
        <li>Ubah <code>version:</code> di <code>pubspec.yaml</code>, contoh <code>1.2.0+3</code> (kode versi 3).</li>
        <li>Jalankan <code>flutter build apk --release</code>.</li>
        <li>Unggah <code>app-release.apk</code> pada formulir ini dengan kode versi yang sama (3).</li>
        <li>Aplikasi seluruh tim menampilkan pemberitahuan pembaruan pada pembukaan berikutnya.</li>
      </ol>
      <div class="mt-2 small">
        Catatan: Android selalu meminta persetujuan saat memasang aplikasi dari luar Play Store.
        Petugas cukup menekan tombol unduh, lalu memilih <strong>Pasang</strong> pada berkas yang terunduh.
      </div>
    </div>
  </div>
</div>

<?php require_once 'footer.php'; ?>
