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
 *
 * CATATAN PENTING TENTANG PENYIMPANAN DI cPanel
 * ---------------------------------------------
 * Pemeriksaan TIDAK memakai tabel information_schema, karena akun database
 * pada sebagian hosting cPanel tidak diberi izin membaca tabel itu. Bila
 * dipaksakan, muncul kesalahan:
 *
 *     #1044 - Access denied for user 'cpses_...'@'localhost'
 *             to database 'information_schema'
 *
 * Sebagai gantinya dipakai perintah SHOW COLUMNS, yang selalu tersedia pada
 * akun database biasa sekaligus lebih ringan.
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

        // Nama tabel dan kolom hanya boleh berisi huruf, angka, dan garis
        // bawah. Selain itu ditolak, sebagai pengaman.
        if (preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1
            || preg_match('/^[A-Za-z0-9_]+$/', $kolom) !== 1) {
            $simpanan[$kunci] = false;
            return false;
        }

        $hasil = @$conn->query(
            'SHOW COLUMNS FROM `' . $tabel . '` LIKE \''
            . $conn->real_escape_string($kolom) . '\''
        );

        $ada = ($hasil instanceof mysqli_result) && $hasil->num_rows > 0;

        if ($hasil instanceof mysqli_result) {
            $hasil->free();
        }

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
