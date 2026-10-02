<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - API BARANG BAWAAN & KASIR  (FITUR PRO)
 *  Berkas : api/kasir.php
 *  Versi  : 1   (1 Oktober 2026)
 *
 *  Dipanggil aplikasi Android dengan token login (Authorization: Bearer ...).
 *  Seluruh aturan ada pada api/kasir_inti.php; berkas ini hanya pintu masuk.
 *
 *  DAFTAR PERINTAH (parameter "aksi")
 *  ---------------------------------
 *    siap             memeriksa kesiapan tabel kasir
 *    siapkan          membuat tabel yang belum ada (ADMIN)
 *    diagnosa         keterangan lengkap untuk pemeriksaan
 *    akses            status PRO / masa perkenalan
 *    ringkas          ringkasan hari ini (nota, penjualan, piutang, stok)
 *
 *    katalog          daftar produk bersama (tabel `produk`) untuk sinkron
 *    produk_daftar    daftar produk (cari, batas)
 *    produk_ambil     satu produk (id)
 *    produk_barcode   mencari produk dari hasil SCAN (barcode)
 *    produk_simpan    menambah / memperbarui produk
 *    produk_hapus     menonaktifkan / menghapus produk (id)
 *    harga_khusus     harga khusus untuk sales yang sedang masuk
 *
 *    stok_daftar      stok bawaan + nama produk (cari, hanya_ada)
 *    stok_gerak       mencatat barang masuk / rusak / kembali / koreksi
 *    stok_riwayat     riwayat perubahan stok
 *
 *    kasir_simpan     menyimpan nota (CASH / UTANG / TITIP)
 *    kasir_daftar     daftar nota
 *    kasir_ambil      satu nota lengkap dengan barangnya
 *    kasir_batal      membatalkan nota + stok dikembalikan
 *    kasir_cetak      menandai nota sudah dicetak
 *
 *    piutang_daftar   daftar utang & titip
 *    piutang_ambil    satu piutang + riwayat pembayarannya
 *    piutang_bayar    mencatat pembayaran / angsuran
 *
 *    struk_baca       template struk milik sales
 *    struk_simpan     menyimpan template struk
 *    struk_contoh     contoh nota untuk Uji Cetak printer
 *
 *    laporan          laporan penjualan & piutang satu periode
 *    setelan_baca     membaca setelan umum
 *    setelan_simpan   mengubah setelan umum (ADMIN)
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/kolom.php';
require_once __DIR__ . '/langganan_inti.php';
require_once __DIR__ . '/kasir_inti.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if (!in_array($metode, ['GET', 'POST'], true)) {
    rts_api_fail('Method tidak diizinkan.', 405);
}

$user = rts_api_require_user();
$conn = rts_api_db();

$aksi = strtolower(rts_api_param('aksi', 'akses'));
$masukan = rts_api_input();

$role = strtoupper((string) $user['role']);
$idSales = rts_ks_sales_id($user);
$namaSales = rts_ks_nama_sales($user);

/* ------------------------------------------------------- id_sales yang dituju */

/**
 * Menentukan sales yang datanya ingin dilihat.
 * Sales biasa hanya boleh melihat datanya sendiri; pengelola boleh memilih.
 */
$idSalesLihat = $idSales;

if (rts_ks_boleh_semua($user)) {
    $pilihan = rts_ks_teks($masukan['id_sales'] ?? '', 60);

    if ($pilihan !== '') {
        $idSalesLihat = $pilihan;
    }
}

/**
 * Memastikan tabel sudah ada sebelum perintah dijalankan.
 */
function rts_ks_perlu_siap(mysqli $conn): void
{
    if (rts_ks_siap($conn)) {
        return;
    }

    rts_api_fail(
        'Data kasir belum disiapkan di server. Buka menu Barang Bawaan lalu tekan tombol SIAPKAN DATA KASIR.',
        409,
        ['perlu_siap' => true, 'aksi_siap' => 'siapkan']
    );
}

/* ==========================================================================
 *  PERINTAH YANG TIDAK MEMERLUKAN AKUN PRO
 * ========================================================================== */

if ($aksi === 'siap') {
    $belum = [];

    foreach (rts_ks_tabel() as $nama) {
        if (!rts_ks_ada_tabel($conn, $nama)) {
            $belum[] = $nama;
        }
    }

    rts_api_response(true, count($belum) === 0 ? 'Data kasir sudah siap.' : 'Data kasir belum disiapkan.', [
        'siap' => count($belum) === 0,
        'versi' => RTS_KS_VERSI,
        'belum' => $belum,
        'boleh_siapkan' => in_array($role, ['ADMIN', 'ASS'], true),
    ]);
}

if ($aksi === 'siapkan') {
    if (!in_array($role, ['ADMIN', 'ASS'], true)) {
        rts_api_fail('Hanya ADMIN yang dapat menyiapkan data kasir.', 403);
    }

    $hasil = rts_ks_siapkan_database($conn);

    rts_api_response($hasil['ok'], $hasil['pesan'], [
        'siap' => rts_ks_siap($conn),
        'versi' => RTS_KS_VERSI,
        'dibuat' => $hasil['dibuat'],
        'gagal' => $hasil['gagal'],
    ]);
}

if ($aksi === 'diagnosa') {
    $belum = [];
    $ada = [];

    foreach (rts_ks_tabel() as $nama) {
        if (rts_ks_ada_tabel($conn, $nama)) {
            $ada[] = $nama;
        } else {
            $belum[] = $nama;
        }
    }

    $jumlahProduk = 0;
    $jumlahNota = 0;

    if (rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        $res = $conn->query('SELECT COUNT(*) AS total FROM rts_ks_produk');
        $baris = $res ? $res->fetch_assoc() : null;
        $jumlahProduk = $baris ? (int) $baris['total'] : 0;
    }

    if (rts_ks_ada_tabel($conn, 'rts_ks_penjualan')) {
        $res = $conn->query('SELECT COUNT(*) AS total FROM rts_ks_penjualan');
        $baris = $res ? $res->fetch_assoc() : null;
        $jumlahNota = $baris ? (int) $baris['total'] : 0;
    }

    rts_api_response(true, 'Pemeriksaan selesai.', [
        'versi' => RTS_KS_VERSI,
        'siap' => count($belum) === 0,
        'tabel_ada' => $ada,
        'tabel_belum' => $belum,
        'jumlah_produk' => $jumlahProduk,
        'jumlah_nota' => $jumlahNota,
        'mode_akses' => rts_ks_setelan_baca($conn, 'mode_akses', 'PRO'),
    ]);
}

if ($aksi === 'akses') {
    $akses = rts_ks_akses($conn, $user);

    $qris = function_exists('rts_lg_qris') ? rts_lg_qris() : [];

    rts_api_response(true, (string) ($akses['pesan'] ?? 'Fitur kasir dapat dipakai.'), [
        'akses' => $akses,
        'siap' => rts_ks_siap($conn),
        'qris' => $qris,
        'harga' => function_exists('rts_lg_harga') ? rts_lg_harga() : 0,
        'durasi_hari' => function_exists('rts_lg_durasi') ? rts_lg_durasi() : 30,
        'trial_hari' => function_exists('rts_lg_trial') ? rts_lg_trial() : 7,
    ]);
}

/* ==========================================================================
 *  KATALOG PRODUK (dibaca dari tabel `produk` yang sama dengan API produk)
 *
 *  Perintah ini dipakai aplikasi versi lama yang memanggil
 *  kasir.php?aksi=katalog. Sumber datanya adalah tabel `produk` pada
 *  database (daftar produk bersama). Bila tabel itu belum ada, dipakai tabel
 *  lama rts_ks_produk supaya tidak ada yang berhenti bekerja.
 * ========================================================================== */

if ($aksi === 'katalog') {
    $cari = rts_ks_teks(rts_api_param('q', ''), 60);
    $items = [];

    $adaProdukBaru = rts_api_ada_kolom($conn, 'produk', 'barcode_bungkus');

    if ($adaProdukBaru) {
        $sql = 'SELECT * FROM `produk` WHERE `status_aktif` = 1';

        if ($cari !== '') {
            $aman = $conn->real_escape_string($cari);
            $sql .= " AND (`nama` LIKE '%$aman%' OR `merek` LIKE '%$aman%'"
                . " OR `sku` LIKE '%$aman%' OR `barcode_bungkus` LIKE '%$aman%')";
        }

        $sql .= ' ORDER BY `nama` ASC LIMIT 500';
        $hasil = $conn->query($sql);

        while ($hasil && ($baris = $hasil->fetch_assoc())) {
            $hargaBungkus = (float) ($baris['harga_bungkus'] ?? 0);
            $hargaBatang = (float) ($baris['harga_batang'] ?? 0);
            $isi = (int) ($baris['isi_per_bungkus'] ?? 0);

            if ($hargaBatang <= 0 && $isi > 0 && $hargaBungkus > 0) {
                $hargaBatang = round($hargaBungkus / $isi / 100) * 100;
            }

            $items[] = [
                'id' => (int) $baris['id'],
                'nama' => (string) $baris['nama'],
                'merek' => (string) ($baris['merek'] ?? ''),
                'barcode_pack' => (string) ($baris['barcode_bungkus'] ?? ''),
                'barcode_batang' => '',
                'isi_per_pack' => $isi,
                'harga_pack' => $hargaBungkus,
                'harga_batang' => $hargaBatang,
                'catatan' => (string) ($baris['catatan'] ?? ''),
                'aktif' => true,
                'diubah_pada' => (string) ($baris['diubah_pada'] ?? ''),
            ];
        }
    } elseif (rts_ks_ada_tabel($conn, 'rts_ks_produk')) {
        foreach (rts_ks_produk_cari($conn, $cari, 500) as $satu) {
            $items[] = $satu;
        }
    }

    rts_api_response(true, count($items) . ' produk pada katalog.', [
        'items' => $items,
        'jumlah' => count($items),
        'sumber' => $adaProdukBaru ? 'produk' : 'rts_ks_produk',
    ]);
}

/* ==========================================================================
 *  PENGAMAN AKUN PRO UNTUK SELURUH PERINTAH BERIKUTNYA
 * ========================================================================== */

$akses = rts_ks_akses($conn, $user);

if (empty($akses['boleh'])) {
    rts_api_fail(
        (string) ($akses['pesan'] ?? 'Fitur ini hanya untuk Akun PRO.'),
        403,
        [
            'perlu_pro' => true,
            'akses' => $akses,
            'qris' => function_exists('rts_lg_qris') ? rts_lg_qris() : [],
            'harga' => function_exists('rts_lg_harga') ? rts_lg_harga() : 0,
        ]
    );
}

/* ==========================================================================
 *  RINGKASAN HARI INI
 * ========================================================================== */

if ($aksi === 'ringkas') {
    rts_ks_perlu_siap($conn);

    $userLihat = $user;
    $userLihat['username'] = $idSalesLihat;

    $tanggal = rts_ks_teks(rts_api_param('tanggal', ''), 20);

    $ringkas = rts_ks_ringkas($conn, $userLihat, $tanggal);
    $ringkas['id_sales'] = $idSalesLihat;

    rts_api_response(true, 'Ringkasan ' . $ringkas['tanggal'], ['ringkas' => $ringkas]);
}

/* ==========================================================================
 *  PRODUK
 * ========================================================================== */

if ($aksi === 'produk_daftar') {
    rts_ks_perlu_siap($conn);

    $cari = rts_ks_teks(rts_api_param('cari', ''), 60);
    $batas = (int) rts_api_param('batas', '60');
    $semua = rts_api_param('semua', '0') === '1';

    $daftar = rts_ks_produk_cari($conn, $cari, $batas, !$semua);

    rts_api_response(true, count($daftar) . ' produk ditemukan.', [
        'items' => $daftar,
        'jumlah' => count($daftar),
    ]);
}

if ($aksi === 'produk_ambil') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $produk = rts_ks_produk_ambil($conn, $id, $idSales);

    if (!$produk) {
        rts_api_fail('Produk tidak ditemukan.', 404);
    }

    rts_api_response(true, 'Produk ditemukan.', ['produk' => $produk]);
}

if ($aksi === 'produk_barcode') {
    rts_ks_perlu_siap($conn);

    $kode = rts_ks_teks(rts_api_param('barcode', ''), 64);

    if ($kode === '') {
        rts_api_fail('Barcode belum terbaca.');
    }

    $hasil = rts_ks_produk_dari_barcode($conn, $kode);

    if (!$hasil) {
        // Dijawab dengan kode 200 supaya aplikasi menampilkan pesan yang benar
        // ("barcode belum terdaftar"), bukan pesan berkas API tidak ada.
        rts_api_response(false, 'Barcode ' . $kode . ' belum ada pada daftar produk.', [
            'ditemukan' => false,
            'barcode' => $kode,
        ]);
    }

    $produk = rts_ks_produk_ambil($conn, (int) $hasil['produk']['id'], $idSales);
    $saldo = rts_ks_stok_saldo($conn, $idSales, (int) $hasil['produk']['id']);

    rts_api_response(true, 'Produk ditemukan: ' . $hasil['produk']['nama'], [
        'ditemukan' => true,
        'satuan' => (string) $hasil['satuan'],
        'produk' => $produk ? $produk : $hasil['produk'],
        'stok_pack' => $saldo['pack'],
        'stok_batang' => $saldo['batang'],
        'stok_teks' => rts_ks_stok_teks($saldo['pack'], $saldo['batang']),
    ]);
}

if ($aksi === 'produk_simpan') {
    rts_ks_perlu_siap($conn);

    $hasil = rts_ks_produk_simpan($conn, $masukan, $user);

    rts_api_response($hasil['ok'], $hasil['pesan'], [
        'id' => $hasil['id'],
        'produk' => $hasil['id'] > 0 ? rts_ks_produk_ambil($conn, (int) $hasil['id'], $idSales) : null,
    ], $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'produk_hapus') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');

    if (!in_array($role, ['ADMIN', 'ASS'], true)) {
        // Sales hanya boleh menghapus produk yang ia buat sendiri.
        $produk = rts_ks_produk_ambil($conn, $id, $idSales);

        if (!$produk) {
            rts_api_fail('Produk tidak ditemukan.', 404);
        }
    }

    $hasil = rts_ks_produk_hapus($conn, $id, $user);

    rts_api_response($hasil['ok'], $hasil['pesan'], [], $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'harga_khusus') {
    rts_ks_perlu_siap($conn);

    $produkId = (int) rts_api_param('produk_id', '0');
    $hasil = rts_ks_harga_khusus_simpan(
        $conn,
        $produkId,
        $idSales,
        rts_api_param('harga_pack', '0'),
        rts_api_param('harga_batang', '0')
    );

    rts_api_response($hasil['ok'], $hasil['pesan'], [
        'produk' => rts_ks_produk_ambil($conn, $produkId, $idSales),
    ], $hasil['ok'] ? 200 : 400);
}

/* ==========================================================================
 *  STOK BARANG BAWAAN
 * ========================================================================== */

if ($aksi === 'stok_daftar') {
    rts_ks_perlu_siap($conn);

    $cari = rts_ks_teks(rts_api_param('cari', ''), 60);
    $hanyaAda = rts_api_param('hanya_ada', '0') === '1';

    $daftar = rts_ks_stok_daftar($conn, $idSalesLihat, $cari, $hanyaAda);

    $jumlahPack = 0;
    $jumlahBatang = 0;
    $nilai = 0.0;

    foreach ($daftar as $item) {
        $jumlahPack += (int) $item['stok_pack'];
        $jumlahBatang += (int) $item['stok_batang'];
        $nilai += (float) $item['nilai'];
    }

    rts_api_response(true, count($daftar) . ' produk pada daftar barang bawaan.', [
        'items' => $daftar,
        'jumlah' => count($daftar),
        'id_sales' => $idSalesLihat,
        'total_pack' => $jumlahPack,
        'total_batang' => $jumlahBatang,
        'nilai' => $nilai,
        'nilai_teks' => rts_ks_uang($nilai),
    ]);
}

if ($aksi === 'stok_gerak') {
    rts_ks_perlu_siap($conn);

    $produkId = (int) rts_api_param('produk_id', '0');
    $jenis = strtoupper(rts_ks_teks(rts_api_param('jenis', 'MASUK'), 12));
    $pack = rts_ks_bulat(rts_api_param('pack', '0'));
    $batang = rts_ks_bulat(rts_api_param('batang', '0'));
    $keterangan = rts_ks_teks(rts_api_param('keterangan', ''), 255);

    if (!in_array($jenis, ['MASUK', 'RUSAK', 'KEMBALI', 'KOREKSI', 'OPNAME'], true)) {
        rts_api_fail('Jenis perubahan stok tidak dikenal.');
    }

    $produk = rts_ks_produk_ambil($conn, $produkId, $idSales);

    if (!$produk) {
        rts_api_fail('Produk tidak ditemukan.', 404);
    }

    if ($pack === 0 && $batang === 0) {
        rts_api_fail('Jumlah pack atau batang belum diisi.');
    }

    $dPack = $pack;
    $dBatang = $batang;

    if (in_array($jenis, ['RUSAK', 'KEMBALI'], true)) {
        // Barang keluar dari tas: jumlah dikurangi.
        $dPack = -abs($pack);
        $dBatang = -abs($batang);
    }

    if ($jenis === 'OPNAME') {
        // Opname: angka yang diketik adalah SISA sebenarnya.
        $saldo = rts_ks_stok_saldo($conn, $idSales, $produkId);
        $dPack = $pack - $saldo['pack'];
        $dBatang = $batang - $saldo['batang'];
        $keterangan = $keterangan !== '' ? $keterangan : 'Penyesuaian hasil hitung fisik';
    }

    $hasil = rts_ks_stok_ubah(
        $conn,
        $idSales,
        $namaSales,
        $produkId,
        $jenis,
        $dPack,
        $dBatang,
        $keterangan,
        'STOK',
        0
    );

    rts_api_response($hasil['ok'], $hasil['pesan'], [
        'stok_pack' => $hasil['pack'],
        'stok_batang' => $hasil['batang'],
        'stok_teks' => rts_ks_stok_teks((int) $hasil['pack'], (int) $hasil['batang']),
        'nama_produk' => (string) $produk['nama'],
    ], $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'stok_riwayat') {
    rts_ks_perlu_siap($conn);

    $produkId = (int) rts_api_param('produk_id', '0');
    $batas = (int) rts_api_param('batas', '150');

    $daftar = rts_ks_stok_riwayat($conn, $idSalesLihat, $produkId, $batas);

    rts_api_response(true, count($daftar) . ' catatan perubahan stok.', [
        'items' => $daftar,
        'jumlah' => count($daftar),
        'id_sales' => $idSalesLihat,
    ]);
}

/* ==========================================================================
 *  KASIR
 * ========================================================================== */

if ($aksi === 'kasir_simpan') {
    rts_ks_perlu_siap($conn);

    $hasil = rts_ks_kasir_simpan($conn, $user, $masukan);

    rts_api_response($hasil['ok'], (string) $hasil['pesan'], $hasil, $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'kasir_daftar') {
    rts_ks_perlu_siap($conn);

    $hasil = rts_ks_kasir_daftar($conn, [
        'id_sales' => $idSalesLihat,
        'cari' => rts_ks_teks(rts_api_param('cari', ''), 60),
        'dari' => rts_ks_teks(rts_api_param('dari', ''), 20),
        'sampai' => rts_ks_teks(rts_api_param('sampai', ''), 20),
        'belum_lunas' => rts_api_param('belum_lunas', '0') === '1',
        'batas' => (int) rts_api_param('batas', '60'),
    ]);

    rts_api_response(true, $hasil['jumlah'] . ' nota ditemukan.', $hasil);
}

if ($aksi === 'kasir_ambil') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $nota = rts_ks_kasir_ambil($conn, $id);

    if (!$nota) {
        rts_api_fail('Nota tidak ditemukan.', 404);
    }

    if (!rts_ks_boleh_semua($user) && $nota['id_sales'] !== $idSales) {
        rts_api_fail('Nota ini bukan milik Anda.', 403);
    }

    rts_api_response(true, 'Nota ' . $nota['nomor'], ['nota' => $nota]);
}

if ($aksi === 'kasir_batal') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $alasan = rts_ks_teks(rts_api_param('alasan', ''), 200);

    $hasil = rts_ks_kasir_batal($conn, $id, $alasan, $user);

    rts_api_response($hasil['ok'], $hasil['pesan'], [], $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'kasir_cetak') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $nota = rts_ks_kasir_ambil($conn, $id);

    if (!$nota) {
        rts_api_fail('Nota tidak ditemukan.', 404);
    }

    if (!rts_ks_boleh_semua($user) && $nota['id_sales'] !== $idSales) {
        rts_api_fail('Nota ini bukan milik Anda.', 403);
    }

    rts_ks_kasir_tandai_cetak($conn, $id);

    rts_api_response(true, 'Nota ditandai sudah dicetak.', ['nomor' => $nota['nomor']]);
}

/* ==========================================================================
 *  PIUTANG (UTANG & TITIP)
 * ========================================================================== */

if ($aksi === 'piutang_daftar') {
    rts_ks_perlu_siap($conn);

    $hasil = rts_ks_piutang_daftar($conn, [
        'id_sales' => $idSalesLihat,
        'jenis' => rts_ks_teks(rts_api_param('jenis', ''), 10),
        'status' => rts_ks_teks(rts_api_param('status', ''), 12),
        'cari' => rts_ks_teks(rts_api_param('cari', ''), 60),
        'batas' => (int) rts_api_param('batas', '80'),
    ]);

    $hasil['id_sales'] = $idSalesLihat;

    rts_api_response(true, $hasil['jumlah'] . ' piutang ditemukan.', $hasil);
}

if ($aksi === 'piutang_ambil') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $piutang = rts_ks_piutang_ambil($conn, $id);

    if (!$piutang) {
        rts_api_fail('Piutang tidak ditemukan.', 404);
    }

    rts_api_response(true, 'Piutang ' . $piutang['nomor'], ['piutang' => $piutang]);
}

if ($aksi === 'piutang_bayar') {
    rts_ks_perlu_siap($conn);

    $id = (int) rts_api_param('id', '0');
    $jumlah = rts_api_param('jumlah', '0');
    $metodeBayar = rts_ks_teks(rts_api_param('metode', 'CASH'), 12);
    $catatan = rts_ks_teks(rts_api_param('catatan', ''), 255);

    $hasil = rts_ks_piutang_bayar($conn, $id, $jumlah, $metodeBayar, $catatan, $user);

    rts_api_response($hasil['ok'], $hasil['pesan'], [
        'sisa' => $hasil['sisa'],
        'sisa_teks' => rts_ks_uang($hasil['sisa']),
        'status' => $hasil['status'],
        'piutang' => rts_ks_piutang_ambil($conn, $id),
    ], $hasil['ok'] ? 200 : 400);
}

/* ==========================================================================
 *  STRUK
 * ========================================================================== */

if ($aksi === 'struk_baca') {
    $struk = rts_ks_struk_baca($conn, $idSales);

    rts_api_response(true, 'Template struk.', ['struk' => $struk, 'id_sales' => $idSales]);
}

if ($aksi === 'struk_simpan') {
    rts_ks_perlu_siap($conn);

    $hasil = rts_ks_struk_simpan($conn, $idSales, $masukan);

    rts_api_response($hasil['ok'], $hasil['pesan'], ['struk' => $hasil['struk']], $hasil['ok'] ? 200 : 400);
}

if ($aksi === 'struk_contoh') {
    rts_ks_perlu_siap($conn);

    $struk = rts_ks_struk_baca($conn, $idSales);
    $stok = rts_ks_stok_daftar($conn, $idSales, '', false);

    $items = [];

    foreach ($stok as $produk) {
        if (count($items) >= 2) {
            break;
        }

        $isi = (int) $produk['isi_per_pack'];

        if ((int) $produk['stok_pack'] > 0) {
            $items[] = [
                'nama_produk' => (string) $produk['nama'],
                'satuan' => 'PACK',
                'jumlah' => 2,
                'harga_satuan' => (float) $produk['harga_pack'],
                'subtotal' => 2 * (float) $produk['harga_pack'],
            ];
        }

        if ($isi > 0 && (int) $produk['stok_batang'] >= 3) {
            $items[] = [
                'nama_produk' => (string) $produk['nama'],
                'satuan' => 'BATANG',
                'jumlah' => 3,
                'harga_satuan' => (float) $produk['harga_batang'],
                'subtotal' => 3 * (float) $produk['harga_batang'],
            ];
        }
    }

    if (count($items) === 0) {
        $items[] = [
            'nama_produk' => 'Contoh Produk Rokok 16',
            'satuan' => 'PACK',
            'jumlah' => 2,
            'harga_satuan' => 32000.0,
            'subtotal' => 64000.0,
        ];
        $items[] = [
            'nama_produk' => 'Contoh Produk Rokok 16',
            'satuan' => 'BATANG',
            'jumlah' => 3,
            'harga_satuan' => 2200.0,
            'subtotal' => 6600.0,
        ];
    }

    $total = 0.0;

    foreach ($items as $item) {
        $total += (float) $item['subtotal'];
    }

    $bayar = (float) (ceil($total / 50000) * 50000);

    rts_api_response(true, 'Contoh nota untuk uji cetak.', [
        'struk' => $struk,
        'nota' => [
            'nomor' => 'KS-CONTOH-0001',
            'tanggal' => rts_ks_sekarang(),
            'nama_sales' => $namaSales,
            'nama_customer' => 'TOKO CONTOH UJI CETAK',
            'customer_id' => 'CONTOH',
            'hp_customer' => '',
            'metode' => 'CASH',
            'status' => 'LUNAS',
            'total' => $total,
            'bayar' => $bayar,
            'kembali' => $bayar - $total,
            'items' => $items,
            'contoh' => true,
        ],
    ]);
}

/* ==========================================================================
 *  LAPORAN & SETELAN
 * ========================================================================== */

if ($aksi === 'laporan') {
    rts_ks_perlu_siap($conn);

    $dari = rts_ks_teks(rts_api_param('dari', date('Y-m-01')), 20);
    $sampai = rts_ks_teks(rts_api_param('sampai', date('Y-m-d')), 20);

    $nota = rts_ks_kasir_daftar($conn, [
        'id_sales' => $idSalesLihat,
        'dari' => $dari,
        'sampai' => $sampai,
        'batas' => 200,
    ]);

    $piutang = rts_ks_piutang_daftar($conn, [
        'id_sales' => $idSalesLihat,
        'batas' => 300,
    ]);

    $struk = rts_ks_struk_baca($conn, $idSales);

    $userLihat = $user;
    $userLihat['username'] = $idSalesLihat;

    rts_api_response(true, 'Laporan ' . $dari . ' sampai ' . $sampai, [
        'dari' => $dari,
        'sampai' => $sampai,
        'id_sales' => $idSalesLihat,
        'nota' => $nota,
        'piutang' => $piutang,
        'struk' => $struk,
        'ringkas' => rts_ks_ringkas($conn, $userLihat, date('Y-m-d', strtotime($sampai))),
    ]);
}

if ($aksi === 'setelan_baca') {
    rts_api_response(true, 'Setelan kasir.', [
        'mode_akses' => rts_ks_setelan_baca($conn, 'mode_akses', 'PRO'),
        'versi' => RTS_KS_VERSI,
        'boleh_ubah' => in_array($role, ['ADMIN', 'ASS'], true),
    ]);
}

if ($aksi === 'setelan_simpan') {
    if (!in_array($role, ['ADMIN', 'ASS'], true)) {
        rts_api_fail('Hanya ADMIN yang dapat mengubah setelan kasir.', 403);
    }

    $mode = strtoupper(rts_ks_teks(rts_api_param('mode_akses', ''), 10));

    if (!in_array($mode, ['PRO', 'SEMUA'], true)) {
        rts_api_fail('Pilihan mode akses tidak dikenal. Gunakan PRO atau SEMUA.');
    }

    rts_ks_setelan_tulis($conn, 'mode_akses', $mode);

    rts_api_response(true, $mode === 'SEMUA'
        ? 'Masa perkenalan aktif: seluruh akun dapat memakai fitur kasir.'
        : 'Fitur kasir kembali hanya untuk Akun PRO.', [
        'mode_akses' => $mode,
    ]);
}

/* ==========================================================================
 *  PERINTAH TIDAK DIKENAL
 * ========================================================================== */

rts_api_fail('Perintah "' . $aksi . '" tidak dikenal pada API kasir.', 400, [
    'daftar_aksi' => [
        'siap', 'siapkan', 'diagnosa', 'akses', 'ringkas',
        'produk_daftar', 'produk_ambil', 'produk_barcode', 'produk_simpan', 'produk_hapus', 'harga_khusus',
        'stok_daftar', 'stok_gerak', 'stok_riwayat',
        'kasir_simpan', 'kasir_daftar', 'kasir_ambil', 'kasir_batal', 'kasir_cetak',
        'piutang_daftar', 'piutang_ambil', 'piutang_bayar',
        'struk_baca', 'struk_simpan', 'struk_contoh',
        'laporan', 'setelan_baca', 'setelan_simpan',
    ],
]);
