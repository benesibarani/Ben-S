// RTS-PANEL-ROUND: 18J - penanda putaran RTS Panel (diperiksa PERIKSA_KODE_APLIKASI.ps1)
// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : PROGRAM
//  Berkas : lib/program.dart
//  Versi  : 3   (5 Oktober 2026 - Putaran 18I)
//
//  ISI BERKAS INI
//  --------------
//      RtsProgramPage        - SATU menu PRO "Program" saja. Isinya:
//                                1. daftar PROGRAM (Introdeal, BD, dan
//                                   program buatan Sales sendiri),
//                                2. LIST CUSTOMER yang mengikuti program,
//                                3. tombol melayang (FAB) INPUT PROGRAM:
//                                   pilih customer -> pilih programnya,
//                                4. peta & filter (program, kunjungan, hari),
//                                5. catatan program yang tersimpan di HP.
//      RtsBackupOfflinePage  - menu PRO "Backup & Sinkron Data Offline".
//
//  ARTI PROGRAM (sesuai penjelasan Bapak)
//  --------------------------------------
//      INTRODEAL = Introductory Deal - PROGRAM PAKET. Paket baku 2+1 dan 1+1;
//                  Sales juga dapat membuat paket sendiri (contoh 3+1).
//      BD        = New Brand Distribution - TIDAK memakai paket, karena
//                  produknya sudah ada di outlet.
//      LAIN-LAIN = Sales dapat membuat program sendiri (misalnya program
//                  khusus produk baru) langsung dari aplikasi.
//
//  PRODUK
//  ------
//      Produk diambil dari MENU BARANG BAWAAN (tersimpan di HP), sehingga
//      input program tetap dapat dikerjakan tanpa internet.
//
//  CATATAN
//  -------
//  - Semua tombol SINKRON di dalam menu sudah DIHILANGKAN; sinkronisasi data
//    dilakukan dari menu "Sinkronisasi" pada menu utama.
//  - Berkas ini memakai peta.dart untuk ubin OpenStreetMap supaya tampilannya
//    sama dengan menu Peta Customer / Radar / Rute Plan.
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

/* -------------------------------------------------------------- penolong peta */

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

/// Peta kecil OpenStreetMap (dipakai form input program & peta filter).
Widget _petaMiniProgram({
  required List<Map<String, dynamic>> toko,
  double? sayaLat,
  double? sayaLng,
  double tinggi = 200,
  Color warnaLain = rtsKsMaroon,
  bool penuh = false,
}) {
  // Titik dibatasi supaya peta tidak berat (lihat rtsPetaBatasTitik).
  final List<Map<String, dynamic>> bertitik =
      rtsPetaPotongTitik(toko.where(_adaTitik).toList());

  double lat = sayaLat ?? 3.5952;
  double lng = sayaLng ?? 98.6722;

  if (bertitik.isNotEmpty) {
    lat = _latTitik(bertitik.first) ?? lat;
    lng = _lngTitik(bertitik.first) ?? lng;
  }

  final Widget peta = FlutterMap(
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
                  point: LatLng(_latTitik(t) ?? lat, _lngTitik(t) ?? lng),
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
      );

  // penuh = true -> peta mengisi SELURUH ruang yang tersedia (layar penuh).
  return ClipRRect(
    borderRadius: BorderRadius.circular(penuh ? 0 : 10),
    child: penuh ? SizedBox.expand(child: peta) : SizedBox(height: tinggi, child: peta),
  );
}

/* ============================================================================
 * PETA PROGRAM - SATU LAYAR PENUH
 * ----------------------------------------------------------------------------
 *  Dibuka dari tombol PETA PENUH pada kotak "Peta & filter program".
 *  Penyaringnya sama: PROGRAM, KUNJUNGAN (sudah / belum hari ini), dan HARI.
 *  Seluruh layar dipakai untuk peta supaya titik toko dapat dilihat jelas.
 * ========================================================================== */

class _RtsProgramPetaPenuh extends StatefulWidget {
  const _RtsProgramPetaPenuh({
    required this.toko,
    required this.sudah,
    required this.dikunjungi,
    required this.namaProgram,
    required this.programAwal,
    required this.kunjunganAwal,
    required this.hariAwal,
    this.sayaLat,
    this.sayaLng,
  });

  /// Seluruh toko yang bertitik koordinat.
  final List<Map<String, dynamic>> toko;

  /// Toko yang sudah mengikuti tiap program: {nama program: {id_customer}}.
  final Map<String, Set<String>> sudah;

  /// Toko yang sudah dikunjungi hari ini.
  final Set<String> dikunjungi;

  final List<String> namaProgram;
  final String programAwal;
  final String kunjunganAwal;
  final String hariAwal;
  final double? sayaLat;
  final double? sayaLng;

  @override
  State<_RtsProgramPetaPenuh> createState() => _RtsProgramPetaPenuhState();
}

class _RtsProgramPetaPenuhState extends State<_RtsProgramPetaPenuh> {
  late String _program = widget.programAwal;
  late String _kunjungan = widget.kunjunganAwal;
  late String _hari = widget.hariAwal;

  List<Map<String, dynamic>> _saring() {
    return widget.toko
        .where((Map<String, dynamic> t) {
          if (!_adaTitik(t)) return false;

          final String id = '${t['id_customer']}';

          if (_program != 'SEMUA' &&
              !(widget.sudah[_program] ?? <String>{}).contains(id)) {
            return false;
          }

          if (_kunjungan == 'SUDAH' && !widget.dikunjungi.contains(id)) {
            return false;
          }

          if (_kunjungan == 'BELUM' && widget.dikunjungi.contains(id)) {
            return false;
          }

          if (_hari != 'SEMUA' &&
              !'${t['hari']}'.toUpperCase().contains(_hari.toUpperCase())) {
            return false;
          }

          return true;
        })
        .map((Map<String, dynamic> t) => <String, dynamic>{
              ...t,
              'program_sudah': _program == 'SEMUA'
                  ? widget.sudah.values
                      .any((Set<String> s) => s.contains('${t['id_customer']}'))
                  : ((widget.sudah[_program] ?? <String>{})
                      .contains('${t['id_customer']}')),
            })
        .toList();
  }

  Widget _chip(String teks, bool aktif, Color warna, VoidCallback tekan) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: ChoiceChip(
        label: Text(
          teks,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            color: aktif ? Colors.white : rtsKsTeks,
          ),
        ),
        selected: aktif,
        onSelected: (_) => tekan(),
        selectedColor: warna,
        backgroundColor: Colors.white,
        side: BorderSide(color: aktif ? warna : rtsKsGaris),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _baris(String judul, List<Widget> chip) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          judul,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: rtsKsTeks2,
          ),
        ),
        const SizedBox(height: 2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: chip),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> tampil = _saring();
    int jmlSudah = 0;

    for (final Map<String, dynamic> t in tampil) {
      if (t['program_sudah'] == true) jmlSudah++;
    }

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Peta Program (layar penuh)'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Tutup peta penuh',
            icon: const Icon(Icons.close_fullscreen_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _baris('PROGRAM', <Widget>[
                  for (final String p in widget.namaProgram)
                    _chip(
                      p,
                      _program == p,
                      rtsKsMaroon,
                      () => setState(() => _program = p),
                    ),
                ]),
                const SizedBox(height: 4),
                _baris('KUNJUNGAN', <Widget>[
                  for (final String k in <String>['SEMUA', 'SUDAH', 'BELUM'])
                    _chip(
                      k,
                      _kunjungan == k,
                      k == 'SUDAH'
                          ? rtsKsHijau
                          : (k == 'BELUM' ? rtsKsKuning : rtsKsMaroon),
                      () => setState(() => _kunjungan = k),
                    ),
                ]),
                const SizedBox(height: 4),
                _baris('HARI', <Widget>[
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
                    _chip(
                      h,
                      _hari == h,
                      h == 'SEMUA' ? rtsKsMaroon : rtsPetaWarnaHari(h),
                      () => setState(() => _hari = h),
                    ),
                ]),
                const SizedBox(height: 5),
                Text(
                  '${tampil.length} toko tampil, $jmlSudah sudah mengikuti '
                  'program (hijau) dan ${tampil.length - jmlSudah} belum (merah). '
                  'Segitiga biru = posisi Bapak.',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: rtsKsTeks2,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _petaMiniProgram(
              toko: tampil,
              sayaLat: widget.sayaLat,
              sayaLng: widget.sayaLng,
              penuh: true,
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------- halaman */

/// Menu PRO "Program": daftar customer yang mengikuti program + tombol
/// melayang untuk menginput program.
class RtsProgramPage extends StatefulWidget {
  /// [jenisAwal] : nama program yang langsung dipilih saat halaman dibuka
  ///               (dipakai tombol Program Introdeal / Program BD pada versi
  ///               sebelumnya; sekarang hanya sebagai cadangan supaya
  ///               pemanggilan lama tetap sah).
  /// [bukaAwal]   : 'input' = langsung membuka form INPUT PROGRAM,
  ///               'peta'  = langsung membuka peta & filter program.
  const RtsProgramPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
    this.jenisAwal,
    this.bukaAwal = '',
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;
  final String? jenisAwal;
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

  /// Daftar program: INTRODEAL, BD, dan program buatan Sales.
  List<Map<String, dynamic>> _program = <Map<String, dynamic>>[];

  /// List customer yang mengikuti program (hasil dari HP).
  List<Map<String, dynamic>> _customer = <Map<String, dynamic>>[];

  /// Penyaring program yang sedang dipilih ('' = semua program).
  String _saring = '';

  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  String _catatan = '';

  /// Jumlah catatan program di HP yang belum dikirim ke server.
  int _belumKirim = 0;

  /// Penyaring SALES DISTRICT: daftar customer yang dibaca cukup satu
  /// district, supaya menu Program tetap ringan.
  RtsDistrict _district = const RtsDistrict();

  /// Penyaring HARI KUNJUNGAN pada List Customer ('Semua' = semua hari).
  /// Dengan penyaring ini daftar customer yang mengikuti program dapat dipilah
  /// per hari kunjungan (Senin ... Minggu).
  String _hari = 'Semua';

  /// Penyaring KUNJUNGAN pada List Customer: Semua / SUDAH / BELUM dikunjungi
  /// hari ini.
  String _kunjungan = 'Semua';

  /// Toko yang sudah dikunjungi HARI INI (id customer).
  Set<String> _dikunjungi = <String>{};

  @override
  void initState() {
    super.initState();

    // Nilai awal dari pemanggilan versi lama (tombol Program Introdeal/BD).
    final String awal = '${widget.jenisAwal ?? ''}'.trim().toUpperCase();
    if (awal.isNotEmpty) _saring = awal;

    unawaited(_muat());

    // Halaman yang diminta langsung dibuka (input program / peta & filter).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final String minta = widget.bukaAwal.trim().toLowerCase();
      if (minta.isEmpty) return;

      // Ditunda sedikit supaya daftar program sempat dimuat lebih dulu.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;

        if (minta == 'input') {
          unawaited(_bukaInputProgram());
          return;
        }

        if (minta == 'peta' || minta == 'program' || minta == 'filter') {
          unawaited(_petaFilter());
        }
      });
    });
  }

  /* -------------------------------------------------------------------- muat */

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      // Penyaring Sales District dibaca lebih dulu supaya daftar customer
      // langsung dipotong sesuai pilihan.
      if (_district.daftar.isEmpty) {
        _district = await RtsDistrict.muat();

        if (!mounted) return;
      }

      final Map<String, dynamic> jenis = await _api.kirim('jenis_daftar');
      final Map<String, dynamic> daftar = await _api.kirim(
        'program_customer_daftar',
        <String, dynamic>{
          'jenis': _saring,
          'batas': 300,
          'district': _district.district,
        },
      );
      final Map<String, dynamic> ringkas = await _api.kirim('offline_ringkas');

      // Toko yang sudah dikunjungi hari ini (dipakai penyaring KUNJUNGAN).
      final Set<String> dikunjungi = <String>{};

      try {
        final Map<String, dynamic> kunjungan =
            await _api.kirim('kunjungan_hari_ini');
        final List<dynamic> ids = (kunjungan['id_customer'] is List)
            ? kunjungan['id_customer'] as List<dynamic>
            : <dynamic>[];

        dikunjungi.addAll(ids.map((dynamic e) => '$e'));
      } on RtsKasirGalat {
        // riwayat kunjungan gagal dibaca: daftar tetap ditampilkan
      }

      if (!mounted) return;

      setState(() {
        _program = _daftarDari(jenis['items']);
        _customer = _daftarDari(daftar['items']);
        _catatan = '${daftar['message'] ?? ''}';
        _belumKirim = int.tryParse('${ringkas['program_input_belum'] ?? 0}') ?? 0;
        _dikunjungi = dikunjungi;
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

  /// List customer yang mengikuti program SESUDAH penyaring HARI KUNJUNGAN
  /// dan KUNJUNGAN dipakai.
  List<Map<String, dynamic>> get _tampil {
    return _customer.where((Map<String, dynamic> c) {
      final String id = '${c['id_customer']}';

      if (_kunjungan == 'SUDAH' && !_dikunjungi.contains(id)) return false;
      if (_kunjungan == 'BELUM' && _dikunjungi.contains(id)) return false;

      if (_hari != 'Semua') {
        final String hariToko = '${c['hari']}'.toUpperCase();

        if (!hariToko.contains(_hari.toUpperCase())) return false;
      }

      return true;
    }).toList();
  }

  /// Mengganti penyaring SALES DISTRICT: pilihan disimpan (dipakai bersama
  /// seluruh menu PRO), lalu daftar customer dibaca ulang.
  Future<void> _ubahDistrict(String district) async {
    if (district == _district.district) return;

    setState(() {
      _district = RtsDistrict(
        daftar: _district.daftar,
        district: district,
        terkunci: _district.terkunci,
        jumlah: _district.jumlah,
        districtSaya: _district.districtSaya,
        sinkronPada: _district.sinkronPada,
      );
    });

    await RtsDistrict.simpan(district);

    if (!mounted) return;

    await _muat();
  }

  List<Map<String, dynamic>> _daftarDari(dynamic isi) {
    return (isi is List ? isi : <dynamic>[])
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
        .toList();
  }

  /* ------------------------------------------------------------ daftar program */

  /// Mengelola daftar program: menambah, mengubah, dan menghapus.
  Future<void> _kelolaProgram() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: const Text('Daftar program'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: <Widget>[
                const Text(
                  'INTRODEAL (program paket 2+1 / 1+1) dan BD (New Brand '
                  'Distribution) sudah tersedia. Bapak juga dapat membuat '
                  'PROGRAM SENDIRI, misalnya program untuk produk tertentu.',
                  style: TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
                ),
                const SizedBox(height: 8),
                for (final Map<String, dynamic> p in _program)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      p['pakai_paket'] == true
                          ? Icons.card_giftcard_outlined
                          : Icons.new_releases_outlined,
                      color: rtsKsMaroon,
                      size: 20,
                    ),
                    title: Text(
                      '${p['nama']}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      '${p['keterangan']}'
                      '${p['pakai_paket'] == true ? ' - memakai paket' : ' - tanpa paket'}'
                      ' - ${p['jumlah_toko'] ?? 0} customer',
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        IconButton(
                          tooltip: 'Ubah keterangan',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await _formProgram(awal: p);
                          },
                        ),
                        if (p['bawaan'] != true)
                          IconButton(
                            tooltip: 'Hapus program',
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await _hapusProgram(p);
                            },
                          ),
                      ],
                    ),
                  ),
              ],
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
                unawaited(_formProgram());
              },
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('PROGRAM BARU'),
            ),
          ],
        ),
      ),
    );

    await _muat();
  }

  /// Membuat / mengubah satua program (nama, keterangan, memakai paket atau tidak).
  Future<void> _formProgram({Map<String, dynamic>? awal}) async {
    final bool baru = awal == null;
    final TextEditingController nama = TextEditingController(
      text: baru ? '' : '${awal!['nama']}',
    );
    final TextEditingController keterangan = TextEditingController(
      text: baru ? '' : '${awal!['keterangan']}',
    );

    bool pakaiPaket = !baru && awal!['pakai_paket'] == true;

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: Text(baru ? 'Program baru' : 'Ubah program'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: nama,
                  textCapitalization: TextCapitalization.characters,
                  enabled: baru,
                  decoration: const InputDecoration(
                    labelText: 'Nama program (contoh: PROGRAM GAWIH)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (boleh kosong)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pakaiPaket,
                  onChanged: (bool v) => setDialog(() => pakaiPaket = v),
                  title: const Text(
                    'Program memakai PAKET',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Contoh INTRODEAL memakai paket 2+1 / 1+1. Program seperti '
                    'BD tidak memakai paket.',
                    style: TextStyle(fontSize: 11),
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
      ),
    );

    if (simpan != true || !mounted) return;

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('jenis_simpan', <String, dynamic>{
        'nama': nama.text,
        'keterangan': keterangan.text,
        'pakai_paket': pakaiPaket,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Program tersimpan di HP.'}');
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _hapusProgram(Map<String, dynamic> p) async {
    final bool setuju = await showDialog<bool>(
          context: context,
          builder: (BuildContext ctx) => AlertDialog(
            title: Text('Hapus program ${p['nama']}?'),
            content: const Text(
              'Program buatan Sales akan dihapus dari daftar pilihan. Riwayat '
              'input yang sudah dicatat TETAP tersimpan.',
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
          await _api.kirim('jenis_hapus', <String, dynamic>{'id': p['id']});

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Program dihapus.'}');
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /* --------------------------------------------------------------- input program */

  /// Membuka form INPUT PROGRAM dari tombol melayang, lengkap dengan
  /// pemeriksa galat supaya kegagalan membaca data di HP tidak mematikan
  /// seluruh layar Program.
  Future<void> _bukaInputProgram() async {
    try {
      await _inputProgram();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } catch (e) {
      if (mounted) {
        rtsKsPesan(context, 'Gagal membuka form input program: $e', galat: true);
      }
    }
  }

  /// Membuka form INPUT PROGRAM (dipakai tombol melayang).
  Future<void> _inputProgram({Map<String, dynamic>? toko, String program = ''}) async {
    final bool? berubah = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _RtsInputProgramPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          pengguna: widget.pengguna,
          toko: toko,
          programAwal: program.isEmpty ? _saring : program,
        ),
      ),
    );

    if (berubah == true) await _muat();
  }

  /* ------------------------------------------------------- detail satu customer */

  /// Riwayat program satu customer + tombol tambah / hapus.
  Future<void> _detailCustomer(Map<String, dynamic> c) async {
    final String idCustomer = '${c['id_customer'] ?? ''}';

    List<Map<String, dynamic>> riwayat;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'program_input_daftar',
        <String, dynamic>{'id_customer': idCustomer, 'batas': 200},
      );

      riwayat = _daftarDari(hasil['items']);
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
      return;
    }

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: Text('${c['nama_toko']}'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    rtsKsSambung(
                      'ID $idCustomer',
                      '${c['jumlah_program'] ?? 0} program diikuti',
                    ),
                    style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final dynamic p in (c['program'] is List)
                          ? c['program'] as List<dynamic>
                          : <dynamic>[])
                        if (p is Map)
                          _lencana(
                            text: '${p['jenis']}'
                                '${'${p['paket']}'.isEmpty ? '' : ' ${p['paket']}'}',
                            warna: rtsKsMaroon,
                          ),
                    ],
                  ),
                  const Divider(height: 18),
                  if (riwayat.isEmpty)
                    const Text(
                      'Belum ada catatan program untuk customer ini.',
                      style: TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                    ),
                  for (final Map<String, dynamic> s in riwayat)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${s['jenis']}'
                        '${'${s['paket']}'.isEmpty ? '' : ' paket ${s['paket']}'}'
                        '${'${s['nama_produk']}'.isEmpty ? '' : ' - ${s['nama_produk']}'}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        rtsKsSambung(
                          '${s['jumlah_teks']} ${s['satuan']}',
                          rtsKsSambung('${s['tanggal']}',
                              '${s['kirim'] == true ? 'sudah dikirim' : 'belum dikirim'}'),
                        ),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        tooltip: 'Hapus catatan ini',
                        icon: const Icon(Icons.delete_outline, size: 19),
                        onPressed: () async {
                          try {
                            await _api.kirim('program_input_hapus',
                                <String, dynamic>{'id': s['id']});

                            setDialog(() => riwayat.remove(s));

                            if (ctx2.mounted) {
                              rtsKsPesan(ctx2, 'Catatan dihapus dari HP.');
                            }
                          } on RtsKasirGalat catch (e) {
                            if (ctx2.mounted) rtsKsPesan(ctx2, e.pesan, galat: true);
                          }
                        },
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
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_inputProgram(
                  toko: <String, dynamic>{
                    'id': idCustomer,
                    'nama': '${c['nama_toko']}',
                  },
                ));
              },
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('TAMBAH PROGRAM'),
            ),
          ],
        ),
      ),
    );

    await _muat();
  }

  /* ------------------------------------------------------- catatan tersimpan di HP */

  /// Melihat & membereskan catatan program yang tersimpan di HP.
  Future<void> _lihatCatatan() async {
    List<Map<String, dynamic>> items;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'program_input_daftar',
        <String, dynamic>{'batas': 200},
      );

      items = _daftarDari(hasil['items']);
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
                    '${s['jenis']}'
                    '${'${s['paket']}'.isEmpty ? '' : ' paket ${s['paket']}'}'
                    ' - ${s['jumlah_teks']} ${s['satuan']}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    rtsKsSambung(
                      '${s['nama_toko']} (${s['id_customer']})',
                      '${s['tanggal']}'
                          '${s['kirim'] == true ? ' - sudah dikirim' : ' - belum dikirim'}',
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: IconButton(
                    tooltip: 'Hapus catatan ini',
                    icon: const Icon(Icons.delete_outline, size: 19),
                    onPressed: () async {
                      try {
                        await _api.kirim('program_input_hapus',
                            <String, dynamic>{'id': s['id']});

                        setDialog(() => items.removeAt(i));

                        if (ctx2.mounted) {
                          rtsKsPesan(ctx2, 'Catatan dihapus dari HP.');
                        }
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

    await _muat();
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

          kiriman.add(<String, dynamic>{
            'tabel': 'program_input',
            'id_hp': k['id'],
          });
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
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    } finally {
      if (mounted) setState(() => _sibuk = false);

      await _muat();
    }
  }

  /* ------------------------------------------------------------------------ peta */

  /// PETA & FILTER: peta toko + penyaring program, kunjungan, dan hari.
  Future<void> _petaFilter() async {
    List<Map<String, dynamic>> toko;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'toko_peta',
        <String, dynamic>{'district': _district.district},
      );

      toko = _daftarDari(hasil['items']);
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
      return;
    }

    // Toko yang sudah mengikuti tiap program (dari catatan di HP).
    final Map<String, Set<String>> sudah = <String, Set<String>>{};

    for (final Map<String, dynamic> p in _program) {
      final String nama = '${p['nama']}';

      try {
        final Map<String, dynamic> hasil = await _api.kirim(
          'program_customer_daftar',
          <String, dynamic>{
            'jenis': nama,
            'batas': 500,
            'district': _district.district,
          },
        );

        sudah[nama] = <String>{
          for (final Map<String, dynamic> c in _daftarDari(hasil['items']))
            '${c['id_customer']}',
        };
      } on RtsKasirGalat {
        sudah[nama] = <String>{};
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
      // riwayat kunjungan gagal dibaca: penyaring tetap jalan
    }

    double? sayaLat;
    double? sayaLng;

    final dynamic posisi = await rtsKsAmbilLokasi();

    if (posisi != null) {
      sayaLat = (posisi.latitude as num).toDouble();
      sayaLng = (posisi.longitude as num).toDouble();
    }

    if (!mounted) return;

    String fProgram = _saring.isEmpty ? 'SEMUA' : _saring;
    String fKunjungan = 'SEMUA';
    String fHari = 'SEMUA';

    final List<String> namaProgram = <String>[
      'SEMUA',
      ..._program.map((Map<String, dynamic> p) => '${p['nama']}'),
    ];

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) {
          List<Map<String, dynamic>> saring() {
            return toko.where((Map<String, dynamic> t) {
              if (!_adaTitik(t)) return false;

              final String id = '${t['id_customer']}';

              if (fProgram != 'SEMUA' &&
                  !(sudah[fProgram] ?? <String>{}).contains(id)) {
                return false;
              }

              if (fKunjungan == 'SUDAH' && !dikunjungi.contains(id)) return false;
              if (fKunjungan == 'BELUM' && dikunjungi.contains(id)) return false;

              if (fHari != 'SEMUA' &&
                  !'${t['hari']}'.toUpperCase().contains(fHari)) {
                return false;
              }

              return true;
            }).toList();
          }

          final List<Map<String, dynamic>> tampil =
              saring().map((Map<String, dynamic> t) => <String, dynamic>{
                        ...t,
                        'program_sudah': fProgram == 'SEMUA'
                            ? (sudah.values.any(
                                (Set<String> s) => s.contains('${t['id_customer']}')))
                            : ((sudah[fProgram] ?? <String>{})
                                .contains('${t['id_customer']}')),
                      }).toList();

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
                        for (final String p in namaProgram)
                          ChoiceChip(
                            label: Text('PROGRAM $p',
                                style: const TextStyle(fontSize: 11)),
                            selected: fProgram == p,
                            onSelected: (_) => setDialog(() => fProgram = p),
                          ),
                        for (final String k in <String>['SEMUA', 'SUDAH', 'BELUM'])
                          ChoiceChip(
                            label: Text('KUNJUNGAN $k',
                                style: const TextStyle(fontSize: 11)),
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
                            label: Text('HARI $h',
                                style: const TextStyle(fontSize: 11)),
                            selected: fHari == h,
                            onSelected: (_) => setDialog(() => fHari = h),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$fProgram: ${tampil.length} toko tampil, $jmlSudah sudah '
                      'mengikuti program (hijau) dan ${tampil.length - jmlSudah} '
                      'belum (merah).',
                      style: const TextStyle(
                          fontSize: 11, color: rtsKsTeks2, height: 1.35),
                    ),
                    const SizedBox(height: 6),
                    _petaMiniProgram(
                      toko: tampil,
                      sayaLat: sayaLat,
                      sayaLng: sayaLng,
                      tinggi: 260,
                    ),
                    const SizedBox(height: 6),
                    if (tampil.isEmpty)
                      const Text(
                        'Tidak ada toko yang cocok dengan penyaring. Ubah '
                        'pilihan di atas.',
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
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
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
                          warna: t['program_sudah'] == true
                              ? rtsKsHijau
                              : rtsKsTeks2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: <Widget>[
              // Membuka peta SATU LAYAR PENUH dengan penyaring yang sama.
              TextButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();

                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => _RtsProgramPetaPenuh(
                        toko: toko,
                        sudah: sudah,
                        dikunjungi: dikunjungi,
                        namaProgram: namaProgram,
                        programAwal: fProgram,
                        kunjunganAwal: fKunjungan,
                        hariAwal: fHari,
                        sayaLat: sayaLat,
                        sayaLng: sayaLng,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.open_in_full_rounded, size: 17),
                label: const Text('PETA PENUH'),
              ),
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

  /* ------------------------------------------------------------------ kirim server */

  /// Permintaan ke server (dipakai mengirim catatan program).
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

  /* -------------------------------------------------------------------- layar */

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

  Widget _kartuCustomer(Map<String, dynamic> c) {
    final int jumlah = int.tryParse('${c['jumlah'] ?? 0}') ?? 0;
    final String hari = '${c['hari'] ?? ''}';
    final String district = '${c['district'] ?? ''}';
    final bool sudahDikunjungi = _dikunjungi.contains('${c['id_customer']}');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 7),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: rtsKsGaris),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => unawaited(_detailCustomer(c)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                radius: 15,
                backgroundColor: rtsKsMaroon,
                foregroundColor: Colors.white,
                child: Text(
                  '${c['nama_toko']}'.trim().isEmpty
                      ? '?'
                      : '${c['nama_toko']}'.trim().substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${c['nama_toko']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      rtsKsSambung(
                        'ID ${c['id_customer']} - $jumlah catatan program',
                        rtsKsSambung(
                          hari.isEmpty ? '' : 'Hari $hari',
                          district.isEmpty ? '' : district,
                        ),
                      ),
                      style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final dynamic p in (c['program'] is List)
                            ? c['program'] as List<dynamic>
                            : <dynamic>[])
                          if (p is Map)
                            _lencana(
                              text: '${p['jenis']}'
                                  '${'${p['paket']}'.isEmpty ? '' : ' ${p['paket']}'}',
                              warna: rtsKsMaroon,
                            ),
                        if (sudahDikunjungi)
                          _lencana(text: 'SUDAH DIKUNJUNGI', warna: rtsKsHijau),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: rtsKsTeks2, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> namaProgram = <String>[
      for (final Map<String, dynamic> p in _program) '${p['nama']}',
    ];

    // List customer sesudah penyaring HARI KUNJUNGAN dan KUNJUNGAN dipakai.
    final List<Map<String, dynamic>> tampil = _tampil;

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Program'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Peta & filter program',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => unawaited(_petaFilter()),
          ),
          IconButton(
            tooltip: _belumKirim > 0
                ? 'Catatan program di HP: $_belumKirim belum dikirim'
                : 'Catatan program di HP',
            icon: Badge(
              isLabelVisible: _belumKirim > 0,
              label: Text('$_belumKirim'),
              child: const Icon(Icons.cloud_upload_outlined),
            ),
            onPressed: () => unawaited(_lihatCatatan()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => unawaited(_bukaInputProgram()),
        icon: const Icon(Icons.add_rounded),
        label: const Text('INPUT PROGRAM'),
      ),
      body: RefreshIndicator(
        onRefresh: _muat,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 86),
          children: <Widget>[
            if (_sibuk) const LinearProgressIndicator(minHeight: 3),
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'LIST CUSTOMER YANG MENGIKUTI PROGRAM',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: rtsKsTeks,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => unawaited(_kelolaProgram()),
                  icon: const Icon(Icons.tune_rounded, size: 17),
                  label: const Text('DAFTAR PROGRAM',
                      style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            Text(
              'Tekan tombol merah INPUT PROGRAM di bawah untuk memilih customer '
              'dari List Customer, lalu pilih programnya (Introdeal, BD, atau '
              'program buatan Bapak sendiri). Produk diambil dari Menu Barang '
              'Bawaan, jadi tetap dapat dikerjakan tanpa internet.',
              style: const TextStyle(fontSize: 11, color: rtsKsTeks2, height: 1.4),
            ),
            const SizedBox(height: 8),
            RtsDistrictBar(
              info: _district,
              onUbah: (String d) => unawaited(_ubahDistrict(d)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('SEMUA PROGRAM',
                        style: TextStyle(fontSize: 11)),
                    selected: _saring.isEmpty,
                    onSelected: (_) {
                      setState(() => _saring = '');
                      unawaited(_muat());
                    },
                  ),
                  for (final String p in namaProgram) ...<Widget>[
                    const SizedBox(width: 6),
                    ChoiceChip(
                      label: Text('$p', style: const TextStyle(fontSize: 11)),
                      selected: _saring == p,
                      onSelected: (_) {
                        setState(() => _saring = p);
                        unawaited(_muat());
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Hari kunjungan:',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: rtsKsTeks2,
              ),
            ),
            const SizedBox(height: 3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String h in <String>[
                    'Semua',
                    'Senin',
                    'Selasa',
                    'Rabu',
                    'Kamis',
                    'Jumat',
                    'Sabtu',
                    'Minggu',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          h == 'Semua' ? 'SEMUA HARI' : h.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _hari == h ? Colors.white : rtsKsTeks,
                          ),
                        ),
                        selected: _hari == h,
                        onSelected: (_) => setState(() => _hari = h),
                        selectedColor: h == 'Semua'
                            ? rtsKsMaroon
                            : rtsPetaWarnaHari(h),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: _hari == h
                              ? (h == 'Semua' ? rtsKsMaroon : rtsPetaWarnaHari(h))
                              : rtsKsGaris,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Kunjungan hari ini:',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: rtsKsTeks2,
              ),
            ),
            const SizedBox(height: 3),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String k in <String>['Semua', 'SUDAH', 'BELUM'])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          k == 'Semua' ? 'SEMUA KUNJUNGAN' : k,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _kunjungan == k ? Colors.white : rtsKsTeks,
                          ),
                        ),
                        selected: _kunjungan == k,
                        onSelected: (_) => setState(() => _kunjungan = k),
                        selectedColor: k == 'SUDAH'
                            ? rtsKsHijau
                            : (k == 'BELUM' ? rtsKsKuning : rtsKsMaroon),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: _kunjungan == k
                              ? (k == 'SUDAH'
                                  ? rtsKsHijau
                                  : (k == 'BELUM' ? rtsKsKuning : rtsKsMaroon))
                              : rtsKsGaris,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_catatan.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '${_tampil.length} dari ${_customer.length} customer tampil. '
                  '$_catatan',
                  style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                ),
              ),
            if (_galat.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _galat,
                  style: const TextStyle(color: rtsKsMerah, fontSize: 12),
                ),
              ),
            const SizedBox(height: 8),
            if (_memuat && tampil.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (!_memuat && tampil.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
                child: Text(
                  (_customer.isEmpty
                          ? 'Belum ada customer yang mengikuti program'
                              '${_saring.isEmpty ? '' : ' $_saring'}.'
                          : 'Tidak ada customer yang cocok dengan penyaring '
                              'Hari${_hari == 'Semua' ? '' : ' $_hari'} / '
                              'Kunjungan${_kunjungan == 'Semua' ? '' : ' $_kunjungan'}. '
                              'Ubah penyaring di atas.') +
                      '\n\n'
                      'Tekan tombol merah INPUT PROGRAM di kanan bawah, pilih '
                      'customer dari List Customer, lalu pilih programnya.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: rtsKsTeks2,
                    height: 1.5,
                  ),
                ),
              ),
            for (final Map<String, dynamic> c in tampil) _kartuCustomer(c),
          ],
        ),
      ),
    );
  }
}

/* ============================================================================
 *  INPUT PROGRAM (tombol melayang pada menu Program)
 * ----------------------------------------------------------------------------
 *  Urutan kerjanya sesuai permintaan Bapak:
 *      1. Muncul LIST CUSTOMER -> pilih satu toko/customer.
 *      2. Pilih PROGRAMNYA: INTRODEAL (2+1 / 1+1 / paket sendiri), BD, atau
 *         program buatan Sales sendiri (tombol PROGRAM BARU).
 *      3. Pilih produk dari Menu Barang Bawaan (boleh dikosongkan bila hanya
 *         ingin mencatat customer yang mengikuti program).
 *      4. SIMPAN DI HP - tidak memerlukan internet.
 * ========================================================================== */

class _RtsInputProgramPage extends StatefulWidget {
  const _RtsInputProgramPage({
    required this.baseUrl,
    required this.token,
    required this.pengguna,
    this.toko,
    this.programAwal = '',
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  /// Customer yang sudah dipilih sebelumnya (boleh kosong).
  final Map<String, dynamic>? toko;

  /// Program yang sudah dipilih sebelumnya (boleh kosong).
  final String programAwal;

  @override
  State<_RtsInputProgramPage> createState() => _RtsInputProgramPageState();
}

class _RtsInputProgramPageState extends State<_RtsInputProgramPage> {
  late final RtsKasirApi _api = RtsKasirApi(
    baseUrl: widget.baseUrl,
    token: widget.token,
    pengguna: widget.pengguna,
  );

  final TextEditingController _jumlah = TextEditingController(text: '1');
  final TextEditingController _catatan = TextEditingController();

  List<Map<String, dynamic>> _program = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _paketItems = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _produk = <Map<String, dynamic>>[];

  Map<String, dynamic>? _toko;
  String _programPilih = '';
  String _paket = '';
  String _satuan = 'PACK';
  int _produkPilih = -1;

  double? _sayaLat;
  double? _sayaLng;

  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';

  @override
  void initState() {
    super.initState();

    _toko = widget.toko;
    _programPilih = widget.programAwal.toUpperCase();

    unawaited(_muat());
  }

  @override
  void dispose() {
    _jumlah.dispose();
    _catatan.dispose();
    super.dispose();
  }

  /* -------------------------------------------------------------------- muat */

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> jenis = await _api.kirim('jenis_daftar');
      final Map<String, dynamic> produk =
          await _api.kirim('produk_daftar', <String, dynamic>{'batas': 300});

      if (_toko != null) _toko = await _lengkapiToko(_toko!);

      final dynamic posisi = await rtsKsAmbilLokasi();

      if (!mounted) return;

      setState(() {
        _program = _daftarDari(jenis['items']);
        _produk = _daftarDari(produk['items']);

        if (_programPilih.isEmpty && _program.isNotEmpty) {
          _programPilih = '${_program.first['nama']}';
        }

        if (posisi != null) {
          _sayaLat = (posisi.latitude as num).toDouble();
          _sayaLng = (posisi.longitude as num).toDouble();
        }

        _memuat = false;
      });

      await _muatPaket();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
      });
    }
  }

  List<Map<String, dynamic>> _daftarDari(dynamic isi) {
    return (isi is List ? isi : <dynamic>[])
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
        .toList();
  }

  Map<String, dynamic>? get _programData {
    for (final Map<String, dynamic> p in _program) {
      if ('${p['nama']}' == _programPilih) return p;
    }

    return null;
  }

  bool get _pakaiPaket => _programData?['pakai_paket'] == true;

  /// Membaca daftar paket program yang sedang dipilih.
  Future<void> _muatPaket() async {
    if (_programPilih.isEmpty) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'paket_daftar',
        <String, dynamic>{'jenis': _programPilih},
      );

      if (!mounted) return;

      setState(() {
        _paketItems = _daftarDari(hasil['items']);

        if (!_pakaiPaket) {
          _paket = '';
        } else if (_paket.isEmpty ||
            !_paketItems.any((Map<String, dynamic> p) => '${p['nama']}' == _paket)) {
          _paket = _paketItems.isEmpty ? '' : '${_paketItems.first['nama']}';
        }
      });
    } on RtsKasirGalat {
      // daftar paket tidak terbaca: program tetap dapat dipilih
    }
  }

  /* ------------------------------------------------------------------ customer */

  /// Melengkapi toko terpilih dengan titik koordinat dan hari kunjungan.
  Future<Map<String, dynamic>> _lengkapiToko(Map<String, dynamic> toko) async {
    try {
      // Dibaca SATU toko saja (bukan seluruh daftar), supaya form input
      // program tetap cepat walaupun salinan di HP memuat ribuan toko.
      final Map<String, dynamic> hasil = await _api.kirim(
        'toko_peta',
        <String, dynamic>{
          'id_customer': '${toko['id_customer'] ?? toko['id'] ?? ''}',
        },
      );

      for (final Map<String, dynamic> t in _daftarDari(hasil['items'])) {
        if ('${t['id_customer']}' == '${toko['id']}') {
          return <String, dynamic>{...toko, ...t};
        }
      }
    } on RtsKasirGalat {
      // titik toko tidak ditemukan: peta tetap tampil tanpa titik toko
    }

    return toko;
  }

  /// Menampilkan LIST CUSTOMER (memakai halaman pemilih toko yang sudah ada:
  /// datanya dari master_toko dan diurutkan dari yang TERDEKAT).
  Future<void> _pilihCustomer() async {
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
  }

  /* --------------------------------------------------------------- program baru */

  Future<void> _programBaru() async {
    final TextEditingController nama = TextEditingController();
    final TextEditingController keterangan = TextEditingController();

    bool pakaiPaket = false;

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setDialog) => AlertDialog(
          title: const Text('Program baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Program buatan Bapak sendiri, misalnya PROGRAM GAWIH atau '
                  'program khusus produk tertentu.',
                  style: TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nama,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Nama program',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: keterangan,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan (boleh kosong)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: pakaiPaket,
                  onChanged: (bool v) => setDialog(() => pakaiPaket = v),
                  title: const Text(
                    'Program memakai PAKET',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Contoh INTRODEAL memakai paket 2+1 / 1+1.',
                    style: TextStyle(fontSize: 11),
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
      ),
    );

    if (simpan != true || !mounted) return;

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('jenis_simpan', <String, dynamic>{
        'nama': nama.text,
        'keterangan': keterangan.text,
        'pakai_paket': pakaiPaket,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Program tersimpan di HP.'}');

      await _muat();

      final dynamic posisi = await _api.kirim('jenis_daftar');

      for (final Map<String, dynamic> p in _daftarDari(posisi['items'])) {
        if ('${p['nama']}'.toUpperCase() ==
            nama.text.trim().toUpperCase()) {
          setState(() => _programPilih = '${p['nama']}');

          break;
        }
      }

      await _muatPaket();
    } on RtsKasirGalat catch (e) {
      if (mounted) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Membuat paket sendiri untuk program yang memakai paket (contoh 3+1).
  Future<void> _paketBaru() async {
    final TextEditingController nama = TextEditingController();
    final TextEditingController keterangan = TextEditingController();

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Paket sendiri'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
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
        'jenis': _programPilih,
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

  /* -------------------------------------------------------------------- simpan */

  String _tanggalHariIni() {
    final DateTime hari = DateTime.now();
    final String bulan = hari.month < 10 ? '0${hari.month}' : '${hari.month}';
    final String tanggal = hari.day < 10 ? '0${hari.day}' : '${hari.day}';

    return '${hari.year}-$bulan-$tanggal';
  }

  Future<void> _simpan() async {
    if (_sibuk) return;

    if (_toko == null) {
      rtsKsPesan(context, 'Pilih dulu customer dari LIST CUSTOMER.', galat: true);
      return;
    }

    if (_programPilih.isEmpty) {
      rtsKsPesan(context, 'Pilih dulu programnya.', galat: true);
      return;
    }

    final Map<String, dynamic> produk =
        (_produkPilih >= 0 && _produkPilih < _produk.length)
            ? _produk[_produkPilih]
            : <String, dynamic>{};

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('program_input_simpan', <String, dynamic>{
        'jenis': _programPilih,
        'paket': _pakaiPaket ? _paket : '',
        'paket_keterangan': _pakaiPaket ? _keteranganPaket(_paket) : '',
        'id_customer': '${_toko?['id'] ?? _toko?['id_customer'] ?? ''}',
        'nama_toko': '${_toko?['nama'] ?? ''}',
        'produk_id': produk['id'] ?? 0,
        'nama_produk': produk['nama'] ?? '',
        'sku': produk['sku'] ?? '',
        'jumlah': _jumlah.text,
        'satuan': _satuan,
        'tanggal': _tanggalHariIni(),
        'catatan': _catatan.text,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Program tersimpan di HP.'}');

      Navigator.of(context).pop(true);
    } on RtsKasirGalat catch (e) {
      if (mounted) {
        rtsKsPesan(context, e.pesan, galat: true);
        setState(() => _sibuk = false);
      }
    }
  }

  String _keteranganPaket(String nama) {
    for (final Map<String, dynamic> p in _paketItems) {
      if ('${p['nama']}' == nama) return '${p['keterangan'] ?? ''}';
    }

    return '';
  }

  /* --------------------------------------------------------------------- layar */

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> petaToko = _toko == null
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[_toko!];

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Input Program'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: <Widget>[
          if (_sibuk) const LinearProgressIndicator(minHeight: 3),
          if (_galat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _galat,
                style: const TextStyle(color: rtsKsMerah, fontSize: 12),
              ),
            ),
          if (_memuat)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: CircularProgressIndicator()),
            ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: rtsKsGaris),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '1. CUSTOMER (dari List Customer)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if (_toko == null)
                    const Text(
                      'Belum ada customer dipilih. Tekan tombol di bawah untuk '
                      'membuka List Customer (urut dari yang terdekat).',
                      style: TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
                    )
                  else
                    Text(
                      '${_toko!['nama']}\n'
                      'ID ${_toko!['id'] ?? _toko!['id_customer']}'
                      '${'${_toko!['alamat'] ?? ''}'.trim().isEmpty ? '' : ' - ${_toko!['alamat']}'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                      onPressed: _pilihCustomer,
                      icon: const Icon(Icons.people_alt_outlined, size: 18),
                      label: const Text('PILIH DARI LIST CUSTOMER'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: rtsKsGaris),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '2. PROGRAM',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final Map<String, dynamic> p in _program)
                        ChoiceChip(
                          label: Text(
                            '${p['nama']}',
                            style: const TextStyle(fontSize: 11.5),
                          ),
                          selected: _programPilih == '${p['nama']}',
                          onSelected: (_) {
                            setState(() => _programPilih = '${p['nama']}');
                            unawaited(_muatPaket());
                          },
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add_rounded, size: 15),
                        label: const Text('PROGRAM BARU',
                            style: TextStyle(fontSize: 11.5)),
                        onPressed: () => unawaited(_programBaru()),
                      ),
                    ],
                  ),
                  if (_programData != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_programData!['keterangan']}'
                        '${_pakaiPaket ? ' - program PAKET' : ' - tanpa paket'}',
                        style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                      ),
                    ),
                  if (_pakaiPaket) ...<Widget>[
                    const SizedBox(height: 8),
                    const Text(
                      'Paket (pilih satu)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rtsKsTeks2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: <Widget>[
                        for (final Map<String, dynamic> p in _paketItems)
                          ChoiceChip(
                            label: Text(
                              '${p['nama']}'
                              '${'${p['keterangan']}'.isEmpty ? '' : ' (${p['keterangan']})'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            selected: _paket == '${p['nama']}',
                            onSelected: (_) =>
                                setState(() => _paket = '${p['nama']}'),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add_rounded, size: 15),
                          label: const Text('PAKET SENDIRI',
                              style: TextStyle(fontSize: 11)),
                          onPressed: () => unawaited(_paketBaru()),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: rtsKsGaris),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '3. PRODUK (dari Barang Bawaan)',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  if (_produk.isEmpty)
                    const Text(
                      'Daftar produk masih kosong. Isi dulu Menu Barang Bawaan '
                      '(atau tekan SINKRONKAN SEKARANG pada menu Sinkronisasi), '
                      'lalu buka halaman ini lagi.',
                      style: TextStyle(fontSize: 11.5, color: rtsKsTeks2, height: 1.4),
                    )
                  else
                    DropdownButtonFormField<int>(
                      initialValue: _produkPilih,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Produk program',
                        border: OutlineInputBorder(),
                      ),
                      items: <DropdownMenuItem<int>>[
                        const DropdownMenuItem<int>(
                          value: -1,
                          child: Text('TANPA PRODUK (catatan saja)',
                              style: TextStyle(fontSize: 12.5)),
                        ),
                        for (int i = 0; i < _produk.length; i++)
                          DropdownMenuItem<int>(
                            value: i,
                            child: Text(
                              '${_produk[i]['nama']}'
                              '${'${_produk[i]['sku']}'.isEmpty ? '' : ' - ${_produk[i]['sku']}'}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                      ],
                      onChanged: (int? v) => setState(() => _produkPilih = v ?? -1),
                    ),
                  if (_produkPilih >= 0) ...<Widget>[
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: _jumlah,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Jumlah',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _satuan,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Satuan',
                              border: OutlineInputBorder(),
                            ),
                            items: const <DropdownMenuItem<String>>[
                              DropdownMenuItem<String>(
                                  value: 'PACK', child: Text('PACK')),
                              DropdownMenuItem<String>(
                                  value: 'BATANG', child: Text('BATANG')),
                              DropdownMenuItem<String>(
                                  value: 'BALL', child: Text('BALL')),
                            ],
                            onChanged: (String? v) =>
                                setState(() => _satuan = v ?? 'PACK'),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _catatan,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (boleh kosong)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'PETA LOKASI',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          _petaMiniProgram(
            toko: petaToko,
            sayaLat: _sayaLat,
            sayaLng: _sayaLng,
            tinggi: 190,
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _toko == null
                  ? 'Peta menampilkan posisi Bapak. Pilih customer supaya titik '
                      'tokonya ikut tampil.'
                  : 'Titik merah = toko yang dipilih, titik biru = posisi Bapak.',
              style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsHijau,
        foregroundColor: Colors.white,
        onPressed: _sibuk ? null : () => unawaited(_simpan()),
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('SIMPAN DI HP'),
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
