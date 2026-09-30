# KOTAK KEAMANAN DATA PRODUKSI - HASIL PENANGANAN

Diperbarui: 30 September 2026, 10:12 WIB

---

## RINGKASAN

| Nomor | Tindakan | Keadaan | Dikerjakan oleh |
| --- | --- | --- | --- |
| 1 | Repositori diubah menjadi **Private** | **SELESAI** | Bapak (terverifikasi 30 Sep 2026) |
| 2 | Berkas dump database dihapus dari cabang `main` | **SELESAI** | Saya (commit `82fcffd`) |
| 3 | Kata sandi database diganti | **BELUM** - perlu Bapak kerjakan di cPanel | - |

---

## 1. REPOSITORI SUDAH PRIVATE - SELESAI

Pemeriksaan langsung ke GitHub menunjukkan:

```
name       : Ben-S
private    : True
visibility : private
```

Artinya repo `benesibarani/Ben-S` **tidak lagi dapat dibuka tanpa login**.
Ini tindakan yang paling menentukan, karena menutup seluruh isi repo sekaligus
(termasuk riwayat).

---

## 2. BERKAS DUMP SUDAH DIHAPUS DARI MAIN - SELESAI

Berkas `benedics_benes_sales.sql` (1,4 MB, 8.737 baris) sudah **dihapus** dari
cabang `main` pada commit:

    82fcffd  Hapus dump database produksi dari repositori (keamanan data customer)

Pemeriksaan ulang: berkas itu **sudah tidak ada** pada daftar berkas cabang
`main` (tersisa 25 berkas, seluruhnya berkas website dan gambar).

**Catatan penting yang perlu Bapak ketahui:** berkas itu **masih tersimpan pada
riwayat** `main` (commit `28e7277`). Karena repo sudah Private, riwayat itu hanya
dapat dibuka oleh pemilik repo dan kolaborator - bukan lagi oleh umum.

Cabang kerja sesi ini (`arena/01a0beb2-ben-s`) **bersih**: berkas dump tidak
pernah masuk ke pohon berkas maupun riwayatnya.

Bila Bapak ingin riwayatnya benar-benar bersih juga, ada dua pilihan:

| Pilihan | Keterangan |
| --- | --- |
| Biarkan (disarankan) | Repo sudah Private, risikonya sudah sangat kecil. Riwayat tidak diubah sehingga tidak ada risiko berkas lain rusak |
| Hapus repo lalu buat ulang | Cara paling pasti. Saya dapat membantu mengunggah ulang seluruh berkas yang masih diperlukan ke repo baru |

Menulis ulang riwayat (force push) **tidak saya lakukan**, karena berisiko
merusak berkas lain tanpa manfaat besar bila repo sudah Private.

---

## 3. KATA SANDI DATABASE - PERLU BAPAK KERJAKAN

Ini satu-satunya langkah yang belum selesai, dan **hanya dapat dikerjakan dari
cPanel** (saya tidak memiliki akses ke hosting Bapak).

Kenapa langkah ini penting meski repo sudah Private: data Bapak sempat terbuka
selama ±5 hari (25-30 September). Halaman yang pernah tersalin pihak ketiga
(misalnya layanan cache atau mesin pencari) tidak dapat ditarik kembali - tetapi
kata sandi yang diganti membuat salinan lama itu **tidak lagi berguna untuk
masuk** ke database.

### Langkah-langkah (sekitar 3 menit)

| Nomor | Langkah |
| --- | --- |
| 1 | Masuk cPanel - buka menu **MySQL Databases** |
| 2 | Gulir ke bagian **Current Users** - cari pengguna database yang dipakai website (biasanya `benedics_...`) |
| 3 | Klik **Change Password** pada pengguna itu |
| 4 | Ketik kata sandi baru (buat yang kuat: minimal 12 huruf, campur huruf besar-kecil, angka, dan lambang). **Catat di tempat aman, jangan dikirim ke siapa pun termasuk ke saya** |
| 5 | Klik **Change Password** untuk menyimpan |
| 6 | Buka **File Manager** - masuk ke `public_html` - buka berkas `config.php` |
| 7 | Ganti nilai kata sandi database pada `config.php` dengan yang baru, lalu **Save** |
| 8 | Buka website `https://rts.benedic-s.com/` - pastikan login dan data tetap tampil |
| 9 | Buka aplikasi RTS Panel di HP - pastikan login dan data tetap berjalan |

Bila pada langkah 8 atau 9 muncul pesan kesalahan koneksi database, artinya
kata sandi pada `config.php` belum sama dengan yang baru - periksa kembali
langkah 4 dan 7.

### Tentang kata sandi pengguna aplikasi

Kata sandi akun petugas pada tabel `sales_users` **sudah berbentuk hash**
(bcrypt), sehingga tidak terbaca langsung dari dump itu. Meski demikian, karena
dump tersebut memuat alamat email/nama pengguna, ada baiknya Bapak menyarankan
petugas berganti kata sandi secara berkala. Caranya sudah tersedia di aplikasi:
menu **Profil - Ganti Password**.

---

## SATU HAL LAGI YANG SAYA TEMUKAN

Pada cabang `main` terdapat berkas **`dashboard.php` versi lama** (10,6 KB).
Pemeriksaan menunjukkan berkas itu **memuat kredensial database langsung** di
dalam kodenya (versi baru sudah memakai `config.php`, sehingga lebih aman).

Berkas ini **tidak** termasuk dalam tiga langkah di atas, jadi belum saya hapus.
Karena repo sudah Private, keberadaannya sekarang tidak lagi berbahaya untuk
umum. Bila Bapak ingin saya hapuskan juga, cukup beri tahu - satu perintah saja.

---

## PEMERIKSAAN AKHIR

| Nomor | Periksa | Hasil yang diharapkan |
| --- | --- | --- |
| 1 | Buka `https://github.com/benesibarani/Ben-S` pada peramban **mode penyamaran** (Ctrl+Shift+N) | Muncul halaman **404 / Page not found** (tanda repo sudah Private) |
| 2 | Buka alamat yang sama setelah login GitHub | Repo terbuka dengan tanda **Private** di sebelah nama |
| 3 | Buka daftar berkas cabang `main` | `benedics_benes_sales.sql` tidak ada lagi pada daftar |
| 4 | Buka website dan aplikasi | Tetap berjalan normal |
| 5 | Menu **Pengaturan - Versi Aplikasi** pada website | Halaman unggah APK tetap berjalan |
