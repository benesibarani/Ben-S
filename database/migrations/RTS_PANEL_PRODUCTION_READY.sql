-- =============================================================================
-- RTS PANEL - PENYIAPAN DATABASE PRODUKSI UNTUK APLIKASI ANDROID
-- Target: database produksi (rts.benedic-s.com)
--
-- !!! JANGAN JALANKAN SEBELUM BACKUP SELESAI !!!
--
-- Urutan wajib:
--   1. Jalankan RTS_PANEL_PRODUCTION_CHECK.sql dan pastikan tidak ada
--      kebutuhan tak terduga.
--   2. BACKUP database produksi:
--      cPanel -> phpMyAdmin -> pilih database produksi -> Export -> Go
--      atau cPanel -> Backup Wizard -> Download a MySQL Database Backup.
--   3. BACKUP file website produksi (folder public_html) menjadi zip.
--   4. Baru jalankan file ini.
--   5. Jalankan bagian PEMERIKSAAN di bawah dan simpan hasilnya.
--
-- File ini aman dijalankan berulang kali (idempotent):
-- setiap perubahan hanya dilakukan bila objeknya belum ada.
-- Tidak ada perintah DELETE, DROP, atau TRUNCATE di dalam file ini.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. TABEL api_tokens (token login Android)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `api_tokens` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `user_id` INT NOT NULL,
  `token_hash` CHAR(64) NOT NULL,
  `device_name` VARCHAR(100) DEFAULT NULL,
  `expires_at` TIMESTAMP NOT NULL,
  `last_used_at` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_token_hash` (`token_hash`),
  KEY `idx_api_tokens_user` (`user_id`),
  KEY `idx_api_tokens_expires` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- -----------------------------------------------------------------------------
-- 2. KOLOM master_toko.tipe_customer (REGULER / GSP)
-- -----------------------------------------------------------------------------

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko'
               AND COLUMN_NAME = 'tipe_customer');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `master_toko` ADD COLUMN `tipe_customer` ENUM(''REGULER'',''GSP'') NOT NULL DEFAULT ''REGULER'' AFTER `id_customer`',
  'SELECT ''Kolom master_toko.tipe_customer sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.STATISTICS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko'
               AND INDEX_NAME = 'idx_master_toko_tipe_customer');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `master_toko` ADD INDEX `idx_master_toko_tipe_customer` (`tipe_customer`)',
  'SELECT ''Index tipe_customer sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

UPDATE `master_toko`
SET `tipe_customer` = 'REGULER'
WHERE `tipe_customer` IS NULL OR `tipe_customer` = '';


-- -----------------------------------------------------------------------------
-- 3. TABEL master_toko_deleted (arsip customer yang dihapus)
-- -----------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS `master_toko_deleted` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `original_id` INT DEFAULT NULL,
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
  KEY `idx_deleted_id_customer` (`id_customer`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- -----------------------------------------------------------------------------
-- 4. KOLOM AUDIT pada pengajuan_sales
-- -----------------------------------------------------------------------------

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales'
               AND COLUMN_NAME = 'processed_by');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_sales` ADD COLUMN `processed_by` VARCHAR(150) DEFAULT NULL',
  'SELECT ''pengajuan_sales.processed_by sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales'
               AND COLUMN_NAME = 'processed_at');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_sales` ADD COLUMN `processed_at` TIMESTAMP NULL DEFAULT NULL',
  'SELECT ''pengajuan_sales.processed_at sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales'
               AND COLUMN_NAME = 'approval_note');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_sales` ADD COLUMN `approval_note` TEXT DEFAULT NULL',
  'SELECT ''pengajuan_sales.approval_note sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;


-- -----------------------------------------------------------------------------
-- 5. KOLOM pada pengajuan_gsp
-- -----------------------------------------------------------------------------

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp'
               AND COLUMN_NAME = 'jenis_request');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_gsp` ADD COLUMN `jenis_request` ENUM(''PENAMBAHAN'',''PENGHAPUSAN'') NOT NULL DEFAULT ''PENAMBAHAN''',
  'SELECT ''pengajuan_gsp.jenis_request sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp'
               AND COLUMN_NAME = 'processed_by');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_gsp` ADD COLUMN `processed_by` VARCHAR(150) DEFAULT NULL',
  'SELECT ''pengajuan_gsp.processed_by sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp'
               AND COLUMN_NAME = 'processed_at');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_gsp` ADD COLUMN `processed_at` TIMESTAMP NULL DEFAULT NULL',
  'SELECT ''pengajuan_gsp.processed_at sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

SET @ada := (SELECT COUNT(*) FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp'
               AND COLUMN_NAME = 'approval_note');
SET @sql := IF(@ada = 0,
  'ALTER TABLE `pengajuan_gsp` ADD COLUMN `approval_note` TEXT DEFAULT NULL',
  'SELECT ''pengajuan_gsp.approval_note sudah ada.'' AS info');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;


-- -----------------------------------------------------------------------------
-- 6. PEMERIKSAAN AKHIR
-- -----------------------------------------------------------------------------

SELECT 'api_tokens' AS item, IF(COUNT(*) > 0, 'SIAP', 'BELUM') AS status
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'api_tokens'

UNION ALL
SELECT 'master_toko.tipe_customer', IF(COUNT(*) > 0, 'SIAP', 'BELUM')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko' AND COLUMN_NAME = 'tipe_customer'

UNION ALL
SELECT 'master_toko_deleted', IF(COUNT(*) > 0, 'SIAP', 'BELUM')
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko_deleted'

UNION ALL
SELECT 'pengajuan_sales.processed_by', IF(COUNT(*) > 0, 'SIAP', 'BELUM')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME = 'processed_by'

UNION ALL
SELECT 'pengajuan_gsp.jenis_request', IF(COUNT(*) > 0, 'SIAP', 'BELUM')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp' AND COLUMN_NAME = 'jenis_request';

SELECT `tipe_customer`, COUNT(*) AS jumlah
FROM `master_toko`
GROUP BY `tipe_customer`;
