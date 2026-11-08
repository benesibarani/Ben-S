<?php
/**
 * RTS Panel API - Sales menjawab perubahan data toko: Setujui atau Tolak
 * Endpoint : /api/notif_perubahan_respon.php   (POST, wajib Bearer token)
 *
 * Body JSON:
 *   id    : ID pengajuan (dari notif_perubahan_toko.php)
 *   aksi  : "setujui" atau "tolak"
 *
 * Hanya mengubah STATUS pengajuan (Disetujui / Ditolak). master_toko TIDAK diubah.
 * Hanya pengajuan milik salesman yang sama dan masih Pending yang bisa dijawab.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$id = (int) rts_api_param('id', '0');
$aksi = strtolower(rts_api_param('aksi'));

if ($id <= 0 || !in_array($aksi, ['setujui', 'tolak'], true)) {
    rts_api_fail('Data jawaban tidak lengkap.', 422);
}

$salesman = trim((string) ($user['salesman'] ?? ''));

$cek = $conn->prepare(
    "SELECT p.status_approval, p.jenis_request, m.salesman
     FROM pengajuan_sales p
     INNER JOIN master_toko m ON m.id_customer = p.id_customer
     WHERE p.id = ?
     LIMIT 1"
);

if (!$cek) {
    error_log('RTS API notif_perubahan_respon prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$cek->bind_param('i', $id);
$cek->execute();
$hasil = $cek->get_result();
$pengajuan = $hasil ? $hasil->fetch_assoc() : null;
$cek->close();

if (!$pengajuan) {
    rts_api_fail('Pengajuan tidak ditemukan.', 404);
}

if ($salesman === '' || trim((string) $pengajuan['salesman']) !== $salesman) {
    rts_api_fail('Anda tidak berhak menjawab pengajuan ini.', 403);
}

if (($pengajuan['status_approval'] ?? '') !== 'Pending') {
    rts_api_fail('Pengajuan ini sudah diproses sebelumnya.', 409);
}

if (!in_array(strtolower(trim((string) $pengajuan['jenis_request'])), ['ganti nama', 'ganti alamat'], true)) {
    rts_api_fail('Jenis pengajuan ini tidak memakai konfirmasi perubahan data.', 422);
}

$statusBaru = $aksi === 'setujui' ? 'Disetujui' : 'Ditolak';
$actor = trim((string) ($user['nama_lengkap'] ?? '')) !== ''
    ? (string) $user['nama_lengkap']
    : (string) ($user['username'] ?? 'SALES');
$catatan = 'Dijawab Sales: data master toko sudah berubah.';

$punyaProcessedBy = rts_api_ada_kolom($conn, 'pengajuan_sales', 'processed_by');
$punyaProcessedAt = rts_api_ada_kolom($conn, 'pengajuan_sales', 'processed_at');
$punyaNote = rts_api_ada_kolom($conn, 'pengajuan_sales', 'approval_note');

$sql = 'UPDATE pengajuan_sales SET status_approval = ?';
$tipe = 's';
$nilai = [$statusBaru];

if ($punyaProcessedBy) {
    $sql .= ', processed_by = ?';
    $tipe .= 's';
    $nilai[] = $actor;
}

if ($punyaProcessedAt) {
    $sql .= ', processed_at = NOW()';
}

if ($punyaNote) {
    $sql .= ', approval_note = ?';
    $tipe .= 's';
    $nilai[] = $catatan;
}

$sql .= " WHERE id = ? AND status_approval = 'Pending'";
$tipe .= 'i';
$nilai[] = $id;

$update = $conn->prepare($sql);

if (!$update) {
    error_log('RTS API notif_perubahan_respon update error: ' . $conn->error);
    rts_api_fail('Status pengajuan gagal disimpan.', 500);
}

$update->bind_param($tipe, ...$nilai);

if (!$update->execute()) {
    error_log('RTS API notif_perubahan_respon execute error: ' . $update->error);
    $update->close();
    rts_api_fail('Status pengajuan gagal disimpan.', 500);
}

$terubah = $update->affected_rows;
$update->close();

if ($terubah < 1) {
    rts_api_fail('Pengajuan ini sudah diproses sebelumnya.', 409);
}

rts_api_response(true, $statusBaru === 'Disetujui'
    ? 'Perubahan dikonfirmasi. Status pengajuan: Disetujui.'
    : 'Perubahan ditolak. Status pengajuan: Ditolak.', ['status' => $statusBaru]);
