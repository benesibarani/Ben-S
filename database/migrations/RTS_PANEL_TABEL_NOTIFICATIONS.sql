-- =============================================================================
-- RTS Panel By Bene
-- Tabel Pemberitahuan (notifications) - OPSIONAL
-- =============================================================================
--
-- KAPAN DIPERLUKAN?
--
-- Fitur Pemberitahuan pada aplikasi Android dapat dipakai TANPA berkas ini.
-- Daftar "Perlu Diperiksa" dan "Hasil Pengajuan Saya" disusun langsung dari
-- tabel pengajuan_sales dan pengajuan_gsp yang sudah ada.
--
-- Berkas ini hanya diperlukan bila Anda ingin pemberitahuan sistem tersimpan
-- permanen, misalnya:
--   - "Pengajuan Anda disetujui" tersimpan sebagai riwayat di HP
--   - lonceng pada website (header.php) menghitung pemberitahuan yang belum
--     dibaca melalui tabel notifications
--
-- AMAN DIJALANKAN:
--   - Hanya MEMBUAT tabel baru bila belum ada (CREATE TABLE IF NOT EXISTS)
--   - Tidak mengubah, memindahkan, atau menghapus data yang sudah ada
--   - Tidak menyentuh tabel lain
--
-- CARA MENJALANKAN (server Staging lebih dahulu, lalu Produksi):
--   1. Buka cPanel > phpMyAdmin
--   2. Pilih database tujuan (benedics_coba untuk uji, benedics_bene_sales
--      untuk produksi)
--   3. Buka tab SQL, salin seluruh isi berkas ini, tekan GO
--   4. Periksa pada tab Struktur: tabel notifications harus muncul
--
-- =============================================================================

CREATE TABLE IF NOT EXISTS `notifications` (
  `id` INT(11) NOT NULL AUTO_INCREMENT,
  `user_id` INT(11) DEFAULT NULL,
  `recipient_email` VARCHAR(100) DEFAULT NULL,
  `title` VARCHAR(150) NOT NULL,
  `message` TEXT NOT NULL,
  `type` ENUM('INFO','SUCCESS','WARNING','DANGER') NOT NULL DEFAULT 'INFO',
  `reference_type` VARCHAR(50) DEFAULT NULL,
  `reference_id` INT(11) DEFAULT NULL,
  `is_read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_notifications_user` (`user_id`),
  KEY `idx_notifications_email` (`recipient_email`),
  KEY `idx_notifications_read` (`is_read`),
  KEY `idx_notifications_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- =============================================================================
-- PEMERIKSAAN SETELAH DIJALANKAN
-- =============================================================================
-- Jalankan perintah berikut untuk memastikan tabel siap dipakai:

-- SELECT COUNT(*) AS jumlah_pemberitahuan FROM notifications;

-- Cara aplikasi Android memakai tabel ini:
--   recipient_email  : email akun penerima (sales_users.email)
--   user_id          : id akun penerima (boleh berupa 0 bila tidak diisi)
--   title, message   : judul dan isi pemberitahuan
--   type             : INFO / SUCCESS / WARNING / DANGER (memengaruhi warna)
--   reference_type   : PENGAJUAN_TOKO / PENGAJUAN_GSP / PENGAJUAN_BARU
--   reference_id     : nomor pengajuan terkait
--   is_read          : 0 = belum dibaca, 1 = sudah dibaca
