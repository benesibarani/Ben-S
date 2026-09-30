# =============================================================================
#  RTS PANEL BY BENE - PASANG GAMBAR QRIS
#  Berkas : PASANG_GAMBAR_QRIS.ps1
#
#  KEGUNAAN
#  --------
#  Menyalin gambar QRIS milik Bapak ke tempat yang dibaca aplikasi, dengan nama
#  berkas yang benar:
#
#        D:\Project\rts_panel_app\assets\images\qris_bene_s.jpg
#
#  Skrip ini TIDAK mengubah berkas kode apa pun dan TIDAK menghapus berkas.
#  Hanya menyalin satu berkas gambar.
#
#  CARA PAKAI (Windows PowerShell, di dalam folder proyek)
#  ------------------------------------------------------
#        cd D:\Project\rts_panel_app
#        .\PASANG_GAMBAR_QRIS.ps1                 -> mencari sendiri di Unduhan
#        .\PASANG_GAMBAR_QRIS.ps1 -Jalur "C:\...\qris.png"   -> memakai berkas tertentu
#
#  Setelah selesai, jalankan:
#        flutter clean
#        flutter run -d CPH1937
# =============================================================================

param(
    [string]$Jalur = ''
)

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '==================================================================' -ForegroundColor DarkRed
Write-Host ' PASANG GAMBAR QRIS - RTS PANEL BY BENE' -ForegroundColor White
Write-Host '==================================================================' -ForegroundColor DarkRed
Write-Host ''

# ------------------------------------------------------------------ folder proyek
$akar = (Get-Location).Path

if (-not (Test-Path (Join-Path $akar 'pubspec.yaml'))) {
    Write-Host 'PERHATIAN: folder ini sepertinya bukan folder proyek Flutter.' -ForegroundColor Yellow
    Write-Host "Folder sekarang : $akar" -ForegroundColor Gray
    Write-Host 'Jalankan skrip ini dari folder D:\Project\rts_panel_app' -ForegroundColor Yellow
    Write-Host ''
    exit 1
}

$folderGambar = Join-Path $akar 'assets\images'

if (-not (Test-Path $folderGambar)) {
    New-Item -ItemType Directory -Path $folderGambar -Force | Out-Null
    Write-Host "Folder dibuat : $folderGambar" -ForegroundColor Gray
}

$tujuan = Join-Path $folderGambar 'qris_bene_s.jpg'

# ------------------------------------------------------------------ cari berkas
function Cari-GambarQris {
    $folder = @()

    if ($env:USERPROFILE) {
        $folder += (Join-Path $env:USERPROFILE 'Downloads')
        $folder += (Join-Path $env:USERPROFILE 'Desktop')
        $folder += (Join-Path $env:USERPROFILE 'Pictures')
        $folder += (Join-Path $env:USERPROFILE 'OneDrive\Pictures')
        $folder += (Join-Path $env:USERPROFILE 'OneDrive\Downloads')
    }

    $kandidat = @()

    foreach ($f in $folder) {
        if (-not (Test-Path $f)) { continue }

        $kandidat += Get-ChildItem -Path $f -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|webp)$' } |
            Where-Object { $_.Name -match '(?i)qris|bene|whatsapp|wa\d' }
    }

    if ($kandidat.Count -eq 0) { return $null }

    $kandidat = $kandidat | Sort-Object LastWriteTime -Descending

    Write-Host 'Gambar yang ditemukan:' -ForegroundColor Cyan

    $nomor = 1
    foreach ($k in $kandidat | Select-Object -First 8) {
        Write-Host ("  [{0}] {1}" -f $nomor, $k.FullName) -ForegroundColor Gray
        Write-Host ("       diubah {0}" -f $k.LastWriteTime) -ForegroundColor DarkGray
        $nomor++
    }

    Write-Host ''
    $pilih = Read-Host ('Pilih nomor gambar QRIS [1], atau tekan Enter untuk nomor 1')

    if ([string]::IsNullOrWhiteSpace($pilih)) { $pilih = '1' }

    $angka = 0
    if (-not [int]::TryParse($pilih, [ref]$angka)) { $angka = 1 }

    $daftar = @($kandidat | Select-Object -First 8)

    if ($angka -lt 1 -or $angka -gt $daftar.Count) { $angka = 1 }

    return $daftar[$angka - 1].FullName
}

if ([string]::IsNullOrWhiteSpace($Jalur)) {
    $Jalur = Cari-GambarQris

    if (-not $Jalur) {
        Write-Host ''
        Write-Host 'Gambar QRIS tidak ditemukan otomatis.' -ForegroundColor Yellow
        Write-Host 'Jalankan lagi dengan menuliskan lokasi gambarnya, contoh:' -ForegroundColor Yellow
        Write-Host '   .\PASANG_GAMBAR_QRIS.ps1 -Jalur "C:\Users\Bene\Downloads\qris.png"' -ForegroundColor White
        Write-Host ''
        exit 1
    }
}

if (-not (Test-Path $Jalur)) {
    Write-Host "Berkas tidak ditemukan : $Jalur" -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------ salin
try {
    if (Test-Path $tujuan) {
        $cadangan = "$tujuan.lama_$(Get-Date -Format 'ddMM-yyyy_HHmmss')"
        Copy-Item -Path $tujuan -Destination $cadangan -Force
        Write-Host "Gambar lama disimpan : $cadangan" -ForegroundColor Gray
    }

    Copy-Item -Path $Jalur -Destination $tujuan -Force

    $ukuran = (Get-Item $tujuan).Length

    Write-Host ''
    Write-Host 'BERHASIL' -ForegroundColor Green
    Write-Host "  Sumber : $Jalur" -ForegroundColor Gray
    Write-Host "  Tujuan : $tujuan ($([math]::Round($ukuran / 1KB, 1)) KB)" -ForegroundColor Gray
    Write-Host ''
    Write-Host 'Langkah berikutnya:' -ForegroundColor Cyan
    Write-Host '    flutter clean' -ForegroundColor White
    Write-Host '    flutter run -d CPH1937' -ForegroundColor White
    Write-Host ''
    Write-Host 'Lalu buka aplikasi - Profil - Rencana Akun - tombol LANGGANAN PRO.' -ForegroundColor Gray
    Write-Host 'Gambar QRIS harus tampil beserta nominal Rp5.000.' -ForegroundColor Gray
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host 'GAGAL menyalin gambar QRIS:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ''
    exit 1
}
