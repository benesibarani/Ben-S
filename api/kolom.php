<?php
/**
 * RTS Panel API - Pemeriksaan Ketersediaan Kolom
 * Berkas: api/kolom.php
 *
 * Berkas kecil ini dipakai bersama oleh login.php, session_check.php, dan
 * api_bootstrap.php untuk memastikan sebuah kolom benar-benar ada pada tabel
 * sebelum dipakai pada perintah SELECT.
 *
 * Gunanya: menambah kolom baru pada database (misalnya kolom akun_pro untuk
 * Akun PRO) tidak akan membuat API yang sudah berjalan menjadi gagal. Selama
 * kolomnya belum ada, API memakai nilai bawaan.
 */

if (!function_exists('rts_api_ada_kolom')) {
    /**
     * Memeriksa keberadaan sebuah kolom pada tabel di database yang aktif.
     *
     * Hasil pemeriksaan disimpan di memori selama satu permintaan, sehingga
     * satu kolom hanya diperiksa sekali walau dipanggil berkali-kali.
     */
    function rts_api_ada_kolom(mysqli $conn, string $tabel, string $kolom): bool
    {
        static $simpanan = [];

        $kunci = $tabel . '.' . $kolom;

        if (array_key_exists($kunci, $simpanan)) {
            return $simpanan[$kunci];
        }

        if ($conn->connect_errno) {
            $simpanan[$kunci] = false;
            return false;
        }

        $stmt = $conn->prepare(
            'SELECT COUNT(*) AS total
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?'
        );

        if (!$stmt) {
            $simpanan[$kunci] = false;
            return false;
        }

        $stmt->bind_param('ss', $tabel, $kolom);
        $stmt->execute();
        $hasil = $stmt->get_result();
        $baris = $hasil ? $hasil->fetch_assoc() : null;
        $stmt->close();

        $ada = $baris && (int) $baris['total'] > 0;

        $simpanan[$kunci] = $ada;

        return $ada;
    }
}

if (!function_exists('rts_api_akun_pro')) {
    /**
     * Membaca penanda Akun PRO dari baris pengguna.
     *
     * Mengembalikan 1 bila akun berlangganan (PRO), 0 bila akun GRATIS atau
     * kolomnya belum ada di database.
     *
     * @param array<string,mixed> $baris
     */
    function rts_api_akun_pro(array $baris): int
    {
        $nilai = $baris['akun_pro'] ?? 0;

        if (is_bool($nilai)) {
            return $nilai ? 1 : 0;
        }

        $teks = strtolower(trim((string) $nilai));

        return ($teks === '1' || $teks === 'true' || $teks === 'ya') ? 1 : 0;
    }
}
