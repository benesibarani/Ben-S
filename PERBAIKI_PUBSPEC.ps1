# =============================================================================
#  RTS PANEL BY BENE - PERBAIKI PUBSPEC.YAML (PAKET IKLAN BELUM TERPASANG)
#  Berkas: PERBAIKI_PUBSPEC.ps1
#
#  GEJALA YANG DIPERBAIKI:
#
#     Di VS Code muncul banyak tulisan merah seperti:
#        Target of URI doesn't exist:
#        'package:google_mobile_ads/google_mobile_ads.dart'
#        Undefined name 'MobileAds'
#        Undefined class 'BannerAd'
#        Undefined class 'NativeAd'
#        ... dan seterusnya
#
#  SEBABNYA: main.dart memakai paket iklan (google_mobile_ads) dan paket versi
#  (package_info_plus), tetapi kedua paket itu belum terdaftar di pubspec.yaml
#  proyek Bapak. Akibatnya Dart tidak mengenal MobileAds, BannerAd, NativeAd,
#  AdSize, AdWidget, dan sejenisnya.
#
#  YANG DIKERJAKAN SKRIP INI:
#
#     1. Mencadangkan pubspec.yaml yang sekarang ke cadangan_arena
#     2. Menambahkan paket yang kurang PADA TEMPAT YANG BENAR, tanpa mengubah
#        bagian lain (nama proyek, daftar assets, dan paket Anda tetap utuh)
#     3. Memastikan folder assets/images terdaftar (agar gambar latar terbaca)
#     4. Memastikan nomor versi siap untuk pembaruan otomatis
#     5. Menjalankan flutter pub get
#     6. MEMERIKSA hasilnya - paket benar-benar terpasang atau tidak
#
#  CARA PAKAI:
#     1. Simpan di folder proyek: D:\Project\rts_panel_app
#     2. Di terminal VS Code:
#          powershell -ExecutionPolicy Bypass -File .\PERBAIKI_PUBSPEC.ps1
#     3. Setelah selesai, di VS Code tekan Ctrl+Shift+P, ketik
#        "Dart: Restart Analysis Server", lalu tekan Enter
#        (tulisan merah akan hilang)
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

function TulisHasil($ok, $teks) {
    if ($ok) { Write-Host "   OK      : $teks" -ForegroundColor Green }
    else     { Write-Host "   MASALAH : $teks" -ForegroundColor Red }
}

function Simpan-TanpaBom($jalur, $teks) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $teks, $utf8)
}

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

$jalurPubspec = "pubspec.yaml"

if (-not (Test-Path $jalurPubspec)) {
    Write-Host "pubspec.yaml tidak ditemukan di $proyek" -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# 1. Cadangkan
# -----------------------------------------------------------------------------
TulisJudul "1. Mencadangkan pubspec.yaml"

$folderCadangan = "cadangan_arena"

if (-not (Test-Path $folderCadangan)) {
    New-Item -ItemType Directory -Path $folderCadangan | Out-Null
}

Copy-Item $jalurPubspec (Join-Path $folderCadangan "pubspec.yaml.asli") -Force
Write-Host "   dicadangkan: cadangan_arena\pubspec.yaml.asli" -ForegroundColor Gray

$isiAwal = Get-Content $jalurPubspec -Raw
$isi = $isiAwal

# -----------------------------------------------------------------------------
# 2. Paket yang kurang
# -----------------------------------------------------------------------------
TulisJudul "2. Memeriksa paket yang dibutuhkan main.dart"

$paket = @(
    @{ nama = "google_mobile_ads"; versi = "9.1.0";  untuk = "iklan AdMob (banner + native)" },
    @{ nama = "package_info_plus"; versi = "10.2.1"; untuk = "pembaruan otomatis (versi aplikasi)" }
)

$kurang = @()

foreach ($satu in $paket) {
    if ($isiAwal -match ("(?m)^\s*" + [regex]::Escape($satu.nama) + "\s*:")) {
        Write-Host "   sudah ada : $($satu.nama)" -ForegroundColor Gray
    }
    else {
        Write-Host "   BELUM ADA : $($satu.nama)  ($($satu.untuk))" -ForegroundColor Yellow
        $kurang += $satu
    }
}

# -----------------------------------------------------------------------------
# 3. Menambahkan paket yang kurang pada bagian dependencies
# -----------------------------------------------------------------------------
if ($kurang.Count -gt 0) {
    TulisJudul "3. Menambahkan paket ke bagian dependencies"

    $baris = @(Get-Content $jalurPubspec)
    $keluar = New-Object System.Collections.Generic.List[string]

    # Titik sisip: baris "cupertino_icons", atau "sdk: flutter" dalam dependencies.
    $titik = -1

    for ($i = 0; $i -lt $baris.Count; $i++) {
        if ($baris[$i] -match '^\s*cupertino_icons\s*:') {
            $titik = $i
            break
        }
    }

    if ($titik -lt 0) {
        for ($i = 0; $i -lt $baris.Count; $i++) {
            if ($baris[$i] -match '^\s*sdk:\s*flutter\s*$') {
                $titik = $i
                break
            }
        }
    }

    if ($titik -lt 0) {
        Write-Host "   GAGAL menemukan bagian dependencies." -ForegroundColor Red
        Write-Host "   Kirimkan isi pubspec.yaml ke saya." -ForegroundColor Yellow
        exit 1
    }

    for ($i = 0; $i -lt $baris.Count; $i++) {
        $keluar.Add($baris[$i])

        if ($i -eq $titik) {
            foreach ($satu in $kurang) {
                $keluar.Add("  # " + $satu.untuk)
                $keluar.Add("  " + $satu.nama + ": ^" + $satu.versi)
            }
        }
    }

    $isi = ($keluar -join "`r`n") + "`r`n"

    foreach ($satu in $kurang) {
        Write-Host "   DITAMBAH: $($satu.nama): ^$($satu.versi)" -ForegroundColor Green
    }
}
else {
    TulisJudul "3. Tidak ada paket yang perlu ditambahkan"
    Write-Host "   Kedua paket sudah terdaftar." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 4. Memastikan folder assets/images terdaftar
# -----------------------------------------------------------------------------
TulisJudul "4. Memeriksa bagian assets"

if ($isi -match '(?m)^\s*-\s*assets/images/\s*$') {
    Write-Host "   sudah ada : seluruh folder assets/images terdaftar" -ForegroundColor Gray
}
elseif ($isi -match '(?m)^\s*assets:\s*$') {
    # Ganti pendaftaran per-berkas gambar menjadi pendaftaran folder, supaya
    # gambar baru yang ditambahkan nanti langsung terbaca tanpa ubah berkas ini.
    $isiBaru = [regex]::Replace(
        $isi,
        '(?m)^(\s*)-\s*assets/images/[^\r\n]*$',
        '$1- assets/images/'
    )

    if ($isiBaru -ne $isi) {
        $isi = $isiBaru
        Write-Host "   DIPERBARUI: pendaftaran gambar diubah menjadi seluruh folder" -ForegroundColor Green
    }
    else {
        $isi = $isi -replace '(?m)^(\s*)assets:\s*$', "`$1assets:`r`n`$1  - assets/images/"
        Write-Host "   DITAMBAH: pendaftaran folder assets/images" -ForegroundColor Green
    }
}
else {
    Write-Host "   Bagian assets belum ada - ditambahkan." -ForegroundColor Yellow

    $isi = $isi.TrimEnd() + "`r`n`r`nflutter:`r`n  uses-material-design: true`r`n`r`n  assets:`r`n    - assets/images/`r`n"

    Write-Host "   DITAMBAH: bagian flutter + assets" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 5. Nomor versi untuk pembaruan otomatis
# -----------------------------------------------------------------------------
TulisJudul "5. Memeriksa nomor versi aplikasi"

if ($isi -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    $namaVersi = $Matches[1]
    $kodeVersi = [int]$Matches[2]

    if ($kodeVersi -lt 2) {
        $isi = [regex]::Replace($isi, '(?m)^version:.*$', 'version: 1.1.0+2')
        Write-Host "   DIPERBARUI: version: 1.1.0+2 (agar siap pembaruan otomatis)" -ForegroundColor Green
    }
    else {
        Write-Host "   sudah siap: versi $namaVersi (kode $kodeVersi)" -ForegroundColor Gray
    }
}
else {
    Write-Host "   Baris version tidak dikenali - dibiarkan apa adanya." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 6. Simpan
# -----------------------------------------------------------------------------
TulisJudul "6. Menyimpan pubspec.yaml"

if ($isi -ne $isiAwal) {
    Simpan-TanpaBom $jalurPubspec $isi
    Write-Host "   pubspec.yaml diperbarui." -ForegroundColor Green
}
else {
    Write-Host "   pubspec.yaml tidak perlu diubah." -ForegroundColor Green
}

Write-Host ""
Write-Host "   Isi bagian dependencies sekarang:" -ForegroundColor White

$barisBaru = @(Get-Content $jalurPubspec)
$didalam = $false

foreach ($satu in $barisBaru) {
    if ($satu -match '^dependencies:') { $didalam = $true; Write-Host "     $satu" -ForegroundColor DarkGray; continue }
    if ($didalam -and $satu -match '^[a-zA-Z]') { $didalam = $false }
    if ($didalam) { Write-Host "     $satu" -ForegroundColor DarkGray }
}

# -----------------------------------------------------------------------------
# 7. flutter pub get
# -----------------------------------------------------------------------------
TulisJudul "7. Memasang paket (flutter pub get)"
Write-Host "   Perlu internet. Tunggu sampai selesai..." -ForegroundColor Yellow
Write-Host ""

flutter pub get

# -----------------------------------------------------------------------------
# 8. MEMERIKSA HASIL
# -----------------------------------------------------------------------------
TulisJudul "8. Memeriksa hasil pemasangan"

$bermasalah = 0
$jalurKonfig = ".dart_tool\package_config.json"

if (Test-Path $jalurKonfig) {
    $konfig = Get-Content $jalurKonfig -Raw

    foreach ($satu in $paket) {
        if ($konfig -match [regex]::Escape($satu.nama)) {
            TulisHasil $true "$($satu.nama) TERPASANG"
        }
        else {
            TulisHasil $false "$($satu.nama) BELUM terpasang"
            $bermasalah++
        }
    }
}
else {
    TulisHasil $false ".dart_tool\package_config.json belum ada - pub get belum berhasil"
    $bermasalah++
}

# pubspec.lock juga diperiksa sebagai bukti kedua.
if (Test-Path "pubspec.lock") {
    $kunci = Get-Content "pubspec.lock" -Raw

    $adaIklan = $kunci -match "(?m)^\s+google_mobile_ads:"
    $adaVersi = $kunci -match "(?m)^\s+package_info_plus:"

    TulisHasil $adaIklan "pubspec.lock memuat google_mobile_ads"
    TulisHasil $adaVersi "pubspec.lock memuat package_info_plus"

    if (-not ($adaIklan -and $adaVersi)) { $bermasalah++ }
}

# -----------------------------------------------------------------------------
# 9. Selesai
# -----------------------------------------------------------------------------
Write-Host ""

if ($bermasalah -gt 0) {
    Write-Host "   ADA $bermasalah MASALAH." -ForegroundColor Red
    Write-Host ""
    Write-Host "   Yang perlu diperiksa:" -ForegroundColor Yellow
    Write-Host "     1. Sambungan internet komputer" -ForegroundColor Gray
    Write-Host "     2. Bila pub get menampilkan tulisan error di atas, salin dan" -ForegroundColor Gray
    Write-Host "        kirimkan kepada saya" -ForegroundColor Gray
    Write-Host "     3. Bila error memuat 'version solving failed', artinya ada paket" -ForegroundColor Gray
    Write-Host "        yang versinya bentrok - kirimkan bagian itu saja" -ForegroundColor Gray
    exit 1
}

TulisJudul "SELESAI - PAKET SUDAH TERPASANG"

Write-Host "   Tulisan merah pada VS Code akan hilang setelah langkah berikut:" -ForegroundColor Green
Write-Host ""
Write-Host "     1. Di VS Code tekan Ctrl + Shift + P" -ForegroundColor White
Write-Host "     2. Ketik: Dart: Restart Analysis Server" -ForegroundColor White
Write-Host "     3. Tekan Enter" -ForegroundColor White
Write-Host ""
Write-Host "   Bila masih ada tulisan merah pada baris impor, tutup dan buka" -ForegroundColor Gray
Write-Host "   kembali berkas main.dart." -ForegroundColor Gray
Write-Host ""
Write-Host "   Selanjutnya jalankan (HP sudah tersambung nirkabel):" -ForegroundColor White
Write-Host "     powershell -ExecutionPolicy Bypass -File .\PASANG_FITUR_BARU.ps1" -ForegroundColor Cyan
