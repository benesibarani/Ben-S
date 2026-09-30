<?php
/**
 * RTS Panel API - Keterangan Versi Aplikasi Android
 * Endpoint: /api/app_versi.php
 *
 * KEGUNAAN
 * --------
 * Dibaca oleh aplikasi RTS Panel setiap kali dibuka, untuk mengetahui apakah
 * sudah ada versi baru. Bila kode versi di server lebih besar dari versi yang
 * terpasang di HP, aplikasi menampilkan kotak pemberitahuan pembaruan.
 *
 * CARA PAKAI
 * ----------
 *   GET https://rts.benedic-s.com/api/app_versi.php
 *
 * Balasan sukses:
 * {
 *   "success": true,
 *   "message": "Versi terbaru tersedia.",
 *   "versi": {
 *     "version_code": 3,
 *     "version_name": "1.2.0",
 *     "wajib": false,
 *     "catatan": "Perbaikan filter GSP...",
 *     "apk": "https://rts.benedic-s.com/apk/rts_panel_v3.apk",
 *     "ukuran_mb": 12.4,
 *     "dipublikasikan": "30-09-2026 11:20"
 *   }
 * }
 *
 * Bila belum ada versi yang diumumkan (atau tabelnya belum dibuat):
 * {
 *   "success": false,
 *   "message": "Belum ada versi aplikasi yang diumumkan."
 * }
 *
 * CATATAN PENTING
 * ---------------
 * - Endpoint ini TIDAK memerlukan token, karena keterangan versi bukan data
 *   pribadi, dan aplikasi harus tetap dapat memeriksa pembaruan walau sesi
 *   login pengguna sudah berakhir.
 * - Endpoint ini TIDAK memakai tabel information_schema, karena akun database
 *   cPanel tidak diberi izin membacanya.
 * - Tabel rts_app_versi dibuat dengan menjalankan RTS_PANEL_APP_VERSI.sql.
 * - Bila tabel belum ada, balasan tetap berupa JSON yang sah (success: false)
 *   sehingga aplikasi dengan tenang beralih memakai berkas apk/app_versi.json.
 */

require_once dirname(__DIR__) . '/config.php';

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Api-Token');
header('Access-Control-Allow-Methods: GET, OPTIONS');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

/**
 * Mengirim balasan JSON lalu berhenti.
 *
 * @param array<string,mixed> $data
 */
function rts_versi_jawab(array $data, int $status = 200): void
{
    http_response_code($status);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

/* ------------------------------------------------------------------ koneksi */

$rts_versi_conn = null;

foreach (['conn', 'mysqli', 'koneksi', 'db', 'link'] as $nama) {
    if (isset($GLOBALS[$nama]) && $GLOBALS[$nama] instanceof mysqli) {
        $rts_versi_conn = $GLOBALS[$nama];
        break;
    }

    if (isset($$nama) && $$nama instanceof mysqli) {
        $rts_versi_conn = $$nama;
        break;
    }
}

if (!($rts_versi_conn instanceof mysqli) || $rts_versi_conn->connect_errno) {
    rts_versi_jawab([
        'success' => false,
        'message' => 'Server sedang mengalami gangguan.',
    ], 500);
}

$rts_versi_conn->set_charset('utf8mb4');

/* ------------------------------------------------------- periksa tabel ada */

$ada_tabel = false;

$hasil_tabel = @$rts_versi_conn->query("SHOW TABLES LIKE 'rts_app_versi'");

if ($hasil_tabel instanceof mysqli_result) {
    $ada_tabel = $hasil_tabel->num_rows > 0;
    $hasil_tabel->free();
}

if (!$ada_tabel) {
    rts_versi_jawab([
        'success' => false,
        'message' => 'Belum ada versi aplikasi yang diumumkan.',
        'petunjuk' => 'Jalankan RTS_PANEL_APP_VERSI.sql pada database, lalu '
            . 'unggah APK lewat halaman app_versi.php.',
    ]);
}

/* ------------------------------------------------------ ambil versi terbaru */

$versi = null;

$ambil = @$rts_versi_conn->query(
    'SELECT version_code, version_name, wajib, catatan, apk, ukuran_mb, dibuat_pada
     FROM rts_app_versi
     WHERE aktif = 1
     ORDER BY version_code DESC, id DESC
     LIMIT 1'
);

if ($ambil instanceof mysqli_result) {
    $versi = $ambil->fetch_assoc();
    $ambil->free();
}

/* Bila tidak ada baris berstatus aktif, dipakai baris terbaru apa pun. */
if (!$versi) {
    $ambil2 = @$rts_versi_conn->query(
        'SELECT version_code, version_name, wajib, catatan, apk, ukuran_mb, dibuat_pada
         FROM rts_app_versi
         ORDER BY version_code DESC, id DESC
         LIMIT 1'
    );

    if ($ambil2 instanceof mysqli_result) {
        $versi = $ambil2->fetch_assoc();
        $ambil2->free();
    }
}

if (!$versi || trim((string) ($versi['apk'] ?? '')) === '') {
    rts_versi_jawab([
        'success' => false,
        'message' => 'Belum ada versi aplikasi yang diumumkan.',
    ]);
}

/* ------------------------------------------------------------------ balasan */

$waktu = (string) ($versi['dibuat_pada'] ?? '');

$waktu_rapi = $waktu;

if ($waktu !== '') {
    $cap = strtotime($waktu);

    if ($cap !== false) {
        $waktu_rapi = date('d-m-Y H:i', $cap);
    }
}

rts_versi_jawab([
    'success' => true,
    'message' => 'Versi terbaru tersedia.',
    'versi' => [
        'version_code' => (int) ($versi['version_code'] ?? 0),
        'version_name' => (string) ($versi['version_name'] ?? ''),
        'wajib' => ((int) ($versi['wajib'] ?? 0)) === 1,
        'catatan' => (string) ($versi['catatan'] ?? ''),
        'apk' => (string) $versi['apk'],
        'ukuran_mb' => (float) ($versi['ukuran_mb'] ?? 0),
        'dipublikasikan' => $waktu_rapi,
    ],
]);
