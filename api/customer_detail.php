<?php
/**
 * RTS Panel API - Detail Customer
 * Endpoint : /api/customer_detail.php?id=3000032344
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Parameter:
 *   id : id_customer (kolom id_customer pada master_toko)
 *
 * Hak akses mengikuti peran:
 * - ADMIN, ASS, WSS, SMST : semua district
 * - RTS, TF               : hanya customer dengan salesman yang ditugaskan
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (!in_array(($_SERVER['REQUEST_METHOD'] ?? 'GET'), ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$scope = rts_api_scope($user);
$conn = rts_api_db();

$hasTipe = rts_api_has_column('master_toko', 'tipe_customer');
$tipeExpr = $hasTipe ? 'tipe_customer' : "'REGULER' AS tipe_customer";

$idCustomer = rts_api_param('id');

if ($idCustomer === '') {
    rts_api_fail('Parameter id customer wajib dikirim.', 422);
}

$sql = 'SELECT id, id_customer, nama_toko, ' . $tipeExpr . ', salesman, sales_district,
               alamat, kunjungan, hari, latitude, longitude, status_aktif
        FROM master_toko
        WHERE id_customer = ?';

$params = [$idCustomer];
$types = 's';

if ($scope['mode'] === 'district') {
    $sql .= ' AND UPPER(TRIM(sales_district)) = ?';
    $params[] = $scope['district_upper'];
    $types .= 's';
} elseif ($scope['mode'] === 'salesman') {
    $sql .= ' AND salesman = ?';
    $params[] = $scope['salesman'];
    $types .= 's';
} elseif ($scope['mode'] === 'none') {
    $sql .= ' AND 1 = 0';
}

$sql .= ' LIMIT 1';

$stmt = $conn->prepare($sql);

if (!$stmt) {
    error_log('RTS API customer detail prepare error: ' . $conn->error);
    rts_api_fail('Gagal membaca detail customer.', 500);
}

$stmt->bind_param($types, ...$params);
$stmt->execute();
$result = $stmt->get_result();
$row = $result ? $result->fetch_assoc() : null;
$stmt->close();

if (!$row) {
    rts_api_fail('Customer tidak ditemukan atau bukan bagian tugas Anda.', 404);
}

$mapUrl = '';
if (trim((string) $row['latitude']) !== '' && trim((string) $row['longitude']) !== '') {
    $mapUrl = 'https://www.openstreetmap.org/?mlat=' . rawurlencode((string) $row['latitude'])
        . '&mlon=' . rawurlencode((string) $row['longitude'])
        . '#map=18/' . rawurlencode((string) $row['latitude'])
        . '/' . rawurlencode((string) $row['longitude']);
}

rts_api_response(true, 'Detail customer berhasil dibaca.', [
    'data' => [
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
        'map_url' => $mapUrl,
    ],
    'scope' => $scope,
]);
