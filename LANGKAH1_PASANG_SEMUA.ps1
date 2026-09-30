# =============================================================================
#  RTS PANEL BY BENE - LANGKAH 1: PASANG SEMUA (PUTARAN IKLAN + PRO + FOTO)
#  Berkas : LANGKAH1_PASANG_SEMUA.ps1
#
#  SATU-SATUNYA SKRIP YANG PERLU DIJALANKAN UNTUK TOPIK INI.
#
#  APA YANG DIKERJAKAN SKRIP INI (8 langkah, semuanya dicadangkan lebih dahulu)
#     1. Memastikan folder proyek Flutter ditemukan
#     2. Menyalin main.dart  ->  D:\Project\rts_panel_app\main.dart
#                                D:\Project\rts_panel_app\lib\main.dart
#     3. Menyalin pubspec.yaml (memuat image_picker + nomor versi 1.2.1+4)
#     4. Menambahkan izin KAMERA pada AndroidManifest.xml (bila belum ada)
#     5. Mengubah NAMA APLIKASI pada layar HP menjadi "RTS Panel"
#        (sebelumnya tertulis rts_panel_app)
#     6. Memasang gambar QRIS Bapak -> assets\images\qris_bene_s.jpg
#     7. Menjalankan flutter clean dan flutter pub get
#     8. Menampilkan perintah terakhir yang perlu diketik
#
#  Skrip ini TIDAK menghapus berkas apa pun. Berkas lama selalu dicadangkan
#  dengan tambahan ".lama_tanggal_jam".
#
#  CARA PAKAI
#  ----------
#     1. Ekstrak paket RTS_PANEL_PUTARAN_7.zip ke Desktop
#     2. Buka PowerShell, masuk ke folder hasil ekstrak, contoh:
#            cd "$env:USERPROFILE\Desktop\RTS_PANEL_PUTARAN_7"
#     3. Jalankan:
#            .\LANGKAH1_PASANG_SEMUA.ps1
#     4. Bila muncul pesan "running scripts is disabled", jalankan:
#            powershell -ExecutionPolicy Bypass -File .\LANGKAH1_PASANG_SEMUA.ps1
# =============================================================================

param(
    [string]$Proyek = ''
)

$ErrorActionPreference = 'Stop'

$akarSkrip = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($akarSkrip)) {
    $akarSkrip = (Get-Location).Path
}

# ---------------------------------------------------------------------- tampilan

function Judul($teks) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host (' ' + $teks) -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host ''
}

function Baik($teks) { Write-Host ('   [ OK ] ' + $teks) -ForegroundColor Green }
function Info($teks) { Write-Host ('          ' + $teks) -ForegroundColor Gray }
function Awas($teks) { Write-Host ('   [ ! ]  ' + $teks) -ForegroundColor Yellow }
function Galat($teks) { Write-Host ('   [ X ]  ' + $teks) -ForegroundColor Red }

function Simpan-TanpaBom($jalur, $teks) {
    $penyandi = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $teks, $penyandi)
}

function Salin-DenganCadangan($sumber, $tujuan) {
    if (-not (Test-Path $sumber)) {
        Galat "Berkas sumber tidak ada: $sumber"
        return $false
    }

    if (Test-Path $tujuan) {
        $cadangan = $tujuan + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
        Copy-Item -Path $tujuan -Destination $cadangan -Force
        Info ("cadangan lama : " + (Split-Path $cadangan -Leaf))
    }

    $folderTujuan = Split-Path -Parent $tujuan

    if (-not (Test-Path $folderTujuan)) {
        New-Item -ItemType Directory -Path $folderTujuan -Force | Out-Null
    }

    Copy-Item -Path $sumber -Destination $tujuan -Force
    return $true
}

Judul 'RTS PANEL BY BENE - LANGKAH 1: PASANG SEMUA'
Write-Host ' Topik putaran ini:' -ForegroundColor White
Write-Host '   - iklan saat aplikasi dibuka (app open)' -ForegroundColor Gray
Write-Host '   - iklan native di seluruh menu' -ForegroundColor Gray
Write-Host '   - halaman Langganan PRO dengan QRIS (30 hari + uji coba 7 hari)' -ForegroundColor Gray
Write-Host '   - foto pribadi setiap pengguna' -ForegroundColor Gray
Write-Host ''

# =============================================================================
# 0. FOLDER BERKAS SUMBER (hasil ekstrak paket)
# =============================================================================

$folderAplikasi = Join-Path $akarSkrip '2_APLIKASI_copy_ke_proyek'

if (-not (Test-Path $folderAplikasi)) {
    Galat 'Folder "2_APLIKASI_copy_ke_proyek" tidak ditemukan.'
    Write-Host ''
    Write-Host ' Skrip ini harus dijalankan dari DALAM folder hasil ekstrak paket.' -ForegroundColor Yellow
    Write-Host ' Contoh:' -ForegroundColor Yellow
    Write-Host '     cd "$env:USERPROFILE\Desktop\RTS_PANEL_PUTARAN_7"' -ForegroundColor White
    Write-Host '     .\LANGKAH1_PASANG_SEMUA.ps1' -ForegroundColor White
    Write-Host ''
    exit 1
}

$berkasMain = Join-Path $folderAplikasi 'main.dart'
$berkasPubspec = Join-Path $folderAplikasi 'pubspec.yaml'
$berkasManifestPanduan = Join-Path $folderAplikasi 'android_manifest_tambahan.xml'

Baik 'Berkas aplikasi dari paket ditemukan.'

# =============================================================================
# 1. MENEMUKAN FOLDER PROYEK FLUTTER
# =============================================================================

Judul '1. Mencari folder proyek Flutter'

$kandidat = @()

if (-not [string]::IsNullOrWhiteSpace($Proyek)) {
    $kandidat += $Proyek
}

$kandidat += 'D:\Project\rts_panel_app'
$kandidat += (Join-Path $env:USERPROFILE 'rts_panel_app')

if (Test-Path 'D:\Project') {
    $kandidat += (Get-ChildItem -Path 'D:\Project' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
}

$folderProyek = ''

foreach ($k in $kandidat) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }

    if (Test-Path (Join-Path $k 'pubspec.yaml')) {
        $folderProyek = (Resolve-Path $k).Path
        break
    }
}

if ($folderProyek -eq '') {
    Awas 'Folder proyek Flutter belum ditemukan secara otomatis.'
    Write-Host ''
    Write-Host ' Tuliskan lokasi folder proyek (yang berisi pubspec.yaml).' -ForegroundColor Yellow
    Write-Host ' Contoh: D:\Project\rts_panel_app' -ForegroundColor Gray
    Write-Host ''

    $jawab = Read-Host '   Lokasi folder proyek'

    if ([string]::IsNullOrWhiteSpace($jawab) -or -not (Test-Path (Join-Path $jawab 'pubspec.yaml'))) {
        Galat 'Folder itu tidak memuat pubspec.yaml. Skrip dihentikan tanpa mengubah apa pun.'
        exit 1
    }

    $folderProyek = (Resolve-Path $jawab).Path
}

Baik "Folder proyek : $folderProyek"
Info 'Skrip akan menyalin berkas ke folder ini. Tekan Enter untuk mulai, atau'
Info 'tekan Ctrl+C untuk membatalkan.'

Read-Host '   Tekan Enter untuk mulai' | Out-Null

# =============================================================================
# 2. main.dart  ->  akar dan lib
# =============================================================================

Judul '2. Memasang main.dart (akar + lib\main.dart)'

$tujuanAkar = Join-Path $folderProyek 'main.dart'
$tujuanLib = Join-Path $folderProyek 'lib\main.dart'

if (Salin-DenganCadangan $berkasMain $tujuanAkar) {
    Baik 'main.dart (akar) diperbarui.'
}

if (Salin-DenganCadangan $berkasMain $tujuanLib) {
    Baik 'lib\main.dart diperbarui  <-- INI YANG DIBANGUN FLUTTER.'
}

# =============================================================================
# 3. pubspec.yaml
# =============================================================================

Judul '3. Memasang pubspec.yaml (image_picker + versi 1.2.0+3)'

$tujuanPubspec = Join-Path $folderProyek 'pubspec.yaml'

if (Salin-DenganCadangan $berkasPubspec $tujuanPubspec) {
    $isiPubspec = Get-Content $tujuanPubspec -Raw
    $versi = '(tidak terbaca)'

    if ($isiPubspec -match '(?m)^version:\s*(.+)$') {
        $versi = $Matches[1].Trim()
    }

    Baik "pubspec.yaml diperbarui (versi $versi)."

    if ($isiPubspec -match 'image_picker') {
        Baik 'image_picker sudah ada di dalamnya (untuk memilih foto).'
    } else {
        Awas 'image_picker TIDAK ada di pubspec. Gunakan pubspec.yaml dari paket ini.'
    }
}

# =============================================================================
# 4. IZIN KAMERA PADA AndroidManifest.xml
# =============================================================================

Judul '4. Menambahkan izin KAMERA pada AndroidManifest.xml'

$jalurManifest = Join-Path $folderProyek 'android\app\src\main\AndroidManifest.xml'

if (-not (Test-Path $jalurManifest)) {
    Awas 'AndroidManifest.xml tidak ditemukan.'
    Info 'Bila folder proyek ini belum lengkap, jalankan flutter create . lebih dahulu.'
} else {
    $isiManifest = Get-Content $jalurManifest -Raw

    if ($isiManifest -match 'android\.permission\.CAMERA') {
        Baik 'Izin KAMERA sudah ada. Tidak diubah lagi.'
    } else {
        $barisKamera = '<uses-permission android:name="android.permission.CAMERA" />'

        if ($isiManifest -match '<application') {
            $cadanganManifest = $jalurManifest + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
            Copy-Item -Path $jalurManifest -Destination $cadanganManifest -Force
            Info ('cadangan lama : ' + (Split-Path $cadanganManifest -Leaf))

            $pengganti = "`r`n    " + $barisKamera + "`r`n`r`n`$1"
            $isiBaru = [regex]::Replace($isiManifest, '(\s*<application)', $pengganti, 1)
            Simpan-TanpaBom $jalurManifest $isiBaru

            $cek = Get-Content $jalurManifest -Raw

            if ($cek -match 'android\.permission\.CAMERA') {
                Baik 'Izin KAMERA ditambahkan (untuk mengambil foto dari kamera).'
            } else {
                Awas 'Izin KAMERA belum berhasil ditambahkan. Buka android_manifest_tambahan.xml.'
            }
        } else {
            Awas 'Baris <application> tidak ditemukan pada AndroidManifest.xml.'
            Info 'Tambahkan manual: ' + $barisKamera
        }
    }

    if ((Get-Content $jalurManifest -Raw) -match 'com.google.android.gms.ads\.APPLICATION_ID') {
        Baik 'Kode aplikasi AdMob sudah ada pada AndroidManifest.xml.'
    } else {
        Awas 'Kode aplikasi AdMob BELUM ada pada AndroidManifest.xml.'
        Info 'Iklan tidak akan tampil tanpa baris meta-data APPLICATION_ID.'
        Info 'Baris itu seharusnya sudah ada sejak putaran iklan sebelumnya.'
        Info 'Contoh barisnya ada pada berkas android_manifest_tambahan.xml'
        Info '(folder 2_APLIKASI_copy_ke_proyek) bagian bawah.'
    }
}

# =============================================================================
# 5. NAMA APLIKASI PADA LAYAR HP  ->  "RTS Panel"
# =============================================================================

Judul '5. Mengubah nama aplikasi pada layar HP menjadi "RTS Panel"'

$namaBaru = 'RTS Panel'

if (-not (Test-Path $jalurManifest)) {
    Awas 'AndroidManifest.xml tidak ditemukan - nama aplikasi tidak diubah.'
} else {
    $isiNama = Get-Content $jalurManifest -Raw

    if ($isiNama -match ('android:label="' + [regex]::Escape($namaBaru) + '"')) {
        Baik 'Nama aplikasi sudah "RTS Panel". Tidak diubah lagi.'
    } elseif ($isiNama -match 'android:label="[^"]*"') {
        $namaLama = [regex]::Match($isiNama, 'android:label="([^"]*)"').Groups[1].Value

        $cadanganNama = $jalurManifest + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
        Copy-Item -Path $jalurManifest -Destination $cadanganNama -Force
        Info ('cadangan lama : ' + (Split-Path $cadanganNama -Leaf))

        $isiNamaBaru = [regex]::Replace($isiNama, 'android:label="[^"]*"', ('android:label="' + $namaBaru + '"'))
        Simpan-TanpaBom $jalurManifest $isiNamaBaru

        $cekNama = Get-Content $jalurManifest -Raw

        if ($cekNama -match ('android:label="' + [regex]::Escape($namaBaru) + '"')) {
            Baik ('Nama aplikasi diubah dari "' + $namaLama + '" menjadi "' + $namaBaru + '".')
            Info 'Nama baru terlihat pada layar HP setelah aplikasi dipasang ulang.'
        } else {
            Awas 'Nama aplikasi belum berhasil diubah.'
        }
    } else {
        Awas 'Baris android:label tidak ditemukan pada AndroidManifest.xml.'
        Info 'Tambahkan sendiri pada tag <application>: android:label="RTS Panel"'
    }
}

# =============================================================================
# 6. GAMBAR QRIS
# =============================================================================

Judul '6. Memasang gambar QRIS'

$folderGambar = Join-Path $folderProyek 'assets\images'

if (-not (Test-Path $folderGambar)) {
    New-Item -ItemType Directory -Path $folderGambar -Force | Out-Null
    Info "Folder dibuat : $folderGambar"
}

$tujuanQris = Join-Path $folderGambar 'qris_bene_s.jpg'

if (Test-Path $tujuanQris) {
    Baik "Gambar QRIS sudah ada ($([math]::Round((Get-Item $tujuanQris).Length / 1KB, 1)) KB)."
    Info 'Lewati langkah ini bila gambar itu sudah benar.'
} else {
    Awas 'Gambar QRIS belum ada. Halaman Langganan PRO tetap dapat dibuka,'
    Info 'tetapi gambarnya belum tampil.'

    $jawab = Read-Host '   Tulis lokasi gambar QRIS (atau tekan Enter agar dicarikan otomatis)'

    if ([string]::IsNullOrWhiteSpace($jawab)) {
        Info 'Mencari gambar QRIS di folder Unduhan / Desktop / Pictures...'

        $cari = @()

        foreach ($f in @('Downloads', 'Desktop', 'Pictures', 'OneDrive\Pictures', 'OneDrive\Downloads')) {
            $folderCari = Join-Path $env:USERPROFILE $f

            if (Test-Path $folderCari) {
                $cari += Get-ChildItem -Path $folderCari -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } |
                    Where-Object { $_.Name -match '(?i)qris|bene|whatsapp|wa\d' }
            }
        }

        if ($cari.Count -gt 0) {
            $pilih = $cari | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Info ('Ditemukan : ' + $pilih.FullName)
            Info ('Diubah    : ' + $pilih.LastWriteTime)

            $ya = Read-Host '   Pakai gambar ini? (Y/n)'

            if ([string]::IsNullOrWhiteSpace($ya) -or $ya -match '^(?i)y') {
                $jawab = $pilih.FullName
            }
        } else {
            Awas 'Tidak ada gambar yang cocok ditemukan.'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($jawab) -and (Test-Path $jawab)) {
        Copy-Item -Path $jawab -Destination $tujuanQris -Force
        Baik 'Gambar QRIS dipasang menjadi assets\images\qris_bene_s.jpg.'
    } else {
        Info 'Dilewati. Pasang kapan saja dengan menjalankan berkas'
        Info 'PASANG_GAMBAR_QRIS.ps1 yang ada di folder 3_SKRIP_POWERSHELL.'
    }
}

# =============================================================================
# 6. flutter clean + flutter pub get
# =============================================================================

Judul '7. Menjalankan flutter clean dan flutter pub get'

$flutter = Get-Command flutter -ErrorAction SilentlyContinue

if (-not $flutter) {
    Awas 'Perintah "flutter" tidak ditemukan pada PATH.'
    Info 'Buka PowerShell baru, lalu jalankan sendiri di folder proyek:'
    Info '    flutter clean'
    Info '    flutter pub get'
} else {
    Push-Location $folderProyek

    try {
        Info 'Menjalankan flutter clean...'
        & flutter clean

        Info 'Menjalankan flutter pub get...'
        & flutter pub get

        Baik 'flutter clean dan flutter pub get selesai.'
    }
    catch {
        Awas 'Perintah flutter gagal dijalankan. Jalankan sendiri di folder proyek:'
        Info '    flutter clean'
        Info '    flutter pub get'
    }
    finally {
        Pop-Location
    }
}

# =============================================================================
# 7. RINGKASAN
# =============================================================================

Judul '8. SELESAI - LANGKAH BERIKUTNYA'

Write-Host ' Di komputer (sekarang):' -ForegroundColor White
Write-Host '     cd ' $folderProyek -ForegroundColor Gray
Write-Host ''
Write-Host '     flutter devices' -ForegroundColor White
Write-Host '     flutter run -d CPH1937' -ForegroundColor White
Write-Host ''
Write-Host ' Di hosting (cPanel) - WAJIB dikerjakan supaya langganan PRO bekerja:' -ForegroundColor White
Write-Host '     1. Unggah isi folder 1_SERVER_unggah_ke_hosting ke public_html' -ForegroundColor Gray
Write-Host '     2. Buka https://rts.benedic-s.com/langganan_admin.php' -ForegroundColor Gray
Write-Host '     3. Tekan tombol PERBARUI DATABASE' -ForegroundColor Gray
Write-Host ''
Write-Host ' Periksa di aplikasi:' -ForegroundColor White
Write-Host '     Layar HP    : nama aplikasi harus "RTS Panel"' -ForegroundColor Gray
Write-Host '     Pengaturan  : penanda harus RTS-2026-09-30-7' -ForegroundColor Gray
Write-Host '     Profil      : tombol LANGGANAN PRO tampil + gambar QRIS tampil' -ForegroundColor Gray
Write-Host '     Profil      : ketuk foto -> pilih dari galeri -> foto berubah' -ForegroundColor Gray
Write-Host '     Beranda     : iklan banner + iklan native tampil (akun GRATIS)' -ForegroundColor Gray
Write-Host ''
Write-Host ' Bila ada yang gagal, buka berkas BACA_DULU.txt bagian "KALAU ADA MASALAH".' -ForegroundColor Yellow
Write-Host ''
