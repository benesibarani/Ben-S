# =============================================================================
#  RTS PANEL BY BENE - PEMERIKSA BERKAS GRADLE (TANPA BUILD)
#  Berkas: PERIKSA_GRADLE.ps1
#
#  Skrip ini TIDAK membangun aplikasi. Tugasnya hanya MEMBACA berkas Gradle
#  lalu menyusunnya menjadi satu laporan kecil.
#
#  Hasilnya:
#    1. Disimpan sebagai LAPORAN_GRADLE.txt di folder proyek
#    2. DISALIN KE CLIPBOARD, jadi Bapak cukup menempelkan (Ctrl+V) ke chat
#
#  CARA PAKAI:
#    1. Simpan di folder proyek: D:\Project\rts_panel_app
#    2. Terminal VS Code:
#         powershell -ExecutionPolicy Bypass -File .\PERIKSA_GRADLE.ps1
#    3. Buka chat, tekan Ctrl+V, kirim.
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

$baris = New-Object System.Collections.Generic.List[string]

function Tambah($teks) {
    $baris.Add([string]$teks)
}

# --- Judul ---------------------------------------------------------------------
Tambah "===================== LAPORAN GRADLE RTS PANEL ====================="
Tambah ("Waktu laporan : " + (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
Tambah ""

# --- Versi Flutter -------------------------------------------------------------
Tambah "== VERSI FLUTTER =="
try {
    $versiFlutter = (flutter --version 2>$null | Select-Object -First 3) -join " | "
    Tambah $versiFlutter
} catch {
    Tambah "(gagal membaca versi flutter)"
}
Tambah ""

# --- Daftar berkas -------------------------------------------------------------
Tambah "== DAFTAR BERKAS DI FOLDER android =="
Get-ChildItem "android" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Tambah ("  " + $_.Name + "  (" + $_.Length + " byte)")
}
Tambah ""

Tambah "== DAFTAR BERKAS DI FOLDER android\app =="
Get-ChildItem "android\app" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Tambah ("  " + $_.Name + "  (" + $_.Length + " byte)")
}
Tambah ""

# --- Fungsi pembaca berkas -----------------------------------------------------
function BacaBerkas($jalur) {
    Tambah ("== ISI " + $jalur + " ==")

    if (-not (Test-Path $jalur)) {
        Tambah "(BERKAS TIDAK ADA)"
        Tambah ""
        return
    }

    $isi = Get-Content $jalur -ErrorAction SilentlyContinue
    $nomor = 0

    foreach ($satu in $isi) {
        $nomor++
        Tambah ("{0,4}: {1}" -f $nomor, $satu)
    }

    Tambah ("(jumlah baris: " + $nomor + ")")
    Tambah ""
}

function Hitung($jalur, $pola) {
    if (-not (Test-Path $jalur)) { return "berkas tidak ada" }
    $isi = Get-Content $jalur -Raw -ErrorAction SilentlyContinue
    if ($null -eq $isi) { return "0" }
    return ([regex]::Matches($isi, $pola)).Count.ToString()
}

# --- Deteksi penggandaan -------------------------------------------------------
Tambah "== JUMLAH KEMUNCULAN (untuk mendeteksi penggandaan) =="
Tambah ("  app/build.gradle.kts  -> 'flutter-gradle-plugin'   : " + (Hitung "android\app\build.gradle.kts" "flutter-gradle-plugin"))
Tambah ("  app/build.gradle.kts  -> 'plugins {'                : " + (Hitung "android\app\build.gradle.kts" "plugins\s*\{"))
Tambah ("  app/build.gradle.kts  -> 'google-services'          : " + (Hitung "android\app\build.gradle.kts" "google-services"))
Tambah ("  app/build.gradle.kts  -> 'apply plugin'             : " + (Hitung "android\app\build.gradle.kts" "apply plugin"))
Tambah ("  settings.gradle.kts   -> 'includeBuild'             : " + (Hitung "android\settings.gradle.kts" "includeBuild"))
Tambah ("  settings.gradle.kts   -> 'pluginManagement'         : " + (Hitung "android\settings.gradle.kts" "pluginManagement"))
Tambah ("  settings.gradle.kts   -> 'google-services'          : " + (Hitung "android\settings.gradle.kts" "google-services"))
Tambah ("  settings.gradle.kts   -> 'include'                  : " + (Hitung "android\settings.gradle.kts" "include\s*\("))
Tambah ("  build.gradle.kts      -> 'flutter'                  : " + (Hitung "android\build.gradle.kts" "flutter"))
Tambah ""

# --- Isi berkas ----------------------------------------------------------------
BacaBerkas "android\settings.gradle.kts"
BacaBerkas "android\build.gradle.kts"
BacaBerkas "android\app\build.gradle.kts"
BacaBerkas "android\gradle.properties"
BacaBerkas "android\gradle\wrapper\gradle-wrapper.properties"
BacaBerkas "pubspec.yaml"

# --- Daftar isi proyek ---------------------------------------------------------
Tambah "== PUSTAKA FLUTTER YANG TERDAFTAR (.flutter-plugins-dependencies) =="
if (Test-Path ".flutter-plugins-dependencies") {
    $isiPlugin = Get-Content ".flutter-plugins-dependencies" -Raw
    foreach ($nama in @("firebase_core", "firebase_messaging", "flutter_local_notifications", "geolocator", "geocoding")) {
        $ada = if ($isiPlugin -match $nama) { "ADA" } else { "TIDAK ADA" }
        Tambah ("  " + $nama + " : " + $ada)
    }
} else {
    Tambah "(berkas tidak ada)"
}
Tambah ""

Tambah "===================== AKHIR LAPORAN ====================="

# --- Simpan dan salin ke clipboard ---------------------------------------------
$teks = $baris -join "`r`n"
$jalurLaporan = Join-Path $proyek "LAPORAN_GRADLE.txt"

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($jalurLaporan, $teks, $utf8)

Write-Host ""
Write-Host "Laporan tersimpan di: $jalurLaporan" -ForegroundColor Green
Write-Host ("Jumlah baris laporan: " + $baris.Count) -ForegroundColor Green
Write-Host ""

try {
    Set-Clipboard -Value $teks
    Write-Host "Laporan SUDAH DISALIN ke clipboard." -ForegroundColor Green
    Write-Host ""
    Write-Host "LANGKAH SELANJUTNYA:" -ForegroundColor Cyan
    Write-Host "  1. Buka chat Arena"
    Write-Host "  2. Tekan Ctrl+V lalu kirim"
    Write-Host ""
} catch {
    Write-Host "Gagal menyalin ke clipboard. Buka berkas LAPORAN_GRADLE.txt" -ForegroundColor Yellow
    Write-Host "lalu salin seluruh isinya secara manual." -ForegroundColor Yellow
}

Write-Host "Tidak ada build yang dijalankan - skrip ini hanya membaca berkas." -ForegroundColor Yellow
