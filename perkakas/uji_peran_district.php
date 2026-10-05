<?php
/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - PERAN WSS & SMST = SEMUA DISTRICT
 *  Berkas : perkakas/uji_peran_district.php
 *
 *  Cara pakai (PHP 8.2 asli, tanpa server web):
 *      node perkakas/run_php.mjs perkakas uji_peran_district.php
 *
 *  Yang diuji: fungsi ASLI dari api/api_bootstrap.php
 *      rts_api_peran_semua_district()
 *      rts_api_peran_semua_district_akun()
 *      rts_api_scope()
 *
 *  Fungsi-fungsi itu diambil apa adanya dari berkas asli (bukan disalin),
 *  kemudian dijalankan pada beberapa contoh akun. Dengan begitu, bila suatu
 *  saat daftar perannya berubah, pengujian ini akan ikut mengikuti berkas
 *  aslinya.
 *
 *  CATATAN PENTING: seluruh berkas api/api_bootstrap.php TIDAK dijalankan
 *  (agar tidak menyentuh database). Hanya ketiga fungsi di atas yang diuji.
 * ============================================================================
 */

$berkas = dirname(__DIR__) . '/api/api_bootstrap.php';

if (!is_file($berkas)) {
    echo "[X] api/api_bootstrap.php tidak ditemukan\n";

    exit(1);
}

$isi = (string) file_get_contents($berkas);

/* --------------------------------------------------------------------------
 * Ambil ketiga fungsi dari berkas asli. Pola di bawah cocok dengan bentuk
 * penulisan fungsi pada bootstrap (termasuk komentar docblock di atasnya
 * tidak diambil, hanya badannya).
 * ----------------------------------------------------------------------- */

$pola = '/function rts_api_(peran_semua_district|peran_semua_district_akun|scope)\(.*?\n\}/s';

if (!preg_match_all($pola, $isi, $cocok)) {
    echo "[X] ketiga fungsi tidak ditemukan pada api/api_bootstrap.php\n";

    exit(1);
}

$fungsi = implode("\n\n", $cocok[0]);

if (substr_count($fungsi, 'function rts_api_') !== 3) {
    echo "[X] jumlah fungsi yang diambil tidak tiga: " . substr_count($fungsi, 'function rts_api_') . "\n";

    exit(1);
}

/* eval HANYA berisi fungsi yang diambil dari berkas asli. */
eval($fungsi);

$lulus = 0;
$gagal = 0;

function periksa(string $nama, bool $syarat, string $tambahan = ''): void
{
    global $lulus, $gagal;

    if ($syarat) {
        $lulus++;
        echo "   [V] $nama\n";
    } else {
        $gagal++;
        echo "   [X] $nama" . ($tambahan !== '' ? " -> $tambahan" : '') . "\n";
    }
}

echo "[1] Kewenangan peran pada rts_api_peran_semua_district_akun()\n";

$kasus = [
    'ADMIN'       => true,
    'ASS'         => true,
    'WSS'         => true,
    'SMST'        => true,
    'wss'         => true,
    ' smst '      => true,
    'WSS GROSIR'  => true,
    'SMST-MODERN' => true,
    'WSS/OUTLET'  => true,
    'RTS'         => false,
    'TF'          => false,
    'GROSIR'      => false,
    ''            => false,
];

foreach ($kasus as $peran => $harapan) {
    $hasil = rts_api_peran_semua_district_akun((string) $peran);

    periksa(
        'peran "' . $peran . '" => ' . ($harapan ? 'SEMUA DISTRICT' : 'dibatasi'),
        $hasil === $harapan,
        'hasil=' . var_export($hasil, true)
    );
}

echo "\n[2] Cakupan data rts_api_scope() untuk akun per contoh\n";

$akun = [
    [
        'nama' => 'WSS Medan (district kosong)',
        'user' => ['role' => 'WSS', 'sales_district' => '', 'salesman' => ''],
        'mode' => 'all',
    ],
    [
        'nama' => 'SMST Medan Kota (district diisi)',
        'user' => ['role' => 'SMST', 'sales_district' => 'MEDAN KOTA', 'salesman' => 'A'],
        'mode' => 'all',
    ],
    [
        'nama' => 'RTS dengan district',
        'user' => ['role' => 'RTS', 'sales_district' => 'MEDAN KOTA', 'salesman' => 'A'],
        'mode' => 'district',
    ],
    [
        'nama' => 'TF dengan district',
        'user' => ['role' => 'TF', 'sales_district' => 'DENAI', 'salesman' => 'B'],
        'mode' => 'district',
    ],
    [
        'nama' => 'RTS tanpa district (pengaman salesman)',
        'user' => ['role' => 'RTS', 'sales_district' => '', 'salesman' => 'C'],
        'mode' => 'salesman',
    ],
    [
        'nama' => 'RTS tanpa district & salesman',
        'user' => ['role' => 'RTS', 'sales_district' => '', 'salesman' => ''],
        'mode' => 'none',
    ],
];

foreach ($akun as $satu) {
    $scope = rts_api_scope($satu['user']);

    periksa(
        $satu['nama'] . ' => mode "' . $satu['mode'] . '"',
        ($scope['mode'] ?? '') === $satu['mode'],
        'mode=' . var_export($scope['mode'] ?? null, true)
    );
}

echo "\n[3] Keterangan (label) yang dibaca aplikasi\n";

$wss = rts_api_scope(['role' => 'WSS', 'sales_district' => 'MEDAN KOTA', 'salesman' => '']);
$rts = rts_api_scope(['role' => 'RTS', 'sales_district' => 'MEDAN KOTA', 'salesman' => '']);

periksa('WSS berlabel "Semua district"', ($wss['label'] ?? '') === 'Semua district', (string) ($wss['label'] ?? ''));
periksa('WSS: semua_district = true', ($wss['semua_district'] ?? false) === true);
periksa('WSS: all_area = true', ($wss['all_area'] ?? false) === true);
periksa('RTS berlabel "Sales District: MEDAN KOTA"', ($rts['label'] ?? '') === 'Sales District: MEDAN KOTA', (string) ($rts['label'] ?? ''));
periksa('RTS: semua_district = false', ($rts['semua_district'] ?? true) === false);

echo "\n============================================================\n";
echo '  HASIL: ' . $lulus . ' LULUS / ' . $gagal . " GAGAL\n";
echo "============================================================\n";

exit($gagal === 0 ? 0 : 1);
