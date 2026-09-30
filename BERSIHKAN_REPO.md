# PENTING - DATA PRODUKSI MASIH DAPAT DIUNDUH PUBLIK

Tanggal pemeriksaan: 30 September 2026

---

## APA YANG TERJADI

Repositori GitHub `benesibarani/Ben-S` berstatus **PUBLIK** (dapat dibuka siapa
saja, tanpa login). Di dalamnya, pada cabang `main`, terdapat berkas:

    benedics_benes_sales.sql   (8.737 baris)

Berkas itu adalah **dump database produksi** yang memuat data asli, antara lain:

| Tabel | Isi |
| --- | --- |
| `sales_users` | Akun pengguna beserta kata sandi yang sudah di-hash |
| `master_toko` | Data customer (nama toko, alamat, dan data lain) |
| `master_toko_tf` | Data toko TF |
| `pengajuan_sales`, `pengajuan_gsp` | Seluruh pengajuan |
| `data_trade_promo`, `program_sales` | Data program penjualan |
| `stok_gsp`, `target_insentif`, `riwayat_aksi` | Data stok, target, dan riwayat |

Berkas ini sudah dapat diunduh siapa saja sejak **25 September 2026** (tanggal
unggahan pada GitHub).

Berdasarkan UU Perlindungan Data Pribadi, data customer (nama, alamat, kontak)
tidak seharusnya terbuka untuk umum. Karena itu bagian ini perlu dikerjakan.

---

## KABAR BAIKNYA

Pemeriksaan sudah dilakukan, dan **tidak ada kredensial database** pada paket
zip mana pun di repo (tidak ada `config.php`, dan `auth.php` memakai
`config.php`, bukan kata sandi langsung). Jadi yang perlu ditangani hanya satu
berkas dump itu.

---

## TIGA TINDAKAN (urut dari yang paling penting)

### 1. HAPUS BERKAS DUMP DARI GITHUB (sekitar 1 menit)

1. Buka:

       https://github.com/benesibarani/Ben-S/blob/main/benedics_benes_sales.sql

2. Klik ikon **tempat sampah** (🗑) di kanan atas halaman berkas.
3. Pada halaman konfirmasi, gulir ke bawah, klik **Commit changes**.

Berkas itu hilang dari tampilan repo.

### 2. UBAH REPO MENJADI PRIBADI (PRIVATE) - INI KUNCI UTAMANYA

Langkah 1 di atas **belum cukup**, karena berkas itu masih tersimpan pada
riwayat (history) GitHub dan tetap dapat dibuka lewat tautan lama. Cara
menutupnya secara menyeluruh:

1. Buka:

       https://github.com/benesibarani/Ben-S/settings

2. Gulir paling bawah sampai kotak merah **Danger Zone**.
3. Klik **Change repository visibility** - **Change visibility** - pilih
   **Make private**.
4. Ketik nama repo `benesibarani/Ben-S` pada kotak konfirmasi, lalu klik
   **I understand, change repository visibility**.

Setelah ini, hanya akun Bapak yang dapat membuka repo dan mengunduh berkasnya.

**Pengaruh pada tautan unduhan:** tautan pada `UNDUH.md` tetap berjalan, tetapi
GitHub akan meminta login lebih dahulu. Gunakan akun **benesibarani**.

### 3. GANTI KATA SANDI DATABASE

Karena dump itu memuat akun basis data, sebaiknya kata sandi database diganti:

1. cPanel - **MySQL Databases** - bagian **Current Users** - pilih pengguna
   database - **Change Password**.
2. Buka `public_html/config.php` di cPanel File Manager.
3. Ganti nilai kata sandi pada baris `$pass` (atau nama serupa) dengan yang
   baru, lalu simpan.
4. Buka aplikasi dan website - pastikan login tetap berjalan.

Catatan: kata sandi pengguna aplikasi (kolom `password` pada `sales_users`)
sudah berbentuk hash bcrypt, jadi tidak terbaca langsung. Meski begitu, karena
dump itu terbuka cukup lama, menyarankan petugas berganti kata sandi adalah
langkah yang baik - caranya sudah tersedia di aplikasi (menu Profil - Ganti
Password).

---

## SETELAH SELESAI

| Nomor | Periksa | Hasil yang diharapkan |
| --- | --- | --- |
| 1 | Buka repo tanpa login (mode penyamaran/incognito) | Muncul halaman "404" atau "Page not found" |
| 2 | Buka `https://github.com/benesibarani/Ben-S` saat login | Repo terbuka bertanda **Private** |
| 3 | Buka website dan aplikasi | Tetap berjalan normal (kata sandi database baru) |
| 4 | Unduh `RTS_PANEL_FITUR_BARU.zip` dari repo | Berhasil setelah login |

---

## CATATAN

Saya (asisten) tidak dapat mengubah setelan repo maupun menghapus berkas pada
cabang `main` dari sini, karena:

- perubahan setelan repo ditolak oleh izin akses yang tersedia (HTTP 403);
- cabang `main` bukan cabang kerja sesi ini, sehingga tidak boleh saya ubah.

Karena itu ketiga langkah di atas perlu Bapak kerjakan sendiri (~3 menit total).
Bila Bapak ingin saya yang mengerjakan, cukup beri tahu - saya dapat membantu
setelah izin akses GitHub disesuaikan pada Arena.

Terakhir: berkas dump database **jangan diunggah lagi** ke GitHub. Bila perlu
menyimpan cadangan, gunakan Google Drive pribadi atau simpanan di cPanel
(bukan repositori yang dapat dibuka publik).
