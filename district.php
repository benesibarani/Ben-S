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
 *  Daftar diambil dari BEBERAPA sumber, lalu digabung:
 *
 *    a. AKUN TIM  - kolom sales_users.sales_district (dibaca dengan
 *       GROUP BY). District baru yang ditambahkan Admin lewat Kelola User
 *       langsung ikut muncul pada formulir pendaftaran.
 *
 *    b. CUSTOMER  - kolom master_toko.sales_district (data customer/outlet).
 *
 *    c. OUTLET TF - kolom master_toko_tf.sales_district (outlet khusus TF).
 *       Bila Bapak menambah outlet baru untuk TF di database, districtnya
 *       OTOMATIS ikut muncul pada kotak pilihan pendaftaran - tidak perlu
 *       diubah lagi di halaman mana pun.
 *
 *    d. DAFTAR BAWAAN - 12 district yang selama ini dipakai halaman
 *       manage_users.php. Dipakai sebagai cadangan supaya formulir tetap
 *       lengkap walau tabelnya masih kosong atau kolomnya belum ada.
 *
 *  Tabel yang belum ada di database dilewati dengan tenang (tidak error),
 *  jadi berkas ini tetap aman dipakai baik master_toko_tf ada maupun tidak.
 *
 *  Perbandingan nama district TIDAK membedakan huruf besar/kecil, sehingga
 *  "MEDAN KOTA" dari database dan "Medan Kota" pada daftar bawaan dianggap
 *  satu district yang sama. Pemeriksaan cakupan data pada aplikasi Android
 *  juga memakai perbandingan UPPER(), jadi keduanya sama-sama bekerja.
 * ============================================================================
 */

if (!defined('RTS_DISTRICT_VERSI')) {
    /** Ditampilkan pada periksa_district.php */
    define('RTS_DISTRICT_VERSI', 2);
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

        /* Keberadaan kolom diperiksa dengan MEMBACA SATU BARIS hasil SHOW
           COLUMNS. Cara ini lebih aman daripada mengandalkan num_rows, sebab
           ada penyedia hosting yang tidak melaporkan jumlah baris pada
           perintah SHOW COLUMNS (num_rows = 0 walau kolomnya ada). */
        $ada = ($hasil->fetch_assoc() !== null);

        $hasil->free();

        return $ada;
    }
}

if (!function_exists('rts_district_sumber_tabel')) {
    /**
     * Tabel-tabel yang ikut menjadi sumber daftar district, berurutan.
     *
     * Nama kolom yang dipakai: `sales_district` (nama yang benar), dengan
     * `district` sebagai cadangan bila suatu saat strukturnya berbeda.
     * Tabel yang belum ada / tanpa kolom district DILEWATI - tidak error.
     *
     * @return array<int,array<string,string>> tiap butir: tabel, kolom, label
     */
    function rts_district_sumber_tabel($conn): array
    {
        $rencana = [
            ['tabel' => 'sales_users',    'label' => 'Akun tim'],
            ['tabel' => 'master_toko',    'label' => 'Customer'],
            ['tabel' => 'master_toko_tf', 'label' => 'Outlet TF'],
        ];

        $pakai = [];

        foreach ($rencana as $satu) {
            $kolom = '';

            foreach (['sales_district', 'district'] as $coba) {
                if (rts_district_kolom_ada($conn, $satu['tabel'], $coba)) {
                    $kolom = $coba;
                    break;
                }
            }

            if ($kolom === '') {
                continue;
            }

            $pakai[] = [
                'tabel' => $satu['tabel'],
                'kolom' => $kolom,
                'label' => $satu['label'],
            ];
        }

        return $pakai;
    }
}

if (!function_exists('rts_district_dari_tabel')) {
    /**
     * Nilai district yang benar-benar ada pada SATU tabel.
     *
     * @return array<string,int>  kunci = district (HURUF BESAR), nilai = jumlah baris
     */
    function rts_district_dari_tabel($conn, string $tabel, string $kolom): array
    {
        if (!rts_district_kolom_ada($conn, $tabel, $kolom)) {
            return [];
        }

        $hasil = @$conn->query(
            'SELECT TRIM(`' . $kolom . '`) AS nilai, COUNT(*) AS jumlah'
            . ' FROM `' . $tabel . '`'
            . ' WHERE TRIM(COALESCE(`' . $kolom . "`, '')) <> ''"
            . ' GROUP BY TRIM(`' . $kolom . '`)'
            . ' ORDER BY jumlah DESC, nilai ASC'
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

            $daftar[strtoupper($nilai)] = (int) $baris['jumlah'];
        }

        $hasil->free();

        return $daftar;
    }
}

if (!function_exists('rts_district_dari_db')) {
    /**
     * Seluruh district yang benar-benar ada di database, DIGABUNG dari:
     *
     *     sales_users.sales_district     (akun tim)
     *     master_toko.sales_district     (data customer/outlet)
     *     master_toko_tf.sales_district  (outlet khusus TF)
     *
     * Tabel yang belum ada dilewati dengan tenang. Hasilnya disimpan di
     * ingatan selama satu permintaan halaman supaya tidak membaca berulang.
     *
     * @return array<string,array<string,mixed>>  kunci = district (huruf besar),
     *         isi = ['nilai', 'jumlah', 'sumber' => [label => jumlah], 'dari_tf']
     */
    function rts_district_dari_db($conn): array
    {
        static $simpan = null;

        if ($simpan !== null) {
            return $simpan;
        }

        $daftar = [];

        foreach (rts_district_sumber_tabel($conn) as $sumber) {
            $per_tabel = rts_district_dari_tabel($conn, $sumber['tabel'], $sumber['kolom']);

            foreach ($per_tabel as $kunci => $jumlah) {
                if (!isset($daftar[$kunci])) {
                    /* Bentuk tulisan yang ditampilkan diambil dari sumber
                       pertama yang memilikinya (akun tim lebih dahulu). */
                    $daftar[$kunci] = [
                        'nilai' => $kunci,
                        'jumlah' => 0,
                        'sumber' => [],
                        'dari_tf' => false,
                    ];
                }

                $daftar[$kunci]['jumlah'] += (int) $jumlah;
                $daftar[$kunci]['sumber'][$sumber['label']] = (int) $jumlah;

                if ($sumber['tabel'] === 'master_toko_tf') {
                    $daftar[$kunci]['dari_tf'] = true;
                }
            }
        }

        /* Tampilan nama: pakai bentuk bawaan bila ada (mis. "Medan Kota"),
           supaya tidak muncul dua tulisan berbeda untuk district yang sama. */
        $bawaan = [];

        foreach (rts_district_bawaan() as $satu) {
            $bawaan[strtoupper($satu)] = $satu;
        }

        foreach ($daftar as $kunci => $butir) {
            $daftar[$kunci]['nilai'] = $bawaan[$kunci] ?? $butir['nilai'];
        }

        $simpan = $daftar;

        return $simpan;
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
                'sumber' => $db[$kunci]['sumber'] ?? [],
                'dari_tf' => (bool) ($db[$kunci]['dari_tf'] ?? false),
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
                'sumber' => $butir['sumber'] ?? [],
                'dari_tf' => (bool) ($butir['dari_tf'] ?? false),
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

if (!function_exists('rts_district_tf_saja')) {
    /**
     * District yang muncul dari OUTLET TF (master_toko_tf) - inilah district
     * yang tadinya belum ada pada pendaftaran sebelum TAMBAHAN 18C.
     *
     * @return array<int,string>
     */
    function rts_district_tf_saja($conn): array
    {
        $hasil = [];

        foreach (rts_district_pilihan($conn) as $butir) {
            if (!empty($butir['dari_tf'])) {
                $hasil[] = (string) $butir['nilai'];
            }
        }

        return $hasil;
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
