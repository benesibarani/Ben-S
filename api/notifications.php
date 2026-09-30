<?php
/**
 * RTS Panel API - Pemberitahuan
 * Endpoint : /api/notifications.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * GET  -> daftar pemberitahuan + ringkasan pengajuan
 * POST -> menandai pemberitahuan sudah dibaca
 *         body: { "action": "read", "id": 12 }
 *         body: { "action": "read_all" }
 *
 * Balasan memuat tiga bagian:
 *
 *  1. perlu_diperiksa : pengajuan Pending pada cakupan akun.
 *                       Untuk ADMIN, ASS, WSS, dan SMST berisi seluruh
 *                       pengajuan. Untuk RTS dan TF berisi pengajuan sendiri.
 *
 *  2. pengajuan_saya  : pengajuan milik akun yang login beserta hasilnya
 *                       (Disetujui / Ditolak / masih Pending), supaya sales
 *                       mengetahui tindak lanjut pengajuannya dari HP.
 *
 *  3. data            : isi tabel notifications bila tabelnya tersedia.
 *                       Bila belum ada, bagian ini berisi daftar kosong dan
 *                       kolom "tersedia" bernilai false. Bagian 1 dan 2 tetap
 *                       berfungsi, sehingga fitur ini dapat dipakai lebih
 *                       dahulu tanpa perubahan database.
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = $_SERVER['REQUEST_METHOD'] ?? 'GET';

if ($metode !== 'GET' && $metode !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan GET atau POST.', 405);
}

/** @var mysqli $conn */
$conn = rts_api_db();
$user = rts_api_require_user();
$scope = rts_api_scope($user);

$emailSaya = (string) ($user['email'] ?? '');
$idSaya = (int) ($user['id'] ?? 0);
$idUserSaya = $idSaya > 0 ? $idSaya : 0;
$semuaArea = (bool) ($scope['all_area'] ?? false);
$bolehProses = (bool) ($scope['can_approve'] ?? false);

/* ------------------------------------------------------- ketersediaan tabel */

$tabelNotifAda = rts_api_has_column('notifications', 'is_read');

/* Mengolah potongan query menjadi ekspresi kolom yang aman. */
$kolomTokoBaru = rts_api_has_column('pengajuan_sales', 'nama_toko_baru');
$kolomProses = rts_api_has_column('pengajuan_sales', 'processed_at');
$kolomCatatan = rts_api_has_column('pengajuan_sales', 'approval_note');

$exprNamaToko = $kolomTokoBaru
    ? "COALESCE(NULLIF(nama_toko_baru, ''), nama_toko_lama)"
    : 'nama_toko_lama';

$exprWaktuProses = $kolomProses ? "COALESCE(processed_at, tanggal_request)" : 'tanggal_request';
$exprCatatan = $kolomCatatan ? "COALESCE(approval_note, '')" : "''";

$exprNamaGsp = "COALESCE(NULLIF(toko_baru_nama, ''), toko_lama_nama)";

/* =========================================================== tandai dibaca */

if ($metode === 'POST') {
    if (!$tabelNotifAda) {
        rts_api_response(true, 'Belum ada pemberitahuan yang perlu ditandai.', [
            'tersedia' => false,
            'diubah' => 0,
        ]);
    }

    $aksi = rts_api_param('action', 'read');

    if ($aksi === 'read_all') {
        $stmt = $conn->prepare(
            'UPDATE notifications SET is_read = 1
             WHERE is_read = 0 AND (recipient_email = ? OR user_id = ?)'
        );

        if (!$stmt) {
            rts_api_fail('Server sedang mengalami gangguan.', 500);
        }

        $stmt->bind_param('si', $emailSaya, $idUserSaya);
        $stmt->execute();
        $diubah = $stmt->affected_rows;
        $stmt->close();

        rts_api_response(true, 'Seluruh pemberitahuan ditandai sudah dibaca.', [
            'tersedia' => true,
            'diubah' => (int) $diubah,
        ]);
    }

    $idNotif = (int) rts_api_param('id', '0');

    if ($idNotif <= 0) {
        rts_api_fail('ID pemberitahuan tidak dikenali.', 422);
    }

    $stmt = $conn->prepare(
        'UPDATE notifications SET is_read = 1
         WHERE id = ? AND (recipient_email = ? OR user_id = ?)'
    );

    if (!$stmt) {
        rts_api_fail('Server sedang mengalami gangguan.', 500);
    }

    $stmt->bind_param('isi', $idNotif, $emailSaya, $idUserSaya);
    $stmt->execute();
    $diubah = $stmt->affected_rows;
    $stmt->close();

    rts_api_response(true, 'Pemberitahuan ditandai sudah dibaca.', [
        'tersedia' => true,
        'diubah' => (int) $diubah,
    ]);
}

/* ================================================================ baca data */

$batas = (int) rts_api_param('limit', '20');

if ($batas < 1 || $batas > 50) {
    $batas = 20;
}

/* -------------------------------------------- 1. pengajuan perlu diperiksa */

$perluData = [];
$perluJumlah = 0;

$syaratPerluToko = $semuaArea ? '' : ' AND sales_email = ?';
$syaratPerluGsp = $semuaArea ? '' : ' AND sales_email = ?';

$sqlPerlu = "SELECT 'TOKO' AS tipe, id, salesman, sales_distric AS district,
                    jenis_request, $exprNamaToko AS nama_toko, status_approval,
                    tanggal_request, '' AS catatan
             FROM pengajuan_sales
             WHERE status_approval = 'Pending'$syaratPerluToko
             UNION ALL
             SELECT 'GSP' AS tipe, id, salesman, sales_district AS district,
                    'Penambahan GSP' AS jenis_request, $exprNamaGsp AS nama_toko,
                    status_approval, tanggal_request, '' AS catatan
             FROM pengajuan_gsp
             WHERE status_approval = 'Pending'$syaratPerluGsp
             ORDER BY tanggal_request DESC
             LIMIT " . (int) $batas;

$stmtPerlu = $conn->prepare($sqlPerlu);

if ($stmtPerlu) {
    if (!$semuaArea) {
        $stmtPerlu->bind_param('ss', $emailSaya, $emailSaya);
    }

    $stmtPerlu->execute();
    $hasilPerlu = $stmtPerlu->get_result();

    while ($hasilPerlu && ($row = $hasilPerlu->fetch_assoc())) {
        $perluData[] = [
            'tipe' => (string) $row['tipe'],
            'id' => (int) $row['id'],
            'jenis_request' => (string) ($row['jenis_request'] ?? ''),
            'nama_toko' => (string) ($row['nama_toko'] ?? ''),
            'salesman' => (string) ($row['salesman'] ?? ''),
            'district' => (string) ($row['district'] ?? ''),
            'status_approval' => (string) ($row['status_approval'] ?? ''),
            'tanggal_request' => (string) ($row['tanggal_request'] ?? ''),
        ];
    }

    $stmtPerlu->close();
}

/* Hitungan menyeluruh, tidak terbatas pada halaman yang ditampilkan. */
$sqlHitungPerlu = "SELECT
        (SELECT COUNT(*) FROM pengajuan_sales WHERE status_approval = 'Pending'$syaratPerluToko) +
        (SELECT COUNT(*) FROM pengajuan_gsp WHERE status_approval = 'Pending'$syaratPerluGsp)
        AS total";

$stmtHitung = $conn->prepare($sqlHitungPerlu);

if ($stmtHitung) {
    if (!$semuaArea) {
        $stmtHitung->bind_param('ss', $emailSaya, $emailSaya);
    }

    $stmtHitung->execute();
    $hasilHitung = $stmtHitung->get_result();
    $barisHitung = $hasilHitung ? $hasilHitung->fetch_assoc() : null;
    $perluJumlah = $barisHitung ? (int) $barisHitung['total'] : 0;
    $stmtHitung->close();
}

/* --------------------------------------------------- 2. pengajuan milik saya */

$sayaData = [];
$sayaJumlah = 0;
$sayaPending = 0;
$sayaDisetujui = 0;
$sayaDitolak = 0;

if ($emailSaya !== '') {
    $sqlSaya = "SELECT 'TOKO' AS tipe, id, jenis_request, $exprNamaToko AS nama_toko,
                       status_approval, tanggal_request,
                       $exprWaktuProses AS waktu_proses, $exprCatatan AS catatan
                FROM pengajuan_sales
                WHERE sales_email = ?
                UNION ALL
                SELECT 'GSP' AS tipe, id, 'Penambahan GSP' AS jenis_request,
                       $exprNamaGsp AS nama_toko, status_approval, tanggal_request,
                       tanggal_request AS waktu_proses, '' AS catatan
                FROM pengajuan_gsp
                WHERE sales_email = ?
                ORDER BY waktu_proses DESC
                LIMIT " . (int) $batas;

    $stmtSaya = $conn->prepare($sqlSaya);

    if ($stmtSaya) {
        $stmtSaya->bind_param('ss', $emailSaya, $emailSaya);
        $stmtSaya->execute();
        $hasilSaya = $stmtSaya->get_result();

        while ($hasilSaya && ($row = $hasilSaya->fetch_assoc())) {
            $status = (string) ($row['status_approval'] ?? 'Pending');

            $sayaData[] = [
                'tipe' => (string) $row['tipe'],
                'id' => (int) $row['id'],
                'jenis_request' => (string) ($row['jenis_request'] ?? ''),
                'nama_toko' => (string) ($row['nama_toko'] ?? ''),
                'status_approval' => $status,
                'tanggal_request' => (string) ($row['tanggal_request'] ?? ''),
                'waktu_proses' => (string) ($row['waktu_proses'] ?? ''),
                'catatan' => (string) ($row['catatan'] ?? ''),
            ];
        }

        $stmtSaya->close();
    }

    $sqlHitungSaya = "SELECT status_approval, COUNT(*) AS total
                      FROM (
                          SELECT status_approval FROM pengajuan_sales WHERE sales_email = ?
                          UNION ALL
                          SELECT status_approval FROM pengajuan_gsp WHERE sales_email = ?
                      ) AS gabungan
                      GROUP BY status_approval";

    $stmtHitungSaya = $conn->prepare($sqlHitungSaya);

    if ($stmtHitungSaya) {
        $stmtHitungSaya->bind_param('ss', $emailSaya, $emailSaya);
        $stmtHitungSaya->execute();
        $hasilHitungSaya = $stmtHitungSaya->get_result();

        while ($hasilHitungSaya && ($row = $hasilHitungSaya->fetch_assoc())) {
            $status = strtolower((string) $row['status_approval']);
            $jumlah = (int) $row['total'];
            $sayaJumlah += $jumlah;

            if ($status === 'pending') {
                $sayaPending += $jumlah;
            } elseif ($status === 'disetujui') {
                $sayaDisetujui += $jumlah;
            } elseif ($status === 'ditolak') {
                $sayaDitolak += $jumlah;
            }
        }

        $stmtHitungSaya->close();
    }
}

/* --------------------------------------- 3. isi tabel notifications (bila ada) */

$dataNotif = [];
$belumDibaca = 0;

if ($tabelNotifAda) {
    $sqlNotif = 'SELECT id, title, message, type, is_read, created_at,
                        reference_type, reference_id
                 FROM notifications
                 WHERE recipient_email = ? OR user_id = ?
                 ORDER BY is_read ASC, created_at DESC
                 LIMIT ' . (int) $batas;

    $stmtNotif = $conn->prepare($sqlNotif);

    if ($stmtNotif) {
        $stmtNotif->bind_param('si', $emailSaya, $idUserSaya);
        $stmtNotif->execute();
        $hasilNotif = $stmtNotif->get_result();

        while ($hasilNotif && ($row = $hasilNotif->fetch_assoc())) {
            $dataNotif[] = [
                'id' => (int) $row['id'],
                'title' => (string) ($row['title'] ?? ''),
                'message' => (string) ($row['message'] ?? ''),
                'type' => strtoupper((string) ($row['type'] ?? 'INFO')),
                'is_read' => (int) ($row['is_read'] ?? 0) === 1,
                'created_at' => (string) ($row['created_at'] ?? ''),
                'reference_type' => (string) ($row['reference_type'] ?? ''),
                'reference_id' => (int) ($row['reference_id'] ?? 0),
            ];
        }

        $stmtNotif->close();
    }

    $stmtJumlah = $conn->prepare(
        'SELECT COUNT(*) AS total FROM notifications
         WHERE is_read = 0 AND (recipient_email = ? OR user_id = ?)'
    );

    if ($stmtJumlah) {
        $stmtJumlah->bind_param('si', $emailSaya, $idUserSaya);
        $stmtJumlah->execute();
        $hasilJumlah = $stmtJumlah->get_result();
        $barisJumlah = $hasilJumlah ? $hasilJumlah->fetch_assoc() : null;
        $belumDibaca = $barisJumlah ? (int) $barisJumlah['total'] : 0;
        $stmtJumlah->close();
    }
}

/* ------------------------------------------------------------- angka lonceng */

$angkaLonceng = ($bolehProses || $semuaArea) ? $perluJumlah : $sayaPending;

if ($belumDibaca > 0) {
    $angkaLonceng += $belumDibaca;
}

/* ------------------------------------------------------------------ balasan */

rts_api_response(true, 'Pemberitahuan berhasil dibaca.', [
    'tersedia' => $tabelNotifAda,
    'belum_dibaca' => $belumDibaca,
    'angka_lonceng' => $angkaLonceng,
    'cakupan' => [
        'mode' => (string) ($scope['mode'] ?? ''),
        'label' => (string) ($scope['label'] ?? ''),
        'all_area' => $semuaArea,
        'can_approve' => $bolehProses,
    ],
    'perlu_diperiksa' => [
        'jumlah' => $perluJumlah,
        'data' => $perluData,
    ],
    'pengajuan_saya' => [
        'jumlah' => $sayaJumlah,
        'pending' => $sayaPending,
        'disetujui' => $sayaDisetujui,
        'ditolak' => $sayaDitolak,
        'data' => $sayaData,
    ],
    'data' => $dataNotif,
]);
