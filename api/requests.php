<?php
/**
 * RTS Panel API - Daftar Pengajuan
 * Endpoint : /api/requests.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Parameter (GET atau POST):
 *   type   : TOKO | GSP   (kosong = keduanya)
 *   status : Pending | Disetujui | Ditolak (kosong = semua)
 *   q      : cari nama toko / id customer / salesman
 *   from   : tanggal awal  (YYYY-MM-DD)
 *   to     : tanggal akhir (YYYY-MM-DD)
 *   page   : halaman (default 1)
 *   limit  : jumlah per halaman (default 20, maksimal 100)
 *
 * Hak akses:
 * - ADMIN, ASS, WSS, SMST : melihat semua pengajuan
 * - RTS, TF               : hanya pengajuan milik sendiri
 * - Hanya ADMIN dan ASS yang dipanggil "boleh_approve": true
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
if (!in_array($method, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$scope = rts_api_request_scope($user);
$conn = rts_api_db();

/* --------------------------------- struktur tabel yang mungkin belum ada */

$salesPunya = [
    'processed_by' => rts_api_has_column('pengajuan_sales', 'processed_by'),
    'processed_at' => rts_api_has_column('pengajuan_sales', 'processed_at'),
    'approval_note' => rts_api_has_column('pengajuan_sales', 'approval_note'),
];

$gspPunya = [
    'jenis_request' => rts_api_has_column('pengajuan_gsp', 'jenis_request'),
    'processed_by' => rts_api_has_column('pengajuan_gsp', 'processed_by'),
    'processed_at' => rts_api_has_column('pengajuan_gsp', 'processed_at'),
    'approval_note' => rts_api_has_column('pengajuan_gsp', 'approval_note'),
];

function rts_col(array $punya, string $nama, string $fallback = 'NULL'): string
{
    return $punya[$nama] ? $nama : $fallback;
}

/* ------------------------------------------------------------- parameter */

$type = strtoupper(rts_api_param('type'));
$status = rts_api_param('status');
$keyword = strtoupper(rts_api_param('q'));
$from = rts_api_param('from');
$to = rts_api_param('to');
$page = max(1, (int) rts_api_param('page', '1'));
$limit = (int) rts_api_param('limit', '20');

if ($limit < 1) {
    $limit = 20;
}
if ($limit > 100) {
    $limit = 100;
}

$offset = ($page - 1) * $limit;
$statusValid = in_array($status, ['Pending', 'Disetujui', 'Ditolak'], true);

/* ------------------------------------------------------- bangun klausa SQL */

function rts_build_where(
    array $scope,
    array $punya,
    string $tabel,
    string $kolomDistrict,
    bool $statusValid,
    string $status,
    string $keyword,
    string $from,
    string $to,
    string $jenisExpr
): array {
    $where = [];
    $params = [];
    $types = '';

    if (!$scope['can_view_all']) {
        $where[] = 'sales_email = ?';
        $params[] = $scope['email'];
        $types .= 's';
    }

    if ($statusValid) {
        $where[] = 'status_approval = ?';
        $params[] = $status;
        $types .= 's';
    }

    if ($keyword !== '') {
        $like = '%' . $keyword . '%';
        if ($tabel === 'pengajuan_sales') {
            $where[] = '(UPPER(COALESCE(nama_toko_baru,\'\')) LIKE ? OR UPPER(COALESCE(nama_toko_lama,\'\')) LIKE ? OR UPPER(COALESCE(id_customer,\'\')) LIKE ? OR UPPER(COALESCE(salesman,\'\')) LIKE ? OR UPPER(COALESCE(jenis_request,\'\')) LIKE ?)';
            for ($i = 0; $i < 5; $i++) {
                $params[] = $like;
                $types .= 's';
            }
        } else {
            $where[] = '(UPPER(COALESCE(toko_baru_nama,\'\')) LIKE ? OR UPPER(COALESCE(toko_lama_nama,\'\')) LIKE ? OR UPPER(COALESCE(toko_baru_id,\'\')) LIKE ? OR UPPER(COALESCE(toko_lama_id,\'\')) LIKE ? OR UPPER(COALESCE(salesman,\'\')) LIKE ?)';
            for ($i = 0; $i < 5; $i++) {
                $params[] = $like;
                $types .= 's';
            }
        }
    }

    if ($from !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $from)) {
        $where[] = 'DATE(tanggal_request) >= ?';
        $params[] = $from;
        $types .= 's';
    }

    if ($to !== '' && preg_match('/^\d{4}-\d{2}-\d{2}$/', $to)) {
        $where[] = 'DATE(tanggal_request) <= ?';
        $params[] = $to;
        $types .= 's';
    }

    return [$where, $params, $types];
}

[$whereToko, $paramsToko, $typesToko] = rts_build_where(
    $scope,
    $salesPunya,
    'pengajuan_sales',
    'sales_distric',
    $statusValid,
    $status,
    $keyword,
    $from,
    $to,
    'jenis_request'
);

[$whereGsp, $paramsGsp, $typesGsp] = rts_build_where(
    $scope,
    $gspPunya,
    'pengajuan_gsp',
    'sales_district',
    $statusValid,
    $status,
    $keyword,
    $from,
    $to,
    rts_col($gspPunya, 'jenis_request', "'PENAMBAHAN'")
);

$whereTokoSql = $whereToko ? (' WHERE ' . implode(' AND ', $whereToko)) : '';
$whereGspSql = $whereGsp ? (' WHERE ' . implode(' AND ', $whereGsp)) : '';

/* ------------------------------------------------------------ hitung total */

$totalToko = 0;
$totalGsp = 0;

$c1 = $conn->prepare('SELECT COUNT(*) AS total FROM pengajuan_sales' . $whereTokoSql);
if ($c1) {
    if ($paramsToko) {
        $c1->bind_param($typesToko, ...$paramsToko);
    }
    $c1->execute();
    $r1 = $c1->get_result();
    if ($r1 && ($row1 = $r1->fetch_assoc())) {
        $totalToko = (int) $row1['total'];
    }
    $c1->close();
}

$c2 = $conn->prepare('SELECT COUNT(*) AS total FROM pengajuan_gsp' . $whereGspSql);
if ($c2) {
    if ($paramsGsp) {
        $c2->bind_param($typesGsp, ...$paramsGsp);
    }
    $c2->execute();
    $r2 = $c2->get_result();
    if ($r2 && ($row2 = $r2->fetch_assoc())) {
        $totalGsp = (int) $row2['total'];
    }
    $c2->close();
}

$total = $totalToko + $totalGsp;

/* -------------------------------------------------------- jumlah per status */

$counts = ['Pending' => 0, 'Disetujui' => 0, 'Ditolak' => 0, 'total' => $total];

foreach (['pengajuan_sales' => [$whereToko, $paramsToko, $typesToko], 'pengajuan_gsp' => [$whereGsp, $paramsGsp, $typesGsp]] as $tabel => $info) {
    $stmt = $conn->prepare(
        'SELECT status_approval, COUNT(*) AS total FROM ' . $tabel
        . ($info[0] ? (' WHERE ' . implode(' AND ', $info[0])) : '')
        . ' GROUP BY status_approval'
    );

    if (!$stmt) {
        continue;
    }

    if ($info[1]) {
        $stmt->bind_param($info[2], ...$info[1]);
    }

    $stmt->execute();
    $res = $stmt->get_result();

    while ($res && ($row = $res->fetch_assoc())) {
        $key = (string) $row['status_approval'];
        if (!isset($counts[$key])) {
            $counts[$key] = 0;
        }
        $counts[$key] += (int) $row['total'];
    }

    $stmt->close();
}

/* -------------------------------------------------------------------- data */

$bagian = [];

if ($type === '' || $type === 'TOKO') {
    $sqlToko = "SELECT
            'TOKO' AS tipe,
            id,
            sales_email,
            tanggal_request,
            salesman,
            sales_distric AS district,
            jenis_request,
            COALESCE(NULLIF(nama_toko_baru, ''), nama_toko_lama) AS nama_toko,
            id_customer,
            COALESCE(NULLIF(alamat_baru, ''), alamat_lama) AS alamat,
            status_approval,
            " . rts_col($salesPunya, 'processed_by') . " AS processed_by,
            " . rts_col($salesPunya, 'processed_at') . " AS processed_at,
            " . rts_col($salesPunya, 'approval_note') . " AS approval_note,
            NULL AS pic,
            NULL AS nomor_hp,
            NULL AS koordinat,
            NULL AS toko_lama_nama,
            NULL AS toko_baru_nama,
            NULL AS toko_lama_id,
            NULL AS toko_baru_id
        FROM pengajuan_sales" . $whereTokoSql;

    $bagian[] = [$sqlToko, $paramsToko, $typesToko];
}

if ($type === '' || $type === 'GSP') {
    $sqlGsp = "SELECT
            'GSP' AS tipe,
            id,
            sales_email,
            tanggal_request,
            salesman,
            sales_district AS district,
            " . rts_col($gspPunya, 'jenis_request', "'PENAMBAHAN'") . " AS jenis_request,
            COALESCE(NULLIF(toko_baru_nama, ''), toko_lama_nama) AS nama_toko,
            COALESCE(NULLIF(toko_baru_id, ''), toko_lama_id) AS id_customer,
            alamat_lengkap AS alamat,
            status_approval,
            " . rts_col($gspPunya, 'processed_by') . " AS processed_by,
            " . rts_col($gspPunya, 'processed_at') . " AS processed_at,
            " . rts_col($gspPunya, 'approval_note') . " AS approval_note,
            pic_nama AS pic,
            nomor_hp,
            koordinat,
            toko_lama_nama,
            toko_baru_nama,
            toko_lama_id,
            toko_baru_id
        FROM pengajuan_gsp" . $whereGspSql;

    $bagian[] = [$sqlGsp, $paramsGsp, $typesGsp];
}

if (!$bagian) {
    rts_api_response(true, 'Data pengajuan berhasil dibaca.', [
        'data' => [],
        'counts' => $counts,
        'meta' => [
            'page' => $page,
            'limit' => $limit,
            'total' => 0,
            'total_pages' => 1,
            'has_more' => false,
            'counts' => $counts,
        ],
        'scope' => $scope,
    ]);
}

$union = implode(' UNION ALL ', array_map(static fn (array $b): string => $b[0], $bagian));

$sql = 'SELECT * FROM (' . $union . ') AS gabungan
        ORDER BY tanggal_request DESC, id DESC
        LIMIT ? OFFSET ?';

$params = [];
$types = '';
foreach ($bagian as $b) {
    foreach ($b[1] as $p) {
        $params[] = $p;
    }
    $types .= $b[2];
}
$params[] = $limit;
$params[] = $offset;
$types .= 'ii';

$stmt = $conn->prepare($sql);

if (!$stmt) {
    error_log('RTS API requests prepare error: ' . $conn->error);
    rts_api_fail('Gagal membaca data pengajuan.', 500);
}

$stmt->bind_param($types, ...$params);
$stmt->execute();
$hasil = $stmt->get_result();

$data = [];
$myEmail = $scope['email'];

while ($hasil && ($row = $hasil->fetch_assoc())) {
    $status2 = (string) ($row['status_approval'] ?? 'Pending');

    $data[] = [
        'id' => (int) $row['id'],
        'tipe' => (string) $row['tipe'],
        'tanggal_request' => (string) ($row['tanggal_request'] ?? ''),
        'salesman' => (string) ($row['salesman'] ?? ''),
        'district' => (string) ($row['district'] ?? ''),
        'jenis_request' => (string) ($row['jenis_request'] ?? ''),
        'nama_toko' => (string) ($row['nama_toko'] ?? ''),
        'id_customer' => (string) ($row['id_customer'] ?? ''),
        'alamat' => (string) ($row['alamat'] ?? ''),
        'status_approval' => $status2,
        'processed_by' => (string) ($row['processed_by'] ?? ''),
        'processed_at' => (string) ($row['processed_at'] ?? ''),
        'approval_note' => (string) ($row['approval_note'] ?? ''),
        'pic' => (string) ($row['pic'] ?? ''),
        'nomor_hp' => (string) ($row['nomor_hp'] ?? ''),
        'koordinat' => (string) ($row['koordinat'] ?? ''),
        'toko_lama_nama' => (string) ($row['toko_lama_nama'] ?? ''),
        'toko_baru_nama' => (string) ($row['toko_baru_nama'] ?? ''),
        'toko_lama_id' => (string) ($row['toko_lama_id'] ?? ''),
        'toko_baru_id' => (string) ($row['toko_baru_id'] ?? ''),
        'boleh_proses' => $scope['can_approve'] && $status2 === 'Pending',
        'boleh_hapus' => $scope['can_view_all']
            || ($status2 === 'Pending'
                && strcasecmp((string) ($row['sales_email'] ?? ''), $myEmail) === 0),
    ];
}
$stmt->close();

$totalPages = $limit > 0 ? (int) ceil($total / $limit) : 1;

rts_api_response(true, 'Data pengajuan berhasil dibaca.', [
    'data' => $data,
    'counts' => $counts,
    'meta' => [
        'page' => $page,
        'limit' => $limit,
        'total' => $total,
        'total_toko' => $totalToko,
        'total_gsp' => $totalGsp,
        'total_pages' => max(1, $totalPages),
        'has_more' => ($offset + count($data)) < $total,
        'counts' => $counts,
    ],
    'scope' => $scope,
]);
