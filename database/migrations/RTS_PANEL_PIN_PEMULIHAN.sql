-- ============================================================================
--  RTS PANEL BY BENE - PIN PEMULIHAN PASSWORD
--  Berkas : RTS_PANEL_PIN_PEMULIHAN.sql   (untuk cPanel / phpMyAdmin)
--
--  KEGUNAAN
--  --------
--  Menambah tiga kolom pada tabel sales_users:
--     pin_hash             : hash PIN 6 digit (BUKAN PIN asli)
--     pin_gagal            : jumlah PIN salah berturut-turut
--     pin_terkunci_sampai  : waktu kunci berakhir (NULL = tidak terkunci)
--
--  CARA MENJALANKAN (phpMyAdmin)
--  -----------------------------
--  1. Pilih database produksi (benedics_bene_sales) di panel kiri.
--  2. Klik tab SQL, tempel isi berkas ini, lalu klik Kirim (Go).
--  3. Jika muncul "#1060 - Duplicate column name", kolom itu SUDAH ada.
--     Tidak ada yang rusak. Lanjutkan ke baris berikutnya secara manual.
-- ============================================================================

ALTER TABLE `sales_users`
  ADD COLUMN `pin_hash` VARCHAR(255) NULL DEFAULT NULL,
  ADD COLUMN `pin_gagal` INT NOT NULL DEFAULT 0,
  ADD COLUMN `pin_terkunci_sampai` DATETIME NULL DEFAULT NULL;
