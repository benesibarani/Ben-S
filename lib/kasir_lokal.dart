/// ============================================================================
///  RTS PANEL BY BENE - MESIN KASIR OFFLINE (SQLite di dalam HP)
///  Berkas : lib/kasir_lokal.dart
///  Versi  : 1   (1 Oktober 2026)
///
///  CARA KERJA
///  ---------
///  SELURUH data kasir disimpan DI DALAM HP memakai SQLite:
///     produk (salinan dari server), stok bawaan, riwayat stok, nota penjualan,
///     barang terjual, piutang utang/titip, pembayaran/angsuran, dan template
///     struk. Jadi sales dapat bekerja TANPA INTERNET sama sekali.
///
///  SERVER menyimpan DAFTAR PRODUK BERSAMA pada tabel `produk`
///  (berkas database/migrations/RTS_PANEL_PRODUK.sql). Isinya:
///     SKU, barcode BUNGKUS (barcode batang tidak dipakai), nama, merek,
///     isi per bungkus, harga bungkus, harga batang.
///  Aplikasi mengunduhnya lewat tombol "SINKRON PRODUK" dan menyimpan
///  salinannya di HP, sehingga semua sales memakai daftar produk yang SAMA.
///  Produk yang ditambah dari HP juga naik ke tabel itu. Sebelum
///  disinkronkan pun aplikasi sudah dapat dipakai (produk diisi di HP).
///
///  DAFTAR TOKO juga disalin dari tabel `master_toko` server (menu Kasir ->
///  Pilih Toko), sehingga pemilihan toko tetap dapat dipakai saat tidak ada
///  internet.
///
///  YANG MASIH PERLU INTERNET (hanya sesekali):
///     1. Masuk pertama kali (login).
///     2. Memeriksa status Akun PRO (hasilnya disimpan; berlaku luring
///        sampai 30 hari sejak pemeriksaan terakhir).
///     3. Sinkron produk dari/ke server (opsional, dianjurkan sekali sehari).
///
///  BERKAS CADANGAN
///  ---------------
///  Data hanya ada di HP. Bila HP hilang/rusak, data ikut hilang. Karena itu
///  tersedia tombol CADANGKAN yang menyalin seluruh database ke berkas
///  rts_panel_cadangan_YYYYMMDD_HHMMSS.db, dan tombol PULIHKAN untuk
///  mengembalikannya. Anjurkan sales mencadangkan setiap hari/minggu.
///
///  BERKAS INI TIDAK MEMANGGIL kasir.dart (supaya tidak ada lingkaran impor).
/// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/* ------------------------------------------------------------------------- */
/* KESALAHAN                                                                 */
/* ------------------------------------------------------------------------- */

/// Kesalahan pada fitur kasir yang membawa keterangan tambahan.
class RtsKasirGalat implements Exception {
  RtsKasirGalat(this.pesan, {this.perluPro = false, this.perluSiap = false});

  final String pesan;
  final bool perluPro;
  final bool perluSiap;

  @override
  String toString() => pesan;
}

/* ------------------------------------------------------------------------- */
/* MESIN LOKAL                                                               */
/* ------------------------------------------------------------------------- */

class RtsKasirLokal {
  RtsKasirLokal._();

  /// Satu mesin dipakai bersama seluruh halaman.
  static final RtsKasirLokal aku = RtsKasirLokal._();

  /// Nama berkas database di dalam HP.
  static const String namaBerkas = 'rts_panel_kasir.db';

  /// Lama hasil pemeriksaan PRO boleh dipakai saat HP tidak ada internet.
  static const int batasLuringHari = 30;

  /// Lama hasil pemeriksaan PRO dianggap masih segar (tidak diperiksa ulang).
  static const int segarJam = 6;

  /// Masa segar khusus jawaban "BELUM BOLEH" (akun GRATIS / masa PRO habis).
  ///
  /// Sengaja dibuat pendek: akun yang baru diperpanjang atau baru disetujui
  /// ADMIN tidak boleh tetap terkunci karena jawaban lama masih dianggap
  /// segar. Sesudah [segarTolakMenit] menit, aplikasi memeriksa ulang ke
  /// server secara otomatis.
  static const int segarTolakMenit = 3;

  /// Bila server tidak dapat dihubungi (tidak ada internet), percobaan
  /// berikutnya ditunda selama ini supaya menu tidak menunggu lama.
  static const int tundaGagalMenit = 2;

  Database? _db;
  bool _perbaikanSudah = false;
  String baseUrl = '';
  String token = '';
  Map<String, dynamic> pengguna = <String, dynamic>{};

  Map<String, dynamic> _aksesSimpan = <String, dynamic>{};
  DateTime? _aksesDiperiksa;
  DateTime? _aksesGagal;

  /* ------------------------------------------------------------------ akun */

  String get idSales {
    final String nama = '${pengguna['username'] ?? ''}'.trim();

    return nama.isEmpty ? 'tanpa-nama' : nama;
  }

  String get namaSales {
    final String lengkap = '${pengguna['nama_lengkap'] ?? ''}'.trim();

    return lengkap.isEmpty ? idSales : lengkap;
  }

  String get role => '${pengguna['role'] ?? ''}'.toUpperCase();

  bool get pengelola => role == 'ADMIN' || role == 'ASS';

  /// Membaca nilai benar dari balasan server (1 / true / 'ya').
  static bool _benar(dynamic nilai) {
    if (nilai == true) return true;
    if (nilai == false || nilai == null) return false;

    final String teks = nilai.toString().trim().toLowerCase();

    return teks == '1' || teks == 'true' || teks == 'ya';
  }

  /// True bila DATA AKUN DARI SERVER (login / session_check / SINKRON AKUN)
  /// menyatakan akun ini PRO.
  ///
  /// Inilah bukti terkuat yang dimiliki aplikasi: data itu datang dari server
  /// pada saat login atau pemeriksaan sesi. Bila akun sudah disetujui ADMIN
  /// tetapi jawaban lama di HP masih "belum boleh", data ini yang menanganinya
  /// sehingga menu PRO langsung terbuka.
  bool get proSesi => pengelola || _benar(pengguna['akun_pro']);

  /// Label tingkat akun menurut data yang tersimpan di HP.
  String get labelSesi => proSesi ? 'PRO' : 'GRATIS';

  /// Mengisi keterangan akun. Dipanggil setiap halaman kasir dibuka.
  Future<void> atur({
    String? baseUrl,
    String? token,
    Map<String, dynamic>? pengguna,
  }) async {
    if (baseUrl != null && baseUrl.isNotEmpty) this.baseUrl = baseUrl;
    if (token != null && token.isNotEmpty) this.token = token;

    if (pengguna != null && pengguna.isNotEmpty) {
      this.pengguna = pengguna;

      // Disimpan supaya halaman lain (misalnya Printer & Struk) yang dibuka
      // langsung dari Beranda tetap mengenal siapa pemilik datanya.
      await _setelanTulis('pengguna', jsonEncode(pengguna));
    } else if (this.pengguna.isEmpty) {
      final String simpan = await _setelanBaca('pengguna', '');

      if (simpan.isNotEmpty) {
        try {
          final dynamic urai = jsonDecode(simpan);

          if (urai is Map) {
            this.pengguna = urai.cast<String, dynamic>();
          }
        } catch (_) {
          // keterangan akun tidak terbaca: data tetap dapat dipakai
        }
      }
    }

    await siapkanTabel();
  }

  /* ------------------------------------------------------------- database */

  Future<Database> get db async {
    if (_db != null && _db!.isOpen) return _db!;

    final String tempat = await getDatabasesPath();
    final String jalur = p.join(tempat, namaBerkas);

    _db = await openDatabase(
      jalur,
      version: 4,
      onCreate: (Database d, int v) async {
        for (final String sql in _perintahTabel()) {
          await d.execute(sql);
        }
      },
      onUpgrade: (Database d, int lama, int baru) async {
        // Database lama (versi 1) belum memakai kolom sku, belum punya tabel
        // toko, dan masih menyimpan kolom barcode_batang.
        // Versi 3 menambahkan titik koordinat & jadwal kunjungan pada tabel
        // toko, serta tabel kantor, kunjungan, dan peta_gores (pensil rute).
        // Versi 4 menambahkan tabel program (INTRODEAL & BD) pada menu PRO.
        await _perbaikiTabel(d);
      },
      onConfigure: (Database d) async {
        await d.execute('PRAGMA foreign_keys = ON');
      },
    );

    return _db!;
  }

  /// Alamat berkas database (dipakai untuk mencadangkan).
  Future<String> jalurDatabase() async {
    final String tempat = await getDatabasesPath();

    return p.join(tempat, namaBerkas);
  }

  List<String> _perintahTabel() {
    return <String>[
      '''CREATE TABLE IF NOT EXISTS produk (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_server INTEGER NOT NULL DEFAULT 0,
        sku TEXT NOT NULL DEFAULT '',
        barcode_pack TEXT NOT NULL DEFAULT '',
        nama TEXT NOT NULL,
        merek TEXT NOT NULL DEFAULT '',
        isi_per_pack INTEGER NOT NULL DEFAULT 0,
        harga_pack REAL NOT NULL DEFAULT 0,
        harga_batang REAL NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT '',
        aktif INTEGER NOT NULL DEFAULT 1,
        dari_server INTEGER NOT NULL DEFAULT 0,
        perlu_kirim INTEGER NOT NULL DEFAULT 1,
        diubah_pada TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_produk_barcode_pack ON produk(barcode_pack)'
      ' WHERE barcode_pack <> \'\'',
      'CREATE INDEX IF NOT EXISTS idx_produk_nama ON produk(nama)',
      '''CREATE TABLE IF NOT EXISTS toko (
        id_customer TEXT PRIMARY KEY,
        nama TEXT NOT NULL DEFAULT '',
        alamat TEXT NOT NULL DEFAULT '',
        district TEXT NOT NULL DEFAULT '',
        salesman TEXT NOT NULL DEFAULT '',
        hp TEXT NOT NULL DEFAULT '',
        tipe TEXT NOT NULL DEFAULT 'REGULER',
        latitude TEXT NOT NULL DEFAULT '',
        longitude TEXT NOT NULL DEFAULT '',
        kunjungan TEXT NOT NULL DEFAULT '',
        hari TEXT NOT NULL DEFAULT '',
        diperbarui TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE INDEX IF NOT EXISTS idx_toko_nama ON toko(nama)',
      '''CREATE TABLE IF NOT EXISTS program (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        jenis TEXT NOT NULL DEFAULT 'INTRODEAL',
        sku TEXT NOT NULL DEFAULT '',
        barcode_pack TEXT NOT NULL DEFAULT '',
        nama TEXT NOT NULL DEFAULT '',
        merek TEXT NOT NULL DEFAULT '',
        isi_per_pack INTEGER NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT '',
        periode TEXT NOT NULL DEFAULT '',
        aktif INTEGER NOT NULL DEFAULT 1,
        dari_server INTEGER NOT NULL DEFAULT 0,
        diubah_pada TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_program_jenis_sku'
      ' ON program(jenis, sku)',
      'CREATE INDEX IF NOT EXISTS idx_program_nama ON program(nama)',
      ..._perintahPeta(),
      '''CREATE TABLE IF NOT EXISTS stok (
        id_sales TEXT NOT NULL,
        produk_id INTEGER NOT NULL,
        pack INTEGER NOT NULL DEFAULT 0,
        batang INTEGER NOT NULL DEFAULT 0,
        diubah TEXT NOT NULL DEFAULT '',
        PRIMARY KEY (id_sales, produk_id)
      )''',
      '''CREATE TABLE IF NOT EXISTS stok_gerak (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tanggal TEXT NOT NULL,
        id_sales TEXT NOT NULL DEFAULT '',
        nama_sales TEXT NOT NULL DEFAULT '',
        produk_id INTEGER NOT NULL DEFAULT 0,
        nama_produk TEXT NOT NULL DEFAULT '',
        jenis TEXT NOT NULL DEFAULT 'MASUK',
        pack_delta INTEGER NOT NULL DEFAULT 0,
        batang_delta INTEGER NOT NULL DEFAULT 0,
        saldo_pack INTEGER NOT NULL DEFAULT 0,
        saldo_batang INTEGER NOT NULL DEFAULT 0,
        keterangan TEXT NOT NULL DEFAULT '',
        ref_tipe TEXT NOT NULL DEFAULT '',
        ref_id INTEGER NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX IF NOT EXISTS idx_gerak_sales ON stok_gerak(id_sales, id)',
      '''CREATE TABLE IF NOT EXISTS penjualan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nomor TEXT NOT NULL UNIQUE,
        tanggal TEXT NOT NULL,
        id_sales TEXT NOT NULL DEFAULT '',
        nama_sales TEXT NOT NULL DEFAULT '',
        district TEXT NOT NULL DEFAULT '',
        jenis_customer TEXT NOT NULL DEFAULT 'REGULER',
        customer_id TEXT NOT NULL DEFAULT '',
        nama_customer TEXT NOT NULL DEFAULT '',
        hp_customer TEXT NOT NULL DEFAULT '',
        alamat_customer TEXT NOT NULL DEFAULT '',
        metode TEXT NOT NULL DEFAULT 'CASH',
        total REAL NOT NULL DEFAULT 0,
        bayar REAL NOT NULL DEFAULT 0,
        kembali REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'LUNAS',
        jumlah_item INTEGER NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT '',
        dicetak INTEGER NOT NULL DEFAULT 0,
        cetak_terakhir TEXT NOT NULL DEFAULT '',
        dibatalkan INTEGER NOT NULL DEFAULT 0,
        batal_alasan TEXT NOT NULL DEFAULT '',
        batal_pada TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE INDEX IF NOT EXISTS idx_jual_sales ON penjualan(id_sales, id)',
      '''CREATE TABLE IF NOT EXISTS penjualan_item (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        penjualan_id INTEGER NOT NULL,
        produk_id INTEGER NOT NULL DEFAULT 0,
        nama_produk TEXT NOT NULL DEFAULT '',
        satuan TEXT NOT NULL DEFAULT 'PACK',
        isi_per_pack INTEGER NOT NULL DEFAULT 0,
        pack INTEGER NOT NULL DEFAULT 0,
        batang INTEGER NOT NULL DEFAULT 0,
        harga_satuan REAL NOT NULL DEFAULT 0,
        subtotal REAL NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX IF NOT EXISTS idx_item_nota ON penjualan_item(penjualan_id)',
      '''CREATE TABLE IF NOT EXISTS piutang (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nomor TEXT NOT NULL UNIQUE,
        jenis TEXT NOT NULL DEFAULT 'UTANG',
        penjualan_id INTEGER NOT NULL DEFAULT 0,
        tanggal TEXT NOT NULL,
        jatuh_tempo TEXT NOT NULL DEFAULT '',
        id_sales TEXT NOT NULL DEFAULT '',
        nama_sales TEXT NOT NULL DEFAULT '',
        customer_id TEXT NOT NULL DEFAULT '',
        nama_customer TEXT NOT NULL DEFAULT '',
        hp_customer TEXT NOT NULL DEFAULT '',
        total REAL NOT NULL DEFAULT 0,
        dibayar REAL NOT NULL DEFAULT 0,
        sisa REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'BELUM',
        rincian TEXT NOT NULL DEFAULT '',
        catatan TEXT NOT NULL DEFAULT '',
        diperbarui TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE INDEX IF NOT EXISTS idx_piut_sales ON piutang(id_sales, status)',
      '''CREATE TABLE IF NOT EXISTS piutang_bayar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        piutang_id INTEGER NOT NULL,
        tanggal TEXT NOT NULL,
        jumlah REAL NOT NULL DEFAULT 0,
        metode TEXT NOT NULL DEFAULT 'CASH',
        catatan TEXT NOT NULL DEFAULT '',
        sisa_sesudah REAL NOT NULL DEFAULT 0
      )''',
      'CREATE INDEX IF NOT EXISTS idx_bayar_piut ON piutang_bayar(piutang_id)',
      '''CREATE TABLE IF NOT EXISTS struk (
        id_sales TEXT PRIMARY KEY,
        judul TEXT NOT NULL DEFAULT 'RTS PANEL',
        baris1 TEXT NOT NULL DEFAULT '',
        baris2 TEXT NOT NULL DEFAULT '',
        baris3 TEXT NOT NULL DEFAULT '',
        footer1 TEXT NOT NULL DEFAULT 'Terima kasih',
        footer2 TEXT NOT NULL DEFAULT '',
        footer3 TEXT NOT NULL DEFAULT '',
        lebar_kertas INTEGER NOT NULL DEFAULT 58,
        jenis_printer TEXT NOT NULL DEFAULT '58',
        diameter_roll INTEGER NOT NULL DEFAULT 40,
        ukuran_huruf TEXT NOT NULL DEFAULT 'SEDANG',
        garis TEXT NOT NULL DEFAULT '-',
        jumlah_salinan INTEGER NOT NULL DEFAULT 1,
        tampilkan_barcode INTEGER NOT NULL DEFAULT 1,
        tampilkan_hp INTEGER NOT NULL DEFAULT 1,
        tampilkan_ttd INTEGER NOT NULL DEFAULT 0,
        tampilkan_metode INTEGER NOT NULL DEFAULT 1,
        diperbarui TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE IF NOT EXISTS setelan (
        kunci TEXT PRIMARY KEY,
        nilai TEXT NOT NULL DEFAULT '',
        diperbarui TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE IF NOT EXISTS penomoran (
        tanggal TEXT NOT NULL,
        prefix TEXT NOT NULL,
        urut INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (tanggal, prefix)
      )''',
    ];
  }

  /// Tabel untuk menu PETA CUSTOMER, RADAR CUSTOMER, dan RUTE PLAN.
  ///
  ///   kantor     : titik lokasi kantor / mitra (diatur ADMIN, disalin dari
  ///                server supaya rute tetap dapat dihitung tanpa internet)
  ///   kunjungan  : riwayat "toko ini sudah saya kunjungi" beserta jamnya
  ///   peta_gores : garis rute yang digambar memakai pensil pada peta
  List<String> _perintahPeta() {
    return <String>[
      '''CREATE TABLE IF NOT EXISTS kantor (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_server INTEGER NOT NULL DEFAULT 0,
        nama TEXT NOT NULL DEFAULT '',
        alamat TEXT NOT NULL DEFAULT '',
        district TEXT NOT NULL DEFAULT '',
        latitude REAL NOT NULL DEFAULT 0,
        longitude REAL NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT '',
        diubah_pada TEXT NOT NULL DEFAULT '',
        dari_server INTEGER NOT NULL DEFAULT 1,
        diperbarui TEXT NOT NULL DEFAULT ''
      )''',
      '''CREATE TABLE IF NOT EXISTS kunjungan (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        id_customer TEXT NOT NULL DEFAULT '',
        nama TEXT NOT NULL DEFAULT '',
        tanggal TEXT NOT NULL DEFAULT '',
        jam TEXT NOT NULL DEFAULT '',
        id_sales TEXT NOT NULL DEFAULT '',
        nama_sales TEXT NOT NULL DEFAULT '',
        latitude REAL NOT NULL DEFAULT 0,
        longitude REAL NOT NULL DEFAULT 0,
        catatan TEXT NOT NULL DEFAULT ''
      )''',
      'CREATE INDEX IF NOT EXISTS idx_kunjungan_tanggal ON kunjungan(tanggal)',
      'CREATE INDEX IF NOT EXISTS idx_kunjungan_customer ON kunjungan(id_customer)',
      '''CREATE TABLE IF NOT EXISTS peta_gores (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nama TEXT NOT NULL DEFAULT '',
        warna INTEGER NOT NULL DEFAULT 0,
        tebal REAL NOT NULL DEFAULT 4,
        titik TEXT NOT NULL DEFAULT '',
        jumlah INTEGER NOT NULL DEFAULT 0,
        id_sales TEXT NOT NULL DEFAULT '',
        dibuat TEXT NOT NULL DEFAULT ''
      )''',
    ];
  }

  /// Membuat tabel yang belum ada (aman dipanggil berkali-kali).
  Future<void> siapkanTabel() async {
    final Database d = await db;

    for (final String sql in _perintahTabel()) {
      await d.execute(sql);
    }

    // Penyesuaian database lama cukup sekali setiap aplikasi dijalankan.
    if (!_perbaikanSudah) {
      _perbaikanSudah = true;
      await _perbaikiTabel(d);
    }
  }

  /// Menyesuaikan database lama agar sesuai bentuk terbaru.
  ///
  /// Seluruh perintah di bawah AMAN dijalankan berkali-kali: bila kolomnya
  /// sudah ada, kesalahannya diabaikan sehingga data sales tidak terganggu.
  Future<void> _perbaikiTabel(DatabaseExecutor d) async {
    Future<void> coba(String sql) async {
      try {
        await d.execute(sql);
      } catch (_) {
        // kolom/tabel sudah ada: tidak perlu dikerjakan lagi
      }
    }

    // 1. Kolom baru pada tabel produk & struk.
    await coba("ALTER TABLE produk ADD COLUMN sku TEXT NOT NULL DEFAULT ''");
    await coba('ALTER TABLE produk ADD COLUMN perlu_kirim INTEGER NOT NULL DEFAULT 1');
    await coba("ALTER TABLE struk ADD COLUMN jenis_printer TEXT NOT NULL DEFAULT '58'");
    await coba('ALTER TABLE struk ADD COLUMN diameter_roll INTEGER NOT NULL DEFAULT 40');

    // 1b. Kolom baru pada tabel toko (putaran 12 - peta, radar, dan rute).
    await coba("ALTER TABLE toko ADD COLUMN latitude TEXT NOT NULL DEFAULT ''");
    await coba("ALTER TABLE toko ADD COLUMN longitude TEXT NOT NULL DEFAULT ''");
    await coba("ALTER TABLE toko ADD COLUMN kunjungan TEXT NOT NULL DEFAULT ''");
    await coba("ALTER TABLE toko ADD COLUMN hari TEXT NOT NULL DEFAULT ''");

    // 1c. Tabel baru untuk peta, radar, dan rute (aman bila sudah ada).
    for (final String sql in _perintahPeta()) {
      await coba(sql);
    }

    // 1d. Tabel PROGRAM (putaran 18G - menu PRO "Program").
    //     INTRODEAL  : produk launching yang sedang diperkenalkan
    //     BD         : produk Business Development
    await coba('''CREATE TABLE IF NOT EXISTS program (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      jenis TEXT NOT NULL DEFAULT 'INTRODEAL',
      sku TEXT NOT NULL DEFAULT '',
      barcode_pack TEXT NOT NULL DEFAULT '',
      nama TEXT NOT NULL DEFAULT '',
      merek TEXT NOT NULL DEFAULT '',
      isi_per_pack INTEGER NOT NULL DEFAULT 0,
      catatan TEXT NOT NULL DEFAULT '',
      periode TEXT NOT NULL DEFAULT '',
      aktif INTEGER NOT NULL DEFAULT 1,
      dari_server INTEGER NOT NULL DEFAULT 0,
      diubah_pada TEXT NOT NULL DEFAULT ''
    )''');
    await coba('CREATE UNIQUE INDEX IF NOT EXISTS idx_program_jenis_sku'
        ' ON program(jenis, sku)');
    await coba('CREATE INDEX IF NOT EXISTS idx_program_nama ON program(nama)');

    // 2. Kolom barcode_batang DIHAPUS (barcode hanya ada pada bungkus).
    //    SQLite lama belum mendukung DROP COLUMN, jadi tabel dibangun ulang
    //    dengan cara yang aman: salin dulu, baru ganti nama.
    try {
      final List<Map<String, Object?>> kolom =
          await d.rawQuery('PRAGMA table_info(produk)');
      final bool adaBatang = kolom.any((Map<String, Object?> k) =>
          '${k['name']}'.toLowerCase() == 'barcode_batang');

      if (adaBatang) {
        await d.execute('DROP TABLE IF EXISTS produk_tanpa_batang');
        await d.execute('''CREATE TABLE produk_tanpa_batang (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          id_server INTEGER NOT NULL DEFAULT 0,
          sku TEXT NOT NULL DEFAULT '',
          barcode_pack TEXT NOT NULL DEFAULT '',
          nama TEXT NOT NULL,
          merek TEXT NOT NULL DEFAULT '',
          isi_per_pack INTEGER NOT NULL DEFAULT 0,
          harga_pack REAL NOT NULL DEFAULT 0,
          harga_batang REAL NOT NULL DEFAULT 0,
          catatan TEXT NOT NULL DEFAULT '',
          aktif INTEGER NOT NULL DEFAULT 1,
          dari_server INTEGER NOT NULL DEFAULT 0,
          perlu_kirim INTEGER NOT NULL DEFAULT 1,
          diubah_pada TEXT NOT NULL DEFAULT ''
        )''');
        await d.execute('''INSERT INTO produk_tanpa_batang
          (id, id_server, sku, barcode_pack, nama, merek, isi_per_pack,
           harga_pack, harga_batang, catatan, aktif, dari_server, perlu_kirim,
           diubah_pada)
          SELECT id, id_server, sku, barcode_pack, nama, merek, isi_per_pack,
                 harga_pack, harga_batang, catatan, aktif, dari_server,
                 perlu_kirim, diubah_pada
          FROM produk''');
        await d.execute('DROP TABLE produk');
        await d.execute('ALTER TABLE produk_tanpa_batang RENAME TO produk');
        await d.execute(
          "CREATE UNIQUE INDEX IF NOT EXISTS idx_produk_barcode_pack"
          " ON produk(barcode_pack) WHERE barcode_pack <> ''",
        );
        await d.execute('CREATE INDEX IF NOT EXISTS idx_produk_nama ON produk(nama)');
      }
    } catch (_) {
      // bila pembangunan ulang gagal, kolom lama dibiarkan (tidak dipakai lagi)
    }
  }

  /* --------------------------------------------------------------- bantuan */

  static String _uang(dynamic nilai) {
    final double angka = _angka(nilai);
    final bool bulat = (angka - angka.round()).abs() < 0.005;

    final String teks = bulat
        ? angka.abs().round().toString()
        : angka.abs().toStringAsFixed(2).replaceAll('.', ',');

    final List<String> bagian = teks.split(',');
    final StringBuffer kiri = StringBuffer();
    final String angkaKiri = bagian[0];

    for (int i = 0; i < angkaKiri.length; i++) {
      final int sisa = angkaKiri.length - i;

      kiri.write(angkaKiri[i]);

      if (sisa > 1 && sisa % 3 == 1) kiri.write('.');
    }

    final String hasil = bagian.length > 1 ? '$kiri,${bagian[1]}' : kiri.toString();

    return angka < 0 ? '-$hasil' : hasil;
  }

  static double _angka(dynamic nilai) {
    if (nilai is num) return nilai.toDouble();

    String teks = '${nilai ?? ''}'.replaceAll(RegExp(r'[^0-9,.\-]'), '');

    if (teks.isEmpty) return 0;

    if (teks.contains(',')) {
      teks = teks.replaceAll('.', '').replaceAll(',', '.');

      return double.tryParse(teks) ?? 0;
    }

    final List<String> bagian = teks.split('.');

    if (bagian.length > 1 && bagian.last.length == 3) {
      teks = bagian.join();
    }

    return double.tryParse(teks) ?? 0;
  }

  static int _bulat(dynamic nilai) => _angka(nilai).round();

  static String _teks(dynamic nilai, [int maks = 255]) {
    final String bersih = '${nilai ?? ''}'.trim().replaceAll(RegExp(r'\s+'), ' ');

    return bersih.length <= maks ? bersih : bersih.substring(0, maks);
  }

  static String _waktu([DateTime? saat]) {
    final DateTime t = saat ?? DateTime.now();

    return '${t.year}-${_dua(t.month)}-${_dua(t.day)} '
        '${_dua(t.hour)}:${_dua(t.minute)}:${_dua(t.second)}';
  }

  static String _dua(int angka) => angka < 10 ? '0$angka' : '$angka';

  static String _stokTeks(int pack, int batang) {
    final List<String> bagian = <String>[];

    if (pack != 0) bagian.add('$pack pack');
    if (batang != 0 || pack == 0) bagian.add('$batang batang');

    return bagian.join(' ');
  }

  Future<String> _setelanBaca(String kunci, [String bawaan = '']) async {
    try {
      final Database d = await db;
      final List<Map<String, Object?>> baris = await d.query(
        'setelan',
        columns: <String>['nilai'],
        where: 'kunci = ?',
        whereArgs: <Object?>[kunci],
        limit: 1,
      );

      if (baris.isEmpty) return bawaan;

      final String nilai = '${baris.first['nilai'] ?? ''}'.trim();

      return nilai.isEmpty ? bawaan : nilai;
    } catch (_) {
      return bawaan;
    }
  }

  Future<void> _setelanTulis(String kunci, String nilai) async {
    try {
      final Database d = await db;

      await d.insert(
        'setelan',
        <String, Object?>{
          'kunci': kunci,
          'nilai': nilai,
          'diperbarui': _waktu(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {
      // gagal menyimpan setelan tidak menghalangi pemakaian
    }
  }

  /// Nomor dokumen harian: KS-20261001-0007 / PT-20261001-0007.
  ///
  /// Dipanggil di dalam transaksi supaya nomornya tidak kembar.
  Future<String> _nomor(DatabaseExecutor d, String prefix) async {
    final DateTime t = DateTime.now();
    final String hari = '${t.year}-${_dua(t.month)}-${_dua(t.day)}';
    final String kunci = '${t.year}${_dua(t.month)}${_dua(t.day)}';
    final String atas = prefix.toUpperCase();

    final List<Map<String, Object?>> ada = await d.query(
      'penomoran',
      where: 'tanggal = ? AND prefix = ?',
      whereArgs: <Object?>[hari, atas],
      limit: 1,
    );

    int urut = 1;

    if (ada.isEmpty) {
      await d.insert('penomoran', <String, Object?>{
        'tanggal': hari,
        'prefix': atas,
        'urut': 1,
      });
    } else {
      urut = _bulat(ada.first['urut']) + 1;

      await d.update(
        'penomoran',
        <String, Object?>{'urut': urut},
        where: 'tanggal = ? AND prefix = ?',
        whereArgs: <Object?>[hari, atas],
      );
    }

    return '$atas-$kunci-${urut.toString().padLeft(4, '0')}';
  }

  /* ------------------------------------------------------------- kewenangan */

  /// Memeriksa apakah fitur kasir boleh dipakai (Akun PRO).
  ///
  /// Hasil dari server disimpan, sehingga saat tidak ada internet aplikasi
  /// tetap dapat dipakai sampai [batasLuringHari] hari sejak pemeriksaan
  /// terakhir.
  Future<Map<String, dynamic>> akses({bool paksa = false}) async {
    if (pengelola) {
      return <String, dynamic>{
        'boleh': true,
        'label': 'PRO',
        'mode': 'PENGELOLA',
        'pesan': '',
      };
    }

    final DateTime sekarang = DateTime.now();

    // 0. BUKTI DARI DATA AKUN (paling kuat, berasal dari server).
    //    Login dan pemeriksaan sesi mengirim `akun_pro` dari database. Bila
    //    nilainya 1, akun ini PRO - jadi jawaban lama "belum boleh" yang
    //    tersimpan di HP TIDAK boleh lagi mengunci menu PRO.
    if (proSesi) {
      _aksesSimpan = <String, dynamic>{
        'boleh': true,
        'label': 'PRO',
        'mode': 'SESI',
        'pesan': '',
        'sisa_hari': _aksesSimpan['sisa_hari'] ?? 0,
      };
      _aksesDiperiksa = sekarang;
      _aksesGagal = null;

      await _setelanTulis('akses_simpan', jsonEncode(_aksesSimpan));
      await _setelanTulis('akses_pada', _waktu());

      return _aksesSimpan;
    }

    // Hasil yang tersimpan langsung dipakai HANYA bila masih segar:
    //  - jawaban "boleh"       : [segarJam] jam (supaya tetap jalan luring),
    //  - jawaban "belum boleh" : [segarTolakMenit] menit saja.
    // Masa segar yang pendek untuk jawaban "belum boleh" inilah yang membuat
    // akun yang BARU diperpanjang / BARU disetujui ADMIN langsung terbuka.
    if (!paksa && _aksesSimpan.isNotEmpty && _aksesDiperiksa != null) {
      final int segarMenit =
          _aksesSimpan['boleh'] == true ? segarJam * 60 : segarTolakMenit;

      if (sekarang.difference(_aksesDiperiksa!).inMinutes < segarMenit) {
        return _aksesSimpan;
      }
    }

    // 1. Coba periksa ke server. Bila percobaan sebelumnya baru saja gagal
    //    (misalnya tidak ada internet), percobaan berikutnya ditunda
    //    [tundaGagalMenit] menit supaya menu tidak menunggu lama.
    final bool bolehCobaKeServer = paksa ||
        _aksesGagal == null ||
        sekarang.difference(_aksesGagal!).inMinutes >= tundaGagalMenit;

    if (bolehCobaKeServer && baseUrl.isNotEmpty && token.isNotEmpty) {
      try {
        final Uri uri = Uri.parse('$baseUrl/kasir.php?aksi=akses');
        final http.Response jawab = await http.get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 20));

        final dynamic urai = jsonDecode(jawab.body);

        if (urai is Map) {
          final Map<String, dynamic> peta = urai.cast<String, dynamic>();
          final Map<String, dynamic> isi = (peta['akses'] is Map)
              ? (peta['akses'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};

          if (isi.isNotEmpty) {
            _aksesSimpan = isi;
            _aksesDiperiksa = sekarang;
            _aksesGagal = null;

            await _setelanTulis('akses_simpan', jsonEncode(isi));
            await _setelanTulis('akses_pada', _waktu());

            return isi;
          }
        }
      } catch (_) {
        // Tidak ada internet: waktu kegagalan dicatat supaya percobaan
        // berikutnya tidak menunggu lama, lalu lanjut memakai simpanan.
        _aksesGagal = sekarang;
      }
    }

    // 2. Pakai simpanan pemeriksaan terakhir.
    if (_aksesSimpan.isEmpty) {
      final String simpan = await _setelanBaca('akses_simpan', '');

      if (simpan.isNotEmpty) {
        try {
          final dynamic urai = jsonDecode(simpan);

          if (urai is Map) {
            _aksesSimpan = urai.cast<String, dynamic>();
          }
        } catch (_) {
          _aksesSimpan = <String, dynamic>{};
        }
      }
    }

    if (_aksesSimpan.isNotEmpty) {
      final String pada = await _setelanBaca('akses_pada', '');
      final DateTime? waktu = DateTime.tryParse(pada.replaceAll(' ', 'T'));
      final int umurHari =
          waktu == null ? 9999 : sekarang.difference(waktu).inDays;

      if (_aksesSimpan['boleh'] == true && umurHari <= batasLuringHari) {
        final String label = '${_aksesSimpan['label'] ?? 'PRO'}';

        return <String, dynamic>{
          ..._aksesSimpan,
          'luring': true,
          'pesan': 'Diperiksa luring$label - terakhir diperiksa $umurHari hari lalu.',
        };
      }

      if (_aksesSimpan['boleh'] == true) {
        return <String, dynamic>{
          'boleh': false,
          'label': 'GRATIS',
          'pesan': 'Masa berlaku perlu diperiksa ulang. Sambungkan internet '
              'sekali, lalu buka menu Sinkronisasi dan tekan SINKRON AKUN.',
          'perlu_segarkan': true,
        };
      }

      // Jawaban "belum boleh" yang tersimpan tetap dipakai, tetapi diberi
      // keterangan supaya pengguna tahu cara menyegarkan status akunnya.
      // Nilai dari simpanan dibaca lewat variabel supaya tidak ada tanda kutip
      // bersarang di dalam satu baris (lebih mudah dibaca & diperiksa).
      final Object? labelSimpan = _aksesSimpan['label'];
      final Object? pesanSimpan = _aksesSimpan['pesan'];

      final String labelAkses =
          labelSimpan == null ? 'GRATIS' : labelSimpan.toString();
      final String pesanAkses = pesanSimpan == null
          ? 'Fitur Barang Bawaan & Kasir tersedia untuk Akun PRO.'
          : pesanSimpan.toString();

      return <String, dynamic>{
        ..._aksesSimpan,
        'boleh': false,
        'label': labelAkses,
        'pesan': '$pesanAkses Bila pembayaran sudah disetujui ADMIN, '
            'buka menu Sinkronisasi lalu tekan SINKRON AKUN.',
        'perlu_segarkan': true,
      };
    }

    return <String, dynamic>{
      'boleh': false,
      'label': 'GRATIS',
      'pesan': 'Perlu sambungan internet SEKALI untuk memeriksa langganan. '
          'Setelah itu aplikasi dapat dipakai tanpa internet. Bila pembayaran '
          'sudah disetujui ADMIN, buka menu Sinkronisasi lalu tekan '
          'SINKRON AKUN.',
      'perlu_segarkan': true,
    };
  }

  Future<void> _pastikanBoleh() async {
    final Map<String, dynamic> hasil = await akses();

    if (hasil['boleh'] != true) {
      throw RtsKasirGalat(
        '${hasil['pesan'] ?? 'Fitur Barang Bawaan & Kasir tersedia untuk Akun PRO.'}',
        perluPro: true,
      );
    }
  }

  /* ----------------------------------------------------------------- pintu */

  /// Pintu perintah, bentuknya disamakan dengan api/kasir.php supaya seluruh
  /// halaman kasir tidak perlu diubah.
  Future<Map<String, dynamic>> kirim(
    String aksi, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    await siapkanTabel();

    switch (aksi.toLowerCase()) {
      case 'siap':
        return <String, dynamic>{
          'success': true,
          'message': 'Data kasir tersimpan di HP dan siap dipakai.',
          'siap': true,
          'lokal': true,
        };

      case 'siapkan':
        return <String, dynamic>{
          'success': true,
          'message': 'Data kasir sudah siap di HP.',
          'siap': true,
        };

      case 'akses':
        final Map<String, dynamic> hasil = await akses(paksa: true);

        return <String, dynamic>{
          'success': true,
          'message': '${hasil['pesan'] ?? 'Fitur kasir dapat dipakai.'}',
          'akses': hasil,
        };

      case 'ringkas':
        await _pastikanBoleh();

        return <String, dynamic>{
          'success': true,
          'message': 'Ringkasan hari ini.',
          'ringkas': await _ringkas(_teks(data['tanggal'], 20)),
        };

      case 'produk_daftar':
        await _pastikanBoleh();

        final List<Map<String, dynamic>> daftar =
            await _produkCari(_teks(data['cari'], 60), _bulat(data['batas'] ?? 200));

        return <String, dynamic>{
          'success': true,
          'message': '${daftar.length} produk ditemukan.',
          'items': daftar,
          'jumlah': daftar.length,
        };

      case 'produk_ambil':
        await _pastikanBoleh();

        final Map<String, dynamic>? produk = await _produkAmbil(_bulat(data['id']));

        if (produk == null) {
          throw RtsKasirGalat('Produk tidak ditemukan.');
        }

        return <String, dynamic>{
          'success': true,
          'message': 'Produk ditemukan.',
          'produk': produk,
        };

      case 'produk_barcode':
        await _pastikanBoleh();

        final String kode = _teks(data['barcode'], 64);

        if (kode.isEmpty) {
          throw RtsKasirGalat('Barcode belum terbaca.');
        }

        final Map<String, dynamic>? hasil = await _produkDariBarcode(kode);

        if (hasil == null) {
          return <String, dynamic>{
            'success': false,
            'message': 'Barcode $kode belum ada pada daftar produk. '
                'Tambahkan produknya lebih dahulu pada menu Barang Bawaan.',
            'ditemukan': false,
            'barcode': kode,
          };
        }

        final Map<String, dynamic> produk =
            hasil['produk'] as Map<String, dynamic>;
        final Map<String, dynamic> saldo =
            await _stokSaldo(_bulat(produk['id']));

        return <String, dynamic>{
          'success': true,
          'message': 'Produk ditemukan: ${produk['nama']}',
          'ditemukan': true,
          'satuan': hasil['satuan'],
          'produk': produk,
          'stok_pack': saldo['pack'],
          'stok_batang': saldo['batang'],
          'stok_teks': _stokTeks(
            _bulat(saldo['pack']),
            _bulat(saldo['batang']),
          ),
        };

      case 'produk_simpan':
        await _pastikanBoleh();

        return _produkSimpan(data);

      case 'produk_hapus':
        await _pastikanBoleh();

        return _produkHapus(_bulat(data['id']));

      case 'stok_daftar':
        await _pastikanBoleh();

        return _stokDaftar(
          _teks(data['cari'], 60),
          data['hanya_ada'] == true || data['hanya_ada'] == 1 || data['hanya_ada'] == '1',
        );

      case 'stok_gerak':
        await _pastikanBoleh();

        return _stokGerak(data);

      case 'stok_hapus':
        await _pastikanBoleh();

        return _stokHapus(_bulat(data['produk_id']), _teks(data['keterangan'], 255));

      case 'stok_hapus_semua':
        await _pastikanBoleh();

        return _stokHapusSemua();

      case 'stok_riwayat':
        await _pastikanBoleh();

        final List<Map<String, dynamic>> daftar =
            await _stokRiwayat(_bulat(data['produk_id']));

        return <String, dynamic>{
          'success': true,
          'message': '${daftar.length} catatan perubahan stok.',
          'items': daftar,
          'jumlah': daftar.length,
        };

      case 'kasir_simpan':
        await _pastikanBoleh();

        return _kasirSimpan(data);

      case 'kasir_daftar':
        await _pastikanBoleh();

        return _kasirDaftar(_teks(data['cari'], 60), _bulat(data['batas'] ?? 60));

      case 'kasir_ambil':
        await _pastikanBoleh();

        final Map<String, dynamic>? nota = await _kasirAmbil(_bulat(data['id']));

        if (nota == null) {
          throw RtsKasirGalat('Nota tidak ditemukan.');
        }

        return <String, dynamic>{
          'success': true,
          'message': 'Nota ${nota['nomor']}',
          'nota': nota,
        };

      case 'kasir_batal':
        await _pastikanBoleh();

        return _kasirBatal(_bulat(data['id']), _teks(data['alasan'], 200));

      case 'kasir_cetak':
        await _pastikanBoleh();

        final Database d = await db;

        await d.rawUpdate(
          'UPDATE penjualan SET dicetak = dicetak + 1, cetak_terakhir = ? WHERE id = ?',
          <Object?>[_waktu(), _bulat(data['id'])],
        );

        return <String, dynamic>{
          'success': true,
          'message': 'Nota ditandai sudah dicetak.',
        };

      case 'piutang_daftar':
        await _pastikanBoleh();

        return _piutangDaftar(
          _teks(data['jenis'], 10),
          _teks(data['status'], 12),
          _teks(data['cari'], 60),
        );

      case 'piutang_ambil':
        await _pastikanBoleh();

        final Map<String, dynamic>? piutang =
            await _piutangAmbil(_bulat(data['id']));

        if (piutang == null) {
          throw RtsKasirGalat('Piutang tidak ditemukan.');
        }

        return <String, dynamic>{
          'success': true,
          'message': 'Piutang ${piutang['nomor']}',
          'piutang': piutang,
        };

      case 'piutang_bayar':
        await _pastikanBoleh();

        return _piutangBayar(data);

      case 'struk_baca':
        return <String, dynamic>{
          'success': true,
          'message': 'Template struk.',
          'struk': await _strukBaca(),
        };

      case 'struk_simpan':
        await _pastikanBoleh();

        return _strukSimpan(data);

      case 'struk_contoh':
        await _pastikanBoleh();

        return _strukContoh();

      case 'laporan':
        await _pastikanBoleh();

        final String dari = _teks(data['dari'], 20);
        final String sampai = _teks(data['sampai'], 20);

        return <String, dynamic>{
          'success': true,
          'message': 'Laporan $dari sampai $sampai',
          'dari': dari,
          'sampai': sampai,
          'nota': await _kasirDaftar('', 200),
          'piutang': await _piutangDaftar('', '', ''),
          'ringkas': await _ringkas(''),
        };

      case 'sinkron_produk':
        await _pastikanBoleh();

        return _sinkronProduk();

      case 'toko_daftar':
        await _pastikanBoleh();

        return _tokoDaftar(_teks(data['cari'], 60), _bulat(data['batas'] ?? 60));

      case 'toko_segarkan':
        await _pastikanBoleh();

        return _tokoSegarkan();

      case 'toko_peta':
        await _pastikanBoleh();

        return _tokoPeta();

      case 'kunjungan_simpan':
        await _pastikanBoleh();

        return _kunjunganSimpan(data);

      case 'kunjungan_hari_ini':
        await _pastikanBoleh();

        return _kunjunganHariIni();

      case 'kunjungan_daftar':
        await _pastikanBoleh();

        return _kunjunganDaftar(
          _teks(data['id_customer'], 40),
          _bulat(data['batas'] ?? 200),
        );

      case 'kunjungan_hapus':
        await _pastikanBoleh();

        return _kunjunganHapus(_bulat(data['id']));

      case 'kantor_daftar':
        return _kantorDaftar();

      case 'kantor_segarkan':
        return _kantorSegarkan();

      case 'kantor_simpan':
        return _kantorSimpan(data);

      case 'kantor_hapus':
        return _kantorHapus(data);

      case 'program_daftar':
        await _pastikanBoleh();

        return _programDaftar(_teks(data['jenis'], 20), _teks(data['cari'], 60));

      case 'program_simpan':
        await _pastikanBoleh();

        return _programSimpan(data);

      case 'program_hapus':
        await _pastikanBoleh();

        return _programHapus(_bulat(data['id']));

      case 'program_ganti':
        await _pastikanBoleh();

        return _programGanti(
          _teks(data['jenis'], 20),
          data['items'] is List ? data['items'] as List<dynamic> : <dynamic>[],
        );

      case 'program_toko':
        await _pastikanBoleh();

        return _programToko(_teks(data['id_customer'], 40));

      case 'gores_daftar':
        await _pastikanBoleh();

        return _goresDaftar();

      case 'gores_simpan':
        await _pastikanBoleh();

        return _goresSimpan(data);

      case 'gores_hapus':
        await _pastikanBoleh();

        return _goresHapus(_bulat(data['id']));

      case 'gores_hapus_semua':
        await _pastikanBoleh();

        return _goresHapusSemua();

      case 'cadangan_info':
        return _cadanganInfo();

      case 'cadangkan':
        return _cadangkan();

      case 'pulihkan':
        return _pulihkan(_teks(data['berkas'], 200));
    }

    throw RtsKasirGalat('Perintah "$aksi" tidak dikenal pada mesin kasir lokal.');
  }

  /* ----------------------------------------------------------------- produk */

  Map<String, dynamic> _produkBentuk(Map<String, Object?> baris) {
    final int isi = _bulat(baris['isi_per_pack']);
    double hargaPack = _angka(baris['harga_pack']);
    double hargaBatang = _angka(baris['harga_batang']);

    if (hargaBatang <= 0 && isi > 0 && hargaPack > 0) {
      hargaBatang = (hargaPack / isi / 100).round() * 100;
    }

    return <String, dynamic>{
      'id': _bulat(baris['id']),
      'id_server': _bulat(baris['id_server']),
      'sku': '${baris['sku'] ?? ''}',
      'barcode_pack': '${baris['barcode_pack'] ?? ''}',
      // Barcode batang tidak dipakai lagi: barcode hanya ada pada bungkus.
      'barcode_batang': '',
      'nama': '${baris['nama'] ?? ''}',
      'merek': '${baris['merek'] ?? ''}',
      'isi_per_pack': isi,
      'harga_pack': hargaPack,
      'harga_batang': hargaBatang,
      'harga_pack_teks': _uang(hargaPack),
      'harga_batang_teks': _uang(hargaBatang),
      'aktif': _bulat(baris['aktif']) == 1,
      'catatan': '${baris['catatan'] ?? ''}',
      'dari_server': _bulat(baris['dari_server']) == 1,
      'perlu_kirim': _bulat(baris['perlu_kirim']) == 1,
    };
  }

  Future<List<Map<String, dynamic>>> _produkCari(String cari, int batas) async {
    final Database d = await db;

    final int jumlah = batas < 1 ? 200 : (batas > 500 ? 500 : batas);

    List<Map<String, Object?>> baris;

    if (cari.isEmpty) {
      baris = await d.query('produk',
          where: 'aktif = 1', orderBy: 'nama ASC', limit: jumlah);
    } else {
      final String mirip = '%$cari%';

      baris = await d.rawQuery(
        'SELECT * FROM produk WHERE aktif = 1 AND '
        '(nama LIKE ? OR merek LIKE ? OR sku = ? OR barcode_pack = ?) '
        'ORDER BY nama ASC LIMIT $jumlah',
        <Object?>[mirip, mirip, cari, cari],
      );
    }

    return baris.map(_produkBentuk).toList();
  }

  Future<Map<String, dynamic>?> _produkAmbil(int id) async {
    if (id <= 0) return null;

    final Database d = await db;
    final List<Map<String, Object?>> baris =
        await d.query('produk', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);

    if (baris.isEmpty) return null;

    return _produkBentuk(baris.first);
  }

  Future<Map<String, dynamic>?> _produkDariBarcode(String kode) async {
    final Database d = await db;
    final List<Map<String, Object?>> baris = await d.query(
      'produk',
      where: 'barcode_pack = ? AND barcode_pack <> \'\'',
      whereArgs: <Object?>[kode],
      limit: 1,
    );

    if (baris.isEmpty) return null;

    // Barcode hanya ada pada bungkus, jadi hasil scan selalu 1 bungkus.
    return <String, dynamic>{
      'produk': _produkBentuk(baris.first),
      'satuan': 'PACK',
    };
  }

  Future<Map<String, dynamic>> _produkSimpan(Map<String, dynamic> data) async {
    final Database d = await db;

    final int id = _bulat(data['id']);
    final String nama = _teks(data['nama'], 150);
    final String merek = _teks(data['merek'], 80);
    final String sku = _teks(data['sku'], 64);
    final String barcodePack = _teks(data['barcode_pack'], 64);
    final int isi = _bulat(data['isi_per_pack']);
    final double hargaPack = _angka(data['harga_pack']);
    final double hargaBatang = _angka(data['harga_batang']);
    final String catatan = _teks(data['catatan'], 255);

    if (nama.length < 2) {
      throw RtsKasirGalat('Nama produk terlalu pendek.');
    }

    if (hargaPack < 0 || hargaBatang < 0) {
      throw RtsKasirGalat('Harga tidak boleh negatif.');
    }

    // Barcode hanya untuk bungkus, dan tidak boleh dipakai produk lain.
    if (barcodePack.isNotEmpty) {
      final List<Map<String, Object?>> lain = await d.query(
        'produk',
        where: 'barcode_pack = ? AND id <> ?',
        whereArgs: <Object?>[barcodePack, id],
        limit: 1,
      );

      if (lain.isNotEmpty) {
        throw RtsKasirGalat(
          'Barcode $barcodePack sudah dipakai produk "${lain.first['nama']}".',
        );
      }
    }

    if (id > 0) {
      await d.update(
        'produk',
        <String, Object?>{
          'sku': sku,
          'nama': nama,
          'merek': merek,
          'barcode_pack': barcodePack,
          'isi_per_pack': isi,
          'harga_pack': hargaPack,
          'harga_batang': hargaBatang,
          'catatan': catatan,
          'perlu_kirim': 1,
          'diubah_pada': _waktu(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );

      return <String, dynamic>{
        'success': true,
        'message': 'Produk diperbarui.',
        'id': id,
        'produk': await _produkAmbil(id),
      };
    }

    final int baru = await d.insert('produk', <String, Object?>{
      'sku': sku,
      'nama': nama,
      'merek': merek,
      'barcode_pack': barcodePack,
      'isi_per_pack': isi,
      'harga_pack': hargaPack,
      'harga_batang': hargaBatang,
      'catatan': catatan,
      'aktif': 1,
      'dari_server': 0,
      'perlu_kirim': 1,
      'diubah_pada': _waktu(),
    });

    return <String, dynamic>{
      'success': true,
      'message': 'Produk baru tersimpan di HP.',
      'id': baru,
      'produk': await _produkAmbil(baru),
    };
  }

  Future<Map<String, dynamic>> _produkHapus(int id) async {
    if (id <= 0) {
      throw RtsKasirGalat('Produk tidak ditemukan.');
    }

    final Database d = await db;

    final List<Map<String, Object?>> terpakai = await d.rawQuery(
      'SELECT COUNT(*) AS total FROM penjualan_item WHERE produk_id = ?',
      <Object?>[id],
    );

    final bool pernahTerjual = _bulat(terpakai.first['total']) > 0;

    if (pernahTerjual) {
      await d.update('produk', <String, Object?>{'aktif': 0},
          where: 'id = ?', whereArgs: <Object?>[id]);

      return <String, dynamic>{
        'success': true,
        'message': 'Produk dinonaktifkan (pernah terjual, riwayatnya tetap disimpan).',
      };
    }

    await d.delete('produk', where: 'id = ?', whereArgs: <Object?>[id]);
    await d.delete('stok', where: 'produk_id = ?', whereArgs: <Object?>[id]);

    return <String, dynamic>{
      'success': true,
      'message': 'Produk dihapus dari HP.',
    };
  }

  /* -------------------------------------------------------------------- stok */

  Future<Map<String, dynamic>> _stokSaldo(int produkId) async {
    final Database d = await db;
    final List<Map<String, Object?>> baris = await d.query(
      'stok',
      where: 'id_sales = ? AND produk_id = ?',
      whereArgs: <Object?>[idSales, produkId],
      limit: 1,
    );

    if (baris.isEmpty) return <String, dynamic>{'pack': 0, 'batang': 0};

    return <String, dynamic>{
      'pack': _bulat(baris.first['pack']),
      'batang': _bulat(baris.first['batang']),
    };
  }

  /// Mengubah saldo stok sekaligus mencatat riwayatnya.
  Future<Map<String, dynamic>> _stokUbah({
    required DatabaseExecutor d,
    required int produkId,
    required String namaProduk,
    required String jenis,
    required int deltaPack,
    required int deltaBatang,
    String keterangan = '',
    String refTipe = '',
    int refId = 0,
  }) async {
    final Map<String, dynamic> saldo = await _stokSaldo(produkId);

    final int packBaru = _bulat(saldo['pack']) + deltaPack;
    final int batangBaru = _bulat(saldo['batang']) + deltaBatang;

    if (packBaru < 0 || batangBaru < 0) {
      throw RtsKasirGalat(
        'Stok $namaProduk tidak mencukupi. Sisa '
        '${_stokTeks(_bulat(saldo['pack']), _bulat(saldo['batang']))}.',
      );
    }

    await d.insert(
      'stok',
      <String, Object?>{
        'id_sales': idSales,
        'produk_id': produkId,
        'pack': packBaru,
        'batang': batangBaru,
        'diubah': _waktu(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    await d.insert('stok_gerak', <String, Object?>{
      'tanggal': _waktu(),
      'id_sales': idSales,
      'nama_sales': namaSales,
      'produk_id': produkId,
      'nama_produk': namaProduk,
      'jenis': jenis.toUpperCase(),
      'pack_delta': deltaPack,
      'batang_delta': deltaBatang,
      'saldo_pack': packBaru,
      'saldo_batang': batangBaru,
      'keterangan': keterangan,
      'ref_tipe': refTipe.toUpperCase(),
      'ref_id': refId,
    });

    return <String, dynamic>{'pack': packBaru, 'batang': batangBaru};
  }

  Future<Map<String, dynamic>> _stokDaftar(String cari, bool hanyaAda) async {
    final Database d = await db;

    String where = 'p.aktif = 1';
    final List<Object?> args = <Object?>[idSales];

    if (cari.isNotEmpty) {
      where += ' AND (p.nama LIKE ? OR p.merek LIKE ? OR p.sku = ? OR p.barcode_pack = ?)';
      final String mirip = '%$cari%';
      args.addAll(<Object?>[mirip, mirip, cari, cari]);
    }

    if (hanyaAda) {
      where += ' AND (COALESCE(s.pack, 0) > 0 OR COALESCE(s.batang, 0) > 0)';
    }

    final List<Map<String, Object?>> baris = await d.rawQuery(
      'SELECT p.*, s.pack AS stok_pack, s.batang AS stok_batang '
      'FROM produk p LEFT JOIN stok s ON s.produk_id = p.id AND s.id_sales = ? '
      'WHERE $where ORDER BY p.nama ASC LIMIT 300',
      args,
    );

    int totalPack = 0;
    int totalBatang = 0;
    double nilai = 0;

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      final Map<String, dynamic> produk = _produkBentuk(b);

      final int pack = _bulat(b['stok_pack']);
      final int batang = _bulat(b['stok_batang']);

      totalPack += pack;
      totalBatang += batang;

      final double nilaiSatu =
          pack * _angka(produk['harga_pack']) + batang * _angka(produk['harga_batang']);

      nilai += nilaiSatu;

      produk['stok_pack'] = pack;
      produk['stok_batang'] = batang;
      produk['stok_total_batang'] = pack * _bulat(produk['isi_per_pack']) + batang;
      produk['stok_teks'] = _stokTeks(pack, batang);
      produk['nilai'] = nilaiSatu;
      produk['nilai_teks'] = _uang(nilaiSatu);

      items.add(produk);
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} produk pada daftar barang bawaan.',
      'items': items,
      'jumlah': items.length,
      'total_pack': totalPack,
      'total_batang': totalBatang,
      'nilai': nilai,
      'nilai_teks': _uang(nilai),
      'lokal': true,
    };
  }

  Future<Map<String, dynamic>> _stokGerak(Map<String, dynamic> data) async {
    final int produkId = _bulat(data['produk_id']);
    final String jenis = _teks(data['jenis'], 12).toUpperCase();
    final int pack = _bulat(data['pack']);
    final int batang = _bulat(data['batang']);
    String keterangan = _teks(data['keterangan'], 255);

    if (!<String>['MASUK', 'RUSAK', 'KEMBALI', 'KOREKSI', 'OPNAME'].contains(jenis)) {
      throw RtsKasirGalat('Jenis perubahan stok tidak dikenal.');
    }

    final Map<String, dynamic>? produk = await _produkAmbil(produkId);

    if (produk == null) {
      throw RtsKasirGalat('Produk tidak ditemukan.');
    }

    if (pack == 0 && batang == 0 && jenis != 'OPNAME') {
      throw RtsKasirGalat('Jumlah pack atau batang belum diisi.');
    }

    final Database d = await db;

    int dPack = pack;
    int dBatang = batang;

    if (jenis == 'RUSAK' || jenis == 'KEMBALI') {
      dPack = -pack.abs();
      dBatang = -batang.abs();
    }

    if (jenis == 'OPNAME') {
      final Map<String, dynamic> saldo = await _stokSaldo(produkId);

      dPack = pack - _bulat(saldo['pack']);
      dBatang = batang - _bulat(saldo['batang']);

      if (keterangan.isEmpty) keterangan = 'Penyesuaian hasil hitung fisik';
    }

    final Map<String, dynamic> baru = await _stokUbah(
      d: d,
      produkId: produkId,
      namaProduk: '${produk['nama']}',
      jenis: jenis,
      deltaPack: dPack,
      deltaBatang: dBatang,
      keterangan: keterangan,
      refTipe: 'STOK',
    );

    return <String, dynamic>{
      'success': true,
      'message': 'Stok ${produk['nama']} sekarang '
          '${_stokTeks(_bulat(baru['pack']), _bulat(baru['batang']))}.',
      'nama_produk': produk['nama'],
      'stok_pack': baru['pack'],
      'stok_batang': baru['batang'],
      'stok_teks': _stokTeks(_bulat(baru['pack']), _bulat(baru['batang'])),
    };
  }

  /// Menghapus (menolkkan) stok satu produk. Riwayatnya tetap tercatat.
  Future<Map<String, dynamic>> _stokHapus(int produkId, String keterangan) async {
    if (produkId <= 0) {
      throw RtsKasirGalat('Produk belum dipilih.');
    }

    final Map<String, dynamic>? produk = await _produkAmbil(produkId);

    if (produk == null) {
      throw RtsKasirGalat('Produk tidak ditemukan.');
    }

    final Map<String, dynamic> saldo = await _stokSaldo(produkId);
    final int pack = _bulat(saldo['pack']);
    final int batang = _bulat(saldo['batang']);

    if (pack == 0 && batang == 0) {
      return <String, dynamic>{
        'success': true,
        'message': 'Stok ${produk['nama']} memang sudah kosong.',
        'stok_teks': '0 batang',
      };
    }

    final Database d = await db;

    await _stokUbah(
      d: d,
      produkId: produkId,
      namaProduk: '${produk['nama']}',
      jenis: 'HAPUS',
      deltaPack: -pack,
      deltaBatang: -batang,
      keterangan: keterangan.isEmpty ? 'Stok dihapus dari menu Stok' : keterangan,
      refTipe: 'STOK',
    );

    return <String, dynamic>{
      'success': true,
      'message': 'Stok ${produk['nama']} dihapus (menjadi 0).',
      'stok_pack': 0,
      'stok_batang': 0,
      'stok_teks': '0 batang',
    };
  }

  /// Menghapus stok SELURUH produk milik sales yang sedang masuk.
  Future<Map<String, dynamic>> _stokHapusSemua() async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = await d.query(
      'stok',
      where: 'id_sales = ? AND (pack <> 0 OR batang <> 0)',
      whereArgs: <Object?>[idSales],
    );

    int jumlah = 0;

    for (final Map<String, Object?> b in baris) {
      final int produkId = _bulat(b['produk_id']);
      final Map<String, dynamic>? produk = await _produkAmbil(produkId);

      if (produk == null) continue;

      await _stokUbah(
        d: d,
        produkId: produkId,
        namaProduk: '${produk['nama']}',
        jenis: 'HAPUS',
        deltaPack: -_bulat(b['pack']),
        deltaBatang: -_bulat(b['batang']),
        keterangan: 'Stok dihapus seluruhnya dari menu Stok',
        refTipe: 'STOK',
      );

      jumlah++;
    }

    return <String, dynamic>{
      'success': true,
      'message': jumlah == 0
          ? 'Tidak ada stok yang perlu dihapus.'
          : 'Stok $jumlah produk dihapus (menjadi 0).',
      'jumlah': jumlah,
    };
  }

  Future<List<Map<String, dynamic>>> _stokRiwayat(int produkId) async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = produkId > 0
        ? await d.query(
            'stok_gerak',
            where: 'id_sales = ? AND produk_id = ?',
            whereArgs: <Object?>[idSales, produkId],
            orderBy: 'id DESC',
            limit: 300,
          )
        : await d.query(
            'stok_gerak',
            where: 'id_sales = ?',
            whereArgs: <Object?>[idSales],
            orderBy: 'id DESC',
            limit: 300,
          );

    final List<Map<String, dynamic>> hasil = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      final int pack = _bulat(b['pack_delta']);
      final int batang = _bulat(b['batang_delta']);

      final List<String> ubah = <String>[];

      if (pack != 0) ubah.add('${pack > 0 ? '+' : ''}$pack pack');
      if (batang != 0) ubah.add('${batang > 0 ? '+' : ''}$batang batang');

      hasil.add(<String, dynamic>{
        'id': _bulat(b['id']),
        'tanggal': '${b['tanggal'] ?? ''}',
        'jenis': '${b['jenis'] ?? ''}',
        'nama_produk': '${b['nama_produk'] ?? ''}',
        'perubahan': ubah.isEmpty ? 'tetap' : ubah.join(' '),
        'saldo': _stokTeks(_bulat(b['saldo_pack']), _bulat(b['saldo_batang'])),
        'keterangan': '${b['keterangan'] ?? ''}',
      });
    }

    return hasil;
  }

  /* ------------------------------------------------------------------ kasir */

  Future<Map<String, dynamic>> _kasirSimpan(Map<String, dynamic> data) async {
    final List<dynamic> masukan =
        (data['items'] is List) ? data['items'] as List<dynamic> : <dynamic>[];

    if (masukan.isEmpty) {
      throw RtsKasirGalat('Belum ada barang yang dimasukkan ke nota.');
    }

    String metode = _teks(data['metode'], 10).toUpperCase();

    if (!<String>['CASH', 'UTANG', 'TITIP'].contains(metode)) {
      metode = 'CASH';
    }

    double total = 0;

    final List<Map<String, dynamic>> baris = <Map<String, dynamic>>[];

    for (final dynamic item in masukan) {
      if (item is! Map) continue;

      final Map<String, dynamic> isi = item.cast<String, dynamic>();
      final int produkId = _bulat(isi['produk_id']);

      final Map<String, dynamic>? produk = await _produkAmbil(produkId);

      if (produk == null) {
        throw RtsKasirGalat('Ada barang yang tidak ada pada daftar produk.');
      }

      final int pack = _bulat(isi['pack']);
      final int batang = _bulat(isi['batang']);

      if (pack < 0 || batang < 0) {
        throw RtsKasirGalat('Jumlah tidak boleh negatif.');
      }

      if (pack == 0 && batang == 0) continue;

      if (batang > 0 && _bulat(produk['isi_per_pack']) <= 0) {
        throw RtsKasirGalat(
          'Produk "${produk['nama']}" tidak dijual per batang (isi per pack belum diisi).',
        );
      }

      final double hargaPack = _angka(isi['harga_pack']) > 0
          ? _angka(isi['harga_pack'])
          : _angka(produk['harga_pack']);

      final double hargaBatang = _angka(isi['harga_batang']) > 0
          ? _angka(isi['harga_batang'])
          : _angka(produk['harga_batang']);

      final double subtotal = pack * hargaPack + batang * hargaBatang;

      total += subtotal;

      baris.add(<String, dynamic>{
        'produk_id': produkId,
        'nama_produk': produk['nama'],
        'satuan': pack > 0 ? 'PACK' : 'BATANG',
        'isi_per_pack': _bulat(produk['isi_per_pack']),
        'pack': pack,
        'batang': batang,
        'harga_satuan': pack > 0 ? hargaPack : hargaBatang,
        'subtotal': subtotal,
      });
    }

    if (baris.isEmpty) {
      throw RtsKasirGalat('Belum ada barang yang sah pada nota.');
    }

    if (total <= 0) {
      throw RtsKasirGalat('Total nota masih nol. Periksa harga barang.');
    }

    double bayar = _angka(data['bayar']);
    double kembali = 0;
    String status = 'LUNAS';

    if (metode == 'CASH') {
      if (bayar <= 0) bayar = total;

      if (bayar + 0.01 < total) {
        throw RtsKasirGalat(
          'Uang diterima Rp ${_uang(bayar)} kurang dari total Rp ${_uang(total)}.',
        );
      }

      kembali = bayar - total;
    } else {
      bayar = 0;
      status = 'BELUM';
    }

    final Database d = await db;

    String nomorNota = '';
    int notaId = 0;
    Map<String, dynamic>? piutang;

    await d.transaction((Transaction txn) async {
      nomorNota = await _nomor(txn, 'KS');

      final int jumlahItem = baris.fold<int>(
        0,
        (int a, Map<String, dynamic> b) =>
            a + ((_bulat(b['pack']) > 0 ? 1 : 0) + (_bulat(b['batang']) > 0 ? 1 : 0)),
      );

      notaId = await txn.insert('penjualan', <String, Object?>{
        'nomor': nomorNota,
        'tanggal': _waktu(),
        'id_sales': idSales,
        'nama_sales': namaSales,
        'district': _teks(pengguna['sales_district'], 60),
        'jenis_customer': _teks(data['jenis_customer'], 20).isEmpty
            ? 'REGULER'
            : _teks(data['jenis_customer'], 20).toUpperCase(),
        'customer_id': _teks(data['customer_id'], 40),
        'nama_customer': _teks(data['nama_customer'], 150),
        'hp_customer': _teks(data['hp_customer'], 30),
        'alamat_customer': _teks(data['alamat_customer'], 255),
        'metode': metode,
        'total': total,
        'bayar': bayar,
        'kembali': kembali,
        'status': status,
        'jumlah_item': jumlahItem,
        'catatan': _teks(data['catatan'], 255),
        'dibatalkan': 0,
      });

      for (final Map<String, dynamic> b in baris) {
        await txn.insert('penjualan_item', <String, Object?>{
          'penjualan_id': notaId,
          'produk_id': b['produk_id'],
          'nama_produk': b['nama_produk'],
          'satuan': b['satuan'],
          'isi_per_pack': b['isi_per_pack'],
          'pack': b['pack'],
          'batang': b['batang'],
          'harga_satuan': b['harga_satuan'],
          'subtotal': b['subtotal'],
        });
      }

      // Stok berkurang. Satu produk dihitung sekali saja walau ada dua baris
      // (pack dan batang).
      final Map<int, List<int>> perProduk = <int, List<int>>{};

      for (final Map<String, dynamic> b in baris) {
        final int pid = _bulat(b['produk_id']);

        perProduk.putIfAbsent(pid, () => <int>[0, 0, _bulat(b['isi_per_pack'])]);

        perProduk[pid]![0] += _bulat(b['pack']);
        perProduk[pid]![1] += _bulat(b['batang']);
      }

      for (final MapEntry<int, List<int>> masuk in perProduk.entries) {
        final int pid = masuk.key;
        final int butuhPack = masuk.value[0];
        final int butuhBatang = masuk.value[1];
        final int isi = masuk.value[2];

        final Map<String, dynamic>? produk = await _produkAmbil(pid);
        final String namaProduk = produk == null ? 'Produk' : '${produk['nama']}';

        final Map<String, dynamic> saldo = await _stokSaldo(pid);

        final int sisaPack = _bulat(saldo['pack']) - butuhPack;

        if (sisaPack < 0) {
          throw RtsKasirGalat(
            'Stok $namaProduk kurang. Sisa ${_bulat(saldo['pack'])} pack, '
            'dibutuhkan $butuhPack pack.',
          );
        }

        int bukaPack = 0;

        if (butuhBatang > _bulat(saldo['batang'])) {
          if (isi <= 0) {
            throw RtsKasirGalat('Produk $namaProduk tidak dijual per batang.');
          }

          final int kurang = butuhBatang - _bulat(saldo['batang']);
          bukaPack = (kurang / isi).ceil();

          if (bukaPack > sisaPack) {
            throw RtsKasirGalat(
              'Stok $namaProduk kurang. Sisa ${_bulat(saldo['pack'])} pack dan '
              '${_bulat(saldo['batang'])} batang, dibutuhkan $butuhPack pack dan '
              '$butuhBatang batang.',
            );
          }
        }

        String keterangan = 'Terjual pada nota $nomorNota';

        if (bukaPack > 0) {
          keterangan += ' (membuka $bukaPack pack menjadi ${bukaPack * isi} batang)';
        }

        await _stokUbah(
          d: txn,
          produkId: pid,
          namaProduk: namaProduk,
          jenis: 'JUAL',
          deltaPack: -butuhPack - bukaPack,
          deltaBatang: bukaPack * isi - butuhBatang,
          keterangan: keterangan,
          refTipe: 'KASIR',
          refId: notaId,
        );
      }

      // Piutang untuk UTANG dan TITIP.
      if (metode != 'CASH') {
        final List<String> rincian = <String>[];

        for (final Map<String, dynamic> b in baris) {
          final List<String> bagian = <String>[];

          if (_bulat(b['pack']) > 0) bagian.add('${_bulat(b['pack'])} pack');
          if (_bulat(b['batang']) > 0) bagian.add('${_bulat(b['batang'])} batang');

          rincian.add('${bagian.join(' + ')} ${b['nama_produk']}');
        }

        final String nomorPiutang = await _nomor(txn, 'PT');

        String tempo = _teks(data['jatuh_tempo'], 20);

        if (tempo.isEmpty) {
          tempo = DateTime.now()
              .add(Duration(days: metode == 'UTANG' ? 7 : 30))
              .toIso8601String()
              .substring(0, 10);
        }

        final int piutangId = await txn.insert('piutang', <String, Object?>{
          'nomor': nomorPiutang,
          'jenis': metode,
          'penjualan_id': notaId,
          'tanggal': _waktu(),
          'jatuh_tempo': tempo,
          'id_sales': idSales,
          'nama_sales': namaSales,
          'customer_id': _teks(data['customer_id'], 40),
          'nama_customer': _teks(data['nama_customer'], 150),
          'hp_customer': _teks(data['hp_customer'], 30),
          'total': total,
          'dibayar': 0,
          'sisa': total,
          'status': 'BELUM',
          'rincian': rincian.join(', '),
          'catatan': _teks(data['catatan'], 255),
          'diperbarui': _waktu(),
        });

        piutang = <String, dynamic>{
          'id': piutangId,
          'nomor': nomorPiutang,
          'jenis': metode,
          'jatuh_tempo': tempo,
          'sisa': total,
        };
      }
    });

    return <String, dynamic>{
      'success': true,
      'message': 'Nota $nomorNota tersimpan di HP.',
      'id': notaId,
      'nomor': nomorNota,
      'total': total,
      'total_teks': _uang(total),
      'bayar': bayar,
      'kembali': kembali,
      'kembali_teks': _uang(kembali),
      'metode': metode,
      'status': status,
      'piutang': piutang,
      'nota': await _kasirAmbil(notaId),
    };
  }

  Future<Map<String, dynamic>?> _kasirAmbil(int id) async {
    if (id <= 0) return null;

    final Database d = await db;
    final List<Map<String, Object?>> baris =
        await d.query('penjualan', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);

    if (baris.isEmpty) return null;

    final Map<String, Object?> n = baris.first;

    final List<Map<String, Object?>> itemBaris = await d.query(
      'penjualan_item',
      where: 'penjualan_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id ASC',
    );

    final List<Map<String, dynamic>> items = itemBaris
        .map((Map<String, Object?> b) => <String, dynamic>{
              'produk_id': _bulat(b['produk_id']),
              'nama_produk': '${b['nama_produk'] ?? ''}',
              'satuan': '${b['satuan'] ?? 'PACK'}',
              'isi_per_pack': _bulat(b['isi_per_pack']),
              'pack': _bulat(b['pack']),
              'batang': _bulat(b['batang']),
              'harga_satuan': _angka(b['harga_satuan']),
              'harga_satuan_teks': _uang(b['harga_satuan']),
              'subtotal': _angka(b['subtotal']),
              'subtotal_teks': _uang(b['subtotal']),
            })
        .toList();

    Map<String, dynamic>? piutang;

    final List<Map<String, Object?>> piutangBaris = await d.query(
      'piutang',
      where: 'penjualan_id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );

    if (piutangBaris.isNotEmpty) {
      final Map<String, Object?> p = piutangBaris.first;

      piutang = <String, dynamic>{
        'id': _bulat(p['id']),
        'nomor': '${p['nomor'] ?? ''}',
        'jenis': '${p['jenis'] ?? ''}',
        'jatuh_tempo': '${p['jatuh_tempo'] ?? ''}',
        'total': _angka(p['total']),
        'dibayar': _angka(p['dibayar']),
        'sisa': _angka(p['sisa']),
        'status': '${p['status'] ?? ''}',
      };
    }

    return <String, dynamic>{
      'id': _bulat(n['id']),
      'nomor': '${n['nomor'] ?? ''}',
      'tanggal': '${n['tanggal'] ?? ''}',
      'id_sales': '${n['id_sales'] ?? ''}',
      'nama_sales': '${n['nama_sales'] ?? ''}',
      'district': '${n['district'] ?? ''}',
      'jenis_customer': '${n['jenis_customer'] ?? ''}',
      'customer_id': '${n['customer_id'] ?? ''}',
      'nama_customer': '${n['nama_customer'] ?? ''}',
      'hp_customer': '${n['hp_customer'] ?? ''}',
      'alamat_customer': '${n['alamat_customer'] ?? ''}',
      'metode': '${n['metode'] ?? ''}',
      'total': _angka(n['total']),
      'total_teks': _uang(n['total']),
      'bayar': _angka(n['bayar']),
      'bayar_teks': _uang(n['bayar']),
      'kembali': _angka(n['kembali']),
      'kembali_teks': _uang(n['kembali']),
      'status': '${n['status'] ?? ''}',
      'catatan': '${n['catatan'] ?? ''}',
      'dicetak': _bulat(n['dicetak']),
      'dibatalkan': _bulat(n['dibatalkan']) == 1,
      'items': items,
      'piutang': piutang,
    };
  }

  Future<Map<String, dynamic>> _kasirDaftar(String cari, int batas) async {
    final Database d = await db;

    final int jumlah = batas < 1 ? 60 : (batas > 500 ? 500 : batas);

    String where = 'id_sales = ?';
    final List<Object?> args = <Object?>[idSales];

    if (cari.isNotEmpty) {
      where += ' AND (nomor LIKE ? OR nama_customer LIKE ? OR customer_id = ?)';
      final String mirip = '%$cari%';
      args.addAll(<Object?>[mirip, mirip, cari]);
    }

    final List<Map<String, Object?>> baris = await d.query(
      'penjualan',
      where: where,
      whereArgs: args,
      orderBy: 'id DESC',
      limit: jumlah,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    double total = 0;
    double cash = 0;

    for (final Map<String, Object?> n in baris) {
      final double nilai = _angka(n['total']);
      final bool batal = _bulat(n['dibatalkan']) == 1;

      total += nilai;

      if ('${n['metode']}'.toUpperCase() == 'CASH' && !batal) {
        cash += nilai;
      }

      items.add(<String, dynamic>{
        'id': _bulat(n['id']),
        'nomor': '${n['nomor'] ?? ''}',
        'tanggal': '${n['tanggal'] ?? ''}',
        'nama_customer': '${n['nama_customer'] ?? ''}',
        'customer_id': '${n['customer_id'] ?? ''}',
        'metode': '${n['metode'] ?? ''}',
        'total': nilai,
        'total_teks': _uang(nilai),
        'status': '${n['status'] ?? ''}',
        'dibatalkan': batal,
        'jumlah_item': _bulat(n['jumlah_item']),
        'nama_sales': '${n['nama_sales'] ?? ''}',
        'dicetak': _bulat(n['dicetak']),
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} nota tersimpan di HP.',
      'items': items,
      'jumlah': items.length,
      'total': total,
      'total_teks': _uang(total),
      'cash': cash,
      'cash_teks': _uang(cash),
    };
  }

  Future<Map<String, dynamic>> _kasirBatal(int id, String alasan) async {
    final Map<String, dynamic>? nota = await _kasirAmbil(id);

    if (nota == null) {
      throw RtsKasirGalat('Nota tidak ditemukan.');
    }

    if (nota['dibatalkan'] == true) {
      throw RtsKasirGalat('Nota ini sudah dibatalkan sebelumnya.');
    }

    final Map<String, dynamic>? piutang =
        (nota['piutang'] is Map) ? (nota['piutang'] as Map).cast<String, dynamic>() : null;

    if (piutang != null && _angka(piutang['dibayar']) > 0) {
      throw RtsKasirGalat(
        'Nota ini sudah ada pembayaran piutangnya. Hapus pembayaran lebih dahulu.',
      );
    }

    final Database d = await db;

    await d.transaction((Transaction txn) async {
      final List<dynamic> items =
          (nota['items'] is List) ? nota['items'] as List<dynamic> : <dynamic>[];

      for (final dynamic item in items) {
        if (item is! Map) continue;

        final Map<String, dynamic> b = item.cast<String, dynamic>();
        final int pid = _bulat(b['produk_id']);

        await _stokUbah(
          d: txn,
          produkId: pid,
          namaProduk: '${b['nama_produk']}',
          jenis: 'BATAL',
          deltaPack: _bulat(b['pack']),
          deltaBatang: _bulat(b['batang']),
          keterangan: alasan.isEmpty
              ? 'Pembatalan nota ${nota['nomor']}'
              : 'Pembatalan nota ${nota['nomor']} - $alasan',
          refTipe: 'KASIR',
          refId: id,
        );
      }

      await txn.update(
        'penjualan',
        <String, Object?>{
          'dibatalkan': 1,
          'batal_alasan': alasan,
          'batal_pada': _waktu(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );

      await txn.update(
        'piutang',
        <String, Object?>{'status': 'BATAL', 'diperbarui': _waktu()},
        where: 'penjualan_id = ?',
        whereArgs: <Object?>[id],
      );
    });

    return <String, dynamic>{
      'success': true,
      'message': 'Nota ${nota['nomor']} dibatalkan dan stok dikembalikan.',
    };
  }

  /* ---------------------------------------------------------------- piutang */

  Future<Map<String, dynamic>> _piutangDaftar(
    String jenis,
    String status,
    String cari,
  ) async {
    final Database d = await db;

    String where = 'id_sales = ?';
    final List<Object?> args = <Object?>[idSales];

    if (jenis.isNotEmpty) {
      where += ' AND jenis = ?';
      args.add(jenis.toUpperCase());
    }

    if (status.isNotEmpty) {
      where += ' AND status = ?';
      args.add(status.toUpperCase());
    }

    if (cari.isNotEmpty) {
      where += ' AND (nomor LIKE ? OR nama_customer LIKE ? OR customer_id = ?)';
      final String mirip = '%$cari%';
      args.addAll(<Object?>[mirip, mirip, cari]);
    }

    final List<Map<String, Object?>> baris = await d.query(
      'piutang',
      where: where,
      whereArgs: args,
      orderBy: "CASE status WHEN 'LUNAS' THEN 1 ELSE 0 END ASC, id DESC",
      limit: 300,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    double belum = 0;
    double dibayar = 0;

    for (final Map<String, Object?> p in baris) {
      final double sisa = _angka(p['sisa']);
      final double sudah = _angka(p['dibayar']);
      final String st = '${p['status'] ?? ''}';

      if (st != 'LUNAS' && st != 'BATAL') belum += sisa;

      dibayar += sudah;

      final String tempo = '${p['jatuh_tempo'] ?? ''}';
      final bool terlambat = tempo.isNotEmpty &&
          st != 'LUNAS' &&
          st != 'BATAL' &&
          (DateTime.tryParse(tempo)?.isBefore(DateTime.now()) ?? false);

      items.add(<String, dynamic>{
        'id': _bulat(p['id']),
        'nomor': '${p['nomor'] ?? ''}',
        'jenis': '${p['jenis'] ?? ''}',
        'tanggal': '${p['tanggal'] ?? ''}',
        'jatuh_tempo': tempo,
        'nama_customer': '${p['nama_customer'] ?? ''}',
        'customer_id': '${p['customer_id'] ?? ''}',
        'hp_customer': '${p['hp_customer'] ?? ''}',
        'nama_sales': '${p['nama_sales'] ?? ''}',
        'total': _angka(p['total']),
        'total_teks': _uang(p['total']),
        'dibayar': sudah,
        'dibayar_teks': _uang(sudah),
        'sisa': sisa,
        'sisa_teks': _uang(sisa),
        'status': st,
        'rincian': '${p['rincian'] ?? ''}',
        'terlambat': terlambat,
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} piutang tersimpan di HP.',
      'items': items,
      'jumlah': items.length,
      'belum': belum,
      'belum_teks': _uang(belum),
      'dibayar': dibayar,
      'dibayar_teks': _uang(dibayar),
      'lokal': true,
    };
  }

  Future<Map<String, dynamic>?> _piutangAmbil(int id) async {
    if (id <= 0) return null;

    final Database d = await db;
    final List<Map<String, Object?>> baris =
        await d.query('piutang', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);

    if (baris.isEmpty) return null;

    final Map<String, Object?> p = baris.first;

    final List<Map<String, Object?>> bayarBaris = await d.query(
      'piutang_bayar',
      where: 'piutang_id = ?',
      whereArgs: <Object?>[id],
      orderBy: 'id ASC',
    );

    final List<Map<String, dynamic>> pembayaran = bayarBaris
        .map((Map<String, Object?> b) => <String, dynamic>{
              'id': _bulat(b['id']),
              'tanggal': '${b['tanggal'] ?? ''}',
              'jumlah': _angka(b['jumlah']),
              'jumlah_teks': _uang(b['jumlah']),
              'metode': '${b['metode'] ?? ''}',
              'catatan': '${b['catatan'] ?? ''}',
              'sisa_sesudah_teks': _uang(b['sisa_sesudah']),
            })
        .toList();

    return <String, dynamic>{
      'id': _bulat(p['id']),
      'nomor': '${p['nomor'] ?? ''}',
      'jenis': '${p['jenis'] ?? ''}',
      'penjualan_id': _bulat(p['penjualan_id']),
      'tanggal': '${p['tanggal'] ?? ''}',
      'jatuh_tempo': '${p['jatuh_tempo'] ?? ''}',
      'nama_customer': '${p['nama_customer'] ?? ''}',
      'customer_id': '${p['customer_id'] ?? ''}',
      'hp_customer': '${p['hp_customer'] ?? ''}',
      'nama_sales': '${p['nama_sales'] ?? ''}',
      'total': _angka(p['total']),
      'total_teks': _uang(p['total']),
      'dibayar': _angka(p['dibayar']),
      'dibayar_teks': _uang(p['dibayar']),
      'sisa': _angka(p['sisa']),
      'sisa_teks': _uang(p['sisa']),
      'status': '${p['status'] ?? ''}',
      'rincian': '${p['rincian'] ?? ''}',
      'catatan': '${p['catatan'] ?? ''}',
      'pembayaran': pembayaran,
    };
  }

  Future<Map<String, dynamic>> _piutangBayar(Map<String, dynamic> data) async {
    final int id = _bulat(data['id']);
    final Map<String, dynamic>? piutang = await _piutangAmbil(id);

    if (piutang == null) {
      throw RtsKasirGalat('Piutang tidak ditemukan.');
    }

    final String status = '${piutang['status']}';

    if (status == 'LUNAS' || status == 'BATAL') {
      throw RtsKasirGalat('Piutang ini sudah ${status.toLowerCase()}.');
    }

    final double nilai = _angka(data['jumlah']);

    if (nilai <= 0) {
      throw RtsKasirGalat('Jumlah pembayaran belum diisi.');
    }

    final double sisa = _angka(piutang['sisa']);

    if (nilai > sisa + 0.01) {
      throw RtsKasirGalat(
        'Jumlah melebihi sisa piutang Rp ${_uang(sisa)}.',
      );
    }

    String metode = _teks(data['metode'], 12).toUpperCase();

    if (!<String>['CASH', 'TRANSFER', 'QRIS'].contains(metode)) {
      metode = 'CASH';
    }

    final double dibayarBaru = _angka(piutang['dibayar']) + nilai;
    double sisaBaru = _angka(piutang['total']) - dibayarBaru;

    if (sisaBaru < 0) sisaBaru = 0;

    final String statusBaru = sisaBaru <= 0.01
        ? 'LUNAS'
        : (dibayarBaru > 0 ? 'SEBAGIAN' : 'BELUM');

    final Database d = await db;

    await d.transaction((Transaction txn) async {
      await txn.insert('piutang_bayar', <String, Object?>{
        'piutang_id': id,
        'tanggal': _waktu(),
        'jumlah': nilai,
        'metode': metode,
        'catatan': _teks(data['catatan'], 255),
        'sisa_sesudah': sisaBaru,
      });

      await txn.update(
        'piutang',
        <String, Object?>{
          'dibayar': dibayarBaru,
          'sisa': sisaBaru,
          'status': statusBaru,
          'diperbarui': _waktu(),
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );

      final int notaId = _bulat(piutang['penjualan_id']);

      if (notaId > 0) {
        await txn.update(
          'penjualan',
          <String, Object?>{'status': statusBaru == 'LUNAS' ? 'LUNAS' : statusBaru},
          where: 'id = ?',
          whereArgs: <Object?>[notaId],
        );
      }
    });

    return <String, dynamic>{
      'success': true,
      'message': statusBaru == 'LUNAS'
          ? 'Piutang ${piutang['nomor']} LUNAS.'
          : 'Pembayaran Rp ${_uang(nilai)} tersimpan. Sisa Rp ${_uang(sisaBaru)}.',
      'sisa': sisaBaru,
      'sisa_teks': _uang(sisaBaru),
      'status': statusBaru,
      'piutang': await _piutangAmbil(id),
    };
  }

  /* ------------------------------------------------------------------ struk */

  Map<String, dynamic> _strukBawaan() {
    return <String, dynamic>{
      'judul': 'RTS PANEL',
      'baris1': 'PT. Wismilak Inti Makmur',
      'baris2': '',
      'baris3': '',
      'footer1': 'Terima kasih',
      'footer2': 'Barang yang sudah dibeli',
      'footer3': 'tidak dapat ditukar',
      'lebar_kertas': 58,
      'jenis_printer': '58',
      'diameter_roll': 40,
      'ukuran_huruf': 'SEDANG',
      'garis': '-',
      'jumlah_salinan': 1,
      'tampilkan_barcode': 1,
      'tampilkan_hp': 1,
      'tampilkan_ttd': 0,
      'tampilkan_metode': 1,
    };
  }

  Future<Map<String, dynamic>> _strukBaca() async {
    final Database d = await db;
    final List<Map<String, Object?>> baris = await d.query(
      'struk',
      where: 'id_sales = ?',
      whereArgs: <Object?>[idSales],
      limit: 1,
    );

    final Map<String, dynamic> bawaan = _strukBawaan();

    if (baris.isEmpty) {
      bawaan['ada'] = false;

      return bawaan;
    }

    final Map<String, Object?> s = baris.first;

    for (final String kunci in bawaan.keys.toList()) {
      if (s.containsKey(kunci) && s[kunci] != null) {
        bawaan[kunci] = s[kunci];
      }
    }

    bawaan['ada'] = true;

    return bawaan;
  }

  Future<Map<String, dynamic>> _strukSimpan(Map<String, dynamic> data) async {
    final Map<String, dynamic> bawaan = _strukBawaan();

    final Map<String, Object?> simpan = <String, Object?>{
      'id_sales': idSales,
      'diperbarui': _waktu(),
    };

    for (final String kunci in <String>[
      'judul',
      'baris1',
      'baris2',
      'baris3',
      'footer1',
      'footer2',
      'footer3',
    ]) {
      final int maks = kunci == 'judul' ? 60 : 120;

      simpan[kunci] = data.containsKey(kunci)
          ? _teks(data[kunci], maks)
          : '${bawaan[kunci]}';
    }

    // Jenis printer: 58 mm (mini/mobile) atau 80 mm (desktop/POS).
    String jenis = _teks(data['jenis_printer'], 4);

    if (!<String>['58', '80'].contains(jenis)) {
      final int lebarLama = data.containsKey('lebar_kertas')
          ? _bulat(data['lebar_kertas'])
          : _bulat(bawaan['lebar_kertas']);

      jenis = lebarLama >= 76 ? '80' : '58';
    }

    final int lebar = jenis == '80' ? 80 : 58;

    // Diameter roll kertas (mm). Pilihannya mengikuti jenis printer:
    //   58 mm : 30, 38, 40, 45, 50
    //   80 mm : 40, 47, 80, 100, 140
    final Map<String, List<int>> daftarRoll = <String, List<int>>{
      '58': <int>[30, 38, 40, 45, 50],
      '80': <int>[40, 47, 80, 100, 140],
    };

    int roll = data.containsKey('diameter_roll')
        ? _bulat(data['diameter_roll'])
        : _bulat(bawaan['diameter_roll']);

    if (!daftarRoll[jenis]!.contains(roll)) {
      final int bawaanRoll = _bulat(bawaan['diameter_roll']);

      roll = daftarRoll[jenis]!.contains(bawaanRoll)
          ? bawaanRoll
          : daftarRoll[jenis]!.first;
    }

    int salinan = data.containsKey('jumlah_salinan')
        ? _bulat(data['jumlah_salinan'])
        : _bulat(bawaan['jumlah_salinan']);

    if (salinan < 1 || salinan > 3) salinan = 1;

    String huruf = _teks(data['ukuran_huruf'], 10).toUpperCase();

    if (!<String>['KECIL', 'SEDANG', 'BESAR'].contains(huruf)) huruf = 'SEDANG';

    String garis = _teks(data['garis'], 3);

    if (garis.isEmpty) garis = '-';

    simpan['lebar_kertas'] = lebar;
    simpan['jenis_printer'] = jenis;
    simpan['diameter_roll'] = roll;
    simpan['jumlah_salinan'] = salinan;
    simpan['ukuran_huruf'] = huruf;
    simpan['garis'] = garis;

    for (final String kunci in <String>[
      'tampilkan_barcode',
      'tampilkan_hp',
      'tampilkan_ttd',
      'tampilkan_metode',
    ]) {
      simpan[kunci] = data.containsKey(kunci)
          ? (_bulat(data[kunci]) == 1 ? 1 : 0)
          : _bulat(bawaan[kunci]);
    }

    final Database d = await db;

    await d.insert('struk', simpan, conflictAlgorithm: ConflictAlgorithm.replace);

    return <String, dynamic>{
      'success': true,
      'message': 'Template struk disimpan di HP '
          '(printer $lebar mm, roll $roll mm).',
      'struk': await _strukBaca(),
    };
  }

  Future<Map<String, dynamic>> _strukContoh() async {
    final Map<String, dynamic> struk = await _strukBaca();
    final Map<String, dynamic> stok = await _stokDaftar('', false);

    final List<dynamic> daftar =
        (stok['items'] is List) ? stok['items'] as List<dynamic> : <dynamic>[];

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final dynamic item in daftar) {
      if (item is! Map) continue;

      final Map<String, dynamic> p = item.cast<String, dynamic>();

      if (items.length >= 2) break;

      if (_bulat(p['stok_pack']) > 0) {
        final double harga = _angka(p['harga_pack']);

        items.add(<String, dynamic>{
          'nama_produk': '${p['nama']}',
          'satuan': 'PACK',
          'pack': 2,
          'batang': 0,
          'harga_satuan': harga,
          'subtotal': 2 * harga,
        });
      }

      if (_bulat(p['isi_per_pack']) > 0 && _bulat(p['stok_batang']) >= 3) {
        final double harga = _angka(p['harga_batang']);

        items.add(<String, dynamic>{
          'nama_produk': '${p['nama']}',
          'satuan': 'BATANG',
          'pack': 0,
          'batang': 3,
          'harga_satuan': harga,
          'subtotal': 3 * harga,
        });
      }
    }

    if (items.isEmpty) {
      items.add(<String, dynamic>{
        'nama_produk': 'Contoh Produk Rokok 16',
        'satuan': 'PACK',
        'pack': 2,
        'batang': 0,
        'harga_satuan': 32000,
        'subtotal': 64000,
      });
      items.add(<String, dynamic>{
        'nama_produk': 'Contoh Produk Rokok 16',
        'satuan': 'BATANG',
        'pack': 0,
        'batang': 3,
        'harga_satuan': 2200,
        'subtotal': 6600,
      });
    }

    double total = 0;

    for (final Map<String, dynamic> i in items) {
      total += _angka(i['subtotal']);
    }

    final double bayar = ((total / 50000).ceil() * 50000).toDouble();

    return <String, dynamic>{
      'success': true,
      'message': 'Contoh nota untuk uji cetak.',
      'struk': struk,
      'nota': <String, dynamic>{
        'nomor': 'KS-CONTOH-0001',
        'tanggal': _waktu(),
        'nama_sales': namaSales,
        'nama_customer': 'TOKO CONTOH UJI CETAK',
        'customer_id': 'CONTOH',
        'hp_customer': '',
        'metode': 'CASH',
        'status': 'LUNAS',
        'total': total,
        'bayar': bayar,
        'kembali': bayar - total,
        'items': items,
        'contoh': true,
      },
    };
  }

  /* -------------------------------------------------------------- ringkasan */

  Future<Map<String, dynamic>> _ringkas(String tanggal) async {
    final Database d = await db;

    final String hari = tanggal.isEmpty ? _waktu().substring(0, 10) : tanggal;

    final List<Map<String, Object?>> nota = await d.rawQuery(
      'SELECT COUNT(*) AS jumlah, COALESCE(SUM(total), 0) AS total, '
      "COALESCE(SUM(CASE WHEN metode = 'CASH' THEN total ELSE 0 END), 0) AS cash "
      'FROM penjualan WHERE id_sales = ? AND dibatalkan = 0 AND substr(tanggal, 1, 10) = ?',
      <Object?>[idSales, hari],
    );

    final List<Map<String, Object?>> piutang = await d.rawQuery(
      'SELECT COALESCE(SUM(CASE WHEN substr(tanggal, 1, 10) = ? THEN total ELSE 0 END), 0) AS baru, '
      "COALESCE(SUM(CASE WHEN status IN ('BELUM', 'SEBAGIAN') THEN sisa ELSE 0 END), 0) AS belum "
      'FROM piutang WHERE id_sales = ?',
      <Object?>[hari, idSales],
    );

    final List<Map<String, Object?>> stok = await d.rawQuery(
      'SELECT COUNT(*) AS jumlah, '
      'COALESCE(SUM(s.pack * p.harga_pack + s.batang * p.harga_batang), 0) AS nilai '
      'FROM stok s INNER JOIN produk p ON p.id = s.produk_id '
      'WHERE s.id_sales = ? AND (s.pack > 0 OR s.batang > 0)',
      <Object?>[idSales],
    );

    final Map<String, Object?> n = nota.isEmpty ? <String, Object?>{} : nota.first;
    final Map<String, Object?> p2 = piutang.isEmpty ? <String, Object?>{} : piutang.first;
    final Map<String, Object?> s = stok.isEmpty ? <String, Object?>{} : stok.first;

    return <String, dynamic>{
      'tanggal': hari,
      'jumlah_nota': _bulat(n['jumlah']),
      'total_jual': _angka(n['total']),
      'total_jual_teks': _uang(n['total']),
      'cash': _angka(n['cash']),
      'cash_teks': _uang(n['cash']),
      'piutang_baru': _angka(p2['baru']),
      'piutang_baru_teks': _uang(p2['baru']),
      'piutang_belum': _angka(p2['belum']),
      'piutang_belum_teks': _uang(p2['belum']),
      'jumlah_produk': _bulat(s['jumlah']),
      'nilai_stok': _angka(s['nilai']),
      'nilai_stok_teks': _uang(s['nilai']),
    };
  }

  /* ------------------------------------------------------- sinkron & berkas */

  /// Menyinkronkan daftar produk bersama (tabel `produk` di server).
  ///
  ///   1. Produk yang dibuat/diubah di HP dikirim ke server (perintah "impor").
  ///   2. Daftar produk dari server diunduh dan menggantikan salinan di HP.
  ///
  /// Dengan begitu SEMUA sales memakai daftar produk yang sama.
  Future<Map<String, dynamic>> _sinkronProduk() async {
    if (baseUrl.isEmpty || token.isEmpty) {
      throw RtsKasirGalat('Alamat server belum dikenal. Masuk kembali ke aplikasi.');
    }

    final Database d = await db;
    final Uri alamat = Uri.parse('$baseUrl/produk.php');

    final Map<String, String> kepala = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final bool pengelola = <String>['ADMIN', 'ASS'].contains(role);

    int terkirim = 0;
    int diunduh = 0;
    int dinonaktifkan = 0;
    final List<String> catatanGagal = <String>[];

    /* ------------------------------------------- 1. KIRIM produk dari HP --- */

    final List<Map<String, Object?>> lokal = await d.query(
      'produk',
      where: 'perlu_kirim = 1 OR id_server = 0',
      orderBy: 'id ASC',
      limit: 300,
    );

    bool sampaiServer = false;

    if (lokal.isNotEmpty) {
      final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

      for (final Map<String, Object?> p in lokal) {
        items.add(<String, dynamic>{
          'id_lokal': _bulat(p['id']),
          'id': _bulat(p['id_server']),
          'sku': '${p['sku'] ?? ''}',
          'nama': '${p['nama'] ?? ''}',
          'merek': '${p['merek'] ?? ''}',
          'barcode_bungkus': '${p['barcode_pack'] ?? ''}',
          'isi_per_bungkus': _bulat(p['isi_per_pack']),
          'harga_bungkus': _angka(p['harga_pack']),
          'harga_batang': _angka(p['harga_batang']),
          'catatan': '${p['catatan'] ?? ''}',
          'status_aktif': _bulat(p['aktif']) == 1 ? 1 : 0,
        });
      }

      try {
        final http.Response jawab = await http
            .post(
              alamat,
              headers: kepala,
              body: jsonEncode(<String, dynamic>{
                'aksi': 'impor',
                'items': items,
              }),
            )
            .timeout(const Duration(seconds: 90));

        final dynamic urai = jsonDecode(jawab.body);

        if (urai is Map && urai['success'] == true) {
          sampaiServer = true;

          final List<dynamic> peta =
              (urai['peta'] is List) ? urai['peta'] as List<dynamic> : <dynamic>[];

          for (final dynamic satu in peta) {
            if (satu is! Map) continue;

            final Map<String, dynamic> baris = satu.cast<String, dynamic>();
            final int idLokal = _bulat(baris['lokal']);
            final int idServer = _bulat(baris['id_server']);

            if (idLokal > 0 && idServer > 0) {
              await d.update(
                'produk',
                <String, Object?>{
                  'id_server': idServer,
                  'dari_server': 1,
                  'perlu_kirim': 0,
                },
                where: 'id = ?',
                whereArgs: <Object?>[idLokal],
              );

              terkirim++;
            }
          }

          final List<dynamic> gagal =
              (urai['gagal'] is List) ? urai['gagal'] as List<dynamic> : <dynamic>[];

          for (final dynamic satu in gagal) {
            if (satu is Map) {
              catatanGagal.add('${satu['nama'] ?? '-'}: ${satu['pesan'] ?? ''}');
            }
          }
        } else if (urai is Map) {
          throw RtsKasirGalat('${urai['message'] ?? 'Produk ditolak server.'}');
        }
      } on RtsKasirGalat {
        rethrow;
      } catch (_) {
        // tidak ada internet: lanjut mencoba mengunduh di bawah
      }
    }

    /* ---------------------------------------- 2. UNDUH daftar produk ------- */

    try {
      final Uri uri = alamat.replace(queryParameters: <String, String>{
        'aksi': 'daftar',
        'batas': '2000',
        if (pengelola) 'semua': '1',
      });

      final http.Response jawab = await http
          .get(uri, headers: kepala)
          .timeout(const Duration(seconds: 60));

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map || urai['success'] != true) {
        throw RtsKasirGalat(
          'Daftar produk di server tidak dapat dibaca'
          '${urai is Map && urai['message'] != null ? ': ${urai['message']}' : '.'}',
        );
      }

      final List<dynamic> items =
          (urai['items'] is List) ? urai['items'] as List<dynamic> : <dynamic>[];

      final Set<int> idServerAda = <int>{};
      final String waktu = _waktu();

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        final Map<String, dynamic> p = satu.cast<String, dynamic>();
        final int idServer = _bulat(p['id']);

        if (idServer <= 0) continue;

        idServerAda.add(idServer);

        final List<Map<String, Object?>> sudah = await d.query(
          'produk',
          where: 'id_server = ?',
          whereArgs: <Object?>[idServer],
          limit: 1,
        );

        final Map<String, Object?> isi = <String, Object?>{
          'id_server': idServer,
          'sku': _teks(p['sku'], 64),
          'nama': _teks(p['nama'], 150),
          'merek': _teks(p['merek'], 80),
          'barcode_pack': _teks(p['barcode_pack'], 64),
          'isi_per_pack': _bulat(p['isi_per_pack']),
          'harga_pack': _angka(p['harga_pack']),
          'harga_batang': _angka(p['harga_batang']),
          'catatan': _teks(p['catatan'], 255),
          'aktif': p['aktif'] == false ? 0 : 1,
          'dari_server': 1,
          'perlu_kirim': 0,
          'diubah_pada': _teks(p['diubah_pada'], 30).isEmpty
              ? waktu
              : _teks(p['diubah_pada'], 30),
        };

        if (sudah.isEmpty) {
          await d.insert('produk', isi);
        } else {
          await d.update('produk', isi,
              where: 'id = ?', whereArgs: <Object?>[sudah.first['id']]);
        }

        diunduh++;
      }

      // Produk yang sudah tidak ada / dinonaktifkan di server ikut
      // disembunyikan di HP (hanya untuk sales; pengelola melihat semua).
      if (!pengelola && items.isNotEmpty) {
        final List<Map<String, Object?>> dariServer = await d.query(
          'produk',
          where: 'dari_server = 1 AND aktif = 1',
          columns: <String>['id', 'id_server'],
        );

        for (final Map<String, Object?> p in dariServer) {
          final int idServer = _bulat(p['id_server']);

          if (idServer > 0 && !idServerAda.contains(idServer)) {
            await d.update('produk', <String, Object?>{'aktif': 0, 'perlu_kirim': 0},
                where: 'id = ?', whereArgs: <Object?>[p['id']]);

            dinonaktifkan++;
          }
        }
      }

      await _setelanTulis('sinkron_produk_pada', waktu);
      sampaiServer = true;
    } catch (e) {
      if (!sampaiServer) {
        throw RtsKasirGalat(
          'Sinkron produk gagal: tidak dapat menghubungi server. Periksa '
          'internet HP, lalu coba lagi. (${e is RtsKasirGalat ? e.pesan : e})',
        );
      }
    }

    String pesan = 'Sinkron selesai. $diunduh produk pada daftar bersama '
        'dibaca dari server, $terkirim produk dari HP dikirim ke server.';

    if (dinonaktifkan > 0) {
      pesan += ' $dinonaktifkan produk dinonaktifkan di server sehingga '
          'disembunyikan dari daftar.';
    }

    if (catatanGagal.isNotEmpty) {
      pesan += ' ${catatanGagal.length} produk ditolak server '
          '(barcode kembar): ${catatanGagal.take(3).join('; ')}';
    }

    return <String, dynamic>{
      'success': true,
      'message': pesan,
      'diunduh': diunduh,
      'terkirim': terkirim,
      'dinonaktifkan': dinonaktifkan,
      'gagal': catatanGagal,
    };
  }

  /* ------------------------------------------------------------------- toko */

  /// Menyalin daftar toko dari tabel `master_toko` server ke HP.
  ///
  /// Daftar ini dipakai halaman "Pilih Toko" pada menu Kasir, sehingga toko
  /// yang dipilih benar-benar berasal dari database master_toko. Salinannya
  /// dapat dipakai walaupun HP sedang tanpa internet.
  Future<Map<String, dynamic>> _tokoSegarkan() async {
    if (baseUrl.isEmpty || token.isEmpty) {
      throw RtsKasirGalat('Alamat server belum dikenal. Masuk kembali ke aplikasi.');
    }

    final Database d = await db;

    final Map<String, String> kepala = <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
    };

    final String waktu = _waktu();
    int jumlah = 0;
    int halaman = 1;
    bool lanjut = true;

    while (lanjut && halaman <= 30) {
      final Uri uri = Uri.parse('$baseUrl/customers.php').replace(
        queryParameters: <String, String>{
          'page': '$halaman',
          'limit': '100',
        },
      );

      final http.Response jawab = await http
          .get(uri, headers: kepala)
          .timeout(const Duration(seconds: 45));

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map || urai['success'] != true) {
        throw RtsKasirGalat(
          'Daftar toko tidak dapat dibaca dari server'
          '${urai is Map && urai['message'] != null ? ': ${urai['message']}' : '.'}',
        );
      }

      final List<dynamic> data =
          (urai['data'] is List) ? urai['data'] as List<dynamic> : <dynamic>[];

      if (data.isEmpty) break;

      final Batch kelompok = d.batch();

      for (final dynamic satu in data) {
        if (satu is! Map) continue;

        final Map<String, dynamic> toko = satu.cast<String, dynamic>();
        final String idCustomer = _teks(toko['id_customer'], 40);

        if (idCustomer.isEmpty) continue;

        kelompok.insert(
          'toko',
          <String, Object?>{
            'id_customer': idCustomer,
            'nama': _teks(toko['nama_toko'], 150),
            'alamat': _teks(toko['alamat'], 255),
            'district': _teks(toko['sales_district'], 80),
            'salesman': _teks(toko['salesman'], 80),
            'hp': _teks(toko['nomor_hp'] ?? toko['hp'], 30),
            'tipe': _teks(toko['tipe_customer'], 20).isEmpty
                ? 'REGULER'
                : _teks(toko['tipe_customer'], 20),
            // Titik koordinat & jadwal kunjungan dipakai menu PETA CUSTOMER,
            // RADAR CUSTOMER, dan RUTE PLAN.
            'latitude': _teks(toko['latitude'], 30),
            'longitude': _teks(toko['longitude'], 30),
            'kunjungan': _teks(toko['kunjungan'], 40),
            'hari': _teks(toko['hari'], 30),
            'diperbarui': waktu,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        jumlah++;
      }

      await kelompok.commit(noResult: true);

      final Map<String, dynamic> meta = (urai['meta'] is Map)
          ? (urai['meta'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final bool adaLagi = meta['has_more'] == true;

      lanjut = adaLagi && data.length >= 100;
      halaman++;
    }

    await _setelanTulis('toko_sinkron_pada', waktu);

    return <String, dynamic>{
      'success': true,
      'message': 'Daftar toko dari master_toko tersimpan di HP: $jumlah toko.',
      'jumlah': jumlah,
      'waktu': waktu,
    };
  }

  /// Membaca salinan daftar toko di HP (dapat dipakai tanpa internet).
  Future<Map<String, dynamic>> _tokoDaftar(String cari, int batas) async {
    final Database d = await db;
    final int jumlah = batas < 1 ? 60 : (batas > 300 ? 300 : batas);

    String where = '';
    List<Object?> args = <Object?>[];

    if (cari.isNotEmpty) {
      where = '(nama LIKE ? OR id_customer LIKE ? OR alamat LIKE ?)';
      final String suka = '%$cari%';
      args = <Object?>[suka, suka, suka];
    }

    final List<Map<String, Object?>> baris = await d.query(
      'toko',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'nama ASC',
      limit: jumlah,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      items.add(<String, dynamic>{
        'id': '${b['id_customer'] ?? ''}',
        'id_customer': '${b['id_customer'] ?? ''}',
        'nama': '${b['nama'] ?? ''}',
        'alamat': '${b['alamat'] ?? ''}',
        'district': '${b['district'] ?? ''}',
        'salesman': '${b['salesman'] ?? ''}',
        'hp': '${b['hp'] ?? ''}',
        'tipe': '${b['tipe'] ?? 'REGULER'}',
        'kunjungan': '${b['kunjungan'] ?? ''}',
        'hari': '${b['hari'] ?? ''}',
        'latitude': _angka(b['latitude']),
        'longitude': _angka(b['longitude']),
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} toko pada salinan di HP.',
      'items': items,
      'jumlah': items.length,
      'sinkron_pada': await _setelanBaca('toko_sinkron_pada', ''),
    };
  }

  /* ----------------------------------------------------------------- program */

  /// Bentuk satu produk PROGRAM (INTRODEAL / BD) untuk aplikasi.
  Map<String, dynamic> _programBentuk(Map<String, Object?> baris) {
    return <String, dynamic>{
      'id': _bulat(baris['id']),
      'jenis': '${baris['jenis'] ?? 'INTRODEAL'}',
      'sku': '${baris['sku'] ?? ''}',
      'barcode_pack': '${baris['barcode_pack'] ?? ''}',
      'nama': '${baris['nama'] ?? ''}',
      'merek': '${baris['merek'] ?? ''}',
      'isi_per_pack': _bulat(baris['isi_per_pack']),
      'catatan': '${baris['catatan'] ?? ''}',
      'periode': '${baris['periode'] ?? ''}',
      'aktif': _bulat(baris['aktif']) == 1,
      'dari_server': _bulat(baris['dari_server']) == 1,
      'diubah_pada': '${baris['diubah_pada'] ?? ''}',
    };
  }

  /// Menghitung berapa customer yang sudah membeli satu produk program.
  ///
  /// Pembelian dibaca dari nota kasir yang TERSIMPAN DI HP (tabel penjualan &
  /// penjualan_item). Pencocokan memakai nama produk pada nota, atau SKU /
  /// barcode produk bawaan yang dipakai pada nota tersebut. Jadi Sales dapat
  /// melihat customer mana yang sudah masuk produk launching TANPA mengubah
  /// data apa pun di server.
  Future<Map<String, Object?>> _programHitungToko(
    DatabaseExecutor d, {
    required String nama,
    required String sku,
    required String barcode,
  }) async {
    final List<Map<String, Object?>> baris = await d.rawQuery(
      'SELECT COUNT(DISTINCT j.customer_id) AS jumlah, MAX(j.tanggal) AS terakhir '
          'FROM penjualan_item i '
          'JOIN penjualan j ON j.id = i.penjualan_id '
          'LEFT JOIN produk pr ON pr.id = i.produk_id '
          'WHERE j.dibatalkan = 0 '
          '  AND ( UPPER(i.nama_produk) = UPPER(?) '
          "        OR (pr.sku <> '' AND pr.sku = ?) "
          "        OR (pr.barcode_pack <> '' AND pr.barcode_pack = ?) )",
      <Object?>[nama, sku, barcode],
    );

    if (baris.isEmpty) {
      return <String, Object?>{'jumlah': 0, 'terakhir': ''};
    }

    return <String, Object?>{
      'jumlah': _bulat(baris.first['jumlah']),
      'terakhir': '${baris.first['terakhir'] ?? ''}',
    };
  }

  /// Daftar produk program di HP + jumlah customer yang sudah membelinya.
  Future<Map<String, dynamic>> _programDaftar(String jenis, String cari) async {
    final Database d = await db;

    String where = '';
    final List<Object?> args = <Object?>[];

    final String jns = jenis.toUpperCase();

    if (jns == 'INTRODEAL' || jns == 'BD') {
      where = 'jenis = ?';
      args.add(jns);
    }

    if (cari.isNotEmpty) {
      final String suka = '%$cari%';

      where += where.isEmpty ? '' : ' AND ';
      where += '(nama LIKE ? OR merek LIKE ? OR sku LIKE ? OR barcode_pack LIKE ?)';
      args.addAll(<Object?>[suka, suka, suka, suka]);
    }

    final List<Map<String, Object?>> baris = await d.query(
      'program',
      where: where.isEmpty ? null : where,
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'nama ASC',
      limit: 500,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    int sudahDibeli = 0;

    for (final Map<String, Object?> b in baris) {
      final Map<String, dynamic> satu = _programBentuk(b);
      final Map<String, Object?> hitung = await _programHitungToko(
        d,
        nama: '${satu['nama']}',
        sku: '${satu['sku']}',
        barcode: '${satu['barcode_pack']}',
      );

      satu['jumlah_toko'] = _bulat(hitung['jumlah']);
      satu['terakhir'] = '${hitung['terakhir'] ?? ''}';
      satu['dibeli'] = _bulat(hitung['jumlah']) > 0;

      if (satu['dibeli'] == true) sudahDibeli++;

      items.add(satu);
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} produk program di HP, $sudahDibeli sudah '
          'pernah dibeli customer.',
      'items': items,
      'jumlah': items.length,
      'sudah_dibeli': sudahDibeli,
      'jenis': jns,
    };
  }

  /// Menyimpan / mengubah satu produk program pada salinan di HP.
  Future<Map<String, dynamic>> _programSimpan(Map<String, dynamic> data) async {
    final Database d = await db;

    final int id = _bulat(data['id']);
    final String jenis = _teks(data['jenis'], 20).toUpperCase() == 'BD'
        ? 'BD'
        : 'INTRODEAL';
    final String nama = _teks(data['nama'], 150);
    final String barcode = _teks(data['barcode_pack'], 64);
    String sku = _teks(data['sku'], 64);

    if (nama.length < 2) {
      throw RtsKasirGalat('Nama produk program terlalu pendek.');
    }

    // Bila SKU dikosongkan, dipakai barcode; bila keduanya kosong dipakai nama.
    if (sku.isEmpty) sku = barcode.isNotEmpty ? barcode : nama.toUpperCase();

    final Map<String, Object?> isi = <String, Object?>{
      'jenis': jenis,
      'sku': sku,
      'barcode_pack': barcode,
      'nama': nama,
      'merek': _teks(data['merek'], 80),
      'isi_per_pack': _bulat(data['isi_per_pack']),
      'catatan': _teks(data['catatan'], 255),
      'periode': _teks(data['periode'], 60),
      'aktif': (data['aktif'] == false || _bulat(data['aktif']) == 0) ? 0 : 1,
      'diubah_pada': _waktu(),
    };

    if (id > 0) {
      await d.update('program', isi, where: 'id = ?', whereArgs: <Object?>[id]);
    } else {
      final List<Map<String, Object?>> ada = await d.query(
        'program',
        where: 'jenis = ? AND sku = ?',
        whereArgs: <Object?>[jenis, sku],
        limit: 1,
      );

      if (ada.isNotEmpty) {
        await d.update(
          'program',
          isi,
          where: 'id = ?',
          whereArgs: <Object?>[_bulat(ada.first['id'])],
        );
      } else {
        await d.insert('program', isi);
      }
    }

    return <String, dynamic>{
      'success': true,
      'message': 'Produk program tersimpan di HP.',
      'jenis': jenis,
      'sku': sku,
    };
  }

  /// Menghapus satu produk program dari salinan di HP.
  Future<Map<String, dynamic>> _programHapus(int id) async {
    if (id < 1) {
      throw RtsKasirGalat('Produk program yang ingin dihapus tidak dikenal.');
    }

    final Database d = await db;
    final int jumlah = await d.delete('program', where: 'id = ?', whereArgs: <Object?>[id]);

    return <String, dynamic>{
      'success': true,
      'message': jumlah > 0
          ? 'Produk program dihapus dari HP.'
          : 'Produk program tidak ditemukan.',
      'jumlah': jumlah,
    };
  }

  /// Mengganti SELURUH daftar satu jenis dengan hasil SINKRON ONLINE.
  ///
  /// Daftar lama jenis tersebut dibuang lebih dulu supaya produk yang sudah
  /// tidak di-launching tidak tertinggal di HP.
  Future<Map<String, dynamic>> _programGanti(
    String jenis,
    List<dynamic> items,
  ) async {
    final Database d = await db;
    final String jns = jenis.toUpperCase() == 'BD' ? 'BD' : 'INTRODEAL';
    final String waktu = _waktu();

    await d.delete('program', where: 'jenis = ?', whereArgs: <Object?>[jns]);

    int jumlah = 0;

    for (final dynamic satu in items) {
      if (satu is! Map) continue;

      final Map<String, dynamic> p = satu.cast<String, dynamic>();
      final String nama = _teks(p['nama'], 150);

      if (nama.isEmpty) continue;

      final String barcode = _teks(p['barcode_pack'], 64);
      String sku = _teks(p['sku'], 64);

      if (sku.isEmpty) sku = barcode.isNotEmpty ? barcode : nama.toUpperCase();

      await d.insert('program', <String, Object?>{
        // Seluruh baris pada perintah ini milik satu sub-menu (jns), supaya
        // daftar INTRODEAL dan BD tidak pernah tertukar.
        'jenis': jns,
        'sku': sku,
        'barcode_pack': barcode,
        'nama': nama,
        'merek': _teks(p['merek'], 80),
        'isi_per_pack': _bulat(p['isi_per_pack']),
        'catatan': _teks(p['catatan'], 255),
        'periode': _teks(p['periode'], 60),
        'aktif': (p['aktif'] == false || _bulat(p['aktif']) == 0) ? 0 : 1,
        'dari_server': 1,
        'diubah_pada': waktu,
      });

      jumlah++;
    }

    return <String, dynamic>{
      'success': true,
      'message': '$jumlah produk $jns disimpan di HP dari server.',
      'jumlah': jumlah,
      'jenis': jns,
      'diubah_pada': waktu,
    };
  }

  /// Status program untuk SATU toko: produk mana yang SUDAH dibeli.
  Future<Map<String, dynamic>> _programToko(String idCustomer) async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = await d.query(
      'program',
      orderBy: 'nama ASC',
      limit: 500,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    int sudah = 0;

    for (final Map<String, Object?> b in baris) {
      final Map<String, dynamic> satu = _programBentuk(b);

      final List<Map<String, Object?>> hitung = await d.rawQuery(
        'SELECT COUNT(*) AS jumlah, MAX(j.tanggal) AS terakhir, '
            'MAX(j.nomor) AS nomor '
            'FROM penjualan_item i '
            'JOIN penjualan j ON j.id = i.penjualan_id '
            'LEFT JOIN produk pr ON pr.id = i.produk_id '
            'WHERE j.dibatalkan = 0 AND j.customer_id = ? '
            '  AND ( UPPER(i.nama_produk) = UPPER(?) '
            "        OR (pr.sku <> '' AND pr.sku = ?) "
            "        OR (pr.barcode_pack <> '' AND pr.barcode_pack = ?) )",
        <Object?>[
          idCustomer,
          '${satu['nama']}',
          '${satu['sku']}',
          '${satu['barcode_pack']}',
        ],
      );

      final int jumlah = hitung.isEmpty ? 0 : _bulat(hitung.first['jumlah']);

      satu['dibeli'] = jumlah > 0;
      satu['tanggal_beli'] = hitung.isEmpty ? '' : '${hitung.first['terakhir'] ?? ''}';
      satu['nomor_nota'] = hitung.isEmpty ? '' : '${hitung.first['nomor'] ?? ''}';

      if (jumlah > 0) sudah++;

      items.add(satu);
    }

    return <String, dynamic>{
      'success': true,
      'message': '$sudah dari ${items.length} produk program sudah pernah '
          'dibeli toko ini.',
      'items': items,
      'jumlah': items.length,
      'sudah': sudah,
      'id_customer': idCustomer,
    };
  }

  /* ------------------------------------------------------ peta, radar, rute */

  /// Satu toko beserta titik koordinat dan jadwal kunjungannya.
  Map<String, dynamic> _tokoBentukPeta(Map<String, Object?> b) {
    final double lat = _angka(b['latitude']);
    final double lng = _angka(b['longitude']);

    return <String, dynamic>{
      'id_customer': '${b['id_customer'] ?? ''}',
      'nama': '${b['nama'] ?? ''}',
      'alamat': '${b['alamat'] ?? ''}',
      'district': '${b['district'] ?? ''}',
      'salesman': '${b['salesman'] ?? ''}',
      'hp': '${b['hp'] ?? ''}',
      'tipe': '${b['tipe'] ?? 'REGULER'}',
      'kunjungan': '${b['kunjungan'] ?? ''}',
      'hari': '${b['hari'] ?? ''}',
      'latitude': lat,
      'longitude': lng,
      'bertitik': lat != 0 && lng != 0,
      'diperbarui': '${b['diperbarui'] ?? ''}',
    };
  }

  /// Seluruh toko pada salinan di HP - dipakai PETA CUSTOMER, RADAR, RUTE PLAN.
  Future<Map<String, dynamic>> _tokoPeta() async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = await d.query(
      'toko',
      orderBy: 'nama ASC',
      limit: 5000,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    int bertitik = 0;

    for (final Map<String, Object?> b in baris) {
      final Map<String, dynamic> satu = _tokoBentukPeta(b);

      if (satu['bertitik'] == true) bertitik++;

      items.add(satu);
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} toko pada salinan di HP, $bertitik sudah '
          'memiliki titik koordinat.',
      'items': items,
      'jumlah': items.length,
      'bertitik': bertitik,
      'sinkron_pada': await _setelanBaca('toko_sinkron_pada', ''),
    };
  }

  /* ------------------------------------------------------------ kunjungan */

  Future<Map<String, dynamic>> _kunjunganSimpan(Map<String, dynamic> data) async {
    final Database d = await db;
    final String idCustomer = _teks(data['id_customer'], 40);

    if (idCustomer.isEmpty) {
      throw RtsKasirGalat('Toko belum dipilih.');
    }

    final String waktu = _waktu();

    final int id = await d.insert('kunjungan', <String, Object?>{
      'id_customer': idCustomer,
      'nama': _teks(data['nama'], 150),
      'tanggal': waktu.substring(0, 10),
      'jam': waktu,
      'id_sales': idSales,
      'nama_sales': namaSales,
      'latitude': _angka(data['latitude']),
      'longitude': _angka(data['longitude']),
      'catatan': _teks(data['catatan'], 200),
    });

    final Map<String, dynamic> hari = await _kunjunganHariIni();

    return <String, dynamic>{
      'success': true,
      'message': 'Kunjungan ${_teks(data['nama'], 60)} tercatat pada $waktu.',
      'id': id,
      'waktu': waktu,
      'hari_ini': hari,
    };
  }

  Future<Map<String, dynamic>> _kunjunganHariIni() async {
    final Database d = await db;
    final String tanggal = _waktu().substring(0, 10);

    final List<Map<String, Object?>> baris = await d.query(
      'kunjungan',
      where: 'tanggal = ?',
      whereArgs: <Object?>[tanggal],
      orderBy: 'id DESC',
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];
    final List<String> idCustomer = <String>[];

    for (final Map<String, Object?> b in baris) {
      final String id = '${b['id_customer'] ?? ''}';

      if (id.isNotEmpty && !idCustomer.contains(id)) idCustomer.add(id);

      items.add(<String, dynamic>{
        'id': _bulat(b['id']),
        'id_customer': id,
        'nama': '${b['nama'] ?? ''}',
        'jam': '${b['jam'] ?? ''}',
        'catatan': '${b['catatan'] ?? ''}',
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '$tanggal: ${items.length} kunjungan tercatat.',
      'tanggal': tanggal,
      'items': items,
      'id_customer': idCustomer,
      'jumlah': items.length,
    };
  }

  Future<Map<String, dynamic>> _kunjunganDaftar(
    String idCustomer,
    int batas,
  ) async {
    final Database d = await db;
    final int jumlah = batas < 1 ? 200 : (batas > 500 ? 500 : batas);

    final List<Map<String, Object?>> baris = await d.query(
      'kunjungan',
      where: idCustomer.isEmpty ? null : 'id_customer = ?',
      whereArgs: idCustomer.isEmpty ? null : <Object?>[idCustomer],
      orderBy: 'id DESC',
      limit: jumlah,
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      items.add(<String, dynamic>{
        'id': _bulat(b['id']),
        'id_customer': '${b['id_customer'] ?? ''}',
        'nama': '${b['nama'] ?? ''}',
        'tanggal': '${b['tanggal'] ?? ''}',
        'jam': '${b['jam'] ?? ''}',
        'nama_sales': '${b['nama_sales'] ?? ''}',
        'catatan': '${b['catatan'] ?? ''}',
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} catatan kunjungan.',
      'items': items,
      'jumlah': items.length,
    };
  }

  Future<Map<String, dynamic>> _kunjunganHapus(int id) async {
    final Database d = await db;

    await d.delete('kunjungan', where: 'id = ?', whereArgs: <Object?>[id]);

    return <String, dynamic>{
      'success': true,
      'message': 'Catatan kunjungan dihapus.',
    };
  }

  /* ------------------------------------------------------- lokasi kantor */

  Map<String, dynamic> _kantorBentuk(Map<String, Object?> b) {
    return <String, dynamic>{
      'id': _bulat(b['id']),
      'id_server': _bulat(b['id_server']),
      'nama': '${b['nama'] ?? ''}',
      'alamat': '${b['alamat'] ?? ''}',
      'district': '${b['district'] ?? ''}',
      'latitude': _angka(b['latitude']),
      'longitude': _angka(b['longitude']),
      'catatan': '${b['catatan'] ?? ''}',
      'diubah_pada': '${b['diubah_pada'] ?? ''}',
      'dari_server': _bulat(b['dari_server']) == 1,
    };
  }

  Future<Map<String, dynamic>> _kantorDaftar() async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = await d.query(
      'kantor',
      orderBy: 'nama ASC',
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      items.add(_kantorBentuk(b));
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} titik lokasi kantor / mitra.',
      'items': items,
      'jumlah': items.length,
      'sinkron_pada': await _setelanBaca('kantor_sinkron_pada', ''),
      'pengelola': pengelola,
    };
  }

  /// Menyalin titik lokasi kantor dari server (tabel `rts_kantor`).
  /// Titik disimpan di HP supaya RUTE PLAN tetap dapat dihitung luring.
  Future<Map<String, dynamic>> _kantorSegarkan() async {
    if (baseUrl.isEmpty || token.isEmpty) {
      throw RtsKasirGalat('Alamat server belum dikenal. Masuk kembali ke aplikasi.');
    }

    final Database d = await db;

    final http.Response jawab = await http.get(
      Uri.parse('$baseUrl/kantor.php?aksi=daftar'),
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    ).timeout(const Duration(seconds: 30));

    final dynamic urai = jsonDecode(jawab.body);

    if (urai is! Map || urai['success'] != true) {
      throw RtsKasirGalat(
        'Titik lokasi kantor tidak dapat dibaca dari server. Pastikan berkas '
        'api/kantor.php sudah diunggah dan tabel rts_kantor sudah dibuat.',
      );
    }

    final List<dynamic> data =
        (urai['items'] is List) ? urai['items'] as List<dynamic> : <dynamic>[];

    // Titik dari server diganti; titik yang dibuat di HP (bila ada) dibiarkan.
    await d.delete('kantor', where: 'dari_server = 1');

    final Batch kelompok = d.batch();
    final String waktu = _waktu();

    for (final dynamic satu in data) {
      if (satu is! Map) continue;

      final Map<String, dynamic> k = satu.cast<String, dynamic>();

      kelompok.insert('kantor', <String, Object?>{
        'id_server': _bulat(k['id']),
        'nama': _teks(k['nama'], 120),
        'alamat': _teks(k['alamat'], 255),
        'district': _teks(k['district'], 120),
        'latitude': _angka(k['latitude']),
        'longitude': _angka(k['longitude']),
        'catatan': _teks(k['catatan'], 200),
        'diubah_pada': _teks(k['diubah_pada'], 30),
        'dari_server': 1,
        'diperbarui': waktu,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await kelompok.commit(noResult: true);
    await _setelanTulis('kantor_sinkron_pada', waktu);

    final Map<String, dynamic> daftar = await _kantorDaftar();

    return <String, dynamic>{
      'success': true,
      'message': 'Titik lokasi kantor disegarkan dari server: '
          '${data.length} titik.',
      'waktu': waktu,
      ...daftar,
    };
  }

  /// Menyimpan titik lokasi kantor / mitra (hanya ADMIN & ASS).
  /// Titik disimpan di server (tabel `rts_kantor`) lalu disalin ke HP.
  Future<Map<String, dynamic>> _kantorSimpan(Map<String, dynamic> data) async {
    if (!pengelola) {
      throw RtsKasirGalat(
        'Titik lokasi kantor hanya dapat diatur oleh ADMIN atau ASS.',
      );
    }

    if (baseUrl.isEmpty || token.isEmpty) {
      throw RtsKasirGalat('Alamat server belum dikenal. Masuk kembali ke aplikasi.');
    }

    final String nama = _teks(data['nama'], 120);
    final String alamat = _teks(data['alamat'], 255);
    final String district = _teks(data['district'], 120);
    final String catatan = _teks(data['catatan'], 200);
    final double lat = _angka(data['latitude']);
    final double lng = _angka(data['longitude']);

    if (nama.isEmpty) {
      throw RtsKasirGalat('Nama kantor / mitra belum diisi.');
    }

    if (lat == 0 && lng == 0) {
      throw RtsKasirGalat(
        'Titik lokasi belum ada. Tekan AMBIL TITIK DARI LOKASI SAYA atau isi '
        'lintang dan bujur kantor.',
      );
    }

    final Database d = await db;
    final int id = _bulat(data['id']);
    final int idServer = _bulat(data['id_server']);
    final String waktu = _waktu();
    int idServerBaru = idServer;

    try {
      final http.Response jawab = await http.post(
        Uri.parse('$baseUrl/kantor.php?aksi=simpan'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'id': idServer,
          'nama': nama,
          'alamat': alamat,
          'district': district,
          'latitude': lat,
          'longitude': lng,
          'catatan': catatan,
        }),
      ).timeout(const Duration(seconds: 30));

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map || urai['success'] != true) {
        throw RtsKasirGalat(
          urai is Map && urai['message'] != null
              ? '${urai['message']}'
              : 'Titik lokasi kantor gagal disimpan di server.',
        );
      }

      idServerBaru = _bulat(urai['id']);

      if (idServerBaru < 1 && urai['kantor'] is Map) {
        idServerBaru = _bulat((urai['kantor'] as Map)['id']);
      }
    } on RtsKasirGalat {
      rethrow;
    } catch (_) {
      throw RtsKasirGalat(
        'Titik lokasi kantor perlu disimpan saat ada internet. Sambungkan '
        'internet, lalu tekan SIMPAN kembali.',
      );
    }

    final Map<String, Object?> nilai = <String, Object?>{
      'id_server': idServerBaru,
      'nama': nama,
      'alamat': alamat,
      'district': district,
      'latitude': lat,
      'longitude': lng,
      'catatan': catatan,
      'diubah_pada': waktu,
      'dari_server': 1,
      'diperbarui': waktu,
    };

    if (id > 0) {
      await d.update(
        'kantor',
        nilai,
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
    } else {
      await d.insert('kantor', nilai);
    }

    final Map<String, dynamic> daftar = await _kantorDaftar();

    return <String, dynamic>{
      'success': true,
      'message': 'Titik lokasi "$nama" tersimpan di server dan di HP.',
      'id_server': idServerBaru,
      ...daftar,
    };
  }

  /// Menghapus titik lokasi kantor (hanya ADMIN & ASS).
  Future<Map<String, dynamic>> _kantorHapus(Map<String, dynamic> data) async {
    if (!pengelola) {
      throw RtsKasirGalat(
        'Titik lokasi kantor hanya dapat dihapus oleh ADMIN atau ASS.',
      );
    }

    final Database d = await db;
    final int id = _bulat(data['id']);
    final int idServer = _bulat(data['id_server']);

    if (idServer > 0 && baseUrl.isNotEmpty && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse('$baseUrl/kantor.php?aksi=hapus'),
          headers: <String, String>{
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(<String, dynamic>{'id': idServer}),
        ).timeout(const Duration(seconds: 30));
      } catch (_) {
        throw RtsKasirGalat(
          'Penghapusan titik kantor perlu internet. Sambungkan internet, lalu '
          'coba lagi.',
        );
      }
    }

    await d.delete('kantor', where: 'id = ?', whereArgs: <Object?>[id]);

    final Map<String, dynamic> daftar = await _kantorDaftar();

    return <String, dynamic>{
      'success': true,
      'message': 'Titik lokasi kantor dihapus.',
      ...daftar,
    };
  }

  /* -------------------------------------------- goresan pensil rute (HP) */

  Future<Map<String, dynamic>> _goresDaftar() async {
    final Database d = await db;

    final List<Map<String, Object?>> baris = await d.query(
      'peta_gores',
      orderBy: 'id DESC',
    );

    final List<Map<String, dynamic>> items = <Map<String, dynamic>>[];

    for (final Map<String, Object?> b in baris) {
      items.add(<String, dynamic>{
        'id': _bulat(b['id']),
        'nama': '${b['nama'] ?? ''}',
        'warna': _bulat(b['warna']),
        'tebal': _angka(b['tebal']),
        'titik': '${b['titik'] ?? ''}',
        'jumlah': _bulat(b['jumlah']),
        'dibuat': '${b['dibuat'] ?? ''}',
      });
    }

    return <String, dynamic>{
      'success': true,
      'message': '${items.length} goresan rute tersimpan di HP.',
      'items': items,
      'jumlah': items.length,
    };
  }

  Future<Map<String, dynamic>> _goresSimpan(Map<String, dynamic> data) async {
    final Database d = await db;
    final dynamic titik = data['titik'];
    final List<dynamic> daftar = (titik is List) ? titik : <dynamic>[];

    final List<List<double>> rapi = <List<double>>[];

    for (final dynamic satu in daftar) {
      if (satu is! List || satu.length < 2) continue;

      rapi.add(<double>[_angka(satu[0]), _angka(satu[1])]);

      if (rapi.length >= 2000) break;
    }

    if (rapi.length < 2) {
      throw RtsKasirGalat('Goresan terlalu pendek untuk disimpan.');
    }

    String nama = _teks(data['nama'], 80);

    if (nama.isEmpty) nama = 'Goresan ${_waktu()}';

    final int id = await d.insert('peta_gores', <String, Object?>{
      'nama': nama,
      'warna': _bulat(data['warna']),
      'tebal': _angka(data['tebal']) <= 0 ? 4 : _angka(data['tebal']),
      'titik': jsonEncode(rapi),
      'jumlah': rapi.length,
      'id_sales': idSales,
      'dibuat': _waktu(),
    });

    final Map<String, dynamic> daftarGores = await _goresDaftar();

    return <String, dynamic>{
      'success': true,
      'message': 'Goresan "$nama" tersimpan (${rapi.length} titik).',
      'id': id,
      ...daftarGores,
    };
  }

  Future<Map<String, dynamic>> _goresHapus(int id) async {
    final Database d = await db;

    await d.delete('peta_gores', where: 'id = ?', whereArgs: <Object?>[id]);

    final Map<String, dynamic> daftarGores = await _goresDaftar();

    return <String, dynamic>{
      'success': true,
      'message': 'Goresan rute dihapus.',
      ...daftarGores,
    };
  }

  Future<Map<String, dynamic>> _goresHapusSemua() async {
    final Database d = await db;

    await d.delete('peta_gores');

    return <String, dynamic>{
      'success': true,
      'message': 'Seluruh goresan rute di HP dihapus.',
      'items': <Map<String, dynamic>>[],
      'jumlah': 0,
    };
  }

  /// Folder berkas cadangan. Diletakkan pada folder aplikasi di penyimpanan HP
  /// supaya tidak memerlukan izin tambahan.
  Future<Directory> _folderCadangan() async {
    Directory? dasar;

    try {
      dasar = await getExternalStorageDirectory();
    } catch (_) {
      dasar = null;
    }

    dasar ??= await getApplicationDocumentsDirectory();

    final Directory folder = Directory(p.join(dasar.path, 'cadangan'));

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    return folder;
  }

  Future<Map<String, dynamic>> _cadanganInfo() async {
    final String sinkron = await _setelanBaca('sinkron_pada', '');
    final List<Map<String, dynamic>> berkas = <Map<String, dynamic>>[];

    try {
      final Directory folder = await _folderCadangan();

      final List<FileSystemEntity> isi = await folder.list().toList();

      for (final FileSystemEntity f in isi) {
        if (f is! File) continue;
        if (!f.path.toLowerCase().endsWith('.db')) continue;

        final FileStat stat = await f.stat();

        berkas.add(<String, dynamic>{
          'nama': p.basename(f.path),
          'ukuran': stat.size,
          'ukuran_teks': '${(stat.size / 1024).round()} KB',
          'waktu': '${stat.modified}'.substring(0, 16),
          'jalur': f.path,
        });
      }

      berkas.sort((Map<String, dynamic> a, Map<String, dynamic> b) =>
          '${b['nama']}'.compareTo('${a['nama']}'));
    } catch (_) {
      // daftar kosong
    }

    final Database d = await db;

    final List<Map<String, Object?>> jual = await d.rawQuery(
      'SELECT COUNT(*) AS jumlah FROM penjualan WHERE id_sales = ?',
      <Object?>[idSales],
    );

    final List<Map<String, Object?>> piut = await d.rawQuery(
      'SELECT COUNT(*) AS jumlah FROM piutang WHERE id_sales = ?',
      <Object?>[idSales],
    );

    final List<Map<String, Object?>> prod =
        await d.rawQuery('SELECT COUNT(*) AS jumlah FROM produk');

    String folder = '';

    try {
      folder = (await _folderCadangan()).path;
    } catch (_) {
      folder = '';
    }

    return <String, dynamic>{
      'success': true,
      'message': 'Data tersimpan di HP.',
      'berkas': berkas,
      'jumlah_berkas': berkas.length,
      'folder': folder,
      'sinkron_terakhir': sinkron,
      'jumlah_produk': _bulat(prod.isEmpty ? 0 : prod.first['jumlah']),
      'jumlah_nota': _bulat(jual.isEmpty ? 0 : jual.first['jumlah']),
      'jumlah_piutang': _bulat(piut.isEmpty ? 0 : piut.first['jumlah']),
    };
  }

  Future<Map<String, dynamic>> _cadangkan() async {
    final Database d = await db;

    // Data ditulis ke cakram lebih dahulu supaya berkas cadangan lengkap.
    await d.rawQuery('PRAGMA wal_checkpoint(FULL)').catchError((Object _) => <Map<String, Object?>>[]);

    final Directory folder = await _folderCadangan();
    final String sumber = await jalurDatabase();

    final DateTime t = DateTime.now();

    final String nama = 'rts_panel_cadangan_${t.year}${_dua(t.month)}${_dua(t.day)}'
        '_${_dua(t.hour)}${_dua(t.minute)}${_dua(t.second)}.db';

    final File tujuan = File(p.join(folder.path, nama));

    await File(sumber).copy(tujuan.path);

    final FileStat stat = await tujuan.stat();

    return <String, dynamic>{
      'success': true,
      'message': 'Cadangan dibuat: $nama (${(stat.size / 1024).round()} KB). '
          'Simpan berkas ini ke Google Drive atau kirim ke diri sendiri agar '
          'aman bila HP hilang.',
      'nama': nama,
      'jalur': tujuan.path,
      'folder': folder.path,
    };
  }

  Future<Map<String, dynamic>> _pulihkan(String nama) async {
    if (nama.isEmpty) {
      throw RtsKasirGalat('Berkas cadangan belum dipilih.');
    }

    final Directory folder = await _folderCadangan();
    final File sumber = File(p.join(folder.path, p.basename(nama)));

    if (!await sumber.exists()) {
      throw RtsKasirGalat('Berkas cadangan tidak ditemukan.');
    }

    // Berkas diperiksa lebih dahulu: harus berupa database SQLite yang memuat
    // tabel produk. Jadi berkas yang salah tidak akan merusak data.
    Database? uji;

    try {
      uji = await openDatabase(sumber.path, readOnly: true);
      await uji.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'produk'",
      );
    } catch (e) {
      try {
        await uji?.close();
      } catch (_) {}

      throw RtsKasirGalat('Berkas cadangan tidak dapat dibaca atau bukan berkas RTS Panel.');
    }

    final bool sah = (await uji.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'produk'",
    ))
        .isNotEmpty;

    await uji.close();

    if (!sah) {
      throw RtsKasirGalat('Berkas cadangan tidak memuat data RTS Panel.');
    }

    // Database lama disalin ke berkas .sebelum agar masih dapat dikembalikan.
    final String jalur = await jalurDatabase();

    try {
      await _db?.close();
    } catch (_) {}

    _db = null;

    if (await File(jalur).exists()) {
      await File(jalur).copy('$jalur.sebelum');
    }

    await sumber.copy(jalur);

    await siapkanTabel();

    return <String, dynamic>{
      'success': true,
      'message': 'Data berhasil dipulihkan dari $nama. Data sebelum pemulihan '
          'disimpan sebagai berkas .sebelum.',
    };
  }
}
