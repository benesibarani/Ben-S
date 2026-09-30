# =============================================================================
#  RTS PANEL BY BENE - BERSIHKAN FOLDER ASSETS (MEMPERKECIL UKURAN APK)
#  Berkas : BERSIHKAN_ASSETS.ps1
#
#  KENAPA BERKAS INI ADA
#  ---------------------
#  pubspec.yaml memuat aturan:
#        assets:
#          - assets/images/
#  Artinya SELURUH berkas di dalam folder assets\images IKUT DIBUNGKUS ke
#  dalam APK - bukan hanya gambar. Bila di sana ada berkas lain (misalnya
#  salinan database .sql, berkas cadangan .lama_, atau gambar berganda),
#  ukuran APK membengkak dan isinya dapat dibaca siapa pun yang memiliki APK.
#
#  APA YANG DIKERJAKAN SKRIP INI
#     1. Menemukan folder proyek Flutter
#     2. Membaca seluruh isi folder assets\ secara menyeluruh
#     3. Menampilkan daftar berkas beserta ukurannya, dari yang terbesar
#     4. Memindahkan berkas yang BUKAN gambar (dan berkas cadangan/berganda)
#        ke folder di luar assets:  <proyek>\_di_luar_apk\<tanggal>\
#     5. Menampilkan perkiraan penghematan ukuran APK
#
#  PENTING: SKRIP INI TIDAK PERNAH MENGHAPUS BERKAS.
#  Berkas yang dipindahkan tetap ada di folder _di_luar_apk dan dapat
#  dikembalikan kapan saja.
#
#  CARA PAKAI
#  ----------
#     cd D:\Project\rts_panel_app
#     .\BERSIHKAN_ASSETS.ps1                    -> memeriksa dulu (tidak pindah)
#     .\BERSIHKAN_ASSETS.ps1 -Pindahkan         -> benar-benar memindahkan
#     .\BERSIHKAN_ASSETS.ps1 -Pindahkan -Bangun -> sekaligus build APK
#
#  Bila muncul pesan "running scripts is disabled":
#     powershell -ExecutionPolicy Bypass -File .\BERSIHKAN_ASSETS.ps1 -Pindahkan
# =============================================================================

param(
    [string]$Proyek = '',
    [switch]$Pindahkan,
    [switch]$Bangun
)

$ErrorActionPreference = 'Stop'

function Judul($teks) {
    Write-Host ''
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host (' ' + $teks) -ForegroundColor White
    Write-Host ('=' * 68) -ForegroundColor DarkRed
    Write-Host ''
}

function Info($teks) { Write-Host ('   ' + $teks) -ForegroundColor Gray }
function Baik($teks) { Write-Host ('   [ OK ] ' + $teks) -ForegroundColor Green }
function Awas($teks) { Write-Host ('   [ ! ]  ' + $teks) -ForegroundColor Yellow }
function Galat($teks) { Write-Host ('   [ X ]  ' + $teks) -ForegroundColor Red }

function Ukuran-Teks($bita) {
    if ($bita -ge 1MB) { return ('{0:N1} MB' -f ($bita / 1MB)) }
    if ($bita -ge 1KB) { return ('{0:N1} KB' -f ($bita / 1KB)) }
    return ("$bita B")
}

Judul 'BERSIHKAN FOLDER ASSETS - RTS PANEL BY BENE'

# =============================================================================
# 1. FOLDER PROYEK
# =============================================================================

$kandidat = @()

if (-not [string]::IsNullOrWhiteSpace($Proyek)) { $kandidat += $Proyek }

$kandidat += (Get-Location).Path
$kandidat += 'D:\Project\rts_panel_app'
$kandidat += (Join-Path $env:USERPROFILE 'rts_panel_app')

$folderProyek = ''

foreach ($k in $kandidat) {
    if ([string]::IsNullOrWhiteSpace($k)) { continue }

    if (Test-Path (Join-Path $k 'pubspec.yaml')) {
        $folderProyek = (Resolve-Path $k).Path
        break
    }
}

if ($folderProyek -eq '') {
    Awas 'Folder proyek Flutter tidak ditemukan.'
    $jawab = Read-Host '   Tulis lokasi folder proyek (mis. D:\Project\rts_panel_app)'

    if ([string]::IsNullOrWhiteSpace($jawab) -or -not (Test-Path (Join-Path $jawab 'pubspec.yaml'))) {
        Galat 'Folder itu tidak memuat pubspec.yaml. Skrip dihentikan tanpa mengubah apa pun.'
        exit 1
    }

    $folderProyek = (Resolve-Path $jawab).Path
}

Baik "Folder proyek : $folderProyek"

$folderAssets = Join-Path $folderProyek 'assets'

if (-not (Test-Path $folderAssets)) {
    Awas 'Folder assets tidak ada pada proyek ini. Tidak ada yang perlu dibersihkan.'
    exit 0
}

# =============================================================================
# 2. DAFTAR SELURUH BERKAS PADA assets\  (menyeluruh sampai ke anak folder)
# =============================================================================

Judul '1. Memeriksa isi folder assets'

$semua = @(Get-ChildItem -Path $folderAssets -File -Recurse -ErrorAction SilentlyContinue)

if ($semua.Count -eq 0) {
    Info 'Folder assets kosong.'
    exit 0
}

$totalSemua = ($semua | Measure-Object -Property Length -Sum).Sum

Info ("Jumlah berkas : " + $semua.Count)
Info ("Ukuran total  : " + (Ukuran-Teks $totalSemua))
Info ''
Info 'Sepuluh berkas terbesar:'

$urut = $semua | Sort-Object Length -Descending

foreach ($b in ($urut | Select-Object -First 10)) {
    $relatif = $b.FullName.Substring($folderAssets.Length).TrimStart('\')
    Info ('  ' + (Ukuran-Teks $b.Length).PadLeft(10) + '  ' + $relatif)
}

# =============================================================================
# 3. MENENTUKAN BERKAS YANG SEBAIKNYA KELUAR DARI assets\
# =============================================================================

Judul '2. Menentukan berkas yang sebaiknya dikeluarkan dari APK'

$akhiranGambar = @('.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp')

$pindah = @()
$catatan = @()

foreach ($b in $semua) {
    $akhiran = $b.Extension.ToLowerInvariant()
    $nama = $b.Name
    $relatif = $b.FullName.Substring($folderAssets.Length).TrimStart('\')
    $sebab = ''

    if ($akhiran -eq '.sql' -or $akhiran -eq '.sqlite' -or $akhiran -eq '.db') {
        $sebab = 'SALINAN DATABASE - jangan pernah ada di dalam APK, datanya dapat dibaca siapa pun'
    } elseif ($nama -match '\.lama_|\.bak$|\.old$|\.backup$|\.tmp$|\.zip$|\.rar$|\.7z$|\.pdf$|\.csv$|\.xlsx?$|\.docx?$|\.psd$|\.ai$|\.txt$|\.json$|\.ps1$|\.apk$') {
        $sebab = 'bukan gambar / berkas cadangan'
    } elseif ($akhiran -notin $akhiranGambar) {
        $sebab = 'jenis berkas bukan gambar'
    }

    if ($sebab -ne '') {
        $pindah += [pscustomobject]@{
            Berkas  = $b
            Relatif = $relatif
            Sebab   = $sebab
            Ukuran  = $b.Length
        }
    }
}

# Gambar berganda: nama sama, akhiran berbeda (mis. qris_bene_s.jpg dan .jpeg)
$perNama = @{}

foreach ($b in $semua) {
    if ($b.Extension.ToLowerInvariant() -notin $akhiranGambar) { continue }

    $dasar = [System.IO.Path]::GetFileNameWithoutExtension($b.FullName).ToLowerInvariant()
    $kunci = $b.DirectoryName.ToLowerInvariant() + '|' + $dasar

    if (-not $perNama.ContainsKey($kunci)) { $perNama[$kunci] = @() }

    $perNama[$kunci] += $b
}

foreach ($kunci in $perNama.Keys) {
    $kelompok = $perNama[$kunci]

    if ($kelompok.Count -le 1) { continue }

    # Simpan yang .jpg bila ada (itulah yang dipanggil aplikasi), selebihnya
    # diusulkan keluar.
    $utama = $kelompok | Where-Object { $_.Extension.ToLowerInvariant() -eq '.jpg' } | Select-Object -First 1

    if (-not $utama) { $utama = $kelompok | Select-Object -First 1 }

    foreach ($b in $kelompok) {
        if ($b.FullName -eq $utama.FullName) { continue }
        if ($pindah | Where-Object { $_.Berkas.FullName -eq $b.FullName }) { continue }

        $pindah += [pscustomobject]@{
            Berkas  = $b
            Relatif = $b.FullName.Substring($folderAssets.Length).TrimStart('\')
            Sebab   = 'gambar berganda (nama sama, akhiran berbeda)'
            Ukuran  = $b.Length
        }
    }
}

if ($pindah.Count -eq 0) {
    Baik 'Folder assets sudah bersih - hanya berisi gambar yang dipakai aplikasi.'
    Info ''
    Info ('Ukuran assets saat ini : ' + (Ukuran-Teks $totalSemua))
    Info 'Tidak ada berkas yang perlu dipindahkan.'
} else {
    $totalPindah = ($pindah | Measure-Object -Property Ukuran -Sum).Sum

    Info ("Ditemukan " + $pindah.Count + " berkas yang sebaiknya keluar dari assets:")
    Info ''

    foreach ($p in ($pindah | Sort-Object Ukuran -Descending)) {
        Awas ((Ukuran-Teks $p.Ukuran).PadLeft(10) + '  ' + $p.Relatif)
        Info ('             sebab: ' + $p.Sebab)
    }

    Info ''
    Info ('Perkiraan ukuran yang dapat dihemat : ' + (Ukuran-Teks $totalPindah))

    if ($pindah | Where-Object { $_.Sebab -like 'SALINAN DATABASE*' }) {
        Write-Host ''
        Write-Host '   PERHATIAN PENTING' -ForegroundColor Red
        Write-Host '   Ada salinan database di dalam folder assets. Berkas itu ikut' -ForegroundColor Yellow
        Write-Host '   dibungkus ke dalam APK dan dapat dibaca siapa pun yang memegang' -ForegroundColor Yellow
        Write-Host '   APK - termasuk data customer. Sebaiknya segera dipindahkan.' -ForegroundColor Yellow
    }
}

# =============================================================================
# 4. MEMINDAHKAN (bila diminta)
# =============================================================================

if ($pindah.Count -gt 0) {
    if (-not $Pindahkan) {
        Judul '3. BELUM DIPINDAHKAN (mode pemeriksaan)'
        Write-Host '   Skrip ini baru MEMERIKSA. Tidak ada berkas yang diubah.' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '   Untuk benar-benar memindahkan berkas tersebut ke folder di luar' -ForegroundColor White
        Write-Host '   assets (berkas TIDAK dihapus, hanya dipindah):' -ForegroundColor White
        Write-Host ''
        Write-Host '       .\BERSIHKAN_ASSETS.ps1 -Pindahkan' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '   Untuk memindahkan sekaligus membangun APK rilis:' -ForegroundColor White
        Write-Host '       .\BERSIHKAN_ASSETS.ps1 -Pindahkan -Bangun' -ForegroundColor Cyan
        Write-Host ''
    } else {
        Judul '3. Memindahkan berkas ke luar folder assets'

        $folderTujuan = Join-Path $folderProyek ('_di_luar_apk\' + (Get-Date -Format 'yyyy-MM-dd_HHmmss'))

        if (-not (Test-Path $folderTujuan)) {
            New-Item -ItemType Directory -Path $folderTujuan -Force | Out-Null
        }

        $berhasil = 0

        foreach ($p in $pindah) {
            $tujuanBerkas = Join-Path $folderTujuan $p.Relatif
            $folderInduk = Split-Path -Parent $tujuanBerkas

            if (-not (Test-Path $folderInduk)) {
                New-Item -ItemType Directory -Path $folderInduk -Force | Out-Null
            }

            try {
                Move-Item -Path $p.Berkas.FullName -Destination $tujuanBerkas -Force
                $berhasil++
                Baik ('dipindah: ' + $p.Relatif)
            }
            catch {
                Galat ('GAGAL memindahkan: ' + $p.Relatif + ' - ' + $_.Exception.Message)
            }
        }

        Info ''
        Info ("Berkas dipindahkan : $berhasil dari " + $pindah.Count)
        Info ("Tempat penyimpanan : $folderTujuan")
        Info 'Berkas TIDAK dihapus. Bila ternyata masih diperlukan, cukup'
        Info 'salin kembali dari folder itu ke tempat semula.'

        $sisa = @(Get-ChildItem -Path $folderAssets -File -Recurse -ErrorAction SilentlyContinue)
        $totalSisa = ($sisa | Measure-Object -Property Length -Sum).Sum

        Info ''
        Info ('Ukuran assets sebelum : ' + (Ukuran-Teks $totalSemua))
        Info ('Ukuran assets sekarang: ' + (Ukuran-Teks $totalSisa))
    }
}

# =============================================================================
# 5. LANGKAH BERIKUTNYA - MEMBANGUN APK YANG LEBIH KECIL
# =============================================================================

Judul '4. Membangun APK yang lebih kecil'

Write-Host ' Pilihan perintah build (pilih salah satu):' -ForegroundColor White
Write-Host ''
Write-Host '  A. APK biasa (semua jenis HP) - ukuran paling besar:' -ForegroundColor Gray
Write-Host '       flutter clean' -ForegroundColor Cyan
Write-Host '       flutter build apk --release' -ForegroundColor Cyan
Write-Host ''
Write-Host '  B. APK khusus HP MODERN (arm64) - jauh lebih kecil, satu berkas.' -ForegroundColor Gray
Write-Host '     Cocok untuk hampir semua HP tahun 2017 ke atas (termasuk CPH1937):' -ForegroundColor Gray
Write-Host '       flutter clean' -ForegroundColor Cyan
Write-Host '       flutter build apk --release --target-platform android-arm64' -ForegroundColor Cyan
Write-Host ''
Write-Host '  C. TIGA APK terpisah (paling hemat kuota petugas):' -ForegroundColor Gray
Write-Host '       flutter clean' -ForegroundColor Cyan
Write-Host '       flutter build apk --release --split-per-abi' -ForegroundColor Cyan
Write-Host '     Hasilnya tiga berkas di build\app\outputs\flutter-apk\:' -ForegroundColor Gray
Write-Host '       app-arm64-v8a-release.apk    <-- unggah yang INI ke app_versi.php' -ForegroundColor White
Write-Host '       app-armeabi-v7a-release.apk  <-- untuk HP lama' -ForegroundColor Gray
Write-Host '       app-x86_64-release.apk       <-- untuk emulator komputer' -ForegroundColor Gray
Write-Host ''
Write-Host ' Catatan: flutter clean WAJIB dijalankan lebih dahulu setiap kali' -ForegroundColor Yellow
Write-Host ' berganti cara build, supaya hasilnya benar-benar baru.' -ForegroundColor Yellow
Write-Host ''

if ($Bangun) {
    Judul '5. Membangun APK rilis (khusus arm64)'

    $flutter = Get-Command flutter -ErrorAction SilentlyContinue

    if (-not $flutter) {
        Awas 'Perintah flutter tidak ditemukan. Jalankan sendiri di folder proyek:'
        Info '   flutter clean'
        Info '   flutter build apk --release --target-platform android-arm64'
    } else {
        Push-Location $folderProyek

        try {
            Info 'flutter clean...'
            & flutter clean

            Info 'flutter pub get...'
            & flutter pub get

            Info 'flutter build apk --release --target-platform android-arm64...'
            & flutter build apk --release --target-platform android-arm64

            $berkasApk = Join-Path $folderProyek 'build\app\outputs\flutter-apk\app-release.apk'

            if (Test-Path $berkasApk) {
                $ukuranApk = (Get-Item $berkasApk).Length

                Write-Host ''
                Baik ('APK selesai: ' + (Ukuran-Teks $ukuranApk))
                Info ('letak: ' + $berkasApk)
                Info ''
                Info 'Langkah berikutnya: unggah berkas itu ke'
                Info 'https://rts.benedic-s.com/app_versi.php'
            } else {
                Awas 'APK tidak ditemukan setelah build. Periksa pesan galat di atas.'
            }
        }
        catch {
            Awas 'Build gagal dijalankan. Kirimkan tulisan galatnya ke pengembang.'
        }
        finally {
            Pop-Location
        }
    }
}

Write-Host ''
Write-Host ' Selesai. Bila ukuran APK masih besar, periksa bahwa tidak ada berkas' -ForegroundColor Gray
Write-Host ' .sql atau berkas cadangan yang tersisa pada folder assets.' -ForegroundColor Gray
Write-Host ''
