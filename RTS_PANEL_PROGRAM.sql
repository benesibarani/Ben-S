-- ============================================================================
--  RTS PANEL BY BENE - TABEL BARU UNTUK MENU PRO "PROGRAM" (INTRODEAL & BD)
--  Putaran 18G - 5 Oktober 2026
--
--  CARA PAKAI
--  ----------
--    1. Backup dulu database Bapak (sangat dianjurkan).
--    2. Buka phpMyAdmin -> pilih database Bapak -> menu SQL.
--    3. Tempel SELURUH isi berkas ini, lalu tekan GO.
--
--  CATATAN
--  -------
--  Perintah di bawah hanya MEMBUAT TABEL BARU bernama rts_program_produk.
--  TIDAK ada tabel atau data lama yang diubah / dihapus. Bila tabelnya sudah
--  ada, perintah ini tidak melakukan apa-apa (aman dijalankan berkali-kali).
--
--  Tabel ini dipakai menu PRO "Program" pada aplikasi RTS Panel:
--      INTRODEAL : produk launching yang sedang diperkenalkan
--      BD        : produk Business Development
--  ADMIN / ASS boleh mengisi daftar ini dari aplikasi (tombol KIRIM KE SERVER),
--  dan seluruh Sales dapat mengambilnya dengan tombol SINKRON ONLINE.
-- ============================================================================

CREATE TABLE IF NOT EXISTS rts_program_produk (
  id INT AUTO_INCREMENT PRIMARY KEY,
  jenis VARCHAR(20) NOT NULL DEFAULT 'INTRODEAL',
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

-- Contoh dua baris (boleh dihapus / diubah):
-- INSERT INTO rts_program_produk (jenis, sku, barcode_pack, nama, merek, isi_per_pack, periode, aktif)
-- VALUES ('INTRODEAL', 'WI-001', '8991234567890', 'Wismilak Inti Kretek', 'Wismilak', 10, 'Oktober 2026', 1);
