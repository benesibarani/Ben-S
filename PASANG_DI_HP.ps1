# =============================================================================
#  RTS PANEL BY BENE - PASANG APLIKASI KE HP
#  Berkas: PASANG_DI_HP.ps1
#
#  Dipakai ketika build SUDAH berhasil (file app-debug.apk sudah jadi), tetapi
#  pemasangan ke HP gagal, misalnya karena koneksi nirkabel terputus:
#
#     adb.exe: device '..._adb-tls-connect._tcp' not found
#     Error: ADB exited with exit code 1
#
#  Skrip ini memasang file APK yang sudah jadi ke HP yang terhubung,
#  jadi tidak perlu membangun ulang dari awal.
#
#  CARA PAKAI:
#    1. Sambungkan HP ke komputer memakai KABEL USB (lebih stabil daripada
#       nirkabel). Pada HP pilih mode "Transfer File", lalu setujui
#       "Izinkan penelusuran USB" bila muncul.
#    2. Simpan berkas ini di folder proyek:  D:\Project\rts_panel_app
#    3. Terminal VS Code, jalankan:
#         powershell -ExecutionPolicy Bypass -File .\PASANG_DI_HP.ps1
# =============================================================================

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
$paket  = "com.example.rts_panel_app"

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

# --- 1. Mulai ulang ADB --------------------------------------------------------
TulisJudul "1. Memulai ulang koneksi ADB"
adb kill-server 2>$null
adb start-server 2>$null
Write-Host "   Selesai."

# --- 2. Daftar perangkat -------------------------------------------------------
TulisJudul "2. Daftar perangkat yang terbaca"
adb devices -l

$perangkat = @()
foreach ($baris in (adb devices)) {
    if ($baris -match "^(\S+)\s+device") {
        $perangkat += $Matches[1]
    }
}

if ($perangkat.Count -eq 0) {
    Write-Host ""
    Write-Host "Tidak ada HP yang terbaca." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Periksa hal berikut:" -ForegroundColor Yellow
    Write-Host "  1. Kabel USB benar-benar tersambung (coba ganti lubang USB)."
    Write-Host "  2. Pada HP, pilih mode 'Transfer File' (bukan 'Hanya Mengisi Daya')."
    Write-Host "  3. Setujui pertanyaan 'Izinkan penelusuran USB?' pada layar HP."
    Write-Host "  4. Opsi Pengembang > Penelusuran USB (USB debugging) sudah aktif."
    Write-Host ""
    Write-Host "Setelah tersambung, jalankan lagi skrip ini." -ForegroundColor Yellow
    exit 1
}

# Bila lebih dari satu, pakai yang pertama dan beri tahu pengguna.
$target = $perangkat[0]

if ($perangkat.Count -gt 1) {
    Write-Host ""
    Write-Host "Terdapat $($perangkat.Count) perangkat. Yang dipakai: $target" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "Perangkat yang dipakai: $target" -ForegroundColor Green
}

# --- 3. Cari file APK yang sudah jadi ------------------------------------------
TulisJudul "3. Mencari file APK hasil build"

$kandidat = @(
    "build\app\outputs\flutter-apk\app-debug.apk",
    "build\app\outputs\apk\debug\app-debug.apk",
    "build\app\outputs\flutter-apk\app-release.apk"
)

$apk = $null
foreach ($jalur in $kandidat) {
    if (Test-Path $jalur) {
        $apk = $jalur
        break
    }
}

if (-not $apk) {
    Write-Host "   File APK belum ada. Membangun ulang (3-10 menit)..." -ForegroundColor Yellow
    flutter build apk --debug
    foreach ($jalur in $kandidat) {
        if (Test-Path $jalur) { $apk = $jalur; break }
    }
}

if (-not $apk) {
    Write-Host "   File APK tidak ditemukan. Salin pesan di atas dan kirimkan ke saya." -ForegroundColor Red
    exit 1
}

$ukuran = [math]::Round((Get-Item $apk).Length / 1MB, 1)
Write-Host "   Ditemukan: $apk  ($ukuran MB)" -ForegroundColor Green

# --- 4. Pasang ke HP -----------------------------------------------------------
TulisJudul "4. Memasang aplikasi ke HP"
Write-Host "   Proses ini 1-3 menit. Pada layar HP mungkin muncul pertanyaan" -ForegroundColor Yellow
Write-Host "   pemasangan - tekan Setuju / Instal." -ForegroundColor Yellow
Write-Host ""

adb -s $target install -r $apk

$hasil = $LASTEXITCODE

if ($hasil -ne 0) {
    Write-Host ""
    Write-Host "Pemasangan gagal (kode $hasil)." -ForegroundColor Red
    Write-Host "Coba cara berikut: salin file APK di atas ke HP (lewat kabel USB)," -ForegroundColor Yellow
    Write-Host "lalu buka file itu di HP dan tekan Instal." -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "Pemasangan berhasil." -ForegroundColor Green

# --- 5. Buka aplikasi di HP ----------------------------------------------------
TulisJudul "5. Membuka aplikasi di HP"

adb -s $target shell monkey -p $paket -c android.intent.category.LAUNCHER 1 2>$null

Write-Host ""
Write-Host "Aplikasi RTS Panel sudah terpasang dan dibuka di HP." -ForegroundColor Green
Write-Host "Silakan login memakai username dan password Bapak." -ForegroundColor Green

# --- 6. Penutup ----------------------------------------------------------------
TulisJudul "Catatan"
Write-Host "Untuk pengembangan dengan 'hot reload' (perubahan langsung terlihat"
Write-Host "tanpa pasang ulang), jalankan:"
Write-Host ""
Write-Host "    flutter run" -ForegroundColor Cyan
Write-Host ""
Write-Host "Sebaiknya memakai kabel USB. Koneksi nirkabel sering terputus ketika" -ForegroundColor Yellow
Write-Host "proses build berlangsung lama." -ForegroundColor Yellow
