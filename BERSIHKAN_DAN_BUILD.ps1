# =============================================================================
#  RTS PANEL BY BENE - BERSIHKAN GRADLE LALU BANGUN ULANG
#  Berkas: BERSIHKAN_DAN_BUILD.ps1
#
#  Dipakai setelah pengaturan Gradle diperbaiki (android.newDsl=false dan
#  android.builtInKotlin=false pada android\gradle.properties).
#
#  Skrip ini:
#    1. Memeriksa pengaturan penting pada gradle.properties
#    2. Memeriksa plugin google-services pada berkas Gradle
#    3. Membersihkan hasil build lama
#    4. Menghentikan Gradle yang masih hidup
#    5. Membangun dan menjalankan aplikasi di HP
#
#  CARA PAKAI:
#    1. Simpan di folder proyek: D:\Project\rts_panel_app
#    2. Sambungkan HP memakai KABEL USB (lebih stabil daripada nirkabel)
#    3. Terminal VS Code:
#         powershell -ExecutionPolicy Bypass -File .\BERSIHKAN_DAN_BUILD.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

function TulisHasil($ok, $teks) {
    if ($ok) {
        Write-Host "   OK      : $teks" -ForegroundColor Green
    } else {
        Write-Host "   PERIKSA : $teks" -ForegroundColor Yellow
    }
}

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

# --- 1. Periksa gradle.properties ---------------------------------------------
TulisJudul "1. Memeriksa android\gradle.properties"

$jalurProp = "android\gradle.properties"

if (-not (Test-Path $jalurProp)) {
    Write-Host "   Berkas tidak ditemukan!" -ForegroundColor Red
    Write-Host "   Salin gradle.properties.updated ke android\gradle.properties" -ForegroundColor Yellow
    exit 1
}

$isiProp = Get-Content $jalurProp -Raw

$adaNewDsl = $isiProp -match "android\.newDsl\s*=\s*false"
$adaBuiltIn = $isiProp -match "android\.builtInKotlin\s*=\s*false"

TulisHasil $adaNewDsl "android.newDsl=false"
TulisHasil $adaBuiltIn "android.builtInKotlin=false"

if (-not $adaNewDsl -or -not $adaBuiltIn) {
    Write-Host ""
    Write-Host "   DUA BARIS ITU BELUM ADA - inilah penyebab build gagal." -ForegroundColor Red
    Write-Host "   Ganti SELURUH isi android\gradle.properties dengan isi" -ForegroundColor Yellow
    Write-Host "   berkas gradle.properties.updated, lalu jalankan skrip ini lagi." -ForegroundColor Yellow
    exit 1
}

# --- 2. Periksa jalur selain yang diharapkan ----------------------------------
TulisJudul "2. Memeriksa android.enableJetifier"

if ($isiProp -match "android\.enableJetifier\s*=\s*true") {
    Write-Host "   android.enableJetifier=true masih dipakai." -ForegroundColor Yellow
    Write-Host "   Bila build masih gagal karena Jetifier, hapus baris itu."
} else {
    Write-Host "   Tidak dipakai (aman)." -ForegroundColor Green
}

# --- 3. Periksa plugin google-services ----------------------------------------
TulisJudul "3. Memeriksa plugin google-services"

$jalurSettings = "android\settings.gradle.kts"
$jalurApp = "android\app\build.gradle.kts"

if (Test-Path $jalurSettings) {
    $isiSettings = Get-Content $jalurSettings -Raw
    TulisHasil ($isiSettings -match "com\.google\.gms\.google-services") "settings.gradle.kts"
} else {
    TulisHasil $false "android\settings.gradle.kts tidak ditemukan"
}

if (Test-Path $jalurApp) {
    $isiApp = Get-Content $jalurApp -Raw
    TulisHasil ($isiApp -match "com\.google\.gms\.google-services") "app\build.gradle.kts"
} else {
    TulisHasil $false "android\app\build.gradle.kts tidak ditemukan"
}

# --- 4. Periksa google-services.json ------------------------------------------
TulisJudul "4. Memeriksa android\app\google-services.json"

$jalurGoogle = "android\app\google-services.json"

if (Test-Path $jalurGoogle) {
    try {
        $isiGoogle = Get-Content $jalurGoogle -Raw | ConvertFrom-Json
        $paketJson = $isiGoogle.client[0].client_info.android_client_info.package_name
        Write-Host "   Nama paket di berkas : $paketJson"

        if ($paketJson -eq "com.example.rts_panel_app") {
            Write-Host "   COCOK dengan aplikasi." -ForegroundColor Green
        } else {
            Write-Host "   TIDAK COCOK - seharusnya com.example.rts_panel_app" -ForegroundColor Red
            exit 1
        }
    }
    catch {
        Write-Host "   Berkas tidak dapat dibaca. Unduh ulang dari Firebase Console." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "   BELUM ADA. Letakkan di android\app\google-services.json" -ForegroundColor Red
    exit 1
}

# --- 5. Bersihkan --------------------------------------------------------------
TulisJudul "5. Membersihkan hasil build lama"

foreach ($jalur in @("build", ".dart_tool", "android\.gradle")) {
    if (Test-Path $jalur) {
        Remove-Item -Recurse -Force $jalur -ErrorAction SilentlyContinue
        Write-Host "   dihapus : $jalur"
    }
}

Write-Host "   menjalankan flutter clean..."
flutter clean

Write-Host "   mengambil paket ulang..."
flutter pub get

# --- 6. Hentikan Gradle --------------------------------------------------------
TulisJudul "6. Menghentikan Gradle yang masih hidup"

Push-Location "android"
if (Test-Path "gradlew.bat") {
    .\gradlew.bat --stop
}
Pop-Location

# --- 7. Perangkat --------------------------------------------------------------
TulisJudul "7. Daftar perangkat"

$keluaran = flutter devices
$keluaran

$perangkat = @()
foreach ($baris in $keluaran) {
    if ($baris -match "^\s*(\S+)\s+.*\b(android|mobile|ios)\b" -and $baris -notmatch "wireless") {
        $perangkat += $Matches[1]
    }
}

$target = ""
if ($perangkat.Count -ge 1) {
    $target = $perangkat[0]
    Write-Host ""
    Write-Host "   Perangkat kabel dipakai: $target" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "   Tidak ada perangkat KABEL yang terbaca." -ForegroundColor Yellow
    Write-Host "   Bila HP tersambung nirkabel, pemasangan bisa terputus di tengah build." -ForegroundColor Yellow
    Write-Host "   Disarankan: pasang kabel USB dan coba lagi." -ForegroundColor Yellow
}

# --- 8. Bangun dan jalankan ----------------------------------------------------
TulisJudul "8. Membangun dan menjalankan aplikasi"
Write-Host "   Build pertama dengan Firebase memakan 10-15 menit." -ForegroundColor Yellow
Write-Host "   Jangan ditutup. Silakan tinggalkan sebentar." -ForegroundColor Yellow
Write-Host ""

if ($target -ne "") {
    flutter run -d $target
} else {
    flutter run
}

TulisJudul "Selesai"
Write-Host "Bila masih gagal, salin 20 baris pertama yang berwarna merah" -ForegroundColor Green
Write-Host "dan kirimkan ke saya." -ForegroundColor Green
