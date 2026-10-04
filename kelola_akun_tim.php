<?php
/*
 * ============================================================================
 *  RTS PANEL BY BENE - KELOLA AKUN TIM (UNTUK ADMIN DAN ASS)
 *  Berkas : kelola_akun_tim.php
 *  Letakkan di : public_html (satu folder dengan dashboard.php, sidebar.php,
 *                manage_users.php, dan district.php)
 *
 *  KEGUNAAN
 *  --------
 *  Memberi ASS (Assistant) menu sendiri untuk mengurus akun TIM SALES:
 *
 *      - MENGEDIT  : nama, email, username, salesman, district, status,
 *                    masa PRO, dan password akun WSS / SMST / RTS / TF
 *      - MENGHAPUS : akun WSS/SMST/RTS/TF DIHAPUS PERMANEN, tetapi SELURUH
 *                    datanya disalin lebih dahulu ke tabel arsip
 *                    `sales_users_arsip` sehingga masih dapat dipulihkan
 *
 *  BATAS KEWENANGAN (PENTING - INI YANG MEMBUAT ASS TIDAK BERBAHAYA)
 *  ----------------------------------------------------------------
 *  Halaman ini HANYA menyentuh akun dengan role:
 *        WSS, SMST, RTS, TF
 *  Akun ADMIN dan ASS TIDAK PERNAH tampil dan TIDAK PERNAH dapat diubah
 *  maupun dihapus dari halaman ini - walau alamat halaman disunting dengan
 *  tangan. Setiap permintaan diperiksa ULANG di server memakai
 *  `rts_kelola_role_sah()`, bukan hanya disembunyikan dari tampilan.
 *
 *  SIAPA YANG BOLEH MASUK
 *  ----------------------
 *        ADMIN : boleh semua (termasuk membuat akun baru hasil kerja lama
 *                sudah tetap ada di menu "Kelola User")
 *        ASS   : boleh seluruh pekerjaan pada halaman ini
 *        lainnya (WSS, SMST, RTS, TF) : DITOLAK
 *
 *  KEAMANAN
 *  --------
 *  1. Seluruh perintah database memakai prepared statement (bind_param).
 *     Tidak ada satu pun nilai dari formulir yang ditempel langsung ke SQL.
 *  2. Setiap perubahan (edit, hapus, tambah, pulihkan) memakai POST +
 *     token keamanan sesi (csrf) - sehingga tidak bisa dipicu lewat
 *     tautan/laman lain.
 *  3. Akun yang dihapus tidak dapat menghapus dirinya sendiri, tidak dapat
 *     menghapus akun terakhir yang masih aktif pada satu role, dan tidak
 *     dapat mengubah status/role akun ADMIN-ASS.
 * ============================================================================
 */

if (!is_file(__DIR__ . '/config.php') || !is_file(__DIR__ . '/auth.php')) {
    http_response_code(500);
    exit('Berkas config.php atau auth.php tidak ditemukan di folder ini. '
        . 'Pastikan halaman kelola_akun_tim.php diletakkan di public_html, '
        . 'satu folder dengan index.php dan dashboard.php.');
}

require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';

/* Berkas district.php (daftar Sales District dari database) sifatnya
   penunjang: bila belum ada di hosting, halaman ini tetap berjalan memakai
   daftar cadangan di bawah. */
if (is_file(__DIR__ . '/district.php')) {
    require_once __DIR__ . '/district.php';
}

if (!function_exists('rts_district_bawaan')) {
    function rts_district_bawaan(): array
    {
        return [
            'Medan Amplas', 'Medan Helvetia', 'Medan Johor', 'Medan Kota',
            'Medan Perjuangan', 'Medan Petisah', 'Medan Marelan',
            'Medan Selayang', 'Hamparan Perak', 'Sunggal Deli',
            'Pancur Batu', 'Modren Trade',
        ];
    }
}

if (!function_exists('rts_district_kolom_ada')) {
    function rts_district_kolom_ada($conn, string $tabel, string $kolom): bool
    {
        if (!($conn instanceof mysqli)) {
            return false;
        }

        if (preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1 || preg_match('/^[A-Za-z0-9_]+$/', $kolom) !== 1) {
            return false;
        }

        $hasil = @$conn->query('SHOW COLUMNS FROM ' . $tabel . " LIKE '"
            . $conn->real_escape_string($kolom) . "'");

        if (!($hasil instanceof mysqli_result)) {
            return false;
        }

        $ada = $hasil->num_rows > 0;
        $hasil->free();

        return $ada;
    }
}

if (!function_exists('rts_district_pilihan')) {
    function rts_district_pilihan($conn): array
    {
        $daftar = [];

        foreach (rts_district_bawaan() as $bawaan) {
            $daftar[$bawaan] = ['nilai' => $bawaan, 'dari_db' => false, 'jumlah' => 0];
        }

        if ($conn instanceof mysqli && rts_district_kolom_ada($conn, 'sales_users', 'sales_district')) {
            $hasil = @$conn->query("SELECT sales_district AS nilai, COUNT(*) AS jumlah FROM sales_users "
                . "WHERE TRIM(COALESCE(sales_district, '')) <> '' "
                . 'GROUP BY sales_district ORDER BY sales_district ASC');

            if ($hasil instanceof mysqli_result) {
                while ($baris = $hasil->fetch_assoc()) {
                    $nilai = trim((string) $baris['nilai']);

                    if ($nilai === '') {
                        continue;
                    }

                    $daftar[$nilai] = [
                        'nilai' => $nilai,
                        'dari_db' => true,
                        'jumlah' => (int) $baris['jumlah'],
                    ];
                }

                $hasil->free();
            }
        }

        return array_values($daftar);
    }
}

if (!function_exists('rts_district_rapikan')) {
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

rts_require_login();

$kat_role_login = rts_current_role();

/* ---------------------------------------------------------------- penjaga */

if (!in_array($kat_role_login, ['ADMIN', 'ASS'], true)) {
    http_response_code(403);
    require_once __DIR__ . '/header.php';
    ?>
    <div class="alert alert-danger border-danger shadow-sm">
      <h4 class="alert-heading"><i class="fa-solid fa-ban"></i> Akses ditolak</h4>
      <p class="mb-2">Halaman <b>Kelola Akun Tim</b> hanya dapat dibuka oleh akun
      <b>ADMIN</b> atau <b>ASS</b>. Peran yang terbaca dari akun Bapak:
      <b><?= htmlspecialchars($kat_role_login === '' ? '(kosong)' : $kat_role_login) ?></b>.</p>
      <a href="dashboard.php" class="btn btn-danger btn-sm">Kembali ke Dashboard</a>
    </div>
    <?php
    require_once __DIR__ . '/footer.php';
    exit;
}

/* --------------------------------------------------------------------------
   DAFTAR ROLE TIM SALES (kepanjangan dibetulkan sesuai keterangan Bapak)

     WSS  = Warehouse Shoe Sale
            Punya outlet sendiri dan ada di SETIAP district karena GROSIR.

     SMST = Sales Modern Small Trade
            Punya outlet sendiri dan ada di SETIAP district karena MODERN
            TRADE.

     RTS  = Retail Salesman   (menangani district tertentu)

     TF   = Task Force        (sales yang ditugaskan menjual produk perusahaan
                               yang dititipkan di customer yang di-cover WSS)

   WSS & SMST memakai cakupan SEMUA DISTRICT secara otomatis.
   -------------------------------------------------------------------------- */

/* Kepanjangan resmi tiap role - SATU-SATUNYA sumber, jadi tidak ada
   kemungkinan tulisan berbeda antar bagian halaman. */
$kat_panjang_role = [
    'WSS'  => 'Warehouse Shoe Sale',
    'SMST' => 'Sales Modern Small Trade',
    'RTS'  => 'Retail Salesman',
    'TF'   => 'Task Force',
];

/* Keterangan panjang - tampil pada kartu jumlah akun dan pada kotak Role. */
$kat_keterangan_role = [
    'WSS'  => 'Punya outlet sendiri dan ada di SETIAP district karena Grosir '
            . '(Warehouse Shoe Sale).',
    'SMST' => 'Punya outlet sendiri dan ada di SETIAP district karena Modern '
            . 'Trade (Sales Modern Small Trade).',
    'RTS'  => 'Retail salesman - menangani district tertentu.',
    'TF'   => 'Sales yang ditugaskan menjual produk perusahaan yang dititipkan '
            . 'di customer yang di-cover WSS.',
];

/* Cakupan wilayah (untuk lencana pada daftar keterangan role). */
$kat_cakupan_role = [
    'WSS'  => 'SEMUA district',
    'SMST' => 'SEMUA district',
    'RTS'  => 'District tertentu',
    'TF'   => 'Mengikuti cakupan WSS',
];

/* WSS dan SMST OTOMATIS memakai SEMUA DISTRICT, karena outletnya ada di
   setiap district. Bila salah satu role ini dipilih, isian Sales District
   dikosongkan sendiri - baik oleh halaman maupun oleh pemeriksaan di server. */
$kat_role_semua_district = ['WSS', 'SMST'];

$kat_role_boleh = ['WSS', 'SMST', 'RTS', 'TF'];

/* Nama tampil pada kotak pilihan: kode + kepanjangan resminya. */
$kat_nama_role = [];

foreach ($kat_panjang_role as $kat_kode => $kat_panjang) {
    $kat_nama_role[$kat_kode] = $kat_kode . ' (' . $kat_panjang . ')';
}

/** Role sah yang boleh disentuh halaman ini. */
if (!function_exists('rts_kelola_role_sah')) {
    function rts_kelola_role_sah(string $role): bool
    {
        return in_array(strtoupper(trim($role)), ['WSS', 'SMST', 'RTS', 'TF'], true);
    }
}

/** Membaca angka dari masukan apa pun. */
if (!function_exists('rts_kelola_angka')) {
    function rts_kelola_angka($nilai): int
    {
        $teks = preg_replace('/[^0-9\-]/', '', (string) $nilai) ?? '';

        return $teks === '' ? 0 : (int) $teks;
    }
}

/** Mencatat pekerjaan ke tabel arsip (dipakai untuk hapus & edit). */
if (!function_exists('rts_kelola_tabel_arsip_ada')) {
    function rts_kelola_tabel_arsip_ada($conn): bool
    {
        $hasil = @$conn->query("SHOW TABLES LIKE 'sales_users_arsip'");

        if ($hasil instanceof mysqli_result) {
            $ada = $hasil->num_rows > 0;
            $hasil->free();

            return $ada;
        }

        return false;
    }
}

/* ---------------------------------------------------------------- token */

if (empty($_SESSION['kat_token'])) {
    try {
        $_SESSION['kat_token'] = bin2hex(random_bytes(16));
    } catch (Throwable $e) {
        $_SESSION['kat_token'] = hash('sha256', uniqid('rts', true));
    }
}
$kat_token = (string) $_SESSION['kat_token'];

$kat_kabar = '';
$kat_galat = '';
$kat_jenis_pesan = 'success';

/* Proses formulir -------------------------------------------------------- */

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $kat_aksi = (string) ($_POST['kat_aksi'] ?? '');
    $kat_token_kirim = (string) ($_POST['kat_token'] ?? '');

    if (!hash_equals($kat_token, $kat_token_kirim)) {
        $kat_galat = 'Token keamanan tidak cocok. Muat ulang halaman lalu coba lagi.';
        $kat_jenis_pesan = 'danger';
    } elseif ($kat_aksi === 'edit') {
        /* --------------------------------------------------------- EDIT */
        $kat_id = rts_kelola_angka($_POST['kat_id'] ?? 0);

        $kat_stmt = $conn->prepare('SELECT * FROM sales_users WHERE id = ? LIMIT 1');
        $kat_stmt->bind_param('i', $kat_id);
        $kat_stmt->execute();
        $kat_lama = $kat_stmt->get_result()->fetch_assoc();

        if (!$kat_lama) {
            $kat_galat = 'Akun tidak ditemukan.';
            $kat_jenis_pesan = 'danger';
        } elseif (!rts_kelola_role_sah((string) $kat_lama['role'])) {
            $kat_galat = 'Akun dengan role ' . htmlspecialchars(strtoupper((string) $kat_lama['role']))
                . ' TIDAK dapat diubah dari halaman ini. Halaman ini hanya untuk akun '
                . 'WSS, SMST, RTS, dan TF.';
            $kat_jenis_pesan = 'danger';
        } else {
            $kat_nama = trim((string) ($_POST['nama_lengkap'] ?? ''));
            $kat_email = trim((string) ($_POST['email'] ?? ''));
            $kat_username = trim((string) ($_POST['username'] ?? ''));
            $kat_role = strtoupper(trim((string) ($_POST['role'] ?? '')));
            $kat_salesman = trim((string) ($_POST['salesman'] ?? ''));
            $kat_district = rts_district_rapikan($conn, (string) ($_POST['sales_district'] ?? ''));

            /* WSS & SMST otomatis SEMUA DISTRICT (outletnya ada di setiap
               district). Pemeriksaan ini dilakukan di SERVER, jadi tetap
               berlaku walau pilihan dikirim dengan cara lain. */
            if (in_array($kat_role, $kat_role_semua_district, true)) {
                $kat_district = '';
            }
            $kat_status = ((string) ($_POST['status_aktif'] ?? 'Aktif')) === 'Nonaktif' ? 'Nonaktif' : 'Aktif';
            $kat_password = (string) ($_POST['password'] ?? '');

            $kat_pro_30 = rts_kelola_angka($_POST['akun_pro_30'] ?? 0);
            $kat_pro_30 = max(0, min(3650, $kat_pro_30));

            if ($kat_nama === '' || $kat_username === '') {
                $kat_galat = 'Nama lengkap dan username wajib diisi.';
                $kat_jenis_pesan = 'danger';
            } elseif (!rts_kelola_role_sah($kat_role)) {
                $kat_galat = 'Role yang dipilih tidak dikenal. Pilih WSS, SMST, RTS, atau TF saja.';
                $kat_jenis_pesan = 'danger';
            } elseif ($kat_email !== '' && !filter_var($kat_email, FILTER_VALIDATE_EMAIL)) {
                $kat_galat = 'Alamat email tidak sah. Kosongkan bila tidak dipakai.';
                $kat_jenis_pesan = 'danger';
            } elseif ($kat_password !== '' && strlen($kat_password) < 6) {
                $kat_galat = 'Password baru minimal 6 karakter. Kosongkan bila tidak ingin diganti.';
                $kat_jenis_pesan = 'danger';
            } else {
                /* Username tidak boleh sama dengan akun lain. */
                $kat_dup = $conn->prepare('SELECT id FROM sales_users WHERE username = ? AND id <> ? LIMIT 1');
                $kat_dup->bind_param('si', $kat_username, $kat_id);
                $kat_dup->execute();
                $kat_username_ada = $kat_dup->get_result()->num_rows > 0;

                if ($kat_username_ada) {
                    $kat_galat = 'Username "' . htmlspecialchars($kat_username) . '" sudah dipakai akun lain.';
                    $kat_jenis_pesan = 'danger';
                } else {
                    /* Kolom akun_pro tidak selalu ada (tergantung .sql yang sudah dijalankan). */
                    $kat_ada_pro = rts_district_kolom_ada($conn, 'sales_users', 'akun_pro');

                    /* Password: bila kotak "Password Baru" dibiarkan KOSONG, password
                       LAMA dipakai kembali (tidak diganti). Dengan begitu jumlah
                       parameter selalu tetap delapan - tidak ada pengikatan yang
                       bisa salah, dan password tidak pernah terhapus tanpa sengaja. */
                    $kat_hash = $kat_password !== ''
                        ? password_hash($kat_password, PASSWORD_DEFAULT)
                        : (string) ($kat_lama['password'] ?? '');

                    $kat_stmt2 = $conn->prepare('UPDATE sales_users SET nama_lengkap = ?, '
                        . 'email = ?, username = ?, role = ?, salesman = ?, sales_district = ?, '
                        . 'status_aktif = ?, password = ? WHERE id = ?');
                    $kat_stmt2->bind_param('ssssssssi', $kat_nama, $kat_email, $kat_username,
                        $kat_role, $kat_salesman, $kat_district, $kat_status, $kat_hash, $kat_id);
                    $kat_ok = $kat_stmt2->execute();

                    if (!$kat_ok) {
                        $kat_galat = 'Gagal menyimpan perubahan: ' . htmlspecialchars($kat_stmt2->error);
                        $kat_jenis_pesan = 'danger';
                    } else {
                        /* Langganan PRO: dijalankan hanya bila kotak hari diisi
                           lebih dari nol dan kolomnya tersedia di database. */
                        if ($kat_ada_pro && $kat_pro_30 > 0) {
                            $kat_pro = $conn->prepare('UPDATE sales_users SET akun_pro = 1 WHERE id = ?');
                            $kat_pro->bind_param('i', $kat_id);
                            $kat_pro->execute();

                            $kat_ada_sampai = rts_district_kolom_ada($conn, 'sales_users', 'pro_sampai');
                            $kat_ada_mulai = rts_district_kolom_ada($conn, 'sales_users', 'pro_mulai');

                            if ($kat_ada_sampai) {
                                /* Bila masa PRO sebelumnya masih berjalan, tambahannya
                                   disambung dari tanggal itu. Bila sudah habis,
                                   dihitung dari hari ini. */
                                $kat_dasar = (string) ($kat_lama['pro_sampai'] ?? '');
                                $kat_waktu = ($kat_dasar !== '' && strtotime($kat_dasar) !== false
                                        && strtotime($kat_dasar) > time())
                                    ? (int) strtotime($kat_dasar)
                                    : time();

                                $kat_sampai = date('Y-m-d H:i:s', $kat_waktu + ($kat_pro_30 * 86400));

                                $kat_pro2 = $conn->prepare('UPDATE sales_users SET pro_sampai = ? WHERE id = ?');
                                $kat_pro2->bind_param('si', $kat_sampai, $kat_id);
                                $kat_pro2->execute();

                                if ($kat_ada_mulai && (string) ($kat_lama['pro_mulai'] ?? '') === '') {
                                    $kat_mulai = date('Y-m-d H:i:s');
                                    $kat_pro3 = $conn->prepare('UPDATE sales_users SET pro_mulai = ? WHERE id = ?');
                                    $kat_pro3->bind_param('si', $kat_mulai, $kat_id);
                                    $kat_pro3->execute();
                                }

                                $kat_kabar = 'Akun ' . htmlspecialchars($kat_username)
                                    . ' disimpan dan masa PRO ' . (int) $kat_pro_30
                                    . ' hari ditambahkan (berlaku sampai '
                                    . date('d-m-Y', (int) strtotime($kat_sampai)) . ').';
                            } else {
                                $kat_kabar = 'Akun ' . htmlspecialchars($kat_username)
                                    . ' disimpan dan ditandai PRO (kolom masa berlaku belum ada '
                                    . 'di database, jadi tanggal berakhirnya belum dicatat).';
                            }
                        }

                        if ($kat_kabar === '') {
                            $kat_kabar = 'Akun ' . htmlspecialchars($kat_username) . ' berhasil disimpan.';
                        }

                        if (in_array($kat_role, $kat_role_semua_district, true)) {
                            $kat_kabar .= ' Sales District dijadikan SEMUA DISTRICT '
                                . '(WSS & SMST ada di setiap district).';
                        }

                        /* Salinan perubahan ke arsip (bila tabel arsip sudah ada). */
                        if (rts_kelola_tabel_arsip_ada($conn)) {
                            rts_kelola_arsipkan($conn, $kat_id, 'DIUBAH', (string) ($_SESSION['username'] ?? ''));
                        }
                    }
                }
            }
        }
    } elseif ($kat_aksi === 'tambah') {
        /* ------------------------------------------------------- TAMBAH */
        $kat_nama = trim((string) ($_POST['nama_lengkap'] ?? ''));
        $kat_email = trim((string) ($_POST['email'] ?? ''));
        $kat_username = trim((string) ($_POST['username'] ?? ''));
        $kat_password = (string) ($_POST['password'] ?? '');
        $kat_role = strtoupper(trim((string) ($_POST['role'] ?? 'RTS')));
        $kat_salesman = trim((string) ($_POST['salesman'] ?? ''));
        $kat_district = rts_district_rapikan($conn, (string) ($_POST['sales_district'] ?? ''));

        /* WSS & SMST otomatis SEMUA DISTRICT (outletnya ada di setiap district). */
        if (in_array($kat_role, $kat_role_semua_district, true)) {
            $kat_district = '';
        }
        $kat_status = ((string) ($_POST['status_aktif'] ?? 'Aktif')) === 'Nonaktif' ? 'Nonaktif' : 'Aktif';

        if ($kat_nama === '' || $kat_username === '' || strlen($kat_password) < 6) {
            $kat_galat = 'Nama lengkap, username, dan password (minimal 6 karakter) wajib diisi.';
            $kat_jenis_pesan = 'danger';
        } elseif (!rts_kelola_role_sah($kat_role)) {
            $kat_galat = 'Role yang dipilih tidak dikenal. Hanya WSS, SMST, RTS, dan TF.';
            $kat_jenis_pesan = 'danger';
        } elseif ($kat_email !== '' && !filter_var($kat_email, FILTER_VALIDATE_EMAIL)) {
            $kat_galat = 'Alamat email tidak sah. Kosongkan bila tidak dipakai.';
            $kat_jenis_pesan = 'danger';
        } else {
            $kat_dup = $conn->prepare('SELECT id FROM sales_users WHERE username = ? LIMIT 1');
            $kat_dup->bind_param('s', $kat_username);
            $kat_dup->execute();
            $kat_ada = $kat_dup->get_result()->num_rows > 0;

            if ($kat_ada) {
                $kat_galat = 'Username "' . htmlspecialchars($kat_username) . '" sudah dipakai.';
                $kat_jenis_pesan = 'danger';
            } else {
                $kat_hash = password_hash($kat_password, PASSWORD_DEFAULT);

                $kat_stmt = $conn->prepare('INSERT INTO sales_users '
                    . '(nama_lengkap, email, username, password, role, salesman, sales_district, status_aktif) '
                    . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
                $kat_stmt->bind_param('ssssssss', $kat_nama, $kat_email, $kat_username, $kat_hash,
                    $kat_role, $kat_salesman, $kat_district, $kat_status);

                if ($kat_stmt->execute()) {
                    $kat_kabar = 'Akun baru ' . htmlspecialchars($kat_username) . ' ('
                        . htmlspecialchars($kat_role) . ') berhasil dibuat dan dapat langsung masuk aplikasi.';

                    if (in_array($kat_role, $kat_role_semua_district, true)) {
                        $kat_kabar .= ' Sales District otomatis SEMUA DISTRICT '
                            . '(WSS & SMST ada di setiap district).';
                    }
                } else {
                    $kat_galat = 'Gagal membuat akun: ' . htmlspecialchars($kat_stmt->error);
                    $kat_jenis_pesan = 'danger';
                }
            }
        }
    } elseif ($kat_aksi === 'rapikan') {
        /* ------------------------------------------------------- RAPIKAN */
        /* Menjadikan seluruh akun WSS & SMST sebagai SEMUA DISTRICT.
           Data lamanya disalin lebih dahulu ke tabel arsip, jadi masih dapat
           dilihat (dan dikembalikan) bila diperlukan. */
        $kat_oleh = (string) ($_SESSION['username'] ?? '');

        if (!rts_kelola_tabel_arsip_ada($conn)) {
            $kat_galat = 'Tabel arsip `sales_users_arsip` belum ada, jadi perapian DIBATALKAN '
                . 'supaya data district yang lama tidak hilang tanpa salinan.';
            $kat_jenis_pesan = 'danger';
        } else {
            $kat_sasar = [];
            $kat_h3 = @$conn->query("SELECT id, username FROM sales_users "
                . "WHERE UPPER(role) IN ('WSS','SMST') "
                . "AND TRIM(COALESCE(sales_district, '')) <> '' LIMIT 300");

            if ($kat_h3 instanceof mysqli_result) {
                while ($kat_b3 = $kat_h3->fetch_assoc()) {
                    $kat_sasar[] = $kat_b3;
                }

                $kat_h3->free();
            }

            if (!$kat_sasar) {
                $kat_kabar = 'Semua akun WSS & SMST sudah memakai SEMUA DISTRICT. '
                    . 'Tidak ada yang perlu dirapikan.';
            } else {
                $kat_berhasil = 0;
                $kat_gagal = 0;
                $kat_kosong = '';

                foreach ($kat_sasar as $kat_b3) {
                    $kat_id3 = (int) $kat_b3['id'];

                    /* Salinan SEBELUM diubah (memuat district yang lama). */
                    if (!rts_kelola_arsipkan($conn, $kat_id3, 'DIRAPIKAN', $kat_oleh)) {
                        $kat_gagal++;
                        continue;
                    }

                    $kat_up = $conn->prepare('UPDATE sales_users SET sales_district = ? WHERE id = ?');
                    $kat_up->bind_param('si', $kat_kosong, $kat_id3);

                    if ($kat_up->execute()) {
                        $kat_berhasil++;
                    } else {
                        $kat_gagal++;
                    }
                }

                $kat_kabar = (int) $kat_berhasil . ' akun WSS/SMST dijadikan SEMUA DISTRICT.'
                    . ' Data district lamanya tersimpan di tabel arsip dengan keterangan DIRAPIKAN.';

                if ($kat_gagal > 0) {
                    $kat_kabar .= ' ' . (int) $kat_gagal . ' akun gagal dirapikan.';
                }
            }
        }
    } elseif ($kat_aksi === 'hapus') {
        /* -------------------------------------------------------- HAPUS */
        $kat_id = rts_kelola_angka($_POST['kat_id'] ?? 0);
        $kat_konfirmasi = strtoupper(trim((string) ($_POST['kat_konfirmasi'] ?? '')));

        $kat_stmt = $conn->prepare('SELECT * FROM sales_users WHERE id = ? LIMIT 1');
        $kat_stmt->bind_param('i', $kat_id);
        $kat_stmt->execute();
        $kat_baris = $kat_stmt->get_result()->fetch_assoc();

        if (!$kat_baris) {
            $kat_galat = 'Akun tidak ditemukan.';
            $kat_jenis_pesan = 'danger';
        } elseif (!rts_kelola_role_sah((string) $kat_baris['role'])) {
            $kat_galat = 'Akun dengan role ' . htmlspecialchars(strtoupper((string) $kat_baris['role']))
                . ' tidak boleh dihapus dari halaman ini.';
            $kat_jenis_pesan = 'danger';
        } elseif ((int) $kat_id === (int) ($_SESSION['user_id'] ?? 0)) {
            $kat_galat = 'Akun yang sedang dipakai masuk tidak dapat menghapus dirinya sendiri.';
            $kat_jenis_pesan = 'danger';
        } elseif ($kat_konfirmasi !== 'HAPUS') {
            $kat_galat = 'Ketik kata HAPUS pada kotak konfirmasi untuk meneruskan penghapusan.';
            $kat_jenis_pesan = 'danger';
        } else {
            /* Jangan sampai satu role kehabisan akun aktif. */
            $kat_role_target = strtoupper((string) $kat_baris['role']);
            $kat_cek = $conn->prepare("SELECT COUNT(*) AS n FROM sales_users "
                . "WHERE UPPER(role) = ? AND status_aktif = 'Aktif' AND id <> ?");
            $kat_cek->bind_param('si', $kat_role_target, $kat_id);
            $kat_cek->execute();
            $kat_sisa = (int) ($kat_cek->get_result()->fetch_assoc()['n'] ?? 0);

            if ($kat_sisa < 1) {
                $kat_galat = 'Akun ' . htmlspecialchars($kat_role_target)
                    . ' ini adalah SATU-SATUNYA akun aktif pada role tersebut. '
                    . 'Buat/aktifkan akun pengganti lebih dahulu, atau ubah statusnya menjadi '
                    . 'Nonaktif (tidak bisa masuk) daripada menghapus.';
                $kat_jenis_pesan = 'danger';
            } elseif (!rts_kelola_tabel_arsip_ada($conn)) {
                $kat_galat = 'Tabel arsip `sales_users_arsip` belum ada, jadi penghapusan DIBATALKAN '
                    . 'supaya data akun tidak hilang tanpa salinan. Jalankan berkas '
                    . 'RTS_PANEL_ARSIP_AKUN.sql di phpMyAdmin (tombol panduan ada di bawah), '
                    . 'lalu ulangi penghapusan.';
                $kat_jenis_pesan = 'danger';
            } else {
                $kat_arsip_ok = rts_kelola_arsipkan($conn, $kat_id, 'DIHAPUS', (string) ($_SESSION['username'] ?? ''));

                if (!$kat_arsip_ok) {
                    $kat_galat = 'Gagal menyalin akun ke tabel arsip, jadi penghapusan DIBATALKAN '
                        . 'supaya tidak ada data yang hilang.';
                    $kat_jenis_pesan = 'danger';
                } else {
                    $kat_hapus = $conn->prepare('DELETE FROM sales_users WHERE id = ? LIMIT 1');
                    $kat_hapus->bind_param('i', $kat_id);

                    if ($kat_hapus->execute() && $kat_hapus->affected_rows > 0) {
                        $kat_kabar = 'Akun ' . htmlspecialchars((string) $kat_baris['username'])
                            . ' (' . htmlspecialchars($kat_role_target) . ') sudah DIHAPUS. '
                            . 'Salinan lengkapnya tersimpan pada tabel sales_users_arsip '
                            . '(lihat daftar Arsip Akun di bawah) dan dapat dipulihkan '
                            . 'lewat tombol Pulihkan.';
                    } else {
                        $kat_galat = 'Gagal menghapus akun. Tidak ada perubahan yang dilakukan.';
                        $kat_jenis_pesan = 'danger';
                    }
                }
            }
        }
    } elseif ($kat_aksi === 'pulihkan') {
        /* ---------------------------------------------------- PULIHKAN */
        $kat_arsip_id = rts_kelola_angka($_POST['kat_arsip_id'] ?? 0);

        if (!rts_kelola_tabel_arsip_ada($conn)) {
            $kat_galat = 'Tabel arsip belum ada.';
            $kat_jenis_pesan = 'danger';
        } else {
            $kat_stmt = $conn->prepare('SELECT * FROM sales_users_arsip WHERE id = ? LIMIT 1');
            $kat_stmt->bind_param('i', $kat_arsip_id);
            $kat_stmt->execute();
            $kat_arsip = $kat_stmt->get_result()->fetch_assoc();

            if (!$kat_arsip) {
                $kat_galat = 'Catatan arsip tidak ditemukan.';
                $kat_jenis_pesan = 'danger';
            } elseif (!rts_kelola_role_sah((string) ($kat_arsip['role'] ?? ''))) {
                $kat_galat = 'Catatan arsip itu bukan akun tim sales (WSS/SMST/RTS/TF), jadi tidak dipulihkan.';
                $kat_jenis_pesan = 'danger';
            } else {
                $kat_uname = (string) ($kat_arsip['username'] ?? '');

                $kat_dup = $conn->prepare('SELECT id FROM sales_users WHERE username = ? LIMIT 1');
                $kat_dup->bind_param('s', $kat_uname);
                $kat_dup->execute();
                $kat_ada = $kat_dup->get_result()->num_rows > 0;

                if ($kat_ada) {
                    $kat_galat = 'Username "' . htmlspecialchars($kat_uname)
                        . '" sekarang sudah dipakai akun lain. Ubah dulu username akun itu, '
                        . 'baru pulihkan arsip ini.';
                    $kat_jenis_pesan = 'danger';
                } else {
                    $kat_hash = (string) ($kat_arsip['password'] ?? '');

                    if ($kat_hash === '') {
                        $kat_hash = password_hash(bin2hex(random_bytes(6)), PASSWORD_DEFAULT);
                    }

                    $kat_nama = (string) ($kat_arsip['nama_lengkap'] ?? '');
                    $kat_email = (string) ($kat_arsip['email'] ?? '');
                    $kat_role = strtoupper((string) ($kat_arsip['role'] ?? 'RTS'));
                    $kat_salesman = (string) ($kat_arsip['salesman'] ?? '');
                    $kat_district = (string) ($kat_arsip['sales_district'] ?? '');
                    $kat_status = ((string) ($kat_arsip['status_aktif'] ?? 'Aktif')) === 'Nonaktif'
                        ? 'Nonaktif' : 'Aktif';

                    $kat_stmt2 = $conn->prepare('INSERT INTO sales_users '
                        . '(nama_lengkap, email, username, password, role, salesman, sales_district, status_aktif) '
                        . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?)');
                    $kat_stmt2->bind_param('ssssssss', $kat_nama, $kat_email, $kat_uname, $kat_hash,
                        $kat_role, $kat_salesman, $kat_district, $kat_status);

                    if ($kat_stmt2->execute()) {
                        $kat_kabar = 'Akun ' . htmlspecialchars($kat_uname) . ' dipulihkan. '
                            . 'Kalau dulu passwordnya lupa, ganti lewat tombol Edit.';
                    } else {
                        $kat_galat = 'Gagal memulihkan akun: ' . htmlspecialchars($kat_stmt2->error);
                        $kat_jenis_pesan = 'danger';
                    }
                }
            }
        }
    }
}

/**
 * Menyalin satu akun dari sales_users ke sales_users_arsip.
 *
 * Dipanggil SEBELUM akun dihapus, dan juga setiap kali akun diubah.
 * Penyalinan dikerjakan OLEH DATABASE sendiri (INSERT ... SELECT), sehingga
 * seluruh kolom ikut tersalin APA ADANYA - termasuk kolom tambahan yang
 * mungkin Bapak buat kemudian. Hanya kolom yang sama-sama ada pada kedua
 * tabel yang disalin.
 */
function rts_kelola_kolom_tabel($conn, string $tabel): array
{
    $kolom = [];

    if (!($conn instanceof mysqli) || preg_match('/^[A-Za-z0-9_]+$/', $tabel) !== 1) {
        return $kolom;
    }

    $hasil = @$conn->query('SHOW COLUMNS FROM ' . $tabel);

    if ($hasil instanceof mysqli_result) {
        while ($baris = $hasil->fetch_assoc()) {
            $kolom[] = (string) ($baris['Field'] ?? '');
        }

        $hasil->free();
    }

    return array_values(array_filter($kolom, static function ($satu) {
        return $satu !== '';
    }));
}

function rts_kelola_arsipkan($conn, int $id, string $aksi, string $oleh): bool
{
    if (!rts_kelola_tabel_arsip_ada($conn) || $id <= 0) {
        return false;
    }

    $kolom_arsip = rts_kelola_kolom_tabel($conn, 'sales_users_arsip');
    $kolom_akun = rts_kelola_kolom_tabel($conn, 'sales_users');

    if (!$kolom_akun || !$kolom_arsip) {
        return false;
    }

    /* Kolom yang ada pada KEDUA tabel, selain id. */
    $pakai = [];

    foreach ($kolom_akun as $satu) {
        if (strtolower($satu) === 'id') {
            continue;
        }

        if (in_array($satu, $kolom_arsip, true)) {
            $pakai[] = $satu;
        }
    }

    if (!$pakai) {
        return false;
    }

    $daftar_kolom = [];
    $daftar_nilai = [];

    foreach ($pakai as $satu) {
        $daftar_kolom[] = '`' . $satu . '`';
        $daftar_nilai[] = '`' . $satu . '`';
    }

    /* Keterangan: aksi apa, oleh siapa, kapan. */
    if (in_array('aksi', $kolom_arsip, true)) {
        $daftar_kolom[] = '`aksi`';
        $daftar_nilai[] = "'" . $conn->real_escape_string(strtoupper($aksi)) . "'";
    }

    if (in_array('oleh', $kolom_arsip, true)) {
        $daftar_kolom[] = '`oleh`';
        $daftar_nilai[] = '?';
        $ada_oleh = true;
    }

    if (in_array('waktu', $kolom_arsip, true)) {
        $daftar_kolom[] = '`waktu`';
        $daftar_nilai[] = 'NOW()';
    }

    $sql = 'INSERT INTO sales_users_arsip (' . implode(', ', $daftar_kolom) . ') '
        . 'SELECT ' . implode(', ', $daftar_nilai) . ' FROM sales_users WHERE id = ?';

    $stmt = $conn->prepare($sql);

    if (!$stmt) {
        return false;
    }

    if (isset($ada_oleh)) {
        $stmt->bind_param('si', $oleh, $id);
    } else {
        $stmt->bind_param('i', $id);
    }

    return $stmt->execute();
}

/* ------------------------------------------------------------- baca data */

$kat_ada_pro = rts_district_kolom_ada($conn, 'sales_users', 'akun_pro');
$kat_ada_arsip = rts_kelola_tabel_arsip_ada($conn);

$kat_kolom_pro = '';
if ($kat_ada_pro) {
    $kat_kolom_pro = ', akun_pro';

    if (rts_district_kolom_ada($conn, 'sales_users', 'pro_sampai')) {
        $kat_kolom_pro .= ', pro_sampai';
    }
}

/* Daftar akun tim (WSS/SMST/RTS/TF) - akun ADMIN & ASS TIDAK ikut dibaca. */
$kat_daftar = [];
$kat_hasil = $conn->query("SELECT id, nama_lengkap, email, username, role, salesman, "
    . "sales_district, status_aktif" . $kat_kolom_pro . " FROM sales_users "
    . "WHERE UPPER(role) IN ('WSS','SMST','RTS','TF') "
    . "ORDER BY FIELD(UPPER(role),'WSS','SMST','RTS','TF'), nama_lengkap ASC");

if ($kat_hasil instanceof mysqli_result) {
    while ($kat_baris = $kat_hasil->fetch_assoc()) {
        $kat_daftar[] = $kat_baris;
    }
    $kat_hasil->free();
}

/* Arsip 30 terakhir. */
$kat_arsip = [];
if ($kat_ada_arsip) {
    $kat_hasil2 = @$conn->query('SELECT id, nama_lengkap, email, username, role, sales_district, '
        . 'status_aktif, aksi, oleh, waktu FROM sales_users_arsip ORDER BY id DESC LIMIT 30');

    if ($kat_hasil2 instanceof mysqli_result) {
        while ($kat_baris2 = $kat_hasil2->fetch_assoc()) {
            $kat_arsip[] = $kat_baris2;
        }
        $kat_hasil2->free();
    }
}

/* Jumlah akun per role. */
$kat_jumlah = ['WSS' => 0, 'SMST' => 0, 'RTS' => 0, 'TF' => 0];
foreach ($kat_daftar as $kat_baris3) {
    $kat_kunci = strtoupper((string) $kat_baris3['role']);
    if (isset($kat_jumlah[$kat_kunci])) {
        $kat_jumlah[$kat_kunci]++;
    }
}

/* Berapa akun WSS/SMST yang masih memakai district tertentu - dipakai untuk
   menampilkan tombol "RAPIKAN JADI SEMUA DISTRICT". */
$kat_perlu_rapi = 0;
$kat_hitung_rapi = @$conn->query("SELECT COUNT(*) AS n FROM sales_users "
    . "WHERE UPPER(role) IN ('WSS','SMST') "
    . "AND TRIM(COALESCE(sales_district, '')) <> ''");

if ($kat_hitung_rapi instanceof mysqli_result) {
    $kat_perlu_rapi = (int) ($kat_hitung_rapi->fetch_assoc()['n'] ?? 0);
    $kat_hitung_rapi->free();
}

/* Daftar district untuk kotak pilihan: nilai nyata dari database digabung
   dengan daftar bawaan (lihat district.php). Namanya sengaja berbeda dari
   $kat_district di atas supaya tidak tertukar dengan isian formulir. */
$kat_district_daftar = [];

foreach (rts_district_pilihan($conn) as $kat_butir) {
    $kat_district_daftar[] = (string) $kat_butir['nilai'];
}

function kat_e($nilai): string
{
    return htmlspecialchars((string) $nilai, ENT_QUOTES, 'UTF-8');
}

require_once __DIR__ . '/header.php';
?>
<main class="container-fluid py-4">
  <div class="d-flex justify-content-between align-items-center flex-wrap gap-2">
    <div>
      <h3 class="mb-1"><i class="fa-solid fa-users-gear text-primary"></i> Kelola Akun Tim</h3>
      <p class="text-muted mb-0">
        Khusus ADMIN dan <b>ASS</b>: mengedit, menghapus, dan menambah akun
        <b>WSS</b> (Warehouse Shoe Sale), <b>SMST</b> (Sales Modern Small Trade),
        <b>RTS</b> (Sales / Salesman), dan <b>TF</b> (Team Force).
        Akun ADMIN dan ASS tidak tampil di sini.
      </p>
    </div>
    <button class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#katTambah">
      <i class="fa-solid fa-user-plus"></i> Tambah Akun Tim
    </button>
  </div>

  <?php if ($kat_galat !== ''): ?>
    <div class="alert alert-danger shadow-sm mt-3"><?= $kat_galat ?></div>
  <?php endif; ?>

  <?php if ($kat_kabar !== ''): ?>
    <div class="alert alert-<?= kat_e($kat_jenis_pesan) ?> shadow-sm mt-3"><?= $kat_kabar ?></div>
  <?php endif; ?>

  <div class="row g-3 mt-3">
    <?php foreach ($kat_panjang_role as $kat_kode => $kat_panjang): ?>
      <div class="col-6 col-lg-3">
        <div class="card border-0 shadow-sm h-100">
          <div class="card-body">
            <div class="fw-bold text-primary"><?= kat_e($kat_kode) ?></div>
            <div class="text-muted small" style="min-height:34px"><?= kat_e($kat_panjang) ?></div>
            <div class="fs-3 fw-bold"><?= (int) $kat_jumlah[$kat_kode] ?></div>
            <div class="text-muted small">
              akun -
              <?= kat_e($kat_cakupan_role[$kat_kode] ?? '') ?>
            </div>
          </div>
        </div>
      </div>
    <?php endforeach; ?>
  </div>

  <div class="card border-0 shadow-sm mt-4">
    <div class="card-header bg-white"><strong>Keterangan Role</strong></div>
    <div class="card-body">
      <div class="row g-3">
        <?php foreach ($kat_panjang_role as $kat_kode => $kat_panjang): ?>
          <div class="col-md-6">
            <div class="border rounded p-3 h-100">
              <div class="d-flex justify-content-between align-items-start gap-2">
                <div>
                  <span class="badge text-bg-primary"><?= kat_e($kat_kode) ?></span>
                  <b class="ms-1"><?= kat_e($kat_panjang) ?></b>
                </div>
                <?php if (($kat_cakupan_role[$kat_kode] ?? '') !== ''): ?>
                  <span class="badge <?= in_array($kat_kode, ['WSS', 'SMST'], true)
                      ? 'text-bg-info' : 'text-bg-light text-muted' ?>">
                    <?= kat_e($kat_cakupan_role[$kat_kode]) ?>
                  </span>
                <?php endif; ?>
              </div>
              <div class="text-muted small mt-2">
                <?= kat_e($kat_keterangan_role[$kat_kode] ?? '') ?>
              </div>
            </div>
          </div>
        <?php endforeach; ?>
      </div>
      <div class="form-text mt-3 mb-0">
        WSS dan SMST ada di SETIAP district (Grosir dan Modern Trade), jadi kedua
        role itu <b>OTOMATIS memakai SEMUA DISTRICT</b> - kotak Sales District
        dikosongkan sendiri saat role WSS atau SMST dipilih. RTS menangani
        district tertentu, sedangkan TF menjual produk titipan di customer yang
        di-cover WSS.
      </div>

      <?php if ($kat_perlu_rapi > 0): ?>
        <div class="alert alert-info mt-3 mb-0 d-flex justify-content-between
                    align-items-center flex-wrap gap-2">
          <div>
            Ada <b><?= (int) $kat_perlu_rapi ?> akun WSS/SMST</b> yang masih memakai
            district tertentu. Karena keduanya ada di setiap district, sebaiknya
            dijadikan <b>SEMUA DISTRICT</b>. Data district lamanya disalin lebih
            dahulu ke tabel arsip, jadi masih dapat dilihat kembali.
          </div>
          <form method="post"
                onsubmit="return confirm('Jadikan seluruh akun WSS &amp; SMST sebagai SEMUA DISTRICT?')">
            <input type="hidden" name="kat_aksi" value="rapikan">
            <input type="hidden" name="kat_token" value="<?= kat_e($kat_token) ?>">
            <button class="btn btn-sm btn-info">
              <i class="fa-solid fa-wand-magic-sparkles"></i> RAPIKAN JADI SEMUA DISTRICT
            </button>
          </form>
        </div>
      <?php endif; ?>
    </div>
  </div>

  <?php if (!$kat_ada_arsip): ?>
    <div class="alert alert-warning shadow-sm mt-4">
      <h5 class="alert-heading"><i class="fa-solid fa-triangle-exclamation"></i> Tabel arsip belum ada</h5>
      <p class="mb-2">
        Supaya akun yang dihapus <b>tidak hilang begitu saja</b>, penghapusan baru akan
        berjalan setelah tabel arsip dibuat. Buka <b>phpMyAdmin</b>, pilih database
        <b>benedics_benes_sales</b>, lalu jalankan (Import / jalankan perintah SQL) isi
        berkas <b>RTS_PANEL_ARSIP_AKUN.sql</b>:
      </p>
      <pre class="bg-light p-3 rounded small mb-2">CREATE TABLE IF NOT EXISTS sales_users_arsip LIKE sales_users;
ALTER TABLE sales_users_arsip ADD COLUMN aksi VARCHAR(20) NOT NULL DEFAULT 'DIHAPUS';
ALTER TABLE sales_users_arsip ADD COLUMN oleh VARCHAR(100) NOT NULL DEFAULT '';
ALTER TABLE sales_users_arsip ADD COLUMN waktu TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;</pre>
      <p class="mb-0 small">
        Selama tabel ini belum ada, tombol <b>Hapus</b> akan menolak dengan pesan yang jelas
        (bukan menghapus setengah jalan). Mengedit dan menambah akun tetap berjalan normal.
      </p>
    </div>
  <?php endif; ?>

  <div class="card border-0 shadow-sm mt-4">
    <div class="card-header bg-white d-flex justify-content-between align-items-center">
      <strong>Daftar Akun Tim</strong>
      <span class="badge text-bg-secondary"><?= count($kat_daftar) ?> akun</span>
    </div>
    <div class="table-responsive">
      <table class="table table-hover align-middle mb-0">
        <thead class="table-light">
          <tr>
            <th>Nama</th>
            <th>Username</th>
            <th>Role</th>
            <th>Salesman</th>
            <th>District</th>
            <th>Status</th>
            <th>PRO</th>
            <th class="text-end">Aksi</th>
          </tr>
        </thead>
        <tbody>
        <?php if (!$kat_daftar): ?>
          <tr><td colspan="8" class="text-center text-muted py-4">
            Belum ada akun tim. Tekan <b>Tambah Akun Tim</b> di atas.
          </td></tr>
        <?php endif; ?>

        <?php foreach ($kat_daftar as $kat_u):
            $kat_uid = (int) $kat_u['id'];
            $kat_pro_aktif = $kat_ada_pro && (int) ($kat_u['akun_pro'] ?? 0) === 1;
            $kat_pro_sampai = (string) ($kat_u['pro_sampai'] ?? '');
        ?>
          <tr>
            <td><?= kat_e($kat_u['nama_lengkap']) ?></td>
            <td><?= kat_e($kat_u['username']) ?></td>
            <td><span class="badge text-bg-primary"><?= kat_e(strtoupper((string) $kat_u['role'])) ?></span></td>
            <td><?= kat_e($kat_u['salesman'] !== '' ? $kat_u['salesman'] : '-') ?></td>
            <td><?= kat_e(($kat_u['sales_district'] ?? '') !== '' ? $kat_u['sales_district'] : 'Semua') ?></td>
            <td>
              <?php if (strtoupper((string) $kat_u['status_aktif']) === 'AKTIF'): ?>
                <span class="badge text-bg-success">Aktif</span>
              <?php else: ?>
                <span class="badge text-bg-danger">Nonaktif</span>
              <?php endif; ?>
            </td>
            <td>
              <?php if ($kat_pro_aktif): ?>
                <span class="badge text-bg-warning" title="PRO berlaku sampai <?= kat_e($kat_pro_sampai) ?>">
                  PRO<?= $kat_pro_sampai !== '' ? ' s/d ' . kat_e(date('d-m-Y', (int) strtotime($kat_pro_sampai))) : '' ?>
                </span>
              <?php else: ?>
                <span class="badge text-bg-light text-muted">Gratis</span>
              <?php endif; ?>
            </td>
            <td class="text-end">
              <button class="btn btn-sm btn-outline-primary" data-bs-toggle="modal"
                      data-bs-target="#katEdit<?= $kat_uid ?>">
                <i class="fa-solid fa-pen-to-square"></i> Edit
              </button>
              <button class="btn btn-sm btn-outline-danger" data-bs-toggle="modal"
                      data-bs-target="#katHapus<?= $kat_uid ?>">
                <i class="fa-solid fa-trash"></i> Hapus
              </button>
            </td>
          </tr>
        <?php endforeach; ?>
        </tbody>
      </table>
    </div>
  </div>

  <?php if ($kat_arsip): ?>
    <div class="card border-0 shadow-sm mt-4">
      <div class="card-header bg-white"><strong>Arsip Akun (30 terakhir)</strong></div>
      <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
          <thead class="table-light">
            <tr><th>#</th><th>Nama</th><th>Username</th><th>Role</th><th>District</th>
                <th>Tindakan</th><th>Oleh</th><th>Waktu</th><th></th></tr>
          </thead>
          <tbody>
            <?php foreach ($kat_arsip as $kat_a): ?>
              <tr>
                <td><?= (int) $kat_a['id'] ?></td>
                <td><?= kat_e($kat_a['nama_lengkap']) ?></td>
                <td><?= kat_e($kat_a['username']) ?></td>
                <td><span class="badge text-bg-primary"><?= kat_e(strtoupper((string) $kat_a['role'])) ?></span></td>
                <td><?= kat_e(($kat_a['sales_district'] ?? '') !== '' ? $kat_a['sales_district'] : '-') ?></td>
                <td><?= kat_e($kat_a['aksi']) ?></td>
                <td><?= kat_e($kat_a['oleh']) ?></td>
                <td class="small text-muted"><?= kat_e($kat_a['waktu']) ?></td>
                <td class="text-end">
                  <?php if (strtoupper((string) $kat_a['aksi']) === 'DIHAPUS'): ?>
                    <form method="post" onsubmit="return confirm('Pulihkan akun ini kembali?')">
                      <input type="hidden" name="kat_aksi" value="pulihkan">
                      <input type="hidden" name="kat_token" value="<?= kat_e($kat_token) ?>">
                      <input type="hidden" name="kat_arsip_id" value="<?= (int) $kat_a['id'] ?>">
                      <button class="btn btn-sm btn-outline-success">
                        <i class="fa-solid fa-rotate-left"></i> Pulihkan
                      </button>
                    </form>
                  <?php else: ?>
                    <span class="text-muted small">(catatan perubahan)</span>
                  <?php endif; ?>
                </td>
              </tr>
            <?php endforeach; ?>
          </tbody>
        </table>
      </div>
    </div>
  <?php endif; ?>

  <p class="text-muted small mt-4 mb-0">
    Catatan: akun yang dihapus dicatat lebih dahulu ke tabel <b>sales_users_arsip</b>
    (permanen, tidak ikut terhapus), sehingga masih dapat dipulihkan lewat tombol
    <b>Pulihkan</b> di atas. Penghapusan sengaja ditolak bila satu role tinggal satu
    akun aktif, supaya tim Bapak tidak kehabisan akun.
  </p>
</main>

<?php foreach ($kat_daftar as $kat_u):
    $kat_uid = (int) $kat_u['id'];
    $kat_pro_aktif = $kat_ada_pro && (int) ($kat_u['akun_pro'] ?? 0) === 1;
    $kat_pro_sampai = (string) ($kat_u['pro_sampai'] ?? '');
?>
  <div class="modal fade" id="katEdit<?= $kat_uid ?>" tabindex="-1">
    <div class="modal-dialog modal-lg">
      <div class="modal-content">
        <form method="post">
          <div class="modal-header">
            <h5 class="modal-title">Edit <?= kat_e($kat_u['nama_lengkap']) ?></h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <input type="hidden" name="kat_aksi" value="edit">
            <input type="hidden" name="kat_token" value="<?= kat_e($kat_token) ?>">
            <input type="hidden" name="kat_id" value="<?= $kat_uid ?>">

            <div class="row g-3">
              <div class="col-md-6">
                <label class="form-label">Nama Lengkap</label>
                <input name="nama_lengkap" class="form-control"
                       value="<?= kat_e($kat_u['nama_lengkap']) ?>" required>
              </div>
              <div class="col-md-6">
                <label class="form-label">Email (boleh dikosongkan)</label>
                <input type="email" name="email" class="form-control"
                       value="<?= kat_e($kat_u['email']) ?>">
              </div>
              <div class="col-md-6">
                <label class="form-label">Username</label>
                <input name="username" class="form-control"
                       value="<?= kat_e($kat_u['username']) ?>" required>
              </div>
              <div class="col-md-6">
                <label class="form-label">Role</label>
                <select name="role" class="form-select" data-kat-role>
                  <?php foreach ($kat_nama_role as $kat_kode => $kat_label): ?>
                    <option value="<?= kat_e($kat_kode) ?>"
                      data-ket="<?= kat_e(($kat_cakupan_role[$kat_kode] ?? '') . ' - '
                          . ($kat_keterangan_role[$kat_kode] ?? '')) ?>"
                      <?= strtoupper((string) $kat_u['role']) === $kat_kode ? 'selected' : '' ?>>
                      <?= kat_e($kat_label) ?>
                    </option>
                  <?php endforeach; ?>
                </select>
                <div class="form-text" data-kat-ket></div>
              </div>
              <div class="col-md-6">
                <label class="form-label">Salesman</label>
                <input name="salesman" class="form-control"
                       value="<?= kat_e($kat_u['salesman']) ?>"
                       placeholder="Nama sales (boleh dikosongkan)">
              </div>
              <div class="col-md-6">
                <label class="form-label">Sales District</label>
                <select name="sales_district" class="form-select" data-kat-district>
                  <option value="">-- Semua District --</option>
                  <?php foreach ($kat_district_daftar as $kat_d): ?>
                    <option value="<?= kat_e($kat_d) ?>"
                      <?= (string) ($kat_u['sales_district'] ?? '') === $kat_d ? 'selected' : '' ?>>
                      <?= kat_e($kat_d) ?>
                    </option>
                  <?php endforeach; ?>
                </select>
                <div class="form-text">
                  Otomatis <b>Semua District</b> bila role WSS atau SMST.
                </div>
              </div>
              <div class="col-md-6">
                <label class="form-label">Status Akun</label>
                <select name="status_aktif" class="form-select">
                  <option <?= strtoupper((string) $kat_u['status_aktif']) === 'AKTIF' ? 'selected' : '' ?>>Aktif</option>
                  <option <?= strtoupper((string) $kat_u['status_aktif']) === 'NONAKTIF' ? 'selected' : '' ?>>Nonaktif</option>
                </select>
                <div class="form-text">Nonaktif = tidak bisa masuk, tetapi data tetap ada.
              WSS &amp; SMST lazimnya <b>Semua District</b>.</div>
              </div>
              <div class="col-md-6">
                <label class="form-label">Password Baru (opsional)</label>
                <input type="password" name="password" class="form-control"
                       placeholder="Kosongkan bila tidak diganti" autocomplete="new-password">
                <div class="form-text">Minimal 6 karakter bila diisi.</div>
              </div>

              <?php if ($kat_ada_pro): ?>
                <div class="col-12">
                  <div class="border rounded p-3 bg-light">
                    <div class="fw-semibold mb-1">
                      <i class="fa-solid fa-crown text-warning"></i> Langganan PRO
                      <?= $kat_pro_aktif ? '(sekarang PRO)' : '(sekarang GRATIS)' ?>
                    </div>
                    <label class="form-label">Tambahan masa PRO (hari)</label>
                    <input name="akun_pro_30" type="number" min="0" max="3650" value="0"
                           class="form-control" style="max-width:200px">
                    <div class="form-text">
                      Isi misalnya <b>30</b> untuk menambah 30 hari (langsung menjadi PRO).
                      Biarkan 0 bila tidak ingin mengubah langganan.
                      <?= $kat_pro_sampai !== '' ? 'Berlaku sampai: ' . kat_e($kat_pro_sampai) . '.' : '' ?>
                    </div>
                  </div>
                </div>
              <?php endif; ?>
            </div>
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-light" data-bs-dismiss="modal">Batal</button>
            <button class="btn btn-primary"><i class="fa-solid fa-floppy-disk"></i> Simpan Perubahan</button>
          </div>
        </form>
      </div>
    </div>
  </div>

  <div class="modal fade" id="katHapus<?= $kat_uid ?>" tabindex="-1">
    <div class="modal-dialog">
      <div class="modal-content">
        <form method="post">
          <div class="modal-header">
            <h5 class="modal-title text-danger">Hapus Akun</h5>
            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
          </div>
          <div class="modal-body">
            <input type="hidden" name="kat_aksi" value="hapus">
            <input type="hidden" name="kat_token" value="<?= kat_e($kat_token) ?>">
            <input type="hidden" name="kat_id" value="<?= $kat_uid ?>">

            <p class="mb-2">Akun berikut akan <b>DIPERMANEN</b> dihapus:</p>
            <ul class="mb-3">
              <li>Nama: <b><?= kat_e($kat_u['nama_lengkap']) ?></b></li>
              <li>Username: <b><?= kat_e($kat_u['username']) ?></b></li>
              <li>Role: <b><?= kat_e(strtoupper((string) $kat_u['role'])) ?></b></li>
            </ul>
            <div class="alert alert-warning py-2 small mb-3">
              Seluruh data akun ini disalin lebih dahulu ke tabel <b>sales_users_arsip</b>,
              jadi masih dapat dipulihkan. Catatan kinerja/kunjungan yang sudah ada
              (misalnya pada master_toko) TIDAK ikut terhapus.
            </div>
            <label class="form-label">Ketik <b>HAPUS</b> untuk meneruskan</label>
            <input name="kat_konfirmasi" class="form-control" placeholder="HAPUS" autocomplete="off">
          </div>
          <div class="modal-footer">
            <button type="button" class="btn btn-light" data-bs-dismiss="modal">Batal</button>
            <button class="btn btn-danger"><i class="fa-solid fa-trash"></i> Hapus Permanen</button>
          </div>
        </form>
      </div>
    </div>
  </div>
<?php endforeach; ?>

<div class="modal fade" id="katTambah" tabindex="-1">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <form method="post">
        <div class="modal-header">
          <h5 class="modal-title">Tambah Akun Tim</h5>
          <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
        </div>
        <div class="modal-body">
          <input type="hidden" name="kat_aksi" value="tambah">
          <input type="hidden" name="kat_token" value="<?= kat_e($kat_token) ?>">

          <div class="row g-3">
            <div class="col-md-6">
              <label class="form-label">Nama Lengkap</label>
              <input name="nama_lengkap" class="form-control" required>
            </div>
            <div class="col-md-6">
              <label class="form-label">Email (boleh dikosongkan)</label>
              <input type="email" name="email" class="form-control">
            </div>
            <div class="col-md-6">
              <label class="form-label">Username</label>
              <input name="username" class="form-control" required autocomplete="off">
            </div>
            <div class="col-md-6">
              <label class="form-label">Password</label>
              <input type="password" name="password" class="form-control" minlength="6" required
                     autocomplete="new-password">
              <div class="form-text">Minimal 6 karakter.</div>
            </div>
            <div class="col-md-6">
              <label class="form-label">Role</label>
              <select name="role" class="form-select" data-kat-role>
                <?php foreach ($kat_nama_role as $kat_kode => $kat_label): ?>
                  <option value="<?= kat_e($kat_kode) ?>"
                    data-ket="<?= kat_e(($kat_cakupan_role[$kat_kode] ?? '') . ' - '
                        . ($kat_keterangan_role[$kat_kode] ?? '')) ?>">
                    <?= kat_e($kat_label) ?>
                  </option>
                <?php endforeach; ?>
              </select>
              <div class="form-text" data-kat-ket></div>
            </div>
            <div class="col-md-6">
              <label class="form-label">Salesman</label>
              <input name="salesman" class="form-control" placeholder="Nama sales (boleh dikosongkan)">
            </div>
            <div class="col-md-6">
              <label class="form-label">Sales District</label>
              <select name="sales_district" class="form-select" data-kat-district>
                <option value="">-- Semua District --</option>
                <?php foreach ($kat_district_daftar as $kat_d): ?>
                  <option value="<?= kat_e($kat_d) ?>"><?= kat_e($kat_d) ?></option>
                <?php endforeach; ?>
              </select>
              <div class="form-text">
                Otomatis <b>Semua District</b> bila role WSS atau SMST.
              </div>
            </div>
            <div class="col-md-6">
              <label class="form-label">Status</label>
              <select name="status_aktif" class="form-select">
                <option>Aktif</option>
                <option>Nonaktif</option>
              </select>
            </div>
          </div>
        </div>
        <div class="modal-footer">
          <button type="button" class="btn btn-light" data-bs-dismiss="modal">Batal</button>
          <button class="btn btn-primary"><i class="fa-solid fa-user-plus"></i> Simpan Akun</button>
        </div>
      </form>
    </div>
  </div>
</div>

<script>
/* Menampilkan keterangan role (termasuk cakupan districtnya) tepat di bawah
   kotak Role, mengikuti pilihan yang sedang aktif pada formulir. */
(function () {
  document.querySelectorAll('[data-kat-role]').forEach(function (kotak) {
    var keterangan = kotak.parentElement.querySelector('[data-kat-ket]');

    var bentuk = kotak.closest('form');
    var distrik = bentuk ? bentuk.querySelector('[data-kat-district]') : null;

    function perbarui() {
      if (keterangan) {
        var pilihan = kotak.options[kotak.selectedIndex];
        keterangan.innerHTML = pilihan ? (pilihan.getAttribute('data-ket') || '') : '';
      }

      /* WSS & SMST = SEMUA DISTRICT: kotak district dikosongkan dan dimatikan,
         karena keduanya ada di setiap district. */
      if (distrik) {
        var semuaDistrict = (kotak.value === 'WSS' || kotak.value === 'SMST');

        if (semuaDistrict) {
          distrik.value = '';
          distrik.setAttribute('disabled', 'disabled');
          distrik.classList.add('bg-light');
        } else {
          distrik.removeAttribute('disabled');
          distrik.classList.remove('bg-light');
        }
      }
    }

    kotak.addEventListener('change', perbarui);
    perbarui();
  });
})();
</script>

<?php require_once __DIR__ . '/footer.php'; ?>
