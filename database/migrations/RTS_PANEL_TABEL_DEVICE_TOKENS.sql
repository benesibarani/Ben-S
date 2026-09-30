-- =============================================================================
-- RTS Panel By Bene
-- TABEL TOKEN PERANGKAT (untuk Pemberitahuan HP lewat Firebase)
-- =============================================================================
--
-- Tabel ini menyimpan daftar HP yang sudah login, supaya server dapat
-- mengirim pemberitahuan ke layar HP walaupun aplikasi sedang ditutup
-- sepenuhnya.
--
-- Satu akun boleh memiliki beberapa HP (misalnya HP kerja dan HP pribadi),
-- dan satu HP boleh berpindah akun (misalnya berganti sales) - data lamanya
-- otomatis diperbarui, tidak menumpuk.
--
-- Berkas ini AMAN dijalankan berkali-kali (memakai IF NOT EXISTS).
--
-- Cara menjalankan:
--   1. cPanel > phpMyAdmin > pilih database (benedics_benes_sales)
--   2. Tab SQL > salin seluruh isi berkas ini > GO
--   3. Ulangi pada database staging (benedics_coba) bila ingin diuji di sana
--
-- =============================================================================

CREATE TABLE IF NOT EXISTS `rts_device_tokens` (
    `id` INT NOT NULL AUTO_INCREMENT,

    -- Pemilik HP ini, disamakan dengan kolom email pada tabel sales_users.
    `user_email` VARCHAR(150) NOT NULL,

    -- Token perangkat dari Firebase. Memakai character set ascii supaya
    -- penanda unik dapat dipasang pada seluruh kolom tanpa terpotong.
    `token` VARCHAR(255) CHARACTER SET ascii NOT NULL,

    -- 'android' (saat ini hanya Android yang dipakai).
    `platform` VARCHAR(20) NOT NULL DEFAULT 'android',

    -- Merek/tipe HP, hanya untuk memudahkan pemeriksaan.
    `perangkat` VARCHAR(100) NOT NULL DEFAULT '',

    `dibuat_pada` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `diperbarui_pada` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        ON UPDATE CURRENT_TIMESTAMP,

    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_token` (`token`),
    KEY `idx_email` (`user_email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- =============================================================================
-- PEMERIKSAAN SETELAH DIJALANKAN
-- =============================================================================

-- Melihat isi tabel (harusnya kosong sebelum aplikasi mendaftar):
--
--   SELECT id, user_email, platform, perangkat, diperbarui_pada
--   FROM rts_device_tokens
--   ORDER BY diperbarui_pada DESC;
--
-- Setelah aplikasi dibuka di HP, akan muncul satu baris untuk akun yang
-- sedang login. Bila barisnya tidak muncul, periksa:
--   1. Apakah berkas firebase_service_account sudah diletakkan di server.
--   2. Apakah api/device_token.php sudah di-upload.
--   3. Apakah aplikasi versi baru sudah terpasang di HP.
--
-- Menghapus semua token (misalnya saat pengujian):
--
--   DELETE FROM rts_device_tokens;
-- =============================================================================
