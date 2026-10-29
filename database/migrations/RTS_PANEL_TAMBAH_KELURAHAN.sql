-- RTS Panel By Bene - Tambah kolom kelurahan
-- Untuk: pengajuan Ganti Alamat (form Pengajuan Baru di aplikasi) dan data toko master_toko.
--
-- CARA PAKAI (WAJIB):
--   1. Backup database benedics_benes_sales dari cPanel / phpMyAdmin.
--   2. Uji dulu pada database TESTING.
--   3. Baru jalankan pada database produksi.
--
-- File aman diulang karena memakai IF NOT EXISTS.
-- Kolom baru bersifat NULL sehingga data lama tidak berubah.

ALTER TABLE `pengajuan_sales` ADD COLUMN IF NOT EXISTS `kelurahan` VARCHAR(100) DEFAULT NULL AFTER `alamat_baru`;
ALTER TABLE `master_toko` ADD COLUMN IF NOT EXISTS `kelurahan` VARCHAR(100) DEFAULT NULL AFTER `alamat`;
-- Arsip hapus permanen. Lewati baris ini bila tabel master_toko_deleted belum ada.
ALTER TABLE `master_toko_deleted` ADD COLUMN IF NOT EXISTS `kelurahan` VARCHAR(100) DEFAULT NULL AFTER `alamat`;

-- Pemeriksaan hasil (harus menampilkan 3 baris, masing-masing kelurahan):
-- SELECT TABLE_NAME, COLUMN_NAME, COLUMN_TYPE
--   FROM information_schema.COLUMNS
--  WHERE TABLE_SCHEMA = DATABASE() AND COLUMN_NAME = 'kelurahan';
