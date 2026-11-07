<?php
/**
 * RTS Panel API - Inti pemeriksaan PIN pemulihan (dipakai bersama oleh
 * verifikasi_pin_reset.php dan reset_password_pin.php).
 *
 * Aturan:
 *   - PIN salah sekali pun -> aplikasi mengarahkan pengguna ke WhatsApp Admin.
 *   - 5 kali PIN salah berturut-turut -> reset dikunci 15 menit.
 *   - Pesan galat dibuat sama untuk username tidak ada dan PIN salah,
 *     supaya username yang terdaftar tidak bisa ditebak.
 */

const RTS_PIN_MAKS_SALAH = 5;
const RTS_PIN_KUNCI_MENIT = 15;

/**
 * Memeriksa username dan PIN. Balasan:
 *   ['ok' => true,  'id' => int]
 *   ['ok' => false, 'status' => int, 'message' => string]
 */
function rts_pin_periksa(mysqli $conn, string $username, string $pin): array
{
    $galatSalah = ['ok' => false, 'status' => 401, 'message' => 'Username atau PIN salah. Hubungi Admin.'];

    $kolomLogin = rts_api_has_column('sales_users', 'username') ? 'username' : 'email';

    $stmt = $conn->prepare(
        'SELECT id, status_aktif, pin_hash, pin_gagal, pin_terkunci_sampai
         FROM sales_users
         WHERE ' . $kolomLogin . ' = ?
         LIMIT 1'
    );

    if (!$stmt) {
        error_log('RTS API pin pemulihan prepare error: ' . $conn->error);

        return ['ok' => false, 'status' => 500, 'message' => 'Server sedang mengalami gangguan.'];
    }

    $stmt->bind_param('s', $username);
    $stmt->execute();
    $hasil = $stmt->get_result();
    $akun = $hasil ? $hasil->fetch_assoc() : null;
    $stmt->close();

    if (!$akun) {
        return $galatSalah;
    }

    $idUser = (int) $akun['id'];

    if (strcasecmp((string) ($akun['status_aktif'] ?? 'Aktif'), 'Aktif') !== 0) {
        return ['ok' => false, 'status' => 403, 'message' => 'Akun tidak aktif. Hubungi Admin.'];
    }

    if (trim((string) ($akun['pin_hash'] ?? '')) === '') {
        return ['ok' => false, 'status' => 422, 'message' => 'PIN belum diatur untuk akun ini. Hubungi Admin.'];
    }

    $kunciSampai = (string) ($akun['pin_terkunci_sampai'] ?? '');

    if ($kunciSampai !== '' && strtotime($kunciSampai) > time()) {
        $sisaMenit = (int) ceil((strtotime($kunciSampai) - time()) / 60);

        return [
            'ok' => false,
            'status' => 429,
            'message' => 'Reset dikunci sementara karena PIN salah berulang kali. Coba lagi dalam '
                . $sisaMenit . ' menit atau hubungi Admin.',
        ];
    }

    if (!password_verify($pin, (string) $akun['pin_hash'])) {
        $gagal = ((int) ($akun['pin_gagal'] ?? 0)) + 1;

        if ($gagal >= RTS_PIN_MAKS_SALAH) {
            $kunci = date('Y-m-d H:i:s', time() + (RTS_PIN_KUNCI_MENIT * 60));
            $catat = $conn->prepare(
                'UPDATE sales_users SET pin_gagal = 0, pin_terkunci_sampai = ? WHERE id = ?'
            );

            if ($catat) {
                $catat->bind_param('si', $kunci, $idUser);
                $catat->execute();
                $catat->close();
            }
        } else {
            $catat = $conn->prepare('UPDATE sales_users SET pin_gagal = ? WHERE id = ?');

            if ($catat) {
                $catat->bind_param('ii', $gagal, $idUser);
                $catat->execute();
                $catat->close();
            }
        }

        return $galatSalah;
    }

    return ['ok' => true, 'id' => $idUser];
}

/** Mengosongkan penghitung PIN salah setelah PIN benar. */
function rts_pin_bersihkan_gagal(mysqli $conn, int $idUser): void
{
    $catat = $conn->prepare(
        'UPDATE sales_users SET pin_gagal = 0, pin_terkunci_sampai = NULL WHERE id = ?'
    );

    if ($catat) {
        $catat->bind_param('i', $idUser);
        $catat->execute();
        $catat->close();
    }
}
