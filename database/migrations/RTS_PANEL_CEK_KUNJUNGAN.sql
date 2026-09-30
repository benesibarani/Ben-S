-- =============================================================================
-- RTS Panel By Bene
-- PEMERIKSAAN KOLOM KUNJUNGAN PADA MASTER CUSTOMER
-- =============================================================================
--
-- HANYA MEMBACA DATA (SELECT). Tidak ada perintah yang mengubah atau menghapus
-- apa pun, sehingga aman dijalankan pada database produksi.
--
-- KAPAN DIPAKAI?
--
-- Sebelum perbaikan, saat pengajuan "Tambah Baru" disetujui, kolom `kunjungan`
-- pada master_toko terisi NAMA HARI (karena memakai kolom rute_kunjungan),
-- padahal isinya seharusnya frekuensi kunjungan.
--
-- Perbaikan sudah dipasang pada inbox.php dan api/request_apply.php. Berkas ini
-- dipakai untuk memeriksa apakah masih ada data lama yang salah isi.
--
-- CARA MENJALANKAN:
--   1. Buka cPanel > phpMyAdmin
--   2. Pilih database (benedics_bene_sales untuk produksi)
--   3. Tab SQL, salin isi berkas ini, tekan GO
--
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. RINGKASAN: nilai apa saja yang ada pada kolom kunjungan
-- -----------------------------------------------------------------------------
-- Nilai yang BENAR hanya tiga:
--   Weekly            -> 1 kali setiap minggu
--   Bi-Weekly Ganjil  -> 2 minggu sekali pada minggu ganjil
--   Bi-Weekly Genap   -> 2 minggu sekali pada minggu genap
--
-- Bila muncul nama hari (Senin .. Sabtu) atau nilai lain, berarti baris itu
-- berasal dari pengajuan lama dan perlu diperbaiki.

SELECT
    kunjungan,
    COUNT(*) AS jumlah_toko
FROM master_toko
GROUP BY kunjungan
ORDER BY jumlah_toko DESC;

-- -----------------------------------------------------------------------------
-- 2. DAFTAR CUSTOMER YANG PERLU DIPERIKSA
-- -----------------------------------------------------------------------------
-- Menampilkan customer yang kolom kunjungan-nya berisi nama hari (data lama).

SELECT
    id_customer,
    nama_toko,
    kunjungan,
    hari,
    salesman,
    sales_district,
    status_aktif
FROM master_toko
WHERE UPPER(TRIM(kunjungan)) IN
      ('SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU')
ORDER BY nama_toko ASC;

-- -----------------------------------------------------------------------------
-- 3. HITUNGAN: berapa banyak customer yang terpengaruh
-- -----------------------------------------------------------------------------

SELECT COUNT(*) AS jumlah_perlu_diperiksa
FROM master_toko
WHERE UPPER(TRIM(kunjungan)) IN
      ('SENIN', 'SELASA', 'RABU', 'KAMIS', 'JUMAT', 'SABTU', 'MINGGU');

-- =============================================================================
-- 4. JENIS KOLOM PENYIMPANAN (UNTUK MEMASTIKAN PANJANG NILAI CUKUP)
-- =============================================================================
-- Nilai "Bi-Weekly Ganjil" panjangnya 16 huruf. Bila kolom week pada
-- pengajuan_sales bertipe ENUM('Ganjil','Genap') atau VARCHAR yang terlalu
-- pendek, nilai baru tidak akan tersimpan dengan benar.
--
-- Kolom kunjungan pada master_toko minimal harus VARCHAR(20).

SELECT
    TABLE_NAME,
    COLUMN_NAME,
    COLUMN_TYPE,
    IS_NULLABLE,
    COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND (
        (TABLE_NAME = 'pengajuan_sales' AND COLUMN_NAME IN ('week', 'rute_kunjungan'))
     OR (TABLE_NAME = 'master_toko'     AND COLUMN_NAME IN ('kunjungan', 'hari'))
      )
ORDER BY TABLE_NAME, COLUMN_NAME;

-- =============================================================================
-- 5. PERBAIKAN JENIS KOLOM (JANGAN DIJALANKAN TANPA BACKUP)
-- =============================================================================
-- Bacalah bagian 4 lebih dahulu.
--
--  - Bila kolom `week` pada pengajuan_sales bertipe VARCHAR(20) atau lebih
--    panjang  -> tidak perlu apa-apa, lewati bagian ini.
--  - Bila bertipe ENUM('Ganjil','Genap') atau VARCHAR yang lebih pendek dari 20
--    -> nilai "Bi-Weekly Ganjil" tidak dapat tersimpan, dan pengajuan baru dari
--       aplikasi dapat gagal terkirim. Perbaikannya adalah mengubah jenis kolom.
--
-- JANGAN jalankan perintah di bawah sebelum:
--    1. membuat backup database, dan
--    2. mengujinya lebih dahulu pada database staging (benedics_coba).
--
-- Lepas tanda komentar ( /* dan */ ) untuk menjalankannya.
--
-- Nilai lama 'Ganjil' dan 'Genap' TIDAK hilang saat diubah menjadi VARCHAR;
-- keduanya tetap dikenali dan otomatis diterjemahkan menjadi
-- 'Bi-Weekly Ganjil' / 'Bi-Weekly Genap' ketika pengajuan disetujui.

/*
ALTER TABLE pengajuan_sales
    MODIFY week VARCHAR(20) NULL;

ALTER TABLE master_toko
    MODIFY kunjungan VARCHAR(20) NULL;
*/

-- Setelah menjalankan perintah di atas, ulangi bagian 4 untuk memastikan
-- jenis kolom sudah berubah.

-- =============================================================================
-- BILA HASIL BAGIAN 3 BERNILAI 0
-- =============================================================================
-- Tidak ada yang perlu dikerjakan. Data sudah benar dan perbaikan pada
-- inbox.php serta api/request_apply.php mencegah kejadian yang sama terulang.
--
-- =============================================================================
-- BILA HASIL BAGIAN 3 LEBIH DARI 0
-- =============================================================================
-- Jangan langsung diperbaiki. Dua hal perlu ditentukan lebih dahulu:
--
--   1. Nilai pengganti: Weekly, Bi-Weekly Ganjil, atau Bi-Weekly Genap?
--      Bila ragu, lihat kolom `week` pada tabel pengajuan_sales untuk
--      id_customer tersebut - di situ tersimpan pengajuan aslinya.
--
--   2. Apakah seluruh baris yang terpengaruh memakai nilai yang sama?
--
-- Contoh perintah untuk melihat pengajuan asal dari customer tersebut
-- (jalankan setelah mengubah daftar ID di bawah):
--
--   SELECT id, id_customer, nama_toko_lama, nama_toko_baru, week, hari,
--          visit_day_baru, tanggal_request, status_approval
--   FROM pengajuan_sales
--   WHERE id_customer IN ('3000000001', '3000000002')
--   ORDER BY tanggal_request DESC;
--
-- Setelah nilainya jelas, mintalah Admin membuat perintah UPDATE khusus untuk
-- baris-baris tersebut, dan jalankan SETELAH membuat backup database.
