<?php
$sb_role = strtoupper((string)($_SESSION['role'] ?? ''));
$sb_page = basename($_SERVER['PHP_SELF']);
function sb_active(string $file): string { global $sb_page; return $sb_page === $file ? 'active' : ''; }
$sb_menunggu_pro = 0;

/* Jumlah pernyataan pembayaran QRIS yang belum diperiksa (lencana menu).
   Aman gagal: bila tabel belum ada atau koneksi tidak tersedia, 0. */
if (isset($conn) && $conn instanceof mysqli) {
    $sb_tabel_bayar = @$conn->query("SHOW TABLES LIKE 'pembayaran_pro'");

    if ($sb_tabel_bayar instanceof mysqli_result && $sb_tabel_bayar->num_rows > 0) {
        $sb_tabel_bayar->free();

        $sb_hitung_bayar = @$conn->query("SELECT COUNT(*) AS n FROM pembayaran_pro WHERE status = 'MENUNGGU'");

        if ($sb_hitung_bayar instanceof mysqli_result) {
            $sb_menunggu_pro = (int) ($sb_hitung_bayar->fetch_assoc()['n'] ?? 0);
            $sb_hitung_bayar->free();
        }
    }
}

?><aside class="rts-sidebar"><div class="rts-brand"><span class="brand-mark">R</span><span class="brand-text">RTS <b>PANEL</b></span><button class="sidebar-toggle" id="sidebarToggle" type="button" title="Minimalkan menu"><i class="fa-solid fa-angles-left"></i></button></div><div class="rts-user"><div class="avatar"><?= strtoupper(substr($_SESSION['nama'] ?? 'U', 0, 1)) ?></div><div><strong><?= htmlspecialchars($_SESSION['nama'] ?? '') ?></strong><small><?= htmlspecialchars($sb_role) ?></small></div></div><nav class="rts-menu"><small class="menu-label">MENU UTAMA</small><a class="<?= sb_active('dashboard.php') ?>" href="dashboard.php"><i class="fa-solid fa-chart-line"></i>Dashboard</a><a class="<?= sb_active('master_customer.php') ?>" href="master_customer.php"><i class="fa-solid fa-store"></i>Master Customer</a><?php if (in_array($sb_role, ['ADMIN','ASS'], true)): ?><a class="<?= sb_active('upload_customer.php') ?>" href="upload_customer.php"><i class="fa-solid fa-file-arrow-up"></i>Upload Customer</a><?php endif; ?><a class="<?= sb_active('pengajuan_toko.php') ?>" href="pengajuan_toko.php"><i class="fa-solid fa-file-pen"></i>Pengajuan Customer</a><a class="<?= sb_active('gsp.php') ?>" href="gsp.php"><i class="fa-solid fa-handshake"></i>GSP</a><a class="<?= sb_active('inbox.php') ?>" href="inbox.php"><i class="fa-solid fa-inbox"></i>Inbox</a><a class="<?= sb_active('notifications.php') ?>" href="notifications.php"><i class="fa-solid fa-bell"></i>Notifikasi</a> <?php if (in_array($sb_role, ['ADMIN', 'ASS'], true)): ?><small class="menu-label">KELOLA AKUN</small><a class="<?= sb_active('kelola_akun_tim.php') ?>" href="kelola_akun_tim.php"><i class="fa-solid fa-users-gear"></i>Kelola Akun Tim</a><?php endif; ?><?php if ($sb_role === 'ADMIN'): ?><small class="menu-label">ADMINISTRASI</small><a class="<?= sb_active('manage_users.php') ?>" href="manage_users.php"><i class="fa-solid fa-users-gear"></i>Kelola User</a><a class="<?= sb_active('langganan_admin.php') ?>" href="langganan_admin.php"><i class="fa-solid fa-crown"></i>Langganan PRO<?php if ($sb_menunggu_pro > 0): ?><span style="margin-left:auto;background:#e04b4b;color:#fff;border-radius:999px;padding:1px 8px;font-size:11px;font-weight:700" title="Pernyataan pembayaran menunggu diperiksa"><?= $sb_menunggu_pro > 99 ? '99+' : (int) $sb_menunggu_pro ?></span><?php endif; ?></a><a class="<?= sb_active('app_versi.php') ?>" href="app_versi.php"><i class="fa-solid fa-mobile-screen-button"></i>Versi Aplikasi</a><?php endif; ?><small class="menu-label">AKUN</small><a class="<?= sb_active('akun.php') ?>" href="akun.php"><i class="fa-solid fa-user-gear"></i>Akun Saya</a><a href="logout.php"><i class="fa-solid fa-right-from-bracket"></i>Keluar</a></nav></aside><div class="rts-mobile-overlay"></div>
