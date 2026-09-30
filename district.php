<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - DAFTAR SALES DISTRICT
 *  Berkas : district.php   (letakkan di public_html, satu folder dengan
 *                           index.php dan daftar.php)
 *
 *  KEGUNAAN
 *  --------
 *  Menyediakan satu sumber daftar Sales District untuk seluruh halaman:
 *
 *    1. daftar.php            - formulir pendaftaran tim Sales
 *    2. periksa_district.php  - pemeriksa isi sales_district pada database
 *    3. halaman lain yang memerlukannya (misalnya pendaftaran ulang)
 *
 *  CARA KERJA
 *  ----------
 *  Daftar diambil dari DUA sumber, lalu digabung:
 *
 *    a. DATABASE - nilai yang BENAR-BENAR ADA pada kolom
 *       sales_users.sales_district (dibaca dengan SELECT DISTINCT). Inilah
 *       sebabnya daftar ini selalu sama dengan isi database Bapak; bila ada
 *       district baru yang ditambahkan Admin lewat Kelola User, district itu
 *       langsung ikut muncul pada formulir pendaftaran.
 *
 *    b. DAFTAR BAWAAN - 12 district yang selama ini dipakai halaman
 *       manage_users.php. Dipakai sebagai cadangan supaya formulir tetap
 *       lengkap walau tabel sales_users masih kosong atau kolomnya belum ada.
 *
 *  Perbandingan nama district TIDAK membedakan huruf besar/kecil, sehingga
 *  "MEDAN KOTA" dari database dan "Medan Kota" pada daftar bawaan dianggap
 *  satu district yang sama. Pemeriksaan cakupan data pada aplikasi Android
 *  juga memakai perbandingan UPPER(), jadi keduanya sama-sama bekerja.
 * ============================================================================
 */

if (!defined('RTS_DISTRICT_VERSI')) {
    /** Ditampilkan pada periksa_district.php */
    define('RTS_DISTRICT_VERSI', 1);
}

if (!function_exists('rts_district_bawaan')) {
    /**
     * Daftar district bawaan (sama dengan yang dipakai manage_users.php).
     *
     * @return array<int,string>
     */
    function rts_district_bawaan(): array
    {
        return [
            'Medan Amplas',
            'Medan Helvetia',
            'Medan Johor',
            'Medan Kota',
            'Medan Perjuangan',
            'Medan Petisah',
            'Medan Marelan',
            'Medan Selayang',
            'Hamparan Perak',
            'Sunggal Deli',
            'Pancur Batu',
            'Modren Trade',
        ];
    }
}

if (!function_exists('rts_district_kolom_ada')) {
    /**
     * Memeriksa keberadaan sebuah kolom pada sebuah tabel.
     * Memakai SHOW COLUMNS (bukan information_schema) karena akun database
     * cPanel tidak diberi izin membacanya.
     */
    function rts_district_kolom_ada($conn, string $tabel, string $kolom): bool
    {
        if (!($conn instanceof mysqli)) {
            return false;
        }

        if (preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1 || preg_match('/^[A-Za-z0-9_]+$/', $kolom) !== 1) {
            return false;
        }

        $hasil = @$conn->query('SHOW COLUMNS FROM ' . $tabel . " LIKE '" . $conn->real_escape_string($kolom) . "'");

        if (!($hasil instanceof mysqli_result)) {
            return false;
        }

        $ada = $hasil->num_rows > 0;
        $hasil->free();

        return $ada;
    }
}

if (!function_exists('rts_district_dari_db')) {
    /**
     * Nilai sales_district yang benar-benar ada pada tabel sales_users.
     *
     * @return array<string,array<string,mixed>>  kunci = district (huruf besar),
     *         isi = ['nilai' => nilai asli, 'jumlah' => jumlah akun]
     */
    function rts_district_dari_db($conn): array
    {
        if (!rts_district_kolom_ada($conn, 'sales_users', 'sales_district')) {
            return [];
        }

        $hasil = @$conn->query(
            "SELECT sales_district AS nilai, COUNT(*) AS jumlah
             FROM sales_users
             WHERE TRIM(COALESCE(sales_district, '')) <> ''
             GROUP BY sales_district
             ORDER BY jumlah DESC, sales_district ASC"
        );

        if (!($hasil instanceof mysqli_result)) {
            return [];
        }

        $daftar = [];

        while ($baris = $hasil->fetch_assoc()) {
            $nilai = trim((string) $baris['nilai']);

            if ($nilai === '') {
                continue;
            }

            $daftar[strtoupper($nilai)] = [
                'nilai' => $nilai,
                'jumlah' => (int) $baris['jumlah'],
            ];
        }

        $hasil->free();

        return $daftar;
    }
}

if (!function_exists('rts_district_pilihan')) {
    /**
     * Daftar district untuk kotak pilihan (dropdown) pada formulir.
     *
     * Urutannya: daftar bawaan lebih dahulu (supaya susunannya tidak berubah),
     * lalu district tambahan yang hanya ada di database.
     *
     * @return array<int,array<string,mixed>>  tiap butir: nilai, dari_db, jumlah
     */
    function rts_district_pilihan($conn): array
    {
        $db = rts_district_dari_db($conn);
        $pilihan = [];
        $sudah = [];

        foreach (rts_district_bawaan() as $bawaan) {
            $kunci = strtoupper($bawaan);

            $pilihan[] = [
                'nilai' => $bawaan,
                'dari_db' => isset($db[$kunci]),
                'jumlah' => (int) ($db[$kunci]['jumlah'] ?? 0),
            ];

            $sudah[$kunci] = true;
        }

        $tambahan = [];

        foreach ($db as $kunci => $butir) {
            if (isset($sudah[$kunci])) {
                continue;
            }

            $tambahan[] = [
                'nilai' => (string) $butir['nilai'],
                'dari_db' => true,
                'jumlah' => (int) $butir['jumlah'],
            ];
        }

        usort($tambahan, static function (array $a, array $b): int {
            return strcasecmp((string) $a['nilai'], (string) $b['nilai']);
        });

        foreach ($tambahan as $butir) {
            $pilihan[] = $butir;
        }

        return $pilihan;
    }
}

if (!function_exists('rts_district_sah')) {
    /**
     * Memeriksa apakah sebuah nama district termasuk daftar yang sah.
     */
    function rts_district_sah($conn, string $nilai): bool
    {
        $nilai = trim($nilai);

        if ($nilai === '') {
            return false;
        }

        foreach (rts_district_pilihan($conn) as $butir) {
            if (strcasecmp((string) $butir['nilai'], $nilai) === 0) {
                return true;
            }
        }

        return false;
    }
}

if (!function_exists('rts_district_rapikan')) {
    /**
     * Mengembalikan bentuk baku (bawaan) sebuah nama district bila serupa,
     * contoh: "MEDAN KOTA" -> "Medan Kota". Nama yang tidak dikenal
     * dikembalikan apa adanya setelah spasi berlebih dibuang.
     */
    function rts_district_rapikan($conn, string $nilai): string
    {
        $nilai = trim(preg_replace('/\s+/', ' ', $nilai) ?? $nilai);

        if ($nilai === '') {
            return '';
        }

        foreach (rts_district_pilihan($conn) as $butir) {
            if (strcasecmp((string) $butir['nilai'], $nilai) === 0) {
                return (string) $butir['nilai'];
            }
        }

        return $nilai;
    }
}
