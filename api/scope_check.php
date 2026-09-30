<?php
/**
 * RTS Panel API - Diagnosa Cakupan Data
 * Endpoint : /api/scope_check.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Fungsi: menjelaskan mengapa aplikasi menampilkan sejumlah data tertentu.
 * Berguna bila angka pada dashboard atau Master Customer terasa salah.
 *
 * Balasan berisi:
 *   - data akun yang sedang login (role, salesman, sales_district)
 *   - mode cakupan yang sedang berlaku
 *   - hitungan: total seluruh customer, yang cocok district, yang cocok
 *     salesman, yang cocok keduanya, serta customer aktif dan GSP pada cakupan
 *   - daftar district yang benar-benar ada di master_toko
 *
 * Hanya membaca data. Tidak mengubah apa pun.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (!in_array($_SERVER['REQUEST_METHOD'] ?? 'GET', ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$scope = rts_api_scope($user);
$conn = rts_api_db();

/* ------------------------------------------------------------ fungsi hitung */

function rts_check_count(mysqli $conn, string $where = '', array $params = [], string $types = ''): int
{
    $sql = 'SELECT COUNT(*) AS total FROM master_toko' . ($where !== '' ? ' WHERE ' . $where : '');
    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return 0;
    }

    if ($params) {
        $stmt->bind_param($types, ...$params);
    }

    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    return $baris ? (int) $baris['total'] : 0;
}

/* ---------------------------------------------------------- hitungan utama */

$totalSemua = rts_check_count($conn);

$cocokDistrict = 0;
if ($scope['sales_district'] !== '') {
    $cocokDistrict = rts_check_count(
        $conn,
        'UPPER(TRIM(sales_district)) = ?',
        [strtoupper($scope['sales_district'])],
        's'
    );
}

$cocokSalesman = 0;
if ($scope['salesman'] !== '') {
    $cocokSalesman = rts_check_count($conn, 'salesman = ?', [$scope['salesman']], 's');
}

$cocokKeduanya = 0;
if ($scope['sales_district'] !== '' && $scope['salesman'] !== '') {
    $cocokKeduanya = rts_check_count(
        $conn,
        'UPPER(TRIM(sales_district)) = ? AND salesman = ?',
        [strtoupper($scope['sales_district']), $scope['salesman']],
        'ss'
    );
}

/* --------------------------------------------- hitungan sesuai mode cakupan */

$whereCakupan = '';
$paramsCakupan = [];
$typesCakupan = '';

if ($scope['mode'] === 'district') {
    $whereCakupan = 'UPPER(TRIM(sales_district)) = ?';
    $paramsCakupan = [strtoupper($scope['sales_district'])];
    $typesCakupan = 's';
} elseif ($scope['mode'] === 'salesman') {
    $whereCakupan = 'salesman = ?';
    $paramsCakupan = [$scope['salesman']];
    $typesCakupan = 's';
} elseif ($scope['mode'] === 'none') {
    $whereCakupan = '1 = 0';
}

$aktifCakupan = rts_check_count(
    $conn,
    $whereCakupan === '' ? "status_aktif = 'Aktif'" : $whereCakupan . " AND status_aktif = 'Aktif'",
    $paramsCakupan,
    $typesCakupan
);

$gspCakupan = rts_check_count(
    $conn,
    $whereCakupan === '' ? "tipe_customer = 'GSP'" : $whereCakupan . " AND tipe_customer = 'GSP'",
    $paramsCakupan,
    $typesCakupan
);

/* ------------------------------------------------------------ pengajuan */

$pengajuanSql = "SELECT COUNT(*) AS total FROM pengajuan_sales WHERE status_approval = 'Pending'";
$pengajuanPending = 0;

if ($scope['can_view_all']) {
    $hasilPengajuan = $conn->query($pengajuanSql);
    $pengajuanPending = $hasilPengajuan ? (int) $hasilPengajuan->fetch_assoc()['total'] : 0;
} else {
    $stmtPengajuan = $conn->prepare($pengajuanSql . ' AND sales_email = ?');
    if ($stmtPengajuan) {
        $email = $scope['email'];
        $stmtPengajuan->bind_param('s', $email);
        $stmtPengajuan->execute();
        $pengajuanPending = (int) $stmtPengajuan->get_result()->fetch_assoc()['total'];
        $stmtPengajuan->close();
    }
}

/* --------------------------------------------- daftar district di master_toko */

$daftarDistrict = [];
$hasilDistrict = $conn->query(
    'SELECT UPPER(TRIM(sales_district)) AS district, COUNT(*) AS jumlah
     FROM master_toko
     WHERE sales_district IS NOT NULL AND TRIM(sales_district) <> \'\'
     GROUP BY UPPER(TRIM(sales_district))
     ORDER BY jumlah DESC
     LIMIT 15'
);

if ($hasilDistrict) {
    while ($baris = $hasilDistrict->fetch_assoc()) {
        $daftarDistrict[] = [
            'district' => (string) $baris['district'],
            'jumlah' => (int) $baris['jumlah'],
        ];
    }
}

/* ----------------------------------------------------------- catatan bantuan */

$catatan = 'Cakupan data sudah sesuai akun.';

if ($scope['mode'] === 'district' && $cocokDistrict === 0) {
    $catatan = 'Nama district pada akun tidak ditemukan di master_toko. '
        . 'Bandingkan nilai sales_district akun dengan daftar district di bawah, '
        . 'lalu perbaiki salah satunya melalui halaman Kelola User.';
} elseif ($scope['mode'] === 'salesman') {
    $catatan = 'Sales District belum diisi pada akun, sehingga sementara data '
        . 'dibatasi memakai salesman.';
} elseif ($scope['mode'] === 'none') {
    $catatan = 'Akun belum memiliki Sales District maupun Salesman, sehingga tidak '
        . 'ada data yang dapat ditampilkan. Isi melalui halaman Kelola User.';
} elseif ($scope['mode'] === 'all') {
    $catatan = 'Role ini melihat seluruh customer pada semua district.';
}

rts_api_response(true, 'Diagnosa cakupan data berhasil dibaca.', [
    'akun' => [
        'username' => $user['username'],
        'nama_lengkap' => $user['nama_lengkap'],
        'role' => $user['role'],
        'salesman' => $scope['salesman'],
        'sales_district' => $scope['sales_district'],
    ],
    'scope' => [
        'mode' => $scope['mode'],
        'label' => $scope['label'],
        'all_area' => $scope['all_area'],
        'can_approve' => $scope['can_approve'],
    ],
    'hitungan' => [
        'total_semua_customer' => $totalSemua,
        'cocok_district' => $cocokDistrict,
        'cocok_salesman' => $cocokSalesman,
        'cocok_keduanya' => $cocokKeduanya,
        'aktif_pada_cakupan' => $aktifCakupan,
        'gsp_pada_cakupan' => $gspCakupan,
        'pengajuan_pending' => $pengajuanPending,
    ],
    'district_pada_master_toko' => $daftarDistrict,
    'catatan' => $catatan,
]);
