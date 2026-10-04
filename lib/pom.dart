// ==========================================================================
// RTS PANEL BY BENE - STRUK POM (SPBU) - SEMUA OFFLINE DI DALAM HP
// Berkas : lib/pom.dart
//
// ISI BERKAS INI
//   1. RtsPomLokal  - database SQLite di dalam HP (rts_panel_pom.db)
//                     memuat: SPBU, BBM, Operator, Format struk, dan Arsip.
//   2. RtsPomCetak  - penyusun perintah cetak ESC/POS (printer Bluetooth
//                     58 mm / 80 mm) beserta PRATINJAU teks di layar.
//   3. Halaman-halaman menu STRUK POM:
//        RtsPomMenuPage      - beranda menu (7 sub-menu)
//        RtsPomFormPage      - menu POM (isi & edit sebelum dicetak)
//        RtsPomHistoriPage   - riwayat penginputan + penyaring tanggal
//        RtsPomArsipPage     - kumpulan struk yang sudah dibuat
//        RtsPomStrukPage     - 3 template struk yang dapat diedit
//        RtsPomOperatorPage  - daftar operator
//        RtsPomBbmPage       - daftar BBM + subsidi
//        RtsPomSpbuPage      - data SPBU (header & footer struk)
//
// CATATAN PENTING
//   - Seluruh data tersimpan DI DALAM HP (SQLite) sehingga tetap berjalan
//     tanpa internet.
//   - Struk POM TIDAK memakai logo RTS Panel. Header memakai GAMBAR yang
//     dipilih sendiri oleh pengguna dari galeri HP (misalnya logo SPBU).
// ==========================================================================

import 'dart:async';
import 'dart:io';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as gbr;
import 'package:image_picker/image_picker.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'kasir.dart';

/// Membaca angka yang ditulis dengan gaya Indonesia.
///
/// Ini PENTING karena isian rupiah pada menu POM ditampilkan memakai titik
/// sebagai pemisah ribuan. Tanpa pembaca ini, "10.000" akan terbaca 10.
///
///   "10.000"    -> 10000
///   "1.250.000" -> 1250000
///   "3,5"       -> 3.5
///   "3.5"       -> 3.5     (titik desimal biasa tetap dihormati)
///   "1.500"     -> 1500    (3 angka di belakang titik = pemisah ribuan)
double rtsPomAngka(dynamic nilai) {
  if (nilai is num) return nilai.toDouble();

  final String teks =
      '${nilai ?? ''}'.replaceAll(RegExp(r'[^0-9,.\-]'), '');

  if (teks.isEmpty || teks == '-') return 0;

  String rapi = teks;

  if (rapi.contains(',')) {
    // Koma = tanda desimal: titik dibuang lebih dahulu.
    rapi = rapi.replaceAll('.', '').replaceAll(',', '.');
  } else if (RegExp(r'^-?\d{1,3}(\.\d{3})+$').hasMatch(rapi)) {
    // Pola pemisah ribuan Indonesia: 10.000 / 1.250.000
    rapi = rapi.replaceAll('.', '');
  }

  return double.tryParse(rapi) ?? 0;
}

/* ------------------------------------------------------------------------- */
/* TEMPAT PENYIMPANAN DATA STRUK POM DI DALAM HP                             */
/* ------------------------------------------------------------------------- */

class RtsPomLokal {
  RtsPomLokal._();

  static final RtsPomLokal aku = RtsPomLokal._();

  /// Nama berkas database khusus struk POM di dalam HP.
  static const String namaBerkas = 'rts_panel_pom.db';

  Database? _db;

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;

    final String tempat = await getDatabasesPath();
    final String jalur = p.join(tempat, namaBerkas);

    _db = await openDatabase(
      jalur,
      version: 1,
      onCreate: (Database d, int v) async {
        for (final String sql in _perintahTabel()) {
          await d.execute(sql);
        }

        await _isiAwal(d);
      },
    );

    return _db!;
  }

  /// Menyiapkan tabel (dipanggil setiap menu POM dibuka).
  Future<void> siapkan() async {
    await db;
  }

  List<String> _perintahTabel() {
    return <String>[
      '''CREATE TABLE IF NOT EXISTS pom_spbu (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL DEFAULT '',
        subtitle TEXT NOT NULL DEFAULT '',
        footer TEXT NOT NULL DEFAULT '',
        urutan INTEGER NOT NULL DEFAULT 0,
        dibuat TEXT NOT NULL DEFAULT '',
        diubah TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE IF NOT EXISTS pom_bbm (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL DEFAULT '',
        harga REAL NOT NULL DEFAULT 0,
        subsidi REAL NOT NULL DEFAULT 0,
        urutan INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE IF NOT EXISTS pom_operator (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL DEFAULT '',
        keterangan TEXT NOT NULL DEFAULT '',
        urutan INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE IF NOT EXISTS pom_format (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL DEFAULT '',
        lebar_mm INTEGER NOT NULL DEFAULT 58,
        pakai_logo INTEGER NOT NULL DEFAULT 1,
        pakai_subsidi INTEGER NOT NULL DEFAULT 1,
        pakai_garis INTEGER NOT NULL DEFAULT 1,
        jumlah_salinan INTEGER NOT NULL DEFAULT 1,
        header_tambahan TEXT NOT NULL DEFAULT '',
        footer_tambahan TEXT NOT NULL DEFAULT '',
        jumlah_baris_atas INTEGER NOT NULL DEFAULT 0
      )''',
      '''CREATE TABLE IF NOT EXISTS pom_struk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        format_id INTEGER NOT NULL DEFAULT 1,
        spbu_id INTEGER NOT NULL DEFAULT 0,
        spbu_title TEXT NOT NULL DEFAULT '',
        spbu_subtitle TEXT NOT NULL DEFAULT '',
        spbu_footer TEXT NOT NULL DEFAULT '',
        operator TEXT NOT NULL DEFAULT '',
        bbm_id INTEGER NOT NULL DEFAULT 0,
        bbm_nama TEXT NOT NULL DEFAULT '',
        bbm_harga REAL NOT NULL DEFAULT 0,
        bbm_subsidi REAL NOT NULL DEFAULT 0,
        shift TEXT NOT NULL DEFAULT '',
        pompa TEXT NOT NULL DEFAULT '',
        selang TEXT NOT NULL DEFAULT '',
        no_trans TEXT NOT NULL DEFAULT '',
        waktu TEXT NOT NULL DEFAULT '',
        plat TEXT NOT NULL DEFAULT '',
        odo TEXT NOT NULL DEFAULT '',
        jumlah_beli REAL NOT NULL DEFAULT 0,
        liter REAL NOT NULL DEFAULT 0,
        jumlah_bayar REAL NOT NULL DEFAULT 0,
        kembali REAL NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT '',
        dibuat TEXT NOT NULL DEFAULT '',
        diubah TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE IF NOT EXISTS pom_setelan (
        kunci TEXT PRIMARY KEY,
        nilai TEXT NOT NULL DEFAULT ''
      )''',
    ];
  }

  /// Isi awal supaya aplikasi langsung dapat dipakai.
  Future<void> _isiAwal(Database d) async {
    final String sekarang = DateTime.now().toIso8601String();

    final List<Map<String, Object?>> format = <Map<String, Object?>>[
      <String, Object?>{
        'nama': 'Format 1 - POM Standar (58 mm)',
        'lebar_mm': 58,
        'pakai_logo': 1,
        'pakai_subsidi': 1,
        'pakai_garis': 1,
        'jumlah_salinan': 1,
      },
      <String, Object?>{
        'nama': 'Format 2 - POM Ringkas (58 mm)',
        'lebar_mm': 58,
        'pakai_logo': 0,
        'pakai_subsidi': 0,
        'pakai_garis': 1,
        'jumlah_salinan': 1,
      },
      <String, Object?>{
        'nama': 'Format 3 - POM Lebar (80 mm)',
        'lebar_mm': 80,
        'pakai_logo': 1,
        'pakai_subsidi': 1,
        'pakai_garis': 1,
        'jumlah_salinan': 1,
      },
    ];

    for (final Map<String, Object?> satu in format) {
      await d.insert('pom_format', satu);
    }

    final List<Map<String, Object?>> bbm = <Map<String, Object?>>[
      <String, Object?>{'nama': 'Pertalite', 'harga': 10000, 'subsidi': 0},
      <String, Object?>{'nama': 'Pertamax', 'harga': 0, 'subsidi': 0},
      <String, Object?>{'nama': 'Pertamina Dex', 'harga': 0, 'subsidi': 0},
      <String, Object?>{'nama': 'Bio Solar', 'harga': 6800, 'subsidi': 0},
      <String, Object?>{'nama': 'Dexlite', 'harga': 26600, 'subsidi': 0},
    ];

    for (int i = 0; i < bbm.length; i++) {
      final Map<String, Object?> satu = bbm[i];

      satu['urutan'] = i;
      await d.insert('pom_bbm', satu);
    }

    await d.insert('pom_operator', <String, Object?>{
      'nama': 'OPERATOR',
      'keterangan': 'Contoh - dapat diganti',
      'urutan': 0,
    });

    await d.insert('pom_setelan', <String, Object?>{
      'kunci': 'dibuat',
      'nilai': sekarang,
    });
  }

  /* ------------------------------------------------------------- setelan */

  Future<String> setelanBaca(String kunci, [String bawaan = '']) async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_setelan',
      where: 'kunci = ?',
      whereArgs: <Object?>[kunci],
      limit: 1,
    );

    if (hasil.isEmpty) return bawaan;

    return '${hasil.first['nilai'] ?? bawaan}';
  }

  Future<void> setelanTulis(String kunci, String nilai) async {
    await (await db).insert(
      'pom_setelan',
      <String, Object?>{'kunci': kunci, 'nilai': nilai},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /* ----------------------------------------------------------------- SPBU */

  Future<List<Map<String, dynamic>>> spbuSemua() async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_spbu',
      orderBy: 'urutan ASC, id ASC',
    );

    return hasil.map(_peta).toList();
  }

  Future<int> spbuSimpan(Map<String, dynamic> data) async {
    final Map<String, Object?> isi = <String, Object?>{
      'title': '${data['title'] ?? ''}',
      'subtitle': '${data['subtitle'] ?? ''}',
      'footer': '${data['footer'] ?? ''}',
      'urutan': rtsKsBulat(data['urutan'] ?? 0),
      'diubah': DateTime.now().toIso8601String(),
    };

    final int id = rtsKsBulat(data['id'] ?? 0);

    if (id > 0) {
      await (await db).update('pom_spbu', isi, where: 'id = ?', whereArgs: <Object?>[id]);
      return id;
    }

    isi['dibuat'] = DateTime.now().toIso8601String();

    return (await db).insert('pom_spbu', isi);
  }

  Future<void> spbuHapus(int id) async {
    await (await db).delete('pom_spbu', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /* ------------------------------------------------------------------ BBM */

  Future<List<Map<String, dynamic>>> bbmSemua() async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_bbm',
      orderBy: 'urutan ASC, id ASC',
    );

    return hasil.map(_peta).toList();
  }

  Future<int> bbmSimpan(Map<String, dynamic> data) async {
    final Map<String, Object?> isi = <String, Object?>{
      'nama': '${data['nama'] ?? ''}',
      'harga': rtsKsAngka(data['harga']),
      'subsidi': rtsKsAngka(data['subsidi']),
      'urutan': rtsKsBulat(data['urutan'] ?? 0),
    };

    final int id = rtsKsBulat(data['id'] ?? 0);

    if (id > 0) {
      await (await db).update('pom_bbm', isi, where: 'id = ?', whereArgs: <Object?>[id]);
      return id;
    }

    return (await db).insert('pom_bbm', isi);
  }

  Future<void> bbmHapus(int id) async {
    await (await db).delete('pom_bbm', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /* ------------------------------------------------------------- OPERATOR */

  Future<List<Map<String, dynamic>>> operatorSemua() async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_operator',
      orderBy: 'urutan ASC, id ASC',
    );

    return hasil.map(_peta).toList();
  }

  Future<int> operatorSimpan(Map<String, dynamic> data) async {
    final Map<String, Object?> isi = <String, Object?>{
      'nama': '${data['nama'] ?? ''}',
      'keterangan': '${data['keterangan'] ?? ''}',
      'urutan': rtsKsBulat(data['urutan'] ?? 0),
    };

    final int id = rtsKsBulat(data['id'] ?? 0);

    if (id > 0) {
      await (await db).update('pom_operator', isi,
          where: 'id = ?', whereArgs: <Object?>[id]);
      return id;
    }

    return (await db).insert('pom_operator', isi);
  }

  Future<void> operatorHapus(int id) async {
    await (await db).delete('pom_operator',
        where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /* --------------------------------------------------------------- FORMAT */

  Future<List<Map<String, dynamic>>> formatSemua() async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_format',
      orderBy: 'id ASC',
    );

    return hasil.map(_peta).toList();
  }

  Future<void> formatUbah(Map<String, dynamic> data) async {
    final int id = rtsKsBulat(data['id'] ?? 0);

    if (id <= 0) return;

    await (await db).update(
      'pom_format',
      <String, Object?>{
        'nama': '${data['nama'] ?? ''}',
        'lebar_mm': rtsKsBulat(data['lebar_mm'] ?? 58),
        'pakai_logo': rtsKsBulat(data['pakai_logo'] ?? 1),
        'pakai_subsidi': rtsKsBulat(data['pakai_subsidi'] ?? 1),
        'pakai_garis': rtsKsBulat(data['pakai_garis'] ?? 1),
        'jumlah_salinan': rtsKsBulat(data['jumlah_salinan'] ?? 1),
        'header_tambahan': '${data['header_tambahan'] ?? ''}',
        'footer_tambahan': '${data['footer_tambahan'] ?? ''}',
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  /* --------------------------------------------------------------- STRUK */

  /// Nomor transaksi berikutnya (dihitung dari arsip di dalam HP).
  Future<String> nomorTransBerikut() async {
    final List<Map<String, Object?>> hasil = await (await db).rawQuery(
      'SELECT MAX(CAST(no_trans AS INTEGER)) AS tertinggi FROM pom_struk '
      "WHERE no_trans GLOB '[0-9]*'",
    );

    final int tertinggi = rtsKsBulat(
      hasil.isEmpty ? 0 : (hasil.first['tertinggi'] ?? 0),
    );

    return '${tertinggi + 1}';
  }

  Future<int> strukSimpan(Map<String, dynamic> data) async {
    final int id = rtsKsBulat(data['id'] ?? 0);
    final String sekarang = DateTime.now().toIso8601String();

    final Map<String, Object?> isi = <String, Object?>{
      'format_id': rtsKsBulat(data['format_id'] ?? 1),
      'spbu_id': rtsKsBulat(data['spbu_id'] ?? 0),
      'spbu_title': '${data['spbu_title'] ?? ''}',
      'spbu_subtitle': '${data['spbu_subtitle'] ?? ''}',
      'spbu_footer': '${data['spbu_footer'] ?? ''}',
      'operator': '${data['operator'] ?? ''}',
      'bbm_id': rtsKsBulat(data['bbm_id'] ?? 0),
      'bbm_nama': '${data['bbm_nama'] ?? ''}',
      'bbm_harga': rtsKsAngka(data['bbm_harga']),
      'bbm_subsidi': rtsKsAngka(data['bbm_subsidi']),
      'shift': '${data['shift'] ?? ''}',
      'pompa': '${data['pompa'] ?? ''}',
      'selang': '${data['selang'] ?? ''}',
      'no_trans': '${data['no_trans'] ?? ''}',
      'waktu': '${data['waktu'] ?? sekarang}',
      'plat': '${data['plat'] ?? ''}',
      'odo': '${data['odo'] ?? ''}',
      'jumlah_beli': rtsKsAngka(data['jumlah_beli']),
      'liter': rtsKsAngka(data['liter']),
      'jumlah_bayar': rtsKsAngka(data['jumlah_bayar']),
      'kembali': rtsKsAngka(data['kembali']),
      'catatan': '${data['catatan'] ?? ''}',
      'diubah': sekarang,
    };

    if (id > 0) {
      await (await db).update('pom_struk', isi, where: 'id = ?', whereArgs: <Object?>[id]);
      return id;
    }

    isi['dibuat'] = sekarang;

    return (await db).insert('pom_struk', isi);
  }

  Future<void> strukHapus(int id) async {
    await (await db).delete('pom_struk', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<Map<String, dynamic>?> strukSatu(int id) async {
    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_struk',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );

    if (hasil.isEmpty) return null;

    return _peta(hasil.first);
  }

  /// Daftar struk arsip. [dari] dan [sampai] berupa tanggal (yyyy-MM-dd).
  Future<List<Map<String, dynamic>>> strukSemua({
    String dari = '',
    String sampai = '',
    String cari = '',
    int batas = 300,
  }) async {
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (dari.isNotEmpty) {
      where.add('substr(waktu, 1, 10) >= ?');
      args.add(dari);
    }

    if (sampai.isNotEmpty) {
      where.add('substr(waktu, 1, 10) <= ?');
      args.add(sampai);
    }

    if (cari.trim().isNotEmpty) {
      where.add('(UPPER(spbu_title) LIKE ? OR UPPER(plat) LIKE ? OR '
          'UPPER(no_trans) LIKE ? OR UPPER(bbm_nama) LIKE ?)');
      final String pola = '%${cari.trim().toUpperCase()}%';
      args.add(pola);
      args.add(pola);
      args.add(pola);
      args.add(pola);
    }

    final List<Map<String, Object?>> hasil = await (await db).query(
      'pom_struk',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'waktu DESC, id DESC',
      limit: batas,
    );

    return hasil.map(_peta).toList();
  }

  /// Ringkasan jumlah struk, rupiah, dan liter pada rentang tanggal.
  Future<Map<String, double>> ringkasan({
    String dari = '',
    String sampai = '',
  }) async {
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    if (dari.isNotEmpty) {
      where.add('substr(waktu, 1, 10) >= ?');
      args.add(dari);
    }

    if (sampai.isNotEmpty) {
      where.add('substr(waktu, 1, 10) <= ?');
      args.add(sampai);
    }

    final List<Map<String, Object?>> hasil = await (await db).rawQuery(
      'SELECT COUNT(*) AS jumlah, SUM(jumlah_beli) AS rupiah, '
      'SUM(liter) AS liter FROM pom_struk'
      '${where.isEmpty ? '' : ' WHERE ' + where.join(' AND ')}',
      args.isEmpty ? null : args,
    );

    if (hasil.isEmpty) {
      return <String, double>{'jumlah': 0, 'rupiah': 0, 'liter': 0};
    }

    final Map<String, Object?> baris = hasil.first;

    return <String, double>{
      'jumlah': rtsKsAngka(baris['jumlah']),
      'rupiah': rtsKsAngka(baris['rupiah']),
      'liter': rtsKsAngka(baris['liter']),
    };
  }

  Map<String, dynamic> _peta(Map<String, Object?> baris) {
    return baris.map<String, dynamic>(
      (String kunci, Object? nilai) => MapEntry<String, dynamic>(kunci, nilai),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PENYUSUN STRUK POM (ESC/POS) DAN PRATINJAU DI LAYAR                       */
/* ------------------------------------------------------------------------- */

class RtsPomCetak {
  RtsPomCetak._();

  /// Lebar kertas (jumlah karakter per baris) menurut ukuran mm.
  static int lebarKarakter(int lebarMm) => lebarMm >= 76 ? 42 : 32;

  /// Alamat berkas gambar header (logo) yang dipilih dari galeri HP.
  static Future<String> logoBaca() => RtsPomLokal.aku.setelanBaca('logo_path');

  static Future<void> logoTulis(String jalur) =>
      RtsPomLokal.aku.setelanTulis('logo_path', jalur);

  /// Menyalin gambar pilihan ke folder aplikasi supaya tetap ada
  /// walaupun berkas aslinya dihapus dari galeri.
  static Future<String> logoSimpanDariGaleri() async {
    final ImagePicker pemilih = ImagePicker();

    final XFile? berkas = await pemilih.pickImage(
      source: ImageSource.gallery,
      maxWidth: 900,
      maxHeight: 900,
      imageQuality: 90,
    );

    if (berkas == null) return '';

    final Directory folder = await getApplicationDocumentsDirectory();
    final String tujuan = p.join(folder.path, 'pom_logo.png');

    await File(berkas.path).copy(tujuan);

    await logoTulis(tujuan);

    return tujuan;
  }

  /// Membaca gambar logo sebagai gambar bitmap untuk dicetak.
  static gbr.Image? _gambarLogo(String jalur, int lebarMm) {
    if (jalur.trim().isEmpty) return null;

    final File berkas = File(jalur);

    if (!berkas.existsSync()) return null;

    try {
      final gbr.Image? gambar = gbr.decodeImage(berkas.readAsBytesSync());

      if (gambar == null) return null;

      final int maksTitik = lebarMm >= 76 ? 480 : 320;

      if (gambar.width <= maksTitik) return gambar;

      return gbr.copyResize(gambar, width: maksTitik);
    } catch (_) {
      return null;
    }
  }

  /// Memecah isian menjadi baris-baris (enter juga memisahkan baris).
  static List<String> baris(String teks) {
    return teks
        .split(RegExp(r'[\r\n]+'))
        .map((String satu) => satu.trim())
        .where((String satu) => satu.isNotEmpty)
        .toList();
  }

  static String _gambar(int panjang, String tanda) =>
      List<String>.filled(panjang, tanda).join();

  /// Menyusun perintah cetak (ESC/POS) untuk satu struk POM.
  static Future<List<int>> bangun(
    Map<String, dynamic> s,
    Map<String, dynamic> f, {
    String logo = '',
  }) async {
    final CapabilityProfile profile = await CapabilityProfile.load();

    final int lebarMm = rtsKsBulat(f['lebar_mm'] ?? 58);
    final PaperSize ukuran = lebarMm >= 76 ? PaperSize.mm80 : PaperSize.mm58;

    final Generator g = Generator(ukuran, profile);
    final List<int> bytes = <int>[];

    final int lebar = lebarKarakter(lebarMm);
    final String garisTanda =
        rtsKsBulat(f['pakai_garis'] ?? 1) == 0 ? '' : '-';
    final String tanda = garisTanda.isEmpty ? '-' : garisTanda;

    /* ------------------------------------------------------------- gambar */
    if (rtsKsBulat(f['pakai_logo'] ?? 1) != 0) {
      final gbr.Image? gambar = _gambarLogo(logo, lebarMm);

      if (gambar != null) {
        try {
          bytes.addAll(g.image(gambar));
          bytes.addAll(g.feed(1));
        } catch (_) {
          // printer tidak mendukung gambar: bagian ini dilewati
        }
      }
    }

    /* ------------------------------------------------------------- header */
    for (final String satu in baris('${s['spbu_title'] ?? ''}')) {
      bytes.addAll(g.text(
        satu,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ));
    }

    for (final String satu in baris('${s['spbu_subtitle'] ?? ''}')) {
      bytes.addAll(g.text(satu, styles: const PosStyles(align: PosAlign.center)));
    }

    for (final String satu in baris('${f['header_tambahan'] ?? ''}')) {
      bytes.addAll(g.text(satu, styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(g.text(_gambar(lebar, tanda)));

    /* --------------------------------------------------------------- isi */
    final String shift = '${s['shift'] ?? ''}'.trim();
    final String pompa = '${s['pompa'] ?? ''}'.trim();
    final String selang = '${s['selang'] ?? ''}'.trim();
    final String noTrans = '${s['no_trans'] ?? ''}'.trim();
    final String waktu = '${s['waktu'] ?? ''}'.trim();

    if (shift.isNotEmpty || noTrans.isNotEmpty) {
      bytes.addAll(g.row(<PosColumn>[
        PosColumn(text: 'Shift: $shift', width: 6),
        PosColumn(text: 'No. Trans: $noTrans', width: 6),
      ]));
    }

    if (waktu.isNotEmpty) {
      bytes.addAll(g.text('Waktu: ${rtsKsWaktuLengkap(waktu)}'));
    }

    final String pulauPompa = <String>[pompa, selang]
        .where((String satu) => satu.isNotEmpty)
        .join(' / ');

    bytes.addAll(g.text(_gambar(lebar, tanda)));

    if (pulauPompa.isNotEmpty) {
      bytes.addAll(g.text('Pulau/Pompa: $pulauPompa'));
    }

    final double harga = rtsKsAngka(s['bbm_harga']);
    final double liter = rtsKsAngka(s['liter']);
    final double total = harga * liter;
    final double subsidi = rtsKsAngka(s['bbm_subsidi']);
    final String operator = '${s['operator'] ?? ''}'.trim();

    bytes.addAll(g.text('Nama Produk: ${s['bbm_nama'] ?? '-'}'));
    bytes.addAll(g.text('Harga/Liter: Rp. ${rtsKsUang(harga)}'));
    bytes.addAll(g.text('Volume     : (L) ${liter.toStringAsFixed(3)}'));
    bytes.addAll(g.text('Total Harga: Rp. ${rtsKsUang(total)}'));

    if (operator.isNotEmpty) {
      bytes.addAll(g.text('Operator   : $operator'));
    }

    if (rtsKsBulat(f['pakai_subsidi'] ?? 1) != 0 && subsidi > 0) {
      bytes.addAll(g.text('Subsidi    : Rp. ${rtsKsUang(subsidi)}/liter'));
    }

    bytes.addAll(g.text(_gambar(lebar, tanda)));

    /* ------------------------------------------------------------ bayaran */
    final double bayar = rtsKsAngka(s['jumlah_bayar']);
    final double kembali = rtsKsAngka(s['kembali']);

    bytes.addAll(g.text('CASH'));

    bytes.addAll(g.row(<PosColumn>[
      PosColumn(text: '', width: 6),
      PosColumn(
        text: rtsKsUang(total),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]));

    if (bayar > 0) {
      bytes.addAll(g.row(<PosColumn>[
        PosColumn(text: 'Bayar', width: 6),
        PosColumn(
          text: rtsKsUang(bayar),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));

      bytes.addAll(g.row(<PosColumn>[
        PosColumn(text: 'Kembali', width: 6),
        PosColumn(
          text: rtsKsUang(kembali),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(g.text(_gambar(lebar, tanda)));

    /* ------------------------------------------------------------ kendara */
    final String plat = '${s['plat'] ?? ''}'.trim();
    final String odo = '${s['odo'] ?? ''}'.trim();

    if (plat.isNotEmpty) {
      bytes.addAll(g.text('No. Plat   : $plat'));
    }

    if (odo.isNotEmpty) {
      bytes.addAll(g.text('Odo/No. HP : $odo'));
    }

    if (plat.isNotEmpty || odo.isNotEmpty) {
      bytes.addAll(g.text(_gambar(lebar, tanda)));
    }

    /* ------------------------------------------------------------- footer */
    final String catatan = '${s['catatan'] ?? ''}'.trim();

    if (catatan.isNotEmpty) {
      for (final String satu in baris(catatan)) {
        bytes.addAll(g.text(satu, styles: const PosStyles(align: PosAlign.center)));
      }
    }

    for (final String satu in baris('${s['spbu_footer'] ?? ''}')) {
      bytes.addAll(g.text(satu, styles: const PosStyles(align: PosAlign.center)));
    }

    for (final String satu in baris('${f['footer_tambahan'] ?? ''}')) {
      bytes.addAll(g.text(satu, styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());

    return bytes;
  }

  /// Pratinjau teks struk untuk dilihat di layar sebelum dicetak.
  static List<String> pratinjau(
    Map<String, dynamic> s,
    Map<String, dynamic> f, {
    bool adaLogo = false,
  }) {
    final int lebarMm = rtsKsBulat(f['lebar_mm'] ?? 58);
    final int lebar = lebarKarakter(lebarMm);
    final List<String> keluaran = <String>[];

    void tengah(String teks) {
      final String rapi = teks.trim();

      if (rapi.isEmpty) return;

      if (rapi.length >= lebar) {
        keluaran.add(rapi);
        return;
      }

      final int sisa = ((lebar - rapi.length) / 2).floor();
      keluaran.add('${' ' * sisa}$rapi');
    }

    void kiri(String teks) {
      if (teks.trim().isEmpty) return;

      keluaran.add(teks);
    }

    if (rtsKsBulat(f['pakai_logo'] ?? 1) != 0) {
      tengah(adaLogo ? '[ GAMBAR HEADER ]' : '[ gambar header belum dipilih ]');
    }

    for (final String satu in baris('${s['spbu_title'] ?? ''}')) {
      tengah(satu.toUpperCase());
    }

    for (final String satu in baris('${s['spbu_subtitle'] ?? ''}')) {
      tengah(satu);
    }

    if (rtsKsBulat(f['pakai_garis'] ?? 1) != 0) kiri(_gambar(lebar, '-'));

    kiri('Shift: ${s['shift'] ?? ''}     No. Trans: ${s['no_trans'] ?? ''}');
    kiri('Waktu: ${rtsKsWaktuLengkap('${s['waktu'] ?? ''}')}');

    if (rtsKsBulat(f['pakai_garis'] ?? 1) != 0) kiri(_gambar(lebar, '-'));

    final String pulauPompa = <String>['${s['pompa'] ?? ''}', '${s['selang'] ?? ''}']
        .where((String satu) => satu.trim().isNotEmpty)
        .join(' / ');

    if (pulauPompa.isNotEmpty) kiri('Pulau/Pompa: $pulauPompa');

    final double harga = rtsKsAngka(s['bbm_harga']);
    final double liter = rtsKsAngka(s['liter']);
    final double total = harga * liter;

    kiri('Nama Produk: ${s['bbm_nama'] ?? '-'}');
    kiri('Harga/Liter: Rp. ${rtsKsUang(harga)}');
    kiri('Volume     : (L) ${liter.toStringAsFixed(3)}');
    kiri('Total Harga: Rp. ${rtsKsUang(total)}');

    final String operator = '${s['operator'] ?? ''}'.trim();

    if (operator.isNotEmpty) kiri('Operator   : $operator');

    final double subsidi = rtsKsAngka(s['bbm_subsidi']);

    if (rtsKsBulat(f['pakai_subsidi'] ?? 1) != 0 && subsidi > 0) {
      kiri('Subsidi    : Rp. ${rtsKsUang(subsidi)}/liter');
    }

    if (rtsKsBulat(f['pakai_garis'] ?? 1) != 0) kiri(_gambar(lebar, '-'));

    kiri('CASH');

    final String rapiTotal = rtsKsUang(total);
    kiri('${' ' * (lebar - rapiTotal.length)}$rapiTotal');

    final double bayar = rtsKsAngka(s['jumlah_bayar']);

    if (bayar > 0) {
      kiri('Bayar   : ${rtsKsUang(bayar)}');
      kiri('Kembali : ${rtsKsUang(s['kembali'])}');
    }

    if (rtsKsBulat(f['pakai_garis'] ?? 1) != 0) kiri(_gambar(lebar, '-'));

    if ('${s['plat'] ?? ''}'.trim().isNotEmpty) kiri('No. Plat   : ${s['plat']}');
    if ('${s['odo'] ?? ''}'.trim().isNotEmpty) kiri('Odo/No. HP : ${s['odo']}');

    if (rtsKsBulat(f['pakai_garis'] ?? 1) != 0) kiri(_gambar(lebar, '-'));

    for (final String satu in baris('${s['catatan'] ?? ''}')) {
      tengah(satu);
    }

    for (final String satu in baris('${s['spbu_footer'] ?? ''}')) {
      tengah(satu);
    }

    for (final String satu in baris('${f['footer_tambahan'] ?? ''}')) {
      tengah(satu);
    }

    return keluaran;
  }

  /// Mengirim struk ke printer Bluetooth yang sudah disambungkan pada menu
  /// "Printer & Struk". Mengembalikan keterangan kosong bila berhasil.
  static Future<String> cetak(
    Map<String, dynamic> s,
    Map<String, dynamic> f,
  ) async {
    try {
      if (!await RtsPrinter.izinBluetooth()) {
        return 'Izin Bluetooth belum diberikan. Buka Pengaturan HP - Aplikasi - '
            'RTS Panel - Izin - Perangkat di sekitar (Bluetooth) - Izinkan.';
      }

      if (!await RtsPrinter.sambung()) {
        return 'Printer belum tersambung. Pastikan Bluetooth HP menyala dan '
            'printer thermal sudah dihubungkan pada menu "Printer & Struk", '
            'lalu coba cetak lagi.';
      }

      final String logo = await logoBaca();
      final List<int> bytes = await bangun(s, f, logo: logo);

      final int salinan = rtsKsBulat(f['jumlah_salinan'] ?? 1);

      for (int i = 0; i < (salinan < 1 ? 1 : salinan); i++) {
        final bool ok = await PrintBluetoothThermal.writeBytes(bytes);

        if (!ok) {
          return 'Printer menolak perintah cetak. Periksa kertas dan sambungan '
              'printer, lalu coba lagi.';
        }
      }

      return '';
    } catch (e) {
      return 'Gagal mencetak: $e';
    }
  }

  /// Teks struk untuk disalin (tombol SALIN pada menu Arsip).
  static String teksSalin(
    Map<String, dynamic> s,
    Map<String, dynamic> f, {
    bool adaLogo = false,
  }) {
    return pratinjau(s, f, adaLogo: adaLogo).join('\n');
  }
}

/* ------------------------------------------------------------------------- */
/* BANTUAN TAMPILAN                                                          */
/* ------------------------------------------------------------------------- */

const Color rtsPomLatar = Color(0xfff8f5f1);
const Color rtsPomGaris = Color(0xffece5de);
const Color rtsPomTeks2 = Color(0xff7c736d);
const Color rtsPomBiru = Color(0xff1d6fb8);

class _PomKartu extends StatelessWidget {
  const _PomKartu({required this.child, this.padding = const EdgeInsets.all(14)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: rtsPomGaris),
      ),
      child: child,
    );
  }
}

class _PomJudul extends StatelessWidget {
  const _PomJudul(this.teks);

  final String teks;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 16,
          decoration: BoxDecoration(
            color: rtsKsMaroon,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            teks,
            style: const TextStyle(
              color: rtsKsTeks,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

/// Kolom isian yang dipakai seluruh halaman struk POM.
class _PomIsian extends StatelessWidget {
  const _PomIsian({
    required this.controller,
    required this.label,
    this.hint = '',
    this.ikon,
    this.angka = false,
    this.baris = 1,
    this.onUbah,
    this.sufiks,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? ikon;
  final bool angka;
  final int baris;
  final void Function(String)? onUbah;
  final Widget? sufiks;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: baris,
      onChanged: onUbah,
      keyboardType: angka
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isEmpty ? null : hint,
        prefixIcon:
            ikon == null ? null : Icon(ikon, color: const Color(0xff6d514a), size: 20),
        suffixIcon: sufiks,
        alignLabelWithHint: baris > 1,
        filled: true,
        fillColor: const Color(0xfff8f4ef),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: const TextStyle(fontSize: 13.5),
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xffa99d94)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: rtsKsMaroon, width: 1.4),
        ),
      ),
    );
  }
}

/// Pilihan (dropdown) sederhana dengan label di atasnya.
class _PomPilihan<T> extends StatelessWidget {
  const _PomPilihan({
    required this.label,
    required this.nilai,
    required this.pilihan,
    required this.onPilih,
    this.kosong = 'Belum ada data',
    this.hint = 'Ketuk untuk memilih',
  });

  final String label;
  final T? nilai;
  final List<DropdownMenuItem<T>> pilihan;
  final void Function(T? nilai) onPilih;
  final String kosong;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: rtsPomTeks2,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xfff8f4ef),
            borderRadius: BorderRadius.circular(14),
          ),
          child: pilihan.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    kosong,
                    style: const TextStyle(color: rtsPomTeks2, fontSize: 13.5),
                  ),
                )
              : DropdownButton<T>(
                  isExpanded: true,
                  underline: const SizedBox(),
                  value: nilai,
                  hint: Text(
                    hint,
                    style: const TextStyle(fontSize: 13, color: rtsPomTeks2),
                  ),
                  style: const TextStyle(fontSize: 14, color: rtsKsTeks),
                  items: pilihan,
                  onChanged: onPilih,
                ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU STRUK POM - BERANDA                                                  */
/* ------------------------------------------------------------------------- */

class RtsPomMenuPage extends StatefulWidget {
  const RtsPomMenuPage({super.key});

  @override
  State<RtsPomMenuPage> createState() => _RtsPomMenuPageState();
}

class _RtsPomMenuPageState extends State<RtsPomMenuPage> {
  int _arsip = 0;
  double _hariIni = 0;
  bool _memuat = true;
  bool _contohTerbuka = false;
  List<String> _contoh = <String>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    final String hari = DateTime.now().toIso8601String().substring(0, 10);

    final Map<String, double> ringkasHari =
        await RtsPomLokal.aku.ringkasan(dari: hari, sampai: hari);
    final Map<String, double> ringkasSemua = await RtsPomLokal.aku.ringkasan();

    if (!mounted) return;

    setState(() {
      _arsip = ringkasSemua['jumlah']?.round() ?? 0;
      _hariIni = ringkasHari['rupiah'] ?? 0;
      _memuat = false;
    });

    await _muatContoh();
  }

  /// Contoh struk memakai data paling akhir (atau contoh bawaan).
  Future<void> _muatContoh() async {
    final List<Map<String, dynamic>> struk = await RtsPomLokal.aku.strukSemua(batas: 1);
    final List<Map<String, dynamic>> format = await RtsPomLokal.aku.formatSemua();
    final String logo = await RtsPomCetak.logoBaca();

    if (format.isEmpty) return;

    final Map<String, dynamic> f = format.first;

    Map<String, dynamic> s;

    if (struk.isNotEmpty) {
      s = struk.first;
    } else {
      final List<Map<String, dynamic>> spbu = await RtsPomLokal.aku.spbuSemua();
      final List<Map<String, dynamic>> bbm = await RtsPomLokal.aku.bbmSemua();

      s = <String, dynamic>{
        'spbu_title': spbu.isEmpty ? 'NAMA SPBU' : '${spbu.first['title']}',
        'spbu_subtitle': spbu.isEmpty ? 'Alamat SPBU' : '${spbu.first['subtitle']}',
        'spbu_footer': spbu.isEmpty ? '' : '${spbu.first['footer']}',
        'operator': 'OPERATOR',
        'bbm_nama': bbm.isEmpty ? 'PERTALITE' : '${bbm.first['nama']}',
        'bbm_harga': bbm.isEmpty ? 10000 : bbm.first['harga'],
        'bbm_subsidi': bbm.isEmpty ? 0 : bbm.first['subsidi'],
        'shift': '1',
        'pompa': '1',
        'selang': '1',
        'no_trans': '1',
        'waktu': DateTime.now().toIso8601String(),
        'plat': 'BK 1234 XX',
        'odo': '0',
        'liter': 1,
        'jumlah_bayar': 0,
        'kembali': 0,
        'catatan': '',
      };
    }

    final List<String> teks =
        RtsPomCetak.pratinjau(s, f, adaLogo: logo.trim().isNotEmpty);

    if (!mounted) return;

    setState(() => _contoh = teks);
  }

  void _buka(Widget halaman) {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => halaman))
        .then((_) {
      if (mounted) unawaited(_muat());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Struk POM'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[rtsKsMaroon, rtsKsMaroonDark],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'STRUK POM / SPBU',
                  style: TextStyle(
                    color: Color(0xccffffff),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _memuat ? 'Membaca data...' : '$_arsip struk tersimpan di HP',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hari ini: Rp ${rtsKsUang(_hariIni)} - berjalan tanpa internet',
                  style: const TextStyle(color: Color(0xb3ffffff), fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _PomJudul('MENU STRUK POM'),
          const SizedBox(height: 10),
          _barisMenu(
            ikon: Icons.history_rounded,
            judul: 'Histori',
            keterangan: 'Riwayat penginputan + saring tanggal',
            onTap: () => _buka(const RtsPomHistoriPage()),
          ),
          _barisMenu(
            ikon: Icons.local_gas_station_rounded,
            judul: 'POM',
            keterangan: 'Isi & edit struk sebelum dicetak',
            onTap: () => _buka(const RtsPomFormPage()),
          ),
          _barisMenu(
            ikon: Icons.folder_copy_outlined,
            judul: 'Arsip',
            keterangan: 'Struk yang sudah dibuat - dapat dicetak ulang',
            onTap: () => _buka(const RtsPomArsipPage()),
          ),
          _barisMenu(
            ikon: Icons.receipt_long_outlined,
            judul: 'Struk',
            keterangan: 'Template struk: header, isi, dan footer',
            onTap: () => _buka(const RtsPomStrukPage()),
          ),
          _barisMenu(
            ikon: Icons.person_outline_rounded,
            judul: 'Operator',
            keterangan: 'Nama operator pada menu POM',
            onTap: () => _buka(const RtsPomOperatorPage()),
          ),
          _barisMenu(
            ikon: Icons.opacity_rounded,
            judul: 'BBM',
            keterangan: 'Harga BBM dan subsidi',
            onTap: () => _buka(const RtsPomBbmPage()),
          ),
          _barisMenu(
            ikon: Icons.store_mall_directory_outlined,
            judul: 'SPBU',
            keterangan: 'Nama & alamat SPBU (header dan footer struk)',
            onTap: () => _buka(const RtsPomSpbuPage()),
          ),
          const SizedBox(height: 16),
          _kartuContoh(),
          const SizedBox(height: 14),
          const Text(
            'Semua data struk POM tersimpan DI DALAM HP (SQLite). Aplikasi '
            'tetap dapat membuat dan mencetak struk walaupun tidak ada '
            'internet. Cetak memakai printer Bluetooth 58 mm / 80 mm yang '
            'sudah dihubungkan pada menu "Printer & Struk".',
            style: TextStyle(color: rtsPomTeks2, fontSize: 11.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _barisMenu({
    required IconData ikon,
    required String judul,
    required String keterangan,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: rtsPomGaris),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xfffaecee),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(ikon, color: rtsKsMaroon, size: 23),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        judul,
                        style: const TextStyle(
                          color: rtsKsTeks,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        keterangan,
                        style: const TextStyle(
                          color: rtsPomTeks2,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: rtsPomTeks2),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _kartuContoh() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () => setState(() => _contohTerbuka = !_contohTerbuka),
            child: Row(
              children: <Widget>[
                const Icon(Icons.description_outlined, color: rtsKsMaroon, size: 19),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Contoh struk',
                    style: TextStyle(
                      color: rtsKsTeks,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  _contohTerbuka
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: rtsPomTeks2,
                ),
              ],
            ),
          ),
          if (_contohTerbuka) ...<Widget>[
            const SizedBox(height: 12),
            if (_contoh.isEmpty)
              const Text(
                'Contoh belum dapat dibuat. Tambahkan dulu data SPBU dan BBM.',
                style: TextStyle(color: rtsPomTeks2, fontSize: 12),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xfff3efe9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    _contoh.join('\n'),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      height: 1.3,
                      color: rtsKsTeks,
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Contoh ini memakai data struk terakhir. Tekan menu POM untuk '
              'membuat struk baru.',
              style: TextStyle(color: rtsPomTeks2, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU POM - ISI STRUK SEBELUM DICETAK                                      */
/* ------------------------------------------------------------------------- */

class RtsPomFormPage extends StatefulWidget {
  const RtsPomFormPage({super.key, this.strukId = 0});

  /// Bila diisi, halaman ini dipakai untuk MENGUBAH struk yang sudah ada.
  final int strukId;

  @override
  State<RtsPomFormPage> createState() => _RtsPomFormPageState();
}

class _RtsPomFormPageState extends State<RtsPomFormPage> {
  final TextEditingController shift = TextEditingController(text: '1');
  final TextEditingController pompa = TextEditingController(text: '1');
  final TextEditingController selang = TextEditingController(text: '1');
  final TextEditingController noTrans = TextEditingController();
  final TextEditingController plat = TextEditingController();
  final TextEditingController odo = TextEditingController();
  final TextEditingController jumlahBeli = TextEditingController();
  final TextEditingController liter = TextEditingController(text: '0');
  final TextEditingController bayar = TextEditingController();
  final TextEditingController kembali = TextEditingController(text: '0');
  final TextEditingController catatan = TextEditingController();

  bool _memuat = true;
  bool _menyimpan = false;

  List<Map<String, dynamic>> _spbu = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _bbm = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _operator = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _format = <Map<String, dynamic>>[];

  int _spbuId = 0;
  int _bbmId = 0;
  int _formatId = 0;
  String _operatorNama = '';
  DateTime _waktu = DateTime.now();

  // Salinan nilai dari BBM & SPBU yang dipakai saat mencetak. Disimpan pada
  // setiap struk supaya struk lama tetap benar walaupun data BBM atau SPBU-nya
  // sudah dihapus dari daftar.
  String _namaBbm = '';
  double _hargaBbm = 0;
  double _subsidiBbm = 0;

  String _spbuTitle = '';
  String _spbuSubtitle = '';
  String _spbuFooter = '';

  /// Mengembalikan id hanya bila benar-benar ada pada daftar. Ini mencegah
  /// galat "pilihan tidak ditemukan" pada DropdownButton.
  int? _idSah(List<Map<String, dynamic>> daftar, int id) {
    for (final Map<String, dynamic> satu in daftar) {
      if (rtsKsBulat(satu['id']) == id) return id;
    }

    return null;
  }

  void _pakaiBbm(int id) {
    for (final Map<String, dynamic> satu in _bbm) {
      if (rtsKsBulat(satu['id']) == id) {
        _bbmId = id;
        _namaBbm = '${satu['nama']}';
        _hargaBbm = rtsKsAngka(satu['harga']);
        _subsidiBbm = rtsKsAngka(satu['subsidi']);
        return;
      }
    }
  }

  void _pakaiSpbu(int id) {
    for (final Map<String, dynamic> satu in _spbu) {
      if (rtsKsBulat(satu['id']) == id) {
        _spbuId = id;
        _spbuTitle = '${satu['title']}';
        _spbuSubtitle = '${satu['subtitle']}';
        _spbuFooter = '${satu['footer']}';
        return;
      }
    }
  }

  Map<String, dynamic>? get _formatPilih {
    for (final Map<String, dynamic> satu in _format) {
      if (rtsKsBulat(satu['id']) == _formatId) return satu;
    }

    return _format.isEmpty ? null : _format.first;
  }

  double get _liter => rtsPomAngka(liter.text);
  double get _total => _hargaBbm * _liter;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  @override
  void dispose() {
    shift.dispose();
    pompa.dispose();
    selang.dispose();
    noTrans.dispose();
    plat.dispose();
    odo.dispose();
    jumlahBeli.dispose();
    liter.dispose();
    bayar.dispose();
    kembali.dispose();
    catatan.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    _spbu = await RtsPomLokal.aku.spbuSemua();
    _bbm = await RtsPomLokal.aku.bbmSemua();
    _operator = await RtsPomLokal.aku.operatorSemua();
    _format = await RtsPomLokal.aku.formatSemua();

    if (_spbu.isNotEmpty) _pakaiSpbu(rtsKsBulat(_spbu.first['id']));
    if (_bbm.isNotEmpty) _pakaiBbm(rtsKsBulat(_bbm.first['id']));
    if (_operator.isNotEmpty) _operatorNama = '${_operator.first['nama']}';
    if (_format.isNotEmpty) _formatId = rtsKsBulat(_format.first['id']);

    if (widget.strukId > 0) {
      final Map<String, dynamic>? lama =
          await RtsPomLokal.aku.strukSatu(widget.strukId);

      if (lama != null) {
        // Salinan dari struk lama dipakai lebih dahulu.
        _spbuTitle = '${lama['spbu_title'] ?? ''}';
        _spbuSubtitle = '${lama['spbu_subtitle'] ?? ''}';
        _spbuFooter = '${lama['spbu_footer'] ?? ''}';
        _namaBbm = '${lama['bbm_nama'] ?? ''}';
        _hargaBbm = rtsKsAngka(lama['bbm_harga']);
        _subsidiBbm = rtsKsAngka(lama['bbm_subsidi']);

        // Bila datanya masih ada, pilihan disetel mengikuti data itu.
        _pakaiSpbu(rtsKsBulat(lama['spbu_id']));
        _pakaiBbm(rtsKsBulat(lama['bbm_id']));

        _spbuId = rtsKsBulat(lama['spbu_id']);
        _bbmId = rtsKsBulat(lama['bbm_id']);
        _formatId = rtsKsBulat(lama['format_id'] ?? _formatId);
        _operatorNama = '${lama['operator'] ?? ''}';

        shift.text = '${lama['shift'] ?? ''}';
        pompa.text = '${lama['pompa'] ?? ''}';
        selang.text = '${lama['selang'] ?? ''}';
        noTrans.text = '${lama['no_trans'] ?? ''}';
        plat.text = '${lama['plat'] ?? ''}';
        odo.text = '${lama['odo'] ?? ''}';
        liter.text = '${lama['liter'] ?? 0}';
        jumlahBeli.text = rtsKsUang(lama['jumlah_beli']);
        bayar.text = rtsKsUang(lama['jumlah_bayar']);
        kembali.text = rtsKsUang(lama['kembali']);
        catatan.text = '${lama['catatan'] ?? ''}';

        _waktu = DateTime.tryParse('${lama['waktu']}') ?? DateTime.now();
      }
    } else {
      noTrans.text = await RtsPomLokal.aku.nomorTransBerikut();
      _waktu = DateTime.now();
    }

    if (!mounted) return;

    setState(() => _memuat = false);
  }

  /* --------------------------------------------------------------- hitungan */

  void _dariBeli() {
    final double harga = _hargaBbm;
    final double beli = rtsPomAngka(jumlahBeli.text);

    if (harga > 0 && beli > 0) {
      liter.text = (beli / harga).toStringAsFixed(3);
    }

    _hitungKembali();
  }

  void _dariLiter() {
    final double harga = _hargaBbm;
    final double vol = rtsPomAngka(liter.text);

    if (harga > 0 && vol > 0) {
      jumlahBeli.text = rtsKsUang(harga * vol);
    }

    _hitungKembali();
  }

  void _hitungKembali() {
    final double dibayar = rtsPomAngka(bayar.text);

    kembali.text = rtsKsUang(dibayar - _total);
  }

  Future<void> _pilihWaktu() async {
    final DateTime? tanggal = await showDatePicker(
      context: context,
      initialDate: _waktu,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Pilih tanggal struk',
    );

    if (tanggal == null || !mounted) return;

    final TimeOfDay? jam = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_waktu),
      helpText: 'Pilih jam struk',
    );

    if (jam == null || !mounted) return;

    setState(() {
      _waktu = DateTime(
        tanggal.year,
        tanggal.month,
        tanggal.day,
        jam.hour,
        jam.minute,
      );
    });
  }

  /* -------------------------------------------------------- kumpulkan data */

  Map<String, dynamic> _dataStruk() {
    return <String, dynamic>{
      'id': widget.strukId,
      'format_id': rtsKsBulat(_formatPilih?['id'] ?? _formatId),
      'spbu_id': _spbuId,
      'spbu_title': _spbuTitle,
      'spbu_subtitle': _spbuSubtitle,
      'spbu_footer': _spbuFooter,
      'operator': _operatorNama,
      'bbm_id': _bbmId,
      'bbm_nama': _namaBbm,
      'bbm_harga': _hargaBbm,
      'bbm_subsidi': _subsidiBbm,
      'shift': shift.text.trim(),
      'pompa': pompa.text.trim(),
      'selang': selang.text.trim(),
      'no_trans': noTrans.text.trim(),
      'waktu': _waktu.toIso8601String(),
      'plat': plat.text.trim(),
      'odo': odo.text.trim(),
      'jumlah_beli': rtsPomAngka(jumlahBeli.text),
      'liter': _liter,
      'jumlah_bayar': rtsPomAngka(bayar.text),
      'kembali': rtsPomAngka(kembali.text),
      'catatan': catatan.text.trim(),
    };
  }

  String _periksa() {
    if (_spbuTitle.trim().isEmpty) {
      return 'Data SPBU belum dipilih. Buka menu SPBU lalu tambahkan nomor / '
          'nama SPBU terlebih dahulu (dipakai sebagai kepala struk).';
    }

    if (_namaBbm.isEmpty) {
      return 'Jenis BBM belum dipilih. Buka menu BBM bila daftarnya masih kosong.';
    }

    if (_liter <= 0) {
      return 'Volume (liter) belum diisi. Isi jumlah beli atau tekan tombol '
          'liter cepat (1-4 Liter).';
    }

    return '';
  }

  /* -------------------------------------------------------------- tindakan */

  Future<void> _simpan({bool cetak = false}) async {
    FocusScope.of(context).unfocus();

    final String galat = _periksa();

    if (galat.isNotEmpty) {
      rtsKsPesan(context, galat, galat: true);
      return;
    }

    setState(() => _menyimpan = true);

    final Map<String, dynamic> data = _dataStruk();

    try {
      final int id = await RtsPomLokal.aku.strukSimpan(data);

      if (!mounted) return;

      setState(() {
        _menyimpan = false;
      });

      if (cetak) {
        await _cetak(data, lapor: true);

        if (!mounted) return;

        Navigator.of(context).pop(true);
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Struk tersimpan',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            'Struk nomor ${data['no_trans']} sudah tersimpan di Arsip '
            '(id $id) dan tetap ada walaupun aplikasi ditutup.',
            style: const TextStyle(fontSize: 13.5, height: 1.45),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('TUTUP'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                unawaited(_cetak(data, lapor: true));
              },
              child: const Text('CETAK'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;

      setState(() => _menyimpan = false);
      rtsKsPesan(context, 'Struk gagal disimpan: $e', galat: true);
    }
  }

  Future<void> _cetak(
    Map<String, dynamic> data, {
    bool lapor = true,
  }) async {
    final Map<String, dynamic>? format = _formatPilih;

    if (format == null) {
      if (lapor && mounted) {
        rtsKsPesan(context, 'Template struk belum ada.', galat: true);
      }

      return;
    }

    final String galat = await RtsPomCetak.cetak(data, format);

    if (!mounted) return;

    if (galat.isNotEmpty) {
      rtsKsPesan(context, galat, galat: true);
      return;
    }

    if (lapor) rtsKsPesan(context, 'Struk sudah dikirim ke printer.', galat: false);
  }

  Future<void> _pratinjau() async {
    final Map<String, dynamic>? format = _formatPilih;

    if (format == null) return;

    final String logo = await RtsPomCetak.logoBaca();
    final List<String> teks = RtsPomCetak.pratinjau(
      _dataStruk(),
      format,
      adaLogo: logo.trim().isNotEmpty,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 6),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.description_outlined,
                        color: rtsKsMaroon, size: 19),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Pratinjau struk',
                        style: TextStyle(
                          color: rtsKsTeks,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('TUTUP'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      teks.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                        color: rtsKsTeks,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /* ------------------------------------------------------------- tampilan */

  @override
  Widget build(BuildContext context) {
    if (_memuat) {
      return const Scaffold(
        backgroundColor: rtsPomLatar,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: Text(widget.strukId > 0 ? 'Ubah Struk POM' : 'POM'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pratinjau',
            onPressed: () => unawaited(_pratinjau()),
            icon: const Icon(Icons.description_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          _kartuRingkas(),
          const SizedBox(height: 14),
          const _PomJudul('Petugas & Pompa'),
          const SizedBox(height: 8),
          _kartuPetugas(),
          const SizedBox(height: 14),
          const _PomJudul('Transaksi'),
          const SizedBox(height: 8),
          _kartuTransaksi(),
          const SizedBox(height: 14),
          const _PomJudul('Jumlah & Pembayaran'),
          const SizedBox(height: 8),
          _kartuBayar(),
          const SizedBox(height: 14),
          const _PomJudul('Catatan & Template'),
          const SizedBox(height: 8),
          _kartuCatatan(),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: rtsKsMaroon,
              minimumSize: const Size(0, 48),
            ),
            onPressed: _menyimpan ? null : () => unawaited(_simpan()),
            icon: const Icon(Icons.save_outlined, size: 19),
            label: const Text('SIMPAN'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: _menyimpan
                ? null
                : () => unawaited(_simpan(cetak: true)),
            icon: const Icon(Icons.print_outlined, size: 19),
            label: const Text('SIMPAN & CETAK'),
          ),
        ],
      ),
    );
  }

  Widget _kartuRingkas() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[rtsKsMaroon, rtsKsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'STRUK YANG SEDANG DIISI',
            style: TextStyle(
              color: Color(0xccffffff),
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _spbuTitle.trim().isEmpty ? 'SPBU belum diisi' : _spbuTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'No. Trans ${noTrans.text} - ${rtsKsWaktuLengkap(_waktu.toIso8601String())}',
            style: const TextStyle(color: Color(0xb3ffffff), fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            '$_namaBbm ${_hargaBbm > 0 ? '- Rp ${rtsKsUang(_hargaBbm)}/liter' : ''}',
            style: const TextStyle(color: Color(0xb3ffffff), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _kartuPetugas() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _PomIsian(
                  controller: shift,
                  label: 'Shift',
                  angka: true,
                  onUbah: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PomIsian(
                  controller: pompa,
                  label: 'Pompa',
                  angka: true,
                  onUbah: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PomIsian(
                  controller: selang,
                  label: 'Selang',
                  angka: true,
                  onUbah: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _PomPilihan<int>(
            label: 'Operator',
            nilai: _operatorNama.isEmpty ? null : _cariOperatorId(),
            pilihan: _operator
                .map((Map<String, dynamic> satu) => DropdownMenuItem<int>(
                      value: rtsKsBulat(satu['id']),
                      child: Text('${satu['nama']}'),
                    ))
                .toList(),
            kosong: 'Belum ada operator - tambah pada menu Operator',
            onPilih: (int? nilai) {
              if (nilai == null) return;

              setState(() {
                for (final Map<String, dynamic> satu in _operator) {
                  if (rtsKsBulat(satu['id']) == nilai) {
                    _operatorNama = '${satu['nama']}';
                  }
                }
              });
            },
          ),
          const SizedBox(height: 12),
          _PomPilihan<int>(
            label: 'Jenis BBM',
            nilai: _idSah(_bbm, _bbmId),
            pilihan: _bbm
                .map((Map<String, dynamic> satu) => DropdownMenuItem<int>(
                      value: rtsKsBulat(satu['id']),
                      child: Text(
                        '${satu['nama']} - Rp ${rtsKsUang(satu['harga'])}',
                      ),
                    ))
                .toList(),
            kosong: 'Belum ada BBM - tambah pada menu BBM',
            onPilih: (int? nilai) {
              if (nilai == null) return;

              setState(() {
                _pakaiBbm(nilai);
                _dariLiter();
                _dariBeli();
              });
            },
          ),
          const SizedBox(height: 12),
          _PomPilihan<int>(
            label: 'SPBU (header struk)',
            nilai: _idSah(_spbu, _spbuId),
            pilihan: _spbu
                .map((Map<String, dynamic> satu) => DropdownMenuItem<int>(
                      value: rtsKsBulat(satu['id']),
                      child: Text('${satu['title']}'),
                    ))
                .toList(),
            kosong: 'Belum ada SPBU - tambah pada menu SPBU',
            onPilih: (int? nilai) {
              if (nilai == null) return;

              setState(() => _pakaiSpbu(nilai));
            },
          ),
        ],
      ),
    );
  }

  int? _cariOperatorId() {
    for (final Map<String, dynamic> satu in _operator) {
      if ('${satu['nama']}' == _operatorNama) return rtsKsBulat(satu['id']);
    }

    return null;
  }

  Widget _kartuTransaksi() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _PomIsian(
                  controller: noTrans,
                  label: 'No. Trans',
                  angka: true,
                  onUbah: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pilihWaktu,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Waktu',
                      filled: true,
                      fillColor: const Color(0xfff8f4ef),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      labelStyle: const TextStyle(fontSize: 13.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    child: Text(
                      rtsKsWaktuLengkap(_waktu.toIso8601String()),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _PomIsian(
                  controller: odo,
                  label: 'Odo/No. HP',
                  hint: 'Contoh: 26572',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PomIsian(
                  controller: plat,
                  label: 'Plat Nomor',
                  hint: 'BK 1234 XX',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kartuBayar() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _PomIsian(
                  controller: jumlahBeli,
                  label: 'Jumlah Beli (Rp)',
                  hint: '0',
                  onUbah: (_) {
                    _dariBeli();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PomIsian(
                  controller: liter,
                  label: 'Liter',
                  hint: '0',
                  onUbah: (_) {
                    _dariLiter();
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _barisCepat(<String>[
            '10000',
            '15000',
            '20000',
            '25000',
          ], (String nilai) {
            jumlahBeli.text = rtsKsUang(nilai);
            _dariBeli();
            setState(() {});
          }, label: (String nilai) => 'Rp ${rtsKsUang(nilai)}'),
          _barisCepat(<String>['1', '2', '3', '4'], (String nilai) {
            liter.text = nilai;
            _dariLiter();
            setState(() {});
          }, label: (String nilai) => '$nilai Liter'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfff3efe9),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'TOTAL HARGA',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: rtsKsTeks,
                    ),
                  ),
                ),
                Text(
                  'Rp ${rtsKsUang(_total)}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: rtsKsMaroon,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _PomIsian(
                  controller: bayar,
                  label: 'Jumlah Bayar',
                  hint: '0',
                  onUbah: (_) {
                    _hitungKembali();
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _PomIsian(
                  controller: kembali,
                  label: 'Kembali',
                  hint: '0',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _barisCepat(<String>[
            '10000',
            '15000',
            '20000',
            '25000',
          ], (String nilai) {
            bayar.text = rtsKsUang(nilai);
            _hitungKembali();
            setState(() {});
          }, label: (String nilai) => 'Rp ${rtsKsUang(nilai)}'),
          const SizedBox(height: 6),
          Text(
            _hargaBbm <= 0
                ? 'Harga BBM masih Rp 0, jadi total belum dapat dihitung. Buka '
                    'menu BBM untuk mengisi harganya.'
                : 'Harga ${_namaBbm}: Rp ${rtsKsUang(_hargaBbm)}/liter',
            style: const TextStyle(fontSize: 11, color: rtsPomTeks2),
          ),
        ],
      ),
    );
  }

  Widget _barisCepat(
    List<String> nilai,
    void Function(String nilai) onTap, {
    required String Function(String nilai) label,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: nilai
            .map((String satu) => Padding(
                  padding: const EdgeInsets.only(right: 6, bottom: 4),
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      side: const BorderSide(color: rtsPomGaris),
                      foregroundColor: rtsKsTeks,
                    ),
                    onPressed: () => onTap(satu),
                    child: Text(label(satu), style: const TextStyle(fontSize: 11.5)),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _kartuCatatan() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PomIsian(
            controller: catatan,
            label: 'Catatan (tampil di bawah struk)',
            hint: 'Contoh: Mari gunakan Pertamax series',
            baris: 2,
          ),
          const SizedBox(height: 12),
          _PomPilihan<int>(
            label: 'Template struk',
            nilai: _idSah(_format, _formatId),
            pilihan: _format
                .map((Map<String, dynamic> satu) => DropdownMenuItem<int>(
                      value: rtsKsBulat(satu['id']),
                      child: Text(
                        '${satu['nama']} (${rtsKsBulat(satu['lebar_mm'])} mm)',
                      ),
                    ))
                .toList(),
            kosong: 'Template belum tersedia',
            onPilih: (int? nilai) {
              if (nilai == null) return;

              setState(() => _formatId = nilai);
            },
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* TINDAKAN BERSAMA UNTUK STRUK YANG SUDAH TERSIMPAN                         */
/* ------------------------------------------------------------------------- */

class _PomAksi {
  _PomAksi._();

  static Future<Map<String, dynamic>?> _formatDari(Map<String, dynamic> struk) async {
    final List<Map<String, dynamic>> daftar = await RtsPomLokal.aku.formatSemua();

    if (daftar.isEmpty) return null;

    final int id = rtsKsBulat(struk['format_id'] ?? 0);

    for (final Map<String, dynamic> satu in daftar) {
      if (rtsKsBulat(satu['id']) == id) return satu;
    }

    return daftar.first;
  }

  /// Mencetak struk dari arsip.
  static Future<void> cetak(BuildContext context, Map<String, dynamic> struk) async {
    final Map<String, dynamic>? format = await _formatDari(struk);

    if (format == null) {
      if (context.mounted) {
        rtsKsPesan(context, 'Template struk belum ada.', galat: true);
      }

      return;
    }

    final String galat = await RtsPomCetak.cetak(struk, format);

    if (!context.mounted) return;

    rtsKsPesan(
      context,
      galat.isEmpty ? 'Struk sudah dikirim ke printer.' : galat,
      galat: galat.isNotEmpty,
    );
  }

  /// Menyalin teks struk (untuk dikirim lewat WhatsApp dan lain-lain).
  static Future<void> salin(BuildContext context, Map<String, dynamic> struk) async {
    final Map<String, dynamic>? format = await _formatDari(struk);

    if (format == null) return;

    final String logo = await RtsPomCetak.logoBaca();

    await Clipboard.setData(
      ClipboardData(
        text: RtsPomCetak.teksSalin(
          struk,
          format,
          adaLogo: logo.trim().isNotEmpty,
        ),
      ),
    );

    if (!context.mounted) return;

    rtsKsPesan(context, 'Teks struk disalin. Tempel pada WhatsApp atau catatan.');
  }

  /// Membuka struk pada menu POM untuk diubah lalu dicetak kembali.
  static Future<void> ubah(BuildContext context, int id) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => RtsPomFormPage(strukId: id)),
    );
  }

  /// Menghapus struk dari arsip (dengan pertanyaan lebih dahulu).
  static Future<bool> hapus(BuildContext context, Map<String, dynamic> struk) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus struk ini?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Struk nomor ${struk['no_trans']} tanggal '
          '${rtsKsWaktuLengkap('${struk['waktu']}')} akan dihapus dari arsip '
          'di dalam HP. Tindakan ini tidak dapat dibatalkan.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (setuju != true) return false;

    await RtsPomLokal.aku.strukHapus(rtsKsBulat(struk['id']));

    return true;
  }

  /// Lembar pilihan tindakan untuk satu struk (dipakai Histori & Arsip).
  static Future<void> lembar(
    BuildContext context,
    Map<String, dynamic> struk,
    Future<void> Function() segarkan,
  ) async {
    final String? pilihan = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Text(
                'Struk ${struk['no_trans']} - ${rtsKsWaktuLengkap('${struk['waktu']}')}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: rtsKsTeks,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined, color: rtsKsMaroon),
              title: const Text('Cetak ke printer'),
              onTap: () => Navigator.of(ctx).pop('cetak'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: rtsKsMaroon),
              title: const Text('Buka & ubah'),
              onTap: () => Navigator.of(ctx).pop('ubah'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_all_rounded, color: rtsKsMaroon),
              title: const Text('Salin teks struk'),
              onTap: () => Navigator.of(ctx).pop('salin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: rtsKsMerah),
              title: const Text('Hapus dari arsip'),
              onTap: () => Navigator.of(ctx).pop('hapus'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (pilihan == null || !context.mounted) return;

    if (pilihan == 'cetak') {
      await cetak(context, struk);
    } else if (pilihan == 'ubah') {
      await ubah(context, rtsKsBulat(struk['id']));
      await segarkan();
    } else if (pilihan == 'salin') {
      await salin(context, struk);
    } else if (pilihan == 'hapus') {
      final bool terhapus = await hapus(context, struk);

      if (terhapus) await segarkan();
    }
  }
}

/// Kartu ringkas satu struk pada Histori dan Arsip.
class _PomStrukKartu extends StatelessWidget {
  const _PomStrukKartu({
    required this.struk,
    required this.onTap,
    required this.onMenu,
    this.nomor,
  });

  final Map<String, dynamic> struk;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  final String? nomor;

  @override
  Widget build(BuildContext context) {
    final double harga = rtsKsAngka(struk['bbm_harga']);
    final double liter = rtsKsAngka(struk['liter']);
    final double total = rtsKsAngka(struk['jumlah_beli']) > 0
        ? rtsKsAngka(struk['jumlah_beli'])
        : harga * liter;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: rtsPomGaris),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xfff3efe9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      nomor ?? '${struk['no_trans'] ?? '#'}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rtsKsMaroon,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${struk['spbu_title'] ?? 'SPBU'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: rtsKsTeks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${rtsKsWaktuLengkap('${struk['waktu']}')} - '
                        '${struk['bbm_nama'] ?? '-'}',
                        style: const TextStyle(fontSize: 11.5, color: rtsPomTeks2),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rp ${rtsKsUang(total)} - ${liter.toStringAsFixed(3)} L',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: rtsKsMaroon,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Tindakan',
                  onPressed: onMenu,
                  icon: const Icon(Icons.more_vert_rounded, color: rtsPomTeks2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU HISTORI - RIWAYAT PENGINPUTAN + SARING TANGGAL                       */
/* ------------------------------------------------------------------------- */

class RtsPomHistoriPage extends StatefulWidget {
  const RtsPomHistoriPage({super.key});

  @override
  State<RtsPomHistoriPage> createState() => _RtsPomHistoriPageState();
}

class _RtsPomHistoriPageState extends State<RtsPomHistoriPage> {
  final TextEditingController cari = TextEditingController();

  bool _memuat = true;
  String _dari = '';
  String _sampai = '';
  String _kunci = '';
  String _cepat = 'Semua';

  List<Map<String, dynamic>> _struk = <Map<String, dynamic>>[];
  Map<String, double> _ringkas = <String, double>{
    'jumlah': 0,
    'rupiah': 0,
    'liter': 0,
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  @override
  void dispose() {
    cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() => _memuat = true);

    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar = await RtsPomLokal.aku.strukSemua(
      dari: _dari,
      sampai: _sampai,
      cari: _kunci,
    );

    final Map<String, double> ringkas =
        await RtsPomLokal.aku.ringkasan(dari: _dari, sampai: _sampai);

    if (!mounted) return;

    setState(() {
      _struk = daftar;
      _ringkas = ringkas;
      _memuat = false;
    });
  }

  String _tanggalKeTeks(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  Future<void> _pilihTanggal({required bool awal}) async {
    final DateTime mulai = DateTime.now();

    final DateTime? pilih = await showDatePicker(
      context: context,
      initialDate: mulai,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: awal ? 'Pilih tanggal MULAI' : 'Pilih tanggal AKHIR',
    );

    if (pilih == null || !mounted) return;

    setState(() {
      _cepat = 'Pilih sendiri';

      if (awal) {
        _dari = _tanggalKeTeks(pilih);
      } else {
        _sampai = _tanggalKeTeks(pilih);
      }
    });

    await _muat();
  }

  void _pakaiCepat(String pilihan) {
    final DateTime sekarang = DateTime.now();

    setState(() {
      _cepat = pilihan;

      if (pilihan == 'Semua') {
        _dari = '';
        _sampai = '';
      } else if (pilihan == 'Hari ini') {
        _dari = _tanggalKeTeks(sekarang);
        _sampai = _dari;
      } else if (pilihan == '7 hari') {
        _dari = _tanggalKeTeks(sekarang.subtract(const Duration(days: 6)));
        _sampai = _tanggalKeTeks(sekarang);
      } else if (pilihan == '30 hari') {
        _dari = _tanggalKeTeks(sekarang.subtract(const Duration(days: 29)));
        _sampai = _tanggalKeTeks(sekarang);
      }
    });

    unawaited(_muat());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Histori Struk POM'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Segarkan',
            onPressed: _memuat ? null : () => unawaited(_muat()),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                _ringkasan(),
                const SizedBox(height: 14),
                const _PomJudul('Saring tanggal'),
                const SizedBox(height: 8),
                _kartuSaring(),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    const Expanded(child: _PomJudul('Daftar struk')),
                    Text(
                      '${_struk.length} struk',
                      style: const TextStyle(fontSize: 11.5, color: rtsPomTeks2),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_struk.isEmpty)
                  _PomKartu(
                    child: Text(
                      'Belum ada struk pada rentang tanggal itu. Tekan menu POM '
                      'untuk membuat struk baru, atau ubah penyaring tanggal.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: rtsPomTeks2,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  for (final Map<String, dynamic> satu in _struk)
                    _PomStrukKartu(
                      struk: satu,
                      onTap: () {
                        unawaited(
                          _PomAksi.ubah(context, rtsKsBulat(satu['id']))
                              .then((_) => _muat()),
                        );
                      },
                      onMenu: () => unawaited(_PomAksi.lembar(context, satu, _muat)),
                    ),
              ],
            ),
    );
  }

  Widget _ringkasan() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[rtsKsMaroon, rtsKsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _angka('${_ringkas['jumlah']?.round() ?? 0}', 'STRUK'),
          ),
          Expanded(
            child: _angka('Rp ${rtsKsUang(_ringkas['rupiah'])}', 'NILAI'),
          ),
          Expanded(
            child: _angka(
              '${(_ringkas['liter'] ?? 0).toStringAsFixed(2)} L',
              'VOLUME',
            ),
          ),
        ],
      ),
    );
  }

  Widget _angka(String nilai, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(
            color: Color(0xccffffff),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          nilai,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _kartuSaring() {
    return _PomKartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <String>['Semua', 'Hari ini', '7 hari', '30 hari']
                  .map((String satu) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            satu,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: _cepat == satu ? Colors.white : rtsKsTeks,
                            ),
                          ),
                          selected: _cepat == satu,
                          onSelected: (_) => _pakaiCepat(satu),
                          selectedColor: rtsKsMaroon,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _cepat == satu ? rtsKsMaroon : rtsPomGaris,
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_pilihTanggal(awal: true)),
                  icon: const Icon(Icons.event_rounded, size: 17),
                  label: Text(
                    _dari.isEmpty ? 'DARI' : rtsKsTanggal(_dari),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_pilihTanggal(awal: false)),
                  icon: const Icon(Icons.event_available_rounded, size: 17),
                  label: Text(
                    _sampai.isEmpty ? 'SAMPAI' : rtsKsTanggal(_sampai),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ),
          if (_dari.isNotEmpty || _sampai.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Menampilkan struk ${_dari.isEmpty ? 'dari awal' : 'mulai '
                    '${rtsKsTanggal(_dari)}'} '
                '${_sampai.isEmpty ? 'sampai sekarang' : 'sampai '
                    '${rtsKsTanggal(_sampai)}'}.',
                style: const TextStyle(fontSize: 11, color: rtsPomTeks2),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: cari,
            onSubmitted: (String nilai) {
              _kunci = nilai;
              unawaited(_muat());
            },
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Cari SPBU / plat / no. trans',
              hintStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded,
                  color: Color(0xff6d514a), size: 20),
              filled: true,
              fillColor: const Color(0xfff8f4ef),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU ARSIP - KUMPULAN STRUK YANG SUDAH DIBUAT                             */
/* ------------------------------------------------------------------------- */

class RtsPomArsipPage extends StatefulWidget {
  const RtsPomArsipPage({super.key});

  @override
  State<RtsPomArsipPage> createState() => _RtsPomArsipPageState();
}

class _RtsPomArsipPageState extends State<RtsPomArsipPage> {
  final TextEditingController cari = TextEditingController();

  bool _memuat = true;
  String _kunci = '';
  List<Map<String, dynamic>> _struk = <Map<String, dynamic>>[];
  Map<String, double> _ringkas = <String, double>{
    'jumlah': 0,
    'rupiah': 0,
    'liter': 0,
  };

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  @override
  void dispose() {
    cari.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    setState(() => _memuat = true);

    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar =
        await RtsPomLokal.aku.strukSemua(cari: _kunci, batas: 500);
    final Map<String, double> ringkas = await RtsPomLokal.aku.ringkasan();

    if (!mounted) return;

    setState(() {
      _struk = daftar;
      _ringkas = ringkas;
      _memuat = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Arsip Struk POM'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () async {
          await Navigator.of(context).push<bool>(
            MaterialPageRoute<bool>(builder: (_) => const RtsPomFormPage()),
          );

          await _muat();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('STRUK BARU'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              children: <Widget>[
                _PomKartu(
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.folder_copy_outlined,
                          color: rtsKsMaroon, size: 20),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          '${_ringkas['jumlah']?.round() ?? 0} struk tersimpan '
                          '- Rp ${rtsKsUang(_ringkas['rupiah'])} - '
                          '${(_ringkas['liter'] ?? 0).toStringAsFixed(2)} L',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: rtsKsTeks,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: cari,
                  onSubmitted: (String nilai) {
                    _kunci = nilai;
                    unawaited(_muat());
                  },
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Cari SPBU / plat / no. trans',
                    hintStyle: const TextStyle(fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xff6d514a), size: 20),
                    suffixIcon: IconButton(
                      tooltip: 'Cari',
                      onPressed: () {
                        _kunci = cari.text;
                        unawaited(_muat());
                      },
                      icon: const Icon(Icons.tune_rounded, size: 20),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (_struk.isEmpty)
                  _PomKartu(
                    child: Text(
                      _kunci.isEmpty
                          ? 'Arsip masih kosong. Tekan tombol STRUK BARU di '
                              'bawah untuk membuat struk POM pertama.'
                          : 'Tidak ada struk yang cocok dengan pencarian "$_kunci".',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: rtsPomTeks2,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  for (final Map<String, dynamic> satu in _struk)
                    _PomStrukKartu(
                      struk: satu,
                      onTap: () async {
                        await _PomAksi.ubah(context, rtsKsBulat(satu['id']));
                        await _muat();
                      },
                      onMenu: () => unawaited(_PomAksi.lembar(context, satu, _muat)),
                    ),
              ],
            ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU STRUK - TEMPLATE (HEADER, ISI, FOOTER)                               */
/* ------------------------------------------------------------------------- */

class RtsPomStrukPage extends StatefulWidget {
  const RtsPomStrukPage({super.key});

  @override
  State<RtsPomStrukPage> createState() => _RtsPomStrukPageState();
}

class _RtsPomStrukPageState extends State<RtsPomStrukPage> {
  bool _memuat = true;
  String _logo = '';
  List<Map<String, dynamic>> _format = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar = await RtsPomLokal.aku.formatSemua();
    final String logo = await RtsPomCetak.logoBaca();

    if (!mounted) return;

    setState(() {
      _format = daftar;
      _logo = logo;
      _memuat = false;
    });
  }

  Future<void> _pilihLogo() async {
    try {
      final String jalur = await RtsPomCetak.logoSimpanDariGaleri();

      if (jalur.isEmpty) return;

      await _muat();

      if (!mounted) return;

      rtsKsPesan(context, 'Gambar header sudah diganti.');
    } catch (e) {
      if (!mounted) return;

      rtsKsPesan(
        context,
        'Gambar tidak dapat dibuka. Periksa izin Galeri pada Pengaturan HP '
        '($e)',
        galat: true,
      );
    }
  }

  Future<void> _hapusLogo() async {
    await RtsPomCetak.logoTulis('');

    await _muat();

    if (!mounted) return;

    rtsKsPesan(context, 'Gambar header dihapus (struk dicetak tanpa gambar).');
  }

  Future<void> _ujiCetak() async {
    if (_format.isEmpty) return;

    final Map<String, dynamic> contoh = <String, dynamic>{
      'spbu_title': 'UJI CETAK STRUK POM',
      'spbu_subtitle': 'RTS Panel - contoh header',
      'spbu_footer': 'UJI CETAK - abaikan struk ini',
      'operator': 'OPERATOR',
      'bbm_nama': 'PERTALITE',
      'bbm_harga': 10000,
      'bbm_subsidi': 0,
      'shift': '1',
      'pompa': '1',
      'selang': '1',
      'no_trans': '0',
      'waktu': DateTime.now().toIso8601String(),
      'plat': 'BK 1234 XX',
      'odo': '0',
      'liter': 1,
      'jumlah_bayar': 10000,
      'kembali': 0,
      'catatan': 'Contoh cetak dari menu Struk.',
    };

    final String galat = await RtsPomCetak.cetak(contoh, _format.first);

    if (!mounted) return;

    rtsKsPesan(
      context,
      galat.isEmpty ? 'Uji cetak terkirim ke printer.' : galat,
      galat: galat.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Template Struk'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Uji cetak',
            onPressed: _memuat ? null : () => unawaited(_ujiCetak()),
            icon: const Icon(Icons.print_outlined),
          ),
        ],
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: <Widget>[
                const _PomJudul('Gambar header struk'),
                const SizedBox(height: 8),
                _PomKartu(
                  child: Column(
                    children: <Widget>[
                      if (_logo.isNotEmpty && File(_logo).existsSync())
                        Container(
                          height: 120,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xfff3efe9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Image.file(
                              File(_logo),
                              height: 100,
                              fit: BoxFit.contain,
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 90,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xfff3efe9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Center(
                            child: Text(
                              'Belum ada gambar header',
                              style: TextStyle(fontSize: 12.5, color: rtsPomTeks2),
                            ),
                          ),
                        ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: rtsKsMaroon,
                              ),
                              onPressed: () => unawaited(_pilihLogo()),
                              icon: const Icon(Icons.image_outlined, size: 18),
                              label: const Text('PILIH DARI GALERI'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            onPressed: _logo.isEmpty
                                ? null
                                : () => unawaited(_hapusLogo()),
                            child: const Text('HAPUS'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Gambar ini dipakai sebagai KEPALA struk (misalnya logo '
                        'SPBU / Pertamina). Pilih dari galeri HP; gambar '
                        'disimpan di dalam HP sehingga tetap ada walau berkas '
                        'aslinya dihapus. Struk POM tidak memakai logo RTS '
                        'Panel.',
                        style: TextStyle(
                          fontSize: 11,
                          color: rtsPomTeks2,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _PomJudul('Daftar template struk'),
                const SizedBox(height: 8),
                for (final Map<String, dynamic> satu in _format)
                  _kartuFormat(satu),
                const SizedBox(height: 10),
                const Text(
                  'Ketuk satu template untuk mengubah nama, ukuran kertas '
                  '(58/80 mm), gambar header, tulisan tambahan di atas dan di '
                  'bawah struk, serta jumlah salinan. Bagian ISI struk diambil '
                  'dari menu POM, sedangkan nama & alamat SPBU diambil dari '
                  'menu SPBU.',
                  style: TextStyle(fontSize: 11.5, color: rtsPomTeks2, height: 1.5),
                ),
              ],
            ),
    );
  }

  Widget _kartuFormat(Map<String, dynamic> format) {
    final bool pakaiLogo = rtsKsBulat(format['pakai_logo'] ?? 1) != 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () async {
            await Navigator.of(context).push<bool>(
              MaterialPageRoute<bool>(
                builder: (_) => RtsPomFormatPage(format: format),
              ),
            );

            await _muat();
          },
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: rtsPomGaris),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xfffaecee),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    pakaiLogo
                        ? Icons.image_rounded
                        : Icons.text_fields_rounded,
                    color: rtsKsMaroon,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${format['nama']}',
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: rtsKsTeks,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${rtsKsBulat(format['lebar_mm'])} mm - '
                        '${pakaiLogo ? 'pakai gambar' : 'tanpa gambar'} - '
                        'salinan ${rtsKsBulat(format['jumlah_salinan'] ?? 1)}',
                        style: const TextStyle(fontSize: 11.5, color: rtsPomTeks2),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: rtsPomTeks2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Halaman pengubah satu template struk.
class RtsPomFormatPage extends StatefulWidget {
  const RtsPomFormatPage({super.key, required this.format});

  final Map<String, dynamic> format;

  @override
  State<RtsPomFormatPage> createState() => _RtsPomFormatPageState();
}

class _RtsPomFormatPageState extends State<RtsPomFormatPage> {
  late final TextEditingController nama =
      TextEditingController(text: '${widget.format['nama'] ?? ''}');
  late final TextEditingController header = TextEditingController(
    text: '${widget.format['header_tambahan'] ?? ''}',
  );
  late final TextEditingController footer = TextEditingController(
    text: '${widget.format['footer_tambahan'] ?? ''}',
  );
  late final TextEditingController salinan = TextEditingController(
    text: '${rtsKsBulat(widget.format['jumlah_salinan'] ?? 1)}',
  );

  late int lebar = rtsKsBulat(widget.format['lebar_mm'] ?? 58);
  late bool pakaiLogo = rtsKsBulat(widget.format['pakai_logo'] ?? 1) != 0;
  late bool pakaiSubsidi = rtsKsBulat(widget.format['pakai_subsidi'] ?? 1) != 0;
  late bool pakaiGaris = rtsKsBulat(widget.format['pakai_garis'] ?? 1) != 0;

  bool _menyimpan = false;

  @override
  void dispose() {
    nama.dispose();
    header.dispose();
    footer.dispose();
    salinan.dispose();
    super.dispose();
  }

  Map<String, dynamic> _formatBaru() {
    return <String, dynamic>{
      'id': widget.format['id'],
      'nama': nama.text.trim().isEmpty ? 'Format' : nama.text.trim(),
      'lebar_mm': lebar,
      'pakai_logo': pakaiLogo ? 1 : 0,
      'pakai_subsidi': pakaiSubsidi ? 1 : 0,
      'pakai_garis': pakaiGaris ? 1 : 0,
      'jumlah_salinan': rtsPomAngka(salinan.text).round() < 1
          ? 1
          : rtsPomAngka(salinan.text).round(),
      'header_tambahan': header.text,
      'footer_tambahan': footer.text,
    };
  }

  Future<void> _simpan() async {
    setState(() => _menyimpan = true);

    await RtsPomLokal.aku.formatUbah(_formatBaru());

    if (!mounted) return;

    setState(() => _menyimpan = false);

    rtsKsPesan(context, 'Template struk disimpan.');
    Navigator.of(context).pop(true);
  }

  Future<void> _pratinjau() async {
    final List<Map<String, dynamic>> spbu = await RtsPomLokal.aku.spbuSemua();
    final List<Map<String, dynamic>> bbm = await RtsPomLokal.aku.bbmSemua();
    final String logo = await RtsPomCetak.logoBaca();

    final Map<String, dynamic> contoh = <String, dynamic>{
      'spbu_title': spbu.isEmpty ? 'NAMA SPBU' : '${spbu.first['title']}',
      'spbu_subtitle': spbu.isEmpty ? 'Alamat SPBU' : '${spbu.first['subtitle']}',
      'spbu_footer': spbu.isEmpty ? '' : '${spbu.first['footer']}',
      'operator': 'OPERATOR',
      'bbm_nama': bbm.isEmpty ? 'PERTALITE' : '${bbm.first['nama']}',
      'bbm_harga': bbm.isEmpty ? 10000 : bbm.first['harga'],
      'bbm_subsidi': bbm.isEmpty ? 0 : bbm.first['subsidi'],
      'shift': '1',
      'pompa': '1',
      'selang': '1',
      'no_trans': '1',
      'waktu': DateTime.now().toIso8601String(),
      'plat': 'BK 1234 XX',
      'odo': '0',
      'liter': 1,
      'jumlah_bayar': 10000,
      'kembali': 0,
      'catatan': '',
    };

    final List<String> teks = RtsPomCetak.pratinjau(
      contoh,
      _formatBaru(),
      adaLogo: logo.trim().isNotEmpty,
    );

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.7,
          child: Column(
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Text(
                  'Pratinjau template',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: rtsKsTeks,
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Text(
                      teks.join('\n'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.35,
                        color: rtsKsTeks,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ujiCetak() async {
    final List<Map<String, dynamic>> bbm = await RtsPomLokal.aku.bbmSemua();

    final Map<String, dynamic> contoh = <String, dynamic>{
      'spbu_title': 'UJI CETAK',
      'spbu_subtitle': 'Template ${nama.text}',
      'spbu_footer': 'UJI CETAK - abaikan struk ini',
      'operator': 'OPERATOR',
      'bbm_nama': bbm.isEmpty ? 'PERTALITE' : '${bbm.first['nama']}',
      'bbm_harga': bbm.isEmpty ? 10000 : bbm.first['harga'],
      'bbm_subsidi': bbm.isEmpty ? 0 : bbm.first['subsidi'],
      'shift': '1',
      'pompa': '1',
      'selang': '1',
      'no_trans': '0',
      'waktu': DateTime.now().toIso8601String(),
      'plat': 'BK 1234 XX',
      'odo': '0',
      'liter': 1,
      'jumlah_bayar': 10000,
      'kembali': 0,
      'catatan': '',
    };

    final String galat = await RtsPomCetak.cetak(contoh, _formatBaru());

    if (!mounted) return;

    rtsKsPesan(
      context,
      galat.isEmpty ? 'Uji cetak terkirim ke printer.' : galat,
      galat: galat.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Ubah Template'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pratinjau',
            onPressed: () => unawaited(_pratinjau()),
            icon: const Icon(Icons.description_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          const _PomJudul('Nama & ukuran'),
          const SizedBox(height: 8),
          _PomKartu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PomIsian(controller: nama, label: 'Nama template'),
                const SizedBox(height: 12),
                const Text(
                  'Ukuran kertas',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: rtsPomTeks2,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (final int mm in <int>[58, 80])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            '$mm mm',
                            style: TextStyle(
                              fontSize: 12,
                              color: lebar == mm ? Colors.white : rtsKsTeks,
                            ),
                          ),
                          selected: lebar == mm,
                          onSelected: (_) => setState(() => lebar = mm),
                          selectedColor: rtsKsMaroon,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: lebar == mm ? rtsKsMaroon : rtsPomGaris,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        '${RtsPomCetak.lebarKarakter(lebar)} karakter per baris',
                        style: const TextStyle(fontSize: 11, color: rtsPomTeks2),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _PomIsian(
                  controller: salinan,
                  label: 'Jumlah salinan',
                  angka: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _PomJudul('Isi struk'),
          const SizedBox(height: 8),
          _PomKartu(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pakaiLogo,
                  onChanged: (bool nilai) => setState(() => pakaiLogo = nilai),
                  title: const Text(
                    'Pakai gambar header',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Gambar dipilih pada halaman Template Struk.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pakaiSubsidi,
                  onChanged: (bool nilai) => setState(() => pakaiSubsidi = nilai),
                  title: const Text(
                    'Tampilkan subsidi BBM',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Baris subsidi muncul bila nilainya lebih dari nol.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
                const Divider(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pakaiGaris,
                  onChanged: (bool nilai) => setState(() => pakaiGaris = nilai),
                  title: const Text(
                    'Garis pemisah',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Garis putus-putus di antara bagian struk.',
                    style: TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _PomJudul('Tulisan tambahan'),
          const SizedBox(height: 8),
          _PomKartu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PomIsian(
                  controller: header,
                  label: 'Tambahan di ATAS struk',
                  hint: 'Contoh: SPBU 14.201.194',
                  baris: 2,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ditulis di bawah nama SPBU. Tekan enter untuk baris baru.',
                  style: TextStyle(fontSize: 11, color: rtsPomTeks2),
                ),
                const SizedBox(height: 12),
                _PomIsian(
                  controller: footer,
                  label: 'Tambahan di BAWAH struk',
                  hint: 'Contoh: Terima kasih - selamat jalan',
                  baris: 2,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Ditulis paling bawah, di bawah tulisan footer SPBU.',
                  style: TextStyle(fontSize: 11, color: rtsPomTeks2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: rtsKsMaroon,
              minimumSize: const Size(0, 48),
            ),
            onPressed: _menyimpan ? null : () => unawaited(_simpan()),
            icon: const Icon(Icons.save_outlined, size: 19),
            label: const Text('SIMPAN TEMPLATE'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            onPressed: () => unawaited(_ujiCetak()),
            icon: const Icon(Icons.print_outlined, size: 19),
            label: const Text('UJI CETAK TEMPLATE INI'),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU OPERATOR - DAFTAR NAMA OPERATOR                                      */
/* ------------------------------------------------------------------------- */

class RtsPomOperatorPage extends StatefulWidget {
  const RtsPomOperatorPage({super.key});

  @override
  State<RtsPomOperatorPage> createState() => _RtsPomOperatorPageState();
}

class _RtsPomOperatorPageState extends State<RtsPomOperatorPage> {
  bool _memuat = true;
  List<Map<String, dynamic>> _daftar = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar =
        await RtsPomLokal.aku.operatorSemua();

    if (!mounted) return;

    setState(() {
      _daftar = daftar;
      _memuat = false;
    });
  }

  Future<void> _ubah([Map<String, dynamic>? lama]) async {
    final TextEditingController nama =
        TextEditingController(text: '${lama?['nama'] ?? ''}');
    final TextEditingController keterangan =
        TextEditingController(text: '${lama?['keterangan'] ?? ''}');

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          lama == null ? 'Tambah Operator' : 'Edit Operator',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nama,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Nama'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: keterangan,
              decoration: const InputDecoration(
                labelText: 'Keterangan (Opsional)',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (simpan != true) {
      nama.dispose();
      keterangan.dispose();
      return;
    }

    if (nama.text.trim().isEmpty) {
      nama.dispose();
      keterangan.dispose();

      if (!mounted) return;

      rtsKsPesan(context, 'Nama operator wajib diisi.', galat: true);
      return;
    }

    await RtsPomLokal.aku.operatorSimpan(<String, dynamic>{
      'id': lama == null ? 0 : rtsKsBulat(lama['id']),
      'nama': nama.text.trim(),
      'keterangan': keterangan.text.trim(),
      'urutan': lama == null ? _daftar.length : rtsKsBulat(lama['urutan']),
    });

    nama.dispose();
    keterangan.dispose();

    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> data) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus operator?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Nama "${data['nama']}" akan dihapus dari daftar. Struk yang sudah '
          'dibuat tidak berubah karena nama operator disimpan pada setiap '
          'struk.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    await RtsPomLokal.aku.operatorHapus(rtsKsBulat(data['id']));

    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Operator'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => unawaited(_ubah()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('TAMBAH'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              children: <Widget>[
                const Text(
                  'Nama pada daftar ini muncul sebagai pilihan OPERATOR pada '
                  'menu POM.',
                  style: TextStyle(fontSize: 12, color: rtsPomTeks2, height: 1.45),
                ),
                const SizedBox(height: 12),
                if (_daftar.isEmpty)
                  _PomKartu(
                    child: Text(
                      'Belum ada operator. Tekan tombol TAMBAH di bawah.',
                      style: const TextStyle(fontSize: 12.5, color: rtsPomTeks2),
                    ),
                  )
                else
                  for (final Map<String, dynamic> satu in _daftar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PomKartu(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xfff3efe9),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(Icons.person_outline_rounded,
                                  color: rtsKsMaroon, size: 20),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${satu['nama']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: rtsKsTeks,
                                    ),
                                  ),
                                  if ('${satu['keterangan'] ?? ''}'.trim().isNotEmpty)
                                    Text(
                                      '${satu['keterangan']}',
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: rtsPomTeks2,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ubah',
                              onPressed: () => unawaited(_ubah(satu)),
                              icon: const Icon(Icons.edit_outlined,
                                  color: rtsKsMaroon, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              onPressed: () => unawaited(_hapus(satu)),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: rtsKsMerah, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU BBM - HARGA DAN SUBSIDI                                              */
/* ------------------------------------------------------------------------- */

class RtsPomBbmPage extends StatefulWidget {
  const RtsPomBbmPage({super.key});

  @override
  State<RtsPomBbmPage> createState() => _RtsPomBbmPageState();
}

class _RtsPomBbmPageState extends State<RtsPomBbmPage> {
  bool _memuat = true;
  List<Map<String, dynamic>> _daftar = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_muat());
    });
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar = await RtsPomLokal.aku.bbmSemua();

    if (!mounted) return;

    setState(() {
      _daftar = daftar;
      _memuat = false;
    });
  }

  Future<void> _ubah([Map<String, dynamic>? lama]) async {
    final TextEditingController nama =
        TextEditingController(text: '${lama?['nama'] ?? ''}');
    final TextEditingController harga = TextEditingController(
      text: lama == null ? '' : rtsKsUang(lama['harga']),
    );
    final TextEditingController subsidi = TextEditingController(
      text: (lama == null || rtsKsAngka(lama['subsidi']) <= 0)
          ? ''
          : rtsKsUang(lama['subsidi']),
    );

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          lama == null ? 'Tambah BBM' : 'Edit BBM',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: nama,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nama'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: harga,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Harga'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: subsidi,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Subsidi (Opsional)',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (simpan != true) {
      nama.dispose();
      harga.dispose();
      subsidi.dispose();
      return;
    }

    if (nama.text.trim().isEmpty) {
      nama.dispose();
      harga.dispose();
      subsidi.dispose();

      if (!mounted) return;

      rtsKsPesan(context, 'Nama BBM wajib diisi.', galat: true);
      return;
    }

    await RtsPomLokal.aku.bbmSimpan(<String, dynamic>{
      'id': lama == null ? 0 : rtsKsBulat(lama['id']),
      'nama': nama.text.trim(),
      'harga': rtsPomAngka(harga.text),
      'subsidi': rtsPomAngka(subsidi.text),
      'urutan': lama == null ? _daftar.length : rtsKsBulat(lama['urutan']),
    });

    nama.dispose();
    harga.dispose();
    subsidi.dispose();

    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> data) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus BBM?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '"${data['nama']}" akan dihapus dari daftar pilihan pada menu POM. '
          'Struk yang sudah dibuat tidak berubah.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    await RtsPomLokal.aku.bbmHapus(rtsKsBulat(data['id']));

    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('BBM'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => unawaited(_ubah()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('TAMBAH'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              children: <Widget>[
                const Text(
                  'Harga di sini dipakai untuk menghitung TOTAL HARGA pada menu '
                  'POM. Subsidi dituliskan pada struk bila lebih dari nol.',
                  style: TextStyle(fontSize: 12, color: rtsPomTeks2, height: 1.45),
                ),
                const SizedBox(height: 12),
                if (_daftar.isEmpty)
                  _PomKartu(
                    child: Text(
                      'Belum ada BBM. Tekan tombol TAMBAH di bawah.',
                      style: const TextStyle(fontSize: 12.5, color: rtsPomTeks2),
                    ),
                  )
                else
                  for (final Map<String, dynamic> satu in _daftar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PomKartu(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xffe8f0f8),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: Center(
                                child: Text(
                                  '${satu['nama']}'.isEmpty
                                      ? 'B'
                                      : '${satu['nama']}'[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: rtsPomBiru,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${satu['nama']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: rtsKsTeks,
                                    ),
                                  ),
                                  Text(
                                    'Rp ${rtsKsUang(satu['harga'])}'
                                    '${rtsKsAngka(satu['subsidi']) > 0 ? ' - Subsidi Rp ${rtsKsUang(satu['subsidi'])}' : ''}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: rtsPomTeks2,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ubah',
                              onPressed: () => unawaited(_ubah(satu)),
                              icon: const Icon(Icons.edit_outlined,
                                  color: rtsKsMaroon, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              onPressed: () => unawaited(_hapus(satu)),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: rtsKsMerah, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MENU SPBU - HEADER DAN FOOTER STRUK                                       */
/* ------------------------------------------------------------------------- */

class RtsPomSpbuPage extends StatefulWidget {
  const RtsPomSpbuPage({super.key});

  @override
  State<RtsPomSpbuPage> createState() => _RtsPomSpbuPageState();
}

class _RtsPomSpbuPageState extends State<RtsPomSpbuPage> {
  bool _memuat = true;
  List<Map<String, dynamic>> _daftar = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_memuat && mounted) unawaited(_muat());
    });
  }

  Future<void> _muat() async {
    await RtsPomLokal.aku.siapkan();

    final List<Map<String, dynamic>> daftar = await RtsPomLokal.aku.spbuSemua();

    if (!mounted) return;

    setState(() {
      _daftar = daftar;
      _memuat = false;
    });
  }

  Future<void> _ubah([Map<String, dynamic>? lama]) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _RtsPomSpbuFormPage(spbu: lama),
      ),
    );

    await _muat();
  }

  Future<void> _hapus(Map<String, dynamic> data) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus SPBU?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          '"${data['title']}" akan dihapus dari daftar. Struk yang sudah dibuat '
          'tidak berubah karena nama SPBU disimpan pada setiap struk.',
          style: const TextStyle(fontSize: 13.5, height: 1.45),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    await RtsPomLokal.aku.spbuHapus(rtsKsBulat(data['id']));

    await _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('SPBU'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => unawaited(_ubah()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('TAMBAH'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 90),
              children: <Widget>[
                const Text(
                  'Title dan Subtitle menjadi KEPALA struk (di bawah gambar '
                  'header). Footer menjadi tulisan paling bawah pada struk.',
                  style: TextStyle(fontSize: 12, color: rtsPomTeks2, height: 1.45),
                ),
                const SizedBox(height: 12),
                if (_daftar.isEmpty)
                  _PomKartu(
                    child: Text(
                      'Belum ada SPBU. Tekan tombol TAMBAH di bawah untuk mengisi '
                      'nomor SPBU, nama, dan alamatnya.',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: rtsPomTeks2,
                        height: 1.45,
                      ),
                    ),
                  )
                else
                  for (final Map<String, dynamic> satu in _daftar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PomKartu(
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: <Widget>[
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xfffaecee),
                                borderRadius: BorderRadius.circular(11),
                              ),
                              child: const Icon(
                                Icons.store_mall_directory_outlined,
                                color: rtsKsMaroon,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    '${satu['title']}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: rtsKsTeks,
                                    ),
                                  ),
                                  if ('${satu['subtitle'] ?? ''}'.trim().isNotEmpty)
                                    Text(
                                      '${satu['subtitle']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: rtsPomTeks2,
                                      ),
                                    ),
                                  if ('${satu['footer'] ?? ''}'.trim().isNotEmpty)
                                    Text(
                                      'Footer: ${satu['footer']}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: rtsPomTeks2,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ubah',
                              onPressed: () => unawaited(_ubah(satu)),
                              icon: const Icon(Icons.edit_outlined,
                                  color: rtsKsMaroon, size: 20),
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              onPressed: () => unawaited(_hapus(satu)),
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: rtsKsMerah, size: 20),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Formulir tambah / ubah data SPBU (Title, Subtitle, Footer).
class _RtsPomSpbuFormPage extends StatefulWidget {
  const _RtsPomSpbuFormPage({this.spbu});

  final Map<String, dynamic>? spbu;

  @override
  State<_RtsPomSpbuFormPage> createState() => _RtsPomSpbuFormPageState();
}

class _RtsPomSpbuFormPageState extends State<_RtsPomSpbuFormPage> {
  late final TextEditingController title =
      TextEditingController(text: '${widget.spbu?['title'] ?? ''}');
  late final TextEditingController subtitle =
      TextEditingController(text: '${widget.spbu?['subtitle'] ?? ''}');
  late final TextEditingController footer =
      TextEditingController(text: '${widget.spbu?['footer'] ?? ''}');

  bool _menyimpan = false;

  @override
  void dispose() {
    title.dispose();
    subtitle.dispose();
    footer.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    if (title.text.trim().isEmpty) {
      rtsKsPesan(context, 'Title (nomor / nama SPBU) wajib diisi.', galat: true);
      return;
    }

    setState(() => _menyimpan = true);

    await RtsPomLokal.aku.spbuSimpan(<String, dynamic>{
      'id': widget.spbu == null ? 0 : rtsKsBulat(widget.spbu!['id']),
      'title': title.text.trim(),
      'subtitle': subtitle.text.trim(),
      'footer': footer.text.trim(),
      'urutan': widget.spbu == null ? 0 : rtsKsBulat(widget.spbu!['urutan']),
    });

    if (!mounted) return;

    setState(() => _menyimpan = false);

    rtsKsPesan(context, 'Data SPBU disimpan.');
    Navigator.of(context).pop(true);
  }

  /// Hitungan panjang baris: 58 mm paling banyak 32 karakter, 80 mm 42.
  Widget _petunjuk(TextEditingController pengendali, int maks) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: pengendali,
      builder: (BuildContext context, TextEditingValue nilai, Widget? child) {
        final List<String> baris = nilai.text.split('\n');
        final int terpanjang = baris.isEmpty
            ? 0
            : baris.map((String satu) => satu.length).reduce(
                  (int a, int b) => a > b ? a : b,
                );
        final bool lebih = terpanjang > maks;

        return Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            lebih
                ? 'Ada baris sepanjang $terpanjang karakter - '
                    '${maks == 32 ? 'kertas 58 mm' : 'kertas 80 mm'} hanya '
                    'memuat $maks karakter per baris. Pangkas atau tekan enter.'
                : '$terpanjang dari $maks karakter pada baris terpanjang.',
            style: TextStyle(
              fontSize: 10.5,
              color: lebih ? rtsKsMerah : rtsPomTeks2,
              height: 1.35,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsPomLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: Text(widget.spbu == null ? 'Tambah SPBU' : 'Edit SPBU'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        children: <Widget>[
          _PomKartu(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _PomIsian(
                  controller: title,
                  label: 'Title',
                  hint: 'Contoh: 14201105',
                  baris: 2,
                ),
                _petunjuk(title, 42),
                const SizedBox(height: 14),
                _PomIsian(
                  controller: subtitle,
                  label: 'Subtitle',
                  hint: 'SPBU TB SIMATUPANG NO. 107\nJL. TB SIMATUPANG NO. 107',
                  baris: 3,
                ),
                _petunjuk(subtitle, 42),
                const SizedBox(height: 14),
                _PomIsian(
                  controller: footer,
                  label: 'Footer',
                  hint: 'Subsidi bulan ini, dsb.',
                  baris: 4,
                ),
                _petunjuk(footer, 42),
                const SizedBox(height: 10),
                const Text(
                  'Kertas 58 mm memuat paling banyak 32 karakter per baris, '
                  'kertas 80 mm paling banyak 42 karakter. Gunakan enter '
                  'untuk memisahkan baris.',
                  style: TextStyle(
                    fontSize: 11,
                    color: rtsPomTeks2,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: rtsKsMaroon,
              minimumSize: const Size(0, 48),
            ),
            onPressed: _menyimpan ? null : () => unawaited(_simpan()),
            icon: const Icon(Icons.save_outlined, size: 19),
            label: const Text('SIMPAN'),
          ),
        ],
      ),
    );
  }
}
