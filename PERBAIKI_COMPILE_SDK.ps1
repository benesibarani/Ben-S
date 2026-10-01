# =============================================================================
#  RTS PANEL BY BENE - PERBAIKI COMPILE SDK (SATU KALI JALAN)
#  Berkas : PERBAIKI_COMPILE_SDK.ps1
#
#  KENAPA SKRIP INI DIPERLUKAN?
#  ---------------------------
#  Saat membangun aplikasi, Flutter menampilkan pesan:
#
#      Your project is configured to compile against Android SDK 36, but the
#      following plugin(s) require to be compiled against a higher Android
#      SDK version:  - permission_handler_android compiles against Android SDK 37
#      Fix this issue by compiling against the highest Android SDK version
#      ... -> compileSdk = 37
#
#  Artinya: paket izin (permission_handler) sekarang dibangun memakai
#  Android SDK 37, sedangkan proyek Bapak masih 36. Angka yang lebih tinggi
#  SELALU dapat dipakai untuk yang lebih rendah (sifatnya mundur-kompatibel),
#  jadi penyelesaiannya cukup SATU BARIS: compileSdk diubah menjadi 37.
#
#  APA YANG DIKERJAKAN SKRIP INI
#  ----------------------------
#     1. Mencari berkas android\app\build.gradle.kts (atau build.gradle)
#     2. Mencadangkan berkas itu lebih dahulu
#        (nama tambahan .lama_tanggal_jam)
#     3. Mengubah angka compileSdk menjadi 37
#     4. Menampilkan baris hasilnya supaya Bapak dapat memeriksa
#
#  Skrip ini TIDAK menghapus apa pun dan TIDAK mengubah bagian lain.
#
#  CARA PAKAI
#  ----------
#     1. Simpan berkas ini di folder proyek: D:\Project\rts_panel_app
#        (satu folder dengan pubspec.yaml)
#     2. Buka Terminal di VS Code, lalu ketik:
#            powershell -ExecutionPolicy Bypass -File .\PERBAIKI_COMPILE_SDK.ps1
#     3. Setelah selesai, jalankan:
#            flutter clean
#            flutter pub get
#            flutter run -d CPH1937
#
#  BILA ANDROID SDK 37 BELUM ADA DI KOMPUTER
#  -----------------------------------------
#  Android Studio akan mengunduhnya sendiri saat membangun. Bila muncul pesan
#  "Failed to find target with hash string 'android-37'", buka Android Studio:
#     More Actions (atau ikon gerigi) - SDK Manager - tab SDK Platforms -
#     centang "Android API 37" - Apply - tunggu selesai - jalankan ulang.
# =============================================================================

param(
    [string]$Proyek = 'D:\Project\rts_panel_app'
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '====================================================================' -ForegroundColor Cyan
Write-Host ' RTS PANEL BY BENE - PERBAIKI COMPILE SDK MENJADI 37' -ForegroundColor Cyan
Write-Host '====================================================================' -ForegroundColor Cyan
Write-Host ''

# -----------------------------------------------------------------------------
# 1. Menemukan folder proyek
# -----------------------------------------------------------------------------

if (-not (Test-Path $Proyek)) {
    $kandidat = @($Proyek, (Join-Path $env:USERPROFILE 'rts_panel_app'), (Get-Location).Path)

    $Proyek = ''

    foreach ($k in $kandidat) {
        if ((Test-Path $k) -and (Test-Path (Join-Path $k 'pubspec.yaml'))) {
            $Proyek = $k
            break
        }
    }

    if ([string]::IsNullOrWhiteSpace($Proyek)) {
        Write-Host ' Folder proyek tidak ditemukan.' -ForegroundColor Red
        Write-Host ' Buka skrip ini di dalam folder proyek, atau jalankan:' -ForegroundColor Yellow
        Write-Host '     .\PERBAIKI_COMPILE_SDK.ps1 -Proyek "D:\Project\rts_panel_app"' -ForegroundColor White
        exit 1
    }
}

Write-Host " Folder proyek : $Proyek" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Menemukan berkas Gradle tingkat aplikasi
# -----------------------------------------------------------------------------

$kts = Join-Path $Proyek 'android\app\build.gradle.kts'
$groovy = Join-Path $Proyek 'android\app\build.gradle'

if (Test-Path $kts) {
    $berkas = $kts
} elseif (Test-Path $groovy) {
    $berkas = $groovy
} else {
    Write-Host ' Berkas android\app\build.gradle.kts tidak ditemukan.' -ForegroundColor Red
    Write-Host ' Pastikan folder proyek sudah benar (berisi pubspec.yaml).' -ForegroundColor Yellow
    exit 1
}

Write-Host " Berkas Gradle : $berkas" -ForegroundColor Green
Write-Host ''

# -----------------------------------------------------------------------------
# 3. Mencadangkan berkas lama
# -----------------------------------------------------------------------------

$cap = "$berkas.lama_" + (Get-Date).ToString('yyyyMMdd_HHmmss')

Copy-Item -Path $berkas -Destination $cap -Force

Write-Host " Cadangan dibuat : $cap" -ForegroundColor Green
Write-Host ''

# -----------------------------------------------------------------------------
# 4. Mengubah angka compileSdk menjadi 37
# -----------------------------------------------------------------------------

$isi = [System.IO.File]::ReadAllText($berkas)
$lama = $isi
$ditemukan = ''

# Susunan yang mungkin ada di berkas Bapak (diperiksa satu per satu).
$daftarGanti = @(
    @{ Cari = 'compileSdk\s*=\s*flutter\.compileSdkVersion'; Ganti = 'compileSdk = 37'; Nama = 'compileSdk = flutter.compileSdkVersion (.kts)' },
    @{ Cari = 'compileSdkVersion\s+flutter\.compileSdkVersion'; Ganti = 'compileSdkVersion 37';   Nama = 'compileSdkVersion flutter.compileSdkVersion (.gradle)' },
    @{ Cari = 'compileSdk\s*=\s*3[0-9]';                        Ganti = 'compileSdk = 37';       Nama = 'compileSdk = <angka> (.kts)' },
    @{ Cari = 'compileSdkVersion\s+3[0-9]';                     Ganti = 'compileSdkVersion 37';  Nama = 'compileSdkVersion <angka> (.gradle)' }
)

foreach ($d in $daftarGanti) {
    $baru = [regex]::Replace($isi, $d.Cari, $d.Ganti)

    if ($baru -ne $isi) {
        $isi = $baru
        $ditemukan = $d.Nama
        break
    }
}

if ([string]::IsNullOrWhiteSpace($ditemukan)) {
    # Belum ada baris compileSdk: disisipkan tepat sesudah baris "android {".
    # (dipakai objek Regex supaya hanya SATU bagian pertama yang diganti)
    $pola = New-Object System.Text.RegularExpressions.Regex('android\s*\{')
    $baru = $pola.Replace($isi, "android {`r`n    compileSdk = 37", 1)

    if ($baru -ne $isi) {
        $isi = $baru
        $ditemukan = 'baris compileSdk = 37 disisipkan sesudah "android {"'
    }
}

if ([string]::IsNullOrWhiteSpace($ditemukan)) {
    Write-Host ' Bagian "android {" tidak ditemukan di dalam berkas itu.' -ForegroundColor Red
    Write-Host ' Kirimkan berkas berikut ke chat supaya saya perbaiki:' -ForegroundColor Yellow
    Write-Host "     $berkas" -ForegroundColor White
    exit 1
}

# Disimpan tanpa BOM supaya Gradle tidak mengeluh.
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($berkas, $isi, $utf8)

Write-Host " Perubahan : $ditemukan" -ForegroundColor Green
Write-Host ''

# -----------------------------------------------------------------------------
# 5. Menampilkan hasil supaya dapat diperiksa
# -----------------------------------------------------------------------------

Write-Host ' ------- BARIS PENTING SESUDAH DIPERBAIKI -------' -ForegroundColor Cyan

Get-Content $berkas | Select-String -Pattern 'compileSdk|namespace|applicationId|targetSdk' |
    ForEach-Object {
        Write-Host ('   ' + $_.Line.Trim()) -ForegroundColor White
    }

Write-Host ''
Write-Host '====================================================================' -ForegroundColor Cyan
Write-Host ' SELESAI. Langkah berikutnya, ketik berturut-turut:' -ForegroundColor Cyan
Write-Host '====================================================================' -ForegroundColor Cyan
Write-Host '     flutter clean' -ForegroundColor White
Write-Host '     flutter pub get' -ForegroundColor White
Write-Host '     flutter run -d CPH1937' -ForegroundColor White
Write-Host ''
Write-Host ' Bila muncul "Failed to find target with hash string android-37",' -ForegroundColor Yellow
Write-Host ' buka Android Studio - SDK Manager - SDK Platforms - centang' -ForegroundColor Yellow
Write-Host ' "Android API 37" - Apply, lalu jalankan ulang perintah di atas.' -ForegroundColor Yellow
Write-Host ''
Write-Host ' Catatan: SKRIP INI CUKUP DIJALANKAN SEKALI.' -ForegroundColor Green
Write-Host ' Berkas lama tetap ada (berakhiran .lama_tanggal_jam) bila ingin' -ForegroundColor Green
Write-Host ' dikembalikan seperti semula.' -ForegroundColor Green
Write-Host ''
