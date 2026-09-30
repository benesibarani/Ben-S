# =============================================================================
#  RTS PANEL BY BENE - BERSIHKAN BUILD LALU JALANKAN DI HP
#  Berkas: PERBAIKI_DAN_JALANKAN.ps1
#
#  Berkas ini melanjutkan PANDUAN bagian 25 huruf I, tetapi dikerjakan otomatis
#  supaya tidak perlu mengetik satu per satu.
#
#  CARA PAKAI:
#    1. Simpan berkas ini di folder proyek:  D:\Project\rts_panel_app
#       (buat berkas baru di VS Code dengan nama PERBAIKI_DAN_JALANKAN.ps1,
#        lalu tempelkan seluruh isi berkas ini)
#    2. Buka terminal di VS Code (menu Terminal > New Terminal)
#    3. Ketik:
#         powershell -ExecutionPolicy Bypass -File .\PERBAIKI_DAN_JALANKAN.ps1
#
#  AMAN: skrip ini hanya menghapus berkas sementara (build, cache, .dart_tool,
#  android\.gradle, dan folder plugins hasil generate). Kode program tidak
#  diubah dan tidak dihapus.
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

# --- 0. Persiapkan ------------------------------------------------------------
if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    Write-Host "Periksa kembali letak folder proyek Bapak." -ForegroundColor Red
    exit 1
}

Set-Location $proyek

TulisJudul "0. Informasi singkat"
Write-Host "   Folder proyek : $proyek"
Write-Host "   PUB_CACHE     : $env:PUB_CACHE"
Write-Host "   (bila kosong, paket Flutter memakai folder bawaan di C:)"

# --- 1. Lepaskan paket workmanager --------------------------------------------
TulisJudul "1. Memeriksa paket workmanager di pubspec.yaml"

if ((Get-Content "pubspec.yaml" -Raw) -match "workmanager") {
    Write-Host "   workmanager masih terdaftar - sedang dilepas..." -ForegroundColor Yellow
    flutter pub remove workmanager
} else {
    Write-Host "   pubspec.yaml sudah bersih dari workmanager." -ForegroundColor Green
}

# --- 2. Periksa sisa nama paket di berkas lain --------------------------------
TulisJudul "2. Memeriksa sisa nama workmanager di berkas lain"

$cek = @("pubspec.yaml", "pubspec.lock", ".flutter-plugins-dependencies")
$sisa = Select-String -Path $cek -Pattern "workmanager" -SimpleMatch -ErrorAction SilentlyContinue

if ($sisa) {
    Write-Host "   MASIH DITEMUKAN (inilah penyebab error WorkmanagerPlugin):" -ForegroundColor Yellow
    $sisa | ForEach-Object { Write-Host ("   - " + $_.Filename + " baris " + $_.LineNumber) }
} else {
    Write-Host "   Bersih - tidak ada sisa workmanager." -ForegroundColor Green
}

# --- 3. Hapus berkas sementara -------------------------------------------------
TulisJudul "3. Menghapus berkas sementara"

foreach ($jalur in @("build", ".dart_tool", "android\.gradle", "android\app\src\main\java\io\flutter\plugins")) {
    if (Test-Path $jalur) {
        Remove-Item -Recurse -Force $jalur -ErrorAction SilentlyContinue
        Write-Host "   dihapus : $jalur"
    } else {
        Write-Host "   (tidak ada): $jalur"
    }
}

# --- 4. Ambil paket ulang ------------------------------------------------------
TulisJudul "4. flutter pub get"
flutter pub get

# --- 5. Bersihkan build Flutter ------------------------------------------------
TulisJudul "5. flutter clean"
flutter clean

TulisJudul "5b. flutter pub get (setelah clean)"
flutter pub get

# --- 6. Hentikan proses Gradle yang masih hidup --------------------------------
TulisJudul "6. Menghentikan Gradle"
Push-Location "android"
if (Test-Path "gradlew.bat") {
    .\gradlew.bat --stop
} else {
    Write-Host "   gradlew.bat tidak ditemukan di folder android." -ForegroundColor Yellow
}
Pop-Location

# --- 7. Jalankan di HP ---------------------------------------------------------
TulisJudul "7. Daftar perangkat yang terhubung"
flutter devices

TulisJudul "8. Menjalankan aplikasi di HP CPH1937"
Write-Host "   Proses pertama bisa memakan waktu 3-10 menit. Jangan ditutup." -ForegroundColor Yellow
flutter run -d CPH1937

# --- 8. Penutup -----------------------------------------------------------------
TulisJudul "Selesai"
Write-Host "Bila masih muncul error, salin 20 baris pertama yang berwarna merah" -ForegroundColor Green
Write-Host "lalu kirimkan ke saya." -ForegroundColor Green
