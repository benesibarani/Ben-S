<?php 
// 1. Matikan Error Display agar tidak merusak file download
ini_set('display_errors', 0);
error_reporting(E_ALL);

// Seluruh halaman ditahan pada tampungan keluaran MILIK BERKAS INI.
// Penting: bila hosting memakai output_buffering terbatas (misalnya 4096),
// halaman bisa terkirim lebih dahulu sehingga header unduhan tidak terpasang
// dan berkas Excel menjadi rusak. Tampungan di bawah ini tanpa batas, jadi
// halaman baru dikirim setelah berkas selesai disusun.
while (ob_get_level() > 0) {
    ob_end_clean();
}
ob_start();

require_once 'config.php';
require_once 'auth.php';
rts_require_login();
require_once 'header.php'; 

// --- 1. LOGIC AUTO CLEANUP ---
$cleanup_date = date('Y-m-d H:i:s', strtotime('-30 days'));
$conn->query("DELETE FROM pengajuan_sales WHERE status_approval != 'Pending' AND tanggal_request < '$cleanup_date'");

$res_gsp = $conn->query("SELECT link_foto_ktp, link_foto_luar, link_foto_dalam FROM pengajuan_gsp WHERE status_approval != 'Pending' AND tanggal_request < '$cleanup_date'");
if ($res_gsp) {
    while($r = $res_gsp->fetch_assoc()) {
        if (!empty($r['link_foto_ktp']) && file_exists($r['link_foto_ktp'])) unlink($r['link_foto_ktp']);
        if (!empty($r['link_foto_luar']) && file_exists($r['link_foto_luar'])) unlink($r['link_foto_luar']);
        if (!empty($r['link_foto_dalam']) && file_exists($r['link_foto_dalam'])) unlink($r['link_foto_dalam']);
    }
}
$conn->query("DELETE FROM pengajuan_gsp WHERE status_approval != 'Pending' AND tanggal_request < '$cleanup_date'");

// --- 2. LOGIC FILTER & ROLE ---
$role_login = strtoupper((string)($_SESSION['role'] ?? ''));
$can_approve = in_array($role_login, ['ADMIN', 'ASS'], true);
$can_view_all = in_array($role_login, ['ADMIN', 'ASS', 'WSS', 'SMST'], true);
$my_email = $_SESSION['email'] ?? '';
$my_name  = $_SESSION['nama'] ?? '';

$where_toko = []; $where_gsp = [];

// Terapkan pengajuan customer ke Master Customer setelah disetujui.
/**
 * Mengubah nilai kolom `week` pada pengajuan menjadi nilai kolom `kunjungan`
 * pada master_toko.
 *
 * Format baru : Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap
 * Format lama : Ganjil / Genap (pengajuan lama dari website)
 *
 * Mengembalikan teks kosong bila nilai tidak dikenali, supaya kolom kunjungan
 * pada Master Customer tidak ikut berubah tanpa alasan.
 */
function rts_week_ke_kunjungan(string $nilai): string {
    $bersih = trim($nilai);

    if ($bersih === '') return '';

    if (strcasecmp($bersih, 'Weekly') === 0) return 'Weekly';
    if (strcasecmp($bersih, 'Bi-Weekly Ganjil') === 0) return 'Bi-Weekly Ganjil';
    if (strcasecmp($bersih, 'Bi-Weekly Genap') === 0) return 'Bi-Weekly Genap';

    // Format lama
    if (strcasecmp($bersih, 'Ganjil') === 0) return 'Bi-Weekly Ganjil';
    if (strcasecmp($bersih, 'Genap') === 0) return 'Bi-Weekly Genap';

    return '';
}

/**
 * Menentukan nilai kunjungan untuk pengajuan Tambah Baru.
 * Memakai kolom week; bila kosong atau tidak dikenali, dicoba dari
 * rute_kunjungan (pengajuan lama), lalu dipakai Weekly.
 */
function rts_kunjungan_pengajuan_baru(array $request): string {
    $nilai = rts_week_ke_kunjungan((string) ($request['week'] ?? ''));

    if ($nilai !== '') return $nilai;

    $nilai = rts_week_ke_kunjungan((string) ($request['rute_kunjungan'] ?? ''));

    return $nilai !== '' ? $nilai : 'Weekly';
}

function apply_gsp_request(mysqli $conn, int $id): bool {
    $stmt = $conn->prepare('SELECT * FROM pengajuan_gsp WHERE id=? AND status_approval="Pending" LIMIT 1');
    $stmt->bind_param('i', $id); $stmt->execute();
    $request = $stmt->get_result()->fetch_assoc();
    if (!$request) return false;
    $jenis = strtoupper(trim($request['jenis_request'] ?? 'PENAMBAHAN'));
    $customer_id = ($jenis === 'PENGHAPUSAN') ? $request['toko_lama_id'] : $request['toko_baru_id'];
    if (trim($customer_id) === '') return false;
    $tipe = ($jenis === 'PENGHAPUSAN') ? 'REGULER' : 'GSP';
    $update = $conn->prepare('UPDATE master_toko SET tipe_customer=? WHERE id_customer=?');
    $update->bind_param('ss', $tipe, $customer_id);
    return $update->execute() && $update->affected_rows >= 0;
}

function apply_customer_request(mysqli $conn, int $id): bool {
    $stmt = $conn->prepare('SELECT * FROM pengajuan_sales WHERE id=? AND status_approval="Pending" LIMIT 1');
    $stmt->bind_param('i', $id); $stmt->execute();
    $request = $stmt->get_result()->fetch_assoc();
    if (!$request) return false;

    $jenis = strtolower(trim($request['jenis_request'] ?? ''));
    $tipe = strtoupper(trim($request['tipe_baru'] ?? 'REGULER'));
    if (!in_array($tipe, ['REGULER', 'GSP'], true)) $tipe = 'REGULER';

    if (in_array($jenis, ['tambah baru', 'tambah outlet', 'penambahan outlet'], true)) {
        $insert = $conn->prepare('INSERT INTO master_toko (nama_toko, id_customer, tipe_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "Aktif")');

        if (!$insert) return false;

        $longitude = ''; $latitude = '';

        // Kolom kunjungan memakai nilai frekuensi (Weekly / Bi-Weekly ...),
        // bukan nama hari. Sebelumnya kolom ini terisi nama hari karena
        // rute_kunjungan dipakai untuk dua hal sekaligus.
        $kunjungan_baru = rts_kunjungan_pengajuan_baru($request);

        $insert->bind_param('ssssssssss', $request['nama_toko_baru'], $request['id_customer'], $tipe, $request['salesman'], $request['alamat_baru'], $kunjungan_baru, $request['visit_day_baru'], $request['sales_distric'], $longitude, $latitude);
        return $insert->execute();
    }

    if (in_array($jenis, ['hapus toko', 'penghapusan outlet'], true)) {
        $conn->begin_transaction();
        try {
            $find = $conn->prepare('SELECT * FROM master_toko WHERE id_customer=? LIMIT 1');
            $find->bind_param('s', $request['id_customer']);
            $find->execute();
            $customer = $find->get_result()->fetch_assoc();
            if (!$customer) throw new RuntimeException('Customer tidak ditemukan.');

            $archive = $conn->prepare('INSERT INTO master_toko_deleted (original_id, id_customer, nama_toko, tipe_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif, alasan_penghapusan, dihapus_oleh) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)');
            $deleted_by = $_SESSION['nama'] ?? 'SYSTEM';
            $archive->bind_param('isssssssssssss', $customer['id'], $customer['id_customer'], $customer['nama_toko'], $customer['tipe_customer'], $customer['salesman'], $customer['alamat'], $customer['kunjungan'], $customer['hari'], $customer['sales_district'], $customer['longitude'], $customer['latitude'], $customer['status_aktif'], $request['alasan'], $deleted_by);
            if (!$archive->execute()) throw new RuntimeException('Arsip customer gagal dibuat.');

            $delete = $conn->prepare('DELETE FROM master_toko WHERE id_customer=?');
            $delete->bind_param('s', $request['id_customer']);
            if (!$delete->execute()) throw new RuntimeException('Customer gagal dihapus.');
            $conn->commit();
            return true;
        } catch (Throwable $error) {
            $conn->rollback();
            return false;
        }
    }

    // Kolom yang diperbarui disusun bertahap.
    // Kolom kunjungan selalu ditulis, persis seperti pada jalur Tambah Baru,
    // tetapi hanya bila nilai frekuensinya dikenali.
    $set = ['nama_toko=?', 'alamat=?', 'tipe_customer=?', 'hari=?', 'sales_district=?'];
    $nilai = [$request['nama_toko_baru'], $request['alamat_baru'], $tipe, $request['visit_day_baru'], $request['sales_distric']];
    $tipe_param = 'sssss';

    $kunjungan_baru = rts_week_ke_kunjungan((string) ($request['week'] ?? ''));

    if ($kunjungan_baru !== '') {
        $set[] = 'kunjungan=?';
        $nilai[] = $kunjungan_baru;
        $tipe_param .= 's';
    }

    $nilai[] = $request['id_customer'];
    $tipe_param .= 's';

    $update = $conn->prepare('UPDATE master_toko SET ' . implode(', ', $set) . ' WHERE id_customer=?');

    if (!$update) return false;

    $update->bind_param($tipe_param, ...$nilai);
    return $update->execute();
}

if (!$can_view_all) {
    $where_toko[] = "sales_email = '$my_email'";
    $where_gsp[] = "sales_email = '$my_email'";
}

// Nilai saringan dibersihkan lebih dahulu (real_escape_string) supaya aman
// dipakai pada perintah database dan tidak dapat disalahgunakan.
$f_start = $conn->real_escape_string(trim((string) ($_GET['f_start'] ?? '')));
$f_end   = $conn->real_escape_string(trim((string) ($_GET['f_end'] ?? '')));
$f_stat  = $conn->real_escape_string(trim((string) ($_GET['f_status'] ?? '')));
$f_key   = $conn->real_escape_string(trim((string) ($_GET['f_keyword'] ?? '')));

if ($f_start) { $where_toko[] = "DATE(tanggal_request) >= '$f_start'"; $where_gsp[] = "DATE(tanggal_request) >= '$f_start'"; }
if ($f_end) { $where_toko[] = "DATE(tanggal_request) <= '$f_end'"; $where_gsp[] = "DATE(tanggal_request) <= '$f_end'"; }
if ($f_stat) { $where_toko[] = "status_approval = '$f_stat'"; $where_gsp[] = "status_approval = '$f_stat'"; }
if ($f_key) {
    $where_toko[] = "(salesman LIKE '%$f_key%' OR nama_toko_baru LIKE '%$f_key%' OR nama_toko_lama LIKE '%$f_key%')";
    $where_gsp[] = "(salesman LIKE '%$f_key%' OR toko_baru_nama LIKE '%$f_key%' OR toko_lama_nama LIKE '%$f_key%')";
}

$sql_toko = "SELECT *, 'Toko Reguler' as tipe_data FROM pengajuan_sales " . (count($where_toko) ? "WHERE " . implode(' AND ', $where_toko) : "") . " ORDER BY tanggal_request DESC";
$sql_gsp  = "SELECT *, 'GSP' as tipe_data FROM pengajuan_gsp " . (count($where_gsp) ? "WHERE " . implode(' AND ', $where_gsp) : "") . " ORDER BY tanggal_request DESC";

// --- 3. EXPORT EXCEL ---
//
// CATATAN PERBAIKAN
// ----------------
// Sebelumnya berkas Excel hanya memuat 12 kolom pilihan, dan pengajuan Sales
// digabung dengan pengajuan GSP pada satu lembar. Sekarang isi berkas Excel
// sama dengan isi database:
//    Lembar 1 : "Pengajuan Sales"   -> SELURUH kolom tabel pengajuan_sales
//    Lembar 2 : "Pengajuan GSP"     -> SELURUH kolom tabel pengajuan_gsp
//    Lembar 3 : "Gabungan (ringkas)"-> susunan ringkas seperti versi lama,
//                                      supaya laporan yang sudah biasa
//                                      dipakai tetap dapat dibuat
//
// Nama dan urutan kolom dibaca langsung dari database (SHOW COLUMNS),
// sehingga bila kelak Bapak menambahkan kolom baru pada tabel, kolom itu
// otomatis ikut terunduh tanpa perlu mengubah berkas ini.
//
// Saringan (tanggal, status, kata kunci) yang sedang dipakai pada halaman
// tetap berlaku untuk berkas yang diunduh.
//
// CATATAN PERBAIKAN TAMBAHAN (2 Oktober 2026 - berkas tidak dapat dibuka di HP)
// ---------------------------------------------------------------------------
// Penyebab yang diperbaiki pada putaran ini:
//   a. Berkas XLSX disusun SELURUHNYA di dalam memori. Tidak lagi memakai
//      ZipArchive, berkas sementara, mkdir, filesize, atau readfile, supaya
//      tidak bergantung pada penyetelan folder sementara hosting.
//   b. SELURUH tampungan keluaran (output buffer) dikosongkan lebih dahulu,
//      sehingga tidak satu huruf pun dari halaman web dapat menyusup ke dalam
//      berkas Excel (penyebab paling sering munculnya pesan "Excel tidak dapat
//      membuka berkas").
//   c. Isi XLSX dilengkapi bagian standar berkas Excel (styles, docProps,
//      dimension, sheetViews) supaya diterima Microsoft Excel di HP.
//   d. Bila alamat dibuka dengan tambahan &diagnosa=1, halaman menampilkan
//      laporan pemeriksaan hosting (untuk memastikan penyebab bila masih gagal).

// Nama kolom dalam Bahasa Indonesia yang mudah dibaca di Excel.
$label_kolom = [
    'id'               => 'ID',
    'tanggal_request'  => 'Tanggal Request',
    'sales_email'      => 'Email Sales',
    'sales_distric'    => 'Sales District',
    'sales_district'   => 'Sales District',
    'salesman'         => 'Nama Salesman',
    'jenis_request'    => 'Jenis Request',
    'id_customer'      => 'ID Customer',
    'pic'              => 'PIC',
    'rute_kunjungan'   => 'Rute Kunjungan',
    'week'             => 'Frekuensi Kunjungan (Week)',
    'nama_toko_lama'   => 'Nama Toko Lama',
    'nama_toko_baru'   => 'Nama Toko Baru',
    'alamat_lama'      => 'Alamat Lama',
    'alamat_baru'      => 'Alamat Baru',
    'tipe_baru'        => 'Tipe Baru',
    'visit_day_baru'   => 'Hari Kunjungan Baru',
    'alasan'           => 'Alasan',
    'status_approval'  => 'Status Approval',
    'processed_by'     => 'Diproses Oleh',
    'processed_at'     => 'Waktu Proses',
    'approval_note'    => 'Catatan Approval',
    'toko_lama_nama'   => 'Nama Toko Lama',
    'toko_lama_id'     => 'ID Toko Lama',
    'toko_baru_nama'   => 'Nama Toko Baru',
    'toko_baru_id'     => 'ID Toko Baru',
    'alamat_lengkap'   => 'Alamat Lengkap',
    'pic_nama'         => 'Nama PIC',
    'nomor_hp'         => 'Nomor HP',
    'koordinat'        => 'Koordinat',
    'link_foto_ktp'    => 'Foto KTP',
    'link_foto_luar'   => 'Foto Toko (Luar)',
    'link_foto_dalam'  => 'Foto Toko (Dalam)',
];

/** Mengubah nama kolom database menjadi judul yang enak dibaca. */
$label = function (string $nama) use ($label_kolom): string {
    return $label_kolom[$nama] ?? $nama;
};

/** Membaca daftar kolom sebuah tabel langsung dari database. */
$kolom_tabel = function (string $tabel) use ($conn): array {
    $daftar = [];
    $hasil = $conn->query('SHOW COLUMNS FROM `' . $tabel . '`');

    if ($hasil) {
        while ($baris = $hasil->fetch_assoc()) {
            $daftar[] = $baris['Field'];
        }
    }

    return $daftar;
};

/**
 * Menyusun berkas XLSX (ZIP) langsung di dalam memori.
 *
 * Sengaja TIDAK memakai kelas ZipArchive, berkas sementara, maupun readfile
 * supaya hasilnya sama di semua hosting dan tidak mungkin terpotong.
 * Ukuran data kecil (hanya huruf), sehingga aman disusun di memori.
 */
function rts_xlsx_buat(array $bagian): string
{
    $waktu = getdate();
    $jam_dos = (($waktu['hours'] << 11) | ($waktu['minutes'] << 5) | intdiv($waktu['seconds'], 2)) & 0xFFFF;
    $tgl_dos = ((($waktu['year'] - 1980) << 9) | ($waktu['mon'] << 5) | $waktu['mday']) & 0xFFFF;

    $isi_lokal = '';
    $isi_pusat = '';
    $jumlah = 0;
    $offset = 0;

    foreach ($bagian as $nama => $data) {
        $nama = (string) $nama;
        $data = (string) $data;

        $crc = crc32($data);
        $crc_bawah = $crc & 0xFFFF;
        $crc_atas = ($crc >> 16) & 0xFFFF;

        $asli = strlen($data);

        // Data dipadatkan lebih dahulu (deflate). Bila zlib tidak tersedia,
        // berkas tetap sah dengan mode tanpa pemadatan (stored).
        $metode = 8;
        $padat = function_exists('gzcompress') ? @gzcompress($data, 6) : false;

        // gzcompress menghasilkan format zlib: 2 byte tajuk + data + 4 byte adler.
        // ZIP memerlukan deflate mentah, jadi tajuk dan adler dibuang.
        if (is_string($padat) && strlen($padat) > 6) {
            $padat = substr($padat, 2, -4);
        } else {
            $metode = 0;
            $padat = $data;
        }

        $ukuran = strlen($padat);
        $bendera = 0x0800; // nama berkas memakai huruf UTF-8

        $isi_lokal .= "PK\x03\x04"
            . pack('v', 20)            // versi minimum
            . pack('v', $bendera)      // penanda
            . pack('v', $metode)       // cara pemadatan
            . pack('v', $jam_dos)      // jam
            . pack('v', $tgl_dos)      // tanggal
            . pack('v', $crc_bawah) . pack('v', $crc_atas)
            . pack('V', $ukuran)       // ukuran padat
            . pack('V', $asli)         // ukuran asli
            . pack('v', strlen($nama))
            . pack('v', 0)             // panjang keterangan tambahan
            . $nama
            . $padat;

        $isi_pusat .= "PK\x01\x02"
            . pack('v', 20)            // versi pembuat
            . pack('v', 20)            // versi minimum
            . pack('v', $bendera)
            . pack('v', $metode)
            . pack('v', $jam_dos)
            . pack('v', $tgl_dos)
            . pack('v', $crc_bawah) . pack('v', $crc_atas)
            . pack('V', $ukuran)
            . pack('V', $asli)
            . pack('v', strlen($nama))
            . pack('v', 0)             // panjang keterangan tambahan
            . pack('v', 0)             // panjang komentar
            . pack('v', 0)             // nomor cakram
            . pack('v', 0)             // atribut dalam
            . pack('V', 32)            // atribut luar (berkas biasa)
            . pack('V', $offset)       // letak tajuk lokal
            . $nama;

        $offset += 30 + strlen($nama) + $ukuran;
        $jumlah++;
    }

    return $isi_lokal . $isi_pusat
        . "PK\x05\x06"
        . pack('v', 0)                 // nomor cakram
        . pack('v', 0)                 // cakram awal pusat
        . pack('v', $jumlah)
        . pack('v', $jumlah)
        . pack('V', strlen($isi_pusat))
        . pack('V', $offset)
        . pack('v', 0);                // panjang komentar
}

if (isset($_GET['export_excel'])) {
    // Seluruh tampungan keluaran dikosongkan supaya HTML halaman tidak pernah
    // ikut terkirim bersama berkas Excel.
    while (ob_get_level() > 0) {
        ob_end_clean();
    }

    $lembar = [];
    $ringkas = [[
        'Tipe Data', 'Tanggal Request', 'Nama Salesman', 'District',
        'Jenis Request / GSP Lama', 'Detail / GSP Baru', 'ID Customer',
        'Alamat', 'Status Approval', 'Diproses Oleh', 'Waktu Proses', 'Catatan',
    ]];

    // --- Lembar 1 & 2: seluruh kolom masing-masing tabel ---------------------
    $sumber = [
        [
            'judul'   => 'Pengajuan Sales',
            'tabel'   => 'pengajuan_sales',
            'sql'     => $sql_toko,
            'tipe'    => 'Toko Reguler',
            'district' => 'sales_distric',
            'jenis'   => 'jenis_request',
            'toko'    => ['nama_toko_baru', 'nama_toko_lama'],
            'idcust'  => 'id_customer',
            'alamat'  => ['alamat_baru', 'alamat_lama'],
        ],
        [
            'judul'   => 'Pengajuan GSP',
            'tabel'   => 'pengajuan_gsp',
            'sql'     => $sql_gsp,
            'tipe'    => 'GSP',
            'district' => 'sales_district',
            'jenis'   => '',
            'toko'    => ['toko_baru_nama', 'toko_lama_nama'],
            'idcust'  => 'toko_baru_id',
            'alamat'  => ['alamat_lengkap'],
        ],
    ];

    $jumlah_baris = [];

    foreach ($sumber as $satu) {
        $kolom = $kolom_tabel($satu['tabel']);
        $hasil = $conn->query($satu['sql']);

        if (!$kolom || !$hasil) {
            continue;
        }

        // Baris pertama = judul kolom, memakai nama yang mudah dibaca.
        $baris = [array_map($label, $kolom)];

        while ($r = $hasil->fetch_assoc()) {
            $satu_baris = [];

            foreach ($kolom as $nama) {
                $satu_baris[] = (string) ($r[$nama] ?? '');
            }

            $baris[] = $satu_baris;

            // Susunan ringkas untuk lembar ke-3.
            $jenis = $satu['jenis'] !== '' ? ($r[$satu['jenis']] ?? '') : 'GSP';

            $nama_toko = '';
            foreach ($satu['toko'] as $kunci) {
                if ($nama_toko === '' && !empty($r[$kunci])) {
                    $nama_toko = $r[$kunci];
                }
            }

            $alamat = '';
            foreach ($satu['alamat'] as $kunci) {
                if ($alamat === '' && !empty($r[$kunci])) {
                    $alamat = $r[$kunci];
                }
            }

            $ringkas[] = [
                $satu['tipe'],
                $r['tanggal_request'] ?? '',
                $r['salesman'] ?? '',
                $r[$satu['district']] ?? '',
                $jenis,
                $nama_toko,
                ($r[$satu['idcust']] ?? '') !== '' ? $r[$satu['idcust']] : '-',
                $alamat,
                $r['status_approval'] ?? '',
                $r['processed_by'] ?? '',
                $r['processed_at'] ?? '',
                $r['approval_note'] ?? '',
            ];
        }

        $jumlah_baris[$satu['judul']] = count($baris);
        $lembar[] = ['judul' => $satu['judul'], 'baris' => $baris];
    }

    if (!$lembar) {
        http_response_code(500);
        exit('Data pengajuan tidak dapat dibaca dari database.');
    }

    $lembar[] = ['judul' => 'Gabungan (ringkas)', 'baris' => $ringkas];
    $jumlah_baris['Gabungan (ringkas)'] = count($ringkas);

    // --- Nilai dibersihkan lebih dahulu supaya berkas Excel selalu dapat dibuka.
    $esc = function ($nilai): string {
        $teks = (string) $nilai;
        $teks = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/', '', $teks);
        $teks = substr($teks, 0, 32767);

        return htmlspecialchars($teks, ENT_XML1 | ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
    };

    // Nama lembar Excel paling panjang 31 huruf dan tanpa karakter tertentu.
    $nama_lembar = function (string $judul): string {
        $aman = preg_replace('~[\\\\/?*\[\]:]~', ' ', $judul);

        return substr(trim((string) $aman), 0, 31);
    };

    // --- Menyusun bagian-bagian berkas XLSX ----------------------------------
    $bagian = [];
    $def_lembar = [];
    $def_rel = [];
    $def_tipe = [];
    $nama_semua = [];

    foreach ($lembar as $i => $l) {
        $nomor = $i + 1;
        $nama_aman = $nama_lembar($l['judul']);
        $nama_semua[] = $nama_aman;
        $sheet = '';
        $terakhir = 'A1';

        foreach ($l['baris'] as $ri => $row) {
            $sheet .= '<row r="' . ($ri + 1) . '">';

            foreach ($row as $ci => $val) {
                $col = '';
                $n = $ci + 1;

                while ($n > 0) {
                    $n--;
                    $col = chr(65 + ($n % 26)) . $col;
                    $n = intdiv($n, 26);
                }

                $sheet .= '<c r="' . $col . ($ri + 1) . '" t="inlineStr" s="0">'
                    . '<is><t xml:space="preserve">' . $esc($val) . '</t></is></c>';
                $terakhir = $col . ($ri + 1);
            }

            $sheet .= '</row>';
        }

        $bagian['xl/worksheets/sheet' . $nomor . '.xml'] =
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            . '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
            . '<dimension ref="A1:' . $terakhir . '"/>'
            . '<sheetViews><sheetView workbookViewId="0"/></sheetViews>'
            . '<sheetFormatPr defaultRowHeight="15"/>'
            . '<sheetData>' . $sheet . '</sheetData>'
            . '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>'
            . '</worksheet>';

        $def_lembar[] = '<sheet name="' . $esc($nama_aman) . '" sheetId="'
            . $nomor . '" r:id="rId' . $nomor . '"/>';

        $def_rel[] = '<Relationship Id="rId' . $nomor . '" '
            . 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
            . 'Target="worksheets/sheet' . $nomor . '.xml"/>';

        $def_tipe[] = '<Override PartName="/xl/worksheets/sheet' . $nomor . '.xml" '
            . 'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>';
    }

    $bagian['xl/workbook.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        . 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        . '<workbookPr/>'
        . '<bookViews><workbookView xWindow="0" yWindow="0" windowWidth="20000" windowHeight="10000"/></bookViews>'
        . '<sheets>' . implode('', $def_lembar) . '</sheets>'
        . '</workbook>';

    $bagian['xl/_rels/workbook.xml.rels'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        . implode('', $def_rel)
        . '<Relationship Id="rId' . (count($lembar) + 1) . '" '
        . 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
        . 'Target="styles.xml"/></Relationships>';

    // Gaya tampilan paling sederhana (sama seperti berkas Excel baru).
    $bagian['xl/styles.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        . '<fonts count="1"><font><sz val="11"/><color theme="1"/><name val="Calibri"/>'
        . '<family val="2"/><scheme val="minor"/></font></fonts>'
        . '<fills count="2"><fill><patternFill patternType="none"/></fill>'
        . '<fill><patternFill patternType="gray125"/></fill></fills>'
        . '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        . '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        . '<cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>'
        . '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        . '<dxfs count="0"/>'
        . '</styleSheet>';

    $bagian['_rels/.rels'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        . '<Relationship Id="rId1" '
        . 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
        . 'Target="xl/workbook.xml"/>'
        . '<Relationship Id="rId2" '
        . 'Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" '
        . 'Target="docProps/core.xml"/>'
        . '<Relationship Id="rId3" '
        . 'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" '
        . 'Target="docProps/app.xml"/></Relationships>';

    $waktu_iso = gmdate('Y-m-d\TH:i:s\Z');

    $bagian['docProps/core.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<cp:coreProperties '
        . 'xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        . 'xmlns:dc="http://purl.org/dc/elements/1.1/" '
        . 'xmlns:dcterms="http://purl.org/dc/terms/" '
        . 'xmlns:dcmitype="http://purl.org/dc/dcmitype/" '
        . 'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        . '<dc:title>Laporan Pengajuan RTS Panel</dc:title>'
        . '<dc:creator>RTS Panel</dc:creator>'
        . '<cp:lastModifiedBy>RTS Panel</cp:lastModifiedBy>'
        . '<dcterms:created xsi:type="dcterms:W3CDTF">' . $waktu_iso . '</dcterms:created>'
        . '<dcterms:modified xsi:type="dcterms:W3CDTF">' . $waktu_iso . '</dcterms:modified>'
        . '</cp:coreProperties>';

    $judul_lembar = '';
    foreach ($nama_semua as $satu_nama) {
        $judul_lembar .= '<vt:lpstr>' . $esc($satu_nama) . '</vt:lpstr>';
    }

    $bagian['docProps/app.xml'] =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<Properties '
        . 'xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
        . 'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
        . '<Application>Microsoft Excel</Application>'
        . '<DocSecurity>0</DocSecurity><ScaleCrop>false</ScaleCrop>'
        . '<HeadingPairs><vt:vector size="2" baseType="variant">'
        . '<vt:variant><vt:lpstr>Worksheets</vt:lpstr></vt:variant>'
        . '<vt:variant><vt:i4>' . count($nama_semua) . '</vt:i4></vt:variant>'
        . '</vt:vector></HeadingPairs>'
        . '<TitlesOfParts><vt:vector size="' . count($nama_semua) . '" baseType="lpstr">'
        . $judul_lembar . '</vt:vector></TitlesOfParts>'
        . '<Company></Company><LinksUpToDate>false</LinksUpToDate>'
        . '<SharedDoc>false</SharedDoc><HyperlinksChanged>false</HyperlinksChanged>'
        . '<AppVersion>16.0300</AppVersion></Properties>';

    // Berkas [Content_Types].xml diletakkan paling depan, sama seperti Excel.
    $tipe_isi =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        . '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        . '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        . '<Default Extension="xml" ContentType="application/xml"/>'
        . '<Override PartName="/xl/workbook.xml" '
        . 'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        . '<Override PartName="/xl/styles.xml" '
        . 'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        . '<Override PartName="/docProps/core.xml" '
        . 'ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        . '<Override PartName="/docProps/app.xml" '
        . 'ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        . implode('', $def_tipe) . '</Types>';

    $urutan = ['[Content_Types].xml' => $tipe_isi];

    foreach ($bagian as $nama_bagian => $isi_bagian) {
        $urutan[$nama_bagian] = $isi_bagian;
    }

    $isi_xlsx = rts_xlsx_buat($urutan);

    // --- Mode pemeriksaan hosting (buka: inbox.php?export_excel=1&diagnosa=1) -
    if (isset($_GET['diagnosa'])) {
        header('Content-Type: text/plain; charset=utf-8');
        header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

        $cek_tanda = substr($isi_xlsx, 0, 4) === "PK\x03\x04" ? 'BENAR (PK)' : 'SALAH';
        $cek_ekor = substr($isi_xlsx, -22, 4) === "PK\x05\x06" ? 'BENAR (PK)' : 'SALAH';

        echo "LAPORAN PEMERIKSAAN EXPORT EXCEL - RTS PANEL\n";
        echo "waktu                : " . date('Y-m-d H:i:s') . "\n";
        echo "versi PHP            : " . PHP_VERSION . " (" . PHP_SAPI . ")\n";
        echo "ZipArchive           : " . (class_exists('ZipArchive') ? 'ADA' : 'TIDAK ADA') . "\n";
        echo "zlib (gzcompress)    : " . (function_exists('gzcompress') ? 'ADA' : 'TIDAK ADA') . "\n";
        echo "mbstring             : " . (function_exists('mb_check_encoding') ? 'ADA' : 'TIDAK ADA') . "\n";
        echo "output_buffering     : " . (string) ini_get('output_buffering') . "\n";
        echo "zlib.output_compression: " . (string) ini_get('zlib.output_compression') . "\n";
        echo "memory_limit         : " . (string) ini_get('memory_limit') . "\n";
        echo "folder sementara     : " . sys_get_temp_dir() . " (" . (is_writable(sys_get_temp_dir()) ? 'bisa ditulis' : 'TIDAK bisa ditulis') . ")\n";
        echo "headers sudah terkirim: " . (headers_sent() ? 'YA' : 'belum') . "\n";
        echo "sisa tampungan       : " . ob_get_level() . "\n";
        echo "baris per lembar     :";

        foreach ($jumlah_baris as $nama_l => $jml) {
            echo " " . $nama_l . "=" . $jml;
        }

        echo "\n";
        echo "ukuran berkas xlsx   : " . strlen($isi_xlsx) . " byte\n";
        echo "jumlah bagian        : " . count($urutan) . "\n";
        echo "empat byte pertama   : " . $cek_tanda . "\n";
        echo "penutup berkas       : " . $cek_ekor . "\n";
        echo "nama lembar          : " . implode(' | ', $nama_semua) . "\n";
        echo "empat byte pertama (hex): " . strtoupper(bin2hex(substr($isi_xlsx, 0, 4))) . "\n";
        exit;
    }

    // --- Berkas dikirim apa adanya -------------------------------------------
    header('Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    header('Content-Disposition: attachment; filename="Laporan_Pengajuan_' . date('Ymd_His') . '.xlsx"');
    header('Content-Length: ' . strlen($isi_xlsx));
    header('Content-Transfer-Encoding: binary');
    header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
    header('Pragma: no-cache');
    header('Expires: 0');
    header('X-Content-Type-Options: nosniff');

    echo $isi_xlsx;
    exit;
}

// --- 4. LOGIC ACTIONS ---
if (isset($_POST['action_type'])) {
    $id = (int)$_POST['req_id'];
    $table = ($_POST['data_type'] == 'GSP') ? 'pengajuan_gsp' : 'pengajuan_sales';
    $act = $_POST['action_type']; 
    
    if ($act == 'delete') {
        if (!$can_view_all) {
            $check = $conn->query("SELECT id FROM $table WHERE id=$id AND sales_email='$my_email' AND status_approval='Pending'");
            if ($check->num_rows == 0) die("Akses Ditolak");
        }
        $conn->query("DELETE FROM $table WHERE id=$id");
        echo "<script>alert('Data Berhasil Dihapus'); window.location='inbox.php';</script>";
    } elseif ($can_approve) {
        $status = ($act == 'approve') ? 'Disetujui' : 'Ditolak';
        if ($status === 'Disetujui' && $table === 'pengajuan_sales' && !apply_customer_request($conn, $id)) {
            die('Pengajuan tidak dapat diterapkan ke Master Customer. Periksa data pengajuan.');
        }
        if ($status === 'Disetujui' && $table === 'pengajuan_gsp' && !apply_gsp_request($conn, $id)) {
            die('Pengajuan GSP tidak dapat diterapkan ke Master Customer. Periksa ID customer.');
        }
        $processed_by = $_SESSION['nama'] ?? ($_SESSION['username'] ?? 'SYSTEM');
        $approval_note = trim($_POST['approval_note'] ?? '');
        $audit = $conn->prepare("UPDATE $table SET status_approval=?, processed_by=?, processed_at=CURRENT_TIMESTAMP, approval_note=? WHERE id=?");
        $audit->bind_param('sssi', $status, $processed_by, $approval_note, $id);
        $audit->execute();
        $owner_stmt = $conn->prepare("SELECT sales_email FROM $table WHERE id=? LIMIT 1");
        $owner_stmt->bind_param('i', $id); $owner_stmt->execute();
        $owner = $owner_stmt->get_result()->fetch_assoc();
        if (!empty($owner['sales_email'])) {
            $judulNotif = 'Status Pengajuan ' . $status;
            $pesanNotif = 'Pengajuan Anda diproses oleh ' . $processed_by . '. Catatan: ' . ($approval_note ?: '-');
            $tipeNotif  = $status === 'Disetujui' ? 'SUCCESS' : 'DANGER';

            rts_notify_email($conn, $owner['sales_email'], $judulNotif, $pesanNotif, $tipeNotif, $table, $id);

            /* TAMBAHAN FIREBASE: kirim juga ke layar HP pengirim pengajuan,
               supaya tetap masuk walaupun aplikasinya sedang ditutup. */
            if (is_file(__DIR__ . '/api/fcm_kirim.php')) {
                require_once __DIR__ . '/api/fcm_kirim.php';

                rts_push_kirim($conn, $owner['sales_email'], $judulNotif, $pesanNotif, [
                    'tipe' => $tipeNotif,
                    'ref_tipe' => $table,
                    'ref_id' => $id,
                ]);
            }
        }
        
        $admin = $_SESSION['nama'];
        $detail = "Mengubah status ID $id ($table) menjadi $status";
        $conn->query("INSERT INTO riwayat_aksi (admin_name, action_type, request_detail) VALUES ('$admin', '$status', '$detail')");
        
        echo "<script>alert('Status Berhasil Diupdate: $status'); window.location='inbox.php';</script>";
    }
}
// Logic Bulk
if ($can_approve && isset($_POST['bulk_action']) && isset($_POST['req_ids'])) {
    $act = $_POST['bulk_action']; 
    $status = ($act == 'approve_all') ? 'Disetujui' : 'Ditolak';
    $count = 0;
    foreach ($_POST['req_ids'] as $val) {
        list($id, $type) = explode(':', $val);
        $id = (int)$id;
        $table = ($type == 'GSP') ? 'pengajuan_gsp' : 'pengajuan_sales';
        $applied = true;
        if ($status === 'Disetujui' && $table === 'pengajuan_sales') {
            $applied = apply_customer_request($conn, $id);
        } elseif ($status === 'Disetujui' && $table === 'pengajuan_gsp') {
            $applied = apply_gsp_request($conn, $id);
        }
        $processed_by = $_SESSION['nama'] ?? ($_SESSION['username'] ?? 'SYSTEM');
        $approval_note = trim($_POST['approval_note'] ?? '');
        $audit = $conn->prepare("UPDATE $table SET status_approval=?, processed_by=?, processed_at=CURRENT_TIMESTAMP, approval_note=? WHERE id=?");
        $audit->bind_param('sssi', $status, $processed_by, $approval_note, $id);
        if ($applied && $audit->execute()) {
            $count++;
            $detail = "Bulk $status ID $id ($type)";
            $conn->query("INSERT INTO riwayat_aksi (admin_name, action_type, request_detail) VALUES ('$my_name', '$status', '$detail')");

            // Pemberitahuan untuk pengirim pengajuan, sama seperti pada
            // pemrosesan satu per satu.
            $owner_stmt = $conn->prepare("SELECT sales_email FROM $table WHERE id=? LIMIT 1");
            $owner_stmt->bind_param('i', $id);
            $owner_stmt->execute();
            $owner = $owner_stmt->get_result()->fetch_assoc();
            if (!empty($owner['sales_email'])) {
                $judulNotif = 'Status Pengajuan ' . $status;
                $pesanNotif = 'Pengajuan Anda diproses oleh ' . $processed_by . '. Catatan: ' . ($approval_note ?: '-');
                $tipeNotif  = $status === 'Disetujui' ? 'SUCCESS' : 'DANGER';

                rts_notify_email($conn, $owner['sales_email'], $judulNotif, $pesanNotif, $tipeNotif, $table, $id);

                /* TAMBAHAN FIREBASE: kirim juga ke layar HP pengirim pengajuan. */
                if (is_file(__DIR__ . '/api/fcm_kirim.php')) {
                    require_once __DIR__ . '/api/fcm_kirim.php';

                    rts_push_kirim($conn, $owner['sales_email'], $judulNotif, $pesanNotif, [
                        'tipe' => $tipeNotif,
                        'ref_tipe' => $table,
                        'ref_id' => $id,
                    ]);
                }
            }
        }
    }
    echo "<script>alert('Berhasil memproses $count pengajuan.'); window.location='inbox.php';</script>";
    exit();
}

// Logic Edit
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['update_request'])) {
        $id = (int)$_POST['edit_id'];
        // Cek Security
        if (!$can_view_all) {
            $check = $conn->query("SELECT id FROM pengajuan_sales WHERE id=$id AND sales_email='$my_email' AND status_approval='Pending'");
            if ($check->num_rows == 0) { echo "<script>alert('Akses Ditolak'); window.location='inbox.php';</script>"; exit(); }
        }
        $stmt = $conn->prepare("UPDATE pengajuan_sales SET sales_distric=?, salesman=?, jenis_request=?, id_customer=?, pic=?, rute_kunjungan=?, week=?, nama_toko_lama=?, nama_toko_baru=?, alamat_lama=?, alamat_baru=?, tipe_baru=?, visit_day_baru=?, alasan=?, tanggal_request=CURRENT_TIMESTAMP WHERE id=?");
        $stmt->bind_param("sssissssssssssi", $_POST['sales_distric'], $_POST['salesman'], $_POST['jenis_request'], $_POST['id_customer'], $_POST['pic'], $_POST['rute_kunjungan'], $_POST['week'], $_POST['nama_toko_lama'], $_POST['nama_toko_baru'], $_POST['alamat_lama'], $_POST['alamat_baru'], $_POST['tipe'], $_POST['visit_day'], $_POST['alasan'], $id);
        if($stmt->execute()) echo "<script>alert('Data Toko Berhasil Diupdate!');</script>";
    }
    if (isset($_POST['update_gsp'])) {
        $id = (int)$_POST['edit_gsp_id'];
        if (!$can_view_all) {
            $check = $conn->query("SELECT id FROM pengajuan_gsp WHERE id=$id AND sales_email='$my_email' AND status_approval='Pending'");
            if ($check->num_rows == 0) { echo "<script>alert('Akses Ditolak'); window.location='inbox.php';</script>"; exit(); }
        }
        $target_dir = "uploads/";
        $f_ktp = uploadImage("foto_ktp", $target_dir) ?? $_POST['old_foto_ktp'];
        $f_luar = uploadImage("foto_luar", $target_dir) ?? $_POST['old_foto_luar'];
        $f_dalam = uploadImage("foto_dalam", $target_dir) ?? $_POST['old_foto_dalam'];
        $stmt = $conn->prepare("UPDATE pengajuan_gsp SET sales_district=?, salesman=?, toko_lama_nama=?, toko_lama_id=?, toko_baru_nama=?, toko_baru_id=?, alamat_lengkap=?, pic_nama=?, nomor_hp=?, koordinat=?, link_foto_ktp=?, link_foto_luar=?, link_foto_dalam=?, tanggal_request=CURRENT_TIMESTAMP WHERE id=?");
        $stmt->bind_param("sssssssssssssi", $_POST['sales_district'], $_POST['salesman'], $_POST['toko_lama_nama'], $_POST['toko_lama_id'], $_POST['toko_baru_nama'], $_POST['toko_baru_id'], $_POST['alamat_lengkap'], $_POST['pic_nama'], $_POST['nomor_hp'], $_POST['koordinat'], $f_ktp, $f_luar, $f_dalam, $id);
        if($stmt->execute()) echo "<script>alert('Data GSP Berhasil Diupdate!');</script>";
    }
}
?>

<!-- MODAL DETAIL GSP (DENGAN LATITUDE/LONGITUDE) -->
<div class="modal fade" id="gspDetailModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header bg-light"><h5 class="modal-title fw-bold">Detail Pengajuan GSP</h5><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div><div class="modal-body"><div class="row"><div class="col-md-6 mb-3"><label class="small text-muted fw-bold">SALESMAN</label><div id="d_salesman" class="fw-bold text-primary"></div></div><div class="col-md-6 mb-3"><label class="small text-muted fw-bold">DISTRICT</label><div id="d_district"></div></div><div class="col-md-6"><div class="p-2 border rounded bg-light mb-2"><small class="text-danger fw-bold d-block">GSP LAMA</small><div id="d_toko_lama"></div><small id="d_id_lama" class="text-muted"></small></div></div><div class="col-md-6"><div class="p-2 border rounded bg-light mb-2"><small class="text-success fw-bold d-block">GSP BARU</small><div id="d_toko_baru"></div><small id="d_id_baru" class="text-muted"></small></div></div><div class="col-12 mt-2"><table class="table table-sm table-borderless"><tr><td width="30%" class="text-muted">Alamat</td><td id="d_alamat"></td></tr><tr><td class="text-muted">PIC</td><td id="d_pic"></td></tr><tr><td class="text-muted">No HP</td><td id="d_hp"></td></tr><tr><td class="text-muted">Koordinat</td><td><a href="#" id="d_maps" target="_blank" class="text-decoration-none"><i class="fas fa-map-marker-alt"></i> Buka Maps</a></td></tr>
<tr><td class="text-muted">Status Approval</td><td id="d_status"></td></tr><tr><td class="text-muted">Diproses Oleh</td><td id="d_processed"></td></tr><tr><td class="text-muted">Catatan</td><td id="d_note"></td></tr>
<!-- TAMBAHAN BARU: LATITUDE & LONGITUDE -->
<tr><td class="text-muted">Latitude</td><td id="d_lat" class="fw-bold text-dark"></td></tr>
<tr><td class="text-muted">Longitude</td><td id="d_long" class="fw-bold text-dark"></td></tr>
</table></div><div class="col-12 border-top pt-3"><label class="small text-muted fw-bold mb-2">DOKUMENTASI</label><div class="row g-2 text-center"><div class="col-4"><img id="img_ktp" src="" class="img-fluid rounded border mb-1" style="max-height:150px;"><div class="small text-muted">KTP</div></div><div class="col-4"><img id="img_luar" src="" class="img-fluid rounded border mb-1" style="max-height:150px;"><div class="small text-muted">Luar</div></div><div class="col-4"><img id="img_dalam" src="" class="img-fluid rounded border mb-1" style="max-height:150px;"><div class="small text-muted">Dalam</div></div></div></div></div></div><div class="modal-footer"><button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Tutup</button></div></div></div></div>

<!-- MODAL EDIT TOKO & GSP (SAMA SEPERTI SEBELUMNYA) -->
<div class="modal fade" id="editTokoModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header bg-info text-white"><h5 class="modal-title fw-bold">Edit Pengajuan Toko</h5><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div><div class="modal-body"><form method="POST"><input type="hidden" name="update_request" value="1"><input type="hidden" name="edit_id" id="et_id"><div class="row g-3"><div class="col-md-6"><label class="small fw-bold">Salesman</label><input type="text" name="salesman" id="et_salesman" class="form-control" readonly></div><div class="col-md-6"><label class="small fw-bold">District</label><input type="text" name="sales_distric" id="et_dist" class="form-control" required></div><div class="col-12"><label class="small fw-bold">Jenis</label><select name="jenis_request" id="et_jenis" class="form-select" readonly><option value="Tambah Baru">Tambah Baru</option><option value="Ganti Nama">Ganti Nama</option><option value="Ganti Alamat">Ganti Alamat</option><option value="Hapus Toko">Hapus Toko</option></select></div><div class="col-12 bg-light p-2 rounded"><input name="id_customer" id="et_id_cust" class="form-control mb-2" placeholder="ID Customer"><input name="nama_toko_lama" id="et_nm_lama" class="form-control mb-2" placeholder="Nama Lama"><input name="nama_toko_baru" id="et_nm_baru" class="form-control mb-2" placeholder="Nama Baru"><input name="alamat_lama" id="et_al_lama" class="form-control mb-2" placeholder="Alamat Lama"><input name="alamat_baru" id="et_al_baru" class="form-control mb-2" placeholder="Alamat Baru"></div><div class="col-md-4"><label class="small">PIC</label><input name="pic" id="et_pic" class="form-control"></div><div class="col-md-4"><label class="small">Hari</label><select name="rute_kunjungan" id="et_rute" class="form-select"><option>Senin</option><option>Selasa</option><option>Rabu</option><option>Kamis</option><option>Jumat</option><option>Sabtu</option></select></div><div class="col-md-4"><label class="small">Frekuensi</label><select name="week" id="et_week" class="form-select"><option>Weekly</option><option>Bi-Weekly Ganjil</option><option>Bi-Weekly Genap</option><option>Ganjil</option><option>Genap</option></select></div><div class="col-12"><label class="small">Alasan</label><textarea name="alasan" id="et_alasan" class="form-control"></textarea></div><div class="col-12"><button class="btn btn-primary w-100">Simpan Perubahan</button></div></div></form></div></div></div></div>
<div class="modal fade" id="editGspModal" tabindex="-1"><div class="modal-dialog modal-lg"><div class="modal-content"><div class="modal-header bg-warning"><h5 class="modal-title fw-bold">Edit Pengajuan GSP</h5><button type="button" class="btn-close" data-bs-dismiss="modal"></button></div><div class="modal-body"><form method="POST" enctype="multipart/form-data"><input type="hidden" name="update_gsp" value="1"><input type="hidden" name="edit_gsp_id" id="eg_id"><input type="hidden" name="old_foto_ktp" id="eg_old_ktp"><input type="hidden" name="old_foto_luar" id="eg_old_luar"><input type="hidden" name="old_foto_dalam" id="eg_old_dalam"><div class="row g-3"><div class="col-md-6"><label class="small">Salesman</label><input type="text" name="salesman" id="eg_salesman" class="form-control" readonly></div><div class="col-md-6"><label class="small">District</label><input type="text" name="sales_district" id="eg_dist" class="form-control" required></div><div class="col-md-6 bg-light p-2"><label class="small text-danger">GSP Lama</label><input name="toko_lama_nama" id="eg_nm_lama" class="form-control mb-1"><input name="toko_lama_id" id="eg_id_lama" class="form-control"></div><div class="col-md-6 bg-light p-2"><label class="small text-success">GSP Baru</label><input name="toko_baru_nama" id="eg_nm_baru" class="form-control mb-1"><input name="toko_baru_id" id="eg_id_baru" class="form-control"></div><div class="col-12"><label class="small">Alamat</label><textarea name="alamat_lengkap" id="eg_alamat" class="form-control"></textarea></div><div class="col-md-6"><label class="small">PIC</label><input name="pic_nama" id="eg_pic" class="form-control"></div><div class="col-md-6"><label class="small">HP</label><input name="nomor_hp" id="eg_hp" class="form-control"></div><div class="col-12"><label class="small">Koordinat</label><input name="koordinat" id="eg_koor" class="form-control"></div><div class="col-12 border-top pt-2"><label class="small fw-bold">Update Foto (Biarkan kosong jika tidak ubah)</label></div><div class="col-md-4"><label class="small">KTP</label><input type="file" name="foto_ktp" class="form-control form-control-sm"></div><div class="col-md-4"><label class="small">Luar</label><input type="file" name="foto_luar" class="form-control form-control-sm"></div><div class="col-md-4"><label class="small">Dalam</label><input type="file" name="foto_dalam" class="form-control form-control-sm"></div><div class="col-12"><button class="btn btn-warning w-100 fw-bold">Update GSP</button></div></div></form></div></div></div></div>

<div class="container-fluid p-0">
    <div class="alert alert-danger shadow-sm border-danger d-flex align-items-center mb-4">
        <i class="fas fa-trash-alt fs-4 me-3"></i>
        <div><strong>PEMBERITAHUAN SISTEM:</strong> Data Pengajuan Selesai > 30 Hari dihapus otomatis.</div>
    </div>

    <!-- FILTER -->
    <div class="card shadow-sm mb-4">
        <div class="card-header bg-white py-3 d-flex justify-content-between align-items-center">
            <h5 class="mb-0 fw-bold text-primary"><i class="fas fa-inbox me-2"></i> Inbox Semua Pengajuan</h5>
            <?php if($can_approve): ?>
            <div class="d-flex gap-2">
                <a href="?export_excel=true&<?php echo http_build_query($_GET); ?>" class="btn btn-success btn-sm"><i class="fas fa-file-excel me-1"></i> Export Excel (.xlsx - seluruh kolom)</a>
                <a href="?export_excel=1&diagnosa=1" target="_blank" class="btn btn-outline-secondary btn-sm" title="Periksa kesiapan export di hosting"><i class="fas fa-stethoscope me-1"></i> Periksa Export</a>
            </div>
            <?php endif; ?>
        </div>
        <div class="card-body bg-light">
            <form method="GET" class="row g-2">
                <div class="col-md-2"><input type="date" name="f_start" class="form-control form-control-sm" value="<?= $f_start ?>"></div>
                <div class="col-md-2"><input type="date" name="f_end" class="form-control form-control-sm" value="<?= $f_end ?>"></div>
                <div class="col-md-2"><select name="f_status" class="form-select form-select-sm"><option value="">- Semua Status -</option><option value="Pending">Pending</option><option value="Disetujui">Disetujui</option><option value="Ditolak">Ditolak</option></select></div>
                <div class="col-md-4"><input type="text" name="f_keyword" class="form-control form-control-sm" value="<?= $f_key ?>" placeholder="Cari Nama Toko / Sales..."></div>
                <div class="col-md-2"><button class="btn btn-primary btn-sm w-100">Filter</button></div>
            </form>
        </div>
    </div>

    <!-- TABEL DATA -->
    <div class="card shadow-sm border-0">
        <form method="POST" id="bulkForm">
        <div class="card-body p-0 table-responsive">
            
            <?php if($can_approve): ?>
            <div class="p-2 bg-light border-bottom d-flex gap-2">
                <small class="text-muted align-self-center me-2"><i class="fas fa-level-up-alt fa-rotate-90"></i> Yang ditandai:</small>
                <button type="submit" name="bulk_action" value="approve_all" class="btn btn-sm btn-success" onclick="return confirm('Setujui semua?')">Setujui</button>
                <button type="submit" name="bulk_action" value="reject_all" class="btn btn-sm btn-danger" onclick="return confirm('Tolak semua?')">Tolak</button>
            </div>
            <?php endif; ?>

            <table class="table table-hover align-middle mb-0 text-nowrap small">
                <thead class="table-light">
                    <tr>
                        <?php if($can_approve): ?><th width="1"><input type="checkbox" id="checkAll"></th><?php endif; ?>
                        <th>Tanggal</th><th>Tipe</th><th>Salesman</th><th>Detail Pengajuan</th><th>Status</th><th>Diproses</th><th class="text-end">Aksi</th>
                    </tr>
                </thead>
                <tbody>
                    <?php
                    // GABUNGKAN DATA
                    $data_gabungan = [];
                    $res_toko = $conn->query($sql_toko);
                    while($r = $res_toko->fetch_assoc()) {
                        $r['tipe_label'] = '<span class="badge bg-info text-dark">Reguler</span>';
                        $r['judul'] = $r['jenis_request'];
                        $id_show = $r['id_customer'] ? "<span class='badge bg-light text-dark border ms-1'>ID: ".$r['id_customer']."</span>" : "";
                        $r['detail'] = ($r['nama_toko_baru'] ?: $r['nama_toko_lama']) . $id_show . "<br><span class='text-muted'>".$r['alamat_baru']."</span>";
                        $r['data_type'] = 'Toko';
                        $data_gabungan[] = $r;
                    }
                    $res_gsp = $conn->query($sql_gsp);
                    while($r = $res_gsp->fetch_assoc()) {
                        $r['tipe_label'] = '<span class="badge bg-warning text-dark">GSP</span>';
                        $r['judul'] = "Pergantian GSP";
                        $r['detail'] = "<span class='text-danger'>Putus: ".$r['toko_lama_nama']."</span><br><span class='text-success'>Ganti: ".$r['toko_baru_nama']."</span>";
                        $r['data_type'] = 'GSP';
                        $data_gabungan[] = $r;
                    }
                    usort($data_gabungan, function($a, $b) { return strtotime($b['tanggal_request']) - strtotime($a['tanggal_request']); });

                    if (count($data_gabungan) > 0): foreach ($data_gabungan as $row):
                    ?>
                    <tr>
                        <?php if($can_approve): ?>
                        <td><?php if($row['status_approval'] == 'Pending'): ?><input type="checkbox" name="req_ids[]" value="<?= $row['id'] ?>:<?= $row['data_type'] ?>" class="row-check"><?php endif; ?></td>
                        <?php endif; ?>
                        
                        <td><div class="fw-bold"><?= date('d/m/y', strtotime($row['tanggal_request'])) ?></div><div class="text-muted"><?= date('H:i', strtotime($row['tanggal_request'])) ?></div></td>
                        <td><?= $row['tipe_label'] ?></td>
                        <td><div class="fw-bold"><?= $row['salesman'] ?></div><div class="text-muted"><?= $row['sales_district'] ?? $row['sales_distric'] ?></div></td>
                        <td><div class="fw-bold text-primary"><?= $row['judul'] ?></div><div><?= $row['detail'] ?></div></td>
                        <td><span class="badge bg-<?= $row['status_approval']=='Disetujui'?'success':($row['status_approval']=='Ditolak'?'danger':'warning') ?>"><?= $row['status_approval'] ?></span></td>
                        <td><?php if (!empty($row['processed_by'])): ?><span class="fw-semibold"><?= htmlspecialchars($row['processed_by']) ?></span><br><small class="text-muted"><?= !empty($row['processed_at']) ? date('d/m/y H:i', strtotime($row['processed_at'])) : '' ?></small><?php if (!empty($row['approval_note'])): ?><br><small title="<?= htmlspecialchars($row['approval_note']) ?>" class="text-muted"><i class="fas fa-comment"></i> <?= htmlspecialchars(mb_strimwidth($row['approval_note'], 0, 35, '...')) ?></small><?php endif; ?><?php else: ?><span class="text-muted">Belum diproses</span><?php endif; ?></td>
                        <td class="text-end">
                            <?php if($row['data_type'] == 'GSP'): ?>
                                <button type="button" onclick='viewGSP(<?= json_encode($row, JSON_HEX_APOS|JSON_HEX_QUOT) ?>)' class="btn btn-xs btn-outline-info" title="Detail"><i class="fas fa-eye"></i></button>
                            <?php endif; ?>

                            <!-- TOMBOL EDIT -->
                            <?php if($can_approve || $row['status_approval'] == 'Pending'): ?>
                                <?php if($row['data_type'] == 'GSP'): ?>
                                    <button type="button" onclick='editGSPData(<?= json_encode($row, JSON_HEX_APOS|JSON_HEX_QUOT) ?>)' class="btn btn-xs btn-warning text-dark"><i class="fas fa-pencil-alt"></i></button>
                                <?php else: ?>
                                    <button type="button" onclick='editTokoData(<?= json_encode($row, JSON_HEX_APOS|JSON_HEX_QUOT) ?>)' class="btn btn-xs btn-warning text-dark"><i class="fas fa-pencil-alt"></i></button>
                                <?php endif; ?>
                            <?php endif; ?>

                            <!-- ACTION ADMIN -->
                            <?php if($can_approve): ?>
                                <?php if($row['status_approval'] == 'Pending'): ?>
                                <button type="submit" form="singleAct<?= $row['data_type'].$row['id'] ?>" name="action_type" value="approve" class="btn btn-xs btn-success" title="Setujui" onclick="return askApprovalNote(this.form, 'Setujui')">✔</button>
                                <button type="submit" form="singleAct<?= $row['data_type'].$row['id'] ?>" name="action_type" value="reject" class="btn btn-xs btn-danger" title="Tolak" onclick="return askApprovalNote(this.form, 'Ditolak')">✖</button>
                                <?php endif; ?>
                                <button type="submit" form="singleAct<?= $row['data_type'].$row['id'] ?>" name="action_type" value="delete" class="btn btn-xs btn-dark" title="Hapus" onclick="return confirm('Hapus Permanen?')"><i class="fas fa-trash"></i></button>
                            
                            <!-- ACTION SALES -->
                            <?php elseif($row['status_approval'] == 'Pending'): ?>
                                <button type="submit" form="singleAct<?= $row['data_type'].$row['id'] ?>" name="action_type" value="delete" class="btn btn-xs btn-danger" title="Batalkan" onclick="return confirm('Batalkan?')"><i class="fas fa-trash"></i></button>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; else: ?><tr><td colspan="7" class="text-center py-5 text-muted">Belum ada data.</td></tr><?php endif; ?>
                </tbody>
            </table>
        </div>
        </form>

        <?php foreach ($data_gabungan as $row): ?>
        <form method="POST" id="singleAct<?= $row['data_type'].$row['id'] ?>" style="display:none;">
            <input type="hidden" name="req_id" value="<?= $row['id'] ?>"><input type="hidden" name="data_type" value="<?= $row['data_type'] ?>">
        </form>
        <?php endforeach; ?>
    </div>
</div>

<script>
function askApprovalNote(form, action) {
    const note = prompt('Catatan ' + action + ' (opsional):', '');
    if (note === null) return false;
    let input = form.querySelector('input[name="approval_note"]');
    if (!input) { input = document.createElement('input'); input.type = 'hidden'; input.name = 'approval_note'; form.appendChild(input); }
    input.value = note;
    return true;
}

document.getElementById('checkAll')?.addEventListener('change', function() {
    var checkboxes = document.querySelectorAll('.row-check');
    for (var checkbox of checkboxes) { checkbox.checked = this.checked; }
});

function viewGSP(data) {
    document.getElementById('d_salesman').innerText = data.salesman;
    document.getElementById('d_district').innerText = data.sales_district;
    document.getElementById('d_toko_lama').innerText = data.toko_lama_nama + " (" + data.toko_lama_id + ")";
    document.getElementById('d_toko_baru').innerText = data.toko_baru_nama + " (" + data.toko_baru_id + ")";
    document.getElementById('d_alamat').innerText = data.alamat_lengkap;
    document.getElementById('d_pic').innerText = data.pic_nama;
    document.getElementById('d_hp').innerText = data.nomor_hp;
    document.getElementById('d_status').innerText = data.status_approval || 'Pending';
    document.getElementById('d_processed').innerText = data.processed_by ? (data.processed_by + ' - ' + (data.processed_at || '')) : 'Belum diproses';
    document.getElementById('d_note').innerText = data.approval_note || '-';
    document.getElementById('d_maps').href = "https://www.google.com/maps/search/?api=1&query=" + data.koordinat;
    
    // --- FITUR BARU: AUTO SPLIT KOORDINAT ---
    let lat = "-";
    let long = "-";
    if (data.koordinat && data.koordinat.includes(',')) {
        const split = data.koordinat.split(',');
        lat = split[0].trim();
        long = split[1].trim();
    } else if (data.koordinat) {
        lat = data.koordinat; // Fallback jika format beda
    }
    document.getElementById('d_lat').innerText = lat;
    document.getElementById('d_long').innerText = long;

    const noImg = 'https://via.placeholder.com/150?text=No+Image';
    document.getElementById('img_ktp').src = data.link_foto_ktp || noImg;
    document.getElementById('img_luar').src = data.link_foto_luar || noImg;
    document.getElementById('img_dalam').src = data.link_foto_dalam || noImg;
    new bootstrap.Modal(document.getElementById('gspDetailModal')).show();
}

function editTokoData(data) {
    document.getElementById('et_id').value = data.id;
    document.getElementById('et_salesman').value = data.salesman;
    document.getElementById('et_dist').value = data.sales_distric;
    document.getElementById('et_jenis').value = data.jenis_request;
    document.getElementById('et_id_cust').value = data.id_customer;
    document.getElementById('et_nm_lama').value = data.nama_toko_lama;
    document.getElementById('et_nm_baru').value = data.nama_toko_baru;
    document.getElementById('et_al_lama').value = data.alamat_lama;
    document.getElementById('et_al_baru').value = data.alamat_baru;
    document.getElementById('et_pic').value = data.pic;
    document.getElementById('et_rute').value = data.rute_kunjungan;
    document.getElementById('et_week').value = data.week;
    document.getElementById('et_alasan').value = data.alasan;
    new bootstrap.Modal(document.getElementById('editTokoModal')).show();
}

function editGSPData(data) {
    document.getElementById('eg_id').value = data.id;
    document.getElementById('eg_salesman').value = data.salesman;
    document.getElementById('eg_dist').value = data.sales_district;
    document.getElementById('eg_nm_lama').value = data.toko_lama_nama;
    document.getElementById('eg_id_lama').value = data.toko_lama_id;
    document.getElementById('eg_nm_baru').value = data.toko_baru_nama;
    document.getElementById('eg_id_baru').value = data.toko_baru_id;
    document.getElementById('eg_alamat').value = data.alamat_lengkap;
    document.getElementById('eg_pic').value = data.pic_nama;
    document.getElementById('eg_hp').value = data.nomor_hp;
    document.getElementById('eg_koor').value = data.koordinat;
    document.getElementById('eg_old_ktp').value = data.link_foto_ktp;
    document.getElementById('eg_old_luar').value = data.link_foto_luar;
    document.getElementById('eg_old_dalam').value = data.link_foto_dalam;
    new bootstrap.Modal(document.getElementById('editGspModal')).show();
}
</script>

<?php require_once 'footer.php'; ?>