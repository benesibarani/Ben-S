# =============================================================================
#  RTS PANEL BY BENE - PERBAIKI BERKAS GRADLE ROOT LALU BUILD
#  Berkas: PERBAIKI_ROOT_GRADLE.ps1
#
#  PENYEBAB YANG DIPERBAIKI:
#
#     Berkas android\build.gradle.kts (ROOT) ternyata berisi isi berkas
#     android\app\build.gradle.kts. Akibatnya plugin Flutter terpasang DUA KALI
#     dan muncul pesan:
#
#        Cannot add task 'generateLockfiles' as a task with that name already
#        exists
#
#  YANG DIKERJAKAN SKRIP INI:
#
#     1. Mencadangkan berkas Gradle yang sekarang (tidak ada yang dihapus)
#     2. Menulis ulang android\build.gradle.kts (ROOT) memakai template
#        BAWAAN FLUTTER SDK yang ada di komputer Bapak
#     3. Menulis ulang android\app\build.gradle.kts dengan versi yang benar
#     4. Memastikan android\settings.gradle.kts memuat plugin google-services
#     5. Memindahkan berkas sisa (build.gradle - Copy.kts, *.lama) ke folder
#        cadangan agar tidak mengganggu
#     6. MEMERIKSA hasil perbaikan; bila masih ada penggandaan, skrip BERHENTI
#        (tidak membuang waktu build)
#     7. Membersihkan hasil build lama lalu menjalankan flutter run
#
#  CARA PAKAI:
#     1. Simpan di folder proyek: D:\Project\rts_panel_app
#     2. Sambungkan HP memakai KABEL USB
#     3. Terminal VS Code:
#          powershell -ExecutionPolicy Bypass -File .\PERBAIKI_ROOT_GRADLE.ps1
#
#  Untuk memperbaiki SAJA tanpa build:
#          powershell -ExecutionPolicy Bypass -File .\PERBAIKI_ROOT_GRADLE.ps1 -TanpaBuild
# =============================================================================

param(
    [switch]$TanpaBuild
)

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

$jalurRoot     = "android\build.gradle.kts"
$jalurApp      = "android\app\build.gradle.kts"
$jalurSettings = "android\settings.gradle.kts"

# -----------------------------------------------------------------------------
# 1. Cadangkan berkas sekarang
# -----------------------------------------------------------------------------
TulisJudul "1. Mencadangkan berkas Gradle yang sekarang"

$folderCadangan = "android\cadangan_arena"
if (-not (Test-Path $folderCadangan)) {
    New-Item -ItemType Directory -Path $folderCadangan | Out-Null
}

if (Test-Path $jalurRoot) {
    Copy-Item $jalurRoot (Join-Path $folderCadangan "build.gradle.kts.asli") -Force
    Write-Host "   dicadangkan: build.gradle.kts (root)"
}

if (Test-Path $jalurApp) {
    Copy-Item $jalurApp (Join-Path $folderCadangan "app-build.gradle.kts.asli") -Force
    Write-Host "   dicadangkan: app\build.gradle.kts"
}

# -----------------------------------------------------------------------------
# 2. Ambil template ROOT dari Flutter SDK Bapak sendiri
# -----------------------------------------------------------------------------
TulisJudul "2. Mencari template Gradle bawaan Flutter SDK"

$isiApp = @'
plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.rts_panel_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // TAMBAHAN: diperlukan paket pemberitahuan HP (flutter_local_notifications
        // dan firebase_messaging)
        isCoreLibraryDesugaringEnabled = true

        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.rts_panel_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        //
        // TAMBAHAN FIREBASE: layanan Google mensyaratkan Android 6.0 (level 23)
        // atau lebih baru. maxOf() memakai nilai bawaan Flutter bila lebih tinggi.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // TAMBAHAN: diperlukan paket pemberitahuan HP, geolocator, dan Firebase
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// TAMBAHAN: pustaka Java yang dipakai paket pemberitahuan HP dan Firebase.
// Blok ini harus berada di bagian paling bawah berkas.
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
'@

# Template cadangan (dipakai hanya bila template SDK tidak ditemukan).
$isiRootCadangan = @'
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
'@

$isiRoot = $null
$asalTemplate = ""

# Baca flutter.sdk dari android\local.properties
$sdkFlutter = ""
if (Test-Path "android\local.properties") {
    foreach ($satu in (Get-Content "android\local.properties")) {
        if ($satu -match "^\s*flutter\.sdk\s*=\s*(.+)$") {
            $sdkFlutter = $Matches[1].Trim().Replace("\\", "\").Replace("\\:", ":")
        }
    }
}

Write-Host "   Flutter SDK : $sdkFlutter"

if ($sdkFlutter -ne "" -and (Test-Path $sdkFlutter)) {
    $dasarTemplate = Join-Path $sdkFlutter "packages\flutter_tools\templates"

    if (Test-Path $dasarTemplate) {
        $semua = Get-ChildItem -Path $dasarTemplate -Recurse -Filter "build.gradle.kts.tmpl" -File -ErrorAction SilentlyContinue

        $pilihan = $semua | Where-Object { $_.FullName -match "app_shared" -and $_.DirectoryName -match "android\.tmpl$" } |
            Select-Object -First 1

        if (-not $pilihan) {
            $pilihan = $semua | Where-Object { $_.DirectoryName -match "android\.tmpl$" } | Select-Object -First 1
        }

        if (-not $pilihan) {
            $pilihan = $semua | Select-Object -First 1
        }

        if ($pilihan) {
            $kandidat = Get-Content $pilihan.FullName -Raw

            # Template ROOT tidak boleh memuat plugin aplikasi.
            if ($kandidat -notmatch "flutter-gradle-plugin" -and $kandidat -notmatch "\{\{") {
                $isiRoot = $kandidat
                $asalTemplate = $pilihan.FullName
                Write-Host "   Template ditemukan: $asalTemplate" -ForegroundColor Green
            }
            else {
                Write-Host "   Template SDK kurang cocok - memakai template cadangan." -ForegroundColor Yellow
            }
        }
    }
}

if (-not $isiRoot) {
    $isiRoot = $isiRootCadangan
    $asalTemplate = "template cadangan di dalam skrip ini"
    Write-Host "   Memakai template cadangan." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 3. Tulis ulang berkas ROOT dan APP
# -----------------------------------------------------------------------------
TulisJudul "3. Menulis ulang berkas Gradle"

Simpan-TanpaBom $jalurRoot ($isiRoot.TrimEnd() + "`r`n")
Write-Host "   ditulis: android\build.gradle.kts (isi: $asalTemplate)"

Simpan-TanpaBom $jalurApp ($isiApp.TrimEnd() + "`r`n")
Write-Host "   ditulis: android\app\build.gradle.kts (versi aplikasi + Firebase)"

# -----------------------------------------------------------------------------
# 4. Pastikan settings.gradle.kts memuat plugin google-services
# -----------------------------------------------------------------------------
TulisJudul "4. Memeriksa android\settings.gradle.kts"

if (Test-Path $jalurSettings) {
    $isiSettings = Get-Content $jalurSettings -Raw

    if ($isiSettings -notmatch "google-services") {
        $baris = Get-Content $jalurSettings
        $hasil = New-Object System.Collections.Generic.List[string]
        $disisipkan = $false

        foreach ($satu in $baris) {
            $hasil.Add($satu)

            if (-not $disisipkan -and $satu -match "dev\.flutter\.flutter-plugin-loader") {
                $hasil.Add('    // START: FlutterFire Configuration')
                $hasil.Add('    id("com.google.gms.google-services") version "4.5.0" apply false')
                $hasil.Add('    // END: FlutterFire Configuration')
                $disisipkan = $true
            }
        }

        if ($disisipkan) {
            Simpan-TanpaBom $jalurSettings ($hasil -join "`r`n")
            Write-Host "   DISISIPKAN plugin google-services 4.5.0." -ForegroundColor Green
        }
        else {
            Write-Host "   GAGAL menyisipkan. Kirim isi settings.gradle.kts ke saya." -ForegroundColor Red
        }
    }
    else {
        Write-Host "   Plugin google-services sudah ada." -ForegroundColor Green
    }
}
else {
    Write-Host "   BERKAS TIDAK ADA - kirim kabar ke saya." -ForegroundColor Red
}

# -----------------------------------------------------------------------------
# 5. Pindahkan berkas sisa
# -----------------------------------------------------------------------------
TulisJudul "5. Memindahkan berkas sisa"

$sisa = @(
    "android\app\build.gradle - Copy.kts",
    "android\app\build.gradle.kts.lama",
    "android\settings.gradle.kts.lama"
)

foreach ($satu in $sisa) {
    if (Test-Path $satu) {
        $namaTujuan = Join-Path $folderCadangan ([System.IO.Path]::GetFileName($satu).Replace(" ", "_"))
        Move-Item $satu $namaTujuan -Force
        Write-Host "   dipindahkan: $satu"
    }
}

# -----------------------------------------------------------------------------
# 6. PERIKSA HASIL - berhenti bila masih ada penggandaan
# -----------------------------------------------------------------------------
TulisJudul "6. Memeriksa hasil perbaikan"

$bermasalah = 0

$isiRootBaru = Get-Content $jalurRoot -Raw
$isiAppBaru  = Get-Content $jalurApp -Raw

# ROOT tidak boleh memuat plugin aplikasi Flutter.
if ($isiRootBaru -match "flutter-gradle-plugin") {
    TulisHasil $false "android\build.gradle.kts MASIH memuat 'flutter-gradle-plugin'"
    $bermasalah++
} else {
    TulisHasil $true "android\build.gradle.kts tidak memuat plugin aplikasi"
}

if ($isiRootBaru -match "id\(""com\.android\.application""\)") {
    TulisHasil $false "android\build.gradle.kts MASIH memuat 'com.android.application'"
    $bermasalah++
} else {
    TulisHasil $true "android\build.gradle.kts tidak memuat 'com.android.application'"
}

# APP harus memuat tepat satu plugin Flutter dan satu google-services.
$jumlahPluginFlutter = ([regex]::Matches($isiAppBaru, "flutter-gradle-plugin")).Count
$jumlahGoogleServices = ([regex]::Matches($isiAppBaru, "google-services")).Count

TulisHasil ($jumlahPluginFlutter -eq 1) "app flutter-gradle-plugin: $jumlahPluginFlutter kemunculan (harus 1)"
TulisHasil ($jumlahGoogleServices -ge 1) "app google-services: $jumlahGoogleServices kemunculan (harus minimal 1)"

if ($jumlahPluginFlutter -ne 1) { $bermasalah++ }

# Berkas sisa harus sudah tidak ada di tempat semula.
foreach ($satu in $sisa) {
    if (Test-Path $satu) {
        TulisHasil $false "berkas sisa masih ada: $satu"
        $bermasalah++
    }
}

TulisHasil (Test-Path "android\app\google-services.json") "android\app\google-services.json ada"

Write-Host ""
if ($bermasalah -gt 0) {
    Write-Host "   ADA $bermasalah MASALAH - build tidak dijalankan." -ForegroundColor Red
    Write-Host "   Kirimkan seluruh keluaran ini ke saya." -ForegroundColor Yellow
    exit 1
}

Write-Host "   Semua pemeriksaan LOLOS." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. Bersihkan dan build
# -----------------------------------------------------------------------------
TulisJudul "7. Membersihkan hasil build lama"

foreach ($jalur in @("build", ".dart_tool", "android\.gradle", "android\app\build")) {
    if (Test-Path $jalur) {
        Remove-Item -Recurse -Force $jalur -ErrorAction SilentlyContinue
        Write-Host "   dihapus : $jalur"
    }
}

flutter clean
flutter pub get

Push-Location "android"
if (Test-Path "gradlew.bat") { .\gradlew.bat --stop }
Pop-Location

if ($TanpaBuild) {
    TulisJudul "Selesai (tanpa build)"
    Write-Host "Perbaikan selesai. Untuk membangun, jalankan:" -ForegroundColor Green
    Write-Host "    flutter run" -ForegroundColor Cyan
    exit 0
}

TulisJudul "8. Membangun dan menjalankan aplikasi"
Write-Host "   Build pertama dengan Firebase memakan 10-15 menit." -ForegroundColor Yellow
Write-Host "   Jangan ditutup. Silakan tinggalkan sebentar." -ForegroundColor Yellow
Write-Host ""

$keluaran = flutter devices
$keluaran

# Memilih perangkat KABEL saja.
# Daftar nirkabel memakai id yang memuat "_adb-tls-connect"; id itu dilewati
# supaya tidak tertukar lagi seperti percobaan sebelumnya.
$perangkat = @()

$mesin = (flutter devices --machine) -join "`n"
try {
    $daftar = ConvertFrom-Json $mesin
    if ($daftar -isnot [array]) { $daftar = @($daftar) }
    foreach ($satu in $daftar) {
        if ($satu.targetPlatform -match "^android" -and $satu.id -notmatch "_adb-tls-connect") {
            $perangkat += $satu.id
        }
    }
}
catch {
    Write-Host "   (daftar mesin tidak terbaca - memakai cara sederhana)" -ForegroundColor DarkGray
    foreach ($baris in $keluaran) {
        if ($baris -match "adb-\S+" -and $baris -notmatch "_adb-tls-connect") {
            $perangkat += $Matches[0]
        }
    }
}

if ($perangkat.Count -ge 1) {
    Write-Host "   Perangkat kabel dipakai: $($perangkat[0])" -ForegroundColor Green
    flutter run -d $perangkat[0]
}
else {
    Write-Host "   Tidak ada perangkat kabel terbaca - memakai daftar bawaan." -ForegroundColor Yellow
    flutter run
}

TulisJudul "Selesai"
Write-Host "Bila masih gagal, salin 20 baris pertama yang berwarna merah." -ForegroundColor Green
