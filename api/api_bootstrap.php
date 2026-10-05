<?php
/**
 * RTS Panel API - Bootstrap
 * File ini TIDAK BOLEH diakses langsung dari browser.
 * Dipakai oleh endpoint API lain (customers.php, customer_detail.php, dsb).
 */

if (!defined('RTS_API_BOOTSTRAP')) {
    define('RTS_API_BOOTSTRAP', 1);
} else {
    return;
}

if (basename((string) ($_SERVER['SCRIPT_FILENAME'] ?? '')) === basename(__FILE__)) {
    http_response_code(403);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['success' => false, 'message' => 'Akses langsung tidak diizinkan.']);
    exit;
}

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

/* ------------------------------------------------------------------ output */

function rts_api_headers(): void
{
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store');
    header('X-Content-Type-Options: nosniff');
    header('Access-Control-Allow-Origin: *');
    header('Access-Control-Allow-Headers: Content-Type, Authorization, X-Api-Token');
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
}

function rts_api_response(bool $success, string $message, array $extra = [], int $status = 200): void
{
    http_response_code($status);
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message,
    ], $extra), JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function rts_api_fail(string $message, int $status = 400, array $extra = []): void
{
    rts_api_response(false, $message, $extra, $status);
}

function rts_api_handle_preflight(): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

/* --------------------------------------------------------------- database */

/* Pemeriksaan keberadaan kolom (dipakai untuk kolom baru seperti akun_pro). */
require_once __DIR__ . '/kolom.php';

function rts_api_db(): mysqli
{
    static $conn = null;

    if ($conn instanceof mysqli && !$conn->connect_errno) {
        return $conn;
    }

    require_once dirname(__DIR__) . '/config.php';

    // config.php website memakai variabel $conn. Beberapa penamaan lain tetap didukung.
    // Diperiksa pada $GLOBALS (config.php di-include di luar fungsi) maupun pada
    // lingkup lokal (config.php di-include di dalam fungsi ini).
    foreach (['conn', 'mysqli', 'koneksi', 'db', 'link'] as $nama) {
        $kandidat = null;

        if (isset($GLOBALS[$nama]) && $GLOBALS[$nama] instanceof mysqli) {
            $kandidat = $GLOBALS[$nama];
        } elseif (isset($$nama) && $$nama instanceof mysqli) {
            $kandidat = $$nama;
        }

        if ($kandidat instanceof mysqli && !$kandidat->connect_errno) {
            $conn = $kandidat;
            $conn->set_charset('utf8mb4');

            return $conn;
        }
    }

    error_log('RTS API: koneksi database gagal.');
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

/* ----------------------------------------------------------- struktur tabel */

/**
 * Memeriksa apakah sebuah kolom ada pada tabel.
 * Dipakai agar API tetap berjalan walaupun migrasi belum dijalankan penuh.
 */
function rts_api_has_column(string $table, string $column): bool
{
    static $cache = [];

    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) {
        return $cache[$key];
    }

    $conn = rts_api_db();

    $stmt = $conn->prepare(
        'SELECT COUNT(*) AS total
         FROM information_schema.COLUMNS
         WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
    );

    if (!$stmt) {
        $cache[$key] = false;
        return false;
    }

    $stmt->bind_param('ss', $table, $column);
    $stmt->execute();
    $result = $stmt->get_result();
    $baris = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    $ada = $baris && (int) $baris['total'] > 0;

    $cache[$key] = $ada;

    return $ada;
}

/* ------------------------------------------------------------ request data */

function rts_api_input(): array
{
    static $data = null;

    if (is_array($data)) {
        return $data;
    }

    $data = $_POST;

    $raw = file_get_contents('php://input');
    if (is_string($raw) && trim($raw) !== '') {
        $json = json_decode($raw, true);
        if (is_array($json)) {
            $data = array_merge($data, $json);
        }
    }

    return $data;
}

function rts_api_param(string $key, string $default = ''): string
{
    $data = rts_api_input();
    $value = $data[$key] ?? $_GET[$key] ?? $default;

    return trim((string) $value);
}

/* ------------------------------------------------------------------- token */

/**
 * Membaca token dari header Authorization: Bearer xxx atau X-Api-Token.
 */
function rts_api_bearer_token(): string
{
    $header = '';

    if (!empty($_SERVER['HTTP_AUTHORIZATION'])) {
        $header = (string) $_SERVER['HTTP_AUTHORIZATION'];
    } elseif (!empty($_SERVER['REDIRECT_HTTP_AUTHORIZATION'])) {
        $header = (string) $_SERVER['REDIRECT_HTTP_AUTHORIZATION'];
    } elseif (function_exists('apache_request_headers')) {
        $headers = apache_request_headers();
        if (is_array($headers)) {
            foreach ($headers as $name => $value) {
                if (strcasecmp((string) $name, 'Authorization') === 0) {
                    $header = (string) $value;
                    break;
                }
            }
        }
    }

    if ($header !== '' && preg_match('/Bearer\s+(.+)/i', $header, $match)) {
        return trim($match[1]);
    }

    return trim((string) ($_SERVER['HTTP_X_API_TOKEN'] ?? ''));
}

/**
 * Memvalidasi token dan mengembalikan data user yang sedang login.
 * Struktur: [id, username, nama_lengkap, role, salesman, sales_district]
 */
function rts_api_require_user(): array
{
    $token = rts_api_bearer_token();

    if ($token === '' || strlen($token) < 20) {
        rts_api_fail('Token tidak ditemukan. Silakan login kembali.', 401);
    }

    $conn = rts_api_db();
    $hash = hash('sha256', $token);

    // Kolom akun_pro (penanda Akun PRO) hanya dipakai bila sudah ada, supaya
    // API tetap berjalan pada database yang belum ditambahi kolom itu.
    $punyaAkunPro = rts_api_ada_kolom($conn, 'sales_users', 'akun_pro');

    $kolomAkunPro = $punyaAkunPro ? 'u.akun_pro' : '0 AS akun_pro';

    $stmt = $conn->prepare(
        'SELECT t.id AS token_id, t.expires_at, u.id, u.username, u.nama_lengkap, u.email, u.role,
                u.salesman, u.sales_district, u.status_aktif, ' . $kolomAkunPro . '
         FROM api_tokens t
         INNER JOIN sales_users u ON u.id = t.user_id
         WHERE t.token_hash = ?
         LIMIT 1'
    );

    if (!$stmt) {
        error_log('RTS API token prepare error: ' . $conn->error);
        rts_api_fail('Server sedang mengalami gangguan.', 500);
    }

    $stmt->bind_param('s', $hash);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    if (!$row) {
        rts_api_fail('Sesi tidak valid. Silakan login kembali.', 401);
    }

    if (strtotime((string) $row['expires_at']) < time()) {
        rts_api_fail('Sesi sudah berakhir. Silakan login kembali.', 401);
    }

    if (strcasecmp((string) ($row['status_aktif'] ?? 'Aktif'), 'Aktif') !== 0) {
        rts_api_fail('Akun tidak aktif. Hubungi Admin.', 403);
    }

    $conn->query('UPDATE api_tokens SET last_used_at = NOW() WHERE id = ' . (int) $row['token_id']);

    return [
        'id' => (int) $row['id'],
        'username' => (string) $row['username'],
        'nama_lengkap' => (string) $row['nama_lengkap'],
        'email' => (string) ($row['email'] ?? ''),
        'role' => strtoupper((string) $row['role']),
        'salesman' => (string) ($row['salesman'] ?? ''),
        'sales_district' => (string) ($row['sales_district'] ?? ''),
        'akun_pro' => rts_api_akun_pro($row),
    ];
}

/* -------------------------------------------------------------------- hak */

/**
 * Peran yang melihat SELURUH district (tidak dipotong Sales District).
 *
 * - ADMIN, ASS               : pengelola
 * - WSS  (Warehouse Shoe Sale)        : outlet sendiri, ada di SETIAP district
 * - SMST (Sales Modern Small Trade)   : outlet sendiri, ada di SETIAP district
 *
 * Karena WSS dan SMST berada di setiap district, daftar customer mereka tidak
 * boleh dibatasi menurut Sales District akun.
 */
function rts_api_peran_semua_district(): array
{
    return ['ADMIN', 'ASS', 'WSS', 'SMST'];
}

/**
 * True bila akun berperan WSS / SMST (termasuk penulisan bervariasi pada
 * database, misalnya "WSS GROSIR" atau "SMST-MODERN").
 */
function rts_api_peran_semua_district_akun(string $role): bool
{
    $role = strtoupper(trim($role));

    if ($role === '') {
        return false;
    }

    if (in_array($role, rts_api_peran_semua_district(), true)) {
        return true;
    }

    foreach (['WSS', 'SMST'] as $kode) {
        if (str_starts_with($role, $kode . ' ')
            || str_starts_with($role, $kode . '-')
            || str_starts_with($role, $kode . '/')) {
            return true;
        }
    }

    return false;
}

/**
 * Hak pada modul pengajuan.
 * - ADMIN, ASS        : melihat semua dan boleh approve / reject
 * - WSS, SMST         : melihat semua, tidak boleh approve
 * - RTS, TF           : hanya pengajuan milik sendiri
 */
function rts_api_request_scope(array $user): array
{
    $semuaDistrict = rts_api_peran_semua_district_akun((string) ($user['role'] ?? ''));

    return [
        'role' => $user['role'],
        'can_approve' => in_array($user['role'], ['ADMIN', 'ASS'], true),
        // WSS & SMST melihat semua customer (ada di setiap district).
        'can_view_all' => $semuaDistrict,
        'semua_district' => $semuaDistrict,
        'email' => $user['email'],
    ];
}

/**
 * Menentukan cakupan data customer sesuai peran.
 * - ADMIN  : semua customer, boleh approve / reject
 * - ASS    : semua customer, boleh approve / reject
 * - WSS    : semua customer semua district, tidak boleh approve
 * - SMST   : semua customer semua district, tidak boleh approve
 * - RTS    : hanya customer dengan salesman yang ditugaskan
 * - TF     : hanya customer dengan salesman yang ditugaskan
 */
function rts_api_scope(array $user): array
{
    $role = $user['role'];
    // WSS & SMST ada di setiap district - daftar customer-nya TIDAK dipotong
    // menurut Sales District (lihat rts_api_peran_semua_district_akun).
    $allArea = rts_api_peran_semua_district_akun((string) $role);
    $district = trim((string) ($user['sales_district'] ?? ''));
    $salesman = trim((string) ($user['salesman'] ?? ''));

    if ($allArea) {
        $mode = 'all';
    } elseif ($district !== '') {
        // RTS dan TF dibatasi sesuai Sales District.
        $mode = 'district';
    } elseif ($salesman !== '') {
        // Pengaman: bila district belum diisi, dipakai pembatasan salesman.
        $mode = 'salesman';
    } else {
        // Tanpa district dan tanpa salesman: tidak ada data yang ditampilkan.
        $mode = 'none';
    }

    $label = 'Semua district';
    if ($mode === 'district') {
        $label = 'Sales District: ' . $district;
    } elseif ($mode === 'salesman') {
        $label = 'Salesman: ' . $salesman;
    } elseif ($mode === 'none') {
        $label = 'Belum ada penugasan district';
    }

    return [
        'role' => $role,
        'all_area' => $allArea,
        'semua_district' => $allArea,
        'can_approve' => in_array($role, ['ADMIN', 'ASS'], true),
        'salesman' => $salesman,
        'sales_district' => $district,
        'district_upper' => strtoupper($district),
        'mode' => $mode,
        'label' => $label,
    ];
}
