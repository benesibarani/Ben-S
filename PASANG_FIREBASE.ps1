# =============================================================================
#  RTS PANEL BY BENE - PEMASANGAN FIREBASE (PEMBERITAHUAN WALAU APLIKASI DITUTUP)
#  Berkas: PASANG_FIREBASE.ps1
#
#  Skrip ini menyiapkan sisi Android/Gradle untuk Firebase:
#    1. Memeriksa berkas android\app\google-services.json (dari Firebase Console)
#    2. Menyisipkan plugin google-services pada android\settings.gradle.kts
#    3. Memastikan plugin google-services ada pada android\app\build.gradle.kts
#    4. Memeriksa apakah nama paket pada google-services.json sudah cocok
#    5. Menjalankan flutter pub get
#
#  BERKAS INI AMAN DIJALANKAN BERKALI-KALI:
#    - Berkas asli dicadangkan lebih dahulu dengan akhiran .lama
#    - Bagian yang sudah ada tidak disisipkan dua kali
#
#  CARA PAKAI:
#    1. Letakkan berkas google-services.json di folder android\app\ proyek
#    2. Simpan berkas ini di D:\Project\rts_panel_app
#    3. Terminal VS Code:
#         powershell -ExecutionPolicy Bypass -File .\PASANG_FIREBASE.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
$paketAplikasi = "com.example.rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

# Menulis berkas TANPA penanda BOM, supaya tidak merusak berkas Gradle.
function Simpan-TanpaBom($jalur, $teks) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $teks, $utf8)
}

# Menyisipkan baris tertentu setelah baris yang cocok dengan pola.
function Sisipkan-Setelah($jalur, $pola, $barisBaru, $keterangan) {
    $isi = Get-Content $jalur -Raw

    if ($isi -match "google-services") {
        Write-Host "   SUDAH ADA - tidak diubah: $keterangan" -ForegroundColor Green
        return $true
    }

    $baris = Get-Content $jalur
    $hasil = New-Object System.Collections.Generic.List[string]
    $disisipkan = $false

    foreach ($satu in $baris) {
        $hasil.Add($satu)

        if (-not $disisipkan -and $satu -match $pola) {
            foreach ($tambahan in $barisBaru) { $hasil.Add($tambahan) }
            $disisipkan = $true
        }
    }

    if (-not $disisipkan) {
        Write-Host "   GAGAL menyisipkan: $keterangan" -ForegroundColor Red
        Write-Host "   Kirimkan isi berkas berikut ke saya:" -ForegroundColor Yellow
        Write-Host "   $jalur" -ForegroundColor Yellow
        return $false
    }

    Simpan-TanpaBom $jalur ($hasil -join "`r`n")
    Write-Host "   DISISIPKAN pada: $keterangan" -ForegroundColor Green
    return $true
}

# --- 0. Persiapkan -------------------------------------------------------------
if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

TulisJudul "0. Persiapan"
Write-Host "   Folder proyek : $proyek"

# --- 1. Berkas google-services.json -------------------------------------------
TulisJudul "1. Memeriksa android\app\google-services.json"

$jalurGoogle = "android\app\google-services.json"

if (-not (Test-Path $jalurGoogle)) {
    Write-Host ""
    Write-Host "   BERKAS BELUM ADA." -ForegroundColor Red
    Write-Host ""
    Write-Host "   Cara mendapatkannya:" -ForegroundColor Yellow
    Write-Host "     a. Buka console.firebase.google.com"
    Write-Host "     b. Buat proyek, lalu tambahkan aplikasi Android"
    Write-Host "     c. Isi nama paket: $paketAplikasi"
    Write-Host "     d. Unduh google-services.json"
    Write-Host "     e. Letakkan di folder: android\app\"
    Write-Host ""
    Write-Host "   Setelah berkas itu ada, jalankan lagi skrip ini." -ForegroundColor Yellow
    exit 1
}

$ukuran = [math]::Round((Get-Item $jalurGoogle).Length / 1KB, 1)
Write-Host "   Ditemukan: $jalurGoogle ($ukuran KB)" -ForegroundColor Green

# Memeriksa nama paket di dalam berkas tersebut.
try {
    $isiGoogle = Get-Content $jalurGoogle -Raw | ConvertFrom-Json
    $paketJson = $isiGoogle.client[0].client_info.android_client_info.package_name
    $idProyek = $isiGoogle.project_info.project_id

    Write-Host "   Nama paket pada berkas : $paketJson"
    Write-Host "   Proyek Firebase        : $idProyek"

    if ($paketJson -ne $paketAplikasi) {
        Write-Host ""
        Write-Host "   PERINGATAN: nama paket TIDAK COCOK." -ForegroundColor Red
        Write-Host "   Seharusnya : $paketAplikasi" -ForegroundColor Yellow
        Write-Host "   Di berkas  : $paketJson" -ForegroundColor Yellow
        Write-Host "   Hapus aplikasi di Firebase Console, lalu tambahkan lagi" -ForegroundColor Yellow
        Write-Host "   dengan nama paket yang benar dan unduh ulang berkasnya." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "   Nama paket COCOK." -ForegroundColor Green
}
catch {
    Write-Host "   Berkas google-services.json tidak dapat dibaca sebagai JSON." -ForegroundColor Red
    Write-Host "   Unduh ulang berkasnya dari Firebase Console." -ForegroundColor Yellow
    exit 1
}

# --- 2. Cadangkan berkas asli --------------------------------------------------
TulisJudul "2. Mencadangkan berkas Gradle asli"

foreach ($jalur in @("android\settings.gradle.kts", "android\app\build.gradle.kts")) {
    if (Test-Path $jalur) {
        $cadangan = "$jalur.lama"

        if (-not (Test-Path $cadangan)) {
            Copy-Item $jalur $cadangan
            Write-Host "   dicadangkan: $cadangan"
        } else {
            Write-Host "   cadangan sudah ada: $cadangan"
        }
    } else {
        Write-Host "   tidak ditemukan: $jalur" -ForegroundColor Yellow
    }
}

# --- 3. settings.gradle.kts ----------------------------------------------------
TulisJudul "3. Menyisipkan plugin pada android\settings.gradle.kts"

$jalurSettings = "android\settings.gradle.kts"

if (Test-Path $jalurSettings) {
    $ok = Sisipkan-Setelah $jalurSettings `
        'id\("dev\.flutter\.flutter-plugin-loader"\)' `
        @(
            '    // START: FlutterFire Configuration',
            '    id("com.google.gms.google-services") version "4.5.0" apply false',
            '    // END: FlutterFire Configuration'
        ) `
        "settings.gradle.kts"

    if (-not $ok) { exit 1 }
} else {
    Write-Host "   Berkas tidak ditemukan. Kirimkan isi folder android ke saya." -ForegroundColor Red
    exit 1
}

# --- 4. app\build.gradle.kts ---------------------------------------------------
TulisJudul "4. Memeriksa plugin pada android\app\build.gradle.kts"

$jalurApp = "android\app\build.gradle.kts"

if (Test-Path $jalurApp) {
    $ok = Sisipkan-Setelah $jalurApp `
        'id\("com\.android\.application"\)' `
        @(
            '    // START: FlutterFire Configuration',
            '    id("com.google.gms.google-services")',
            '    // END: FlutterFire Configuration'
        ) `
        "app\build.gradle.kts"
} else {
    Write-Host "   Berkas tidak ditemukan." -ForegroundColor Red
    exit 1
}

# --- 5. Pub get ----------------------------------------------------------------
TulisJudul "5. Mengambil paket Firebase (flutter pub get)"
flutter pub get

# --- 6. Pemeriksaan hasil ------------------------------------------------------
TulisJudul "6. Pemeriksaan hasil"

$isiSettings = Get-Content $jalurSettings -Raw
$isiApp = Get-Content $jalurApp -Raw

if ($isiSettings -match "google-services") {
    Write-Host "   settings.gradle.kts  : plugin google-services ADA" -ForegroundColor Green
} else {
    Write-Host "   settings.gradle.kts  : plugin google-services BELUM ADA" -ForegroundColor Red
}

if ($isiApp -match "com\.google\.gms\.google-services") {
    Write-Host "   app\build.gradle.kts : plugin google-services ADA" -ForegroundColor Green
} else {
    Write-Host "   app\build.gradle.kts : plugin google-services BELUM ADA" -ForegroundColor Red
}

if (Test-Path ".flutter-plugins-dependencies") {
    $isiPlugin = Get-Content ".flutter-plugins-dependencies" -Raw

    if ($isiPlugin -match "firebase_messaging") {
        Write-Host "   firebase_messaging   : terdaftar" -ForegroundColor Green
    } else {
        Write-Host "   firebase_messaging   : belum terdaftar (pastikan pubspec.yaml sudah diganti)" -ForegroundColor Yellow
    }
}

# --- 7. Langkah berikutnya -----------------------------------------------------
TulisJudul "7. Langkah berikutnya"
Write-Host "   1. Pastikan pubspec.yaml sudah memakai versi terbaru"
Write-Host "      (berisi firebase_core dan firebase_messaging)."
Write-Host "   2. Bangun dan pasang ke HP:"
Write-Host ""
Write-Host "        flutter run" -ForegroundColor Cyan
Write-Host ""
Write-Host "   3. Setelah aplikasi terbuka, buka Pengaturan di aplikasi dan lihat"
Write-Host "      kartu Pemberitahuan HP - akan ada keterangan status Firebase."
Write-Host ""
Write-Host "   Bila build gagal, salin 20 baris pertama yang berwarna merah" -ForegroundColor Yellow
Write-Host "   dan kirimkan ke saya." -ForegroundColor Yellow
