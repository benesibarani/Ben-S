# =============================================================================
#  RTS PANEL BY BENE - PASANG APK YANG SUDAH JADI LEWAT KABEL USB
#  Berkas: PASANG_LEWAT_KABEL.ps1
#
#  KABAR BAIK: build sudah BERHASIL.
#     Build build\app\outputs\flutter-apk\app-debug.apk   (1416,3 detik)
#
#  Sisa satu langkah: memasang APK itu ke HP. Sebelumnya gagal karena
#  flutter memilih "CPH1937 (wireless)" - koneksi nirkabel yang sudah mati
#  (adb-tls-connect), padahal HP tidak terhubung kabel.
#
#  SKRIP INI TIDAK MEMBANGUN ULANG. Hanya memasang APK yang sudah ada.
#  Karena itu jalannya cepat (1-2 menit), bukan 23 menit.
#
#  CARA PAKAI:
#     1. Sambungkan HP ke komputer memakai KABEL USB
#     2. Di HP, pilih mode USB "Transfer file" (bukan "Hanya mengisi daya")
#     3. Bila muncul pertanyaan di HP "Izinkan penelusuran USB?" -> ketuk IZINKAN
#     4. Di terminal VS Code:
#           powershell -ExecutionPolicy Bypass -File .\PASANG_LEWAT_KABEL.ps1
#
#  Untuk melihat daftar perangkat SAJA (tanpa memasang):
#           powershell -ExecutionPolicy Bypass -File .\PASANG_LEWAT_KABEL.ps1 -HanyaPeriksa
# =============================================================================

param(
    [switch]$HanyaPeriksa
)

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
$kodePaket = "com.example.rts_panel_app"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

function TulisPetunjuk($teks) {
    Write-Host "   $teks" -ForegroundColor Yellow
}

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

# -----------------------------------------------------------------------------
# 1. Mencari adb.exe
# -----------------------------------------------------------------------------
TulisJudul "1. Mencari adb.exe (alat pemasang bawaan Android)"

$adb = $null
$kandidat = @()

# Dari berkas local.properties proyek (paling tepat)
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
    Write-Host "   adb.exe TIDAK ditemukan." -ForegroundColor Red
    Write-Host "   Kirimkan keluaran 'flutter doctor -v' ke saya." -ForegroundColor Yellow
    exit 1
}

Write-Host "   adb : $adb" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 2. Menutup koneksi nirkabel yang sudah mati
# -----------------------------------------------------------------------------
TulisJudul "2. Menutup koneksi nirkabel yang sudah mati"

Write-Host "   mematikan server adb..."
& $adb kill-server | Out-Null
Start-Sleep -Seconds 2

Write-Host "   memulai ulang server adb..."
& $adb start-server | Out-Null
Start-Sleep -Seconds 3

# adb disconnect tanpa nama akan memutus semua sambungan nirkabel
& $adb disconnect 2>&1 | ForEach-Object { if ($_) { Write-Host "   $_" } }
Start-Sleep -Seconds 2

Write-Host "   Koneksi nirkabel dibersihkan." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 3. Membaca daftar perangkat
# -----------------------------------------------------------------------------
TulisJudul "3. Membaca daftar perangkat yang terhubung"

$mentah = & $adb devices -l 2>&1

Write-Host "   Keluaran adb devices -l :" -ForegroundColor DarkGray
foreach ($b in $mentah) { Write-Host "     $b" -ForegroundColor DarkGray }

$kabel = @()
$nirkabel = @()

foreach ($b in $mentah) {
    if ([string]::IsNullOrWhiteSpace($b)) { continue }
    if ($b -match "List of devices") { continue }
    if ($b -match "^\s*\*\s") { continue }

    $bagian = ($b.Trim() -split "\s+")
    if ($bagian.Count -lt 2) { continue }

    $serial = $bagian[0]
    $status = $bagian[1]

    $catatan = [pscustomobject]@{ Serial = $serial; Status = $status; Baris = $b.Trim() }

    if ($serial -match "_adb-tls-connect" -or $serial -match ":\d+$") {
        $nirkabel += $catatan
    }
    else {
        $kabel += $catatan
    }
}

Write-Host ""
if ($kabel.Count -eq 0) {
    Write-Host "   Tidak ada perangkat KABEL terdeteksi." -ForegroundColor Red
}
else {
    foreach ($satu in $kabel) {
        if ($satu.Status -eq "device") {
            Write-Host "   KABEL    : $($satu.Serial) - siap dipakai" -ForegroundColor Green
        }
        elseif ($satu.Status -eq "unauthorized") {
            Write-Host "   KABEL    : $($satu.Serial) - BELUM DIIZINKAN di HP" -ForegroundColor Red
        }
        else {
            Write-Host "   KABEL    : $($satu.Serial) - keadaan '$($satu.Status)'" -ForegroundColor Yellow
        }
    }
}

foreach ($satu in $nirkabel) {
    Write-Host "   NIRKABEL : $($satu.Serial) - keadaan '$($satu.Status)'" -ForegroundColor DarkGray
}

# Perangkat kabel yang benar-benar siap
$siap = @($kabel | Where-Object { $_.Status -eq "device" })
$perluIzin = @($kabel | Where-Object { $_.Status -eq "unauthorized" })

# -----------------------------------------------------------------------------
# 4. Bila belum ada perangkat kabel - beri petunjuk jelas
# -----------------------------------------------------------------------------
if ($siap.Count -eq 0) {
    TulisJudul "Perangkat kabel belum siap - ikuti langkah berikut di HP"

    if ($perluIzin.Count -ge 1) {
        Write-Host "   HP SUDAH terbaca, tetapi belum diizinkan." -ForegroundColor Red
        Write-Host "   Lihat layar HP: akan ada pertanyaan" -ForegroundColor Yellow
        Write-Host "      'Izinkan penelusuran USB?'" -ForegroundColor Yellow
        Write-Host "   Ketuk IZINKAN (bila ada pilihan, centang 'Selalu izinkan dari komputer ini')." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Bila pertanyaannya tidak muncul:" -ForegroundColor Yellow
        Write-Host "      Cabut kabel, lalu tancapkan lagi." -ForegroundColor Yellow
        Write-Host "      Atau di HP: Opsi pengembang - Cabut otorisasi penelusuran USB, lalu tancapkan lagi." -ForegroundColor Yellow
    }
    else {
        Write-Host "   HP belum terbaca lewat kabel sama sekali. Periksa berurutan:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   1) KABEL" -ForegroundColor White
        Write-Host "      Pakai kabel data (kabel bawaan HP). Sebagian kabel hanya untuk mengisi daya." -ForegroundColor Gray
        Write-Host ""
        Write-Host "   2) MODE USB DI HP" -ForegroundColor White
        Write-Host "      Setelah kabel ditancapkan, tarik bilah atas HP dan ketuk pemberitahuan USB," -ForegroundColor Gray
        Write-Host "      lalu pilih 'Transfer file' / 'MTP'." -ForegroundColor Gray
        Write-Host "      Bila hanya 'Mengisi daya', komputer tidak akan melihat HP." -ForegroundColor Gray
        Write-Host ""
        Write-Host "   3) PENELUSURAN USB DI HP" -ForegroundColor White
        Write-Host "      Pengaturan - Tentang ponsel - ketuk 'Nomor bentukan' 7 kali" -ForegroundColor Gray
        Write-Host "      Pengaturan - Opsi pengembang - aktifkan 'Penelusuran USB'" -ForegroundColor Gray
        Write-Host "      Pengaturan - Opsi pengembang - MATIKAN 'Penelusuran nirkabel' (agar tidak tertukar)" -ForegroundColor Gray
        Write-Host "      Pengaturan - Opsi pengembang - 'Pilih konfigurasi USB default' - pilih Transfer file" -ForegroundColor Gray
        Write-Host ""
        Write-Host "   4) IZINKAN DI LAYAR HP" -ForegroundColor White
        Write-Host "      Akan muncul 'Izinkan penelusuran USB?' - ketuk IZINKAN." -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "   Setelah itu jalankan lagi skrip ini:" -ForegroundColor Cyan
    Write-Host "      powershell -ExecutionPolicy Bypass -File .\PASANG_LEWAT_KABEL.ps1" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Catatan: APK sudah jadi, jadi tidak ada build ulang." -ForegroundColor Green
    exit 1
}

Write-Host "   Perangkat siap: $($siap[0].Serial)" -ForegroundColor Green

# -----------------------------------------------------------------------------
# 5. Memeriksa berkas APK
# -----------------------------------------------------------------------------
TulisJudul "5. Memeriksa berkas APK hasil build tadi"

$apk = "build\app\outputs\flutter-apk\app-debug.apk"

if (-not (Test-Path $apk)) {
    Write-Host "   APK tidak ditemukan di $apk" -ForegroundColor Red
    Write-Host "   Membangun ulang (memakai cache Gradle, jadi lebih cepat)..." -ForegroundColor Yellow
    flutter build apk --debug
}

if (-not (Test-Path $apk)) {
    Write-Host "   APK tetap tidak ada - kirimkan keluaran ini ke saya." -ForegroundColor Red
    exit 1
}

$ukuran = (Get-Item $apk).Length / 1MB
Write-Host ("   ditemukan: $apk ({0:N1} MB)" -f $ukuran) -ForegroundColor Green
Write-Host ("   waktu dibuat: " + (Get-Item $apk).LastWriteTime.ToString("dd-MM-yyyy HH:mm")) -ForegroundColor Gray

if ($HanyaPeriksa) {
    TulisJudul "Selesai (hanya memeriksa)"
    Write-Host "Perangkat dan APK siap. Untuk memasang, jalankan tanpa -HanyaPeriksa." -ForegroundColor Green
    exit 0
}

# -----------------------------------------------------------------------------
# 6. Memasang APK
# -----------------------------------------------------------------------------
$serial = $siap[0].Serial

TulisJudul "6. Memasang aplikasi ke HP ($serial)"
Write-Host "   Tidak ada build ulang. Hanya pemasangan. Tunggu 1-2 menit..." -ForegroundColor Yellow
Write-Host ""

$pasang = & $adb -s $serial install -r -d $apk 2>&1
foreach ($b in $pasang) { Write-Host "   $b" }

$teksPasang = ($pasang | Out-String)

if ($teksPasang -match "Success") {
    Write-Host ""
    Write-Host "   APLIKASI BERHASIL DIPASANG." -ForegroundColor Green
}
elseif ($teksPasang -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
    Write-Host ""
    Write-Host "   Pemasangan ditolak karena aplikasi versi lama memakai kunci berbeda." -ForegroundColor Red
    Write-Host "   PERINGATAN: aplikasi lama harus dihapus lebih dulu." -ForegroundColor Yellow
    Write-Host "   Akibatnya sesi login dan pengaturan 'Ingat saya' ikut hilang - perlu login ulang." -ForegroundColor Yellow
    Write-Host ""
    $jawab = Read-Host "   Hapus aplikasi lama lalu pasang yang baru? (ketik Y lalu Enter)"
    if ($jawab -eq "Y" -or $jawab -eq "y") {
        & $adb -s $serial uninstall $kodePaket 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 2
        $pasang2 = & $adb -s $serial install -r -d $apk 2>&1
        foreach ($b in $pasang2) { Write-Host "   $b" }
        if (($pasang2 | Out-String) -match "Success") {
            Write-Host "   APLIKASI BERHASIL DIPASANG." -ForegroundColor Green
        }
        else {
            Write-Host "   Masih gagal - kirimkan keluaran ini ke saya." -ForegroundColor Red
            exit 1
        }
    }
    else {
        Write-Host "   Dibatalkan. Aplikasi lama tetap utuh." -ForegroundColor Yellow
        exit 1
    }
}
elseif ($teksPasang -match "INSTALL_FAILED_INSUFFICIENT_STORAGE") {
    Write-Host ""
    Write-Host "   Ruang penyimpanan HP tidak cukup. Kosongkan sedikit lalu jalankan lagi." -ForegroundColor Red
    exit 1
}
else {
    Write-Host ""
    Write-Host "   Pemasangan belum berhasil - kirimkan keluaran di atas ke saya." -ForegroundColor Red
    exit 1
}

# -----------------------------------------------------------------------------
# 7. Menjalankan aplikasi
# -----------------------------------------------------------------------------
TulisJudul "7. Menjalankan aplikasi di HP"

& $adb -s $serial shell am start -n "$kodePaket/.MainActivity" 2>&1 | ForEach-Object { Write-Host "   $_" }

Start-Sleep -Seconds 2

# Bila cara di atas gagal, pakai cara cadangan
$cek = & $adb -s $serial shell dumpsys window 2>&1 | Select-String $kodePaket
if (-not $cek) {
    Write-Host "   Memakai cara cadangan untuk membuka aplikasi..." -ForegroundColor Gray
    & $adb -s $serial shell monkey -p $kodePaket -c android.intent.category.LAUNCHER 1 2>&1 | ForEach-Object { Write-Host "   $_" }
}

Write-Host "   Aplikasi dibuka di layar HP." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Selesai
# -----------------------------------------------------------------------------
TulisJudul "SELESAI"

Write-Host "   Aplikasi RTS Panel sudah terpasang dan terbuka di HP Bapak." -ForegroundColor Green
Write-Host ""
Write-Host "   Yang perlu diperiksa di HP:" -ForegroundColor White
Write-Host "     1. Layar login muncul" -ForegroundColor Gray
Write-Host "     2. Muncul pertanyaan 'Izinkan Notifikasi' - ketuk IZINKAN" -ForegroundColor Gray
Write-Host "     3. Login dengan username, lalu buka Pengaturan" -ForegroundColor Gray
Write-Host "     4. Di kartu Pengaturan lihat tulisan 'Firebase:' apakah Aktif" -ForegroundColor Gray
Write-Host ""
Write-Host "   Bila ingin melihat catatan aplikasi (log) sekaligus hot reload," -ForegroundColor White
Write-Host "   jalankan perintah ini (build sudah hangat, jadi cepat):" -ForegroundColor White
Write-Host "     flutter run -d $serial" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Nomor perangkat kabel Bapak: $serial" -ForegroundColor Cyan
Write-Host "   (Catat: selalu pakai -d $serial supaya tidak tertukar ke nirkabel lagi)" -ForegroundColor Gray
