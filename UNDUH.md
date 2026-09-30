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

**Panduan lengkap** (4.700+ baris, semua bagian 1-43):

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
| 3 | `PASANG_FITUR_BARU.ps1` | Jalankan kedua: ikon Android, izin iklan, build, dan pasang ke HP |
| 4 | `RTS_PANEL_AKUN_PRO.zip` | Ekstrak ke `public_html` pada hosting (uji coba dulu) |
| 5 | `RTS_PANEL_FIREBASE.zip` | Ekstrak ke `public_html` (bila belum dipasang) |

---

## BILA DIMINTA LOGIN

Repo ini bersifat **pribadi** (private), sehingga GitHub meminta login lebih
dahulu. Gunakan akun GitHub Bapak (**benesibarani**) - setelah login, seluruh
tautan di atas langsung berjalan.
