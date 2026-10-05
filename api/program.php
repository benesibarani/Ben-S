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

/** Perintah SQL pembuatan tabel (dipakai aksi periksa & simpan). */
function rts_pr_sql(): string
{
    return 'CREATE TABLE IF NOT EXISTS rts_program_produk ('
        . ' id INT AUTO_INCREMENT PRIMARY KEY,'
        . " jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',"
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

/** Membuat tabel bila belum ada. */
function rts_pr_siapkan_tabel(mysqli $conn): bool
{
    if (rts_pr_tabel_ada($conn)) {
        return true;
    }

    if (!$conn->query(rts_pr_sql())) {
        return false;
    }

    return rts_pr_tabel_ada($conn);
}

/** Satu baris tabel menjadi bentuk yang dipakai aplikasi. */
function rts_pr_bentuk(array $baris): array
{
    return [
        'id' => (int) ($baris['id'] ?? 0),
        'jenis' => (string) ($baris['jenis'] ?? 'INTRODEAL'),
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
    $sql = 'SELECT id, jenis, sku, barcode_pack, nama, merek, isi_per_pack, '
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
        . '(jenis, sku, barcode_pack, nama, merek, isi_per_pack, catatan, periode, aktif, diubah_oleh, diubah_pada) '
        . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NOW()) '
        . 'ON DUPLICATE KEY UPDATE barcode_pack = VALUES(barcode_pack), nama = VALUES(nama), '
        . 'merek = VALUES(merek), isi_per_pack = VALUES(isi_per_pack), catatan = VALUES(catatan), '
        . 'periode = VALUES(periode), aktif = VALUES(aktif), diubah_oleh = VALUES(diubah_oleh), '
        . 'diubah_pada = NOW()'
    );

    if (!$stmt) {
        rts_api_fail('Perintah simpan gagal disiapkan pada server.', 500);
    }

    $stmt->bind_param(
        'sssssisisi',
        $jenis,
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

/* ------------------------------------------------------------------- periksa */

if ($aksi === 'periksa') {
    rts_api_response(true, 'Pemeriksaan tabel program selesai.', [
        'tabel' => rts_pr_tabel_ada($conn),
        'nama_tabel' => 'rts_program_produk',
        'boleh_tulis' => $pengelola,
        'sql' => rts_pr_sql(),
    ]);
}

/* -------------------------------------------------------------------- lainnya */

rts_api_fail('Perintah tidak dikenal: ' . $aksi, 400);
