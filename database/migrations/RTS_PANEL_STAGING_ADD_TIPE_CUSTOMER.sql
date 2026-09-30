-- =============================================================================
-- RTS PANEL - TAMBAH KOLOM tipe_customer PADA TABEL master_toko
-- Untuk database STAGING (benedics_coba) di coba.benedic-s.com
-- Aman dijalankan berulang kali (idempotent).
--
-- JANGAN jalankan di database produksi sebelum backup dan pengujian selesai.
--
-- Cara pakai di cPanel -> phpMyAdmin:
--   1. Pilih database staging (benedics_coba).
--   2. Buka tab SQL.
--   3. Tempel seluruh isi file ini, lalu klik Go.
--   4. Lihat hasil paling bawah: jumlah REGULER dan GSP.
-- =============================================================================

-- 1. Tambah kolom tipe_customer bila belum ada
SET @kolom_ada := (
    SELECT COUNT(*)
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'master_toko'
      AND COLUMN_NAME = 'tipe_customer'
);

SET @sql_kolom := IF(
    @kolom_ada = 0,
    'ALTER TABLE `master_toko` ADD COLUMN `tipe_customer` ENUM(''REGULER'',''GSP'') NOT NULL DEFAULT ''REGULER'' AFTER `id_customer`',
    'SELECT ''Kolom tipe_customer sudah ada, dilewati.'' AS info'
);

PREPARE stmt_kolom FROM @sql_kolom;
EXECUTE stmt_kolom;
DEALLOCATE PREPARE stmt_kolom;

-- 2. Tambah index agar filter tipe cepat
SET @index_ada := (
    SELECT COUNT(*)
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'master_toko'
      AND INDEX_NAME = 'idx_master_toko_tipe_customer'
);

SET @sql_index := IF(
    @index_ada = 0,
    'ALTER TABLE `master_toko` ADD INDEX `idx_master_toko_tipe_customer` (`tipe_customer`)',
    'SELECT ''Index tipe_customer sudah ada, dilewati.'' AS info'
);

PREPARE stmt_index FROM @sql_index;
EXECUTE stmt_index;
DEALLOCATE PREPARE stmt_index;

-- 3. Rapikan nilai yang masih kosong
UPDATE `master_toko`
SET `tipe_customer` = 'REGULER'
WHERE `tipe_customer` IS NULL OR `tipe_customer` = '';

-- 4. Periksa hasil: jumlah customer per kategori
SELECT `tipe_customer`, COUNT(*) AS jumlah
FROM `master_toko`
GROUP BY `tipe_customer`;

-- 5. Periksa struktur kolom
SHOW COLUMNS FROM `master_toko` LIKE 'tipe_customer';
