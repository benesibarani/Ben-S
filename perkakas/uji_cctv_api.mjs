/**
 * ============================================================================
 *  ALAT PENGUJIAN DI KOMPUTER - PENGUJI api/cctv.php (bukan untuk hosting)
 *  Berkas : perkakas/uji_cctv_api.mjs
 *
 *  Cara pakai:
 *      node perkakas/uji_cctv_api.mjs
 *
 *  Yang dikerjakan:
 *    1. Menyiapkan folder kerja /home/user/uji (perkakas uji) berisi salinan
 *       api/cctv.php + api/langganan_inti.php + bootstrap tiruan + data kamera.
 *    2. Menjalankan 8 keadaan pengujian memakai PHP 8.2 asli (php-wasm).
 *    3. Memeriksa kode HTTP, isi balasan JSON, dan memastikan berkas data
 *       TIDAK berubah saat hanya membaca daftar.
 *
 *  Catatan: server ATCS Dishub TIDAK dapat dihubungi dari dalam kotak uji ini,
 *  jadi keadaan "segarkan" memang menghasilkan pesan "belum dapat dihubungi" -
 *  itulah yang diperiksa (aplikasi tetap memakai daftar yang tersimpan).
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
  fs.mkdirSync(UJI + '/data', { recursive: true });

  fs.copyFileSync(REPO + '/api/cctv.php', UJI + '/api/cctv.php');
  fs.copyFileSync(REPO + '/api/langganan_inti.php', UJI + '/api/langganan_inti.php');
  fs.copyFileSync(REPO + '/api/kolom.php', UJI + '/api/kolom.php');
  fs.copyFileSync(REPO + '/perkakas/uji_api_bootstrap_tiruan.php', UJI + '/api/api_bootstrap.php');
  fs.copyFileSync(REPO + '/perkakas/uji_mysqli_tiruan.php', UJI + '/mysqli_tiruan.php');
  fs.copyFileSync(REPO + '/perkakas/uji_tes_cctv_api.php', UJI + '/tes_cctv_api.php');
  fs.copyFileSync(REPO + '/cctv_medan.json', UJI + '/data/cctv_medan.json');
  fs.writeFileSync(UJI + '/config.php', "<?php\n// Tiruan: database uji diambil dari RtsUjiDb.\n");
}

/* --------------------------------------------------------------- menjalankan */

function jalankan(keadaan) {
  fs.writeFileSync(UJI + '/keadaan.json', JSON.stringify(keadaan, null, 2));

  let keluaran = '';

  try {
    keluaran = execFileSync('node', [REPO + '/perkakas/run_php.mjs', UJI, 'tes_cctv_api.php'], {
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
    balasan: json ? amanParse(json[1]) : null,
  };
}

function amanParse(teks) {
  try {
    return JSON.parse(teks);
  } catch {
    return null;
  }
}

/* ------------------------------------------------------------- keadaan uji */

const token = 'uji_token_palsu_yang_panjang_sekali_1234567890';

const userPro = {
  id: 7,
  username: 'sales_pro',
  nama_lengkap: 'Sales PRO',
  role: 'RTS',
  salesman: 'UJI',
  sales_district: 'MEDAN KOTA',
  status_aktif: 'Aktif',
  akun_pro: 1,
};

const userGratis = { ...userPro, id: 8, username: 'sales_gratis', role: 'RTS', akun_pro: 0 };

const langgananPro = {
  id: 7,
  username: 'sales_pro',
  akun_pro: 1,
  pro_mulai: new Date(Date.now() - 10 * 86400000).toISOString().slice(0, 10),
  pro_selesai: new Date(Date.now() + 20 * 86400000).toISOString().slice(0, 10),
};

const langgananGratis = { id: 8, username: 'sales_gratis', akun_pro: 0, pro_selesai: '', trial_selesai: '' };

console.log('[i] Menyiapkan folder uji ' + UJI + ' ...');
siapkan();

/* ------------------------------------------------------- 1. kesepakatan API */

console.log('\n[1] Kesepakatan fungsi: rts_api_* yang dipakai cctv.php ada di bootstrap asli');
{
  const endpoint = fs.readFileSync(REPO + '/api/cctv.php', 'utf8');
  const bootstrap = fs.readFileSync(REPO + '/api/api_bootstrap.php', 'utf8');
  const kolom = fs.readFileSync(REPO + '/api/kolom.php', 'utf8');
  const langganan = fs.readFileSync(REPO + '/api/langganan_inti.php', 'utf8');

  const nama = new Set();

  for (const cocok of endpoint.matchAll(/\b(rts_api|rts_lg)_[a-z0-9_]+/g)) nama.add(cocok[0]);

  const hilang = [...nama].filter(
    (n) => !bootstrap.includes('function ' + n + '(') && !kolom.includes('function ' + n + '(') && !langganan.includes('function ' + n + '('),
  );

  periksa('semua ' + nama.size + ' fungsi rts_api_*/rts_lg_* ada di berkas asli', hilang.length === 0, hilang.join(', '));
  periksa('api/cctv.php memuat gembok PRO (rts_lg_status)', endpoint.includes('rts_lg_status'));
  periksa('api/cctv.php menyebut periksa_cctv.php pada pesan bantuan', endpoint.includes('periksa_cctv.php'));
}

/* --------------------------------------------------------- 2. tanpa token */

console.log('\n[2] Tanpa token -> harus ditolak 401');
{
  const hasil = jalankan({ metode: 'GET', token: '', token_ada: false, user: userGratis, get: { aksi: 'daftar' } });

  periksa('kode HTTP 401', hasil.kode === 401, 'kode=' + hasil.kode);
  periksa('success=false', hasil.balasan && hasil.balasan.success === false);
  periksa('pesan menyebut token', !!hasil.balasan && /token/i.test(hasil.balasan.message));
}

/* --------------------------------------------------- 3. akun GRATIS = kunci */

console.log('\n[3] Akun GRATIS -> harus ditolak 403 + perlu_pro');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userGratis,
    langganan: langgananGratis,
    get: { aksi: 'daftar' },
  });

  periksa('kode HTTP 403', hasil.kode === 403, 'kode=' + hasil.kode);
  periksa('success=false', hasil.balasan && hasil.balasan.success === false);
  periksa('perlu_pro = true (di bagian paling atas balasan, sama seperti api/kasir.php)', !!hasil.balasan && hasil.balasan.perlu_pro === true, JSON.stringify(hasil.balasan));
  periksa('pesan menyebut AKUN PRO', !!hasil.balasan && /AKUN PRO/i.test(hasil.balasan.message));
  periksa(
    'keterangan langganan ikut dikirim (harga 5000, durasi 30, trial 7)',
    !!hasil.balasan &&
      hasil.balasan.langganan &&
      hasil.balasan.langganan.harga === 5000 &&
      hasil.balasan.langganan.durasi_hari === 30 &&
      hasil.balasan.langganan.trial_hari === 7,
    JSON.stringify(hasil.balasan && hasil.balasan.langganan),
  );
  periksa('tidak ada daftar kamera yang bocor', !hasil.balasan || !JSON.stringify(hasil.balasan).includes('stream.m3u8'));
}

/* -------------------------------------------------------- 4. akun PRO biasa */

console.log('\n[4] Akun PRO (masa berjalan) -> 111 kamera');
{
  const sebelum = fs.readFileSync(UJI + '/data/cctv_medan.json');
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'daftar' },
  });
  const sesudah = fs.readFileSync(UJI + '/data/cctv_medan.json');

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('success=true', !!hasil.balasan && hasil.balasan.success === true);
  periksa('data.jumlah = 111', !!hasil.balasan && hasil.balasan.data && hasil.balasan.data.jumlah === 111, JSON.stringify(hasil.balasan && hasil.balasan.data && hasil.balasan.data.jumlah));
  periksa('data.akun_pro = 1', !!(hasil.balasan && hasil.balasan.data) && hasil.balasan.data.akun_pro === 1);

  const kamera = (hasil.balasan && hasil.balasan.data && hasil.balasan.data.kamera) || [];
  periksa('larik kamera berisi 111 butir', Array.isArray(kamera) && kamera.length === 111, 'jumlah=' + kamera.length);

  const polaBenar = kamera.every(
    (k) => typeof k.kode === 'string' && k.kode.length > 3 && typeof k.nama === 'string' && k.nama.length > 0 && /^https:\/\/atcsdishub\.medan\.go\.id\/stream\/[^/]+\/stream\.m3u8$/.test(k.url),
  );
  periksa('setiap kamera punya kode, nama, dan tautan HLS berpola benar', polaBenar);

  const kode = kamera.map((k) => k.kode);
  periksa('tidak ada kode kamera kembar', new Set(kode).size === kode.length);

  const urut = JSON.stringify(kamera.map((k) => Number(k.nomor)));
  const urutBenar = kamera.every((k, i) => i === 0 || Number(kamera[i - 1].nomor) <= Number(k.nomor));
  periksa('daftar terurut menurut nomor kamera', urutBenar, urut.slice(0, 60));

  periksa('koordinat wajar (contoh kamera pertama)', kamera[0] && kamera[0].lat > 2 && kamera[0].lat < 5 && kamera[0].lon > 97 && kamera[0].lon < 99);

  periksa('berkas data TIDAK berubah saat hanya membaca daftar', Buffer.compare(sebelum, sesudah) === 0);
}

/* ------------------------------------------------------------- 5. ADMIN ASS */

console.log('\n[5] ADMIN dan ASS (pengelola) tetap boleh membuka tanpa langganan');
{
  for (const role of ['ADMIN', 'ASS']) {
    const hasil = jalankan({
      metode: 'GET',
      token,
      token_ada: true,
      user: { ...userGratis, role },
      langganan: { ...langgananGratis, role },
      get: { aksi: 'daftar' },
    });

    periksa('role ' + role + ' -> kode 200', hasil.kode === 200, 'kode=' + hasil.kode);
    periksa('role ' + role + ' -> 111 kamera', !!(hasil.balasan && hasil.balasan.data) && hasil.balasan.data.jumlah === 111);
    periksa('role ' + role + ' -> akun_pro 0 (tanpa langganan)', !!(hasil.balasan && hasil.balasan.data) && hasil.balasan.data.akun_pro === 0);
  }
}

/* ---------------------------------------------------------- 6. aksi = uji */

console.log('\n[6] aksi=uji&jumlah=5 -> uji 5 tautan kamera');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'uji', jumlah: '5' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('data.jumlah = 5', !!hasil.balasan && hasil.balasan.data && hasil.balasan.data.jumlah === 5);
  periksa('ada data.hidup (angka)', !!hasil.balasan && typeof hasil.balasan.data.hidup === 'number');
  periksa('pesan menyebut "kamera hidup"', !!hasil.balasan && /kamera hidup/i.test(hasil.balasan.message), hasil.balasan && hasil.balasan.message);

  const kamera = (hasil.balasan && hasil.balasan.data && hasil.balasan.data.kamera) || [];
  periksa(
    'setiap hasil uji punya kode, hidup (bool), kode_http, catatan',
    kamera.length === 5 && kamera.every((k) => typeof k.kode === 'string' && typeof k.hidup === 'boolean' && typeof k.kode_http === 'number' && typeof k.catatan === 'string'),
  );
  periksa(
    'di kotak uji ini ATCS tidak dapat dihubungi -> kamera terbaca tidak hidup',
    kamera.every((k) => k.hidup === false),
    JSON.stringify(kamera.map((k) => [k.kode, k.kode_http])),
  );
}

/* --------------------------------------------------- 7. aksi=uji kode pilih */

console.log('\n[7] aksi=uji&kode=... -> hanya kamera yang diminta');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'uji', kode: 'L1RADENSALEHBALAIKOTA' },
  });

  const kamera = (hasil.balasan && hasil.balasan.data && hasil.balasan.data.kamera) || [];
  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('tepat 1 kamera diperiksa', kamera.length === 1, 'jumlah=' + kamera.length);
  periksa('kode kamera sesuai permintaan', kamera[0] && kamera[0].kode === 'L1RADENSALEHBALAIKOTA', JSON.stringify(kamera[0] || {}));

  const hasilKosong = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'uji', kode: 'KODE_YANG_TIDAK_ADA' },
  });

  periksa('kode tak dikenal -> 200 dengan 0 kamera', hasilKosong.kode === 200 && hasilKosong.balasan.data.jumlah === 0);
}

/* ------------------------------------------------- 8. segarkan tanpa ATCS */

console.log('\n[8] aksi=segarkan saat ATCS tidak dapat dihubungi -> daftar lama tetap dipakai');
{
  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'segarkan' },
  });

  periksa('kode HTTP 200', hasil.kode === 200, 'kode=' + hasil.kode);
  periksa('success=true (tidak membuat aplikasi eror)', !!hasil.balasan && hasil.balasan.success === true);
  periksa('data.jumlah tetap 111', !!hasil.balasan && hasil.balasan.data && hasil.balasan.data.jumlah === 111, JSON.stringify(hasil.balasan && hasil.balasan.data && hasil.balasan.data.jumlah));
  periksa('data.dari_situs = 0', !!hasil.balasan && hasil.balasan.data.dari_situs === 0);
  periksa(
    'pesan menjelaskan ATCS belum dapat dihubungi',
    !!hasil.balasan && /ATCS/i.test(hasil.balasan.message),
    hasil.balasan && hasil.balasan.message,
  );
}

/* -------------------------------------------- 9. berkas data belum ada */

console.log('\n[9] Berkas data belum ada + ATCS tidak dapat dihubungi -> pesan bantuan jelas');
{
  const cadangan = fs.readFileSync(UJI + '/data/cctv_medan.json');
  fs.rmSync(UJI + '/data/cctv_medan.json');

  const hasil = jalankan({
    metode: 'GET',
    token,
    token_ada: true,
    user: userPro,
    langganan: langgananPro,
    get: { aksi: 'daftar' },
  });

  fs.writeFileSync(UJI + '/data/cctv_medan.json', cadangan);

  periksa('kode HTTP 503', hasil.kode === 503, 'kode=' + hasil.kode);
  periksa('success=false', !!hasil.balasan && hasil.balasan.success === false);
  periksa('perlu_berkas = true', !!hasil.balasan && hasil.balasan.perlu_berkas === true, JSON.stringify(hasil.balasan));
  periksa('pesan menunjuk periksa_cctv.php?ambil=1', !!hasil.balasan && hasil.balasan.message.includes('periksa_cctv.php?ambil=1'));
}

/* --------------------------------------------------------------- ringkasan */

console.log('\n============================================');
console.log('HASIL: ' + lulus + ' LULUS / ' + gagal + ' GAGAL');
console.log('============================================');

process.exit(gagal ? 1 : 0);
