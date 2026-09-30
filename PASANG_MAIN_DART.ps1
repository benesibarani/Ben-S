# =============================================================================
#  RTS PANEL BY BENE - MEMASANG main.dart KE TEMPAT YANG BENAR
#  Berkas : PASANG_MAIN_DART.ps1
#
#  MASALAH YANG DISELESAIKAN
#  -------------------------
#  Flutter membangun aplikasi dari berkas:   lib\main.dart
#  Bukan dari berkas main.dart yang berada di akar folder proyek.
#
#  Bila kode baru hanya ada pada main.dart (akar) sementara lib\main.dart
#  masih versi lama, maka:
#      - build BERHASIL, aplikasi terpasang, tetapi TAMPILAN TIDAK BERUBAH
#      - inilah sebabnya perbaikan cuaca tidak tampak di HP
#
#  CARA KERJA SKRIP INI
#  ---------------------
#  1. Membaca penanda kode (rtsKodeAplikasi) pada main.dart dan lib\main.dart
#  2. Menyalin yang PALING BARU ke lib\main.dart
#  3. Berkas lib\main.dart yang lama DICADANGKAN lebih dahulu
#     (nama: lib\main.dart.lama_thnnn-bb-tt_jjmmss)
#  4. Memeriksa hasilnya dan menunjukkan langkah berikutnya
#
#  CARA PAKAI  (PowerShell, di folder D:\Project\rts_panel_app)
#  -----------------------------------------------------------
#     .\PASANG_MAIN_DART.ps1
#
#  Setelah itu jalankan:
#     flutter clean
#     flutter run -d CPH1937
# =============================================================================

$harapan = 'RTS-2026-10-01-9'

function TulisJudul($teks) {
    Write-Host ""
    Write-Host "===============================================================" -ForegroundColor DarkGray
    Write-Host "  $teks" -ForegroundColor White
    Write-Host "===============================================================" -ForegroundColor DarkGray
}

function TulisHasil($ok, $teks) {
    if ($ok) { Write-Host "   [BENAR] $teks" -ForegroundColor Green }
    else { Write-Host "   [PERLU DIPERBAIKI] $teks" -ForegroundColor Yellow }
}

function AmbilPenanda($jalur) {
    if (-not (Test-Path $jalur)) { return "" }

    $isi = Get-Content $jalur -Raw

    if ($isi -match "rtsKodeAplikasi\s*=\s*'([^']+)'") {
        return $Matches[1]
    }

    return ""
}

Write-Host ""
Write-Host "RTS PANEL BY BENE - MEMASANG main.dart KE lib\main.dart" -ForegroundColor Cyan
Write-Host "Flutter membangun aplikasi dari lib\main.dart (bukan dari main.dart akar)." -ForegroundColor DarkGray

# -----------------------------------------------------------------------------
# 1. Memeriksa letaknya
# -----------------------------------------------------------------------------
TulisJudul "1. Memeriksa berkas"

if (-not (Test-Path "pubspec.yaml")) {
    Write-Host "   Folder ini bukan folder proyek Flutter (pubspec.yaml tidak ada)." -ForegroundColor Red
    Write-Host "   Buka PowerShell di D:\Project\rts_panel_app, lalu ulangi." -ForegroundColor Yellow
    exit 1
}

$adaAkar = Test-Path "main.dart"
$adaLib = Test-Path "lib\main.dart"

TulisHasil $adaAkar "main.dart (akar folder)"
TulisHasil $adaLib "lib\main.dart (berkas yang dibangun Flutter)"

$kodeAkar = AmbilPenanda "main.dart"
$kodeLib = AmbilPenanda "lib\main.dart"

Write-Host ""
Write-Host "   Kode pada main.dart      : $(if ($kodeAkar) { $kodeAkar } else { '(tidak ada penanda / versi lama)' })" -ForegroundColor Gray
Write-Host "   Kode pada lib\main.dart  : $(if ($kodeLib) { $kodeLib } else { '(tidak ada penanda / versi lama)' })" -ForegroundColor Gray
Write-Host "   Kode yang diharapkan     : $harapan" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 2. Menentukan perlu disalin atau tidak
# -----------------------------------------------------------------------------
TulisJudul "2. Menentukan berkas yang dipakai"

if ($kodeLib -eq $harapan -and $kodeAkar -eq $harapan) {
    Write-Host "   KEDUA berkas sudah versi terbaru - tidak ada yang perlu disalin." -ForegroundColor Green
    Write-Host ""
    Write-Host "   Bila tampilan di HP masih belum berubah, jalankan:" -ForegroundColor White
    Write-Host "     flutter clean" -ForegroundColor Gray
    Write-Host "     flutter run -d <nama HP>" -ForegroundColor Gray
    exit 0
}

if ($kodeAkar -eq "" -and $kodeLib -eq "") {
    Write-Host ""
    Write-Host "   Kedua berkas TIDAK memuat penanda kode terbaru." -ForegroundColor Red
    Write-Host "   Berarti main.dart dari paket baru belum diekstrak ke folder ini." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   Ekstrak RTS_PANEL_FITUR_BARU.zip ke folder ini (pilih Timpa)," -ForegroundColor White
    Write-Host "   lalu jalankan skrip ini lagi." -ForegroundColor White
    exit 1
}

if ($kodeLib -eq $harapan) {
    Write-Host "   lib\main.dart sudah versi terbaru - tidak perlu disalin." -ForegroundColor Green
}
else {
    # Sumber: main.dart akar bila bernilai harapan, atau bila penandanya lebih
    # besar (lebih baru) daripada yang ada pada lib\main.dart.
    $pakaiAkar = $false

    if ($kodeAkar -eq $harapan) {
        $pakaiAkar = $true
    }
    elseif ($kodeAkar -ne "" -and $kodeAkar -gt $kodeLib) {
        $pakaiAkar = $true
    }

    if ($pakaiAkar) {
        Write-Host "   main.dart (akar) LEBIH BARU daripada lib\main.dart." -ForegroundColor Yellow
        Write-Host "   Berkas ini akan disalin ke lib\main.dart." -ForegroundColor White
    }
    else {
        Write-Host ""
        Write-Host "   main.dart (akar) TIDAK lebih baru daripada lib\main.dart." -ForegroundColor Red
        Write-Host "   Kemungkinan paket baru belum diekstrak ke folder ini." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "   Langkah: ekstrak RTS_PANEL_FITUR_BARU.zip ke folder ini" -ForegroundColor White
        Write-Host "   (pilih Timpa / Replace), lalu jalankan skrip ini lagi." -ForegroundColor White
        exit 1
    }
}

# -----------------------------------------------------------------------------
# 3. Menyalin (dengan cadangan)
# -----------------------------------------------------------------------------
TulisJudul "3. Menyalin ke lib\main.dart"

$waktu = Get-Date -Format "yyyy-MM-dd_HHmmss"

if ($adaLib) {
    $cadangan = "lib\main.dart.lama_$waktu"

    Copy-Item "lib\main.dart" $cadangan -Force

    if (Test-Path $cadangan) {
        Write-Host "   Cadangan berkas lama : $cadangan" -ForegroundColor Green
    }
    else {
        Write-Host "   Cadangan GAGAL dibuat - penyalinan dibatalkan demi keamanan." -ForegroundColor Red
        exit 1
    }
}

Copy-Item "main.dart" "lib\main.dart" -Force

$kodeSetelah = AmbilPenanda "lib\main.dart"

Write-Host ""

if ($kodeSetelah -eq $harapan) {
    TulisHasil $true "lib\main.dart sekarang memuat kode $kodeSetelah"
}
else {
    TulisHasil $false "Penyalinan belum berhasil (kode terbaca: $kodeSetelah)"
    exit 1
}

# -----------------------------------------------------------------------------
# 4. Langkah berikutnya
# -----------------------------------------------------------------------------
TulisJudul "SELESAI - LANGKAH BERIKUTNYA"

Write-Host "   Jalankan berurutan:" -ForegroundColor White
Write-Host ""
Write-Host "     1. flutter clean" -ForegroundColor Cyan
Write-Host "        (menghapus hasil build lama supaya kode baru benar-benar dipakai)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "     2. flutter run -d CPH1937" -ForegroundColor Cyan
Write-Host "        (ganti CPH1937 dengan nama HP Bapak - lihat dengan" -ForegroundColor DarkGray
Write-Host "         perintah: flutter devices)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "   Bila hanya ingin memasang tanpa menjalankan:" -ForegroundColor White
Write-Host "     flutter build apk --debug" -ForegroundColor Gray
Write-Host "     .\ADB.ps1 pasang" -ForegroundColor Gray
Write-Host ""
Write-Host "   Setelah aplikasi terbuka di HP:" -ForegroundColor White
Write-Host "     1. Buka menu Pengaturan - bagian 'CUACA BERANDA'" -ForegroundColor Gray
Write-Host "     2. Kode aplikasi pada kotak merah muda HARUS terbaca:" -ForegroundColor Gray
Write-Host "            $harapan" -ForegroundColor Cyan
Write-Host "     3. Buka beranda - kotak Cuaca ada di samping nama Admin" -ForegroundColor Gray
Write-Host ""
Write-Host "   Bila kode aplikasi masih berbeda, berarti aplikasi di HP belum" -ForegroundColor Yellow
Write-Host "   tergantikan - jalankan lagi: .\PASANG_CEPAT.ps1" -ForegroundColor Yellow
Write-Host ""
