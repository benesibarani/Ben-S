<?php
/**
 * RTS Panel API - Daftar Customer
 * Endpoint : /api/customers.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Parameter (GET atau POST):
 *   q        : cari nama toko / id customer / salesman
 *   tipe     : REGULER | GSP
 *   status   : Aktif | Nonaktif
 *   district : nama district
 *   page     : halaman (default 1)
 *   limit    : jumlah per halaman (default 20, maksimal 100)
 *
 * Catatan:
 *   Bila kolom master_toko.tipe_customer belum ada, filter tipe diabaikan
 *   dan balasan memuat "tipe_available": false agar aplikasi tidak
 *   menampilkan angka yang menyesatkan.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if (!in_array($method, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$scope = rts_api_scope($user);
$conn = rts_api_db();

// Kolom tipe_customer mungkin belum ada bila migrasi belum dijalankan penuh.
$hasTipe = rts_api_has_column('master_toko', 'tipe_customer');
$tipeExpr = $hasTipe ? 'tipe_customer' : "'REGULER' AS tipe_customer";

$search = strtoupper(rts_api_param('q'));
$tipe = strtoupper(rts_api_param('tipe'));
$status = rts_api_param('status');
$district = strtoupper(rts_api_param('district'));
$page = max(1, (int) rts_api_param('page', '1'));
$limit = (int) rts_api_param('limit', '20');

if ($limit < 1) {
    $limit = 20;
}
if ($limit > 100) {
    $limit = 100;
}

$offset = ($page - 1) * $limit;

/* ------------------------------------------------------- filter dasar dulu */

$where = [];
$params = [];
$types = '';

if ($search !== '') {
    $where[] = '(UPPER(nama_toko) LIKE ? OR UPPER(id_customer) LIKE ? OR UPPER(salesman) LIKE ?)';
    $like = '%' . $search . '%';
    $params[] = $like;
    $params[] = $like;
    $params[] = $like;
    $types .= 'sss';
}

if (in_array($status, ['Aktif', 'Nonaktif'], true)) {
    $where[] = 'status_aktif = ?';
    $params[] = $status;
    $types .= 's';
}

if ($district !== '') {
    $where[] = 'UPPER(sales_district) = ?';
    $params[] = $district;
    $types .= 's';
}

// Hak akses data customer.
// - all      : ADMIN, ASS, WSS, SMST melihat semua district
// - district : RTS dan TF melihat customer pada Sales District miliknya
// - salesman : pengaman bila district akun belum diisi
// - none     : tidak menampilkan data sama sekali
if ($scope['mode'] === 'district') {
    $where[] = 'UPPER(TRIM(sales_district)) = ?';
    $params[] = $scope['district_upper'];
    $types .= 's';
} elseif ($scope['mode'] === 'salesman') {
    $where[] = 'salesman = ?';
    $params[] = $scope['salesman'];
    $types .= 's';
} elseif ($scope['mode'] === 'none') {
    $where[] = '1 = 0';
}

$baseWhere = $where;
$baseParams = $params;
$baseTypes = $types;

/* ---------------------------------------- jumlah per tipe (tanpa filter tipe) */

$counts = [
    'REGULER' => 0,
    'GSP' => 0,
    'total' => 0,
];

if ($hasTipe) {
    $countSql = 'SELECT tipe_customer, COUNT(*) AS total FROM master_toko'
        . ($baseWhere ? (' WHERE ' . implode(' AND ', $baseWhere)) : '')
        . ' GROUP BY tipe_customer';

    $countStmt = $conn->prepare($countSql);

    if ($countStmt) {
        if ($baseParams) {
            $countStmt->bind_param($baseTypes, ...$baseParams);
        }
        $countStmt->execute();
        $countResult = $countStmt->get_result();

        while ($countResult && ($countRow = $countResult->fetch_assoc())) {
            $key = strtoupper((string) $countRow['tipe_customer']);
            $jumlah = (int) $countRow['total'];

            if (!isset($counts[$key])) {
                $counts[$key] = 0;
            }
            $counts[$key] += $jumlah;
            $counts['total'] += $jumlah;
        }

        $countStmt->close();
    }
}

/* -------------------------------------------------------------- filter tipe */

if ($hasTipe && in_array($tipe, ['REGULER', 'GSP'], true)) {
    $where[] = 'tipe_customer = ?';
    $params[] = $tipe;
    $types .= 's';
}

$whereSql = $where ? (' WHERE ' . implode(' AND ', $where)) : '';

/* ------------------------------------------------------------------- total */

$total = 0;
$countStmt = $conn->prepare(
    'SELECT COUNT(*) AS total FROM master_toko' . $whereSql
);

if (!$countStmt) {
    error_log('RTS API customers count error: ' . $conn->error);
    rts_api_fail('Gagal membaca data customer.', 500);
}

if ($params) {
    $countStmt->bind_param($types, ...$params);
}
$countStmt->execute();
$countResult = $countStmt->get_result();
if ($countResult && ($countRow = $countResult->fetch_assoc())) {
    $total = (int) $countRow['total'];
}
$countStmt->close();

/* -------------------------------------------------------------------- data */

$sql = 'SELECT id, id_customer, nama_toko, ' . $tipeExpr . ', salesman, sales_district,
               alamat, kunjungan, hari, latitude, longitude, status_aktif
        FROM master_toko' . $whereSql . '
        ORDER BY nama_toko ASC
        LIMIT ? OFFSET ?';

$stmt = $conn->prepare($sql);

if (!$stmt) {
    error_log('RTS API customers prepare error: ' . $conn->error);
    rts_api_fail('Gagal membaca data customer.', 500);
}

$bindParams = $params;
$bindParams[] = $limit;
$bindParams[] = $offset;
$stmt->bind_param($types . 'ii', ...$bindParams);
$stmt->execute();
$result = $stmt->get_result();

$data = [];
while ($result && ($row = $result->fetch_assoc())) {
    $data[] = [
        'id' => (int) $row['id'],
        'id_customer' => (string) ($row['id_customer'] ?? ''),
        'nama_toko' => (string) ($row['nama_toko'] ?? ''),
        'tipe_customer' => strtoupper((string) ($row['tipe_customer'] ?? 'REGULER')),
        'salesman' => (string) ($row['salesman'] ?? ''),
        'sales_district' => (string) ($row['sales_district'] ?? ''),
        'alamat' => (string) ($row['alamat'] ?? ''),
        'kunjungan' => (string) ($row['kunjungan'] ?? ''),
        'hari' => (string) ($row['hari'] ?? ''),
        'latitude' => (string) ($row['latitude'] ?? ''),
        'longitude' => (string) ($row['longitude'] ?? ''),
        'status_aktif' => (string) ($row['status_aktif'] ?? 'Aktif'),
    ];
}
$stmt->close();

$totalPages = $limit > 0 ? (int) ceil($total / $limit) : 1;

rts_api_response(true, 'Data customer berhasil dibaca.', [
    'data' => $data,
    'tipe_available' => $hasTipe,
    'counts' => $counts,
    'meta' => [
        'page' => $page,
        'limit' => $limit,
        'total' => $total,
        'total_pages' => max(1, $totalPages),
        'has_more' => ($offset + count($data)) < $total,
        'tipe_available' => $hasTipe,
        'counts' => $counts,
    ],
    'scope' => $scope,
]);
