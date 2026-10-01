<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - INTI BARANG BAWAAN & KASIR  (FITUR PRO)
 *  Berkas : api/kasir_inti.php
 *  Versi  : 1   (1 Oktober 2026)
 *
 *  KEGUNAAN
 *  --------
 *  Seluruh aturan fitur "Barang Bawaan" dan "Kasir" untuk sales canvasser
 *  PT. Wismilak Inti Makmur (rokok dijual per PACK dan per BATANG):
 *
 *     PRODUK   : daftar barang yang dibawa (nama, barcode, isi per pack, harga)
 *     STOK     : saldo bawaan per sales + riwayat setiap perubahan
 *     KASIR    : nota penjualan, stok otomatis berkurang, nomor nota
 *     BAYAR    : CASH (tunai), UTANG (dibayar kemudian), TITIP (barang dititipkan)
 *     PIUTANG  : daftar utang & titipan yang dapat diperbarui sampai lunas
 *     STRUK    : template struk yang dapat diubah bebas oleh setiap sales
 *
 *  DIPAKAI OLEH
 *  ------------
 *     api/kasir.php  (seluruh permintaan dari aplikasi Android)
 *
 *  SUSUNAN TABEL  (semuanya berawalan rts_ks_)
 *  ------------------------------------------
 *     rts_ks_produk          master produk + barcode
 *     rts_ks_harga           harga khusus per sales (opsional)
 *     rts_ks_stok            saldo stok bawaan (pack + batang)
 *     rts_ks_stok_gerak      riwayat perubahan stok
 *     rts_ks_penjualan       nota kasir
 *     rts_ks_penjualan_item  barang pada setiap nota
 *     rts_ks_piutang         utang & titip
 *     rts_ks_piutang_bayar   angsuran / pelunasan
 *     rts_ks_struk           template struk per sales
 *     rts_ks_setelan         setelan umum (misalnya masa perkenalan)
 *     rts_ks_penomoran       nomor nota harian
 *
 *  SIFATNYA AMAN GAGAL
 *  -------------------
 *  Seluruh fungsi memeriksa lebih dahulu apakah tabelnya sudah ada. Bila
 *  belum, fungsi mengembalikan keterangan yang jelas (bukan kesalahan PHP),
 *  sehingga aplikasi tetap berjalan dan menampilkan tombol
 *  "SIAPKAN DATA KASIR" kepada ADMIN.
 *
 *  CATATAN: tidak memakai tabel information_schema (akun database cPanel
 *  sering tidak diberi izin membacanya - kesalahan #1044). Pemeriksaan tabel
 *  dan kolom memakai SHOW TABLES / SHOW COLUMNS.
 * ============================================================================
 */

if (!defined('RTS_KS_VERSI')) {
    define('RTS_KS_VERSI', 1);
}

/* ==========================================================================
 *  BAGIAN 1 - SUSUNAN TABEL
 * ========================================================================== */

/**
 * Nama seluruh tabel kasir.
 *
 * @return string[]
 */
function rts_ks_tabel(): array
{
    return [
        'rts_ks_produk',
        'rts_ks_harga',
        'rts_ks_stok',
        'rts_ks_stok_gerak',
        'rts_ks_penjualan',
        'rts_ks_penjualan_item',
        'rts_ks_piutang',
        'rts_ks_piutang_bayar',
        'rts_ks_struk',
        'rts_ks_setelan',
        'rts_ks_penomoran',
    ];
}

/**
 * Perintah pembuatan seluruh tabel.
 * Susunannya sama dengan berkas database/migrations/RTS_PANEL_KASIR.sql.
 *
 * @return array<string,string>
 */
function rts_ks_perintah_tabel(): array
{
    $opsi = ' ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';

    return [
        'rts_ks_produk' => 'CREATE TABLE IF NOT EXISTS rts_ks_produk (
            id INT AUTO_INCREMENT PRIMARY KEY,
            barcode_pack VARCHAR(64) NULL,
            barcode_batang VARCHAR(64) NULL,
            nama VARCHAR(150) NOT NULL,
            merek VARCHAR(80) NOT NULL DEFAULT \'\',
            isi_per_pack INT NOT NULL DEFAULT 0,
            harga_pack DECIMAL(14,2) NOT NULL DEFAULT 0,
            harga_batang DECIMAL(14,2) NOT NULL DEFAULT 0,
            foto VARCHAR(255) NOT NULL DEFAULT \'\',
            aktif TINYINT(1) NOT NULL DEFAULT 1,
            dibuat_oleh VARCHAR(60) NOT NULL DEFAULT \'\',
            dibuat_pada DATETIME NULL,
            diubah_oleh VARCHAR(60) NOT NULL DEFAULT \'\',
            diubah_pada DATETIME NULL,
            catatan VARCHAR(255) NOT NULL DEFAULT \'\',
            UNIQUE KEY rts_ks_produk_barcode_pack (barcode_pack),
            UNIQUE KEY rts_ks_produk_barcode_batang (barcode_batang),
            KEY rts_ks_produk_nama (nama)
        )' . $opsi,

        'rts_ks_harga' => 'CREATE TABLE IF NOT EXISTS rts_ks_harga (
            id INT AUTO_INCREMENT PRIMARY KEY,
            produk_id INT NOT NULL,
            id_sales VARCHAR(60) NOT NULL,
            harga_pack DECIMAL(14,2) NULL,
            harga_batang DECIMAL(14,2) NULL,
            diperbarui DATETIME NULL,
            UNIQUE KEY rts_ks_harga_sales (produk_id, id_sales)
        )' . $opsi,

        'rts_ks_stok' => 'CREATE TABLE IF NOT EXISTS rts_ks_stok (
            id INT AUTO_INCREMENT PRIMARY KEY,
            id_sales VARCHAR(60) NOT NULL,
            produk_id INT NOT NULL,
            pack INT NOT NULL DEFAULT 0,
            batang INT NOT NULL DEFAULT 0,
            diubah DATETIME NULL,
            UNIQUE KEY rts_ks_stok_sales (id_sales, produk_id)
        )' . $opsi,

        'rts_ks_stok_gerak' => 'CREATE TABLE IF NOT EXISTS rts_ks_stok_gerak (
            id INT AUTO_INCREMENT PRIMARY KEY,
            tanggal DATETIME NOT NULL,
            id_sales VARCHAR(60) NOT NULL,
            nama_sales VARCHAR(100) NOT NULL DEFAULT \'\',
            produk_id INT NOT NULL,
            jenis VARCHAR(12) NOT NULL,
            pack_delta INT NOT NULL DEFAULT 0,
            batang_delta INT NOT NULL DEFAULT 0,
            saldo_pack INT NOT NULL DEFAULT 0,
            saldo_batang INT NOT NULL DEFAULT 0,
            keterangan VARCHAR(255) NOT NULL DEFAULT \'\',
            ref_tipe VARCHAR(12) NOT NULL DEFAULT \'\',
            ref_id INT NOT NULL DEFAULT 0,
            KEY rts_ks_gerak_sales (id_sales, tanggal),
            KEY rts_ks_gerak_produk (produk_id)
        )' . $opsi,

        'rts_ks_penjualan' => 'CREATE TABLE IF NOT EXISTS rts_ks_penjualan (
            id INT AUTO_INCREMENT PRIMARY KEY,
            nomor VARCHAR(30) NOT NULL,
            tanggal DATETIME NOT NULL,
            id_sales VARCHAR(60) NOT NULL,
            nama_sales VARCHAR(100) NOT NULL DEFAULT \'\',
            role VARCHAR(20) NOT NULL DEFAULT \'\',
            district VARCHAR(60) NOT NULL DEFAULT \'\',
            jenis_customer VARCHAR(20) NOT NULL DEFAULT \'REGULER\',
            customer_id VARCHAR(40) NOT NULL DEFAULT \'\',
            nama_customer VARCHAR(150) NOT NULL DEFAULT \'\',
            hp_customer VARCHAR(30) NOT NULL DEFAULT \'\',
            alamat_customer VARCHAR(255) NOT NULL DEFAULT \'\',
            metode VARCHAR(10) NOT NULL DEFAULT \'CASH\',
            total DECIMAL(14,2) NOT NULL DEFAULT 0,
            bayar DECIMAL(14,2) NOT NULL DEFAULT 0,
            kembali DECIMAL(14,2) NOT NULL DEFAULT 0,
            status VARCHAR(12) NOT NULL DEFAULT \'LUNAS\',
            jumlah_item INT NOT NULL DEFAULT 0,
            catatan VARCHAR(255) NOT NULL DEFAULT \'\',
            foto VARCHAR(255) NOT NULL DEFAULT \'\',
            dicetak INT NOT NULL DEFAULT 0,
            cetak_terakhir DATETIME NULL,
            dibatalkan TINYINT(1) NOT NULL DEFAULT 0,
            batal_alasan VARCHAR(255) NOT NULL DEFAULT \'\',
            batal_oleh VARCHAR(60) NOT NULL DEFAULT \'\',
            batal_pada DATETIME NULL,
            dibuat_pada DATETIME NULL,
            UNIQUE KEY rts_ks_jual_nomor (nomor),
            KEY rts_ks_jual_sales (id_sales, tanggal),
            KEY rts_ks_jual_customer (customer_id)
        )' . $opsi,

        'rts_ks_penjualan_item' => 'CREATE TABLE IF NOT EXISTS rts_ks_penjualan_item (
            id INT AUTO_INCREMENT PRIMARY KEY,
            penjualan_id INT NOT NULL,
            produk_id INT NOT NULL,
            barcode VARCHAR(64) NOT NULL DEFAULT \'\',
            nama_produk VARCHAR(150) NOT NULL,
            satuan VARCHAR(10) NOT NULL DEFAULT \'PACK\',
            isi_per_pack INT NOT NULL DEFAULT 0,
            pack INT NOT NULL DEFAULT 0,
            batang INT NOT NULL DEFAULT 0,
            harga_satuan DECIMAL(14,2) NOT NULL DEFAULT 0,
            subtotal DECIMAL(14,2) NOT NULL DEFAULT 0,
            KEY rts_ks_item_nota (penjualan_id),
            KEY rts_ks_item_produk (produk_id)
        )' . $opsi,

        'rts_ks_piutang' => 'CREATE TABLE IF NOT EXISTS rts_ks_piutang (
            id INT AUTO_INCREMENT PRIMARY KEY,
            nomor VARCHAR(30) NOT NULL,
            jenis VARCHAR(10) NOT NULL DEFAULT \'UTANG\',
            penjualan_id INT NOT NULL DEFAULT 0,
            tanggal DATETIME NOT NULL,
            jatuh_tempo DATE NULL,
            id_sales VARCHAR(60) NOT NULL,
            nama_sales VARCHAR(100) NOT NULL DEFAULT \'\',
            district VARCHAR(60) NOT NULL DEFAULT \'\',
            customer_id VARCHAR(40) NOT NULL DEFAULT \'\',
            nama_customer VARCHAR(150) NOT NULL DEFAULT \'\',
            hp_customer VARCHAR(30) NOT NULL DEFAULT \'\',
            total DECIMAL(14,2) NOT NULL DEFAULT 0,
            dibayar DECIMAL(14,2) NOT NULL DEFAULT 0,
            sisa DECIMAL(14,2) NOT NULL DEFAULT 0,
            status VARCHAR(12) NOT NULL DEFAULT \'BELUM\',
            rincian TEXT NULL,
            catatan VARCHAR(255) NOT NULL DEFAULT \'\',
            foto VARCHAR(255) NOT NULL DEFAULT \'\',
            diperbarui DATETIME NULL,
            UNIQUE KEY rts_ks_piut_nomor (nomor),
            KEY rts_ks_piut_sales (id_sales, status),
            KEY rts_ks_piut_customer (customer_id)
        )' . $opsi,

        'rts_ks_piutang_bayar' => 'CREATE TABLE IF NOT EXISTS rts_ks_piutang_bayar (
            id INT AUTO_INCREMENT PRIMARY KEY,
            piutang_id INT NOT NULL,
            tanggal DATETIME NOT NULL,
            jumlah DECIMAL(14,2) NOT NULL DEFAULT 0,
            metode VARCHAR(12) NOT NULL DEFAULT \'CASH\',
            diterima_oleh VARCHAR(60) NOT NULL DEFAULT \'\',
            nama_penerima VARCHAR(100) NOT NULL DEFAULT \'\',
            catatan VARCHAR(255) NOT NULL DEFAULT \'\',
            sisa_sesudah DECIMAL(14,2) NOT NULL DEFAULT 0,
            KEY rts_ks_bayar_piut (piutang_id)
        )' . $opsi,

        'rts_ks_struk' => 'CREATE TABLE IF NOT EXISTS rts_ks_struk (
            id INT AUTO_INCREMENT PRIMARY KEY,
            id_sales VARCHAR(60) NOT NULL,
            judul VARCHAR(60) NOT NULL DEFAULT \'RTS PANEL\',
            baris1 VARCHAR(120) NOT NULL DEFAULT \'\',
            baris2 VARCHAR(120) NOT NULL DEFAULT \'\',
            baris3 VARCHAR(120) NOT NULL DEFAULT \'\',
            footer1 VARCHAR(120) NOT NULL DEFAULT \'Terima kasih\',
            footer2 VARCHAR(120) NOT NULL DEFAULT \'\',
            footer3 VARCHAR(120) NOT NULL DEFAULT \'\',
            lebar_kertas INT NOT NULL DEFAULT 58,
            ukuran_huruf VARCHAR(10) NOT NULL DEFAULT \'SEDANG\',
            tampilkan_barcode TINYINT(1) NOT NULL DEFAULT 1,
            tampilkan_hp TINYINT(1) NOT NULL DEFAULT 1,
            tampilkan_ttd TINYINT(1) NOT NULL DEFAULT 0,
            tampilkan_qris TINYINT(1) NOT NULL DEFAULT 0,
            tampilkan_diskon TINYINT(1) NOT NULL DEFAULT 1,
            tampilkan_metode TINYINT(1) NOT NULL DEFAULT 1,
            header_tebal TINYINT(1) NOT NULL DEFAULT 1,
            garis VARCHAR(3) NOT NULL DEFAULT \'-\',
            jumlah_salinan INT NOT NULL DEFAULT 1,
            catatan_kaki VARCHAR(120) NOT NULL DEFAULT \'\',
            diperbarui DATETIME NULL,
            UNIQUE KEY rts_ks_struk_sales (id_sales)
        )' . $opsi,

        'rts_ks_setelan' => 'CREATE TABLE IF NOT EXISTS rts_ks_setelan (
            id INT AUTO_INCREMENT PRIMARY KEY,
            kunci VARCHAR(40) NOT NULL,
            nilai VARCHAR(255) NOT NULL DEFAULT \'\',
            diperbarui DATETIME NULL,
            UNIQUE KEY rts_ks_setelan_kunci (kunci)
        )' . $opsi,

        'rts_ks_penomoran' => 'CREATE TABLE IF NOT EXISTS rts_ks_penomoran (
            id INT AUTO_INCREMENT PRIMARY KEY,
            tanggal DATE NOT NULL,
            prefix VARCHAR(6) NOT NULL,
            urut INT NOT NULL DEFAULT 0,
            UNIQUE KEY rts_ks_penomoran_hari (tanggal, prefix)
        )' . $opsi,
    ];
}

/**
 * Memeriksa keberadaan sebuah tabel (memakai SHOW TABLES, bukan
 * information_schema).
 */
function rts_ks_ada_tabel(mysqli $conn, string $nama): bool
{
    static $simpanan = [];

    if (array_key_exists($nama, $simpanan)) {
        return $simpanan[$nama];
    }

    if (preg_match('/^[A-Za-z0-9_]+$/', $nama) !== 1) {
        $simpanan[$nama] = false;

        return false;
    }

    $hasil = @$conn->query('SHOW TABLES LIKE \'' . $conn->real_escape_string($nama) . '\'');

    $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

    if ($hasil instanceof mysqli_result) {
        $hasil->free();
    }

    $simpanan[$nama] = $ada;

    return $ada;
}

/**
 * Apakah seluruh tabel kasir sudah ada?
 */
function rts_ks_siap(mysqli $conn): bool
{
    foreach (rts_ks_tabel() as $nama) {
        if (!rts_ks_ada_tabel($conn, $nama)) {
            return false;
        }
    }

    return true;
}

/**
 * Membuat seluruh tabel yang belum ada.
 *
 * @return array{ok:bool,dibuat:string[],gagal:array<string,string>,pesan:string}
 */
function rts_ks_siapkan_database(mysqli $conn): array
{
    $dibuat = [];
    $gagal = [];

    foreach (rts_ks_perintah_tabel() as $nama => $sql) {
        if (rts_ks_ada_tabel($conn, $nama)) {
            continue;
        }

        if (@$conn->query($sql)) {
            $dibuat[] = $nama;
        } else {
            $gagal[$nama] = $conn->error;
        }
    }

    // Penanda versi susunan tabel, dipakai bila nanti ada penambahan kolom.
    rts_ks_setelan_tulis($conn, 'versi_tabel', (string) RTS_KS_VERSI);

    $ok = count($gagal) === 0;

    if ($ok && count($dibuat) === 0) {
        $pesan = 'Data kasir sudah siap dipakai (tidak ada tabel baru yang perlu dibuat).';
    } elseif ($ok) {
        $pesan = 'Selesai. ' . count($dibuat) . ' tabel baru dibuat.';
    } else {
        $pesan = 'Sebagian tabel gagal dibuat. Periksa hak akun database Anda.';
    }

    return ['ok' => $ok, 'dibuat' => $dibuat, 'gagal' => $gagal, 'pesan' => $pesan];
}

/* ==========================================================================
 *  BAGIAN 2 - BANTUAN UMUM
 * ========================================================================== */

/**
 * Membaca angka dari ketikan pengguna. Menerima "32.000", "32000", "Rp 32.000",
 * maupun "32000,50" dan mengembalikan nilainya sebagai angka.
 */
function rts_ks_angka($nilai): float
{
    if (is_int($nilai) || is_float($nilai)) {
        return (float) $nilai;
    }

    $teks = trim((string) $nilai);

    if ($teks === '') {
        return 0.0;
    }

    $teks = (string) preg_replace('/[^0-9,.\-]/', '', $teks);

    if ($teks === '' || $teks === '-') {
        return 0.0;
    }

    if (strpos($teks, ',') !== false) {
        // Koma dipakai sebagai pemisah desimal (cara Indonesia).
        $teks = str_replace('.', '', $teks);
        $teks = str_replace(',', '.', $teks);
    } else {
        $bagian = explode('.', $teks);

        if (count($bagian) > 1 && strlen((string) end($bagian)) === 3) {
            // Titik dipakai sebagai pemisah ribuan: 32.000 -> 32000
            $teks = implode('', $bagian);
        }
    }

    return (float) $teks;
}

/**
 * Membaca angka bulat (misalnya jumlah pack / batang).
 */
function rts_ks_bulat($nilai): int
{
    return (int) round(rts_ks_angka($nilai));
}

/**
 * Menyusun tulisan rupiah untuk ditampilkan pada pesan/struk.
 * Contoh: 32000 -> "32.000"
 */
function rts_ks_uang($nilai): string
{
    $angka = rts_ks_angka($nilai);

    if (abs($angka - round($angka)) < 0.005) {
        return number_format(round($angka), 0, ',', '.');
    }

    return number_format($angka, 2, ',', '.');
}

/**
 * Membersihkan teks masukan (satu baris).
 */
function rts_ks_teks($nilai, int $maks = 150): string
{
    $teks = trim((string) $nilai);
    $teks = (string) preg_replace('/\s+/u', ' ', $teks);

    if (function_exists('mb_substr')) {
        return mb_substr($teks, 0, $maks, 'UTF-8');
    }

    return substr($teks, 0, $maks);
}

/**
 * Identitas sales dari data pengguna yang sedang login.
 * Dipakai sebagai kunci stok, harga khusus, nota, dan template struk.
 */
function rts_ks_sales_id(array $user): string
{
    $id = rts_ks_teks($user['username'] ?? '', 60);

    if ($id === '') {
        $id = 'user-' . (int) ($user['id'] ?? 0);
    }

    return $id;
}

/**
 * Nama tampilan sales.
 */
function rts_ks_nama_sales(array $user): string
{
    $nama = rts_ks_teks($user['nama_lengkap'] ?? '', 100);

    if ($nama === '') {
        $nama = rts_ks_teks($user['username'] ?? '', 100);
    }

    return $nama;
}

/**
 * Apakah pengguna berhak melihat data seluruh sales (bukan hanya dirinya).
 */
function rts_ks_boleh_semua(array $user): bool
{
    $role = strtoupper((string) ($user['role'] ?? ''));

    return in_array($role, ['ADMIN', 'ASS', 'WSS', 'SMST'], true);
}

/**
 * Waktu sekarang dalam bentuk Y-m-d H:i:s.
 */
function rts_ks_sekarang(): string
{
    return date('Y-m-d H:i:s');
}

/**
 * Membaca setelan umum.
 */
function rts_ks_setelan_baca(mysqli $conn, string $kunci, string $bawaan = ''): string
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_setelan')) {
        return $bawaan;
    }

    $stmt = $conn->prepare('SELECT nilai FROM rts_ks_setelan WHERE kunci = ? LIMIT 1');

    if (!$stmt) {
        return $bawaan;
    }

    $stmt->bind_param('s', $kunci);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return $bawaan;
    }

    $nilai = trim((string) $baris['nilai']);

    return $nilai === '' ? $bawaan : $nilai;
}

/**
 * Menyimpan setelan umum.
 */
function rts_ks_setelan_tulis(mysqli $conn, string $kunci, string $nilai): bool
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_setelan')) {
        return false;
    }

    $stmt = $conn->prepare(
        'INSERT INTO rts_ks_setelan (kunci, nilai, diperbarui) VALUES (?, ?, NOW())
         ON DUPLICATE KEY UPDATE nilai = ?, diperbarui = NOW()'
    );

    if (!$stmt) {
        return false;
    }

    $stmt->bind_param('sss', $kunci, $nilai, $nilai);
    $ok = $stmt->execute();
    $stmt->close();

    return (bool) $ok;
}

/**
 * Membuat nomor dokumen harian, contoh: KS-20261001-0007
 *
 * Harus dipanggil di dalam transaksi agar nomor tidak kembar.
 */
function rts_ks_nomor(mysqli $conn, string $prefix, string $tanggal = ''): string
{
    $hari = $tanggal !== '' ? date('Y-m-d', strtotime($tanggal)) : date('Y-m-d');
    $kunci = date('Ymd', strtotime($hari));

    $stmt = $conn->prepare(
        'INSERT IGNORE INTO rts_ks_penomoran (tanggal, prefix, urut) VALUES (?, ?, 0)'
    );

    if ($stmt) {
        $stmt->bind_param('ss', $hari, $prefix);
        $stmt->execute();
        $stmt->close();
    }

    $stmt = $conn->prepare(
        'UPDATE rts_ks_penomoran SET urut = urut + 1 WHERE tanggal = ? AND prefix = ?'
    );

    if ($stmt) {
        $stmt->bind_param('ss', $hari, $prefix);
        $stmt->execute();
        $stmt->close();
    }

    $urut = 1;
    $stmt = $conn->prepare(
        'SELECT urut FROM rts_ks_penomoran WHERE tanggal = ? AND prefix = ? LIMIT 1'
    );

    if ($stmt) {
        $stmt->bind_param('ss', $hari, $prefix);
        $stmt->execute();
        $hasil = $stmt->get_result();
        $baris = $hasil ? $hasil->fetch_assoc() : null;
        $stmt->close();

        if ($baris) {
            $urut = max(1, (int) $baris['urut']);
        }
    }

    return strtoupper($prefix) . '-' . $kunci . '-' . str_pad((string) $urut, 4, '0', STR_PAD_LEFT);
}

/* ==========================================================================
 *  BAGIAN 3 - PRODUK
 * ========================================================================== */

/**
 * Menyusun data produk menjadi bentuk yang dipakai aplikasi.
 *
 * @param array<string,mixed> $baris
 * @return array<string,mixed>
 */
function rts_ks_produk_bentuk(array $baris, string $idSales = ''): array
{
    $isi = (int) ($baris['isi_per_pack'] ?? 0);

    $hargaPack = rts_ks_angka($baris['harga_pack'] ?? 0);
    $hargaBatang = rts_ks_angka($baris['harga_batang'] ?? 0);

    if (array_key_exists('khusus_pack', $baris) && $baris['khusus_pack'] !== null) {
        $hargaPack = rts_ks_angka($baris['khusus_pack']);
    }

    if (array_key_exists('khusus_batang', $baris) && $baris['khusus_batang'] !== null) {
        $hargaBatang = rts_ks_angka($baris['khusus_batang']);
    }

    if ($hargaBatang <= 0 && $isi > 0 && $hargaPack > 0) {
        // Belum ada harga batang: dihitung otomatis, dibulatkan ke ratusan.
        $hargaBatang = round(($hargaPack / $isi) / 100) * 100;
    }

    return [
        'id' => (int) ($baris['id'] ?? 0),
        'barcode_pack' => (string) ($baris['barcode_pack'] ?? ''),
        'barcode_batang' => (string) ($baris['barcode_batang'] ?? ''),
        'nama' => (string) ($baris['nama'] ?? ''),
        'merek' => (string) ($baris['merek'] ?? ''),
        'isi_per_pack' => $isi,
        'harga_pack' => $hargaPack,
        'harga_batang' => $hargaBatang,
        'harga_pack_teks' => rts_ks_uang($hargaPack),
        'harga_batang_teks' => rts_ks_uang($hargaBatang),
        'foto' => (string) ($baris['foto'] ?? ''),
        'aktif' => (int) ($baris['aktif'] ?? 1) === 1,
        'catatan' => (string) ($baris['catatan'] ?? ''),
    ];
}

/**
 * Mencari produk (nama, merek, atau barcode).
 *
 * @return array<int,array<string,mixed>>
 */
function rts_ks_produk_cari(mysqli $conn, string $cari = '', int $batas = 60, bool $hanyaAktif = true): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return [];
    }

    $batas = max(1, min(200, $batas));

    $sql = 'SELECT * FROM rts_ks_produk';
    $where = [];
    $params = [];
    $tipe = '';

    if ($hanyaAktif) {
        $where[] = 'aktif = 1';
    }

    $cari = trim($cari);

    if ($cari !== '') {
        $where[] = '(nama LIKE ? OR merek LIKE ? OR barcode_pack = ? OR barcode_batang = ?)';
        $mirip = '%' . $cari . '%';
        $params[] = $mirip;
        $params[] = $mirip;
        $params[] = $cari;
        $params[] = $cari;
        $tipe .= 'ssss';
    }

    if (count($where) > 0) {
        $sql .= ' WHERE ' . implode(' AND ', $where);
    }

    $sql .= ' ORDER BY nama ASC LIMIT ' . $batas;

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return [];
    }

    if ($tipe !== '') {
        $stmt->bind_param($tipe, ...$params);
    }

    $stmt->execute();
    $hasil = $stmt->get_result();

    $daftar = [];

    while ($hasil && ($baris = $hasil->fetch_assoc())) {
        $daftar[] = rts_ks_produk_bentuk($baris);
    }

    $stmt->close();

    return $daftar;
}

/**
 * Mengambil satu produk beserta harga efektif untuk seorang sales.
 *
 * @return array<string,mixed>|null
 */
function rts_ks_produk_ambil(mysqli $conn, int $id, string $idSales = ''): ?array
{
    if ($id <= 0 || !rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return null;
    }

    $stmt = $conn->prepare('SELECT * FROM rts_ks_produk WHERE id = ? LIMIT 1');

    if (!$stmt) {
        return null;
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return null;
    }

    $baris['khusus_pack'] = null;
    $baris['khusus_batang'] = null;

    if ($idSales !== '' && rts_ks_ada_tabel($conn, 'rts_ks_harga')) {
        $stmt = $conn->prepare(
            'SELECT harga_pack, harga_batang FROM rts_ks_harga WHERE produk_id = ? AND id_sales = ? LIMIT 1'
        );

        if ($stmt) {
            $stmt->bind_param('is', $id, $idSales);
            $stmt->execute();
            $hasil = $stmt->get_result();
            $khusus = $hasil ? $hasil->fetch_assoc() : null;
            $stmt->close();

            if ($khusus) {
                $baris['khusus_pack'] = $khusus['harga_pack'];
                $baris['khusus_batang'] = $khusus['harga_batang'];
            }
        }
    }

    return rts_ks_produk_bentuk($baris, $idSales);
}

/**
 * Mencari produk dari hasil SCAN BARCODE.
 *
 * @return array{produk:array<string,mixed>,satuan:string}|null
 */
function rts_ks_produk_dari_barcode(mysqli $conn, string $kode): ?array
{
    $kode = trim($kode);

    if ($kode === '' || !rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return null;
    }

    $stmt = $conn->prepare(
        'SELECT * FROM rts_ks_produk WHERE barcode_pack = ? OR barcode_batang = ? LIMIT 1'
    );

    if (!$stmt) {
        return null;
    }

    $stmt->bind_param('ss', $kode, $kode);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return null;
    }

    $satuan = 'PACK';

    if ((string) $baris['barcode_batang'] === $kode && (string) $baris['barcode_pack'] !== $kode) {
        $satuan = 'BATANG';
    }

    return ['produk' => rts_ks_produk_bentuk($baris), 'satuan' => $satuan];
}

/**
 * Menyimpan produk baru atau memperbarui produk yang sudah ada.
 *
 * @param array<string,mixed> $data
 * @param array<string,mixed> $user
 * @return array{ok:bool,id:int,pesan:string}
 */
function rts_ks_produk_simpan(mysqli $conn, array $data, array $user): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Tabel produk belum dibuat. Buka menu Barang Bawaan lalu tekan SIAPKAN DATA KASIR.'];
    }

    $id = (int) ($data['id'] ?? 0);
    $nama = rts_ks_teks($data['nama'] ?? '', 150);
    $merek = rts_ks_teks($data['merek'] ?? '', 80);
    $barcodePack = rts_ks_teks($data['barcode_pack'] ?? '', 64);
    $barcodeBatang = rts_ks_teks($data['barcode_batang'] ?? '', 64);
    $isi = rts_ks_bulat($data['isi_per_pack'] ?? 0);
    $hargaPack = rts_ks_angka($data['harga_pack'] ?? 0);
    $hargaBatang = rts_ks_angka($data['harga_batang'] ?? 0);
    $catatan = rts_ks_teks($data['catatan'] ?? '', 255);
    $foto = rts_ks_teks($data['foto'] ?? '', 255);
    $aktif = array_key_exists('aktif', $data) ? (rts_ks_bulat($data['aktif']) === 1 ? 1 : 0) : 1;

    if (strlen($nama) < 2) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Nama produk terlalu pendek.'];
    }

    if ($isi < 0) {
        $isi = 0;
    }

    if ($hargaPack < 0 || $hargaBatang < 0) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Harga tidak boleh negatif.'];
    }

    if ($barcodePack !== '' && $barcodeBatang !== '' && $barcodePack === $barcodeBatang) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Barcode pack dan barcode batang tidak boleh sama.'];
    }

    // Barcode tidak boleh dipakai produk lain.
    foreach ([['barcode_pack', $barcodePack], ['barcode_batang', $barcodeBatang]] as $pasang) {
        $kolom = $pasang[0];
        $kode = $pasang[1];

        if ($kode === '') {
            continue;
        }

        $stmt = $conn->prepare(
            'SELECT id, nama FROM rts_ks_produk WHERE ' . $kolom . ' = ? AND id <> ? LIMIT 1'
        );

        if ($stmt) {
            $stmt->bind_param('si', $kode, $id);
            $stmt->execute();
            $hasil = $stmt->get_result();
            $lain = $hasil ? $hasil->fetch_assoc() : null;
            $stmt->close();

            if ($lain) {
                return [
                    'ok' => false,
                    'id' => 0,
                    'pesan' => 'Barcode ' . $kode . ' sudah dipakai produk "' . $lain['nama'] . '".',
                ];
            }
        }
    }

    $oleh = rts_ks_sales_id($user);

    if ($id > 0) {
        $stmt = $conn->prepare(
            'UPDATE rts_ks_produk SET barcode_pack = ?, barcode_batang = ?, nama = ?, merek = ?,
                    isi_per_pack = ?, harga_pack = ?, harga_batang = ?, foto = ?, aktif = ?,
                    catatan = ?, diubah_oleh = ?, diubah_pada = NOW()
             WHERE id = ?'
        );

        if (!$stmt) {
            return ['ok' => false, 'id' => 0, 'pesan' => 'Gagal menyiapkan perintah simpan.'];
        }

        $stmt->bind_param(
            'ssssiddsissi',
            $barcodePack,
            $barcodeBatang,
            $nama,
            $merek,
            $isi,
            $hargaPack,
            $hargaBatang,
            $foto,
            $aktif,
            $catatan,
            $oleh,
            $id
        );

        $ok = $stmt->execute();

        if (!$ok) {
            $galat = $conn->error;
            $stmt->close();

            return ['ok' => false, 'id' => 0, 'pesan' => 'Gagal menyimpan: ' . $galat];
        }

        $stmt->close();

        return ['ok' => true, 'id' => $id, 'pesan' => 'Produk diperbarui.'];
    }

    $bst = $barcodePack === '' ? null : $barcodePack;
    $bbt = $barcodeBatang === '' ? null : $barcodeBatang;

    $stmt = $conn->prepare(
        'INSERT INTO rts_ks_produk (barcode_pack, barcode_batang, nama, merek, isi_per_pack,
                harga_pack, harga_batang, foto, aktif, catatan, dibuat_oleh, dibuat_pada)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'
    );

    if (!$stmt) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Gagal menyiapkan perintah simpan.'];
    }

    $stmt->bind_param(
        'ssssiddsiss',
        $bst,
        $bbt,
        $nama,
        $merek,
        $isi,
        $hargaPack,
        $hargaBatang,
        $foto,
        $aktif,
        $catatan,
        $oleh
    );

    $ok = $stmt->execute();

    if (!$ok) {
        $galat = $conn->error;
        $stmt->close();

        return ['ok' => false, 'id' => 0, 'pesan' => 'Gagal menyimpan: ' . $galat];
    }

    $baru = (int) $conn->insert_id;
    $stmt->close();

    return ['ok' => true, 'id' => $baru, 'pesan' => 'Produk baru tersimpan.'];
}

/**
 * Menonaktifkan produk. Produk yang sudah pernah dipakai bertransaksi TIDAK
 * dihapus, supaya riwayat penjualan tetap utuh.
 *
 * @param array<string,mixed> $user
 * @return array{ok:bool,pesan:string}
 */
function rts_ks_produk_hapus(mysqli $conn, int $id, array $user): array
{
    if ($id <= 0 || !rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return ['ok' => false, 'pesan' => 'Produk tidak ditemukan.'];
    }

    $terpakai = false;

    if (rts_ks_ada_tabel($conn, 'rts_ks_penjualan_item')) {
        $stmt = $conn->prepare('SELECT COUNT(*) AS total FROM rts_ks_penjualan_item WHERE produk_id = ?');

        if ($stmt) {
            $stmt->bind_param('i', $id);
            $stmt->execute();
            $hasil = $stmt->get_result();
            $baris = $hasil ? $hasil->fetch_assoc() : null;
            $stmt->close();
            $terpakai = $baris && (int) $baris['total'] > 0;
        }
    }

    $oleh = rts_ks_sales_id($user);

    if ($terpakai) {
        $stmt = $conn->prepare(
            'UPDATE rts_ks_produk SET aktif = 0, diubah_oleh = ?, diubah_pada = NOW() WHERE id = ?'
        );

        if ($stmt) {
            $stmt->bind_param('si', $oleh, $id);
            $stmt->execute();
            $stmt->close();
        }

        return ['ok' => true, 'pesan' => 'Produk dinonaktifkan (pernah terjual, jadi riwayatnya tetap disimpan).'];
    }

    $stmt = $conn->prepare('DELETE FROM rts_ks_produk WHERE id = ?');

    if ($stmt) {
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $stmt->close();
    }

    if (rts_ks_ada_tabel($conn, 'rts_ks_stok')) {
        $stmt = $conn->prepare('DELETE FROM rts_ks_stok WHERE produk_id = ?');

        if ($stmt) {
            $stmt->bind_param('i', $id);
            $stmt->execute();
            $stmt->close();
        }
    }

    if (rts_ks_ada_tabel($conn, 'rts_ks_harga')) {
        $stmt = $conn->prepare('DELETE FROM rts_ks_harga WHERE produk_id = ?');

        if ($stmt) {
            $stmt->bind_param('i', $id);
            $stmt->execute();
            $stmt->close();
        }
    }

    return ['ok' => true, 'pesan' => 'Produk dihapus.'];
}

/**
 * Menyimpan harga khusus seorang sales untuk sebuah produk.
 *
 * @return array{ok:bool,pesan:string}
 */
function rts_ks_harga_khusus_simpan(mysqli $conn, int $produkId, string $idSales, $hargaPack, $hargaBatang): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_harga')) {
        return ['ok' => false, 'pesan' => 'Tabel harga belum dibuat.'];
    }

    if ($produkId <= 0 || $idSales === '') {
        return ['ok' => false, 'pesan' => 'Produk atau sales tidak dikenal.'];
    }

    $pack = rts_ks_angka($hargaPack);
    $batang = rts_ks_angka($hargaBatang);

    if ($pack < 0 || $batang < 0) {
        return ['ok' => false, 'pesan' => 'Harga tidak boleh negatif.'];
    }

    if ($pack <= 0 && $batang <= 0) {
        // Dikosongkan berarti kembali memakai harga umum.
        $stmt = $conn->prepare('DELETE FROM rts_ks_harga WHERE produk_id = ? AND id_sales = ?');

        if ($stmt) {
            $stmt->bind_param('is', $produkId, $idSales);
            $stmt->execute();
            $stmt->close();
        }

        return ['ok' => true, 'pesan' => 'Harga khusus dihapus, kembali memakai harga umum.'];
    }

    $stmt = $conn->prepare(
        'INSERT INTO rts_ks_harga (produk_id, id_sales, harga_pack, harga_batang, diperbarui)
         VALUES (?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE harga_pack = ?, harga_batang = ?, diperbarui = NOW()'
    );

    if (!$stmt) {
        return ['ok' => false, 'pesan' => 'Gagal menyiapkan perintah simpan.'];
    }

    $stmt->bind_param(
        'isdddd',
        $produkId,
        $idSales,
        $pack,
        $batang,
        $pack,
        $batang
    );

    $ok = $stmt->execute();
    $stmt->close();

    if (!$ok) {
        return ['ok' => false, 'pesan' => 'Gagal menyimpan harga khusus.'];
    }

    return ['ok' => true, 'pesan' => 'Harga khusus disimpan.'];
}

/* ==========================================================================
 *  BAGIAN 4 - STOK BARANG BAWAAN
 * ========================================================================== */

/**
 * Saldo stok seorang sales untuk satu produk.
 *
 * @return array{pack:int,batang:int}
 */
function rts_ks_stok_saldo(mysqli $conn, string $idSales, int $produkId): array
{
    $kosong = ['pack' => 0, 'batang' => 0];

    if (!rts_ks_ada_tabel($conn, 'rts_ks_stok') || $idSales === '' || $produkId <= 0) {
        return $kosong;
    }

    $stmt = $conn->prepare(
        'SELECT pack, batang FROM rts_ks_stok WHERE id_sales = ? AND produk_id = ? LIMIT 1'
    );

    if (!$stmt) {
        return $kosong;
    }

    $stmt->bind_param('si', $idSales, $produkId);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return $kosong;
    }

    return ['pack' => (int) $baris['pack'], 'batang' => (int) $baris['batang']];
}

/**
 * Mengubah saldo stok sekaligus mencatatnya pada riwayat.
 *
 * @return array{ok:bool,pack:int,batang:int,pesan:string}
 */
function rts_ks_stok_ubah(
    mysqli $conn,
    string $idSales,
    string $namaSales,
    int $produkId,
    string $jenis,
    int $deltaPack,
    int $deltaBatang,
    string $keterangan = '',
    string $refTipe = '',
    int $refId = 0
): array {
    if (!rts_ks_ada_tabel($conn, 'rts_ks_stok')) {
        return ['ok' => false, 'pack' => 0, 'batang' => 0, 'pesan' => 'Tabel stok belum dibuat.'];
    }

    $saldo = rts_ks_stok_saldo($conn, $idSales, $produkId);

    $packBaru = $saldo['pack'] + $deltaPack;
    $batangBaru = $saldo['batang'] + $deltaBatang;

    if ($packBaru < 0 || $batangBaru < 0) {
        return [
            'ok' => false,
            'pack' => $saldo['pack'],
            'batang' => $saldo['batang'],
            'pesan' => 'Stok tidak mencukupi. Sisa saat ini ' . $saldo['pack'] . ' pack ' . $saldo['batang'] . ' batang.',
        ];
    }

    $stmt = $conn->prepare(
        'INSERT INTO rts_ks_stok (id_sales, produk_id, pack, batang, diubah)
         VALUES (?, ?, ?, ?, NOW())
         ON DUPLICATE KEY UPDATE pack = ?, batang = ?, diubah = NOW()'
    );

    if (!$stmt) {
        return ['ok' => false, 'pack' => $saldo['pack'], 'batang' => $saldo['batang'], 'pesan' => 'Gagal menyiapkan perubahan stok.'];
    }

    $stmt->bind_param('siiiii', $idSales, $produkId, $packBaru, $batangBaru, $packBaru, $batangBaru);

    if (!$stmt->execute()) {
        $galat = $conn->error;
        $stmt->close();

        return ['ok' => false, 'pack' => $saldo['pack'], 'batang' => $saldo['batang'], 'pesan' => 'Gagal mengubah stok: ' . $galat];
    }

    $stmt->close();

    if (rts_ks_ada_tabel($conn, 'rts_ks_stok_gerak')) {
        $jenis = strtoupper(rts_ks_teks($jenis, 12));
        $namaSales = rts_ks_teks($namaSales, 100);
        $keterangan = rts_ks_teks($keterangan, 255);
        $refTipe = strtoupper(rts_ks_teks($refTipe, 12));

        $stmt = $conn->prepare(
            'INSERT INTO rts_ks_stok_gerak (tanggal, id_sales, nama_sales, produk_id, jenis,
                    pack_delta, batang_delta, saldo_pack, saldo_batang, keterangan, ref_tipe, ref_id)
             VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );

        if ($stmt) {
            // 11 nilai: id_sales, nama_sales, produk_id, jenis, pack_delta,
            // batang_delta, saldo_pack, saldo_batang, keterangan, ref_tipe, ref_id
            $stmt->bind_param(
                'ssisiiiissi',
                $idSales,
                $namaSales,
                $produkId,
                $jenis,
                $deltaPack,
                $deltaBatang,
                $packBaru,
                $batangBaru,
                $keterangan,
                $refTipe,
                $refId
            );
            $stmt->execute();
            $stmt->close();
        }
    }

    return ['ok' => true, 'pack' => $packBaru, 'batang' => $batangBaru, 'pesan' => 'Stok diperbarui.'];
}

/**
 * Daftar stok bawaan lengkap dengan nama produk dan nilainya.
 *
 * @return array<int,array<string,mixed>>
 */
function rts_ks_stok_daftar(mysqli $conn, string $idSales, string $cari = '', bool $hanyaAda = false): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        return [];
    }

    $sql = 'SELECT p.*, s.pack AS stok_pack, s.batang AS stok_batang
            FROM rts_ks_produk p
            LEFT JOIN rts_ks_stok s ON s.produk_id = p.id AND s.id_sales = ?
            WHERE p.aktif = 1';

    $params = [$idSales];
    $tipe = 's';

    $cari = trim($cari);

    if ($cari !== '') {
        $sql .= ' AND (p.nama LIKE ? OR p.merek LIKE ? OR p.barcode_pack = ? OR p.barcode_batang = ?)';
        $mirip = '%' . $cari . '%';
        $params[] = $mirip;
        $params[] = $mirip;
        $params[] = $cari;
        $params[] = $cari;
        $tipe .= 'ssss';
    }

    if ($hanyaAda) {
        $sql .= ' AND (COALESCE(s.pack, 0) > 0 OR COALESCE(s.batang, 0) > 0)';
    }

    $sql .= ' ORDER BY p.nama ASC LIMIT 300';

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return [];
    }

    $stmt->bind_param($tipe, ...$params);
    $stmt->execute();
    $hasil = $stmt->get_result();

    $daftar = [];

    while ($hasil && ($baris = $hasil->fetch_assoc())) {
        $produk = rts_ks_produk_bentuk($baris);

        $pack = (int) ($baris['stok_pack'] ?? 0);
        $batang = (int) ($baris['stok_batang'] ?? 0);
        $isi = (int) $produk['isi_per_pack'];

        $totalBatang = $pack * $isi + $batang;

        $produk['stok_pack'] = $pack;
        $produk['stok_batang'] = $batang;
        $produk['stok_total_batang'] = $totalBatang;
        $produk['stok_teks'] = rts_ks_stok_teks($pack, $batang);
        $produk['nilai'] = $pack * (float) $produk['harga_pack'] + $batang * (float) $produk['harga_batang'];
        $produk['nilai_teks'] = rts_ks_uang($produk['nilai']);

        $daftar[] = $produk;
    }

    $stmt->close();

    return $daftar;
}

/**
 * Tulisan stok, contoh: "10 pack 3 batang".
 */
function rts_ks_stok_teks(int $pack, int $batang): string
{
    $bagian = [];

    if ($pack !== 0) {
        $bagian[] = $pack . ' pack';
    }

    if ($batang !== 0 || $pack === 0) {
        $bagian[] = $batang . ' batang';
    }

    return implode(' ', $bagian);
}

/**
 * Riwayat perubahan stok.
 *
 * @return array<int,array<string,mixed>>
 */
function rts_ks_stok_riwayat(mysqli $conn, string $idSales, int $produkId = 0, int $batas = 150): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_stok_gerak')) {
        return [];
    }

    $batas = max(1, min(500, $batas));

    $sql = 'SELECT g.*, p.nama AS nama_produk
            FROM rts_ks_stok_gerak g
            LEFT JOIN rts_ks_produk p ON p.id = g.produk_id
            WHERE g.id_sales = ?';

    $params = [$idSales];
    $tipe = 's';

    if ($produkId > 0) {
        $sql .= ' AND g.produk_id = ?';
        $params[] = $produkId;
        $tipe .= 'i';
    }

    $sql .= ' ORDER BY g.id DESC LIMIT ' . $batas;

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return [];
    }

    $stmt->bind_param($tipe, ...$params);
    $stmt->execute();
    $hasil = $stmt->get_result();

    $daftar = [];

    while ($hasil && ($baris = $hasil->fetch_assoc())) {
        $pack = (int) $baris['pack_delta'];
        $batang = (int) $baris['batang_delta'];

        $daftar[] = [
            'id' => (int) $baris['id'],
            'tanggal' => (string) $baris['tanggal'],
            'jenis' => (string) $baris['jenis'],
            'nama_produk' => (string) ($baris['nama_produk'] ?? ''),
            'perubahan' => rts_ks_delta_teks($pack, $batang),
            'saldo' => rts_ks_stok_teks((int) $baris['saldo_pack'], (int) $baris['saldo_batang']),
            'keterangan' => (string) $baris['keterangan'],
        ];
    }

    $stmt->close();

    return $daftar;
}

/**
 * Tulisan perubahan stok, contoh: "+10 pack", "-2 pack 3 batang".
 */
function rts_ks_delta_teks(int $pack, int $batang): string
{
    $bagian = [];

    if ($pack !== 0) {
        $bagian[] = ($pack > 0 ? '+' : '') . $pack . ' pack';
    }

    if ($batang !== 0) {
        $bagian[] = ($batang > 0 ? '+' : '') . $batang . ' batang';
    }

    if (count($bagian) === 0) {
        return 'tetap';
    }

    return implode(' ', $bagian);
}

/* ==========================================================================
 *  BAGIAN 5 - KASIR (PENJUALAN)
 * ========================================================================== */

/**
 * Menyiapkan satu baris barang pada nota.
 *
 * @param array<string,mixed> $item
 * @return array{ok:bool,pesan:string,baris:array<string,mixed>|null}
 */
function rts_ks_kasir_siapkan_baris(mysqli $conn, array $item, string $idSales): array
{
    $produkId = (int) ($item['produk_id'] ?? 0);

    if ($produkId <= 0) {
        return ['ok' => false, 'pesan' => 'Ada barang yang belum dipilih.', 'baris' => null];
    }

    $produk = rts_ks_produk_ambil($conn, $produkId, $idSales);

    if (!$produk) {
        return ['ok' => false, 'pesan' => 'Barang tidak ditemukan pada daftar produk.', 'baris' => null];
    }

    $pack = rts_ks_bulat($item['pack'] ?? 0);
    $batang = rts_ks_bulat($item['batang'] ?? 0);

    if ($pack < 0 || $batang < 0) {
        return ['ok' => false, 'pesan' => 'Jumlah tidak boleh negatif.', 'baris' => null];
    }

    if ($pack === 0 && $batang === 0) {
        return ['ok' => false, 'pesan' => 'Jumlah pack atau batang belum diisi.', 'baris' => null];
    }

    if ($batang > 0 && (int) $produk['isi_per_pack'] <= 0) {
        return [
            'ok' => false,
            'pesan' => 'Produk "' . $produk['nama'] . '" tidak dijual per batang. Isi per pack belum diisi.',
            'baris' => null,
        ];
    }

    $hargaPack = array_key_exists('harga_pack', $item) && rts_ks_angka($item['harga_pack']) > 0
        ? rts_ks_angka($item['harga_pack'])
        : (float) $produk['harga_pack'];

    $hargaBatang = array_key_exists('harga_batang', $item) && rts_ks_angka($item['harga_batang']) > 0
        ? rts_ks_angka($item['harga_batang'])
        : (float) $produk['harga_batang'];

    $satuan = $pack > 0 ? 'PACK' : 'BATANG';
    $jumlah = $pack > 0 ? $pack : $batang;
    $harga = $pack > 0 ? $hargaPack : $hargaBatang;

    return [
        'ok' => true,
        'pesan' => '',
        'baris' => [
            'produk_id' => $produkId,
            'barcode' => (string) ($produk['barcode_pack'] !== '' ? $produk['barcode_pack'] : $produk['barcode_batang']),
            'nama_produk' => (string) $produk['nama'],
            'satuan' => $satuan,
            'isi_per_pack' => (int) $produk['isi_per_pack'],
            'pack' => $pack,
            'batang' => $batang,
            'harga_satuan' => $harga,
            'subtotal' => $pack * $hargaPack + $batang * $hargaBatang,
            'jumlah' => $jumlah,
            'total_pack' => $pack,
            'total_batang' => $pack * (int) $produk['isi_per_pack'] + $batang,
        ],
    ];
}

/**
 * Menyimpan satu nota kasir.
 *
 * Data yang dikirim aplikasi:
 *   metode          : CASH | UTANG | TITIP
 *   bayar           : uang diterima (untuk CASH)
 *   customer_id, nama_customer, hp_customer, alamat_customer, jenis_customer
 *   jatuh_tempo     : tanggal (untuk UTANG / TITIP, opsional)
 *   catatan, foto
 *   items[]         : produk_id, pack, batang, harga_pack, harga_batang
 *
 * @param array<string,mixed> $user
 * @param array<string,mixed> $data
 * @return array<string,mixed>
 */
function rts_ks_kasir_simpan(mysqli $conn, array $user, array $data): array
{
    if (!rts_ks_siap($conn)) {
        return ['ok' => false, 'pesan' => 'Data kasir belum disiapkan. Buka menu Barang Bawaan lalu tekan SIAPKAN DATA KASIR.'];
    }

    $idSales = rts_ks_sales_id($user);
    $namaSales = rts_ks_nama_sales($user);

    $items = (isset($data['items']) && is_array($data['items'])) ? $data['items'] : [];

    if (count($items) === 0) {
        return ['ok' => false, 'pesan' => 'Belum ada barang yang dimasukkan ke nota.'];
    }

    $metode = strtoupper(rts_ks_teks($data['metode'] ?? 'CASH', 10));

    if (!in_array($metode, ['CASH', 'UTANG', 'TITIP'], true)) {
        $metode = 'CASH';
    }

    /* ---------------------------------------- siapkan baris & hitung total */

    $baris = [];
    $total = 0.0;

    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }

        $siap = rts_ks_kasir_siapkan_baris($conn, $item, $idSales);

        if (!$siap['ok']) {
            return ['ok' => false, 'pesan' => (string) $siap['pesan']];
        }

        $satu = $siap['baris'];

        $total += (float) $satu['subtotal'];
        $baris[] = $satu;
    }

    if (count($baris) === 0) {
        return ['ok' => false, 'pesan' => 'Belum ada barang yang sah pada nota.'];
    }

    if ($total <= 0) {
        return ['ok' => false, 'pesan' => 'Total nota masih nol. Periksa harga barang.'];
    }

    /* ------------------------------------------------------------- pembayaran */

    $bayar = rts_ks_angka($data['bayar'] ?? 0);
    $kembali = 0.0;
    $status = 'LUNAS';

    if ($metode === 'CASH') {
        if ($bayar <= 0) {
            $bayar = $total;
        }

        if ($bayar < $total) {
            return [
                'ok' => false,
                'pesan' => 'Uang diterima Rp ' . rts_ks_uang($bayar) . ' kurang dari total Rp ' . rts_ks_uang($total) . '.',
            ];
        }

        $kembali = $bayar - $total;
    } else {
        $bayar = 0.0;
        $status = 'BELUM';
    }

    $conn->begin_transaction();

    try {
        $nomor = rts_ks_nomor($conn, 'KS');
        $sekarang = rts_ks_sekarang();

        $namaCustomer = rts_ks_teks($data['nama_customer'] ?? '', 150);
        $customerId = rts_ks_teks($data['customer_id'] ?? '', 40);
        $hpCustomer = rts_ks_teks($data['hp_customer'] ?? '', 30);
        $alamatCustomer = rts_ks_teks($data['alamat_customer'] ?? '', 255);
        $jenisCustomer = strtoupper(rts_ks_teks($data['jenis_customer'] ?? 'REGULER', 20));
        $catatan = rts_ks_teks($data['catatan'] ?? '', 255);
        $foto = rts_ks_teks($data['foto'] ?? '', 255);
        $district = rts_ks_teks($user['sales_district'] ?? '', 60);
        $role = strtoupper((string) ($user['role'] ?? ''));
        $jumlahItem = 0;

        foreach ($baris as $satu) {
            if ((int) $satu['pack'] > 0) {
                $jumlahItem++;
            }

            if ((int) $satu['batang'] > 0) {
                $jumlahItem++;
            }
        }

        /* ------------------------------------------------- nota penjualan */

        $stmt = $conn->prepare(
            'INSERT INTO rts_ks_penjualan (nomor, tanggal, id_sales, nama_sales, role, district,
                    jenis_customer, customer_id, nama_customer, hp_customer, alamat_customer,
                    metode, total, bayar, kembali, status, jumlah_item, catatan, foto, dibuat_pada)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );

        if (!$stmt) {
            throw new RuntimeException('Gagal menyiapkan nota: ' . $conn->error);
        }

        // 20 nilai: nomor..metode = 12 teks, total/bayar/kembali = 3 angka,
        // status = teks, jumlah_item = angka, catatan/foto/dibuat_pada = 3 teks.
        $stmt->bind_param(
            'ssssssssssssdddsisss',
            $nomor,
            $sekarang,
            $idSales,
            $namaSales,
            $role,
            $district,
            $jenisCustomer,
            $customerId,
            $namaCustomer,
            $hpCustomer,
            $alamatCustomer,
            $metode,
            $total,
            $bayar,
            $kembali,
            $status,
            $jumlahItem,
            $catatan,
            $foto,
            $sekarang
        );

        $stmt->execute();
        $notaId = (int) $conn->insert_id;
        $stmt->close();

        /* ------------------------------------------------------ barang nota */

        $stmt = $conn->prepare(
            'INSERT INTO rts_ks_penjualan_item (penjualan_id, produk_id, barcode, nama_produk, satuan,
                    isi_per_pack, pack, batang, harga_satuan, subtotal)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
        );

        if (!$stmt) {
            throw new RuntimeException('Gagal menyiapkan barang nota: ' . $conn->error);
        }

        foreach ($baris as $satu) {
            $stmt->bind_param(
                'iissiiiidd',
                $notaId,
                $satu['produk_id'],
                $satu['barcode'],
                $satu['nama_produk'],
                $satu['satuan'],
                $satu['isi_per_pack'],
                $satu['pack'],
                $satu['batang'],
                $satu['harga_satuan'],
                $satu['subtotal']
            );
            $stmt->execute();
        }

        $stmt->close();

        /* ------------------------------------------------- stok berkurang */

        // Dikumpulkan per produk dulu, supaya satu produk dengan dua baris
        // (pack dan batang) dihitung sekali saja.
        $perProduk = [];

        foreach ($baris as $satu) {
            $pid = (int) $satu['produk_id'];

            if (!isset($perProduk[$pid])) {
                $perProduk[$pid] = [
                    'pack' => 0,
                    'batang' => 0,
                    'isi' => (int) $satu['isi_per_pack'],
                    'nama' => (string) $satu['nama_produk'],
                ];
            }

            $perProduk[$pid]['pack'] += (int) $satu['pack'];
            $perProduk[$pid]['batang'] += (int) $satu['batang'];
        }

        foreach ($perProduk as $pid => $butuh) {
            $saldo = rts_ks_stok_saldo($conn, $idSales, (int) $pid);

            $butuhPack = (int) $butuh['pack'];
            $butuhBatang = (int) $butuh['batang'];
            $isi = (int) $butuh['isi'];

            $sisaPack = $saldo['pack'] - $butuhPack;

            if ($sisaPack < 0) {
                throw new RuntimeException(
                    'Stok ' . $butuh['nama'] . ' kurang. Sisa ' . $saldo['pack'] . ' pack,'
                    . ' dibutuhkan ' . $butuhPack . ' pack.'
                );
            }

            $bukaPack = 0;

            if ($butuhBatang > $saldo['batang']) {
                if ($isi <= 0) {
                    throw new RuntimeException('Produk ' . $butuh['nama'] . ' tidak dijual per batang.');
                }

                $kurang = $butuhBatang - $saldo['batang'];
                $bukaPack = (int) ceil($kurang / $isi);

                if ($bukaPack > $sisaPack) {
                    throw new RuntimeException(
                        'Stok ' . $butuh['nama'] . ' kurang. Sisa ' . $saldo['pack'] . ' pack dan '
                        . $saldo['batang'] . ' batang, dibutuhkan ' . $butuhPack . ' pack dan '
                        . $butuhBatang . ' batang.'
                    );
                }
            }

            $deltaPack = -$butuhPack - $bukaPack;
            $deltaBatang = $bukaPack * $isi - $butuhBatang;

            $keterangan = 'Terjual pada nota ' . $nomor;

            if ($bukaPack > 0) {
                $keterangan .= ' (termasuk membuka ' . $bukaPack . ' pack menjadi ' . ($bukaPack * $isi) . ' batang)';
            }

            $ubah = rts_ks_stok_ubah(
                $conn,
                $idSales,
                $namaSales,
                (int) $pid,
                'JUAL',
                $deltaPack,
                $deltaBatang,
                $keterangan,
                'KASIR',
                $notaId
            );

            if (!$ubah['ok']) {
                throw new RuntimeException((string) $ubah['pesan']);
            }
        }

        /* ------------------------------------------------- piutang (utang/titip) */

        $piutang = null;

        if ($metode !== 'CASH') {
            $rincian = [];

            foreach ($baris as $satu) {
                $bagian = [];

                if ((int) $satu['pack'] > 0) {
                    $bagian[] = (int) $satu['pack'] . ' pack';
                }

                if ((int) $satu['batang'] > 0) {
                    $bagian[] = (int) $satu['batang'] . ' batang';
                }

                $rincian[] = implode(' + ', $bagian) . ' ' . $satu['nama_produk'];
            }

            $nomorPiutang = rts_ks_nomor($conn, 'PT');
            $jatuhTempo = rts_ks_teks($data['jatuh_tempo'] ?? '', 20);

            if ($jatuhTempo === '' && $metode === 'UTANG') {
                // Bawaan: 7 hari untuk utang, 30 hari untuk titipan.
                $jatuhTempo = date('Y-m-d', strtotime('+7 days'));
            }

            if ($jatuhTempo === '' && $metode === 'TITIP') {
                $jatuhTempo = date('Y-m-d', strtotime('+30 days'));
            }

            $tempoDb = $jatuhTempo !== '' ? date('Y-m-d', strtotime($jatuhTempo)) : null;
            $teksRincian = rts_ks_teks(implode(', ', $rincian), 2000);

            $stmt = $conn->prepare(
                'INSERT INTO rts_ks_piutang (nomor, jenis, penjualan_id, tanggal, jatuh_tempo, id_sales,
                        nama_sales, district, customer_id, nama_customer, hp_customer,
                        total, dibayar, sisa, status, rincian, catatan, foto, diperbarui)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, \'BELUM\', ?, ?, ?, ?)'
            );

            if (!$stmt) {
                throw new RuntimeException('Gagal menyiapkan piutang: ' . $conn->error);
            }

            // 17 nilai: nomor, jenis, penjualan_id, tanggal, jatuh_tempo, id_sales,
            // nama_sales, district, customer_id, nama_customer, hp_customer,
            // total, sisa, rincian, catatan, foto, diperbarui
            $stmt->bind_param(
                'ssissssssssddssss',
                $nomorPiutang,
                $metode,
                $notaId,
                $sekarang,
                $tempoDb,
                $idSales,
                $namaSales,
                $district,
                $customerId,
                $namaCustomer,
                $hpCustomer,
                $total,
                $total,
                $teksRincian,
                $catatan,
                $foto,
                $sekarang
            );

            $stmt->execute();
            $piutangId = (int) $conn->insert_id;
            $stmt->close();

            $piutang = [
                'id' => $piutangId,
                'nomor' => $nomorPiutang,
                'jenis' => $metode,
                'jatuh_tempo' => $tempoDb,
                'sisa' => $total,
            ];
        }

        $conn->commit();
    } catch (Throwable $galat) {
        $conn->rollback();

        return ['ok' => false, 'pesan' => 'Nota dibatalkan, tidak ada yang tersimpan. ' . $galat->getMessage()];
    }

    return [
        'ok' => true,
        'pesan' => 'Nota ' . $nomor . ' tersimpan.',
        'id' => $notaId,
        'nomor' => $nomor,
        'total' => $total,
        'total_teks' => rts_ks_uang($total),
        'bayar' => $bayar,
        'kembali' => $kembali,
        'kembali_teks' => rts_ks_uang($kembali),
        'metode' => $metode,
        'status' => $status,
        'piutang' => $piutang,
        'nota' => rts_ks_kasir_ambil($conn, $notaId),
    ];
}

/**
 * Mengambil satu nota lengkap dengan barangnya.
 *
 * @return array<string,mixed>|null
 */
function rts_ks_kasir_ambil(mysqli $conn, int $id): ?array
{
    if ($id <= 0 || !rts_ks_ada_tabel($conn, 'rts_ks_penjualan')) {
        return null;
    }

    $stmt = $conn->prepare('SELECT * FROM rts_ks_penjualan WHERE id = ? LIMIT 1');

    if (!$stmt) {
        return null;
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $nota = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$nota) {
        return null;
    }

    $items = [];

    $stmt = $conn->prepare('SELECT * FROM rts_ks_penjualan_item WHERE penjualan_id = ? ORDER BY id ASC');

    if ($stmt) {
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $hasil = $stmt->get_result();

        while ($hasil && ($baris = $hasil->fetch_assoc())) {
            $items[] = [
                'produk_id' => (int) $baris['produk_id'],
                'barcode' => (string) $baris['barcode'],
                'nama_produk' => (string) $baris['nama_produk'],
                'satuan' => (string) $baris['satuan'],
                'isi_per_pack' => (int) $baris['isi_per_pack'],
                'pack' => (int) $baris['pack'],
                'batang' => (int) $baris['batang'],
                'harga_satuan' => (float) $baris['harga_satuan'],
                'harga_satuan_teks' => rts_ks_uang($baris['harga_satuan']),
                'subtotal' => (float) $baris['subtotal'],
                'subtotal_teks' => rts_ks_uang($baris['subtotal']),
            ];
        }

        $stmt->close();
    }

    $piutang = null;

    if (rts_ks_ada_tabel($conn, 'rts_ks_piutang')) {
        $stmt = $conn->prepare('SELECT * FROM rts_ks_piutang WHERE penjualan_id = ? LIMIT 1');

        if ($stmt) {
            $stmt->bind_param('i', $id);
            $stmt->execute();
            $hasil = $stmt->get_result();
            $baris = $hasil ? $hasil->fetch_assoc() : null;
            $stmt->close();

            if ($baris) {
                $piutang = [
                    'id' => (int) $baris['id'],
                    'nomor' => (string) $baris['nomor'],
                    'jenis' => (string) $baris['jenis'],
                    'jatuh_tempo' => (string) ($baris['jatuh_tempo'] ?? ''),
                    'total' => (float) $baris['total'],
                    'dibayar' => (float) $baris['dibayar'],
                    'sisa' => (float) $baris['sisa'],
                    'status' => (string) $baris['status'],
                ];
            }
        }
    }

    return [
        'id' => (int) $nota['id'],
        'nomor' => (string) $nota['nomor'],
        'tanggal' => (string) $nota['tanggal'],
        'id_sales' => (string) $nota['id_sales'],
        'nama_sales' => (string) $nota['nama_sales'],
        'district' => (string) $nota['district'],
        'jenis_customer' => (string) $nota['jenis_customer'],
        'customer_id' => (string) $nota['customer_id'],
        'nama_customer' => (string) $nota['nama_customer'],
        'hp_customer' => (string) $nota['hp_customer'],
        'alamat_customer' => (string) $nota['alamat_customer'],
        'metode' => (string) $nota['metode'],
        'total' => (float) $nota['total'],
        'total_teks' => rts_ks_uang($nota['total']),
        'bayar' => (float) $nota['bayar'],
        'bayar_teks' => rts_ks_uang($nota['bayar']),
        'kembali' => (float) $nota['kembali'],
        'kembali_teks' => rts_ks_uang($nota['kembali']),
        'status' => (string) $nota['status'],
        'catatan' => (string) $nota['catatan'],
        'foto' => (string) $nota['foto'],
        'dicetak' => (int) $nota['dicetak'],
        'dibatalkan' => (int) $nota['dibatalkan'] === 1,
        'items' => $items,
        'piutang' => $piutang,
    ];
}

/**
 * Daftar nota kasir.
 *
 * @param array<string,mixed> $filter
 * @return array<string,mixed>
 */
function rts_ks_kasir_daftar(mysqli $conn, array $filter): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_penjualan')) {
        return ['items' => [], 'total' => 0, 'total_teks' => '0'];
    }

    $batas = max(1, min(200, (int) ($filter['batas'] ?? 60)));
    $idSales = trim((string) ($filter['id_sales'] ?? ''));
    $cari = trim((string) ($filter['cari'] ?? ''));
    $dari = trim((string) ($filter['dari'] ?? ''));
    $sampai = trim((string) ($filter['sampai'] ?? ''));
    $belumLunas = !empty($filter['belum_lunas']);

    $sql = 'SELECT * FROM rts_ks_penjualan WHERE 1 = 1';
    $params = [];
    $tipe = '';

    if ($idSales !== '') {
        $sql .= ' AND id_sales = ?';
        $params[] = $idSales;
        $tipe .= 's';
    }

    if ($cari !== '') {
        $sql .= ' AND (nomor LIKE ? OR nama_customer LIKE ? OR customer_id = ?)';
        $mirip = '%' . $cari . '%';
        $params[] = $mirip;
        $params[] = $mirip;
        $params[] = $cari;
        $tipe .= 'sss';
    }

    if ($dari !== '') {
        $sql .= ' AND tanggal >= ?';
        $params[] = date('Y-m-d 00:00:00', strtotime($dari));
        $tipe .= 's';
    }

    if ($sampai !== '') {
        $sql .= ' AND tanggal <= ?';
        $params[] = date('Y-m-d 23:59:59', strtotime($sampai));
        $tipe .= 's';
    }

    if ($belumLunas) {
        $sql .= ' AND status <> \'LUNAS\' AND dibatalkan = 0';
    }

    $sql .= ' ORDER BY id DESC LIMIT ' . $batas;

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return ['items' => [], 'total' => 0, 'total_teks' => '0'];
    }

    if ($tipe !== '') {
        $stmt->bind_param($tipe, ...$params);
    }

    $stmt->execute();
    $hasil = $stmt->get_result();

    $daftar = [];
    $jumlah = 0.0;
    $cash = 0.0;

    while ($hasil && ($baris = $hasil->fetch_assoc())) {
        $total = (float) $baris['total'];
        $jumlah += $total;

        if (strtoupper((string) $baris['metode']) === 'CASH' && (int) $baris['dibatalkan'] !== 1) {
            $cash += $total;
        }

        $daftar[] = [
            'id' => (int) $baris['id'],
            'nomor' => (string) $baris['nomor'],
            'tanggal' => (string) $baris['tanggal'],
            'nama_customer' => (string) $baris['nama_customer'],
            'customer_id' => (string) $baris['customer_id'],
            'metode' => (string) $baris['metode'],
            'total' => $total,
            'total_teks' => rts_ks_uang($total),
            'status' => (string) $baris['status'],
            'dibatalkan' => (int) $baris['dibatalkan'] === 1,
            'jumlah_item' => (int) $baris['jumlah_item'],
            'nama_sales' => (string) $baris['nama_sales'],
            'dicetak' => (int) $baris['dicetak'],
        ];
    }

    $stmt->close();

    return [
        'items' => $daftar,
        'jumlah' => count($daftar),
        'total' => $jumlah,
        'total_teks' => rts_ks_uang($jumlah),
        'cash' => $cash,
        'cash_teks' => rts_ks_uang($cash),
    ];
}

/**
 * Membatalkan sebuah nota, stok dikembalikan seperti semula.
 *
 * @param array<string,mixed> $user
 * @return array{ok:bool,pesan:string}
 */
function rts_ks_kasir_batal(mysqli $conn, int $id, string $alasan, array $user): array
{
    if (!rts_ks_siap($conn) || $id <= 0) {
        return ['ok' => false, 'pesan' => 'Nota tidak ditemukan.'];
    }

    $nota = rts_ks_kasir_ambil($conn, $id);

    if (!$nota) {
        return ['ok' => false, 'pesan' => 'Nota tidak ditemukan.'];
    }

    if (!empty($nota['dibatalkan'])) {
        return ['ok' => false, 'pesan' => 'Nota ini sudah dibatalkan sebelumnya.'];
    }

    if (strtoupper((string) $user['role']) !== 'ADMIN' && $nota['id_sales'] !== rts_ks_sales_id($user)) {
        return ['ok' => false, 'pesan' => 'Nota ini bukan milik Anda.'];
    }

    if (!empty($nota['piutang']) && (float) $nota['piutang']['dibayar'] > 0) {
        return ['ok' => false, 'pesan' => 'Nota ini sudah ada pembayaran piutangnya. Batalkan pembayaran lebih dahulu.'];
    }

    $conn->begin_transaction();

    try {
        foreach ($nota['items'] as $item) {
            $dPack = (int) $item['pack'];
            $dBatang = (int) $item['batang'];

            $ubah = rts_ks_stok_ubah(
                $conn,
                (string) $nota['id_sales'],
                (string) $nota['nama_sales'],
                (int) $item['produk_id'],
                'BATAL',
                $dPack,
                $dBatang,
                'Pembatalan nota ' . $nota['nomor'] . ($alasan !== '' ? ' - ' . rts_ks_teks($alasan, 120) : ''),
                'KASIR',
                $id
            );

            if (!$ubah['ok']) {
                throw new RuntimeException((string) $ubah['pesan']);
            }
        }

        $oleh = rts_ks_sales_id($user);
        $alasanTeks = rts_ks_teks($alasan, 255);

        $stmt = $conn->prepare(
            'UPDATE rts_ks_penjualan SET dibatalkan = 1, batal_alasan = ?, batal_oleh = ?, batal_pada = NOW()
             WHERE id = ?'
        );

        if ($stmt) {
            $stmt->bind_param('ssi', $alasanTeks, $oleh, $id);
            $stmt->execute();
            $stmt->close();
        }

        if (rts_ks_ada_tabel($conn, 'rts_ks_piutang')) {
            $stmt = $conn->prepare('UPDATE rts_ks_piutang SET status = \'BATAL\', diperbarui = NOW() WHERE penjualan_id = ?');

            if ($stmt) {
                $stmt->bind_param('i', $id);
                $stmt->execute();
                $stmt->close();
            }
        }

        $conn->commit();
    } catch (Throwable $galat) {
        $conn->rollback();

        return ['ok' => false, 'pesan' => 'Nota gagal dibatalkan. ' . $galat->getMessage()];
    }

    return ['ok' => true, 'pesan' => 'Nota ' . $nota['nomor'] . ' dibatalkan dan stok dikembalikan.'];
}

/**
 * Mencatat bahwa nota sudah dicetak.
 */
function rts_ks_kasir_tandai_cetak(mysqli $conn, int $id): void
{
    if ($id <= 0 || !rts_ks_ada_tabel($conn, 'rts_ks_penjualan')) {
        return;
    }

    $stmt = $conn->prepare(
        'UPDATE rts_ks_penjualan SET dicetak = dicetak + 1, cetak_terakhir = NOW() WHERE id = ?'
    );

    if ($stmt) {
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $stmt->close();
    }
}

/* ==========================================================================
 *  BAGIAN 6 - PIUTANG (UTANG & TITIP)
 * ========================================================================== */

/**
 * Daftar piutang beserta ringkasannya.
 *
 * @param array<string,mixed> $filter
 * @return array<string,mixed>
 */
function rts_ks_piutang_daftar(mysqli $conn, array $filter): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_piutang')) {
        return ['items' => [], 'belum_teks' => '0', 'jumlah' => 0];
    }

    $batas = max(1, min(300, (int) ($filter['batas'] ?? 80)));
    $idSales = trim((string) ($filter['id_sales'] ?? ''));
    $jenis = strtoupper(trim((string) ($filter['jenis'] ?? '')));
    $status = strtoupper(trim((string) ($filter['status'] ?? '')));
    $cari = trim((string) ($filter['cari'] ?? ''));

    $sql = 'SELECT * FROM rts_ks_piutang WHERE 1 = 1';
    $params = [];
    $tipe = '';

    if ($idSales !== '') {
        $sql .= ' AND id_sales = ?';
        $params[] = $idSales;
        $tipe .= 's';
    }

    if ($jenis !== '' && in_array($jenis, ['UTANG', 'TITIP'], true)) {
        $sql .= ' AND jenis = ?';
        $params[] = $jenis;
        $tipe .= 's';
    }

    if ($status !== '' && in_array($status, ['BELUM', 'SEBAGIAN', 'LUNAS', 'BATAL'], true)) {
        $sql .= ' AND status = ?';
        $params[] = $status;
        $tipe .= 's';
    }

    if ($cari !== '') {
        $sql .= ' AND (nomor LIKE ? OR nama_customer LIKE ? OR customer_id = ?)';
        $mirip = '%' . $cari . '%';
        $params[] = $mirip;
        $params[] = $mirip;
        $params[] = $cari;
        $tipe .= 'sss';
    }

    $sql .= ' ORDER BY (status = \'LUNAS\') ASC, id DESC LIMIT ' . $batas;

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return ['items' => [], 'belum_teks' => '0', 'jumlah' => 0];
    }

    if ($tipe !== '') {
        $stmt->bind_param($tipe, ...$params);
    }

    $stmt->execute();
    $hasil = $stmt->get_result();

    $daftar = [];
    $belum = 0.0;
    $dibayar = 0.0;

    while ($hasil && ($baris = $hasil->fetch_assoc())) {
        $sisa = (float) $baris['sisa'];
        $total = (float) $baris['total'];

        if (!in_array((string) $baris['status'], ['LUNAS', 'BATAL'], true)) {
            $belum += $sisa;
        }

        $dibayar += (float) $baris['dibayar'];

        $daftar[] = [
            'id' => (int) $baris['id'],
            'nomor' => (string) $baris['nomor'],
            'jenis' => (string) $baris['jenis'],
            'tanggal' => (string) $baris['tanggal'],
            'jatuh_tempo' => (string) ($baris['jatuh_tempo'] ?? ''),
            'nama_customer' => (string) $baris['nama_customer'],
            'customer_id' => (string) $baris['customer_id'],
            'hp_customer' => (string) $baris['hp_customer'],
            'nama_sales' => (string) $baris['nama_sales'],
            'total' => $total,
            'total_teks' => rts_ks_uang($total),
            'dibayar' => (float) $baris['dibayar'],
            'dibayar_teks' => rts_ks_uang($baris['dibayar']),
            'sisa' => $sisa,
            'sisa_teks' => rts_ks_uang($sisa),
            'status' => (string) $baris['status'],
            'rincian' => (string) ($baris['rincian'] ?? ''),
            'terlambat' => $baris['jatuh_tempo'] !== null && (string) $baris['jatuh_tempo'] !== ''
                && strtotime((string) $baris['jatuh_tempo']) < strtotime(date('Y-m-d'))
                && !in_array((string) $baris['status'], ['LUNAS', 'BATAL'], true),
        ];
    }

    $stmt->close();

    return [
        'items' => $daftar,
        'jumlah' => count($daftar),
        'belum' => $belum,
        'belum_teks' => rts_ks_uang($belum),
        'dibayar' => $dibayar,
        'dibayar_teks' => rts_ks_uang($dibayar),
    ];
}

/**
 * Mengambil satu piutang beserta riwayat pembayarannya.
 *
 * @return array<string,mixed>|null
 */
function rts_ks_piutang_ambil(mysqli $conn, int $id): ?array
{
    if ($id <= 0 || !rts_ks_ada_tabel($conn, 'rts_ks_piutang')) {
        return null;
    }

    $stmt = $conn->prepare('SELECT * FROM rts_ks_piutang WHERE id = ? LIMIT 1');

    if (!$stmt) {
        return null;
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return null;
    }

    $bayar = [];

    $stmt = $conn->prepare('SELECT * FROM rts_ks_piutang_bayar WHERE piutang_id = ? ORDER BY id ASC');

    if ($stmt) {
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $hasil = $stmt->get_result();

        while ($hasil && ($b = $hasil->fetch_assoc())) {
            $bayar[] = [
                'id' => (int) $b['id'],
                'tanggal' => (string) $b['tanggal'],
                'jumlah' => (float) $b['jumlah'],
                'jumlah_teks' => rts_ks_uang($b['jumlah']),
                'metode' => (string) $b['metode'],
                'nama_penerima' => (string) $b['nama_penerima'],
                'catatan' => (string) $b['catatan'],
                'sisa_sesudah_teks' => rts_ks_uang($b['sisa_sesudah']),
            ];
        }

        $stmt->close();
    }

    return [
        'id' => (int) $baris['id'],
        'nomor' => (string) $baris['nomor'],
        'jenis' => (string) $baris['jenis'],
        'penjualan_id' => (int) $baris['penjualan_id'],
        'tanggal' => (string) $baris['tanggal'],
        'jatuh_tempo' => (string) ($baris['jatuh_tempo'] ?? ''),
        'nama_customer' => (string) $baris['nama_customer'],
        'customer_id' => (string) $baris['customer_id'],
        'hp_customer' => (string) $baris['hp_customer'],
        'nama_sales' => (string) $baris['nama_sales'],
        'total' => (float) $baris['total'],
        'total_teks' => rts_ks_uang($baris['total']),
        'dibayar' => (float) $baris['dibayar'],
        'dibayar_teks' => rts_ks_uang($baris['dibayar']),
        'sisa' => (float) $baris['sisa'],
        'sisa_teks' => rts_ks_uang($baris['sisa']),
        'status' => (string) $baris['status'],
        'rincian' => (string) ($baris['rincian'] ?? ''),
        'catatan' => (string) $baris['catatan'],
        'pembayaran' => $bayar,
    ];
}

/**
 * Mencatat pembayaran / angsuran piutang (utang atau titipan).
 *
 * @param array<string,mixed> $user
 * @return array{ok:bool,pesan:string,sisa:float,status:string}
 */
function rts_ks_piutang_bayar(mysqli $conn, int $id, $jumlah, string $metode, string $catatan, array $user): array
{
    if (!rts_ks_siap($conn) || $id <= 0) {
        return ['ok' => false, 'pesan' => 'Piutang tidak ditemukan.', 'sisa' => 0, 'status' => ''];
    }

    $piutang = rts_ks_piutang_ambil($conn, $id);

    if (!$piutang) {
        return ['ok' => false, 'pesan' => 'Piutang tidak ditemukan.', 'sisa' => 0, 'status' => ''];
    }

    if (in_array($piutang['status'], ['LUNAS', 'BATAL'], true)) {
        return ['ok' => false, 'pesan' => 'Piutang ini sudah ' . strtolower($piutang['status']) . '.', 'sisa' => (float) $piutang['sisa'], 'status' => (string) $piutang['status']];
    }

    if (strtoupper((string) $user['role']) !== 'ADMIN' && $piutang['nama_sales'] !== rts_ks_nama_sales($user)) {
        return ['ok' => false, 'pesan' => 'Piutang ini bukan milik Anda.', 'sisa' => (float) $piutang['sisa'], 'status' => (string) $piutang['status']];
    }

    $nilai = rts_ks_angka($jumlah);

    if ($nilai <= 0) {
        return ['ok' => false, 'pesan' => 'Jumlah pembayaran belum diisi.', 'sisa' => (float) $piutang['sisa'], 'status' => (string) $piutang['status']];
    }

    if ($nilai > (float) $piutang['sisa'] + 0.01) {
        return [
            'ok' => false,
            'pesan' => 'Jumlah melebihi sisa piutang Rp ' . rts_ks_uang($piutang['sisa']) . '.',
            'sisa' => (float) $piutang['sisa'],
            'status' => (string) $piutang['status'],
        ];
    }

    $metode = strtoupper(rts_ks_teks($metode, 12));

    if (!in_array($metode, ['CASH', 'TRANSFER', 'QRIS'], true)) {
        $metode = 'CASH';
    }

    $dibayarBaru = (float) $piutang['dibayar'] + $nilai;
    $sisaBaru = (float) $piutang['total'] - $dibayarBaru;

    if ($sisaBaru < 0) {
        $sisaBaru = 0.0;
    }

    $statusBaru = $sisaBaru <= 0.01 ? 'LUNAS' : ($dibayarBaru > 0 ? 'SEBAGIAN' : 'BELUM');

    $sekarang = rts_ks_sekarang();
    $oleh = rts_ks_sales_id($user);
    $nama = rts_ks_nama_sales($user);
    $catatanTeks = rts_ks_teks($catatan, 255);

    $conn->begin_transaction();

    try {
        $stmt = $conn->prepare(
            'INSERT INTO rts_ks_piutang_bayar (piutang_id, tanggal, jumlah, metode, diterima_oleh,
                    nama_penerima, catatan, sisa_sesudah)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );

        if (!$stmt) {
            throw new RuntimeException('Gagal menyiapkan pembayaran.');
        }

        $stmt->bind_param(
            'isdssssd',
            $id,
            $sekarang,
            $nilai,
            $metode,
            $oleh,
            $nama,
            $catatanTeks,
            $sisaBaru
        );
        $stmt->execute();
        $stmt->close();

        $stmt = $conn->prepare(
            'UPDATE rts_ks_piutang SET dibayar = ?, sisa = ?, status = ?, diperbarui = NOW() WHERE id = ?'
        );

        if (!$stmt) {
            throw new RuntimeException('Gagal memperbarui piutang.');
        }

        $stmt->bind_param('ddsi', $dibayarBaru, $sisaBaru, $statusBaru, $id);
        $stmt->execute();
        $stmt->close();

        // Nota kasirnya ikut diperbarui agar laporan penjualan sesuai.
        if ((int) $piutang['penjualan_id'] > 0) {
            $statusNota = $statusBaru === 'LUNAS' ? 'LUNAS' : ($statusBaru === 'SEBAGIAN' ? 'SEBAGIAN' : 'BELUM');

            $stmt = $conn->prepare('UPDATE rts_ks_penjualan SET status = ? WHERE id = ?');

            if ($stmt) {
                $stmt->bind_param('si', $statusNota, $piutang['penjualan_id']);
                $stmt->execute();
                $stmt->close();
            }
        }

        $conn->commit();
    } catch (Throwable $galat) {
        $conn->rollback();

        return ['ok' => false, 'pesan' => 'Pembayaran gagal disimpan. ' . $galat->getMessage(), 'sisa' => (float) $piutang['sisa'], 'status' => (string) $piutang['status']];
    }

    $pesan = $statusBaru === 'LUNAS'
        ? 'Piutang ' . $piutang['nomor'] . ' LUNAS.'
        : 'Pembayaran Rp ' . rts_ks_uang($nilai) . ' tersimpan. Sisa Rp ' . rts_ks_uang($sisaBaru) . '.';

    return ['ok' => true, 'pesan' => $pesan, 'sisa' => $sisaBaru, 'status' => $statusBaru];
}

/* ==========================================================================
 *  BAGIAN 7 - TEMPLATE STRUK
 * ========================================================================== */

/**
 * Template struk bawaan (sebelum diubah sales).
 *
 * @return array<string,mixed>
 */
function rts_ks_struk_bawaan(): array
{
    return [
        'judul' => 'RTS PANEL',
        'baris1' => 'PT. Wismilak Inti Makmur',
        'baris2' => '',
        'baris3' => '',
        'footer1' => 'Terima kasih',
        'footer2' => 'Barang yang sudah dibeli',
        'footer3' => 'tidak dapat ditukar',
        'lebar_kertas' => 58,
        'ukuran_huruf' => 'SEDANG',
        'tampilkan_barcode' => 1,
        'tampilkan_hp' => 1,
        'tampilkan_ttd' => 0,
        'tampilkan_qris' => 0,
        'tampilkan_diskon' => 1,
        'tampilkan_metode' => 1,
        'header_tebal' => 1,
        'garis' => '-',
        'jumlah_salinan' => 1,
        'catatan_kaki' => '',
    ];
}

/**
 * Membaca template struk seorang sales (bawaan bila belum pernah diubah).
 *
 * @return array<string,mixed>
 */
function rts_ks_struk_baca(mysqli $conn, string $idSales): array
{
    $bawaan = rts_ks_struk_bawaan();

    if (!rts_ks_ada_tabel($conn, 'rts_ks_struk') || $idSales === '') {
        return $bawaan;
    }

    $stmt = $conn->prepare('SELECT * FROM rts_ks_struk WHERE id_sales = ? LIMIT 1');

    if (!$stmt) {
        return $bawaan;
    }

    $stmt->bind_param('s', $idSales);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $baris = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$baris) {
        return $bawaan;
    }

    foreach ($bawaan as $kunci => $nilai) {
        if (!array_key_exists($kunci, $baris) || $baris[$kunci] === null) {
            continue;
        }

        if (is_int($nilai)) {
            $bawaan[$kunci] = (int) $baris[$kunci];
        } elseif (is_float($nilai)) {
            $bawaan[$kunci] = (float) $baris[$kunci];
        } else {
            $bawaan[$kunci] = (string) $baris[$kunci];
        }
    }

    $bawaan['ada'] = true;

    return $bawaan;
}

/**
 * Menyimpan template struk milik seorang sales.
 *
 * @param array<string,mixed> $data
 * @return array{ok:bool,pesan:string,struk:array<string,mixed>}
 */
function rts_ks_struk_simpan(mysqli $conn, string $idSales, array $data): array
{
    if (!rts_ks_ada_tabel($conn, 'rts_ks_struk')) {
        return ['ok' => false, 'pesan' => 'Tabel struk belum dibuat.', 'struk' => rts_ks_struk_bawaan()];
    }

    $bawaan = rts_ks_struk_bawaan();

    $teks = ['judul', 'baris1', 'baris2', 'baris3', 'footer1', 'footer2', 'footer3', 'catatan_kaki'];
    $angka = ['tampilkan_barcode', 'tampilkan_hp', 'tampilkan_ttd', 'tampilkan_qris', 'tampilkan_diskon', 'tampilkan_metode', 'header_tebal'];
    $angkaBiasa = ['lebar_kertas', 'jumlah_salinan'];

    $nilai = [];

    foreach ($teks as $kunci) {
        $nilai[$kunci] = array_key_exists($kunci, $data)
            ? rts_ks_teks($data[$kunci], $kunci === 'judul' ? 60 : 120)
            : (string) $bawaan[$kunci];
    }

    foreach ($angka as $kunci) {
        $nilai[$kunci] = array_key_exists($kunci, $data)
            ? (rts_ks_bulat($data[$kunci]) === 1 ? 1 : 0)
            : (int) $bawaan[$kunci];
    }

    foreach ($angkaBiasa as $kunci) {
        $nilai[$kunci] = array_key_exists($kunci, $data)
            ? rts_ks_bulat($data[$kunci])
            : (int) $bawaan[$kunci];
    }

    if ($nilai['lebar_kertas'] < 40 || $nilai['lebar_kertas'] > 80) {
        $nilai['lebar_kertas'] = 58;
    }

    if ($nilai['jumlah_salinan'] < 1 || $nilai['jumlah_salinan'] > 3) {
        $nilai['jumlah_salinan'] = 1;
    }

    $ukuran = strtoupper(rts_ks_teks($data['ukuran_huruf'] ?? $bawaan['ukuran_huruf'], 10));

    if (!in_array($ukuran, ['KECIL', 'SEDANG', 'BESAR'], true)) {
        $ukuran = 'SEDANG';
    }

    $garis = (string) ($data['garis'] ?? $bawaan['garis']);
    $garis = rts_ks_teks($garis, 3);

    if ($garis === '') {
        $garis = '-';
    }

    $sql = 'INSERT INTO rts_ks_struk (id_sales, judul, baris1, baris2, baris3, footer1, footer2,
                footer3, lebar_kertas, ukuran_huruf, tampilkan_barcode, tampilkan_hp, tampilkan_ttd,
                tampilkan_qris, tampilkan_diskon, tampilkan_metode, header_tebal, garis, jumlah_salinan,
                catatan_kaki, diperbarui)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
            ON DUPLICATE KEY UPDATE judul = ?, baris1 = ?, baris2 = ?, baris3 = ?, footer1 = ?,
                footer2 = ?, footer3 = ?, lebar_kertas = ?, ukuran_huruf = ?, tampilkan_barcode = ?,
                tampilkan_hp = ?, tampilkan_ttd = ?, tampilkan_qris = ?, tampilkan_diskon = ?,
                tampilkan_metode = ?, header_tebal = ?, garis = ?, jumlah_salinan = ?,
                catatan_kaki = ?, diperbarui = NOW()';

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return ['ok' => false, 'pesan' => 'Gagal menyiapkan simpan struk.', 'struk' => rts_ks_struk_baca($conn, $idSales)];
    }

    // 39 nilai: 20 pada bagian VALUES + 19 pada bagian UPDATE.
    // Dipecah begitu supaya jumlah dan urutannya pasti tepat.
    $jenis = str_repeat('s', 8) . 'is' . str_repeat('i', 7) . 'sis';
    $jenis .= str_repeat('s', 7) . 'is' . str_repeat('i', 7) . 'sis';

    $stmt->bind_param(
        $jenis,
        $idSales,
        $nilai['judul'],
        $nilai['baris1'],
        $nilai['baris2'],
        $nilai['baris3'],
        $nilai['footer1'],
        $nilai['footer2'],
        $nilai['footer3'],
        $nilai['lebar_kertas'],
        $ukuran,
        $nilai['tampilkan_barcode'],
        $nilai['tampilkan_hp'],
        $nilai['tampilkan_ttd'],
        $nilai['tampilkan_qris'],
        $nilai['tampilkan_diskon'],
        $nilai['tampilkan_metode'],
        $nilai['header_tebal'],
        $garis,
        $nilai['jumlah_salinan'],
        $nilai['catatan_kaki'],
        $nilai['judul'],
        $nilai['baris1'],
        $nilai['baris2'],
        $nilai['baris3'],
        $nilai['footer1'],
        $nilai['footer2'],
        $nilai['footer3'],
        $nilai['lebar_kertas'],
        $ukuran,
        $nilai['tampilkan_barcode'],
        $nilai['tampilkan_hp'],
        $nilai['tampilkan_ttd'],
        $nilai['tampilkan_qris'],
        $nilai['tampilkan_diskon'],
        $nilai['tampilkan_metode'],
        $nilai['header_tebal'],
        $garis,
        $nilai['jumlah_salinan'],
        $nilai['catatan_kaki']
    );

    $ok = $stmt->execute();

    if (!$ok) {
        $galat = $conn->error;
        $stmt->close();

        return ['ok' => false, 'pesan' => 'Gagal menyimpan struk: ' . $galat, 'struk' => rts_ks_struk_baca($conn, $idSales)];
    }

    $stmt->close();

    return ['ok' => true, 'pesan' => 'Template struk disimpan.', 'struk' => rts_ks_struk_baca($conn, $idSales)];
}

/* ==========================================================================
 *  BAGIAN 8 - RINGKASAN & HAK AKSES
 * ========================================================================== */

/**
 * Ringkasan hari ini untuk halaman depan menu Barang Bawaan / Kasir.
 *
 * @param array<string,mixed> $user
 * @return array<string,mixed>
 */
function rts_ks_ringkas(mysqli $conn, array $user, string $tanggal = ''): array
{
    $idSales = rts_ks_sales_id($user);
    $hari = $tanggal !== '' ? date('Y-m-d', strtotime($tanggal)) : date('Y-m-d');

    $hasil = [
        'tanggal' => $hari,
        'jumlah_nota' => 0,
        'total_jual' => 0.0,
        'total_jual_teks' => '0',
        'cash' => 0.0,
        'cash_teks' => '0',
        'piutang_baru' => 0.0,
        'piutang_baru_teks' => '0',
        'piutang_belum' => 0.0,
        'piutang_belum_teks' => '0',
        'jumlah_produk' => 0,
        'nilai_stok' => 0.0,
        'nilai_stok_teks' => '0',
    ];

    if (!rts_ks_ada_tabel($conn, 'rts_ks_penjualan')) {
        return $hasil;
    }

    $stmt = $conn->prepare(
        'SELECT COUNT(*) AS jumlah, COALESCE(SUM(total), 0) AS total,
                COALESCE(SUM(CASE WHEN metode = \'CASH\' THEN total ELSE 0 END), 0) AS cash
         FROM rts_ks_penjualan
         WHERE id_sales = ? AND dibatalkan = 0 AND DATE(tanggal) = ?'
    );

    if ($stmt) {
        $stmt->bind_param('ss', $idSales, $hari);
        $stmt->execute();
        $res = $stmt->get_result();
        $baris = $res ? $res->fetch_assoc() : null;
        $stmt->close();

        if ($baris) {
            $hasil['jumlah_nota'] = (int) $baris['jumlah'];
            $hasil['total_jual'] = (float) $baris['total'];
            $hasil['total_jual_teks'] = rts_ks_uang($baris['total']);
            $hasil['cash'] = (float) $baris['cash'];
            $hasil['cash_teks'] = rts_ks_uang($baris['cash']);
        }
    }

    if (rts_ks_ada_tabel($conn, 'rts_ks_piutang')) {
        $stmt = $conn->prepare(
            'SELECT COALESCE(SUM(CASE WHEN DATE(tanggal) = ? THEN total ELSE 0 END), 0) AS baru,
                    COALESCE(SUM(CASE WHEN status IN (\'BELUM\', \'SEBAGIAN\') THEN sisa ELSE 0 END), 0) AS belum
             FROM rts_ks_piutang
             WHERE id_sales = ?'
        );

        if ($stmt) {
            $stmt->bind_param('ss', $hari, $idSales);
            $stmt->execute();
            $res = $stmt->get_result();
            $baris = $res ? $res->fetch_assoc() : null;
            $stmt->close();

            if ($baris) {
                $hasil['piutang_baru'] = (float) $baris['baru'];
                $hasil['piutang_baru_teks'] = rts_ks_uang($baris['baru']);
                $hasil['piutang_belum'] = (float) $baris['belum'];
                $hasil['piutang_belum_teks'] = rts_ks_uang($baris['belum']);
            }
        }
    }

    if (rts_ks_ada_tabel($conn, 'rts_ks_stok') && rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        $stmt = $conn->prepare(
            'SELECT COUNT(*) AS jumlah,
                    COALESCE(SUM(s.pack * p.harga_pack + s.batang * p.harga_batang), 0) AS nilai
             FROM rts_ks_stok s
             INNER JOIN rts_ks_produk p ON p.id = s.produk_id
             WHERE s.id_sales = ? AND (s.pack > 0 OR s.batang > 0)'
        );

        if ($stmt) {
            $stmt->bind_param('s', $idSales);
            $stmt->execute();
            $res = $stmt->get_result();
            $baris = $res ? $res->fetch_assoc() : null;
            $stmt->close();

            if ($baris) {
                $hasil['jumlah_produk'] = (int) $baris['jumlah'];
                $hasil['nilai_stok'] = (float) $baris['nilai'];
                $hasil['nilai_stok_teks'] = rts_ks_uang($baris['nilai']);
            }
        }
    }

    return $hasil;
}

/**
 * Menentukan apakah pengguna boleh memakai fitur kasir.
 *
 * Aturan:
 *   - ADMIN dan ASS selalu boleh (untuk mengelola & menguji).
 *   - Bila setelan mode_akses = SEMUA, seluruh akun boleh (masa perkenalan).
 *   - Selain itu fitur hanya untuk akun PRO (berlangganan atau masa uji coba).
 *
 * @param array<string,mixed> $user
 * @return array<string,mixed>
 */
function rts_ks_akses(mysqli $conn, array $user): array
{
    $role = strtoupper((string) ($user['role'] ?? ''));

    $hasil = [
        'boleh' => false,
        'mode' => 'PRO',
        'pesan' => '',
        'sisa_hari' => 0,
        'label' => 'GRATIS',
    ];

    if (in_array($role, ['ADMIN', 'ASS'], true)) {
        $hasil['boleh'] = true;
        $hasil['mode'] = 'PENGELOLA';
        $hasil['label'] = 'PRO';

        return $hasil;
    }

    if (strtoupper(rts_ks_setelan_baca($conn, 'mode_akses', 'PRO')) === 'SEMUA') {
        $hasil['boleh'] = true;
        $hasil['mode'] = 'SEMUA';
        $hasil['label'] = 'PRO';

        return $hasil;
    }

    if (function_exists('rts_lg_baris') && function_exists('rts_lg_status')) {
        $baris = rts_lg_baris($conn, (int) ($user['id'] ?? 0));

        if (is_array($baris)) {
            $status = rts_lg_status($baris);

            $hasil['label'] = (string) ($status['label'] ?? 'GRATIS');
            $hasil['sisa_hari'] = (int) ($status['sisa_hari'] ?? 0);
            $hasil['trial_aktif'] = !empty($status['trial_aktif']);
            $hasil['sisa_trial_hari'] = (int) ($status['sisa_trial_hari'] ?? 0);
            $hasil['harga'] = (int) ($status['harga'] ?? 0);
            $hasil['berlaku_sampai'] = (string) ($status['berlaku_sampai'] ?? '');
            $hasil['boleh'] = !empty($status['pro']);
        }
    }

    if (!$hasil['boleh'] && (int) ($user['akun_pro'] ?? 0) === 1) {
        $hasil['boleh'] = true;
        $hasil['label'] = 'PRO';
    }

    if (!$hasil['boleh']) {
        $hasil['pesan'] = 'Fitur Barang Bawaan & Kasir tersedia untuk Akun PRO. '
            . 'Buka menu Langganan PRO untuk mengaktifkannya (masa uji coba 7 hari gratis).';
    }

    return $hasil;
}
