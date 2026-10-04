/**
 * ALAT PENGUJIAN DI KOMPUTER (bukan untuk hosting).
 *
 * Menjalankan berkas PHP memakai PHP 8.2 ASLI (php-wasm) langsung dari
 * sandbox/komputer, TANPA server web. Dipakai untuk menguji berkas di folder
 * api/ dan halaman-halaman PHP sebelum diunggah ke hosting.
 *
 * Pemakaian:
 *     node perkakas/run_php.mjs <folder kerja> <skrip.php>
 *
 * Contoh:
 *     node perkakas/run_php.mjs /home/user/uji tes_cctv_api.php
 *
 * Keterangan:
 *   - Seluruh berkas komputer dipasang (mount) apa adanya, jadi skrip PHP
 *     dapat memakai require/include dengan alamat yang sama seperti aslinya.
 *   - Keluaran (echo) skrip dicetak ke layar, termasuk kode keluar PHP.
 *   - Saat pertama dijalankan, paket @php-wasm/node dipasang ke folder
 *     sementara /tmp/perkakas_php (perlu internet).
 */
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const DIR_NPM = '/tmp/perkakas_php';

function siapkanPaket() {
  const sasaran = DIR_NPM + '/node_modules/@php-wasm/universal';

  if (fs.existsSync(sasaran)) return;

  fs.mkdirSync(DIR_NPM, { recursive: true });

  if (!fs.existsSync(DIR_NPM + '/package.json')) {
    fs.writeFileSync(DIR_NPM + '/package.json', JSON.stringify({ name: 'perkakas-php', type: 'module' }));
  }

  execSync('npm install --no-audit --no-fund @php-wasm/node @php-wasm/universal', {
    cwd: DIR_NPM,
    stdio: 'ignore',
  });
}

const folder = process.argv[2];
const skrip = process.argv[3];

if (!folder || !skrip) {
  console.error('Pemakaian: node perkakas/run_php.mjs <folder kerja> <skrip.php>');
  process.exit(2);
}

const alamatSkrip = path.resolve(folder, skrip);

if (!fs.existsSync(alamatSkrip)) {
  console.error('[X] Berkas tidak ditemukan: ' + alamatSkrip);
  process.exit(2);
}

siapkanPaket();

const universal = await import(DIR_NPM + '/node_modules/@php-wasm/universal/index.js');
const node = await import(DIR_NPM + '/node_modules/@php-wasm/node/index.js');

const { PHP } = universal;
const { loadNodeRuntime } = node;

console.log('[i] Menyiapkan PHP 8.2 (php-wasm)...');

const runtime = await loadNodeRuntime('8.2', { emscriptenOptions: { processId: 1 } });
const php = new PHP(runtime);

// Semua folder komputer dipasang ke dalam PHP, supaya require/include dengan
// alamat asli (__DIR__) langsung bekerja.
if (typeof node.useHostFilesystem === 'function') {
  node.useHostFilesystem(php);
} else {
  for (const nama of fs.readdirSync('/')) {
    if (nama === 'dev' || nama === 'proc') continue;

    const alamat = '/' + nama;

    try {
      if (!fs.statSync(alamat).isDirectory()) continue;
    } catch {
      continue;
    }

    if (!php.fileExists(alamat)) php.mkdirTree(alamat);

    if (typeof node.createNodeFsMountHandler === 'function') {
      php.mount(alamat, node.createNodeFsMountHandler(alamat));
    }
  }

  php.chdir(process.cwd());
}

const kode =
  '<?php\n' +
  '$argv = array(' + JSON.stringify(path.basename(alamatSkrip)) + ');\n' +
  '$_SERVER["SCRIPT_FILENAME"] = ' + JSON.stringify(alamatSkrip) + ";\n" +
  '$_SERVER["SCRIPT_NAME"] = ' + JSON.stringify('/' + path.basename(alamatSkrip)) + ";\n" +
  '$_SERVER["DOCUMENT_ROOT"] = ' + JSON.stringify(folder) + ";\n" +
  '$_SERVER["REQUEST_METHOD"] = $_SERVER["REQUEST_METHOD"] ?? "GET";\n' +
  'require ' + JSON.stringify(alamatSkrip) + ";\n";

const hasil = await php.run({ code: kode });

if (hasil.errors) {
  console.error('--- galat PHP ---');
  console.error(String(hasil.errors).trim());
}

process.stdout.write(hasil.text || '');

if (!String(hasil.text || '').endsWith('\n')) process.stdout.write('\n');

process.exit(hasil.exitCode === 0 ? 0 : 1);
