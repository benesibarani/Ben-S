<?php
require_once __DIR__ . '/config.php';
require_once __DIR__ . '/auth.php';
rts_require_login();

if (!rts_is_approver()) {
    http_response_code(403);
    exit('Akses hanya untuk ADMIN atau ASS.');
}

$message = '';
$error = '';
$isAdmin = rts_is_admin();
$required = [
    'id_customer', 'nama_toko', 'tipe_customer', 'salesman', 'alamat',
    'kunjungan', 'hari', 'sales_district', 'longitude', 'latitude', 'status_aktif'
];

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['file_customer'])) {
    // Mencegah proses upload besar dihentikan oleh batas waktu PHP.
    @set_time_limit(0);

    $file = $_FILES['file_customer'];
    $replace = $isAdmin && !empty($_POST['replace_all']);

    if ($file['error'] !== UPLOAD_ERR_OK) {
        $error = 'File gagal diupload. Kode error: ' . (int) $file['error'];
    } elseif ($file['size'] > 20 * 1024 * 1024) {
        $error = 'Ukuran file maksimal 20 MB.';
    } else {
        $handle = fopen($file['tmp_name'], 'rb');

        if (!$handle) {
            $error = 'File CSV tidak dapat dibaca.';
        } else {
            // Hilangkan BOM UTF-8 jika file berasal dari Excel.
            $firstLine = fgets($handle);
            if ($firstLine === false) {
                $error = 'File CSV kosong.';
            } else {
                $firstLine = preg_replace('/^\xEF\xBB\xBF/', '', $firstLine);
                $header = str_getcsv($firstLine, ',');
                $header = array_map(static fn($value) => strtolower(trim((string) $value)), $header);

                $missing = array_diff($required, $header);
                $duplicates = array_diff_assoc($header, array_unique($header));

                if ($missing) {
                    $error = 'Kolom tidak lengkap: ' . implode(', ', $missing);
                } elseif ($duplicates) {
                    $error = 'Ada nama kolom CSV yang berulang.';
                } elseif (count($header) !== count($required)) {
                    $error = 'Jumlah kolom CSV harus tepat 11 kolom. Kolom id dan created_at tidak perlu diupload.';
                } else {
                    try {
                        $conn->begin_transaction();

                        if ($replace && !$conn->query('DELETE FROM master_toko')) {
                            throw new RuntimeException('Data customer lama gagal dihapus.');
                        }

                        // Ambil ID yang sudah ada satu kali saja, bukan SELECT untuk setiap baris.
                        $existing = [];
                        $result = $conn->query('SELECT id_customer FROM master_toko');
                        if (!$result) {
                            throw new RuntimeException('Gagal membaca data customer: ' . $conn->error);
                        }
                        while ($item = $result->fetch_assoc()) {
                            $existing[(string) $item['id_customer']] = true;
                        }
                        $result->free();

                        $insert = $conn->prepare(
                            'INSERT INTO master_toko
                            (id_customer, nama_toko, tipe_customer, salesman, alamat, kunjungan, hari,
                             sales_district, longitude, latitude, status_aktif)
                             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
                        );
                        $update = $conn->prepare(
                            'UPDATE master_toko SET nama_toko=?, tipe_customer=?, salesman=?, alamat=?,
                             kunjungan=?, hari=?, sales_district=?, longitude=?, latitude=?, status_aktif=?
                             WHERE id_customer=?'
                        );

                        if (!$insert || !$update) {
                            throw new RuntimeException('Statement database gagal dibuat: ' . $conn->error);
                        }

                        $count = 0;
                        $skipped = 0;
                        $csvLine = 1;

                        while (($row = fgetcsv($handle, 0, ',')) !== false) {
                            $csvLine++;

                            if (count($row) === 1 && trim((string) $row[0]) === '') {
                                continue;
                            }
                            if (count($row) !== count($header)) {
                                throw new RuntimeException('Format kolom tidak sesuai pada baris CSV ' . $csvLine . '.');
                            }

                            $values = array_combine($header, $row);
                            $id = trim((string) ($values['id_customer'] ?? ''));
                            if ($id === '') {
                                $skipped++;
                                continue;
                            }

                            $type = strtoupper(trim((string) ($values['tipe_customer'] ?? 'REGULER')));
                            if (!in_array($type, ['REGULER', 'GSP'], true)) {
                                throw new RuntimeException('tipe_customer harus REGULER atau GSP pada baris CSV ' . $csvLine . '.');
                            }
                            $status = trim((string) ($values['status_aktif'] ?? '')) === 'Nonaktif' ? 'Nonaktif' : 'Aktif';

                            $nama = trim((string) ($values['nama_toko'] ?? ''));
                            $salesman = trim((string) ($values['salesman'] ?? ''));
                            $alamat = trim((string) ($values['alamat'] ?? ''));
                            $kunjungan = trim((string) ($values['kunjungan'] ?? ''));
                            $hari = trim((string) ($values['hari'] ?? ''));
                            $district = trim((string) ($values['sales_district'] ?? ''));
                            $longitude = trim((string) ($values['longitude'] ?? ''));
                            $latitude = trim((string) ($values['latitude'] ?? ''));

                            if (isset($existing[$id])) {
                                $update->bind_param('sssssssssss', $nama, $type, $salesman, $alamat, $kunjungan, $hari, $district, $longitude, $latitude, $status, $id);
                                $ok = $update->execute();
                            } else {
                                $insert->bind_param('sssssssssss', $id, $nama, $type, $salesman, $alamat, $kunjungan, $hari, $district, $longitude, $latitude, $status);
                                $ok = $insert->execute();
                                if ($ok) {
                                    $existing[$id] = true;
                                }
                            }

                            if (!$ok) {
                                throw new RuntimeException('Gagal pada baris CSV ' . $csvLine . ', ID ' . $id . ': ' . $conn->error);
                            }
                            $count++;
                        }

                        $conn->commit();
                        $message = $count . ' data berhasil diproses' . ($skipped ? ', ' . $skipped . ' baris kosong dilewati' : '') . '.';

                        /* -----------------------------------------------------------------
                         * PEMBERITAHUAN OTOMATIS: DATA CUSTOMER DIPERBARUI
                         *
                         * Dikirim ke seluruh petugas (kecuali Admin yang melakukan)
                         * langsung ke layar HP, sehingga mereka dapat menarik data
                         * terbaru tanpa harus diberi tahu lewat pesan terpisah.
                         *
                         * Aman gagal: bila tabel pemberitahuan atau Firebase belum
                         * ada, bagian ini berhenti dengan tenang dan unggahan tetap
                         * dianggap berhasil.
                         * ----------------------------------------------------------------- */
                        if (is_file(__DIR__ . '/api/notif_otomatis.php')) {
                            require_once __DIR__ . '/api/notif_otomatis.php';

                            if (function_exists('rts_notif_aktivitas') && isset($conn) && $conn instanceof mysqli) {
                                try {
                                    $judulNotif = 'Data Customer Diperbarui';
                                    $pesanNotif = (string) $count . ' data customer baru saja '
                                        . 'diperbarui oleh Admin pada ' . date('d-m-Y H:i') . '. '
                                        . 'Buka menu Sinkronisasi untuk mengambil data terbaru.';

                                    rts_notif_aktivitas(
                                        $conn,
                                        $judulNotif,
                                        $pesanNotif,
                                        'AKTIVITAS',
                                        ['halaman' => 'master_customer'],
                                        (string) ($_SESSION['email'] ?? '')
                                    );
                                } catch (Throwable $galatNotif) {
                                    error_log('RTS notif customer: ' . $galatNotif->getMessage());
                                }
                            }
                        }
                    } catch (Throwable $exception) {
                        $conn->rollback();
                        $error = 'Upload dibatalkan: ' . $exception->getMessage();
                    }
                }
            }
            fclose($handle);
        }
    }
}

require_once __DIR__ . '/header.php';
?>
<div class="card border-0 shadow-sm" style="max-width:900px">
    <div class="card-body p-4">
        <h3>Upload Data Customer</h3>
        <p class="text-muted">ADMIN/ASS dapat upload CSV UTF-8 dengan pemisah koma (,).</p>
        <?php if ($message): ?><div class="alert alert-success"><?= htmlspecialchars($message) ?></div><?php endif; ?>
        <?php if ($error): ?><div class="alert alert-danger"><?= htmlspecialchars($error) ?></div><?php endif; ?>
        <a class="btn btn-outline-success mb-3" href="template_customer.csv" download>Download Template CSV</a>
        <form method="post" enctype="multipart/form-data">
            <input type="file" name="file_customer" class="form-control mb-3" accept=".csv,text/csv" required>
            <?php if ($isAdmin): ?>
                <div class="form-check border border-danger rounded p-3 mb-3">
                    <input class="form-check-input" type="checkbox" name="replace_all" id="replaceAll">
                    <label class="form-check-label text-danger fw-bold" for="replaceAll">Hapus semua data customer lama sebelum upload</label>
                    <div class="small text-muted">Gunakan hanya setelah backup. Data master_toko akan diganti seluruhnya.</div>
                </div>
            <?php endif; ?>
            <button class="btn btn-primary">Upload dan Update Data</button>
        </form>
        <hr>
        <small class="text-muted">Jika ID Customer sudah ada, data diperbarui. Jika belum ada, data ditambahkan. Proses menggunakan transaksi dan menampilkan baris yang bermasalah jika terjadi error.</small>
    </div>
</div>
<?php require_once __DIR__ . '/footer.php'; ?>
