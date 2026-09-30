<?php
/**
 * RTS Panel API - Proses Pengajuan (Setujui / Tolak / Hapus)
 * Endpoint : /api/request_action.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Body JSON:
 *   type   : TOKO | GSP
 *   id     : nomor pengajuan
 *   action : approve | reject | delete
 *   note   : catatan (boleh kosong, khusus approve / reject)
 *
 * Hak akses:
 * - approve / reject : hanya ADMIN dan ASS
 * - delete           : ADMIN, ASS, WSS, SMST (semua data)
 *                      RTS dan TF hanya pengajuan milik sendiri yang masih Pending
 *
 * Saat DISETUJUI, pengajuan langsung diterapkan ke Master Customer
 * dengan logika yang sama seperti website (inbox.php).
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/request_apply.php';

/**
 * Menyimpan pemberitahuan untuk satu penerima.
 *
 * Diabaikan dengan tenang bila tabel notifications belum tersedia pada
 * database, supaya tindakan utama (menyetujui, menolak, atau mengirim
 * pengajuan) tidak pernah gagal hanya karena pemberitahuan.
 */
function rts_notif_simpan(
    mysqli $conn,
    string $email,
    string $judul,
    string $pesan,
    string $tipe = 'INFO',
    string $refTipe = '',
    int $refId = 0
): void {
    $email = trim($email);

    if ($email === '') {
        return;
    }

    if (!rts_api_has_column('notifications', 'is_read')) {
        return;
    }

    $tipe = strtoupper(trim($tipe));

    if (!in_array($tipe, ['INFO', 'SUCCESS', 'WARNING', 'DANGER'], true)) {
        $tipe = 'INFO';
    }

    $stmt = $conn->prepare(
        'INSERT INTO notifications
         (recipient_email, title, message, type, reference_type, reference_id)
         VALUES (?, ?, ?, ?, ?, ?)'
    );

    if (!$stmt) {
        return;
    }

    $stmt->bind_param('sssssi', $email, $judul, $pesan, $tipe, $refTipe, $refId);

    if (!$stmt->execute()) {
        error_log('RTS API notifikasi error: ' . $stmt->error);
    }

    $idPemberitahuan = (int) $conn->insert_id;
    $stmt->close();

    /* TAMBAHAN FIREBASE: pemberitahuan dikirim juga ke layar HP, supaya tetap
       masuk walaupun aplikasi sedang ditutup sepenuhnya. Bila Firebase belum
       disiapkan di server, fungsi ini hanya diam dan tidak mengubah apa pun. */
    if (is_file(__DIR__ . '/fcm_kirim.php')) {
        require_once __DIR__ . '/fcm_kirim.php';

        rts_push_kirim($conn, $email, $judul, $pesan, [
            'kunci' => 'SISTEM|' . $idPemberitahuan,
            'id' => $idPemberitahuan,
            'tipe' => $tipe,
            'ref_tipe' => $refTipe,
            'ref_id' => $refId,
        ]);
    }
}


rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$scope = rts_api_request_scope($user);
$conn = rts_api_db();

$type = strtoupper(rts_api_param('type'));
$action = strtolower(rts_api_param('action'));
$id = (int) rts_api_param('id', '0');
$note = rts_api_param('note');

if (!in_array($type, ['TOKO', 'GSP'], true)) {
    rts_api_fail('Jenis pengajuan tidak dikenali.', 422);
}

if ($id <= 0) {
    rts_api_fail('Nomor pengajuan tidak valid.', 422);
}

if (!in_array($action, ['approve', 'reject', 'delete'], true)) {
    rts_api_fail('Aksi tidak dikenali.', 422);
}

$table = $type === 'GSP' ? 'pengajuan_gsp' : 'pengajuan_sales';

/* --------------------------------------------------------- baca pengajuan */

$stmt = $conn->prepare('SELECT * FROM ' . $table . ' WHERE id=? LIMIT 1');
if (!$stmt) {
    error_log('RTS API request_action prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$stmt->bind_param('i', $id);
$stmt->execute();
$result = $stmt->get_result();
$request = $result ? $result->fetch_assoc() : null;
$stmt->close();

if (!$request) {
    rts_api_fail('Pengajuan tidak ditemukan.', 404);
}

$statusSekarang = (string) ($request['status_approval'] ?? 'Pending');
$pemilik = (string) ($request['sales_email'] ?? '');
$milikSendiri = strcasecmp($pemilik, $scope['email']) === 0;

/* ------------------------------------------------------------- hak akses */

if ($action === 'delete') {
    if (!$scope['can_view_all'] && !($milikSendiri && $statusSekarang === 'Pending')) {
        rts_api_fail('Anda tidak berhak menghapus pengajuan ini.', 403);
    }

    $delete = $conn->prepare('DELETE FROM ' . $table . ' WHERE id=?');

    if (!$delete) {
        rts_api_fail('Gagal menghapus pengajuan.', 500);
    }

    $delete->bind_param('i', $id);
    $ok = $delete->execute();
    $delete->close();

    if (!$ok) {
        rts_api_fail('Pengajuan gagal dihapus.', 500);
    }

    rts_api_response(true, 'Pengajuan berhasil dihapus.', [
        'action' => 'delete',
        'id' => $id,
        'type' => $type,
        'status' => 'Dihapus',
    ]);
}

if (!$scope['can_approve']) {
    rts_api_fail('Hanya ADMIN dan ASS yang boleh menyetujui atau menolak pengajuan.', 403);
}

if ($statusSekarang !== 'Pending') {
    rts_api_fail('Pengajuan ini sudah diproses sebelumnya (status: ' . $statusSekarang . ').', 409);
}

$statusBaru = $action === 'approve' ? 'Disetujui' : 'Ditolak';
$catatanPenerapan = '';

if ($action === 'approve') {
    $hasil = $type === 'GSP'
        ? rts_api_apply_gsp_request($conn, $id)
        : rts_api_apply_customer_request($conn, $id, $user['nama_lengkap']);

    if (!$hasil['ok']) {
        rts_api_fail($hasil['message'], 409);
    }

    $catatanPenerapan = $hasil['message'];
}

/* --------------------------------------------------- simpan status + audit */

$actor = $user['nama_lengkap'] !== '' ? $user['nama_lengkap'] : $user['username'];
$punyaProcessedBy = rts_api_has_column($table, 'processed_by');
$punyaProcessedAt = rts_api_has_column($table, 'processed_at');
$punyaNote = rts_api_has_column($table, 'approval_note');

if ($punyaProcessedBy && $punyaProcessedAt && $punyaNote) {
    $sql = 'UPDATE ' . $table . '
            SET status_approval=?, processed_by=?, processed_at=NOW(), approval_note=?
            WHERE id=?';
    $update = $conn->prepare($sql);

    if ($update) {
        $update->bind_param('sssi', $statusBaru, $actor, $note, $id);
    }
} else {
    $sql = 'UPDATE ' . $table . ' SET status_approval=? WHERE id=?';
    $update = $conn->prepare($sql);

    if ($update) {
        $update->bind_param('si', $statusBaru, $id);
    }
}

if (!$update || !$update->execute()) {
    error_log('RTS API request_action update error: ' . $conn->error);
    rts_api_fail('Status pengajuan gagal disimpan.', 500);
}
$update->close();

/* ------------------------------------------------------------- riwayat aksi */

if (rts_api_has_column('riwayat_aksi', 'admin_name')) {
    $detail = 'Android: ' . $statusBaru . ' ID ' . $id . ' (' . $type . ')';
    $riwayat = $conn->prepare(
        'INSERT INTO riwayat_aksi (admin_name, action_type, request_detail) VALUES (?, ?, ?)'
    );

    if ($riwayat) {
        $riwayat->bind_param('sss', $actor, $statusBaru, $detail);
        $riwayat->execute();
        $riwayat->close();
    }
}

/* ------------------------------------------------------------ pemberitahuan */

$namaTokoPengajuan = (string) ($request['nama_toko_baru'] ?? '');

if ($namaTokoPengajuan === '') {
    $namaTokoPengajuan = (string) ($request['nama_toko_lama'] ?? '');
}

if ($namaTokoPengajuan === '') {
    $namaTokoPengajuan = (string) ($request['toko_baru_nama'] ?? '');
}

if ($namaTokoPengajuan === '') {
    $namaTokoPengajuan = (string) ($request['toko_lama_nama'] ?? '');
}

if ($namaTokoPengajuan === '') {
    $namaTokoPengajuan = 'ID ' . $id;
}

$jenisPengajuan = trim((string) ($request['jenis_request'] ?? ''));

if ($jenisPengajuan === '') {
    $jenisPengajuan = $type === 'GSP' ? 'Penambahan GSP' : 'Pengajuan';
}

$setuju = $action === 'approve';
$namaPemroses = $actor === '' ? 'ADMIN' : $actor;

$isiNotif = 'Pengajuan "' . $jenisPengajuan . '" untuk ' . $namaTokoPengajuan
    . ($setuju ? ' telah DISETUJUI' : ' telah DITOLAK')
    . ' oleh ' . $namaPemroses . '.';

if ($note !== '') {
    $isiNotif .= ' Catatan: ' . $note;
}

rts_notif_simpan(
    $conn,
    $pemilik,
    $setuju ? 'Pengajuan Disetujui' : 'Pengajuan Ditolak',
    $isiNotif,
    $setuju ? 'SUCCESS' : 'DANGER',
    'PENGAJUAN_' . $type,
    $id
);

/* ------------------------------------------------------------------ balasan */

$pesan = $action === 'approve'
    ? 'Pengajuan disetujui dan sudah diterapkan ke Master Customer.'
    : 'Pengajuan ditolak.';

if ($action === 'approve' && $catatanPenerapan !== '') {
    $pesan = 'Pengajuan disetujui. ' . $catatanPenerapan;
}

rts_api_response(true, $pesan, [
    'action' => $action,
    'id' => $id,
    'type' => $type,
    'status' => $statusBaru,
    'processed_by' => $actor,
    'catatan_penerapan' => $catatanPenerapan,
]);
