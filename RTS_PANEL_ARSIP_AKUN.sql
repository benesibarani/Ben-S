-- ============================================================================
--  RTS PANEL BY BENE - TABEL ARSIP AKUN TIM
--  Berkas : RTS_PANEL_ARSIP_AKUN.sql
--
--  KEGUNAAN
--  --------
--  Membuat SATU tabel baru bernama `sales_users_arsip` pada database
--  benedics_benes_sales.
--
--  Tabel ini adalah KOTAK ARSIP untuk akun tim (WSS, SMST, RTS, TF):
--     - Sebelum sebuah akun DIHAPUS dari sales_users, SELURUH isinya
--       (nama, email, username, password, role, salesman, district, status,
--       dan kolom lain yang ada) disalin lebih dahulu ke tabel ini.
--     - Setiap kali sebuah akun DIEDIT lewat halaman Kelola Akun Tim, isi
--       terbarunya juga dicatat ke tabel ini.
--     - Dengan begitu, akun yang salah dihapus MASIH DAPAT DIPULIHKAN lewat
--       tombol "Pulihkan" pada halaman Kelola Akun Tim (website).
--
--  AMAN DIJALANKAN BERKALI-KALI
--  ----------------------------
--  Perintah pertama memakai "CREATE TABLE IF NOT EXISTS", jadi bila tabelnya
--  sudah ada tidak terjadi apa-apa dan tidak ada data yang terhapus.
--  Perintah ALTER TABLE ditulis terpisah; BILA muncul pesan
--  "Duplicate column name 'aksi'" artinya kolomnya sudah ada - itu BUKAN
--  kesalahan dan aman untuk dilewati.
--
--  CARA MENJALANKAN (phpMyAdmin)
--  -----------------------------
--   1. Masuk cPanel -> phpMyAdmin
--   2. Pilih database : benedics_benes_sales  (klik namanya di kiri)
--   3. Klik tab "SQL"
--   4. Tempel SELURUH isi berkas ini, lalu tekan tombol "Go" / "Jalankan"
--   5. Selesai. Kembali ke aplikasi web -> menu "Kelola Akun Tim".
--
--  CATATAN: perintah di bawah TIDAK menyentuh tabel sales_users sama sekali.
--  Tidak ada satu pun akun yang diubah atau dihapus oleh berkas ini.
-- ============================================================================

-- 1. Salinan susunan tabel akun (kolom, tipe, dan kunci utama ikut tersalin).
CREATE TABLE IF NOT EXISTS sales_users_arsip LIKE sales_users;

-- 2. Kolom keterangan: aksi apa yang terjadi (DIHAPUS / DIUBAH / DIHAPUS-... ).
ALTER TABLE sales_users_arsip ADD COLUMN aksi VARCHAR(30) NOT NULL DEFAULT 'DIHAPUS';

-- 3. Kolom keterangan: siapa (username) yang melakukan.
ALTER TABLE sales_users_arsip ADD COLUMN oleh VARCHAR(100) NOT NULL DEFAULT '';

-- 4. Kolom keterangan: kapan kejadiannya.
ALTER TABLE sales_users_arsip ADD COLUMN waktu TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- 5. Indeks pencarian supaya daftar arsip tetap cepat walau isinya banyak.
ALTER TABLE sales_users_arsip ADD INDEX idx_arsip_username (username);

-- ============================================================================
--  SELESAI. Setelah ini, halaman Kelola Akun Tim dapat menghapus akun dengan
--  aman (selalu disalin ke arsip lebih dahulu).
-- ============================================================================


-- ============================================================================
--  TAMBAHAN OPSIONAL (jalankan hanya bila perlu)
-- ============================================================================
--
--  a. MASA LANGGANAN PRO & TRIAL PER AKUN
--     Sejak TAMBAHAN 18B, halaman Kelola Akun Tim dapat:
--        - membuat / memperpanjang PRO   (hanya ADMIN)
--        - memperpanjang TRIAL           (hanya ADMIN)
--        - menghapus status PRO          (hanya ADMIN)
--
--     Nama kolom yang dipakai adalah kolom yang SAMA dengan menu Langganan PRO
--     dan aplikasi Android:  akun_pro, pro_mulai, pro_selesai, trial_mulai,
--     trial_selesai. Halaman mencari sendiri kolomnya; bila tidak ada, halaman
--     menampilkan pesan yang menjelaskan apa yang harus dijalankan (tidak error).
--
--     Bila di database Bapak belum ada kolomnya, jalankan perintah berikut
--     (PALING MUDAH: jalankan berkas RTS_PANEL_LANGGANAN_PRO.sql yang sudah ada):
--
--        ALTER TABLE sales_users ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;
--        ALTER TABLE sales_users ADD COLUMN pro_mulai DATETIME NULL;
--        ALTER TABLE sales_users ADD COLUMN pro_selesai DATETIME NULL;
--        ALTER TABLE sales_users ADD COLUMN trial_mulai DATETIME NULL;
--        ALTER TABLE sales_users ADD COLUMN trial_selesai DATETIME NULL;
--
--     Catatan: nama kolom tanggal berakhir PRO yang benar adalah `pro_selesai`
--     (itulah yang dibaca aplikasi Android). Bila di database hanya ada
--     `pro_sampai`, halaman tetap dapat memakainya sebagai cadangan:
--
--        ALTER TABLE sales_users ADD COLUMN pro_sampai DATETIME NULL;
--
--     Bila salah satu kolom sudah ada, akan muncul pesan
--     "Duplicate column name" - itu bukan kesalahan, cukup dilewati.
--
--  a2. MEMERIKSA STATUS LANGGANAN
--
--        SELECT id, username, role, akun_pro, pro_mulai, pro_selesai,
--               trial_mulai, trial_selesai
--        FROM sales_users
--        WHERE UPPER(role) IN ('WSS','SMST','RTS','TF')
--        ORDER BY akun_pro DESC, username ASC;

--  b. MELIHAT ISI ARSIP
--
--        SELECT id, nama_lengkap, username, role, sales_district, aksi, oleh, waktu
--        FROM sales_users_arsip ORDER BY id DESC;
--
--  c. MEMULIHKAN SECARA MANUAL (bila perlu, tanpa lewat website)
--     Ganti angka 1 pada contoh berikut dengan nomor arsip yang diinginkan.
--     Lihat dulu barisnya dengan perintah (b) di atas.
--
--        INSERT INTO sales_users (nama_lengkap, email, username, password, role,
--                                 salesman, sales_district, status_aktif)
--        SELECT nama_lengkap, email, username, password, role, salesman,
--               sales_district, status_aktif
--        FROM sales_users_arsip WHERE id = 1;
-- ============================================================================
