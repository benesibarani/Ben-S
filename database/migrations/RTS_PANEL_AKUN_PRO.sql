-- ============================================================================
--  RTS PANEL BY BENE - KOLOM AKUN PRO
--  Berkas : RTS_PANEL_AKUN_PRO.sql
--
--  KEGUNAAN
--  --------
--  Menambah SATU kolom pada tabel sales_users yang menandai apakah sebuah akun
--  berstatus PRO (berlangganan) atau GRATIS.
--
--  AKIBATNYA PADA APLIKASI ANDROID (pilihan b):
--     akun_pro = 0  ->  Akun GRATIS : iklan tampil
--     akun_pro = 1  ->  Akun PRO    : iklan tidak tampil sama sekali
--
--  KEAMANAN
--  --------
--  - Perintah di bawah HANYA MENAMBAH KOLOM. Tidak ada data yang dihapus,
--    tidak ada baris yang diubah, dan tidak ada password yang disentuh.
--  - Seluruh akun yang sudah ada otomatis bernilai 0 (GRATIS), sehingga
--    aplikasi tetap berjalan normal seperti sekarang sampai Anda menandai
--    akun tertentu sebagai PRO pada halaman akun_pro.php.
--  - Jalankan lebih dahulu pada database UJI COBA (benedics_coba), lalu pada
--    produksi SETELAH backup database.
--
--  CARA MENJALANKAN
--  ----------------
--  1. Buka cPanel - phpMyAdmin
--  2. Pilih database (uji coba: benedics_coba | produksi: benedics_bene_sales)
--  3. Buka tab SQL
--  4. Tempel isi berkas ini, tekan Go
--  5. Periksa hasilnya dengan perintah pemeriksaan di bagian bawah berkas ini
--
--  CATATAN: bila muncul pesan "Duplicate column name 'akun_pro'", artinya
--  kolomnya sudah ada - tidak perlu dikerjakan lagi, tidak ada yang rusak.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- LANGKAH 1 - Periksa lebih dahulu, apakah kolomnya sudah ada
--            (jalankan bagian ini saja bila hanya ingin memeriksa)
-- ---------------------------------------------------------------------------
SELECT COUNT(*) AS kolom_akun_pro_sudah_ada
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'sales_users'
  AND COLUMN_NAME = 'akun_pro';

-- ---------------------------------------------------------------------------
-- LANGKAH 2 - Menambah kolom akun_pro
--            (lewati bagian ini bila hasil pemeriksaan di atas menunjukkan 1)
-- ---------------------------------------------------------------------------
ALTER TABLE sales_users
    ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;

-- ---------------------------------------------------------------------------
-- LANGKAH 3 - Periksa hasilnya
-- ---------------------------------------------------------------------------
-- 3a. Pastikan kolomnya sudah ada
SELECT COLUMN_NAME, COLUMN_TYPE, COLUMN_DEFAULT, IS_NULLABLE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME = 'sales_users'
  AND COLUMN_NAME = 'akun_pro';

-- 3b. Ringkasan jumlah akun PRO dan GRATIS
SELECT
    SUM(akun_pro = 1) AS jumlah_pro,
    SUM(akun_pro = 0) AS jumlah_gratis,
    COUNT(*)          AS jumlah_akun
FROM sales_users;

-- ---------------------------------------------------------------------------
--  LANGKAH OPSIONAL - Menandai akun sebagai PRO lewat SQL
--  (cara yang disarankan tetap memakai halaman akun_pro.php pada website,
--   karena lebih aman dan tidak berisiko salah ketik)
-- ---------------------------------------------------------------------------

-- Contoh: menandai akun dengan username tertentu sebagai PRO
-- UPDATE sales_users SET akun_pro = 1 WHERE username = 'admin';

-- Contoh: mengembalikan seluruh akun menjadi GRATIS
-- UPDATE sales_users SET akun_pro = 0;

-- ============================================================================
--  SELESAI
--  Setelah kolom ini ada, buka halaman akun_pro.php pada website untuk
--  menandai akun mana yang PRO. Halaman itu juga akan berhenti menampilkan
--  peringatan "kolom database belum ada".
-- ============================================================================
