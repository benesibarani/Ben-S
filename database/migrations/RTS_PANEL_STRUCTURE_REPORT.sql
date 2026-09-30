-- =============================================================================
-- RTS PANEL - PEMERIKSAAN STRUKTUR DATABASE (VERSI 2)
--
-- HANYA MEMBACA. Tidak mengubah apa pun. Aman dijalankan di mana saja.
--
-- Versi ini hanya menyentuh information_schema, sehingga tidak terpengaruh
-- database yang sedang aktif dipilih dan tidak akan memunculkan error
-- "#1109 - Unknown table ... in information_schema" seperti versi pertama.
--
-- Cara pakai:
--   1. phpMyAdmin -> klik salah satu database (boleh database mana saja).
--   2. Tab SQL -> tempel SELURUH isi file ini -> Kirim / Go.
--   3. Hasilnya tiga kolom: kategori, nama, info.
--   4. Kirimkan hasilnya (boleh berupa tangkapan layar).
--
-- Hasil akan menampilkan semua database yang namanya berawalan "benedics",
-- sehingga langsung terlihat perbedaan antara database staging dan produksi.
-- =============================================================================

SELECT 'TABEL' AS kategori,
       CONCAT(TABLE_SCHEMA, '.', TABLE_NAME) AS nama,
       IFNULL(TABLE_ROWS, 0) AS info
FROM information_schema.TABLES
WHERE TABLE_SCHEMA LIKE 'benedics%'
  AND TABLE_NAME IN (
      'api_tokens',
      'master_toko',
      'master_toko_deleted',
      'sales_users',
      'pengajuan_sales',
      'pengajuan_gsp',
      'riwayat_aksi'
  )

UNION ALL

SELECT 'KOLOM' AS kategori,
       CONCAT(TABLE_SCHEMA, '.', TABLE_NAME, '.', COLUMN_NAME) AS nama,
       COLUMN_TYPE AS info
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA LIKE 'benedics%'
  AND (
        (TABLE_NAME = 'sales_users' AND COLUMN_NAME IN ('username', 'status_aktif', 'salesman', 'sales_district'))
     OR (TABLE_NAME = 'master_toko' AND COLUMN_NAME IN ('tipe_customer'))
     OR (TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME IN ('processed_by', 'processed_at', 'approval_note'))
     OR (TABLE_NAME = 'pengajuan_gsp' AND COLUMN_NAME IN ('jenis_request', 'processed_by', 'processed_at', 'approval_note'))
  )

ORDER BY kategori, nama;
