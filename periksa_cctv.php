<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PEMERIKSA & PENGAMBIL DAFTAR CCTV KOTA MEDAN
 *  Berkas : periksa_cctv.php   (letakkan di public_html sementara)
 *
 *  GUNA UNTUK APA?
 *  ---------------
 *  Menjawab pertanyaan: "bagaimana mengetahui tautan video CCTV Kota Medan?"
 *
 *  Halaman ini:
 *    1. Mengambil DAFTAR KAMERA resmi dari API milik situs ATCS Dishub Kota
 *       Medan, lalu menyimpannya ke berkas data/cctv_medan.json supaya
 *       aplikasi RTS Panel (menu CCTV Online untuk akun PRO) dapat membacanya.
 *    2. MENAMPILKAN CONTOH DATA MENTAH dari API, supaya jelas nama kolom
 *       (field) yang tersedia - termasuk tautan stream untuk tiap kamera.
 *    3. MENGUJI apakah tautan stream benar-benar hidup (ALIVE / MATI), satu
 *       kali klik, memakai curl_multi (cepat, banyak sekaligus).
 *    4. Menyusun sendiri tautan stream dengan POLA RESMI bila API tidak
 *       memberi kolom tautan langsung:
 *            https://atcsdishub.medan.go.id/stream/<KODE>/stream.m3u8
 *       dengan <KODE> = "L" + nomor kamera + nama persimpangan tanpa spasi
 *       dan tanpa tanda hubung (titik tetap dipakai), contoh:
 *            L3KESAWANPALANGMERAH, L1RADENSALEHBALAIKOTA.
 *
 *  HANYA MEMBACA. Tidak ada data Bapak yang diubah. Halaman ini boleh dihapus
 *  dari hosting setelah selesai dipakai.
 *
 *  CARA PAKAI (buka di browser, sesudah diunggah)
 *  ----------------------------------------------
 *    periksa_cctv.php                 -> lihat keadaan & petunjuk
 *    periksa_cctv.php?ambil=1         -> ambil daftar kamera dari API ATCS
 *    periksa_cctv.php?paksa=1&ambil=1 -> ambil ulang walau masih ada simpanan
 *    periksa_cctv.php?uji=10          -> uji 10 tautan pertama (hidup/mati)
 *    periksa_cctv.php?uji=semua       -> uji semua tautan
 *    periksa_cctv.php?unduh=1         -> unduh data/cctv_medan.json
 *
 *  CATATAN PENTING
 *  ---------------
 *  - Kunci API di bawah adalah kunci PUBLIK milik situs ATCS Dishub Kota
 *    Medan: nilainya dapat dibaca siapa saja pada berkas JavaScript halaman
 *    mereka. Kunci itu BUKAN milik RTS Panel dan tidak ada data Bapak di
 *    dalamnya. Bila suatu saat Dishub mengganti kuncinya, cukup ubah dua
 *    baris di bawah (atau isi berkas cctv_kunci.php).
 *  - Supaya tidak membebani server Dishub, hasil pengambilan DISIMPAN
 *    (cache) dan hanya diambil ulang bila sudah lebih dari 12 jam.
 * ============================================================================
 */

define('CCTV_VERSI', 1);

/** Alamat API resmi daftar kamera (dipakai situsnya sendiri). */
define('CCTV_API', 'https://atcsdishub.medan.go.id/api/v3/pv/ldevice');

/** Alamat dasar situs ATCS Kota Medan. */
define('CCTV_BASE', 'https://atcsdishub.medan.go.id');

/** Kunci PUBLIK situs ATCS (bukan kunci milik RTS Panel). */
$cctv_client_id = '8e21ec02-8cdb-47b3-a51d-a65fa742fafc';
$cctv_client_secret = '677def13b9a745ead7d25c6ff8dd6d7154ddc4a59756e8b1c27755d59444351d';

/* Bila Bapak ingin menyimpan kunci pada berkas terpisah, cukup buat berkas
   cctv_kunci.php berisi:
       <?php $cctv_client_id = '...'; $cctv_client_secret = '...';
   Berkas itu akan dipakai menggantikan kunci di atas. */
if (is_file(__DIR__ . '/cctv_kunci.php')) {
    include __DIR__ . '/cctv_kunci.php';
}

/** Berapa jam daftar disimpan sebelum diambil ulang dari API. */
define('CCTV_SIMPAN_JAM', 12);

/** Folder penyimpanan (dibuat otomatis bila belum ada). */
define('CCTV_FOLDER', __DIR__ . '/data');

$cctv_berkas = CCTV_FOLDER . '/cctv_medan.json';
$cctv_mentah = CCTV_FOLDER . '/cctv_medan_mentah.json';

/* ------------------------------------------------------------------ bantuan */

/** Menjalankan permintaan HTTP (cURL bila ada, kalau tidak pakai stream). */
function cctv_minta(string $url, array $kepala = [], int $batas = 25, bool $kunci = false): array
{
    $kepala[] = 'Accept: application/json, text/plain, */*';

    if (function_exists('curl_init')) {
        $c = curl_init($url);
        curl_setopt_array($c, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_HTTPHEADER => $kepala,
            CURLOPT_TIMEOUT => $batas,
            CURLOPT_CONNECTTIMEOUT => 12,
            CURLOPT_FOLLOWLOCATION => true,
            CURLOPT_MAXREDIRS => 4,
            CURLOPT_USERAGENT => 'RTS-Panel-CCTV-Pemeriksa/1.0',
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_NOBODY => $kunci,
        ]);

        $isi = curl_exec($c);
        $kode = (int) curl_getinfo($c, CURLINFO_RESPONSE_CODE);
        $galat = curl_error($c);
        curl_close($c);

        return ['kode' => $kode, 'isi' => (string) $isi, 'galat' => $galat];
    }

    $konteks = stream_context_create(['http' => [
        'method' => $kunci ? 'HEAD' : 'GET',
        'header' => implode("\r\n", $kepala),
        'timeout' => $batas,
        'ignore_errors' => true,
    ], 'ssl' => ['verify_peer' => true, 'verify_peer_name' => true]]);

    $isi = @file_get_contents($url, false, $konteks);
    $kode = 0;

    foreach ((array) ($http_response_header ?? []) as $baris) {
        if (preg_match('#^HTTP/\S+\s+(\d{3})#', $baris, $cocok)) {
            $kode = (int) $cocok[1];
        }
    }

    return ['kode' => $kode, 'isi' => (string) $isi, 'galat' => $isi === false ? 'gagal menyambung' : ''];
}

/** Menyiapkan folder data. */
function cctv_siapkan_folder(): bool
{
    if (!is_dir(CCTV_FOLDER)) {
        @mkdir(CCTV_FOLDER, 0755, true);
    }

    return is_dir(CCTV_FOLDER) && is_writable(CCTV_FOLDER);
}

/** Umur berkas simpanan dalam jam. */
function cctv_umur_jam(string $berkas): float
{
    if (!is_file($berkas)) {
        return 9999;
    }

    return (time() - (int) filemtime($berkas)) / 3600;
}

/** Membuat kode kamera dari nomor + nama (pola resmi ATCS). */
function cctv_kode(int $nomor, string $nama): string
{
    $bersih = preg_replace('/[^A-Za-z0-9.]/', '', strtoupper($nama));

    return 'L' . $nomor . $bersih;
}

/** Memotong teks dengan aman (tidak bergantung pada mbstring). */
function cctv_potong(string $teks, int $batas): string
{
    if (function_exists('mb_substr')) {
        return mb_substr($teks, 0, $batas);
    }

    return substr($teks, 0, $batas);
}

/** Mengambil nilai pertama yang ada pada sebuah larik. */
function cctv_ambil($larik, array $nama, $bawaan = null)
{
    if (!is_array($larik)) {
        return $bawaan;
    }

    foreach ($nama as $satu) {
        if (isset($larik[$satu]) && $larik[$satu] !== '' && $larik[$satu] !== null) {
            return $larik[$satu];
        }
    }

    return $bawaan;
}

/* ------------------------------------------------------------------- proses */

$cctv_kabar = [];
$cctv_galat = '';
$cctv_mentah_contoh = '';
$cctv_ringkas = null;
$cctv_daftar = [];
$cctv_dari_simpanan = false;

/* 1. Ambil dari API */
if (isset($_GET['ambil'])) {
    if (!cctv_siapkan_folder()) {
        $cctv_galat = 'Folder data/ tidak dapat dibuat atau tidak dapat ditulis. '
            . 'Buat folder bernama data di dalam public_html lalu beri izin tulis (0755 atau 0775).';
    } elseif (cctv_umur_jam($cctv_berkas) < CCTV_SIMPAN_JAM && !isset($_GET['paksa'])) {
        $cctv_kabar[] = 'Daftar masih baru (kurang dari ' . CCTV_SIMPAN_JAM . ' jam), jadi tidak diambil ulang. '
            . 'Tambahkan &paksa=1 bila ingin memaksa.';
    } else {
        $butir_semua = [];
        $meta_akhir = [];
        $halaman = 1;
        $halaman_total = 1;
        $batas_halaman = 25;

        do {
            $minta = cctv_minta(
                CCTV_API . '?page=' . $halaman . '&paginate=100',
                [
                    'Content-Type: application/json',
                    'x-client-id: ' . $cctv_client_id,
                    'x-client-secret: ' . $cctv_client_secret,
                ]
            );

            if ($minta['kode'] !== 200) {
                $cctv_galat = 'Gagal mengambil daftar dari API ATCS pada halaman ' . $halaman
                    . ' (HTTP ' . $minta['kode'] . ')'
                    . ($minta['galat'] !== '' ? ': ' . $minta['galat'] : '')
                    . '. Isi balasannya: ' . cctv_potong(trim($minta['isi']), 300);
                break;
            }

            $json = json_decode($minta['isi'], true);

            if (!is_array($json)) {
                $cctv_galat = 'Balasan API ATCS bukan JSON yang sah.';
                $cctv_mentah_contoh = cctv_potong($minta['isi'], 600);
                break;
            }

            $butir = $json['data'] ?? [];

            if (!is_array($butir) || !$butir) {
                $meta_akhir = is_array($json['meta'] ?? null) ? $json['meta'] : $meta_akhir;
                break;
            }

            $butir_semua = array_merge($butir_semua, $butir);
            $meta_akhir = is_array($json['meta'] ?? null) ? $json['meta'] : [];
            $halaman_total = max(1, (int) ($meta_akhir['pages'] ?? 1));
            $halaman++;
        } while ($halaman <= $halaman_total && $halaman <= $batas_halaman);

        if ($butir_semua && $cctv_galat === '') {
            $gabungan = ['meta' => $meta_akhir, 'data' => $butir_semua];
            file_put_contents($cctv_mentah, json_encode($gabungan, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
            $cctv_ringkas = $gabungan;

            $cctv_kabar[] = 'Berhasil mengambil daftar dari API ATCS: ' . number_format(count($butir_semua))
                . ' kamera dari ' . number_format(max(1, $halaman - 1)) . ' halaman. Data mentah disimpan pada '
                . 'data/cctv_medan_mentah.json.';
        }
    }
}

/* 2. Susun daftar kamera dari data mentah (bila ada) */
$cctv_mentah_lokal = is_file($cctv_mentah)
    ? json_decode((string) file_get_contents($cctv_mentah), true)
    : null;

if (is_array($cctv_mentah_lokal)) {
    if ($cctv_ringkas === null) {
        $cctv_ringkas = $cctv_mentah_lokal;
    }

    $baris = $cctv_mentah_lokal['data'] ?? ($cctv_mentah_lokal['result'] ?? []);

    if (is_array($baris) && $baris) {
        $contoh = $baris[0];
        $cctv_mentah_contoh = json_encode($contoh, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);

        foreach ($baris as $satu) {
            $perangkat = null;

            if (isset($satu['tb_device_lokasi'][0]) && is_array($satu['tb_device_lokasi'][0])) {
                $perangkat = $satu['tb_device_lokasi'][0];
            } elseif (isset($satu['device'][0]) && is_array($satu['device'][0])) {
                $perangkat = $satu['device'][0];
            } elseif (is_array($satu)) {
                $perangkat = $satu;
            }

            if (!is_array($perangkat)) {
                continue;
            }

            $nama = (string) cctv_ambil($perangkat, ['nama', 'nama_device', 'nama_kamera'], '');
            $alias = (string) cctv_ambil($perangkat, ['nama_alias', 'alias'], '');
            $lokasi = (string) cctv_ambil($satu, ['nama_lokasi', 'lokasi'], $nama);
            $nomor = (int) cctv_ambil($perangkat, ['id_device', 'nomor', 'id'], cctv_ambil($satu, ['id_device', 'id_lokasi'], 0));

            $langsung = (string) cctv_ambil($perangkat, ['url_hls', 'url_stream', 'url', 'hls', 'stream'], '');
            $player = (string) cctv_ambil($perangkat, ['url_proxy_hls', 'url_proxy'], '');
            $poster = (string) cctv_ambil($perangkat, ['poster', 'url_poster'], '');

            if ($poster !== '' && strpos($poster, 'http') !== 0) {
                $poster = CCTV_BASE . '/' . ltrim($poster, '/');
            }

            $kode = '';

            if ($langsung !== '' && strpos($langsung, '/stream/') !== false) {
                $sisa = substr($langsung, strpos($langsung, '/stream/') + 8);
                $kode = explode('/', $sisa)[0];
            } elseif ($nama !== '' && $nomor > 0) {
                $kode = cctv_kode($nomor, $nama);
            }

            $tautan = $langsung !== '' && strpos($langsung, '.m3u8') !== false
                ? $langsung
                : ($kode !== '' ? CCTV_BASE . '/stream/' . $kode . '/stream.m3u8' : '');

            $cctv_daftar[] = [
                'kode' => $kode,
                'nomor' => $nomor,
                'nama' => $nama !== '' ? $nama : $lokasi,
                'alias' => $alias,
                'lokasi' => $lokasi,
                'url' => $tautan,
                'player' => $player,
                'poster' => $poster,
                'lat' => (float) cctv_ambil($satu, ['latitude', 'lat'], 0),
                'lon' => (float) cctv_ambil($satu, ['longitude', 'lng', 'lon'], 0),
            ];
        }
    }
}

/* 3. Bila belum ada data mentah, pakai berkas daftar yang sudah ada */
if (!$cctv_daftar && is_file($cctv_berkas)) {
    $lama = json_decode((string) file_get_contents($cctv_berkas), true);

    if (is_array($lama) && !empty($lama['kamera'])) {
        $cctv_daftar = $lama['kamera'];
        $cctv_dari_simpanan = true;
    }
}

/* 4. Simpan hasil susunan */
if ($cctv_daftar && isset($_GET['ambil'])) {
    $isi_simpan = [
        'sumber' => 'ATCS Dishub Kota Medan (diambil oleh periksa_cctv.php)',
        'diambil' => date('c'),
        'pola_stream' => CCTV_BASE . '/stream/{KODE}/stream.m3u8',
        'jumlah' => count($cctv_daftar),
        'kamera' => $cctv_daftar,
    ];

    file_put_contents($cctv_berkas, json_encode($isi_simpan, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));

    $cctv_kabar[] = 'Daftar kamera disimpan ke data/cctv_medan.json (' . count($cctv_daftar) . ' kamera). '
        . 'Berkas ini yang dibaca oleh aplikasi RTS Panel pada menu CCTV Online.';
}

/* 5. Uji tautan (hidup / mati) */
$cctv_uji = null;

if (isset($_GET['uji']) && $cctv_daftar) {
    $minta = trim((string) $_GET['uji']);
    $batas_uji = $minta === 'semua' ? count($cctv_daftar) : max(1, min((int) $minta, count($cctv_daftar)));

    $cctv_uji = [];

    if (function_exists('curl_multi_init')) {
        $multi = curl_multi_init();
        $pegangan = [];

        for ($i = 0; $i < $batas_uji; $i++) {
            $kamera = $cctv_daftar[$i];

            if (empty($kamera['url'])) {
                $cctv_uji[$i] = ['kode' => $kamera['kode'] ?? '', 'nama' => $kamera['nama'] ?? '', 'kode_http' => 0, 'hidup' => false, 'catatan' => 'tautan kosong'];
                continue;
            }

            $c = curl_init($kamera['url']);
            curl_setopt_array($c, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_TIMEOUT => 8,
                CURLOPT_CONNECTTIMEOUT => 6,
                CURLOPT_HTTPHEADER => ['Range: bytes=0-600', 'Accept: */*'],
                CURLOPT_USERAGENT => 'RTS-Panel-CCTV-Pemeriksa/1.0',
                CURLOPT_SSL_VERIFYPEER => true,
            ]);

            curl_multi_add_handle($multi, $c);
            $pegangan[(int) $c] = ['c' => $c, 'i' => $i, 'kamera' => $kamera];
        }

        $jalan = null;

        do {
            $status = curl_multi_exec($multi, $jalan);

            if ($jalan) {
                curl_multi_select($multi, 1.0);
            }
        } while ($jalan > 0 && $status === CURLM_OK);

        foreach ($pegangan as $satu) {
            $kode_http = (int) curl_getinfo($satu['c'], CURLINFO_RESPONSE_CODE);
            $isi = (string) curl_multi_getcontent($satu['c']);
            $hidup = in_array($kode_http, [200, 206], true) && stripos($isi, '#EXTM3U') !== false;

            $cctv_uji[$satu['i']] = [
                'kode' => $satu['kamera']['kode'] ?? '',
                'nama' => $satu['kamera']['nama'] ?? '',
                'kode_http' => $kode_http,
                'hidup' => $hidup,
                'catatan' => $hidup ? 'kiriman HLS diterima' : 'tidak mengirim daftar putar HLS',
            ];

            curl_multi_remove_handle($multi, $satu['c']);
            curl_close($satu['c']);
        }

        curl_multi_close($multi);
    } else {
        for ($i = 0; $i < $batas_uji; $i++) {
            $kamera = $cctv_daftar[$i];
            $minta_satu = cctv_minta($kamera['url'] ?? '', [], 8);
            $hidup = in_array($minta_satu['kode'], [200, 206], true) && stripos($minta_satu['isi'], '#EXTM3U') !== false;

            $cctv_uji[$i] = [
                'kode' => $kamera['kode'] ?? '',
                'nama' => $kamera['nama'] ?? '',
                'kode_http' => $minta_satu['kode'],
                'hidup' => $hidup,
                'catatan' => $hidup ? 'kiriman HLS diterima' : 'tidak mengirim daftar putar HLS',
            ];
        }
    }

    ksort($cctv_uji);
}

/* 6. Unduh berkas daftar */
if (isset($_GET['unduh']) && is_file($cctv_berkas)) {
    header('Content-Type: application/json; charset=utf-8');
    header('Content-Disposition: attachment; filename="cctv_medan.json"');
    readfile($cctv_berkas);
    exit;
}

$cctv_hidup = 0;
$cctv_mati = 0;

if ($cctv_uji) {
    foreach ($cctv_uji as $satu) {
        $satu['hidup'] ? $cctv_hidup++ : $cctv_mati++;
    }
}
?>
<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pemeriksa CCTV Kota Medan - RTS Panel</title>
<style>
  :root { --merah:#7b1e2b; --garis:#e5e0da; }
  * { box-sizing:border-box; }
  body { margin:0; background:#f6f4f1; color:#231f1c; font:15px/1.6 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; }
  .bungkus { max-width:1000px; margin:0 auto; padding:18px; }
  h1 { font-size:20px; margin:0 0 4px; }
  h2 { font-size:16px; margin:22px 0 8px; color:var(--merah); }
  .kartu { background:#fff; border:1px solid var(--garis); border-radius:12px; padding:14px 16px; margin-bottom:14px; }
  .tombol { display:inline-block; padding:9px 14px; margin:0 8px 8px 0; border-radius:9px; background:var(--merah); color:#fff; text-decoration:none; font-weight:600; font-size:14px; }
  .tombol.polos { background:#fff; color:var(--merah); border:1px solid var(--merah); }
  .kabar { padding:10px 12px; border-radius:9px; margin-bottom:10px; font-size:14px; }
  .kabar.ok { background:#e8f6ec; border:1px solid #b7e0c3; }
  .kabar.galat { background:#fdecec; border:1px solid #f3c2c2; }
  .kabar.info { background:#eef4fd; border:1px solid #c6d9f5; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th, td { border-bottom:1px solid var(--garis); padding:7px 8px; text-align:left; vertical-align:top; }
  th { background:#faf8f6; }
  code, pre { background:#f3f1ee; border-radius:6px; }
  code { padding:1px 5px; font-size:13px; }
  pre { padding:10px; overflow:auto; font-size:12px; max-height:340px; }
  .hidup { color:#1a7a3c; font-weight:700; }
  .mati { color:#a32020; font-weight:700; }
  .kecil { font-size:13px; color:#6a625c; }
  .angka { font-variant-numeric:tabular-nums; }
</style>
</head>
<body>
<div class="bungkus">

  <h1>Pemeriksa CCTV Kota Medan</h1>
  <p class="kecil">
    Alat bantu untuk menu <b>CCTV Online</b> (akun PRO) - mengambil daftar kamera resmi dari
    <a href="https://atcsdishub.medan.go.id/streaming" target="_blank" rel="noopener">atcsdishub.medan.go.id</a>
    dan menguji tautan videonya. Hanya membaca.
  </p>

  <?php foreach ($cctv_kabar as $satu): ?>
    <div class="kabar ok"><?= htmlspecialchars($satu) ?></div>
  <?php endforeach; ?>

  <?php if ($cctv_galat !== ''): ?>
    <div class="kabar galat"><?= htmlspecialchars($cctv_galat) ?></div>
  <?php endif; ?>

  <div class="kartu">
    <h2 style="margin-top:0">Keadaan sekarang</h2>
    <table>
      <tr><th style="width:46%">PHP di hosting</th><td class="angka"><?= htmlspecialchars(PHP_VERSION) ?></td></tr>
      <tr><th>cURL tersedia</th><td><?= function_exists('curl_init') ? 'YA (pengambilan & pengujian cepat)' : 'TIDAK - memakai cara cadangan (lebih lambat)' ?></td></tr>
      <tr><th>curl_multi (uji banyak sekaligus)</th><td><?= function_exists('curl_multi_init') ? 'YA' : 'TIDAK' ?></td></tr>
      <tr><th>Folder data/</th><td><?= is_dir(CCTV_FOLDER) ? (is_writable(CCTV_FOLDER) ? 'ADA & dapat ditulis' : 'ADA tetapi TIDAK dapat ditulis') : 'BELUM ADA (dibuat saat ?ambil=1)' ?></td></tr>
      <tr><th>Berkas daftar kamera</th><td><?= is_file($cctv_berkas)
          ? 'ADA - ' . number_format((int) filesize($cctv_berkas)) . ' huruf, umur ' . number_format(cctv_umur_jam($cctv_berkas), 1) . ' jam'
          : 'BELUM ADA' ?></td></tr>
      <tr><th>Data mentah dari ATCS</th><td><?= is_file($cctv_mentah)
          ? 'ADA - ' . number_format((int) filesize($cctv_mentah)) . ' huruf'
          : 'BELUM ADA' ?></td></tr>
      <tr><th>Jumlah kamera terbaca</th><td class="angka"><b><?= number_format(count($cctv_daftar)) ?></b><?= $cctv_dari_simpanan ? ' (dari berkas tersimpan)' : '' ?></td></tr>
    </table>

    <p style="margin-bottom:0">
      <a class="tombol" href="?ambil=1">Ambil daftar kamera dari ATCS</a>
      <a class="tombol polos" href="?paksa=1&amp;ambil=1">Ambil ulang (paksa)</a>
      <a class="tombol polos" href="?uji=10">Uji 10 tautan pertama</a>
      <a class="tombol polos" href="?uji=semua">Uji SEMUA tautan</a>
      <a class="tombol polos" href="?unduh=1">Unduh daftar (JSON)</a>
    </p>
  </div>

  <?php if ($cctv_ringkas !== null): ?>
    <div class="kartu">
      <h2 style="margin-top:0">Balasan API (ringkas)</h2>
      <table>
        <tr><th style="width:46%">Kunci teratas</th><td><code><?= htmlspecialchars(implode(', ', array_slice(array_keys($cctv_ringkas), 0, 12))) ?></code></td></tr>
        <?php if (isset($cctv_ringkas['meta']) && is_array($cctv_ringkas['meta'])): ?>
          <tr><th>meta</th><td><code><?= htmlspecialchars(json_encode($cctv_ringkas['meta'])) ?></code></td></tr>
        <?php endif; ?>
        <tr><th>Jumlah butir pada halaman ini</th><td class="angka"><?= number_format(count($cctv_ringkas['data'] ?? [])) ?></td></tr>
      </table>
    </div>
  <?php endif; ?>

  <?php if ($cctv_mentah_contoh !== ''): ?>
    <div class="kartu">
      <h2 style="margin-top:0">Contoh data mentah satu kamera (untuk memastikan nama kolom)</h2>
      <pre><?= htmlspecialchars($cctv_mentah_contoh) ?></pre>
      <p class="kecil" style="margin-bottom:0">
        Kolom yang dicari alat ini: nama (<code>nama</code>/<code>nama_alias</code>),
        tautan (<code>url_hls</code>/<code>url_stream</code>/<code>url_proxy_hls</code>),
        gambar (<code>poster</code>), dan nomor kamera (<code>id_device</code>).
      </p>
    </div>
  <?php endif; ?>

  <?php if ($cctv_uji): ?>
    <div class="kartu">
      <h2 style="margin-top:0">Hasil uji tautan (<?= number_format(count($cctv_uji)) ?> kamera)</h2>
      <div class="kabar info">
        Hidup: <b><?= number_format($cctv_hidup) ?></b> &nbsp;|&nbsp; Mati/tidak terjangkau: <b><?= number_format($cctv_mati) ?></b>.
        Kamera yang mati biasanya sedang dimatikan atau dalam perbaikan oleh Dishub - bukan kesalahan aplikasi.
      </div>
      <table>
        <tr><th>#</th><th>Kode kamera</th><th>Nama</th><th>HTTP</th><th>Keadaan</th></tr>
        <?php foreach ($cctv_uji as $i => $satu): ?>
          <tr>
            <td class="angka"><?= number_format($i + 1) ?></td>
            <td><code><?= htmlspecialchars((string) $satu['kode']) ?></code></td>
            <td><?= htmlspecialchars((string) $satu['nama']) ?></td>
            <td class="angka"><?= (int) $satu['kode_http'] ?></td>
            <td class="<?= $satu['hidup'] ? 'hidup' : 'mati' ?>"><?= $satu['hidup'] ? 'HIDUP' : 'MATI' ?>
              <span class="kecil"><?= htmlspecialchars((string) $satu['catatan']) ?></span></td>
          </tr>
        <?php endforeach; ?>
      </table>
    </div>
  <?php endif; ?>

  <?php if ($cctv_daftar): ?>
    <div class="kartu">
      <h2 style="margin-top:0">Daftar kamera (10 teratas)</h2>
      <table>
        <tr><th>#</th><th>Kode</th><th>Nama</th><th>Alias / lokasi</th><th>Tautan video</th></tr>
        <?php foreach (array_slice($cctv_daftar, 0, 10) as $i => $satu): ?>
          <tr>
            <td class="angka"><?= number_format($i + 1) ?></td>
            <td><code><?= htmlspecialchars((string) ($satu['kode'] ?? '')) ?></code></td>
            <td><?= htmlspecialchars((string) ($satu['nama'] ?? '')) ?></td>
            <td class="kecil"><?= htmlspecialchars((string) ($satu['alias'] ?? '')) ?></td>
            <td class="kecil"><a href="<?= htmlspecialchars((string) ($satu['url'] ?? '')) ?>" target="_blank" rel="noopener">buka .m3u8</a></td>
          </tr>
        <?php endforeach; ?>
      </table>
    </div>
  <?php endif; ?>

  <div class="kartu">
    <h2 style="margin-top:0">Pola tautan (untuk dipakai aplikasi)</h2>
    <p style="margin-bottom:6px">Video tiap kamera memakai pola tetap:</p>
    <p><code>https://atcsdishub.medan.go.id/stream/&lt;KODE&gt;/stream.m3u8</code></p>
    <p class="kecil" style="margin-bottom:6px">
      &lt;KODE&gt; = huruf <b>L</b> + nomor kamera + nama persimpangan tanpa spasi/tanda hubung (titik tetap), contoh:
      <code>L1RADENSALEHBALAIKOTA</code>, <code>L3KESAWANPALANGMERAH</code>, <code>L7SM.RAJAAMALIUN</code>.
      Gambar pratinjau: <code>https://atcsdishub.medan.go.id/poster/&lt;NAMA&gt;_&lt;NOMOR&gt;_&lt;LEBAR&gt;.jpg</code>
      (bila tidak ada, situs memakai <code>default_image.jpg</code>).
    </p>
    <p class="kecil" style="margin-bottom:0">
      Kunci API pada halaman ini (x-client-id/x-client-secret) adalah kunci PUBLIK milik situs ATCS
      yang dapat dibaca siapa saja pada berkas JavaScript halaman mereka - bukan kunci milik RTS Panel,
      dan tidak memuat data Bapak. Bila Dishub menggantinya, cukup perbarui dua baris di berkas ini
      atau buat berkas <code>cctv_kunci.php</code>.
    </p>
  </div>

  <p class="kecil">
    Setelah selesai dipakai, berkas ini boleh dihapus dari hosting. Bila ingin menyimpannya,
    tidak ada masalah - halaman ini tidak menulis apa pun kecuali folder <code>data/</code>.
  </p>

</div>
</body>
</html>
