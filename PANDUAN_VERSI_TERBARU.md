# RTS Panel — Panduan Versi Terbaru

## Ringkasan perubahan pada versi ini

1. **Perbaikan angka GSP yang salah.**
   Penyebabnya: kolom `master_toko.tipe_customer` belum ada di database staging.
   Akibatnya filter GSP diabaikan server sehingga jumlahnya sama dengan Reguler.
   Perbaikannya ada dua lapis:
   - migrasi menambah kolom `tipe_customer` pada database staging;
   - API dan aplikasi berhenti menampilkan angka palsu bila kolom belum ada.

2. **Tombol peta pada Detail Customer.**
   Tombol "SALIN LINK PETA" diganti menjadi **BUKA DI GOOGLE MAPS** yang
   langsung membuka aplikasi peta pada titik koordinat customer.
   Tetap tersedia tombol kecil "Salin koordinat" bila diperlukan.

---

## 1. Perbaiki kategori GSP di staging

Jalankan file migrasi ini pada database staging (`benedics_coba`):

```text
database/migrations/RTS_PANEL_STAGING_ADD_TIPE_CUSTOMER.sql
```

Langkah di cPanel:

1. Masuk cPanel → **phpMyAdmin**.
2. Pilih database staging, **bukan** database produksi.
3. Buka tab **SQL**.
4. Tempel seluruh isi file migrasi.
5. Klik **Go**.
6. Lihat hasil paling bawah:

```text
tipe_customer | jumlah
REGULER       | 3273
GSP           | 0
```

Arti hasil tersebut: kolom sudah ada, dan semua customer masih berstatus REGULER.
Angka GSP akan tetap **0** sampai ada customer yang benar-benar ditandai GSP
(melalui halaman Master Customer di website, atau lewat SQL pada database staging).

Untuk menandai satu toko menjadi GSP di staging, contohnya:

```sql
UPDATE master_toko SET tipe_customer = 'GSP' WHERE id_customer = '3000032344';
```

Setelah migrasi dijalankan, buka aplikasi dan tekan tombol muat ulang.
Filter akan berubah menjadi:

```text
Semua Tipe | Reguler (3273) | GSP (0) | Semua Status | Aktif | Nonaktif
```

Selama migrasi belum dijalankan, aplikasi akan:

- menyembunyikan filter tipe;
- menampilkan catatan kuning bahwa kategori GSP belum aktif di server;
- tetap menampilkan seluruh customer tanpa angka menyesatkan.

---

## 2. File API yang di-upload ke staging

Upload ke cPanel staging ke dalam folder `public_html/api/`:

| File | Fungsi |
| --- | --- |
| `api/login.php` | Login Android + pembuatan token |
| `api/api_bootstrap.php` | Helper: koneksi DB, validasi token, hak akses role |
| `api/customers.php` | Daftar customer + pencarian + filter + jumlah per kategori |
| `api/customer_detail.php` | Detail satu customer |
| `api/requests.php` | Daftar pengajuan (toko reguler dan GSP) |
| `api/request_action.php` | Setujui / tolak / hapus pengajuan |
| `api/request_apply.php` | Penerapan pengajuan ke Master Customer (dipakai request_action) |

Catatan:

- Jangan upload ke `rts.benedic-s.com` dahulu.
- `api_bootstrap.php` tidak dapat dibuka langsung dari browser.
- `config.php` tidak diubah dan tidak di-upload ulang.
- Tabel `api_tokens` wajib ada.

## 3. Hak akses pada API

Master Customer:

| Role | Cakupan customer | Approve / Reject |
| --- | --- | --- |
| ADMIN | Semua district | Boleh |
| ASS | Semua district | Boleh |
| WSS | Semua district | Tidak boleh |
| SMST | Semua district | Tidak boleh |
| RTS | Hanya customer dengan salesman yang ditugaskan | Tidak boleh |
| TF | Hanya customer dengan salesman yang ditugaskan | Tidak boleh |

Pengajuan:

| Role | Melihat pengajuan | Setujui / Tolak | Hapus |
| --- | --- | --- | --- |
| ADMIN | Semua | Boleh | Boleh |
| ASS | Semua | Boleh | Boleh |
| WSS | Semua | Tidak boleh | Boleh |
| SMST | Semua | Tidak boleh | Boleh |
| RTS | Hanya milik sendiri | Tidak boleh | Hanya milik sendiri yang Pending |
| TF | Hanya milik sendiri | Tidak boleh | Hanya milik sendiri yang Pending |

Saat pengajuan **disetujui**, API langsung menerapkannya ke `master_toko`
dengan aturan yang sama seperti website:

| Jenis pengajuan | Akibat pada Master Customer |
| --- | --- |
| Tambah Baru | Customer baru ditambahkan dengan status Aktif |
| Ganti Nama / Ganti Alamat | Data customer diperbarui |
| Hapus Toko | Customer diarsipkan ke `master_toko_deleted`, lalu dihapus |
| GSP PENAMBAHAN | Kategori customer menjadi GSP |
| GSP PENGHAPUSAN | Kategori customer kembali menjadi REGULER |

Bila penerapan gagal, status pengajuan **tidak** diubah, sehingga data tidak
pernah tertinggal dalam kondisi setengah diproses.

## 4. File Flutter

| File di workspace | Salin ke |
| --- | --- |
| `main.dart` | `D:\Project\rts_panel_app\lib\main.dart` |
| `widget_test.dart.updated` | `D:\Project\rts_panel_app\test\widget_test.dart` |
| `pubspec.yaml.updated` | `D:\Project\rts_panel_app\pubspec.yaml` |

Isi `pubspec.yaml` terbaru menambahkan `url_launcher` yang dipakai tombol
**BUKA DI GOOGLE MAPS**.

Bila saat `flutter pub get` muncul peringatan versi SDK, cukup ubah baris
`environment:` mengikuti angka versi yang disarankan Flutter.

## 5. Wajib: aktifkan Developer Mode Windows

Karena aplikasi sekarang memakai plugin (`url_launcher`), Flutter di Windows
membutuhkan dukungan symlink. Bila belum aktif, `flutter run` akan berhenti
dengan pesan:

```text
Building with plugins requires symlink support.
Please enable Developer Mode in your system settings.
```

Pada Windows 11 versi baru (24H2 / 25H2), menu **For developers** tidak lagi
tampil di halaman utama System. Ada tiga cara membukanya.

**Cara 1 - paling cepat (disarankan)**

1. Tekan Windows + R.
2. Tulis: `ms-settings:developers`
3. Tekan Enter. Jendela pengaturan Developer akan langsung terbuka.
4. Aktifkan **Developer Mode**.

**Cara 2 - lewat kotak pencarian Settings**

1. Tekan Windows + I.
2. Di kotak **Find a setting**, tulis: `developer`
3. Pilih hasil yang muncul (**Developer settings**).
4. Aktifkan **Developer Mode**.

**Cara 3 - lewat menu baru Windows 11 terbaru**

1. Tekan Windows + I, pilih **System**.
2. Pilih **Advanced** (tulisan kecilnya: performance, optimization, and
   developer features).
3. Cari bagian **Developer features** / **Developer Mode**.
4. Aktifkan **Developer Mode**.

Setelah aktif, tutup PowerShell, buka lagi, lalu jalankan `flutter run`.
Bila Developer Mode tidak dapat diaktifkan karena kebijakan komputer,
alternatifnya: jalankan PowerShell sebagai **Administrator**, lalu jalankan
`flutter run` dari situ.

## 6. Perintah menjalankan di komputer

```powershell
cd D:\Project\rts_panel_app
flutter clean
flutter pub get
flutter run
```

## 7. Bila Google Maps tidak terbuka langsung

Tambahkan blok berikut di dalam tag `<manifest>` pada
`D:\Project\rts_panel_app\android\app\src\main\AndroidManifest.xml`:

```xml
<queries>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="https" />
    </intent>
    <intent>
        <action android:name="android.intent.action.VIEW" />
        <data android:scheme="geo" />
    </intent>
</queries>
```

## 8. Urutan pekerjaan berikutnya

Sudah selesai:

1. Login Android dengan token.
2. Master Customer: daftar, pencarian, filter, detail, dan peta.
3. Pengajuan: daftar, filter, detail, setujui, tolak, dan hapus.

Berikutnya:

1. **Form pengajuan dari Android**: Tambah Baru, Ganti Nama, Ganti Alamat, dan
   Hapus Toko, langsung dari halaman Master Customer.
2. **Notifikasi**: daftar pemberitahuan dan penanda pengajuan baru.
3. **Sinkronisasi**: menarik data terbaru dan menampilkan waktu sinkronisasi terakhir.
4. **Profil**: ganti password sendiri dari aplikasi.
5. **Simpan token di penyimpanan aman Android** agar tidak perlu login ulang.
6. Setelah staging stabil, baru siapkan API dan APK untuk production.

## 9. Mengatasi error Kotlin "different roots"

Gejala:

```text
Execution failed for task ':url_launcher_android:compileDebugKotlin'.
java.lang.Exception: Could not close incremental caches ...
Suppressed: java.lang.IllegalArgumentException:
  this and base files have different roots:
  C:\Users\Bene-S\AppData\Local\Pub\Cache\...\Messages.kt and
  D:\Project\rts_panel_app\android.
```

Penyebab: paket Flutter berada di drive C, sedangkan project ada di drive D.
Kotlin tidak dapat membuat path relatif antara dua drive yang berbeda.

### Perbaikan cepat

**Langkah 1.** Salin seluruh isi file `gradle.properties.updated` ke:

```text
D:\Project\rts_panel_app\android\gradle.properties
```

Isinya menambahkan dua baris:

```properties
kotlin.incremental=false
kotlin.incremental.useClasspathSnapshot=false
```

**Langkah 2.** Bersihkan hasil build lama. Di PowerShell:

```powershell
cd D:\Project\rts_panel_app
flutter clean
Remove-Item -Recurse -Force build -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\.gradle -ErrorAction SilentlyContinue
cd android
.\gradlew.bat --stop
cd ..
flutter pub get
flutter run
```

Penjelasan singkat:

- `flutter clean` membuang hasil build Flutter;
- `Remove-Item build` membuang cache Kotlin yang rusak;
- `Remove-Item android\.gradle` membuang cache Gradle;
- `gradlew --stop` mematikan daemon Kotlin/Gradle yang masih menyimpan cache lama.

### Perbaikan menyeluruh (opsional, lebih cepat untuk ke depan)

Pindahkan lokasi paket Flutter ke drive D agar satu drive dengan project:

```powershell
setx PUB_CACHE "D:\pub-cache"
```

Tutup PowerShell, buka lagi, lalu:

```powershell
cd D:\Project\rts_panel_app
flutter clean
flutter pub get
flutter run
```

Catatan: cara ini akan mengunduh ulang paket ke `D:\pub-cache`.
Setelah itu baris `kotlin.incremental=false` boleh dihapus karena akar masalahnya
sudah hilang.

## 10. Beralih dari staging ke produksi (rts.benedic-s.com)

### Keadaan sekarang

Aplikasi Android masih menunjuk ke **staging**:

```dart
const String rtsApiBaseUrl = 'https://coba.benedic-s.com/api';
const String rtsServerLabel = 'Server Staging';
```

Artinya login, Master Customer, dan Pengajuan semuanya membaca database
staging. Produksi sama sekali belum tersentuh, sehingga aman untuk dicoba-coba.

### Bolehkah langsung memakai produksi?

Boleh, tetapi **jangan** dilakukan sebelum lima hal berikut selesai.
Alasannya: modul Pengajuan menulis ke `master_toko` dan `master_toko_deleted`
di database produksi. Salah klik di produksi berarti data customer asli
berubah.

| No | Wajib dilakukan | Alasan |
| --- | --- | --- |
| 1 | Backup database produksi (Export dari phpMyAdmin) | Bisa dipulihkan bila ada kesalahan |
| 2 | Backup file website produksi (zip `public_html`) | Bisa dipulihkan bila ada masalah file |
| 3 | Jalankan `RTS_PANEL_PRODUCTION_CHECK.sql` | Mengetahui kolom/tabel yang masih kurang |
| 4 | Jalankan `RTS_PANEL_PRODUCTION_READY.sql` | Menambah `api_tokens`, `tipe_customer`, kolom audit |
| 5 | Uji login + Master Customer + Pengajuan di staging sampai lancar | Memastikan alur approve tidak bermasalah |

### Langkah 1 - Periksa kesiapan database produksi (hanya membaca)

File:

```text
database/migrations/RTS_PANEL_PRODUCTION_CHECK.sql
```

cPanel → phpMyAdmin → pilih database produksi → tab SQL → tempel → Go.

Hasilnya daftar "ADA / BELUM ADA". File ini **tidak mengubah apa pun**.
Kirimkan hasilnya sebelum melanjutkan, agar langkah migrasi tepat sasaran.

### Langkah 2 - Backup

- Database: phpMyAdmin → pilih database produksi → **Export** → Go.
- File: cPanel → **File Manager** → pilih `public_html` → **Compress** → zip.

Jangan lanjut sebelum keduanya tersimpan di komputer.

### Langkah 3 - Jalankan migrasi produksi

File:

```text
database/migrations/RTS_PANEL_PRODUCTION_READY.sql
```

Sifatnya aman dan boleh diulang. Yang ditambahkan:

- tabel `api_tokens`;
- kolom `master_toko.tipe_customer` dan indexnya;
- tabel `master_toko_deleted` bila belum ada;
- kolom `processed_by`, `processed_at`, `approval_note` pada kedua tabel pengajuan;
- kolom `pengajuan_gsp.jenis_request`.

Tidak ada perintah `DELETE`, `DROP`, atau `TRUNCATE` di dalamnya.

### Langkah 4 - Upload folder API ke produksi

Upload ke `public_html/api/` pada domain `rts.benedic-s.com`:

```text
api/login.php
api/api_bootstrap.php
api/customers.php
api/customer_detail.php
api/requests.php
api/request_action.php
api/request_apply.php
```

Semua memakai `config.php` produksi yang sudah ada, jadi kredensial database
tidak perlu diubah dan tidak pernah masuk ke aplikasi Android.

Uji cepat dari browser:

```text
https://rts.benedic-s.com/api/login.php
```

Bila muncul:

```json
{"success":false,"message":"Method tidak diizinkan"}
```

berarti folder dan file sudah benar (memang hanya menerima POST).

### Langkah 5 - Ubah alamat API di aplikasi

Di `main.dart` bagian atas, ubah dua baris ini:

```dart
const String rtsApiBaseUrl = 'https://rts.benedic-s.com/api';
const String rtsServerLabel = 'Server Produksi';
```

Lalu:

```powershell
cd D:\Project\rts_panel_app
flutter run
```

### Hal yang berubah setelah pindah ke produksi

| Bagian | Akibat |
| --- | --- |
| Login | Token staging tidak berlaku. Semua pengguna harus login ulang. |
| Master Customer | Data yang tampil adalah data asli, bukan data uji. |
| Pengajuan | Approve dari HP langsung mengubah data produksi. |
| Email notifikasi | Tetap dikirim oleh website, bukan oleh API Android. |

### Bila ingin aman berdua

Bisa dibuat dua cara:

1. **Satu aplikasi, pilih server lewat halaman Pengaturan.** Lebih fleksibel,
   tetapi menambah kompleksitas dan berisiko salah pilih.
2. **Dua APK terpisah**: RTS Panel (staging) untuk uji, RTS Panel (produksi)
   untuk pemakaian harian. Cara ini paling aman dan disarankan.

### Catatan keamanan penting

Repositori GitHub `benesibarani/Ben-S` pernah memuat file dump SQL database
produksi yang dapat diakses publik. Sebelum aplikasi dipakai untuk data asli,
sebaiknya:

1. Jadikan repositori bersifat **private**, atau
2. Hapus file dump SQL tersebut dari repositori beserta riwayatnya, dan
3. Ganti password database produksi di cPanel, lalu sesuaikan `config.php`,
   lalu buat backup baru.

Kredensial database tidak pernah tertanam di aplikasi Android. Aplikasi hanya
menghubungi HTTPS `…/api/…`, sehingga password database tetap berada di server.

## 11. Pemeriksaan lingkungan: domain mana memakai database mana

### Pelajaran dari pemeriksaan pertama

Error:

```text
#1109 - Unknown table 'master_toko' in information_schema
```

Penyebabnya: file pemeriksaan versi pertama mencampur pembacaan
`information_schema` dengan pembacaan tabel biasa dalam satu batch. Bila
konteks database pada koneksi phpMyAdmin bukan database yang dimaksud, tabel
biasa gagal dibaca. Pembacaan `information_schema` sendiri tidak bermasalah.

Perbaikannya: `RTS_PANEL_STRUCTURE_REPORT.sql` hanya menyentuh
`information_schema`, sehingga aman dijalankan dari database mana pun.

### Temuan penting dari tangkapan layar

Pada phpMyAdmin terlihat database `benedics_bene_sales` sudah memiliki:

```text
api_tokens            -> ADA
master_toko_deleted   -> ADA
master_toko           -> ADA
pengajuan_sales       -> ADA
pengajuan_gsp         -> ADA
sales_users           -> ADA
riwayat_aksi          -> ADA
```

Artinya, sebagian besar kebutuhan aplikasi Android sudah tersedia di sana.
Yang belum terlihat (masih perlu diperiksa) adalah kolom-kolom berikut:

- `sales_users.username`
- `sales_users.status_aktif`
- `sales_users.salesman`
- `sales_users.sales_district`
- `master_toko.tipe_customer`
- `pengajuan_sales.processed_by`, `processed_at`, `approval_note`
- `pengajuan_gsp.jenis_request`, `processed_by`, `processed_at`, `approval_note`

### Langkah 1 - Jalankan laporan struktur (hanya membaca)

File:

```text
database/migrations/RTS_PANEL_STRUCTURE_REPORT.sql
```

phpMyAdmin → klik salah satu database → tab SQL → tempel seluruh isi → Kirim.

Hasilnya menampilkan semua database yang namanya berawalan `benedics`, sehingga
langsung terlihat perbedaan database staging dan produksi. Hasil ini juga sudah
menjawab kebutuhan pemeriksaan kolom.

### Langkah 2 - Tahu pasti domain mana memakai database mana

Upload file berikut ke **kedua** domain:

```text
api/env_check.php
```

Menjadi:

```text
https://coba.benedic-s.com/api/env_check.php
https://rts.benedic-s.com/api/env_check.php
```

Buka keduanya di browser. Hasilnya berupa JSON berisi:

```json
{
  "domain": "coba.benedic-s.com",
  "database": "benedics_coba",
  "tabel": { "api_tokens": true, "master_toko": true, "...": true },
  "kolom": { "sales_users.username": true, "master_toko.tipe_customer": false },
  "jumlah": { "customer": 3273, "pengguna": 12 }
}
```

Dengan ini jelas terlihat:

- staging memakai database yang mana;
- produksi memakai database yang mana;
- tabel dan kolom apa saja yang sudah ada di masing-masing.

**Penting:** hapus `env_check.php` dari kedua domain setelah selesai. File itu
hanya untuk pemeriksaan dan tidak boleh dibiarkan di server.

### Langkah 3 - Putuskan tujuan pemakaian

Setelah hasil keduanya diketahui, pilih salah satu:

1. **Uji dulu di staging** (disarankan). Tambahkan kekurangan kolom/tabel di
   database staging, selesaikan pengujian alur approve, baru pindah ke produksi.
2. **Langsung ke produksi** dengan syarat wajib: backup database dan file
   produksi lebih dahulu, lalu jalankan `RTS_PANEL_PRODUCTION_READY.sql`.

## 12. Hasil pemeriksaan struktur dan keputusan berikutnya

### Ringkasan hasil

Laporan `RTS_PANEL_STRUCTURE_REPORT.sql` menunjukkan **kedua database sudah
lengkap**. Semua tabel dan kolom yang dibutuhkan aplikasi Android sudah ada di
`benedics_bene_sales` maupun `benedics_coba`.

Tabel:

| Tabel | benedics_bene_sales | benedics_coba |
| --- | --- | --- |
| api_tokens | ADA | ADA |
| master_toko | ADA | ADA |
| master_toko_deleted | ADA | ADA |
| sales_users | ADA | ADA |
| pengajuan_sales | ADA | ADA |
| pengajuan_gsp | ADA | ADA |
| riwayat_aksi | ADA | ADA |

Kolom:

| Kolom | benedics_bene_sales | benedics_coba |
| --- | --- | --- |
| sales_users.username | varchar(50) | varchar(50) |
| sales_users.status_aktif | enum(Aktif,Nonaktif) | enum(Aktif,Nonaktif) |
| sales_users.salesman | varchar(150) | varchar(150) |
| sales_users.sales_district | varchar(100) | varchar(100) |
| master_toko.tipe_customer | enum(REGULER,GSP) | enum(REGULER,GSP) |
| pengajuan_sales.processed_by | varchar(150) | varchar(150) |
| pengajuan_sales.processed_at | timestamp | timestamp |
| pengajuan_sales.approval_note | text | text |
| pengajuan_gsp.jenis_request | enum(PENAMBAHAN,PENGHAPUSAN) | enum(PENAMBAHAN,PENGHAPUSAN) |
| pengajuan_gsp.processed_by | varchar(150) | varchar(150) |
| pengajuan_gsp.processed_at | timestamp | timestamp |
| pengajuan_gsp.approval_note | text | text |

### Kesimpulan penting

1. **Migrasi produksi TIDAK diperlukan.** File
   `RTS_PANEL_PRODUCTION_READY.sql` tidak perlu dijalankan karena semua yang
   dibutuhkannya sudah ada. Simpan saja sebagai cadangan.
2. **Kolom `tipe_customer` sekarang sudah ada di kedua database.** Karena itu
   filter GSP di aplikasi akan menampilkan angka sebenarnya setelah aplikasi
   dijalankan ulang.
3. Jumlah token pada tabel `api_tokens` memberi petunjuk:

| Database | Baris api_tokens | Arti |
| --- | --- | --- |
| benedics_coba | 2 | Ada 2 login dari pengujian aplikasi, jadi ini yang dipakai staging |
| benedics_bene_sales | 0 | Belum pernah ada login aplikasi, kemungkinan besar ini produksi |

Untuk memastikan pasangan domain-database, jalankan `api/env_check.php` pada
kedua domain, atau periksa nama database di dalam `config.php` masing-masing.

### Isi tiap database

| Keterangan | benedics_bene_sales | benedics_coba |
| --- | --- | --- |
| Jumlah customer | 3337 (perkiraan) | 3543 (perkiraan) |
| Customer terarsip | 303 | 303 |
| Akun pengguna | 13 | 13 |
| Pengajuan toko | 14 | 14 |
| Pengajuan GSP | 0 | 0 |
| Riwayat aksi | 1503 | 1371 |

Catatan: angka pada `information_schema.TABLE_ROWS` untuk InnoDB adalah
perkiraan, jadi boleh berbeda sedikit dengan jumlah sebenarnya.

### Yang perlu diperhatikan sebelum memakai produksi

Modul Pengajuan **mengubah data**. Di produksi, menekan SETUJU akan langsung:

- menambah, mengubah, atau menghapus customer asli pada `master_toko`;
- memindahkan customer terhapus ke `master_toko_deleted`.

Karena itu urutannya:

1. Backup database produksi (phpMyAdmin → Export) dan file `public_html` (zip).
2. Upload 7 file API ke `public_html/api/` pada domain produksi.
3. Ubah 2 baris alamat API di `main.dart`.
4. `flutter run`, login sebagai ADMIN.
5. Uji **hanya meload data dulu** (Master Customer dan daftar Pengajuan).
6. Baru uji approve pada satu pengajuan yang memang layak diproses.

### Langkah teknis pindah ke produksi

**a. Upload folder API** ke `public_html/api/` domain `rts.benedic-s.com`:

```text
api/login.php
api/api_bootstrap.php
api/customers.php
api/customer_detail.php
api/requests.php
api/request_action.php
api/request_apply.php
```

**b. Ubah dua baris di `main.dart`:**

```dart
const String rtsApiBaseUrl = 'https://rts.benedic-s.com/api';
const String rtsServerLabel = 'Server Produksi';
```

**c. Jalankan:**

```powershell
cd D:\Project\rts_panel_app
flutter run
```

Token staging tidak berlaku di produksi, jadi login ulang diperlukan.

### Pilihan strategi pemakaian

| Pilihan | Keterangan | Catatan |
| --- | --- | --- |
| Satu aplikasi, alamat API tetap | Paling sederhana | Harus edit dan build ulang bila ingin pindah server |
| Satu aplikasi, server bisa dipilih di halaman Pengaturan | Fleksibel untuk uji dan kerja harian | Perlu tambahan halaman Pengaturan |
| Dua APK terpisah (staging dan produksi) | Paling aman | Perlu dua kali build, applicationId berbeda |

## 13. Kepastian domain dan database (hasil env_check)

### Hasil pemeriksaan

| Item | coba.benedic-s.com | rts.benedic-s.com |
| --- | --- | --- |
| Domain | staging | produksi |
| Database | `benedics_coba` | `benedics_bene_sales` |
| PHP | 8.2.33 | 8.2.33 |
| Seluruh tabel | ADA | ADA |
| Seluruh kolom | ADA | ADA |
| Jumlah customer | 3273 | 3356 |
| Customer GSP | 2 | 0 |
| Akun pengguna | 13 | 13 |
| Pengajuan toko Pending | 9 | 9 |
| Pengajuan toko total | 14 | 14 |
| Token aplikasi | 8 | 0 |

### Kesimpulan

1. **Pasangan domain dan database sudah pasti:**

```text
coba.benedic-s.com  ->  benedics_coba       (staging)
rts.benedic-s.com   ->  benedics_bene_sales (produksi)
```

2. **Kedua database sudah lengkap.** Tidak ada migrasi yang perlu dijalankan,
   baik di staging maupun di produksi.

3. **Staging memiliki 2 customer GSP.** Jadi filter tipe pada aplikasi akan
   menampilkan angka sebenarnya, misalnya:

```text
Semua Tipe | Reguler (3271) | GSP (2) | Semua Status | Aktif | Nonaktif
```

   Produksi menampilkan GSP 0 karena memang belum ada customer GSP di sana.

4. **Produksi belum pernah dipakai aplikasi Android.** Terlihat dari
   `token_aktif: 0`. Semua token yang ada (8 buah) berada di staging.

5. **Hapus `env_check.php`** dari kedua domain setelah pemeriksaan selesai.

### Fitur baru: Pengaturan Server di aplikasi

Agar tidak perlu mengubah kode dan build ulang setiap kali berpindah server,
aplikasi sekarang memiliki pemilih server.

Cara memakai:

1. Di halaman login, tekan tulisan server di bagian bawah, misalnya
   **"Staging • benedics_coba"**.
2. Pilih **Produksi** atau **Staging**, lalu tekan **GUNAKAN**.
3. Aplikasi meminta login ulang, karena token tiap server berbeda.

Penanda server agar tidak keliru:

| Tempat | Penanda |
| --- | --- |
| Halaman login | Tulisan server dan nama database di bawah tombol MASUK |
| Dashboard kanan atas | Label kecil **PRODUKSI** (hijau) atau **STAGING** (kuning) |
| Dashboard bawah | Kotak informasi server beserta keterangannya |
| Menu Pengaturan | Kartu server aktif: nama, alamat API, dan nama database |
| Dialog Setujui / Tolak | Peringatan merah, hanya muncul bila server produksi |

Pengaturan ini tersimpan di perangkat, jadi pilihan Anda tetap dipakai
walaupun aplikasi ditutup.

### File yang perlu disalin

| File di workspace | Salin ke |
| --- | --- |
| `main.dart` | `D:\Project\rts_panel_app\lib\main.dart` |
| `pubspec.yaml.updated` | `D:\Project\rts_panel_app\pubspec.yaml` |

Karena ada paket baru (`shared_preferences`), jalankan:

```powershell
cd D:\Project\rts_panel_app
flutter pub get
flutter run
```

### Urutan yang disarankan

1. Selesaikan pengujian di **staging** lebih dahulu: Master Customer dan
   Pengajuan, termasuk satu approve dan satu reject.
2. Bila sudah lancar, buka Pengaturan di aplikasi dan pindah ke **Produksi**.
3. Uji hanya membaca data dahulu di produksi (Master Customer dan daftar
   Pengajuan).
4. Selanjutnya approve di produksi hanya pada pengajuan yang memang layak
   diproses, karena langsung mengubah data asli.

## 14. Perbaikan: kolom tidak terbaca dan berkas API belum lengkap

### Gejala yang muncul

1. Master Customer menampilkan **3356 customer** (berarti aplikasi sudah memakai
   **produksi**, karena `benedics_bene_sales` berisi 3356 customer), tetapi
   memunculkan peringatan "Kategori GSP belum aktif di server".
2. Halaman Pengajuan menampilkan:
   `Server mengirim data yang tidak dikenali (kode 404)`.

### Penyebab 1 - pemeriksaan kolom selalu gagal

Pada `api_bootstrap.php` dan `login.php` dipakai perintah:

```php
$stmt = $conn->prepare('SHOW COLUMNS FROM `master_toko` LIKE ?');
```

MySQL **tidak menerima parameter (tanda tanya) pada perintah SHOW**, sehingga
prepare gagal. Akibatnya fungsi selalu menjawab "kolom tidak ada", walau
kolomnya benar-benar ada. Itulah mengapa filter GSP hilang dan peringatan
muncul, padahal `tipe_customer` sudah ada di kedua database.

Perbaikan: pemeriksaan kolom kini memakai `information_schema` yang memang
mendukung parameter:

```php
SELECT COUNT(*) AS total
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?
```

File yang diperbaiki:

```text
api/api_bootstrap.php
api/login.php
```

### Penyebab 2 - berkas API belum lengkap di server

Kode 404 berasal dari web server, bukan dari API. Artinya berkas
`requests.php` belum ada di folder `api` pada server yang sedang dipakai.

Berkas yang harus ada di `public_html/api/`:

```text
login.php
api_bootstrap.php
customers.php
customer_detail.php
requests.php            <- belum ada
request_action.php      <- belum ada
request_apply.php       <- belum ada
env_check.php           <- sementara, hapus setelah selesai
```

### Perbaikan pada aplikasi

1. Pesan kesalahan 404 sekarang lebih jelas, menyebut nama berkas dan alamat
   API yang dipakai, misalnya:

```text
Fitur "requests.php" belum tersedia di server Produksi.
Pastikan seluruh berkas di folder api sudah di-upload ke
https://rts.benedic-s.com/api.
```

2. Pesan peringatan GSP tidak lagi menyebut "database staging", tetapi mengikuti
   nama database server yang sedang aktif.

3. `env_check.php` sekarang menampilkan daftar berkas API yang ada dan yang
   belum ada:

```json
"berkas_api": {
  "login.php": true,
  "api_bootstrap.php": true,
  "customers.php": true,
  "customer_detail.php": true,
  "requests.php": false,
  "request_action.php": false,
  "request_apply.php": false
}
```

### Langkah yang perlu dilakukan

**a. Upload berkas API ke server yang sedang dipakai aplikasi.**

Buka `https://rts.benedic-s.com/api/env_check.php` dan lihat bagian
`berkas_api`. Upload berkas yang masih bernilai `false`:

```text
requests.php
request_action.php
request_apply.php
```

**b. Timpa dua berkas yang sudah diperbaiki** (jangan dilewatkan):

```text
api_bootstrap.php
login.php
```

**c. Salin `main.dart` terbaru** ke `D:\Project\rts_panel_app\lib\main.dart`,
lalu:

```powershell
cd D:\Project\rts_panel_app
flutter run
```

**d. Hapus `env_check.php`** setelah semuanya berjalan normal.

### Hasil yang diharapkan setelah perbaikan

Pada Master Customer (produksi):

```text
Semua Tipe | Reguler (3356) | GSP (0) | Semua Status | Aktif | Nonaktif
```

Pada staging akan muncul angka GSP 2, karena staging memang memiliki
2 customer GSP.

Pada halaman Pengajuan:

```text
Status: Semua | Pending (9) | Disetujui (5) | Ditolak (0)
Jenis : Semua Jenis | Toko Reguler | GSP
```

## 15. Perbaikan: Invalid constant value dan cara membaca kolom di phpMyAdmin

### A. Error "Invalid constant value" pada main.dart

Gejala:

```text
Invalid constant value. (dart)
Invalid constant value. [Ln 1882, Col 18]
```

Penyebab: pada widget peringatan GSP, teksnya memakai nilai yang bukan
konstanta (`${RtsConfig.server.database}`), tetapi widget pembungkusnya masih
`const`.

Kode yang salah:

```dart
          const Expanded(
            child: Text(
              'Kategori GSP belum terbaca dari server. ... '
              '${RtsConfig.server.database}, lalu tekan muat ulang.',
              style: TextStyle(
```

Perbaikan: hapus `const` pada `Expanded` dan `Text`, lalu `const` dipindah ke
`TextStyle`:

```dart
          Expanded(
            child: Text(
              'Kategori GSP belum terbaca dari server. ... '
              '${RtsConfig.server.database}, lalu tekan muat ulang.',
              style: const TextStyle(
```

Aturannya sederhana: **jangan pakai `const` pada widget yang teksnya memuat
`${...}` yang bukan konstanta.**

### B. Cara membaca struktur kolom di phpMyAdmin tanpa error

Tanda tanya (`?`) adalah milik **PHP (prepared statement)**, bukan SQL.
phpMyAdmin akan menolaknya dengan:

```text
#1064 - You have an error in your SQL syntax ... near '?'
```

Tiga cara yang benar:

**Cara 1 - tanpa SQL sama sekali (paling mudah)**

1. Klik tabel **master_toko** pada daftar database.
2. Buka tab **Struktur**.
3. Cari baris **tipe_customer** pada daftar kolom.

**Cara 2 - perintah SHOW tanpa tanda tanya**

```sql
SHOW COLUMNS FROM benedics_bene_sales.master_toko LIKE 'tipe_customer';
```

Bila kolomnya ada, hasilnya berisi satu baris: `tipe_customer | enum('REGULER','GSP')`.

**Cara 3 - tampilkan semua kolom tabel agar terlihat sekaligus**

```sql
SELECT COLUMN_NAME, COLUMN_TYPE
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'benedics_bene_sales'
  AND TABLE_NAME = 'master_toko'
ORDER BY ORDINAL_POSITION;
```

Catatan: pemeriksaan otomatis lewat `env_check.php` sudah menjawab kebutuhan
ini, dan hasilnya `"master_toko.tipe_customer": true` untuk
`benedics_bene_sales`. Jadi kolomnya memang ada.

### C. Mengapa peringatan GSP masih muncul di aplikasi

Peringatan itu muncul karena **berkas API di server masih versi lama**.

Versi lama memakai:

```php
$stmt = $conn->prepare('SHOW COLUMNS FROM `master_toko` LIKE ?');
```

MySQL menolak parameter pada perintah `SHOW`, sehingga fungsi selalu menjawab
"kolom tidak ada", walau kolomnya benar-benar ada. Versi baru sudah memakai
`information_schema`.

Selama `api_bootstrap.php` di server belum ditimpa versi baru, aplikasi akan
terus menampilkan peringatan tersebut dan menyembunyikan filter tipe.

Ringkasan berkas yang harus ada di `public_html/api/` pada server yang dipakai:

| Berkas | Tindakan |
| --- | --- |
| `api_bootstrap.php` | Timpa dengan versi baru (perbaikan pembacaan kolom) |
| `login.php` | Timpa dengan versi baru |
| `requests.php` | Upload (belum ada) |
| `request_action.php` | Upload (belum ada) |
| `request_apply.php` | Upload (belum ada) |
| `env_check.php` | Timpa, lalu hapus setelah selesai |

Cara memastikan berkas sudah lengkap: buka `…/api/env_check.php` dan lihat
bagian `berkas_api`. Berkas yang bernilai `false` berarti belum ada di server.
Pastikan juga muncul `"versi_env_check": 2`.

## 16. Perbaikan: "Email atau Password Salah" padahal username benar

### Gejala

Setelah `main.dart` dan berkas API versi baru dipakai, login selalu gagal dengan
pesan:

```text
Email atau Password Salah
```

Padahal `env_check.php` menunjukkan `sales_users.username` **true**, dan akun
yang sama berhasil login di website.

### Penyebab

Pada `login.php` versi sebelumnya ada urutan seperti ini:

```php
require_once dirname(__DIR__) . '/config.php';   // di luar fungsi

function rts_api_db_login(): ?mysqli
{
    require_once dirname(__DIR__) . '/config.php';   // di dalam fungsi
    foreach (['conn', ...] as $nama) {
        if (isset($$nama) && ...) { return $$nama; }
    }
    return null;
}
```

`require_once` **tidak menjalankan ulang** berkas yang sudah pernah di-include.
Karena `config.php` sudah di-include di luar fungsi, panggilan di dalam fungsi
tidak menghasilkan apa pun. Akibatnya `$conn` tidak ada di lingkup fungsi,
fungsi mengembalikan `null`, pemeriksaan kolom selalu menjawab "tidak ada", dan
login otomatis jatuh ke mode **email**. Karena field yang diisi berisi username,
hasilnya selalu "Email atau Password Salah".

Ini murni kesalahan kode, bukan masalah database maupun password.

### Perbaikan

1. `login.php` - pemeriksa kolom kini memakai parameter `$conn` yang sudah
   tersedia, tidak lagi mencari ulang koneksi di dalam fungsi.
2. `api_bootstrap.php` dan `login.php` - pencarian koneksi kini memeriksa
   `$GLOBALS` maupun lingkup lokal, sehingga tetap benar pada kedua cara include.

### Berkas yang harus di-upload ulang

```text
api/login.php
api/api_bootstrap.php
```

Keduanya ke `public_html/api/` pada server yang dipakai
(`https://rts.benedic-s.com/api/`).

Tidak ada perubahan pada database. Tidak perlu migrasi. Tidak perlu
mengubah `main.dart` lagi.

### Cara menguji setelah upload

1. Buka aplikasi, masukkan username dan password seperti biasa.
2. Login harus berhasil dan langsung masuk ke Dashboard.

Bila masih menampilkan "Username atau password salah" (perhatikan: tanpa kata
"Email"), berarti kolomnya sudah terbaca dengan benar dan yang perlu diperiksa
adalah password itu sendiri.

### Soal error phpMyAdmin #1142

Saat mencoba:

```sql
SHOW COLUMNS FROM benedics_bene_sales.master_toko LIKE 'tipe_customer';
```

muncul:

```text
#1142 - SELECT command denied to user 'cpses_begh0epwjk'@'localhost'
for table 'benedics_bene_sales.master_toko'
```

Artinya akun phpMyAdmin tersebut tidak berhak membaca tabel milik database lain
lewat penulisan `database.tabel`. Ini normal pada hosting berbagi dan bukan
tanda kerusakan database.

Cara memeriksa kolom yang paling mudah (tanpa SQL):

1. Klik tabel **master_toko** di daftar database.
2. Buka tab **Struktur**.
3. Cari baris **tipe_customer**.

Pemeriksaan lewat `env_check.php` sudah cukup dan hasilnya `true`, jadi kolom
tersebut memang ada.

## 17. Cakupan Master Customer per role dan Sales District

### Aturan yang dipakai sekarang

| Role | Cakupan Master Customer |
| --- | --- |
| ADMIN | Semua district |
| ASS | Semua district |
| WSS | Semua district |
| SMST | Semua district |
| RTS | Sesuai **Sales District** akun |
| TF | Sesuai **Sales District** akun |

Pengaman bila district belum diisi pada akun RTS atau TF:

| Keadaan akun | Perilaku |
| --- | --- |
| District terisi | Menampilkan customer pada district tersebut |
| District kosong, salesman terisi | Menampilkan customer dengan salesman tersebut |
| District dan salesman kosong | Tidak menampilkan data sama sekali |

Tujuannya agar tidak ada data yang bocor hanya karena satu kolom belum diisi
oleh Admin.

### Perbandingan district tidak terpengaruh huruf besar/kecil

Tabel `master_toko` menyimpan district dengan huruf kapital, misalnya
`HAMPARAN PERAK`, sedangkan `sales_users.sales_district` dapat berupa
`Hamparan Perak`. Karena itu perbandingan di API memakai:

```sql
UPPER(TRIM(sales_district)) = ?
```

Sehingga keduanya dianggap sama dan customer tetap tampil.

### Yang berubah di aplikasi

1. **Master Customer** menampilkan kartu keterangan berwarna biru untuk RTS dan TF:

```text
Daftar ini hanya menampilkan customer pada District: MEDAN PETISAH.
Hubungi Admin bila ada customer yang belum terlihat.
```

2. Ringkasan di bawah filter menampilkan cakupannya:

| Role | Tulisan |
| --- | --- |
| ADMIN, ASS, WSS, SMST | Semua district |
| RTS, TF | District: <nama district> |
| RTS, TF tanpa district | Salesman: <nama salesman> |
| RTS, TF tanpa keduanya | Belum ada penugasan district |

3. **Dashboard** pada bagian Level Akses untuk RTS dan TF kini berbunyi
   `Customer sesuai Sales District`.

### Berkas yang perlu di-upload

| Berkas | Tindakan |
| --- | --- |
| `api/api_bootstrap.php` | Timpa (penentu mode cakupan) |
| `api/customers.php` | Timpa (daftar customer) |
| `api/customer_detail.php` | Timpa (detail customer) |

Lalu salin `main.dart` terbaru ke `D:\Project\rts_panel_app\lib\main.dart`
dan jalankan `flutter run`.

### Hal yang perlu diperhatikan

Website (`master_customer.php` pada cPanel) **masih memakai aturan lama**, yaitu
membatasi RTS dan TF berdasarkan `salesman`. Jadi untuk sementara:

- di **aplikasi Android**, RTS/TF melihat seluruh customer pada district-nya;
- di **website**, RTS/TF hanya melihat customer dengan salesman-nya.

Bila ingin disamakan, berkas website yang perlu disesuaikan adalah
`master_customer.php` pada baris:

```php
if (!$all_area) {
    $where[] = 'salesman = ?';
    $params[] = rts_current_salesman();
    $types .= 's';
}
```

Perubahannya sama seperti di API: bandingkan `sales_district` dengan district
pengguna memakai `UPPER(TRIM(...))`.

### Cara menguji

1. Login sebagai akun RTS atau TF yang sudah memiliki `sales_district`.
2. Buka **Master Customer**. Kartu biru akan menampilkan nama districtnya.
3. Jumlah customer akan lebih banyak dari sebelumnya, karena mencakup semua
   salesman pada district tersebut.
4. Buka salah satu detail customer, lalu tekan muat ulang. Detail yang dibuka
   harus tetap berada pada district yang sama.
5. Bila mencoba membuka customer di luar district (misalnya dari tautan lama),
   server akan menjawab "Customer tidak ditemukan atau bukan bagian tugas Anda."

## 18. Website: Master Customer sesuai Role dan Sales District

### Jawaban singkat

Ya, ada **satu berkas website** yang perlu diubah:

```text
master_customer.php
```

Berkas lain tidak perlu diubah.

### Aturan yang dipakai (sama dengan aplikasi Android)

| Role | Cakupan Master Customer |
| --- | --- |
| ADMIN | Semua district |
| ASS | Semua district |
| WSS | Semua district |
| SMST | Semua district |
| RTS | Sesuai Sales District akun |
| TF | Sesuai Sales District akun |

Pengaman bila district belum diisi pada akun RTS atau TF:

| Keadaan akun | Perilaku |
| --- | --- |
| District terisi | Customer pada district tersebut |
| District kosong, salesman terisi | Customer dengan salesman tersebut |
| District dan salesman kosong | Tidak ada data ditampilkan |

### Apa yang berubah di berkas website

1. Cakupan data ditentukan sendiri oleh halaman, tidak lagi bergantung pada
   fungsi `rts_can_see_all_customers()`.
2. RTS dan TF dibatasi dengan:

```php
$where[] = 'UPPER(TRIM(sales_district)) = ?';
$params[] = strtoupper($my_district);
```

   Perbandingan `UPPER(TRIM(...))` dipakai karena `master_toko` menyimpan
   district dengan huruf kapital (`HAMPARAN PERAK`), sedangkan `sales_users`
   bisa berupa `Hamparan Perak`.
3. Filter district dari form juga menjadi tidak peka huruf besar/kecil.
4. Untuk RTS dan TF, kotak isian District di form berubah menjadi keterangan
   tetap (read only), supaya tidak membingungkan.
5. Ditambahkan keterangan cakupan di kepala halaman:

```text
Total data: 412 · Cakupan: Sales District: MEDAN PETISAH
```

6. Tombol **Download CSV** otomatis mengikuti cakupan yang sama, karena memakai
   filter yang sama.
7. Tautan peta pada kolom Maps diganti ke Google Maps
   (`https://www.google.com/maps/search/?api=1&query=lat,lng`), agar sama
   dengan aplikasi Android.

### Cara memasang

1. **Backup dulu.** Di cPanel → File Manager → unduh salinan
   `public_html/master_customer.php` yang sekarang, atau ubah namanya menjadi
   `master_customer_lama.php`.
2. Upload berkas baru:

```text
master_customer_updated.php   →  public_html/master_customer.php
```

3. Buka halaman Master Customer di browser, uji dengan beberapa akun:

| Akun uji | Hasil yang diharapkan |
| --- | --- |
| ADMIN | Semua customer, keterangan "Semua district", kotak District aktif |
| WSS atau SMST | Semua customer, kotak District aktif |
| RTS dengan district terisi | Hanya customer pada district tersebut, ada keterangan biru |
| TF tanpa district | Data dibatasi ke salesman-nya, ada peringatan biru |

4. Bila ada masalah, kembalikan berkas lama:

```text
public_html/master_customer_lama.php  →  public_html/master_customer.php
```

### Berkas yang TIDAK diubah

| Berkas | Keterangan |
| --- | --- |
| `config.php` | Tidak disentuh |
| `auth.php` | Tidak disentuh |
| `index.php` | Login website tetap sama |
| `pengajuan_toko.php`, `inbox.php` | Masih memakai aturannya sendiri |
| `upload_customer.php` | Tidak disentuh |
| `header.php`, `footer.php`, `sidebar.php` | Tidak disentuh |

### Catatan perlunya keseragaman

Aplikasi Android sudah memakai aturan baru. Setelah `master_customer.php`
diganti, website dan aplikasi akan menampilkan data yang sama untuk setiap role.

Halaman lain di website (`inbox.php` dan `pengajuan_toko.php`) masih memakai
aturan sendiri, yaitu:

```php
$can_view_all = in_array($role_login, ['ADMIN', 'ASS', 'WSS', 'SMST'], true);
```

Aturan itu sudah sesuai keinginan Anda:

- ADMIN, ASS, WSS, SMST melihat semua pengajuan;
- RTS dan TF hanya melihat pengajuan miliknya sendiri.

Jadi tidak ada perubahan yang diperlukan di halaman pengajuan.

### Setelah dipasang

Alur kerja yang disarankan:

1. Login website sebagai akun RTS, pastikan jumlah customer sesuai districtnya.
2. Login aplikasi Android dengan akun yang sama, pastikan jumlahnya sama.
3. Bila angkanya berbeda, periksa kolom `sales_district` pada akun tersebut di
   `sales_users`, dan bandingkan dengan nilai `sales_district` di `master_toko`.

## 19. Dashboard website: angka 0 dan cara memperbaikinya

### Gejala

Pada `https://rts.benedic-s.com/dashboard.php`, akun **BENEDICTUS** dengan role
**RTS** menampilkan:

```text
Total Customer      0
Customer Aktif      0
Total GSP           0
Pengajuan Pending   0
```

### Penyebab

Dashboard produksi menghitung angka dengan batas yang tidak sesuai dengan
penugasan akun. Untuk role RTS dan TF, angka tersebut hanya terisi bila akun
memiliki `sales_district` atau `salesman` yang cocok dengan data di
`master_toko`. Bila kolomnya kosong atau perbandingannya berbeda huruf
besar/kecil, hasilnya 0.

Karena Master Customer dan dashboard harus berbicara dengan aturan yang sama,
dashboard dibuat ulang memakai aturan cakupan yang baru.

### Aturan yang dipakai di dashboard baru

| Role | Cakupan angka |
| --- | --- |
| ADMIN, ASS, WSS, SMST | Semua district |
| RTS, TF | Sesuai Sales District akun |
| RTS/TF tanpa district | Memakai salesman |
| RTS/TF tanpa keduanya | Angka 0 disertai peringatan |

| Kartu | Sumber data |
| --- | --- |
| Total Customer | `master_toko` pada cakupan |
| Customer Aktif | `master_toko` dengan `status_aktif = 'Aktif'` pada cakupan |
| Total GSP | `master_toko` dengan `tipe_customer = 'GSP'` pada cakupan |
| Pengajuan Pending | ADMIN/ASS/WSS/SMST: semua. RTS/TF: pengajuan milik sendiri |

Monitoring Stok Kritis juga ikut menyesuaikan:

| Role | Baris yang ditampilkan |
| --- | --- |
| ADMIN, ASS, WSS, SMST | Semua outlet |
| RTS, TF dengan district | Outlet dengan `zona` sama dengan district |
| RTS, TF dengan salesman | Outlet dengan `salesman` sama dengan akun |

### Hasil yang diharapkan setelah dipasang

Untuk akun BENEDICTUS (RTS):

```text
Total Customer      (jumlah customer pada districtnya)
Customer Aktif      (jumlah customer aktif pada districtnya)
Total GSP           (jumlah GSP pada districtnya)
Pengajuan Pending   (pengajuan miliknya sendiri)
```

Bila masih 0, berarti akun tersebut belum memiliki `sales_district` dan
`salesman` yang cocok, atau semua customer pada districtnya memang tidak ada.
Dashboard baru akan menampilkan keterangan penyebabnya secara jelas, misalnya:

```text
Akun Anda belum memiliki Sales District maupun Salesman.
```

### Cara memasang

1. **Backup dulu**: cPanel → File Manager → rename

```text
public_html/dashboard.php   →   public_html/dashboard_lama.php
```

2. Upload berkas baru:

```text
dashboard_updated.php   →   public_html/dashboard.php
```

3. Buka `dashboard.php`, lalu uji dengan beberapa akun.

4. Bila ada masalah, kembalikan berkas lama:

```text
public_html/dashboard_lama.php   →   public_html/dashboard.php
```

### Pengingat keamanan penting

Berkas `dashboard.php` versi lama yang ada di workspace ini memuat **kredensial
database secara tertulis di dalam kode**:

```php
$host = "localhost";
$user = "…";
$pass = "…";
$db   = "…";
```

Bila berkas seperti itu ada di server atau terunggah ke repositori, sebaiknya:

1. Hapus berkas versi lama tersebut setelah dashboard baru dipasang.
2. Jangan pernah mengunggahnya ke repositori publik.
3. Ganti password database dari cPanel.
4. Perbarui `config.php` agar sesuai dengan password baru.
5. Buat backup baru setelah perubahan.

Dashboard baru **tidak memuat kredensial apa pun**; ia memakai `config.php`
dan `auth.php` seperti halaman lain.

## 20. Form pengajuan dari Android dan alat diagnosa cakupan data

### A. Kirim pengajuan langsung dari HP

Sales tidak lagi perlu membuka website untuk mengajukan perubahan customer.

**Dari daftar Master Customer**

Tombol bulat **Ajukan** di kanan bawah. Membuka form dengan pilihan jenis:

```text
Tambah Baru | Ganti Nama | Ganti Alamat | Hapus Toko
```

**Dari detail customer**

Tombol **AJUKAN PERUBAHAN CUSTOMER** di bagian bawah. Customer langsung
terpilih, sehingga tinggal memilih jenis (Ganti Nama, Ganti Alamat, atau
Hapus Toko) dan mengisi keterangan.

Isian pada form:

| Jenis | Isian khusus |
| --- | --- |
| Tambah Baru | Nama toko, alamat, kategori (REGULER/GSP), hari kunjungan |
| Ganti Nama | Nama toko baru |
| Ganti Alamat | Alamat baru |
| Hapus Toko | Tidak ada isian tambahan, disertai peringatan arsip |

Isian yang selalu ada: PIC di toko, rute kunjungan, minggu (Ganjil/Genap), dan
alasan pengajuan.

Yang **tidak** diisi oleh sales karena diambil otomatis dari akun:

```text
sales_email, salesman, sales_distric
```

Sehingga sales tidak dapat mengirim pengajuan atas nama orang lain.

Pengaman tambahan di server:

- Customer yang diajukan harus berada dalam cakupan akun. Bila bukan,
  permintaan ditolak dengan pesan "Customer tidak ditemukan atau bukan bagian
  tugas Anda."
- Bila akun belum memiliki salesman maupun district, pengajuan ditolak dengan
  pesan agar menghubungi Admin.
- Jenis pengajuan hanya boleh salah satu dari empat pilihan di atas.

Setelah terkirim, pengajuan masuk ke `pengajuan_sales` dengan status `Pending`
dan langsung muncul pada menu **Pengajuan** di aplikasi dan **Inbox** di
website.

### B. Alat diagnosa cakupan data

Bila angka pada dashboard atau Master Customer terasa janggal, buka:

```text
Pengaturan  ->  Diagnosa Data  ->  JALANKAN DIAGNOSA
```

Aplikasi akan menampilkan:

| Baris | Arti |
| --- | --- |
| Role | Peran akun yang dipakai |
| Salesman | Nilai `salesman` pada akun |
| Sales District | Nilai `sales_district` pada akun |
| Mode cakupan | `all`, `district`, `salesman`, atau `none` |
| Total seluruh customer | Jumlah customer di seluruh database |
| Cocok district akun | Jumlah customer yang districtnya sama dengan akun |
| Cocok salesman akun | Jumlah customer yang salesmannya sama dengan akun |
| Customer aktif pada cakupan | Jumlah customer aktif yang akan tampil |
| GSP pada cakupan | Jumlah GSP pada cakupan |
| Pengajuan pending | Untuk RTS/TF: pengajuan miliknya. Untuk lainnya: seluruhnya |

Di bawahnya ada catatan yang menjelaskan penyebab bila nilainya 0, misalnya:

```text
Nama district pada akun tidak ditemukan di master_toko. Bandingkan nilai
sales_district akun dengan daftar district di bawah, lalu perbaiki salah
satunya melalui halaman Kelola User.
```

Balasan API juga memuat `district_pada_master_toko`, yaitu 15 district dengan
jumlah customer terbanyak, sehingga bisa dibandingkan dengan isi akun.

### C. Berkas yang perlu di-upload

Ke `public_html/api/`:

| Berkas | Keterangan |
| --- | --- |
| `request_create.php` | Baru - kirim pengajuan dari Android |
| `scope_check.php` | Baru - diagnosa cakupan data |

Salin juga `main.dart` terbaru ke `D:\Project\rts_panel_app\lib\main.dart`,
lalu:

```powershell
cd D:\Project\rts_panel_app
flutter run
```

### D. Cara menguji pengajuan dari Android

1. Login sebagai **RTS** yang districtnya sudah terisi.
2. Buka **Master Customer**, tekan tombol **Ajukan** di kanan bawah.
3. Pilih **Tambah Baru**, isi nama toko, alamat, kategori, hari, PIC, rute,
   minggu, dan alasan.
4. Tekan **KIRIM PENGAJUAN**. Muncul keterangan bahwa pengajuan terkirim.
5. Buka menu **Pengajuan**. Pengajuan tadi muncul dengan status **Pending**.
6. Login sebagai **ADMIN**, buka pengajuan tersebut, lalu tekan **SETUJUI**.
7. Periksa **Master Customer**, customer baru harus sudah muncul.

Bila ingin menguji tanpa mengubah data asli, lakukan pada **server Staging**
lebih dahulu.

### E. Catatan

- Pengajuan dari Android selalu masuk sebagai `Pending`. Tidak ada cara
  menyetujui sendiri dari akun pengirim.
- Bukti tindakan tetap tercatat pada `riwayat_aksi` ketika disetujui atau
  ditolak dari website maupun dari aplikasi.

### F. Perbaikan: error "The getter 'user' isn't defined"

Versi pertama tombol **AJUKAN PERUBAHAN CUSTOMER** memakai data akun
(`user`) pada halaman Detail Customer, padahal halaman itu sebelumnya hanya
menerima `idCustomer` dan `token`. VS Code menandai baris tersebut dengan:

```text
The getter 'user' isn't defined for the type 'CustomerDetailPage...'
```

Perbaikannya:

1. `CustomerDetailPage` kini menerima satu parameter tambahan:

```dart
final RtsUser user;
```

2. Saat halaman detail dibuka dari daftar, akun ikut dikirim:

```dart
CustomerDetailPage(
  user: widget.user,
  idCustomer: customer.idCustomer,
  token: widget.token,
  preview: customer,
)
```

3. Jenis **Ganti Nama**, **Ganti Alamat**, dan **Hapus Toko** hanya masuk akal
   bila customer tujuannya jelas. Karena itu, bila form dibuka dari tombol
   **Ajukan** pada daftar Master Customer, ketiga jenis tersebut tetap terlihat
   tetapi disertai kotak peringatan berisi langkah yang harus dilakukan, dan
   tombol **KIRIM PENGAJUAN** menolak lebih dahulu sebelum data dikirim ke
   server. Ini mencegah pengajuan tanpa ID customer.

Pastikan memakai `main.dart` versi terbaru. Seluruh berkas harus disalin, bukan
potongan tertentu saja.

### G. Pengaman tambahan pada dashboard baru

Sebelum berkas `dashboard_updated.php` dipasang, dua hal berisiko sudah
dihilangkan:

**1. Helper dari `auth.php`**

Dashboard memakai `rts_require_login()`, `rts_current_role()`,
`rts_is_approver()`, dan `rts_current_salesman()`. Bila nama fungsi pada
`auth.php` di server berbeda, halaman akan berhenti dengan tampilan kosong.
Sekarang setiap fungsi diperiksa lebih dahulu:

```php
if (!function_exists('rts_require_login')) {
    // versi cadangan dipakai
}
```

Jadi halaman tetap tampil, memakai versi cadangan, dan tidak pernah blank.

**2. Nama kunci session**

Setiap halaman website bisa menyimpan nama kunci session yang berbeda. Dashboard
kini membaca beberapa kemungkinan sekaligus:

| Data | Kunci yang dicoba |
| --- | --- |
| Nama | `nama`, `nama_lengkap`, `username`, `name` |
| District | `sales_district`, `sales_distric`, `district`, `zona` |
| Email | `email`, `sales_email`, `username` |
| Role | `role`, `user_role` |

Bila tetap tidak ditemukan, dashboard mengambil data akun langsung dari tabel
`sales_users` memakai username. Bila itupun gagal, halaman tetap tampil dengan
angka 0 disertai kotak peringatan, bukan halaman kosong.

**3. Stok kritis tanpa penugasan**

Akun RTS/TF yang belum memiliki district maupun salesman kini memakai syarat
`WHERE 1 = 0`, sehingga Monitoring Stok Kritis tidak pernah menampilkan seluruh
data perusahaan kepada akun yang tidak berhak.

## 21. Ingat saya: buka aplikasi langsung masuk

### A. Cara kerjanya

Sebelumnya centang **Ingat saya** di halaman login hanya berupa tampilan. Kini
centang tersebut benar-benar berfungsi.

**Saat login**

```text
Centang "Ingat saya (tidak perlu login ulang)"  ->  token disimpan di HP
Tidak dicentang                                 ->  token tidak disimpan
```

**Saat aplikasi dibuka kembali**

```text
Halaman pembuka (logo RTS Panel)
   |
   +-- Ada sesi tersimpan?  -- tidak --> Halaman Login
   |
   +-- Ya --> Token diperiksa ke server (session_check.php)
                 |
                 +-- Masih berlaku --> langsung Dashboard
                 |
                 +-- Ditolak server --> sesi dibuang, Halaman Login
                 |
                 +-- Tidak ada internet --> tombol COBA LAGI / Masuk manual
```

Pengguna tidak perlu mengetik username dan password lagi, dan yang paling
penting: **cakupan data tetap diambil dari server**, bukan dari salinan di HP.
Jadi bila Admin mengubah district seorang RTS, perubahan itu langsung berlaku
pada pembukaan aplikasi berikutnya.

### B. Di mana token disimpan

Token disimpan pada penyimpanan pribadi aplikasi (`SharedPreferences`).
Berkas ini tidak dapat dibaca aplikasi lain pada perangkat yang belum di-root.

Kunci yang dipakai:

| Kunci | Isi |
| --- | --- |
| `rts_sesi_token` | Token login |
| `rts_sesi_user` | Identitas akun (username, nama, role, district) |
| `rts_sesi_server` | Server tempat token dibuat |
| `rts_ingat_saya` | Pilihan centang terakhir |

### C. Sesi otomatis dibuang pada keadaan berikut

1. Menekan tombol **Keluar** pada dashboard
2. Menekan **LUPAKAN SESI TERSIMPAN** pada Pengaturan
3. **Mengganti server** (Produksi ↔ Staging) - karena token hanya berlaku pada
   server tempat ia dibuat
4. Server menyatakan token sudah berakhir atau akun tidak aktif

### D. Berkas baru yang perlu di-upload

| Berkas | Tujuan | Keterangan |
| --- | --- | --- |
| `api/session_check.php` | `public_html/api/` | Baru - periksa sesi tersimpan |
| `main.dart` | `lib/main.dart` di PC | Fitur Ingat saya dan halaman pembuka |

### E. Cara menguji

1. Login dengan **Ingat saya dicentang**.
2. Tutup aplikasi sepenuhnya (bukan hanya ditekan tombol back).
3. Buka kembali. Seharusnya muncul logo sekejap, lalu langsung Dashboard tanpa
   diminta password.
4. Buka **Pengaturan**, bagian **Sesi Login** harus bertuliskan
   "Sesi tersimpan aktif" beserta nama akun.
5. Tekan **Keluar**. Buka kembali aplikasi: harus muncul halaman Login.
6. Login lagi tanpa mencentang Ingat saya, lalu tutup dan buka kembali:
   halaman Login yang muncul.

### F. Catatan keamanan

- Bila ponsel hilang dalam keadaan sesi tersimpan, orang lain dapat membuka
  aplikasi. Bila hal ini terjadi, minta Admin menghapus baris token pada tabel
  `api_tokens`, atau ubah password akun tersebut, lalu tekan Keluar pada
  perangkat mana pun yang masih aktif.
- Untuk keamanan lebih tinggi, penyimpanan dapat ditingkatkan ke Android
  Keystore (`flutter_secure_storage`) pada tahap berikutnya. Perlu penambahan
  paket dan pengujian build ulang.

## 22. Perbaikan form pengajuan: pilih toko, kunci kolom, dan titik koordinat

### A. Tombol melayang pada menu Pengajuan

Menu **Pengajuan** kini memiliki tombol bulat **Pengajuan Baru** di kanan
bawah, langsung membuka form pengajuan tanpa harus lewat Master Customer.

### B. Kolom "Nama Toko" sebagai pencarian toko

Pada pengajuan **Ganti Nama** dan **Ganti Alamat**, kolom pertama yang
sebelumnya berlabel "Nama Toko Baru" kini berlabel **Nama Toko** dan berfungsi
sebagai pemilih toko:

1. Ketuk kolom **Nama Toko**
2. Muncul lembar pencarian berisi daftar toko dari database
3. Ketik nama toko, ID customer, atau salesman
4. Pilih salah satu toko

Setelah dipilih, seluruh keterangan di bawahnya terisi sendiri: ID customer,
alamat saat ini, hari kunjungan, frekuensi, salesman, district, dan status.

Kolom **Nama Toko Baru** (untuk penggantian nama) dan **Alamat Baru** (untuk
penggantian alamat) tetap tersedia pada bagian
**Perubahan yang Diajukan**, karena itulah data yang hendak diubah.

Pengaman yang ditambahkan:

| Keadaan | Tindakan aplikasi |
| --- | --- |
| Nama baru sama dengan nama sekarang | Ditolak, minta diubah lebih dahulu |
| Alamat baru sama dengan alamat sekarang | Ditolak, minta diubah lebih dahulu |
| Belum memilih toko | Ditolak dengan pesan "Pilih dulu toko yang dituju" |
| Memakai titik GPS tapi titik belum terbaca | Ditolak, minta tekan Perbarui Titik |

### C. Kolom keterangan terkunci, dibuka dengan centang

Keterangan yang berasal dari database ditampilkan **terkunci** (berlatar abu
dengan ikon gembok). Untuk mengubahnya, pengguna harus **mencentang kotak**
pada kolom tersebut:

| Kolom | Sumber nilai | Cara mengubah |
| --- | --- | --- |
| PIC di Toko | Diisi sales (tidak ada di database) | Langsung ketik |
| Hari Kunjungan | Kolom `hari` pada `master_toko` | Centang kotak di kolomnya |
| Minggu (Ganjil/Genap) | Kolom `kunjungan` pada `master_toko` | Centang kotak di kolomnya |
| Alasan Pengajuan | Diisi sales | Langsung ketik |

Setelah dicentang, kolom berubah menjadi pilihan yang dapat ditekan dan
bertanda **diubah**. Bila batal, hilangkan centangnya agar kembali terkunci
sesuai data database.

### D. Alamat dari titik koordinat dengan warna keakuratan

Pada pengajuan **Ganti Alamat**:

1. Ikon titik lokasi di ujung kanan kolom **Alamat Baru**, atau
2. Centang **Sesuai koordinat sekarang**

Aplikasi akan membaca titik GPS tempat sales berdiri, lalu menuliskannya ke
kolom alamat:

```text
JL. PASAR KLUMPANG NO 12
Koordinat: 3.585242, 98.675318 (GPS ±8 m)
```

Bila sales tidak mengetik alamat apa pun, maka hanya baris koordinat yang
tersimpan. ADMIN tetap dapat membuka titik tersebut di Google Maps.

Tingkat keakuratan ditampilkan dengan warna:

| Akurasi | Warna | Keterangan |
| --- | --- | --- |
| ≤ 10 meter | Hijau | Sangat akurat, aman dipakai sebagai alamat |
| ≤ 25 meter | Biru | Akurat, dapat dipakai |
| ≤ 60 meter | Kuning | Cukup akurat, sebaiknya diperbarui |
| > 60 meter | Merah | Kurang akurat, keluar dari bangunan lalu perbarui |
| Belum dibaca | Abu-abu | Belum ada titik lokasi |

Tersedia tombol **PERBARUI TITIK** dan **CEK DI MAPS** (membuka Google Maps
pada titik tersebut).

Bila GPS belum aktif, izin ditolak, atau izin diblokir permanen, aplikasi
menampilkan langkah perbaikannya, bukan sekadar gagal.

### E. Temuan pada database: Hari dan Rute adalah kolom yang sama

Saat memeriksa data asli, kolom `rute_kunjungan` pada `pengajuan_sales`
ternyata berisi **hari kunjungan**, bukan nama rute:

```text
id 1235: pic='zaki', rute_kunjungan='Rabu', week='Genap'
id 1236: pic='Iqbal', rute_kunjungan='Rabu', week='Genap'
```

Karena itu kolom isian **Rute Kunjungan** yang bebas dihapus dan digabung
menjadi satu kolom **Hari Kunjungan**. Aplikasi kini mengirim:

```text
rute_kunjungan = hari yang dipilih   (contoh: Rabu)
visit_day_baru = hari yang dipilih   (contoh: Rabu)
week           = Ganjil / Genap
```

Dengan demikian isi database dari aplikasi Android seragam dengan isi database
dari website.

### F. Berkas dan langkah yang berubah

**1. Paket baru** - pada `pubspec.yaml` tambahkan:

```yaml
  geolocator: ^14.0.3
```

Lalu jalankan:

```powershell
cd D:\Project\rts_panel_app
flutter pub get
```

**2. Izin lokasi Android** - buka
`D:\Project\rts_panel_app\android\app\src\main\AndroidManifest.xml`,
lalu tempelkan dua baris ini tepat di atas baris `<application`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

**3. `lib/main.dart`** - salin seluruh berkas versi terbaru.

**4. Tidak ada berkas API baru.** Endpoint yang dipakai sudah ada:
`customers.php`, `request_create.php`, `customer_detail.php`.

### G. Cara menguji

1. Buka menu **Pengajuan**, tekan tombol **Pengajuan Baru**.
2. Pilih jenis **Ganti Alamat**.
3. Ketuk kolom **Nama Toko**, ketik nama toko Anda, lalu pilih toko tersebut.
4. Periksa seluruh keterangan sudah terisi dan terkunci.
5. Ubah alamat, atau centang **Sesuai koordinat sekarang** dan izinkan akses
   lokasi saat diminta.
6. Perhatikan warna tingkat keakuratan. Bila merah atau kuning, tekan
   **PERBARUI TITIK**.
7. Tekan **CEK DI MAPS** untuk memastikan titiknya benar.
8. Isi alasan, lalu tekan **KIRIM PENGAJUAN**.
9. Buka menu Pengajuan: pengajuan baru muncul dengan status Pending.

### H. Perbaikan: layar hitam setelah pembaruan halaman pembuka

**Penyebab.** Halaman pembuka memeriksa sesi tersimpan langsung dari
`initState()`:

```dart
void initState() {
  super.initState();
  _periksa();          // memanggil Navigator saat tampilan masih dibangun
}
```

Pada saat itu Flutter masih dalam proses membangun tampilan pertama. Perpindahan
halaman (`Navigator.pushReplacement`) ditolak oleh Flutter, sehingga frame
pertama tidak pernah selesai digambar dan yang tampil hanya layar hitam.

**Perbaikan.** Pemeriksaan dijalankan setelah tampilan pertama selesai:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted) _periksa();
});
```

**Pengaman tambahan**

1. **Keterangan kesalahan tampil di layar.** Bila ada kesalahan lain pada
   tampilan, aplikasi menampilkan kotak merah berisi tulisan kesalahannya
   beserta anjuran mengirimkannya, bukan layar hitam tanpa petunjuk:

```dart
ErrorWidget.builder = (FlutterErrorDetails details) { ... }
```

2. **Batas waktu pembacaan pengaturan.** `SharedPreferences` diberi batas 5
   detik. Bila perangkat lambat menjawab, aplikasi tetap dijalankan dengan
   pengaturan bawaan.

3. **main() tidak lagi bisa gagal.** Pembacaan pengaturan server dan sesi
   dibungkus `try/catch`, sehingga `runApp()` selalu dipanggil.

**Bila layar hitam masih terjadi**, yang perlu diperiksa lebih dahulu:

| Pemeriksaan | Perintah / tempat |
| --- | --- |
| Paket geolocator terpasang | `flutter pub get` di `D:\Project\rts_panel_app` |
| Kesalahan kompilasi | panel Terminal pada VS Code, cari tulisan berwarna merah |
| Tampilan aplikasi terpasang | pastikan baris `Installing build\app\outputs\...` muncul |
| Kesalahan tampilan | pada HP: kirimkan isi kotak merah yang muncul |

## 23. Perbaikan lanjutan form pengajuan: pilih toko, alamat otomatis, dan dropdown

### A. Kolom "Nama Toko" selalu tersedia

Sebelumnya kolom pencarian toko hanya muncul bila form dibuka dari Detail
Customer. Kini kolom **Nama Toko** selalu ada, termasuk saat form dibuka dari
tombol melayang **Pengajuan Baru** pada menu Pengajuan.

Cara kerjanya:

| Keadaan | Tampilan |
| --- | --- |
| Belum ada toko dipilih | Kolom bertuliskan "Ketuk untuk memilih toko" |
| Sudah ada toko dipilih | Nama toko, ID customer, dan tombol **Ganti** |

Pilihan jenis pengajuan kini terhubung dengan kolom tersebut:

- Menekan **Ganti Nama**, **Ganti Alamat**, atau **Hapus Toko** saat belum ada
  toko yang dipilih akan langsung membuka daftar toko.
- Menekan **Tambah Baru** atau tombol **Kosongkan (ajukan toko baru)**
  mengembalikan form ke pengisian toko baru.

Dengan begitu tidak ada lagi pengajuan yang dikirim tanpa ID customer.

### B. Alamat otomatis dari titik koordinat

Sebelumnya titik GPS dituliskan apa adanya ke kolom alamat:

```text
Koordinat: 3.481640, 98.613200
```

Kini titik itu diterjemahkan menjadi alamat lengkap memakai layanan
penerjemah koordinat bawaan Android:

```text
Jl. Darussalam, Petisah Tengah, Medan Petisah, Kota Medan, 20112
```

Cara memakainya:

1. Ketuk ikon titik lokasi di ujung kolom **Alamat Baru**, atau
2. Centang **Sesuai koordinat sekarang**

Keduanya melakukan hal yang sama: membaca titik GPS, menerjemahkannya menjadi
alamat, lalu mengganti isi kolom alamat. **Koordinat tidak ikut dituliskan**
pada kolom alamat.

Kolom alamat menjadi terkunci selama mode koordinat aktif. Bila centangnya
dihilangkan, alamat yang Anda ketik sebelumnya dikembalikan.

Tingkat keakuratan tetap ditampilkan dengan warna seperti sebelumnya
(hijau/biru/kuning/merah) beserta tombol **PERBARUI TITIK** dan **CEK DI MAPS**.

**Bila alamat gagal diterjemahkan** (biasanya karena tidak ada koneksi
internet), aplikasi menampilkan keterangan dan memakai koordinat sebagai
pengganti supaya pengajuan tetap dapat dikirim.

### C. Hari Kunjungan dan Frekuensi Kunjungan berbentuk dropdown

Kedua kolom ini terkunci selama toko diambil dari database. Setelah kotaknya
dicentang, yang muncul adalah **daftar pilihan (dropdown)**, bukan deretan
tombol.

| Kolom | Sumber data | Pilihan |
| --- | --- | --- |
| Hari Kunjungan | `master_toko.hari` | Senin, Selasa, Rabu, Kamis, Jumat, Sabtu |
| Frekuensi Kunjungan | `master_toko.kunjungan` | Weekly, Bi-Weekly Ganjil, Bi-Weekly Genap |

Isi kolom `kunjungan` pada database asli memang berisi tiga nilai tersebut:

```text
Bi-Weekly Ganjil : 1727 toko
Bi-Weekly Genap  : 1702 toko
Weekly           :  147 toko
```

Bila ada nilai lain di database yang belum ada pada daftar pilihan, nilai
tersebut tetap ditampilkan pada dropdown sehingga data tidak pernah hilang dari
pandangan pengguna.

Kolom **Minggu** yang lama sudah tidak dipakai lagi. Sebagai gantinya,
aplikasi mengirim pilihan frekuensi tersebut pada kolom `week`, sehingga isinya
menjadi:

```text
week = Weekly  atau  Bi-Weekly Ganjil  atau  Bi-Weekly Genap
```

### D. Catatan penting: hari dan frekuensi belum diterapkan saat disetujui

Halaman persetujuan website (`inbox.php`) saat ini hanya menerapkan
perubahan nama toko, alamat, tipe, hari, dan district ke `master_toko`.
Kolom `kunjungan` (frekuensi) **belum ikut diperbarui** saat pengajuan
disetujui.

Jadi bila sales mengubah frekuensi kunjungan, perubahan itu tercatat sebagai
keterangan pada pengajuan dan terlihat oleh ADMIN, tetapi belum otomatis
mengubah Master Customer. Bila ingin ikut diterapkan, perlu penyesuaian kecil
pada `inbox.php` dan `request_apply.php` - sebaiknya diuji pada server Staging
lebih dahulu.

### E. Berkas dan langkah yang berubah

**1. Paket baru** - tambahkan pada `pubspec.yaml`:

```yaml
  geocoding: ^4.0.0
  geolocator: ^14.0.3
```

```powershell
cd D:\Project\rts_panel_app
flutter pub get
```

Bila muncul keterangan bahwa versi `geocoding` tidak cocok, ganti menjadi
`geocoding: ^3.0.0`, lalu jalankan `flutter pub get` kembali.

**2. `lib/main.dart`** - salin seluruh berkas versi terbaru.

**3. Tidak ada berkas API baru** dan tidak ada tambahan izin pada
`AndroidManifest.xml` (izin Lokasi sudah ditambahkan sebelumnya).

### F. Cara menguji

1. Buka menu **Pengajuan**, tekan tombol **Pengajuan Baru**.
2. Kolom **Nama Toko** harus muncul dalam keadaan kosong.
3. Tekan **Ganti Alamat**. Daftar toko langsung terbuka - pilih satu toko.
4. Periksa keterangan terisi dan **Frekuensi Kunjungan** menampilkan nilai yang
   sesuai database (misalnya `Bi-Weekly Ganjil`).
5. Centang kotak pada **Hari Kunjungan**: yang muncul adalah dropdown.
6. Centang kotak pada **Frekuensi Kunjungan**: yang muncul adalah dropdown
   berisi Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap.
7. Pada **Alamat Baru**, ketuk ikon titik lokasi. Alamat kolom tersebut harus
   berganti menjadi alamat lengkap, bukan koordinat.
8. Tekan **KIRIM PENGAJUAN**, lalu periksa pada menu Pengajuan.

## 24. Pemberitahuan di aplikasi Android

### A. Apa yang ditampilkan

Lonceng pada sudut kanan atas dashboard kini **berangka** dan dapat ditekan.
Selain lonceng, tersedia juga kotak menu **Notifikasi** pada menu utama.

Halaman Pemberitahuan memuat tiga bagian:

| Bagian | Isi | Untuk siapa |
| --- | --- | --- |
| Perlu Diperiksa | Pengajuan berstatus Pending pada cakupan akun | ADMIN, ASS, WSS, SMST |
| Pengajuan Anda | Pengajuan sendiri yang masih menunggu | RTS, TF |
| Hasil Pengajuan Saya | Pengajuan sendiri yang sudah disetujui / ditolak, beserta catatan pemeriksa | Semua |
| Pemberitahuan Sistem | Isi tabel `notifications` bila tabelnya tersedia | Semua |

Tiga kotak angka di bagian atas menunjukkan jumlah **Menunggu**, **Disetujui**,
dan **Ditolak** dalam satu pandangan.

Setiap kartu pengajuan dapat ditekan dan langsung membuka daftar pengajuan,
sehingga sales tidak perlu mencari sendiri.

### B. Daftar ini tetap berfungsi walau tabel notifikasi belum ada

Bagian 1, 2, dan 3 disusun langsung dari tabel `pengajuan_sales` dan
`pengajuan_gsp` yang sudah ada. Jadi fitur ini dapat langsung dipakai tanpa
perubahan database sama sekali.

Bila tabel `notifications` belum ada, aplikasi menampilkan daftar tersebut dan
menambahkan catatan kecil di bagian bawah halaman. Kolom balasan API
`tersedia` bernilai `false` pada keadaan itu.

### C. Pemberitahuan otomatis

Dua berkas API kini membuat pemberitahuan secara otomatis:

| Kejadian | Pengirim berkas | Penerima pemberitahuan |
| --- | --- | --- |
| Sales mengirim pengajuan | `request_create.php` | Seluruh akun ADMIN dan ASS |
| Pengajuan disetujui | `request_action.php` | Akun pengirim pengajuan |
| Pengajuan ditolak | `request_action.php` | Akun pengirim pengajuan |

Contoh isi pemberitahuan:

```text
Judul  : Pengajuan Disetujui
Isi    : Pengajuan "Ganti Alamat" untuk 107 PONSEL telah DISETUJUI oleh ADMIN.
         Catatan: alamat sudah diperbarui
Jenis  : SUCCESS
```

```text
Judul  : Pengajuan Baru Masuk
Isi    : BENEDICTUS (Medan Kota) mengirim pengajuan "Ganti Nama" untuk
         TOKO SUMBER REJEKI. Silakan diperiksa pada menu Pengajuan.
Jenis  : WARNING
```

Penyimpanan pemberitahuan bersifat **pelengkap**: bila tabel `notifications`
belum ada, penyimpanan dilewati dengan tenang sehingga pengajuan tetap terkirim
dan tetap dapat disetujui.

### D. Berkas yang perlu di-upload

Ke `public_html/api/`:

| Berkas | Keterangan |
| --- | --- |
| `notifications.php` | Baru - daftar dan penanda pemberitahuan |
| `request_action.php` | Timpa - menambah pemberitahuan saat disetujui / ditolak |
| `request_create.php` | Timpa - menambah pemberitahuan saat pengajuan baru masuk |

Ke `lib/main.dart` pada PC: salin seluruh berkas versi terbaru.

**Tidak wajib dijalankan**, hanya bila ingin pemberitahuan tersimpan permanen:

```text
database/migrations/RTS_PANEL_TABEL_NOTIFICATIONS.sql
```

Berkas SQL itu **hanya membuat tabel baru** (`CREATE TABLE IF NOT EXISTS`) dan
tidak mengubah atau menghapus data apa pun. Jalankan pada Staging lebih dahulu.

### E. Cara menguji tanpa tabel notifikasi

1. Login sebagai **RTS** pada aplikasi.
2. Kirim satu pengajuan (misalnya Ganti Alamat).
3. Login sebagai **ADMIN**.
4. Perhatikan lonceng: angkanya bertambah.
5. Buka halaman Pemberitahuan: pengajuan tadi muncul di bagian
   **Perlu Diperiksa**.
6. Setujui pengajuan tersebut.
7. Kembali login sebagai **RTS**, buka Pemberitahuan: pengajuan muncul pada
   **Hasil Pengajuan Saya** dengan status DISETUJUI dan catatan dari ADMIN.
8. Bila tabel notifikasi sudah dibuat, pada langkah 7 juga muncul
   **Pemberitahuan Sistem** berjudul "Pengajuan Disetujui".

### F. Catatan

- Angka lonceng dihitung dari: jumlah pengajuan yang perlu diperiksa (atau
  pengajuan sendiri yang masih menunggu untuk RTS/TF) ditambah pemberitahuan
  yang belum dibaca.
- Menekan sebuah pemberitahuan akan menandainya sudah dibaca. Tombol
  **TANDAI DIBACA** menandai seluruhnya sekaligus.
- Halaman persetujuan pada **website** (`inbox.php`) belum menulis ke tabel
  notifikasi. Bila diinginkan, penyesuaian kecil dapat ditambahkan pada tahap
  berikutnya agar pemberitahuan juga terbuat ketika pengajuan diproses dari
  website.

## 25. Pemberitahuan pada layar HP (bar status dan layar kunci)

### A. Jawaban singkat: bisa

Pemberitahuan RTS Panel kini muncul pada bagian atas layar HP, seperti
pemberitahuan WhatsApp atau aplikasi bank. Aplikasi juga menampilkan
permintaan izin **"Izinkan Notifikasi"**.

Ada dua tingkatan, dan yang sudah dipasang sekarang adalah **tingkatan
pertama** karena tidak memerlukan akun atau layanan tambahan:

| Tingkatan | Cara kerja | Keterlambatan | Perlu akun tambahan |
| --- | --- | --- | --- |
| **Sekarang** | Pemeriksaan berkala selama aplikasi masih hidup di latar belakang HP | 2 menit, dan langsung setiap kali aplikasi dibuka kembali | Tidak |
| Bila diperlukan nanti | Firebase Cloud Messaging (dorongan dari server) | Beberapa detik, walau aplikasi ditutup sepenuhnya | Ya, akun Firebase |

**Catatan revisi.** Rencana awal memakai paket `workmanager` untuk memeriksa
setiap 15 menit walau aplikasi ditutup. Paket itu **dilepas** karena belum
cocok dengan Flutter 3.44.8 yang Anda pakai: kode Kotlin paket tersebut tidak
ikut terkompilasi, sehingga build gagal dengan pesan:

```text
cannot find symbol: class WorkmanagerPlugin
```

Dengan dilepasnya paket itu, pemberitahuan tetap masuk selama aplikasi masih
hidup di latar belakang HP (window 2 menit dan saat aplikasi dibuka kembali).
Untuk pemberitahuan yang tetap masuk walau aplikasi ditutup sepenuhnya,
caranya adalah Firebase Cloud Messaging pada huruf G.

### B. Kapan pemberitahuan muncul

| Kejadian | Penerima | Bunyi pemberitahuan |
| --- | --- | --- |
| Pengajuan baru masuk | ADMIN, ASS, WSS, SMST | Pengajuan Baru Perlu Diperiksa |
| Pengajuan disetujui | Pengirim pengajuan | Pengajuan Disetujui |
| Pengajuan ditolak | Pengirim pengajuan | Pengajuan Ditolak |
| Pemberitahuan dari website | Sesuai penerima | Mengikuti isi tabel notifications |

Contoh isi yang muncul pada layar HP:

```text
RTS Panel By Bene
Pengajuan Disetujui
Pengajuan "Ganti Alamat" untuk 107 PONSEL telah DISETUJUI.
Catatan: alamat sudah diperbarui
```

Pemberitahuan yang ditekan akan langsung membuka menu **Pemberitahuan** di
dalam aplikasi.

### C. Cara aplikasi memeriksa data

```text
Aplikasi terbuka            -> diperiksa setiap 2 menit
Aplikasi dibuka kembali     -> langsung diperiksa
Saat pemberitahuan ditekan  -> membuka menu Pemberitahuan
```

Yang **tidak** diberitahukan berulang: aplikasi menyimpan daftar hal yang
sudah pernah diberitahukan pada perangkat. Jadi satu pengajuan hanya
menghasilkan satu pemberitahuan, tidak berulang setiap pemeriksaan. Pada
pemeriksaan pertama setelah pemasangan, isi yang sudah ada hanya dicatat
tanpa diberitahukan, supaya layar HP tidak langsung penuh.

### D. Izin yang perlu diberikan

| Android | Perilaku |
| --- | --- |
| Android 13 ke atas | Android menampilkan kotak izin "Izinkan Notifikasi". Tekan **IZINKAN** |
| Android 12 ke bawah | Izin diberikan otomatis; aplikasi tetap menampilkan penjelasan lebih dahulu |

Aplikasi menampilkan penjelasan pada saat dashboard pertama dibuka:

```text
Aktifkan Pemberitahuan?
RTS Panel dapat mengirim pemberitahuan ke layar HP Anda:
  - Pengajuan baru yang perlu diperiksa
  - Pengajuan Anda disetujui atau ditolak
[NANTI]  [IZINKAN]
```

Izin dapat diatur ulang kapan saja pada **Pengaturan > Pemberitahuan HP**,
lengkap dengan tombol **IZINKAN PEMBERITAHUAN** dan
**KIRIM PEMBERITAHUAN PERCOBAAN**.

### E. Berkas dan langkah yang perlu dikerjakan

**1. `pubspec.yaml`** - tambahkan satu paket:

```yaml
  flutter_local_notifications: ^19.0.0
```

Bila sebelumnya Anda sudah menambahkan `workmanager: ^0.9.0`, **hapus baris
itu** agar build tidak gagal.

**2. `android/app/src/main/AndroidManifest.xml`** - tambahkan tiga baris ini
tepat di atas baris `<application`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
```

(Dua baris pertama mungkin sudah ada dari tahap sebelumnya. Cukup pastikan
ketiganya ada, jangan sampai dua kali.)

**3. Pengaturan Gradle** - paket pemberitahuan mewajibkan satu pengaturan
tambahan. Ikuti berkas `android_build_gradle_panduan.txt` pada workspace.
Tanpa langkah ini, build gagal dengan pesan
"requires core library desugaring to be enabled".

**4. `lib/main.dart`** - salin seluruh berkas versi terbaru.

**5. Tidak ada berkas API baru.** Endpoint `notifications.php` yang sudah
di-upload pada tahap sebelumnya sudah cukup.

**6. Pengaturan baterai pada HP (khusus Oppo, Realme, Vivo, Xiaomi):**

```text
Pengaturan HP > Baterai > RTS Panel > pilih "Tidak dibatasi" (Unrestricted)
Pengaturan HP > Aplikasi > RTS Panel > Izin > pastikan Notifikasi diizinkan
```

Pabrikan HP tersebut terkenal cepat mematikan aplikasi latar. Bila langkah ini
tidak dilakukan, pemberitahuan bisa berhenti masuk setelah aplikasi ditutup
lama oleh sistem.

### F. Cara menguji

1. Salin berkas, jalankan `flutter pub get`, lalu `flutter run`.
2. Setelah dashboard terbuka, muncul kotak **Aktifkan Pemberitahuan?**.
   Tekan **IZINKAN**, lalu izinkan bila Android menampilkan kotak izin.
3. Akan langsung muncul pemberitahuan percobaan pada bagian atas layar HP.
   Bila tidak terlihat, tarik sedikit ke bawah pada bagian atas layar HP untuk
   membuka panel pemberitahuan.
4. Buka **Pengaturan > Pemberitahuan HP**. Keterangannya harus bertulis
   "Pemberitahuan HP aktif".
5. Tekan **KIRIM PEMBERITAHUAN PERCOBAAN** untuk menguji ulang kapan saja.
6. Uji sungguhan: kirim pengajuan dari akun RTS, lalu login sebagai ADMIN.
   Dalam waktu paling lama 2 menit (aplikasi terbuka), lonceng berangka dan
   pemberitahuan HP akan masuk.
7. Uji aplikasi ditinggal: tekan tombol Home (jangan tutup paksa), tunggu
   beberapa menit, lalu periksa layar HP.

### G. Rencana tingkatan kedua (bila diperlukan)

Bila Anda menginginkan pemberitahuan yang **masuk dalam hitungan detik walau
aplikasi ditutup total**, itu memerlukan **Firebase Cloud Messaging**. Yang
perlu disiapkan:

1. Akun Google dan pembuatan proyek Firebase (gratis)
2. Berkas `google-services.json` dimasukkan ke folder `android/app`
3. Pengaturan pengiriman dari server (kunci layanan FCM disimpan pada
   `config.php`, tidak di aplikasi)

Kelebihan: pemberitahuan tiba seketika, tidak bergantung pada jadwal Android.
Kekurangan: ada layanan pihak ketiga, dan pengaturan awalnya lebih panjang.
Beri tahu saja bila ingin ditempuh; tingkatan pertama tetap dipakai sebagai
cadangan.

### H. Berkas build.gradle.kts yang sudah disesuaikan

Berkas milik Anda memiliki tiga masalah yang membuat build gagal:

| Masalah | Akibat |
| --- | --- |
| Ada dua blok `compileOptions` | Blok kedua membingungkan Gradle |
| Blok kedua memakai sintaks Groovy (`coreLibraryDesugaringEnabled true` tanpa tanda `=`) padahal berkasnya Kotlin DSL | Gradle gagal membaca berkas |
| Blok `dependencies { coreLibraryDesugaring(...) }` belum ada | Desugaring tetap gagal |

Berkas `build.gradle.kts.updated` pada workspace adalah berkas Anda yang sudah
diperbaiki:

1. Hanya ada **satu** blok `compileOptions`, berisi tiga baris:

```kotlin
compileOptions {
    isCoreLibraryDesugaringEnabled = true
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}
```

2. Ditambahkan `multiDexEnabled = true` pada `defaultConfig`.

3. Ditambahkan blok berikut di bagian paling bawah berkas:

```kotlin
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

4. Ditambahkan `id("kotlin-android")` pada blok `plugins`, karena blok
   `kotlin { compilerOptions { ... } }` pada berkas Anda memerlukannya.

Nama paket **tidak berubah**: `com.example.rts_panel_app`, sama seperti berkas
asli. Jadi aplikasi akan memperbarui yang sudah terpasang, bukan memasang
aplikasi kedua.

Cara pakai: simpan berkas lama sebagai `build.gradle.kts.lama`, lalu salin
seluruh isi `build.gradle.kts.updated` ke `build.gradle.kts`.

### I. Bila build masih gagal setelah workmanager dilepas

Gejala: pesan berikut masih muncul walau baris `workmanager` sudah dihapus
dari `pubspec.yaml`:

```text
Your app uses the following plugins that apply Kotlin Gradle Plugin (KGP): workmanager_android

GeneratedPluginRegistrant.java:49: error: cannot find symbol
      flutterEngine.getPlugins().add(new dev.fluttercommunity.workmanager.WorkmanagerPlugin());
```

Artinya paket itu **masih terbaca** oleh sistem build. Ada tiga tempat yang
harus bersih:

| Tempat | Isi | Cara membersihkan |
| --- | --- | --- |
| `pubspec.yaml` | daftar paket | `flutter pub remove workmanager` |
| `pubspec.lock` | versi paket yang terkunci | ikut diperbarui perintah di atas |
| `.flutter-plugins-dependencies` | daftar plugin untuk Android | ikut diperbarui perintah di atas |
| `android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java` | berkas yang dibuat otomatis | dihapus, akan dibuat ulang saat build |

Perintah lengkapnya (salin seluruhnya ke PowerShell):

```powershell
cd D:\Project\rts_panel_app

# 1. Buang paket beserta kunci versinya
flutter pub remove workmanager

# 2. Periksa: harus TIDAK ADA keluaran sama sekali
Select-String -Path pubspec.yaml,pubspec.lock,.flutter-plugins-dependencies `
  -Pattern workmanager -ErrorAction SilentlyContinue

# 3. Buang berkas turunan yang masih menyimpan daftar plugin lama
Remove-Item -Recurse -Force .dart_tool -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force android\app\src\main\java\io\flutter\plugins -ErrorAction SilentlyContinue

# 4. Ambil ulang paket dan bersihkan sisa build
flutter pub get
flutter clean
cd android
gradlew.bat --stop
cd ..

# 5. Jalankan
flutter run
```

Bila langkah 2 masih menampilkan baris, **jangan lanjut ke langkah 4**. Kirimkan
hasil keluarannya, karena berarti masih ada berkas lain yang menyimpan daftar
plugin.

Catatan: pesan `source value 8 is obsolete` dan `uses or overrides a deprecated
API` dari `geolocator` hanyalah peringatan, bukan penyebab build gagal dan
tidak perlu ditangani.

## 26. Halaman Profil dan Sinkronisasi

### A. Halaman Profil

Dibuka dari menu utama **Profil**. Isinya:

| Bagian | Keterangan |
| --- | --- |
| Kartu akun | Nama, username, role, dan district |
| Informasi Akun | Nama, username, role, hak persetujuan, level akses, salesman, district |
| Ganti Password | Tiga kolom password dan tombol GANTI PASSWORD |

**Cara ganti password:**

1. Isi **Password Lama**
2. Isi **Password Baru** (paling sedikit 6 karakter)
3. Isi **Ulangi Password Baru**
4. Tekan **GANTI PASSWORD**

Pengaman yang diperiksa aplikasi lebih dahulu:

| Keadaan | Tindakan |
| --- | --- |
| Ada kolom yang kosong | Ditolak |
| Password baru kurang dari 6 karakter | Ditolak |
| Ulangi password belum sama | Ditolak |
| Password baru sama dengan yang lama | Ditolak |

Pemeriksaan di server (tidak dapat dilewati dari HP):

| Keadaan | Balasan server |
| --- | --- |
| Password lama salah | "Password lama tidak sesuai." |
| Password baru kurang dari 6 karakter | "Password baru paling sedikit 6 karakter." |
| Password lama sama dengan yang baru | "Password baru tidak boleh sama dengan password lama." |

**Setelah password berhasil diganti:**

```text
Sesi pada HP ini          -> TETAP berlaku (tidak terlempar keluar)
Sesi pada perangkat lain  -> DIPUTUS, perlu login kembali
```

Ini penting untuk keamanan: bila password pernah diketahui orang lain, orang
tersebut langsung kehilangan akses pada perangkatnya tanpa mengganggu Anda.

Password disimpan memakai cara yang sama seperti login (`password_hash` dan
`password_verify`), sehingga password lama tetap dapat diverifikasi dan
password baru langsung berlaku pada website maupun aplikasi.

### B. Halaman Sinkronisasi

Dibuka dari menu utama **Sinkronisasi**.

| Bagian | Isi |
| --- | --- |
| Kartu server | Server aktif (Produksi/Staging), database, alamat API, dan kecepatan balasan dalam milidetik |
| Hasil Sinkronisasi | Waktu sinkron terakhir beserta jumlah Customer, Pengajuan, dan Pemberitahuan |
| Tombol | SINKRONKAN SEKARANG |

**Cara kerja.** Menekan tombol akan meminta data terbaru untuk tiga hal
sekaligus pada cakupan akun, lalu menyimpan hasilnya di perangkat:

```text
customers.php    -> jumlah customer pada cakupan
requests.php     -> jumlah pengajuan pada cakupan
notifications.php -> jumlah pemberitahuan
```

Waktu sinkron terakhir tersimpan di HP, jadi tetap terlihat walau aplikasi
ditutup dan dibuka kembali. Angka tersebut adalah jumlah data asli pada cakupan
akun, bukan perkiraan.

### C. Berkas yang perlu di-upload

Ke `public_html/api/`:

| Berkas | Keterangan |
| --- | --- |
| `change_password.php` | Baru - ganti password dari aplikasi |

Ke `lib/main.dart` pada PC: salin seluruh berkas versi terbaru.

**Tidak ada perubahan database** dan tidak ada izin Android tambahan.

### D. Cara menguji

**Profil:**

1. Buka menu **Profil**, periksa seluruh keterangan akun sudah benar.
2. Isi kolom password dengan **password lama yang salah**, tekan GANTI PASSWORD
   -> harus muncul "Password lama tidak sesuai."
3. Isi dengan password lama yang benar dan password baru yang berbeda,
   tekan GANTI PASSWORD -> berhasil.
4. Tekan **Keluar**, lalu login memakai **password baru**.
5. Bila sebelumnya akun ini pernah login di HP lain, HP tersebut harus login
   kembali.

**Sinkronisasi:**

1. Buka menu **Sinkronisasi**.
2. Tekan **SINKRONKAN SEKARANG**.
3. Periksa angka Customer, Pengajuan, dan Pemberitahuan terisi.
4. Tutup aplikasi, buka kembali, buka menu Sinkronisasi: waktu sinkron terakhir
   harus masih tertulis.

### E. Sisa pekerjaan yang belum ditutup

Beberapa hal dari tahap sebelumnya yang perlu penyelesaian:

| Hal | Keterangan |
| --- | --- |
| `dashboard_updated.php` | Belum dipastikan terpasang di produksi (pengganti `dashboard.php`) |
| `master_customer_updated.php` | Belum dipastikan terpasang di produksi |
| `notifications.php`, `request_action.php`, `request_create.php` | Perlu di-upload ulang bila sudah ada perubahan |
| `session_check.php`, `scope_check.php`, `change_password.php` | Berkas API baru |
| `env_check.php` | **Hapus** dari produksi setelah semua pengujian selesai. Kini **versi 4**: memeriksa 12 berkas API + 5 berkas halaman website (`berkas_website`) |
| Firebase (bagian 33) | Perlu dikerjakan: proyek Firebase, `google-services.json`, kunci server, SQL `rts_device_tokens`, lalu `PASANG_FIREBASE.ps1` |
| Salinan aman `inbox_updated.php` / `pengajuan_toko_updated.php` | Dipakai untuk mengganti isi berkas di server tanpa risiko terpotong (bagian 28). Jangan di-upload ke server |
| `dashboard_updated.php` (**revisi**) & `logout_updated.php` | Perbaikan ERR_TOO_MANY_REDIRECTS pada Dashboard dan tombol Keluar (bagian 29) — ganti isi `dashboard.php` dan `logout.php` |
| `dashboard.php` lama | Hapus salinannya, lalu ganti password database dan sesuaikan `config.php` |
| Frekuensi kunjungan (`kunjungan`) | **SELESAI** pada bagian 27: sudah ikut diterapkan saat pengajuan disetujui |
| Pemberitahuan dari website | `inbox.php` sudah memakai `rts_notify_email()` dari `auth.php`; tombol **Setujui Semua / Tolak Semua** baru dilengkapi pada bagian 27 |
| `inbox.php`, `pengajuan_toko.php`, `api/request_apply.php`, `api/request_create.php` | **Perlu di-upload ulang** setelah perbaikan frekuensi kunjungan (bagian 27) |
| `database/migrations/RTS_PANEL_CEK_KUNJUNGAN.sql` | Baru: pemeriksaan data lama kolom `kunjungan` (hanya membaca) |
| Pemberitahuan saat aplikasi ditutup sepenuhnya | Perlu Firebase Cloud Messaging (bagian 25 huruf G) |

---

## BAGIAN 27 — FREKUENSI KUNJUNGAN PADA HALAMAN PENGAJUAN WEBSITE

Bagian ini menyelaraskan **website** dengan **aplikasi Android** supaya kolom
**Frekuensi Kunjungan** (`kunjungan`) pada Master Customer terisi dengan benar,
baik pengajuan itu disetujui dari aplikasi maupun dari website.

**Berkas yang diperbaiki pada bagian ini:**

| Berkas | Tempat upload | Yang diperbaiki |
| --- | --- | --- |
| `pengajuan_toko.php` | `public_html/` | Pilihan **Week (Minggu)** diganti menjadi **Frekuensi Kunjungan**; label **Rute Kunjungan** dipertegas menjadi **Hari Kunjungan** (isian nama hari tidak berubah) |
| `inbox.php` | `public_html/` | Frekuensi ikut diterapkan saat pengajuan disetujui + label Hari/Frekuensi pada modal edit + pemberitahuan pada tombol Setujui Semua |
| `api/request_apply.php` | `public_html/api/` | Sama seperti `inbox.php`, karena inilah yang dipakai saat approve dari aplikasi |
| `api/request_create.php` | `public_html/api/` | Keterangan isian pada bagian atas berkas (komentar, bukan kode) |

Aplikasi Android **tidak perlu di-build ulang** untuk bagian ini. Aplikasi sudah
mengirim nilai `week` berisi **Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap**;
yang kurang hanya sisi website.

### A. Sebelumnya salah di mana

Ada **dua** kolom yang berbeda, dan keduanya pernah memakai sumber yang sama:

| Kolom | Arti | Isi yang benar |
| --- | --- | --- |
| `hari` | Hari kunjungan | Senin, Selasa, ... Sabtu |
| `kunjungan` | Frekuensi kunjungan | Weekly, Bi-Weekly Ganjil, Bi-Weekly Genap |

**1) Halaman pengajuan website** masih menanyakan **Week (Minggu)** dengan
pilihan **Ganjil / Genap**, sehingga sales tidak pernah bisa memilih **Weekly**.

**2) Saat pengajuan** *Tambah Baru* **disetujui**, kolom `kunjungan` diisi dari
`rute_kunjungan` — dan `rute_kunjungan` berisi **nama hari**. Akibatnya Master
Customer menyimpan nama hari (misalnya "Senin") pada kolom `kunjungan`, padahal
isinya seharusnya frekuensi.

**3) Saat pengajuan** *Ganti Nama* **atau** *Ganti Alamat* **disetujui**, kolom
`kunjungan` **tidak ikut diperbarui** sama sekali, walaupun sales sudah memilih
frekuensi pada form pengajuan.

Akibat lanjutan yang paling terasa: kolom **Hari** pada Master Customer terisi
nama hari, sementara **Frekuensi** tetap seperti data lama.

### B. Yang sekarang berlaku

Setiap persetujuan pengajuan akan menerapkan **tujuh** hal sekaligus:

| Jenis pengajuan | Yang diterapkan ke Master Customer |
| --- | --- |
| Tambah Baru | nama toko, ID customer, kategori (REGULER/GSP), salesman, alamat, **frekuensi (`kunjungan`)**, **hari**, district |
| Ganti Nama | nama toko, tipe, hari, district, **frekuensi** |
| Ganti Alamat | alamat, tipe, hari, district, **frekuensi** |
| Hapus Toko | diarsipkan ke `master_toko_deleted` lalu dihapus dari `master_toko` |

Aturan perubahan nilai frekuensi:

| Nilai pada pengajuan | Disimpan ke kolom `kunjungan` |
| --- | --- |
| `Weekly` | `Weekly` |
| `Bi-Weekly Ganjil` | `Bi-Weekly Ganjil` |
| `Bi-Weekly Genap` | `Bi-Weekly Genap` |
| `Ganjil` (pengajuan lama) | `Bi-Weekly Ganjil` |
| `Genap` (pengajuan lama) | `Bi-Weekly Genap` |
| Kosong / tidak dikenali | **tidak diubah** (Master Customer dibiarkan seperti semula) |

Catatan penting untuk **Ganti Nama / Ganti Alamat**: karena pengajuan dibuat
dari aplikasi, kolom `hari` dan `kunjungan` terisi dari centang yang dibuka
sales pada form. Sales sebaiknya hanya mencentang kolom yang benar-benar ingin
diubah.

### C. Cara memasang (jangan terlewat)

> **PENTING:** `pengajuan_toko.php` dan `inbox.php` **sudah ada di server**,
> jadi **jangan menyalin dari panel Diff** — baris yang tidak berubah akan ikut
> terpotong dan halaman menjadi **HTTP ERROR 500**. Pakai salinan aman
> `pengajuan_toko_updated.php` / `inbox_updated.php`, atau ekstrak dari
> `RTS_PANEL_FREKUENSI_KUNJUNGAN.zip`. Penjelasan lengkap: **bagian 28**.

> Letak berkas: halaman website ada di **`public_html/`**, berkas API ada di
> **`public_html/api/`**. Keduanya berbeda folder.

1. Masuk cPanel → **File Manager**.
2. Upload berkas berikut ke **`public_html/`** (timpa berkas lama):
   - `pengajuan_toko_updated.php` → ganti isi `pengajuan_toko.php`
   - `inbox_updated.php` → ganti isi `inbox.php`

   (Salinan `_updated` dipakai supaya isinya tampil utuh di panel — lihat bagian 28.)
3. Masuk folder **`public_html/api/`**, upload (timpa berkas lama):
   - `request_apply.php`
   - `request_create.php`
4. Buka `https://rts.benedic-s.com/api/env_check.php` — pada bagian
   pemeriksaan berkas API, `request_apply.php` dan `request_create.php` harus
   bernilai `true`.
5. **Hapus `env_check.php`** dari server setelah semua pemeriksaan selesai.

Lakukan hal yang sama pada staging (`coba.benedic-s.com`) bila ingin diuji di
staging lebih dahulu.

### D. Cara menguji

**Uji 1 — halaman pengajuan website:**

1. Login ke website sebagai sales → buka menu **Pengajuan**.
2. Pada bagian pelengkap form, kolom **Hari Kunjungan** harus berisi pilihan
   nama hari (Senin s/d Sabtu) dan kolom di sebelahnya harus tertulis
   **Frekuensi Kunjungan** dengan pilihan **Weekly / Bi-Weekly Ganjil /
   Bi-Weekly Genap**.
3. Isi pengajuan **Tambah Baru**, pilih Frekuensi **Bi-Weekly Ganjil**, kirim.

**Uji 2 — persetujuan dari website:**

4. Login sebagai ADMIN → buka **Pengajuan** → temukan pengajuan tadi →
   tekan **Setujui**.
5. Buka **Master Customer** → cari toko tersebut → kolom **Hari** berisi nama
   hari, kolom **Frekuensi** berisi **Bi-Weekly Ganjil**.

**Uji 3 — persetujuan dari aplikasi Android:**

6. Dari aplikasi, buat pengajuan **Ganti Nama** pada satu customer uji, centang
   kolom **Nama Toko** saja, lalu pada **Frekuensi Kunjungan** pilih
   **Weekly**.
7. Login website sebagai ADMIN → **Setujui** pengajuan itu.
8. Periksa Master Customer: nama toko berubah **dan** Frekuensi berubah menjadi
   **Weekly**.

**Uji 4 — tombol Setujui Semua:**

9. Kirim dua pengajuan sekaligus dari aplikasi (misalnya dua **Ganti Alamat**).
10. Di website, centang keduanya → tekan **Setujui Semua**.
11. Buka aplikasi pada HP yang mengirim → menu **Pemberitahuan**: harus muncul
    dua pemberitahuan status *Disetujui*.

### E. Memeriksa data lama

Perbaikan kode **tidak** otomatis memperbaiki customer lama yang kolom
`kunjungan`-nya sudah berisi nama hari. Untuk memeriksanya, jalankan berkas:

```
database/migrations/RTS_PANEL_CEK_KUNJUNGAN.sql
```

Cara mudah: buka **cPanel → phpMyAdmin → pilih database → tab SQL** → salin
seluruh isi berkas → **GO**.

Berkas itu **hanya membaca** (tidak mengubah apa pun), dan akan menampilkan:

1. Ringkasan nilai kolom `kunjungan` beserta jumlah tokonya.
2. Daftar customer yang perlu diperiksa (yang masih berisi nama hari).
3. Angka jumlah customer yang terpengaruh.
4. Jenis/tipe kolom `week` dan `kunjungan`.

- Bila **angka pada poin 3 = 0** → tidak ada yang perlu dikerjakan.
- Bila **lebih dari 0** → jangan langsung diperbaiki. Tentukan dulu nilai
  frekuensi yang benar (lihat kolom `week` pada tabel `pengajuan_sales` untuk
  customer tersebut), buat **backup database**, baru lakukan perbaikan.

**Pemeriksaan jenis kolom (bagian 4) — penting untuk pengajuan baru dari aplikasi:**

Nilai **Bi-Weekly Ganjil** panjangnya 16 huruf, jadi kolomnya harus cukup muat.
Cara paling cepat memeriksanya di phpMyAdmin:

1. Buka tabel **`pengajuan_sales`** → tab **Struktur** → cari baris **`week`**.
2. Buka tabel **`master_toko`** → tab **Struktur** → cari baris **`kunjungan`**.

| Yang terlihat | Artinya |
| --- | --- |
| `varchar(20)` atau lebih | Aman, tidak perlu diubah |
| `varchar` kurang dari 20 | Nilai frekuensi bisa terpotong → jalankan **bagian 5** berkas SQL |
| `enum('Ganjil','Genap')` | Pengajuan baru dari aplikasi **berisiko gagal terkirim** → jalankan **bagian 5** berkas SQL |

**Bagian 5** pada berkas SQL berisi perintah `ALTER TABLE` yang sudah disiapkan,
tetapi **sengaja dinonaktifkan** (diberi tanda komentar). Jalankan hanya setelah
**backup database** dan sebaiknya diuji dulu pada database staging. Bila hasil
pemeriksaan bagian 4 tidak sesuai harapan, kirimkan hasilnya ke saya — saya
siapkan perintah penyesuaian yang khusus untuk kondisi database Bapak.

### F. Catatan

- Perbaikan ini **tidak mengubah tampilan** halaman Pengajuan lain; hanya
  pilihan Week (Minggu) yang berubah nama dan isinya.
- Pada modal **Edit Pengajuan** di `inbox.php`, pilihan frekuensi ikut memuat
  **Ganjil** dan **Genap** agar pengajuan lama tetap dapat dibetulkan tanpa
  kehilangan datanya.
- Kolom `kunjungan` **wajib ada** pada `master_toko` — sama seperti sebelumnya,
  karena jalur *Tambah Baru* memang sudah selalu menulis kolom itu. Periksa
  dengan **bagian 4** pada berkas SQL di atas: kolom harus ada dan sebaiknya
  minimal `VARCHAR(20)` agar **Bi-Weekly Ganjil** (16 huruf) muat.
- Bila nilai frekuensi pada pengajuan **kosong atau tidak dikenali** (misalnya
  karena kolom `week` bertipe pendek seperti `ENUM('Ganjil','Genap')`), maka
  kolom frekuensi pada Master Customer **tidak diubah**; kolom lain (nama,
  alamat, hari, district) tetap diperbarui dan pengajuan tetap dapat disetujui.
  Jadi tidak ada pengajuan yang gagal hanya karena frekuensinya kosong.

---

## BAGIAN 28 — PENTING: CARA MENYALIN BERKAS DARI PANEL AGAR TIDAK ERROR 500

### A. Apa yang terjadi

Saat Bapak menyalin isi berkas dari panel **Diff**, panel itu **menyembunyikan
baris yang tidak berubah**. Baris tersembunyi ditandai tulisan seperti
**"1 unmodified line"** atau **"11 unmodified lines"**.

Akibatnya, yang tersalin **hanya baris yang berubah** — bukan isi berkas secara
utuh. Di server, berkas itu lalu menjadi berkas yang **tidak lengkap** (dan
beberapa baris lama ikut tersalin ulang), sehingga PHP gagal membacanya dan
muncul **HTTP ERROR 500**.

Contoh nyata yang ditemukan pada `inbox.php` di server:

```
if (!$is_admin) {                     <-- baris LAMA yang seharusnya sudah dihapus
// Terapkan pengajuan customer ...    <-- baris baru menempel tidak pada tempatnya
```

Halaman yang terkena akan menampilkan "This page isn't working — HTTP ERROR 500".

**Jadi bukan kode di berkasnya yang salah, melainkan cara menyalinnya.**

### B. Aturan baru (WAJIB dipakai mulai sekarang)

| Keadaan berkas | Cara menyalin yang benar |
| --- | --- |
| Berkas **BARU** dari saya (nama berakhiran `_updated`, `_check`, atau berkas yang belum pernah ada di server) | **Aman** disalin seluruhnya dari panel, karena semua barisnya tampil sebagai penambahan |
| Berkas yang **SUDAH ADA di server** (mis. `inbox.php`, `pengajuan_toko.php`) | **JANGAN** disalin dari panel Diff — pasti terpotong. Pakai salah satu cara aman di bawah |

**Dua cara aman:**

1. **Unggah lewat File Manager (paling disarankan).**
   Unduh `RTS_PANEL_FREKUENSI_KUNJUNGAN.zip` → upload ke `public_html/` →
   klik kanan → **Extract**. Semua berkas masuk ke folder yang benar tanpa
   menyalin satu per satu.

2. **Salin dari berkas salinan aman.**
   Untuk berkas yang sudah ada di server, saya sediakan salinannya dengan nama
   tambahan `_updated`. Contoh: `inbox_updated.php` adalah salinan utuh dari
   `inbox.php`. Karena berkas ini baru, panel menampilkan **seluruh isinya**
   tanpa baris tersembunyi.

   Langkahnya:
   - Buka berkas salinan itu di panel (mis. `inbox_updated.php`).
   - Salin **seluruh** isinya.
   - Di cPanel, buka berkas aslinya (mis. `inbox.php`) → **Edit** → pilih semua
     (Ctrl+A) → hapus → tempel isi tadi → **Save Changes**.
   - Berkas salinan **tidak perlu** di-upload ke server; fungsinya hanya untuk
     disalin.

### C. Cara memastikan berkas di server sudah lengkap

**Cara 1 — dari cPanel.** Buka **File Manager → `public_html`** dan bandingkan
**kolom Size**:

| Berkas | Baris yang benar | Ukuran yang benar |
| --- | --- | --- |
| `inbox.php` | 535 | 42.401 byte |
| `pengajuan_toko.php` | 288 | 14.425 byte |
| `api/request_apply.php` | 362 | 11.470 byte |
| `api/request_create.php` | 291 | 8.146 byte |

Kalau ukurannya jauh lebih kecil (misalnya 8 KB untuk `inbox.php`), berarti
berkasnya terpotong → ganti dengan isi yang lengkap.

**Cara 2 — dari `api/env_check.php` (versi 4).** Buka
`https://rts.benedic-s.com/api/env_check.php`. Sekarang ada bagian
**`berkas_website`** yang memeriksa halaman di `public_html`:

```json
"berkas_website": {
    "inbox.php": { "ada": true, "baris": 535, "harusnya": 535, "status": "COCOK" },
    "pengajuan_toko.php": { "ada": true, "baris": 288, "harusnya": 288, "status": "COCOK" }
}
```

- `status: COCOK` → berkas lengkap.
- `status: PERIKSA (jumlah baris tidak sama)` → berkas terpotong, ganti dengan
  isi yang lengkap.
- `ada: false` → berkas belum ada di `public_html`.

### D. Memulihkan halaman yang sekarang error 500

1. Buka `api/env_check.php` versi 4 untuk melihat **berkas mana** yang terpotong.
2. Untuk setiap berkas yang `status`-nya bukan `COCOK`:
   - buka salinan aman yang sesuai (`inbox_updated.php`,
     `pengajuan_toko_updated.php`) atau ekstrak dari zip;
   - timpa isi berkas di server dengan isi yang lengkap;
   - simpan.
3. Buka kembali halaman yang tadi error.
4. Kalau masih error 500, buka **cPanel → Metrics → Errors** (atau file
   `error_log` di `public_html`) dan kirimkan 5 baris terakhirnya ke saya —
   di situ tertulis nama berkas dan nomor baris penyebabnya.

### E. Berkas mana yang berisiko dan mana yang aman

| Berkas | Dibuat kapan | Aman disalin dari panel Diff? |
| --- | --- | --- |
| `inbox.php` | sudah ada sejak awal | **TIDAK** — pakai `inbox_updated.php` |
| `pengajuan_toko.php` | sudah ada sejak awal | **TIDAK** — pakai `pengajuan_toko_updated.php` |
| `api/request_apply.php`, `api/request_create.php`, `api/env_check.php` | baru | Aman |
| `header.php`, `sidebar.php`, `notifications.php` | baru (versi rts-shell) | Aman |
| `dashboard_updated.php`, `master_customer_updated.php` | baru | Aman |
| `main.dart`, berkas Gradle | baru | Aman |

Catatan: `dashboard_updated.php` dan `master_customer_updated.php` memang
sengaja diberi nama `_updated` supaya **seluruh isinya tampil** di panel dan
aman disalin, lalu di server diganti namanya menjadi `dashboard.php` dan
`master_customer.php`.

---

## BAGIAN 29 — MEMPERBAIKI DASHBOARD BERPUTAR & TOMBOL KELUAR (ERR_TOO_MANY_REDIRECTS)

### A. Gejalanya

| Yang dikerjakan | Yang muncul |
| --- | --- |
| Buka menu **Dashboard** | *This page isn't working — ERR_TOO_MANY_REDIRECTS* |
| Tekan tombol **Keluar** | Error yang sama |

Halamannya **berputar-putar** (browser terus mengalihkan), bukan loading terus.

### B. Penyebabnya

1. `auth.php` menyediakan fungsi `rts_require_login()`. Fungsi ini dipakai
   semua halaman untuk memeriksa sesi, dan bila pengunjung **belum login**,
   fungsi itu mengalihkan ke **`dashboard.php`**.

   Cara ini benar pada desain **lama**, karena dahulu `dashboard.php` memang
   halaman login (halaman lama itu memuat form login sendiri).

2. Setelah `dashboard.php` diganti dengan versi baru (bagian 22), halaman itu
   **tidak lagi memuat form login** — ia hanya boleh dibuka oleh pengguna yang
   sudah login, dan bila belum login ia memanggil `rts_require_login()`,
   yaitu meminta **dialihkan ke `dashboard.php`**.

3. Hasilnya berputar tanpa henti:

```
dashboard.php  ->  rts_require_login()  ->  dashboard.php  ->  dashboard.php  ->  ...
(browser berhenti dan menampilkan: ERR_TOO_MANY_REDIRECTS)
```

Tombol **Keluar** memicu gejala yang sama karena `logout.php` lama menghapus
sesi lalu mengalihkan ke `dashboard.php` — dan setelah sesi hilang,
`dashboard.php` menolak membuka diri.

Urutan yang sama juga menerpa halaman yang belum login: `inbox.php`,
`master_customer.php`, `notifications.php`, dan seterusnya. Karena itu, saat
staging maupun produksi dibuka tanpa login, halaman-halaman itu ikut berputar.

### C. Yang diperbaiki (2 berkas)

| Berkas | Ganti nama di server menjadi | Isi perbaikan |
| --- | --- | --- |
| `dashboard_updated.php` | `dashboard.php` | Penjagaan sesi **tidak lagi** memakai `rts_require_login()` dari `auth.php`. Halaman punya penjaga sendiri yang mengalihkan pengunjung belum login ke **`index.php`** (halaman login). Tidak ada lagi pengalihan ke diri sendiri |
| `logout_updated.php` | `logout.php` | Setelah sesi dihapus, pengalihan diarahkan ke **`index.php`**. Cara menghapus sesi dan cookie tidak diubah |

**Penting:** perbaikan pada `dashboard.php` saja sudah memutus putaran itu untuk
**semua halaman**. Sebab, halaman lain meminta dialihkan ke `dashboard.php`,
dan `dashboard.php` kini meneruskan ke halaman login — tidak berputar lagi.

`auth.php` **tidak perlu diubah** untuk perbaikan ini. (Kalau nanti ingin
dirapikan sampai ke akarnya, kirimkan isi `auth.php` ke saya — satu barisnya
cukup diubah dari `dashboard.php` menjadi `index.php`.)

### D. Cara memasang

1. Pakai berkas salinan `dashboard_updated.php` dan `logout_updated.php`, atau
   ekstrak dari `RTS_PANEL_LOGIN_REDIRECT_FIX.zip`.
2. Di cPanel `public_html`:
   - ganti isi **`dashboard.php`** dengan isi **`dashboard_updated.php`**;
   - ganti isi **`logout.php`** dengan isi **`logout_updated.php`**.
3. Selesai — nama berkas di server tetap `dashboard.php` dan `logout.php`.

Kedua berkas ini **berkas baru** di sesi ini, jadi seluruh isinya tampil di
panel dan aman disalin (lihat bagian 28).

### E. Cara menguji

1. **Uji tanpa login** (buka jendela penyamaran / *incognito*):
   buka `https://rts.benedic-s.com/dashboard.php` → harus **langsung tampil
   halaman login**, bukan error berputar.
   Ulangi untuk `inbox.php`, `master_customer.php`, `notifications.php` —
   semuanya harus menampilkan halaman login.
2. **Uji login**: masuk memakai akun ADMIN → menu **Dashboard** harus tampil
   normal beserta kartu Total Customer / Customer Aktif / Total GSP /
   Pengajuan Pending.
3. **Uji Keluar**: tekan tombol **Keluar** → harus langsung kembali ke halaman
   login, tanpa error.
4. **Uji sesi habis**: setelah keluar, tekan tombol Back pada browser lalu buka
   menu apa pun → harus kembali ke halaman login.

### F. Catatan

- Perbaikan ini **tidak mengubah** isi dashboard, kartu angka, atau cakupan
  role — hanya cara halaman menjaga sesi.
- Halaman `akun.php` dari desain lama memanggil `header("Location: ...")`
  setelah `header.php` mencetak HTML, sehingga pengalihannya sering gagal dan
  halaman tetap tampil walau belum login. Bila ingin dirapikan, beri tahu saya.

---

## BAGIAN 30 — SKRIP OTOMATIS: BERSIHKAN BUILD LALU JALANKAN DI HP

Bagian 25 huruf I menjelaskan pembersihan `workmanager` secara manual. Karena
langkahnya banyak, sekarang tersedia skrip yang mengerjakannya otomatis:

**Berkas:** `PERBAIKI_DAN_JALANKAN.ps1`

### Cara pakai

1. Di VS Code, buat berkas baru di dalam folder proyek
   `D:\Project\rts_panel_app` dengan nama **`PERBAIKI_DAN_JALANKAN.ps1`**,
   lalu tempelkan seluruh isinya.
2. Buka terminal VS Code (**Terminal > New Terminal**).
3. Jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\PERBAIKI_DAN_JALANKAN.ps1
```

### Yang dikerjakan skrip (berurutan)

| Langkah | Tindakan |
| --- | --- |
| 1 | Memeriksa `workmanager` di `pubspec.yaml`; bila masih ada, dijalankan `flutter pub remove workmanager` |
| 2 | Memeriksa sisa nama `workmanager` pada `pubspec.yaml`, `pubspec.lock`, dan `.flutter-plugins-dependencies` (penyebab error `WorkmanagerPlugin`) |
| 3 | Menghapus `build`, `.dart_tool`, `android\.gradle`, dan `android\app\src\main\java\io\flutter\plugins` |
| 4 | `flutter pub get` |
| 5 | `flutter clean` lalu `flutter pub get` |
| 6 | `gradlew.bat --stop` (menghentikan Gradle yang masih hidup) |
| 7 | Menampilkan `flutter devices` |
| 8 | `flutter run -d CPH1937` |

### Aman dijalankan

Skrip hanya menghapus berkas sementara (build/cache). Kode program, `lib/`,
`assets/`, dan berkas Gradle **tidak diubah maupun dihapus**.

### Bila masih gagal

Salin **20 baris pertama yang berwarna merah** dan kirimkan ke saya. Biasanya
penyebabnya salah satu dari:

| Pesan | Artinya |
| --- | --- |
| `cannot find symbol WorkmanagerPlugin` | Masih ada sisa pendaftaran plugin — biasanya dari folder `android\app\src\main\java\io\flutter\plugins` yang belum terhapus |
| `requires core library desugaring` | `build.gradle.kts` belum memakai versi di `build.gradle.kts.updated` |
| `different roots` (Kotlin) | `gradle.properties.updated` belum dipakai, atau Gradle masih berjalan |
| `No connected devices` | Kabel USB belum terbaca — coba `flutter devices` lalu pasang ulang kabel / aktifkan USB debugging |

---

## BAGIAN 31 — BUILD SUDAH BERHASIL, TINGGAL PEMASANGAN KE HP

### A. Kabar baik: masalah build sudah selesai

Keluaran `flutter run` yang terakhir berbunyi:

```
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

Artinya aplikasi **berhasil dibangun**. Peringatan `workmanager_android` **sudah
tidak muncul lagi** — pembersihan pada bagian 25 huruf I dan skrip
`PERBAIKI_DAN_JALANKAN.ps1` berhasil.

Peringatan yang masih tampil **tidak menghalangi** dan tidak perlu ditangani
sekarang:

| Peringatan | Arti |
| --- | --- |
| Kotlin Gradle Plugin / *Built-in Kotlin* | Peringatan untuk versi Flutter **yang akan datang**. Aplikasi tetap berjalan hari ini. Nanti bila perlu, kita ikuti panduan resmi Flutter |
| `source value 8 is obsolete` | Sisa pengaturan lama; aman |
| `geolocator ... deprecated API` | Catatan dari paket pihak ketiga; aman |
| `23 packages have newer versions` | Pemberitahuan biasa, bukan error |

### B. Yang gagal: pemasangan ke HP

```
adb.exe: device 'adb-9909f35e-..._adb-tls-connect._tcp' not found
Error: ADB exited with exit code 1
Error launching application on CPH1937 (wireless).
```

Penyebabnya: HP tersambung **secara nirkabel** (`wireless`). Koneksi nirkabel
sering **terputus di tengah jalan** ketika proses build memakan waktu lama
(build tadi memerlukan 622 detik / sekitar 10 menit). Saat build selesai dan
waktunya memasang aplikasi, sambungan itu sudah hilang.

Jadi aplikasinya **tidak rusak** — hanya belum sampai ke HP.

### C. Cara memasang: `PASANG_DI_HP.ps1`

Berkas APK sudah jadi, jadi tidak perlu build ulang. Tersedia skrip pemasang:

1. Sambungkan HP ke komputer memakai **kabel USB** (lebih stabil).
   Pada layar HP, pilih mode **Transfer File**, lalu setujui
   *"Izinkan penelusuran USB?"*.
2. Simpan berkas **`PASANG_DI_HP.ps1`** di `D:\Project\rts_panel_app`.
3. Jalankan di terminal VS Code:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_DI_HP.ps1
```

Yang dikerjakan skrip:

| Langkah | Tindakan |
| --- | --- |
| 1 | Memulai ulang ADB (`adb kill-server` lalu `adb start-server`) |
| 2 | Menampilkan daftar perangkat; bila tidak ada, memberi petunjuk perbaikan |
| 3 | Mencari `build\app\outputs\flutter-apk\app-debug.apk` (bila belum ada, dibangun ulang otomatis) |
| 4 | Memasang APK ke HP (`adb install -r`) |
| 5 | Membuka aplikasi RTS Panel di HP (`com.example.rts_panel_app`) |

Setelah muncul tulisan **"Pemasangan berhasil"**, aplikasi langsung terbuka di
HP dan siap dipakai.

### D. Cara alternatif (tanpa skrip)

1. Cari berkas `build\app\outputs\flutter-apk\app-debug.apk` di komputer.
2. Salin berkas itu ke HP (lewat kabel USB atau Google Drive).
3. Di HP, buka **File Manager** → tekan berkas `app-debug.apk` →
   *Instal* / *Setuju*.

Cara ini paling sederhana bila kabel USB bermasalah.

### E. Bila ingin memakai `flutter run` (untuk hot reload)

`flutter run` berguna saat mengembangkan aplikasi, karena perubahan kode
langsung terlihat tanpa pasang ulang.

```powershell
flutter devices     # pastikan terbaca "CPH1937 (mobile)" TANPA kata wireless
flutter run
```

**Saran:** pakai kabel USB. Bila tetap ingin nirkabel:

1. Pada HP: **Opsi Pengembang → Penelusuran nirkabel** → *Pasangkan perangkat
   dengan kode*.
2. Di komputer: `adb pair <ip>:<port>` lalu masukkan kode dari HP.
3. Baru jalankan `flutter run`.

Ingat: nirkabel harus dipasangkan ulang setiap kali HP atau komputer
dinyalakan ulang.

### F. Catatan tentang "112 problems" di VS Code

Angka pada panel **Problems** tidak menghalangi pembuatan aplikasi. Build tetap
berhasil. Bila Bapak ingin, kirimkan tangkapan layarnya — saya periksa mana yang
perlu dibersihkan dan mana yang hanya catatan biasa.

### G. Ringkasan status tahap ini

| Bagian | Status |
| --- | --- |
| Build aplikasi Android | **BERHASIL** |
| Pemasangan ke HP | Menunggu `PASANG_DI_HP.ps1` dijalankan |
| Uji alur (login, pengajuan, notifikasi) | Setelah aplikasi terpasang di HP |

---

## BAGIAN 32 — DAFTAR PERIKSA PENGUJIAN APLIKASI

Aplikasi sudah berhasil dibangun dan terpasang di HP. Tahap berikutnya adalah
**pengujian menyeluruh** supaya setiap bagian dipastikan bekerja pada data
nyata.

**Berkas:** `UJI_APLIKASI.md`

Berkas itu berisi **8 bagian dan 50 butir pengujian** dengan kolom centang:

| Bagian | Isi | Jumlah butir |
| --- | --- | --- |
| A | Login & sesi (Ingat Saya, Keluar, ganti server) | 6 |
| B | Tampilan Dashboard (angka, cakupan role, tanpa teks terpotong) | 4 |
| C | Master Customer (cakupan role, filter GSP, tombol peta) | 5 |
| D | **Pengajuan** (FAB, pemilih customer, Hari & Frekuensi, koordinat, approve) | 13 |
| E | Notifikasi di layar HP (izin, percobaan, pengajuan baru, approve) | 8 |
| F | Profil, ganti password, Sinkronisasi | 5 |
| G | Keselarasan aplikasi ↔ website | 5 |
| H | Keamanan & kebersihan (berkas utuh, hapus alat uji, repo private, password DB) | 4 |

Urutan yang disarankan: **A & B** dulu (±10 menit), lalu **D** (paling penting),
lalu **E**, sisanya kapan saja.

Cara melaporkan hasil ada di bagian akhir berkas: cukup sebutkan **nomor butir**
yang gagal beserta tangkapan layarnya.

### Keadaan staging yang perlu diperhatikan

Pemeriksaan `https://coba.benedic-s.com/api/env_check.php` menunjukkan staging
masih memakai **`env_check.php` versi lama** (belum ada bagian `berkas_api`).
Jadi staging **belum tentu** memuat seluruh 12 berkas API terbaru.

Saran: **uji di server produksi** lebih dahulu (sesuai pengujian yang sudah
berjalan), dan bila ingin memakai staging, unggah `api/env_check.php` versi 4 ke
staging untuk memeriksa berkas mana yang belum ada di sana.

---

## BAGIAN 33 — PEMBERITAHUAN HP WALAU APLIKASI DITUTUP (FIREBASE)

### A. Hasil akhir yang akan dicapai

| Keadaan aplikasi | Sebelumnya | Setelah Firebase |
| --- | --- | --- |
| Aplikasi sedang dibuka | Pemberitahuan masuk | Pemberitahuan masuk (**sama**) |
| Aplikasi di latar belakang (di-minimize) | Masuk dalam ±2 menit | **Masuk segera** |
| Aplikasi **ditutup total** dari daftar aplikasi | **Tidak masuk** | **Masuk segera** |
| HP dikunci / layar mati | Masuk dalam ±2 menit | **Masuk segera** |
| Aplikasi dihentikan paksa (Force stop) dari Pengaturan | Tidak masuk | Tidak masuk (batasan Android) |

Pemberitahuan yang dikirim: **pengajuan baru** (ke ADMIN & ASS), **disetujui** dan
**ditolak** (ke pengirim pengajuan), baik yang diproses dari aplikasi maupun
dari website.

### B. YANG HARUS BAPAK KERJAKAN DI FIREBASE CONSOLE

Bagian ini **hanya bisa dikerjakan Bapak** (perlu akun Google). Ikuti berurutan.

### B0. DUA HAL YANG SERING KELIRU SAAT MEMBUAT PROYEK FIREBASE

#### B0.1 — "Project name" BUKAN nama paket aplikasi

Saat membuat proyek, kolom **Project name** hanya nama tampilan pada layar
Firebase Console. Isinya:

| Benar | Salah |
| --- | --- |
| `RTS Panel` | `com.example.rts_panel_app` |
| `RTS Panel By Bene` | apa pun yang memakai titik |

Aturan isian **Project name**: hanya **huruf, angka, spasi**, dan tanda
`- ' !"`. Titik (`.`) dan garis bawah (`_`) **tidak diperbolehkan**.

**Nama paket** `com.example.rts_panel_app` diisi **NANTI**, pada langkah lain:
*Add app* → pilih **Android** → kolom **Android package name**.

Urutan yang benar:

```
Langkah 1 : Create a project   -> Project name: RTS Panel
Langkah 2 : Add app > Android  -> Android package name: com.example.rts_panel_app
Langkah 3 : Download google-services.json
```

**Project ID** dibuat otomatis oleh Google (contoh: `rts-panel-4f8a2`). Tidak
perlu sama dengan apa pun - biarkan saja sesuai saran Google.

#### B0.2 — "You've reached the project limit for your account"

Pesan ini **bukan kesalahan Bapak**. Akun Google gratis hanya boleh memiliki
sejumlah proyek tertentu (jumlahnya berbeda tiap akun). Pesan ini muncul bila
jatah itu sudah habis - termasuk bila ada proyek lama yang pernah dihapus,
karena proyek yang dihapus **masih dihitung sampai sekitar 30 hari**.

Ada empat jalan keluar. Pilih yang paling sesuai:

| Pilihan | Caranya | Waktu |
| --- | --- | --- |
| **1. Pakai proyek Firebase yang sudah ada** (paling cepat) | Buka console.firebase.google.com. Bila sudah ada kartu proyek, klik proyek itu, lalu *Add app* → Android → isi nama paket. Tidak perlu membuat proyek baru | 5 menit |
| **2. Pakai akun Google lain** (paling cepat juga) | Keluar dari akun Google sekarang, masuk memakai akun Google lain (mis. akun email kantor), lalu buat proyek di sana | 10 menit |
| **3. Minta penambahan jatah** | Pada pesan merah itu tekan **Request an increase**, isi alasan singkat (mis. "Untuk aplikasi internal perusahaan"), kirim | Menunggu persetujuan Google (bisa berhari-hari) |
| **4. Hapus proyek lama lalu tunggu** | Hapus proyek yang tidak dipakai di Firebase Console, lalu tunggu sekitar 30 hari | Lama, tidak disarankan |

**Catatan:** satu proyek Firebase boleh memuat **beberapa aplikasi**. Jadi bila
sudah ada proyek milik aplikasi lain, proyek itu boleh dipakai bersama untuk
RTS Panel - cukup tambahkan satu aplikasi Android baru di dalamnya dengan nama
paket `com.example.rts_panel_app`.

#### B0.3 — Bila memakai proyek yang sudah ada

1. Buka **console.firebase.google.com** lalu klik kartu proyek yang akan dipakai.
2. Tekan ikon **gerigi** di kiri atas → **Project settings**.
3. Gulir ke bawah ke bagian **Your apps** → tekan ikon **Android**.
4. Isi **Android package name**: `com.example.rts_panel_app` → **Register app**.
5. Tekan **Download google-services.json** → letakkan di
   `D:\Project\rts_panel_app\android\app\`.
6. Buat kunci server: **Project settings** → tab **Service accounts** →
   **Generate new private key** (lihat langkah B3).
7. **Penting:** pastikan **Firebase Cloud Messaging API** aktif pada proyek itu.
   Buka **console.cloud.google.com** → pilih proyek yang sama →
   **APIs & Services** → **Enabled APIs** → cari **Firebase Cloud Messaging API**.
   Bila belum ada, tekan **Enable**.

Setelah itu lanjutkan ke langkah **B3** dan seterusnya seperti biasa.

#### Langkah 1 — Membuat proyek Firebase

1. Buka **https://console.firebase.google.com** dan masuk memakai akun Google.
2. Tekan **Create a project** (atau *Tambahkan proyek*).
3. Isi nama proyek: **`RTS Panel`** → **Continue**.
4. Google Analytics: boleh **dimatikan** (pilih *Not right now*/matikan) →
   **Create project** → tunggu → **Continue**.

#### Langkah 2 — Mendaftarkan aplikasi Android

1. Di halaman depan proyek, tekan ikon **Android** (lingkaran hijau) di antara
   ikon-ikon platform.
2. **Android package name** — isi PERSIS seperti ini (huruf kecil semua, tanpa
   spasi):

```
com.example.rts_panel_app
```

   > Nama paket ini **harus sama persis**. Bila salah, aplikasi tidak akan bisa
   > dibangun.

3. **App nickname**: `RTS Panel` (boleh apa saja).
4. Tekan **Register app**.
5. Tekan **Download google-services.json** — simpan berkas itu.
6. Letakkan berkas tersebut di folder:

```
D:\Project\rts_panel_app\android\app\google-services.json
```

7. Pada langkah berikutnya (Add Firebase SDK) — **lewati saja**, tekan
   **Next** lalu **Continue to console**. Bagian Gradle sudah disiapkan skrip.

#### Langkah 3 — Membuat kunci server (untuk mengirim dari hosting)

1. Di Firebase Console, tekan ikon **gerigi** di kiri atas → **Project settings**.
2. Pilih tab **Service accounts**.
3. Tekan **Generate new private key** → **Generate key**.
4. Akan terunduh satu berkas dengan nama seperti
   `rts-panel-1a2b3-firebase-adminsdk-xxxxx.json`.

> **PENTING — berkas ini RAHASIA.**
> Jangan kirim ke saya, jangan tempel isinya di chat, jangan disimpan di
> WhatsApp/Google Drive yang bisa diakses orang lain. Berkas ini memberi izin
> mengirim pemberitahuan atas nama proyek Bapak.

#### Langkah 4 — Menaruh kunci server di hosting (DI LUAR public_html)

1. Masuk cPanel → **File Manager**.
2. Masuk ke folder **`/home/benedics/`** — yaitu folder paling atas
   (satu tingkat **di atas** `public_html`).
   - Di File Manager, tekan **Home** pada kolom alamat, atau hapus
     `public_html` dari kolom alamat.
3. Upload berkas kunci tadi ke folder tersebut.
4. **Ubah nama** berkasnya menjadi:

```
rts_fcm_service_account.json
```

5. Pastikan berkas itu **TIDAK** berada di dalam `public_html` dan **TIDAK**
   berada di dalam folder `api`. Bila berada di dalam `public_html`, berkas itu
   dapat diunduh siapa pun dari internet.

#### B0.4 — Bila halaman Firebase masih berbunyi "Welcome to Firebase!"

Halaman itu berarti akun Bapak **tidak memiliki proyek yang bisa dipakai**.
Namun jatahnya sudah penuh. Penyebabnya biasanya salah satu dari dua ini:

1. Ada proyek lama yang pernah dihapus dan **belum benar-benar musnah**
   (Google menyimpannya sekitar 30 hari).
2. Jatah akun memang sudah terpakai oleh proyek Google Cloud lain.

Periksa lebih dahulu, siapa tahu proyek lama Bapak masih bisa dikembalikan:

**Cara memeriksa dan mengembalikan proyek Google Cloud**

1. Buka **https://console.cloud.google.com/cloud-resource-manager**
2. Akan terlihat daftar proyek yang pernah ada.

| Yang terlihat | Artinya | Tindakan |
| --- | --- | --- |
| Ada proyek dengan keterangan **Pending deletion** / *Akan dihapus* | Proyek itu masih bisa dihidupkan kembali | Tekan **tiga titik** di kanan baris proyek → **Restore** → tunggu sebentar |
| Ada proyek tanpa keterangan apa pun (masih hidup) | Proyek itu **boleh langsung dipakai** untuk Firebase | Buka Firebase Console → *Create a project* → pada kolom nama proyek pilih proyek tersebut |
| Daftar kosong | Tidak ada yang bisa dipakai | Pakai **akun Google lain** (lihat di bawah) |

**Setelah proyek berhasil dikembalikan atau ditemukan**, di Firebase Console:

1. Pada halaman *Create a project*, biasanya ada pilihan memakai proyek Google
   Cloud yang sudah ada. Bila tidak ada, tekan **Add project** lalu tekan ikon
   **folder** di sebelah kanan kolom nama proyek.
2. Setelah proyek terbuka, tambahkan aplikasi Android dengan nama paket
   `com.example.rts_panel_app` (langkah B0.3).

**Bila tidak ada proyek yang bisa dipakai: pakai akun Google lain (paling cepat)**

1. Di kanan atas Firebase Console, tekan **foto profil** → **Add another
   account** (atau keluar lalu masuk dengan akun lain).
2. Buat proyek baru dengan nama **RTS Panel** pada akun itu.
3. Lanjutkan langkah B2 dan seterusnya seperti biasa.

Akun Google yang **belum pernah** membuat proyek Firebase pasti masih memiliki
jatah kosong.

**Bila Bapak hanya punya satu akun Google**

Tekan **Request an increase** pada pesan merah di layar *Create a project*,
lalu isi alasan singkat, misalnya:

```
Untuk aplikasi internal perusahaan (RTS Panel) - pemberitahuan pengajuan
penjualan. Akun ini belum memiliki proyek aktif.
```

Sambil menunggu, seluruh pekerjaan lain **tetap dapat dikerjakan**:
pemasangan berkas server, pembuatan tabel `rts_device_tokens`, dan pemasangan
aplikasi. Firebase boleh disusulkan belakangan tanpa membongkar apa pun.

#### B0.5 — CARA TERBAIK: "Add Firebase to Google Cloud project"

Karena akun Bapak sudah banyak memiliki proyek di Google Cloud (terlihat di
*Manage resources*), **tidak perlu membuat proyek baru sama sekali**. Firebase
dapat ditambahkan ke proyek yang sudah ada, dan cara ini **tidak terkena batas
jumlah proyek**.

Langkahnya (sesuai panduan resmi Google):

1. Buka **https://console.firebase.google.com** lalu tekan
   **Create a project** (boleh juga tekan kartu *Get started by setting up a
   Firebase project*).
2. Isi **Project name** dengan bebas, misalnya `RTS Panel`
   (titik tidak boleh - lihat B0.1).
3. **GULIR HALAMAN ITU KE BAWAH.** Di bagian bawah halaman ada tombol/tautan:

```
Add Firebase to Google Cloud project
```

   Tombol inilah yang tidak terlihat sebelumnya, karena berada di bawah
   tombol **Create project**.

4. Setelah ditekan, akan muncul **kolom pencarian**. Ketikkan nama proyek yang
   sudah Bapak miliki (misalnya `My First Project`), lalu **pilih proyek itu
   dari daftar yang muncul**.
5. Tekan **Continue** → pada pertanyaan Google Analytics, boleh dimatikan →
   **Add Firebase**.
6. Setelah proyek terbuka di Firebase Console, lanjutkan ke **B2**:
   *Add app* → **Android** → isi nama paket `com.example.rts_panel_app` →
   unduh `google-services.json`.

**PENTING — proyek mana yang sebaiknya dipilih:**

| Proyek pada daftar Bapak | Saran |
| --- | --- |
| `My First Project` | **Disarankan** - proyek umum, tidak dipakai aplikasi lain |
| `Dashboard1`, `Publishing`, `Trend`, `research`, `BENEA12`, `BENEAI` | Boleh dipilih bila Bapak tidak memakainya untuk hal lain |
| `AI Studio`, `Gemini API`, `Video AI Prompt Studio` (nama berawalan `gen-lang-client-...`) | **Jangan dipilih** - proyek itu milik Google AI Studio; menambahkan Firebase di sana dapat mengganggu aplikasi AI Studio Bapak |
| Proyek yang muncul di tautan **Resources pending deletion** (bawah halaman) | Jangan dipilih; proyek itu sedang menuju penghapusan |

**Catatan penting dari Google:** menambahkan Firebase ke sebuah proyek
**tidak dapat dibatalkan sepenuhnya** (Firebase tidak bisa dilepas kembali
secara penuh dari proyek tersebut). Jadi pilih proyek yang memang akan dipakai
untuk RTS Panel, idealnya yang tidak dipakai aplikasi lain.

**Bila daftar proyeknya kosong / tidak muncul:** itu masalah yang sudah pernah
dilaporkan pengguna lain, dan penyebabnya adalah **Firebase Management API**
yang sudah aktif di proyek tersebut tanpa Firebase.
Perbaikannya: buka **console.cloud.google.com** → pilih proyek itu →
**APIs & Services** → **Enabled APIs** → cari **Firebase Management API** →
**Disable**. Setelah itu ulangi langkah di atas.

#### B0.6 — Setelah proyek Firebase terbuka: menambahkan aplikasi Android

Bila halaman **Project Overview** sudah terbuka (terlihat tulisan
*Welcome to your Firebase project!* beserta lencana **Spark plan**), proyeknya
sudah siap. Yang dipilih di sini adalah proyek **Publishing** - itu boleh
dipakai. Kode proyek yang berbentuk `gen-lang-client-...` hanyalah nomor
otomatis dari Google dan tidak mempengaruhi apa pun.

Langkah menambahkan aplikasi Android:

| Langkah | Yang diklik / diisi |
| --- | --- |
| 1 | Tekan tombol **+ Add app** (di bawah tulisan nama proyek) |
| 2 | Muncul deretan ikon platform - tekan ikon **Android** (robot hijau) |
| 3 | Kolom **Android package name** - isi PERSIS: `com.example.rts_panel_app` |
| 4 | Kolom **App nickname** - isi: `RTS Panel` |
| 5 | Kolom **Debug signing certificate SHA-1** - **KOSONGKAN / lewati** (tidak perlu untuk pemberitahuan) |
| 6 | Tekan **Register app** |
| 7 | Tekan **Download google-services.json** |
| 8 | Tekan **Next** → **Next** → **Continue to console** (langkah SDK tidak perlu dikerjakan; Gradle sudah disiapkan skrip) |

Berkas `google-services.json` yang terunduh **wajib** diletakkan di folder:

```
D:\Project\rts_panel_app\android\app\google-services.json
```

**Catatan tentang pemberitahuan kuning di bagian atas halaman** (tulisan
*Google Analytics for Firebase iOS+ experienced an issue...*): itu pengumuman
dari Google untuk pengguna iOS, **tidak berhubungan** dengan aplikasi RTS Panel
dan tidak perlu ditindaklanjuti.

**Langkah berikutnya setelah ini:** membuat kunci server (langkah B3 pada
bagian ini) - *Project settings* → tab **Service accounts** →
**Generate new private key**.

### C. Berkas yang saya siapkan (sisi server)

| Berkas | Letak di server | Kegunaan |
| --- | --- | --- |
| `api/fcm_kirim.php` | `public_html/api/` | Pengirim pemberitahuan ke Google (baca kunci, ambil tiket akses, kirim) |
| `api/device_token.php` | `public_html/api/` | Menerima pendaftaran HP dari aplikasi |
| `api/request_create.php` | `public_html/api/` | Pengajuan baru dari aplikasi → pemberitahuan ke ADMIN & ASS |
| `api/request_action.php` | `public_html/api/` | Disetujui/ditolak dari aplikasi → pemberitahuan ke pengirim |
| `inbox_updated.php` | `public_html/` → ganti isi `inbox.php` | Disetujui/ditolak dari website → pemberitahuan ke pengirim |
| `pengajuan_toko_updated.php` | `public_html/` → ganti isi `pengajuan_toko.php` | **Perbaikan baru:** pengajuan dari website kini juga memberi tahu ADMIN & ASS |
| `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` | dijalankan di phpMyAdmin | Membuat tabel `rts_device_tokens` |

Semua berkas di atas **aman dipasang lebih dahulu** walaupun Firebase belum
disiapkan: bila kunci belum ada, pengiriman ke HP dilewati dan aplikasi tetap
berjalan seperti biasa.

### D. Urutan pemasangan (kerjakan berurutan)

**Tahap 1 — Sisi server (boleh sekarang, sebelum Firebase siap)**

1. Ekstrak `RTS_PANEL_FIREBASE.zip` ke `public_html/`
   (seluruh isi folder `api/` ikut masuk ke `public_html/api/`).
2. Ganti isi `inbox.php` dengan isi `inbox_updated.php`
   dan `pengajuan_toko.php` dengan isi `pengajuan_toko_updated.php`.
3. Jalankan `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` di phpMyAdmin
   (database produksi dan staging).
4. Letakkan berkas kunci Firebase seperti pada langkah B4.

**Tahap 2 — Sisi aplikasi**

5. Ganti isi `pubspec.yaml` dengan `pubspec.yaml.updated` (ada
   `firebase_core` dan `firebase_messaging`).
6. Ganti isi `android\app\build.gradle.kts` dengan `build.gradle.kts.updated`
   (ada plugin google-services dan minSdk 23).
7. Letakkan `google-services.json` di `android\app\` (langkah B2 nomor 6).
8. Jalankan skrip penyiap Gradle:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_FIREBASE.ps1
```

   Skrip itu menyisipkan plugin pada `android\settings.gradle.kts`,
   mencadangkan berkas asli ke `.lama`, dan menjalankan `flutter pub get`.

9. Bangun dan pasang ke HP:

```powershell
flutter run
```

   Build kali ini lebih lama dari biasanya (unduhan paket Firebase) — sekitar
   10-15 menit. Sabar menunggu.

**Tahap 3 — Ganti isi main.dart dengan berkas `main.dart` terbaru**

`main.dart` di panel sudah memuat bagian Firebase. Bila isinya terpotong
(tanda "unmodified lines"), beri tahu saya — saya siapkan salinannya
seperti `inbox_updated.php`.

### E. Cara menguji

**Uji 1 — Memastikan Firebase aktif di HP**

1. Buka aplikasi → menu **Pengaturan**.
2. Pada kartu **Pemberitahuan HP** akan terlihat baris baru:
   `Firebase: Aktif (pemberitahuan tetap masuk walau aplikasi ditutup)`
   - Bila tertulis **Belum aktif** → periksa kembali langkah B2 (berkas
     `google-services.json`) dan jalan **Uji 2** di bawah.

**Uji 2 — Pemberitahuan dari uji coba Firebase Console**

1. Firebase Console → menu **Messaging** (atau *Cloud Messaging*).
2. Tekan **Create your first campaign** → pilih **Firebase Notification
   messages** → **Create**.
3. Isi **Notification title**: `Uji Firebase RTS Panel`,
   **Notification text**: `Bila tulisan ini muncul, pemberitahuan HP siap.`
4. Tekan **Send test message** → tempelkan token perangkat aplikasi →
   **Test**.
   - Token perangkat dapat diminta dari saya bila perlu; untuk uji sehari-hari
     cukup memakai Uji 3.

**Uji 3 — Uji nyata (yang paling penting)**

1. **Tutup aplikasi total** di HP: buka daftar aplikasi terakhir, geser
   aplikasi RTS Panel ke atas (swipe) sampai hilang.
2. Dari HP lain (atau dari website), kirim pengajuan baru:
   - Bila pengirim adalah akun sales dari aplikasi → **ADMIN & ASS** menerima
     pemberitahuan.
   - Bila dikirim dari website → sekarang **ADMIN & ASS juga** menerima
     pemberitahuan (perbaikan baru).
3. Pemberitahuan harus **muncul di layar HP dalam beberapa detik**, walaupun
   aplikasi baru saja ditutup total.
4. Tekan pemberitahuan itu → aplikasi terbuka pada menu **Pemberitahuan**.
5. Setujui pengajuan tersebut dari website → **pengirimnya** menerima
   pemberitahuan "Disetujui" di HP, juga dalam keadaan aplikasi tertutup.

### F. Batasan yang perlu diketahui

| Keadaan | Pemberitahuan Firebase |
| --- | --- |
| Aplikasi ditutup dari daftar aplikasi (swipe) | **Masuk** |
| HP dikunci / layar mati | **Masuk** |
| HP dalam mode hemat baterai (Oppo/Realme/Xiaomi) | Kadang tertunda — lihat catatan di bawah |
| Aplikasi dihentikan paksa (Force stop di Pengaturan Android) | **Tidak masuk** sampai aplikasi dibuka lagi |
| HP tidak ada internet | Tertunda sampai ada internet |

**Catatan untuk HP Oppo (CPH1937):** Oppo cukup agresif menghentikan aplikasi
latar. Agar pemberitahuan selalu masuk, lakukan sekali saja:

1. Pengaturan HP → **Baterai** → **Penggunaan baterai** → pilih **RTS Panel**
   → **Jangan optimalkan** (Allow background activity).
2. Pengaturan HP → **Aplikasi** → **RTS Panel** → **Manajemen otomatis**
   dimatikan, dan **Aktivitas latar belakang** diizinkan.

Bila dua hal ini belum dilakukan, pemberitahuan biasanya tetap masuk, tetapi
bisa terlambat beberapa detik sampai beberapa menit.

### G. Pemecahan masalah

| Gejala | Kemungkinan penyebab | Tindakan |
| --- | --- | --- |
| Build gagal: *File google-services.json is missing* | Berkas belum diletakkan | Letakkan di `android\app\google-services.json` |
| Build gagal: *No matching client found for package name* | Nama paket di Firebase berbeda | Pastikan `com.example.rts_panel_app` (langkah B2) |
| Build gagal: *Plugin [id: 'com.google.gms.google-services'] was not found* | Plugin belum ada di `settings.gradle.kts` | Jalankan `PASANG_FIREBASE.ps1` |
| Pengaturan aplikasi: `Belum aktif` | Firebase belum tersambung | Periksa `google-services.json`, lalu buka aplikasi kembali |
| Tabel `rts_device_tokens` **tidak ada** (dari `device_token.php`) | SQL belum dijalankan | Jalankan `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` |
| Aplikasi jalan, tabel terisi, tetapi HP tidak berbunyi | Kunci server belum ada/salah | Periksa `rts_fcm_service_account.json` di `/home/benedics/` |
| Pemberitahuan hanya masuk saat aplikasi dibuka | Firebase belum aktif; masih memakai pemeriksaan berkala | Selesaikan Tahap 2 |

**Cara memeriksa kunci server sudah benar.** Buka
`https://rts.benedic-s.com/api/env_check.php` (versi 4) — bagian `berkas_website`
harus `COCOK`. Untuk memastikan kunci **tidak bocor**, coba buka
`https://rts.benedic-s.com/rts_fcm_service_account.json` — hasilnya **harus 404
Not Found**. Bila berkas itu terbuka, segera pindahkan ke luar `public_html`
dan buat kunci baru di Firebase Console.

### H. Berkas yang TIDAK boleh di-upload ke server

| Berkas | Alasan |
| --- | --- |
| `google-services.json` | Hanya dipakai saat membangun aplikasi di komputer |
| Berkas kunci Firebase (nama asli dari Google) | Diletakkan di `/home/benedics/` dengan nama baru; jangan taruh di `public_html` |
| `PASANG_FIREBASE.ps1`, `PERBAIKI_DAN_JALANKAN.ps1`, `PASANG_DI_HP.ps1` | Hanya untuk komputer |
| Salinan `_updated` | Hanya untuk disalin isinya |

### I. STATUS LANGKAH FIREBASE

Tandai yang sudah selesai:

**Sisi Firebase Console**

| No | Langkah | Status |
| --- | --- | --- |
| 1 | Masuk ke proyek Firebase **Publishing** (lewat *Add Firebase to Google Cloud project*) | SELESAI |
| 2 | *Add app* -> Android -> paket `com.example.rts_panel_app` | SELESAI |
| 3 | `google-services.json` tersimpan di `D:\Project\rts_panel_app\android\app\` | SELESAI |
| 4 | Kunci server: *Project settings* -> *Service accounts* -> **Generate new private key** | **BELUM** |
| 5 | Kunci server diletakkan di `/home/benedics/rts_fcm_service_account.json` | **BELUM** |

**Sisi aplikasi (komputer)**

| No | Langkah | Status |
| --- | --- | --- |
| 6 | Ganti isi `pubspec.yaml` dengan `pubspec.yaml.updated` | BELUM |
| 7 | Ganti isi `android\app\build.gradle.kts` dengan `build.gradle.kts.updated` | BELUM |
| 8 | Jalankan `PASANG_FIREBASE.ps1` | BELUM |
| 9 | Ganti isi `main.dart` dengan `main.dart` terbaru (10.281 baris) | BELUM |
| 10 | `flutter run` (build pertama 10-15 menit) | BELUM |

**Sisi server**

| No | Langkah | Status |
| --- | --- | --- |
| 11 | Ekstrak `RTS_PANEL_FIREBASE.zip` ke `public_html/` | BELUM |
| 12 | Ganti isi `inbox.php` (dari `inbox_updated.php`) dan `pengajuan_toko.php` (dari `pengajuan_toko_updated.php`) | BELUM |
| 13 | Jalankan `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` di phpMyAdmin | BELUM |

**Urutan yang disarankan:** 6 -> 7 -> 8 -> 9 -> 10 (aplikasi), lalu 11 -> 13 -> 4 -> 5 (server).
Langkah 11 dan 12 boleh dikerjakan lebih dahulu kapan saja, karena tanpa kunci
Firebase pun berkas-berkas itu aman dipasang.

---

## BAGIAN 34 — MEMPERBAIKI ERROR BUILD "generateLockfiles" (AGP 9)

### A. Pesan error yang muncul

```
FAILURE: Build failed with an exception.

* Where:
Build file 'D:\Project\rts_panel_app\android\app\build.gradle.kts' line: 1

* What went wrong:
An exception occurred applying plugin request [id: 'dev.flutter.flutter-gradle-plugin']
> Failed to apply plugin 'dev.flutter.flutter-gradle-plugin'.
   > Cannot add task 'generateLockfiles' as a task with that name already exists.

┌─ Flutter Fix ──────────────────────────────────────────────────────────┐
│ [!] Starting AGP 9+, only the new DSL interface will be read.          │
│ This results in a build failure when applying the Flutter Gradle       │
│ plugin at D:\Project\rts_panel_app\android\app\build.gradle.kts       │
│ To resolve this update flutter or opt out of `android.newDsl`.         │
└────────────────────────────────────────────────────────────────────────┘
```

### B. Penyebabnya (bahasa sederhana)

Android memiliki "aturan penulisan berkas Gradle". Mulai **AGP 9**
(Android Gradle Plugin versi 9), Google membuat **aturan penulisan baru** dan
menjadikannya **bawaan**.

Masalahnya: **plugin Flutter belum memakai aturan baru itu**, dan **plugin
Firebase (google-services) juga belum**. Keduanya masih memakai aturan lama.
Karena aturan baru dipaksa aktif, plugin Flutter gagal dipasang, dan
muncullah pesan tentang tugas `generateLockfiles` yang berbenturan.

**Buktinya**: build berjalan baik sebelum Firebase ditambahkan. Setelah
plugin `google-services` ikut dipasang, benturan itu baru muncul.

Ini **bukan kesalahan kode kita**. Ini masalah yang sedang dihadapi banyak
pengguna Flutter di seluruh dunia (banyak laporan di GitHub Flutter pada
September 2026). Solusi resmi dari Flutter sendiri adalah **kembali ke aturan
lama** untuk sementara, dengan dua baris pengaturan.

### C. Perbaikannya: 2 baris pada `android\gradle.properties`

Tambahkan **dua baris** ini pada berkas `android\gradle.properties`:

```
android.newDsl=false
android.builtInKotlin=false
```

Berkas lengkapnya sudah saya siapkan: **`gradle.properties.updated`**.
Cara pakai: salin **seluruh** isinya ke
`D:\Project\rts_panel_app\android\gradle.properties` (Ctrl+A lalu hapus,
kemudian tempel seluruh isi berkas itu).

> Perhatikan juga bagian `org.gradle.jvmargs=-Xmx4G`. Tulisan `4G` berarti
> Gradle memakai memori 4 GB. Bila RAM komputer Bapak 4 GB atau kurang, ubah
> menjadi `-Xmx2G`.

### D. Urutan mengerjakan

1. Ganti seluruh isi `android\gradle.properties` dengan isi
   `gradle.properties.updated`.
2. Simpan `BERSIHKAN_DAN_BUILD.ps1` di folder proyek.
3. Sambungkan HP memakai **kabel USB** (lebih stabil daripada nirkabel).
4. Jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\BERSIHKAN_DAN_BUILD.ps1
```

Skrip itu akan:

| Langkah | Tindakan |
| --- | --- |
| 1 | Memeriksa `android.newDsl=false` dan `android.builtInKotlin=false` sudah ada; bila belum, skrip berhenti dan memberi tahu |
| 2 | Memeriksa `android.enableJetifier` |
| 3 | Memeriksa plugin google-services pada `settings.gradle.kts` dan `app\build.gradle.kts` |
| 4 | Memeriksa `google-services.json` **beserta kecocokan nama paketnya** |
| 5 | Menghapus `build`, `.dart_tool`, `android\.gradle`, lalu `flutter clean` dan `flutter pub get` |
| 6 | `gradlew.bat --stop` |
| 7 | Menampilkan daftar perangkat dan **mengutamakan perangkat kabel** |
| 8 | `flutter run` pada perangkat kabel itu |

Build pertama dengan Firebase memakan **10-15 menit**. Jangan ditutup.

### E. Bila masih gagal

| Pesan error | Artinya | Tindakan |
| --- | --- | --- |
| Masih `Cannot add task 'generateLockfiles'` | Dua baris pengaturan belum terbaca | Pastikan keduanya ada di `android\gradle.properties` (bukan `gradle.properties` di folder lain), lalu jalankan lagi skrip |
| `Jetifier is deprecated` / error tentang Jetifier | `android.enableJetifier=true` tidak diterima | Hapus baris `android.enableJetifier=true` dari `android\gradle.properties` |
| `The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support since AGP 9.0` | Kebalikan dari masalah kita: cara baru justru dipaksa | Pastikan `android.builtInKotlin=false` ada |
| `File google-services.json is missing` | Berkas belum ada | Letakkan di `android\app\google-services.json` |
| `No matching client found for package name` | Nama paket di Firebase berbeda | Buat ulang aplikasi di Firebase dengan paket `com.example.rts_panel_app` |
| Error memori / Gradle berhenti sendiri | RAM tidak cukup | Ubah `-Xmx4G` menjadi `-Xmx2G` |
| `Could not close incremental caches ... different roots` | Masalah drive C dan D | Sudah ditangani oleh `kotlin.incremental=false` pada berkas yang sama |

Bila masih gagal, **kirim 20 baris pertama yang berwarna merah** ke saya.

### F. Catatan penting untuk ke depan

Dua baris itu adalah **penyesuaian sementara**, bukan kesalahan. Nanti setelah
Flutter dan semua plugin sudah memakai cara baru AGP 9, dua baris itu boleh
dihapus. Yang perlu diingat: **jangan menghapus kedua baris itu selama masih
memakai Flutter versi sekarang**, karena build akan langsung gagal lagi.

---

## BAGIAN 35 — MEMPERBAIKI VERSI PLUGIN GOOGLE SERVICES (PERBAIKAN PENDUKUNG)

### A. Kesalahan saya yang perlu diperbaiki

Pada bagian 33 dan skrip `PASANG_FIREBASE.ps1`, plugin Google Services
disisipkan dengan versi **4.4.2**. Versi itu **belum mendukung AGP 9**.

Akibatnya build gagal dengan pesan yang sama berulang kali:

```
Cannot add task 'generateLockfiles' as a task with that name already exists
Starting AGP 9+, only the new DSL interface will be read
```

Karena itu, dua baris penyesuaian (`android.newDsl=false` dan
`android.builtInKotlin=false`) **tidak menyelesaikannya** - masalahnya bukan di
situ, melainkan pada **versi plugin** yang terlalu tua.

**Versi yang benar: `com.google.gms.google-services` 4.5.0** (terbit Juni 2026).
Google sendiri kini mencantumkan 4.5.0 pada dokumentasi resminya.

| Versi plugin | AGP 8 | AGP 9 |
| --- | --- | --- |
| 4.4.2 (dipakai sebelumnya) | Bekerja | **GAGAL** |
| 4.4.4 | Bekerja | Belum tentu |
| **4.5.0 (dipakai sekarang)** | Bekerja | **Bekerja** |

### B. Perbaikannya

Satu baris pada `android\settings.gradle.kts`, dari:

```kotlin
id("com.google.gms.google-services") version "4.4.2" apply false
```

menjadi:

```kotlin
id("com.google.gms.google-services") version "4.5.0" apply false
```

Berkas `PASANG_FIREBASE.ps1` juga sudah diperbarui menjadi 4.5.0, sehingga
pemasangan berikutnya tidak mengulangi kesalahan yang sama.

### C. Cara mengerjakan (satu skrip)

Simpan **`PERBAIKI_PLUGIN_FIREBASE.ps1`** di `D:\Project\rts_panel_app`,
sambungkan HP memakai **kabel USB**, lalu jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\PERBAIKI_PLUGIN_FIREBASE.ps1
```

| Langkah | Tindakan skrip |
| --- | --- |
| 1 | Menampilkan versi Gradle, **seluruh isi `settings.gradle.kts`**, dan baris pengaturan `gradle.properties` (bahan pemeriksaan bila masih gagal) |
| 2 | Mengubah versi plugin google-services menjadi **4.5.0** (atau menyisipkannya bila belum ada) |
| 3 | Menonaktifkan `android.enableJetifier` (tidak dipakai pada AGP 9; semua pustaka sudah AndroidX) dan memastikan dua baris penyesuaian AGP 9 ada |
| 4 | Memeriksa plugin google-services pada `app\build.gradle.kts` |
| 5 | Menghapus `build`, `.dart_tool`, `android\.gradle`, lalu `flutter clean`, `flutter pub get`, `gradlew --stop` |
| 6 | Menampilkan daftar perangkat dan menjalankan `flutter run` pada perangkat kabel |

### D. Bila MASIH gagal

Kirimkan dua hal ini ke saya:

1. **Salinan teks bagian "1. Keadaan berkas Gradle sekarang"** dari keluaran
   skrip di atas (di situ terlihat versi Gradle, AGP, Kotlin, dan isi
   `settings.gradle.kts`).
2. **20 baris pertama yang berwarna merah.**

Dengan dua hal itu, penyebabnya dapat dipastikan tanpa menebak lagi.

### E. Pelajaran untuk ke depan

Bila suatu saat muncul error Gradle yang aneh setelah menambah paket baru,
yang perlu dicurigai lebih dahulu:

| Yang dicurigai | Cara memeriksa |
| --- | --- |
| Versi paket terlalu tua untuk AGP yang dipakai | Bandingkan dengan dokumentasi resmi paket tersebut |
| Versi tool (Gradle/AGP/Kotlin) berubah | Periksa `android\settings.gradle.kts` dan `gradle-wrapper.properties` |
| Berkas konfigurasi terpotong | Bandingkan jumlah baris dengan panduan (bagian 28) |

---

## BAGIAN 36 — PENYEBAB SEBENARNYA ERROR "generateLockfiles" SUDAH DITEMUKAN

### A. Apa yang sebenarnya terjadi

Dari laporan `LAPORAN_GRADLE.txt`, terlihat bahwa:

| Berkas | Isi yang benar | Keadaan di komputer |
| --- | --- | --- |
| `android\build.gradle.kts` (**root**) | Hanya pengaturan umum: `allprojects { repositories ... }` dan pengaturan folder build | **Berisi isi berkas aplikasi**: `plugins { id("com.android.application") ... id("dev.flutter.flutter-gradle-plugin") }` |
| `android\app\build.gradle.kts` (**aplikasi**) | Berisi `plugins { ... }` + `android { ... }` + `flutter { ... }` | Benar |

Karena plugin `dev.flutter.flutter-gradle-plugin` **terpasang dua kali**
(sekali di root, sekali di aplikasi), plugin itu mencoba mendaftarkan tugas
`generateLockfiles` dua kali pada proyek yang sama. Gradle menolak, dan
muncullah pesan:

```
Cannot add task 'generateLockfiles' as a task with that name already exists
```

**Inilah sebabnya** dua perbaikan sebelumnya (baris `newDsl` dan versi plugin
4.5.0) tidak mengubah hasilnya: keduanya memang sudah benar, tetapi bukan itu
penyebabnya.

**Bagaimana bisa terjadi:** saat menyalin `build.gradle.kts.updated`, tujuannya
kurang satu folder - seharusnya `android\app\build.gradle.kts`, tetapi
tertempel ke `android\build.gradle.kts`. Penamaan berkas yang membingungkan itu
kekurangan saya, dan sekarang sudah dicegah dua cara:

1. `build.gradle.kts.updated` diberi peringatan di baris paling atas tentang
   tempat yang benar.
2. Tersedia skrip yang **menulis sendiri** berkasnya, jadi tidak ada lagi
   penyalinan manual.

### B. Perbaikannya

Simpan **`PERBAIKI_ROOT_GRADLE.ps1`** di `D:\Project\rts_panel_app`, sambungkan
HP memakai **kabel USB**, lalu jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\PERBAIKI_ROOT_GRADLE.ps1
```

| Langkah | Tindakan skrip |
| --- | --- |
| 1 | Mencadangkan berkas sekarang ke folder `android\cadangan_arena` (tidak ada yang dihapus) |
| 2 | Mencari template root **dari Flutter SDK Bapak sendiri**, sehingga isinya pasti cocok dengan Flutter 3.44.8 |
| 3 | Menulis ulang `android\build.gradle.kts` (root) dengan template itu |
| 4 | Menulis ulang `android\app\build.gradle.kts` dengan versi aplikasi yang benar (memuat Firebase + `minSdk` minimal 23) |
| 5 | Memastikan `android\settings.gradle.kts` memuat plugin google-services 4.5.0 |
| 6 | Memindahkan berkas sisa agar tidak mengganggu: `build.gradle - Copy.kts`, `build.gradle.kts.lama`, `settings.gradle.kts.lama` |
| 7 | **Memeriksa hasil** - bila masih ada penggandaan, skrip BERHENTI dan tidak membuang waktu build |
| 8 | Membersihkan hasil build lama lalu menjalankan `flutter run` |

Untuk memperbaiki saja tanpa membangun:

```powershell
powershell -ExecutionPolicy Bypass -File .\PERBAIKI_ROOT_GRADLE.ps1 -TanpaBuild
```

### C. Pemeriksaan yang dilakukan sebelum build

Skrip mencetak hasil pemeriksaan seperti ini:

```
== 6. Memeriksa hasil perbaikan
   OK      : android\build.gradle.kts tidak memuat plugin aplikasi
   OK      : android\build.gradle.kts tidak memuat 'com.android.application'
   OK      : app flutter-gradle-plugin: 1 kemunculan (harus 1)
   OK      : app google-services: 1 kemunculan (harus minimal 1)
   OK      : android\app\google-services.json ada
   Semua pemeriksaan LOLOS.
```

Bila ada yang bertanda **MASALAH**, build tidak dijalankan dan skrip meminta
keluarannya dikirimkan ke saya. Ini menghemat waktu 10 menit per percobaan.

### D. Keadaan yang sudah benar setelah perbaikan

| Berkas | Isi yang benar |
| --- | --- |
| `android\build.gradle.kts` | `allprojects { repositories { google(); mavenCentral() } }` + pengaturan folder build + `evaluationDependsOn(":app")` |
| `android\app\build.gradle.kts` | `plugins { com.android.application, google-services, kotlin-android, flutter-gradle-plugin }` + `android { ... }` + `flutter { source = "../.." }` + `dependencies { coreLibraryDesugaring }` |
| `android\settings.gradle.kts` | plugin-loader, google-services 4.5.0, com.android.application 9.0.1, kotlin 2.3.20, `include(":app")` |
| `android\gradle.properties` | `android.newDsl=false`, `android.builtInKotlin=false`, `kotlin.incremental=false` |
| `android\gradle\wrapper\gradle-wrapper.properties` | `gradle-9.1.0-all.zip` |

### E. Ringkasan tiga perbaikan yang saling melengkapi

Ketiganya **diperlukan**, dan hanya yang ketiga yang merupakan penyebab utama:

| Perbaikan | Untuk apa | Sudah dikerjakan pada |
| --- | --- | --- |
| `android.newDsl=false` + `android.builtInKotlin=false` | Agar plugin Flutter dan Firebase dapat berjalan pada AGP 9 | Bagian 34 |
| Plugin `google-services` versi 4.5.0 (bukan 4.4.2) | Agar plugin Google Services mendukung AGP 9 | Bagian 35 |
| **Berkas root tidak boleh memuat plugin aplikasi** | Menghilangkan penggandaan plugin Flutter - **inilah penyebab pesan `generateLockfiles`** | Bagian 36 (ini) |

---

## BAGIAN 37 — MEMASANG APK YANG SUDAH JADI KE HP (LEWAT KABEL USB)

### A. Kabar baik: build sudah berhasil

Keluaran terakhir Bapak memuat baris ini:

```
Running Gradle task 'assembleDebug'...      1416.3s
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

Artinya **seluruh masalah Gradle sudah selesai**:
`generateLockfiles`, penggandaan plugin Flutter, `newDsl`, dan versi
google-services. Semuanya tuntas di Bagian 34-36. Build memakan 23,6 menit
(1416,3 detik) karena memakai Gradle 9.1 dan Firebase; build berikutnya jauh
lebih cepat karena cache sudah hangat.

### B. Sisa SATU langkah kecil: APK belum terpasang

Pesan yang tersisa:

```
Launching lib\main.dart on CPH1937 (wireless) in debug mode...
adb.exe: device 'adb-9909f35e-NbqoA0._adb-tls-connect._tcp' not found
Error: ADB exited with exit code 1
Error launching application on CPH1937 (wireless).
```

Bacaan sederhananya:

| Bagian pesan | Artinya |
| --- | --- |
| `on CPH1937 (wireless)` | Flutter mengira HP ada di jaringan nirkabel, **bukan** lewat kabel |
| `_adb-tls-connect._tcp` | Penanda sambungan nirkabel (ADB tanpa kabel) yang sudah mati |
| `ADB exited with exit code 1` | Perintah pemasangan tidak menemukan HP itu, jadi dibatalkan |
| `Error launching application` | Yang gagal hanyalah **pemasangan**, bukan pembuatan aplikasi |

Penyebabnya: HP tidak terhubung ke komputer lewat kabel, sehingga satu-satunya
"perangkat" yang dikenal Flutter adalah sisa daftar nirkabel lama. ADB mencoba
menghubungi alamat yang sudah mati, lalu menyerah.

### C. Perbaikannya

Simpan **`PASANG_LEWAT_KABEL.ps1`** di `D:\Project\rts_panel_app`, sambungkan HP
memakai **kabel USB**, lalu jalankan:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_LEWAT_KABEL.ps1
```

Skrip ini **TIDAK membangun ulang**. Ia hanya memasang APK yang sudah jadi,
jadi selesai dalam 1-2 menit - bukan 23 menit.

| Langkah | Tindakan skrip |
| --- | --- |
| 1 | Mencari `adb.exe` dari `local.properties`, `ANDROID_HOME`, lalu lokasi bawaan |
| 2 | `adb kill-server` + `start-server` + `adb disconnect` - membersihkan sisa nirkabel yang mati |
| 3 | Membaca `adb devices -l` dan memisahkan perangkat **KABEL** dari **NIRKABEL** |
| 4 | Bila belum ada perangkat kabel, menampilkan petunjuk per-bagian lalu BERHENTI (tidak buang waktu) |
| 5 | Memeriksa APK `build\app\outputs\flutter-apk\app-debug.apk` beserta ukuran dan jam pembuatannya |
| 6 | Memasang dengan `adb install -r -d`, dan menangani 3 kegagalan umum dengan jelas |
| 7 | Membuka aplikasi di layar HP |
| 8 | Menampilkan nomor perangkat kabel untuk dipakai pada `flutter run` berikutnya |

Untuk sekadar memeriksa tanpa memasang:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_LEWAT_KABEL.ps1 -HanyaPeriksa
```

### D. Bila HP belum terbaca lewat kabel

Periksa berurutan - ini penyebab tersering:

| Periksa | Cara |
| --- | --- |
| **Kabel** | Pakai kabel data (kabel bawaan HP). Banyak kabel hanya mengisi daya tanpa jalur data |
| **Mode USB** | Setelah kabel ditancapkan, tarik bilah atas HP - ketuk pemberitahuan USB - pilih **Transfer file / MTP**. Bila tetap "Mengisi daya", komputer tidak melihat HP |
| **Opsi pengembang** | Pengaturan - Tentang ponsel - ketuk **Nomor bentukan** 7 kali. Lalu Pengaturan - Opsi pengembang - aktifkan **Penelusuran USB** |
| **Matikan nirkabel** | Di Opsi pengembang, **matikan Penelusuran nirkabel**. Selama hidup, Flutter dapat memilih jalur nirkabel yang mati |
| **Konfigurasi USB default** | Opsi pengembang - **Pilih konfigurasi USB default** - pilih **Transfer file** |
| **Izin di HP** | Layar HP akan menanyakan "Izinkan penelusuran USB?" - ketuk **IZINKAN** |

Bila `adb devices -l` menampilkan `unauthorized`, berarti izin di HP belum
diketuk - cukup ketuk IZINKAN di layar HP lalu ulangi skrip.

### E. Supaya tidak tertukar lagi

Selalu sebut perangkatnya saat menjalankan Flutter:

```powershell
flutter run -d <nomor-perangkat-kabel>
```

Nomor perangkat kabel ditampilkan skrip pada langkah 8. Penanda yang perlu
dihindari: id yang memuat `_adb-tls-connect` - itu jalur nirkabel.

### F. Kemungkinan penolakan pemasangan

| Pesan | Arti dan tindakan |
| --- | --- |
| `Success` | Berhasil - aplikasi langsung dibuka |
| `INSTALL_FAILED_UPDATE_INCOMPATIBLE` | Aplikasi versi lama memakai kunci berbeda. Skrip akan menawarkan menghapus aplikasi lama; **akibatnya sesi login dan "Ingat saya" hilang, perlu login ulang** |
| `INSTALL_FAILED_INSUFFICIENT_STORAGE` | Ruang HP tidak cukup - kosongkan sedikit |
| `INSTALL_FAILED_VERSION_DOWNGRADE` | Tidak akan terjadi karena pemasangan memakai `-d` (mengizinkan versi sama/turun) |

### G. Yang perlu diperiksa setelah aplikasi terpasang

| Nomor | Pemeriksaan |
| --- | --- |
| 1 | Layar login tampil, gambar latar terlihat, tidak ada teks terpotong |
| 2 | Muncul pertanyaan **"Izinkan Notifikasi"** - ketuk IZINKAN |
| 3 | Login memakai **username** berhasil |
| 4 | Menu **Pengaturan** - lihat tulisan **Firebase:** apakah **Aktif** |
| 5 | Tombol **KIRIM PEMBERITAHUAN PERCOBAAN** - notifikasi muncul di bagian atas layar HP |
| 6 | Bila semua di atas lolos - lanjutkan `UJI_APLIKASI.md` |

### H. Setelah build sukses ini, jangan lupa

Karena plugin Firebase sudah benar-benar terbangun, sisa penyiapan sisi server:

| Nomor | Pekerjaan |
| --- | --- |
| 1 | Unduh kunci *service account* Firebase - simpan sebagai `/home/benedics/rts_fcm_service_account.json` |
| 2 | Ekstrak `RTS_PANEL_FIREBASE.zip` ke `public_html/`, lalu timpa `inbox.php` dan `pengajuan_toko.php` |
| 3 | Jalankan `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` di phpMyAdmin (produksi dan staging) |
| 4 | Uji: tutup aplikasi total - kirim pengajuan dari HP - notifikasi harus masuk - ketuk lalu masuk ke menu Pemberitahuan |

---

## BAGIAN 38 — MEMASANG APLIKASI TANPA KABEL (PENELUSURAN NIRKABEL)

### A. Kabar baik: tidak perlu kabel

HP Bapak memakai **Android 11**, dan Android 11 ke atas memiliki menu resmi
**Penelusuran nirkabel** (*Wireless debugging*). Dengan menu itu, aplikasi dapat
dipasang **tanpa kabel sama sekali**.

Yang gagal pada percobaan sebelumnya **bukan karena nirkabel tidak bisa**,
melainkan karena:

| Sebab | Penjelasan |
| --- | --- |
| Sambungan lama sudah mati | Komputer masih menyimpan catatan `adb-9909f35e-NbqoA0._adb-tls-connect._tcp`, padahal sambungan itu sudah tidak ada |
| Belum dipasangkan ulang | Setelah HP dimatikan atau pindah Wi-Fi, nomor sambungan berubah dan pemasangan ulang (*pairing*) perlu dilakukan |
| Menu Penelusuran nirkabel mungkin mati | ColorOS/Oppo mematikan menu itu saat HP dimulai ulang |

Semuanya bisa diperbaiki, dan banyak yang otomatis dikerjakan skrip.

### B. Langkah di HP (sekali saja)

| Nomor | Langkah |
| --- | --- |
| 1 | Pengaturan → Tentang ponsel → ketuk **Nomor bentukan** 7 kali (bila Opsi Pengembang belum aktif) |
| 2 | Pengaturan → Opsi pengembang → **Penelusuran nirkabel** → **AKTIFKAN** |
| 3 | HP dan komputer harus tersambung ke **Wi-Fi yang sama** (jaringan tamu/guest tidak bisa) |
| 4 | Buka layar **Penelusuran nirkabel** dan biarkan terbuka selama proses |

Di layar itu akan terlihat tulisan seperti:

```
IP address & Port
192.168.1.7:37041

[ Pasangkan perangkat dengan kode ]
```

### C. Menjalankan skrip

Simpan **`PASANG_NIRKABEL.ps1`** di `D:\Project\rts_panel_app`, lalu:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1
```

Skrip ini terbagi 10 bagian:

| Bagian | Tindakan skrip |
| --- | --- |
| 1 | Mencari `adb.exe` dan menampilkan versinya |
| 2 | `adb kill-server` + `start-server` + `adb disconnect` - **membersihkan sisa nirkabel yang mati** inilah penyebab kegagalan sebelumnya |
| 3 | Mencari HP di jaringan memakai `adb mdns services` |
| 4 | Bila sambungan sudah hidup, langsung dipakai; bila belum, mencoba menyambung otomatis |
| 5 | Bila belum pernah dipasangkan: memandu **pemasangan dengan kode 6 angka** |
| 6 | Menampilkan keadaan sambungan dan menyimpan nomor perangkat ke `catatan_nirkabel.txt` |
| 7 | Memeriksa APK `build\app\outputs\flutter-apk\app-debug.apk` |
| 8 | Memasang APK lewat nirkabel, dengan penanganan 5 kegagalan umum |
| 9 | Membuka aplikasi di layar HP |
| 10 | Ringkasan dan perintah `flutter run` untuk hot reload |

Skrip **tidak membangun ulang** aplikasi, jadi selesai 2-5 menit (nirkabel
memang lebih lambat daripada kabel untuk pengiriman berkas).

### D. Pemasangan dengan kode 6 angka (pairing)

Bila HP belum pernah dipasangkan dengan komputer ini, skrip akan meminta:

| Nomor | Langkah |
| --- | --- |
| 1 | Di layar Penelusuran nirkabel HP, ketuk **Pasangkan perangkat dengan kode** |
| 2 | Layar HP menampilkan alamat `IP:nomor` dan **kode 6 angka** |
| 3 | Kembali ke terminal, tekan Enter |
| 4 | Skrip akan mencari alamatnya sendiri; bila tidak ketemu, ketik persis alamat dari HP |
| 5 | Ketik **6 angka** dari layar HP, lalu Enter |
| 6 | Skrip memasang, menyambung, lalu memasang aplikasi |

Kode itu **hanya hidup beberapa menit** - kerjakan dengan cepat. Bila kedaluwarsa,
tutup layarnya, ketuk lagi untuk mendapat kode baru, lalu jalankan skrip lagi.

Setelah dipasangkan **sekali**, HP akan selalu mengingat komputer Bapak. Pemasangan
berikutnya tidak perlu kode lagi - cukup menu Penelusuran nirkabel dalam keadaan aktif.

Untuk sekadar memeriksa sambungan tanpa memasang:

```powershell
powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1 -HanyaPeriksa
```

### E. Yang membuat nirkabel gagal - dan penanganannya

| Pesan / keadaan | Sebab | Penanganan |
| --- | --- | --- |
| `device not found` / `not found` | Sambungan lama sudah mati | Jalankan `PASANG_NIRKABEL.ps1` - bagian 2 membersihkannya |
| `failed to pair` | Kode 6 angka sudah kedaluwarsa | Buka layar kode baru di HP, jalankan skrip lagi |
| `unauthorized` | Izin belum diketuk di HP | Buka HP, ketuk **IZINKAN** |
| `offline` | HP tidur / Wi-Fi berubah | Nyalakan layar HP, tunggu 10 detik, jalankan skrip lagi |
| Perangkat tidak ditemukan sama sekali | Beda jaringan, atau isolasi AP menyala | Samakan Wi-Fi; matikan *Client/AP isolation* pada router |
| Windows Firewall menanyakan | adb memerlukan izin jaringan | Pilih **Allow access** (izinkan) |
| Pemasangan terputus di tengah | Nirkabel lebih rentan putus | Jalankan skrip lagi - biasanya percobaan kedua berhasil |

Tambahan agar lebih tahan putus, di **Opsi pengembang** HP:

| Setelan | Nilai |
| --- | --- |
| Tetap terjaga saat mengisi daya (*Stay awake*) | AKTIF |
| Jangan simpan aktivitas (*Don't keep activities*) | MATI |
| Pilih konfigurasi USB default | Transfer file (tidak berpengaruh, hanya untuk kabel) |

### F. Menjalankan aplikasi dengan hot reload tanpa kabel

Setelah tersambung, nomor perangkat akan tampil di akhir skrip dan tersimpan di
`catatan_nirkabel.txt`. Pakai nomor itu:

```powershell
flutter run -d 192.168.1.7:37041
```

Nomor itu **berubah** setiap HP dimatikan atau berpindah jaringan, jadi selalu
periksa `catatan_nirkabel.txt` atau jalankan `PASANG_NIRKABEL.ps1` lagi.

### G. Kalau ternyata nirkabel sama sekali tidak bisa dipakai

Ada satu jalan lain yang masih tanpa kabel:

| Cara | Keterangan |
| --- | --- |
| Memasang APK langsung di HP | Salin `build\app\outputs\flutter-apk\app-debug.apk` ke HP (misalnya lewat WhatsApp *pesan ke diri sendiri*, Google Drive, atau kartu memori), lalu ketuk berkasnya di HP dan pilih **Pasang**. Perlu mengizinkan "Pasang dari sumber tidak dikenal" untuk aplikasi pengirim berkas itu |

Cara ini tidak memerlukan kabel **dan** tidak memerlukan nirkabel. Kekurangannya:
tidak bisa melihat log aplikasi dari komputer dan tidak ada hot reload.

### H. Urutan yang disarankan sekarang

| Nomor | Pekerjaan |
| --- | --- |
| 1 | Aktifkan Penelusuran nirkabel di HP (bagian B) |
| 2 | Jalankan `PASANG_NIRKABEL.ps1` |
| 3 | Periksa 4 hal di HP: login tampil, izin notifikasi, login username, kartu Firebase |
| 4 | Bila Firebase sudah **Aktif** - lanjutkan sisi server (kunci service account, `RTS_PANEL_FIREBASE.zip`, SQL device tokens) |
| 5 | Lanjutkan `UJI_APLIKASI.md` |

---

## BAGIAN 39 - ENAM PERUBAHAN BESAR: TAMPILAN, CUACA, IKLAN, IKON, PEMBARUAN OTOMATIS

Bagian ini menjelaskan enam permintaan Bapak dan cara memasangnya. Semua
perubahan **sudah dikerjakan** pada berkas yang dikirim bersama bagian ini.

### A. Ringkasan enam permintaan

| Nomor | Permintaan | Keadaan |
| --- | --- | --- |
| 1 | Tampilan aplikasi dibuat lebih halus dan rapi | **Selesai** - beranda disusun ulang, ukuran dan jarak dirapatkan |
| 2 | Kotak akun dibuat lebih kecil + laporan cuaca di sebelah Admin | **Selesai** - kotak cuaca muncul di kanan nama pengguna |
| 3 | Slot iklan banner di bawah kotak merah + iklan bentuk asli di setiap menu | **Selesai** - memakai kode uji Google, tinggal ganti kode milik Bapak |
| 4 | "Informasi Akun" pada beranda dihapus (cukup di Profil) | **Selesai** - digantikan slot iklan; keterangan akun lengkap tetap ada di Profil |
| 5 | Ikon Android memakai ikon RTS Panel, bukan ikon Flutter | **Selesai** - skrip membuat seluruh ukuran ikon + ikon adaptif |
| 6 | Aplikasi memeriksa versi dan menawarkan pembaruan otomatis | **Selesai** - halaman unggah APK di website + pemeriksaan otomatis saat aplikasi dibuka |

### B. Cara memasang (dua langkah saja)

| Nomor | Langkah |
| --- | --- |
| 1 | Ekstrak **RTS_PANEL_FITUR_BARU.zip** ke `D:\Project\rts_panel_app` - bila ditanya, pilih **Timpa/Replace** |
| 2 | Jalankan di terminal VS Code: `powershell -ExecutionPolicy Bypass -File .\PASANG_FITUR_BARU.ps1` |

Skrip itu mengerjakan seluruh pekerjaan sisi Android secara otomatis:

| Bagian | Tindakan skrip |
| --- | --- |
| 1 | Memeriksa `main.dart` dan `pubspec.yaml` benar-benar versi terbaru |
| 2 | Membuat ikon aplikasi semua ukuran (48 sampai 192 px) + ikon adaptif Android 8+ |
| 3 | Menambahkan izin INTERNET, izin AD_ID, dan kode aplikasi AdMob pada AndroidManifest.xml |
| 4 | Memeriksa hasil (ikon dan izin ada semua) |
| 5 | `flutter pub get` lalu membangun dan menjalankan aplikasi |

Semua berkas yang diubah dicadangkan lebih dahulu ke folder `cadangan_arena`.
Bila ingin memasang ikon dan izin saja tanpa membangun, tambahkan `-TanpaBuild`.

### C. Beranda baru (permintaan 1, 2, dan 4)

Susunan beranda sekarang:

| Urutan | Isi |
| --- | --- |
| 1 | Bilah atas: lambang R, nama aplikasi, penanda server, lonceng pemberitahuan, tombol keluar |
| 2 | Kotak akun (lebih kecil): nama, `@username`, **kotak cuaca di kanan**, role, District, Salesman |
| 3 | **Slot iklan banner** (di bawah kotak merah) |
| 4 | Menu Utama: enam kartu yang lebih rapat (tinggi 110 px, sebelumnya 142 px) |
| 5 | Keterangan versi aplikasi dan server |

Yang berubah dari tampilan lama:

| Sebelum | Sesudah |
| --- | --- |
| Kotak akun tinggi, jarak lebar | Kotak akun lebih pendek (padding 17/14/15/13), jarak antar bagian 12-14 px |
| Tidak ada cuaca | Kotak cuaca di kanan `@username` |
| Bagian "Informasi Akun" di bawah menu | Dihapus dari beranda, diganti slot iklan |
| Kartu menu tinggi 142 px dengan tulisan 2 baris | Tinggi 110 px, gambar 36 px, tulisan satu baris |

Keterangan akun lengkap (Nama, Username, Role, Hak Persetujuan, Level Akses,
Salesman, Sales District) tetap tersedia di halaman **Profil**.

### D. Laporan cuaca (permintaan 2)

| Hal | Keterangan |
| --- | --- |
| Sumber data | Open-Meteo (gratis, tanpa kunci API, tanpa pendaftaran) |
| Titik lokasi | Titik GPS petugas; bila izin lokasi belum diberikan, dipakai titik terakhir yang pernah tercatat |
| Isi | suhu saat ini, gambar cuaca, nama kota, keterangan cuaca hari ini |
| Masa berlaku | 30 menit; bila aplikasi dibuka lagi, data diambil ulang |
| Bila gagal | Kotak cuaca tidak ditampilkan sama sekali (tidak ada tampilan rusak) |

Aplikasi **tidak meminta izin lokasi** hanya untuk cuaca. Bila petugas sudah
pernah memakai fitur lokasi (misalnya Ganti Alamat), cuaca langsung tampil.

### E. Iklan AdMob (permintaan 3)

| Hal | Keterangan |
| --- | --- |
| Bentuk iklan 1 | **Banner** (kotak mendatar) di beranda, di bawah kotak merah |
| Bentuk iklan 2 | **Native** (bentuk asli, menyatu dengan tampilan) di beranda tidak dipakai; dipakai pada menu: Master Customer, Pengajuan, Notifikasi, Sinkronisasi, Profil, Pengaturan |
| Cara memasang iklan native | Memakai "native template" bawaan plugin - **tidak perlu menyentuh berkas Android sama sekali** |
| Kode unit iklan | Sementara memakai **kode uji resmi Google**, sehingga aman-aman saja walau akun AdMob belum disetujui |
| Bila iklan gagal dimuat | Kotak iklan tidak ditampilkan, aplikasi tetap lancar |

Cara mengganti dengan kode iklan milik Bapak (setelah akun AdMob disetujui):

| Nomor | Langkah |
| --- | --- |
| 1 | Buka https://admob.google.com - daftar - **Apps** - **Add app** - pilih Android |
| 2 | Isi nama paket: `com.example.rts_panel_app` |
| 3 | Buat unit iklan **Banner** dan **Native**, salin kodenya |
| 4 | Buka `main.dart`, cari `class RtsIklan` (bagian paling bawah berkas) |
| 5 | Ganti `bannerIklan` dan `nativeIklan` dengan kode milik Bapak |
| 6 | Ganti `APPLICATION_ID` pada `android\app\src\main\AndroidManifest.xml` dengan kode aplikasi AdMob Bapak (baris itu sudah disiapkan skrip, masih berisi kode uji) |
| 7 | Jalankan `PASANG_FITUR_BARU.ps1` lagi |
| 8 | Untuk mematikan seluruh iklan sementara: ubah `static const bool aktif = true;` menjadi `false` |

### F. Ikon aplikasi (permintaan 5)

Skrip membuat ikon RTS Panel (kotak marun bergradasi + huruf R putih) untuk:

| Folder | Isi |
| --- | --- |
| `mipmap-mdpi` sampai `mipmap-xxxhdpi` | `ic_launcher.png` dan `ic_launcher_round.png` (48, 72, 96, 144, 192 px) |
| `mipmap-*` (yang sama) | `ic_launcher_foreground.png` (108, 162, 216, 324, 432 px) |
| `mipmap-anydpi-v26` | `ic_launcher.xml` dan `ic_launcher_round.xml` (ikon adaptif Android 8+) |
| `drawable` | `ic_launcher_background.xml` (latar marun bergradasi) |

Ikon adaptif membuat bentuk luarnya mengikuti peluncur HP (bulat, kotak
membulat, atau sesuai merek HP), sehingga tampil rapi di semua perangkat.

### G. Pembaruan otomatis (permintaan 6)

**Cara kerja:**

| Nomor | Kejadian |
| --- | --- |
| 1 | Setiap aplikasi dibuka, beranda memeriksa berkas `apk/app_versi.json` di server |
| 2 | Bila kode versi di server lebih besar dari versi di HP, muncul kotak pemberitahuan pembaruan |
| 3 | Petugas menekan **PERBARUI SEKARANG** - berkas APK diunduh lewat peramban HP |
| 4 | Setelah terunduh, petugas membuka berkas itu dan memilih **Pasang** |
| 5 | Bila pembaruan bersifat **pilihan**, petugas dapat menekan **NANTI** (tidak muncul lagi untuk versi itu) |

**Catatan penting:** Android selalu meminta persetujuan saat memasang aplikasi
dari luar Play Store. Ini aturan Android, bukan kekurangan aplikasi - tidak ada
cara memasang diam-diam tanpa persetujuan pemilik HP.

**Halaman unggah di website:** `app_versi.php` (baru). Hanya akun ADMIN yang
dapat membukanya. Isinya:

| Bagian | Kegunaan |
| --- | --- |
| Formulir unggah | Pilih berkas APK, isi versi, kode versi, catatan, dan sifat wajib/pilihan |
| Daftar APK | Semua berkas APK di folder `apk/` beserta ukuran dan waktu unggah, bisa dihapus |
| Versi yang diumumkan | Ringkasan versi yang sedang berlaku beserta tautan unduhannya |
| Berkas keterangan | Isi `app_versi.json` yang dibaca aplikasi, bisa dibuka langsung untuk pemeriksaan |

**Cara merilis versi baru (untuk Bapak):**

| Nomor | Langkah |
| --- | --- |
| 1 | Buka `pubspec.yaml`, ubah `version: 1.1.0+2` menjadi misalnya `version: 1.2.0+3` (angka sesudah + selalu bertambah) |
| 2 | Jalankan `flutter build apk --release` |
| 3 | Buka website - menu **Versi Aplikasi** - unggah `build\app\outputs\flutter-apk\app-release.apk` dengan kode versi yang sama (3) |
| 4 | Selesai - seluruh tim menerima pemberitahuan saat membuka aplikasi |

**Cara memasang bagian website:**

| Nomor | Langkah |
| --- | --- |
| 1 | Ekstrak **RTS_PANEL_VERSI_APK.zip** ke `public_html` (satu folder dengan `dashboard.php`) |
| 2 | Pastikan terbentuk folder `public_html/apk/` berisi `app_versi.json` dan `index.html` |
| 3 | Buka `https://rts.benedic-s.com/app_versi.php` dengan akun ADMIN |
| 4 | Uji dengan menekan **Buka berkas** pada bagian Berkas Keterangan Versi |

Halaman ini **tidak mengubah database** sama sekali, jadi aman dipasang pada
produksi maupun staging. Bila folder `apk` tidak dapat dibuat otomatis, buat
manual lewat cPanel File Manager dengan izin 755.

### H. Akun Pro (rencana berikutnya)

Bagian "Informasi Akun" yang dihapus dari beranda kini digantikan kartu
**Rencana Akun** pada halaman Profil, yang menampilkan:

| Isi | Keterangan |
| --- | --- |
| Akun GRATIS (AKTIF) | Seluruh menu utama tetap dapat dipakai |
| Keterangan Akun PRO | Menu tambahan khusus pelanggan PRO akan ditambahkan pada pembaruan berikutnya |

Bila nanti Akun PRO dikerjakan, tinggal menambahkan menu baru pada beranda dan
menyambungkannya ke pembayaran - susunan beranda sekarang sudah disiapkan untuk
menampung menu ketujuh.

### I. Yang perlu diperiksa setelah aplikasi terpasang

| Nomor | Pemeriksaan | Hasil yang diharapkan |
| --- | --- | --- |
| 1 | Lihat ikon aplikasi pada layar HP | Kotak marun dengan huruf R putih, bukan ikon Flutter |
| 2 | Buka aplikasi - lihat beranda | Kotak akun lebih ringkas, ada kotak cuaca di kanan `@admin` |
| 3 | Lihat di bawah kotak merah | Muncul kotak iklan banner bertuliskan "Test Ad" |
| 4 | Buka menu Pengajuan | Ada kartu iklan bentuk asli di paling atas daftar |
| 5 | Buka menu Profil | Bagian Informasi Akun lengkap + kartu Rencana Akun |
| 6 | Buka menu Pengaturan | Ada bagian "Pembaruan Aplikasi" beserta versi terpasang |
| 7 | Tekan **PERIKSA PEMBARUAN SEKARANG** | Muncul keterangan "Aplikasi sudah memakai versi terbaru" |
| 8 | Buka `https://rts.benedic-s.com/app_versi.php` | Halaman unggah versi tampil (hanya untuk ADMIN) |

### J. Bila ada masalah

| Keadaan | Sebab dan penanganan |
| --- | --- |
| Aplikasi langsung tertutup saat dibuka | `APPLICATION_ID` belum ada pada AndroidManifest - jalankan `PASANG_FITUR_BARU.ps1` (bagian 3 menambahkannya) |
| Ikon masih ikon Flutter | Ikon lama tersimpan pada peluncur HP - cabut aplikasi lama, pasang ulang, atau tunggu beberapa saat lalu mulai ulang HP |
| Kotak iklan tidak muncul | Wajar bila tidak ada internet, atau akun AdMob belum aktif - iklan uji biasanya tetap muncul; periksa log dengan `flutter run` |
| Kotak cuaca tidak muncul | Izin lokasi belum pernah diberikan - buka menu Pengajuan - Ganti Alamat - ambil titik lokasi sekali, lalu buka beranda lagi |
| Pemberitahuan pembaruan tidak muncul | Berkas `apk/app_versi.json` belum ada atau `version_code` belum lebih besar dari versi di HP |
| "Aplikasi sudah memakai versi terbaru" padahal ada versi baru | Angka `version_code` pada halaman app_versi.php harus LEBIH BESAR dari angka sesudah + pada pubspec.yaml saat APK itu dibangun |
| Unggahan APK gagal | Ukuran APK melebihi batas server - naikkan `upload_max_filesize` dan `post_max_size` pada cPanel (misalnya 64M), lalu coba lagi |

---

## BAGIAN 40 - KODE IKLAN ADMOB BAPAK SUDAH DIPASANG

### A. Kode dari akun AdMob Bapak

Akun AdMob: **ca-app-pub-1905352530630884**

| Nomor | Kode | Letaknya | Keadaan |
| --- | --- | --- | --- |
| 1 | Kode aplikasi: `ca-app-pub-1905352530630884~8932651962` | `android/app/src/main/AndroidManifest.xml` | **SUDAH DIPASANG** - ditulis otomatis oleh `PASANG_FITUR_BARU.ps1` |
| 2 | Unit iklan **Banner**: `ca-app-pub-1905352530630884/6675189094` | `main.dart` - `class RtsIklan` - `bannerIklan` | **SUDAH DIPASANG** |
| 3 | Unit iklan **Native** | `main.dart` - `class RtsIklan` - `nativeIklan` | **BELUM ADA** - unitnya belum dibuat di AdMob |

Catatan: kode aplikasi memakai tanda `~` (tilde), kode unit iklan memakai tanda
`/` (garis miring). Keduanya berbeda dan tidak dapat ditukar.

### B. Yang masih perlu dibuat: unit iklan Native

Unit iklan yang dibuat Bapak (kode `6675189094`) berformat **Banner**, sehingga
belum dapat dipakai untuk iklan bentuk asli pada keenam menu. Sementara ini
aplikasi memakai kode **UJI resmi Google** untuk iklan native.

Cara membuat unit Native (sekitar 2 menit):

| Nomor | Langkah |
| --- | --- |
| 1 | Buka https://admob.google.com |
| 2 | Menu kiri **Apps** - pilih aplikasi RTS Panel |
| 3 | Menu kiri **Ad units** - tekan **ADD AD UNIT** |
| 4 | Pilih format **Native** - **Continue** |
| 5 | Isi nama, misalnya "RTS Panel Native" - **Save** |
| 6 | Salin kode yang bertanda garis miring (contoh: `ca-app-pub-1905352530630884/1234567890`) |
| 7 | Kirimkan kode itu ke saya, atau ganti sendiri baris `nativeIklan` pada `class RtsIklan` di `main.dart`, lalu jalankan `PASANG_FITUR_BARU.ps1` lagi |

### C. Yang berubah pada berkas

| Berkas | Perubahan |
| --- | --- |
| `main.dart` | `bannerIklan` diisi kode Bapak; ditambah `kodeAplikasi` sebagai catatan; keterangan modul iklan diperbarui |
| `PASANG_FITUR_BARU.ps1` | `$kodeAplikasiAdmob` diisi kode Bapak; skrip kini **memperbarui** kode aplikasi bila sudah ada di manifest (sebelumnya hanya menambah) |

Perbaikan penting pada skrip: sebelumnya, bila `APPLICATION_ID` sudah ada di
`AndroidManifest.xml` (misalnya masih kode uji dari percobaan sebelumnya), skrip
akan **melewatinya** dan kode Bapak tidak pernah terpasang. Sekarang kode lama
selalu digantikan dengan kode pada skrip.

### D. Hal yang perlu diketahui tentang iklan baru

| Hal | Keterangan |
| --- | --- |
| Waktu tunggu | Unit iklan baru dapat memerlukan waktu **paling lama satu jam** sebelum menampilkan iklan. Selama menunggu, kotak iklan tidak muncul dan aplikasi berjalan normal - ini bukan kesalahan |
| Jangan menekan iklan sendiri | Menekan iklan sendiri berulang kali dapat dianggap pelanggaran oleh Google dan berisiko akun dinonaktifkan. Cukup satu-dua kali untuk mencoba |
| Tampilan "Test Ad" | Selama masih memakai kode uji, yang muncul adalah tulisan "Test Ad" berwarna. Setelah kode Bapak terpasang, iklan asli yang muncul |
| Iklan kosong di staging | Wajar - AdMob dapat membatasi permintaan iklan dari data uji |

### E. Urutan yang disarankan sekarang

| Nomor | Pekerjaan |
| --- | --- |
| 1 | Ekstrak `RTS_PANEL_FITUR_BARU.zip` (isi terbaru) ke `D:\Project\rts_panel_app` - pilih Timpa |
| 2 | Jalankan `PASANG_NIRKABEL.ps1` bila HP belum tersambung (kabel USB rusak) |
| 3 | Jalankan `PASANG_FITUR_BARU.ps1` |
| 4 | Periksa di HP: ikon RTS Panel, kotak cuaca, kotak iklan banner di beranda, iklan di keenam menu |
| 5 | Buat unit iklan **Native** di AdMob, lalu kirimkan kodenya kepada saya untuk dipasang pada pembaruan berikutnya |

---

## BAGIAN 41 - SELURUH KODE IKLAN ADMOB SUDAH LENGKAP DAN TERPASANG

### A. Tiga unit iklan pada akun Bapak

Akun AdMob: **ca-app-pub-1905352530630884**

| Nomor | Nama unit di AdMob | Format | Kode unit | Keadaan pada aplikasi |
| --- | --- | --- | --- | --- |
| 1 | (kode aplikasi) | - | `ca-app-pub-1905352530630884~8932651962` | Terpasang pada AndroidManifest |
| 2 | **BANNER RTS** | Banner | `ca-app-pub-1905352530630884/6675189094` | Terpasang - beranda (bawah kotak merah) |
| 3 | **RTS Panel Native** | Native advanced | `ca-app-pub-1905352530630884/9404285058` | Terpasang - keenam menu |
| 4 | RTS Pop | Pembukaan aplikasi | `ca-app-pub-1905352530630884/3880022875` | Belum dipakai (cadangan) |

**Kode uji Google sudah tidak dipakai lagi.** Seluruh iklan kini memakai akun
Bapak sendiri, jadi tampilan "Test Ad" akan hilang dan digantikan iklan asli.

### B. Tentang unit "Native advanced"

Format ini **tepat** untuk iklan bentuk asli pada Flutter, karena memberi akses
penuh terhadap aset iklan (gambar, judul, isi, tombol) sehingga tampilannya
dapat disesuaikan dengan gaya aplikasi. Inilah sebabnya iklan pada keenam menu
dapat menyatu dengan tampilan RTS Panel, bukan berupa kotak iklan biasa.

### C. Tentang unit "RTS Pop" (belum dipakai)

Unit ini berformat **Pembukaan aplikasi** (App open ad): iklan menutupi seluruh
layar sesaat setelah aplikasi dibuka. Penghasilannya paling besar di antara
ketiga bentuk, tetapi **paling mengganggu** - untuk aplikasi kerja biasanya
tidak disarankan, karena petugas membuka aplikasi berkali-kali sehari.

Unit ini **tidak dipakai** untuk sekarang. Bila nanti ingin dipakai, cukup beri
tahu saya - penambahannya memerlukan satu bagian kode baru pada saat aplikasi
dibuka.

### D. Pembagian iklan per akun - menunggu keputusan Bapak

Keadaan sekarang: **iklan tampil untuk semua akun, termasuk ADMIN.**

Bila nanti ingin diatur, pilihannya:

| Pilihan | Keterangan |
| --- | --- |
| a | Iklan tetap tampil untuk semua akun (seperti sekarang) |
| b | Iklan hanya untuk akun GRATIS; Akun PRO (berbayar) bebas iklan |
| c | Iklan hanya untuk tingkat akses tertentu |

Saya **belum** mengubah apa pun untuk hal ini, karena Bapak belum memutuskan.

### E. Yang berubah pada berkas

| Berkas | Perubahan |
| --- | --- |
| `main.dart` | `nativeIklan` diisi kode Bapak; keterangan modul iklan diperbarui; kode uji Google dibuang seluruhnya |
| `KODE_ADMOB.txt` | Catatan ketiga unit iklan, cara mematikan iklan, dan pilihan pembagian iklan |
| `RTS_PANEL_FITUR_BARU.zip` | Dibuat ulang memuat semua perubahan di atas |

### F. Yang perlu diperiksa setelah aplikasi terpasang

| Nomor | Pemeriksaan | Hasil yang diharapkan |
| --- | --- | --- |
| 1 | Buka beranda | Kotak iklan di bawah kotak merah akun |
| 2 | Buka menu Pengajuan / Master Customer | Kartu iklan bentuk asli di paling atas daftar |
| 3 | Buka menu Profil / Pengaturan / Sinkronisasi / Notifikasi | Kartu iklan bentuk asli tampil |
| 4 | Teks "Test Ad" | Sudah tidak muncul lagi (kode uji sudah dibuang) |

Catatan: unit iklan baru biasanya perlu waktu **paling lama satu jam** sebelum
mulai menampilkan iklan. Selama menunggu, kotak iklan tidak muncul dan aplikasi
berjalan normal - bukan kesalahan.

### G. Bila iklan tidak muncul

| Keadaan | Sebab yang mungkin dan penanganan |
| --- | --- |
| Kosong sama sekali selama beberapa jam | Periksa "Kontrol pemblokiran" pada AdMob - pastikan aplikasi tidak dibatasi |
| Muncul kadang-kadang | Wajar - ketersediaan iklan bergantung pada permintaan pengiklan pada saat itu |
| Tidak muncul pada satu menu saja | Periksa keluaran `flutter run` - cari tulisan `onAdFailedToLoad` beserta kodenya, lalu kirimkan ke saya |
| Muncul di beranda tetapi tidak pada menu | Kemungkinan unit Native advanced belum melayani permintaan - tunggu satu jam, lalu coba lagi |

---

## BAGIAN 42 - ATURAN IKLAN: HANYA UNTUK AKUN GRATIS (PILIHAN B)

### A. Aturan yang diterapkan

| Tingkat akun | Iklan pada beranda (banner) | Iklan pada keenam menu (native) |
| --- | --- | --- |
| **GRATIS** | Tampil | Tampil |
| **PRO** | Tidak tampil | Tidak tampil |

Akun PRO **bebas iklan sepenuhnya** - bukan hanya iklan yang dikurangi.

### B. Bagaimana aplikasi mengetahui sebuah akun PRO

| Nomor | Kejadian |
| --- | --- |
| 1 | Server menyimpan penanda pada kolom `akun_pro` di tabel `sales_users` (1 = PRO, 0 = GRATIS) |
| 2 | Saat login, `api/login.php` mengirim penanda itu bersama data akun |
| 3 | Saat aplikasi dibuka dengan "Ingat saya", `api/session_check.php` mengirim penanda yang sama |
| 4 | Aplikasi menyimpannya pada sesi, lalu memakai `RtsTingkatAkun.pro` untuk menentukan iklan tampil atau tidak |
| 5 | `RtsIklan.aktif` bernilai true hanya bila akun **bukan** PRO dan saklar utama menyala |

Karena penanda ini datang dari server, **pengguna tidak dapat memalsukannya**
dari HP - berbeda bila statusnya hanya disimpan di aplikasi.

### C. Selama kolom database belum ada

API memeriksa keberadaan kolom `akun_pro` lebih dahulu (berkas baru
`api/kolom.php`). Bila kolomnya belum ada:

| Hal | Akibatnya |
| --- | --- |
| API | Tetap berjalan normal - memakai nilai bawaan 0 |
| Aplikasi | Seluruh akun dianggap GRATIS, iklan tampil seperti biasa |
| Halaman `akun_pro.php` | Menampilkan petunjuk cara membuat kolomnya |

Jadi **tidak ada yang rusak** bila berkas PHP dipasang lebih dahulu sebelum
kolomnya dibuat.

### D. Cara menandai akun PRO

**Urutan yang disarankan (uji coba lebih dahulu):**

| Nomor | Langkah |
| --- | --- |
| 1 | Jalankan `RTS_PANEL_AKUN_PRO.sql` pada database **uji coba** (`benedics_coba`) lewat phpMyAdmin - tab SQL - tempel - Go |
| 2 | Unggah semua berkas `RTS_PANEL_AKUN_PRO.zip` ke `public_html` (berkas `api/*` ke folder `api/`) |
| 3 | Buka `https://coba.benedic-s.com/akun_pro.php` - tekan **Jadikan PRO** pada satu akun uji |
| 4 | Buka aplikasi dengan akun itu - iklan harus hilang |
| 5 | Setelah staging berhasil **dan database produksi sudah di-backup**: ulangi langkah 1-2 pada produksi |

**Perintah SQL-nya (hanya menambah kolom, tidak mengubah data):**

```sql
ALTER TABLE sales_users ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;
```

### E. Uji coba tanpa mengubah database

Pada halaman **Profil** aplikasi tersedia saklar **"Uji coba Akun PRO"**
(khusus ADMIN). Menyalakannya akan menyembunyikan seluruh iklan untuk mencoba
tampilan bebas iklan, tanpa perlu membuat kolom database.

Catatan: perubahan saklar ini terlihat setelah **kembali ke beranda** atau
aplikasi dibuka ulang, karena kotak iklan sudah terbentuk pada tampilan
sebelumnya.

### F. Halaman akun_pro.php

| Bagian | Kegunaan |
| --- | --- |
| Ringkasan | Jumlah akun seluruhnya, jumlah PRO, jumlah GRATIS |
| Daftar akun | Nama, email, username, role, district, status aktif, dan tingkat akun |
| Tombol ubah | "Jadikan PRO" atau "Jadikan GRATIS" pada tiap akun |
| Pencarian | Menyaring daftar menurut nama, username, atau email |
| Petunjuk | Muncul otomatis bila kolom database belum ada, lengkap dengan perintah SQL-nya |

Keamanan halaman ini:

| Hal | Keterangan |
| --- | --- |
| Hanya ADMIN | Role lain diarahkan kembali ke dashboard |
| Akun sendiri | Tidak dapat diubah menjadi GRATIS, agar ADMIN tidak terkunci dari halaman ini |
| Data yang diubah | Hanya kolom `akun_pro` - kolom lain tidak disentuh |
| Password | Tidak pernah ditampilkan |

### G. Berkas yang berubah

| Berkas | Keadaan | Isi |
| --- | --- | --- |
| `main.dart` | Diperbarui | `RtsUser.akunPro`, modul `RtsTingkatAkun`, `RtsIklan.aktif` mengikuti tingkat akun, kartu Rencana Akun menampilkan tingkat + saklar uji |
| `api/kolom.php` | **Berkas baru** | Pemeriksaan keberadaan kolom |
| `api/login.php` | Diperbarui | Mengirim `akun_pro` |
| `api/session_check.php` | Diperbarui | Mengirim `akun_pro` |
| `api/api_bootstrap.php` | Diperbarui | Membaca `akun_pro` dari database |
| `akun_pro.php` | **Berkas baru** | Halaman pengaturan akun PRO |
| `RTS_PANEL_AKUN_PRO.sql` | **Berkas baru** | Menambah kolom `akun_pro` |
| `KODE_ADMOB.txt` | Diperbarui | Aturan pembagian iklan |
| `RTS_PANEL_FITUR_BARU.zip` | Dibuat ulang | Memuat `main.dart` terbaru |
| `RTS_PANEL_AKUN_PRO.zip` | **Paket baru** | Seluruh berkas akun PRO + cara pasang |

### H. Bila ada masalah

| Keadaan | Sebab dan penanganan |
| --- | --- |
| Halaman akun_pro.php menampilkan peringatan kolom | Jalankan SQL-nya lebih dahulu (perintah tersedia di halaman itu) |
| Status PRO berubah di website tetapi iklan masih tampil | Pengguna perlu **login kembali** - status dibaca saat login |
| Iklan tetap tampil walau akun sudah PRO | Periksa `api/login.php` dan `api/session_check.php` benar-benar yang baru (bukan berkas lama yang tertinggal) |
| Muncul "Duplicate column name 'akun_pro'" | Kolomnya sudah ada - tidak perlu dikerjakan lagi, tidak ada yang rusak |
| Ingin mematikan SELURUH iklan sementara | Ubah `static const bool saklarIklan = true;` menjadi `false` pada `class RtsIklan` di `main.dart` |

---

## BAGIAN 43 - MEMPERBAIKI ERROR "Target of URI doesn't exist: google_mobile_ads"

### A. Apa yang terjadi

Setelah `main.dart` versi baru dipasang, VS Code menampilkan **268 masalah** dengan
keluhan yang berulang-ulang seperti:

```
Target of URI doesn't exist: 'package:google_mobile_ads/google_mobile_ads.dart'
Undefined name 'MobileAds'
Undefined class 'BannerAd'
Undefined class 'AdSize'
Undefined class 'NativeAd'
The method 'AdWidget' isn't defined for the type '_RtsBannerIklanState'
Undefined name 'TemplateType'
```

**Semua tulisan itu satu sebab saja:** paket `google_mobile_ads` belum terdaftar
di `pubspec.yaml` proyek Bapak, sehingga Dart tidak mengenal seluruh nama yang
berhubungan dengan iklan (MobileAds, BannerAd, NativeAd, AdSize, AdWidget, dan
seterusnya).

Urutannya begini:

| Nomor | Kejadian |
| --- | --- |
| 1 | `main.dart` versi baru sudah masuk proyek (memakai paket iklan dan paket versi) |
| 2 | `pubspec.yaml` belum ikut diperbarui, sehingga paketnya tidak terdaftar |
| 3 | `flutter pub get` belum dijalankan, sehingga paketnya belum terpasang |
| 4 | Dart melaporkan seluruh nama paket sebagai "tidak dikenal" |

### B. Perbaikannya

Simpan **`PERBAIKI_PUBSPEC.ps1`** di `D:\Project\rts_panel_app`, lalu:

```powershell
powershell -ExecutionPolicy Bypass -File .\PERBAIKI_PUBSPEC.ps1
```

Skrip itu **menulis sendiri** bagian yang kurang, jadi tidak ada penyalinan manual:

| Bagian | Tindakan skrip |
| --- | --- |
| 1 | Mencadangkan `pubspec.yaml` ke `cadangan_arena\pubspec.yaml.asli` |
| 2 | Memeriksa apakah `google_mobile_ads` dan `package_info_plus` sudah terdaftar |
| 3 | Menyisipkan paket yang kurang **pada bagian dependencies**, tanpa menyentuh bagian lain (nama proyek, daftar assets, dan paket Bapak yang lain tetap utuh) |
| 4 | Memastikan folder `assets/images` terdaftar |
| 5 | Memastikan `version:` sudah siap untuk pembaruan otomatis (`1.1.0+2`) |
| 6 | Menjalankan `flutter pub get` |
| 7 | **Memeriksa hasilnya** pada `.dart_tool/package_config.json` dan `pubspec.lock` |

### C. Menghilangkan tulisan merah di VS Code

Setelah skrip selesai dan menampilkan `SELESAI - PAKET SUDAH TERPASANG`:

| Nomor | Langkah |
| --- | --- |
| 1 | Di VS Code tekan **Ctrl + Shift + P** |
| 2 | Ketik: `Dart: Restart Analysis Server` |
| 3 | Tekan Enter |
| 4 | Bila masih ada tulisan merah pada baris impor, tutup lalu buka kembali `main.dart` |

Jumlah masalah pada panel **Problems** akan turun dari 268 menjadi hampir nol.

### D. Bila skrip melaporkan MASALAH

| Pesan | Sebab dan penanganan |
| --- | --- |
| `pub get` gagal, tidak ada tulisan error jelas | Periksa sambungan internet komputer |
| `version solving failed` | Ada paket yang versinya bentrok - kirimkan bagian itu kepada saya |
| `google_mobile_ads BELUM terpasang` | Jalankan `flutter pub get` sekali lagi, atau kirimkan keluaran lengkapnya |
| `.dart_tool\package_config.json belum ada` | Pub get belum pernah berhasil dijalankan pada proyek ini |

### E. Mengapa ini tidak terjadi saat build pertama

Build Firebase sebelumnya hanya memerlukan `firebase_core`, `firebase_messaging`,
`geolocator`, `geocoding`, dan `flutter_local_notifications` - semuanya sudah
terdaftar pada `pubspec.yaml` waktu itu. Paket **iklan** (`google_mobile_ads`) dan
paket **versi** (`package_info_plus`) baru ditambahkan pada pembaruan ini, jadi
keduanya harus didaftarkan lebih dahulu sebelum aplikasi dapat dibangun.

### F. Ringkasan perintah untuk pembaruan ini

| Nomor | Perintah | Gunanya |
| --- | --- | --- |
| 1 | `powershell -ExecutionPolicy Bypass -File .\PERBAIKI_PUBSPEC.ps1` | Mendaftarkan paket iklan + menjalankan pub get |
| 2 | `Ctrl + Shift + P` - `Dart: Restart Analysis Server` | Membersihkan tulisan merah di VS Code |
| 3 | `powershell -ExecutionPolicy Bypass -File .\PASANG_FITUR_BARU.ps1` | Ikon, izin iklan, lalu membangun dan memasang ke HP |

---

## BAGIAN 44 - MEMPERBAIKI ERROR #1044 PADA RTS_PANEL_AKUN_PRO

### A. Kesalahan yang muncul

Saat berkas `RTS_PANEL_AKUN_PRO.sql` dijalankan pada phpMyAdmin, muncul:

```
#1044 - Access denied for user 'cpses_begpopoyvq'@'localhost'
        to database 'information_schema'
```

### B. Penyebabnya

Berkas SQL versi 1 saya memakai tabel **information_schema** untuk memeriksa
apakah kolomnya sudah ada:

```sql
SELECT COUNT(*) FROM information_schema.COLUMNS   <-- baris ini penyebabnya
WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'sales_users' ...
```

Akun database pada hosting cPanel **tidak diberi izin membaca tabel
information_schema**. Karena baris itu berada paling atas, phpMyAdmin
**berhenti di situ** dan perintah `ALTER TABLE` (yang sebenarnya menambah kolom)
**tidak pernah dijalankan**.

Catatan: tabel itu milik sistem MySQL, bukan tabel data Bapak - jadi tidak ada
data Bapak yang tersentuh. Yang gagal hanyalah langkah pemeriksaannya.

### C. Perbaikannya (versi 2)

| Berkas | Perubahan |
| --- | --- |
| `RTS_PANEL_AKUN_PRO.sql` | Tidak lagi memakai `information_schema` - diganti `SHOW COLUMNS` yang selalu tersedia |
| `akun_pro.php` | Pemeriksaan kolom juga diganti memakai `SHOW COLUMNS` |
| `api/kolom.php` | Fungsi `rts_api_ada_kolom()` diganti memakai `SHOW COLUMNS` |
| `api/login.php` | Fungsi pemeriksa kolom lama juga disamakan |

Seluruh berkas PHP yang diperbarui ini **memakai nama tabel dan kolom yang
diperiksa dengan pola huruf/angka saja** sebagai pengaman tambahan.

### D. Cara tercepat menjalankan (satu baris saja)

Sebenarnya hanya **satu baris** yang benar-benar diperlukan:

```sql
ALTER TABLE sales_users ADD COLUMN akun_pro TINYINT(1) NOT NULL DEFAULT 0;
```

| Nomor | Langkah |
| --- | --- |
| 1 | Buka cPanel - phpMyAdmin |
| 2 | Klik database `benedics_bene_sales` pada panel kiri |
| 3 | Klik tab **SQL** |
| 4 | Tempel satu baris di atas, klik **Kirim** |
| 5 | Bila muncul `#1060 - Duplicate column name 'akun_pro'`, artinya kolomnya **sudah ada** - tidak ada yang rusak, lanjut saja |

Perintah pemeriksaan dan ringkasan yang ada di dalam berkas SQL sifatnya
**pilihan** - tidak diperlukan untuk keberhasilan.

### E. Bila ingin memakai berkas lengkapnya

Berkas `RTS_PANEL_AKUN_PRO.sql` versi 2 sudah **tidak memakai
information_schema**, sehingga seluruh isinya dapat dijalankan sekaligus:

| Urutan | Isi berkas |
| --- | --- |
| LANGKAH 1 | `SHOW COLUMNS FROM sales_users LIKE 'akun_pro'` - pemeriksaan |
| LANGKAH 2 | `ALTER TABLE sales_users ADD COLUMN akun_pro ...` - menambah kolom |
| LANGKAH 3 | `SHOW COLUMNS ...` - memastikan kolomnya sudah ada |
| LANGKAH 4 | Ringkasan jumlah akun PRO dan GRATIS |

### F. Urutan pemasangan yang disarankan

| Nomor | Langkah |
| --- | --- |
| 1 | Jalankan perintah SQL pada database **uji coba** (`benedics_coba`) |
| 2 | Unggah seluruh berkas `RTS_PANEL_AKUN_PRO.zip` **versi 2** ke `public_html` |
| 3 | Buka `https://coba.benedic-s.com/akun_pro.php` - pastikan daftar akun tampil (bukan peringatan kolom) |
| 4 | Tekan **Jadikan PRO** pada satu akun uji, lalu buka aplikasi memakai akun itu - iklan harus hilang |
| 5 | Setelah staging berhasil **dan produksi sudah di-backup**, ulangi langkah 1-2 pada produksi |

### G. Bila masih ada kesalahan lain

| Pesan | Sebab dan penanganan |
| --- | --- |
| `#1044 ... information_schema` | Berkas SQL versi lama masih dipakai - pakai versi 2, atau jalankan satu baris `ALTER TABLE` pada bagian D |
| `#1060 Duplicate column name 'akun_pro'` | Kolomnya sudah ada - abaikan, lanjut ke langkah website |
| `#1144 Access denied` pada `ALTER TABLE` | Akun database tidak berhak mengubah tabel - beri **ALL PRIVILEGES** lewat cPanel - MySQL Databases |
| `#1146 Table 'sales_users' doesn't exist` | Database yang dipilih salah - pastikan `benedics_bene_sales` (produksi) atau `benedics_coba` (uji coba) |
| Halaman `akun_pro.php` masih menampilkan peringatan kolom | Muat ulang dengan **Ctrl+F5**; bila tetap, pastikan yang diunggah adalah berkas dari paket versi 2 |


## BAGIAN 45 - CUACA BERANDA BELUM TAMPIL (IZIN LOKASI) + TABEL VERSI APLIKASI DI DATABASE

Bagian ini menjawab dua hal yang Bapak tanyakan:

1. **Kenapa laporan cuaca di samping nama Admin belum tampil**, dan bagaimana
   cara memperbaikinya.
2. **Bagaimana caranya mengunggah APK terbaru lewat website** dan menyimpan
   keterangan versi pada database phpMyAdmin supaya aplikasi dapat memperbarui
   diri sendiri.

---

### A. SEBAB CUACA BELUM TAMPIL

Ada **dua sebab** yang ditemukan, dan keduanya sudah diperbaiki:

| Nomor | Sebab | Akibat yang terlihat |
| --- | --- | --- |
| 1 | Izin lokasi belum ada pada `AndroidManifest.xml` | Android menolak permintaan GPS secara diam-diam - tidak muncul pertanyaan izin sama sekali |
| 2 | Kode lama hanya **memeriksa** izin, tidak pernah **meminta** izin | Walaupun izin sudah ada, aplikasi tidak pernah meminta sehingga tetap gagal |

Penjelasan singkat:

- Aplikasi ini memakai paket `geolocator` untuk membaca titik GPS. Paket itu
  **tidak** menambahkan izin lokasi sendiri - izin harus ditulis pada
  `AndroidManifest.xml` aplikasi.
- Tanpa izin tersebut, permintaan lokasi langsung gagal tanpa pertanyaan apa
  pun di layar HP. Itulah sebabnya kotak cuaca tampak kosong atau tidak muncul.

**Perbaikannya sudah dikerjakan lengkap:**

| Nomor | Perbaikan | Berkas |
| --- | --- | --- |
| 1 | Kode aplikasi sekarang **meminta izin sendiri**: memeriksa GPS hidup, memeriksa izin, meminta izin, dan menangani penolakan permanen | `main.dart` |
| 2 | Skrip pemasang sekarang **menambahkan izin lokasi otomatis** ke `AndroidManifest.xml` | `PASANG_FITUR_BARU.ps1` |
| 3 | Ada **kartu pemeriksa "Cuaca Beranda"** pada halaman Pengaturan untuk melihat sebabnya secara langsung | `main.dart` |

---

### B. CARA MEMASANG PERBAIKAN CUACA

**Langkah 1 - Timpa berkas aplikasi**

Ekstrak `RTS_PANEL_FITUR_BARU.zip` ke `D:\Project\rts_panel_app` lalu pilih
**Timpa (Replace)**.

**Langkah 2 - Perbaiki pubspec bila perlu**

Jalankan `PERBAIKI_PUBSPEC.ps1`.

**Langkah 3 - Pasang fitur (sekaligus izin lokasi)**

Jalankan `PASANG_FITUR_BARU.ps1`.

Skrip itu sekarang mencetak baris seperti berikut - tanda bahwa izin sudah
masuk:

```text
   DITAMBAH: izin android.permission.ACCESS_FINE_LOCATION
   DITAMBAH: izin android.permission.ACCESS_COARSE_LOCATION
   ...
   [ADA] izin lokasi ACCESS_FINE_LOCATION ada pada manifest
   [ADA] izin lokasi ACCESS_COARSE_LOCATION ada pada manifest
```

Bila tertulis **sudah ada**, berarti izin memang sudah pernah ditambahkan -
tidak masalah, tidak akan ditulis dua kali.

**Langkah 4 - Pasang aplikasi ke HP**

Jalankan `PASANG_NIRKABEL.ps1` (kabel USB Bapak rusak - tetap memakai
penelusuran nirkabel).

**Langkah 5 - Buka aplikasi**

Saat aplikasi dibuka, Android akan menanyakan:

```text
Izinkan RTS Panel mengakses lokasi perangkat ini?
```

Pilih **Saat aplikasi digunakan (While using the app)** atau **Izinkan**.

Setelah itu laporan cuaca pada kartu merah akan terisi sendiri, dan titik
lokasi dipakai juga oleh tombol "Sesuai Koordinat Sekarang" pada form Ganti
Alamat.

---

### C. CARA MEMERIKSA BILA CUACA MASIH BELUM TAMPIL

Buka menu **Profil - Pengaturan**, lalu lihat bagian **CUACA BERANDA**.

| Tulisan pada baris "Keadaan" | Artinya | Tindakan |
| --- | --- | --- |
| `Menyiapkan laporan cuaca...` | Masih mengambil data | Tunggu sebentar, lalu tekan AMBIL LAPORAN CUACA SEKARANG |
| `Izin lokasi belum diberikan.` | Pertanyaan izin belum dijawab | Tekan AMBIL LAPORAN CUACA SEKARANG - pertanyaan izin akan muncul |
| `Izin lokasi ditolak. Buka Pengaturan HP...` | Pernah ditolak permanen | Buka Pengaturan HP - Aplikasi - RTS Panel - Izin - Lokasi - Izinkan |
| `Layanan lokasi HP sedang dimatikan.` | GPS HP mati | Nyalakan GPS (Lokasi) pada HP |
| `Lokasi belum terbaca.` | GPS belum mendapat titik | Pindah ke tempat terbuka, ulangi sebentar lagi |
| `Laporan cuaca siap.` | Berhasil | Cuaca seharusnya sudah tampil pada beranda |
| `Tidak dapat menghubungi layanan cuaca.` | Internet bermasalah atau layanan cuaca sedang gangguan | Periksa koneksi internet HP |

Tombol **AMBIL LAPORAN CUACA SEKARANG** berguna untuk mencoba ulang tanpa
harus menutup aplikasi.

Catatan: laporan cuaca memakai layanan gratis **Open-Meteo** dan **tidak
memerlukan kunci API** apa pun, jadi tidak ada yang perlu diatur di website.

---

### D. TABEL VERSI APLIKASI PADA DATABASE (SUMBER KETERANGAN PEMBARUAN)

Sebelumnya keterangan versi hanya disimpan pada berkas `apk/app_versi.json`.
Sekarang keterangan itu **juga disimpan pada database** supaya:

- seluruh riwayat unggahan APK terekam (versi, tanggal, ukuran, admin yang
  mengunggah);
- aplikasi tetap dapat memeriksa pembaruan walaupun berkas JSON terhapus atau
  gagal ditulis.

**Langkah 1 - Buat tabelnya (sekali saja)**

Buka cPanel - phpMyAdmin - pilih database - tab **SQL** - tempel seluruh isi
berkas berikut - klik **Kirim**:

```text
database/migrations/RTS_PANEL_APP_VERSI.sql
```

Kolom yang dibuat:

| Kolom | Isi |
| --- | --- |
| `version_code` | angka sesudah tanda `+` pada `pubspec.yaml`, contoh 3 |
| `version_name` | angka sebelum tanda `+`, contoh `1.2.0` |
| `wajib` | `1` bila pembaruan wajib, `0` bila hanya pilihan |
| `catatan` | catatan pembaruan yang dibaca petugas |
| `apk` | alamat unduhan berkas APK |
| `ukuran_mb` | ukuran berkas APK |
| `diunggah_oleh` | email admin yang mengunggah |
| `aktif` | `1` = versi yang diumumkan ke seluruh HP |
| `dibuat_pada` | waktu unggahan |

Berkas SQL ini **tidak memakai `information_schema`**, jadi tidak akan
menimbulkan kesalahan #1044 seperti yang lalu.

Bila tabelnya belum dibuat, semuanya tetap berjalan seperti biasa - aplikasi
otomatis memakai berkas `apk/app_versi.json`. Jadi urutan pengerjaannya bebas.

**Langkah 2 - Unggah berkas website**

Unggah isi `RTS_PANEL_VERSI_APK.zip` ke `public_html` (isi terbaru):

| Berkas | Kegunaan |
| --- | --- |
| `app_versi.php` | Halaman unggah APK + pengaturan versi (menu website) |
| `api/app_versi.php` | Halaman API yang dibaca aplikasi |
| `apk/` | Folder tempat berkas APK dan `app_versi.json` disimpan |

**Langkah 3 - Unggah APK lewat website**

Buka `https://rts.benedic-s.com/app_versi.php`, isi:

| Kolom | Contoh isi |
| --- | --- |
| Nama versi | `1.2.0` |
| Kode versi | `3` |
| Wajib diperbarui | centang bila seluruh petugas harus memperbarui |
| Catatan pembaruan | `Perbaikan filter GSP dan tampilan beranda.` |
| Berkas APK | pilih `app-release.apk` hasil build |

Setelah **Simpan**, halaman itu:

1. menyimpan berkas APK ke `apk/`,
2. menulis `apk/app_versi.json`,
3. mencatat baris baru ke tabel `rts_app_versi`,
4. menampilkan tabel **Riwayat Versi** pada bagian bawah halaman.

**Langkah 4 - Aplikasi memeriksa sendiri**

Setiap kali aplikasi dibuka, aplikasi membaca keterangan versi dari dua jalur
secara berurutan:

```text
1. https://rts.benedic-s.com/api/app_versi.php   (dari database - utama)
2. https://rts.benedic-s.com/apk/app_versi.json  (cadangan)
```

Bila kode versi di server **lebih besar** daripada versi yang terpasang di HP,
muncul kotak pemberitahuan pembaruan lengkap dengan tombol unduh dan (bila
ditandai wajib) tombol itu tidak dapat dilewati.

---

### E. URUTAN PENGERJAAN YANG DISARANKAN

| Nomor | Kegiatan | Tempat |
| --- | --- | --- |
| 1 | Jalankan `RTS_PANEL_APP_VERSI.sql` pada database **uji coba** (`benedics_coba`) | phpMyAdmin |
| 2 | Unggah isi `RTS_PANEL_VERSI_APK.zip` ke `public_html` | cPanel - File Manager |
| 3 | Buka `https://coba.benedic-s.com/app_versi.php`, unggah satu APK percobaan | Browser |
| 4 | Pastikan tabel Riwayat Versi terisi dan `apk/app_versi.json` ada | Browser + File Manager |
| 5 | Timpa `main.dart` dari `RTS_PANEL_FITUR_BARU.zip`, jalankan `PASANG_FITUR_BARU.ps1` | Komputer |
| 6 | Pasang ke HP dengan `PASANG_NIRKABEL.ps1`, izinkan lokasi saat ditanya | HP |
| 7 | Setelah semua lancar, ulangi langkah 1-2 pada produksi | cPanel |

---

### F. BILA ADA KENDALA

| Kejadian | Sebab dan penanganan |
| --- | --- |
| Halaman `app_versi.php` menampilkan peringatan tabel belum ada | Tabel `rts_app_versi` belum dibuat - jalankan `RTS_PANEL_APP_VERSI.sql` (halaman tetap bisa dipakai) |
| Unggahan berhasil, tetapi riwayat database kosong | Berkas `app_versi.php` yang diunggah masih versi lama - unggah yang terbaru dari `RTS_PANEL_VERSI_APK.zip` |
| `#1060 Duplicate column name` | Tidak ada pada berkas ini - hanya berlaku untuk bagian akun PRO |
| Aplikasi tidak menawarkan pembaruan | Kode versi di server harus **lebih besar** daripada `version` pada `pubspec.yaml`, dan `aktif` harus `1` |
| Pertanyaan izin lokasi tidak muncul di HP | Buka Pengaturan HP - Aplikasi - RTS Panel - Izin - Lokasi - pilih **Izinkan** |
| Cuaca tampil, tetapi kotanya tidak sesuai | Titik lokasi murni dari GPS HP - bukan kesalahan aplikasi; kartu cuaca memang mengikuti posisi petugas |

## BAGIAN 46 - MENU "VERSI APLIKASI" PADA DASHBOARD WEBSITE

### A. MASALAHNYA

Halaman pengunggahan APK sebenarnya **sudah ada** sejak BAGIAN 45
(`app_versi.php`), tetapi **belum ada menu yang menunjuk ke halaman itu** pada
dashboard. Akibatnya, halaman tersebut hanya dapat dibuka bila alamatnya
diketik langsung pada browser - dan itu tidak praktis.

Perbaikannya: menambahkan menu **Versi Aplikasi** pada sisi kiri dashboard,
tepat di bawah **Kelola User**, pada bagian **ADMINISTRASI**.

Menu ini **hanya tampil untuk akun berperan ADMIN**, sesuai aturan bahwa hanya
Admin yang mengurusi pembaruan aplikasi. Akun ASS, WSS, SMST, RTS, dan TF tidak
melihat menu tersebut - jadi tampilan mereka tetap bersih seperti sebelumnya.

### B. YANG BERUBAH

| Berkas | Perubahan |
| --- | --- |
| `sidebar.php` | Menu baru **Versi Aplikasi** (ikon HP) pada bagian ADMINISTRASI, hanya ADMIN |
| `dashboard_updated.php` | Kartu **Versi Aplikasi Android** + tombol **Kelola Versi Aplikasi**, dan pintasan **Versi APK** pada baris pintasan bawah - keduanya hanya ADMIN |

Menu pada sidebar adalah bagian yang **wajib** dipasang. Kartu pada dashboard
bersifat **pilihan** (boleh dilewati).

### C. CARA MEMASANG

| Nomor | Kegiatan |
| --- | --- |
| 1 | Unggah `sidebar.php` dari paket `RTS_PANEL_VERSI_APK.zip` ke `public_html` (timpa) |
| 2 | Buka dashboard, tekan **Ctrl+F5** |
| 3 | Menu **Versi Aplikasi** tampil di bawah **Kelola User** |
| 4 | Klik menu itu - halaman unggah APK terbuka |

Bila ingin kartu pintasan juga tampil pada dashboard (pilihan):

| Nomor | Kegiatan |
| --- | --- |
| 1 | Unggah `dashboard_updated.php` ke `public_html` |
| 2 | Lewat File Manager, ubah namanya menjadi `dashboard.php` (unduh dulu yang lama sebagai cadangan) |
| 3 | Tekan **Ctrl+F5** pada dashboard |

Catatan: berkas `dashboard_updated.php` yang belum diganti nama tidak mengubah
apa pun - berkas itu hanya cadangan yang belum dipakai website.

### D. BILA MENU BELUM TAMPAK

| Kejadian | Sebab dan penanganan |
| --- | --- |
| Menu tidak tampak | Akun yang dipakai bukan ADMIN - menu ini sengaja hanya untuk ADMIN |
| Menu tidak tampak pada akun ADMIN | Berkas `sidebar.php` belum diunggah ke `public_html`, atau browser masih memakai tampilan lama - tekan **Ctrl+F5**, atau keluar lalu masuk kembali |
| Menu diklik, muncul **404 Not Found** | Berkas `app_versi.php` belum diunggah - lihat BAGIAN 45 LANGKAH 2 |
| Halaman terbuka, tetapi muncul peringatan tabel belum ada | Tabel `rts_app_versi` belum dibuat - jalankan `RTS_PANEL_APP_VERSI.sql`; halaman tetap dapat dipakai walau tabel belum ada |
| Halaman terbuka, lalu kembali ke dashboard | Akun bukan ADMIN - halaman `app_versi.php` memang mengalihkan pengunjung non-ADMIN ke dashboard |

### E. URUTAN LENGKAP DARI NOL (RINGKAS)

| Nomor | Kegiatan | Berkas |
| --- | --- | --- |
| 1 | Jalankan SQL tabel versi | `database/migrations/RTS_PANEL_APP_VERSI.sql` |
| 2 | Unggah halaman + menu | `app_versi.php`, `sidebar.php`, `api/app_versi.php`, folder `apk/` |
| 3 | (Pilihan) pasang kartu dashboard | `dashboard_updated.php` lalu ganti nama menjadi `dashboard.php` |
| 4 | Muat ulang dashboard | **Ctrl+F5** |
| 5 | Buka menu **Versi Aplikasi**, unggah APK terbaru | Halaman `app_versi.php` |
| 6 | Periksa hasil | `https://rts.benedic-s.com/api/app_versi.php` dan `https://rts.benedic-s.com/apk/app_versi.json` |

## BAGIAN 47 - TIGA PERBAIKAN: MENU VERSI APLIKASI, PESAN PEMBARUAN, KOTAK CUACA

Bagian ini menjawab tiga laporan Bapak pada 30 September 2026.

---

### A. MASALAH 1 - MENU "VERSI APLIKASI" MALAH KEMBALI KE DASHBOARD

**Gejala:** menu sudah tampak pada dashboard, tetapi ketika diklik halaman
hanya kembali ke `dashboard.php`.

**Sebabnya:** halaman `app_versi.php` memeriksa sesi login dengan satu kunci
saja, yaitu `$_SESSION['email']`. Pada akun Bapak, kunci itu tidak terisi
(misalnya kolom `email` pada tabel `sales_users` kosong untuk akun tersebut),
sehingga alurnya menjadi berputar:

```text
klik menu Versi Aplikasi
   -> app_versi.php melihat $_SESSION['email'] kosong
   -> dialihkan ke index.php (halaman login)
   -> index.php melihat sesi masih aktif
   -> dialihkan lagi ke dashboard.php   (inilah yang Bapak lihat)
```

**Perbaikan:** penjagaan sekarang berlapis, sama seperti halaman dashboard:

| Nomor | Pemeriksaan |
| --- | --- |
| 1 | Sudah login bila **salah satu** penanda ada: `is_logged_in`, `user_id`, `username`, `nama`, `email` |
| 2 | Peran dibaca dari session (`role` atau `user_role`) |
| 3 | Bila session tidak menyimpan peran, peran dibaca dari tabel `sales_users` memakai `username` |
| 4 | Ejaan diseragamkan; **SUPER ADMIN** diperlakukan sama dengan **ADMIN** |
| 5 | Koneksi database dicari dari beberapa nama variabel (`conn`, `mysqli`, `koneksi`, `db`, `link`) supaya tidak bergantung pada isi `config.php` |

Bila halaman tetap tidak dapat dibuka, tersedia halaman pemeriksa:

```text
https://rts.benedic-s.com/app_versi.php?diagnosa=1
```

Halaman itu menampilkan peran yang terbaca dan daftar nama kunci session yang
tersedia - cukup dikirimkan kepada saya apa adanya untuk ditindaklanjuti.

**Perbaikan yang sama juga dipasang pada `akun_pro.php`**, karena halaman itu
memakai penjagaan yang sama - supaya tidak terulang pada PUTARAN 4.

---

### B. MASALAH 2 - "TIDAK DAPAT MEMERIKSA PEMBARUAN" PADA APLIKASI

**Gejala:** pada menu Pengaturan, tombol **Periksa Pembaruan Sekarang** menjawab
"tidak dapat memeriksa pembaruan".

**Sebabnya:** aplikasi menafsirkan semua jawaban yang bukan berisi versi
sebagai kegagalan. Padahal jawaban "belum ada versi yang diumumkan" adalah
jawaban yang **sah** - artinya memang belum ada APK yang diunggah. Sebelum
APK pertama diunggah, keadaan itu memang wajar.

**Perbaikan pada aplikasi:**

| Nomor | Sebelum | Sesudah |
| --- | --- | --- |
| 1 | Belum ada versi = galat merah "Tidak dapat memeriksa pembaruan" | Belum ada versi = keterangan biasa "Belum ada versi aplikasi yang diumumkan di server." |
| 2 | Sebab kegagalan tidak jelas | Sebabnya disebut jelas, misalnya: "Halaman api/app_versi.php belum ada di server.", "Berkas keterangan versi belum ada di server (kode 404).", "Halaman API menjawab kode 500." |
| 3 | Jawaban server diabaikan | Pesan dari server (misalnya petunjuk menjalankan SQL tabel versi) ditampilkan apa adanya |

Jadi setelah perbaikan ini, tombol itu akan memberi tahu **persis** apa yang
kurang - apakah halaman API belum diunggah, tabelnya belum dibuat, atau memang
belum ada APK yang diumumkan.

---

### C. MASALAH 3 - KOTAK CUACA TIDAK TAMPAK PADA KARTU MERAH

**Gejala:** pada kartu merah "AKUN RTS PANEL" tidak ada kotak cuaca sama sekali.

**Sebabnya:** kotak cuaca hanya digambar bila datanya sudah ada. Selama izin
lokasi belum diberikan - dan pada HP Bapak build baru belum dipasang - kotak
itu tidak digambar, sehingga tidak ada tanda apa pun bahwa laporan cuaca
memang disediakan di situ.

**Perbaikan:** kotak cuaca **selalu tampil**:

| Keadaan | Tampilan kotak |
| --- | --- |
| Belum ada data | ikon cuaca + tulisan **Cuaca**, dan baris kecil **"Ketuk untuk memuat"** |
| Sedang memuat | lingkaran putar kecil + tulisan **"Memuat..."** |
| Data sudah ada | suhu (misalnya **31°C**), gambar cuaca, dan nama kota + keadaan |

Kotak itu juga **dapat diketuk**. Mengetuknya akan:

1. meminta izin lokasi bila belum pernah diberikan (pertanyaan izin muncul di
   layar HP), lalu
2. mengambil laporan cuaca, dan
3. bila gagal, menampilkan sebabnya pada layar bagian bawah.

Dengan begitu laporan cuaca dapat dihidupkan langsung dari beranda - tidak
harus lewat halaman Pengaturan.

**Yang tetap diperlukan:** build baru harus dipasang ke HP (PUTARAN 3), karena
izin lokasi ditambahkan pada saat build. Aplikasi yang sekarang terpasang di
HP masih build lama, sehingga kotak cuaca belum ada padanya.

---

### D. URUTAN PENGERJAAN SETELAH PERBAIKAN INI

| Nomor | Kegiatan | Berkas |
| --- | --- | --- |
| 1 | Unggah `app_versi.php` yang baru (timpa), lalu klik menu Versi Aplikasi | `RTS_PANEL_VERSI_APK.zip` |
| 2 | Bila masih kembali ke dashboard, buka `app_versi.php?diagnosa=1` dan kirimkan tulisannya | - |
| 3 | Pasang aplikasi baru (izin lokasi + kotak cuaca) | `RTS_PANEL_FITUR_BARU.zip` |
| 4 | Buka aplikasi, ketuk kotak "Cuaca" pada kartu merah, izinkan lokasi | - |
| 5 | Uji tombol Periksa Pembaruan Sekarang - pesannya sudah jelas | - |

### E. BILA MASIH ADA KENDALA

| Kejadian | Sebab dan penanganan |
| --- | --- |
| Menu Versi Aplikasi tetap kembali ke dashboard | Buka `app_versi.php?diagnosa=1`, kirimkan tulisannya; periksa bahwa akun berperan ADMIN pada tabel `sales_users` |
| Halaman `?diagnosa=1` berbunyi "Peran terbaca : (kosong)" | Kolom `role` akun itu kosong pada tabel `sales_users` - isi dengan `ADMIN` lewat phpMyAdmin |
| Pesan "Halaman api/app_versi.php belum ada di server." | Berkas API belum diunggah - lihat PUTARAN 2 |
| Pesan "Belum ada versi aplikasi yang diumumkan di server." | Wajar bila APK belum pernah diunggah - unggah APK pertama pada halaman Versi Aplikasi |
| Kotak "Cuaca" tampil, tetapi tetap bertulisan "Ketuk untuk memuat" | Ketuk kotak itu dan kirimkan tulisan sebab yang muncul pada layar |

## BAGIAN 48 - MENU VERSI APLIKASI MASIH KEMBALI KE DASHBOARD (SEBAB SEBENARNYA)

### A. GEJALA

| Nomor | Yang Bapak lihat |
| --- | --- |
| 1 | Menu **Versi Aplikasi** diklik, halaman kembali ke `dashboard.php` |
| 2 | Alamat pemeriksa `app_versi.php?diagnosa=1` **juga** kembali ke dashboard |

Gejala nomor 2 itulah petunjuk utamanya: halaman pemeriksa pun teralihkan,
padahal halaman itu seharusnya menampilkan keterangan.

### B. SEBAB SEBENARNYA

Ada **dua** kesalahan yang bertumpuk, keduanya sudah diperbaiki.

| Nomor | Kesalahan | Akibat |
| --- | --- | --- |
| 1 | `app_versi.php` **tidak memanggil `session_start()` sendiri** - hanya menunggu `config.php` | Bila `config.php` tidak memulai session, isi `$_SESSION` kosong. Halaman mengira pengunjung belum login, lalu mengalihkan ke `index.php`; halaman login itu melihat sesinya masih aktif, lalu mengalihkannya lagi ke `dashboard.php`. Dari sisi pemakai: terasa seperti "tidak terjadi apa-apa" |
| 2 | Blok pemeriksa `?diagnosa=1` saya letakkan **setelah** pemeriksaan login | Karena pemeriksaan login gagal, blok pemeriksa tidak pernah dijalankan - alamat itu pun ikut teralihkan, sehingga tidak ada keterangan yang bisa dilihat |

Urutan yang lama (salah):

```text
buka app_versi.php?diagnosa=1
   -> session kosong (session belum dimulai di berkas ini)
   -> dianggap belum login
   -> dialihkan ke index.php   (blok diagnosa TIDAK pernah sampai dijalankan)
   -> index.php melihat sesi aktif -> dialihkan ke dashboard.php
```

### C. PERBAIKAN

| Nomor | Perbaikan | Berkas |
| --- | --- | --- |
| 1 | Berkas memulai session sendiri bila belum aktif (`session_status()` lalu `session_start()`) | `app_versi.php`, `akun_pro.php` |
| 2 | Blok pemeriksa `?diagnosa=1` **dipindahkan ke paling atas**, sebelum semua pengalihan - jadi hasilnya selalu dapat dilihat | `app_versi.php`, `akun_pro.php` |
| 3 | Isi pemeriksa ditambah: status session, daftar kunci session, nilai penting (ditampilkan sebagian), koneksi database, peran dari database, dan daftar berkas pendukung | `app_versi.php` |
| 4 | Penanda **VERSI BERKAS** dipasang pada berkas, supaya dapat dipastikan berkas yang diunggah benar-benar yang baru (harus tertulis **VERSI BERKAS : 3**) | `app_versi.php`, `akun_pro.php` |
| 5 | `require_once` memakai `__DIR__` supaya berkas pendukung selalu diambil dari folder yang sama | `app_versi.php`, `akun_pro.php` |
| 6 | Berkas pemeriksa mandiri **`cek_session.php`** dibuat - tanpa penjagaan login sama sekali, sehingga selalu dapat dibuka | `cek_session.php` (baru) |

Perbaikan yang sama dipasang pada `akun_pro.php` supaya PUTARAN 4 tidak
mengalami kendala serupa.

### D. CARA MEMAKAI PEMERIKSA

**Langkah 1 - unggah dua berkas** ke dalam `public_html`:

```text
app_versi.php     (versi 3)
cek_session.php   (baru)
```

**Langkah 2 - buka halaman pemeriksa mandiri:**

```text
https://rts.benedic-s.com/cek_session.php
```

Halaman itu **tidak mungkin teralihkan**, karena tidak ada pemeriksaan login
di dalamnya. Isi yang ditampilkan:

| Bagian | Gunanya |
| --- | --- |
| SESSION | status, nama, dan jumlah kunci session |
| DAFTAR KUNCI SESSION | nama kunci yang benar-benar ada pada sesi Bapak |
| NILAI PENTING | dipakai untuk memastikan kunci mana yang terisi (ditampilkan sebagian) |
| COOKIE YANG DITERIMA | memastikan cookie session benar-benar terkirim |
| PENGATURAN SESSION | `save_path`, `cookie_path`, nama session |
| BERKAS DI FOLDER INI | memastikan `config.php`, `api/app_versi.php`, dan lainnya memang ada |
| app_versi.php | **versi berkas** yang sedang terpasang di server |

Nilai session hanya ditampilkan sebagian (tiga huruf pertama), jadi **aman**
dikirimkan lewat pesan. Berkas ini tidak mengubah data apa pun.

**Langkah 3 - buka halaman pemeriksa halaman versi:**

```text
https://rts.benedic-s.com/app_versi.php?diagnosa=1
```

Tulisan pertamanya harus:

```text
VERSI BERKAS  : 3
```

Bila yang muncul **versi berkas 1**, berarti berkas `app_versi.php` di server
belum tertimpa - unggah ulang, lalu muat ulang dengan **Ctrl+F5**.

### E. CARA MEMBACA HASIL PEMERIKSAAN

| Yang terlihat pada `cek_session.php` | Artinya | Tindakan |
| --- | --- | --- |
| `kunci tersimpan: 0` padahal dashboard dapat dibuka | Cookie session tidak terkirim ke berkas ini | Kirimkan seluruh isi halaman kepada saya |
| `kunci tersimpan: 4` atau lebih, ada `role` dan `username` | Session sehat | Halaman `app_versi.php` seharusnya sudah terbuka setelah berkas versi 3 diunggah |
| `role` tertulis `(kosong)` pada NILAI PENTING | Kolom `role` akun itu kosong pada tabel `sales_users` | Isi kolom `role` dengan `ADMIN` lewat phpMyAdmin |
| `config.php: TIDAK ADA` | Berkas config tidak ada pada folder itu | Berkas website berada di folder yang berbeda - kirimkan keterangan folder yang tertulis |
| `app_versi.php : versi berkas 1` | Berkas baru belum tertimpa | Unggah ulang `app_versi.php` dari paket versi 3 |

### F. SETELAH MASALAHNYA SELESAI

Berkas `cek_session.php` **sebaiknya dihapus** dari `public_html` (cPanel -
File Manager - pilih berkas - Delete), karena berkas itu tidak diperlukan lagi
sehari-hari.

### G. RINGKASAN PERUBAHAN BERKAS

| Berkas | Keadaan |
| --- | --- |
| `app_versi.php` | 960 baris - versi berkas 3 (session + pemeriksa di atas + riwayat versi) |
| `akun_pro.php` | 450 baris - versi berkas 3 (session + pemeriksa di atas) |
| `cek_session.php` | 144 baris - berkas pemeriksa baru |
| `RTS_PANEL_PERIKSA_SESSION.zip` | paket kecil: `cek_session.php` + `app_versi.php` saja |
| `RTS_PANEL_VERSI_APK.zip` | paket lengkap 9 berkas |

## BAGIAN 49 - HASIL PEMERIKSAAN SERVER: SEMUA SEHAT + ALAT PEMERIKSA DIPERBAIKI (VERSI 4)

### A. HASIL PEMERIKSAAN BAPAK (30 September 2026, 05:54)

Kedua laporan Bapak menunjukkan keadaan server yang **sehat**. Ringkasannya:

| Nomor | Yang diperiksa | Hasil | Arti |
| --- | --- | --- | --- |
| 1 | Session | 8 kunci tersimpan: `user_id`, `username`, `nama`, `email`, `role`, `salesman`, `sales_district`, `is_logged_in` | Sesi login **lengkap** |
| 2 | Peran | `ADM***N (5 huruf)` = **ADMIN** | Peran **benar** - memang Admin |
| 3 | Cookie | `PHPSESSID` diterima server | Cookie session **terkirim** dengan benar |
| 4 | Berkas | `config.php`, `auth.php`, `header.php`, `footer.php`, `sidebar.php`, `dashboard.php`, `index.php`, `app_versi.php`, `api/app_versi.php`, `apk/`, `apk/app_versi.json` | **Semua ADA** |
| 5 | Versi berkas | `app_versi.php` = **versi berkas 3**, diubah 30-09-2026 05:53:15 | Berkas baru **sudah terunggah** |

**Kesimpulan:** seluruh syarat agar halaman Versi Aplikasi terbuka sudah terpenuhi.
Penjaga halaman sekarang **lolos**: sesi lengkap, perannya ADMIN. Jadi halaman itu
harusnya sudah dapat dibuka. Silakan dicoba kembali - bila masih kembali ke
dashboard, lanjutkan ke bagian C di bawah.

### B. SATU KEKELIRUAN PADA ALAT PEMERIKSA - SUDAH DIPERBAIKI

Pada laporan Bapak, bagian DATABASE berbunyi:

```text
DATABASE
  koneksi      : conn
  status       : tidak ada koneksi database di halaman ini
```

Kalimat itu **keliru menilai** (bukan tanda server bermasalah). Sebabnya: blok
pemeriksa dijalankan **sebelum** bagian pencarian koneksi database, sehingga
laporan membaca variabel yang belum diisi. Pada berkas **versi 4**:

| Nomor | Perbaikan |
| --- | --- |
| 1 | Pencarian koneksi database **dipindah ke atas**, sebelum blok pemeriksa dan penjaga halaman |
| 2 | Laporan DATABASE kini membaca koneksi yang benar-benar ditemukan (pada server Bapak: variabel **`conn`**), dan menampilkan peran akun dari database |
| 3 | Bagian **KESIMPULAN** diganti menjadi **SIMULASI PENJAGA HALAMAN** - menjawab langsung apakah halaman akan mengalihkan pengunjung atau tidak |

Contoh isi bagian baru itu:

```text
SIMULASI PENJAGA HALAMAN
  (menjawab langsung: apakah halaman ini akan mengalihkan pengunjung)

  penanda login dipakai : is_logged_in
  peran dari session    : ADMIN
  peran setelah disamakan: ADMIN

  HASIL: penjaga LOLOS - halaman tidak mengalihkan pengunjung.
  Halaman ini akan menampilkan formulir unggah APK seperti biasa.
```

Bila yang muncul adalah `HASIL: pengunjung akan dialihkan ...`, sebabnya akan
disebutkan langsung beserta tindakannya.

### C. LANGKAH YANG DISARANKAN

| Nomor | Kegiatan |
| --- | --- |
| 1 | Klik menu **Versi Aplikasi** pada dashboard. Karena sesi lengkap dan peran ADMIN, halaman harus terbuka |
| 2 | Bila sudah terbuka, selesai - lanjutkan PUTARAN 2 (unggah APK nanti setelah aplikasi dibangun) |
| 3 | Bila masih kembali ke dashboard: unggah `app_versi.php` **versi 4**, lalu buka `app_versi.php?diagnosa=1` dan kirimkan bagian **SIMULASI PENJAGA HALAMAN** |
| 4 | Setelah semuanya lancar, hapus `cek_session.php` dari `public_html` |

### D. BILA PENJAGA SUDAH LOLOS TETAPI MENU MASIH KEMBALI KE DASHBOARD

Bila laporan berbunyi "penjaga LOLOS" namun menu tetap kembali ke dashboard,
berarti pengalihannya berasal dari **halaman lain**, bukan dari `app_versi.php`.
Kemungkinan yang perlu diperiksa:

| Nomor | Kemungkinan | Cara memeriksa |
| --- | --- | --- |
| 1 | Aturan pengalihan pada `.htaccess` | Buka cPanel - File Manager - tampilkan berkas tersembunyi - periksa `.htaccess` di dalam `rts.benedic-s.com` |
| 2 | `config.php` memuat penjaga tambahan | Kirimkan cuplikan bagian atas `config.php` (jangan kirimkan bagian password - hapus dulu) |
| 3 | `header.php` memuat penjaga tambahan | Sama seperti nomor 2 |
| 4 | Tampilan lama masih tersimpan di browser | Tekan **Ctrl+F5**, atau coba pada mode penyamaran (Ctrl+Shift+N) |

Cara tercepat memastikan: setelah menekan menu, perhatikan **alamat pada bar**
browser. Bila alamat berakhir `app_versi.php` tetapi isinya dashboard, berarti
memang ada pengalihan dari dalam halaman. Bila alamatnya berubah menjadi
`dashboard.php`, sebabnya ada pada berkas yang dijalankan lebih dahulu
(`config.php` atau `header.php`).

## BAGIAN 50 - CUACA TETAP TIDAK TAMPIL: BUILD DI HP MASIH LAMA + ALAT DIAGNOSA BARU

### A. BUKTI DARI TANGKAPAN LAYAR (30 September 2026, 13.22)

| Nomor | Yang terlihat | Artinya |
| --- | --- | --- |
| 1 | Beranda normal: kartu merah, iklan, 6 menu | Aplikasi berjalan baik |
| 2 | Kartu merah **tidak memuat kotak cuaca** | Aplikasi memakai build lama |
| 3 | Pengaturan HP - Aplikasi - Izin: **Lokasi "Diizinkan"** | Izin lokasi sudah diberikan - jadi kode permintaan izin sudah bekerja |

Kesimpulan: seluruh perbaikan sisi server dan perizinan sudah bekerja. Yang
tinggal adalah **build baru harus dipasang ke HP**, karena build yang terpasang
masih versi yang kotak cuacanya hanya tampil BILA laporan berhasil. Selama
laporan belum berhasil, kotak itu tidak digambar sama sekali - sehingga tidak
ada tanda apa pun dan sebabnya tidak dapat dibaca dari HP.

### B. PERBAIKAN YANG DIPASANG PADA PAKET INI (VERSI 5)

| Nomor | Perbaikan | Kegunaan |
| --- | --- | --- |
| 1 | **Penanda kode aplikasi** `rtsKodeAplikasi = 'RTS-2026-09-30-5'` | Dapat dibandingkan antara nilai pada main.dart dan nilai pada HP - langsung ketahuan kalau build lama |
| 2 | Kartu **Cuaca Beranda** kini menampilkan seluruh keterangan: kode aplikasi, versi terpasang, keadaan, izin lokasi, GPS aktif, titik lokasi, cuaca terbaca, dan keterangan teknis | Sebab kegagalan terbaca langsung di HP |
| 3 | Tombol **SALIN KETERANGAN (KIRIM KE PENGEMBANG)** | Seluruh keterangan disalin ke papan klip sekali tekan, lalu cukup ditempelkan pada pesan - tidak perlu difoto atau diketik |
| 4 | `RtsCuaca` kini mencatat: `izinLokasi`, `gpsAktif`, `titikTerakhir`, `pesanTeknis`, `dicobaPada`, `jumlahBerhasil` | Bahan keterangan pada kartu Pengaturan |
| 5 | `PASANG_FITUR_BARU.ps1` memeriksa **penanda kode aplikasi** pada main.dart dan **mencetak nilainya** | Sebelum build dimulai, sudah diketahui apakah folder proyek berisi kode baru atau lama |
| 6 | Pemeriksa skrip juga menampilkan baris izin lokasi pada AndroidManifest | Memastikan `ACCESS_FINE_LOCATION` dan `ACCESS_COARSE_LOCATION` benar-benar ada |

Contoh tulisan yang dikeluarkan skrip pemasang:

```text
   [ADA] main.dart memuat penanda kode aplikasi
   [ADA] kotak cuaca versi baru (selalu tampil, dapat diketuk)
   [ADA] kartu pemeriksa Cuaca Beranda pada Pengaturan
   [ADA] tombol SALIN KETERANGAN cuaca

   KODE APLIKASI pada main.dart : RTS-2026-09-30-5
   Sesudah aplikasi dipasang ke HP, buka Pengaturan - bagian
   'Cuaca Beranda'. Nilai pada kotak merah muda HARUS SAMA dengan nilai di atas.
```

### C. LANGKAH YANG DISARANKAN

| Nomor | Kegiatan | Berkas |
| --- | --- | --- |
| 1 | Unduh **ulang** `RTS_PANEL_FITUR_BARU.zip` (yang baru, memuat 6 berkas) | tautan pada pesan |
| 2 | Hapus folder `D:\Project\rts_panel_app`, lalu ekstrak ulang dari nol | - |
| 3 | Jalankan `PERBAIKI_PUBSPEC.ps1`, lalu `PASANG_FITUR_BARU.ps1` | - |
| 4 | Perhatikan **KODE APLIKASI** yang dicetak skrip (harus `RTS-2026-09-30-5`) | - |
| 5 | Buka aplikasi - kartu merah kini memuat kotak **Cuaca** | - |
| 6 | Bila masih gagal: Pengaturan - Cuaca Beranda - tekan **SALIN KETERANGAN**, lalu tempelkan pada pesan | `CUACA_BELUM_TAMPIL.txt` |

### D. CARA MEMBACA KETERANGAN YANG DISALIN

| Baris | Arti dan tindakan |
| --- | --- |
| `GPS aktif : TIDAK` | Layanan Lokasi HP mati - hidupkan pada Pengaturan HP - Lokasi |
| `Izin lokasi : Belum diizinkan` | Ketuk kotak Cuaca pada beranda, lalu pilih "Saat aplikasi digunakan" |
| `Izin lokasi : Ditolak permanen` | Pengaturan HP - Aplikasi - RTS Panel - Izin - Lokasi - Izinkan |
| `Titik lokasi : (belum ada)` + keadaan "Membaca titik GPS" | Pindah ke tempat terbuka; di dalam gedung GPS sering tidak mendapat titik |
| `Keterangan teknis: TimeoutException` | Jaringan HP lambat - coba lagi, periksa paket data |
| `Keadaan : Gagal menghubungi layanan cuaca` | Layanan Open-Meteo tidak terjangkau - periksa kuota data |
| `Keadaan : Laporan cuaca siap` | Berhasil - suhu sudah tampil pada kartu merah |

### E. CATATAN PENTING

**Izin lokasi saja tidak cukup - GPS (Layanan Lokasi) pada HP juga harus
aktif.** Bila GPS mati, aplikasi akan mencoba memakai titik lokasi terakhir
yang pernah tercatat; bila belum pernah ada, laporan tidak dapat diambil.

Laporan cuaca memakai layanan gratis **Open-Meteo** yang tidak memerlukan
kunci API, sehingga tidak ada yang perlu diatur pada website.

## BAGIAN 51 - KOREKSI PENTING: JANGAN MENGHAPUS FOLDER PROYEK

### A. KOREKSI ATAS SARAN SEBELUMNYA

Pada BAGIAN 50 saya menyarankan menghapus folder `D:\Project\rts_panel_app`
lalu mengekstrak ulang dari nol. **Saran itu keliru dan sudah dibatalkan.**
Bapak benar untuk bertanya lebih dahulu.

**Sebabnya:** paket `RTS_PANEL_FITUR_BARU.zip` hanya memuat **6 berkas**:

```text
main.dart                      (kode aplikasi)
pubspec.yaml                   (daftar paket + nomor versi)
PASANG_FITUR_BARU.ps1          (skrip pemasang)
PERBAIKI_PUBSPEC.ps1           (skrip pubspec)
android_manifest_tambahan.xml  (catatan izin)
CUACA_BELUM_TAMPIL.txt         (panduan cuaca)
```

Folder `android`, `assets`, dan `lib` **TIDAK ADA** di dalam paket. Jadi bila
folder proyek dihapus, yang hilang adalah:

| Nomor | Berkas yang hilang | Akibatnya |
| --- | --- | --- |
| 1 | `android\app\google-services.json` | Aplikasi tidak dapat memakai Firebase (pemberitahuan HP) |
| 2 | `assets\images\...` | Gambar latar login dan beranda hilang |
| 3 | `android\` (susunan Gradle yang sudah benar) | Build gagal - harus menyusun Gradle dari awal |
| 4 | `lib\` | Susunan program hilang |

**Cara yang benar: TIMPA berkas dari paket, lalu jalankan `flutter clean`.**

Perintah `flutter clean` menghapus **hasil build lama** (`build/` dan
`.dart_tool/`) tanpa menyentuh berkas penting - jadi hasilnya sama bersihnya
dengan "ekstrak dari nol", tetapi tanpa kehilangan apa pun.

### B. SKRIP PEMERIKSA BARU: `PERIKSA_KODE_APLIKASI.ps1`

Skrip ini menjawab pertanyaan "apakah folder proyek saya sudah berisi kode
terbaru?" **tanpa mengubah apa pun** - tidak menghapus, tidak memindahkan.

| Nomor | Yang diperiksa | Kegunaan |
| --- | --- | --- |
| 0 | Letak folder: `pubspec.yaml`, `main.dart`, folder `android` | Memastikan dijalankan pada folder yang benar |
| 1 | **Kode aplikasi** pada `main.dart` | Harus `RTS-2026-09-30-5`; bila beda, berkas baru belum ditimpa |
| 2 | 10 bagian penting di dalam `main.dart` | Cuaca, kotak cuaca baru, kartu pemeriksa, tombol salin, permintaan izin, pesan pembaruan, iklan, dan lain-lain |
| 3 | 9 paket pada `pubspec.yaml` | geolocator, geocoding, iklan, Firebase, dan lain-lain |
| 4 | 6 izin pada `AndroidManifest.xml` | Termasuk lokasi, pemberitahuan, dan kode AdMob |
| 5 | `google-services.json`, `assets`, `lib` | Berkas yang TIDAK ada di dalam paket zip |

Contoh hasil bila semuanya benar:

```text
   [ADA]   main.dart
   [ADA]   folder android (WAJIB - tidak ada di dalam paket zip)

   KODE APLIKASI : RTS-2026-09-30-5
   DIHARAPKAN    : RTS-2026-09-30-5

   [BENAR] main.dart sudah versi terbaru.

   SEMUA BENAR. Folder proyek sudah memuat kode terbaru.

   Langkah berikutnya:
     1. flutter clean
     2. .\PERBAIKI_PUBSPEC.ps1
     3. .\PASANG_FITUR_BARU.ps1
```

Bila ada yang kurang, skrip menyebutkan langkah perbaikannya sekaligus
peringatan agar **tidak menghapus folder proyek**.

### C. URUTAN YANG BENAR (PENGGANTI LANGKAH LAMA)

| Nomor | Perintah | Kegunaan |
| --- | --- | --- |
| 1 | Ekstrak `RTS_PANEL_FITUR_BARU.zip` ke `D:\Project\rts_panel_app`, pilih **TIMPA / Replace** | Memperbarui 6 berkas - berkas lain tidak disentuh |
| 2 | `\.PERIKSA_KODE_APLIKASI.ps1` | Memastikan semua sudah benar sebelum membangun |
| 3 | `flutter clean` | Membersihkan hasil build lama |
| 4 | `.\PERBAIKI_PUBSPEC.ps1` | Mendaftarkan paket |
| 5 | `.\PASANG_FITUR_BARU.ps1` | Membangun dan memasang ke HP |

Bila ingin cadangan tambahan tanpa risiko: **ubah nama** foldernya terlebih
dahulu (misalnya menjadi `rts_panel_app_lama`), lalu ekstrak paket ke folder
baru `rts_panel_app`. Dengan begitu folder lama tetap utuh sebagai cadangan -
tetapi cara ini memerlukan penyalinan `android\`, `assets\`, dan `lib\` dari
folder lama, sehingga **cara menimpa (nomor 1) tetap yang paling mudah**.

## BAGIAN 52 - "adb : The term 'adb' is not recognized" (BUILD SUDAH BERHASIL)

### A. APA YANG TERJADI

Dari tangkapan layar Bapak (30 September 2026, sore):

```text
Running Gradle task 'assembleDebug'...        196,7s
√ Built build\app\outputs\flutter-apk\app-debug.apk

PS D:\Project\rts_panel_app> adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb : The term 'adb' is not recognized as the name of a cmdlet, function,
script file, or operable program. ...
```

| Nomor | Yang terlihat | Artinya |
| --- | --- | --- |
| 1 | `√ Built ... app-debug.apk (196,7s)` | **BUILD BERHASIL** - berkas APK sudah jadi |
| 2 | Kanan bawah VS Code: `CPH1937 (wireless) (android-arm64)` | HP Bapak **tersambung nirkabel** dan dikenali Flutter |
| 3 | `adb : The term 'adb' is not recognized` | Perintah `adb` belum dikenal Windows |

Jadi yang gagal **bukan build dan bukan sambungan HP** - hanya satu perintah
yang belum dikenal. Sebabnya: `adb.exe` berada di dalam folder Android SDK
(`platform-tools`) dan folder itu belum terdaftar pada PATH Windows. Flutter
menemukannya sendiri, tetapi PowerShell tidak.

Peringatan **Kotlin Gradle Plugin (KGP)** yang muncul di atasnya hanyalah
peringatan biasa dari paket `firebase_core` - build tetap berhasil, jadi sekarang
belum perlu diurus.

### B. TIGA JALAN KELUAR

| Nomor | Cara | Perintah | Kelebihan |
| --- | --- | --- | --- |
| A | Langsung lewat Flutter (tanpa adb) | `flutter run -d CPH1937` | Paling mudah - Flutter mencari adb sendiri |
| B | Pemanggil adb (`ADB.ps1`) | `.\ADB.ps1 pasang` | Membantu mencari adb.exe otomatis |
| C | Perbaiki permanen (`TAMBAH_ADB_KE_PATH.ps1`) | `.\TAMBAH_ADB_KE_PATH.ps1` | Sekali jalan, seterusnya `adb` dapat langsung diketik |

Cara A adalah yang paling cepat sekarang, karena APK-nya sudah jadi:

```text
flutter devices                     (melihat nama HP, contoh CPH1937)
flutter run -d CPH1937              (bangun + pasang + jalankan)
flutter install --debug -d CPH1937  (pasang saja, bila tidak ingin dijalankan)
```

### C. BERKAS BARU PADA PAKET INI

| Berkas | Kegunaan |
| --- | --- |
| `ADB.ps1` | Pemanggil adb: mencari `adb.exe` sendiri, lalu menjalankan perintah - `daftar`, `alamat`, `pasang`, `pasang-release`, `buka`, `catatan`, `bersih` |
| `TAMBAH_ADB_KE_PATH.ps1` | Mendaftarkan folder `platform-tools` ke PATH pengguna Windows, dengan cadangan PATH lama |
| `PASANG_CEPAT.ps1` (diperbarui) | Kini memakai HP yang **sudah tersambung** tanpa menanyakan IP:PORT lagi |
| `RTS_PANEL_PERINTAH_HP.zip` | Paket kecil: keempat berkas di atas saja |

Contoh pemakaian `ADB.ps1`:

```text
.\ADB.ps1                 bantuan + daftar HP
.\ADB.ps1 daftar          melihat HP yang tersambung
.\ADB.ps1 alamat          letak adb.exe (untuk disalin)
.\ADB.ps1 pasang          memasang APK debug terbaru
.\ADB.ps1 pasang-release  memasang APK release terbaru
.\ADB.ps1 buka            membuka aplikasi di HP
.\ADB.ps1 catatan         melihat catatan aplikasi
.\ADB.ps1 bersih          menyambung ulang adb
```

### D. CATATAN PENTING TENTANG `TAMBAH_ADB_KE_PATH.ps1`

| Nomor | Hal |
| --- | --- |
| 1 | Yang diubah hanya **PATH pengguna** (User PATH), bukan PATH sistem |
| 2 | PATH lama **dicadangkan** ke `%USERPROFILE%\path_pengguna_cadangan.txt` sebelum diubah |
| 3 | Bila folder `platform-tools` sudah ada pada PATH, skrip tidak mengubah apa pun |
| 4 | Setelah dijalankan, **tutup jendela PowerShell lalu buka yang baru** - Windows membaca PATH hanya saat jendela dibuka |
| 5 | Cara membatalkan tertulis di bagian bawah berkas cadangan itu |

### E. BILA INGIN MENCOBA PERINTAH adb TANPA MENGUBAH APAPUN

Satu baris berikut langsung memakai adb dari letaknya:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices
```

Bila letak SDK berbeda, jalankan `.\ADB.ps1 alamat` untuk melihat letak
sebenarnya, lalu ganti bagian dalam tanda kutip di atas.

## BAGIAN 53 - TAMPILAN TIDAK BERUBAH WALAU BUILD BERHASIL (DUA BERKAS main.dart)

### A. SEBABNYA - DITEMUKAN DARI TANGKAPAN LAYAR

Pada daftar berkas VS Code Bapak terlihat **dua** berkas `main.dart`:

```text
D:\Project\rts_panel_app\
    main.dart          <- berkas dari paket (sudah versi terbaru)
    lib\
        main.dart      <- BERKAS YANG DIBANGUN FLUTTER (masih versi lama)
```

**Flutter membangun aplikasi dari `lib\main.dart`**, bukan dari `main.dart`
yang ada di akar folder proyek. Karena kode baru selama ini hanya masuk ke
`main.dart` (akar), maka:

| Yang terjadi | Sebab |
| --- | --- |
| `flutter build apk` berhasil | Perintah build hanya memeriksa sintaks dan paket - tidak tahu isi berkas mana yang seharusnya dipakai |
| Aplikasi terpasang dan terbuka normal | Sama seperti sebelumnya - yang dibangun tetap `lib\main.dart` versi lama |
| Tampilan tidak berubah (kotak cuaca tetap tidak ada) | Kode kotak cuaca ada pada `main.dart` (akar), yang tidak pernah ikut dibangun |

Inilah sebabnya seluruh perbaikan cuaca (BAGIAN 45 sampai 50) tidak pernah
terlihat di HP, walaupun build selalu berhasil.

### B. PERBAIKAN CEPAT (PILIH SALAH SATU)

**Cara 1 - satu baris perintah (paling ringkas):**

```text
copy main.dart lib\main.dart
flutter clean
flutter run -d CPH1937
```

**Cara 2 - memakai skrip dengan cadangan otomatis (disarankan):**

```text
.\PASANG_MAIN_DART.ps1
flutter clean
flutter run -d CPH1937
```

Skrip itu:

| Nomor | Kegiatan |
| --- | --- |
| 1 | Membaca penanda kode pada `main.dart` dan `lib\main.dart` |
| 2 | Memilih berkas yang paling baru |
| 3 | Mencadangkan `lib\main.dart` lama ke `lib\main.dart.lama_thnnn-bb-tt_jjmmss` |
| 4 | Menyalin berkas baru ke `lib\main.dart` |
| 5 | Memeriksa hasilnya dan menunjukkan langkah berikutnya |

**Cara 3 - cukup ekstrak paket yang baru:**
Paket `RTS_PANEL_FITUR_BARU.zip` sejak sekarang memuat **dua** berkas sekaligus
(`lib/main.dart` dan `main.dart`), sehingga mengekstrak paket ke folder proyek
langsung memperbarui berkas yang benar.

### C. CARA MEMASTIKAN SUDAH BENAR

| Nomor | Kegiatan | Yang diharapkan |
| --- | --- | --- |
| 1 | Jalankan `.\PERIKSA_KODE_APLIKASI.ps1` | Baris `Kode pada lib\main.dart` menampilkan `RTS-2026-09-30-5` |
| 2 | `flutter clean` lalu `flutter run -d CPH1937` | Aplikasi terpasang ulang |
| 3 | Di HP: menu **Pengaturan** bagian **CUACA BERANDA** | Pada kotak merah muda tertulis `Kode aplikasi terpasang: RTS-2026-09-30-5` |
| 4 | Beranda, kartu merah, di samping nama Admin | Muncul kotak **Cuaca** (ikon awan + tulisan "Cuaca" + "Ketuk untuk memuat") |

Bila pada nomor 3 kode aplikasi **belum sama**, berarti aplikasi di HP belum
tergantikan - jalankan `.\PASANG_CEPAT.ps1` atau `flutter run` sekali lagi.

### D. PERUBAHAN PADA SKRIP (PAKET INI)

| Berkas | Perubahan |
| --- | --- |
| `PASANG_MAIN_DART.ps1` | **Baru** - memindahkan `main.dart` ke `lib\main.dart` dengan cadangan otomatis |
| `PERIKSA_KODE_APLIKASI.ps1` | Kini memeriksa `lib\main.dart` (berkas yang dibangun) dan membandingkannya dengan `main.dart` akar, serta menyarankan `PASANG_MAIN_DART.ps1` bila berlainan |
| `PASANG_FITUR_BARU.ps1` | Ditambah langkah **1b**: menyamakan `lib\main.dart` dengan `main.dart` secara otomatis (dengan cadangan) sebelum build |
| `RTS_PANEL_FITUR_BARU.zip` | Kini memuat `lib/main.dart` **dan** `main.dart` sekaligus (13 entri) |
| `RTS_PANEL_PERINTAH_HP.zip` | Kini 5 berkas (ditambah `PASANG_MAIN_DART.ps1`) |

### E. CATATAN UNTUK PENGEMBANG

Sebaiknya `main.dart` hanya disimpan pada satu tempat saja, yaitu
`lib\main.dart`, agar tidak ada lagi kemungkinan berkas tertukar. Paket tetap
memuat salinan di akar folder karena skrip pemeriksa membandingkan keduanya -
bila berbeda, skrip akan memberitahu.

## BAGIAN 54 - PEMBERITAHUAN OTOMATIS KE LAYAR HP (TIGA PERMINTAAN BAPAK)

Tiga pertanyaan Bapak pada 30 September 2026:

1. Apakah pembaruan aplikasi dapat memunculkan pemberitahuan di layar HP
   walaupun aplikasi tidak dibuka?
2. Apakah seluruh aktivitas Admin - misalnya data Customer diperbarui - juga
   memunculkan pemberitahuan otomatis walaupun aplikasi tidak dibuka?
3. Mohon dibuat: bila HP masih memakai aplikasi lama, muncul pemberitahuan
   terus-menerus dengan tombol UPDATE.

**Jawabannya: ketiganya BISA**, dan sudah dikerjakan pada paket ini.

---

### A. CARA KERJANYA

Pemberitahuan ini memakai **Firebase Cloud Messaging (FCM)** - layanan
pemberitahuan resmi Google yang sudah disiapkan sejak awal. Pemberitahuan
jenis ini muncul di layar HP **walaupun aplikasi sedang ditutup**, sama seperti
pemberitahuan WhatsApp.

```text
   Server (rts.benedic-s.com)                    HP petugas
   --------------------------                    ----------
   Admin unggah APK baru
        |
        v
   app_versi.php  ---> api/notif_otomatis.php
                             |
                             +--> catat ke tabel notifications
                             |    (menu Pemberitahuan di aplikasi)
                             |
                             +--> api/fcm_kirim.php  ---> Firebase
                                                              |
                                                              v
                                                    LAYAR HP menyala:
                                                    "Versi Baru RTS Panel"
                                                    [ UPDATE ]
```

---

### B. PERUBAHAN PADA KODE

#### B1. Sisi server

| Berkas | Keadaan | Isi perubahan |
| --- | --- | --- |
| `api/notif_otomatis.php` | **BARU** | Satu pintu pemberitahuan: mencatat ke tabel `notifications` **dan** mengirim ke layar HP. Berisi `rts_notif_semua()`, `rts_notif_kirim()`, `rts_notif_versi_baru()`, `rts_notif_aktivitas()`, `rts_notif_daftar_penerima()`, `rts_notif_catat()` |
| `api/fcm_kirim.php` | diperbarui | Ditambah `rts_push_kirim_semua()` - mengirim ke **seluruh** HP sekaligus. Pemeriksaan tabel tidak lagi memakai `information_schema` (menghindari kesalahan #1044) |
| `app_versi.php` | diperbarui | Setelah unggahan APK berhasil, **otomatis** mengirim pemberitahuan versi baru ke seluruh HP, dan menyebutkan jumlah HP yang berhasil dikirimi |
| `upload_customer.php` | diperbarui | Setelah unggahan data customer berhasil, seluruh petugas (kecuali Admin yang melakukan) menerima pemberitahuan "Data Customer Diperbarui" |
| `pengajuan_toko.php` | (sudah ada) | Pengajuan baru dari website sudah memberi tahu ADMIN dan ASS |

Semua bagian ini **aman gagal**: bila Firebase belum disiapkan atau tabelnya
belum ada, halaman tetap bekerja seperti biasa - hanya pemberitahuannya yang
belum terkirim.

#### B2. Sisi aplikasi

| Nomor | Perubahan |
| --- | --- |
| 1 | Pemberitahuan dapat memuat **tombol**. Pada pemberitahuan pembaruan, tombolnya bertuliskan **UPDATE** |
| 2 | Kelas baru **`RtsPengingatPembaruan`**: menampilkan pengingat pembaruan dan **mengulanginya setiap jam** sampai aplikasi benar-benar diperbarui |
| 3 | Pengingat berhenti **sendiri** setelah versi terpasang sama dengan versi di server - tidak perlu dimatikan manual |
| 4 | Pemberitahuan dari server yang memuat keterangan versi langsung dipakai: bila aplikasi sedang terbuka, kotak pembaruan beserta tombol **PERBARUI SEKARANG** langsung tampil |
| 5 | Menekan tombol UPDATE (atau pemberitahuannya) membuka aplikasi, lalu aplikasi memeriksa versi dan menampilkan kotak pembaruan |
| 6 | Penanda kode aplikasi dinaikkan menjadi **`RTS-2026-09-30-6`** |

Perbedaan penting antara pemberitahuan biasa dan pengingat pembaruan:

| Jenis | Kapan muncul | Berhenti kapan |
| --- | --- | --- |
| Pemberitahuan pengajuan (sudah ada) | Saat ada pengajuan baru | Sekali muncul |
| Pemberitahuan aktivitas Admin | Saat Admin mengubah data | Sekali muncul |
| **Pengingat pembaruan (baru)** | Segera saat versi baru terdeteksi | **Setelah aplikasi diperbarui** |

---

### C. YANG PERLU DIKERJAKAN SEKALI SAJA

| Nomor | Kegiatan | Keterangan |
| --- | --- | --- |
| 1 | Unduh **kunci layanan Firebase** (service account) dari console Firebase, ubah namanya menjadi `rts_fcm_service_account.json`, unggah ke **`/home/benedics/`** | JANGAN ke dalam `public_html` - berkas ini seperti kunci rumah |
| 2 | Jalankan `RTS_PANEL_TABEL_DEVICE_TOKENS.sql` pada database (uji coba dulu) | Membuat tabel `rts_device_tokens` |
| 3 | Unggah 4 berkas ke `public_html`: `api/notif_otomatis.php`, `api/fcm_kirim.php`, `app_versi.php`, `upload_customer.php` | Seluruhnya ada pada `RTS_PANEL_FIREBASE.zip` |
| 4 | Pasang APK baru ke HP, lalu masuk | Token HP otomatis terdaftar ke server setiap login |

Urutan lengkap beserta cara menguji ada pada berkas **`NOTIFIKASI_OTOMATIS.txt`**.

---

### D. CARA MENGUJI

| Ujian | Cara | Hasil yang diharapkan |
| --- | --- | --- |
| Pemberitahuan biasa | Aplikasi - Pengaturan - Pemberitahuan HP - tombol uji | Pemberitahuan muncul di layar HP |
| **Versi baru** | Unggah APK dengan kode versi lebih tinggi lewat menu Versi Aplikasi | Seluruh HP menerima pemberitahuan bertombol UPDATE, **walau aplikasi tertutup** |
| **Aktivitas Admin** | Unggah CSV customer berisi 1-2 baris uji | Petugas lain menerima pemberitahuan "Data Customer Diperbarui" |
| **Pengingat berulang** | Biarkan aplikasi versi lama tetap terpasang | Pemberitahuan pembaruan muncul kembali setiap jam, sampai aplikasi diperbarui |

---

### E. CATATAN PENTING

| Nomor | Hal |
| --- | --- |
| 1 | Pemberitahuan HP memerlukan izin **"Izinkan Notifikasi"** pada HP (Android 13 ke atas). Aplikasi sudah meminta izin ini saat pertama dibuka |
| 2 | Pemberitahuan hanya terkirim kepada HP yang **sudah pernah masuk** (login) sesudah fitur ini dipasang - karena token HP dikirim saat login |
| 3 | Bila pemberitahuan tidak muncul, periksa keadaan pada aplikasi: **Pengaturan - Pemberitahuan HP**. Bila tertulis "Aktif", seluruh syarat sudah terpenuhi |
| 4 | Jumlah HP yang berhasil dikirimi dicatat pada halaman `app_versi.php` setelah unggahan berhasil |
| 5 | Token HP yang sudah tidak berlaku (mis. aplikasi dihapus) otomatis dibuang dari database oleh `api/fcm_kirim.php` |

## BAGIAN 55 - IKLAN APP OPEN, NATIVE SELURUH MENU, LANGGANAN PRO (QRIS), DAN FOTO PRIBADI

Lima permintaan Bapak pada 30 September 2026 - **semuanya BISA** dan sudah
dikerjakan pada putaran ini:

| Nomor | Permintaan | Jawaban | Kode unit / aturan |
| --- | --- | --- | --- |
| 1 | Iklan AdMob saat aplikasi dibuka | **BISA** | App open `ca-app-pub-1905352530630884/8277624384` |
| 2 | Iklan native di semua menu | **BISA** | Native `ca-app-pub-1905352530630884/9404285058` - kini di **10** tempat |
| 3 | QRIS untuk pembayaran akun PRO | **BISA** | Halaman **Langganan PRO** di dalam aplikasi + `langganan_admin.php` di website |
| 4 | Akun PRO 30 hari + uji coba 7 hari | **BISA** | `api/langganan_inti.php` (`rts_lg_harga()` 5000, `rts_lg_durasi()` 30, `rts_lg_trial()` 7) |
| 5 | Setiap pengguna dapat memasang foto sendiri | **BISA** | `api/upload_foto.php` + kamera/galeri pada halaman Profil |

Panduan lengkap beserta cara mengujinya ada pada berkas
**`IKLAN_LANGGANAN_FOTO.txt`**.

---

### A. IKLAN

```text
   Aplikasi dibuka
        |
        +--> Iklan LAYAR PEMBUKA (app open)  -> muncul sekilas, boleh ditutup
        |
        +--> Beranda   : kartu akun + cuaca + banner + iklan NATIVE
        +--> 9 menu lain juga memuat iklan NATIVE
```

Aturan yang dipasang pada aplikasi:

| Nomor | Aturan |
| --- | --- |
| 1 | Iklan hanya untuk **akun GRATIS**. Akun PRO (atau sedang uji coba) bebas iklan |
| 2 | Iklan layar pembuka paling sering **sekali setiap 4 menit** |
| 3 | Bila iklan belum siap atau gagal dimuat, aplikasi **tetap dibuka normal** |
| 4 | Iklan native yang kuotanya kosong **tidak menampilkan kotak kosong** - kartunya disembunyikan |

### B. LANGGANAN PRO

```text
   Petugas login pertama kali  ---> uji coba 7 hari OTOMATIS (bebas iklan)
   Uji coba habis              ---> kembali GRATIS (iklan tampil)
   Petugas pindai QRIS Rp5.000 ---> tekan "SAYA SUDAH BAYAR"
   Admin membuka langganan_admin.php ---> tekan "SETUJUI + 30 HARI"
   Akun PRO aktif 30 hari      ---> iklan hilang tanpa memasang ulang aplikasi
```

| Hal | Aturan |
| --- | --- |
| Uji coba | 7 hari, **sekali saja** setiap akun, diberikan otomatis saat login |
| Langganan | 30 hari setiap pembayaran diterima Admin |
| Harga | Rp5.000 (nominal pada gambar QRIS Bapak) |
| Perpanjangan | masa lama **ditambahkan**, pembayaran awal tidak hangus |
| Setelah habis | kembali GRATIS, iklan tampil lagi |

### C. FOTO PRIBADI

| Hal | Keterangan |
| --- | --- |
| Cara pakai | Profil - ketuk foto (ada tanda kamera) - Kamera / Galeri / Hapus |
| Tempat penyimpanan | `uploads/foto_profil/` pada hosting, namanya di `sales_users.foto_profil` |
| Ukuran paling besar | 2 MB (aplikasi memperkecil otomatis menjadi 900 x 900 titik) |
| Izin | `android.permission.CAMERA` (sudah ada pada `android_manifest_tambahan.xml`) |

---

### D. YANG DIUNGGAH KE HOSTING

| Berkas | Keadaan |
| --- | --- |
| `api/langganan_inti.php` | **BARU** - aturan langganan (30 hari, uji coba 7 hari, QRIS) |
| `api/langganan.php` | **BARU** - API langganan untuk aplikasi |
| `api/upload_foto.php` | **BARU** - unggah/hapus foto pribadi |
| `api/siapkan_langganan.php` | **BARU** - pembaruan database (khusus ADMIN) |
| `api/login.php` | diperbarui - uji coba otomatis + keadaan langganan + foto |
| `api/session_check.php` | diperbarui - masa berlaku PRO + foto |
| `langganan_admin.php` | **BARU** - halaman Admin: setujui QRIS, +30 hari, trial, QRIS |

Setelah semuanya diunggah, buka `langganan_admin.php` lalu tekan tombol
**PERBARUI DATABASE** (membuat kolom `akun_pro`, `foto_profil`, `pro_mulai`,
`pro_selesai`, `trial_mulai`, `trial_selesai`, dan tabel `pembayaran_pro`).

### E. GAMBAR QRIS

Gambar QRIS Bapak dipasang dengan cara Bapak sendiri (gambar dikirim lewat
WhatsApp, bukan berkas proyek):

```text
   .\PASANG_GAMBAR_QRIS.ps1     -> mencari gambar QRIS di Unduhan/Desktop,
                                   menyalinnya menjadi
                                   assets\images\qris_bene_s.jpg
   flutter clean
   flutter run -d CPH1937
```

Nama berkas harus persis **`qris_bene_s.jpg`** pada folder
`assets\images\`. Selama gambarnya belum ada, halaman Langganan PRO tetap
terbuka dan menampilkan NMID + nominal beserta pengingat.
