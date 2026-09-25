-- RTS Panel By Bene
-- Migrasi 001: persiapan Master Customer
--
-- Jalankan setelah backup database.
-- Migrasi ini tidak menghapus atau mengganti data customer yang sudah ada.

SET NAMES utf8mb4;

-- master_toko adalah tabel Master Customer utama.
-- Data lama dianggap REGULER sampai diverifikasi oleh Admin.
ALTER TABLE `master_toko`
    ADD COLUMN IF NOT EXISTS `tipe_customer`
        ENUM('REGULER', 'GSP') NOT NULL DEFAULT 'REGULER'
        AFTER `id_customer`;

-- Kolom ini membantu pencarian berdasarkan salesman dan tipe customer.
-- Jika index sudah ada, abaikan pesan duplicate index dari hosting.
ALTER TABLE `master_toko`
    ADD INDEX `idx_master_toko_salesman` (`salesman`),
    ADD INDEX `idx_master_toko_tipe_customer` (`tipe_customer`),
    ADD INDEX `idx_master_toko_status_aktif` (`status_aktif`),
    ADD INDEX `idx_master_toko_sales_district` (`sales_district`);

-- Pastikan data lama memiliki nilai kategori.
UPDATE `master_toko`
SET `tipe_customer` = 'REGULER'
WHERE `tipe_customer` IS NULL OR `tipe_customer` = '';

-- Catatan:
-- 1. Jangan mengubah data menjadi GSP secara massal sebelum diverifikasi.
-- 2. Role user akan dimigrasikan pada migrasi terpisah setelah daftar role disetujui.
-- 3. Jalankan di database backup/staging terlebih dahulu.
-- RTS Panel By Bene
-- Migrasi 002: data role dan cakupan user
--
-- Jalankan setelah backup database dan setelah migrasi 001.
-- Migrasi ini hanya menambah kolom; data user lama tidak dihapus.

SET NAMES utf8mb4;

ALTER TABLE `sales_users`
    ADD COLUMN IF NOT EXISTS `username`
        varchar(50) DEFAULT NULL
        AFTER `email`,
    ADD COLUMN IF NOT EXISTS `salesman`
        varchar(150) DEFAULT NULL
        AFTER `role`,
    ADD COLUMN IF NOT EXISTS `sales_district`
        varchar(100) DEFAULT NULL
        AFTER `salesman`,
    ADD COLUMN IF NOT EXISTS `status_aktif`
        enum('Aktif', 'Nonaktif') NOT NULL DEFAULT 'Aktif'
        AFTER `sales_district`;

-- Mempercepat pencarian user berdasarkan role dan area kerja.
ALTER TABLE `sales_users`
    ADD INDEX `idx_sales_users_username` (`username`),
    ADD INDEX `idx_sales_users_role` (`role`),
    ADD INDEX `idx_sales_users_salesman` (`salesman`),
    ADD INDEX `idx_sales_users_district` (`sales_district`),
    ADD INDEX `idx_sales_users_status` (`status_aktif`);

-- Normalisasi role lama.
-- User lama dengan role 'super_admin' menjadi ADMIN.
-- User lama dengan role 'admin' menjadi ASS.
-- User lama dengan role 'sales' tetap sales sementara sampai Admin mengisi role sebenarnya.
UPDATE `sales_users`
SET `role` = 'ADMIN'
WHERE LOWER(`role`) = 'super_admin';

UPDATE `sales_users`
SET `role` = 'ASS'
WHERE LOWER(`role`) = 'admin';

-- Catatan:
-- 1. Jangan mengubah seluruh 'sales' menjadi RTS tanpa verifikasi.
-- 2. Isi kolom salesman harus sama dengan nilai salesman pada master_toko.
-- 3. Data salesman dan district dapat diisi melalui menu Admin/User.
-- 4. Filter data harus tetap dilakukan di query server, bukan hanya di tampilan.
-- RTS Panel By Bene
-- Migrasi 003: arsip sebelum penghapusan customer
-- Jalankan setelah backup dan migrasi 001-002.

CREATE TABLE IF NOT EXISTS `master_toko_deleted` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `original_id` int(11) DEFAULT NULL,
  `id_customer` varchar(50) DEFAULT NULL,
  `nama_toko` varchar(150) DEFAULT NULL,
  `tipe_customer` enum('REGULER','GSP') NOT NULL DEFAULT 'REGULER',
  `salesman` varchar(150) DEFAULT NULL,
  `alamat` text DEFAULT NULL,
  `kunjungan` varchar(50) DEFAULT NULL,
  `hari` varchar(20) DEFAULT NULL,
  `sales_district` varchar(100) DEFAULT NULL,
  `longitude` varchar(50) DEFAULT NULL,
  `latitude` varchar(50) DEFAULT NULL,
  `status_aktif` varchar(20) DEFAULT NULL,
  `alasan_penghapusan` text DEFAULT NULL,
  `dihapus_oleh` varchar(150) DEFAULT NULL,
  `dihapus_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_deleted_customer` (`id_customer`),
  KEY `idx_deleted_at` (`dihapus_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- RTS Panel By Bene
-- Migrasi 004: membedakan jenis pengajuan GSP
-- Jalankan setelah backup dan migrasi sebelumnya.

ALTER TABLE `pengajuan_gsp`
    ADD COLUMN IF NOT EXISTS `jenis_request`
        ENUM('PENAMBAHAN', 'PENGHAPUSAN') NOT NULL DEFAULT 'PENAMBAHAN'
        AFTER `id`;

ALTER TABLE `pengajuan_gsp`
    ADD INDEX `idx_pengajuan_gsp_jenis` (`jenis_request`),
    ADD INDEX `idx_pengajuan_gsp_status` (`status_approval`),
    ADD INDEX `idx_pengajuan_gsp_sales_email` (`sales_email`);
-- RTS Panel By Bene
-- Migrasi 005: audit persetujuan pengajuan
-- Jalankan setelah backup dan migrasi sebelumnya.

ALTER TABLE `pengajuan_sales`
    ADD COLUMN IF NOT EXISTS `processed_by` varchar(150) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `processed_at` timestamp NULL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `approval_note` text DEFAULT NULL;

ALTER TABLE `pengajuan_gsp`
    ADD COLUMN IF NOT EXISTS `processed_by` varchar(150) DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `processed_at` timestamp NULL DEFAULT NULL,
    ADD COLUMN IF NOT EXISTS `approval_note` text DEFAULT NULL;

ALTER TABLE `pengajuan_sales`
    ADD INDEX `idx_pengajuan_sales_processed` (`processed_at`);

ALTER TABLE `pengajuan_gsp`
    ADD INDEX `idx_pengajuan_gsp_processed` (`processed_at`);
-- RTS Panel By Bene
-- Migrasi 006: notifikasi user
-- Jalankan setelah backup dan migrasi sebelumnya.

CREATE TABLE IF NOT EXISTS `notifications` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) DEFAULT NULL,
  `recipient_email` varchar(100) DEFAULT NULL,
  `title` varchar(150) NOT NULL,
  `message` text NOT NULL,
  `type` enum('INFO','SUCCESS','WARNING','DANGER') NOT NULL DEFAULT 'INFO',
  `reference_type` varchar(50) DEFAULT NULL,
  `reference_id` int(11) DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_notifications_user` (`user_id`),
  KEY `idx_notifications_email` (`recipient_email`),
  KEY `idx_notifications_read` (`is_read`),
  KEY `idx_notifications_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- RTS Panel By Bene
-- Migrasi 007: token login aplikasi Android
-- Jalankan setelah backup dan migrasi sebelumnya.

CREATE TABLE IF NOT EXISTS `api_tokens` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `device_name` varchar(100) DEFAULT NULL,
  `expires_at` timestamp NOT NULL,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_api_token_hash` (`token_hash`),
  KEY `idx_api_tokens_user` (`user_id`),
  KEY `idx_api_tokens_expiry` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
