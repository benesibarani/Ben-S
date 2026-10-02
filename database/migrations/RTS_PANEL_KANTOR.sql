-- ============================================================================
--  RTS PANEL BY BENE - TABEL LOKASI KANTOR / MITRA (AWAL RUTE PLAN)
--  Berkas : RTS_PANEL_KANTOR.sql
--  Dibuat : 3 Oktober 2026
--
--  CARA MENJALANKAN DI phpMyAdmin
--  ------------------------------
--   1. Buka cPanel -> phpMyAdmin -> pilih database RTS Panel
--      (benedics_benes_sales).
--   2. Klik tab "SQL", tempelkan SELURUH isi berkas ini, lalu tekan GO.
--   3. Muncul pesan "Your SQL query has been executed successfully".
--   4. Tabel baru bernama `rts_kantor` akan tampak pada daftar tabel di
--      sebelah kiri.
--
--  KETERANGAN
--  ----------
--   Tabel ini menyimpan TITIK LOKASI KANTOR / MITRA. Titik ini dipakai menu
--   RUTE PLAN pada aplikasi sebagai AWAL perhitungan urutan kunjungan:
--
--     toko nomor 1 = toko paling dekat dari KANTOR, lalu terus ke yang jauh.
--
--   Cara mengisi (paling mudah, lewat aplikasi - tidak perlu phpMyAdmin):
--     1. Masuk aplikasi memakai akun ADMIN (atau ASS).
--     2. Buka Menu PRO -> RUTE PLAN.
--     3. Tekan tombol gedung (kanan atas) -> LOKASI KANTOR / MITRA.
--     4. Tekan tombol KANTOR di kanan bawah.
--     5. Isi nama & alamat kantor.
--     6. Berdiri di kantor, lalu tekan  AMBIL TITIK DARI LOKASI SAYA.
--     7. Tekan SIMPAN. Titik langsung tersimpan ke tabel ini dan disalin ke
--        seluruh HP sales saat mereka menekan MUAT KANTOR / MUAT DARI SERVER.
--
--   Boleh lebih dari satu kantor (misalnya Kantor Medan dan Kantor Binjai).
--   Sales memilih kantor pada menu RUTE PLAN.
--
--   Aman dijalankan berkali-kali (IF NOT EXISTS) dan tidak menghapus data.
-- ============================================================================

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS `rts_kantor` (
  `id`          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `nama`        VARCHAR(120) NOT NULL              COMMENT 'Nama kantor / mitra, contoh: KANTOR MEDAN',
  `alamat`      VARCHAR(255) NOT NULL DEFAULT ''   COMMENT 'Alamat kantor (opsional, untuk ditampilkan pada daftar rute)',
  `district`    VARCHAR(120) NOT NULL DEFAULT ''   COMMENT 'Sales District yang dilayani kantor ini; kosong = semua district',
  `latitude`    DECIMAL(11,7) NOT NULL DEFAULT 0   COMMENT 'Lintang titik kantor (diambil dari GPS aplikasi)',
  `longitude`   DECIMAL(11,7) NOT NULL DEFAULT 0   COMMENT 'Bujur titik kantor (diambil dari GPS aplikasi)',
  `catatan`     VARCHAR(255) NOT NULL DEFAULT ''   COMMENT 'Catatan (opsional)',
  `dibuat_oleh` VARCHAR(100) NOT NULL DEFAULT ''   COMMENT 'Nama user yang menitikkan',
  `dibuat_pada` DATETIME     NULL     DEFAULT NULL,
  `diubah_oleh` VARCHAR(100) NOT NULL DEFAULT ''   COMMENT 'Nama user yang terakhir mengubah',
  `diubah_pada` DATETIME     NULL     DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_nama` (`nama`),
  KEY `idx_district` (`district`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- ---------------------------------------------------------------------------
--  CONTOH PENGISIAN LANGSUNG DARI phpMyAdmin (bila tidak memakai aplikasi)
--  ------------------------------------------------------------------------
--  Ganti nama, alamat, dan angkanya sesuai kantor Bapak.
--  Angka 3.595200 , 98.672200 adalah contoh titik tengah Kota Medan.
--
--  INSERT INTO `rts_kantor`
--    (`nama`, `alamat`, `district`, `latitude`, `longitude`, `catatan`,
--     `dibuat_oleh`, `dibuat_pada`, `diubah_pada`)
--  VALUES
--    ('KANTOR MEDAN', 'Jl. Contoh No. 1, Medan', '', 3.5952000, 98.6722000,
--     '', 'ADMIN', NOW(), NOW());
--
--  Melihat seluruh titik kantor:
--    SELECT id, nama, alamat, district, latitude, longitude, diubah_pada
--      FROM `rts_kantor` ORDER BY nama;
--
--  Menghapus satu titik kantor:
--    DELETE FROM `rts_kantor` WHERE id = 1;
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
--  PEMERIKSAAN SESUDAH DIJALANKAN (boleh dijalankan, hanya membaca)
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS jumlah_titik_kantor FROM `rts_kantor`;
