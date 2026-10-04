<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API DAFTAR KAMERA CCTV ONLINE (KOTA MEDAN)
 *  Berkas : api/cctv.php
 *  Versi  : 1   (4 Oktober 2026)
 *
 *  Dipanggil aplikasi Android dengan token login (Authorization: Bearer ...).
 *
 *  KEGUNAAN
 *  --------
 *  Memberi daftar kamera CCTV lalu lintas Kota Medan untuk menu
 *  "CCTV Online" (khusus AKUN PRO). Daftar dibaca dari berkas
 *  data/cctv_medan.json di hosting; bila berkas itu belum ada, API ini
 *  MENGAMBIL SENDIRI daftarnya dari situs resmi ATCS Dishub Kota Medan
 *  (pola yang sama dipakai halaman periksa_cctv.php), lalu menyimpannya.
 *
 *  PERINTAH (parameter "aksi")
 *  --------------------------
 *    daftar    daftar kamera (bawaan)
 *    segarkan  ambil ulang daftar dari situs ATCS, lalu simpan
 *    uji       menguji tautan beberapa kamera (parameter kode=KODE,KODE)
 *              atau jumlah=N (menguji N kamera pertama)
 *
 *  ATURAN
 *  ------
 *    - Menu ini untuk AKUN PRO. ADMIN dan ASS tetap boleh membuka (pengelola).
 *    - Membaca saja: tidak ada tabel database Bapak yang diubah.
 *    - Kunci ATCS di bawah adalah kunci PUBLIK milik situs ATCS Dishub Kota
 *      Medan (dapat dibaca siapa saja pada berkas JavaScript halaman mereka),
 *      BUKAN kunci RTS Panel. Bila Dishub menggantinya, cukup buat berkas
 *      cctv_kunci.php di public_html berisi:
 *          <?php $cctv_client_id = '...'; $cctv_client_secret = '...';
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';

if (is_file(__DIR__ . '/langganan_inti.php')) {
    require_once __DIR__ . '/langganan_inti.php';
}

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (!in_array($metode, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$aksi = strtolower(rts_api_param('aksi', 'daftar'));

/* ------------------------------------------------------------------- aturan */

$role = strtoupper((string) ($user['role'] ?? ''));
$pengelola = in_array($role, ['ADMIN', 'ASS'], true);

$statusLangganan = [];
$akunPro = false;

if (function_exists('rts_lg_baris') && function_exists('rts_lg_status')) {
    try {
        $barisLangganan = rts_lg_baris($conn, (int) ($user['id'] ?? 0));
        $statusLangganan = rts_lg_status($barisLangganan);
        $akunPro = !empty($statusLangganan['pro']);
    } catch (Throwable $galatLangganan) {
        $akunPro = false;
    }
}

if (!$akunPro && !$pengelola) {
    rts_api_fail(
        'Menu CCTV Online khusus AKUN PRO. Buka menu Langganan PRO untuk mengaktifkannya, '
        . 'lalu tekan SINKRON AKUN pada menu Sinkronisasi.',
        403,
        [
            'perlu_pro' => true,
            'langganan' => [
                'sumber' => (string) ($statusLangganan['sumber'] ?? 'GRATIS'),
                'harga' => (int) ($statusLangganan['harga'] ?? 0),
                'durasi_hari' => (int) ($statusLangganan['durasi_hari'] ?? 30),
                'trial_hari' => (int) ($statusLangganan['trial_hari'] ?? 7),
            ],
        ]
    );
}

/* ------------------------------------------------------------------ bantuan */

/** Alamat berkas daftar kamera (data/cctv_medan.json di dalam public_html). */
function rts_cctv_berkas(): string
{
    return dirname(__DIR__) . '/data/cctv_medan.json';
}

/** Kunci API ATCS (kunci PUBLIK milik situs ATCS). */
function rts_cctv_kunci(): array
{
    $id = '8e21ec02-8cdb-47b3-a51d-a65fa742fafc';
    $rahasia = '677def13b9a745ead7d25c6ff8dd6d7154ddc4a59756e8b1c27755d59444351d';

    $berkas = dirname(__DIR__) . '/cctv_kunci.php';

    if (is_file($berkas)) {
        include $berkas;
    }

    if (is_file(__DIR__ . '/cctv_kunci.php')) {
        include __DIR__ . '/cctv_kunci.php';
    }

    return ['id' => (string) $id, 'rahasia' => (string) $rahasia];
}

/** Memotong teks dengan aman. */
function rts_cctv_potong(string $teks, int $batas): string
{
    return function_exists('mb_substr') ? mb_substr($teks, 0, $batas) : substr($teks, 0, $batas);
}

/** Membuat kode kamera dari nomor + nama (pola resmi ATCS). */
function rts_cctv_kode(int $nomor, string $nama): string
{
    return 'L' . $nomor . preg_replace('/[^A-Za-z0-9.]/', '', strtoupper($nama));
}

/** Membaca berkas daftar kamera. */
function rts_cctv_baca_berkas(): array
{
    $berkas = rts_cctv_berkas();

    if (!is_file($berkas)) {
        return [];
    }

    $isi = json_decode((string) @file_get_contents($berkas), true);

    if (!is_array($isi)) {
        return [];
    }

    $kamera = $isi['kamera'] ?? ($isi['data']['kamera'] ?? []);

    if (!is_array($kamera)) {
        return [];
    }

    return [
        'sumber' => (string) ($isi['sumber'] ?? 'ATCS Dishub Kota Medan'),
        'pola' => (string) ($isi['pola_stream'] ?? 'https://atcsdishub.medan.go.id/stream/{KODE}/stream.m3u8'),
        'diperbarui' => date('d-m-Y H:i', (int) @filemtime($berkas)),
        'kamera' => $kamera,
    ];
}

/** Membaca nilai pertama yang tersedia pada sebuah larik. */
function rts_cctv_nilai($larik, array $nama, $bawaan = '')
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

/** Mengambil daftar kamera langsung dari situs ATCS Dishub Kota Medan. */
function rts_cctv_ambil_atcs(): array
{
    $kunci = rts_cctv_kunci();
    $semua = [];
    $halaman = 1;
    $halamanMaks = 25;

    do {
        $url = 'https://atcsdishub.medan.go.id/api/v3/pv/ldevice?page=' . $halaman . '&paginate=100';

        $kepala = [
            'Accept: application/json, text/plain, */*',
            'Content-Type: application/json',
            'x-client-id: ' . $kunci['id'],
            'x-client-secret: ' . $kunci['rahasia'],
        ];

        $isi = '';
        $kodeHttp = 0;

        if (function_exists('curl_init')) {
            $c = curl_init($url);
            curl_setopt_array($c, [
                CURLOPT_RETURNTRANSFER => true,
                CURLOPT_HTTPHEADER => $kepala,
                CURLOPT_TIMEOUT => 25,
                CURLOPT_CONNECTTIMEOUT => 12,
                CURLOPT_FOLLOWLOCATION => true,
                CURLOPT_MAXREDIRS => 3,
                CURLOPT_USERAGENT => 'RTS-Panel-CCTV/1.0',
            ]);

            $isi = (string) curl_exec($c);
            $kodeHttp = (int) curl_getinfo($c, CURLINFO_RESPONSE_CODE);
            curl_close($c);
        } else {
            $konteks = stream_context_create(['http' => [
                'method' => 'GET',
                'header' => implode("\r\n", $kepala),
                'timeout' => 25,
                'ignore_errors' => true,
            ]]);

            $isi = (string) @file_get_contents($url, false, $konteks);
            $kodeHttp = $isi === '' ? 0 : 200;
        }

        if ($kodeHttp !== 200) {
            break;
        }

        $json = json_decode($isi, true);

        if (!is_array($json)) {
            break;
        }

        $butir = $json['data'] ?? [];

        if (!is_array($butir) || !$butir) {
            break;
        }

        foreach ($butir as $satu) {
            if (!is_array($satu)) {
                continue;
            }

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

            $nama = (string) rts_cctv_nilai($perangkat, ['nama', 'nama_device', 'nama_kamera']);
            $alias = (string) rts_cctv_nilai($perangkat, ['nama_alias', 'alias']);
            $lokasi = (string) rts_cctv_nilai($satu, ['nama_lokasi', 'lokasi'], $nama);
            $nomor = (int) rts_cctv_nilai(
                $perangkat,
                ['id_device', 'nomor', 'id'],
                rts_cctv_nilai($satu, ['id_device', 'id_lokasi'], 0)
            );

            $langsung = (string) rts_cctv_nilai($perangkat, ['url_hls', 'url_stream', 'url', 'hls', 'stream']);
            $poster = (string) rts_cctv_nilai($perangkat, ['poster', 'url_poster']);

            if ($poster !== '' && strpos($poster, 'http') !== 0) {
                $poster = 'https://atcsdishub.medan.go.id/' . ltrim($poster, '/');
            }

            $kode = '';

            if ($langsung !== '' && strpos($langsung, '/stream/') !== false) {
                $kode = explode('/', substr($langsung, strpos($langsung, '/stream/') + 8))[0];
            } elseif ($nama !== '' && $nomor > 0) {
                $kode = rts_cctv_kode($nomor, $nama);
            }

            if ($kode === '') {
                continue;
            }

            $tautan = ($langsung !== '' && strpos($langsung, '.m3u8') !== false)
                ? $langsung
                : 'https://atcsdishub.medan.go.id/stream/' . $kode . '/stream.m3u8';

            $semua[$kode] = [
                'kode' => $kode,
                'nomor' => $nomor,
                'nama' => $nama !== '' ? $nama : $lokasi,
                'alias' => $alias !== '' ? $alias : $lokasi,
                'url' => $tautan,
                'poster' => $poster,
                'lat' => (float) rts_cctv_nilai($satu, ['latitude', 'lat'], 0),
                'lon' => (float) rts_cctv_nilai($satu, ['longitude', 'lng', 'lon'], 0),
            ];
        }

        $halaman++;
    } while ($halaman <= $halamanMaks);

    return array_values($semua);
}

/** Menyusun daftar baku (kode, nomor, nama, alias, url, lat, lon). */
function rts_cctv_rapikan(array $kamera): array
{
    $hasil = [];

    foreach ($kamera as $satu) {
        if (!is_array($satu)) {
            continue;
        }

        $kode = (string) rts_cctv_nilai($satu, ['kode']);
        $url = (string) rts_cctv_nilai($satu, ['url', 'url_hls', 'stream']);

        if ($kode === '' && strpos($url, '/stream/') !== false) {
            $kode = explode('/', substr($url, strpos($url, '/stream/') + 8))[0];
        }

        if ($kode === '') {
            continue;
        }

        if ($url === '' || strpos($url, '.m3u8') === false) {
            $url = 'https://atcsdishub.medan.go.id/stream/' . $kode . '/stream.m3u8';
        }

        $hasil[$kode] = [
            'kode' => $kode,
            'nomor' => (int) rts_cctv_nilai($satu, ['nomor'], 0),
            'nama' => (string) rts_cctv_nilai($satu, ['nama'], $kode),
            'alias' => (string) rts_cctv_nilai($satu, ['alias'], ''),
            'url' => $url,
            'poster' => (string) rts_cctv_nilai($satu, ['poster'], ''),
            'lat' => (float) rts_cctv_nilai($satu, ['lat', 'latitude'], 0),
            'lon' => (float) rts_cctv_nilai($satu, ['lon', 'longitude', 'lng'], 0),
        ];
    }

    $daftar = array_values($hasil);

    usort($daftar, static function (array $a, array $b): int {
        if ($a['nomor'] === $b['nomor']) {
            return strcmp((string) $a['nama'], (string) $b['nama']);
        }

        return $a['nomor'] <=> $b['nomor'];
    });

    return $daftar;
}

/** Menyimpan daftar kamera ke data/cctv_medan.json. */
function rts_cctv_simpan(array $kamera): bool
{
    $folder = dirname(__DIR__) . '/data';

    if (!is_dir($folder)) {
        @mkdir($folder, 0755, true);
    }

    if (!is_dir($folder) || !is_writable($folder)) {
        return false;
    }

    $isi = [
        'sumber' => 'ATCS Dishub Kota Medan (diambil oleh api/cctv.php)',
        'diambil' => date('c'),
        'pola_stream' => 'https://atcsdishub.medan.go.id/stream/{KODE}/stream.m3u8',
        'jumlah' => count($kamera),
        'kamera' => $kamera,
    ];

    return (bool) @file_put_contents(
        rts_cctv_berkas(),
        json_encode($isi, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)
    );
}

/** Menguji satu tautan kamera (hidup / tidak). */
function rts_cctv_uji(string $url): array
{
    if ($url === '') {
        return ['hidup' => false, 'kode_http' => 0, 'catatan' => 'tautan kosong'];
    }

    if (function_exists('curl_init')) {
        $c = curl_init($url);
        curl_setopt_array($c, [
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => 8,
            CURLOPT_CONNECTTIMEOUT => 6,
            CURLOPT_HTTPHEADER => ['Range: bytes=0-600', 'Accept: */*'],
            CURLOPT_USERAGENT => 'RTS-Panel-CCTV/1.0',
        ]);

        $isi = (string) curl_exec($c);
        $kode = (int) curl_getinfo($c, CURLINFO_RESPONSE_CODE);
        curl_close($c);

        $hidup = in_array($kode, [200, 206], true) && stripos($isi, '#EXTM3U') !== false;

        return [
            'hidup' => $hidup,
            'kode_http' => $kode,
            'catatan' => $hidup ? 'siaran tersedia' : 'tidak mengirim daftar putar HLS',
        ];
    }

    $konteks = stream_context_create(['http' => [
        'method' => 'GET',
        'header' => "Range: bytes=0-600\r\nAccept: */*",
        'timeout' => 8,
        'ignore_errors' => true,
    ]]);

    $isi = (string) @file_get_contents($url, false, $konteks);
    $hidup = stripos($isi, '#EXTM3U') !== false;

    return [
        'hidup' => $hidup,
        'kode_http' => $hidup ? 200 : 0,
        'catatan' => $hidup ? 'siaran tersedia' : 'tidak mengirim daftar putar HLS',
    ];
}

/* --------------------------------------------------------------------- jalan */

$data = rts_cctv_baca_berkas();
$kamera = rts_cctv_rapikan($data['kamera'] ?? []);
$pesanKhusus = '';

if ($aksi === 'segarkan' || ($kamera === [] && $aksi === 'daftar')) {
    $dariAtcs = rts_cctv_ambil_atcs();

    if ($dariAtcs) {
        $kamera = rts_cctv_rapikan($dariAtcs);
        $tersimpan = rts_cctv_simpan($kamera);
        $data = [
            'sumber' => 'ATCS Dishub Kota Medan',
            'pola' => 'https://atcsdishub.medan.go.id/stream/{KODE}/stream.m3u8',
            'diperbarui' => date('d-m-Y H:i'),
            'kamera' => $kamera,
        ];

        if ($aksi === 'segarkan') {
            $pesanKhusus = 'Daftar kamera berhasil diperbarui dari situs ATCS: '
                . count($kamera) . ' kamera.';
        }

        if ($aksi === 'segarkan' && !$tersimpan) {
            rts_api_fail(
                'Daftar kamera berhasil diambil, tetapi tidak dapat disimpan. '
                . 'Pastikan folder data/ ada di dalam public_html dan dapat ditulis.',
                500,
                ['jumlah' => count($kamera)]
            );
        }
    } elseif ($kamera !== []) {
        if ($aksi === 'segarkan') {
            $pesanKhusus = 'Situs ATCS belum dapat dihubungi dari hosting, jadi daftar '
                . 'kamera sebelumnya (' . count($kamera) . ' kamera) tetap dipakai. '
                . 'Coba lagi beberapa saat lagi.';
        }
    } elseif ($kamera === []) {
        rts_api_fail(
            'Daftar kamera belum tersedia dan situs ATCS Dishub belum dapat dihubungi dari hosting ini. '
            . 'Buka halaman periksa_cctv.php?ambil=1 pada website, atau salin berkas cctv_medan.json '
            . 'ke folder data/ di dalam public_html.',
            503,
            ['perlu_berkas' => true]
        );
    }
}

if ($aksi === 'uji') {
    $minta = trim((string) rts_api_param('kode', ''));
    $dipilih = [];

    if ($minta !== '') {
        $kodeDiminta = array_filter(array_map('strtoupper', array_map('trim', explode(',', $minta))));

        foreach ($kamera as $satu) {
            if (in_array(strtoupper((string) $satu['kode']), $kodeDiminta, true)) {
                $dipilih[] = $satu;
            }
        }
    } else {
        $jumlah = max(1, min((int) rts_api_param('jumlah', '10'), 30));

        $dipilih = array_slice($kamera, 0, $jumlah);
    }

    $hasil = [];

    foreach ($dipilih as $satu) {
        $uji = rts_cctv_uji((string) $satu['url']);

        $hasil[] = [
            'kode' => $satu['kode'],
            'nama' => $satu['nama'],
            'hidup' => (bool) $uji['hidup'],
            'kode_http' => (int) $uji['kode_http'],
            'catatan' => (string) $uji['catatan'],
        ];
    }

    $hidup = 0;

    foreach ($hasil as $satu) {
        if ($satu['hidup']) {
            $hidup++;
        }
    }

    rts_api_response(true, 'Pemeriksaan tautan selesai: ' . $hidup . ' dari ' . count($hasil) . ' kamera hidup.', [
        'data' => [
            'jumlah' => count($hasil),
            'hidup' => $hidup,
            'kamera' => $hasil,
        ],
    ]);
}

if (!$kamera) {
    rts_api_fail('Daftar kamera kosong. Jalankan periksa_cctv.php?ambil=1 pada website.', 503);
}

rts_api_response(
    true,
    $pesanKhusus !== ''
        ? $pesanKhusus
        : count($kamera) . ' kamera CCTV Kota Medan siap dipakai.',
    [
        'data' => [
            'jumlah' => count($kamera),
            'sumber' => (string) ($data['sumber'] ?? 'ATCS Dishub Kota Medan'),
            'pola' => (string) ($data['pola'] ?? ''),
            'diperbarui' => (string) ($data['diperbarui'] ?? ''),
            'akun_pro' => $akunPro ? 1 : 0,
            'dari_situs' => $pesanKhusus !== '' && strpos($pesanKhusus, 'berhasil diperbarui') !== false ? 1 : 0,
            'kamera' => $kamera,
        ],
    ]
);
