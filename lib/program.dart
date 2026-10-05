// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : PROGRAM (INTRODEAL & BD)
//  Berkas : lib/program.dart
//  Versi  : 1   (5 Oktober 2026)
//
//  ISI BERKAS INI
//  --------------
//      RtsProgramPage - menu PRO "Program" dengan DUA sub-menu:
//          INTRODEAL : produk yang sedang diperkenalkan ke customer
//          BD        : produk Business Development
//
//  KEGUNAAN (sesuai permintaan)
//  ---------------------------
//  PT Wismilak selalu meluncurkan produk baru, jadi Sales perlu melihat apakah
//  setiap toko SUDAH atau BELUM masuk produk launching. Halaman ini:
//      1. menyimpan daftar produk program di HP (SQLite),
//      2. dapat diisi dari MENU BARANG BAWAAN (satu tekan) atau disinkron dari
//         server lewat tombol SINKRON ONLINE (api/program.php),
//      3. menunjukkan jumlah customer yang sudah membeli tiap produk (dihitung
//         dari nota kasir yang tersimpan di HP),
//      4. dapat memilih TOKO TERDEKAT dari posisi HP (sama seperti Kasir dan
//         Piutang), lalu menampilkan status SUDAH / BELUM per produk,
//      5. ADMIN / ASS dapat mengirim daftar ke server supaya dipakai HP lain.
//
//  CATATAN
//  -------
//  - Berkas ini TIDAK memanggil peta.dart (menghindari impor berputar).
//  - Seluruh nama dan pesan memakai Bahasa Indonesia yang mudah dibaca sales.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import 'kasir.dart';

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
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

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

  /// True bila akun boleh MENGUBAH daftar di server (ADMIN / ASS).
  bool get _pengelola {
    final String peran = '${widget.pengguna['role'] ?? ''}'.toUpperCase();

    return peran == 'ADMIN' || peran == 'ASS';
  }

  @override
  void initState() {
    super.initState();
    _muat();
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
            ? 'Server belum memuat produk $jenis. Daftar di HP dikosongkan.'
            : '${simpan['message'] ?? '$jenis disinkron.'}',
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

    setState(() => _toko = toko);

    await _muatStatusToko();
  }

  /* -------------------------------------------------------------------- layar */

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: rtsProgramJenis.length,
      child: Scaffold(
        backgroundColor: rtsKsLatar,
        appBar: AppBar(
          backgroundColor: rtsKsMaroon,
          foregroundColor: Colors.white,
          title: const Text('Program'),
          actions: <Widget>[
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
                  const SizedBox(height: 6),
                  Text(
                    'Sub-menu ${rtsProgramJudul(_jenis)} - '
                    '${rtsProgramKeterangan(_jenis)}. Produk dapat diambil dari '
                    'Menu Barang Bawaan atau disinkron dari server.',
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
                      'Belum ada produk $jenis.\n\nTekan DARI BARANG BAWAAN untuk '
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
