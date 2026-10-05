// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : PROGRAM (INTRODEAL & BD)
//  Berkas : lib/program.dart
//  Versi  : 2   (5 Oktober 2026 - Putaran 18H)
//
//  ISI BERKAS INI
//  --------------
//      RtsProgramPage - menu PRO "Program" dengan DUA sub-menu:
//          INTRODEAL : Introductory Deal, yaitu PROGRAM PAKET
//                      (paket baku 2+1 dan 1+1, ditambah PAKET SENDIRI yang
//                      dibuat Sales sendiri, misalnya 3+1)
//          BD        : New Brand Distribution - TIDAK memakai paket, karena
//                      produknya adalah produk baru yang sudah ada di outlet
//
//  KEGUNAAN (sesuai permintaan Bapak)
//  ----------------------------------
//  PT Wismilak selalu meluncurkan produk baru, jadi Sales perlu melihat apakah
//  setiap toko SUDAH atau BELUM masuk produk launching. Halaman ini:
//      1. menyimpan daftar produk program di HP (SQLite),
//      2. dapat diisi dari MENU BARANG BAWAAN (satu tekan) atau disinkron dari
//         server lewat tombol SINKRON ONLINE (api/program.php),
//      3. menunjukkan jumlah customer yang sudah membeli tiap produk (dihitung
//         dari nota kasir yang tersimpan di HP),
//      4. dapat memilih TOKO TERDEKAT dari posisi HP (sama seperti Kasir dan
//         Piutang), lalu menampilkan status SUDAH / BELUM per produk,
//      5. ADMIN / ASS dapat mengirim daftar ke server supaya dipakai HP lain,
//      6. [BARU 18H] mencatat INPUT PROGRAM langsung dari HP (CATAT PROGRAM)
//         walau TIDAK ADA internet; catatan tersimpan di HP lalu dikirim ke
//         server lewat tombol CATATAN TERSIMPAN -> KIRIM KE SERVER,
//      7. [BARU 18H] PETA & FILTER: peta OpenStreetMap + penyaring
//         INTRODEAL / BD, penyaring KUNJUNGAN (sudah/belum), dan
//         penyaring HARI kunjungan.
//
//  CATATAN
//  -------
//  - Berkas ini memakai peta.dart untuk ubin OpenStreetMap dan warna hari,
//    supaya tampilan peta sama dengan menu Peta Customer / Radar / Rute Plan.
//  - Seluruh nama dan pesan memakai Bahasa Indonesia yang mudah dibaca sales.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'kasir.dart';
import 'kasir_lokal.dart';
import 'peta.dart';

/// Dua sub-menu Program.
const List<String> rtsProgramJenis = <String>['INTRODEAL', 'BD'];

/// Judul sub-menu.
String rtsProgramJudul(String jenis) =>
    jenis.toUpperCase() == 'BD' ? 'BD' : 'INTRODEAL';

/// Keterangan singkat sub-menu.
String rtsProgramKeterangan(String jenis) => jenis.toUpperCase() == 'BD'
    ? 'Produk Business Development'
    : 'Produk launching yang sedang diperkenalkan';

/// Halaman menu PRO "Program" (Introdeal & BD).
class RtsProgramPage extends StatefulWidget {
  const RtsProgramPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
    this.jenisAwal = '',
    this.paketAwal = '',
    this.bukaAwal = '',
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  /// Sub-menu yang langsung dibuka: 'INTRODEAL' atau 'BD' (boleh kosong).
  final String jenisAwal;

  /// Paket yang langsung dipilih, contoh '2+1' atau '1+1' (boleh kosong).
  final String paketAwal;

  /// Layar yang langsung dibuka: '' daftar program, 'input' catat program,
  /// 'peta' peta & filter.
  final String bukaAwal;

  @override
  State<RtsProgramPage> createState() => _RtsProgramPageState();
}

class _RtsProgramPageState extends State<RtsProgramPage> {
  late final RtsKasirApi _api = RtsKasirApi(
    baseUrl: widget.baseUrl,
    token: widget.token,
    pengguna: widget.pengguna,
  );

  String _jenis = 'INTRODEAL';

  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];
  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  String _catatan = '';

  /// Toko yang sedang dilihat (dipilih dari daftar TERDEKAT).
  Map<String, dynamic>? _toko;

  /// Status per produk untuk toko terpilih: kunci = 'jenis|sku'.
  Map<String, Map<String, dynamic>> _statusToko = <String, Map<String, dynamic>>{};

  /// Paket Introdeal yang sedang dipakai (2+1, 1+1, atau paket buatan Sales).
  String _paket = '2+1';

  /// Daftar paket Introdeal di HP (bawaan + paket buatan Sales).
  List<Map<String, dynamic>> _paketItems = <Map<String, dynamic>>[];

  /// Jumlah catatan program yang masih tersimpan di HP (belum dikirim).
  int _catatanBelumKirim = 0;

  /// Titik posisi Sales (dipakai peta & penghitung jarak).
  double? _sayaLat;
  double? _sayaLng;

  /// True bila akun boleh MENGUBAH daftar di server (ADMIN / ASS).
  bool get _pengelola {
    final String peran = '${widget.pengguna['role'] ?? ''}'.toUpperCase();

    return peran == 'ADMIN' || peran == 'ASS';
  }

  @override
  void initState() {
    super.initState();

    final String jenis = widget.jenisAwal.toUpperCase();

    if (jenis == 'BD' || jenis == 'INTRODEAL') _jenis = jenis;
    if (widget.paketAwal.isNotEmpty) _paket = widget.paketAwal.toUpperCase();

    unawaited(_buka());
  }

  /// Memuat daftar lalu membuka layar yang diminta menu utama (bila ada).
  Future<void> _buka() async {
    await _muat();

    if (!mounted) return;

    if (widget.bukaAwal == 'input') await _catatProgram();
    if (widget.bukaAwal == 'peta') await _petaFilter();
  }

  String _kunci(Map<String, dynamic> p) =>
      '${p['jenis']}|${p['sku']}';

  /* -------------------------------------------------------------------- muat */

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('program_daftar', <String, dynamic>{
        'jenis': _jenis,
      });

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _items = items
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
        _catatan = '${hasil['message'] ?? ''}';
        _memuat = false;
      });

      if (_toko != null) await _muatStatusToko();

      await _muatPaket();
      await _hitungLencana();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
      });
    }
  }

  /// Status SUDAH / BELUM untuk toko yang sedang dipilih.
  Future<void> _muatStatusToko() async {
    final Map<String, dynamic>? toko = _toko;

    if (toko == null) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('program_toko', <String, dynamic>{
        'id_customer': '${toko['id']}',
      });

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _statusToko = <String, Map<String, dynamic>>{
          for (final dynamic satu in items)
            if (satu is Map)
              _kunci(satu.cast<String, dynamic>()): <String, dynamic>{
                'dibeli': satu['dibeli'] == true,
                'tanggal': '${satu['tanggal_beli'] ?? ''}',
                'nomor': '${satu['nomor_nota'] ?? ''}',
              },
        };
      });
    } on RtsKasirGalat {
      // status toko gagal dibaca: daftar produk tetap tampil
    }
  }

  /* ----------------------------------------------------------- sinkron online */

  Future<Map<String, dynamic>?> _server(String aksi,
      {Map<String, String> data = const <String, String>{}}) async {
    if (widget.baseUrl.isEmpty || widget.token.isEmpty) {
      throw RtsKasirGalat('Alamat server belum dikenal. Masuk kembali ke aplikasi.');
    }

    final Uri uri = Uri.parse('$widget.baseUrl/program.php').replace(
      queryParameters: <String, String>{'aksi': aksi, ...data},
    );

    final http.Response jawab = await http.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'Authorization': 'Bearer ${widget.token}',
      },
    ).timeout(const Duration(seconds: 45));

    dynamic urai;

    try {
      urai = jsonDecode(jawab.body);
    } catch (_) {
      throw RtsKasirGalat('Balasan server tidak dapat dibaca (kode ${jawab.statusCode}).');
    }

    if (urai is! Map) {
      throw RtsKasirGalat('Balasan server tidak dikenal.');
    }

    final Map<String, dynamic> balasan = urai.cast<String, dynamic>();

    if (balasan['success'] != true) {
      final String pesan = '${balasan['message'] ?? 'Permintaan ditolak server.'}';

      if (balasan['perlu_pro'] == true) {
        throw RtsKasirGalat('Menu Program khusus AKUN PRO. $pesan');
      }

      throw RtsKasirGalat(pesan);
    }

    return balasan;
  }

  /// Mengambil daftar produk program dari server, lalu menyimpannya di HP.
  Future<void> _sinkronOnline() async {
    if (_sibuk) return;

    setState(() {
      _sibuk = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic>? balasan = await _server(
        'daftar',
        data: <String, String>{'jenis': _jenis},
      );

      if (balasan == null) return;

      if (balasan['perlu_tabel'] == true) {
        if (!mounted) return;

        setState(() {
          _sibuk = false;
          _catatan = '${balasan['catatan'] ?? 'Tabel program belum ada di server.'}';
        });

        await _tampilkanPerintahSql('${balasan['sql'] ?? ''}');
        return;
      }

      final List<dynamic> items =
          (balasan['items'] is List) ? balasan['items'] as List<dynamic> : <dynamic>[];

      final Map<String, dynamic> simpan =
          await _api.kirim('program_ganti', <String, dynamic>{
        'jenis': _jenis,
        'items': items,
      });

      if (!mounted) return;

      rtsKsPesan(
        context,
        items.isEmpty
            ? 'Server belum memuat produk $_jenis. Daftar di HP dikosongkan.'
            : '${simpan['message'] ?? '$_jenis disinkron.'}',
      );

      setState(() => _sibuk = false);

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _galat = e.pesan;
      });
    }
  }

  /// Menampilkan perintah SQL pembuat tabel (untuk ADMIN lewat phpMyAdmin).
  Future<void> _tampilkanPerintahSql(String sql) async {
    if (sql.trim().isEmpty) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Tabel program belum ada di server',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Tekan SALIN SQL, lalu tempel di phpMyAdmin (menu SQL) pada '
                'database Bapak. Sesudah itu tekan SINKRON ONLINE lagi.',
                style: TextStyle(fontSize: 12, height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: rtsKsLatar,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: rtsKsGaris),
                ),
                child: SelectableText(
                  sql,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: sql));

              if (ctx.mounted) rtsKsPesan(ctx, 'Perintah SQL disalin.');
            },
            child: const Text('SALIN SQL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('TUTUP'),
          ),
        ],
      ),
    );
  }

  /* --------------------------------------------------------- ambil dari produk */

  /// Memilih produk dari MENU BARANG BAWAAN, lalu menyimpannya sebagai program.
  Future<void> _ambilDariBarangBawaan() async {
    List<Map<String, dynamic>> bawaan = <Map<String, dynamic>>[];

    try {
      final Map<String, dynamic> hasil = await _api.kirim('produk_daftar', <String, dynamic>{
        'batas': 500,
      });

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      bawaan = items
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
          .toList();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);

      return;
    }

    if (!mounted) return;

    if (bawaan.isEmpty) {
      rtsKsPesan(
        context,
        'Barang Bawaan masih kosong. Buka menu Barang Bawaan lalu isi produk & '
        'sinkron produk terlebih dahulu.',
        galat: true,
      );

      return;
    }

    final Map<String, dynamic>? pilih =
        await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Ambil dari Barang Bawaan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: ListView.separated(
            itemCount: bawaan.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (BuildContext ctx2, int i) {
              final Map<String, dynamic> p = bawaan[i];

              return ListTile(
                dense: true,
                title: Text(
                  '${p['nama']}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  rtsKsSambung(
                    rtsKsSambung('${p['merek']}', 'SKU ${p['sku']}'),
                    '${p['isi_per_pack']} batang/pack',
                  ),
                  style: const TextStyle(fontSize: 11.5),
                ),
                onTap: () => Navigator.of(ctx2).pop(p),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('TUTUP'),
          ),
        ],
      ),
    );

    if (pilih == null || !mounted) return;

    await _formProduk(awal: <String, dynamic>{
      'jenis': _jenis,
      'nama': '${pilih['nama']}',
      'merek': '${pilih['merek']}',
      'sku': '${pilih['sku']}',
      'barcode_pack': '${pilih['barcode_pack']}',
      'isi_per_pack': pilih['isi_per_pack'],
      'catatan': 'Diambil dari Barang Bawaan',
    });
  }

  /* ------------------------------------------------------------ form produk */

  /// Form tambah / ubah satu produk program.
  Future<void> _formProduk({Map<String, dynamic>? awal, Map<String, dynamic>? ada}) async {
    final Map<String, dynamic> isi = ada ?? awal ?? <String, dynamic>{'jenis': _jenis};

    final TextEditingController nama =
        TextEditingController(text: '${isi['nama'] ?? ''}');
    final TextEditingController merek =
        TextEditingController(text: '${isi['merek'] ?? ''}');
    final TextEditingController sku =
        TextEditingController(text: '${isi['sku'] ?? ''}');
    final TextEditingController barcode =
        TextEditingController(text: '${isi['barcode_pack'] ?? ''}');
    final TextEditingController jumlahIsi =
        TextEditingController(text: '${isi['isi_per_pack'] ?? 0}');
    final TextEditingController periode =
        TextEditingController(text: '${isi['periode'] ?? ''}');
    final TextEditingController catatan =
        TextEditingController(text: '${isi['catatan'] ?? ''}');

    bool aktif = isi['aktif'] != false;
    String jenis = '${isi['jenis'] ?? _jenis}'.toUpperCase() == 'BD' ? 'BD' : 'INTRODEAL';

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter ubah) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            ada == null ? 'Tambah Produk Program' : 'Ubah Produk Program',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 430,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: jenis,
                    decoration: const InputDecoration(
                      labelText: 'Sub-menu',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final String j in rtsProgramJenis)
                        DropdownMenuItem<String>(
                          value: j,
                          child: Text('$j - ${rtsProgramKeterangan(j)}'),
                        ),
                    ],
                    onChanged: (String? nilai) {
                      if (nilai != null) ubah(() => jenis = nilai);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nama,
                    decoration: const InputDecoration(
                      labelText: 'Nama produk',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: merek,
                    decoration: const InputDecoration(
                      labelText: 'Merek',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: sku,
                    decoration: const InputDecoration(
                      labelText: 'SKU / kode produk (boleh kosong)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: barcode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Barcode bungkus (boleh kosong)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: jumlahIsi,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Isi per pack (batang)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: periode,
                    decoration: const InputDecoration(
                      labelText: 'Periode launching (contoh: Oktober 2026)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: catatan,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Catatan',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: aktif,
                    title: const Text('Produk aktif ditawarkan'),
                    onChanged: (bool nilai) => ubah(() => aktif = nilai),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('BATAL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () async {
                try {
                  final Map<String, dynamic> hasil =
                      await _api.kirim('program_simpan', <String, dynamic>{
                    'id': isi['id'] ?? 0,
                    'jenis': jenis,
                    'nama': nama.text,
                    'merek': merek.text,
                    'sku': sku.text,
                    'barcode_pack': barcode.text,
                    'isi_per_pack': jumlahIsi.text,
                    'periode': periode.text,
                    'catatan': catatan.text,
                    'aktif': aktif,
                  });

                  if (ctx.mounted) Navigator.of(ctx).pop();

                  if (!mounted) return;

                  rtsKsPesan(context, '${hasil['message'] ?? 'Produk disimpan.'}');

                  setState(() => _jenis = jenis);

                  await _muat();
                } on RtsKasirGalat catch (e) {
                  if (ctx.mounted) rtsKsPesan(ctx, e.pesan, galat: true);
                }
              },
              child: const Text('SIMPAN'),
            ),
          ],
        ),
      ),
    );

    nama.dispose();
    merek.dispose();
    sku.dispose();
    barcode.dispose();
    jumlahIsi.dispose();
    periode.dispose();
    catatan.dispose();
  }

  /* ------------------------------------------------------------ hapus & kirim */

  Future<void> _hapus(Map<String, dynamic> p) async {
    final bool setuju = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Hapus produk program?'),
            content: Text('${p['nama']} akan dihapus dari daftar di HP.'),
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
        ) ??
        false;

    if (!setuju || !mounted) return;

    try {
      await _api.kirim('program_hapus', <String, dynamic>{'id': p['id']});

      if (!mounted) return;

      rtsKsPesan(context, 'Produk program dihapus dari HP.');

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Mengirim satu produk ke server (hanya ADMIN / ASS).
  Future<void> _kirimKeServer(Map<String, dynamic> p) async {
    try {
      await _server('simpan', data: <String, String>{
        'jenis': '${p['jenis']}',
        'sku': '${p['sku']}',
        'barcode_pack': '${p['barcode_pack']}',
        'nama': '${p['nama']}',
        'merek': '${p['merek']}',
        'isi_per_pack': '${p['isi_per_pack']}',
        'catatan': '${p['catatan']}',
        'periode': '${p['periode']}',
        'aktif': p['aktif'] == false ? '0' : '1',
      });

      if (!mounted) return;

      rtsKsPesan(context, '${p['nama']} dikirim ke server.');
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /* ------------------------------------------------------------- pilih toko */

  /// Memilih toko dari Master Customer - daftar diurutkan dari yang TERDEKAT.
  Future<void> _pilihToko() async {
    final Map<String, dynamic>? toko =
        await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => RtsPilihCustomerPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          pengguna: widget.pengguna,
        ),
      ),
    );

    if (toko == null || !mounted) return;

    final Map<String, dynamic> lengkap = await _lengkapiToko(toko);

    if (!mounted) return;

    setState(() => _toko = lengkap);

    await _muatStatusToko();
  }

  /* ------------------------------------------------------------ paket introdeal */

  /// Membaca daftar paket Introdeal dari HP: 2+1, 1+1, dan paket buatan Sales.
  Future<void> _muatPaket() async {
    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('paket_daftar', <String, dynamic>{'jenis': _jenis});

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _paketItems = items
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();

        if (_jenis == 'BD') {
          _paket = '';
        } else if (_paket.isEmpty ||
            !_paketItems.any((Map<String, dynamic> p) => '${p['nama']}' == _paket)) {
          _paket = _paketItems.isEmpty ? '' : '${_paketItems.first['nama']}';
        }
      });
    } on RtsKasirGalat {
      // Daftar paket tidak terbaca: sub-menu tetap dapat dipakai.
    }
  }

  /// Keterangan paket yang sedang dipakai (mis. "Beli 2 gratis 1").
  String _keteranganPaket(String nama) {
    for (final Map<String, dynamic> p in _paketItems) {
      if ('${p['nama']}' == nama) return '${p['keterangan'] ?? ''}';
    }

    return '';
  }

  /// Sales membuat paket sendiri (contoh: 3+1) untuk program INTRODEAL.
  Future<void> _formPaket() async {
    final TextEditingController nama = TextEditingController();
    final TextEditingController keterangan = TextEditingController();

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Buat paket sendiri'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Paket ini dipakai pada program INTRODEAL, contoh 3+1 '
                '(beli 3 gratis 1). Paket tersimpan di HP dan dapat dipakai '
                'seperti paket baku 2+1 dan 1+1.',
                style: TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nama,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nama paket (contoh: 3+1)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keterangan,
                decoration: const InputDecoration(
                  labelText: 'Keterangan (contoh: Beli 3 gratis 1)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );

    if (simpan != true || !mounted) return;

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('paket_simpan', <String, dynamic>{
        'nama': nama.text,
        'keterangan': keterangan.text,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Paket tersimpan di HP.'}');

      setState(() => _paket = nama.text.trim().toUpperCase());

      await _muatPaket();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Menghapus paket buatan Sales (paket bawaan 2+1 & 1+1 tidak bisa dihapus).
  Future<void> _hapusPaket(Map<String, dynamic> p) async {
    final bool setuju = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('Hapus paket ${p['nama']}?'),
            content: const Text(
              'Paket buatan Sales akan dihapus dari HP. Paket bawaan 2+1 dan '
              '1+1 tidak dapat dihapus.',
              style: TextStyle(fontSize: 12, height: 1.4),
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
        ) ??
        false;

    if (!setuju || !mounted) return;

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('paket_hapus', <String, dynamic>{'id': p['id']});

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Paket dihapus.'}');

      if (_paket == '${p['nama']}') setState(() => _paket = '2+1');

      await _muatPaket();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /* ------------------------------------------------------------ input offline */

  /// Menghitung jumlah catatan program yang masih tersimpan di HP.
  Future<void> _hitungLencana() async {
    try {
      final Map<String, dynamic> ringkas = await _api.kirim('offline_ringkas');

      if (!mounted) return;

      setState(() {
        _catatanBelumKirim =
            int.tryParse('${ringkas['program_input_belum'] ?? 0}') ?? 0;
      });
    } on RtsKasirGalat {
      // Ringkasan gagal dibaca: lencana tidak diubah.
    }
  }

  /// Mencatat program ke HP - DAPAT DIPAKAI TANPA INTERNET.
  Future<void> _catatProgram() async {
    if (_items.isEmpty) {
      rtsKsPesan(
        context,
        'Belum ada produk program. Tekan DARI BARANG BAWAAN atau SINKRON ONLINE dulu.',
        galat: true,
      );
      return;
    }

    if (_toko == null) {
      rtsKsPesan(
        context,
        'Pilih dulu toko terdekat (tombol PILIH TOKO TERDEKAT) sebelum mencatat program.',
        galat: true,
      );
      return;
    }

    if (_jenis == 'INTRODEAL' && _paket.isEmpty) {
      rtsKsPesan(
        context,
        'Pilih paket Introdeal dulu (2+1, 1+1, atau PAKET SENDIRI).',
        galat: true,
      );
      return;
    }

    int pilih = 0;
    String satuan = 'PACK';
    final TextEditingController jumlah = TextEditingController(text: '1');
    final TextEditingController catatan = TextEditingController();
    final String tanggal = _tanggalHariIni();

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: Text('Catat program ${rtsProgramJudul(_jenis)}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Catatan disimpan di HP lebih dahulu (tanpa internet), lalu '
                  'dikirim ke server lewat CATATAN TERSIMPAN.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: rtsKsTeks2,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                _petaMini(
                  toko: <Map<String, dynamic>>[_toko!],
                  sayaLat: _sayaLat,
                  sayaLng: _sayaLng,
                  tinggi: 150,
                  warnaLain: rtsKsMaroon,
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Toko: ${_toko!['nama']} (ID ${_toko!['id']})',
                    style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: pilih,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Produk program',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (int i = 0; i < _items.length; i++)
                      DropdownMenuItem<int>(
                        value: i,
                        child: Text(
                          '${_items[i]['nama']}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                  ],
                  onChanged: (int? v) => setDialog(() => pilih = v ?? 0),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: jumlah,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Jumlah',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: satuan,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Satuan',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(value: 'PACK', child: Text('PACK')),
                    DropdownMenuItem<String>(value: 'BATANG', child: Text('BATANG')),
                    DropdownMenuItem<String>(value: 'BALL', child: Text('BALL')),
                  ],
                  onChanged: (String? v) => setDialog(() => satuan = v ?? 'PACK'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: catatan,
                  decoration: const InputDecoration(
                    labelText: 'Catatan (boleh kosong)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('BATAL'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('SIMPAN DI HP'),
            ),
          ],
        ),
      ),
    );

    if (simpan != true || !mounted) return;

    final Map<String, dynamic> produk =
        _items[pilih < 0 || pilih >= _items.length ? 0 : pilih];

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('program_input_simpan', <String, dynamic>{
        'jenis': _jenis,
        'paket': _jenis == 'INTRODEAL' ? _paket : '',
        'paket_keterangan': _jenis == 'INTRODEAL' ? _keteranganPaket(_paket) : '',
        'id_customer': '${_toko?['id'] ?? ''}',
        'nama_toko': '${_toko?['nama'] ?? ''}',
        'produk_id': produk['id'],
        'nama_produk': produk['nama'],
        'sku': produk['sku'],
        'jumlah': jumlah.text,
        'satuan': satuan,
        'tanggal': tanggal,
        'catatan': catatan.text,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Catatan program disimpan di HP.'}');

      await _hitungLencana();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Melihat catatan program yang tersimpan di HP (belum / sudah dikirim).
  Future<void> _lihatCatatan() async {
    List<Map<String, dynamic>> items;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'program_input_daftar',
        <String, dynamic>{'batas': 200},
      );

      items = ((hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
          .toList();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
      return;
    }

    if (!mounted) return;

    if (items.isEmpty) {
      rtsKsPesan(context, 'Belum ada catatan program di HP.');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: Text('Catatan program di HP (${items.length})'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext c, int i) {
                final Map<String, dynamic> s = items[i];

                return ListTile(
                  dense: true,
                  title: Text(
                    '${s['nama_produk']} - ${s['jumlah_teks']} ${s['satuan']}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    rtsKsSambung(
                      '${s['nama_toko']} (${s['id_customer']})',
                      rtsKsSambung(
                        '${s['jenis']}${('${s['paket']}').isEmpty ? '' : ' paket ${s['paket']}'}',
                        '${s['tanggal']}',
                      ),
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: 'Hapus catatan ini',
                    icon: const Icon(Icons.delete_outline, size: 19),
                    onPressed: () async {
                      try {
                        await _api.kirim(
                          'program_input_hapus',
                          <String, dynamic>{'id': s['id']},
                        );

                        setDialog(() => items.removeAt(i));

                        if (ctx2.mounted) {
                          rtsKsPesan(ctx2, 'Catatan dihapus dari HP.');
                        }

                        await _hitungLencana();
                      } on RtsKasirGalat catch (e) {
                        if (ctx2.mounted) rtsKsPesan(ctx2, e.pesan, galat: true);
                      }
                    },
                  ),
                );
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('TUTUP'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_kirimCatatan());
              },
              icon: const Icon(Icons.cloud_upload_outlined, size: 17),
              label: const Text('KIRIM KE SERVER'),
            ),
          ],
        ),
      ),
    );
  }

  /// Mengirim catatan program dari HP ke server (butuh internet).
  Future<void> _kirimCatatan() async {
    if (_sibuk) return;

    setState(() => _sibuk = true);

    int berhasil = 0;
    int gagal = 0;

    try {
      final Map<String, dynamic> ambil =
          await _api.kirim('offline_ambil', <String, dynamic>{'batas': 200});

      final List<dynamic> daftar = (ambil['program_input'] is List)
          ? ambil['program_input'] as List<dynamic>
          : <dynamic>[];

      final List<Map<String, dynamic>> kiriman = <Map<String, dynamic>>[];

      for (final dynamic satu in daftar) {
        if (satu is! Map) continue;

        final Map<String, dynamic> k = satu.cast<String, dynamic>();

        try {
          await _server('input_simpan', data: <String, String>{
            'jenis': '${k['jenis'] ?? 'INTRODEAL'}',
            'paket': '${k['paket'] ?? ''}',
            'paket_keterangan': '${k['paket_keterangan'] ?? ''}',
            'id_customer': '${k['id_customer'] ?? ''}',
            'nama_toko': '${k['nama_toko'] ?? ''}',
            'produk_id': '${k['produk_id'] ?? 0}',
            'nama_produk': '${k['nama_produk'] ?? ''}',
            'sku': '${k['sku'] ?? ''}',
            'jumlah': '${k['jumlah_teks'] ?? k['jumlah'] ?? 1}',
            'satuan': '${k['satuan'] ?? 'PACK'}',
            'tanggal': '${k['tanggal'] ?? ''}',
            'catatan': '${k['catatan'] ?? ''}',
            'id_hp': '${k['id'] ?? ''}',
          });

          kiriman.add(<String, dynamic>{'tabel': 'program_input', 'id_hp': k['id']});
          berhasil++;
        } on RtsKasirGalat {
          gagal++;
        }
      }

      if (kiriman.isNotEmpty) {
        await _api.kirim('offline_tandai', <String, dynamic>{'kiriman': kiriman});
      }

      if (!mounted) return;

      rtsKsPesan(
        context,
        gagal == 0
            ? 'Catatan program terkirim ke server ($berhasil catatan).'
            : 'Terkirim $berhasil catatan, $gagal catatan belum berhasil '
                '(akan dicoba lagi nanti).',
      );

      await _hitungLencana();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /* ------------------------------------------------------------- peta & filter */

  /// Peta kecil OpenStreetMap (dipakai form input program & halaman filter).
  Widget _petaMini({
    required List<Map<String, dynamic>> toko,
    double? sayaLat,
    double? sayaLng,
    double tinggi = 200,
    Color warnaLain = rtsKsTeks2,
  }) {
    final List<Map<String, dynamic>> bertitik = toko
        .where((Map<String, dynamic> t) => _adaTitik(t))
        .toList();

    double lat = sayaLat ?? 3.5952;
    double lng = sayaLng ?? 98.6722;

    if (bertitik.isNotEmpty) {
      lat = _latTitik(bertitik.first) ?? lat;
      lng = _lngTitik(bertitik.first) ?? lng;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        height: tinggi,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: LatLng(lat, lng),
            initialZoom: bertitik.length > 1 ? 12 : 14,
            minZoom: 4,
            maxZoom: 18,
            backgroundColor: rtsPetaAir,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: rtsPetaSumber.first.url,
              userAgentPackageName: 'com.bene.rts_panel_app',
              maxNativeZoom: rtsPetaSumber.first.maksZoom,
            ),
            MarkerLayer(
              markers: <Marker>[
                for (final Map<String, dynamic> t in bertitik)
                  Marker(
                    point: LatLng(
                      _latTitik(t) ?? lat,
                      _lngTitik(t) ?? lng,
                    ),
                    width: 32,
                    height: 32,
                    child: Tooltip(
                      message: '${t['nama']}',
                      child: Container(
                        decoration: BoxDecoration(
                          color: t['program_sudah'] == true ? rtsKsHijau : warnaLain,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.4),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Colors.white,
                          size: 15,
                        ),
                      ),
                    ),
                  ),
                if (sayaLat != null && sayaLng != null)
                  Marker(
                    point: LatLng(sayaLat, sayaLng),
                    width: 30,
                    height: 30,
                    child: const Icon(
                      Icons.my_location_rounded,
                      color: rtsPetaSaya,
                      size: 24,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// True bila toko punya titik koordinat yang dapat digambar di peta.
  bool _adaTitik(Map<String, dynamic> t) {
    if (t['bertitik'] == false) return false;

    return _latTitik(t) != null && _lngTitik(t) != null;
  }

  double? _latTitik(Map<String, dynamic> t) {
    final dynamic a = t['latitude'];

    if (a is num && a != 0) return a.toDouble();

    return null;
  }

  double? _lngTitik(Map<String, dynamic> t) {
    final dynamic b = t['longitude'];

    if (b is num && b != 0) return b.toDouble();

    return null;
  }

  /// PETA & FILTER: peta toko + penyaring program, kunjungan, dan hari.
  Future<void> _petaFilter() async {
    List<Map<String, dynamic>> toko;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('toko_peta');

      toko = ((hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[])
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
          .toList();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
      return;
    }

    // Toko yang sudah dicatat/dibeli untuk program INTRODEAL dan BD.
    final Map<String, Set<String>> sudah = <String, Set<String>>{
      'INTRODEAL': <String>{},
      'BD': <String>{},
    };

    for (final String j in rtsProgramJenis) {
      try {
        final Map<String, dynamic> hasil = await _api.kirim(
          'program_input_daftar',
          <String, dynamic>{'jenis': j, 'batas': 500},
        );

        final List<dynamic> items =
            (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

        sudah[j] = <String>{
          for (final dynamic s in items)
            if (s is Map) '${s['id_customer']}',
        };
      } on RtsKasirGalat {
        // Daftar program gagal dibaca: penyaring tetap jalan.
      }
    }

    // Toko yang sudah dikunjungi HARI INI.
    final Set<String> dikunjungi = <String>{};

    try {
      final Map<String, dynamic> hasil = await _api.kirim('kunjungan_hari_ini');
      final List<dynamic> ids = (hasil['id_customer'] is List)
          ? hasil['id_customer'] as List<dynamic>
          : <dynamic>[];

      dikunjungi.addAll(ids.map((dynamic e) => '$e'));
    } on RtsKasirGalat {
      // Riwayat kunjungan gagal dibaca: penyaring tetap jalan.
    }

    double? sayaLat = _sayaLat;
    double? sayaLng = _sayaLng;

    if (sayaLat == null) {
      final dynamic posisi = await rtsKsAmbilLokasi();

      if (posisi != null) {
        sayaLat = (posisi.latitude as num).toDouble();
        sayaLng = (posisi.longitude as num).toDouble();

        if (mounted) {
          setState(() {
            _sayaLat = sayaLat;
            _sayaLng = sayaLng;
          });
        }
      }
    }

    if (!mounted) return;

    String fJenis = _jenis;
    String fKunjungan = 'SEMUA';
    String fHari = 'SEMUA';

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) {
          List<Map<String, dynamic>> saring() {
            return toko.where((Map<String, dynamic> t) {
              if (!_adaTitik(t)) return false;

              final String id = '${t['id_customer']}';

              if (fJenis != 'SEMUA' && !sudah[fJenis]!.contains(id)) return false;

              if (fKunjungan == 'SUDAH' && !dikunjungi.contains(id)) return false;
              if (fKunjungan == 'BELUM' && dikunjungi.contains(id)) return false;

              if (fHari != 'SEMUA' &&
                  !'${t['hari']}'.toUpperCase().contains(fHari)) {
                return false;
              }

              return true;
            }).toList();
          }

          final List<Map<String, dynamic>> tampil = saring()
              .map((Map<String, dynamic> t) => <String, dynamic>{
                    ...t,
                    'program_sudah': sudah[fJenis]?.contains('${t['id_customer']}') == true,
                  })
              .toList();

          int jmlSudah = 0;

          for (final Map<String, dynamic> t in tampil) {
            if (t['program_sudah'] == true) jmlSudah++;
          }

          return AlertDialog(
            title: const Text('Peta & filter program'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final String j in rtsProgramJenis)
                          ChoiceChip(
                            label: Text('PROGRAM $j', style: const TextStyle(fontSize: 11)),
                            selected: fJenis == j,
                            onSelected: (_) => setDialog(() => fJenis = j),
                          ),
                        for (final String k in <String>['SEMUA', 'SUDAH', 'BELUM'])
                          ChoiceChip(
                            label: Text('KUNJUNGAN $k', style: const TextStyle(fontSize: 11)),
                            selected: fKunjungan == k,
                            onSelected: (_) => setDialog(() => fKunjungan = k),
                          ),
                        for (final String h in <String>[
                          'SEMUA',
                          'SENIN',
                          'SELASA',
                          'RABU',
                          'KAMIS',
                          'JUMAT',
                          'SABTU',
                          'MINGGU',
                        ])
                          ChoiceChip(
                            label: Text('HARI $h', style: const TextStyle(fontSize: 11)),
                            selected: fHari == h,
                            onSelected: (_) => setDialog(() => fHari = h),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$fJenis: ${tampil.length} toko tampil, $jmlSudah sudah '
                      '(hijau) dan ${tampil.length - jmlSudah} belum (abu-abu). '
                      'Warna titik mengikuti hari kunjungan.',
                      style: const TextStyle(fontSize: 11, color: rtsKsTeks2, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    _petaMini(toko: tampil, sayaLat: sayaLat, sayaLng: sayaLng, tinggi: 260),
                    const SizedBox(height: 6),
                    if (tampil.isEmpty)
                      const Text(
                        'Tidak ada toko yang cocok dengan penyaring. Ubah pilihan di atas.',
                        style: TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                      ),
                    for (final Map<String, dynamic> t in tampil.take(30))
                      ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.storefront_rounded,
                          size: 18,
                          color: rtsPetaWarnaHari('${t['hari']}'),
                        ),
                        title: Text(
                          '${t['nama']}',
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          rtsKsSambung(
                            'ID ${t['id_customer']}',
                            rtsKsSambung(
                              '${t['hari']}',
                              (sayaLat != null &&
                                      _latTitik(t) != null &&
                                      _lngTitik(t) != null)
                                  ? rtsKsJarakTeks(
                                      rtsKsJarakMeter(
                                        sayaLat,
                                        sayaLng ?? 0,
                                        _latTitik(t)!,
                                        _lngTitik(t)!,
                                      ),
                                    )
                                  : '',
                            ),
                          ),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: _lencana(
                          text: t['program_sudah'] == true ? 'SUDAH' : 'BELUM',
                          warna: t['program_sudah'] == true ? rtsKsHijau : rtsKsTeks2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('TUTUP'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Tanggal hari ini (format tahun-bulan-hari).
  String _tanggalHariIni() {
    final DateTime hari = DateTime.now();
    final String bulan = hari.month < 10 ? '0${hari.month}' : '${hari.month}';
    final String tanggal = hari.day < 10 ? '0${hari.day}' : '${hari.day}';

    return '${hari.year}-$bulan-$tanggal';
  }

  /// Melengkapi toko terpilih dengan TITIK KOORDINAT dan hari kunjungan.
  ///
  /// Daftar pemilih toko (RtsPilihCustomerPage) hanya mengirim id, nama, hp,
  /// alamat, dan district; titik peta dibaca dari salinan toko di HP supaya
  /// peta kecil pada form CATAT PROGRAM benar-benar menampilkan toko itu.
  Future<Map<String, dynamic>> _lengkapiToko(Map<String, dynamic> toko) async {
    try {
      final Map<String, dynamic> hasil = await _api.kirim('toko_peta');

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        final Map<String, dynamic> t = satu.cast<String, dynamic>();

        if ('${t['id_customer']}' == '${toko['id']}') {
          return <String, dynamic>{...toko, ...t};
        }
      }
    } on RtsKasirGalat {
      // Titik toko tidak ditemukan: peta tetap tampil tanpa titik toko.
    }

    return toko;
  }

  /* -------------------------------------------------------------------- layar */

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: rtsProgramJenis.length,
      initialIndex: _jenis == 'BD' ? 1 : 0,
      child: Scaffold(
        backgroundColor: rtsKsLatar,
        appBar: AppBar(
          backgroundColor: rtsKsMaroon,
          foregroundColor: Colors.white,
          title: const Text('Program'),
          actions: <Widget>[
            IconButton(
              tooltip: _catatanBelumKirim > 0
                  ? 'Catatan program di HP: $_catatanBelumKirim belum dikirim'
                  : 'Catatan program di HP',
              icon: Badge(
                isLabelVisible: _catatanBelumKirim > 0,
                label: Text('$_catatanBelumKirim'),
                child: const Icon(Icons.cloud_upload_outlined),
              ),
              onPressed: () => unawaited(_lihatCatatan()),
            ),
            IconButton(
              tooltip: 'Sinkron dari server',
              icon: const Icon(Icons.cloud_download_outlined),
              onPressed: _sibuk ? null : () => unawaited(_sinkronOnline()),
            ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            indicatorColor: Colors.white,
            onTap: (int i) {
              setState(() => _jenis = rtsProgramJenis[i]);
              unawaited(_muat());
            },
            tabs: <Widget>[
              for (final String j in rtsProgramJenis) Tab(text: j),
            ],
          ),
        ),
        body: Column(
          children: <Widget>[
            if (_sibuk) const LinearProgressIndicator(minHeight: 3),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                          onPressed: _sibuk ? null : _ambilDariBarangBawaan,
                          icon: const Icon(Icons.inventory_2_outlined, size: 17),
                          label: const Text('DARI BARANG BAWAAN',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: rtsKsMaroon,
                            side: const BorderSide(color: rtsKsMaroon),
                          ),
                          onPressed: _pilihToko,
                          icon: const Icon(Icons.my_location_rounded, size: 17),
                          label: const Text('PILIH TOKO TERDEKAT',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _sibuk ? null : () => unawaited(_sinkronOnline()),
                          icon: const Icon(Icons.cloud_download_outlined, size: 17),
                          label: const Text('SINKRON ONLINE',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _formProduk(),
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('TAMBAH PRODUK',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: rtsKsHijau),
                          onPressed: _sibuk ? null : () => unawaited(_catatProgram()),
                          icon: const Icon(Icons.edit_note_rounded, size: 17),
                          label: const Text('CATAT PROGRAM',
                              style: TextStyle(fontSize: 11.5)),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => unawaited(_lihatCatatan()),
                          icon: const Icon(Icons.offline_pin_outlined, size: 17),
                          label: Text(
                            _catatanBelumKirim > 0
                                ? 'CATATAN ($_catatanBelumKirim)'
                                : 'CATATAN TERSIMPAN',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(_petaFilter()),
                      icon: const Icon(Icons.map_outlined, size: 17),
                      label: const Text(
                        'PETA & FILTER (PROGRAM, KUNJUNGAN, HARI)',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                  if (_jenis == 'INTRODEAL') ...<Widget>[
                    const SizedBox(height: 9),
                    const Text(
                      'PAKET INTRODEAL (pilih satu)',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: rtsKsTeks2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final Map<String, dynamic> pkt in _paketItems)
                          InputChip(
                            label: Text(
                              '${pkt['nama']}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            selected: _paket == '${pkt['nama']}',
                            selectedColor: rtsKsMaroon.withValues(alpha: 0.15),
                            onSelected: (_) =>
                                setState(() => _paket = '${pkt['nama']}'),
                            onDeleted: pkt['bawaan'] == true
                                ? null
                                : () => unawaited(_hapusPaket(pkt)),
                            deleteIcon: pkt['bawaan'] == true
                                ? null
                                : const Icon(Icons.close, size: 15),
                            tooltip: '${pkt['keterangan']}',
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 15),
                          label: const Text('PAKET SENDIRI',
                              style: TextStyle(fontSize: 11.5)),
                          onPressed: () => unawaited(_formPaket()),
                        ),
                      ],
                    ),
                    if (_paket.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          'Paket dipakai: $_paket'
                          '${_keteranganPaket(_paket).isEmpty ? '' : ' (${_keteranganPaket(_paket)})'}. '
                          'Produk tetap diambil dari Menu Barang Bawaan.',
                          style: const TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                        ),
                      ),
                  ] else
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Sub-menu BD (New Brand Distribution): TIDAK memakai '
                        'paket - produknya sudah ada di outlet.',
                        style: TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Sub-menu ${rtsProgramJudul(_jenis)} - '
                    '${rtsProgramKeterangan(_jenis)}. Produk dapat diambil dari '
                    'Menu Barang Bawaan atau disinkron dari server. Catatan '
                    'program dapat disimpan di HP walau tanpa internet.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: rtsKsTeks2,
                      height: 1.35,
                    ),
                  ),
                  if (_catatan.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      _catatan,
                      style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                    ),
                  ],
                ],
              ),
            ),
            if (_toko != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: rtsKsMaroon),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.storefront_rounded, color: rtsKsMaroon, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Toko terdekat: ${_toko!['nama']}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                          Text(
                            'ID ${_toko!['id']} - '
                            '${_hitungSudah()} dari ${_items.length} produk sudah dibeli',
                            style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _toko = null;
                        _statusToko = <String, Map<String, dynamic>>{};
                      }),
                      child: const Text('TUTUP'),
                    ),
                  ],
                ),
              ),
            if (_galat.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  _galat,
                  style: const TextStyle(color: rtsKsMerah, fontSize: 12),
                ),
              ),
            if (_memuat && _items.isEmpty)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            if (!_memuat && _items.isEmpty)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'Belum ada produk $_jenis.\n\nTekan DARI BARANG BAWAAN untuk '
                      'mengambil satu produk dari daftar bawaan, atau TAMBAH '
                      'PRODUK untuk mengetik sendiri, atau SINKRON ONLINE untuk '
                      'mengambil daftar dari server.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: rtsKsTeks2,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
            if (_items.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 18),
                  itemCount: _items.length,
                  itemBuilder: (BuildContext ctx, int i) => _kartu(_items[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  int _hitungSudah() {
    int jumlah = 0;

    for (final Map<String, dynamic> p in _items) {
      if (_statusToko[_kunci(p)]?['dibeli'] == true) jumlah++;
    }

    return jumlah;
  }

  /// Huruf pertama nama produk (untuk bulatan kecil pada kartu).
  String _awalan(String teks) {
    final String bersih = teks.trim();

    return bersih.isEmpty ? '?' : bersih.substring(0, 1).toUpperCase();
  }

  Widget _kartu(Map<String, dynamic> p) {
    final Map<String, dynamic>? status = _statusToko[_kunci(p)];
    final bool adaToko = _toko != null;
    final bool sudah = status?['dibeli'] == true;
    final int jumlahToko = int.tryParse('${p['jumlah_toko'] ?? 0}') ?? 0;
    final String tanggalBeli = '${status?['tanggal'] ?? ''}';
    final String teksTokoIni = sudah
        ? (tanggalBeli.isEmpty
            ? 'TOKO INI: SUDAH'
            : 'TOKO INI: SUDAH ($tanggalBeli)')
        : 'TOKO INI: BELUM';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: adaToko && sudah ? rtsKsHijau : rtsKsGaris,
          width: adaToko && sudah ? 1.4 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            CircleAvatar(
              radius: 15,
              backgroundColor: p['aktif'] == false ? rtsKsGaris : rtsKsMaroon,
              foregroundColor: p['aktif'] == false ? rtsKsTeks2 : Colors.white,
              child: Text(
                _awalan('${p['nama']}'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${p['nama']}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rtsKsSambung(
                      rtsKsSambung('${p['merek']}', 'SKU ${p['sku']}'),
                      '${p['isi_per_pack']} batang/pack',
                    ),
                    style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                  ),
                  if ('${p['periode']}'.isNotEmpty || '${p['catatan']}'.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        rtsKsSambung('${p['periode']}', '${p['catatan']}'),
                        style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                      ),
                    ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      _lencana(
                        text: jumlahToko > 0
                            ? 'DIBELI $jumlahToko TOKO'
                            : 'BELUM ADA PEMBELI',
                        warna: jumlahToko > 0 ? rtsKsHijau : rtsKsTeks2,
                      ),
                      if (adaToko)
                        _lencana(
                          text: teksTokoIni,
                          warna: sudah ? rtsKsHijau : rtsKsKuning,
                        ),
                      if (p['dari_server'] == true)
                        _lencana(text: 'DARI SERVER', warna: rtsKsMaroon),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Pilihan produk',
              onSelected: (String aksi) {
                if (aksi == 'ubah') unawaited(_formProduk(ada: p));
                if (aksi == 'hapus') unawaited(_hapus(p));
                if (aksi == 'kirim') unawaited(_kirimKeServer(p));
              },
              itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
                const PopupMenuItem<String>(
                  value: 'ubah',
                  child: Text('Ubah produk'),
                ),
                const PopupMenuItem<String>(
                  value: 'hapus',
                  child: Text('Hapus dari HP'),
                ),
                if (_pengelola)
                  const PopupMenuItem<String>(
                    value: 'kirim',
                    child: Text('Kirim ke server'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lencana({required String text, required Color warna}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: warna.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: warna,
        ),
      ),
    );
  }
}

/* ============================================================================
 * MENU PRO : BACKUP & SINKRON DATA OFFLINE
 * ----------------------------------------------------------------------------
 *  Dipakai setiap Sales (dan terutama ADMIN/ASS) untuk melihat berapa data yang
 *  masih tersimpan DI HP dan belum dikirim ke server:
 *      - kunjungan, nota kasir, piutang, input program, goresan peta
 *      - jumlah yang BELUM KIRIM pada tiap jenis data
 *  Semua tombol bekerja dari data HP (SQLite) sehingga tetap dapat dibuka
 *  walaupun tidak ada internet. Data dikirim ke server memakai tombol
 *  TANDAI SUDAH DIKIRIM setelah laporan dikirim (WhatsApp/email/berkas).
 * ========================================================================== */

/// Halaman "Backup & Sinkron Data Offline".
class RtsBackupOfflinePage extends StatefulWidget {
  const RtsBackupOfflinePage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsBackupOfflinePage> createState() => _RtsBackupOfflinePageState();
}

class _RtsBackupOfflinePageState extends State<RtsBackupOfflinePage> {
  late final RtsKasirApi _api = RtsKasirApi(
    baseUrl: widget.baseUrl,
    token: widget.token,
    pengguna: widget.pengguna,
  );

  Map<String, dynamic> _ringkas = <String, dynamic>{};
  Map<String, dynamic> _cadangan = <String, dynamic>{};
  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';

  @override
  void initState() {
    super.initState();
    unawaited(_muat());
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> ringkas = await _api.kirim('offline_ringkas');
      final Map<String, dynamic> cadangan = await _api.kirim('cadangan_info');

      if (!mounted) return;

      setState(() {
        _ringkas = ringkas;
        _cadangan = cadangan;
        _memuat = false;
      });
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
      });
    }
  }

  int _angka(String kunci) => int.tryParse('${_ringkas[kunci] ?? 0}') ?? 0;

  /// Ringkasan teks yang dapat disalin lalu dilaporkan ke ASS/Admin.
  String _teksRingkas() {
    final List<String> baris = <String>[
      'RTS PANEL - DATA DI HP (belum terkirim)',
      'Sales: ${_ringkas['nama_sales'] ?? ''} (${_ringkas['id_sales'] ?? ''})',
      'Waktu: ${DateTime.now()}',
      '',
      'Kunjungan: ${_angka('kunjungan')} (belum kirim ${_angka('kunjungan_belum')})',
      'Nota kasir: ${_angka('nota')} (belum kirim ${_angka('nota_belum')})',
      'Piutang: ${_angka('piutang')}',
      'Input program: ${_angka('program_input')} (belum kirim ${_angka('program_input_belum')})',
      'Program produk: ${_angka('program')}',
      'Paket Introdeal: ${_angka('paket')}',
      'Goresan peta: ${_angka('goresan')}',
      'Toko tersimpan: ${_angka('toko')}',
      'Produk tersimpan: ${_angka('produk')}',
      'Titik kantor: ${_angka('kantor')}',
    ];

    return baris.join('\n');
  }

  Future<void> _salinRingkas() async {
    await Clipboard.setData(ClipboardData(text: _teksRingkas()));

    if (mounted) rtsKsPesan(context, 'Ringkasan data di HP disalin.');
  }

  /// Menampilkan data yang belum dikirim, supaya dapat dilaporkan/diarsipkan.
  Future<void> _lihatData() async {
    if (_sibuk) return;

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('offline_ambil', <String, dynamic>{'batas': 200});

      final String teks = const JsonEncoder.withIndent('  ').convert(hasil);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          title: Text('Data siap kirim (${hasil['jumlah_kunjungan'] ?? 0} '
              'kunjungan/nota, ${hasil['jumlah_input'] ?? 0} input program)'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(
                teks,
                style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace'),
              ),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('TUTUP'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: teks));

                if (ctx.mounted) {
                  rtsKsPesan(ctx, 'Data siap kirim disalin (tempel ke WhatsApp/email).');
                }
              },
              icon: const Icon(Icons.copy_rounded, size: 17),
              label: const Text('SALIN SEMUA'),
            ),
          ],
        ),
      );
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Menandai data di HP sudah dikirim ke server (setelah laporan terkirim).
  Future<void> _tandaiKirim() async {
    if (_sibuk) return;

    final bool setuju = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: const Text('Tandai sudah dikirim?'),
            content: const Text(
              'Seluruh kunjungan, nota, dan input program yang masih tersimpan '
              'di HP akan ditandai SUDAH DIKIRIM. Lakukan setelah data benar '
              'sudah masuk ke server/pusat.',
              style: TextStyle(fontSize: 12, height: 1.4),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('BATAL'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('TANDAI'),
              ),
            ],
          ),
        ) ??
        false;

    if (!setuju || !mounted) return;

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> ambil =
          await _api.kirim('offline_ambil', <String, dynamic>{'batas': 500});

      final List<Map<String, dynamic>> kiriman = <Map<String, dynamic>>[];

      void tambah(String tabel, dynamic isi) {
        if (isi is! List) return;

        for (final dynamic satu in isi) {
          if (satu is! Map) continue;

          final dynamic id = satu['id_hp'] ?? satu['id'];

          kiriman.add(<String, dynamic>{
            'tabel': tabel,
            'id_hp': int.tryParse('$id') ?? 0,
          });
        }
      }

      tambah('kunjungan', ambil['kunjungan']);

      for (final dynamic satu in (ambil['program_input'] is List)
          ? ambil['program_input'] as List<dynamic>
          : <dynamic>[]) {
        if (satu is! Map) continue;

        kiriman.add(<String, dynamic>{
          'tabel': 'program_input',
          'id_hp': int.tryParse('${satu['id']}') ?? 0,
        });
      }

      final Map<String, dynamic> tandai = kiriman.isEmpty
          ? <String, dynamic>{'message': 'Tidak ada data yang perlu ditandai.'}
          : await _api.kirim('offline_tandai', <String, dynamic>{'kiriman': kiriman});

      if (!mounted) return;

      rtsKsPesan(context, '${tandai['message'] ?? 'Data ditandai sudah dikirim.'}');

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  /// Membuat salinan database HP (berkas .db) sebagai cadangan.
  Future<void> _cadangkan() async {
    if (_sibuk) return;

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil = await _api.kirim('cadangkan');

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Cadangan dibuat.'}');

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);
    }
  }

  Widget _baris(String label, int jumlah, int belum) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: belum > 0 ? rtsKsKuning : rtsKsGaris),
      ),
      child: ListTile(
        dense: true,
        title: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        subtitle: Text(
          belum > 0 ? 'Belum dikirim: $belum dari $jumlah' : '$jumlah data - semua sudah dikirim',
          style: const TextStyle(fontSize: 11),
        ),
        trailing: Text(
          '$jumlah',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> berkas = ((_cadangan['berkas'] is List)
            ? _cadangan['berkas'] as List<dynamic>
            : <dynamic>[])
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
        .toList();

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Backup & Sinkron Data Offline'),
      ),
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: <Widget>[
            if (_sibuk) const LinearProgressIndicator(minHeight: 3),
            const Text(
              'Data di HP',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 3),
            Text(
              'Semua data di bawah ini tersimpan DI DALAM HP, jadi Kasir, '
              'Kunjungan, dan Program tetap dapat dipakai tanpa internet. '
              'Kirim/laporkan datanya, lalu tekan TANDAI SUDAH DIKIRIM.',
              style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
            ),
            const SizedBox(height: 10),
            if (_galat.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _galat,
                  style: const TextStyle(color: rtsKsMerah, fontSize: 12),
                ),
              ),
            if (_memuat && _ringkas.isEmpty)
              const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )),
            if (_ringkas.isNotEmpty) ...<Widget>[
              _baris('Kunjungan', _angka('kunjungan'), _angka('kunjungan_belum')),
              _baris('Nota kasir', _angka('nota'), _angka('nota_belum')),
              _baris('Input program', _angka('program_input'), _angka('program_input_belum')),
              _baris('Piutang', _angka('piutang'), 0),
              _baris('Program produk', _angka('program'), 0),
              _baris('Paket Introdeal', _angka('paket'), 0),
              _baris('Toko tersimpan', _angka('toko'), 0),
              _baris('Produk tersimpan', _angka('produk'), 0),
              _baris('Goresan peta', _angka('goresan'), 0),
              _baris('Titik kantor', _angka('kantor'), 0),
              const SizedBox(height: 8),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sibuk ? null : _lihatData,
                      icon: const Icon(Icons.list_alt_rounded, size: 17),
                      label: const Text('LIHAT DATA SIAP KIRIM',
                          style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _salinRingkas,
                      icon: const Icon(Icons.copy_rounded, size: 17),
                      label: const Text('SALIN RINGKASAN', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                  onPressed: _sibuk ? null : _tandaiKirim,
                  icon: const Icon(Icons.cloud_done_outlined, size: 17),
                  label: const Text('TANDAI SUDAH DIKIRIM'),
                ),
              ),
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _sibuk ? null : _cadangkan,
                  icon: const Icon(Icons.save_alt_rounded, size: 17),
                  label: const Text('BUAT CADANGAN DI HP (BERKAS .DB)'),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cadangan di HP',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${_cadangan['message'] ?? ''}',
                style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
              ),
              const SizedBox(height: 6),
              for (final Map<String, dynamic> b in berkas.take(6))
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 19),
                  title: Text('${b['nama']}', style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    '${b['ukuran_teks'] ?? ''} - ${b['waktu'] ?? ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
