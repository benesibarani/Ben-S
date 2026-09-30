# UJI APLIKASI RTS PANEL — DAFTAR PERIKSA

Berkas ini dipakai untuk menguji aplikasi yang **sudah terpasang di HP** dan
website-nya. Cara pakai: kerjakan berurutan, centang bila hasilnya **benar**.

Bila ada yang **tidak** sesuai, catat **nomornya** dan kirimkan ke saya
(tangkapan layar sangat membantu). Tidak perlu menguji semuanya sekaligus —
boleh per bagian, dan kabari hasil per bagian.

Keterangan singkat:

- **Aplikasi** = aplikasi di HP (RTS Panel By Bene)
- **Website** = `https://rts.benedic-s.com`
- **Staging** = `https://coba.benedic-s.com` (kalau ingin uji di sana dulu)

---

## A. LOGIN & SESI (6 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| A1 | Login memakai **username** | Buka aplikasi, isi username (bukan email) + password | Masuk ke Dashboard | ☐ |
| A2 | Password salah | Isi password acak | Muncul pesan jelas, tidak masuk | ☐ |
| A3 | Ingat Saya | Tutup aplikasi **total** (dari daftar aplikasi), buka lagi | Langsung Dashboard, tidak diminta login | ☐ |
| A4 | Keluar | Menu Pengaturan/Profil → tombol Keluar | Kembali ke halaman login | ☐ |
| A5 | Ganti server | Pengaturan → pindah server (Staging/Produksi) | Diminta login ulang (sesi mengikuti server) | ☐ |
| A6 | Penanda produksi | Pengaturan → lihat penanda server | Server produksi ditandai jelas (tidak tertukar dengan staging) | ☐ |

## B. TAMPILAN DASHBOARD (4 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| B1 | Kartu angka terisi | Buka Dashboard | Total Customer, Customer Aktif, Total GSP, Pengajuan Pending ada angkanya | ☐ |
| B2 | Cakupan role | Login sebagai RTS/TF, lalu sebagai ADMIN | RTS/TF: angka lebih sedikit (sesuai district); ADMIN: seluruh data | ☐ |
| B3 | Tidak ada teks terpotong | Geser/perbesar tampilan | Tidak ada tulisan terpotong atau biru-kuning *overflow* | ☐ |
| B4 | Gambar latar | Lihat Dashboard & login | Gambar dari `assets/images` tampil sebagai latar, tidak menutupi form | ☐ |

## C. MASTER CUSTOMER (5 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| C1 | Cakupan WSS/SMST | Login sebagai WSS atau SMST | Semua district terlihat | ☐ |
| C2 | Cakupan RTS/TF | Login sebagai RTS/TF | Hanya customer pada Sales District akun | ☐ |
| C3 | Filter GSP vs Reguler | Tekan filter GSP | **Hanya** customer GSP (jumlahnya kecil, bukan seluruh data) | ☐ |
| C4 | Tombol peta | Buka Detail Customer → tekan tombol peta | **Sekali klik** langsung membuka Google Maps pada titik customer | ☐ |
| C5 | Pencarian | Ketik sebagian nama toko | Daftar menyempit sesuai kata kunci | ☐ |

## D. PENGAJUAN (13 butir) — bagian terpenting

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| D1 | Tombol mengambang | Buka menu Pengajuan | Ada tombol **Pengajuan Baru** (FAB) | ☐ |
| D2 | Kolom Nama Toko selalu ada | Tekan FAB | Kolom "Nama Toko" (pemilih customer) tampil | ☐ |
| D3 | Daftar toko otomatis | Pilih jenis **Ganti Nama** tanpa memilih customer | Daftar nama toko otomatis terbuka | ☐ |
| D4 | Terkunci dari database | Pilih satu customer | Keterangan terisi otomatis **dan terkunci** | ☐ |
| D5 | Buka lewat centang | Centang salah satu kolom | Hanya kolom itu yang bisa diubah | ☐ |
| D6 | Hari Kunjungan | Buka centang Hari | Berbentuk **dropdown** (Senin s/d Sabtu) | ☐ |
| D7 | Frekuensi Kunjungan | Buka centang Frekuensi | Dropdown: **Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap** | ☐ |
| D8 | Koordinat Ganti Alamat | Pada Ganti Alamat, tekan ikon koordinat | Muncul opsi "Sesuai koordinat sekarang" + indikator warna akurasi | ☐ |
| D9 | Alamat lengkap dari GPS | Tekan "Sesuai koordinat sekarang" | Kolom alamat terisi **alamat lengkap**; **tidak ada** teks angka koordinat mentah | ☐ |
| D10 | Perbarui titik & Cek di Maps | Tekan kedua tombol itu | Titik diperbarui; peta terbuka pada titik tersebut | ☐ |
| D11 | Kirim pengajuan | Isi lengkap → Kirim | Muncul pesan berhasil, pengajuan masuk daftar | ☐ |
| D12 | Setujui (ADMIN/ASS) | Login ADMIN → buka pengajuan → **Setujui** | Status berubah; Master Customer ikut berubah (nama/alamat/hari/frekuensi) | ☐ |
| D13 | Hak role | Login RTS/TF → buka pengajuan | Tombol **Setujui/Tolak tidak ada** | ☐ |

## E. NOTIFIKASI DI LAYAR HP (8 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| E1 | Permintaan izin | Pertama kali membuka (atau tekan lonceng) | Muncul "Izinkan Notifikasi" | ☐ |
| E2 | Tombol IZINKAN | Dashboard → kartu "Aktifkan Pemberitahuan?" → IZINKAN | Izin diberikan; status di Pengaturan jadi "Pemberitahuan HP aktif" | ☐ |
| E3 | Pemberitahuan percobaan | Pengaturan → **KIRIM PEMBERITAHUAN PERCOBAAN** | Muncul pemberitahuan di layar HP | ☐ |
| E4 | Pengajuan baru | Dari HP lain / website, kirim pengajuan baru | ADMIN & ASS menerima pemberitahuan | ☐ |
| E5 | Disetujui | ADMIN menyetujui pengajuan | Pengirim menerima pemberitahuan "Disetujui" | ☐ |
| E6 | Ditolak | ADMIN menolak pengajuan | Pengirim menerima pemberitahuan "Ditolak" | ☐ |
| E7 | Tekan pemberitahuan | Sentuh pemberitahuan di layar HP | Aplikasi terbuka pada menu **Pemberitahuan** | ☐ |
| E8 | Tandai dibaca | Buka menu Pemberitahuan | Angka lonceng berkurang / hilang | ☐ |

> **Catatan penting:** selama aplikasi **hidup** (termasuk di latar belakang),
> pemberitahuan datang dalam ±2 menit. Bila aplikasi **ditutup total**,
> pemberitahuan baru masuk saat aplikasi dibuka lagi — untuk yang instan walau
> aplikasi mati total diperlukan **Firebase** (belum ditempuh, lihat PANDUAN
> bagian 25 huruf G).

## F. PROFIL & SINKRONISASI (5 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| F1 | Informasi akun | Menu Profil | Nama, `@username`, role, district tampil benar | ☐ |
| F2 | Password lama salah | Ganti Password → isi password lama yang salah | Muncul pesan "Password lama tidak sesuai." | ☐ |
| F3 | Ganti password | Isi benar → simpan | Berhasil; **Keluar** lalu login memakai password baru | ☐ |
| F4 | Sesi HP lain | Bila akun pernah login di HP lain | HP lain itu diminta login ulang | ☐ |
| F5 | Sinkronisasi | Menu Sinkronisasi → **SINKRONKAN SEKARANG** | Angka Customer / Pengajuan / Pemberitahuan terisi + waktu sinkron tersimpan | ☐ |

## G. KESELARASAN APLIKASI ↔ WEBSITE (5 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| G1 | Pengajuan dari aplikasi masuk website | Kirim pengajuan dari HP → buka website → menu **Inbox** | Pengajuan itu ada di daftar | ☐ |
| G2 | Frekuensi di form website | Website → **Pengajuan Customer** | Ada kolom **Frekuensi Kunjungan** (Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap) | ☐ |
| G3 | Hasil approve dari website | Website → Setujui pengajuan | Master Customer ikut berubah, termasuk kolom Frekuensi | ☐ |
| G4 | Hasil approve dari aplikasi | Aplikasi (ADMIN) → Setujui | Hasilnya **persis sama** dengan approve dari website | ☐ |
| G5 | Dashboard website | Website → Dashboard | Kartu angka ikut cakupan role (bukan 0) | ☐ |

## H. KEAMANAN & KEBERSIHAN (4 butir)

| No | Yang diuji | Cara | Hasil yang benar | ✓ |
| --- | --- | --- | --- | --- |
| H1 | Berkas website utuh | Upload `api/env_check.php` v4 → buka di browser | Bagian `berkas_website` semua `COCOK` | ☐ |
| H2 | Hapus alat uji | Setelah semua pengujian selesai | `env_check.php` dan `scope_check.php` **dihapus** dari kedua domain | ☐ |
| H3 | Repository GitHub | Buka pengaturan repo `benesibarani/Ben-S` | Sudah **private** (dump SQL produksi jangan publik) | ☐ |
| H4 | Password database | cPanel → MySQL → ubah password user DB → sesuaikan `config.php` | Website tetap berjalan setelah diganti | ☐ |

---

## CARA MELAPORKAN HASIL

Kirim pesan singkat seperti ini:

```
Sudah diuji bagian A, B, C.
Yang gagal: C4 (tombol peta menyalin link, tidak membuka Maps),
            D7 (kolom Frekuensi tidak muncul)
Sisanya benar.
```

Untuk setiap yang gagal, sertakan: **nomor butir**, **apa yang terjadi**,
dan **tangkapan layar** bila ada. Saya akan perbaiki dan kirimkan berkas
lengkapnya.

## URUTAN YANG DISARANKAN

1. **Bagian A dan B** dulu (login + tampilan) — paling cepat, ±10 menit.
2. Lanjut **bagian D** (Pengajuan) — bagian terpenting, karena menyangkut data.
3. Lanjut **E** (Notifikasi) — perlu dua akun untuk uji pengajuan baru.
4. Lanjut **C, F, G, H** kapan saja.
