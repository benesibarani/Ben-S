# =============================================================================
#  RTS PANEL BY BENE - PERBAIKI PLUGIN FIREBASE LALU BUILD
#  Berkas: PERBAIKI_PLUGIN_FIREBASE.ps1
#
#  Memperbaiki penyebab build gagal:
#
#     Cannot add task 'generateLockfiles' as a task with that name already exists
#     Starting AGP 9+, only the new DSL interface will be read
#
#  Penyebabnya: plugin Google Services versi 4.4.2 BELUM mendukung AGP 9.
#  Versi yang benar adalah 4.5.0 (terbit Juni 2026).
#
#  Skrip ini:
#    1. Menampilkan versi Gradle, AGP, Kotlin, dan isi gradle.properties
#       (untuk pemeriksaan - salin bila masih gagal)
#    2. Mengubah versi plugin google-services menjadi 4.5.0
#    3. Menonaktifkan android.enableJetifier (tidak dipakai pada AGP 9)
#    4. Membersihkan hasil build lama
#    5. Membangun dan menjalankan aplikasi di HP
#
#  CARA PAKAI:
#    1. Simpan di folder proyek: D:\Project\rts_panel_app
#    2. Sambungkan HP memakai KABEL USB
#    3. Terminal VS Code:
#         powershell -ExecutionPolicy Bypass -File .\PERBAIKI_PLUGIN_FIREBASE.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
$versiBenar = "4.5.0"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

# Menulis berkas TANPA penanda BOM.
function Simpan-TanpaBom($jalur, $teks) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $teks, $utf8)
}

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

# --- 1. Tampilkan keadaan sekarang (bahan pemeriksaan) -------------------------
TulisJudul "1. Keadaan berkas Gradle sekarang"

$jalurWrapper = "android\gradle\wrapper\gradle-wrapper.properties"
$jalurSettings = "android\settings.gradle.kts"
$jalurProp = "android\gradle.properties"
$jalurApp = "android\app\build.gradle.kts"

if (Test-Path $jalurWrapper) {
    foreach ($baris in (Get-Content $jalurWrapper)) {
        if ($baris -match "distributionUrl") {
            Write-Host "   Gradle : $baris"
        }
    }
}

if (Test-Path $jalurSettings) {
    Write-Host ""
    Write-Host "   --- android\settings.gradle.kts ---"
    Get-Content $jalurSettings | ForEach-Object { Write-Host "   $_" }
}

if (Test-Path $jalurProp) {
    Write-Host ""
    Write-Host "   --- android\gradle.properties (hanya baris pengaturan) ---"
    Get-Content $jalurProp | Where-Object { $_ -match "^\s*[a-zA-Z]" } | ForEach-Object { Write-Host "   $_" }
}

# --- 2. Perbaiki versi plugin google-services ---------------------------------
TulisJudul "2. Mengubah plugin google-services menjadi versi $versiBenar"

if (-not (Test-Path $jalurSettings)) {
    Write-Host "   android\settings.gradle.kts tidak ditemukan." -ForegroundColor Red
    exit 1
}

$isi = Get-Content $jalurSettings -Raw

$pola = 'id\("com\.google\.gms\.google-services"\)\s*version\s*"[^"]+"'

if ($isi -match $pola) {
    $versiLama = ([regex]::Matches($isi, $pola))[0].Value
    Write-Host "   Ditemukan : $versiLama"

    $isi = [regex]::Replace($isi, $pola, 'id("com.google.gms.google-services") version "' + $versiBenar + '"')
    Simpan-TanpaBom $jalurSettings $isi
    Write-Host "   DIUBAH menjadi versi $versiBenar" -ForegroundColor Green
}
else {
    # Belum ada - sisipkan setelah baris flutter-plugin-loader.
    $baris = Get-Content $jalurSettings
    $hasil = New-Object System.Collections.Generic.List[string]
    $disisipkan = $false

    foreach ($satu in $baris) {
        $hasil.Add($satu)

        if (-not $disisipkan -and $satu -match 'dev\.flutter\.flutter-plugin-loader') {
            $hasil.Add('    // START: FlutterFire Configuration')
            $hasil.Add('    id("com.google.gms.google-services") version "' + $versiBenar + '" apply false')
            $hasil.Add('    // END: FlutterFire Configuration')
            $disisipkan = $true
        }
    }

    if ($disisipkan) {
        Simpan-TanpaBom $jalurSettings ($hasil -join "`r`n")
        Write-Host "   DISISIPKAN dengan versi $versiBenar" -ForegroundColor Green
    }
    else {
        Write-Host "   GAGAL menyisipkan. Kirimkan isi settings.gradle.kts ke saya." -ForegroundColor Red
        exit 1
    }
}

# --- 3. Nonaktifkan enableJetifier --------------------------------------------
TulisJudul "3. Menonaktifkan android.enableJetifier"

if (Test-Path $jalurProp) {
    $isiProp = Get-Content $jalurProp -Raw

    if ($isiProp -match "(?m)^\s*android\.enableJetifier\s*=") {
        $isiProp = [regex]::Replace(
            $isiProp,
            "(?m)^\s*android\.enableJetifier\s*=.*$",
            "# android.enableJetifier dimatikan: tidak dipakai lagi pada AGP 9 dan semua pustaka sudah AndroidX"
        )
        Simpan-TanpaBom $jalurProp $isiProp
        Write-Host "   Baris enableJetifier dimatikan (diberi tanda #)." -ForegroundColor Green
    }
    else {
        Write-Host "   Tidak ada baris enableJetifier (aman)." -ForegroundColor Green
    }

    # Pastikan dua baris penyesuaian AGP 9 tetap ada.
    $isiProp = Get-Content $jalurProp -Raw
    $kurang = @()
    if ($isiProp -notmatch "android\.newDsl\s*=\s*false") { $kurang += 'android.newDsl=false' }
    if ($isiProp -notmatch "android\.builtInKotlin\s*=\s*false") { $kurang += 'android.builtInKotlin=false' }

    if ($kurang.Count -gt 0) {
        $isiProp = $isiProp.TrimEnd() + "`r`n" + ($kurang -join "`r`n") + "`r`n"
        Simpan-TanpaBom $jalurProp $isiProp
        Write-Host "   Ditambahkan: $($kurang -join ', ')" -ForegroundColor Green
    }
    else {
        Write-Host "   android.newDsl dan android.builtInKotlin sudah ada." -ForegroundColor Green
    }
}

# --- 4. Periksa plugin di app/build.gradle.kts --------------------------------
TulisJudul "4. Memeriksa android\app\build.gradle.kts"

if (Test-Path $jalurApp) {
    $isiApp = Get-Content $jalurApp -Raw

    if ($isiApp -match 'com\.google\.gms\.google-services') {
        Write-Host "   Plugin google-services ADA di app\build.gradle.kts" -ForegroundColor Green
    }
    else {
        Write-Host "   Plugin google-services BELUM ADA di app\build.gradle.kts" -ForegroundColor Red
        Write-Host "   Ganti isinya dengan build.gradle.kts.updated, lalu jalankan lagi." -ForegroundColor Yellow
    }
}

# --- 5. Bersihkan --------------------------------------------------------------
TulisJudul "5. Membersihkan hasil build lama"

foreach ($jalur in @("build", ".dart_tool", "android\.gradle")) {
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

# --- 6. Bangun -----------------------------------------------------------------
TulisJudul "6. Membangun dan menjalankan aplikasi"
Write-Host "   Build pertama dengan Firebase memakan 10-15 menit." -ForegroundColor Yellow
Write-Host "   Jangan ditutup. Silakan tinggalkan sebentar." -ForegroundColor Yellow
Write-Host ""

$keluaran = flutter devices
$keluaran

$perangkat = @()
foreach ($baris in $keluaran) {
    if ($baris -match "^\s*(\S+)\s+.*\b(android|mobile)\b" -and $baris -notmatch "wireless") {
        $perangkat += $Matches[1]
    }
}

if ($perangkat.Count -ge 1) {
    Write-Host "   Perangkat kabel dipakai: $($perangkat[0])" -ForegroundColor Green
    flutter run -d $perangkat[0]
}
else {
    Write-Host "   Tidak ada perangkat kabel - memakai daftar bawaan." -ForegroundColor Yellow
    flutter run
}

TulisJudul "Selesai"
Write-Host "Bila MASIH gagal, kirimkan:" -ForegroundColor Green
Write-Host "   1. Bagian '1. Keadaan berkas Gradle sekarang' di atas (salin teksnya)" -ForegroundColor Green
Write-Host "   2. 20 baris pertama yang berwarna merah" -ForegroundColor Green
