# =============================================================================
#  RTS PANEL BY BENE - PERBAIKI MAINACTIVITY (DUA BERKAS BERNAMA SAMA)
#  Berkas : PERBAIKI_MAINACTIVITY.ps1
#
#  KENAPA SKRIP INI DIPERLUKAN?
#  ---------------------------
#  Saat membangun aplikasi, Flutter menampilkan pesan:
#
#      e: .../kotlin/MainActivity.kt:75:7 Redeclaration:
#         class MainActivity : FlutterActivity
#      e: .../kotlin/com/example/rts_panel_app/MainActivity.kt:5:7
#         Redeclaration: class MainActivity : FlutterActivity
#      e: .../kotlin/MainActivity.kt:368:17 Unresolved reference 'unaryPlus'
#
#  SEBAB PERTAMA - DUA BERKAS BERNAMA SAMA
#    Di dalam proyek Bapak ada DUA berkas MainActivity.kt:
#       android\app\src\main\kotlin\MainActivity.kt                     <- salinan
#       android\app\src\main\kotlin\com\example\rts_panel_app\
#                                                    MainActivity.kt    <- aslinya
#    Keduanya memakai nama paket yang sama, sehingga Kotlin menganggap
#    kelas MainActivity dibuat dua kali dan menolak membangun aplikasi.
#
#  SEBAB KEDUA - TANDA "+" DI AWAL BARIS (Kotlin)
#    Berkas MainActivity.kt versi lama memuat penulisan seperti ini:
#         pesanGalat = "Berkas tidak dapat dibuka: "
#             + (galat.message ?: "sebab tidak diketahui")
#    Pada Kotlin, tanda + yang terletak di AWAL baris dianggap sebagai
#    "tanda plus satu angka" (unary plus), bukan sambungan kalimat. Itulah
#    pesan "Unresolved reference 'unaryPlus'". Berkas versi baru sudah
#    diperbaiki (tanda + diletakkan di AKHIR baris sebelumnya).
#
#  APA YANG DIKERJAKAN SKRIP INI
#  ----------------------------
#     1. Mencari folder proyek dan membaca nama paket aplikasi dari
#        android\app\build.gradle.kts (bagian applicationId)
#     2. Menuliskan MainActivity.kt dan RtsPenerimaPembaruan.kt versi baru
#        pada tempat yang benar:
#             android\app\src\main\kotlin\<nama paket jadi folder>\
#     3. Memindahkan setiap SALINAN BERLEBIH (berkas lain dengan nama yang
#        sama) menjadi "<nama>.lama_tanggal_jam" supaya tidak ikut dibangun.
#        Berkas itu TIDAK DIHAPUS - hanya diubah namanya.
#     4. Menampilkan hasilnya: berapa berkas MainActivity.kt yang tersisa
#        (harus SATU) dan di folder mana.
#
#  CARA PAKAI
#  ----------
#     1. Simpan skrip ini di folder hasil ekstrak paket (satu folder dengan
#        PERBAIKI_COMPILE_SDK.ps1) ATAU di folder proyek.
#     2. Buka Terminal di folder itu, jalankan:
#            powershell -ExecutionPolicy Bypass -File .\PERBAIKI_MAINACTIVITY.ps1
#     3. Skrip ini juga dijalankan otomatis oleh LANGKAH1_PASANG_SEMUA.ps1.
#     4. Sesudah selesai: flutter clean -> flutter pub get -> flutter run
#
#  Skrip ini TIDAK menghapus apa pun.
# =============================================================================

param(
    [string]$Proyek = 'D:\Project\rts_panel_app'
)

$ErrorActionPreference = 'Continue'

function Judul($teks) {
    Write-Host ''
    Write-Host '====================================================================' -ForegroundColor Cyan
    Write-Host " $teks" -ForegroundColor Cyan
    Write-Host '====================================================================' -ForegroundColor Cyan
}

function Baik($teks) {
    Write-Host "   [BERES]  $teks" -ForegroundColor Green
}

function Info($teks) {
    Write-Host "   [INFO]   $teks" -ForegroundColor Gray
}

function Awas($teks) {
    Write-Host "   [AWAS]   $teks" -ForegroundColor Yellow
}

Judul 'RTS PANEL - PERBAIKI MAINACTIVITY.KT (SATU KALI JALAN)'

# -----------------------------------------------------------------------------
# 1. Folder proyek
# -----------------------------------------------------------------------------

$kandidatProyek = @(
    $Proyek,
    (Join-Path $PSScriptRoot '..'),
    (Join-Path $env:USERPROFILE 'rts_panel_app'),
    (Get-Location).Path
)

$folderProyek = ''

foreach ($k in $kandidatProyek) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }

    if ((Test-Path $k) -and (Test-Path (Join-Path $k 'pubspec.yaml'))) {
        $folderProyek = (Resolve-Path $k).Path
        break
    }
}

if ([string]::IsNullOrWhiteSpace($folderProyek)) {
    Awas 'Folder proyek Flutter tidak ditemukan (yang berisi pubspec.yaml).'
    Write-Host '   Jalankan dengan cara:' -ForegroundColor White
    Write-Host '       .\PERBAIKI_MAINACTIVITY.ps1 -Proyek "D:\Project\rts_panel_app"' -ForegroundColor White
    exit 1
}

Baik "Folder proyek : $folderProyek"

# -----------------------------------------------------------------------------
# 2. Nama paket aplikasi
# -----------------------------------------------------------------------------

$pakej = 'com.example.rts_panel_app'

foreach ($namaGradle in @('android\app\build.gradle.kts', 'android\app\build.gradle')) {
    $berkasGradle = Join-Path $folderProyek $namaGradle

    if (Test-Path $berkasGradle) {
        $isiGradle = Get-Content $berkasGradle -Raw

        if ($isiGradle -match 'applicationId\s*=?\s*"([^"]+)"') {
            $pakej = $Matches[1]
        }

        break
    }
}

Baik "Nama paket aplikasi : $pakej"

# -----------------------------------------------------------------------------
# 3. Berkas sumber (dari paket)
# -----------------------------------------------------------------------------

$folderPaketAplikasi = Join-Path $PSScriptRoot '2_APLIKASI_copy_ke_proyek'

$kandidatMain = @(
    (Join-Path $folderPaketAplikasi 'MainActivity.kt'),
    (Join-Path $PSScriptRoot 'MainActivity.kt'),
    (Join-Path $PSScriptRoot 'android_MainActivity.kt'),
    (Join-Path $PSScriptRoot '..\2_APLIKASI_copy_ke_proyek\MainActivity.kt')
)

$kandidatPenerima = @(
    (Join-Path $folderPaketAplikasi 'RtsPenerimaPembaruan.kt'),
    (Join-Path $PSScriptRoot 'RtsPenerimaPembaruan.kt'),
    (Join-Path $PSScriptRoot 'android_RtsPenerimaPembaruan.kt'),
    (Join-Path $PSScriptRoot '..\2_APLIKASI_copy_ke_proyek\RtsPenerimaPembaruan.kt')
)

$sumberMain = ''
$sumberPenerima = ''

foreach ($k in $kandidatMain) {
    if (Test-Path $k) { $sumberMain = (Resolve-Path $k).Path; break }
}

foreach ($k in $kandidatPenerima) {
    if (Test-Path $k) { $sumberPenerima = (Resolve-Path $k).Path; break }
}

if ([string]::IsNullOrWhiteSpace($sumberMain)) {
    Awas 'Berkas MainActivity.kt versi baru tidak ditemukan.'
    Info 'Letakkan skrip ini di dalam folder hasil ekstrak paket PUTARAN_10,'
    Info 'lalu jalankan lagi (satu folder dengan folder 2_APLIKASI_copy_ke_proyek).'
    exit 1
}

Info ('Sumber MainActivity.kt  : ' + $sumberMain)

if (-not [string]::IsNullOrWhiteSpace($sumberPenerima)) {
    Info ('Sumber PenerimaPembaruan : ' + $sumberPenerima)
} else {
    Awas 'RtsPenerimaPembaruan.kt tidak ditemukan - bagian itu dilewati.'
}

# -----------------------------------------------------------------------------
# 4. Tujuan: android\app\src\main\kotlin\<paket>
# -----------------------------------------------------------------------------

$folderKotlin = Join-Path $folderProyek 'android\app\src\main\kotlin'
$folderTujuan = Join-Path $folderKotlin ($pakej -replace '\.', '\')

if (-not (Test-Path $folderTujuan)) {
    New-Item -ItemType Directory -Path $folderTujuan -Force | Out-Null
    Info "Folder dibuat : $folderTujuan"
}

Baik "Folder tujuan : $folderTujuan"

function Simpan-TanpaBom($jalur, $isi) {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $isi, $utf8)
}

# -----------------------------------------------------------------------------
# 5. Merapikan salinan berlebih LEBIH DAHULU (supaya tidak tertimpa)
# -----------------------------------------------------------------------------

$cap = Get-Date -Format 'ddMM-yyyy_HHmmss'
$akarMain = Join-Path $folderProyek 'android\app\src\main'

$tujuanMain = Join-Path $folderTujuan 'MainActivity.kt'
$tujuanPenerima = Join-Path $folderTujuan 'RtsPenerimaPembaruan.kt'

$dirapikan = 0

$semuaBerkas = Get-ChildItem -Path $akarMain -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'MainActivity.kt' -or $_.Name -eq 'RtsPenerimaPembaruan.kt' }

foreach ($berkas in $semuaBerkas) {
    if ($berkas.FullName -eq $tujuanMain -or $berkas.FullName -eq $tujuanPenerima) {
        continue
    }

    $namaBaru = $berkas.FullName + '.lama_' + $cap

    try {
        Rename-Item -Path $berkas.FullName -NewName (Split-Path $namaBaru -Leaf) -Force
        Write-Host ('   [RAPI]   ' + $berkas.FullName) -ForegroundColor Magenta
        Write-Host ('            -> diubah namanya menjadi ' + (Split-Path $namaBaru -Leaf)) -ForegroundColor Gray
        $dirapikan++
    }
    catch {
        Awas ('Gagal mengubah nama: ' + $berkas.FullName)
    }
}

if ($dirapikan -eq 0) {
    Info 'Tidak ada salinan berlebih - hanya satu berkas (sudah benar).'
} else {
    Baik "$dirapikan salinan berlebih dirapikan (TIDAK dihapus, hanya diubah namanya)."
}

# -----------------------------------------------------------------------------
# 6. Menuliskan berkas versi baru
# -----------------------------------------------------------------------------

$isiMain = Get-Content $sumberMain -Raw
$isiMain = [regex]::Replace($isiMain, '(?m)^package\s+[A-Za-z0-9_.]+', ('package ' + $pakej), 1)

if ($isiMain -notmatch 'package\s+' + [regex]::Escape($pakej)) {
    $isiMain = 'package ' + $pakej + "`r`n`r`n" + $isiMain
}

Simpan-TanpaBom $tujuanMain $isiMain
Baik "MainActivity.kt ditulis ke $tujuanMain"

if (-not [string]::IsNullOrWhiteSpace($sumberPenerima)) {
    $isiPenerima = Get-Content $sumberPenerima -Raw
    $isiPenerima = [regex]::Replace($isiPenerima, '(?m)^package\s+[A-Za-z0-9_.]+', ('package ' + $pakej), 1)

    if ($isiPenerima -notmatch 'package\s+' + [regex]::Escape($pakej)) {
        $isiPenerima = 'package ' + $pakej + "`r`n`r`n" + $isiPenerima
    }

    Simpan-TanpaBom $tujuanPenerima $isiPenerima
    Baik "RtsPenerimaPembaruan.kt ditulis ke $tujuanPenerima"
}

# -----------------------------------------------------------------------------
# 7. Pemeriksaan akhir
# -----------------------------------------------------------------------------

Judul 'PEMERIKSAAN AKHIR'

$sisaMain = @(Get-ChildItem -Path $akarMain -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'MainActivity.kt' })

$sisaPenerima = @(Get-ChildItem -Path $akarMain -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -eq 'RtsPenerimaPembaruan.kt' })

Write-Host ('   Berkas MainActivity.kt yang TERSISA  : ' + $sisaMain.Count) -ForegroundColor White

foreach ($f in $sisaMain) {
    Write-Host ('        ' + $f.FullName) -ForegroundColor Gray
}

Write-Host ('   Berkas RtsPenerimaPembaruan.kt       : ' + $sisaPenerima.Count) -ForegroundColor White

foreach ($f in $sisaPenerima) {
    Write-Host ('        ' + $f.FullName) -ForegroundColor Gray
}

Write-Host ''

if ($sisaMain.Count -eq 1) {
    Write-Host '   BENAR. Hanya ada SATU MainActivity.kt, jadi pesan "Redeclaration"' -ForegroundColor Green
    Write-Host '   tidak akan muncul lagi.' -ForegroundColor Green
} else {
    Write-Host '   PERHATIAN: jumlahnya bukan satu. Kirimkan daftar di atas ke chat.' -ForegroundColor Yellow
}

Write-Host ''
Write-Host '   Langkah berikutnya:' -ForegroundColor White
Write-Host '       flutter clean' -ForegroundColor Gray
Write-Host '       flutter pub get' -ForegroundColor Gray
Write-Host '       flutter run -d CPH1937' -ForegroundColor Gray
Write-Host ''
Write-Host '   Catatan: berkas cadangan berakhiran .lama_tanggal_jam boleh dibiarkan.' -ForegroundColor DarkGray
Write-Host '   Berkas itu tidak ikut dibangun dan tidak mengganggu aplikasi.' -ForegroundColor DarkGray
Write-Host ''
