<?php
/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - PENGUJI api/cctv.php (bukan untuk hosting)
 *  Berkas : perkakas/uji_tes_cctv_api.php
 *
 *  Dijalankan oleh perkakas/uji_cctv_api.mjs memakai perkakas/run_php.mjs
 *  (PHP 8.2 asli / php-wasm). Satu kali jalan = SATU keadaan, karena
 *  api/cctv.php memanggil exit setelah menjawab.
 *
 *  Keadaan dibaca dari uji/keadaan.json. Hasil dicetak di antara penanda:
 *      ###JSON###  ... balasan JSON api/cctv.php ...  ###END###
 *      kode_http=NNN
 * ============================================================================
 */

$berkasUji = __DIR__;
$berkasKeadaan = $berkasUji . '/keadaan.json';

if (!is_file($berkasKeadaan)) {
    echo "###GALAT### keadaan.json tidak ada\n";

    exit(2);
}

$keadaan = json_decode((string) file_get_contents($berkasKeadaan), true);

if (!is_array($keadaan)) {
    echo "###GALAT### keadaan.json tidak dapat dibaca\n";

    exit(2);
}

require_once $berkasUji . '/mysqli_tiruan.php';

RtsUjiDb::$keadaan = $keadaan;

/* -------------------------------------------------------------------------
 * Fungsi yang membaca properti bawaan mysqli_result::num_rows tidak dapat
 * dipakai pada tiruan, jadi diganti tiruannya LEBIH DULU. Berkas
 * api/langganan_inti.php membungkus setiap fungsinya dengan
 * if (!function_exists(...)), sehingga tiruan di bawah ini yang dipakai.
 * ---------------------------------------------------------------------- */

function rts_lg_ada_tabel(mysqli $conn, string $nama): bool
{
    return false;
}

function rts_lg_ada_kolom(mysqli $conn, string $kolom): bool
{
    return true;
}

if (!function_exists('rts_api_ada_kolom')) {
    function rts_api_ada_kolom(mysqli $conn, string $tabel, string $kolom): bool
    {
        return true;
    }
}

/* --------------------------------------------------------------- permintaan */

$_SERVER['REQUEST_METHOD'] = (string) ($keadaan['metode'] ?? 'GET');
$_SERVER['SCRIPT_FILENAME'] = $berkasUji . '/api/cctv.php';
$_SERVER['HTTP_AUTHORIZATION'] = isset($keadaan['token']) && $keadaan['token'] !== ''
    ? 'Bearer ' . (string) $keadaan['token']
    : '';

$_GET = [];

foreach ((array) ($keadaan['get'] ?? []) as $kunci => $nilai) {
    $_GET[(string) $kunci] = (string) $nilai;
}

$_POST = [];

/* ------------------------------------------------------- penangkap keluaran */

ob_start();

register_shutdown_function(static function (): void {
    $isi = (string) ob_get_contents();

    ob_end_clean();

    echo "###JSON###\n" . trim($isi) . "\n###END###\n";
    echo 'kode_http=' . (int) http_response_code() . "\n";
});

require $berkasUji . '/api/cctv.php';
