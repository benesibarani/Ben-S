/**
 * ALAT PENGUJIAN DI KOMPUTER (bukan untuk hosting).
 *
 * Memeriksa nama-nama (simbol) yang dipakai sebuah berkas Dart: setiap nama
 * yang berawalan "rts" atau "Rts" harus benar-benar ADA di salah satu berkas
 * yang diimpor (atau di berkas itu sendiri). Cara ini menangkap salah tulis
 * nama fungsi/kelas sebelum dibangun dengan Flutter.
 *
 * Pemakaian:
 *     node perkakas/periksa_dart_nama.mjs lib/cctv.dart lib/peta.dart lib/kasir.dart
 *
 * Argumen pertama = berkas yang diperiksa; sisanya = berkas tempat mencari
 * definisinya.
 */
import fs from 'node:fs';
import path from 'node:path';

const berkasPeriksa = process.argv[2];
const berkasSumber = process.argv.slice(3);

if (!berkasPeriksa) {
  console.error('Pemakaian: node periksa_dart_nama.mjs <berkas.dart> [berkas sumber ...]');
  process.exit(2);
}

/** Membuang komentar dan isi tanda kutip supaya isi teks tidak ikut diperiksa. */
function buangTeks(teks) {
  return teks
    .replace(/'''[\s\S]*?'''/g, ' ')
    .replace(/"""[\s\S]*?"""/g, ' ')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/\/\/[^\n]*/g, ' ')
    .replace(/'(\\.|[^'\\\n])*'/g, ' ')
    .replace(/"(\\.|[^"\\\n])*"/g, ' ');
}

const isi = fs.readFileSync(berkasPeriksa, 'utf8');

const dipakai = new Set();

for (const cocok of buangTeks(isi).matchAll(/\b(rts|Rts)[A-Za-z0-9_]+/g)) {
  dipakai.add(cocok[0]);
}

const semuaSumber = [berkasPeriksa, ...berkasSumber]
  .map((b) => fs.readFileSync(b, 'utf8'))
  .join('\n');

const hilang = [];

for (const nama of [...dipakai].sort()) {
  if (nama.length < 6) continue;

  const pola = new RegExp('\\b' + nama.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '\\b');
  const adaSebagaiDeklarasi =
    new RegExp('(class|enum|typedef|mixin|extension)\\s+' + nama + '\\b').test(semuaSumber) ||
    new RegExp('(Future<[^>]*>|Future<void>|void|bool|int|double|num|String|Widget|Color|BoxDecoration|TextStyle|List<[^>]*>|LatLng|Position)\\s+' + nama + '\\s*[=(\\{]').test(semuaSumber) ||
    new RegExp('const\\s+(Color|String|double|int|bool|List<[^>]*>)\\s+' + nama + '\\b').test(semuaSumber) ||
    new RegExp('[A-Z][A-Za-z0-9_<>,?\\[\\] ]*\\s+' + nama + '\\s*[(=]').test(semuaSumber) ||
    new RegExp('\\bfinal\\s+[A-Za-z0-9_<>?, ]+\\s+' + nama + '\\s*[=;]').test(semuaSumber);

  if (!adaSebagaiDeklarasi) {
    hilang.push(nama);
  }
}

if (hilang.length) {
  console.log('[X] ' + path.basename(berkasPeriksa) + ' : ' + hilang.length + ' nama tidak ditemukan definisinya:');
  for (const nama of hilang) console.log('      - ' + nama);
  process.exit(1);
}

console.log('[V] ' + path.basename(berkasPeriksa) + ' : ' + dipakai.size + ' nama rts/Rts semuanya punya definisi');
