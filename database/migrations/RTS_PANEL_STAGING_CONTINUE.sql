-- Lanjutan migrasi staging setelah import berhenti pada duplicate index.
-- Jalankan pada database benedics_coba yang sudah memiliki tabel dasar.

ALTER TABLE `sales_users`
 ADD COLUMN IF NOT EXISTS `username` varchar(50) DEFAULT NULL AFTER `email`,
 ADD COLUMN IF NOT EXISTS `salesman` varchar(150) DEFAULT NULL AFTER `role`,
 ADD COLUMN IF NOT EXISTS `sales_district` varchar(100) DEFAULT NULL AFTER `salesman`,
 ADD COLUMN IF NOT EXISTS `status_aktif` enum('Aktif','Nonaktif') NOT NULL DEFAULT 'Aktif' AFTER `sales_district`;

CREATE TABLE IF NOT EXISTS `master_toko_deleted` (
 `id` int NOT NULL AUTO_INCREMENT, `original_id` int DEFAULT NULL, `id_customer` varchar(50) DEFAULT NULL,
 `nama_toko` varchar(150) DEFAULT NULL, `tipe_customer` enum('REGULER','GSP') NOT NULL DEFAULT 'REGULER',
 `salesman` varchar(150) DEFAULT NULL, `alamat` text DEFAULT NULL, `kunjungan` varchar(50) DEFAULT NULL,
 `hari` varchar(20) DEFAULT NULL, `sales_district` varchar(100) DEFAULT NULL, `longitude` varchar(50) DEFAULT NULL,
 `latitude` varchar(50) DEFAULT NULL, `status_aktif` varchar(20) DEFAULT NULL, `alasan_penghapusan` text DEFAULT NULL,
 `dihapus_oleh` varchar(150) DEFAULT NULL, `dihapus_at` timestamp NOT NULL DEFAULT current_timestamp(), PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `pengajuan_gsp` ADD COLUMN IF NOT EXISTS `jenis_request` enum('PENAMBAHAN','PENGHAPUSAN') NOT NULL DEFAULT 'PENAMBAHAN' AFTER `id`;
ALTER TABLE `pengajuan_sales` ADD COLUMN IF NOT EXISTS `processed_by` varchar(150) DEFAULT NULL, ADD COLUMN IF NOT EXISTS `processed_at` timestamp NULL DEFAULT NULL, ADD COLUMN IF NOT EXISTS `approval_note` text DEFAULT NULL;
ALTER TABLE `pengajuan_gsp` ADD COLUMN IF NOT EXISTS `processed_by` varchar(150) DEFAULT NULL, ADD COLUMN IF NOT EXISTS `processed_at` timestamp NULL DEFAULT NULL, ADD COLUMN IF NOT EXISTS `approval_note` text DEFAULT NULL;

CREATE TABLE IF NOT EXISTS `notifications` (
 `id` int NOT NULL AUTO_INCREMENT, `user_id` int DEFAULT NULL, `recipient_email` varchar(100) DEFAULT NULL,
 `title` varchar(150) NOT NULL, `message` text NOT NULL, `type` enum('INFO','SUCCESS','WARNING','DANGER') NOT NULL DEFAULT 'INFO',
 `reference_type` varchar(50) DEFAULT NULL, `reference_id` int DEFAULT NULL, `is_read` tinyint(1) NOT NULL DEFAULT 0,
 `created_at` timestamp NOT NULL DEFAULT current_timestamp(), PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `api_tokens` (
 `id` int NOT NULL AUTO_INCREMENT, `user_id` int NOT NULL, `token_hash` char(64) NOT NULL,
 `device_name` varchar(100) DEFAULT NULL, `expires_at` timestamp NOT NULL, `last_used_at` timestamp NULL DEFAULT NULL,
 `created_at` timestamp NOT NULL DEFAULT current_timestamp(), PRIMARY KEY (`id`), UNIQUE KEY `uq_api_token_hash` (`token_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
