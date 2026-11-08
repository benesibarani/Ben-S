<?php
/**
 * RTS Panel API - Penanda toko baru dari upload Master Customer.
 *
 * Tabel master_toko_baru menyimpan ID customer yang BARU DITAMBAHKAN lewat
 * upload CSV, beserta waktu masuknya. Toko yang sudah ada sebelum upload tidak
 * ditandai, jadi mode "Ganti semua" pun tidak membuat seluruh daftar tampak baru.
 *
 * Toko dianggap baru selama RTS_MTB_HARI hari sejak waktu masuk.
 */

const RTS_MTB_HARI = 14;

/**
 * Memastikan tabel penanda tersedia. Mengembalikan false bila gagal, sehingga
 * pemanggil tetap berjalan tanpa penanda.
 * CATATAN: CREATE TABLE menyebabkan commit otomatis di MySQL. Panggil fungsi ini
 * SEBELUM begin_transaction().
 */
function rts_mtb_pastikan_tabel(mysqli $conn): bool
{
    static $siap = null;

    if ($siap !== null) {
        return $siap;
    }

    $siap = (bool) $conn->query(
        'CREATE TABLE IF NOT EXISTS master_toko_baru (
            id_customer VARCHAR(50) NOT NULL PRIMARY KEY,
            sejak DATETIME NOT NULL,
            INDEX idx_mtb_sejak (sejak)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4'
    );

    if (!$siap) {
        error_log('RTS master_toko_baru: ' . $conn->error);
    }

    return $siap;
}
