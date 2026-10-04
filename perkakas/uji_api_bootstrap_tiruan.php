<?php
/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - TIRUAN api/api_bootstrap.php (bukan hosting)
 *  Berkas : perkakas/uji_api_bootstrap_tiruan.php
 *
 *  Saat pengujian, berkas ini disalin menjadi uji/api/api_bootstrap.php.
 *  Isinya SAMA PERILAKUNYA dengan api/api_bootstrap.php yang asli, tetapi
 *  database-nya memakai tiruan (perkakas/uji_mysqli_tiruan.php) sehingga
 *  tidak perlu server MySQL.
 *
 *  Yang diuji tetap berkas ASLI: api/cctv.php dan api/langganan_inti.php.
 *  Perkakas uji_cctv_api.mjs juga memeriksa bahwa setiap fungsi rts_api_*
 *  yang dipakai api/cctv.php benar-benar ADA di api/api_bootstrap.php asli.
 * ============================================================================
 */

if (!defined('RTS_API_BOOTSTRAP')) {
    define('RTS_API_BOOTSTRAP', 1);
}

function rts_api_headers(): void
{
    header('Content-Type: application/json; charset=utf-8');
}

function rts_api_response(bool $success, string $message, array $extra = [], int $status = 200): void
{
    http_response_code($status);

    echo json_encode(
        array_merge(['success' => $success, 'message' => $message], $extra),
        JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
    );

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

function rts_api_db(): mysqli
{
    static $conn = null;

    if (!$conn instanceof mysqli) {
        $conn = new RtsUjiDb();
    }

    return $conn;
}

function rts_api_input(): array
{
    static $data = null;

    if (is_array($data)) {
        return $data;
    }

    $data = $_POST;

    $mentah = file_get_contents('php://input');

    if (is_string($mentah) && trim($mentah) !== '') {
        $json = json_decode($mentah, true);

        if (is_array($json)) {
            $data = array_merge($data, $json);
        }
    }

    return $data;
}

function rts_api_param(string $key, string $default = ''): string
{
    $data = rts_api_input();
    $nilai = $data[$key] ?? $_GET[$key] ?? $default;

    return trim((string) $nilai);
}

function rts_api_bearer_token(): string
{
    $kepala = (string) ($_SERVER['HTTP_AUTHORIZATION'] ?? '');

    if ($kepala !== '' && preg_match('/Bearer\s+(.+)/i', $kepala, $cocok)) {
        return trim($cocok[1]);
    }

    return trim((string) ($_SERVER['HTTP_X_API_TOKEN'] ?? ''));
}

function rts_api_require_user(): array
{
    $token = rts_api_bearer_token();

    if ($token === '' || strlen($token) < 20) {
        rts_api_fail('Token tidak ditemukan. Silakan login kembali.', 401);
    }

    $keadaan = RtsUjiDb::$keadaan;
    $user = $keadaan['user'] ?? [];

    if (empty($keadaan['token_ada'])) {
        rts_api_fail('Sesi tidak valid. Silakan login kembali.', 401);
    }

    $kedaluwarsa = (string) ($keadaan['token_berlaku'] ?? date('Y-m-d H:i:s', time() + 86400));

    if (strtotime($kedaluwarsa) < time()) {
        rts_api_fail('Sesi sudah berakhir. Silakan login kembali.', 401);
    }

    if (strcasecmp((string) ($user['status_aktif'] ?? 'Aktif'), 'Aktif') !== 0) {
        rts_api_fail('Akun tidak aktif. Hubungi Admin.', 403);
    }

    rts_api_db()->query('UPDATE api_tokens SET last_used_at = NOW() WHERE id = ' . (int) ($keadaan['token_id'] ?? 1));

    return [
        'id' => (int) ($user['id'] ?? 1),
        'username' => (string) ($user['username'] ?? 'sales_uji'),
        'nama_lengkap' => (string) ($user['nama_lengkap'] ?? 'Sales Uji'),
        'email' => (string) ($user['email'] ?? 'uji@contoh.id'),
        'role' => strtoupper((string) ($user['role'] ?? 'RTS')),
        'salesman' => (string) ($user['salesman'] ?? 'UJI'),
        'sales_district' => (string) ($user['sales_district'] ?? 'MEDAN KOTA'),
        'akun_pro' => (int) ($user['akun_pro'] ?? 0),
    ];
}

if (!function_exists('rts_api_ada_kolom')) {
    function rts_api_ada_kolom(mysqli $conn, string $tabel, string $kolom): bool
    {
        return true;
    }
}
