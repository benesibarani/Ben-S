<?php
/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - TIRUAN DATABASE (bukan untuk hosting)
 *  Berkas : perkakas/uji_mysqli_tiruan.php
 *
 *  Berkas ini membuat kelas TURUNAN dari mysqli / mysqli_stmt / mysqli_result
 *  yang menjawab sendiri tanpa server MySQL. Dipakai perkakas/uji_cctv_api.mjs
 *  untuk menguji api/cctv.php di komputer.
 *
 *  ATURAN YANG DIPELAJARI DARI PENGUJIAN SEBELUMNYA (jangan diubah):
 *    - Kelas DASAR (mysqli, mysqli_stmt, mysqli_result) tidak boleh ditulis
 *      ulang - ekstensi aslinya ada di PHP. Tiruan harus kelas TURUNAN.
 *    - Tanda tangan (signature) harus SAMA PERSIS dengan kelas aslinya,
 *      misalnya mysqli::query(string $query, int $result_mode = ...).
 *    - Properti bawaan (num_rows, connect_errno, error, ...) TIDAK dapat
 *      dibaca pada objek tiruan -> fungsi yang membacanya (rts_lg_ada_kolom,
 *      rts_lg_ada_tabel, rts_api_ada_kolom) DIGANTI tiruannya lebih dahulu.
 *    - mysqli_stmt::execute() WAJIB mengembalikan bool.
 *    - Keadaan uji 'tabel_program' = true berarti tabel rts_program_produk ada,
 *      dan 'program' = daftar barisnya (dipakai perkakas/uji_program_api.mjs).
 * ============================================================================
 */

/** Tiruan hasil query. */
class RtsUjiHasil extends mysqli_result
{
    /** Sama dengan tipe kelas aslinya (string|int). */
    public string|int $num_rows = 0;

    /** @var array<int,array<string,mixed>> */
    private array $baris;

    private int $posisi = 0;

    /**
     * @param array<int,array<string,mixed>> $baris
     */
    public function __construct(array $baris = [])
    {
        // CATATAN: numa_rows milik kelas asli bersifat READ-ONLY (properti
        // maya milik ekstensi mysqli), jadi TIDAK boleh ditulis di sini.
        // Karena itu jumlah baris tidak disimpan - fungsi yang memakainya
        // (rts_lg_ada_kolom dan kawan-kawan) sudah diganti tiruannya.
        $this->baris = $baris;
    }

    public function fetch_assoc(): ?array
    {
        return $this->baris[$this->posisi++] ?? null;
    }

    public function fetch_row(): ?array
    {
        $baris = $this->baris[$this->posisi++] ?? null;

        return $baris === null ? null : array_values($baris);
    }

    public function fetch_array(int $mode = MYSQLI_BOTH): ?array
    {
        return $this->fetch_assoc();
    }

    public function free(): void
    {
    }
}

/** Tiruan pernyataan (prepared statement). */
class RtsUjiStmt extends mysqli_stmt
{
    private string $sql;

    /** @var array<int,mixed> */
    private array $nilai = [];

    public function __construct(string $sql = '')
    {
        $this->sql = $sql;
    }

    public function bind_param(string $types, mixed &...$vars): bool
    {
        $this->nilai = $vars;

        return true;
    }

    public function execute(?array $params = null): bool
    {
        return true;
    }

    public function get_result(): mysqli_result|false
    {
        return new RtsUjiHasil(rts_uji_baris_untuk($this->sql, $this->nilai));
    }

    public function close(): bool
    {
        return true;
    }
}

/** Tiruan koneksi database. */
class RtsUjiDb extends mysqli
{
    /** @var array<string,mixed> Keadaan yang sedang diuji (dibaca dari keadaan.json). */
    public static array $keadaan = [];

    public function __construct()
    {
    }

    public function set_charset(string $charset): bool
    {
        return true;
    }

    public function real_escape_string(string $string): string
    {
        return addslashes($string);
    }

    public function query(string $query, int $result_mode = MYSQLI_STORE_RESULT): mysqli_result|bool
    {
        // api/program.php memakai SHOW TABLES LIKE 'rts_program_produk'.
        // Jawabannya mengikuti keadaan uji 'tabel_program'.
        if (stripos($query, 'show tables') !== false) {
            if (stripos($query, 'rts_program_produk') !== false) {
                return new RtsUjiHasil(
                    empty(self::$keadaan['tabel_program'])
                        ? []
                        : [['Tables_in_uji' => 'rts_program_produk']]
                );
            }

            return new RtsUjiHasil([]);
        }

        return true;
    }

    public function prepare(string $query): mysqli_stmt|false
    {
        return new RtsUjiStmt($query);
    }
}

/**
 * Menentukan baris jawaban untuk sebuah perintah SELECT.
 *
 * @param array<int,mixed> $nilai
 * @return array<int,array<string,mixed>>
 */
function rts_uji_baris_untuk(string $sql, array $nilai): array
{
    $keadaan = RtsUjiDb::$keadaan;
    $kecil = strtolower($sql);

    if (strpos($kecil, 'from api_tokens') !== false) {
        if (empty($keadaan['token_ada'])) {
            return [];
        }

        $user = $keadaan['user'] ?? [];

        return [[
            'token_id' => (int) ($keadaan['token_id'] ?? 1),
            'expires_at' => (string) ($keadaan['token_berlaku'] ?? date('Y-m-d H:i:s', time() + 86400)),
            'id' => (int) ($user['id'] ?? 1),
            'username' => (string) ($user['username'] ?? 'sales_uji'),
            'nama_lengkap' => (string) ($user['nama_lengkap'] ?? 'Sales Uji'),
            'email' => (string) ($user['email'] ?? 'uji@contoh.id'),
            'role' => (string) ($user['role'] ?? 'RTS'),
            'salesman' => (string) ($user['salesman'] ?? 'UJI'),
            'sales_district' => (string) ($user['sales_district'] ?? 'MEDAN KOTA'),
            'status_aktif' => (string) ($user['status_aktif'] ?? 'Aktif'),
            'akun_pro' => (int) ($user['akun_pro'] ?? 0),
        ]];
    }

    if (strpos($kecil, 'from rts_program_produk') !== false) {
        $program = $keadaan['program'] ?? [];

        if (!is_array($program)) {
            return [];
        }

        $baris = [];

        foreach ($program as $satu) {
            if (!is_array($satu)) {
                continue;
            }

            if (strpos($kecil, 'where jenis') !== false) {
                $jenis = strtoupper((string) ($satu['jenis'] ?? 'INTRODEAL'));

                if ($jenis !== strtoupper((string) ($nilai[0] ?? ''))) {
                    continue;
                }
            }

            $baris[] = [
                'id' => (int) ($satu['id'] ?? (count($baris) + 1)),
                'jenis' => (string) ($satu['jenis'] ?? 'INTRODEAL'),
                'sku' => (string) ($satu['sku'] ?? ''),
                'barcode_pack' => (string) ($satu['barcode_pack'] ?? ''),
                'nama' => (string) ($satu['nama'] ?? ''),
                'merek' => (string) ($satu['merek'] ?? ''),
                'isi_per_pack' => (int) ($satu['isi_per_pack'] ?? 0),
                'catatan' => (string) ($satu['catatan'] ?? ''),
                'periode' => (string) ($satu['periode'] ?? ''),
                'aktif' => (int) ($satu['aktif'] ?? 1),
                'diubah_oleh' => (string) ($satu['diubah_oleh'] ?? ''),
                'diubah_pada' => (string) ($satu['diubah_pada'] ?? ''),
            ];
        }

        return $baris;
    }

    if (strpos($kecil, 'from sales_users') !== false) {
        $langganan = $keadaan['langganan'] ?? null;

        if (!is_array($langganan)) {
            return [];
        }

        return [[
            'id' => (int) ($langganan['id'] ?? 1),
            'username' => (string) ($langganan['username'] ?? 'sales_uji'),
            'nama_lengkap' => (string) ($langganan['nama_lengkap'] ?? 'Sales Uji'),
            'email' => (string) ($langganan['email'] ?? 'uji@contoh.id'),
            'role' => (string) ($langganan['role'] ?? 'RTS'),
            'akun_pro' => (int) ($langganan['akun_pro'] ?? 0),
            'pro_mulai' => (string) ($langganan['pro_mulai'] ?? ''),
            'pro_selesai' => (string) ($langganan['pro_selesai'] ?? ''),
            'trial_mulai' => (string) ($langganan['trial_mulai'] ?? ''),
            'trial_selesai' => (string) ($langganan['trial_selesai'] ?? ''),
            'foto_profil' => (string) ($langganan['foto_profil'] ?? ''),
        ]];
    }

    return [];
}
