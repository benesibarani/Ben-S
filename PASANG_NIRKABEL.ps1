# =============================================================================
#  RTS PANEL BY BENE - PASANG & JALANKAN TANPA KABEL (PENELUSURAN NIRKABEL)
#  Berkas: PASANG_NIRKABEL.ps1
#
#  Dipakai bila kabel USB rusak / tidak ada. TIDAK memerlukan kabel sama sekali.
#  HP Bapak memakai Android 11, jadi sudah ada menu "Penelusuran nirkabel"
#  (Wireless debugging) yang resmi dari Google.
#
#  SKRIP INI TIDAK MEMBANGUN ULANG APLIKASI. Hanya memasang APK yang sudah jadi
#  (build\\app\\outputs\\flutter-apk\\app-debug.apk), jadi selesai 1-3 menit.
#
#  SYARAT:
#     1. HP dan komputer tersambung ke JARINGAN Wi-Fi YANG SAMA
#     2. Menu Opsi Pengembang sudah aktif di HP
#     3. Layar HP dalam keadaan terbuka (jangan dikunci) selama proses
#
#  CARA PAKAI:
#     1. Di HP: Pengaturan - Opsi pengembang - Penelusuran nirkabel -> AKTIFKAN
#     2. Di terminal VS Code:
#           powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1
#     3. Ikuti panduan di layar. Skrip akan meminta KODE 6 ANGKA yang tampil
#        di HP (sekali saja - setelah itu komputer selalu diingat HP)
#
#  Bila hanya ingin memeriksa sambungan tanpa memasang:
#           powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1 -HanyaPeriksa
# =============================================================================

param(
    [switch]$HanyaPeriksa
)

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
$kodePaket = "com.example.rts_panel_app"
$jalurApk = "build\app\outputs\flutter-apk\app-debug.apk"

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "== $teks" -ForegroundColor Cyan
}

function TulisPetunjuk($teks) {
    Write-Host "   $teks" -ForegroundColor Yellow
}

function TulisBiasa($teks) {
    Write-Host "   $teks" -ForegroundColor Gray
}

if (-not (Test-Path $proyek)) {
    Write-Host "Folder proyek tidak ditemukan: $proyek" -ForegroundColor Red
    exit 1
}

Set-Location $proyek

# =============================================================================
#  BAGIAN 1 - MENCARI adb.exe
# =============================================================================
TulisJudul "1. Mencari adb.exe (alat pemasang bawaan Android)"

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
    Write-Host "   adb.exe TIDAK ditemukan." -ForegroundColor Red
    Write-Host "   Kirimkan keluaran 'flutter doctor -v' ke saya." -ForegroundColor Yellow
    exit 1
}

Write-Host "   adb : $adb" -ForegroundColor Green

$versiAdb = (& $adb version 2>&1 | Select-Object -First 1)
Write-Host "   versi : $versiAdb" -ForegroundColor Gray

# =============================================================================
#  ALAT BANTU PEMBACAAN
# =============================================================================

# Membaca layanan nirkabel yang terlihat dari komputer ini.
# Android 11 menyiarkan dua layanan:
#    _adb-tls-pairing._tcp  -> dipakai saat memasangkan (ada kode 6 angka)
#    _adb-tls-connect._tcp  -> dipakai saat menyambung
function Ambil-Mdns {
    $hasil = @()
    try {
        $baris = & $adb mdns services 2>&1
        foreach ($b in $baris) {
            $t = "$b".Trim()
            if ($t -match "^(\S+)\s+(_adb-tls-pairing\._tcp|_adb-tls-connect\._tcp)\s+(\S+)$") {
                $hasil += [pscustomobject]@{
                    Nama    = $Matches[1]
                    Layanan = $Matches[2]
                    Alamat  = $Matches[3]
                }
            }
        }
    }
    catch { }
    return $hasil
}

# Membaca daftar perangkat yang benar-benar dikenal adb
function Ambil-Perangkat {
    $hasil = @()
    $baris = & $adb devices 2>&1
    foreach ($b in $baris) {
        $t = "$b".Trim()
        if ($t -match "^(\S+)\s+(device|unauthorized|offline)$") {
            $hasil += [pscustomobject]@{
                Serial = $Matches[1]
                Status = $Matches[2]
            }
        }
    }
    return $hasil
}

# Memasang APK ke perangkat tertentu
function Pasang-Apk($serial) {
    $jawab = & $adb -s $serial install -r -d $jalurApk 2>&1
    foreach ($b in $jawab) { Write-Host "   $b" }
    return ($jawab | Out-String)
}

# =============================================================================
#  BAGIAN 2 - MEMBERSIHKAN SAMBUNGAN LAMA YANG MATI
# =============================================================================
TulisJudul "2. Membersihkan sambungan nirkabel lama yang sudah mati"

Write-Host "   mematikan server adb..."
& $adb kill-server 2>&1 | Out-Null
Start-Sleep -Seconds 2

Write-Host "   memulai ulang server adb..."
& $adb start-server 2>&1 | Out-Null
Start-Sleep -Seconds 3

Write-Host "   memutus semua sambungan nirkabel lama..."
& $adb disconnect 2>&1 | ForEach-Object { if ($_) { Write-Host "   $_" } }
Start-Sleep -Seconds 2

Write-Host "   Selesai dibersihkan." -ForegroundColor Green
Write-Host "   (Inilah yang membuat percobaan sebelumnya gagal: adb masih mencari"
Write-Host "    alamat nirkabel lama 'adb-9909f35e-NbqoA0._adb-tls-connect._tcp'"
Write-Host "    yang sudah tidak ada.)" -ForegroundColor DarkGray

# =============================================================================
#  BAGIAN 3 - MELIHAT HP DI JARINGAN
# =============================================================================
TulisJudul "3. Mencari HP di jaringan Wi-Fi"

Write-Host "   menunggu 5 detik agar HP tersiar ulang..." -ForegroundColor DarkGray
Start-Sleep -Seconds 5

$layanan = Ambil-Mdns

if ($layanan.Count -eq 0) {
    Write-Host "   Belum ada layanan nirkabel yang terlihat." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Periksa di HP (berurutan):" -ForegroundColor White
    Write-Host "     a) Pengaturan - Opsi pengembang - Penelusuran nirkabel - AKTIF" -ForegroundColor Gray
    Write-Host "     b) HP dan komputer harus di Wi-Fi YANG SAMA (bukan tamu/guest)" -ForegroundColor Gray
    Write-Host "     c) Layar HP dibuka (jangan dikunci)" -ForegroundColor Gray
    Write-Host "     d) Bila Wi-Fi komputer bernama berbeda dari Wi-Fi HP - samakan dulu" -ForegroundColor Gray
    Write-Host "     e) Router dengan 'isolasi AP / Client isolation' menyala akan" -ForegroundColor Gray
    Write-Host "        menghalangi; matikan di pengaturan router" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Bila sudah diaktifkan, jalankan lagi skrip ini." -ForegroundColor Yellow
    Write-Host "   Skrip masih bisa lanjut dengan alamat yang diketik sendiri." -ForegroundColor DarkGray
}
else {
    foreach ($satu in $layanan) {
        Write-Host "   terlihat : $($satu.Nama)  $($satu.Layanan)  $($satu.Alamat)" -ForegroundColor Green
    }
}

# =============================================================================
#  BAGIAN 4 - BILA SUDAH ADA SAMBUNGAN YANG HIDUP, LANGSUNG PAKAI
# =============================================================================
$perangkat = Ambil-Perangkat
$kabel = @($perangkat | Where-Object { $_.Serial -notmatch ":\d+$" })
$nirkabel = @($perangkat | Where-Object { $_.Serial -match ":\d+$" })
$nirkabelSiap = @($nirkabel | Where-Object { $_.Status -eq "device" })

if ($nirkabelSiap.Count -ge 1) {
    TulisJudul "4. HP sudah tersambung nirkabel"
    Write-Host "   perangkat : $($nirkabelSiap[0].Serial) - siap" -ForegroundColor Green
    $serialPakai = $nirkabelSiap[0].Serial
}
else {
    # Coba sambung otomatis ke alamat yang tersiar di jaringan
    $alamatSambung = ($layanan | Where-Object { $_.Layanan -eq "_adb-tls-connect._tcp" } | Select-Object -First 1)

    if ($alamatSambung) {
        TulisJudul "4. Mencoba menyambung otomatis"
        Write-Host "   alamat : $($alamatSambung.Alamat)" -ForegroundColor Gray
        & $adb connect $alamatSambung.Alamat 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 3

        $perangkat = Ambil-Perangkat
        $nirkabelSiap = @($perangkat | Where-Object { $_.Status -eq "device" -and $_.Serial -match ":\d+$" })
    }

    if ($nirkabelSiap.Count -ge 1) {
        $serialPakai = $nirkabelSiap[0].Serial
        Write-Host "   Berhasil tersambung: $serialPakai" -ForegroundColor Green
    }
    else {
        # ---------------------------------------------------------------------
        #  Memasangkan untuk pertama kali (memakai kode 6 angka)
        # ---------------------------------------------------------------------
        TulisJudul "5. Memasangkan komputer dengan HP (sekali saja)"

        Write-Host "   Di LAYAR HP, lakukan ini:" -ForegroundColor White
        Write-Host "     1. Buka Pengaturan - Opsi pengembang - Penelusuran nirkabel" -ForegroundColor Gray
        Write-Host "     2. Ketuk 'Pasangkan perangkat dengan kode' (Pair device with pairing code)" -ForegroundColor Gray
        Write-Host "     3. Akan muncul: alamat IP:nomor, dan KODE 6 ANGKA" -ForegroundColor Gray
        Write-Host "     4. JANGAN tutup layar itu selama proses ini" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Kode itu hanya hidup beberapa menit, jadi kerjakan dengan cepat." -ForegroundColor Yellow
        Write-Host ""

        Read-Host "   Sudah terbuka di HP? Tekan Enter untuk lanjut"

        # Coba temukan alamat pemasangan secara otomatis
        Start-Sleep -Seconds 3
        $layanan2 = Ambil-Mdns
        $alamatPairing = ($layanan2 | Where-Object { $_.Layanan -eq "_adb-tls-pairing._tcp" } | Select-Object -First 1)

        if ($alamatPairing) {
            $alamatPakaiPairing = $alamatPairing.Alamat
            Write-Host "   alamat pemasangan ditemukan otomatis: $alamatPakaiPairing" -ForegroundColor Green
        }
        else {
            Write-Host "   Alamat tidak terdeteksi otomatis." -ForegroundColor Yellow
            Write-Host "   Ketik persis seperti yang tampil di HP, contoh: 192.168.1.7:43219" -ForegroundColor Gray
            $alamatPakaiPairing = (Read-Host "   Alamat IP:nomor dari layar HP").Trim()
        }

        if ([string]::IsNullOrWhiteSpace($alamatPakaiPairing)) {
            Write-Host "   Alamat kosong - dibatalkan." -ForegroundColor Red
            exit 1
        }

        $kode = (Read-Host "   Ketik 6 ANGKA yang tampil di HP").Trim()

        if ($kode -notmatch "^\d{6}$") {
            Write-Host "   Kode harus 6 angka. Yang diketik: '$kode'" -ForegroundColor Red
            Write-Host "   Tutup layar di HP, buka lagi 'Pasangkan perangkat dengan kode',"
            Write-Host "   lalu jalankan skrip ini kembali." -ForegroundColor Yellow
            exit 1
        }

        Write-Host ""
        Write-Host "   memasangkan..." -ForegroundColor Gray
        & $adb pair $alamatPakaiPairing $kode 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 3

        # Setelah dipasangkan, ambil alamat sambungnya
        Start-Sleep -Seconds 3
        $layanan3 = Ambil-Mdns
        $alamatConnect = ($layanan3 | Where-Object { $_.Layanan -eq "_adb-tls-connect._tcp" } | Select-Object -First 1)

        if ($alamatConnect) {
            Write-Host "   alamat sambung : $($alamatConnect.Alamat)" -ForegroundColor Gray
            & $adb connect $alamatConnect.Alamat 2>&1 | ForEach-Object { Write-Host "   $_" }
        }
        else {
            Write-Host "   Alamat sambung tidak terdeteksi otomatis." -ForegroundColor Yellow
            Write-Host "   Di layar utama 'Penelusuran nirkabel' ada tulisan IP address & Port." -ForegroundColor Gray
            Write-Host "   Contoh tampilannya: 192.168.1.7:37041" -ForegroundColor Gray
            $alamatManual = (Read-Host "   Ketik alamat itu").Trim()
            if (-not [string]::IsNullOrWhiteSpace($alamatManual)) {
                & $adb connect $alamatManual 2>&1 | ForEach-Object { Write-Host "   $_" }
            }
        }

        Start-Sleep -Seconds 4
        $perangkat = Ambil-Perangkat
        $nirkabelSiap = @($perangkat | Where-Object { $_.Status -eq "device" -and $_.Serial -match ":\d+$" })

        if ($nirkabelSiap.Count -ge 1) {
            $serialPakai = $nirkabelSiap[0].Serial
            Write-Host "   BERHASIL tersambung: $serialPakai" -ForegroundColor Green
        }
        else {
            Write-Host ""
            Write-Host "   Belum berhasil tersambung." -ForegroundColor Red
            Write-Host "   Keadaan perangkat sekarang:" -ForegroundColor Yellow
            & $adb devices -l 2>&1 | ForEach-Object { Write-Host "     $_" -ForegroundColor DarkGray }
            Write-Host ""
            Write-Host "   Bila tertulis 'offline' - tunggu 10 detik, lalu jalankan skrip lagi." -ForegroundColor Yellow
            Write-Host "   Bila 'unauthorized' - buka layar HP dan ketuk IZINKAN." -ForegroundColor Yellow
            Write-Host "   Bila 'failed to pair' - kode kedaluwarsa; buka layar kode baru di HP" -ForegroundColor Yellow
            Write-Host "   lalu jalankan skrip ini lagi." -ForegroundColor Yellow
            exit 1
        }
    }
}

# =============================================================================
#  BAGIAN 6 - KEADAAN AKHIR
# =============================================================================
TulisJudul "6. Keadaan sambungan"

& $adb devices -l 2>&1 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
Write-Host ""
Write-Host "   Perangkat yang dipakai: $serialPakai" -ForegroundColor Green

# Menyimpan catatan agar mudah dipakai lagi
$catatan = @()
$catatan += "RTS PANEL - CATATAN SAMBUNGAN NIRKABEL"
$catatan += "Dibuat: $(Get-Date -Format 'dd-MM-yyyy HH:mm')"
$catatan += ""
$catatan += "Nomor perangkat : $serialPakai"
$catatan += ""
$catatan += "Untuk menjalankan aplikasi dengan hot reload (tanpa kabel):"
$catatan += "    flutter run -d $serialPakai"
$catatan += ""
$catatan += "Untuk memasang ulang APK:"
$catatan += "    powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1"
$catatan += ""
$catatan += "PENTING: nomor di atas dapat berubah setiap HP dimatikan atau pindah jaringan."
$catatan += "Bila berubah, jalankan PASANG_NIRKABEL.ps1 lagi - skrip akan mencari nomor baru."
New-Item -ItemType File -Path "catatan_nirkabel.txt" -Force | Out-Null
$catatan -join "`r`n" | Set-Content -Path "catatan_nirkabel.txt" -Encoding UTF8
Write-Host "   Catatan disimpan: catatan_nirkabel.txt" -ForegroundColor Gray

if ($HanyaPeriksa) {
    TulisJudul "Selesai (hanya memeriksa)"
    Write-Host "Sambungan nirkabel siap. Untuk memasang, jalankan tanpa -HanyaPeriksa." -ForegroundColor Green
    exit 0
}

# =============================================================================
#  BAGIAN 7 - MEMERIKSA APK
# =============================================================================
TulisJudul "7. Memeriksa APK hasil build"

if (-not (Test-Path $jalurApk)) {
    Write-Host "   APK belum ada. Membangun sekarang (memakai cache, jadi lebih cepat)..." -ForegroundColor Yellow
    flutter build apk --debug
}

if (-not (Test-Path $jalurApk)) {
    Write-Host "   APK tetap tidak ada - kirimkan keluaran ini ke saya." -ForegroundColor Red
    exit 1
}

$ukuran = (Get-Item $jalurApk).Length / 1MB
Write-Host ("   ditemukan : $jalurApk ({0:N1} MB)" -f $ukuran) -ForegroundColor Green
Write-Host ("   dibuat    : " + (Get-Item $jalurApk).LastWriteTime.ToString("dd-MM-yyyy HH:mm")) -ForegroundColor Gray

# =============================================================================
#  BAGIAN 8 - MEMASANG
# =============================================================================
TulisJudul "8. Memasang aplikasi ke HP (nirkabel)"
Write-Host "   Tidak ada build ulang. Nirkabel memang lebih lambat dari kabel," -ForegroundColor Yellow
Write-Host "   jadi tunggu 2-5 menit. Layar HP harus tetap terbuka." -ForegroundColor Yellow
Write-Host ""

$hasilPasang = Pasang-Apk $serialPakai

if ($hasilPasang -match "Success") {
    Write-Host ""
    Write-Host "   APLIKASI BERHASIL DIPASANG." -ForegroundColor Green
}
elseif ($hasilPasang -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
    Write-Host ""
    Write-Host "   Ditolak: aplikasi versi lama memakai kunci berbeda." -ForegroundColor Red
    Write-Host "   PERINGATAN: aplikasi lama harus dihapus dahulu." -ForegroundColor Yellow
    Write-Host "   Akibatnya sesi login dan 'Ingat saya' ikut hilang - perlu login ulang." -ForegroundColor Yellow
    Write-Host ""
    $jawab = Read-Host "   Hapus aplikasi lama lalu pasang yang baru? (ketik Y lalu Enter)"
    if ($jawab -eq "Y" -or $jawab -eq "y") {
        & $adb -s $serialPakai uninstall $kodePaket 2>&1 | ForEach-Object { Write-Host "   $_" }
        Start-Sleep -Seconds 3
        $hasilPasang2 = Pasang-Apk $serialPakai
        if ($hasilPasang2 -match "Success") {
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
elseif ($hasilPasang -match "INSTALL_FAILED_INSUFFICIENT_STORAGE") {
    Write-Host ""
    Write-Host "   Ruang penyimpanan HP tidak cukup. Kosongkan sedikit lalu jalankan lagi." -ForegroundColor Red
    exit 1
}
elseif ($hasilPasang -match "device offline" -or $hasilPasang -match "device not found") {
    Write-Host ""
    Write-Host "   Sambungan terputus di tengah pemasangan (hal biasa pada nirkabel)." -ForegroundColor Red
    Write-Host "   Jalankan SKRIP INI LAGI - biasanya percobaan kedua berhasil." -ForegroundColor Yellow
    Write-Host "   Bila berulang: di Opsi pengembang HP, nyalakan 'Tetap terjaga saat mengisi daya'" -ForegroundColor Yellow
    Write-Host "   dan pastikan HP tidak masuk mode hemat daya." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host ""
    Write-Host "   Pemasangan belum berhasil - kirimkan keluaran di atas ke saya." -ForegroundColor Red
    exit 1
}

# =============================================================================
#  BAGIAN 9 - MEMBUKA APLIKASI
# =============================================================================
TulisJudul "9. Membuka aplikasi di HP"

& $adb -s $serialPakai shell am start -n "$kodePaket/.MainActivity" 2>&1 | ForEach-Object { Write-Host "   $_" }

Start-Sleep -Seconds 3

$cek = & $adb -s $serialPakai shell dumpsys window 2>&1 | Select-String $kodePaket
if (-not $cek) {
    Write-Host "   Memakai cara cadangan untuk membuka aplikasi..." -ForegroundColor Gray
    & $adb -s $serialPakai shell monkey -p $kodePaket -c android.intent.category.LAUNCHER 1 2>&1 | ForEach-Object { Write-Host "   $_" }
}

Write-Host "   Aplikasi dibuka di layar HP." -ForegroundColor Green

# =============================================================================
#  BAGIAN 10 - SELESAI
# =============================================================================
TulisJudul "SELESAI"

Write-Host "   Aplikasi RTS Panel sudah terpasang lewat NIRKABEL." -ForegroundColor Green
Write-Host ""
Write-Host "   Yang perlu diperiksa di HP:" -ForegroundColor White
Write-Host "     1. Layar login muncul, gambar latar terlihat" -ForegroundColor Gray
Write-Host "     2. Muncul pertanyaan 'Izinkan Notifikasi' - ketuk IZINKAN" -ForegroundColor Gray
Write-Host "     3. Login memakai username" -ForegroundColor Gray
Write-Host "     4. Menu Pengaturan - lihat kartu Firebase: apakah Aktif" -ForegroundColor Gray
Write-Host ""
Write-Host "   Untuk menjalankan dengan hot reload (tanpa kabel):" -ForegroundColor White
Write-Host "     flutter run -d $serialPakai" -ForegroundColor Cyan
Write-Host ""
Write-Host "   PENTING - agar tidak putus lagi:" -ForegroundColor White
Write-Host "     - Jangan matikan menu 'Penelusuran nirkabel' di HP" -ForegroundColor Gray
Write-Host "     - Nomor perangkat dapat berubah setelah HP dimatikan atau pindah Wi-Fi" -ForegroundColor Gray
Write-Host "     - Bila berubah: jalankan PASANG_NIRKABEL.ps1 lagi (cukup 1-3 menit)" -ForegroundColor Gray
Write-Host "     - Nomor tersimpan di catatan_nirkabel.txt" -ForegroundColor Gray
Write-Host ""
Write-Host "   Bila muncul pertanyaan Windows Firewall saat skrip berjalan," -ForegroundColor White
Write-Host "   pilih 'Allow Access' (izinkan) agar sambungan nirkabel lancar." -ForegroundColor Gray
