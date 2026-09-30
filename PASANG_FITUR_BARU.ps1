# =============================================================================
#  RTS PANEL BY BENE - PASANG FITUR BARU (IKON, IKLAN, PEMBARUAN OTOMATIS)
#  Berkas: PASANG_FITUR_BARU.ps1
#
#  Skrip ini mengerjakan SEMUA pekerjaan sisi Android secara otomatis:
#
#     1. Membuat ikon aplikasi RTS Panel (kotak marun + huruf R putih) untuk
#        semua ukuran layar, termasuk ikon adaptif Android 8 ke atas
#     2. Menambahkan izin iklan, izin LOKASI, dan kode aplikasi AdMob pada
#        AndroidManifest.xml
#     3. Memeriksa bahwa main.dart dan pubspec.yaml sudah versi terbaru
#     4. Memasang paket baru (flutter pub get)
#     5. Membangun dan menjalankan aplikasi
#
#  TIDAK ADA berkas yang perlu disalin ke dalam folder tertentu.
#
#  CARA PAKAI:
#     1. Ekstrak RTS_PANEL_FITUR_BARU.zip ke D:\Project\rts_panel_app
#        (pilih Timpa/Replace bila ditanya)
#     2. Sambungkan HP (kabel USB atau penelusuran nirkabel yang aktif)
#     3. Jalankan:
#          powershell -ExecutionPolicy Bypass -File .\PASANG_FITUR_BARU.ps1
#
#  Untuk memasang ikon dan izin SAJA, tanpa membangun:
#          powershell -ExecutionPolicy Bypass -File .\PASANG_FITUR_BARU.ps1 -TanpaBuild
# =============================================================================

param(
    [switch]$TanpaBuild
)

$ErrorActionPreference = "Continue"
$proyek = "D:\Project\rts_panel_app"
# Kode aplikasi AdMob milik Bapak (akun ca-app-pub-1905352530630884).
# Bila kode ini diganti, cukup ubah tulisan di dalam tanda kutip.
$kodeAplikasiAdmob = "ca-app-pub-1905352530630884~8932651962"
$folderCadangan = "cadangan_arena"

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

if (-not (Test-Path $folderCadangan)) {
    New-Item -ItemType Directory -Path $folderCadangan | Out-Null
}

$jalurManifest = "android\app\src\main\AndroidManifest.xml"
$folderRes = "android\app\src\main\res"

$bermasalah = 0

# =============================================================================
#  BAGIAN 1 - MEMERIKSA BERKAS BARU SUDAH ADA
# =============================================================================
TulisJudul "1. Memeriksa berkas aplikasi versi baru"

if (Test-Path "main.dart") {
    $isiMain = Get-Content "main.dart" -Raw

    $adaIklan = $isiMain -match "class RtsIklan"
    $adaCuaca = $isiMain -match "class RtsCuaca"
    $adaPembaruan = $isiMain -match "class RtsPembaruan"
    $adaBeranda = $isiMain -match "class _DashboardPageState"

    # Penanda kode aplikasi. Nilainya dicetak di sini supaya dapat dibandingkan
    # dengan yang tertulis pada halaman Pengaturan di HP sesudah aplikasi
    # dipasang. Bila berbeda, berarti yang terpasang masih build lama.
    $adaKode = $isiMain -match "rtsKodeAplikasi\s*=\s*'([^']+)'"
    $kodeAplikasi = "(tidak ditemukan)"

    if ($adaKode) {
        $kodeAplikasi = $Matches[1]
    }

    # Kotak cuaca versi baru: selalu tampil dan dapat diketuk.
    $adaKotakBaru = $isiMain -match "Ketuk untuk memuat"

    # Kartu pemeriksa cuaca pada halaman Pengaturan.
    $adaKartuDiag = $isiMain -match "class RtsKartuCuaca"

    # Tombol salin keterangan cuaca (untuk dikirim ke pengembang).
    $adaSalinDiag = $isiMain -match "SALIN KETERANGAN"

    TulisHasil $adaIklan "main.dart memuat modul iklan (RtsIklan)"
    TulisHasil $adaCuaca "main.dart memuat laporan cuaca (RtsCuaca)"
    TulisHasil $adaPembaruan "main.dart memuat pembaruan otomatis (RtsPembaruan)"
    TulisHasil $adaBeranda "main.dart memuat beranda baru (_DashboardPageState)"
    TulisHasil $adaKode "main.dart memuat penanda kode aplikasi"
    TulisHasil $adaKotakBaru "kotak cuaca versi baru (selalu tampil, dapat diketuk)"
    TulisHasil $adaKartuDiag "kartu pemeriksa Cuaca Beranda pada Pengaturan"
    TulisHasil $adaSalinDiag "tombol SALIN KETERANGAN cuaca"

    Write-Host ""
    Write-Host "   KODE APLIKASI pada main.dart : $kodeAplikasi" -ForegroundColor Cyan
    Write-Host "   Sesudah aplikasi dipasang ke HP, buka Pengaturan - bagian" -ForegroundColor DarkGray
    Write-Host "   'Cuaca Beranda'. Nilai pada kotak merah muda HARUS SAMA dengan" -ForegroundColor DarkGray
    Write-Host "   nilai di atas. Bila berbeda, yang terpasang masih build lama." -ForegroundColor DarkGray

    if (-not ($adaIklan -and $adaCuaca -and $adaPembaruan -and $adaBeranda -and $adaKode -and $adaKotakBaru)) {
        $bermasalah++
        Write-Host ""
        Write-Host "   main.dart BELUM versi terbaru." -ForegroundColor Red
        Write-Host "   Pastikan RTS_PANEL_FITUR_BARU.zip yang PALING BARU sudah" -ForegroundColor Yellow
        Write-Host "   diekstrak ke $proyek (pilih Timpa/Replace semua)." -ForegroundColor Yellow
    }
}
else {
    TulisHasil $false "main.dart tidak ditemukan"
    $bermasalah++
}

# -----------------------------------------------------------------------------
#  BAGIAN 1B - MEMASTIKAN lib\main.dart SAMA DENGAN main.dart
#
#  Flutter membangun aplikasi dari lib\main.dart. Bila hanya main.dart (akar)
#  yang diperbarui, build berhasil tetapi tampilan aplikasi TIDAK berubah -
#  inilah yang membuat perbaikan cuaca tidak tampak di HP.
# -----------------------------------------------------------------------------
TulisJudul "1b. Menyamakan lib\main.dart dengan main.dart"

function AmbilPenandaMain($jalur) {
    if (-not (Test-Path $jalur)) { return "" }

    $isi = Get-Content $jalur -Raw

    if ($isi -match "rtsKodeAplikasi\s*=\s*'([^']+)'") {
        return $Matches[1]
    }

    return ""
}

$kodeAkarMain = AmbilPenandaMain "main.dart"
$kodeLibMain = AmbilPenandaMain "lib\main.dart"

Write-Host "   main.dart (akar)     : $(if ($kodeAkarMain) { $kodeAkarMain } else { '(versi lama)' })" -ForegroundColor Gray
Write-Host "   lib\main.dart        : $(if ($kodeLibMain) { $kodeLibMain } else { '(versi lama)' })" -ForegroundColor Gray

if (-not (Test-Path "lib\main.dart")) {
    Write-Host ""
    Write-Host "   lib\main.dart TIDAK ADA." -ForegroundColor Red
    Write-Host "   Folder lib mungkin terhapus - hubungi pengembang." -ForegroundColor Yellow
    $bermasalah++
}
elseif ($kodeAkarMain -and $kodeAkarMain -ne $kodeLibMain) {
    $cadanganLib = "lib\main.dart.lama_" + (Get-Date -Format "yyyy-MM-dd_HHmmss")

    Copy-Item "lib\main.dart" $cadanganLib -Force

    if (Test-Path $cadanganLib) {
        Write-Host ""
        Write-Host "   Cadangan berkas lama : $cadanganLib" -ForegroundColor Green
        Copy-Item "main.dart" "lib\main.dart" -Force

        $kodeSetelahSalin = AmbilPenandaMain "lib\main.dart"

        if ($kodeSetelahSalin -eq $kodeAkarMain) {
            Write-Host "   DISALIN: lib\main.dart kini memuat kode $kodeSetelahSalin" -ForegroundColor Green
        }
        else {
            Write-Host "   Penyalinan ke lib\main.dart belum berhasil." -ForegroundColor Red
            $bermasalah++
        }
    }
    else {
        Write-Host "   Cadangan gagal dibuat - penyalinan dibatalkan." -ForegroundColor Red
        $bermasalah++
    }
}
else {
    Write-Host "   Sudah sama - tidak perlu disalin." -ForegroundColor Green
}

if (Test-Path "pubspec.yaml") {
    $isiPubspec = Get-Content "pubspec.yaml" -Raw

    TulisHasil ($isiPubspec -match "google_mobile_ads") "pubspec.yaml memuat google_mobile_ads"
    TulisHasil ($isiPubspec -match "package_info_plus") "pubspec.yaml memuat package_info_plus"

    if ($isiPubspec -match "version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)") {
        Write-Host "   Versi aplikasi pada pubspec: $($Matches[1]) (kode $($Matches[2]))" -ForegroundColor Gray
    }
}
else {
    TulisHasil $false "pubspec.yaml tidak ditemukan"
    $bermasalah++
}

if ($bermasalah -gt 0) {
    Write-Host ""
    Write-Host "   Ekstrak dulu RTS_PANEL_FITUR_BARU.zip ke $proyek, lalu jalankan lagi." -ForegroundColor Yellow
    exit 1
}

# =============================================================================
#  BAGIAN 2 - MEMBUAT IKON APLIKASI
# =============================================================================
TulisJudul "2. Membuat ikon aplikasi RTS Panel"

Add-Type -AssemblyName System.Drawing

function New-GrafikIkon($ukuran, $denganLatar) {
    $bmp = New-Object System.Drawing.Bitmap($ukuran, $ukuran)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    if ($denganLatar) {
        $garis = [int]($ukuran * 0.20)

        $jalur = New-Object System.Drawing.Drawing2D.GraphicsPath
        $jalur.AddArc(0, 0, $garis * 2, $garis * 2, 180, 90)
        $jalur.AddArc($ukuran - $garis * 2 - 1, 0, $garis * 2, $garis * 2, 270, 90)
        $jalur.AddArc($ukuran - $garis * 2 - 1, $ukuran - $garis * 2 - 1, $garis * 2, $garis * 2, 0, 90)
        $jalur.AddArc(0, $ukuran - $garis * 2 - 1, $garis * 2, $garis * 2, 90, 90)
        $jalur.CloseFigure()

        $kotak = New-Object System.Drawing.Rectangle(0, 0, $ukuran, $ukuran)
        $kuas = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            $kotak,
            [System.Drawing.ColorTranslator]::FromHtml("#8C1417"),
            [System.Drawing.ColorTranslator]::FromHtml("#5E0C0F"),
            45
        )

        $g.FillPath($kuas, $jalur)

        $kuas.Dispose()
        $jalur.Dispose()
    }

    # Huruf R putih di tengah.
    $tinggiHuruf = if ($denganLatar) { [float]($ukuran * 0.56) } else { [float]($ukuran * 0.42) }

    $font = New-Object System.Drawing.Font(
        "Arial",
        $tinggiHuruf,
        [System.Drawing.FontStyle]::Bold,
        [System.Drawing.GraphicsUnit]::Pixel
    )

    $format = New-Object System.Drawing.StringFormat
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $kotakTeks = New-Object System.Drawing.RectangleF(0, 0, $ukuran, $ukuran)

    $g.DrawString("R", $font, [System.Drawing.Brushes]::White, $kotakTeks, $format)

    $font.Dispose()
    $format.Dispose()
    $g.Dispose()

    return $bmp
}

$ukuranIkon = @{ "mdpi" = 48; "hdpi" = 72; "xhdpi" = 96; "xxhdpi" = 144; "xxxhdpi" = 192 }
$ukuranDepan = @{ "mdpi" = 108; "hdpi" = 162; "xhdpi" = 216; "xxhdpi" = 324; "xxxhdpi" = 432 }

foreach ($nama in $ukuranIkon.Keys) {
    $folder = Join-Path $folderRes "mipmap-$nama"

    if (-not (Test-Path $folder)) {
        New-Item -ItemType Directory -Path $folder | Out-Null
    }

    $ukuran = $ukuranIkon[$nama]

    $gambar = New-GrafikIkon $ukuran $true
    $gambar.Save((Join-Path $folder "ic_launcher.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $gambar.Save((Join-Path $folder "ic_launcher_round.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $gambar.Dispose()

    $ukuran2 = $ukuranDepan[$nama]
    $gambarDepan = New-GrafikIkon $ukuran2 $false
    $gambarDepan.Save((Join-Path $folder "ic_launcher_foreground.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $gambarDepan.Dispose()

    Write-Host "   dibuat  : mipmap-$nama (ikon $ukuran px, lapisan depan $ukuran2 px)" -ForegroundColor Green
}

# Latar ikon adaptif (gradasi marun) untuk Android 8 ke atas.
$folderDrawable = Join-Path $folderRes "drawable"
if (-not (Test-Path $folderDrawable)) {
    New-Item -ItemType Directory -Path $folderDrawable | Out-Null
}

$latarXml = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Latar ikon adaptif RTS Panel: marun bergradasi. -->
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:startColor="#8C1417"
        android:endColor="#5E0C0F"
        android:angle="315" />
</shape>
'@

Simpan-TanpaBom (Join-Path $folderDrawable "ic_launcher_background.xml") ($latarXml.TrimEnd() + "`r`n")

$folderAnydpi = Join-Path $folderRes "mipmap-anydpi-v26"
if (-not (Test-Path $folderAnydpi)) {
    New-Item -ItemType Directory -Path $folderAnydpi | Out-Null
}

$adaptifXml = @'
<?xml version="1.0" encoding="utf-8"?>
<!-- Ikon aplikasi RTS Panel untuk Android 8 ke atas. Bentuk luarnya diatur
     oleh peluncur HP, sehingga tampil rapi pada semua merek HP. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
'@

Simpan-TanpaBom (Join-Path $folderAnydpi "ic_launcher.xml") ($adaptifXml.TrimEnd() + "`r`n")
Simpan-TanpaBom (Join-Path $folderAnydpi "ic_launcher_round.xml") ($adaptifXml.TrimEnd() + "`r`n")

Write-Host "   dibuat  : ikon adaptif Android 8+" -ForegroundColor Green

# =============================================================================
#  BAGIAN 3 - MENAMBAHKAN IZIN DAN KODE ADMOB PADA MANIFEST
# =============================================================================
TulisJudul "3. Menyiapkan AndroidManifest.xml untuk iklan AdMob"

if (-not (Test-Path $jalurManifest)) {
    TulisHasil $false "AndroidManifest.xml tidak ditemukan"
    exit 1
}

Copy-Item $jalurManifest (Join-Path $folderCadangan "AndroidManifest.xml.asli") -Force
Write-Host "   dicadangkan: $jalurManifest" -ForegroundColor Gray

$isiManifest = Get-Content $jalurManifest -Raw
$isiAwal = $isiManifest

# --- Izin internet (wajib untuk aplikasi rilis) ---
if ($isiManifest -notmatch "android.permission.INTERNET") {
    $barisIzin = '    <uses-permission android:name="android.permission.INTERNET"/>' + "`r`n"
    $isiManifest = $isiManifest -replace "(?m)^(<manifest[^>]*>\s*\r?\n)", "`$1$barisIzin"
    Write-Host "   DITAMBAH: izin INTERNET"
}
else {
    Write-Host "   sudah ada: izin INTERNET" -ForegroundColor Gray
}

# --- Izin lokasi (untuk cuaca beranda dan tombol koordinat "Ganti Alamat") ---
# PENTING: plugin geolocator TIDAK menambahkan izin ini sendiri. Tanpa dua
# baris berikut, aplikasi tidak akan pernah mendapat izin lokasi, sehingga:
#   - laporan cuaca pada beranda tidak muncul
#   - tombol "Sesuai Koordinat Sekarang" gagal membaca titik GPS
$daftarIzinLokasi = @(
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION'
)

foreach ($izinLokasi in $daftarIzinLokasi) {
    if ($isiManifest -notmatch [regex]::Escape($izinLokasi)) {
        $barisLokasi = '    <uses-permission android:name="' + $izinLokasi + '"/>' + "`r`n"
        $isiManifest = $isiManifest -replace "(?m)^(<manifest[^>]*>\s*\r?\n)", "`$1$barisLokasi"
        Write-Host "   DITAMBAH: izin $izinLokasi" -ForegroundColor Green
    }
    else {
        Write-Host "   sudah ada: izin $izinLokasi" -ForegroundColor Gray
    }
}

# --- Izin kode iklan (Android 13 ke atas) ---
if ($isiManifest -notmatch "permission.AD_ID") {
    $barisAdId = '    <uses-permission android:name="com.google.android.gms.permission.AD_ID"/>' + "`r`n"
    $isiManifest = $isiManifest -replace "(?m)^(<manifest[^>]*>\s*\r?\n)", "`$1$barisAdId"
    Write-Host "   DITAMBAH: izin AD_ID (kode iklan Android 13+)" -ForegroundColor Green
}
else {
    Write-Host "   sudah ada: izin AD_ID" -ForegroundColor Gray
}

# --- Kode aplikasi AdMob (wajib; tanpa ini aplikasi langsung tertutup) ---
# Bila kode sudah ada (misalnya masih kode uji dari percobaan sebelumnya),
# nilainya DIPERBARUI menyesuaikan kode di bagian atas skrip ini.
$polaKodeAdmob = 'android:name="com\.google\.android\.gms\.ads\.APPLICATION_ID"\s+android:value="[^"]*"'

if ($isiManifest -match $polaKodeAdmob) {
    $kodeBaru = 'android:name="com.google.android.gms.ads.APPLICATION_ID"' + "`r`n" +
        '            android:value="' + $kodeAplikasiAdmob + '"'

    $isiManifest = $isiManifest -replace $polaKodeAdmob, $kodeBaru

    Write-Host "   DIPERBARUI: kode aplikasi AdMob menjadi $kodeAplikasiAdmob" -ForegroundColor Green
}
elseif ($isiManifest -notmatch "com.google.android.gms.ads.APPLICATION_ID") {
    $metaAdmob = @"
        <!-- Kode aplikasi AdMob RTS Panel. Nilai ini diambil dari variabel
             $kodeAplikasiAdmob pada bagian atas skrip PASANG_FITUR_BARU.ps1.
             Ganti di skrip itu, bukan langsung di berkas ini, supaya tidak
             tertimpa saat skrip dijalankan lagi. -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="$kodeAplikasiAdmob"/>
"@
    $isiManifest = $isiManifest -replace "(?m)^(\s*</application>)", "$metaAdmob`r`n`$1"
    Write-Host "   DITAMBAH: kode aplikasi AdMob $kodeAplikasiAdmob" -ForegroundColor Green
}

if ($isiManifest -ne $isiAwal) {
    Simpan-TanpaBom $jalurManifest $isiManifest
    Write-Host "   AndroidManifest.xml diperbarui." -ForegroundColor Green
}
else {
    Write-Host "   AndroidManifest.xml sudah lengkap." -ForegroundColor Green
}

# =============================================================================
#  BAGIAN 4 - MEMERIKSA HASIL
# =============================================================================
TulisJudul "4. Memeriksa hasil"

$isiManifestBaru = Get-Content $jalurManifest -Raw

TulisHasil ($isiManifestBaru -match "APPLICATION_ID") "kode aplikasi AdMob ada pada manifest"
TulisHasil ($isiManifestBaru -match "permission.AD_ID") "izin AD_ID ada pada manifest"
TulisHasil ($isiManifestBaru -match "android.permission.INTERNET") "izin INTERNET ada pada manifest"
TulisHasil ($isiManifestBaru -match "ACCESS_FINE_LOCATION") "izin lokasi ACCESS_FINE_LOCATION ada pada manifest"
TulisHasil ($isiManifestBaru -match "ACCESS_COARSE_LOCATION") "izin lokasi ACCESS_COARSE_LOCATION ada pada manifest"

foreach ($nama in $ukuranIkon.Keys) {
    $berkas = Join-Path $folderRes "mipmap-$nama\ic_launcher.png"
    if (-not (Test-Path $berkas)) {
        TulisHasil $false "ikon kurang: mipmap-$nama"
        $bermasalah++
    }
}

TulisHasil (Test-Path (Join-Path $folderRes "mipmap-anydpi-v26\ic_launcher.xml")) "ikon adaptif Android 8+"
TulisHasil (Test-Path "android\app\google-services.json") "google-services.json (Firebase)"

# Ikon bawaan Flutter harus sudah tergantikan.
$ikonBawaan = Join-Path $folderRes "mipmap-xxxhdpi\ic_launcher.png"
if (Test-Path $ikonBawaan) {
    $ukuranBerkas = (Get-Item $ikonBawaan).Length
    TulisHasil ($ukuranBerkas -gt 1500) "ikon 192 px tampak sudah tergantikan ($ukuranBerkas bita)"
}

Write-Host ""
if ($bermasalah -gt 0) {
    Write-Host "   ADA $bermasalah MASALAH - kirimkan seluruh tulisan ini ke saya." -ForegroundColor Red
    exit 1
}

Write-Host "   Ikon dan izin iklan SIAP." -ForegroundColor Green

if ($TanpaBuild) {
    TulisJudul "Selesai (tanpa build)"
    Write-Host "Jalankan tanpa -TanpaBuild untuk membangun dan memasang ke HP." -ForegroundColor Green
    exit 0
}

# =============================================================================
#  BAGIAN 5 - MEMASANG PAKET DAN MEMBANGUN
# =============================================================================
TulisJudul "5. Memasang paket baru (flutter pub get)"

flutter pub get

TulisJudul "6. Membangun dan menjalankan aplikasi"
Write-Host "   Build pertama dengan iklan memakan 10-20 menit. Jangan ditutup." -ForegroundColor Yellow
Write-Host ""

$keluaran = flutter devices
$keluaran

# Perangkat KABEL diutamakan; bila tidak ada (kabel rusak), dipakai
# perangkat NIRKABEL yang sedang tersambung.
$perangkatKabel = @()
$perangkatNirkabel = @()

$mesin = (flutter devices --machine) -join "`n"

try {
    $daftar = ConvertFrom-Json $mesin
    if ($daftar -isnot [array]) { $daftar = @($daftar) }

    foreach ($satu in $daftar) {
        if ($satu.targetPlatform -notmatch "^android") { continue }

        if ($satu.id -match "_adb-tls-connect" -or $satu.id -match ":\d+$") {
            $perangkatNirkabel += $satu.id
        }
        else {
            $perangkatKabel += $satu.id
        }
    }
}
catch {
    foreach ($baris in $keluaran) {
        if ($baris -match "adb-\S+") {
            if ($baris -match "_adb-tls-connect") { $perangkatNirkabel += $Matches[0] }
            else { $perangkatKabel += $Matches[0] }
        }
    }
}

$perangkat = @()

if ($perangkatKabel.Count -ge 1) {
    $perangkat = $perangkatKabel
    Write-Host "   Perangkat KABEL terdeteksi." -ForegroundColor Green
}
elseif ($perangkatNirkabel.Count -ge 1) {
    $perangkat = $perangkatNirkabel
    Write-Host "   Perangkat NIRKABEL terdeteksi (kabel tidak dipakai)." -ForegroundColor Green
}

if ($perangkat.Count -ge 1) {
    Write-Host "   Perangkat dipakai: $($perangkat[0])" -ForegroundColor Green
    flutter run -d $perangkat[0]
}
else {
    Write-Host "   Belum ada HP yang tersambung." -ForegroundColor Yellow
    Write-Host "   Karena kabel USB rusak, sambungkan lewat nirkabel lebih dahulu:" -ForegroundColor Yellow
    Write-Host "       powershell -ExecutionPolicy Bypass -File .\PASANG_NIRKABEL.ps1" -ForegroundColor Cyan
    Write-Host "   Setelah tersambung, jalankan lagi skrip ini." -ForegroundColor Yellow
}

TulisJudul "Selesai"
Write-Host "Bila masih gagal, salin 20 baris pertama yang berwarna merah." -ForegroundColor Green
