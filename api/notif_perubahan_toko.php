<?php
/**
 * RTS Panel API - Daftar perubahan data toko yang perlu dikonfirmasi Sales
 * Endpoint : /api/notif_perubahan_toko.php   (GET, wajib Bearer token)
 *
 * Yang ditampilkan: pengajuan Sales berstatus Pending (Ganti Nama / Ganti Alamat)
 * milik toko dengan salesman yang sama, dan data lama pada pengajuan (nama/alamat)
 * sudah berbeda dengan data master_toko sekarang (misalnya admin sudah mengubah
 * data tetapi status pengajuan belum diperbarui).
 *
 * Balasan: { success, data: [ {id, id_customer, jenis, nama_lama, alamat_lama,
 *            nama_master, alamat_master, nama_baru, alamat_baru, tanggal} ] }
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
    rts_api_fail('Method tidak diizinkan. Gunakan GET.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$salesman = trim((string) ($user['salesman'] ?? ''));

if ($salesman === '') {
    rts_api_response(true, 'Tidak ada perubahan.', ['data' => []]);
}

if (!rts_api_ada_kolom($conn, 'pengajuan_sales', 'status_approval')) {
    rts_api_response(true, 'Tidak ada perubahan.', ['data' => []]);
}

$stmt = $conn->prepare(
    "SELECT p.id, p.id_customer, p.jenis_request, p.nama_toko_lama, p.alamat_lama,
            p.nama_toko_baru, p.alamat_baru, p.tanggal_request,
            m.nama_toko AS nama_master, m.alamat AS alamat_master
     FROM pengajuan_sales p
     INNER JOIN master_toko m ON m.id_customer = p.id_customer
     WHERE p.status_approval = 'Pending'
       AND m.salesman = ?
       AND LOWER(TRIM(p.jenis_request)) IN ('ganti nama', 'ganti alamat')
     ORDER BY p.tanggal_request ASC
     LIMIT 50"
);

if (!$stmt) {
    error_log('RTS API notif_perubahan_toko prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$stmt->bind_param('s', $salesman);
$stmt->execute();
$hasil = $stmt->get_result();

/** Pembanding: huruf besar, spasi dirapikan. */
$norm = static function (?string $teks): string {
    return mb_strtoupper(preg_replace('/\s+/', ' ', trim((string) $teks)));
};

$data = [];

while ($baris = $hasil->fetch_assoc()) {
    $namaBeda = trim((string) $baris['nama_toko_lama']) !== ''
        && $norm($baris['nama_toko_lama']) !== $norm($baris['nama_master']);

    $alamatBeda = trim((string) $baris['alamat_lama']) !== ''
        && $norm($baris['alamat_lama']) !== $norm($baris['alamat_master']);

    if (!$namaBeda && !$alamatBeda) {
        continue;
    }

    $data[] = [
        'id' => (int) $baris['id'],
        'id_customer' => (string) $baris['id_customer'],
        'jenis' => (string) $baris['jenis_request'],
        'nama_lama' => (string) ($baris['nama_toko_lama'] ?? ''),
        'alamat_lama' => (string) ($baris['alamat_lama'] ?? ''),
        'nama_master' => (string) ($baris['nama_master'] ?? ''),
        'alamat_master' => (string) ($baris['alamat_master'] ?? ''),
        'nama_baru' => (string) ($baris['nama_toko_baru'] ?? ''),
        'alamat_baru' => (string) ($baris['alamat_baru'] ?? ''),
        'tanggal' => (string) ($baris['tanggal_request'] ?? ''),
    ];
}

$stmt->close();

rts_api_response(true, count($data) . ' perubahan perlu dikonfirmasi.', ['data' => $data]);
