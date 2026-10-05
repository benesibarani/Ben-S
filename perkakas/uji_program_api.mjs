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
    paket: '2+1',
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
    paket: '',
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

const duaPaket = [
  {
    id: 1,
    jenis: 'INTRODEAL',
    nama: '2+1',
    keterangan: 'Beli 2 gratis 1',
    bawaan: 1,
    diubah_oleh: 'sistem',
    diubah_pada: '2026-10-05 08:00:00',
  },
  {
    id: 2,
    jenis: 'INTRODEAL',
    nama: '1+1',
    keterangan: 'Beli 1 gratis 1',
    bawaan: 1,
    diubah_oleh: 'sistem',
    diubah_pada: '2026-10-05 08:00:00',
  },
  {
    id: 3,
    jenis: 'INTRODEAL',
    nama: '3+1',
    keterangan: 'Paket buatan Sales',
    bawaan: 0,
    diubah_oleh: 'admin_uji',
    diubah_pada: '2026-10-05 10:00:00',
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
  periksa('tabel paket Introdeal ada (rts_program_paket)', endpoint.includes('rts_program_paket'));
  periksa('paket bawaan 2+1 dan 1+1 disiapkan server', endpoint.includes("'2+1'") && endpoint.includes("'1+1'"));
  periksa('INTRODEAL = program paket, BD tanpa paket', /INTRODEAL\s*=\s*Introductory Deal/i.test(endpoint));
  periksa('nama program bebas (fungsi rts_pr_program)', endpoint.includes('function rts_pr_program('));
  periksa('kolom jenis catatan program 40 huruf', /jenis VARCHAR\(40\)/.test(endpoint));

  const pindahkanJenis = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: {
      aksi: 'input_simpan',
      jenis: 'program gawih',
      id_customer: 'C-1',
      nama_toko: 'Toko Gawih',
      catatan: 'Ikut program baru',
    },
  });

  periksa('program buatan Sales (nama bebas) diterima server', pindahkanJenis.kode === 200,
    JSON.stringify(pindahkanJenis.balasan));
  periksa('nama program dirapikan huruf besar', !!pindahkanJenis.balasan
    && pindahkanJenis.balasan.jenis === 'PROGRAM GAWIH');
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
    tabel_paket: true,
    tabel_input: true,
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
  periksa('produk INTRODEAL membawa paket 2+1', !!hasil.balasan && hasil.balasan.items[0].paket === '2+1');
  periksa('produk BD paketnya kosong', !!hasil.balasan && hasil.balasan.items[1].paket === '');
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
  periksa('BD tidak memakai paket (paket dikosongkan)', !!hasil.balasan && hasil.balasan.paket === '');

  const paket = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: {
      aksi: 'simpan',
      jenis: 'INTRODEAL',
      paket: ' 2+1 ',
      nama: 'Wismilak Inti Kretek',
      sku: 'WI-001',
    },
  });

  periksa('INTRODEAL menyimpan paket (huruf besar)', !!paket.balasan && paket.balasan.paket === '2+1', JSON.stringify(paket.balasan));
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
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
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    get: { aksi: 'periksa' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('tabel = true', !!hasil.balasan && hasil.balasan.tabel === true);
  periksa('nama tabel benar', !!hasil.balasan && hasil.balasan.nama_tabel === 'rts_program_produk');
  periksa('boleh_tulis = true untuk ADMIN', !!hasil.balasan && hasil.balasan.boleh_tulis === true);
  periksa('SQL ikut dikirim', !!hasil.balasan && String(hasil.balasan.sql).includes('rts_program_produk'));
  periksa('status tabel paket ikut diperiksa', !!hasil.balasan && hasil.balasan.tabel_paket === true);
  periksa('status tabel catatan program ikut diperiksa', !!hasil.balasan && hasil.balasan.tabel_input === true);
  periksa('SQL tabel catatan program ikut dikirim', !!hasil.balasan
    && /CREATE TABLE IF NOT EXISTS rts_program_input/i.test(String(hasil.balasan.sql_input)));
  periksa('SQL tabel paket ikut dikirim', !!hasil.balasan && String(hasil.balasan.sql_paket).includes('rts_program_paket'));
  periksa('SQL paket memuat kolom bawaan', !!hasil.balasan && /bawaan TINYINT/i.test(String(hasil.balasan.sql_paket)));
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
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    get: { aksi: 'apalah' },
  });

  periksa('kode HTTP 400', hasil.kode === 400, 'kode=' + hasil.kode);
  periksa('pesan menyebut perintah', !!hasil.balasan && /perintah/i.test(hasil.balasan.message));
}

/* --------------------------------------- 15. daftar paket Introdeal (2+1, 1+1) */

console.log('\n[15] Daftar PAKET Introdeal -> 2+1 dan 1+1 bawaan ikut terkirim');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    get: { aksi: 'paket_daftar', jenis: 'INTRODEAL' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('jumlah = 3', !!hasil.balasan && hasil.balasan.jumlah === 3, JSON.stringify(hasil.balasan));
  periksa('paket bawaan lebih dahulu (2+1)', !!hasil.balasan && hasil.balasan.items[0].nama === '2+1');
  periksa('paket bawaan ditandai bawaan=true', !!hasil.balasan && hasil.balasan.items[0].bawaan === true);
  periksa('paket buatan Sales ikut terkirim (3+1)', !!hasil.balasan
    && hasil.balasan.items.some((p) => p.nama === '3+1' && p.bawaan === false));
  periksa('tidak perlu membuat tabel', !!hasil.balasan && hasil.balasan.perlu_tabel === false);
}

/* ------------------------------------------------- 16. BD tidak punya paket */

console.log('\n[16] Sub-menu BD -> daftar paket KOSONG (New Brand Distribution)');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    get: { aksi: 'paket_daftar', jenis: 'BD' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('jumlah = 0', !!hasil.balasan && hasil.balasan.jumlah === 0, JSON.stringify(hasil.balasan));
  periksa('pesan menjelaskan produk BD sudah ada di outlet', !!hasil.balasan
    && /sudah ada di outlet/i.test(String(hasil.balasan.message)));
}

/* ---------------------------------- 17. Sales menambah paket / hapus paket */

console.log('\n[17] Paket: Sales ditolak, ADMIN boleh menambah & menghapus paket buatan');
{
  const sales = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_simpan', nama: '4+2', keterangan: 'Beli 4 gratis 2' },
  });

  periksa('Sales ditolak 403', sales.kode === 403, 'kode=' + sales.kode);

  const admin = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_simpan', nama: ' 4+2 ', keterangan: 'Beli 4 gratis 2' },
  });

  periksa('ADMIN menyimpan paket -> 200', admin.kode === 200, 'kode=' + admin.kode);
  periksa('nama paket dirapikan (4+2)', !!admin.balasan && admin.balasan.nama === '4+2');

  const kosong = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_simpan', nama: '   ' },
  });

  periksa('nama paket kosong ditolak 400', kosong.kode === 400, 'kode=' + kosong.kode);
  periksa('pesan menyebut nama paket', !!kosong.balasan && /nama paket/i.test(String(kosong.balasan.message)));

  const salesHapus = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_hapus', nama: '3+1' },
  });

  periksa('Sales ditolak menghapus paket (403)', salesHapus.kode === 403, 'kode=' + salesHapus.kode);

  const adminHapus = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_hapus', nama: '3+1' },
  });

  periksa('ADMIN menghapus paket buatan Sales -> 200', adminHapus.kode === 200, 'kode=' + adminHapus.kode);
  periksa('pesan menyebut paket buatan Sales', !!adminHapus.balasan
    && /paket buatan sales/i.test(String(adminHapus.balasan.message)));

  const hapusBawaan = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    tabel_paket: true,
    program: duaProduk,
    paket: duaPaket,
    post: { aksi: 'paket_hapus', nama: '2+1' },
  });

  periksa('paket bawaan tidak pernah dihapus (perintah hanya untuk bawaan=0)', hapusBawaan.kode === 200);
}

/* -------------------------------- 18. paket saat tabel paket belum dibuat */

console.log('\n[18] Tabel paket belum ada -> dikirim perintah SQL paket');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: false,
    program: duaProduk,
    paket: [],
    get: { aksi: 'paket_daftar', jenis: 'INTRODEAL' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('perlu_tabel = true', !!hasil.balasan && hasil.balasan.perlu_tabel === true);
  periksa('items kosong', !!hasil.balasan && Array.isArray(hasil.balasan.items) && hasil.balasan.items.length === 0);
  periksa('perintah SQL paket dikirim', !!hasil.balasan
    && /CREATE TABLE IF NOT EXISTS rts_program_paket/i.test(String(hasil.balasan.sql_paket || '')));
}

/* ------------------------------------ 19. catatan program dikirim dari HP */

console.log('\n[19] Catatan program dari HP -> INTRODEAL wajib paket, BD tanpa paket');
{
  const introdeal = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: {
      aksi: 'input_simpan',
      jenis: 'INTRODEAL',
      paket: '2+1',
      paket_keterangan: 'Beli 2 gratis 1',
      id_customer: 'C-100',
      nama_toko: 'Toko Uji',
      produk_id: '1',
      nama_produk: 'Wismilak Inti Kretek',
      sku: 'WI-001',
      jumlah: '3',
      satuan: 'PACK',
      tanggal: '2026-10-05',
      id_hp: '12',
    },
  });

  periksa('kode HTTP 200', introdeal.kode === 200, 'kode=' + introdeal.kode);
  periksa('jenis INTRODEAL & paket 2+1', !!introdeal.balasan
    && introdeal.balasan.jenis === 'INTRODEAL' && introdeal.balasan.paket === '2+1');
  periksa('jumlah 3 diterima', !!introdeal.balasan && introdeal.balasan.jumlah === 3);
  periksa('id HP ikut dikembalikan (anti ganda)', !!introdeal.balasan && introdeal.balasan.id_hp === '12');

  const tanpaPaket = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: { aksi: 'input_simpan', jenis: 'INTRODEAL', id_customer: 'C-100', jumlah: '1' },
  });

  periksa('INTRODEAL tanpa paket ditolak 400', tanpaPaket.kode === 400, 'kode=' + tanpaPaket.kode);
  periksa('pesan menyebut paket Introdeal', !!tanpaPaket.balasan
    && /paket introdeal/i.test(String(tanpaPaket.balasan.message)));

  const bd = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: {
      aksi: 'input_simpan',
      jenis: 'BD',
      paket: '2+1',
      id_customer: 'C-200',
      nama_toko: 'Toko BD',
      nama_produk: 'Wismilak Diplomat BD',
      jumlah: '2',
    },
  });

  periksa('BD lolos dan paketnya dikosongkan', !!bd.balasan
    && bd.balasan.paket === '' && bd.balasan.jenis === 'BD');

  const jumlahNol = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: { aksi: 'input_simpan', jenis: 'BD', id_customer: 'C-200', jumlah: '0' },
  });

  periksa('jumlah 0 tanpa produk/catatan ditolak 400', jumlahNol.kode === 400,
    'kode=' + jumlahNol.kode);

  const catatanSaja = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: {
      aksi: 'input_simpan',
      jenis: 'PROGRAM GAWIH',
      id_customer: 'C-300',
      nama_toko: 'Toko Gawih',
      catatan: 'Mau ikut program, menunggu barang',
    },
  });

  periksa('catatan saja tanpa produk diterima (200)', catatanSaja.kode === 200,
    JSON.stringify(catatanSaja.balasan));
  periksa('satuan dirapikan menjadi PACK/BATANG/BALL', !!catatanSaja.balasan
    && ['PACK', 'BATANG', 'BALL'].includes(String(catatanSaja.balasan.satuan ?? '')));

  const tanpaToko = jalankan({
    metode: 'POST',
    token,
    token_ada: true,
    user: userRtsPro,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    post: { aksi: 'input_simpan', jenis: 'BD', jumlah: '1' },
  });

  periksa('tanpa toko ditolak 400', tanpaToko.kode === 400, 'kode=' + tanpaToko.kode);
}

/* ---------------------------------------------- 20. daftar catatan di server */

console.log('\n[20] Daftar catatan program di server + tabel belum ada');
{
  const catatan = [{
    id: 1,
    jenis: 'INTRODEAL',
    paket: '2+1',
    paket_keterangan: 'Beli 2 gratis 1',
    id_customer: 'C-100',
    nama_toko: 'Toko Uji',
    produk_id: 1,
    nama_produk: 'Wismilak Inti Kretek',
    sku: 'WI-001',
    jumlah: 3,
    satuan: 'PACK',
    tanggal: '2026-10-05',
    catatan: '',
    id_sales: 'sales_pro',
    nama_sales: 'Sales PRO',
    diubah_pada: '2026-10-05 11:00:00',
  }];

  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: catatan,
    get: { aksi: 'input_daftar' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('jumlah = 1', !!hasil.balasan && hasil.balasan.jumlah === 1, JSON.stringify(hasil.balasan));
  periksa('nama toko & produk ikut terkirim', !!hasil.balasan
    && hasil.balasan.items[0].nama_toko === 'Toko Uji'
    && hasil.balasan.items[0].nama_produk === 'Wismilak Inti Kretek');
  periksa('paket ikut terkirim', !!hasil.balasan && hasil.balasan.items[0].paket === '2+1');

  const bebas = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: true,
    program: duaProduk,
    paket: duaPaket,
    input: catatan,
    get: { aksi: 'input_daftar', jenis: 'PROGRAM GAWIH' },
  });

  periksa('saring nama program bebas diterima (200)', bebas.kode === 200, 'kode=' + bebas.kode);
  periksa('nama program ikut dikembalikan', !!bebas.balasan
    && String(bebas.balasan.jenis) === 'PROGRAM GAWIH');

  const belum = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userAdmin,
    langganan: langgananPro,
    tabel_program: true,
    tabel_paket: true,
    tabel_input: false,
    program: duaProduk,
    paket: duaPaket,
    input: [],
    get: { aksi: 'input_daftar' },
  });

  periksa('tabel belum ada -> perlu_tabel true', !!belum.balasan && belum.balasan.perlu_tabel === true);
  periksa('SQL tabel catatan program dikirim', !!belum.balasan
    && /CREATE TABLE IF NOT EXISTS rts_program_input/i.test(String(belum.balasan.sql_input || '')));
}

/* ----------------------------------------------------------------- ringkas */

console.log('\n============================================================');
console.log('  HASIL: ' + lulus + ' LULUS / ' + gagal + ' GAGAL');
console.log('============================================================');

process.exit(gagal === 0 ? 0 : 1);
