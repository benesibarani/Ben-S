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
#  Pemeriksaan pada putaran ini ditambah:
#     - lib\kasir.dart, lib\kasir_lokal.dart, dan lib\peta.dart: panjang
#       berkas, jumlah baris, dan KESEIMBANGAN KURUNG. Berkas yang terpotong
#       (misalnya karena salinan yang tidak lengkap) selalu menyisakan kurung
#       tidak berpasangan - jadi hal itu ketahuan SEBELUM membangun aplikasi.
#     - lib\peta.dart: halaman Peta Customer / Radar / Rute Plan / Lokasi
#       Kantor, ubin OpenStreetMap, penyaring warna, alat pensil, dan salin
#       daftar plan.
#     - langkah 6a: memeriksa analysis_options.yaml (berkas pengaturan yang
#       menyuruh pemeriksa kode melewati salinan main.dart di akar folder,
#       supaya tanda merah palsu "Target of URI doesn't exist" tidak muncul).
#     - langkah 6e: menjalankan  flutter analyze  - memeriksa GALAT KODE
#       (jenis nilai yang tidak cocok, nama yang salah tulis) dalam hitungan
#       detik, tanpa perlu membangun aplikasi. Kesalahan seperti
#       "A value of type 'String' can't be assigned to a variable of type
#       'TextEditingController'" ketahuan di sini, bukan sesudah 3-4 menit
#       menunggu build.
#     - pubspec.yaml: paket penunjang kasir luring (sqflite dll).
#     - android\app\build.gradle.kts: angka compileSdk (harus 37).
#     - berkas Kotlin: jumlah MainActivity.kt (harus SATU) dan tanda +
#       yang diletakkan di awal baris (Kotlin tidak mengizinkannya).
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

$harapanKode = 'RTS-2026-10-03-15'

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
    Write-Host "   Jalankan:  .\LANGKAH1_PASANG_SEMUA.ps1 dari paket terbaru" -ForegroundColor Yellow
    Write-Host "   (skrip itu menyalin main.dart ke lib\main.dart, dengan cadangan)" -ForegroundColor DarkGray
}

Write-Host "   CATATAN: main.dart di akar folder hanya SALINAN ACUAN." -ForegroundColor DarkGray
Write-Host "            Berkas yang dibangun Flutter adalah lib\main.dart." -ForegroundColor DarkGray
Write-Host "            Karena itu tanda merah di VS Code pada main.dart (akar)" -ForegroundColor DarkGray
Write-Host "            TIDAK mempengaruhi hasil build." -ForegroundColor DarkGray
Write-Host ""

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
    @{ Nama = "aturan iklan akun PRO";                     Pola = "RtsTingkatAkun" },
    @{ Nama = "tombol SINKRON AKUN (menu Sinkronisasi)";   Pola = "SINKRON AKUN" },
    @{ Nama = "status PRO diperiksa ulang saat app dibuka"; Pola = "_periksaHakPro" },
    @{ Nama = "penyegar status akun (tanya ke server)";    Pola = "class RtsAkunSegar" }
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
# 6. Berkas KASIR LURING (kasir.dart & kasir_lokal.dart)
# -----------------------------------------------------------------------------
TulisJudul "6. Berkas kasir luring (kasir.dart & kasir_lokal.dart)"

function Periksa-KurungDart($jalur) {
    # Membersihkan komentar dan tulisan di dalam tanda kutip, lalu menghitung
    # jumlah kurung. Berkas yang TERPOTONG selalu menyisakan kurung yang
    # tidak berpasangan, sehingga hal itu dapat diketahui lebih dahulu.
    $isi = [System.IO.File]::ReadAllText($jalur)
    $bersih = New-Object System.Text.StringBuilder
    $i = 0
    $n = $isi.Length

    while ($i -lt $n) {
        $c = $isi[$i]

        if ($c -eq '/' -and ($i + 1) -lt $n -and $isi[$i + 1] -eq '/') {
            while ($i -lt $n -and $isi[$i] -ne "`n") { $i++ }
            continue
        }

        if ($c -eq '/' -and ($i + 1) -lt $n -and $isi[$i + 1] -eq '*') {
            $i += 2
            while (($i + 1) -lt $n -and -not ($isi[$i] -eq '*' -and $isi[$i + 1] -eq '/')) { $i++ }
            $i += 2
            continue
        }

        if ($c -eq "'" -or $c -eq '"') {
            $tanda = $c
            $i++

            while ($i -lt $n) {
                if ($isi[$i] -eq '\') { $i += 2; continue }
                if ($isi[$i] -eq $tanda) { $i++; break }
                if ($isi[$i] -eq "`n") { break }
                $i++
            }

            continue
        }

        [void]$bersih.Append($c)
        $i++
    }

    $kode = $bersih.ToString()
    $hasil = @{}

    foreach ($pasang in @(@('(', ')'), @('[', ']'), @('{', '}'))) {
        $kiri = ([regex]::Matches($kode, [regex]::Escape($pasang[0]))).Count
        $kanan = ([regex]::Matches($kode, [regex]::Escape($pasang[1]))).Count

        $hasil[$pasang[0]] = @{ Kiri = $kiri; Kanan = $kanan; Sama = ($kiri -eq $kanan) }
    }

    return $hasil
}

foreach ($namaBerkas in @('lib\kasir.dart', 'lib\kasir_lokal.dart', 'lib\peta.dart')) {
    if (-not (Test-Path $namaBerkas)) {
        TulisHasil $false "$namaBerkas ADA (wajib ada)"
        $bermasalah++
        continue
    }

    $info = Get-Item $namaBerkas
    $isiBerkas = [System.IO.File]::ReadAllText($namaBerkas)
    $jumlahBaris = ($isiBerkas -split "`n").Count

    $kurung = Periksa-KurungDart $namaBerkas
    $semuaSama = $true

    foreach ($kunci in @('(', '[', '{')) {
        if (-not $kurung[$kunci].Sama) { $semuaSama = $false }
    }

    TulisHasil $semuaSama "$namaBerkas UTUH - semua kurung berpasangan"

    if (-not $semuaSama) {
        $kKurung = $kurung['(']
        $kSiku = $kurung['[']
        $kKurawal = $kurung['{']

        Write-Host ("            ( )  " + $kKurung.Kiri + " buka / " + $kKurung.Kanan + " tutup") -ForegroundColor Yellow
        Write-Host ("            [ ]  " + $kSiku.Kiri + " buka / " + $kSiku.Kanan + " tutup") -ForegroundColor Yellow
        Write-Host ("            { }  " + $kKurawal.Kiri + " buka / " + $kKurawal.Kanan + " tutup") -ForegroundColor Yellow
        $bermasalah++
    }

    Write-Host "            $jumlahBaris baris, $($info.Length) byte, terakhir diubah $($info.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor Gray
}

if (Test-Path 'lib\kasir.dart') {
    $isiKasir = [System.IO.File]::ReadAllText('lib\kasir.dart')

    $tandaKasir = @(
        @{ Nama = "pemindai kamera memakai nama pendek ms."; Pola = "mobile_scanner.dart' as ms;" },
        @{ Nama = "barcode nota memakai daftar karakter";     Pola = "Barcode.code128(isiBarcode.split(''))" },
        @{ Nama = "seluruh data kasir dipanggil dari HP";     Pola = "RtsKasirLokal.aku.kirim" },
        @{ Nama = "halaman Server & Cadangan";                Pola = "class RtsCadanganPage" },
        @{ Nama = "tombol KIRIM berkas cadangan";             Pola = "rts/pembaruan" }
    )

    foreach ($satu in $tandaKasir) {
        $adaTanda = $isiKasir -match [regex]::Escape($satu.Pola)

        TulisHasil $adaTanda $satu.Nama

        if (-not $adaTanda) { $bermasalah++ }
    }
}

if (Test-Path 'lib\kasir_lokal.dart') {
    $isiLokal = [System.IO.File]::ReadAllText('lib\kasir_lokal.dart')

    $tandaLokal = @(
        @{ Nama = "mesin kasir SQLite (RtsKasirLokal)"; Pola = "class RtsKasirLokal" },
        @{ Nama = "database di dalam HP (sqflite)";     Pola = "package:sqflite/sqflite.dart" },
        @{ Nama = "sinkron produk dari server";         Pola = "sinkron_produk" },
        @{ Nama = "cadangkan data";                     Pola = "cadangan_info" },
        @{ Nama = "izin PRO berlaku luring 30 hari";    Pola = "batasLuringHari" },
        @{ Nama = "jawaban GRATIS hanya 3 menit (segar)"; Pola = "segarTolakMenit" },
        @{ Nama = "pemeriksaan ulang setelah gagal";    Pola = "tundaGagalMenit" },
        @{ Nama = "data akun server = bukti PRO";       Pola = "bool get proSesi" }
    )

    foreach ($satu in $tandaLokal) {
        $adaTanda = $isiLokal -match [regex]::Escape($satu.Pola)

        TulisHasil $adaTanda $satu.Nama

        if (-not $adaTanda) { $bermasalah++ }
    }
}

if (Test-Path 'lib\peta.dart') {
    $isiPeta = [System.IO.File]::ReadAllText('lib\peta.dart')

    $tandaPeta = @(
        @{ Nama = "halaman PETA CUSTOMER";                    Pola = "class RtsPetaCustomerPage" },
        @{ Nama = "halaman RADAR CUSTOMER";                   Pola = "class RtsRadarPage" },
        @{ Nama = "halaman RUTE PLAN";                        Pola = "class RtsRutePage" },
        @{ Nama = "halaman LOKASI KANTOR / MITRA";            Pola = "class RtsKantorPage" },
        @{ Nama = "peta memakai OpenStreetMap";               Pola = "tile.openstreetmap.org" },
        @{ Nama = "penyaring warna per HARI & FREKUENSI";     Pola = "Warna menurut FREKUENSI" },
        @{ Nama = "alat PENSIL garis rute";                   Pola = "_mulaiGores" },
        @{ Nama = "salin daftar plan (Nama + Id Customer)";   Pola = "SALIN NAMA & KODE" },
        @{ Nama = "titik kantor dari server (kantor_segarkan)"; Pola = "kantor_segarkan" }
    )

    foreach ($satu in $tandaPeta) {
        $adaTanda = $isiPeta -match [regex]::Escape($satu.Pola)

        TulisHasil $adaTanda $satu.Nama

        if (-not $adaTanda) { $bermasalah++ }
    }
}
else {
    TulisHasil $false "lib\peta.dart ADA (wajib ada - menu peta)"
    Write-Host "            Jalankan .\LANGKAH1_PASANG_SEMUA.ps1 dari paket terbaru." -ForegroundColor Yellow
    $bermasalah++
}

# -----------------------------------------------------------------------------
# 6a. analysis_options.yaml (pemeriksa kode) - menghilangkan tanda merah palsu
# -----------------------------------------------------------------------------
TulisJudul "6a. Pengaturan pemeriksa kode (analysis_options.yaml)"

if (-not (Test-Path 'analysis_options.yaml')) {
    Write-Host "   [LEWAT] analysis_options.yaml belum ada." -ForegroundColor Yellow
    Write-Host "           Berkas itu membuat VS Code MELEWATI salinan main.dart di" -ForegroundColor Yellow
    Write-Host "           akar folder, sehingga tanda merah palsu" -ForegroundColor Yellow
    Write-Host '           (pesan "Target of URI does not exist") tidak muncul.' -ForegroundColor Yellow
    Write-Host "           Jalankan .\LANGKAH1_PASANG_SEMUA.ps1 dari paket terbaru" -ForegroundColor Yellow
    Write-Host "           untuk memasangnya (tidak mempengaruhi hasil build)." -ForegroundColor Yellow
    Write-Host "           Pemeriksaan kode tetap lanjut pada langkah 6e di bawah." -ForegroundColor DarkGray
}
else {
    $isiAnalysis = [System.IO.File]::ReadAllText('analysis_options.yaml')

    TulisHasil $true "analysis_options.yaml ADA"

    $adaExclude = ($isiAnalysis -match 'exclude') -and ($isiAnalysis -match 'main\.dart')

    TulisHasil $adaExclude "salinan main.dart di akar folder dilewati pemeriksa kode"

    if (-not $adaExclude) {
        Write-Host "            Isi berkas itu belum memuat baris 'exclude: - main.dart'." -ForegroundColor Yellow
        Write-Host "            Timpa dengan analysis_options.yaml dari paket terbaru" -ForegroundColor Yellow
        Write-Host "            supaya tanda merah palsu hilang dari VS Code." -ForegroundColor Yellow
    }
}

# -----------------------------------------------------------------------------
# 6b. Paket kasir luring pada pubspec.yaml
# -----------------------------------------------------------------------------
TulisJudul "6b. Paket kasir luring pada pubspec.yaml"

foreach ($satu in @('sqflite', 'path_provider', 'path:', 'mobile_scanner', 'esc_pos_utils_plus', 'print_bluetooth_thermal', 'flutter_map', 'latlong2')) {
    $adaPaket = $isiPubspec -match [regex]::Escape($satu)

    TulisHasil $adaPaket "paket $satu"

    if (-not $adaPaket) { $bermasalah++ }
}

# -----------------------------------------------------------------------------
# 6c. Angka compileSdk pada Gradle (harus 37)
# -----------------------------------------------------------------------------
TulisJudul "6c. Angka compileSdk pada berkas Gradle"

$berkasGradle = ''

foreach ($kandidat in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
    if (Test-Path $kandidat) { $berkasGradle = $kandidat; break }
}

if ([string]::IsNullOrWhiteSpace($berkasGradle)) {
    TulisHasil $false "berkas build.gradle.kts / build.gradle tidak ditemukan"
    $bermasalah++
}
else {
    $isiGradle = [System.IO.File]::ReadAllText($berkasGradle)
    $angkaSdk = ''

    if ($isiGradle -match 'compileSdk\s*=\s*(\d+)') {
        $angkaSdk = $Matches[1]
    }
    elseif ($isiGradle -match 'compileSdkVersion\s+(\d+)') {
        $angkaSdk = $Matches[1]
    }

    if ([string]::IsNullOrWhiteSpace($angkaSdk)) {
        Write-Host "   [BELUM] $berkasGradle masih memakai bawaan Flutter (compileSdk belum ditulis)" -ForegroundColor Yellow
        Write-Host "           Jalankan PERBAIKI_COMPILE_SDK.ps1 sekali saja." -ForegroundColor Yellow
        $bermasalah++
    }
    elseif ([int]$angkaSdk -ge 37) {
        TulisHasil $true "compileSdk = $angkaSdk pada $berkasGradle"
    }
    else {
        Write-Host "   [BELUM] compileSdk masih $angkaSdk (perlu 37)" -ForegroundColor Yellow
        Write-Host "           Jalankan PERBAIKI_COMPILE_SDK.ps1 sekali saja." -ForegroundColor Yellow
        $bermasalah++
    }
}

# -----------------------------------------------------------------------------
# 6d. Berkas Kotlin (MainActivity) - jumlah berkas & tanda + di awal baris
# -----------------------------------------------------------------------------
TulisJudul "6d. Berkas Kotlin (MainActivity)"

$akarKotlin = 'android\app\src\main'
$daftarMain = @()

if (Test-Path $akarKotlin) {
    $daftarMain = @(Get-ChildItem -Path $akarKotlin -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'MainActivity.kt' })
}

TulisHasil ($daftarMain.Count -eq 1) ("hanya SATU berkas MainActivity.kt (jumlah sekarang: " + $daftarMain.Count + ")")

foreach ($f in $daftarMain) {
    Write-Host ('            ' + $f.FullName) -ForegroundColor Gray
}

if ($daftarMain.Count -ne 1) {
    Write-Host '            Bila jumlahnya DUA, pembangunan berhenti dengan pesan' -ForegroundColor Yellow
    Write-Host '            "Redeclaration: class MainActivity". Jalankan' -ForegroundColor Yellow
    Write-Host '            PERBAIKI_MAINACTIVITY.ps1 untuk merapikannya.' -ForegroundColor Yellow
    $bermasalah++
}

# Kotlin TIDAK mengizinkan tanda + diletakkan di AWAL baris sebagai sambungan.
# Bila ada, pembangunan berhenti dengan pesan "Unresolved reference 'unaryPlus'".
$tandaPlus = 0

$daftarKotlin = @(Get-ChildItem -Path $akarKotlin -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name.EndsWith('.kt') })

foreach ($f in $daftarKotlin) {
    $barisKt = @(Get-Content $f.FullName)

    for ($i = 0; $i -lt $barisKt.Count; $i++) {
        $bersih = $barisKt[$i].Trim()

        if ($bersih -match '^\+') {
            $tandaPlus++
            Write-Host ("            " + $f.Name + " baris " + ($i + 1) + " dimulai tanda + : " + $bersih) -ForegroundColor Yellow
        }
    }
}

TulisHasil ($tandaPlus -eq 0) "tidak ada tanda + di awal baris pada berkas Kotlin"

if ($tandaPlus -ne 0) {
    $bermasalah++
}

# -----------------------------------------------------------------------------
# 6e. PEMERIKSA PALING PENTING - flutter analyze (mencari GALAT kode)
# -----------------------------------------------------------------------------
TulisJudul "6e. Pemeriksaan kode Dart (flutter analyze)"

$adaFlutter = $null -ne (Get-Command flutter -ErrorAction SilentlyContinue)

if (-not $adaFlutter) {
    Write-Host "   [LEWAT] perintah 'flutter' tidak ditemukan di jendela PowerShell ini." -ForegroundColor Yellow
    Write-Host "           Buka PowerShell dari dalam folder proyek (Open in Terminal)," -ForegroundColor Yellow
    Write-Host "           lalu jalankan skrip ini lagi." -ForegroundColor Yellow
}
else {
    Write-Host "   Menjalankan: flutter analyze   (30-90 detik, tidak membangun APK)" -ForegroundColor Gray

    $keluaran = @(& flutter analyze 2>&1)
    $teks = ($keluaran | Out-String)

    # Baris GALAT   : "error - ... - [berkas:baris]"  atau  "Error: ..."
    # Baris KUNING  : "warning - ...", "info - ..."
    $daftarGalat = @($keluaran | Where-Object {
        $satuBaris = "$_"
        ($satuBaris -match '(?m)^\s*error\s') -or ($satuBaris -match 'Error:')
    })

    $daftarKuning = @($keluaran | Where-Object { "$_" -match '(?m)^\s*warning\s' })

    if ($daftarGalat.Count -eq 0) {
        TulisHasil $true "flutter analyze: TIDAK ADA GALAT kode (kode siap dibangun)"

        if ($teks -match 'No issues found') {
            Write-Host "            Pesan dari Flutter: No issues found! (sepenuhnya bersih)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "   [BELUM] flutter analyze menemukan GALAT kode berikut:" -ForegroundColor Red
        Write-Host ""

        foreach ($satuBaris in $daftarGalat) {
            Write-Host ("            " + "$satuBaris".Trim()) -ForegroundColor Yellow
        }

        Write-Host ""
        Write-Host "            Sebab tersering: satu baris yang jenis nilainya tidak cocok" -ForegroundColor Yellow
        Write-Host "            (misalnya teks disimpan ke kotak isian). Salin SELURUH baris" -ForegroundColor Yellow
        Write-Host "            yang dimulai kata 'error' di atas, kirimkan untuk diperbaiki." -ForegroundColor Yellow
        $bermasalah++
    }

    # Peringatan (tanda kuning) tidak menghentikan build, tetapi tetap
    # ditampilkan supaya dapat dibersihkan sebelum rilis.
    if ($daftarKuning.Count -gt 0) {
        Write-Host ""
        Write-Host "   Peringatan (tanda kuning) - TIDAK menghentikan build:" -ForegroundColor Yellow

        foreach ($satuBaris in $daftarKuning) {
            Write-Host ("            " + "$satuBaris".Trim()) -ForegroundColor Gray
        }

        Write-Host ('            Jumlah peringatan: ' + $daftarKuning.Count) -ForegroundColor Gray
    }
    elseif ($daftarGalat.Count -eq 0) {
        Write-Host "   Tidak ada peringatan (tanda kuning) juga - kode sepenuhnya bersih." -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# 7. Kesimpulan dan langkah berikutnya
# -----------------------------------------------------------------------------

TulisJudul "KESIMPULAN"

if ($bermasalah -eq 0) {
    Write-Host "   SEMUA BENAR. Folder proyek sudah memuat kode terbaru." -ForegroundColor Green
    Write-Host "   (Termasuk pemeriksaan flutter analyze - kode siap dibangun.)" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Langkah berikutnya:" -ForegroundColor White
    Write-Host "     1. flutter clean" -ForegroundColor Gray
    Write-Host "     2. flutter pub get" -ForegroundColor Gray
    Write-Host "     3. flutter run -d CPH1937        (bangun + pasang ke HP)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   Uji kasir luring: matikan internet HP, lalu buat satu nota." -ForegroundColor Green
    Write-Host "   Sesudah itu tekan CADANGKAN SEKARANG dan KIRIM ke Google Drive." -ForegroundColor Green
}
else {
    Write-Host "   ADA $bermasalah hal yang belum benar (lihat tanda [BELUM] di atas)." -ForegroundColor Red
    Write-Host ""
    Write-Host "   Langkah perbaikan - JANGAN MENGHAPUS FOLDER PROYEK:" -ForegroundColor White
    Write-Host "     1. Ekstrak RTS_PANEL_PUTARAN_12.zip ke Desktop" -ForegroundColor Gray
    Write-Host "     2. Jalankan .\LANGKAH1_PASANG_SEMUA.ps1 dari folder hasil ekstrak" -ForegroundColor Gray
    Write-Host "        (skrip itu menimpa main.dart, lib\kasir.dart, lib\kasir_lokal.dart," -ForegroundColor Gray
    Write-Host "         lib\peta.dart, pubspec.yaml, berkas Android, dan memperbaiki compileSdk)" -ForegroundColor Gray
    Write-Host "     3. Jalankan skrip ini lagi - semua harus [ADA] / [BENAR]" -ForegroundColor Gray
    Write-Host "     4. flutter clean  ->  flutter pub get  ->  flutter run -d CPH1937" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   PENTING: jangan menyunting lib\kasir.dart dengan tangan dan jangan" -ForegroundColor Yellow
    Write-Host "   menempelkan sebagian isinya. Berkas itu harus ditimpa UTUH. Berkas" -ForegroundColor Yellow
    Write-Host "   yang tersambung sebagian akan tampak seperti berkas baru, tetapi" -ForegroundColor Yellow
    Write-Host "   kurungnya tidak berpasangan (inilah yang ditandai [BELUM] di atas)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   MENGAPA TIDAK BOLEH MENGHAPUS FOLDER:" -ForegroundColor Yellow
    Write-Host "     Paket zip TIDAK memuat folder android, assets, dan lib." -ForegroundColor Yellow
    Write-Host "     Bila folder dihapus, google-services.json (Firebase) dan" -ForegroundColor Yellow
    Write-Host "     gambar latar akan hilang, sehingga build gagal." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "   Pemeriksaan selesai. Tidak ada berkas yang diubah." -ForegroundColor DarkGray
Write-Host ""
