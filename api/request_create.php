<?php
/**
 * RTS Panel API - Kirim Pengajuan Baru dari Android
 * Endpoint : /api/request_create.php
 *
 * Header wajib:
 *   Authorization: Bearer <token>
 *
 * Body JSON:
 *   jenis            : Tambah Baru | Ganti Nama | Ganti Alamat | Hapus Toko
 *   id_customer      : ID customer (untuk Ganti Nama / Ganti Alamat / Hapus Toko)
 *   nama_toko_lama   : nama toko saat ini
 *   nama_toko_baru   : nama toko yang diajukan
 *   alamat_lama      : alamat saat ini
 *   alamat_baru      : alamat yang diajukan
 *   tipe_baru        : REGULER | GSP (khusus Tambah Baru)
 *   visit_day_baru   : hari kunjungan (khusus Tambah Baru)
 *   pic              : nama PIC di toko
 *   rute_kunjungan   : rute kunjungan
 *   week             : frekuensi kunjungan
 *                      Weekly | Bi-Weekly Ganjil | Bi-Weekly Genap
 *                      (Ganjil / Genap masih diterima untuk data lama)
 *   alasan           : alasan pengajuan
 *
 * sales_email, salesman, dan sales_distric diambil otomatis dari akun yang
 * login, sehingga sales tidak dapat mengirim atas nama orang lain.
 */

require_once __DIR__ . '/api_bootstrap.php';

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
$conn = rts_api_db();

$jenis = rts_api_param('jenis');
$idCustomer = rts_api_param('id_customer');
$namaLama = rts_api_param('nama_toko_lama');
$namaBaru = rts_api_param('nama_toko_baru');
$alamatLama = rts_api_param('alamat_lama');
$alamatBaru = rts_api_param('alamat_baru');
$tipeBaru = strtoupper(rts_api_param('tipe_baru', 'REGULER'));
$visitDay = rts_api_param('visit_day_baru');
$pic = rts_api_param('pic');
$rute = rts_api_param('rute_kunjungan');
$week = rts_api_param('week');
$alasan = rts_api_param('alasan');

$jenisValid = ['Tambah Baru', 'Ganti Nama', 'Ganti Alamat', 'Hapus Toko'];

if (!in_array($jenis, $jenisValid, true)) {
    rts_api_fail('Jenis pengajuan tidak dikenali.', 422);
}

/* ----------------------------------------------------------- validasi isian */

$wajib = [];

if ($jenis === 'Tambah Baru') {
    if ($namaBaru === '') {
        $wajib[] = 'nama toko baru';
    }
    if (!in_array($tipeBaru, ['REGULER', 'GSP'], true)) {
        $tipeBaru = 'REGULER';
    }
} else {
    if ($idCustomer === '') {
        $wajib[] = 'ID customer';
    }
    if ($jenis === 'Ganti Nama' && $namaBaru === '') {
        $wajib[] = 'nama toko baru';
    }
    if ($jenis === 'Ganti Alamat' && $alamatBaru === '') {
        $wajib[] = 'alamat baru';
    }
}

if ($alasan === '') {
    $wajib[] = 'alasan pengajuan';
}

if ($wajib) {
    rts_api_fail('Lengkapi dulu: ' . implode(', ', $wajib) . '.', 422);
}

/* ------------------------------- periksa bahwa customer berada pada cakupan */

$scope = rts_api_scope($user);

if ($jenis !== 'Tambah Baru' && $scope['mode'] !== 'all') {
    $cekSql = 'SELECT id_customer, nama_toko, alamat FROM master_toko WHERE id_customer = ?';
    $cekParams = [$idCustomer];
    $cekTypes = 's';

    if ($scope['mode'] === 'district') {
        $cekSql .= ' AND UPPER(TRIM(sales_district)) = ?';
        $cekParams[] = $scope['district_upper'];
        $cekTypes .= 's';
    } elseif ($scope['mode'] === 'salesman') {
        $cekSql .= ' AND salesman = ?';
        $cekParams[] = $scope['salesman'];
        $cekTypes .= 's';
    } else {
        $cekSql .= ' AND 1 = 0';
    }

    $cekSql .= ' LIMIT 1';

    $cek = $conn->prepare($cekSql);

    if ($cek) {
        $cek->bind_param($cekTypes, ...$cekParams);
        $cek->execute();
        $hasilCek = $cek->get_result();
        $dataCek = $hasilCek ? $hasilCek->fetch_assoc() : null;
        $cek->close();

        if (!$dataCek) {
            rts_api_fail('Customer tidak ditemukan atau bukan bagian tugas Anda.', 404);
        }

        // Lengkapi data lama dari database bila aplikasi belum mengirimkannya.
        if ($namaLama === '') {
            $namaLama = (string) ($dataCek['nama_toko'] ?? '');
        }
        if ($alamatLama === '') {
            $alamatLama = (string) ($dataCek['alamat'] ?? '');
        }
    }
}

/* ---------------------------------------------------------- data pengirim */

$salesEmail = $user['email'];
$salesman = $scope['salesman'];
$salesDistrict = $scope['sales_district'];

if ($salesEmail === '') {
    rts_api_fail('Email akun belum terisi. Hubungi Admin.', 422);
}

if ($salesman === '' && $salesDistrict === '') {
    rts_api_fail(
        'Akun Anda belum memiliki Salesman atau Sales District. Hubungi Admin.',
        422
    );
}

/* ------------------------------------------------------------------ simpan */

$insert = $conn->prepare(
    'INSERT INTO pengajuan_sales
     (sales_email, sales_distric, salesman, jenis_request, id_customer, pic,
      rute_kunjungan, week, nama_toko_lama, nama_toko_baru, alamat_lama,
      alamat_baru, tipe_baru, visit_day_baru, alasan)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
);

if (!$insert) {
    error_log('RTS API request_create prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$idCustomerSimpan = $jenis === 'Tambah Baru' ? '' : $idCustomer;

$insert->bind_param(
    'ssssissssssssss',
    $salesEmail,
    $salesDistrict,
    $salesman,
    $jenis,
    $idCustomerSimpan,
    $pic,
    $rute,
    $week,
    $namaLama,
    $namaBaru,
    $alamatLama,
    $alamatBaru,
    $tipeBaru,
    $visitDay,
    $alasan
);

if (!$insert->execute()) {
    error_log('RTS API request_create insert error: ' . $insert->error);
    $insert->close();
    rts_api_fail('Pengajuan gagal dikirim. Coba lagi.', 500);
}

$idBaru = (int) $conn->insert_id;
$insert->close();

/* ---------------------------------------------------------- pemberitahuan */

$namaTokoNotif = $namaBaru !== '' ? $namaBaru : $namaLama;

if ($namaTokoNotif === '') {
    $namaTokoNotif = $idCustomerSimpan !== ''
        ? ('ID ' . $idCustomerSimpan)
        : 'toko baru';
}

$isiNotifAdmin = $salesman . ' (' . $salesDistrict . ') mengirim pengajuan "'
    . $jenis . '" untuk ' . $namaTokoNotif
    . '. Silakan diperiksa pada menu Pengajuan.';

$penerimaNotif = $conn->query(
    "SELECT email FROM sales_users
     WHERE UPPER(TRIM(role)) IN ('ADMIN', 'ASS')
       AND email IS NOT NULL AND TRIM(email) <> ''"
);

if ($penerimaNotif) {
    while ($barisPenerima = $penerimaNotif->fetch_assoc()) {
        rts_notif_simpan(
            $conn,
            (string) $barisPenerima['email'],
            'Pengajuan Baru Masuk',
            $isiNotifAdmin,
            'WARNING',
            'PENGAJUAN_BARU',
            $idBaru
        );
    }
}

rts_api_response(true, 'Pengajuan "' . $jenis . '" berhasil dikirim dan menunggu pemeriksaan.', [
    'id' => $idBaru,
    'jenis' => $jenis,
    'status_approval' => 'Pending',
    'salesman' => $salesman,
    'district' => $salesDistrict,
]);
