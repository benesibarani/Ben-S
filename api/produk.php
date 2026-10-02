<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API DAFTAR PRODUK (PRODUK BERSAMA)
 *  Berkas : api/produk.php
 *  Versi  : 1   (3 Oktober 2026)
 *
 *  Dipanggil aplikasi Android dengan token login (Authorization: Bearer ...).
 *
 *  Tabel database yang dipakai: `produk`
 *  (dibuat oleh berkas database/migrations/RTS_PANEL_PRODUK.sql, atau otomatis
 *   oleh berkas ini bila belum ada)
 *
 *  DAFTAR PERINTAH (parameter "aksi")
 *  ---------------------------------
 *    hitung    jumlah produk (untuk pemeriksaan cepat)
 *    daftar    daftar produk: parameter q, sejak, semua, batas
 *    simpan    menambah / mengubah satu produk
 *    impor     menambah / mengubah BANYAK produk sekaligus (dipakai sinkron
 *              dari aplikasi: mengirim produk yang baru dibuat di HP)
 *    hapus     menonaktifkan produk (permanen=1 -> dihapus sungguhan, ADMIN)
 *    aktifkan  memakai kembali produk yang tadi dinonaktifkan
 *
 *  CATATAN ATURAN
 *  --------------
 *    - Semua user yang sudah login boleh MENAMBAH produk (seperti sebelumnya
 *      di HP), karena sales memang menambah barang yang dibawanya.
 *    - Menghapus permanen dan menonaktifkan hanya ADMIN / ASS.
 *    - Barcode hanya untuk BUNGKUS. Tidak ada barcode batang.
 *    - Harga di tabel ini berlaku SAMA untuk semua sales.
 *    - Stok TIDAK disimpan di server (stok ada di HP masing-masing sales).
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (!in_array($metode, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$masukan = rts_api_input();
$aksi = strtolower(rts_api_param('aksi', 'daftar'));

$role = strtoupper((string) ($user['role'] ?? ''));
$namaUser = trim((string) ($user['nama_lengkap'] ?? ''));

if ($namaUser === '') {
    $namaUser = (string) ($user['username'] ?? 'USER');
}

/* ------------------------------------------------------------------ tabel */

/**
 * Perintah pembuatan tabel produk (sama persis dengan berkas SQL migrasi).
 * Dipakai untuk memastikan tabel ada, sehingga API tetap jalan walaupun
 * berkas SQL belum sempat dijalankan di phpMyAdmin.
 */
function rts_pr_sql_tabel(): string
{
    return 'CREATE TABLE IF NOT EXISTS `produk` (
      `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
      `sku`              VARCHAR(64)  NOT NULL DEFAULT \'\',
      `barcode_bungkus`  VARCHAR(64)  NULL     DEFAULT NULL,
      `nama`             VARCHAR(150) NOT NULL,
      `merek`            VARCHAR(80)  NOT NULL DEFAULT \'\',
      `isi_per_bungkus`  INT          NOT NULL DEFAULT 0,
      `harga_bungkus`    DECIMAL(14,2) NOT NULL DEFAULT 0,
      `harga_batang`     DECIMAL(14,2) NOT NULL DEFAULT 0,
      `catatan`          VARCHAR(255) NOT NULL DEFAULT \'\',
      `status_aktif`     TINYINT(1)   NOT NULL DEFAULT 1,
      `dibuat_oleh`      VARCHAR(100) NOT NULL DEFAULT \'\',
      `dibuat_pada`      DATETIME     NULL DEFAULT NULL,
      `diubah_oleh`      VARCHAR(100) NOT NULL DEFAULT \'\',
      `diubah_pada`      DATETIME     NULL DEFAULT NULL,
      PRIMARY KEY (`id`),
      UNIQUE KEY `uniq_barcode_bungkus` (`barcode_bungkus`),
      KEY `idx_nama` (`nama`),
      KEY `idx_aktif` (`status_aktif`),
      KEY `idx_diubah` (`diubah_pada`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci';
}

function rts_pr_ada_tabel(mysqli $conn): bool
{
    $hasil = $conn->query("SHOW TABLES LIKE 'produk'");

    if ($hasil instanceof mysqli_result) {
        $ada = $hasil->num_rows > 0;
        $hasil->free();

        return $ada;
    }

    return false;
}

/** Membuat tabel bila belum ada. Mengembalikan pesan kesalahan bila gagal. */
function rts_pr_pastikan_tabel(mysqli $conn): string
{
    if (rts_pr_ada_tabel($conn)) {
        return '';
    }

    if ($conn->query(rts_pr_sql_tabel())) {
        return '';
    }

    return 'Tabel produk belum ada dan tidak dapat dibuat otomatis. '
        . 'Jalankan berkas RTS_PANEL_PRODUK.sql lewat phpMyAdmin. '
        . 'Keterangan server: ' . $conn->error;
}

/* ---------------------------------------------------------------- bantuan */

function rts_pr_teks($nilai, int $maks = 150): string
{
    $teks = trim((string) $nilai);
    $teks = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F]/u', '', $teks);
    $teks = is_string($teks) ? $teks : '';

    if (function_exists('mb_substr')) {
        return mb_substr($teks, 0, $maks, 'UTF-8');
    }

    return substr($teks, 0, $maks);
}

function rts_pr_angka($nilai): float
{
    if (is_string($nilai)) {
        $nilai = str_replace(['Rp', 'rp', ' ', '.'], '', $nilai);
        $nilai = str_replace(',', '.', $nilai);
    }

    $angka = (float) $nilai;

    return $angka > 0 ? $angka : 0.0;
}

function rts_pr_bulat($nilai): int
{
    $angka = (int) round(rts_pr_angka($nilai));

    return $angka > 0 ? $angka : 0;
}

/**
 * Nilai barcode: kosong berarti NULL (supaya banyak produk boleh tanpa
 * barcode, sedangkan UNIQUE tetap menjaga barcode tidak kembar).
 */
function rts_pr_barcode($nilai): ?string
{
    $teks = rts_pr_teks($nilai, 64);

    return $teks === '' ? null : $teks;
}

/** Menyusun satu baris produk menjadi bentuk yang dipakai aplikasi. */
function rts_pr_bentuk(array $b): array
{
    $hargaBungkus = (float) ($b['harga_bungkus'] ?? 0);
    $hargaBatang = (float) ($b['harga_batang'] ?? 0);
    $isi = (int) ($b['isi_per_bungkus'] ?? 0);

    if ($hargaBatang <= 0 && $isi > 0 && $hargaBungkus > 0) {
        $hargaBatang = round($hargaBungkus / $isi / 100) * 100;
    }

    return [
        'id' => (int) ($b['id'] ?? 0),
        'sku' => (string) ($b['sku'] ?? ''),
        'barcode_pack' => (string) ($b['barcode_bungkus'] ?? ''),
        'barcode_bungkus' => (string) ($b['barcode_bungkus'] ?? ''),
        'nama' => (string) ($b['nama'] ?? ''),
        'merek' => (string) ($b['merek'] ?? ''),
        'isi_per_pack' => $isi,
        'isi_per_bungkus' => $isi,
        'harga_pack' => $hargaBungkus,
        'harga_bungkus' => $hargaBungkus,
        'harga_batang' => $hargaBatang,
        'catatan' => (string) ($b['catatan'] ?? ''),
        'aktif' => ((int) ($b['status_aktif'] ?? 1)) === 1,
        'diubah_pada' => (string) ($b['diubah_pada'] ?? ''),
        'diubah_oleh' => (string) ($b['diubah_oleh'] ?? ''),
    ];
}

/* ------------------------------------------------------- pemastian tabel */

$galatTabel = rts_pr_pastikan_tabel($conn);

if ($galatTabel !== '' && $aksi !== 'hitung') {
    rts_api_fail($galatTabel, 500, ['tabel_produk' => false]);
}

/* ============================================================ 1. MENGHITUNG */

if ($aksi === 'hitung') {
    if ($galatTabel !== '') {
        rts_api_fail($galatTabel, 500, ['tabel_produk' => false]);
    }

    $hasil = $conn->query('SELECT COUNT(*) AS jumlah FROM `produk`');
    $jumlah = $hasil instanceof mysqli_result ? (int) ($hasil->fetch_assoc()['jumlah'] ?? 0) : 0;

    rts_api_response(true, "Tabel produk siap. $jumlah produk tersimpan.", [
        'tabel_produk' => true,
        'jumlah' => $jumlah,
    ]);
}

/* =============================================================== 2. DAFTAR */

if ($aksi === 'daftar') {
    $cari = rts_pr_teks(rts_api_param('q', ''), 60);
    $sejak = rts_pr_teks(rts_api_param('sejak', ''), 25);
    $batas = (int) rts_api_param('batas', '500');
    $semua = rts_api_param('semua', '0') === '1';
    $bolehSemua = in_array($role, ['ADMIN', 'ASS'], true);

    if ($batas < 1) {
        $batas = 500;
    }

    if ($batas > 2000) {
        $batas = 2000;
    }

    $where = [];
    $params = [];
    $tipe = '';

    if (!$semua || !$bolehSemua) {
        $where[] = '`status_aktif` = 1';
    }

    if ($cari !== '') {
        $where[] = '(`nama` LIKE ? OR `merek` LIKE ? OR `sku` LIKE ? OR `barcode_bungkus` LIKE ?)';
        $suka = '%' . $cari . '%';
        $params[] = $suka;
        $params[] = $suka;
        $params[] = $suka;
        $params[] = $suka;
        $tipe .= 'ssss';
    }

    if ($sejak !== '') {
        // Sinkron cepat: hanya baris yang berubah setelah waktu terakhir.
        $where[] = '(`diubah_pada` IS NOT NULL AND `diubah_pada` >= ?)';
        $params[] = $sejak;
        $tipe .= 's';
    }

    $sql = 'SELECT * FROM `produk`';

    if ($where) {
        $sql .= ' WHERE ' . implode(' AND ', $where);
    }

    $sql .= ' ORDER BY `nama` ASC, `id` ASC LIMIT ' . $batas;

    $items = [];
    $stmt = $conn->prepare($sql);

    if ($stmt) {
        if ($params) {
            $stmt->bind_param($tipe, ...$params);
        }

        $stmt->execute();
        $hasil = $stmt->get_result();

        while ($hasil && ($baris = $hasil->fetch_assoc())) {
            $items[] = rts_pr_bentuk($baris);
        }

        $stmt->close();
    }

    rts_api_response(true, count($items) . ' produk dibaca dari daftar produk.', [
        'items' => $items,
        'jumlah' => count($items),
        'waktu_server' => date('Y-m-d H:i:s'),
        'tabel_produk' => true,
    ]);
}

/* =============================================================== 3. SIMPAN */

/**
 * Menyimpan satu produk. Dipakai perintah "simpan" dan juga oleh "impor".
 * Mengembalikan array: ['ok' => bool, 'id' => int, 'pesan' => string,
 *                       'dibuat' => bool]
 */
function rts_pr_simpan_satu(mysqli $conn, array $data, string $namaUser): array
{
    $id = (int) ($data['id'] ?? 0);
    $nama = rts_pr_teks($data['nama'] ?? '', 150);

    if (strlen($nama) < 2) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Nama produk terlalu pendek.', 'dibuat' => false];
    }

    $sku = rts_pr_teks($data['sku'] ?? '', 64);
    $barcode = rts_pr_barcode($data['barcode_bungkus'] ?? ($data['barcode_pack'] ?? ''));
    $merek = rts_pr_teks($data['merek'] ?? '', 80);
    $catatan = rts_pr_teks($data['catatan'] ?? '', 255);

    $isi = rts_pr_bulat($data['isi_per_bungkus'] ?? ($data['isi_per_pack'] ?? 0));
    $hargaBungkus = rts_pr_angka($data['harga_bungkus'] ?? ($data['harga_pack'] ?? 0));
    $hargaBatang = rts_pr_angka($data['harga_batang'] ?? 0);

    if ($hargaBatang <= 0 && $isi > 0 && $hargaBungkus > 0) {
        $hargaBatang = round($hargaBungkus / $isi / 100) * 100;
    }

    $aktif = 1;

    if (array_key_exists('status_aktif', $data) || array_key_exists('aktif', $data)) {
        $nilai = $data['status_aktif'] ?? $data['aktif'];
        $aktif = ($nilai === false || $nilai === 0 || $nilai === '0') ? 0 : 1;
    }

    // Barcode tidak boleh kembar.
    if ($barcode !== null) {
        $cek = $conn->prepare('SELECT id, nama FROM `produk` WHERE `barcode_bungkus` = ? LIMIT 1');

        if ($cek) {
            $cek->bind_param('s', $barcode);
            $cek->execute();
            $hasilCek = $cek->get_result();
            $lain = $hasilCek ? $hasilCek->fetch_assoc() : null;
            $cek->close();

            if ($lain && (int) $lain['id'] !== $id) {
                return [
                    'ok' => false,
                    'id' => (int) $lain['id'],
                    'pesan' => 'Barcode ' . $barcode . ' sudah dipakai produk "'
                        . $lain['nama'] . '".',
                    'dibuat' => false,
                ];
            }
        }
    }

    $sekarang = date('Y-m-d H:i:s');

    if ($id > 0) {
        $ada = $conn->prepare('SELECT id, dibuat_oleh, dibuat_pada FROM `produk` WHERE `id` = ? LIMIT 1');

        if (!$ada) {
            return ['ok' => false, 'id' => 0, 'pesan' => 'Produk tidak dapat dibaca: ' . $conn->error, 'dibuat' => false];
        }

        $ada->bind_param('i', $id);
        $ada->execute();
        $hasilAda = $ada->get_result();
        $lama = $hasilAda ? $hasilAda->fetch_assoc() : null;
        $ada->close();

        if (!$lama) {
            return ['ok' => false, 'id' => 0, 'pesan' => "Produk id $id tidak ada di daftar produk.", 'dibuat' => false];
        }

        $ubah = $conn->prepare(
            'UPDATE `produk` SET `sku` = ?, `barcode_bungkus` = ?, `nama` = ?, `merek` = ?,'
            . ' `isi_per_bungkus` = ?, `harga_bungkus` = ?, `harga_batang` = ?, `catatan` = ?,'
            . ' `status_aktif` = ?, `diubah_oleh` = ?, `diubah_pada` = ? WHERE `id` = ?'
        );

        if (!$ubah) {
            return ['ok' => false, 'id' => 0, 'pesan' => 'Produk tidak dapat disimpan: ' . $conn->error, 'dibuat' => false];
        }

        $nilai = [
            $sku, $barcode, $nama, $merek, $isi, $hargaBungkus,
            $hargaBatang, $catatan, $aktif, $namaUser, $sekarang, $id,
        ];
        $ubah->bind_param(str_repeat('s', count($nilai)), ...$nilai);

        $ok = $ubah->execute();
        $galat = $ubah->error;
        $ubah->close();

        if (!$ok) {
            return ['ok' => false, 'id' => $id, 'pesan' => 'Produk gagal diubah: ' . $galat, 'dibuat' => false];
        }

        return ['ok' => true, 'id' => $id, 'pesan' => "Produk \"$nama\" diperbarui.", 'dibuat' => false];
    }

    $tambah = $conn->prepare(
        'INSERT INTO `produk` (`sku`, `barcode_bungkus`, `nama`, `merek`, `isi_per_bungkus`,'
        . ' `harga_bungkus`, `harga_batang`, `catatan`, `status_aktif`, `dibuat_oleh`,'
        . ' `dibuat_pada`, `diubah_oleh`, `diubah_pada`)'
        . ' VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );

    if (!$tambah) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Produk tidak dapat ditambah: ' . $conn->error, 'dibuat' => false];
    }

    $nilai = [
        $sku, $barcode, $nama, $merek, $isi, $hargaBungkus, $hargaBatang,
        $catatan, $aktif, $namaUser, $sekarang, $namaUser, $sekarang,
    ];
    $tambah->bind_param(str_repeat('s', count($nilai)), ...$nilai);

    $ok = $tambah->execute();
    $galat = $tambah->error;
    $idBaru = (int) $conn->insert_id;
    $tambah->close();

    if (!$ok) {
        return ['ok' => false, 'id' => 0, 'pesan' => 'Produk gagal ditambah: ' . $galat, 'dibuat' => false];
    }

    return ['ok' => true, 'id' => $idBaru, 'pesan' => "Produk \"$nama\" ditambahkan ke daftar produk bersama.", 'dibuat' => true];
}

if ($aksi === 'simpan') {
    $hasil = rts_pr_simpan_satu($conn, $masukan, $namaUser);

    if (!$hasil['ok']) {
        rts_api_fail($hasil['pesan'], 400, ['id' => $hasil['id']]);
    }

    // Balasan memuat produk terbaru supaya aplikasi langsung memakainya.
    $produk = null;
    $stmt = $conn->prepare('SELECT * FROM `produk` WHERE `id` = ? LIMIT 1');

    if ($stmt) {
        $id = (int) $hasil['id'];
        $stmt->bind_param('i', $id);
        $stmt->execute();
        $hasilAmbil = $stmt->get_result();
        $baris = $hasilAmbil ? $hasilAmbil->fetch_assoc() : null;
        $stmt->close();

        if ($baris) {
            $produk = rts_pr_bentuk($baris);
        }
    }

    rts_api_response(true, $hasil['pesan'], [
        'id' => (int) $hasil['id'],
        'dibuat' => (bool) $hasil['dibuat'],
        'produk' => $produk,
    ]);
}

/* ================================================================ 4. IMPOR */

if ($aksi === 'impor') {
    $items = $masukan['items'] ?? [];

    if (!is_array($items) || !$items) {
        rts_api_fail('Tidak ada produk yang dikirim untuk disimpan.', 400);
    }

    if (count($items) > 500) {
        rts_api_fail('Terlalu banyak produk dalam satu kali kirim (maksimal 500).', 400);
    }

    $dibuat = 0;
    $diperbarui = 0;
    $gagal = [];
    $peta = [];

    foreach ($items as $item) {
        if (!is_array($item)) {
            continue;
        }

        $hasil = rts_pr_simpan_satu($conn, $item, $namaUser);

        if ($hasil['ok']) {
            if ($hasil['dibuat']) {
                $dibuat++;
            } else {
                $diperbarui++;
            }

            $peta[] = [
                'lokal' => (int) ($item['id_lokal'] ?? 0),
                'barcode' => rts_pr_teks($item['barcode_bungkus'] ?? ($item['barcode_pack'] ?? ''), 64),
                'nama' => rts_pr_teks($item['nama'] ?? '', 150),
                'id_server' => (int) $hasil['id'],
            ];
        } else {
            $gagal[] = [
                'nama' => rts_pr_teks($item['nama'] ?? '', 150),
                'pesan' => $hasil['pesan'],
            ];
        }
    }

    rts_api_response(true, "Sinkron produk: $dibuat baru, $diperbarui diperbarui"
        . (count($gagal) ? ', ' . count($gagal) . ' gagal.' : '.'), [
        'dibuat' => $dibuat,
        'diperbarui' => $diperbarui,
        'gagal' => $gagal,
        'peta' => $peta,
    ]);
}

/* ================================================================ 5. HAPUS */

if ($aksi === 'hapus' || $aksi === 'aktifkan') {
    if (!in_array($role, ['ADMIN', 'ASS'], true)) {
        rts_api_fail('Hanya ADMIN / ASS yang dapat menghapus atau memakai kembali produk.', 403);
    }

    $id = (int) ($masukan['id'] ?? 0);
    $permanen = rts_api_param('permanen', '0') === '1'
        || (isset($masukan['permanen']) && (int) $masukan['permanen'] === 1);

    if ($id <= 0) {
        rts_api_fail('Produk yang akan dihapus belum dipilih.', 400);
    }

    if ($aksi === 'aktifkan') {
        $stmt = $conn->prepare('UPDATE `produk` SET `status_aktif` = 1, `diubah_oleh` = ?, `diubah_pada` = NOW() WHERE `id` = ?');

        if (!$stmt) {
            rts_api_fail('Produk tidak dapat dipakai kembali: ' . $conn->error, 500);
        }

        $stmt->bind_param('si', $namaUser, $id);
        $stmt->execute();
        $st = $stmt->affected_rows;
        $stmt->close();

        rts_api_response(true, $st > 0
            ? 'Produk dipakai kembali.'
            : 'Produk sudah dalam keadaan dipakai.', ['id' => $id, 'aktif' => true]);
    }

    if ($permanen) {
        $stmt = $conn->prepare('DELETE FROM `produk` WHERE `id` = ?');

        if (!$stmt) {
            rts_api_fail('Produk tidak dapat dihapus: ' . $conn->error, 500);
        }

        $stmt->bind_param('i', $id);
        $stmt->execute();
        $st = $stmt->affected_rows;
        $stmt->close();

        rts_api_response(true, $st > 0 ? 'Produk dihapus dari daftar produk bersama.' : 'Produk tidak ditemukan.', [
            'id' => $id,
            'dihapus' => $st > 0,
        ]);
    }

    $stmt = $conn->prepare('UPDATE `produk` SET `status_aktif` = 0, `diubah_oleh` = ?, `diubah_pada` = NOW() WHERE `id` = ?');

    if (!$stmt) {
        rts_api_fail('Produk tidak dapat dinonaktifkan: ' . $conn->error, 500);
    }

    $stmt->bind_param('si', $namaUser, $id);
    $stmt->execute();
    $stmt->close();

    rts_api_response(true, 'Produk dinonaktifkan (tidak lagi muncul di HP sales lain).', [
        'id' => $id,
        'aktif' => false,
    ]);
}

/* ------------------------------------------------------------- tak dikenal */

rts_api_fail('Perintah "' . $aksi . '" tidak dikenal pada API produk.', 400, [
    'aksi_dikenal' => ['hitung', 'daftar', 'simpan', 'impor', 'hapus', 'aktifkan'],
]);
