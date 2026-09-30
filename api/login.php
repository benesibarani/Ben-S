<?php
/**
 * RTS Panel API - Login Android
 * Endpoint: /api/login.php
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type');
header('Access-Control-Allow-Methods: POST, OPTIONS');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode([
        'success' => false,
        'message' => 'Method tidak diizinkan.'
    ]);
    exit;
}

require_once dirname(__DIR__) . '/config.php';
require_once __DIR__ . '/kolom.php';

/**
 * Mencari koneksi database dari config.php.
 * Diperiksa pada $GLOBALS (bila config.php sudah di-include di luar fungsi)
 * maupun pada lingkup lokal (bila di-include di dalam fungsi).
 */
function rts_api_db_login(): ?mysqli
{
    foreach (['conn', 'mysqli', 'koneksi', 'db', 'link'] as $nama) {
        $kandidat = null;

        if (isset($GLOBALS[$nama]) && $GLOBALS[$nama] instanceof mysqli) {
            $kandidat = $GLOBALS[$nama];
        } elseif (isset($$nama) && $$nama instanceof mysqli) {
            $kandidat = $$nama;
        }

        if ($kandidat instanceof mysqli && !$kandidat->connect_errno) {
            $kandidat->set_charset('utf8mb4');
            return $kandidat;
        }
    }

    return null;
}

function rts_login_has_column(mysqli $conn, string $table, string $column): bool
{
    static $cache = [];

    $key = $table . '.' . $column;
    if (array_key_exists($key, $cache)) {
        return $cache[$key];
    }

    if (!$conn instanceof mysqli || $conn->connect_errno) {
        $cache[$key] = false;
        return false;
    }

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

function api_response(bool $success, string $message, array $extra = [], int $status = 200): void
{
    http_response_code($status);
    echo json_encode(array_merge([
        'success' => $success,
        'message' => $message,
    ], $extra), JSON_UNESCAPED_UNICODE);
    exit;
}

if (!isset($conn) || !($conn instanceof mysqli) || $conn->connect_errno) {
    error_log('RTS API login: database connection failed.');
    api_response(false, 'Server sedang mengalami gangguan.', [], 500);
}

$raw = file_get_contents('php://input');
$payload = json_decode($raw ?: '', true);

// Mendukung JSON Android dan form POST biasa.
$username = trim((string) ($payload['username'] ?? $_POST['username'] ?? ''));
$password = (string) ($payload['password'] ?? $_POST['password'] ?? '');
$deviceName = trim((string) ($payload['device_name'] ?? $_POST['device_name'] ?? 'Android'));

if ($username === '' || $password === '') {
    api_response(false, 'Username dan password wajib diisi.', [], 422);
}

// Tabel sales_users produksi bisa berbeda dengan staging, jadi kolom diperiksa dulu.
$punyaUsername = rts_login_has_column($conn, 'sales_users', 'username');
$punyaStatus = rts_login_has_column($conn, 'sales_users', 'status_aktif');
$punyaAkunPro = rts_api_ada_kolom($conn, 'sales_users', 'akun_pro');
$punyaSalesman = rts_login_has_column($conn, 'sales_users', 'salesman');
$punyaDistrict = rts_login_has_column($conn, 'sales_users', 'sales_district');

$kolom = [
    'id',
    'nama_lengkap',
    'email',
    'password',
    'role',
    $punyaUsername ? 'username' : "'' AS username",
    $punyaSalesman ? 'salesman' : "'' AS salesman",
    $punyaDistrict ? 'sales_district' : "'' AS sales_district",
    $punyaStatus ? 'status_aktif' : "'Aktif' AS status_aktif",
    $punyaAkunPro ? 'akun_pro' : '0 AS akun_pro',
];

$kolomLogin = $punyaUsername ? 'username' : 'email';

$stmt = $conn->prepare(
    'SELECT ' . implode(', ', $kolom) . '
     FROM sales_users
     WHERE ' . $kolomLogin . ' = ?
     LIMIT 1'
);

if (!$stmt) {
    error_log('RTS API login prepare error: ' . $conn->error);
    api_response(false, 'Server sedang mengalami gangguan.', [], 500);
}

$stmt->bind_param('s', $username);
$stmt->execute();
$result = $stmt->get_result();
$user = $result ? $result->fetch_assoc() : null;
$stmt->close();

if (!$user || !password_verify($password, (string) $user['password'])) {
    api_response(
        false,
        $punyaUsername
            ? 'Username atau password salah.'
            : 'Email atau password salah.',
        [],
        401
    );
}

if (strcasecmp((string) ($user['status_aktif'] ?? 'Aktif'), 'Aktif') !== 0) {
    api_response(false, 'Akun tidak aktif. Hubungi Admin.', [], 403);
}

$token = bin2hex(random_bytes(32));
$tokenHash = hash('sha256', $token);
$expiresAt = date('Y-m-d H:i:s', time() + (30 * 24 * 60 * 60));

$tokenStmt = $conn->prepare(
    'INSERT INTO api_tokens (user_id, token_hash, device_name, expires_at)
     VALUES (?, ?, ?, ?)'
);

if (!$tokenStmt) {
    error_log('RTS API token prepare error: ' . $conn->error);
    api_response(false, 'Tabel API belum siap di server.', [], 500);
}

$userId = (int) $user['id'];
$tokenStmt->bind_param('isss', $userId, $tokenHash, $deviceName, $expiresAt);

if (!$tokenStmt->execute()) {
    error_log('RTS API token insert error: ' . $tokenStmt->error);
    $tokenStmt->close();
    api_response(false, 'Token login gagal dibuat.', [], 500);
}
$tokenStmt->close();

api_response(true, 'Login berhasil.', [
    'token' => $token,
    'expires_at' => $expiresAt,
    'user' => [
        'id' => (int) $user['id'],
        'username' => $user['username'],
        'nama_lengkap' => $user['nama_lengkap'],
        'email' => $user['email'],
        'role' => strtoupper((string) $user['role']),
        'salesman' => $user['salesman'] ?? '',
        'sales_district' => $user['sales_district'] ?? '',
        'status_aktif' => $user['status_aktif'] ?? 'Aktif',
        'akun_pro' => rts_api_akun_pro($user),
    ],
]);
