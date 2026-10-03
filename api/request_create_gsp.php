<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - PENGAJUAN GSP DARI APLIKASI ANDROID
 *  Berkas : api/request_create_gsp.php
 *
 *  KEGUNAAN
 *  --------
 *  Mengirim pengajuan GSP (Galan Strategist Partner) dari menu Utama > GSP.
 *  Ada dua jenis pengajuan:
 *    PENAMBAHAN   -> toko dipilih dari Master Customer lalu diusulkan menjadi GSP.
 *                    Wajib melampirkan 3 foto: KTP, luar toko, dalam toko.
 *    PENGHAPUSAN  -> GSP yang sedang aktif diusulkan dikembalikan menjadi REGULER
 *                    (sama seperti menu Hapus Toko pada Pengajuan Baru).
 *
 *  Cara pengiriman (form-data / multipart):
 *    Header : Authorization: Bearer <token>
 *    Isian  : jenis        = PENAMBAHAN | PENGHAPUSAN
 *             id_customer  = ID customer pada Master Customer (wajib)
 *             nama_toko    = nama toko (boleh dikosongkan, diambil dari server)
 *             alamat       = alamat lengkap (boleh dikosongkan, diambil dari server)
 *             pic          = nama PIC (wajib untuk PENAMBAHAN)
 *             nomor_hp     = nomor HP PIC (wajib untuk PENAMBAHAN)
 *             koordinat    = "lat,lng" (wajib untuk PENAMBAHAN)
 *             alasan       = alasan pengajuan (boleh dikosongkan)
 *             foto_ktp, foto_luar, foto_dalam  = berkas gambar (wajib PENAMBAHAN)
 *
 *  HASIL
 *    { success: true, message: "...", data: { id, jenis, status_approval } }
 *
 *  CATATAN DATABASE
 *    Data disimpan pada tabel pengajuan_gsp. Kolom foto (link_foto_ktp,
 *    link_foto_luar, link_foto_dalam) memang hanya ada pada tabel ini,
 *    bukan pada pengajuan_sales. Berkas gambar disimpan pada folder
 *    uploads/gsp/ di hosting.
 *
 *    Bila kolom jenis_request belum ada (migrasi belum dijalankan), pengajuan
 *    tetap disimpan sebagai PENAMBAHAN seperti perilaku website. Buka halaman
 *    Langganan / Akun PRO pada website lalu tekan "Perbarui Database".
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';

/**
 * Menyimpan pemberitahuan untuk satu penerima.
 *
 * Diabaikan dengan tenang bila tabel notifications belum tersedia, supaya
 * pengajuan tetap dapat terkirim walaupun pemberitahuan gagal.
 */
if (!function_exists('rts_notif_simpan')) {
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
            error_log('RTS API notifikasi GSP error: ' . $stmt->error);
        }

        $idPemberitahuan = (int) $conn->insert_id;
        $stmt->close();

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
}

/**
 * Folder penyimpanan foto GSP.
 */
function rts_gsp_folder(): string
{
    return dirname(__DIR__) . '/uploads/gsp';
}

/**
 * Menyimpan satu berkas foto GSP.
 *
 * @return array{ok: bool, pesan: string, relatif: string}
 */
function rts_gsp_simpan_foto(string $namaIsian, string $awalan, string $jenis): array
{
    if (!isset($_FILES[$namaIsian])) {
        return ['ok' => false, 'pesan' => 'Berkas ' . $awalan . ' belum dikirim.', 'relatif' => ''];
    }

    $berkas = $_FILES[$namaIsian];

    if (!is_array($berkas) || !isset($berkas['tmp_name'])) {
        return ['ok' => false, 'pesan' => 'Berkas ' . $awalan . ' tidak dikenali.', 'relatif' => ''];
    }

    $kodeGalat = (int) ($berkas['error'] ?? 1);

    if ($kodeGalat !== 0) {
        $pesan = 'Berkas ' . $awalan . ' gagal diunggah.';

        switch ($kodeGalat) {
            case UPLOAD_ERR_INI_SIZE:
            case UPLOAD_ERR_FORM_SIZE:
                $pesan = 'Ukuran foto ' . $awalan . ' terlalu besar. Gunakan foto di bawah 3 MB.';
                break;
            case UPLOAD_ERR_NO_FILE:
                $pesan = 'Belum ada berkas foto ' . $awalan . ' yang dipilih.';
                break;
        }

        return ['ok' => false, 'pesan' => $pesan, 'relatif' => ''];
    }

    $ukuran = (int) ($berkas['size'] ?? 0);

    if ($ukuran <= 0) {
        return ['ok' => false, 'pesan' => 'Berkas foto ' . $awalan . ' kosong.', 'relatif' => ''];
    }

    if ($ukuran > 3 * 1024 * 1024) {
        return [
            'ok' => false,
            'pesan' => 'Ukuran foto ' . $awalan . ' terlalu besar (maksimal 3 MB).',
            'relatif' => '',
        ];
    }

    $sementara = (string) $berkas['tmp_name'];
    $ukuranGambar = @getimagesize($sementara);

    if (!is_array($ukuranGambar)) {
        return [
            'ok' => false,
            'pesan' => 'Berkas ' . $awalan . ' bukan gambar. Gunakan foto JPG atau PNG.',
            'relatif' => '',
        ];
    }

    $jenisGambar = (int) ($ukuranGambar[2] ?? 0);
    $akhiran = '';

    switch ($jenisGambar) {
        case IMAGETYPE_JPEG:
            $akhiran = 'jpg';
            break;
        case IMAGETYPE_PNG:
            $akhiran = 'png';
            break;
        case IMAGETYPE_WEBP:
            $akhiran = 'webp';
            break;
        default:
            return [
                'ok' => false,
                'pesan' => 'Jenis gambar ' . $awalan . ' belum didukung. Gunakan JPG, PNG, atau WEBP.',
                'relatif' => '',
            ];
    }

    $folder = rts_gsp_folder();

    if (!is_dir($folder) && !@mkdir($folder, 0755, true) && !is_dir($folder)) {
        return [
            'ok' => false,
            'pesan' => 'Folder penyimpanan foto GSP tidak dapat dibuat. Hubungi Admin hosting.',
            'relatif' => '',
        ];
    }

    $penjaga = $folder . '/index.html';

    if (!is_file($penjaga)) {
        @file_put_contents($penjaga, 'Akses langsung tidak diizinkan.');
    }

    $namaBaru = 'gsp_' . $jenis . '_' . date('Ymd_His') . '_' . bin2hex(random_bytes(3))
        . '.' . $akhiran;
    $jalurBaru = $folder . '/' . $namaBaru;

    if (!@move_uploaded_file($sementara, $jalurBaru)) {
        if (!@rename($sementara, $jalurBaru)) {
            return [
                'ok' => false,
                'pesan' => 'Foto ' . $awalan . ' gagal disimpan di server. Coba lagi.',
                'relatif' => '',
            ];
        }
    }

    @chmod($jalurBaru, 0644);

    return ['ok' => true, 'pesan' => '', 'relatif' => 'uploads/gsp/' . $namaBaru];
}

rts_api_headers();
rts_api_handle_preflight();

if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan POST.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$jenis = strtoupper(rts_api_param('jenis', 'PENAMBAHAN'));
$idCustomer = rts_api_param('id_customer');
$namaToko = rts_api_param('nama_toko');
$alamat = rts_api_param('alamat');
$pic = rts_api_param('pic');
$nomorHp = rts_api_param('nomor_hp');
$koordinat = rts_api_param('koordinat');
$alasan = rts_api_param('alasan');

if (!in_array($jenis, ['PENAMBAHAN', 'PENGHAPUSAN'], true)) {
    rts_api_fail('Jenis pengajuan GSP tidak dikenali.', 422);
}

if ($idCustomer === '') {
    rts_api_fail('Pilih dulu toko yang dituju pada kolom Nama Toko.', 422);
}

$adaKolomJenis = rts_api_has_column('pengajuan_gsp', 'jenis_request');
$adaTipeCustomer = rts_api_has_column('master_toko', 'tipe_customer');

/* ------------------------------------------------- periksa cakupan tugas */

$scope = rts_api_scope($user);

$cekSql = 'SELECT id_customer, nama_toko, alamat'
    . ($adaTipeCustomer ? ', tipe_customer' : ", 'REGULER' AS tipe_customer")
    . ' FROM master_toko WHERE id_customer = ?';
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
} elseif ($scope['mode'] !== 'all') {
    $cekSql .= ' AND 1 = 0';
}

$cekSql .= ' LIMIT 1';

$cek = $conn->prepare($cekSql);
$dataCek = null;

if ($cek) {
    $cek->bind_param($cekTypes, ...$cekParams);
    $cek->execute();
    $hasilCek = $cek->get_result();
    $dataCek = $hasilCek ? $hasilCek->fetch_assoc() : null;
    $cek->close();
}

if (!$dataCek) {
    rts_api_fail('Toko tidak ditemukan atau bukan bagian tugas Anda.', 404);
}

if ($namaToko === '') {
    $namaToko = (string) ($dataCek['nama_toko'] ?? '');
}

if ($alamat === '') {
    $alamat = (string) ($dataCek['alamat'] ?? '');
}

/* ------------------------------------------------------ keadaan GSP sekarang */

$tipeSekarang = strtoupper(trim((string) ($dataCek['tipe_customer'] ?? 'REGULER')));

if ($jenis === 'PENAMBAHAN' && $tipeSekarang === 'GSP') {
    rts_api_fail('Toko ini sudah berstatus GSP. Tidak perlu diajukan lagi.', 422);
}

if ($jenis === 'PENGHAPUSAN' && $tipeSekarang !== 'GSP') {
    rts_api_fail('Toko ini bukan GSP, jadi tidak dapat diajukan sebagai Hapus GSP.', 422);
}

/* -------------------------------------------------------------- validasi isian */

if ($jenis === 'PENAMBAHAN') {
    $wajib = [];

    if ($pic === '') {
        $wajib[] = 'nama PIC';
    }
    if ($nomorHp === '') {
        $wajib[] = 'nomor HP';
    }
    if ($koordinat === '') {
        $wajib[] = 'titik koordinat (tekan Ambil Titik Lokasi)';
    }
    if ($alamat === '') {
        $wajib[] = 'alamat lengkap';
    }

    if ($wajib) {
        rts_api_fail('Lengkapi dulu: ' . implode(', ', $wajib) . '.', 422);
    }
}

/* ------------------------------------------------------------ data pengirim */

$salesEmail = (string) ($user['email'] ?? '');
$salesman = $scope['salesman'];
$salesDistrict = $scope['sales_district'];

if ($salesEmail === '') {
    rts_api_fail('Email akun belum terisi. Hubungi Admin.', 422);
}

if ($salesman === '' && $salesDistrict === '') {
    rts_api_fail('Akun Anda belum memiliki Salesman atau Sales District. Hubungi Admin.', 422);
}

/* ---------------------------------------------------------------- foto GSP */

$fotoKtp = '';
$fotoLuar = '';
$fotoDalam = '';
$berkasTersimpan = [];

if ($jenis === 'PENAMBAHAN') {
    $awalanBerkas = strtolower($jenis) . '_' . preg_replace('/[^A-Za-z0-9]/', '', $idCustomer);

    foreach (['foto_ktp' => 'KTP', 'foto_luar' => 'luar toko', 'foto_dalam' => 'dalam toko'] as $isian => $label) {
        $hasilFoto = rts_gsp_simpan_foto($isian, $label, $awalanBerkas);

        if (!$hasilFoto['ok']) {
            foreach ($berkasTersimpan as $jalur) {
                @unlink(dirname(__DIR__) . '/' . $jalur);
            }

            rts_api_fail($hasilFoto['pesan'], 422);
        }

        $berkasTersimpan[] = $hasilFoto['relatif'];

        if ($isian === 'foto_ktp') {
            $fotoKtp = $hasilFoto['relatif'];
        } elseif ($isian === 'foto_luar') {
            $fotoLuar = $hasilFoto['relatif'];
        } else {
            $fotoDalam = $hasilFoto['relatif'];
        }
    }
}

/* -------------------------------------------------------------------- simpan */

$tokoLamaNama = '';
$tokoLamaId = '';
$tokoBaruNama = '';
$tokoBaruId = '';

if ($jenis === 'PENAMBAHAN') {
    $tokoBaruNama = $namaToko;
    $tokoBaruId = $idCustomer;
} else {
    $tokoLamaNama = $namaToko;
    $tokoLamaId = $idCustomer;
}

$kolom = [
    'sales_email', 'sales_district', 'salesman',
    'toko_lama_nama', 'toko_lama_id', 'toko_baru_nama', 'toko_baru_id',
    'alamat_lengkap', 'pic_nama', 'nomor_hp', 'koordinat',
    'link_foto_ktp', 'link_foto_luar', 'link_foto_dalam',
];
$nilai = [
    $salesEmail, $salesDistrict, $salesman,
    $tokoLamaNama, $tokoLamaId, $tokoBaruNama, $tokoBaruId,
    $alamat, $pic, $nomorHp, $koordinat,
    $fotoKtp, $fotoLuar, $fotoDalam,
];
$tipeBind = 'ssssssssssssss';
$tanda = '?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?';

if ($adaKolomJenis) {
    $kolom[] = 'jenis_request';
    $nilai[] = $jenis;
    $tipeBind .= 's';
    $tanda .= ', ?';
}

/* Status dan tanggal ditulis langsung supaya pengajuan tetap terbaca oleh
   halaman Pengajuan walaupun kolomnya belum memiliki nilai bawaan. */
if (rts_api_has_column('pengajuan_gsp', 'status_approval')) {
    $kolom[] = 'status_approval';
    $nilai[] = 'Pending';
    $tipeBind .= 's';
    $tanda .= ', ?';
}

if (rts_api_has_column('pengajuan_gsp', 'tanggal_request')) {
    $kolom[] = 'tanggal_request';
    $nilai[] = date('Y-m-d H:i:s');
    $tipeBind .= 's';
    $tanda .= ', ?';
}

$sql = 'INSERT INTO pengajuan_gsp (' . implode(', ', $kolom) . ') VALUES (' . $tanda . ')';
$insert = $conn->prepare($sql);

if (!$insert) {
    foreach ($berkasTersimpan as $jalur) {
        @unlink(dirname(__DIR__) . '/' . $jalur);
    }

    error_log('RTS API request_create_gsp prepare error: ' . $conn->error);
    rts_api_fail('Server sedang mengalami gangguan.', 500);
}

$insert->bind_param($tipeBind, ...$nilai);

if (!$insert->execute()) {
    error_log('RTS API request_create_gsp insert error: ' . $insert->error);
    $insert->close();

    foreach ($berkasTersimpan as $jalur) {
        @unlink(dirname(__DIR__) . '/' . $jalur);
    }

    rts_api_fail('Pengajuan GSP gagal dikirim. Coba lagi.', 500);
}

$idBaru = (int) $conn->insert_id;
$insert->close();

/* ---------------------------------------------------------- pemberitahuan */

$judulJenis = $jenis === 'PENGHAPUSAN' ? 'Hapus GSP' : 'Tambahkan GSP';
$namaNotif = $namaToko !== '' ? $namaToko : ('ID ' . $idCustomer);

$isiNotifAdmin = $salesman . ' (' . $salesDistrict . ') mengirim pengajuan "'
    . $judulJenis . '" untuk ' . $namaNotif;

if ($alasan !== '') {
    $isiNotifAdmin .= '. Alasan: ' . $alasan;
}

$isiNotifAdmin .= '. Silakan diperiksa pada menu Pengajuan.';

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
            'Pengajuan GSP Baru',
            $isiNotifAdmin,
            'WARNING',
            'PENGAJUAN_GSP',
            $idBaru
        );
    }
}

rts_api_response(
    true,
    'Pengajuan "' . $judulJenis . '" berhasil dikirim dan menunggu pemeriksaan ADMIN.',
    [
        'id' => $idBaru,
        'jenis' => $jenis,
        'status_approval' => 'Pending',
        'nama_toko' => $namaNotif,
        'salesman' => $salesman,
        'district' => $salesDistrict,
        'foto_ktp' => $fotoKtp,
        'foto_luar' => $fotoLuar,
        'foto_dalam' => $fotoDalam,
    ]
);
