-- ============================================================================
--  RTS PANEL BY BENE - LANGGANAN PRO (masa berlaku 30 hari + uji coba 7 hari)
--  Berkas : database/migrations/RTS_PANEL_LANGGANAN_PRO.sql
--
--  CARA MENJALANKAN
--  ----------------
--  Cara termudah : buka halaman langganan_admin.php di website, tekan tombol
--                  "PERBARUI DATABASE" (prosesnya sama dengan berkas ini).
--  Cara manual   : phpMyAdmin -> pilih database -> tab SQL -> tempel isi berkas
--                  ini -> Kirim.
--
--  CATATAN PENTING
--  ---------------
--  Jalankan pada DATABASE UJI COBA lebih dahulu (benedics_coba), setelah
--  backup. Bila muncul pesan seperti:
--      #1060 - Duplicate column name 'akun_pro'
--  artinya kolom itu SUDAH ADA - pesan itu aman dan boleh dilewati.
--
--  Seluruh perintah hanya MENAMBAH kolom/tabel dan tidak menghapus data.
-- ============================================================================

-- 1. Kolom penanda langganan pada tabel sales_users -------------------------

-- Penanda akun PRO (1 = PRO, 0 = GRATIS). Bila sudah ada, lewati baris ini.
ALTER TABLE sales_users
  ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;

-- Nama berkas foto pribadi petugas (mis. uploads/foto_profil/u3_20260930.jpg).
ALTER TABLE sales_users
  ADD COLUMN foto_profil VARCHAR(255) NOT NULL DEFAULT '';

-- Tanggal mulai berlangganan PRO.
ALTER TABLE sales_users
  ADD COLUMN pro_mulai DATETIME NULL DEFAULT NULL;

-- Tanggal berakhir berlangganan PRO (30 hari setiap pembayaran).
ALTER TABLE sales_users
  ADD COLUMN pro_selesai DATETIME NULL DEFAULT NULL;

-- Tanggal mulai uji coba gratis (7 hari, sekali saja per akun).
ALTER TABLE sales_users
  ADD COLUMN trial_mulai DATETIME NULL DEFAULT NULL;

-- Tanggal berakhir uji coba gratis.
ALTER TABLE sales_users
  ADD COLUMN trial_selesai DATETIME NULL DEFAULT NULL;

-- 2. Tabel pernyataan pembayaran QRIS --------------------------------------
--    Diisi saat petugas menekan "SAYA SUDAH BAYAR" pada aplikasi, lalu
--    disetujui Admin melalui halaman langganan_admin.php.

CREATE TABLE IF NOT EXISTS pembayaran_pro (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NOT NULL,
  jumlah INT NOT NULL DEFAULT 0,
  hari INT NOT NULL DEFAULT 30,
  catatan VARCHAR(255) NOT NULL DEFAULT '',
  sebab VARCHAR(40) NOT NULL DEFAULT '',
  status VARCHAR(20) NOT NULL DEFAULT 'MENUNGGU',
  dibuat DATETIME NULL DEFAULT NULL,
  diproses_pada DATETIME NULL DEFAULT NULL,
  KEY idx_user (user_id),
  KEY idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- 3. Pemeriksaan hasil -----------------------------------------------------
--    Menampilkan kolom langganan yang sudah ada.

SHOW COLUMNS FROM sales_users LIKE 'akun_pro';
SHOW COLUMNS FROM sales_users LIKE 'foto_profil';
SHOW COLUMNS FROM sales_users LIKE 'pro_mulai';
SHOW COLUMNS FROM sales_users LIKE 'pro_selesai';
SHOW COLUMNS FROM sales_users LIKE 'trial_mulai';
SHOW COLUMNS FROM sales_users LIKE 'trial_selesai';
SHOW TABLES LIKE 'pembayaran_pro';
