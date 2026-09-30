# =============================================================================
#  RTS PANEL BY BENE - PASANG CEPAT KE HP (NIRKABEL, TAHAN TERPUTUS)
#  Berkas : PASANG_CEPAT.ps1
#
#  GUNA DI PAKAI SAAT APA
#  ----------------------
#  Ketika pemasangan lewat skrip panjang terputus di tengah, atau ketika HP
#  sudah pernah dipasangkan dan Bapak hanya ingin memasang APK yang sudah ada.
#  Skrip ini:
#     1. mencari adb.exe
#     2. menyambung ulang ke HP secara nirkabel (diulang sampai berhasil)
#     3. menunggu HP benar-benar siap (bukan "offline")
#     4. memasang berkas APK (debug atau release) - diulang bila gagal
#     5. membuka aplikasi di HP
#
#  CARA PAKAI
#  ----------
#  Buka PowerShell di folder D:\Project\rts_panel_app, lalu salah satu:
#
#     .\PASANG_CEPAT.ps1                        (menanyakan IP:PORT HP)
#     .\PASANG_CEPAT.ps1 192.168.1.10:37000     (langsung dengan alamat)
#     .\PASANG_CEPAT.ps1 192.168.1.10:37000 -Berkas build\app\outputs\flutter-apk\app-release.apk
#     .\PASANG_CEPAT.ps1 -Pasangkan              (HP belum pernah dipasangkan:
#                                                 akan diminta kode 6 angka)
#
#  Bila muncul tulisan "running scripts is disabled", jalankan dulu:
#     Set-ExecutionPolicy -Scope Process Bypass
#
#  Skrip ini TIDAK menghapus data aplikasi dan TIDAK mengubah berkas kode.
# =============================================================================

param(
    [Parameter(Position = 0)]
    [string]$Alamat = "",

    [string]$Berkas = "",

    [switch]$Pasangkan,

    [int]$Ulang = 5
)

$kodePaket = "com.example.rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  $teks" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
}

function TulisHasil($ok, $teks) {
    if ($ok) {
        Write-Host "   [BERHASIL] $teks" -ForegroundColor Green
    }
    else {
        Write-Host "   [GAGAL]    $teks" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "RTS PANEL BY BENE - PASANG CEPAT KE HP (NIRKABEL)" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Mencari adb.exe
# -----------------------------------------------------------------------------
TulisJudul "1. Mencari adb.exe"

$adb = $null
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
    if ($satu -and (Test-Path $satu)) { $adb = $satu; break }
}

if (-not $adb) {
    $cari = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($cari) { $adb = $cari.Source }
}

if (-not $adb) {
    TulisHasil $false "adb.exe tidak ditemukan"
    Write-Host "   Kirimkan keluaran 'flutter doctor -v' kepada pengembang." -ForegroundColor Yellow
    exit 1
}

TulisHasil $true "adb ditemukan: $adb"

# -----------------------------------------------------------------------------
# 2. Alamat HP
# -----------------------------------------------------------------------------
if (-not $Alamat) {
    Write-Host ""
    Write-Host "   Di HP: Pengaturan - Sistem - Opsi Pengembang - Penelusuran nirkabel." -ForegroundColor Yellow
    Write-Host "   Catat IP address & Port yang muncul (contoh: 192.168.1.10:37000)." -ForegroundColor Yellow
    Write-Host ""
    $Alamat = Read-Host "   Tuliskan IP:PORT HP sekarang"
}

$Alamat = $Alamat.Trim()

if ($Alamat -notmatch "^\d+\.\d+\.\d+\.\d+:\d+$") {
    TulisHasil $false "Alamat tidak sesuai bentuk IP:PORT (contoh: 192.168.1.10:37000)"
    exit 1
}

TulisJudul "2. Menyambung ke HP: $Alamat"

$ipSaja = $Alamat.Split(":")[0]

# Pemasangan (pairing) - hanya bila diminta
if ($Pasangkan) {
    Write-Host "   Di HP tekan 'Pair device with pairing code'." -ForegroundColor Yellow
    Write-Host "   Muncul IP:PORT KHUSUS PEMASANGAN (berbeda dari nomor di atas)." -ForegroundColor Yellow
    Write-Host ""

    $alamatPasang = Read-Host "   Tuliskan IP:PORT untuk pemasangan"
    $kode = Read-Host "   Tuliskan kode 6 angka yang muncul di HP"

    $alamatPasang = $alamatPasang.Trim()
    $kode = $kode.Trim()

    if ($alamatPasang -and $kode) {
        Write-Host ""
        Write-Host "   Memasangkan..." -ForegroundColor Gray

        $hasilPair = & $adb pair $alamatPasang $kode 2>&1
        $hasilPair | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

        if ($hasilPair -match "Successfully paired") {
            TulisHasil $true "Pemasangan (pairing) berhasil"
        }
        else {
            TulisHasil $false "Pemasangan (pairing) belum berhasil - dicoba tetap menyambung"
        }
    }
}

# Membersihkan sambungan lama, lalu menyambung ulang
& $adb disconnect $ipSaja 2>&1 | Out-Null
& $adb kill-server 2>&1 | Out-Null
& $adb start-server 2>&1 | Out-Null

$tersambung = $false

for ($i = 1; $i -le $Ulang; $i++) {
    Write-Host ""
    Write-Host "   Percobaan $i dari $Ulang..." -ForegroundColor Gray

    $hasil = & $adb connect $Alamat 2>&1
    $hasil | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

    Start-Sleep -Seconds 2

    $perangkat = & $adb devices 2>&1
    $barisHp = $perangkat | Where-Object { $_ -match [regex]::Escape($Alamat) }

    if ($barisHp -match "\sdevice$") {
        $tersambung = $true
        TulisHasil $true "HP tersambung dan siap"
        break
    }
    elseif ($barisHp -match "unauthorized") {
        Write-Host "   HP minta izin: lihat layar HP, tekan 'Allow / Izinkan'." -ForegroundColor Yellow
    }
    elseif ($barisHp -match "offline") {
        Write-Host "   HP masih 'offline' - menyambung ulang..." -ForegroundColor Yellow
        & $adb disconnect $Alamat 2>&1 | Out-Null
    }
    else {
        Write-Host "   HP belum terlihat. Periksa: Wi-Fi sama? Penelusuran nirkabel hidup?" -ForegroundColor Yellow
        Write-Host "   Port berubah setiap kali Penelusuran nirkabel dinyalakan ulang." -ForegroundColor DarkGray
    }

    if ($i -lt $Ulang) { Start-Sleep -Seconds 3 }
}

if (-not $tersambung) {
    TulisHasil $false "Gagal menyambung ke HP setelah $Ulang percobaan"
    Write-Host ""
    Write-Host "   Yang perlu diperiksa:" -ForegroundColor Yellow
    Write-Host "     1. HP dan komputer pada jaringan Wi-Fi yang sama" -ForegroundColor Gray
    Write-Host "     2. Penelusuran nirkabel di HP masih HIDUP" -ForegroundColor Gray
    Write-Host "     3. IP:PORT masih sama (port berubah bila dimatikan/hidupkan ulang)" -ForegroundColor Gray
    exit 1
}

# -----------------------------------------------------------------------------
# 3. Mencari berkas APK
# -----------------------------------------------------------------------------
TulisJudul "3. Mencari berkas APK"

if (-not $Berkas) {
    $kandidatApk = @(
        "build\app\outputs\flutter-apk\app-debug.apk",
        "build\app\outputs\flutter-apk\app-release.apk"
    )

    foreach ($satu in $kandidatApk) {
        if (Test-Path $satu) { $Berkas = $satu; break }
    }
}

if (-not $Berkas -or -not (Test-Path $Berkas)) {
    TulisHasil $false "Berkas APK belum ada"
    Write-Host ""
    Write-Host "   Buat dulu berkasnya, jalankan salah satu:" -ForegroundColor Yellow
    Write-Host "     flutter build apk --debug      (untuk mencoba cepat)" -ForegroundColor Gray
    Write-Host "     flutter build apk --release    (untuk dipasang ke tim)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Atau langsung pasang tanpa berkas, jalankan:" -ForegroundColor Yellow
    Write-Host "     flutter run -d $Alamat" -ForegroundColor Gray
    exit 1
}

$infoApk = Get-Item $Berkas
$ukuranMb = [math]::Round($infoApk.Length / 1MB, 1)

TulisHasil $true "$Berkas ($ukuranMb MB, diubah $($infoApk.LastWriteTime))"

# -----------------------------------------------------------------------------
# 4. Memasang APK
# -----------------------------------------------------------------------------
TulisJudul "4. Memasang ke HP"

$berhasilPasang = $false

for ($i = 1; $i -le $Ulang; $i++) {
    Write-Host ""
    Write-Host "   Percobaan pemasangan $i dari $Ulang..." -ForegroundColor Gray

    $hasilPasang = & $adb -s $Alamat install -r $Berkas 2>&1
    $hasilPasang | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

    if ($hasilPasang -match "Success") {
        $berhasilPasang = $true
        TulisHasil $true "Aplikasi terpasang di HP"
        break
    }
    elseif ($hasilPasang -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
        Write-Host ""
        Write-Host "   Tanda tangan aplikasi berbeda dari yang terpasang." -ForegroundColor Yellow
        Write-Host "   Perlu menghapus aplikasi lama lebih dahulu (data aplikasi hilang)." -ForegroundColor Yellow
        $jawab = Read-Host "   Hapus aplikasi lama sekarang? (tulis: ya)"

        if ($jawab -eq "ya") {
            & $adb -s $Alamat uninstall $kodePaket 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
            Write-Host "   Aplikasi lama dihapus - mencoba memasang lagi..." -ForegroundColor Gray
        }
        else {
            exit 1
        }
    }
    elseif ($hasilPasang -match "INSTALL_FAILED_VERSION_DOWNGRADE") {
        Write-Host "   Versi terpasang lebih baru - mencoba dengan izin turun versi..." -ForegroundColor Yellow
        $hasilPasang = & $adb -s $Alamat install -r -d $Berkas 2>&1
        $hasilPasang | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

        if ($hasilPasang -match "Success") {
            $berhasilPasang = $true
            TulisHasil $true "Aplikasi terpasang di HP"
            break
        }
    }
    elseif ($hasilPasang -match "device offline" -or $hasilPasang -match "device not found") {
        Write-Host "   Sambungan terputus di tengah pemasangan - menyambung ulang..." -ForegroundColor Yellow
        & $adb disconnect $Alamat 2>&1 | Out-Null
        Start-Sleep -Seconds 2
        & $adb connect $Alamat 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
    }
    elseif ($hasilPasang -match "INSTALL_FAILED_INSUFFICIENT_STORAGE") {
        TulisHasil $false "Ruang penyimpanan HP tidak cukup"
        Write-Host "   Kosongkan sedikit ruang pada HP, lalu jalankan lagi." -ForegroundColor Yellow
        exit 1
    }

    if ($i -lt $Ulang) { Start-Sleep -Seconds 3 }
}

if (-not $berhasilPasang) {
    TulisHasil $false "Pemasangan belum berhasil setelah $Ulang percobaan"
    Write-Host "   Kirimkan tulisan di atas kepada pengembang." -ForegroundColor Yellow
    exit 1
}

# -----------------------------------------------------------------------------
# 5. Membuka aplikasi di HP
# -----------------------------------------------------------------------------
TulisJudul "5. Membuka aplikasi di HP"

& $adb -s $Alamat shell am start -n "$kodePaket/.MainActivity" 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }

Start-Sleep -Seconds 3

$cek = & $adb -s $Alamat shell dumpsys window 2>&1 | Select-String $kodePaket

if (-not $cek) {
    Write-Host "   Memakai cara cadangan untuk membuka aplikasi..." -ForegroundColor Gray
    & $adb -s $Alamat shell monkey -p $kodePaket -c android.intent.category.LAUNCHER 1 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor Gray }
}

TulisJudul "SELESAI"
Write-Host "   Aplikasi sudah terpasang dan dibuka di HP." -ForegroundColor Green
Write-Host ""
Write-Host "   Langkah berikutnya di HP:" -ForegroundColor White
Write-Host "     1. Bila ada pertanyaan izin lokasi - pilih 'Saat aplikasi digunakan'" -ForegroundColor Gray
Write-Host "     2. Buka beranda - kotak Cuaca ada di samping nama Admin" -ForegroundColor Gray
Write-Host "     3. Bila masih berbunyi 'Ketuk untuk memuat' - ketuk kotak itu" -ForegroundColor Gray
Write-Host "     4. Bila masih gagal: Pengaturan - Cuaca Beranda - SALIN KETERANGAN" -ForegroundColor Gray
Write-Host ""
