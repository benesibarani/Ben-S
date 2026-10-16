# benedic-s — CV profesional Benedictus L. Sibarani

Website CV berbahasa Indonesia dengan foto asli, profil profesional, riwayat karier, filter Sales/IT, detail pekerjaan, keahlian, pendidikan, dan kontak. Konten mengikuti dokumen CV yang diberikan; pekerjaan terakhir dicatat Mei 2023–Juni 2026, bukan diasumsikan masih berjalan.

## Pengembangan

Memerlukan Node.js 22+.

```sh
npm ci
npm run dev
```

Buka port yang ditampilkan Vite (default 5173). Font dan ikon disajikan lokal, tanpa CDN eksternal.

```sh
npm test        # Build dan 5 pengujian DOM/interaksi
npm run build  # Hasil produksi di dist/
npm run preview
```

Pengujian DOM memverifikasi filter, accordion, menu mobile, tautan kontak, serta keberadaan aset. Pengujian visual browser belum dilakukan karena unduhan Chromium diblokir oleh akses jaringan lingkungan.

## Memasang ke domain

1. Jalankan `npm ci` dan `npm run build`.
2. Unggah **isi folder `dist/` saja** ke document root domain melalui panel hosting, atau gunakan static hosting dengan build command `npm run build` dan output directory `dist`.
3. Hubungkan nama domain lengkap melalui pengaturan custom domain hosting, lalu ikuti petunjuk record DNS dari penyedia hosting.
4. Aktifkan HTTPS dan periksa tombol unduh CV, email, WhatsApp, serta LinkedIn.

Website tidak memerlukan PHP, database, atau backend. File PHP lama dalam repositori tidak diubah dan **bukan bagian dari website CV**; jangan unggah seluruh repositori sebagai document root. Jika hosting yang sama menjalankan aplikasi lama, simpan aplikasi itu pada direktori/subdomain terpisah sebelum memasang website ini.

Domain belum dihubungkan otomatis. Nama lengkap beserta ekstensinya dan penyedia hosting perlu dikonfirmasi untuk konfigurasi DNS yang tepat.

## Pembaruan konten

- Profil, pendidikan, keahlian, dan kontak: `index.html`.
- Riwayat pekerjaan dan interaksi: `src/main.js`.
- Tampilan responsif: `src/style.css`.
- Foto: `public/assets/benedictus.jpeg`.
- CV PDF asli: `public/assets/CV-Benedictus-Sibarani.pdf`.

Foto, nomor telepon, email, dan CV PDF dapat diakses publik saat website diterbitkan. Pastikan data yang ingin dipublikasikan sudah sesuai.
