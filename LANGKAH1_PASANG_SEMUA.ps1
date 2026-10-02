# =============================================================================
#  RTS PANEL BY BENE - LANGKAH 1: PASANG SEMUA (PUTARAN IKLAN + PRO + FOTO)
#  Berkas : LANGKAH1_PASANG_SEMUA.ps1
#
#  SATU-SATUNYA SKRIP YANG PERLU DIJALANKAN UNTUK TOPIK INI.
#
#  APA YANG DIKERJAKAN SKRIP INI (9 langkah, semuanya dicadangkan lebih dahulu)
#     1. Memastikan folder proyek Flutter ditemukan
#     2. Menyalin main.dart  ->  D:\Project\rts_panel_app\main.dart
#                                D:\Project\rts_panel_app\lib\main.dart
#     3. Menyalin pubspec.yaml (memuat sqflite + flutter_map + versi 1.2.5+8)
#     4. Menyalin lib\kasir.dart, lib\kasir_lokal.dart, DAN lib\peta.dart
#        (kasir_lokal.dart  = mesin kasir di dalam HP, berjalan tanpa internet)
#        (peta.dart = PETA CUSTOMER, RADAR CUSTOMER, RUTE PLAN, dan LOKASI
#                     KANTOR memakai OpenStreetMap)
#     5. Menambahkan izin KAMERA pada AndroidManifest.xml (bila belum ada)
#     6. Mengubah NAMA APLIKASI pada layar HP menjadi "RTS Panel"
#        (sebelumnya tertulis rts_panel_app)
#     6b. Memasang MainActivity.kt pada tempat yang benar dan memindahkan
#        salinan berlebih (mencegah galat "Redeclaration: class MainActivity")
#     7. Memasang gambar QRIS Bapak -> assets\images\qris_bene_s.jpg
#     8. Memperbaiki compileSdk menjadi 37 (sekali saja) supaya pesan
#        "permission_handler_android compiles against Android SDK 37"
#        tidak menghentikan pembangunan, lalu menjalankan
#        flutter clean dan flutter pub get
#     9. Menampilkan perintah terakhir yang perlu diketik
#
#  Skrip ini TIDAK menghapus berkas apa pun. Berkas lama selalu dicadangkan
#  dengan tambahan ".lama_tanggal_jam".
#
#  CARA PAKAI
#  ----------
#     1. Ekstrak paket RTS_PANEL_PUTARAN_12.zip ke Desktop
#     2. Buka PowerShell, masuk ke folder hasil ekstrak, contoh:
#            cd "$env:USERPROFILE\Desktop\RTS_PANEL_PUTARAN_12"
#     3. Jalankan:
#            .\LANGKAH1_PASANG_SEMUA.ps1
#     4. Bila muncul pesan "running scripts is disabled", jalankan:
#            powershell -ExecutionPolicy Bypass -File .\LANGKAH1_PASANG_SEMUA.ps1
# =============================================================================

param(
    [string]$Proyek = ''
)

$ErrorActionPreference = 'Stop'

$akarSkrip = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($akarSkrip)) {
    $akarSkrip = (Get-Location).Path
}

# ---------------------------------------------------------------------- tampilan

function Judul($teks) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host (' ' + $teks) -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host ''
}

function Baik($teks) { Write-Host ('   [ OK ] ' + $teks) -ForegroundColor Green }
function Info($teks) { Write-Host ('          ' + $teks) -ForegroundColor Gray }
function Awas($teks) { Write-Host ('   [ ! ]  ' + $teks) -ForegroundColor Yellow }
function Galat($teks) { Write-Host ('   [ X ]  ' + $teks) -ForegroundColor Red }

function Simpan-TanpaBom($jalur, $teks) {
    $penyandi = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($jalur, $teks, $penyandi)
}

function Salin-DenganCadangan($sumber, $tujuan) {
    if (-not (Test-Path $sumber)) {
        Galat "Berkas sumber tidak ada: $sumber"
        return $false
    }

    if (Test-Path $tujuan) {
        $cadangan = $tujuan + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
        Copy-Item -Path $tujuan -Destination $cadangan -Force
        Info ("cadangan lama : " + (Split-Path $cadangan -Leaf))
    }

    $folderTujuan = Split-Path -Parent $tujuan

    if (-not (Test-Path $folderTujuan)) {
        New-Item -ItemType Directory -Path $folderTujuan -Force | Out-Null
    }

    Copy-Item -Path $sumber -Destination $tujuan -Force
    return $true
}

Judul 'RTS PANEL BY BENE - LANGKAH 1: PASANG SEMUA'
Write-Host ' Topik putaran ini:' -ForegroundColor White
Write-Host '   - iklan saat aplikasi dibuka (app open)' -ForegroundColor Gray
Write-Host '   - iklan native di seluruh menu' -ForegroundColor Gray
Write-Host '   - halaman Langganan PRO dengan QRIS (30 hari + uji coba 7 hari)' -ForegroundColor Gray
Write-Host '   - foto pribadi setiap pengguna' -ForegroundColor Gray
Write-Host ''

# =============================================================================
# 0. FOLDER BERKAS SUMBER (hasil ekstrak paket)
# =============================================================================

$folderAplikasi = Join-Path $akarSkrip '2_APLIKASI_copy_ke_proyek'

if (-not (Test-Path $folderAplikasi)) {
    Galat 'Folder "2_APLIKASI_copy_ke_proyek" tidak ditemukan.'
    Write-Host ''
    Write-Host ' Skrip ini harus dijalankan dari DALAM folder hasil ekstrak paket.' -ForegroundColor Yellow
    Write-Host ' Contoh:' -ForegroundColor Yellow
    Write-Host '     cd "$env:USERPROFILE\Desktop\RTS_PANEL_PUTARAN_12"' -ForegroundColor White
    Write-Host '     .\LANGKAH1_PASANG_SEMUA.ps1' -ForegroundColor White
    Write-Host ''
    exit 1
}

$berkasMain = Join-Path $folderAplikasi 'main.dart'
$berkasKasir = Join-Path $folderAplikasi 'kasir.dart'
$berkasKasirLokal = Join-Path $folderAplikasi 'kasir_lokal.dart'
$berkasPeta = Join-Path $folderAplikasi 'peta.dart'
$berkasPubspec = Join-Path $folderAplikasi 'pubspec.yaml'
$berkasManifestPanduan = Join-Path $folderAplikasi 'android_manifest_tambahan.xml'
$berkasMainActivity = Join-Path $folderAplikasi 'MainActivity.kt'
$berkasFilePaths = Join-Path $folderAplikasi 'file_paths.xml'
$berkasPenerima = Join-Path $folderAplikasi 'RtsPenerimaPembaruan.kt'

Baik 'Berkas aplikasi dari paket ditemukan.'

# =============================================================================
# 1. MENEMUKAN FOLDER PROYEK FLUTTER
# =============================================================================

Judul '1. Mencari folder proyek Flutter'

$kandidat = @()

if (-not [string]::IsNullOrWhiteSpace($Proyek)) {
    $kandidat += $Proyek
}

$kandidat += 'D:\Project\rts_panel_app'
$kandidat += (Join-Path $env:USERPROFILE 'rts_panel_app')

if (Test-Path 'D:\Project') {
    $kandidat += (Get-ChildItem -Path 'D:\Project' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName })
}

$folderProyek = ''

foreach ($k in $kandidat) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }

    if (Test-Path (Join-Path $k 'pubspec.yaml')) {
        $folderProyek = (Resolve-Path $k).Path
        break
    }
}

if ($folderProyek -eq '') {
    Awas 'Folder proyek Flutter belum ditemukan secara otomatis.'
    Write-Host ''
    Write-Host ' Tuliskan lokasi folder proyek (yang berisi pubspec.yaml).' -ForegroundColor Yellow
    Write-Host ' Contoh: D:\Project\rts_panel_app' -ForegroundColor Gray
    Write-Host ''

    $jawab = Read-Host '   Lokasi folder proyek'

    if ([string]::IsNullOrWhiteSpace($jawab) -or -not (Test-Path (Join-Path $jawab 'pubspec.yaml'))) {
        Galat 'Folder itu tidak memuat pubspec.yaml. Skrip dihentikan tanpa mengubah apa pun.'
        exit 1
    }

    $folderProyek = (Resolve-Path $jawab).Path
}

Baik "Folder proyek : $folderProyek"
Info 'Skrip akan menyalin berkas ke folder ini. Tekan Enter untuk mulai, atau'
Info 'tekan Ctrl+C untuk membatalkan.'

Read-Host '   Tekan Enter untuk mulai' | Out-Null

# =============================================================================
# 2. main.dart  ->  akar dan lib
# =============================================================================

Judul '2. Memasang main.dart (akar + lib\main.dart)'

$tujuanAkar = Join-Path $folderProyek 'main.dart'
$tujuanLib = Join-Path $folderProyek 'lib\main.dart'

if (Salin-DenganCadangan $berkasMain $tujuanAkar) {
    Baik 'main.dart (akar) diperbarui.'
}

if (Salin-DenganCadangan $berkasMain $tujuanLib) {
    Baik 'lib\main.dart diperbarui  <-- INI YANG DIBANGUN FLUTTER.'
}

# lib\kasir.dart berisi seluruh halaman FITUR PRO Barang Bawaan & Kasir
# (produk, stok, kasir, piutang, printer bluetooth, template struk).
if (Test-Path $berkasKasir) {
    $tujuanKasir = Join-Path $folderProyek 'lib\kasir.dart'

    if (Salin-DenganCadangan $berkasKasir $tujuanKasir) {
        Baik 'lib\kasir.dart diperbarui  <-- halaman Barang Bawaan, Kasir, Piutang, Printer.'
    }
} else {
    Info 'Berkas kasir.dart tidak ada di dalam paket - menu Barang Bawaan,'
    Info 'Kasir, Piutang, dan Printer akan tampil sebagai "sedang disiapkan".'
}

# lib\kasir_lokal.dart adalah MESIN KASIR DI DALAM HP (SQLite).
# Berkas inilah yang membuat stok, penjualan, piutang, dan template struk
# tetap tersimpan dan tetap berjalan TANPA INTERNET. Wajib ada.
if (Test-Path $berkasKasirLokal) {
    $tujuanKasirLokal = Join-Path $folderProyek 'lib\kasir_lokal.dart'

    if (Salin-DenganCadangan $berkasKasirLokal $tujuanKasirLokal) {
        Baik 'lib\kasir_lokal.dart dipasang  <-- data kasir tersimpan di HP (tanpa internet).'
    }
} else {
    Awas 'kasir_lokal.dart TIDAK ada di folder paket!'
    Awas 'Tanpa berkas itu aplikasi GAGAL dibangun (lib\kasir.dart memanggilnya).'
    Awas 'Pastikan memakai paket RTS_PANEL_PUTARAN_12.zip yang lengkap.'
}

# lib\peta.dart berisi TIGA MENU PRO PETA (OpenStreetMap): PETA CUSTOMER,
# RADAR CUSTOMER, dan RUTE PLAN (lengkap dengan pensil rute + daftar plan yang
# dapat disalin), serta halaman LOKASI KANTOR / MITRA untuk ADMIN & ASS.
if (Test-Path $berkasPeta) {
    $tujuanPeta = Join-Path $folderProyek 'lib\peta.dart'

    if (Salin-DenganCadangan $berkasPeta $tujuanPeta) {
        Baik 'lib\peta.dart dipasang  <-- Peta Customer, Radar Customer, Rute Plan.'
    }
} else {
    Awas 'peta.dart TIDAK ada di folder paket!'
    Awas 'Tanpa berkas itu aplikasi GAGAL dibangun (lib\main.dart memanggilnya).'
}

# =============================================================================
# 3. pubspec.yaml
# =============================================================================

Judul '3. Memasang pubspec.yaml (sqflite + kamera barcode + printer + peta + versi 1.2.5+8)'

$tujuanPubspec = Join-Path $folderProyek 'pubspec.yaml'

if (Salin-DenganCadangan $berkasPubspec $tujuanPubspec) {
    $isiPubspec = Get-Content $tujuanPubspec -Raw
    $versi = '(tidak terbaca)'

    if ($isiPubspec -match '(?m)^version:\s*(.+)$') {
        $versi = $Matches[1].Trim()
    }

    Baik "pubspec.yaml diperbarui (versi $versi)."

    if ($isiPubspec -match 'image_picker') {
        Baik 'image_picker sudah ada di dalamnya (untuk memilih foto).'
    } else {
        Awas 'image_picker TIDAK ada di pubspec. Gunakan pubspec.yaml dari paket ini.'
    }

    foreach ($paketWajib in @('sqflite', 'path_provider', 'path:', 'mobile_scanner',
            'esc_pos_utils_plus', 'print_bluetooth_thermal', 'permission_handler',
            'flutter_map', 'latlong2')) {
        if ($isiPubspec -match [regex]::Escape($paketWajib)) {
            Baik "paket $paketWajib sudah ada di pubspec."
        } else {
            Awas "paket $paketWajib TIDAK ada di pubspec. Gunakan pubspec.yaml dari paket ini."
        }
    }
}

# =============================================================================
# 4. IZIN KAMERA PADA AndroidManifest.xml
# =============================================================================

Judul '4. Menambahkan izin KAMERA pada AndroidManifest.xml'

$jalurManifest = Join-Path $folderProyek 'android\app\src\main\AndroidManifest.xml'

if (-not (Test-Path $jalurManifest)) {
    Awas 'AndroidManifest.xml tidak ditemukan.'
    Info 'Bila folder proyek ini belum lengkap, jalankan flutter create . lebih dahulu.'
} else {
    $isiManifest = Get-Content $jalurManifest -Raw

    if ($isiManifest -match 'android\.permission\.CAMERA') {
        Baik 'Izin KAMERA sudah ada. Tidak diubah lagi.'
    } else {
        $barisKamera = '<uses-permission android:name="android.permission.CAMERA" />'

        if ($isiManifest -match '<application') {
            $cadanganManifest = $jalurManifest + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
            Copy-Item -Path $jalurManifest -Destination $cadanganManifest -Force
            Info ('cadangan lama : ' + (Split-Path $cadanganManifest -Leaf))

            $pengganti = "`r`n    " + $barisKamera + "`r`n`r`n`$1"
            $isiBaru = [regex]::Replace($isiManifest, '(\s*<application)', $pengganti, 1)
            Simpan-TanpaBom $jalurManifest $isiBaru

            $cek = Get-Content $jalurManifest -Raw

            if ($cek -match 'android\.permission\.CAMERA') {
                Baik 'Izin KAMERA ditambahkan (untuk mengambil foto dari kamera).'
            } else {
                Awas 'Izin KAMERA belum berhasil ditambahkan. Buka android_manifest_tambahan.xml.'
            }
        } else {
            Awas 'Baris <application> tidak ditemukan pada AndroidManifest.xml.'
            Info 'Tambahkan manual: ' + $barisKamera
        }
    }

    if ((Get-Content $jalurManifest -Raw) -match 'com.google.android.gms.ads\.APPLICATION_ID') {
        Baik 'Kode aplikasi AdMob sudah ada pada AndroidManifest.xml.'
    } else {
        Awas 'Kode aplikasi AdMob BELUM ada pada AndroidManifest.xml.'
        Info 'Iklan tidak akan tampil tanpa baris meta-data APPLICATION_ID.'
        Info 'Baris itu seharusnya sudah ada sejak putaran iklan sebelumnya.'
        Info 'Contoh barisnya ada pada berkas android_manifest_tambahan.xml'
        Info '(folder 2_APLIKASI_copy_ke_proyek) bagian bawah.'
    }
}

# =============================================================================
# 4b. PEMBARUAN LANGSUNG DI DALAM APLIKASI (unduh + pasang tanpa Chrome)
# =============================================================================

Judul '4b. Menyiapkan pembaruan langsung di dalam aplikasi'

if (-not (Test-Path $berkasMainActivity) -or -not (Test-Path $berkasFilePaths)) {
    Awas 'Berkas MainActivity.kt / file_paths.xml tidak ditemukan di folder paket.'
    Info 'Pembaruan lewat peramban (Chrome) tetap bekerja seperti biasa.'
} elseif (-not (Test-Path $folderProyek)) {
    Awas 'Folder proyek belum ditemukan - langkah ini dilewati.'
} else {
    # --- Nama paket aplikasi dibaca dari build.gradle(.kts) ------------------
    $pakej = 'com.example.rts_panel_app'
    $berkasGradle = Join-Path $folderProyek 'android\app\build.gradle.kts'

    if (-not (Test-Path $berkasGradle)) {
        $berkasGradle = Join-Path $folderProyek 'android\app\build.gradle'
    }

    if (Test-Path $berkasGradle) {
        $isiGradle = Get-Content $berkasGradle -Raw

        if ($isiGradle -match 'applicationId\s*=?\s*"([^"]+)"') {
            $pakej = $Matches[1]
        }
    }

    Info ('Nama paket aplikasi : ' + $pakej)

    # --- 1) MainActivity.kt + RtsPenerimaPembaruan.kt ------------------------
    #
    # PENTING (perbaikan 2 Oktober 2026):
    #   Pada putaran sebelumnya berkas ini ditulis ke folder MainActivity.kt
    #   yang ditemukan PERTAMA. Bila di dalam proyek ternyata ada DUA berkas
    #   MainActivity.kt (misalnya satu di folder induk "kotlin" dan satu di
    #   dalam folder paket), Kotlin menolak membangun dengan pesan:
    #       Redeclaration: class MainActivity : FlutterActivity
    #   Karena itu pekerjaan ini diserahkan kepada PERBAIKI_MAINACTIVITY.ps1
    #   yang menulis berkas pada tempat yang benar DAN memindahkan setiap
    #   salinan berlebih (diubah namanya menjadi .lama_tanggal, tidak dihapus).
    $berkasPerbaikiMain = Join-Path $PSScriptRoot 'PERBAIKI_MAINACTIVITY.ps1'

    if (Test-Path $berkasPerbaikiMain) {
        try {
            & powershell -NoProfile -ExecutionPolicy Bypass -File `
                $berkasPerbaikiMain -Proyek $folderProyek

            Baik 'MainActivity.kt dipasang & salinan berlebih dirapikan.'
        }
        catch {
            Awas 'Pemasangan MainActivity.kt gagal pada langkah otomatis.'
            Info 'Jalankan sendiri berkas PERBAIKI_MAINACTIVITY.ps1 dari folder'
            Info '3_SKRIP_POWERSHELL, lalu jalankan lagi skrip ini.'
        }
    } else {
        Awas 'PERBAIKI_MAINACTIVITY.ps1 tidak ditemukan di folder paket.'
        Info 'Bila muncul pesan "Redeclaration: class MainActivity", unduh'
        Info 'berkas itu dari daftar tautan (TAUTAN_UNDUH.txt) lalu jalankan.'
    }

    # --- 2) file_paths.xml ---------------------------------------------------
    $folderXml = Join-Path $folderProyek 'android\app\src\main\res\xml'

    if (-not (Test-Path $folderXml)) {
        New-Item -ItemType Directory -Path $folderXml -Force | Out-Null
    }

    Copy-Item -Path $berkasFilePaths -Destination (Join-Path $folderXml 'file_paths.xml') -Force
    Baik 'file_paths.xml dipasang pada android\app\src\main\res\xml.'

    # --- 3) AndroidManifest.xml : izin + pembagi berkas ----------------------
    if (-not (Test-Path $jalurManifest)) {
        Awas 'AndroidManifest.xml tidak ditemukan - bagian ini dilewati.'
    } else {
        $isiMan = Get-Content $jalurManifest -Raw

        if ($isiMan -match 'REQUEST_INSTALL_PACKAGES') {
            Baik 'Izin REQUEST_INSTALL_PACKAGES sudah ada.'
        } elseif ($isiMan -match '<application') {
            $cadanganManifest2 = $jalurManifest + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
            Copy-Item -Path $jalurManifest -Destination $cadanganManifest2 -Force
            Info ('cadangan lama : ' + (Split-Path $cadanganManifest2 -Leaf))

            $barisIzinPasang = '<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />'
            $penggantiIzin = "`r`n    " + $barisIzinPasang + "`r`n`r`n`$1"
            $isiMan = [regex]::Replace($isiMan, '(\s*<application)', $penggantiIzin, 1)
            Info 'Izin REQUEST_INSTALL_PACKAGES ditambahkan.'
        }

        if ($isiMan -match 'RtsPenerimaPembaruan') {
            Baik 'Bagian <receiver> pembaruan sudah ada.'
        } elseif ($isiMan -match '</application>') {
            $penerima = @'
        <receiver
            android:name=".RtsPenerimaPembaruan"
            android:exported="true"
            android:enabled="true">
            <intent-filter>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED" />
            </intent-filter>
        </receiver>

'@
            $isiMan = [regex]::Replace($isiMan, '(</application>)', ($penerima + '$1'), 1)
            Info 'Bagian <receiver> pembaruan ditambahkan.'
        }

        if ($isiMan -match 'rtsberkas') {
            Baik 'Bagian <provider> FileProvider sudah ada.'
        } elseif ($isiMan -match '<application[^>]*>') {
            $provider = @'
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.rtsberkas"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>

'@
            $isiMan = [regex]::Replace($isiMan, '(<application[^>]*>)', ('$1' + "`r`n" + $provider), 1)
            Info 'Bagian <provider> FileProvider ditambahkan.'
        }

        Simpan-TanpaBom $jalurManifest $isiMan

        $cekBeres = Get-Content $jalurManifest -Raw

        if ($cekBeres -match 'RtsPenerimaPembaruan') {
            Baik 'Pembuka aplikasi sesudah pembaruan sudah terpasang pada AndroidManifest.xml.'
        } else {
            Awas 'Bagian <receiver> belum ada pada AndroidManifest.xml.'
            Info 'Tambahkan manual dari android_manifest_tambahan.xml bagian 3.'
        }

        if (($cekBeres -match 'REQUEST_INSTALL_PACKAGES') -and ($cekBeres -match 'rtsberkas') -and ($cekBeres -match 'RtsPenerimaPembaruan')) {
            Baik 'AndroidManifest.xml siap untuk pembaruan di dalam aplikasi.'
        } else {
            Awas 'Sebagian penambahan pada AndroidManifest.xml belum berhasil.'
            Info 'Buka android_manifest_tambahan.xml untuk menambahkan manual.'
        }
    }
}

# =============================================================================
# 5. NAMA APLIKASI PADA LAYAR HP  ->  "RTS Panel"
# =============================================================================

Judul '5. Mengubah nama aplikasi pada layar HP menjadi "RTS Panel"'

$namaBaru = 'RTS Panel'

if (-not (Test-Path $jalurManifest)) {
    Awas 'AndroidManifest.xml tidak ditemukan - nama aplikasi tidak diubah.'
} else {
    $isiNama = Get-Content $jalurManifest -Raw

    if ($isiNama -match ('android:label="' + [regex]::Escape($namaBaru) + '"')) {
        Baik 'Nama aplikasi sudah "RTS Panel". Tidak diubah lagi.'
    } elseif ($isiNama -match 'android:label="[^"]*"') {
        $namaLama = [regex]::Match($isiNama, 'android:label="([^"]*)"').Groups[1].Value

        $cadanganNama = $jalurManifest + '.lama_' + (Get-Date -Format 'ddMM-yyyy_HHmmss')
        Copy-Item -Path $jalurManifest -Destination $cadanganNama -Force
        Info ('cadangan lama : ' + (Split-Path $cadanganNama -Leaf))

        $isiNamaBaru = [regex]::Replace($isiNama, 'android:label="[^"]*"', ('android:label="' + $namaBaru + '"'))
        Simpan-TanpaBom $jalurManifest $isiNamaBaru

        $cekNama = Get-Content $jalurManifest -Raw

        if ($cekNama -match ('android:label="' + [regex]::Escape($namaBaru) + '"')) {
            Baik ('Nama aplikasi diubah dari "' + $namaLama + '" menjadi "' + $namaBaru + '".')
            Info 'Nama baru terlihat pada layar HP setelah aplikasi dipasang ulang.'
        } else {
            Awas 'Nama aplikasi belum berhasil diubah.'
        }
    } else {
        Awas 'Baris android:label tidak ditemukan pada AndroidManifest.xml.'
        Info 'Tambahkan sendiri pada tag <application>: android:label="RTS Panel"'
    }
}

# =============================================================================
# 6. GAMBAR QRIS
# =============================================================================

Judul '6. Memasang gambar QRIS'

$folderGambar = Join-Path $folderProyek 'assets\images'

if (-not (Test-Path $folderGambar)) {
    New-Item -ItemType Directory -Path $folderGambar -Force | Out-Null
    Info "Folder dibuat : $folderGambar"
}

$tujuanQris = Join-Path $folderGambar 'qris_bene_s.jpg'

if (Test-Path $tujuanQris) {
    Baik "Gambar QRIS sudah ada ($([math]::Round((Get-Item $tujuanQris).Length / 1KB, 1)) KB)."
    Info 'Lewati langkah ini bila gambar itu sudah benar.'
} else {
    Awas 'Gambar QRIS belum ada. Halaman Langganan PRO tetap dapat dibuka,'
    Info 'tetapi gambarnya belum tampil.'

    $jawab = Read-Host '   Tulis lokasi gambar QRIS (atau tekan Enter agar dicarikan otomatis)'

    if ([string]::IsNullOrWhiteSpace($jawab)) {
        Info 'Mencari gambar QRIS di folder Unduhan / Desktop / Pictures...'

        $cari = @()

        foreach ($f in @('Downloads', 'Desktop', 'Pictures', 'OneDrive\Pictures', 'OneDrive\Downloads')) {
            $folderCari = Join-Path $env:USERPROFILE $f

            if (Test-Path $folderCari) {
                $cari += Get-ChildItem -Path $folderCari -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } |
                    Where-Object { $_.Name -match '(?i)qris|bene|whatsapp|wa\d' }
            }
        }

        if ($cari.Count -gt 0) {
            $pilih = $cari | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            Info ('Ditemukan : ' + $pilih.FullName)
            Info ('Diubah    : ' + $pilih.LastWriteTime)

            $ya = Read-Host '   Pakai gambar ini? (Y/n)'

            if ([string]::IsNullOrWhiteSpace($ya) -or $ya -match '^(?i)y') {
                $jawab = $pilih.FullName
            }
        } else {
            Awas 'Tidak ada gambar yang cocok ditemukan.'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($jawab) -and (Test-Path $jawab)) {
        Copy-Item -Path $jawab -Destination $tujuanQris -Force
        Baik 'Gambar QRIS dipasang menjadi assets\images\qris_bene_s.jpg.'
    } else {
        Info 'Dilewati. Pasang kapan saja dengan menjalankan berkas'
        Info 'PASANG_GAMBAR_QRIS.ps1 yang ada di folder 3_SKRIP_POWERSHELL.'
    }
}

# =============================================================================
# 5b. MEMPERBAIKI compileSdk MENJADI 37 (SEKALI SAJA)
# =============================================================================

Judul '7. Memperbaiki compileSdk Android menjadi 37 (sekali saja)'

$berkasPerbaikiSdk = Join-Path $PSScriptRoot 'PERBAIKI_COMPILE_SDK.ps1'

if (Test-Path $berkasPerbaikiSdk) {
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File `
            $berkasPerbaikiSdk -Proyek $folderProyek

        Baik 'compileSdk diperiksa/diperbaiki menjadi 37.'
    }
    catch {
        Awas 'Pemeriksaan compileSdk dilewati. Jalankan sendiri berkas'
        Awas 'PERBAIKI_COMPILE_SDK.ps1 di folder 3_SKRIP_POWERSHELL.'
    }
} else {
    Info 'Berkas PERBAIKI_COMPILE_SDK.ps1 tidak ada di folder paket.'
    Info 'Bila pembangunan berhenti dengan pesan permission_handler_android'
    Info 'compiles against Android SDK 37, jalankan berkas itu lebih dahulu.'
}

# =============================================================================
# 6. flutter clean + flutter pub get
# =============================================================================

Judul '8. Menjalankan flutter clean dan flutter pub get'

$flutter = Get-Command flutter -ErrorAction SilentlyContinue

if (-not $flutter) {
    Awas 'Perintah "flutter" tidak ditemukan pada PATH.'
    Info 'Buka PowerShell baru, lalu jalankan sendiri di folder proyek:'
    Info '    flutter clean'
    Info '    flutter pub get'
} else {
    Push-Location $folderProyek

    try {
        Info 'Menjalankan flutter clean...'
        & flutter clean

        Info 'Menjalankan flutter pub get...'
        & flutter pub get

        Baik 'flutter clean dan flutter pub get selesai.'
    }
    catch {
        Awas 'Perintah flutter gagal dijalankan. Jalankan sendiri di folder proyek:'
        Info '    flutter clean'
        Info '    flutter pub get'
    }
    finally {
        Pop-Location
    }
}

# =============================================================================
# 8. RINGKASAN
# =============================================================================

Judul '9. SELESAI - LANGKAH BERIKUTNYA'

Write-Host ' Di komputer (sekarang):' -ForegroundColor White
Write-Host '     cd ' $folderProyek -ForegroundColor Gray
Write-Host ''
Write-Host '     flutter devices' -ForegroundColor White
Write-Host '     flutter run -d CPH1937' -ForegroundColor White
Write-Host ''
Write-Host ' Di hosting (cPanel) - WAJIB dikerjakan supaya langganan PRO bekerja:' -ForegroundColor White
Write-Host '     1. Unggah isi folder 1_SERVER_unggah_ke_hosting ke public_html' -ForegroundColor Gray
Write-Host '     2. Buka https://rts.benedic-s.com/langganan_admin.php' -ForegroundColor Gray
Write-Host '     3. Tekan tombol PERBARUI DATABASE' -ForegroundColor Gray
Write-Host ''
Write-Host ' Periksa di aplikasi:' -ForegroundColor White
Write-Host '     Layar HP    : nama aplikasi harus "RTS Panel"' -ForegroundColor Gray
Write-Host '     Pengaturan  : penanda RTS-2026-10-03-13 (penanda lama dilewati)' -ForegroundColor Gray
Write-Host '     Pembaruan   : kotak Pembaruan -> PERBARUI SEKARANG' -ForegroundColor Gray
Write-Host '                   (berkas diunduh DI DALAM aplikasi, tanpa Chrome)' -ForegroundColor Gray
Write-Host '     Profil      : tombol LANGGANAN PRO tampil + gambar QRIS tampil' -ForegroundColor Gray
Write-Host '     Profil      : ketuk foto -> pilih dari galeri -> foto berubah' -ForegroundColor Gray
Write-Host '     Beranda     : iklan banner + iklan native tampil (akun GRATIS)' -ForegroundColor Gray
Write-Host '     Barang Bawaan: SIAPKAN DATA -> produk -> stok -> nota (tanpa internet)' -ForegroundColor Gray
Write-Host '     Menu PRO    : Peta Customer, Radar Customer, Rute Plan tampil' -ForegroundColor Gray
Write-Host '     Pengaturan  : penanda harus RTS-2026-10-03-13' -ForegroundColor Gray
Write-Host ''
Write-Host ' Di hosting (cPanel) - KHUSUS MENU PETA:' -ForegroundColor White
Write-Host '     1. Unggah  api\kantor.php  ke folder api pada hosting' -ForegroundColor Gray
Write-Host '     2. Jalankan  RTS_PANEL_KANTOR.sql  di phpMyAdmin' -ForegroundColor Gray
Write-Host '     3. Masuk aplikasi sebagai ADMIN -> Menu PRO -> RUTE PLAN' -ForegroundColor Gray
Write-Host '     4. Tekan tombol gedung -> KANTOR -> AMBIL TITIK DARI LOKASI SAYA' -ForegroundColor Gray
Write-Host ''
Write-Host ' Bila ada yang gagal, buka berkas BACA_DULU.txt bagian "KALAU ADA MASALAH".' -ForegroundColor Yellow
Write-Host ''
