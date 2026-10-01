-- ============================================================================
--  RTS PANEL BY BENE - FITUR PRO : BARANG BAWAAN & KASIR
--  Berkas  : database/migrations/RTS_PANEL_KASIR.sql
--  Versi   : 1  (1 Oktober 2026)
--
--  CARA PAKAI
--  ----------
--  Cara termudah  : buka aplikasi - menu "Barang Bawaan" - tekan tombol
--                   "SIAPKAN DATA KASIR" (hanya ADMIN). Tabel dibuat otomatis.
--  Cara manual    : cPanel - phpMyAdmin - pilih database benedics_bene_sales -
--                   tab "Import" - pilih berkas ini - Go.
--
--  CATATAN KEAMANAN
--  ----------------
--  Berkas ini HANYA berisi susunan tabel (CREATE TABLE). Tidak ada satu pun
--  data asli (customer, petugas, penjualan) di dalamnya, sehingga aman
--  disimpan pada penyimpanan mana pun.
--
--  Seluruh tabel berawalan rts_ks_ (ks = kasir & stok) supaya mudah dikenali
--  dan tidak mengganggu tabel yang sudah ada.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. MASTER PRODUK
--    Satu daftar produk dipakai bersama seluruh sales (rokok Wismilak yang
--    dibawa sama). Barang siapa yang menemukan produk baru boleh menambah.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_produk (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  barcode_pack  VARCHAR(64)  NULL COMMENT 'barcode pada bungkus/pack',
  barcode_batang VARCHAR(64) NULL COMMENT 'barcode pada batang (bila ada)',
  nama          VARCHAR(150) NOT NULL,
  merek         VARCHAR(80)  NOT NULL DEFAULT '',
  isi_per_pack  INT          NOT NULL DEFAULT 0 COMMENT 'jumlah batang dalam 1 pack (12/16/20)',
  harga_pack    DECIMAL(14,2) NOT NULL DEFAULT 0,
  harga_batang  DECIMAL(14,2) NOT NULL DEFAULT 0,
  foto          VARCHAR(255) NOT NULL DEFAULT '',
  aktif         TINYINT(1)   NOT NULL DEFAULT 1,
  dibuat_oleh   VARCHAR(60)  NOT NULL DEFAULT '',
  dibuat_pada   DATETIME     NULL,
  diubah_oleh   VARCHAR(60)  NOT NULL DEFAULT '',
  diubah_pada   DATETIME     NULL,
  catatan       VARCHAR(255) NOT NULL DEFAULT '',
  UNIQUE KEY rts_ks_produk_barcode_pack (barcode_pack),
  UNIQUE KEY rts_ks_produk_barcode_batang (barcode_batang),
  KEY rts_ks_produk_nama (nama)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 2. HARGA KHUSUS PER SALES (opsional)
--    Bila harga di sebuah district berbeda, sales dapat menetapkan harga
--    khusus untuk dirinya sendiri. Bila tidak ada baris di sini, harga yang
--    dipakai adalah harga pada tabel rts_ks_produk.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_harga (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  produk_id    INT NOT NULL,
  id_sales     VARCHAR(60) NOT NULL,
  harga_pack   DECIMAL(14,2) NULL,
  harga_batang DECIMAL(14,2) NULL,
  diperbarui   DATETIME NULL,
  UNIQUE KEY rts_ks_harga_sales (produk_id, id_sales)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 3. SALDO STOK BAWAAN PER SALES
--    Disimpan sebagai pack + batang (batang = eceran dari pack yang dibuka),
--    sesuai cara sales menghitung dagangan di dalam tas.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_stok (
  id        INT AUTO_INCREMENT PRIMARY KEY,
  id_sales  VARCHAR(60) NOT NULL,
  produk_id INT NOT NULL,
  pack      INT NOT NULL DEFAULT 0,
  batang    INT NOT NULL DEFAULT 0,
  diubah    DATETIME NULL,
  UNIQUE KEY rts_ks_stok_sales (id_sales, produk_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 4. RIWAYAT PERUBAHAN STOK (buku besar)
--    Setiap barang masuk, terjual, rusak, dikembalikan, atau dikoreksi
--    tercatat di sini beserta jam sampai detik dan saldo sesudahnya.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_stok_gerak (
  id           INT AUTO_INCREMENT PRIMARY KEY,
  tanggal      DATETIME NOT NULL,
  id_sales     VARCHAR(60)  NOT NULL,
  nama_sales   VARCHAR(100) NOT NULL DEFAULT '',
  produk_id    INT NOT NULL,
  jenis        VARCHAR(12) NOT NULL COMMENT 'MASUK, JUAL, RUSAK, KEMBALI, KOREKSI, OPNAME, BATAL',
  pack_delta   INT NOT NULL DEFAULT 0,
  batang_delta INT NOT NULL DEFAULT 0,
  saldo_pack   INT NOT NULL DEFAULT 0,
  saldo_batang INT NOT NULL DEFAULT 0,
  keterangan   VARCHAR(255) NOT NULL DEFAULT '',
  ref_tipe     VARCHAR(12) NOT NULL DEFAULT '',
  ref_id       INT NOT NULL DEFAULT 0,
  KEY rts_ks_gerak_sales (id_sales, tanggal),
  KEY rts_ks_gerak_produk (produk_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 5. NOTA PENJUALAN KASIR
--    jenis pembayaran : CASH (tunai), UTANG (dibayar kemudian),
--                       TITIP (barang dititipkan, uang menyusul)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_penjualan (
  id              INT AUTO_INCREMENT PRIMARY KEY,
  nomor           VARCHAR(30) NOT NULL,
  tanggal         DATETIME NOT NULL,
  id_sales        VARCHAR(60)  NOT NULL,
  nama_sales      VARCHAR(100) NOT NULL DEFAULT '',
  role            VARCHAR(20)  NOT NULL DEFAULT '',
  district        VARCHAR(60)  NOT NULL DEFAULT '',
  jenis_customer  VARCHAR(20)  NOT NULL DEFAULT 'REGULER',
  customer_id     VARCHAR(40)  NOT NULL DEFAULT '',
  nama_customer   VARCHAR(150) NOT NULL DEFAULT '',
  hp_customer     VARCHAR(30)  NOT NULL DEFAULT '',
  alamat_customer VARCHAR(255) NOT NULL DEFAULT '',
  metode          VARCHAR(10)  NOT NULL DEFAULT 'CASH',
  total           DECIMAL(14,2) NOT NULL DEFAULT 0,
  bayar           DECIMAL(14,2) NOT NULL DEFAULT 0,
  kembali         DECIMAL(14,2) NOT NULL DEFAULT 0,
  status          VARCHAR(12)  NOT NULL DEFAULT 'LUNAS' COMMENT 'LUNAS, BELUM, SEBAGIAN',
  jumlah_item     INT NOT NULL DEFAULT 0,
  catatan         VARCHAR(255) NOT NULL DEFAULT '',
  foto            VARCHAR(255) NOT NULL DEFAULT '',
  dicetak         INT NOT NULL DEFAULT 0,
  cetak_terakhir  DATETIME NULL,
  dibatalkan      TINYINT(1) NOT NULL DEFAULT 0,
  batal_alasan    VARCHAR(255) NOT NULL DEFAULT '',
  batal_oleh      VARCHAR(60)  NOT NULL DEFAULT '',
  batal_pada      DATETIME NULL,
  dibuat_pada     DATETIME NULL,
  UNIQUE KEY rts_ks_jual_nomor (nomor),
  KEY rts_ks_jual_sales (id_sales, tanggal),
  KEY rts_ks_jual_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 6. BARANG YANG TERJUAL PADA SETIAP NOTA
--    Satu baris untuk tiap satuan: baris PACK dan baris BATANG terpisah,
--    supaya struk menampilkan "2 pack x Rp32.000" dan "3 batang x Rp2.200"
--    persis seperti yang dihitung sales.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_penjualan_item (
  id          INT AUTO_INCREMENT PRIMARY KEY,
  penjualan_id INT NOT NULL,
  produk_id   INT NOT NULL,
  barcode     VARCHAR(64)  NOT NULL DEFAULT '',
  nama_produk VARCHAR(150) NOT NULL,
  satuan      VARCHAR(10)  NOT NULL DEFAULT 'PACK',
  isi_per_pack INT NOT NULL DEFAULT 0,
  pack        INT NOT NULL DEFAULT 0,
  batang      INT NOT NULL DEFAULT 0,
  harga_satuan DECIMAL(14,2) NOT NULL DEFAULT 0,
  subtotal    DECIMAL(14,2) NOT NULL DEFAULT 0,
  KEY rts_ks_item_nota (penjualan_id),
  KEY rts_ks_item_produk (produk_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 7. PIUTANG (UTANG dan TITIP) - dapat diperbarui sampai lunas
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_piutang (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  nomor         VARCHAR(30) NOT NULL,
  jenis         VARCHAR(10) NOT NULL DEFAULT 'UTANG' COMMENT 'UTANG atau TITIP',
  penjualan_id  INT NOT NULL DEFAULT 0,
  tanggal       DATETIME NOT NULL,
  jatuh_tempo   DATE NULL,
  id_sales      VARCHAR(60)  NOT NULL,
  nama_sales    VARCHAR(100) NOT NULL DEFAULT '',
  district      VARCHAR(60)  NOT NULL DEFAULT '',
  customer_id   VARCHAR(40)  NOT NULL DEFAULT '',
  nama_customer VARCHAR(150) NOT NULL DEFAULT '',
  hp_customer   VARCHAR(30)  NOT NULL DEFAULT '',
  total         DECIMAL(14,2) NOT NULL DEFAULT 0,
  dibayar       DECIMAL(14,2) NOT NULL DEFAULT 0,
  sisa          DECIMAL(14,2) NOT NULL DEFAULT 0,
  status        VARCHAR(12) NOT NULL DEFAULT 'BELUM' COMMENT 'BELUM, SEBAGIAN, LUNAS, BATAL',
  rincian       TEXT NULL COMMENT 'ringkasan barang yang diutangkan/dititipkan',
  catatan       VARCHAR(255) NOT NULL DEFAULT '',
  foto          VARCHAR(255) NOT NULL DEFAULT '',
  diperbarui    DATETIME NULL,
  UNIQUE KEY rts_ks_piut_nomor (nomor),
  KEY rts_ks_piut_sales (id_sales, status),
  KEY rts_ks_piut_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 8. PEMBAYARAN / ANGSURAN PIUTANG
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_piutang_bayar (
  id            INT AUTO_INCREMENT PRIMARY KEY,
  piutang_id    INT NOT NULL,
  tanggal       DATETIME NOT NULL,
  jumlah        DECIMAL(14,2) NOT NULL DEFAULT 0,
  metode        VARCHAR(12) NOT NULL DEFAULT 'CASH' COMMENT 'CASH, TRANSFER, QRIS',
  diterima_oleh VARCHAR(60)  NOT NULL DEFAULT '',
  nama_penerima VARCHAR(100) NOT NULL DEFAULT '',
  catatan       VARCHAR(255) NOT NULL DEFAULT '',
  sisa_sesudah  DECIMAL(14,2) NOT NULL DEFAULT 0,
  KEY rts_ks_bayar_piut (piutang_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 9. TEMPLATE STRUK - dapat diubah bebas oleh setiap sales
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_struk (
  id               INT AUTO_INCREMENT PRIMARY KEY,
  id_sales         VARCHAR(60) NOT NULL,
  judul            VARCHAR(60)  NOT NULL DEFAULT 'RTS PANEL',
  baris1           VARCHAR(120) NOT NULL DEFAULT '',
  baris2           VARCHAR(120) NOT NULL DEFAULT '',
  baris3           VARCHAR(120) NOT NULL DEFAULT '',
  footer1          VARCHAR(120) NOT NULL DEFAULT 'Terima kasih',
  footer2          VARCHAR(120) NOT NULL DEFAULT '',
  footer3          VARCHAR(120) NOT NULL DEFAULT '',
  lebar_kertas     INT NOT NULL DEFAULT 58 COMMENT '58 atau 80 mm',
  ukuran_huruf     VARCHAR(10) NOT NULL DEFAULT 'SEDANG' COMMENT 'KECIL, SEDANG, BESAR',
  tampilkan_barcode TINYINT(1) NOT NULL DEFAULT 1,
  tampilkan_hp     TINYINT(1) NOT NULL DEFAULT 1,
  tampilkan_ttd    TINYINT(1) NOT NULL DEFAULT 0,
  tampilkan_qris   TINYINT(1) NOT NULL DEFAULT 0,
  tampilkan_diskon TINYINT(1) NOT NULL DEFAULT 1,
  tampilkan_metode TINYINT(1) NOT NULL DEFAULT 1,
  header_tebal     TINYINT(1) NOT NULL DEFAULT 1,
  garis            VARCHAR(3) NOT NULL DEFAULT '-',
  jumlah_salinan   INT NOT NULL DEFAULT 1,
  catatan_kaki     VARCHAR(120) NOT NULL DEFAULT '',
  diperbarui       DATETIME NULL,
  UNIQUE KEY rts_ks_struk_sales (id_sales)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 10. SETELAN UMUM KASIR
--     Contoh: mode_akses (PRO atau SEMUA) untuk masa perkenalan.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_setelan (
  id         INT AUTO_INCREMENT PRIMARY KEY,
  kunci      VARCHAR(40) NOT NULL,
  nilai      VARCHAR(255) NOT NULL DEFAULT '',
  diperbarui DATETIME NULL,
  UNIQUE KEY rts_ks_setelan_kunci (kunci)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------------
-- 11. PENOMORAN NOTA (KS-20261001-0001, PT-20261001-0001)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS rts_ks_penomoran (
  id      INT AUTO_INCREMENT PRIMARY KEY,
  tanggal DATE NOT NULL,
  prefix  VARCHAR(6) NOT NULL,
  urut    INT NOT NULL DEFAULT 0,
  UNIQUE KEY rts_ks_penomoran_hari (tanggal, prefix)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================================
--  SELESAI. Sesudah diimpor, pada aplikasi akan muncul keterangan
--  "Data kasir siap dipakai" ketika menu Barang Bawaan dibuka.
-- ============================================================================
