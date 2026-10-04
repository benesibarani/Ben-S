/**
 * ALAT PENGUJIAN DI KOMPUTER (bukan untuk hosting).
 *
 * Pemeriksa sintaks PHP memakai PHP 8.2 ASLI (php-wasm) - hasilnya sama
 * seperti perintah `php -l`.
 *
 * Pemakaian:
 *     node perkakas/lint_php.mjs berkas.php [berkas2.php ...]
 *
 * Catatan: saat pertama dijalankan, alat ini memasang paket @php-wasm/node
 * ke folder sementara /tmp/perkakas_php (perlu internet).
 */
import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

const DIR_NPM = '/tmp/perkakas_php';

function siapkan() {
  const sasaran = DIR_NPM + '/node_modules/@php-wasm/universal';

  if (fs.existsSync(sasaran)) {
    return;
  }

  fs.mkdirSync(DIR_NPM, { recursive: true });

  if (!fs.existsSync(DIR_NPM + '/package.json')) {
    fs.writeFileSync(DIR_NPM + '/package.json', JSON.stringify({ name: 'perkakas-php', type: 'module' }));
  }

  execSync('npm install --no-audit --no-fund @php-wasm/node @php-wasm/universal', {
    cwd: DIR_NPM,
    stdio: 'ignore',
  });
}

siapkan();

const { PHP } = await import(DIR_NPM + '/node_modules/@php-wasm/universal/index.js');
const { loadNodeRuntime } = await import(DIR_NPM + '/node_modules/@php-wasm/node/index.js');

const runtime = await loadNodeRuntime('8.2', { emscriptenOptions: { processId: 1 } });
const php = new PHP(runtime);

let gagal = 0;

for (const berkas of process.argv.slice(2)) {
  const isi = fs.readFileSync(berkas);
  const b64 = isi.toString('base64');
  const php_kode = '<?php\n$isi = base64_decode(' + JSON.stringify(b64) + ');\n'
    + 'try {\n'
    + '    token_get_all($isi, TOKEN_PARSE);\n'
    + '    echo "[V]";\n'
    + '} catch (Throwable $e) {\n'
    + '    echo "[X] " . $e->getMessage() . " (baris " . $e->getLine() . ")";\n'
    + '}\n';

  const out = await php.run({ code: php_kode });
  const pesan = (out.text || '').trim();

  if (pesan.startsWith('[V]')) {
    console.log('[V] ' + path.basename(berkas) + ' : sintaks PHP sah (' + isi.length + ' B)');
  } else {
    gagal++;
    console.log('[X] ' + path.basename(berkas) + ' : ' + pesan.replace('[X] ', ''));
  }
}

process.exit(gagal ? 1 : 0);
