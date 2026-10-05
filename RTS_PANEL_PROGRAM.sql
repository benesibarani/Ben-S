-- ============================================================================
--  RTS PANEL BY BENE - TABEL BARU UNTUK MENU PRO "PROGRAM" (INTRODEAL & BD)
--  Putaran 18I - 5 Oktober 2026 (revisi: paket Introdeal + input program +
--                 nama program bebas, karena Sales dapat membuat program
--                 sendiri di samping INTRODEAL dan BD)
--
--  CARA PAKAI
--  ----------
--    1. Backup dulu database Bapak (sangat dianjurkan).
--    2. Buka phpMyAdmin -> pilih database Bapak -> menu SQL.
--    3. Tempel SELURUH isi berkas ini, lalu tekan GO.
--
--  CATATAN
--  -------
--  Perintah di bawah hanya MEMBUAT TABEL BARU (tidak ada tabel / data lama
--  yang dihapus). Bisa dijalankan berkali-kali dengan aman.
--
--  Tabel yang dibuat:
--   1. rts_program_produk = daftar produk program.
--   2. rts_program_paket  = daftar PAKET Introdeal (2+1, 1+1, paket buatan
--      Sales), sekaligus diisi paket bawaan 2+1 dan 1+1.
--   3. rts_program_input  = CATATAN PROGRAM yang dikirim dari HP Sales
--      (hasil tombol CATAT PROGRAM -> KIRIM KE SERVER).
--
--  ARTI PROGRAM (sesuai penjelasan Bapak)
--  --------------------------------------
--    INTRODEAL = Introductory Deal, yaitu PROGRAM PAKET. Paket bakunya "2+1"
--                dan "1+1"; Sales juga dapat membuat paket sendiri (mis. "3+1").
--                Produk diambil dari Menu Barang Bawaan.
--    BD        = New Brand Distribution (produk baru yang SUDAH ADA di outlet).
--                TIDAK memakai paket - hanya produk.
-- ============================================================================

CREATE TABLE IF NOT EXISTS rts_program_produk (
  id INT AUTO_INCREMENT PRIMARY KEY,
  jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',
  paket VARCHAR(20) NOT NULL DEFAULT '',
  sku VARCHAR(64) NOT NULL DEFAULT '',
  barcode_pack VARCHAR(64) NOT NULL DEFAULT '',
  nama VARCHAR(150) NOT NULL DEFAULT '',
  merek VARCHAR(80) NOT NULL DEFAULT '',
  isi_per_pack INT NOT NULL DEFAULT 0,
  catatan VARCHAR(255) NOT NULL DEFAULT '',
  periode VARCHAR(60) NOT NULL DEFAULT '',
  aktif TINYINT NOT NULL DEFAULT 1,
  diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',
  diubah_pada DATETIME NULL,
  UNIQUE KEY uq_program_jenis_sku (jenis, sku)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- CATATAN PROGRAM yang dicatat Sales dari HP (dipakai tombol CATAT PROGRAM,
-- lalu dikirim ke server lewat CATATAN TERSIMPAN -> KIRIM KE SERVER):
CREATE TABLE IF NOT EXISTS rts_program_input (
  id INT AUTO_INCREMENT PRIMARY KEY,
  jenis VARCHAR(40) NOT NULL DEFAULT 'INTRODEAL',
  paket VARCHAR(20) NOT NULL DEFAULT '',
  paket_keterangan VARCHAR(120) NOT NULL DEFAULT '',
  id_customer VARCHAR(40) NOT NULL DEFAULT '',
  nama_toko VARCHAR(150) NOT NULL DEFAULT '',
  produk_id INT NOT NULL DEFAULT 0,
  nama_produk VARCHAR(150) NOT NULL DEFAULT '',
  sku VARCHAR(64) NOT NULL DEFAULT '',
  jumlah DECIMAL(12,2) NOT NULL DEFAULT 0,
  satuan VARCHAR(20) NOT NULL DEFAULT 'PACK',
  tanggal VARCHAR(20) NOT NULL DEFAULT '',
  catatan VARCHAR(255) NOT NULL DEFAULT '',
  id_sales VARCHAR(40) NOT NULL DEFAULT '',
  nama_sales VARCHAR(80) NOT NULL DEFAULT '',
  id_hp VARCHAR(60) NOT NULL DEFAULT '',
  diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',
  diubah_pada DATETIME NULL,
  KEY ix_input_sales (id_sales),
  KEY ix_input_customer (id_customer)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Paket Introdeal (2+1, 1+1, dan paket buatan Sales):
CREATE TABLE IF NOT EXISTS rts_program_paket (
  id INT AUTO_INCREMENT PRIMARY KEY,
  jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',
  nama VARCHAR(20) NOT NULL DEFAULT '',
  keterangan VARCHAR(120) NOT NULL DEFAULT '',
  bawaan TINYINT NOT NULL DEFAULT 0,
  diubah_oleh VARCHAR(80) NOT NULL DEFAULT '',
  diubah_pada DATETIME NULL,
  UNIQUE KEY uq_paket_jenis_nama (jenis, nama)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Paket bawaan 2+1 dan 1+1 (tidak menimpa paket buatan Sales):
INSERT IGNORE INTO rts_program_paket (jenis, nama, keterangan, bawaan, diubah_oleh, diubah_pada)
VALUES ('INTRODEAL', '2+1', 'Beli 2 gratis 1', 1, 'sistem', NOW()),
       ('INTRODEAL', '1+1', 'Beli 1 gratis 1', 1, 'sistem', NOW());

-- Contoh dua baris (boleh dihapus / diubah):
-- INSERT INTO rts_program_produk (jenis, sku, barcode_pack, nama, merek, isi_per_pack, periode, aktif)
-- VALUES ('INTRODEAL', 'WI-001', '8991234567890', 'Wismilak Inti Kretek', 'Wismilak', 10, 'Oktober 2026', 1);
