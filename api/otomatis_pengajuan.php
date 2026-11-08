<?php
/**
 * RTS Panel - Tugas otomatis pengajuan Sales (JALANKAN LEWAT CRON, BUKAN BROWSER)
 *
 * Aturan:
 *  1. Pengajuan Sales yang masih Pending lebih dari 60 hari sejak tanggal_request
 *     -> status menjadi Disetujui. Hanya STATUS yang berubah, master_toko TIDAK
 *     diubah (admin biasanya sudah mengubah datanya secara langsung).
 *  2. Pengajuan Sales yang sudah Disetujui/Ditolak lebih dari 30 hari sejak
 *     diproses -> dipindah ke tabel pengajuan_sales_arsip, lalu dihapus dari
 *     pengajuan_sales. Data arsip tetap ada di database.
 *
 * Contoh pengaturan cron di cPanel (setiap hari pukul 01:00 WIB):
 *   /usr/local/bin/php /home/USER_CPANEL/public_html/api/otomatis_pengajuan.php >/dev/null 2>&1
 *
 * Uji manual lewat terminal:
 *   php api/otomatis_pengajuan.php
 */

if (PHP_SAPI !== 'cli') {
    http_response_code(403);
    echo "Tugas ini hanya dapat dijalankan dari cron (CLI).\n";
    exit;
}

require_once __DIR__ . '/api_bootstrap.php';

const RTS_OTOMATIS_SETUJUI_HARI = 60;
const RTS_OTOMATIS_ARSIP_HARI = 30;

$conn = rts_api_db();

$punyaProcessedAt = rts_api_ada_kolom($conn, 'pengajuan_sales', 'processed_at');
$punyaProcessedBy = rts_api_ada_kolom($conn, 'pengajuan_sales', 'processed_by');
$punyaApprovalNote = rts_api_ada_kolom($conn, 'pengajuan_sales', 'approval_note');

$waktuSekarang = time();
$batasSetujui = date('Y-m-d H:i:s', $waktuSekarang - (RTS_OTOMATIS_SETUJUI_HARI * 86400));
$batasArsip = date('Y-m-d H:i:s', $waktuSekarang - (RTS_OTOMATIS_ARSIP_HARI * 86400));
$sekarang = date('Y-m-d H:i:s', $waktuSekarang);

/* ------------------------------------------- 1. Pending > 60 hari -> Disetujui */

$set = ["status_approval = 'Disetujui'"];
$tipe = '';
$nilai = [];

if ($punyaProcessedBy) {
    $set[] = 'processed_by = ?';
    $tipe .= 's';
    $nilai[] = 'SISTEM';
}

if ($punyaProcessedAt) {
    $set[] = 'processed_at = ?';
    $tipe .= 's';
    $nilai[] = $sekarang;
}

if ($punyaApprovalNote) {
    $set[] = 'approval_note = ?';
    $tipe .= 's';
    $nilai[] = 'Otomatis disetujui sistem: belum diproses lebih dari ' . RTS_OTOMATIS_SETUJUI_HARI . ' hari.';
}

$tipe .= 's';
$nilai[] = $batasSetujui;

$sqlSetujui = 'UPDATE pengajuan_sales SET ' . implode(', ', $set)
    . " WHERE status_approval = 'Pending' AND tanggal_request IS NOT NULL AND tanggal_request < ?";

$stmt = $conn->prepare($sqlSetujui);

if (!$stmt) {
    fwrite(STDERR, 'Gagal menyiapkan pengajuan otomatis: ' . $conn->error . "\n");
    exit(1);
}

$stmt->bind_param($tipe, ...$nilai);
$stmt->execute();
$jumlahDisetujui = $stmt->affected_rows;
$stmt->close();

echo 'Pending > ' . RTS_OTOMATIS_SETUJUI_HARI . ' hari -> Disetujui: ' . $jumlahDisetujui . " pengajuan\n";

/* --------------------------------- 2. Diproses > 30 hari -> arsip, lalu hapus */

if (!$punyaProcessedAt) {
    echo "Pengarsipan dilewati: kolom processed_at belum ada di pengajuan_sales.\n";
    exit(0);
}

/* DDL (CREATE TABLE) menyebabkan commit otomatis di MySQL, jadi dijalankan
   sebelum transaksi dimulai. */
$buatArsip = $conn->query('CREATE TABLE IF NOT EXISTS pengajuan_sales_arsip LIKE pengajuan_sales');

if (!$buatArsip) {
    fwrite(STDERR, 'Gagal menyiapkan tabel arsip: ' . $conn->error . "\n");
    exit(1);
}

$kondisiArsip = "status_approval IN ('Disetujui', 'Ditolak') AND processed_at IS NOT NULL AND processed_at < ?";

$conn->begin_transaction();

try {
    $salin = $conn->prepare(
        'INSERT INTO pengajuan_sales_arsip SELECT * FROM pengajuan_sales WHERE ' . $kondisiArsip
    );

    if (!$salin) {
        throw new RuntimeException('Gagal menyiapkan salinan arsip: ' . $conn->error);
    }

    $salin->bind_param('s', $batasArsip);
    $salin->execute();
    $jumlahArsip = $salin->affected_rows;
    $salin->close();

    $hapus = $conn->prepare('DELETE FROM pengajuan_sales WHERE ' . $kondisiArsip);

    if (!$hapus) {
        throw new RuntimeException('Gagal menyiapkan penghapusan: ' . $conn->error);
    }

    $hapus->bind_param('s', $batasArsip);
    $hapus->execute();
    $jumlahHapus = $hapus->affected_rows;
    $hapus->close();

    if ($jumlahArsip !== $jumlahHapus) {
        throw new RuntimeException('Jumlah arsip (' . $jumlahArsip . ') dan hapus (' . $jumlahHapus . ') tidak sama. Dibatalkan.');
    }

    $conn->commit();

    echo 'Diproses > ' . RTS_OTOMATIS_ARSIP_HARI . ' hari -> diarsipkan dan dihapus: ' . $jumlahHapus . " pengajuan\n";
} catch (Throwable $galat) {
    $conn->rollback();
    fwrite(STDERR, 'Pengarsipan dibatalkan: ' . $galat->getMessage() . "\n");
    exit(1);
}

exit(0);
