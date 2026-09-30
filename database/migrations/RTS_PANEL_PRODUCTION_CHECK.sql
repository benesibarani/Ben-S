-- =============================================================================
-- RTS PANEL - PEMERIKSAAN KESIAPAN DATABASE PRODUKSI
-- Database: rts.benedic-s.com  (benedics_rts / sesuai config.php produksi)
--
-- FILE INI HANYA MEMBACA DATA (SELECT). TIDAK MENGUBAH APA PUN.
-- Aman dijalankan di produksi kapan saja.
--
-- Cara pakai:
--   1. cPanel -> phpMyAdmin -> pilih database PRODUKSI.
--   2. Tab SQL -> tempel seluruh isi file ini -> Go.
--   3. Lihat tabel hasil: setiap baris berstatus ADA atau BELUM ADA.
--   4. Kirimkan hasilnya, agar langkah migrasi produksi disusun tepat.
--
-- Catatan: bila ada baris "BELUM ADA", jangan beralih ke produksi dulu.
-- =============================================================================

SELECT 'Tabel api_tokens' AS item,
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA') AS status,
       'Tempat token login Android' AS keterangan
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'api_tokens'

UNION ALL
SELECT 'Tabel master_toko',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Master Customer utama'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko'

UNION ALL
SELECT 'Tabel master_toko_deleted',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Arsip customer yang dihapus (wajib untuk pengajuan Hapus Toko)'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko_deleted'

UNION ALL
SELECT 'Tabel sales_users',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Akun login website dan Android'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users'

UNION ALL
SELECT 'Tabel pengajuan_sales',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Pengajuan toko reguler'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales'

UNION ALL
SELECT 'Tabel pengajuan_gsp',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Pengajuan GSP'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp'

UNION ALL
SELECT 'Tabel riwayat_aksi',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Catatan tindakan approve / reject'
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'riwayat_aksi'

UNION ALL
SELECT 'Kolom sales_users.username',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Login Android memakai username'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users' AND COLUMN_NAME = 'username'

UNION ALL
SELECT 'Kolom sales_users.status_aktif',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Pemeriksaan akun aktif'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users' AND COLUMN_NAME = 'status_aktif'

UNION ALL
SELECT 'Kolom sales_users.salesman',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Pembatasan data untuk role RTS dan TF'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users' AND COLUMN_NAME = 'salesman'

UNION ALL
SELECT 'Kolom sales_users.sales_district',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'District pengguna'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users' AND COLUMN_NAME = 'sales_district'

UNION ALL
SELECT 'Kolom master_toko.tipe_customer',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Kategori REGULER / GSP'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko' AND COLUMN_NAME = 'tipe_customer'

UNION ALL
SELECT 'Kolom pengajuan_sales.processed_by',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Nama pemeriksa pengajuan'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME = 'processed_by'

UNION ALL
SELECT 'Kolom pengajuan_sales.processed_at',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Waktu pemeriksaan pengajuan'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME = 'processed_at'

UNION ALL
SELECT 'Kolom pengajuan_sales.approval_note',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Catatan approve / reject'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME = 'approval_note'

UNION ALL
SELECT 'Kolom pengajuan_gsp.jenis_request',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'PENAMBAHAN atau PENGHAPUSAN GSP'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp' AND COLUMN_NAME = 'jenis_request'

UNION ALL
SELECT 'Kolom pengajuan_gsp.processed_by',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Nama pemeriksa pengajuan GSP'
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'pengajuan_gsp' AND COLUMN_NAME = 'processed_by'

UNION ALL
SELECT 'Index idx_master_toko_tipe_customer',
       IF(COUNT(*) > 0, 'ADA', 'BELUM ADA'),
       'Mempercepat filter kategori'
FROM information_schema.STATISTICS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'master_toko' AND INDEX_NAME = 'idx_master_toko_tipe_customer';

-- ---------------------------------------------------------------------------
-- Ringkasan jumlah data penting (hanya membaca)
-- ---------------------------------------------------------------------------

SELECT 'Jumlah customer' AS keterangan, COUNT(*) AS jumlah FROM master_toko
UNION ALL
SELECT 'Jumlah akun pengguna', COUNT(*) FROM sales_users
UNION ALL
SELECT 'Pengajuan toko Pending', COUNT(*) FROM pengajuan_sales WHERE status_approval = 'Pending';
