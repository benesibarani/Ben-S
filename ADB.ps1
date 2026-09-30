# =============================================================================
#  RTS PANEL BY BENE - pemanggil adb (tanpa perlu mengatur PATH)
#  Berkas : ADB.ps1
#
#  MASALAH YANG DISELESAIKAN
#  -------------------------
#  Ketika menjalankan "adb install ..." muncul tulisan:
#      adb : The term 'adb' is not recognized as the name of a cmdlet ...
#  Sebabnya: adb.exe berada di dalam folder Android SDK (platform-tools),
#  dan folder itu belum terdaftar pada PATH Windows. Skrip ini mencari adb.exe
#  sendiri, lalu meneruskan perintah Bapak kepadanya.
#
#  CARA PAKAI  (PowerShell, di folder D:\Project\rts_panel_app)
#  -----------------------------------------------------------
#     .\ADB.ps1                 -> bantuan + daftar HP yang tersambung
#     .\ADB.ps1 daftar          -> melihat HP yang tersambung
#     .\ADB.ps1 alamat          -> mencetak letak adb.exe (untuk disalin)
#     .\ADB.ps1 pasang          -> memasang APK DEBUG ke HP (yang terbaru)
#     .\ADB.ps1 pasang-release  -> memasang APK RELEASE ke HP
#     .\ADB.ps1 buka            -> membuka aplikasi di HP
#     .\ADB.ps1 catatan         -> melihat catatan aplikasi (untuk mencari sebab)
#     .\ADB.ps1 bersih          -> menyambung ulang: kill-server + start-server
#
#  Bila muncul "running scripts is disabled", jalankan dulu:
#     Set-ExecutionPolicy -Scope Process Bypass
# =============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Perintah = "",

    [Parameter(Position = 1)]
    [string]$Tambahan = ""
)

$kodePaket = "com.example.rts_panel_app"

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

# -----------------------------------------------------------------------------
# Mencari adb.exe
# -----------------------------------------------------------------------------
function Cari-Adb {
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

    foreach ($satu in $kandidat) {
        if ($satu -and (Test-Path $satu)) { return $satu }
    }

    $cari = Get-Command adb.exe -ErrorAction SilentlyContinue

    if ($cari) { return $cari.Source }

    return $null
}

$adb = Cari-Adb

if (-not $adb) {
    Write-Host ""
    Write-Host "   adb.exe TIDAK ditemukan pada komputer ini." -ForegroundColor Red
    Write-Host ""
    Write-Host "   Yang dapat dilakukan tanpa adb:" -ForegroundColor Yellow
    Write-Host "     flutter devices                 (melihat HP yang tersambung)" -ForegroundColor Gray
    Write-Host "     flutter run -d <nama HP>        (bangun + pasang + jalankan)" -ForegroundColor Gray
    Write-Host "     flutter install --debug -d <nama HP>   (pasang saja)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Bila adb tetap diperlukan, jalankan: flutter doctor -v" -ForegroundColor Gray
    Write-Host "   lalu kirimkan keluarannya kepada pengembang." -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------------------------------------
# Perintah
# -----------------------------------------------------------------------------
switch ($Perintah.ToLower()) {

    "" {
        TulisJudul "Pemanggil adb - RTS Panel By Bene"
        Write-Host "   adb ditemukan : $adb" -ForegroundColor Green
        Write-Host ""
        Write-Host "   Perintah yang tersedia:" -ForegroundColor White
        Write-Host "     .\ADB.ps1 daftar          melihat HP yang tersambung" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 alamat          mencetak letak adb.exe" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 pasang          memasang APK debug terbaru" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 pasang-release  memasang APK release terbaru" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 buka            membuka aplikasi di HP" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 catatan         melihat catatan aplikasi" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 bersih          menyambung ulang adb" -ForegroundColor Gray

        Write-Host ""
        Write-Host "   HP yang tersambung sekarang:" -ForegroundColor White
        & $adb devices -l
    }

    "alamat" {
        Write-Host ""
        Write-Host "   adb.exe berada di:" -ForegroundColor White
        Write-Host "   $adb" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "   Bila ingin memakai langsung, salin bentuk berikut:" -ForegroundColor Gray
        Write-Host "   & `"$adb`" devices" -ForegroundColor Gray
    }

    "daftar" {
        TulisJudul "HP yang tersambung"
        & $adb devices -l
        Write-Host ""
        Write-Host "   Yang diharapkan: diakhiri kata 'device'." -ForegroundColor Gray
        Write-Host "   Bila 'offline' atau 'unauthorized', jalankan:" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1 bersih" -ForegroundColor Gray
    }

    "bersih" {
        TulisJudul "Menyambung ulang adb"
        & $adb disconnect 2>&1 | Out-Null
        & $adb kill-server 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        & $adb start-server 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "   Selesai. Bila HP nirkabel tidak muncul lagi, sambungkan dengan:" -ForegroundColor White
        Write-Host "     .\PASANG_CEPAT.ps1" -ForegroundColor Gray
        Write-Host "     (atau: adb connect IP:PORT dari Opsi Pengembang - Penelusuran nirkabel)" -ForegroundColor Gray
        Write-Host ""
        & $adb devices -l
    }

    "pasang" { $jenis = "debug" }
    "pasang-debug" { $jenis = "debug" }
    "pasang-release" { $jenis = "release" }

    "buka" {
        TulisJudul "Membuka aplikasi di HP"
        & $adb shell am start -n "$kodePaket/.MainActivity" 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        Start-Sleep -Seconds 2
        $cek = & $adb shell dumpsys window 2>&1 | Select-String $kodePaket
        if (-not $cek) {
            Write-Host "   Memakai cara cadangan..." -ForegroundColor Gray
            & $adb shell monkey -p $kodePaket -c android.intent.category.LAUNCHER 1 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        }
        Write-Host "   Aplikasi dibuka di layar HP." -ForegroundColor Green
    }

    "catatan" {
        TulisJudul "Catatan aplikasi (tekan Ctrl+C untuk berhenti)"
        Write-Host "   Menampilkan baris yang berkaitan dengan RTS, cuaca, dan lokasi..." -ForegroundColor Gray
        Write-Host ""
        & $adb logcat | Select-String -Pattern "rts|cuaca|lokasi|location|flutter" 
    }

    default {
        Write-Host ""
        Write-Host "   Perintah '$Perintah' tidak dikenal." -ForegroundColor Yellow
        Write-Host "   Jalankan tanpa tambahan untuk melihat daftar perintah:" -ForegroundColor Gray
        Write-Host "     .\ADB.ps1" -ForegroundColor Gray
        exit 1
    }
}

# -----------------------------------------------------------------------------
# Pemasangan APK (dipakai perintah pasang / pasang-debug / pasang-release)
# -----------------------------------------------------------------------------
if ($jenis) {
    TulisJudul "Memasang APK $jenis"

    # Mencari berkas APK
    if ($jenis -eq "debug") {
        $kandidatApk = @(
            "build\app\outputs\flutter-apk\app-debug.apk"
        )
    }
    else {
        $kandidatApk = @(
            "build\app\outputs\flutter-apk\app-release.apk"
        )
    }

    $berkas = ""

    foreach ($satu in $kandidatApk) {
        if (Test-Path $satu) { $berkas = $satu; break }
    }

    if (-not $berkas) {
        TulisHasil $false "Berkas APK $jenis belum ada"
        Write-Host ""
        Write-Host "   Buat dulu berkasnya:" -ForegroundColor Yellow
        if ($jenis -eq "debug") {
            Write-Host "     flutter build apk --debug" -ForegroundColor Gray
        }
        else {
            Write-Host "     flutter build apk --release" -ForegroundColor Gray
        }
        exit 1
    }

    $info = Get-Item $berkas
    Write-Host "   Berkas : $berkas" -ForegroundColor Gray
    Write-Host "   Ukuran : $([math]::Round($info.Length / 1MB, 1)) MB" -ForegroundColor Gray
    Write-Host "   Waktu  : $($info.LastWriteTime)" -ForegroundColor Gray

    # Mencari HP
    $perangkat = & $adb devices 2>&1

    $daftarHp = @()

    foreach ($baris in $perangkat) {
        if ($baris -match "^(\S+)\s+device$") {
            $daftarHp += $Matches[1]
        }
    }

    if ($daftarHp.Count -eq 0) {
        TulisHasil $false "Tidak ada HP yang siap dipasangi"
        Write-Host ""
        Write-Host "   Periksa:" -ForegroundColor Yellow

        foreach ($baris in $perangkat) {
            if ($baris -match "offline") {
                Write-Host "     - ada HP berstatus 'offline' - jalankan: .\ADB.ps1 bersih" -ForegroundColor Gray
            }
            if ($baris -match "unauthorized") {
                Write-Host "     - HP minta izin: lihat layar HP, tekan 'Allow / Izinkan'" -ForegroundColor Gray
            }
        }

        Write-Host "     - HP nirkabel belum tersambung - jalankan: .\PASANG_CEPAT.ps1" -ForegroundColor Gray
        exit 1
    }

    if ($daftarHp.Count -gt 1) {
        Write-Host ""
        Write-Host "   Lebih dari satu HP tersambung:" -ForegroundColor Yellow
        $no = 1
        foreach ($satu in $daftarHp) {
            Write-Host "     $no. $satu" -ForegroundColor Gray
            $no++
        }
        $pilih = Read-Host "   Tulis nomor HP yang ingin dipasangi"
        $indeks = [int]$pilih - 1
        $hp = $daftarHp[$indeks]
    }
    else {
        $hp = $daftarHp[0]
    }

    Write-Host ""
    Write-Host "   HP     : $hp" -ForegroundColor Gray
    Write-Host "   Memasang..." -ForegroundColor Gray

    $hasil = & $adb -s $hp install -r $berkas 2>&1
    $hasil | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

    if ($hasil -match "Success") {
        TulisHasil $true "Aplikasi terpasang di HP"
        Write-Host ""
        Write-Host "   Membuka aplikasi..." -ForegroundColor Gray
        & $adb -s $hp shell am start -n "$kodePaket/.MainActivity" 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
        Write-Host ""
        Write-Host "   Di HP: bila muncul pertanyaan izin lokasi - pilih" -ForegroundColor White
        Write-Host "   'Saat aplikasi digunakan'. Lalu lihat kotak Cuaca pada kartu merah." -ForegroundColor White
    }
    else {
        TulisHasil $false "Pemasangan belum berhasil"
        Write-Host ""
        Write-Host "   Bila tertulis INSTALL_FAILED_UPDATE_INCOMPATIBLE:" -ForegroundColor Yellow
        Write-Host "     aplikasi lama bertanda tangan berbeda - perlu dihapus dulu:" -ForegroundColor Gray
        Write-Host "     & `"$adb`" -s $hp uninstall $kodePaket" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   Bila tertulis INSTALL_FAILED_VERSION_DOWNGRADE:" -ForegroundColor Yellow
        Write-Host "     & `"$adb`" -s $hp install -r -d $berkas" -ForegroundColor Gray
        exit 1
    }
}
