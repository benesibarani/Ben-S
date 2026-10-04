/**
 * ALAT PENGUJIAN DI KOMPUTER (bukan untuk hosting).
 *
 * Pemeriksa kasar berkas Dart: memastikan tanda kurung () [] {} berimbang,
 * tanda kutip tidak menggantung, dan tidak ada sisa tanda yang tertinggal.
 * Berguna untuk menangkap salah tulis sebelum dibangun dengan Flutter.
 *
 * Pemakaian:
 *     node perkakas/periksa_dart.mjs lib/cctv.dart [berkas2.dart ...]
 *
 * Catatan: alat ini BUKAN pengganti `flutter analyze`. Pemeriksaan menyeluruh
 * tetap dilakukan di komputer Bapak dengan perintah:
 *     flutter analyze
 */
import fs from 'node:fs';
import path from 'node:path';

function bersihkan(isi) {
  let keluar = '';
  let i = 0;
  const n = isi.length;
  let mode = 'biasa'; // biasa | baris | blok | teks1 | teks2 | teks3 | teks32

  while (i < n) {
    const c = isi[i];
    const c2 = isi.slice(i, i + 2);
    const c3 = isi.slice(i, i + 3);

    if (mode === 'biasa') {
      if (c2 === '//') { mode = 'baris'; i += 2; continue; }
      if (c2 === '/*') { mode = 'blok'; i += 2; continue; }
      if (c3 === "'''") { mode = 'teks3'; i += 3; continue; }
      if (c3 === '"""') { mode = 'teks32'; i += 3; continue; }
      if (c === "'") { mode = 'teks1'; i += 1; continue; }
      if (c === '"') { mode = 'teks2'; i += 1; continue; }
      keluar += c;
      i += 1;
      continue;
    }

    if (mode === 'baris') {
      if (c === '\n') { mode = 'biasa'; keluar += '\n'; }
      i += 1;
      continue;
    }

    if (mode === 'blok') {
      if (c2 === '*/') { mode = 'biasa'; i += 2; continue; }
      if (c === '\n') keluar += '\n';
      i += 1;
      continue;
    }

    if (mode === 'teks3' || mode === 'teks32') {
      const tutup = mode === 'teks3' ? "'''" : '"""';

      if (c3 === tutup) { mode = 'biasa'; i += 3; continue; }
      if (c === '\\') { i += 2; continue; }
      if (c === '\n') keluar += '\n';
      i += 1;
      continue;
    }

    // teks satu baris
    if (c === '\\') { i += 2; continue; }
    if ((mode === 'teks1' && c === "'") || (mode === 'teks2' && c === '"')) {
      mode = 'biasa';
      i += 1;
      continue;
    }
    if (c === '\n') {
      // tanda kutip menggantung pada satu baris
      keluar += '\u0000';
      mode = 'biasa';
      keluar += '\n';
      i += 1;
      continue;
    }
    i += 1;
  }

  return { kode: keluar, mode };
}

let gagal = 0;

for (const berkas of process.argv.slice(2)) {
  const isi = fs.readFileSync(berkas, 'utf8');
  const { kode, mode } = bersihkan(isi);

  const tumpuk = [];
  const pasangan = { ')': '(', ']': '[', '}': '{' };
  let galat = '';
  let baris = 1;

  for (const c of kode) {
    if (c === '\n') baris++;

    if (c === '\u0000') {
      galat = 'tanda kutip menggantung pada baris ' + baris;
      break;
    }

    if (c === '(' || c === '[' || c === '{') {
      tumpuk.push({ c, baris });
      continue;
    }

    if (c === ')' || c === ']' || c === '}') {
      const atas = tumpuk.pop();

      if (!atas || atas.c !== pasangan[c]) {
        galat = 'tanda "' + c + '" berlebih / tidak berpasangan pada baris ' + baris;
        break;
      }
    }
  }

  if (!galat && tumpuk.length) {
    galat = 'tanda "' + tumpuk[tumpuk.length - 1].c + '" belum ditutup (dibuka pada baris ' + tumpuk[tumpuk.length - 1].baris + ')';
  }

  if (!galat && mode !== 'biasa') {
    galat = 'ada komentar/teks yang belum ditutup di akhir berkas (' + mode + ')';
  }

  const jumlahBaris = isi.split('\n').length;

  if (galat) {
    gagal++;
    console.log('[X] ' + path.basename(berkas) + ' : ' + galat);
  } else {
    console.log('[V] ' + path.basename(berkas) + ' : kurung berimbang (' + jumlahBaris + ' baris, ' + isi.length + ' B)');
  }
}

process.exit(gagal ? 1 : 0);
