# =============================================================================
#  RTS PANEL BY BENE - PERIKSA KODE APLIKASI
#  Berkas : PERIKSA_KODE_APLIKASI.ps1
#
#  KEGUNAAN
#  --------
#  Memeriksa ISI folder D:\Project\rts_panel_app SEBELUM membangun aplikasi,
#  tanpa mengubah apa pun. Skrip ini menjawab pertanyaan:
#
#      "Apakah folder proyek saya sudah berisi kode paling baru?"
#
#  Skrip ini TIDAK menghapus, TIDAK memindahkan, dan TIDAK mengubah berkas.
#  Aman dijalankan berkali-kali.
#
#  CARA PAKAI
#  ----------
#  1. Buka PowerShell DI DALAM folder D:\Project\rts_panel_app
#     (cara: buka foldernya, tekan Shift + klik kanan pada ruang kosong,
#            pilih "Open PowerShell window here" / "Open in Terminal")
#  2. Jalankan:   .\PERIKSA_KODE_APLIKASI.ps1
#  3. Baca hasilnya. Bila ada yang [BELUM], ikuti petunjuk pada bagian akhir.
#
#  PENTING - JANGAN MENGHAPUS FOLDER PROYEK
#  ----------------------------------------
#  Folder proyek memuat berkas yang TIDAK ada di dalam paket zip, misalnya:
#      android\app\google-services.json   (penghubung Firebase)
#      assets\images\...                  (gambar latar login & beranda)
#      android\ ...                       (susunan Gradle yang sudah benar)
#  Menghapus folder membuat berkas-berkas itu hilang dan build akan gagal.
#  Cara yang benar: TIMPA berkas dari paket, lalu bersihkan hasil build lama
#  dengan perintah "flutter clean".
# =============================================================================

$harapanKode = 'RTS-2026-09-30-8'

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  $teks" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
}

function TulisHasil($ok, $teks) {
    if ($ok) {
        Write-Host "   [ADA]   $teks" -ForegroundColor Green
    }
    else {
        Write-Host "   [BELUM] $teks" -ForegroundColor Yellow
    }
}

$bermasalah = 0

Write-Host ""
Write-Host "RTS PANEL BY BENE - PEMERIKSA KODE APLIKASI" -ForegroundColor Cyan
Write-Host "Skrip ini tidak mengubah apa pun. Aman dijalankan berkali-kali." -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 0. Memastikan dijalankan pada folder yang benar
# -----------------------------------------------------------------------------
TulisJudul "0. Letak folder"

Write-Host "   Folder sekarang: $(Get-Location)" -ForegroundColor Gray

$adaPubspec = Test-Path "pubspec.yaml"
$adaMain = Test-Path "main.dart"
$adaLib = Test-Path "lib\main.dart"
$adaAndroid = Test-Path "android"

TulisHasil $adaPubspec "pubspec.yaml"
TulisHasil $adaMain "main.dart (akar folder - berkas dari paket)"
TulisHasil $adaLib "lib\main.dart (BERKAS YANG DIBANGUN FLUTTER)"
TulisHasil $adaAndroid "folder android (WAJIB - tidak ada di dalam paket zip)"

if (-not ($adaPubspec -and $adaMain)) {
    Write-Host ""
    Write-Host "   Skrip ini dijalankan pada folder yang SALAH." -ForegroundColor Red
    Write-Host "   Buka PowerShell di dalam D:\Project\rts_panel_app, lalu ulangi." -ForegroundColor Yellow
    exit 1
}

if (-not $adaAndroid) {
    $bermasalah++
    Write-Host ""
    Write-Host "   Folder android TIDAK ADA. Jangan lanjut membangun aplikasi." -ForegroundColor Red
    Write-Host "   Kemungkinan folder ini bukan proyek Flutter, atau folder android" -ForegroundColor Yellow
    Write-Host "   pernah terhapus. Hubungi pengembang sebelum melanjutkan." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 1. Penanda kode aplikasi pada main.dart DAN lib\main.dart
#
# PENTING: Flutter membangun aplikasi dari lib\main.dart, bukan dari main.dart
# yang ada di akar folder proyek. Bila hanya main.dart (akar) yang baru,
# tampilan aplikasi TIDAK berubah walaupun build berhasil.
# -----------------------------------------------------------------------------
TulisJudul "1. Kode aplikasi pada main.dart dan lib\main.dart"

function AmbilPenanda($jalur) {
    if (-not (Test-Path $jalur)) { return "" }

    $isi = Get-Content $jalur -Raw

    if ($isi -match "rtsKodeAplikasi\s*=\s*'([^']+)'") {
        return $Matches[1]
    }

    return ""
}

$kodeAkarFile = AmbilPenanda "main.dart"
$kodeLibFile = AmbilPenanda "lib\main.dart"

Write-Host ""
Write-Host "   Kode pada main.dart       : $(if ($kodeAkarFile) { $kodeAkarFile } else { '(tidak ada penanda / versi lama)' })" -ForegroundColor Gray
Write-Host "   Kode pada lib\main.dart   : $(if ($kodeLibFile) { $kodeLibFile } else { '(tidak ada penanda / versi lama)' })" -ForegroundColor Gray
Write-Host "   Diharapkan                : $harapanKode" -ForegroundColor Cyan
Write-Host ""

if ($kodeLibFile -ne $harapanKode) {
    $bermasalah++
    Write-Host "   [PERHATIAN] lib\main.dart BELUM versi terbaru!" -ForegroundColor Red
    Write-Host "   Inilah sebabnya tampilan aplikasi tidak berubah di HP." -ForegroundColor Yellow
    Write-Host "   Jalankan:  .\PASANG_MAIN_DART.ps1" -ForegroundColor Yellow
    Write-Host "   (skrip itu menyalin main.dart ke lib\main.dart, dengan cadangan)" -ForegroundColor DarkGray
}

$isiMain = Get-Content "main.dart" -Raw
$kodeAplikasi = $kodeAkarFile
$adaKode = ($kodeAplikasi -ne "")

$infoMain = Get-Item "main.dart"
$ukuranMain = [math]::Round($infoMain.Length / 1024)

Write-Host "   Ukuran        : $ukuranMain KB ($($infoMain.Length) bita)" -ForegroundColor Gray
Write-Host "   Terakhir ubah : $($infoMain.LastWriteTime)" -ForegroundColor Gray
Write-Host ""
Write-Host "   KODE APLIKASI : $kodeAplikasi" -ForegroundColor Cyan
Write-Host "   DIHARAPKAN    : $harapanKode" -ForegroundColor Cyan
Write-Host ""

if ($kodeAplikasi -eq $harapanKode) {
    Write-Host "   [BENAR] main.dart sudah versi terbaru." -ForegroundColor Green
}
else {
    $bermasalah++
    Write-Host "   [SALAH] main.dart BELUM versi terbaru." -ForegroundColor Red
    Write-Host "   Artinya: berkas main.dart dari paket baru belum ditimpa ke" -ForegroundColor Yellow
    Write-Host "   folder ini. Ekstrak ulang RTS_PANEL_FITUR_BARU.zip ke folder" -ForegroundColor Yellow
    Write-Host "   ini dan pilih TIMPA / Replace semua." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 2. Bagian-bagian penting di dalam main.dart
# -----------------------------------------------------------------------------
TulisJudul "2. Isi main.dart"

$bagian = @(
    @{ Nama = "laporan cuaca (RtsCuaca)";                  Pola = "class RtsCuaca" },
    @{ Nama = "kotak cuaca baru (Ketuk untuk memuat)";     Pola = "Ketuk untuk memuat" },
    @{ Nama = "kartu pemeriksa Cuaca Beranda";             Pola = "class RtsKartuCuaca" },
    @{ Nama = "tombol SALIN KETERANGAN cuaca";             Pola = "SALIN KETERANGAN" },
    @{ Nama = "permintaan izin lokasi";                    Pola = "requestPermission" },
    @{ Nama = "pesan pembaruan yang jelas";                Pola = "belumAdaVersi" },
    @{ Nama = "modul iklan (RtsIklan)";                    Pola = "class RtsIklan" },
    @{ Nama = "pembaruan otomatis (RtsPembaruan)";         Pola = "class RtsPembaruan" },
    @{ Nama = "beranda baru (_DashboardPageState)";        Pola = "class _DashboardPageState" },
    @{ Nama = "aturan iklan akun PRO";                     Pola = "RtsTingkatAkun" }
)

foreach ($satu in $bagian) {
    $adaBagian = $isiMain -match [regex]::Escape($satu.Pola)

    TulisHasil $adaBagian $satu.Nama

    if (-not $adaBagian) {
        $bermasalah++
    }
}

# -----------------------------------------------------------------------------
# 3. Paket pada pubspec.yaml
# -----------------------------------------------------------------------------
TulisJudul "3. Paket pada pubspec.yaml"

$isiPubspec = Get-Content "pubspec.yaml" -Raw

$paket = @(
    "geolocator",
    "geocoding",
    "google_mobile_ads",
    "package_info_plus",
    "shared_preferences",
    "http:",
    "firebase_core",
    "firebase_messaging",
    "url_launcher"
)

foreach ($satu in $paket) {
    $adaPaket = $isiPubspec -match [regex]::Escape($satu)

    TulisHasil $adaPaket "paket $satu"

    if (-not $adaPaket) {
        $bermasalah++
    }
}

$versiPubspec = "(tidak terbaca)"

if ($isiPubspec -match "(?m)^version:\s*(\S+)") {
    $versiPubspec = $Matches[1]
}

Write-Host ""
Write-Host "   Versi aplikasi pada pubspec.yaml : $versiPubspec" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 4. Izin pada AndroidManifest.xml
# -----------------------------------------------------------------------------
TulisJudul "4. Izin pada AndroidManifest.xml"

$jalurManifest = "android\app\src\main\AndroidManifest.xml"

if (Test-Path $jalurManifest) {
    $isiManifest = Get-Content $jalurManifest -Raw

    $izin = @(
        @{ Nama = "ACCESS_FINE_LOCATION (lokasi tepat)";     Pola = "ACCESS_FINE_LOCATION" },
        @{ Nama = "ACCESS_COARSE_LOCATION (lokasi perkiraan)"; Pola = "ACCESS_COARSE_LOCATION" },
        @{ Nama = "INTERNET";                                Pola = "android.permission.INTERNET" },
        @{ Nama = "POST_NOTIFICATIONS (pemberitahuan)";      Pola = "POST_NOTIFICATIONS" },
        @{ Nama = "AD_ID (iklan)";                           Pola = "permission.AD_ID" },
        @{ Nama = "kode aplikasi AdMob";                     Pola = "APPLICATION_ID" }
    )

    foreach ($satu in $izin) {
        $adaIzin = $isiManifest -match [regex]::Escape($satu.Pola)

        TulisHasil $adaIzin $satu.Nama

        if (-not $adaIzin) {
            $bermasalah++
        }
    }
}
else {
    TulisHasil $false "AndroidManifest.xml tidak ditemukan pada $jalurManifest"
    $bermasalah++
}

# -----------------------------------------------------------------------------
# 5. Berkas penting lain (tidak ada di dalam paket zip)
# -----------------------------------------------------------------------------
TulisJudul "5. Berkas penting lain pada folder proyek"

$lain = @(
    @{ Nama = "android\app\google-services.json (Firebase)"; Jalur = "android\app\google-services.json" },
    @{ Nama = "assets (gambar latar)";                       Jalur = "assets" },
    @{ Nama = "lib (folder program)";                        Jalur = "lib" }
)

foreach ($satu in $lain) {
    TulisHasil (Test-Path $satu.Jalur) $satu.Nama
}

# -----------------------------------------------------------------------------
# 6. Kesimpulan dan langkah berikutnya
# -----------------------------------------------------------------------------
TulisJudul "KESIMPULAN"

if ($bermasalah -eq 0) {
    Write-Host "   SEMUA BENAR. Folder proyek sudah memuat kode terbaru." -ForegroundColor Green
    Write-Host ""
    Write-Host "   Langkah berikutnya:" -ForegroundColor White
    Write-Host "     1. flutter clean                 (bersihkan hasil build lama)" -ForegroundColor Gray
    Write-Host "     2. .\PERBAIKI_PUBSPEC.ps1        (daftarkan paket)" -ForegroundColor Gray
    Write-Host "     3. .\PASANG_FITUR_BARU.ps1       (bangun + pasang ke HP)" -ForegroundColor Gray
}
else {
    Write-Host "   ADA $bermasalah hal yang belum benar (lihat tanda [BELUM] di atas)." -ForegroundColor Red
    Write-Host ""
    Write-Host "   Langkah perbaikan - JANGAN MENGHAPUS FOLDER PROYEK:" -ForegroundColor White
    Write-Host "     1. Ekstrak ulang RTS_PANEL_FITUR_BARU.zip ke folder ini" -ForegroundColor Gray
    Write-Host "        (pilih TIMPA / Replace semua berkas yang ditanya)" -ForegroundColor Gray
    Write-Host "     2. Jalankan skrip ini lagi - semua harus [ADA]" -ForegroundColor Gray
    Write-Host "     3. flutter clean" -ForegroundColor Gray
    Write-Host "     4. .\PERBAIKI_PUBSPEC.ps1" -ForegroundColor Gray
    Write-Host "     5. .\PASANG_FITUR_BARU.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   MENGAPA TIDAK BOLEH MENGHAPUS FOLDER:" -ForegroundColor Yellow
    Write-Host "     Paket zip TIDAK memuat folder android, assets, dan lib." -ForegroundColor Yellow
    Write-Host "     Bila folder dihapus, google-services.json (Firebase) dan" -ForegroundColor Yellow
    Write-Host "     gambar latar akan hilang, sehingga build gagal." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "   Pemeriksaan selesai. Tidak ada berkas yang diubah." -ForegroundColor DarkGray
Write-Host ""
