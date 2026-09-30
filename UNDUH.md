# CARA MENGUNDUH BERKAS RTS PANEL

Berkas-berkas RTS Panel tersimpan pada GitHub. Semua unduhan dilakukan dari
halaman berikut (buka di komputer yang dipakai bekerja):

    https://github.com/benesibarani/Ben-S/tree/arena/01a0beb2-ben-s

---

## CARA 1 - UNDUH SATU BERKAS (paling sering dipakai)

1. Buka alamat di atas.
2. Cari nama berkas yang diinginkan pada daftar.
3. Klik nama berkasnya.
4. Pada halaman berkas, klik ikon **unduh** di kanan atas
   (tulisannya "Download raw file"), atau klik kanan lalu pilih
   **Save link as**.

Bila berkas berupa gambar/zip, tombol unduhnya berupa ikon panah ke bawah
di bagian kanan atas halaman.

---

## CARA 2 - TAUTAN LANGSUNG (tanpa mencari)

Tempel alamat berikut pada peramban (Chrome), lalu tekan Enter:

**Paket aplikasi Android** (main.dart, pubspec.yaml, dan kedua skrip):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/RTS_PANEL_FITUR_BARU.zip

**Paket Akun PRO untuk server** (akun_pro.php, api/, dan SQL):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/RTS_PANEL_AKUN_PRO.zip

**Paket Firebase untuk server** (api fcm, device_token, inbox, pengajuan_toko):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/RTS_PANEL_FIREBASE.zip

**Paket Versi & Unggah APK untuk server** (menu sidebar + halaman unggah + API versi + SQL tabel versi):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/RTS_PANEL_VERSI_APK.zip

**Paket Menu Saja** (bila hanya ingin menambahkan menu "Versi Aplikasi" pada dashboard):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/RTS_PANEL_MENU_VERSI.zip

**Panduan lengkap** (5.000+ baris, semua bagian 1-45):

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/PANDUAN_VERSI_TERBARU.md

**Catatan kode iklan AdMob:**

    https://github.com/benesibarani/Ben-S/raw/refs/heads/arena/01a0beb2-ben-s/KODE_ADMOB.txt

**Berkas terpisah (untuk menyalin isinya):**

| Berkas | Alamat |
| --- | --- |
| main.dart | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/main.dart |
| pubspec.yaml | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/pubspec.yaml.updated |
| PERBAIKI_PUBSPEC.ps1 | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/PERBAIKI_PUBSPEC.ps1 |
| PASANG_FITUR_BARU.ps1 | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/PASANG_FITUR_BARU.ps1 |
| PASANG_NIRKABEL.ps1 | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/PASANG_NIRKABEL.ps1 |
| PERBAIKI_ROOT_GRADLE.ps1 | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/PERBAIKI_ROOT_GRADLE.ps1 |
| CARA_PASANG_AKUN_PRO.txt | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/CARA_PASANG_AKUN_PRO.txt |
| CARA_PASANG_VERSI_APK.txt | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/CARA_PASANG_VERSI_APK.txt |
| RTS_PANEL_APP_VERSI.sql | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/database/migrations/RTS_PANEL_APP_VERSI.sql |
| app_versi.php (halaman unggah) | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/app_versi.php |
| sidebar.php (menu dashboard) | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/sidebar.php |
| dashboard_updated.php (kartu pintasan) | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/dashboard_updated.php |
| api/app_versi.php (API versi) | https://github.com/benesibarani/Ben-S/blob/arena/01a0beb2-ben-s/api/app_versi.php |

---

## CARA 3 - SEMUA BERKAS SEKALIGUS

Bila ingin mengunduh seluruh isi cabang kerja sekaligus:

    https://github.com/benesibarani/Ben-S/archive/refs/heads/arena/01a0beb2-ben-s.zip

Berkas terunduh berupa satu zip berisi seluruh berkas. Ukurannya lebih besar
karena memuat banyak paket lama juga.

Catatan: ZIP tidak dapat dibuka di dalam GitHub. Berkasnya harus diunduh lebih
dahulu, baru diekstrak di komputer.

---

## URUTAN PEMAKAIAN SETELAH SEMUA TERUNDUH

| Nomor | Berkas | Tujuan |
| --- | --- | --- |
| 1 | `RTS_PANEL_FITUR_BARU.zip` | Ekstrak ke `D:\Project\rts_panel_app` (pilih Timpa) |
| 2 | `PERBAIKI_PUBSPEC.ps1` | Jalankan pertama: mendaftarkan paket iklan + `flutter pub get` |
| 3 | `PASANG_FITUR_BARU.ps1` | Jalankan kedua: ikon Android, **izin lokasi + izin iklan**, build, dan pasang ke HP |
| 4 | `RTS_PANEL_AKUN_PRO.zip` | Ekstrak ke `public_html` pada hosting (uji coba dulu) |
| 5 | `RTS_PANEL_VERSI_APK.zip` | Ekstrak ke `public_html` (menu "Versi Aplikasi" + halaman unggah APK); jalankan dulu `RTS_PANEL_APP_VERSI.sql` |
| 6 | `RTS_PANEL_FIREBASE.zip` | Ekstrak ke `public_html` (bila belum dipasang) |

Catatan penting untuk paket nomor 3: skrip `PASANG_FITUR_BARU.ps1` sekarang
menambahkan **izin lokasi** (`ACCESS_FINE_LOCATION` dan `ACCESS_COARSE_LOCATION`)
ke `AndroidManifest.xml`. Inilah yang membuat laporan cuaca beranda dapat
tampil. Setelah aplikasi terpasang, izinkan lokasi saat HP bertanya.

---

## SOAL LOGIN

**Keadaan 30 September 2026 (sore): repo ini PUBLIC kembali** - dipilih Bapak
agar tautan unduhan langsung berjalan tanpa perlu login. Jadi seluruh tautan di
atas sekarang dapat dibuka siapa pun yang memiliki alamatnya.

Beberapa hal yang perlu diketahui karena repo publik:

| Nomor | Hal | Keadaan sekarang |
| --- | --- | --- |
| 1 | `dashboard.php` versi lama yang memuat password database langsung | **Sudah dihapus dari repositori** (30 Sep 2026) - salinan di hosting tidak diubah |
| 2 | Berkas dump database produksi | Sudah dihapus dari cabang `main`, tetapi masih ada pada **riwayat** `main` (dapat dibuka lewat alamat commit lama) |
| 3 | Langkah keamanan nomor 3 - ganti password database cPanel | **BELUM dikerjakan** |

Saran: setelah semua berkas selesai diunduh dan pekerjaan selesai, kembalikan
repo menjadi **Private** lagi (Settings - General - Danger Zone - Change
visibility - Make private), dan **ganti password database** pada cPanel.
Selama repo publik, siapa pun yang tahu alamatnya dapat membaca seluruh berkas
di dalamnya.

Bila muncul halaman **404 / Page not found**, biasanya karena nama berkas salah
ketik. Periksa kembali alamatnya.
