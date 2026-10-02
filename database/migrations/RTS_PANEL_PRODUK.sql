-- ============================================================================
--  RTS PANEL BY BENE - TABEL PRODUK (DAFTAR PRODUK BERSAMA)
--  Berkas : RTS_PANEL_PRODUK.sql
--  Dibuat : 3 Oktober 2026
--
--  CARA MENJALANKAN DI phpMyAdmin
--  ------------------------------
--   1. Buka cPanel -> phpMyAdmin -> pilih database RTS Panel
--      (benedics_benes_sales).
--   2. Klik tab "SQL", tempelkan SELURUH isi berkas ini, lalu tekan GO.
--   3. Muncul pesan "1 row affected" / "Your SQL query has been executed".
--   4. Tabel baru bernama `produk` akan tampak pada daftar tabel di sebelah
--      kiri. Buka tabel itu bila ingin menambah / mengubah produk langsung
--      dari komputer.
--
--  KETERANGAN
--  ----------
--   Tabel ini adalah DAFTAR PRODUK BERSAMA. Isinya dipakai oleh SEMUA user
--   aplikasi (semua sales), sehingga:
--     - Produk yang ditambah di sini langsung dapat diunduh oleh semua HP
--       lewat menu  Barang Bawaan -> PRODUK -> tombol SINKRON PRODUK.
--     - Produk yang ditambah dari aplikasi oleh sales juga naik ke tabel ini
--       (tersinkron), sehingga sales lain bisa memakainya.
--     - Harga di tabel ini berlaku SAMA untuk semua sales.
--
--   Barcode hanya untuk BUNGKUS (pack). Tidak ada kolom barcode batang,
--   sesuai permintaan: barcode hanya ada pada bungkus.
--
--   STOK TIDAK DISIMPAN DI SINI. Stok disimpan di dalam HP masing-masing
--   sales (database aplikasi/SQLite) karena kasir harus tetap jalan tanpa
--   internet. Yang dibagi bersama hanya daftar produk + harganya.
--
--   Aman dijalankan berkali-kali (IF NOT EXISTS) dan tidak menghapus data.
-- ============================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `produk` (
  `id`               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `sku`              VARCHAR(64)  NOT NULL DEFAULT ''  COMMENT 'Kode produk (opsional, boleh sama dengan barcode)',
  `barcode_bungkus`  VARCHAR(64)  NULL     DEFAULT NULL COMMENT 'Barcode pada bungkus/pack (unik, boleh kosong)',
  `nama`             VARCHAR(150) NOT NULL              COMMENT 'Nama produk',
  `merek`            VARCHAR(80)  NOT NULL DEFAULT ''   COMMENT 'Merek (opsional)',
  `isi_per_bungkus`  INT          NOT NULL DEFAULT 0    COMMENT 'Jumlah batang dalam satu bungkus/pack',
  `harga_bungkus`    DECIMAL(14,2) NOT NULL DEFAULT 0   COMMENT 'Harga per bungkus/pack',
  `harga_batang`     DECIMAL(14,2) NOT NULL DEFAULT 0   COMMENT 'Harga per batang',
  `catatan`          VARCHAR(255) NOT NULL DEFAULT ''   COMMENT 'Catatan (opsional)',
  `status_aktif`     TINYINT(1)   NOT NULL DEFAULT 1    COMMENT '1 = dipakai, 0 = tidak dipakai (disembunyikan)',
  `dibuat_oleh`      VARCHAR(100) NOT NULL DEFAULT ''   COMMENT 'Nama user yang menambah',
  `dibuat_pada`      DATETIME     NULL     DEFAULT NULL,
  `diubah_oleh`      VARCHAR(100) NOT NULL DEFAULT ''   COMMENT 'Nama user yang terakhir mengubah',
  `diubah_pada`      DATETIME     NULL     DEFAULT NULL COMMENT 'Dipakai aplikasi untuk sinkron lebih cepat',
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_barcode_bungkus` (`barcode_bungkus`),
  KEY `idx_nama` (`nama`),
  KEY `idx_aktif` (`status_aktif`),
  KEY `idx_diubah` (`diubah_pada`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ---------------------------------------------------------------------------
--  CATATAN PENTING SOAL BARCODE
--  ----------------------------
--  Kolom barcode_bungkus dibuat UNIK tetapi boleh berisi NULL (kosong).
--  Artinya:
--    - Satu barcode hanya boleh dimiliki satu produk.
--    - Produk tanpa barcode tetap boleh banyak (isinya NULL).
--  Kalau aplikasi mengirim barcode kosong, yang tersimpan adalah NULL,
--  bukan tanda kutip kosong. Jadi jangan heran bila di phpMyAdmin tampak
--  "NULL" pada produk yang belum punya barcode.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
--  CONTOH CARA MENGISI DARI phpMyAdmin (tempelkan pada tab SQL bila perlu)
--  Ganti angkanya sesuai produk Bapak:
--
--  INSERT INTO `produk`
--    (`sku`, `barcode_bungkus`, `nama`, `merek`, `isi_per_bungkus`,
--     `harga_bungkus`, `harga_batang`, `dibuat_oleh`, `dibuat_pada`, `diubah_pada`)
--  VALUES
--    ('SMP-MILD-16', '8992761111234', 'Sampoerna Mild 16', 'Sampoerna',
--     16, 32000, 2200, 'ADMIN', NOW(), NOW()),
--    ('DJM-12', NULL, 'Dji Sam Soe 12', 'Dji Sam Soe', 12, 26000, 2400,
--     'ADMIN', NOW(), NOW());
--
--  Melihat seluruh isi tabel:
--    SELECT * FROM `produk` ORDER BY `nama`;
-- ---------------------------------------------------------------------------
