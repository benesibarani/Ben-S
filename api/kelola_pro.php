<?php
/**
 * ============================================================================
 *  RTS PANEL BY BENE - KELOLA AKUN PRO (KHUSUS ADMIN)
 *  Berkas : api/kelola_pro.php
 *
 *  KEGUNAAN
 *  --------
 *  Dipakai oleh halaman "Kelola Akun PRO" di dalam aplikasi Android, supaya
 *  ADMIN dapat mengurus langganan petugas LANGSUNG DARI HP - tanpa membuka
 *  komputer:
 *
 *     - Melihat pernyataan pembayaran QRIS yang menunggu diperiksa
 *     - Menyetujui pembayaran  -> masa PRO 30 hari langsung diberikan
 *     - Menolak pernyataan pembayaran
 *     - Memberikan masa PRO (+30 hari, +90 hari) kepada petugas mana pun
 *     - Memberikan uji coba 7 hari
 *     - Menghentikan langganan (akun kembali GRATIS, iklan tampil kembali)
 *     - Memperbarui database (membuat kolom/tabel langganan yang belum ada)
 *
 *  CARA PAKAI (token login ADMIN pada header Authorization)
 *     GET  kelola_pro.php                    -> daftar akun + pembayaran
 *     POST kelola_pro.php  aksi=setujui      bayar_id=..
 *     POST kelola_pro.php  aksi=tolak        bayar_id=..
 *     POST kelola_pro.php  aksi=aktifkan     user_id=.. hari=30|90
 *     POST kelola_pro.php  aksi=trial        user_id=..
 *     POST kelola_pro.php  aksi=hentikan     user_id=..
 *     POST kelola_pro.php  aksi=perbarui_database
 *
 *  Aturannya sama dengan halaman website (langganan_admin.php) karena
 *  keduanya memakai berkas aturan yang sama: api/langganan_inti.php.
 * ============================================================================
 */

require_once __DIR__ . '/api_bootstrap.php';
require_once __DIR__ . '/langganan_inti.php';

rts_api_headers();
rts_api_handle_preflight();

$metode = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');

if ($metode !== 'GET' && $metode !== 'POST') {
    rts_api_fail('Method tidak diizinkan. Gunakan GET atau POST.', 405);
}

$user = rts_api_require_user();

if (strtoupper((string) ($user['role'] ?? '')) !== 'ADMIN') {
    rts_api_fail('Halaman kelola Akun PRO hanya untuk ADMIN.', 403);
}

$conn = rts_api_db();

if (!function_exists('rts_kp_daftar_akun')) {
    /**
     * Susunan kolom langganan yang benar-benar ada di database.
     */
    function rts_kp_bawaan(string $kolom): string
    {
        $angka = ['akun_pro'];

        if (in_array($kolom, $angka, true)) {
            return "'0' AS " . $kolom;
        }

        return "'' AS " . $kolom;
    }

    /**
     * Daftar seluruh pengguna beserta keadaan langganannya.
     *
     * @return array<int,array<string,mixed>>
     */
    function rts_kp_daftar_akun(mysqli $conn): array
    {
        $punya = rts_lg_kolom_tersedia($conn);

        $pilih = ['id', 'username', 'nama_lengkap', 'email', 'role', 'status_aktif'];

        foreach ($punya as $kolom => $ada) {
            $pilih[] = $ada ? $kolom : rts_kp_bawaan($kolom);
        }

        $hasil = @$conn->query(
            'SELECT ' . implode(', ', $pilih) . ' FROM sales_users '
            . 'ORDER BY akun_pro DESC, role ASC, username ASC'
        );

        $daftar = [];

        if ($hasil instanceof mysqli_result) {
            while ($baris = $hasil->fetch_assoc()) {
                $status = rts_lg_status($baris);
                $foto = (string) ($baris['foto_profil'] ?? '');

                $daftar[] = [
                    'id' => (int) $baris['id'],
                    'username' => (string) ($baris['username'] ?? ''),
                    'nama_lengkap' => (string) ($baris['nama_lengkap'] ?? ''),
                    'role' => strtoupper((string) ($baris['role'] ?? '')),
                    'status_aktif' => (string) ($baris['status_aktif'] ?? 'Aktif'),
                    'foto_profil' => $foto,
                    'akun_pro' => (int) $status['akun_pro'],
                    'pro_aktif' => (bool) $status['pro_aktif'],
                    'pro_tanpa_batas' => (bool) $status['pro_tanpa_batas'],
                    'trial_aktif' => (bool) $status['trial_aktif'],
                    'trial_tersedia' => (bool) $status['trial_tersedia'],
                    'trial_pernah_dipakai' => (bool) $status['trial_pernah_dipakai'],
                    'sisa_hari' => (int) $status['sisa_hari'],
                    'sisa_trial_hari' => (int) $status['sisa_trial_hari'],
                    'berlaku_sampai' => (string) $status['berlaku_sampai'],
                    'label' => (string) $status['label'],
                    'sumber' => (string) $status['sumber'],
                ];
            }

            $hasil->free();
        }

        return $daftar;
    }

    /**
     * Daftar pernyataan pembayaran (yang menunggu diperiksa di atas).
     *
     * @return array<int,array<string,mixed>>
     */
    function rts_kp_daftar_bayar(mysqli $conn): array
    {
        if (!rts_lg_tabel_pembayaran($conn)) {
            return [];
        }

        $hasil = @$conn->query(
            "SELECT p.id, p.user_id, p.jumlah, p.hari, p.catatan, p.status, p.dibuat,
                    p.diproses_pada, u.nama_lengkap, u.username, u.role
             FROM pembayaran_pro p
             LEFT JOIN sales_users u ON u.id = p.user_id
             ORDER BY (p.status = 'MENUNGGU') DESC, p.dibuat DESC
             LIMIT 60"
        );

        $daftar = [];

        if ($hasil instanceof mysqli_result) {
            while ($baris = $hasil->fetch_assoc()) {
                $daftar[] = [
                    'id' => (int) $baris['id'],
                    'user_id' => (int) $baris['user_id'],
                    'jumlah' => (int) $baris['jumlah'],
                    'hari' => (int) $baris['hari'],
                    'catatan' => (string) ($baris['catatan'] ?? ''),
                    'status' => strtoupper((string) $baris['status']),
                    'dibuat' => (string) ($baris['dibuat'] ?? ''),
                    'diproses_pada' => (string) ($baris['diproses_pada'] ?? ''),
                    'nama_lengkap' => (string) ($baris['nama_lengkap'] ?? ''),
                    'username' => (string) ($baris['username'] ?? ''),
                    'role' => strtoupper((string) ($baris['role'] ?? '')),
                ];
            }

            $hasil->free();
        }

        return $daftar;
    }

    /**
     * Memberi tahu seorang petugas lewat pemberitahuan (aman gagal).
     */
    function rts_kp_kabari(mysqli $conn, int $userId, string $judul, string $pesan): void
    {
        try {
            if (!is_file(__DIR__ . '/notif_otomatis.php')) {
                return;
            }

            require_once __DIR__ . '/notif_otomatis.php';

            if (!function_exists('rts_notif_kirim')) {
                return;
            }

            $email = '';

            $cari = @$conn->query('SELECT email FROM sales_users WHERE id = ' . $userId . ' LIMIT 1');

            if ($cari instanceof mysqli_result) {
                $email = (string) ($cari->fetch_assoc()['email'] ?? '');
                $cari->free();
            }

            if ($email === '') {
                return;
            }

            rts_notif_kirim(
                $conn,
                [$email],
                $judul,
                $pesan,
                'LANGGANAN',
                ['tipe' => 'langganan', 'halaman' => 'langganan'],
                'pengguna',
                $userId
            );
        } catch (Throwable $galat) {
            error_log('RTS kelola_pro: pemberitahuan gagal - ' . $galat->getMessage());
        }
    }

    /**
     * Seluruh jawaban dari endpoint ini.
     *
     * @return array<string,mixed>
     */
    function rts_kp_jawaban(mysqli $conn): array
    {
        return [
            'daftar' => rts_kp_daftar_akun($conn),
            'bayar' => rts_kp_daftar_bayar($conn),
            'kolom' => rts_lg_kolom_tersedia($conn),
            'tabel_pembayaran' => rts_lg_tabel_pembayaran($conn),
            'qris' => rts_lg_qris(),
            'versi_server' => 1,
        ];
    }
}

/* ---------------------------------------------------------------- kiriman */

$masukan = $_POST;

if ($metode === 'POST') {
    $mentah = file_get_contents('php://input');

    if (is_string($mentah) && trim($mentah) !== '') {
        $terurai = json_decode($mentah, true);

        if (is_array($terurai)) {
            $masukan = array_merge($masukan, $terurai);
        }
    }
}

$aksi = strtolower(trim((string) ($masukan['aksi'] ?? $_GET['aksi'] ?? '')));

if ($aksi === '') {
    rts_api_response(true, 'Daftar akun dan pembayaran.', rts_kp_jawaban($conn));
}

$userId = (int) ($masukan['user_id'] ?? 0);
$bayarId = (int) ($masukan['bayar_id'] ?? 0);
$hari = (int) ($masukan['hari'] ?? 0);
$kabar = '';
$berhasil = true;

if ($aksi === 'perbarui_database') {
    $catatan = rts_lg_siapkan_database($conn);

    $berhasil = true;
    $kabar = 'Pembaruan database selesai diperiksa.';
} elseif ($aksi === 'aktifkan') {
    if ($userId <= 0) {
        rts_api_fail('Petugas tidak dipilih.', 422);
    }

    $hasil = rts_lg_beri($conn, $userId, $hari > 0 ? $hari : rts_lg_durasi(), 'ADMIN ' . (string) $user['username']);

    $berhasil = !empty($hasil['berhasil']);
    $kabar = (string) $hasil['pesan'];

    if ($berhasil) {
        rts_kp_kabari(
            $conn,
            $userId,
            'Akun PRO Anda Sudah Aktif',
            'Akun PRO aktif ' . ($hari > 0 ? $hari : rts_lg_durasi())
                . ' hari ke depan. Seluruh iklan dimatikan. Terima kasih.'
        );
    }
} elseif ($aksi === 'trial') {
    if ($userId <= 0) {
        rts_api_fail('Petugas tidak dipilih.', 422);
    }

    $hasil = rts_lg_mulai_trial($conn, $userId);

    $berhasil = !empty($hasil['berhasil']);
    $kabar = (string) $hasil['pesan'];

    if ($berhasil) {
        rts_kp_kabari(
            $conn,
            $userId,
            'Uji Coba Akun PRO Dimulai',
            'Uji coba gratis ' . rts_lg_trial() . ' hari dimulai. Seluruh iklan '
                . 'dimatikan selama uji coba. Selamat mencoba!'
        );
    }
} elseif ($aksi === 'hentikan') {
    if ($userId <= 0) {
        rts_api_fail('Petugas tidak dipilih.', 422);
    }

    $bagian = [];

    if (rts_lg_ada_kolom($conn, 'akun_pro')) {
        $bagian[] = 'akun_pro = 0';
    }

    if (rts_lg_ada_kolom($conn, 'pro_selesai')) {
        $bagian[] = 'pro_selesai = NOW()';
    }

    if (rts_lg_ada_kolom($conn, 'trial_mulai')) {
        $bagian[] = "trial_mulai = IF(trial_mulai IS NULL OR trial_mulai = '', NOW(), trial_mulai)";
    }

    if (rts_lg_ada_kolom($conn, 'trial_selesai')) {
        $bagian[] = 'trial_selesai = NOW()';
    }

    if (!$bagian) {
        rts_api_fail('Kolom langganan belum ada di database. Tekan PERBARUI DATABASE lebih dahulu.', 409);
    }

    if (@$conn->query('UPDATE sales_users SET ' . implode(', ', $bagian) . ' WHERE id = ' . $userId)) {
        $kabar = 'Langganan dihentikan. Akun kembali GRATIS (iklan tampil kembali).';

        rts_kp_kabari(
            $conn,
            $userId,
            'Masa PRO Berakhir',
            'Masa langganan PRO akun Anda dihentikan Admin. Akun kembali GRATIS. '
                . 'Terima kasih telah memakai RTS Panel.'
        );
    } else {
        $berhasil = false;
        $kabar = 'Gagal menghentikan langganan: ' . $conn->error;
    }
} elseif ($aksi === 'setujui' || $aksi === 'tolak') {
    if ($bayarId <= 0) {
        rts_api_fail('Pernyataan pembayaran tidak dipilih.', 422);
    }

    if (!rts_lg_tabel_pembayaran($conn)) {
        rts_api_fail('Tabel pembayaran belum ada di database.', 409);
    }

    $cari = @$conn->query(
        'SELECT user_id, jumlah, hari FROM pembayaran_pro WHERE id = ' . $bayarId . ' LIMIT 1'
    );

    if (!($cari instanceof mysqli_result) || !($klaim = $cari->fetch_assoc())) {
        rts_api_fail('Data pembayaran tidak ditemukan.', 404);
    }

    $cari->free();

    $pemilik = (int) $klaim['user_id'];

    if ($aksi === 'setujui') {
        $hariKlaim = (int) $klaim['hari'] > 0 ? (int) $klaim['hari'] : rts_lg_durasi();

        $hasil = rts_lg_beri($conn, $pemilik, $hariKlaim, 'PEMBAYARAN QRIS (aplikasi)');

        $berhasil = !empty($hasil['berhasil']);
        $kabar = $berhasil
            ? 'Pembayaran disetujui. ' . (string) $hasil['pesan']
            : (string) $hasil['pesan'];

        if ($berhasil) {
            rts_kp_kabari(
                $conn,
                $pemilik,
                'Pembayaran Diterima - Akun PRO Aktif',
                'Pembayaran Anda sudah diperiksa dan diterima. Akun PRO aktif '
                    . $hariKlaim . ' hari ke depan. Terima kasih.'
            );
        }
    } else {
        if (@$conn->query(
            "UPDATE pembayaran_pro SET status = 'DITOLAK', diproses_pada = NOW() WHERE id = " . $bayarId
        )) {
            $kabar = 'Pernyataan pembayaran ditolak. Petugas tetap GRATIS sampai pembayaran diterima.';

            rts_kp_kabari(
                $conn,
                $pemilik,
                'Pernyataan Pembayaran Ditolak',
                'Pernyataan pembayaran Anda belum dapat diterima Admin. Bila sudah '
                    . 'membayar, hubungi Admin dengan bukti pembayaran.'
            );
        } else {
            $berhasil = false;
            $kabar = 'Gagal menolak pernyataan pembayaran.';
        }
    }
} else {
    rts_api_fail('Perintah "' . $aksi . '" belum dikenal.', 400);
}

$jawaban = rts_kp_jawaban($conn);
$jawaban['berhasil'] = $berhasil;

rts_api_response($berhasil, $kabar, $jawaban, $berhasil ? 200 : 400);
