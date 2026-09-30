-- ============================================================================
--  RTS PANEL BY BENE - KOLOM AKUN PRO
--  Berkas : RTS_PANEL_AKUN_PRO.sql      VERSI 2 (untuk cPanel / phpMyAdmin)
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
--  PERBEDAAN DENGAN VERSI 1
--  ------------------------
--  Versi 1 gagal dengan pesan:
--     #1044 - Access denied for user 'cpses_...'@'localhost'
--             to database 'information_schema'
--  Sebabnya: versi 1 memakai tabel information_schema untuk memeriksa kolom,
--  sedangkan akun phpMyAdmin di cPanel tidak diberi izin membaca tabel itu.
--  Akibatnya phpMyAdmin berhenti pada baris pertama dan perintah ALTER TABLE
--  tidak pernah dijalankan.
--
--  Versi 2 ini TIDAK memakai information_schema sama sekali. Seluruh
--  pemeriksaan memakai SHOW COLUMNS, yang selalu tersedia.
--
--  CARA MENJALANKAN (phpMyAdmin)
--  -----------------------------
--  1. Buka cPanel - phpMyAdmin
--  2. Pilih database di panel kiri:
--        uji coba : benedics_coba
--        produksi : benedics_bene_sales
--  3. Klik tab SQL
--  4. Tempel SELURUH isi berkas ini, lalu klik Kirim (Go)
--  5. Bila muncul pesan "#1060 - Duplicate column name 'akun_pro'" - itu
--     berarti kolomnya SUDAH ADA. Tidak ada yang rusak. Buka tab Struktur
--     tabel sales_users untuk memastikan kolom akun_pro ada di baris paling
--     bawah, lalu lanjutkan ke bagian website (akun_pro.php).
--
--  KEAMANAN
--  --------
--  Perintah ALTER TABLE di bawah HANYA MENAMBAH KOLOM. Tidak ada data yang
--  dihapus, tidak ada baris yang diubah, dan tidak ada password yang disentuh.
--  Seluruh akun yang sudah ada otomatis bernilai 0 (GRATIS).
-- ============================================================================


-- ---------------------------------------------------------------------------
-- LANGKAH 1 - Memeriksa, apakah kolomnya sudah ada
--   Hasil kosong (0 baris)  = kolom belum ada, lanjutkan ke LANGKAH 2
--   Muncul satu baris       = kolom sudah ada, LANGSUNG ke LANGKAH 3
-- ---------------------------------------------------------------------------
SHOW COLUMNS FROM sales_users LIKE 'akun_pro';


-- ---------------------------------------------------------------------------
-- LANGKAH 2 - Menambah kolom akun_pro
--   (lewati bagian ini bila LANGKAH 1 sudah menampilkan satu baris)
-- ---------------------------------------------------------------------------
ALTER TABLE sales_users
    ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;


-- ---------------------------------------------------------------------------
-- LANGKAH 3 - Memastikan kolomnya sudah ada
--   Hasil yang diharapkan: satu baris dengan Field = akun_pro
-- ---------------------------------------------------------------------------
SHOW COLUMNS FROM sales_users LIKE 'akun_pro';


-- ---------------------------------------------------------------------------
-- LANGKAH 4 - Ringkasan jumlah akun (seluruhnya masih GRATIS setelah ini)
-- ---------------------------------------------------------------------------
SELECT
    SUM(akun_pro = 1) AS jumlah_pro,
    SUM(akun_pro = 0) AS jumlah_gratis,
    COUNT(*)          AS jumlah_akun
FROM sales_users;


-- ============================================================================
--  LANGKAH OPSIONAL - Menandai akun sebagai PRO lewat SQL
--  Cara yang disarankan tetap memakai halaman akun_pro.php pada website,
--  karena lebih aman dan tidak berisiko salah ketik.
-- ============================================================================

-- Contoh: menandai akun dengan username tertentu sebagai PRO
-- UPDATE sales_users SET akun_pro = 1 WHERE username = 'admin';

-- Contoh: mengembalikan seluruh akun menjadi GRATIS
-- UPDATE sales_users SET akun_pro = 0;

-- ============================================================================
--  SELESAI
--  Setelah kolom ini ada, unggah dan buka halaman akun_pro.php pada website
--  untuk menandai akun mana yang PRO. Halaman itu juga akan berhenti
--  menampilkan peringatan "kolom database belum ada".
-- ============================================================================
