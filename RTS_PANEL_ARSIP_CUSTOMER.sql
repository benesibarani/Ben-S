-- ============================================================================
-- RTS PANEL BY BENE
-- RTS_PANEL_ARSIP_CUSTOMER.sql
-- Memastikan tabel arsip customer `master_toko_deleted` sudah lengkap.
--
-- KAPAN DIPERLUKAN?
--   Halaman Upload Data Customer (putaran 18) sudah dapat membuat tabel ini
--   sendiri lewat tombol "BUAT / PERIKSA TABEL ARSIP". Berkas SQL ini hanya
--   untuk Bapak yang lebih suka mengerjakannya lewat phpMyAdmin.
--
-- CARA PAKAI (phpMyAdmin):
--   1. Pilih database: benedics_benes_sales
--   2. Buka tab "SQL", tempel isi berkas ini, tekan "Go".
--   3. Aman dijalankan berulang kali (memakai IF NOT EXISTS).
--
-- BERKAS INI TIDAK MENGHAPUS DAN TIDAK MENGUBAH DATA CUSTOMER APA PUN.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABEL ARSIP
-- ----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `master_toko_deleted` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `original_id` INT(11) DEFAULT NULL,
  `id_customer` VARCHAR(50) DEFAULT NULL,
  `nama_toko` VARCHAR(150) DEFAULT NULL,
  `tipe_customer` ENUM('REGULER','GSP') NOT NULL DEFAULT 'REGULER',
  `salesman` VARCHAR(150) DEFAULT NULL,
  `alamat` TEXT DEFAULT NULL,
  `kunjungan` VARCHAR(50) DEFAULT NULL,
  `hari` VARCHAR(20) DEFAULT NULL,
  `sales_district` VARCHAR(100) DEFAULT NULL,
  `longitude` VARCHAR(50) DEFAULT NULL,
  `latitude` VARCHAR(50) DEFAULT NULL,
  `status_aktif` VARCHAR(20) DEFAULT NULL,
  `alasan_penghapusan` TEXT DEFAULT NULL,
  `dihapus_oleh` VARCHAR(150) DEFAULT NULL,
  `dihapus_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_deleted_customer` (`id_customer`),
  KEY `idx_deleted_at` (`dihapus_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- 2. BILA TABEL SUDAH ADA TETAPI MASIH KURANG KOLOM
--
--    Kolom di bawah ini yang dipakai halaman Upload Data Customer untuk
--    mencatat siapa dan kapan data dihapus. Jalankan hanya baris yang
--    kolomnya belum ada (lihat cara memeriksa pada bagian 3).
--    Bila kolomnya sudah ada, perintah akan menampilkan galat
--    "Duplicate column name" - itu aman, artinya tidak perlu dijalankan.
-- ----------------------------------------------------------------------------

-- ALTER TABLE `master_toko_deleted` ADD COLUMN `original_id` INT(11) NULL AFTER `id`;
-- ALTER TABLE `master_toko_deleted` ADD COLUMN `alasan_penghapusan` TEXT NULL;
-- ALTER TABLE `master_toko_deleted` ADD COLUMN `dihapus_oleh` VARCHAR(150) NULL;
-- ALTER TABLE `master_toko_deleted` ADD COLUMN `dihapus_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- ----------------------------------------------------------------------------
-- 3. MEMERIKSA HASILNYA
-- ----------------------------------------------------------------------------

-- Daftar kolom tabel arsip:
SELECT COLUMN_NAME, COLUMN_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko_deleted'
ORDER BY ORDINAL_POSITION;

-- Jumlah data customer sekarang dan jumlah data yang sudah diarsipkan:
SELECT 'Customer aktif' AS bagian, COUNT(*) AS jumlah FROM `master_toko`
UNION ALL
SELECT 'Di dalam arsip', COUNT(*) FROM `master_toko_deleted`;

-- 50 data arsip terakhir:
SELECT `id`, `id_customer`, `nama_toko`, `sales_district`, `alasan_penghapusan`,
       `dihapus_oleh`, `dihapus_at`
FROM `master_toko_deleted`
ORDER BY `dihapus_at` DESC
LIMIT 50;

-- ----------------------------------------------------------------------------
-- 4. MENGEMBALIKAN SATU CUSTOMER DARI ARSIP (bila diperlukan)
--
--    Ganti 3000032344 dengan id_customer yang ingin dikembalikan.
--    Jalankan bagian ini HANYA bila customer tersebut belum ada lagi di
--    master_toko (bila sudah ada, tidak perlu dilakukan).
-- ----------------------------------------------------------------------------

-- INSERT INTO `master_toko`
--   (`id_customer`, `nama_toko`, `tipe_customer`, `salesman`, `alamat`,
--    `kunjungan`, `hari`, `sales_district`, `longitude`, `latitude`, `status_aktif`)
-- SELECT `id_customer`, `nama_toko`, `tipe_customer`, `salesman`, `alamat`,
--        `kunjungan`, `hari`, `sales_district`, `longitude`, `latitude`, `status_aktif`
-- FROM `master_toko_deleted`
-- WHERE `id_customer` = '3000032344'
-- ORDER BY `dihapus_at` DESC
-- LIMIT 1;

-- ----------------------------------------------------------------------------
-- 5. CATATAN PENTING
--
--    - Menghapus data dari tabel arsip (bila benar-benar tidak diperlukan):
--
--          DELETE FROM `master_toko_deleted` WHERE `dihapus_at` < '2026-01-01';
--
--      Lakukan HANYA setelah backup database.
--
--    - Halaman Upload Data Customer tidak pernah menghapus isi tabel arsip,
--      jadi data lama tidak akan hilang sendiri.
-- ============================================================================
-- RTS Panel By Bene - Putaran 18
-- ============================================================================
