-- ============================================================================
--  RTS PANEL BY BENE - TABEL VERSI APLIKASI (PEMBARUAN OTOMATIS)
--  Berkas : RTS_PANEL_APP_VERSI.sql
--
--  KEGUNAAN
--  --------
--  Menyimpan keterangan versi aplikasi Android yang terbaru, sehingga aplikasi
--  RTS Panel di HP seluruh tim dapat mengetahui ada versi baru setiap kali
--  dibuka, lalu menawarkan pembaruan.
--
--  TABEL INI MELENGKAPI, BUKAN MENGGANTIKAN, berkas apk/app_versi.json:
--     1. Berkas JSON tetap ditulis oleh halaman app_versi.php
--     2. Tabel ini dipakai halaman API (api/app_versi.php) sebagai sumber
--        utama, karena lebih andal
--     3. Aplikasi membaca API lebih dahulu; bila API tidak tersedia (misalnya
--        tabel belum dibuat), aplikasi otomatis memakai berkas JSON
--
--  Dengan begitu, memasang berkas ini TIDAK akan memutus fitur pembaruan yang
--  sudah berjalan.
--
--  CARA MENJALANKAN (phpMyAdmin)
--  -----------------------------
--  1. Buka cPanel - phpMyAdmin
--  2. Pilih database (uji coba: benedics_coba | produksi: benedics_bene_sales)
--  3. Klik tab SQL
--  4. Tempel SELURUH isi berkas ini, klik Kirim (Go)
--
--  CATATAN: berkas ini TIDAK memakai tabel information_schema, karena akun
--  database cPanel tidak diberi izin membacanya (kesalahan #1044).
--
--  KEAMANAN: perintah di bawah hanya MEMBUAT TABEL BARU bila belum ada.
--  Tabel lain (sales_users, master_toko, dan lainnya) tidak disentuh sama
--  sekali.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- LANGKAH 1 - Periksa, apakah tabelnya sudah ada
--   Hasil kosong = belum ada, lanjutkan ke LANGKAH 2
-- ---------------------------------------------------------------------------
SHOW TABLES LIKE 'rts_app_versi';


-- ---------------------------------------------------------------------------
-- LANGKAH 2 - Membuat tabel versi aplikasi
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `rts_app_versi` (
    `id`           INT(11)      NOT NULL AUTO_INCREMENT,
    `version_code` INT(11)      NOT NULL COMMENT 'angka sesudah tanda + pada pubspec.yaml',
    `version_name` VARCHAR(20)  NOT NULL COMMENT 'angka sebelum tanda +, contoh 1.2.0',
    `wajib`        TINYINT(1)   NOT NULL DEFAULT 0 COMMENT '1 = pembaruan wajib',
    `catatan`      TEXT         NULL COMMENT 'catatan pembaruan untuk petugas',
    `apk`          VARCHAR(255) NOT NULL COMMENT 'alamat unduhan berkas APK',
    `ukuran_mb`    DECIMAL(6,2) NOT NULL DEFAULT 0.00,
    `diunggah_oleh` VARCHAR(120) NULL COMMENT 'email admin yang mengunggah',
    `aktif`        TINYINT(1)   NOT NULL DEFAULT 1 COMMENT '1 = versi yang diumumkan',
    `dibuat_pada`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_kode` (`version_code`),
    KEY `idx_aktif` (`aktif`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;


-- ---------------------------------------------------------------------------
-- LANGKAH 3 - Periksa hasilnya
--   Hasil yang diharapkan: satu baris dengan Tables_in_... = rts_app_versi
-- ---------------------------------------------------------------------------
SHOW TABLES LIKE 'rts_app_versi';

-- Isi tabel (masih kosong sebelum ada unggahan dari halaman app_versi.php)
SELECT COUNT(*) AS jumlah_baris FROM rts_app_versi;


-- ============================================================================
--  LANGKAH OPSIONAL - Mencatat versi pertama lewat SQL
--
--  Cara yang disarankan: unggah APK lewat halaman app_versi.php pada website
--  (menu "Versi Aplikasi"), karena halaman itu mengisi seluruh kolom dengan
--  benar sekaligus menulis berkas app_versi.json.
--
--  Bila ingin mencatat manual, contohnya seperti berikut:
--
--  INSERT INTO rts_app_versi
--      (version_code, version_name, wajib, catatan, apk, ukuran_mb, diunggah_oleh, aktif)
--  VALUES
--      (3, '1.2.0', 0, 'Perbaikan filter GSP dan tampilan beranda baru.',
--       'https://rts.benedic-s.com/apk/rts_panel_v3.apk', 12.40, 'admin@benedic-s.com', 1);
--
--  Bila ada lebih dari satu baris berstatus aktif = 1, halaman API akan
--  memakai baris dengan version_code TERBESAR.
-- ============================================================================

-- ============================================================================
--  SELESAI
--  Setelah tabel ini ada, unggah dan buka halaman app_versi.php pada website.
--  Halaman itu akan menyimpan setiap unggahan ke tabel ini sekaligus menulis
--  berkas app_versi.json.
-- ============================================================================
