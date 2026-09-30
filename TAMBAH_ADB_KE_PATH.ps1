# =============================================================================
#  RTS PANEL BY BENE - MENDAFTARKAN adb KE PATH WINDOWS (perbaikan permanen)
#  Berkas : TAMBAH_ADB_KE_PATH.ps1
#
#  GUNA
#  ---
#  Menghilangkan tulisan:
#      adb : The term 'adb' is not recognized as the name of a cmdlet ...
#  Setelah dijalankan SEKALI, perintah "adb" dapat diketik langsung dari
#  PowerShell mana pun (setelah jendela PowerShell dibuka ulang).
#
#  APA YANG DIUBAH
#  ---------------
#  Hanya PATH milik PENGGUNA (User PATH) - bukan PATH sistem. Yang ditambahkan
#  hanya satu folder, yaitu folder platform-tools tempat adb.exe berada.
#  Skrip ini TIDAK menghapus isi PATH yang sudah ada.
#
#  KEAMANAN
#  --------
#  Sebelum mengubah, isi PATH lama DISIMPAN ke berkas cadangan:
#      %USERPROFILE%\path_pengguna_cadangan.txt
#  Bila ingin membatalkan, buka berkas itu dan kembalikan nilai lamanya
#  (caranya tertulis pada bagian akhir skrip ini).
#
#  CARA PAKAI
#  ----------
#     .\TAMBAH_ADB_KE_PATH.ps1
#  Bila dijalankan dengan hak pengguna biasa (tanpa administrator) - itu sudah
#  cukup, karena yang diubah adalah PATH pengguna.
# =============================================================================

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  $teks" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
}

function TulisHasil($ok, $teks) {
    if ($ok) { Write-Host "   [BERHASIL] $teks" -ForegroundColor Green }
    else { Write-Host "   [GAGAL]    $teks" -ForegroundColor Red }
}

Write-Host ""
Write-Host "RTS PANEL BY BENE - MENDAFTARKAN adb KE PATH WINDOWS" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Mencari adb.exe
# -----------------------------------------------------------------------------
TulisJudul "1. Mencari adb.exe"

$kandidat = @()

if (Test-Path "android\local.properties") {
    foreach ($satu in (Get-Content "android\local.properties")) {
        if ($satu -match "^\s*sdk\.dir\s*=\s*(.+)$") {
            $sdk = $Matches[1].Trim().Replace("\\", "\").Replace("\:", ":")
            $kandidat += (Join-Path $sdk "platform-tools\adb.exe")
        }
    }
}

if ($env:ANDROID_SDK_ROOT) { $kandidat += (Join-Path $env:ANDROID_SDK_ROOT "platform-tools\adb.exe") }
if ($env:ANDROID_HOME)     { $kandidat += (Join-Path $env:ANDROID_HOME "platform-tools\adb.exe") }
$kandidat += (Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe")
$kandidat += "C:\Android\Sdk\platform-tools\adb.exe"
$kandidat += "D:\Android\Sdk\platform-tools\adb.exe"
$kandidat += "C:\Program Files\Android\Sdk\platform-tools\adb.exe"

$adb = $null

foreach ($satu in $kandidat) {
    if ($satu -and (Test-Path $satu)) { $adb = $satu; break }
}

if (-not $adb) {
    $cari = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cari) { $adb = $cari.Source }
}

if (-not $adb) {
    TulisHasil $false "adb.exe tidak ditemukan - PATH tidak diubah"
    Write-Host ""
    Write-Host "   Jalankan 'flutter doctor -v' lalu kirimkan keluarannya" -ForegroundColor Yellow
    Write-Host "   kepada pengembang." -ForegroundColor Yellow
    exit 1
}

$folderAdb = Split-Path $adb -Parent

TulisHasil $true "adb ditemukan"
Write-Host "   Berkas : $adb" -ForegroundColor Gray
Write-Host "   Folder : $folderAdb" -ForegroundColor Gray

# -----------------------------------------------------------------------------
# 2. Membaca PATH pengguna sekarang
# -----------------------------------------------------------------------------
TulisJudul "2. Memeriksa PATH pengguna"

$pathPengguna = [Environment]::GetEnvironmentVariable("Path", "User")

if (-not $pathPengguna) { $pathPengguna = "" }

$sudahAda = $false

foreach ($satu in ($pathPengguna -split ";")) {
    if ($satu.Trim().TrimEnd("\") -ieq $folderAdb.TrimEnd("\")) {
        $sudahAda = $true
        break
    }
}

if ($sudahAda) {
    TulisHasil $true "Folder itu SUDAH ada pada PATH - tidak perlu diubah"
    Write-Host ""
    Write-Host "   Bila perintah 'adb' masih belum dikenali:" -ForegroundColor Yellow
    Write-Host "     1. TUTUP semua jendela PowerShell, lalu buka yang baru" -ForegroundColor Gray
    Write-Host "     2. Bila masih belum, restart/keluar lalu masuk Windows" -ForegroundColor Gray
    exit 0
}

Write-Host "   Jumlah bagian PATH sekarang: $(($pathPengguna -split ';').Count)" -ForegroundColor Gray

# -----------------------------------------------------------------------------
# 3. Menyimpan cadangan PATH lama
# -----------------------------------------------------------------------------
TulisJudul "3. Menyimpan cadangan PATH"

$berkasCadangan = Join-Path $env:USERPROFILE "path_pengguna_cadangan.txt"

$isiCadangan = @(
    "CADANGAN PATH PENGGUNA - RTS PANEL BY BENE",
    "Disimpan: $(Get-Date -Format 'dd-MM-yyyy HH:mm:ss')",
    "",
    "PATH LAMA:",
    $pathPengguna,
    "",
    "CARA MENGEMBALIKAN BILA PERLU:",
    "  Buka PowerShell, lalu jalankan (satu baris):",
    '  [Environment]::SetEnvironmentVariable("Path", (Get-Content "$env:USERPROFILE\path_pengguna_cadangan.txt" | Select-Object -Index 4), "User")'
)

$isiCadangan | Set-Content -Path $berkasCadangan -Encoding UTF8

if (Test-Path $berkasCadangan) {
    TulisHasil $true "Cadangan tersimpan: $berkasCadangan"
}
else {
    TulisHasil $false "Cadangan gagal disimpan - PATH tidak diubah (demi keamanan)"
    exit 1
}

# -----------------------------------------------------------------------------
# 4. Menambahkan folder adb ke PATH
# -----------------------------------------------------------------------------
TulisJudul "4. Menambahkan folder adb ke PATH"

$pathBaru = $pathPengguna.TrimEnd(";") + ";" + $folderAdb

[Environment]::SetEnvironmentVariable("Path", $pathBaru, "User")

$periksa = [Environment]::GetEnvironmentVariable("Path", "User")

if ($periksa -match [regex]::Escape($folderAdb)) {
    TulisHasil $true "Folder adb sudah ditambahkan ke PATH pengguna"
}
else {
    TulisHasil $false "Penambahan belum berhasil - kembalikan PATH dari cadangan"
    exit 1
}

# -----------------------------------------------------------------------------
# 5. Selesai
# -----------------------------------------------------------------------------
TulisJudul "SELESAI"

Write-Host "   Langkah terakhir: TUTUP jendela PowerShell ini, lalu BUKA BARU." -ForegroundColor White
Write-Host "   Setelah itu perintah berikut dapat langsung diketik:" -ForegroundColor White
Write-Host ""
Write-Host "     adb devices" -ForegroundColor Cyan
Write-Host "     adb install -r build\app\outputs\flutter-apk\app-debug.apk" -ForegroundColor Cyan
Write-Host "     adb shell am start -n com.example.rts_panel_app/.MainActivity" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Bila suatu saat ingin membatalkan perubahan ini:" -ForegroundColor Gray
Write-Host "     buka berkas $berkasCadangan" -ForegroundColor Gray
Write-Host "     lalu jalankan perintah yang tertulis di bagian bawah berkas itu." -ForegroundColor Gray
Write-Host ""
