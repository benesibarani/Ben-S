<?php
/**
 * RTS Panel API - Penerapan Pengajuan ke Master Customer
 * Dipakai oleh request_action.php saat pengajuan DISETUJUI.
 *
 * Logika disalin dari inbox.php agar hasil approve dari Android
 * persis sama dengan hasil approve dari website.
 *
 * File ini TIDAK dipanggil langsung oleh aplikasi.
 */

if (!defined('RTS_API_BOOTSTRAP')) {
    http_response_code(403);
    exit;
}

/**
 * Mengubah nilai kolom `week` pada pengajuan menjadi nilai kolom `kunjungan`
 * pada master_toko.
 *
 * Format baru : Weekly / Bi-Weekly Ganjil / Bi-Weekly Genap
 * Format lama : Ganjil / Genap
 *
 * Mengembalikan teks kosong bila nilai tidak dikenali.
 */
function rts_api_week_ke_kunjungan(string $nilai): string
{
    $bersih = trim($nilai);

    if ($bersih === '') {
        return '';
    }

    if (strcasecmp($bersih, 'Weekly') === 0) {
        return 'Weekly';
    }

    if (strcasecmp($bersih, 'Bi-Weekly Ganjil') === 0) {
        return 'Bi-Weekly Ganjil';
    }

    if (strcasecmp($bersih, 'Bi-Weekly Genap') === 0) {
        return 'Bi-Weekly Genap';
    }

    if (strcasecmp($bersih, 'Ganjil') === 0) {
        return 'Bi-Weekly Ganjil';
    }

    if (strcasecmp($bersih, 'Genap') === 0) {
        return 'Bi-Weekly Genap';
    }

    return '';
}

/**
 * Penerapan pengajuan customer biasa (pengajuan_sales).
 * Jenis: Tambah Baru / Ganti Nama / Ganti Alamat / Hapus Toko.
 *
 * @return array{ok: bool, message: string}
 */
function rts_api_apply_customer_request(mysqli $conn, int $id, string $actor): array
{
    $stmt = $conn->prepare('SELECT * FROM pengajuan_sales WHERE id=? LIMIT 1');
    if (!$stmt) {
        return ['ok' => false, 'message' => 'Gagal membaca pengajuan.'];
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $result = $stmt->get_result();
    $request = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    if (!$request) {
        return ['ok' => false, 'message' => 'Pengajuan tidak ditemukan.'];
    }

    $jenis = strtolower(trim((string) ($request['jenis_request'] ?? '')));
    $tipe = strtoupper(trim((string) ($request['tipe_baru'] ?? 'REGULER')));
    if (!in_array($tipe, ['REGULER', 'GSP'], true)) {
        $tipe = 'REGULER';
    }

    $hasTipe = rts_api_has_column('master_toko', 'tipe_customer');

    /* ------------------------------------------------------- Tambah Baru */
    if (in_array($jenis, ['tambah baru', 'tambah outlet', 'penambahan outlet'], true)) {
        if ($hasTipe) {
            $sql = 'INSERT INTO master_toko
                    (nama_toko, id_customer, tipe_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "Aktif")';
        } else {
            $sql = 'INSERT INTO master_toko
                    (nama_toko, id_customer, salesman, alamat, kunjungan, hari, sales_district, longitude, latitude, status_aktif)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, "Aktif")';
        }

        $insert = $conn->prepare($sql);
        if (!$insert) {
            return ['ok' => false, 'message' => 'Gagal menyiapkan data customer baru.'];
        }

        $namaToko = (string) ($request['nama_toko_baru'] ?? '');
        $idCustomer = (string) ($request['id_customer'] ?? '');
        $salesman = (string) ($request['salesman'] ?? '');
        $alamat = (string) ($request['alamat_baru'] ?? '');
        // Kolom kunjungan memakai nilai frekuensi (Weekly / Bi-Weekly ...),
        // bukan nama hari.
        $kunjungan = rts_api_week_ke_kunjungan((string) ($request['week'] ?? ''));

        if ($kunjungan === '') {
            $kunjungan = rts_api_week_ke_kunjungan(
                (string) ($request['rute_kunjungan'] ?? '')
            );
        }

        if ($kunjungan === '') {
            $kunjungan = 'Weekly';
        }
        $hari = (string) ($request['visit_day_baru'] ?? '');
        $district = (string) ($request['sales_distric'] ?? '');
        $longitude = '';
        $latitude = '';

        if ($hasTipe) {
            $insert->bind_param(
                'ssssssssss',
                $namaToko,
                $idCustomer,
                $tipe,
                $salesman,
                $alamat,
                $kunjungan,
                $hari,
                $district,
                $longitude,
                $latitude
            );
        } else {
            $insert->bind_param(
                'sssssssss',
                $namaToko,
                $idCustomer,
                $salesman,
                $alamat,
                $kunjungan,
                $hari,
                $district,
                $longitude,
                $latitude
            );
        }

        $ok = $insert->execute();
        $insert->close();

        return $ok
            ? ['ok' => true, 'message' => 'Customer baru berhasil ditambahkan.']
            : ['ok' => false, 'message' => 'Customer baru gagal ditambahkan.'];
    }

    /* ------------------------------------------------------- Hapus Toko */
    if (in_array($jenis, ['hapus toko', 'penghapusan outlet'], true)) {
        $conn->begin_transaction();

        try {
            $find = $conn->prepare('SELECT * FROM master_toko WHERE id_customer=? LIMIT 1');
            $find->bind_param('s', $request['id_customer']);
            $find->execute();
            $hasilFind = $find->get_result();
            $customer = $hasilFind ? $hasilFind->fetch_assoc() : null;
            $find->close();

            if (!$customer) {
                throw new RuntimeException('Customer tidak ditemukan pada Master Customer.');
            }

            $tipeLama = $customer['tipe_customer'] ?? 'REGULER';

            $archive = $conn->prepare(
                'INSERT INTO master_toko_deleted
                 (original_id, id_customer, nama_toko, tipe_customer, salesman, alamat, kunjungan, hari,
                  sales_district, longitude, latitude, status_aktif, alasan_penghapusan, dihapus_oleh)
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
            );

            if (!$archive) {
                throw new RuntimeException('Gagal menyiapkan arsip customer.');
            }

            $archive->bind_param(
                'isssssssssssss',
                $customer['id'],
                $customer['id_customer'],
                $customer['nama_toko'],
                $tipeLama,
                $customer['salesman'],
                $customer['alamat'],
                $customer['kunjungan'],
                $customer['hari'],
                $customer['sales_district'],
                $customer['longitude'],
                $customer['latitude'],
                $customer['status_aktif'],
                $request['alasan'],
                $actor
            );

            if (!$archive->execute()) {
                throw new RuntimeException('Arsip customer gagal dibuat.');
            }
            $archive->close();

            $delete = $conn->prepare('DELETE FROM master_toko WHERE id_customer=?');
            $delete->bind_param('s', $request['id_customer']);

            if (!$delete->execute()) {
                throw new RuntimeException('Customer gagal dihapus.');
            }
            $delete->close();

            $conn->commit();

            return ['ok' => true, 'message' => 'Customer diarsipkan lalu dihapus.'];
        } catch (Throwable $error) {
            $conn->rollback();

            return ['ok' => false, 'message' => $error->getMessage()];
        }
    }

    /* ------------------------------------- Ganti Nama / Ganti Alamat */

    // Kolom yang diperbarui disusun bertahap.
    // Kolom kunjungan selalu ditulis, persis seperti pada jalur Tambah Baru,
    // tetapi hanya bila nilai frekuensinya dikenali.
    $set = ['nama_toko=?', 'alamat=?', 'hari=?', 'sales_district=?'];
    $nilai = [
        $request['nama_toko_baru'],
        $request['alamat_baru'],
        $request['visit_day_baru'],
        $request['sales_distric'],
    ];
    $tipeParam = 'ssss';

    if ($hasTipe) {
        $set[] = 'tipe_customer=?';
        $nilai[] = $tipe;
        $tipeParam .= 's';
    }

    $kunjunganBaru = rts_api_week_ke_kunjungan((string) ($request['week'] ?? ''));

    if ($kunjunganBaru !== '') {
        $set[] = 'kunjungan=?';
        $nilai[] = $kunjunganBaru;
        $tipeParam .= 's';
    }

    $nilai[] = $request['id_customer'];
    $tipeParam .= 's';

    $update = $conn->prepare(
        'UPDATE master_toko SET ' . implode(', ', $set) . ' WHERE id_customer=?'
    );

    if (!$update) {
        return ['ok' => false, 'message' => 'Gagal menyiapkan perubahan customer.'];
    }

    $update->bind_param($tipeParam, ...$nilai);

    $ok = $update->execute();
    $changes = $update->affected_rows;
    $update->close();

    if (!$ok) {
        return ['ok' => false, 'message' => 'Perubahan customer gagal disimpan.'];
    }

    if ($changes === 0) {
        return [
            'ok' => true,
            'message' => 'Pengajuan disetujui, namun data customer tidak berubah (nilai sama).',
        ];
    }

    return ['ok' => true, 'message' => 'Data customer berhasil diperbarui.'];
}

/**
 * Penerapan pengajuan GSP (pengajuan_gsp).
 * - PENAMBAHAN  : customer ditandai GSP.
 * - PENGHAPUSAN : kategori GSP dikembalikan menjadi REGULER.
 *
 * @return array{ok: bool, message: string}
 */
function rts_api_apply_gsp_request(mysqli $conn, int $id): array
{
    if (!rts_api_has_column('master_toko', 'tipe_customer')) {
        return [
            'ok' => false,
            'message' => 'Kolom tipe_customer belum ada pada Master Customer. Jalankan migrasi terlebih dahulu.',
        ];
    }

    $stmt = $conn->prepare('SELECT * FROM pengajuan_gsp WHERE id=? LIMIT 1');
    if (!$stmt) {
        return ['ok' => false, 'message' => 'Gagal membaca pengajuan GSP.'];
    }

    $stmt->bind_param('i', $id);
    $stmt->execute();
    $result = $stmt->get_result();
    $request = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    if (!$request) {
        return ['ok' => false, 'message' => 'Pengajuan GSP tidak ditemukan.'];
    }

    $jenis = strtoupper(trim((string) ($request['jenis_request'] ?? 'PENAMBAHAN')));
    $idCustomer = ($jenis === 'PENGHAPUSAN')
        ? (string) ($request['toko_lama_id'] ?? '')
        : (string) ($request['toko_baru_id'] ?? '');

    if (trim($idCustomer) === '') {
        return ['ok' => false, 'message' => 'ID customer pada pengajuan GSP belum diisi.'];
    }

    $tipe = ($jenis === 'PENGHAPUSAN') ? 'REGULER' : 'GSP';

    $update = $conn->prepare('UPDATE master_toko SET tipe_customer=? WHERE id_customer=?');
    if (!$update) {
        return ['ok' => false, 'message' => 'Gagal menyiapkan perubahan kategori GSP.'];
    }

    $update->bind_param('ss', $tipe, $idCustomer);
    $ok = $update->execute();
    $changes = $update->affected_rows;
    $update->close();

    if (!$ok) {
        return ['ok' => false, 'message' => 'Perubahan kategori GSP gagal disimpan.'];
    }

    if ($changes === 0) {
        return [
            'ok' => false,
            'message' => 'Customer dengan ID ' . $idCustomer . ' tidak ditemukan pada Master Customer.',
        ];
    }

    return [
        'ok' => true,
        'message' => ($tipe === 'GSP')
            ? 'Customer berhasil ditandai GSP.'
            : 'Kategori GSP customer berhasil dikembalikan menjadi REGULER.',
    ];
}
