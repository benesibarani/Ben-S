/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - PENGUJI api/program.php (bukan untuk hosting)
 *  Berkas : perkakas/uji_program_api.mjs
 *
 *  Cara pakai:
 *      node perkakas/uji_program_api.mjs
 *
 *  Yang dikerjakan:
 *    1. Menyiapkan folder kerja /home/user/uji berisi salinan api/program.php,
 *       api/langganan_inti.php, bootstrap tiruan, dan database tiruan.
 *    2. Menjalankan keadaan pengujian memakai PHP 8.2 asli (php-wasm).
 *    3. Memeriksa kode HTTP, isi balasan JSON, dan aturan hak:
 *       ADMIN/ASS boleh menulis, peran lain hanya membaca, AKUN GRATIS ditolak.
 * ============================================================================
 */
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';

const REPO = path.resolve(new URL('..', import.meta.url).pathname);
const UJI = '/home/user/uji';

let lulus = 0;
let gagal = 0;

function periksa(nama, syarat, tambahan = '') {
  if (syarat) {
    lulus++;
    console.log('   [V] ' + nama);
  } else {
    gagal++;
    console.log('   [X] ' + nama + (tambahan ? ' -> ' + tambahan : ''));
  }
}

/* ------------------------------------------------------------- penyiapan */

function siapkan() {
  fs.rmSync(UJI, { recursive: true, force: true });
  fs.mkdirSync(UJI + '/api', { recursive: true });

  fs.copyFileSync(REPO + '/api/program.php', UJI + '/api/program.php');
  fs.copyFileSync(REPO + '/api/langganan_inti.php', UJI + '/api/langganan_inti.php');
  fs.copyFileSync(REPO + '/api/kolom.php', UJI + '/api/kolom.php');
  fs.copyFileSync(REPO + '/perkakas/uji_api_bootstrap_tiruan.php', UJI + '/api/api_bootstrap.php');
  fs.copyFileSync(REPO + '/perkakas/uji_mysqli_tiruan.php', UJI + '/mysqli_tiruan.php');
  fs.copyFileSync(REPO + '/perkakas/uji_tes_program_api.php', UJI + '/tes_program_api.php');
  fs.writeFileSync(UJI + '/config.php', "<?php\n// Tiruan: database uji diambil dari RtsUjiDb.\n");
}

/* --------------------------------------------------------------- menjalankan */

function jalankan(keadaan) {
  fs.writeFileSync(UJI + '/keadaan.json', JSON.stringify(keadaan, null, 2));

  let keluaran = '';

  try {
    keluaran = execFileSync('node', [REPO + '/perkakas/run_php.mjs', UJI, 'tes_program_api.php'], {
      cwd: REPO,
      encoding: 'utf8',
      timeout: 240000,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (galat) {
    keluaran = String(galat.stdout || '') + '\n' + String(galat.stderr || '');
  }

  const json = keluaran.match(/###JSON###\n([\s\S]*?)\n###END###/);
  const kode = keluaran.match(/kode_http=(\d+)/);

  return {
    mentah: keluaran,
    kode: kode ? Number(kode[1]) : 0,
    balasan: json ? JSON.parse(json[1]) : null,
  };
}

/* ------------------------------------------------------------- keadaan uji */

const token = 'uji_token_palsu_yang_panjang_sekali_1234567890';

const userRtsPro = {
  id: 7,
  username: 'sales_pro',
  nama_lengkap: 'Sales PRO',
  role: 'RTS',
  salesman: 'UJI',
  sales_district: 'MEDAN KOTA',
  status_aktif: 'Aktif',
  akun_pro: 1,
};

const userRtsGratis = { ...userRtsPro, id: 8, username: 'sales_gratis', akun_pro: 0 };

const userAdmin = {
  ...userRtsPro,
  id: 9,
  username: 'admin_uji',
  nama_lengkap: 'Admin Uji',
  role: 'ADMIN',
};

const userWss = {
  ...userRtsPro,
  id: 10,
  username: 'wss_uji',
  nama_lengkap: 'WSS Uji',
  role: 'WSS',
  sales_district: '',
};

const langgananPro = {
  id: 7,
  username: 'sales_pro',
  akun_pro: 1,
  pro_mulai: new Date(Date.now() - 10 * 86400000).toISOString().slice(0, 10),
  pro_selesai: new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10),
};

const langgananGratis = {
  id: 8,
  username: 'sales_gratis',
  akun_pro: 0,
  pro_selesai: '',
  trial_selesai: '',
};

const duaProduk = [
  {
    id: 1,
    jenis: 'INTRODEAL',
    sku: 'WI-001',
    barcode_pack: '8991234567890',
    nama: 'Wismilak Inti Kretek',
    merek: 'Wismilak',
    isi_per_pack: 10,
    catatan: 'Produk launching Oktober',
    periode: 'Okt 2026',
    aktif: 1,
    diubah_oleh: 'admin_uji',
    diubah_pada: '2026-10-05 09:00:00',
  },
  {
    id: 2,
    jenis: 'BD',
    sku: 'BD-777',
    barcode_pack: '8997777777777',
    nama: 'Wismilak Diplomat BD',
    merek: 'Wismilak',
    isi_per_pack: 12,
    catatan: '',
    periode: 'Okt 2026',
    aktif: 1,
    diubah_oleh: 'admin_uji',
    diubah_pada: '2026-10-05 09:10:00',
  },
];

console.log('[i] Menyiapkan folder uji ' + UJI + ' ...');
siapkan();

/* ------------------------------------------------------- 1. kesepakatan API */

console.log('\n[1] Kesepakatan fungsi: rts_api_* yang dipakai program.php ada di bootstrap asli');
{
  const endpoint = fs.readFileSync(REPO + '/api/program.php', 'utf8');
  const bootstrap = fs.readFileSync(REPO + '/api/api_bootstrap.php', 'utf8');
  const kolom = fs.readFileSync(REPO + '/api/kolom.php', 'utf8');
  const langganan = fs.readFileSync(REPO + '/api/langganan_inti.php', 'utf8');

  const nama = new Set();

  for (const cocok of endpoint.matchAll(/\b(rts_api|rts_lg)_[a-z0-9_]+/g)) nama.add(cocok[0]);

  const hilang = [...nama].filter(
    (n) => !bootstrap.includes('function ' + n + '(') && !kolom.includes('function ' + n + '(') && !langganan.includes('function ' + n + '('),
  );

  periksa('semua ' + nama.size + ' fungsi rts_api_*/rts_lg_* ada di berkas asli', hilang.length === 0, hilang.join(', '));
  periksa('api/program.php memuat gembok PRO (rts_lg_status)', endpoint.includes('rts_lg_status'));
  periksa('dua jenis program tertulis (INTRODEAL & BD)', endpoint.includes("'INTRODEAL'") && endpoint.includes("'BD'"));
  periksa('tabel BARU saja yang dipakai (rts_program_produk)', endpoint.includes('rts_program_produk'));
}

/* --------------------------------------------------------- 2. tanpa token */

console.log('\n[2] Tanpa token -> harus ditolak 401');
{
  const hasil = jalankan({ metode: 'GET', token: '', token_ada: false, user: userRtsGratis, get: { aksi: 'daftar' } });

  periksa('kode HTTP 401', hasil.kode === 401, 'kode=' + hasil.kode);
  periksa('success=false', !!hasil.balasan && hasil.balasan.success === false);
  periksa('pesan menyebut token', !!hasil.balasan && /token/i.test(hasil.balasan.message));
}

/* --------------------------------------------------- 3. akun GRATIS = kunci */

console.log('\n[3] Akun GRATIS -> harus ditolak 403 + perlu_pro');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsGratis,
    langganan: langgananGratis,
    get: { aksi: 'daftar' },
  });

  periksa('kode HTTP 403', hasil.kode === 403, 'kode=' + hasil.kode);
  periksa('perlu_pro = true', !!hasil.balasan && hasil.balasan.perlu_pro === true);
  periksa('keterangan langganan (harga 5000, durasi 30, trial 7)', !!hasil.balasan
    && !!hasil.balasan.langganan
    && hasil.balasan.langganan.harga === 5000
    && hasil.balasan.langganan.durasi_hari === 30
    && hasil.balasan.langganan.trial_hari === 7, JSON.stringify(hasil.balasan));
}

/* --------------------------------- 4. PRO, tabel belum ada -> dikirim SQL */

console.log('\n[4] Akun PRO, tabel belum ada -> daftar kosong + perintah SQL');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: false,
    get: { aksi: 'daftar' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('success=true', !!hasil.balasan && hasil.balasan.success === true);
  periksa('items kosong', !!hasil.balasan && Array.isArray(hasil.balasan.items) && hasil.balasan.items.length === 0);
  periksa('perlu_tabel = true', !!hasil.balasan && hasil.balasan.perlu_tabel === true);
  periksa('perintah SQL CREATE TABLE dikirim', !!hasil.balasan && /CREATE TABLE IF NOT EXISTS rts_program_produk/i.test(String(hasil.balasan.sql || '')));
  periksa('SQL menyimpan jenis, sku, barcode, nama', !!hasil.balasan
    && /jenis VARCHAR/i.test(String(hasil.balasan.sql))
    && /sku VARCHAR/i.test(String(hasil.balasan.sql))
    && /barcode_pack VARCHAR/i.test(hasil.balasan.sql)
    && /nama VARCHAR/i.test(hasil.balasan.sql));
}

/* ------------------------------------------- 5. PRO, tabel ada -> daftar */

console.log('\n[5] Akun PRO, tabel ada -> daftar produk program');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    get: { aksi: 'daftar' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('jumlah = 2', !!hasil.balasan && hasil.balasan.jumlah === 2, JSON.stringify(hasil.balasan));
  periksa('produk pertama INTRODEAL', !!hasil.balasan && hasil.balasan.items[0].jenis === 'INTRODEAL');
  periksa('produk kedua BD', !!hasil.balasan && hasil.balasan.items[1].jenis === 'BD');
  periksa('nama produk ikut dikirim', !!hasil.balasan && hasil.balasan.items[0].nama === 'Wismilak Inti Kretek');
  periksa('isi_per_pack berupa angka', !!hasil.balasan && hasil.balasan.items[0].isi_per_pack === 10);
  periksa('boleh_tulis = false untuk RTS', !!hasil.balasan && hasil.balasan.boleh_tulis === false);
}

/* ------------------------------------------------ 6. saring jenis = BD */

console.log('\n[6] Saring jenis=BD -> hanya produk BD');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    get: { aksi: 'daftar', jenis: 'BD' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('jumlah = 1', !!hasil.balasan && hasil.balasan.jumlah === 1, JSON.stringify(hasil.balasan));
  periksa('yang tersisa hanya BD', !!hasil.balasan && hasil.balasan.items[0].jenis === 'BD');
}

/* ------------------------------------------------- 7. RTS dilarang menulis */

console.log('\n[7] RTS akun PRO menyimpan ke server -> ditolak 403 (hanya pengelola)');
{
  const hasil = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    post: { aksi: 'simpan', jenis: 'INTRODEAL', nama: 'Produk Baru', sku: 'WI-999' },
  });

  periksa('kode HTTP 403', hasil.kode === 403, 'kode=' + hasil.kode);
  periksa('pesan menyebut ADMIN dan ASS', !!hasil.balasan && /ADMIN dan ASS/i.test(hasil.balasan.message));
}

/* ------------------------------------------------------ 8. ADMIN menyimpan */

console.log('\n[8] ADMIN menyimpan produk -> tersimpan');
{
  const hasil = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    post: {
      aksi: 'simpan',
      jenis: 'BD',
      nama: 'Wismilak Signature BD',
      sku: 'BD-900',
      barcode_pack: '8999000000001',
      merek: 'Wismilak',
      isi_per_pack: '20',
      periode: 'Okt 2026',
    },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('success=true', !!hasil.balasan && hasil.balasan.success === true);
  periksa('jenis BD', !!hasil.balasan && hasil.balasan.jenis === 'BD');
  periksa('sku tersimpan', !!hasil.balasan && hasil.balasan.sku === 'BD-900');
}

/* ---------------------------------------------- 9. ADMIN, tabel belum ada */

console.log('\n[9] ADMIN menyimpan saat tabel belum ada -> tabel dibuat otomatis');
{
  const hasil = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true, // tiruan: query CREATE berhasil, tabel menjadi ada
    program: [],
    post: { aksi: 'simpan', jenis: 'INTRODEAL', nama: 'Produk Pertama', sku: '' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa(
    'sku kosong diisi dari nama produk (huruf besar)',
    !!hasil.balasan && hasil.balasan.sku === 'PRODUK PERTAMA',
    JSON.stringify(hasil.balasan),
  );
}

/* ---------------------------------------------------------- 10. nama kosong */

console.log('\n[10] ADMIN menyimpan tanpa nama -> ditolak 400');
{
  const hasil = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    program: [],
    post: { aksi: 'simpan', jenis: 'INTRODEAL', nama: '   ' },
  });

  periksa('kode HTTP 400', hasil.kode === 400, 'kode=' + hasil.kode);
  periksa('pesan menyebut nama', !!hasil.balasan && /nama/i.test(hasil.balasan.message));
}

/* ----------------------------------------------------------------- 11. hapus */

console.log('\n[11] Hapus produk: RTS ditolak, ADMIN dijalankan');
{
  const rts = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    post: { aksi: 'hapus', jenis: 'BD', sku: 'BD-777' },
  });

  periksa('RTS ditolak 403', rts.kode === 403, 'kode=' + rts.kode);

  const admin = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    post: { aksi: 'hapus', jenis: 'BD', sku: 'BD-777' },
  });

  periksa('ADMIN dijalankan (200)', admin.kode === 200, 'kode=' + admin.kode);
  periksa('jenis & sku dikembalikan', !!admin.balasan && admin.balasan.jenis === 'BD' && admin.balasan.sku === 'BD-777');

  const kosong = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    post: { aksi: 'hapus', jenis: 'BD', sku: '' },
  });

  periksa('sku kosong ditolak 400', kosong.kode === 400, 'kode=' + kosong.kode);
}

/* -------------------------------------------------------------- 12. WSS */

console.log('\n[12] WSS (ada di setiap district) dapat membaca daftar program');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userWss,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    get: { aksi: 'daftar' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('WSS menerima 2 produk', !!hasil.balasan && hasil.balasan.jumlah === 2, JSON.stringify(hasil.balasan));
  periksa('WSS tidak boleh menulis (boleh_tulis=false)', !!hasil.balasan && hasil.balasan.boleh_tulis === false);
}

/* ------------------------------------------------------------ 13. periksa */

console.log('\n[13] Aksi periksa -> status tabel + perintah SQL');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    get: { aksi: 'periksa' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('tabel = true', !!hasil.balasan && hasil.balasan.tabel === true);
  periksa('nama tabel benar', !!hasil.balasan && hasil.balasan.nama_tabel === 'rts_program_produk');
  periksa('boleh_tulis = true untuk ADMIN', !!hasil.balasan && hasil.balasan.boleh_tulis === true);
  periksa('SQL ikut dikirim', !!hasil.balasan && String(hasil.balasan.sql).includes('rts_program_produk'));
}

/* ----------------------------------------------------------- 14. aksi salah */

console.log('\n[14] Perintah tidak dikenal -> ditolak 400');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    program: duaProduk,
    get: { aksi: 'apalah' },
  });

  periksa('kode HTTP 400', hasil.kode === 400, 'kode=' + hasil.kode);
  periksa('pesan menyebut perintah', !!hasil.balasan && /perintah/i.test(hasil.balasan.message));
}

/* ----------------------------------------------------------------- ringkas */

console.log('\n============================================================');
console.log('  HASIL: ' + lulus + ' LULUS / ' + gagal + ' GAGAL');
console.log('============================================================');

process.exit(gagal === 0 ? 0 : 1);
