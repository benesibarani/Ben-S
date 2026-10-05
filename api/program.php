<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API PROGRAM (INTRODEAL & BD)
 *  Berkas : api/program.php
 *  Versi  : 1   (5 Oktober 2026)
 *
 *  Dipanggil aplikasi Android dengan token login (Authorization: Bearer ...).
 *
 *  KEGUNAAN
 *  --------
 *  Menyimpan daftar PRODUK LAUNCHING PT Wismilak supaya dapat disinkron ke
 *  seluruh HP Sales. Dipakai menu PRO "Program" dengan dua sub-menu:
 *
 *      INTRODEAL : produk yang sedang diperkenalkan ke customer
 *      BD        : produk Business Development
 *
 *  PERINTAH (parameter "aksi")
 *  --------------------------
 *    daftar   daftar produk program (bawaan)
 *             parameter jenis=INTRODEAL / BD (kosong = keduanya)
 *    paket_daftar  daftar PAKET Introdeal (2+1, 1+1, paket buatan Sales)
 *    paket_simpan  menambah / mengubah satu paket Introdeal
 *    paket_hapus   menghapus satu paket buatan Sales
 *    input_simpan  menerima CATATAN PROGRAM yang dikirim dari HP Sales
 *                  (dipakai tombol KIRIM KE SERVER pada menu Program)
 *    input_daftar  daftar catatan program yang sudah masuk ke server
 *
 *  KETERANGAN (sesuai penjelasan Bapak)
 *  --------------------------------
 *    INTRODEAL = Introductory Deal, yaitu PROGRAM PAKET. Paket baku yang
 *                selalu ada: "2+1" dan "1+1". Sales juga dapat membuat
 *                paket sendiri (misalnya "3+1") dari aplikasi.
 *    BD        = New Brand Distribution. TIDAK ada program paket -
 *                produknya produk baru yang SUDAH ADA di outlet.
 *    LAIN-LAIN = Sales dapat membuat PROGRAM SENDIRI (nama program bebas,
 *                contoh "PROGRAM GAWIH"). Karena itu kolom `jenis` pada
 *                catatan program menerima nama program apa saja.
 *    simpan   menambah / mengubah satu produk program
 *             parameter: jenis, sku, barcode_pack, nama, merek,
 *                        isi_per_pack, catatan, periode, aktif
 *    hapus    menghapus satu produk program (jenis + sku)
 *    periksa  memeriksa apakah tabel sudah ada + memberi perintah SQL
 *
 *  ATURAN
 *  ------
 *    - Menu ini untuk AKUN PRO. ADMIN dan ASS tetap boleh membuka (pengelola).
 *    - Yang boleh MENULIS ke server hanya ADMIN dan ASS. Peran lain (WSS,
 *      SMST, RTS, TF) hanya MENERIMA daftar lalu menyimpannya di HP.
 *    - API ini TIDAK menyentuh tabel lain milik Bapak. Bila tabel
 *      rts_program_produk belum ada, tabel itu dibuat sendiri (hanya tabel
 *      BARU, tidak ada data lama yang diubah). Perintah SQL lengkapnya juga
 *      dikirim pada aksi periksa, bila ADMIN ingin membuatnya sendiri dulu
 *      lewat phpMyAdmin.
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';

if (is_file(__DIR__ . '/langganan_inti.php')) {
    require_once __DIR__ . '/langganan_inti.php';
}

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (!in_array($metode, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$aksi = strtolower(rts_api_param('aksi', 'daftar'));

/* ------------------------------------------------------------------- aturan */

$role = strtoupper(trim((string) ($user['role'] ?? '')));
$pengelola = in_array($role, ['ADMIN', 'ASS'], true);

$statusLangganan = [];
$akunPro = false;

if (function_exists('rts_lg_baris') && function_exists('rts_lg_status')) {
    try {
        $barisLangganan = rts_lg_baris($conn, (int) ($user['id'] ?? 0));
        $statusLangganan = rts_lg_status($barisLangganan);
        $akunPro = !empty($statusLangganan['pro']);
    } catch (Throwable $galatLangganan) {
        $akunPro = false;
    }
}

if (!$akunPro && !$pengelola) {
    rts_api_fail(
        'Menu Program khusus AKUN PRO. Buka menu Langganan PRO untuk mengaktifkannya, '
        . 'lalu tekan SINKRON AKUN pada menu Sinkronisasi.',
        403,
        [
            'perlu_pro' => true,
            'langganan' => [
                'sumber' => (string) ($statusLangganan['sumber'] ?? 'GRATIS'),
                'harga' => (int) ($statusLangganan['harga'] ?? 0),
                'durasi_hari' => (int) ($statusLangganan['durasi_hari'] ?? 30),
                'trial_hari' => (int) ($statusLangganan['trial_hari'] ?? 7),
            ],
        ]
    );
}

/* ------------------------------------------------------------------ bantuan */

/** Memotong teks dengan aman. */
function rts_pr_potong(string $teks, int $batas): string
{
    return function_exists('mb_substr') ? mb_substr($teks, 0, $batas) : substr($teks, 0, $batas);
}

/** Menyusun angka bulat dari nilai apa pun. */
function rts_pr_bulat($nilai): int
{
    if (is_int($nilai)) {
        return $nilai;
    }

    return (int) round((float) str_replace(',', '.', (string) $nilai));
}

/** Jenis program: INTRODEAL atau BD. */
function rts_pr_jenis(string $nilai): string
{
    $nilai = strtoupper(trim($nilai));

    return $nilai === 'BD' ? 'BD' : 'INTRODEAL';
}

/**
 * Nama PROGRAM dari HP Sales: nama apa saja (huruf besar) sampai 40 huruf.
 *
 * Dipakai pada catatan program, supaya Sales dapat membuat program sendiri di
 * samping INTRODEAL dan BD.
 */
function rts_pr_program(string $nilai): string
{
    $nama = strtoupper(rts_pr_potong(trim($nilai), 40));

    return $nama === '' ? 'INTRODEAL' : $nama;
}

/** Perintah SQL pembuatan tabel (dipakai aksi periksa & simpan). */
function rts_pr_sql(): string
{
    return 'CREATE TABLE IF NOT EXISTS rts_program_produk ('
        . ' id INT AUTO_INCREMENT PRIMARY KEY,'
        . " jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',"
        . " paket VARCHAR(20) NOT NULL DEFAULT '',"
        . " sku VARCHAR(64) NOT NULL DEFAULT '',"
        . " barcode_pack VARCHAR(64) NOT NULL DEFAULT '',"
        . " nama VARCHAR(150) NOT NULL DEFAULT '',"
        . " merek VARCHAR(80) NOT NULL DEFAULT '',"
        . ' isi_per_pack INT NOT NULL DEFAULT 0,'
        . " catatan VARCHAR(255) NOT NULL DEFAULT '',"
        . " periode VARCHAR(60) NOT NULL DEFAULT '',"
        . ' aktif TINYINT NOT NULL DEFAULT 1,'
        . " diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',"
        . ' diubah_pada DATETIME NULL,'
        . ' UNIQUE KEY uq_program_jenis_sku (jenis, sku)'
        . ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
}

/** Perintah SQL pembuat tabel PAKET Introdeal (2+1, 1+1, paket buatan Sales). */
function rts_pr_sql_paket(): string
{
    return 'CREATE TABLE IF NOT EXISTS rts_program_paket ('
        . ' id INT AUTO_INCREMENT PRIMARY KEY,'
        . " jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',"
        . " nama VARCHAR(20) NOT NULL DEFAULT '',"
        . " keterangan VARCHAR(120) NOT NULL DEFAULT '',"
        . ' bawaan TINYINT NOT NULL DEFAULT 0,'
        . " diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',"
        . ' diubah_pada DATETIME NULL,'
        . ' UNIQUE KEY uq_paket_jenis_nama (jenis, nama)'
        . ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
}

/** True bila tabel rts_program_produk sudah ada. */
function rts_pr_tabel_ada(mysqli $conn): bool
{
    $hasil = $conn->query("SHOW TABLES LIKE 'rts_program_produk'");

    if (!$hasil) {
        return false;
    }

    $baris = $hasil->fetch_row();

    return $baris !== null && $baris !== false;
}

/** Perintah SQL pembuat tabel CATATAN PROGRAM dari HP Sales. */
function rts_pr_sql_input(): string
{
    return 'CREATE TABLE IF NOT EXISTS rts_program_input ('
        . ' id INT AUTO_INCREMENT PRIMARY KEY,'
        . " jenis VARCHAR(40) NOT NULL DEFAULT 'INTRODEAL',"
        . " paket VARCHAR(20) NOT NULL DEFAULT '',"
        . " paket_keterangan VARCHAR(120) NOT NULL DEFAULT '',"
        . " id_customer VARCHAR(40) NOT NULL DEFAULT '',"
        . " nama_toko VARCHAR(150) NOT NULL DEFAULT '',"
        . ' produk_id INT NOT NULL DEFAULT 0,'
        . " nama_produk VARCHAR(150) NOT NULL DEFAULT '',"
        . " sku VARCHAR(64) NOT NULL DEFAULT '',"
        . ' jumlah DECIMAL(12,2) NOT NULL DEFAULT 0,'
        . " satuan VARCHAR(20) NOT NULL DEFAULT 'PACK',"
        . " tanggal VARCHAR(20) NOT NULL DEFAULT '',"
        . " catatan VARCHAR(255) NOT NULL DEFAULT '',"
        . " id_sales VARCHAR(40) NOT NULL DEFAULT '',"
        . " nama_sales VARCHAR(80) NOT NULL DEFAULT '',"
        . " id_hp VARCHAR(60) NOT NULL DEFAULT '',"
        . " diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',"
        . ' diubah_pada DATETIME NULL,'
        . ' KEY ix_input_sales (id_sales),'
        . ' KEY ix_input_customer (id_customer)'
        . ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
}

/** True bila tabel catatan program sudah ada. */
function rts_pr_tabel_input_ada(mysqli $conn): bool
{
    $hasil = $conn->query("SHOW TABLES LIKE 'rts_program_input'");

    if (!$hasil) {
        return false;
    }

    $baris = $hasil->fetch_row();

    return $baris !== null && $baris !== false;
}

/** Membuat tabel catatan program bila belum ada. */
function rts_pr_siapkan_input(mysqli $conn): bool
{
    if (!rts_pr_tabel_input_ada($conn) && !$conn->query(rts_pr_sql_input())) {
        return false;
    }

    if (!rts_pr_tabel_input_ada($conn)) {
        return false;
    }

    // Nama program buatan Sales sampai 40 huruf (database yang dibuat sebelum
    // putaran 18I masih VARCHAR(20)).
    $conn->query("ALTER TABLE rts_program_input MODIFY jenis VARCHAR(40) NOT NULL DEFAULT 'INTRODEAL'");

    return true;
}

/** True bila tabel paket sudah ada. */
function rts_pr_tabel_paket_ada(mysqli $conn): bool
{
    $hasil = $conn->query("SHOW TABLES LIKE 'rts_program_paket'");

    if (!$hasil) {
        return false;
    }

    $baris = $hasil->fetch_row();

    return $baris !== null && $baris !== false;
}

/**
 * Membuat tabel PAKET + mengisi paket INTRODEAL bawaan (2+1 dan 1+1).
 *
 * Paket baku hanya diisi bila tabelnya masih kosong, supaya paket buatan
 * Sales tidak pernah tertimpa.
 */
function rts_pr_siapkan_paket(mysqli $conn): bool
{
    if (!rts_pr_tabel_paket_ada($conn) && !$conn->query(rts_pr_sql_paket())) {
        return false;
    }

    if (!rts_pr_tabel_paket_ada($conn)) {
        return false;
    }

    $hasil = $conn->query('SELECT COUNT(*) AS jumlah FROM rts_program_paket');
    $baris = $hasil ? $hasil->fetch_assoc() : null;

    if ($baris && (int) $baris['jumlah'] > 0) {
        return true;
    }

    $conn->query(
        "INSERT IGNORE INTO rts_program_paket (jenis, nama, keterangan, bawaan, diubah_oleh, diubah_pada) "
        . "VALUES ('INTRODEAL', '2+1', 'Beli 2 gratis 1', 1, 'sistem', NOW()), "
        . "('INTRODEAL', '1+1', 'Beli 1 gratis 1', 1, 'sistem', NOW())"
    );

    return true;
}

/** Membuat tabel produk & paket bila belum ada. */
function rts_pr_siapkan_tabel(mysqli $conn): bool
{
    if (!rts_pr_tabel_ada($conn) && !$conn->query(rts_pr_sql())) {
        return false;
    }

    if (!rts_pr_tabel_ada($conn)) {
        return false;
    }

    // Kolom `paket` untuk tabel yang dibuat sebelum putaran 18H.
    $conn->query("ALTER TABLE rts_program_produk ADD COLUMN paket VARCHAR(20) NOT NULL DEFAULT ''");

    if (!rts_pr_siapkan_paket($conn)) {
        return false;
    }

    return rts_pr_siapkan_input($conn);
}

/** Satu baris tabel menjadi bentuk yang dipakai aplikasi. */
function rts_pr_bentuk(array $baris): array
{
    return [
        'id' => (int) ($baris['id'] ?? 0),
        'jenis' => (string) ($baris['jenis'] ?? 'INTRODEAL'),
        'paket' => (string) ($baris['paket'] ?? ''),
        'sku' => (string) ($baris['sku'] ?? ''),
        'barcode_pack' => (string) ($baris['barcode_pack'] ?? ''),
        'nama' => (string) ($baris['nama'] ?? ''),
        'merek' => (string) ($baris['merek'] ?? ''),
        'isi_per_pack' => (int) ($baris['isi_per_pack'] ?? 0),
        'catatan' => (string) ($baris['catatan'] ?? ''),
        'periode' => (string) ($baris['periode'] ?? ''),
        'aktif' => ((int) ($baris['aktif'] ?? 1)) === 1,
        'diubah_oleh' => (string) ($baris['diubah_oleh'] ?? ''),
        'diubah_pada' => (string) ($baris['diubah_pada'] ?? ''),
    ];
}

/* -------------------------------------------------------------------- daftar */

if ($aksi === 'daftar') {
    if (!rts_pr_tabel_ada($conn)) {
        rts_api_response(true, 'Tabel program belum ada di server.', [
            'items' => [],
            'jumlah' => 0,
            'perlu_tabel' => true,
            'sql' => rts_pr_sql(),
            'catatan' => 'ADMIN dapat membuat tabelnya dari aplikasi (tombol '
                . 'SIMPAN KE SERVER) atau lewat phpMyAdmin memakai perintah SQL '
                . 'yang dikirim pada kolom sql.',
        ]);
    }

    $jenis = strtoupper(trim(rts_api_param('jenis')));
    rts_pr_siapkan_tabel($conn);

    $sql = 'SELECT id, jenis, paket, sku, barcode_pack, nama, merek, isi_per_pack, '
        . 'catatan, periode, aktif, diubah_oleh, diubah_pada '
        . 'FROM rts_program_produk';
    $params = [];
    $types = '';

    if ($jenis === 'INTRODEAL' || $jenis === 'BD') {
        $sql .= ' WHERE jenis = ?';
        $params[] = $jenis;
        $types .= 's';
    }

    $sql .= ' ORDER BY jenis ASC, nama ASC';

    $stmt = $conn->prepare($sql);
    $items = [];

    if ($stmt) {
        if ($params) {
            $stmt->bind_param($types, ...$params);
        }

        $stmt->execute();
        $hasil = $stmt->get_result();

        if ($hasil) {
            while (($baris = $hasil->fetch_assoc()) !== null) {
                $items[] = rts_pr_bentuk($baris);
            }
        }

        $stmt->close();
    }

    rts_api_response(true, count($items) . ' produk program di server.', [
        'items' => $items,
        'jumlah' => count($items),
        'jenis' => $jenis,
        'perlu_tabel' => false,
        'boleh_tulis' => $pengelola,
    ]);
}

/* -------------------------------------------------------------------- simpan */

if ($aksi === 'simpan') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN dan ASS yang boleh mengubah daftar program di server.', 403);
    }

    if (!rts_pr_siapkan_tabel($conn)) {
        rts_api_fail(
            'Tabel rts_program_produk belum ada dan tidak dapat dibuat otomatis. '
            . 'Minta ADMIN membuatnya lewat phpMyAdmin memakai perintah SQL pada aksi periksa.',
            500,
            ['perlu_tabel' => true, 'sql' => rts_pr_sql()]
        );
    }

    $jenis = rts_pr_jenis(rts_api_param('jenis', 'INTRODEAL'));
    // BD (New Brand Distribution) TIDAK memakai paket.
    $paket = $jenis === 'BD'
        ? ''
        : strtoupper(rts_pr_potong(trim(rts_api_param('paket')), 20));
    $nama = rts_pr_potong(trim(rts_api_param('nama')), 150);
    $sku = rts_pr_potong(trim(rts_api_param('sku')), 64);
    $barcode = rts_pr_potong(trim(rts_api_param('barcode_pack')), 64);
    $merek = rts_pr_potong(trim(rts_api_param('merek')), 80);
    $catatan = rts_pr_potong(trim(rts_api_param('catatan')), 255);
    $periode = rts_pr_potong(trim(rts_api_param('periode')), 60);
    $isi = rts_pr_bulat(rts_api_param('isi_per_pack', '0'));
    $aktif = rts_api_param('aktif', '1') === '0' ? 0 : 1;

    if ($nama === '') {
        rts_api_fail('Nama produk program belum diisi.');
    }

    // Kunci baris: SKU; bila kosong dipakai barcode; bila keduanya kosong
    // dipakai nama produk (huruf besar).
    if ($sku === '') {
        $sku = $barcode !== '' ? $barcode : strtoupper($nama);
    }

    $diubahOleh = rts_pr_potong((string) ($user['username'] ?? ''), 80);

    $stmt = $conn->prepare(
        'INSERT INTO rts_program_produk '
        . '(jenis, paket, sku, barcode_pack, nama, merek, isi_per_pack, catatan, periode, aktif, diubah_oleh, diubah_pada) '
        . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW()) '
        . 'ON DUPLICATE KEY UPDATE paket = VALUES(paket), barcode_pack = VALUES(barcode_pack), nama = VALUES(nama), '
        . 'merek = VALUES(merek), isi_per_pack = VALUES(isi_per_pack), catatan = VALUES(catatan), '
        . 'periode = VALUES(periode), aktif = VALUES(aktif), diubah_oleh = VALUES(diubah_oleh), '
        . 'diubah_pada = NOW()'
    );

    if (!$stmt) {
        rts_api_fail('Perintah simpan gagal disiapkan pada server.', 500);
    }

    $stmt->bind_param(
        'ssssssisisi',
        $jenis,
        $paket,
        $sku,
        $barcode,
        $nama,
        $merek,
        $isi,
        $catatan,
        $periode,
        $aktif,
        $diubahOleh
    );

    $berhasil = $stmt->execute();

    $stmt->close();

    if (!$berhasil) {
        rts_api_fail('Produk program gagal disimpan di server.', 500);
    }

    rts_api_response(true, 'Produk program tersimpan di server.', [
        'jenis' => $jenis,
        'paket' => $paket,
        'sku' => $sku,
    ]);
}

/* --------------------------------------------------------------------- hapus */

if ($aksi === 'hapus') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN dan ASS yang boleh menghapus daftar program di server.', 403);
    }

    $jenis = rts_pr_jenis(rts_api_param('jenis', 'INTRODEAL'));
    $sku = rts_pr_potong(trim(rts_api_param('sku')), 64);

    if ($sku === '') {
        rts_api_fail('Kode produk (sku) belum diisi.');
    }

    if (!rts_pr_tabel_ada($conn)) {
        rts_api_fail('Tabel program belum ada di server.', 404, ['perlu_tabel' => true]);
    }

    $stmt = $conn->prepare('DELETE FROM rts_program_produk WHERE jenis = ? AND sku = ?');

    if (!$stmt) {
        rts_api_fail('Perintah hapus gagal disiapkan pada server.', 500);
    }

    $stmt->bind_param('ss', $jenis, $sku);
    $berhasil = $stmt->execute();
    $stmt->close();

    if (!$berhasil) {
        rts_api_fail('Produk program gagal dihapus dari server.', 500);
    }

    rts_api_response(true, 'Perintah hapus produk program sudah dijalankan.', [
        'jenis' => $jenis,
        'sku' => $sku,
    ]);
}

/* -------------------------------------------------------------- paket introdeal */

if ($aksi === 'paket_daftar') {
    if (!rts_pr_siapkan_paket($conn)) {
        rts_api_response(true, 'Tabel paket belum ada di server.', [
            'items' => [],
            'jumlah' => 0,
            'perlu_tabel' => true,
            'sql_paket' => rts_pr_sql_paket(),
        ]);
    }

    $jenis = strtoupper(trim(rts_api_param('jenis', 'INTRODEAL')));

    if ($jenis === 'BD') {
        rts_api_response(true, 'Sub-menu BD tidak memakai paket - produknya sudah ada di outlet.', [
            'items' => [],
            'jumlah' => 0,
            'jenis' => 'BD',
            'perlu_tabel' => false,
        ]);
    }

    $stmt = $conn->prepare(
        'SELECT id, jenis, nama, keterangan, bawaan, diubah_oleh, diubah_pada '
        . "FROM rts_program_paket WHERE jenis = 'INTRODEAL' "
        . 'ORDER BY bawaan DESC, id ASC'
    );

    $items = [];
    $hasil = $stmt ? ($stmt->execute() ? $stmt->get_result() : false) : false;

    if ($hasil) {
        while (($baris = $hasil->fetch_assoc()) !== null) {
            $items[] = [
                'id' => (int) $baris['id'],
                'jenis' => (string) $baris['jenis'],
                'nama' => (string) $baris['nama'],
                'keterangan' => (string) $baris['keterangan'],
                'bawaan' => ((int) $baris['bawaan']) === 1,
                'diubah_pada' => (string) ($baris['diubah_pada'] ?? ''),
            ];
        }
    }

    if ($stmt) {
        $stmt->close();
    }

    rts_api_response(true, count($items) . ' paket Introdeal di server.', [
        'items' => $items,
        'jumlah' => count($items),
        'jenis' => 'INTRODEAL',
        'perlu_tabel' => false,
    ]);
}

if ($aksi === 'paket_simpan') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN dan ASS yang boleh mengubah daftar paket di server.', 403);
    }

    if (!rts_pr_siapkan_paket($conn)) {
        rts_api_fail(
            'Tabel rts_program_paket belum ada dan tidak dapat dibuat otomatis.',
            500,
            ['perlu_tabel' => true, 'sql_paket' => rts_pr_sql_paket()]
        );
    }

    $nama = strtoupper(rts_pr_potong(trim(rts_api_param('nama')), 20));
    $keterangan = rts_pr_potong(trim(rts_api_param('keterangan')), 120);

    if ($nama === '') {
        rts_api_fail('Nama paket belum diisi (contoh: 3+1).');
    }

    $diubahOleh = rts_pr_potong((string) ($user['username'] ?? ''), 80);

    $stmt = $conn->prepare(
        'INSERT INTO rts_program_paket (jenis, nama, keterangan, bawaan, diubah_oleh, diubah_pada) '
        . "VALUES ('INTRODEAL', ?, ?, 0, ?, NOW()) "
        . 'ON DUPLICATE KEY UPDATE keterangan = VALUES(keterangan), '
        . 'diubah_oleh = VALUES(diubah_oleh), diubah_pada = NOW()'
    );

    if (!$stmt) {
        rts_api_fail('Perintah simpan paket gagal disiapkan pada server.', 500);
    }

    $stmt->bind_param('sss', $nama, $keterangan, $diubahOleh);
    $berhasil = $stmt->execute();
    $stmt->close();

    if (!$berhasil) {
        rts_api_fail('Paket gagal disimpan di server.', 500);
    }

    rts_api_response(true, 'Paket ' . $nama . ' tersimpan di server.', ['nama' => $nama]);
}

if ($aksi === 'paket_hapus') {
    if (!$pengelola) {
        rts_api_fail('Hanya ADMIN dan ASS yang boleh menghapus paket di server.', 403);
    }

    $nama = strtoupper(rts_pr_potong(trim(rts_api_param('nama')), 20));

    if ($nama === '') {
        rts_api_fail('Nama paket belum diisi.');
    }

    if (!rts_pr_tabel_paket_ada($conn)) {
        rts_api_fail('Tabel paket belum ada di server.', 404, ['perlu_tabel' => true]);
    }

    $stmt = $conn->prepare(
        "DELETE FROM rts_program_paket WHERE jenis = 'INTRODEAL' AND nama = ? AND bawaan = 0"
    );

    if (!$stmt) {
        rts_api_fail('Perintah hapus paket gagal disiapkan pada server.', 500);
    }

    $stmt->bind_param('s', $nama);
    $berhasil = $stmt->execute();
    $stmt->close();

    if (!$berhasil) {
        rts_api_fail('Paket gagal dihapus dari server.', 500);
    }

    rts_api_response(true, 'Paket buatan Sales dihapus dari server (paket bawaan tidak dihapus).', [
        'nama' => $nama,
    ]);
}

/* ------------------------------------------------------------- catatan program */

if ($aksi === 'input_simpan') {
    if (!rts_pr_siapkan_input($conn)) {
        rts_api_fail(
            'Tabel rts_program_input belum ada dan tidak dapat dibuat otomatis.',
            500,
            ['perlu_tabel' => true, 'sql_input' => rts_pr_sql_input()]
        );
    }

    // Jenis = NAMA PROGRAM pilihan Sales (INTRODEAL, BD, atau nama program
    // buatan Sales sendiri).
    $jenis = rts_pr_program(rts_api_param('jenis', 'INTRODEAL'));

    // BD (New Brand Distribution) tidak memakai paket.
    $paket = $jenis === 'BD'
        ? ''
        : strtoupper(rts_pr_potong(trim(rts_api_param('paket')), 20));

    if ($jenis === 'INTRODEAL' && $paket === '') {
        rts_api_fail('Paket Introdeal belum ikut terkirim (contoh: 2+1 atau 1+1).');
    }

    $idCustomer = rts_pr_potong(trim(rts_api_param('id_customer')), 40);
    $namaToko = rts_pr_potong(trim(rts_api_param('nama_toko')), 150);

    if ($idCustomer === '' && $namaToko === '') {
        rts_api_fail('Toko/customer belum ikut terkirim dari HP.');
    }

    $namaProduk = rts_pr_potong(trim(rts_api_param('nama_produk')), 150);
    $catatan = rts_pr_potong(trim(rts_api_param('catatan')), 255);
    $jumlah = (float) str_replace(',', '.', trim(rts_api_param('jumlah', '0')));

    // Produk boleh dikosongkan (cukup catatan), tetapi salah satu harus ada.
    if ($namaProduk === '' && $catatan === '') {
        rts_api_fail('Isi produk atau catatan supaya keterangan program jelas.');
    }

    if ($namaProduk !== '' && $jumlah <= 0) {
        rts_api_fail('Jumlah program harus lebih besar dari 0.');
    }

    $diubahOleh = rts_pr_potong((string) ($user['username'] ?? ''), 80);
    $idHp = rts_pr_potong(trim(rts_api_param('id_hp')), 60);
    $idSales = rts_pr_potong((string) ($user['username'] ?? ''), 40);

    if ($idHp !== '') {
        // Catatan yang sama tidak masuk dua kali bila tombol ditekan ulang.
        $hapus = $conn->prepare('DELETE FROM rts_program_input WHERE id_hp = ? AND id_sales = ?');

        if ($hapus) {
            $hapus->bind_param('ss', $idHp, $idSales);
            $hapus->execute();
            $hapus->close();
        }
    }

    $stmt = $conn->prepare(
        'INSERT INTO rts_program_input '
        . '(jenis, paket, paket_keterangan, id_customer, nama_toko, produk_id, nama_produk, '
        . 'sku, jumlah, satuan, tanggal, catatan, id_sales, nama_sales, id_hp, diubah_oleh, diubah_pada) '
        . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())'
    );

    if (!$stmt) {
        rts_api_fail('Perintah simpan catatan program gagal disiapkan pada server.', 500);
    }

    $paketKeterangan = rts_pr_potong(trim(rts_api_param('paket_keterangan')), 120);
    $produkId = (int) rts_api_param('produk_id', '0');
    $sku = rts_pr_potong(trim(rts_api_param('sku')), 64);
    $satuan = strtoupper(rts_pr_potong(trim(rts_api_param('satuan', 'PACK')), 20));

    if (!in_array($satuan, ['PACK', 'BATANG', 'BALL'], true)) {
        $satuan = 'PACK';
    }
    $tanggal = rts_pr_potong(trim(rts_api_param('tanggal')), 20);
    $namaSales = rts_pr_potong((string) ($user['nama_lengkap'] ?? ''), 80);

    $stmt->bind_param(
        'sssssisdsssssss',
        $jenis,
        $paket,
        $paketKeterangan,
        $idCustomer,
        $namaToko,
        $produkId,
        $namaProduk,
        $sku,
        $jumlah,
        $satuan,
        $tanggal,
        $catatan,
        $idSales,
        $namaSales,
        $idHp,
        $diubahOleh
    );

    $berhasil = $stmt->execute();
    $stmt->close();

    if (!$berhasil) {
        rts_api_fail('Catatan program gagal disimpan di server.', 500);
    }

    rts_api_response(true, 'Catatan program diterima server.', [
        'jenis' => $jenis,
        'paket' => $paket,
        'id_customer' => $idCustomer,
        'jumlah' => $jumlah,
        'satuan' => $satuan,
        'id_hp' => $idHp,
    ]);
}

if ($aksi === 'input_daftar') {
    if (!rts_pr_tabel_input_ada($conn)) {
        rts_api_response(true, 'Tabel catatan program belum ada di server.', [
            'items' => [],
            'jumlah' => 0,
            'perlu_tabel' => true,
            'sql_input' => rts_pr_sql_input(),
        ]);
    }

    // Kosong = seluruh program; selain itu nama program yang diminta.
    $mintaJenis = trim(rts_api_param('jenis', ''));
    $jenis = $mintaJenis === '' ? '' : rts_pr_program($mintaJenis);
    $batas = (int) rts_api_param('batas', '200');
    $batas = $batas < 1 ? 200 : ($batas > 500 ? 500 : $batas);

    $sql = 'SELECT id, jenis, paket, paket_keterangan, id_customer, nama_toko, produk_id, '
        . 'nama_produk, sku, jumlah, satuan, tanggal, catatan, id_sales, nama_sales, diubah_pada '
        . 'FROM rts_program_input';
    $params = [];
    $types = '';

    if ($jenis !== '') {
        $sql .= ' WHERE jenis = ?';
        $params[] = $jenis;
        $types .= 's';
    }

    $sql .= ' ORDER BY id DESC LIMIT ' . $batas;

    $stmt = $conn->prepare($sql);
    $items = [];

    if ($stmt) {
        if ($params) {
            $stmt->bind_param($types, ...$params);
        }

        $stmt->execute();
        $hasil = $stmt->get_result();

        if ($hasil) {
            while (($baris = $hasil->fetch_assoc()) !== null) {
                $items[] = [
                    'id' => (int) $baris['id'],
                    'jenis' => (string) $baris['jenis'],
                    'paket' => (string) $baris['paket'],
                    'paket_keterangan' => (string) $baris['paket_keterangan'],
                    'id_customer' => (string) $baris['id_customer'],
                    'nama_toko' => (string) $baris['nama_toko'],
                    'produk_id' => (int) $baris['produk_id'],
                    'nama_produk' => (string) $baris['nama_produk'],
                    'sku' => (string) $baris['sku'],
                    'jumlah' => (float) $baris['jumlah'],
                    'satuan' => (string) $baris['satuan'],
                    'tanggal' => (string) $baris['tanggal'],
                    'catatan' => (string) $baris['catatan'],
                    'id_sales' => (string) $baris['id_sales'],
                    'nama_sales' => (string) $baris['nama_sales'],
                    'diubah_pada' => (string) ($baris['diubah_pada'] ?? ''),
                ];
            }
        }

        $stmt->close();
    }

    rts_api_response(true, count($items) . ' catatan program di server.', [
        'items' => $items,
        'jumlah' => count($items),
        'jenis' => $jenis,
        'perlu_tabel' => false,
    ]);
}

/* ------------------------------------------------------------------- periksa */

if ($aksi === 'periksa') {
    rts_api_response(true, 'Pemeriksaan tabel program selesai.', [
        'tabel' => rts_pr_tabel_ada($conn),
        'tabel_paket' => rts_pr_tabel_paket_ada($conn),
        'tabel_input' => rts_pr_tabel_input_ada($conn),
        'nama_tabel' => 'rts_program_produk',
        'boleh_tulis' => $pengelola,
        'sql' => rts_pr_sql(),
        'sql_paket' => rts_pr_sql_paket(),
        'sql_input' => rts_pr_sql_input(),
    ]);
}

/* -------------------------------------------------------------------- lainnya */

rts_api_fail('Perintah tidak dikenal: ' . $aksi, 400);
