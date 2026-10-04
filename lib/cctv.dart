// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : CCTV ONLINE (KAMERA LALU LINTAS MEDAN)
//  Berkas : lib/cctv.dart
//  Versi  : 1   (4 Oktober 2026)
//
//  ISI BERKAS INI (dipisah dari main.dart supaya pembaruan berikutnya cukup
//  mengganti satu berkas):
//
//     1. RtsCctvPage      - DAFTAR KAMERA CCTV KOTA MEDAN
//            daftar dibaca dari server (api/cctv.php), dapat DICARI, dapat
//            diurutkan menurut NAMA / NOMOR / JARAK dari posisi HP, dan
//            disimpan di dalam HP supaya tetap terbaca walau tanpa internet.
//     2. RtsCctvPutarPage - PEMUTAR VIDEO (langsung di dalam aplikasi)
//            memutar siaran HLS (.m3u8), ada tombol play/pause, bisukan,
//            LAYAR PENUH, peta, salin tautan, dan jalan keluar "buka di
//            pemutar lain" bila kamera sedang dimatikan Dishub.
//     3. RtsCctvPetaPage  - PETA LOKASI KAMERA (OpenStreetMap)
//
//  SUMBER SIARAN
//  -------------
//  Kamera milik Dinas Perhubungan Kota Medan (ATCS / ITS Kota Medan) dan
//  terbuka untuk umum:  https://atcsdishub.medan.go.id/streaming
//  Tautan video memakai pola tetap:
//      https://atcsdishub.medan.go.id/stream/<KODE>/stream.m3u8
//  Daftar kamera diambil website (periksa_cctv.php atau api/cctv.php) lalu
//  disimpan sebagai data/cctv_medan.json dan dibaca aplikasi lewat api/cctv.php.
//
//  CATATAN PENTING
//  ---------------
//  - Menu ini khusus AKUN PRO: diperiksa aplikasi (Menu PRO) DAN diperiksa
//    ulang di server (api/cctv.php), jadi tidak dapat dilanggar.
//  - Aplikasi TIDAK menyimpan kata sandi apa pun untuk CCTV: siaran memang
//    terbuka untuk umum, sama seperti membukanya di peramban.
//  - Bila kamera sedang dimatikan / diperbaiki Dishub, aplikasi menampilkan
//    keterangan "sedang tidak tersedia" - itu bukan kerusakan aplikasi.
//  - Warna dan pesan dipakai bersama menu PRO lain (kasir.dart), peta memakai
//    penolong dari peta.dart supaya tampilannya seragam.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import 'kasir.dart';
import 'peta.dart';

/// Versi berkas ini - ditampilkan pada halaman daftar kamera.
const String rtsCctvVersiBerkas = '1';

/// Halaman resmi siaran (dibuka di peramban bila diminta).
const String rtsCctvHalaman = 'https://atcsdishub.medan.go.id/streaming';

/// Kunci penyimpanan daftar kamera di dalam HP.
const String rtsCctvKunciSimpan = 'rts_cctv_simpan';
const String rtsCctvKunciWaktu = 'rts_cctv_waktu';

/* ------------------------------------------------------------------------- */
/* MODEL DATA                                                                */
/* ------------------------------------------------------------------------- */

/// Satu kamera CCTV Kota Medan.
class RtsCctvKamera {
  const RtsCctvKamera({
    required this.kode,
    required this.nomor,
    required this.nama,
    required this.alias,
    required this.url,
    this.poster = '',
    this.lat = 0,
    this.lon = 0,
  });

  final String kode;
  final int nomor;
  final String nama;
  final String alias;
  final String url;
  final String poster;
  final double lat;
  final double lon;

  /// Titik peta kamera tersedia dan masuk akal.
  bool get adaTitik => rtsPetaTitikSah(lat, lon);

  LatLng get titik => LatLng(lat, lon);

  /// Tulisan untuk daftar: alias dipakai bila ada, kalau tidak nama.
  String get keterangan => alias.trim().isEmpty ? nama : alias;

  factory RtsCctvKamera.dari(Map<dynamic, dynamic> isi) {
    final Object? nomorMentah = isi['nomor'];

    return RtsCctvKamera(
      kode: '${isi['kode'] ?? ''}',
      nomor: nomorMentah is num
          ? nomorMentah.toInt()
          : int.tryParse('${nomorMentah ?? ''}') ?? 0,
      nama: '${isi['nama'] ?? ''}',
      alias: '${isi['alias'] ?? ''}',
      url: '${isi['url'] ?? ''}',
      poster: '${isi['poster'] ?? ''}',
      lat: _angka(isi['lat']),
      lon: _angka(isi['lon'] ?? isi['lng']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kode': kode,
        'nomor': nomor,
        'nama': nama,
        'alias': alias,
        'url': url,
        'poster': poster,
        'lat': lat,
        'lon': lon,
      };

  static double _angka(Object? nilai) {
    if (nilai is num) return nilai.toDouble();

    return double.tryParse('${nilai ?? ''}') ?? 0;
  }
}

/* ------------------------------------------------------------------------- */
/* PENOLONG UMUM                                                             */
/* ------------------------------------------------------------------------- */

/// Membuka tautan di luar aplikasi (VLC / peramban / pemutar lain).
Future<void> rtsCctvBukaLuar(BuildContext context, String url) async {
  try {
    final bool dibuka = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );

    if (!dibuka && context.mounted) {
      rtsKsPesan(context, 'Tautan tidak dapat dibuka.', galat: true);
    }
  } catch (_) {
    if (context.mounted) {
      rtsKsPesan(context, 'Tautan tidak dapat dibuka.', galat: true);
    }
  }
}

/// Tulisan jarak yang seragam (memakai penolong peta).
String rtsCctvJarakTeks(double meter) => rtsPetaJarakTeks(meter);

/* ------------------------------------------------------------------------- */
/* HALAMAN 1 : DAFTAR KAMERA CCTV                                            */
/* ------------------------------------------------------------------------- */

class RtsCctvPage extends StatefulWidget {
  const RtsCctvPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic>? pengguna;

  @override
  State<RtsCctvPage> createState() => _RtsCctvPageState();
}

class _RtsCctvPageState extends State<RtsCctvPage> {
  final TextEditingController _cari = TextEditingController();

  List<RtsCctvKamera> _kamera = <RtsCctvKamera>[];
  bool _memuat = true;
  bool _menyegarkan = false;
  String _galat = '';
  String _sumber = '';
  String _diperbarui = '';
  bool _dariSimpanan = false;

  String _kunci = '';
  String _urut = 'Nama';
  Position? _saya;

  static const List<String> _pilihanUrut = <String>[
    'Nama',
    'Nomor',
    'Terdekat',
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_mulai());
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Future<void> _mulai() async {
    await _bacaSimpanan();
    await _muat();
  }

  /* ------------------------------------------------------------- simpanan */

  Future<void> _bacaSimpanan() async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String teks = sp.getString(rtsCctvKunciSimpan) ?? '';

      if (teks.isEmpty) return;

      final dynamic urai = jsonDecode(teks);

      if (urai is! List) return;

      final List<RtsCctvKamera> daftar = <RtsCctvKamera>[];

      for (final dynamic satu in urai) {
        if (satu is Map) {
          daftar.add(RtsCctvKamera.dari(satu));
        }
      }

      if (!mounted || daftar.isEmpty) return;

      setState(() {
        _kamera = daftar;
        _dariSimpanan = true;
        _diperbarui = sp.getString(rtsCctvKunciWaktu) ?? '';
      });
    } catch (_) {
      // simpanan rusak: tidak masalah, nanti diambil dari server
    }
  }

  Future<void> _tulisSimpanan(List<RtsCctvKamera> daftar) async {
    try {
      final SharedPreferences sp = await SharedPreferences.getInstance();
      final String waktu = rtsPetaTanggalTeks(DateTime.now());

      await sp.setString(
        rtsCctvKunciSimpan,
        jsonEncode(daftar.map((RtsCctvKamera k) => k.toJson()).toList()),
      );
      await sp.setString(rtsCctvKunciWaktu, waktu);
    } catch (_) {
      // penyimpanan penuh: daftar tetap bisa dipakai selama aplikasi terbuka
    }
  }

  /* --------------------------------------------------------- ambil server */

  Future<void> _muat({bool segarkan = false, bool diam = false}) async {
    if (!diam) {
      setState(() {
        _memuat = _kamera.isEmpty;
        _menyegarkan = _kamera.isNotEmpty;
        _galat = '';
      });
    }

    if (widget.baseUrl.isEmpty || widget.token.isEmpty) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _menyegarkan = false;
        _galat = 'Alamat server belum diatur pada menu Pengaturan.';
      });

      return;
    }

    try {
      final Uri uri = Uri.parse(
        '${widget.baseUrl}/cctv.php?aksi=${segarkan ? 'segarkan' : 'daftar'}',
      );

      final http.Response jawab = await http.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 30));

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map) {
        throw const FormatException('Balasan server tidak dapat dibaca.');
      }

      final Map<String, dynamic> peta = urai.cast<String, dynamic>();

      if (peta['success'] != true) {
        // Gembok PRO dikirim server di bagian paling atas balasan
        // (sama seperti api/kasir.php), jadi diperiksa di dua tempat.
        final Map<String, dynamic> data = (peta['data'] is Map)
            ? (peta['data'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};

        final bool perluPro =
            peta['perlu_pro'] == true || data['perlu_pro'] == true;

        final String pesan = '${peta['message'] ?? 'Daftar kamera tidak dapat dibaca.'}';

        if (!mounted) return;

        setState(() {
          _memuat = false;
          _menyegarkan = false;
          _galat = perluPro ? '$pesan\n\nMenu ini khusus AKUN PRO.' : pesan;
        });

        return;
      }

      final Map<String, dynamic> data = (peta['data'] is Map)
          ? (peta['data'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final List<dynamic> butir = (data['kamera'] is List)
          ? (data['kamera'] as List<dynamic>)
          : <dynamic>[];

      final List<RtsCctvKamera> daftar = <RtsCctvKamera>[];

      for (final dynamic satu in butir) {
        if (satu is Map) {
          final RtsCctvKamera kamera = RtsCctvKamera.dari(satu);

          if (kamera.kode.isNotEmpty && kamera.url.isNotEmpty) {
            daftar.add(kamera);
          }
        }
      }

      if (!mounted) return;

      if (daftar.isEmpty) {
        setState(() {
          _memuat = false;
          _menyegarkan = false;
          _galat = 'Server belum memuat daftar kamera. Buka periksa_cctv.php '
              'pada website lalu tekan AMBIL DAFTAR KAMERA.';
        });

        return;
      }

      setState(() {
        _kamera = daftar;
        _memuat = false;
        _menyegarkan = false;
        _galat = '';
        _dariSimpanan = false;
        _sumber = '${data['sumber'] ?? 'ATCS Dishub Kota Medan'}';
        _diperbarui = '${data['diperbarui'] ?? ''}';
      });

      await _tulisSimpanan(daftar);

      if (segarkan && mounted) {
        final String pesanServer = '${peta['message'] ?? ''}';

        rtsKsPesan(
          context,
          pesanServer.isEmpty ? '${daftar.length} kamera diperbarui.' : pesanServer,
        );
      }
    } on TimeoutException {
      _gagalMuat('Server lama tidak menjawab. Periksa sambungan internet.');
    } catch (galat) {
      _gagalMuat('$galat');
    }
  }

  void _gagalMuat(String pesan) {
    if (!mounted) return;

    setState(() {
      _memuat = false;
      _menyegarkan = false;

      if (_kamera.isNotEmpty) {
        _galat = '';
      } else {
        _galat = 'Daftar kamera tidak dapat diambil.\n$pesan';
      }
    });

    if (_kamera.isNotEmpty && mounted) {
      rtsKsPesan(
        context,
        _dariSimpanan
            ? 'Tidak ada internet - daftar tersimpan di HP tetap dipakai.'
            : 'Gagal menyegarkan daftar. Yang tampil adalah daftar sebelumnya.',
        galat: true,
      );
    }
  }

  /* ------------------------------------------------------------- penapis */

  List<RtsCctvKamera> get _tampil {
    final String kunci = _kunci.trim().toLowerCase();

    final List<RtsCctvKamera> daftar = _kamera.where((RtsCctvKamera k) {
      if (kunci.isEmpty) return true;

      return k.nama.toLowerCase().contains(kunci) ||
          k.alias.toLowerCase().contains(kunci) ||
          k.kode.toLowerCase().contains(kunci) ||
          '${k.nomor}'.contains(kunci);
    }).toList();

    if (_urut == 'Terdekat') {
      final Position? saya = _saya;

      if (saya == null) {
        daftar.sort((RtsCctvKamera a, RtsCctvKamera b) => a.nomor.compareTo(b.nomor));

        return daftar;
      }

      daftar.sort((RtsCctvKamera a, RtsCctvKamera b) {
        final double ja = a.adaTitik
            ? rtsPetaJarakMeter(saya.latitude, saya.longitude, a.lat, a.lon)
            : double.infinity;
        final double jb = b.adaTitik
            ? rtsPetaJarakMeter(saya.latitude, saya.longitude, b.lat, b.lon)
            : double.infinity;

        return ja.compareTo(jb);
      });

      return daftar;
    }

    if (_urut == 'Nomor') {
      daftar.sort((RtsCctvKamera a, RtsCctvKamera b) => a.nomor.compareTo(b.nomor));

      return daftar;
    }

    daftar.sort(
      (RtsCctvKamera a, RtsCctvKamera b) =>
          a.nama.toLowerCase().compareTo(b.nama.toLowerCase()),
    );

    return daftar;
  }

  double? _jarakKe(RtsCctvKamera kamera) {
    final Position? saya = _saya;

    if (saya == null || !kamera.adaTitik) return null;

    return rtsPetaJarakMeter(saya.latitude, saya.longitude, kamera.lat, kamera.lon);
  }

  Future<void> _pakaiLokasi() async {
    final Position? titik = await rtsPetaAmbilLokasi();

    if (!mounted) return;

    if (titik == null) {
      rtsKsPesan(
        context,
        'Lokasi HP belum dapat dibaca. Nyalakan GPS lalu izinkan aplikasi '
        'memakai lokasi.',
        galat: true,
      );

      return;
    }

    setState(() {
      _saya = titik;
      _urut = 'Terdekat';
    });

    rtsKsPesan(context, 'Daftar diurutkan dari kamera terdekat.');
  }

  /* ------------------------------------------------------------- tampilan */

  @override
  Widget build(BuildContext context) {
    final List<RtsCctvKamera> daftar = _tampil;

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        title: const Text('CCTV Online'),
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: 'Keterangan',
            onPressed: _bukaKeterangan,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          IconButton(
            tooltip: 'Segarkan dari server',
            onPressed: _menyegarkan ? null : () => _muat(segarkan: true),
            icon: _menyegarkan
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.cloud_download_outlined),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _kepala(daftar.length),
          Expanded(child: _isi(daftar)),
        ],
      ),
    );
  }

  Widget _kepala(int jumlahTampil) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: <Widget>[
          TextField(
            controller: _cari,
            textInputAction: TextInputAction.search,
            onChanged: (String nilai) => setState(() => _kunci = nilai),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Cari kamera (nama, simpang, atau nomor)',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _kunci.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _cari.clear();
                        setState(() => _kunci = '');
                      },
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      for (final String pilih in _pilihanUrut) ...<Widget>[
                        _tombolUrut(pilih),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ),
              if (_saya == null)
                TextButton.icon(
                  onPressed: _pakaiLokasi,
                  icon: const Icon(Icons.my_location_rounded, size: 16),
                  label: const Text('Pakai lokasi'),
                )
              else
                const Icon(Icons.my_location_rounded, size: 16, color: rtsKsHijau),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$jumlahTampil dari ${_kamera.length} kamera'
                  '${_dariSimpanan ? ' - tersimpan di HP' : ''}'
                  '${_diperbarui.isEmpty ? '' : ' - diperbarui $_diperbarui'}',
                  style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                ),
              ),
              const Text(
                'Sumber: Dishub Kota Medan',
                style: TextStyle(fontSize: 11, color: rtsKsTeks2),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tombolUrut(String pilihan) {
    final bool aktif = _urut == pilihan;

    return GestureDetector(
      onTap: () {
        if (pilihan == 'Terdekat' && _saya == null) {
          unawaited(_pakaiLokasi());
          return;
        }

        setState(() => _urut = pilihan);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: aktif ? rtsKsMaroon : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: aktif ? rtsKsMaroon : rtsKsGaris),
        ),
        child: Text(
          pilihan,
          style: TextStyle(
            fontSize: 12,
            fontWeight: aktif ? FontWeight.w700 : FontWeight.w500,
            color: aktif ? Colors.white : rtsKsTeks,
          ),
        ),
      ),
    );
  }

  Widget _isi(List<RtsCctvKamera> daftar) {
    if (_memuat) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Mengambil daftar kamera...', style: TextStyle(color: rtsKsTeks2)),
          ],
        ),
      );
    }

    if (_galat.isNotEmpty && _kamera.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.videocam_off_outlined, size: 46, color: rtsKsTeks2),
              const SizedBox(height: 12),
              Text(
                _galat,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsKsTeks, height: 1.5),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                onPressed: () => _muat(),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('COBA LAGI'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => rtsCctvBukaLuar(context, rtsCctvHalaman),
                child: const Text('Buka halaman resmi ATCS Dishub Medan'),
              ),
            ],
          ),
        ),
      );
    }

    if (daftar.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada kamera yang cocok dengan pencarian.',
          style: TextStyle(color: rtsKsTeks2),
        ),
      );
    }

    return RefreshIndicator(
      color: rtsKsMaroon,
      onRefresh: () => _muat(segarkan: true, diam: true),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: daftar.length,
        separatorBuilder: (_, __) => const SizedBox(height: 9),
        itemBuilder: (BuildContext context, int i) => _kartu(daftar[i], i),
      ),
    );
  }

  Widget _kartu(RtsCctvKamera kamera, int urutan) {
    final double? jarak = _jarakKe(kamera);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _putar(kamera),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: rtsKsGaris),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rtsKsMaroon.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    const Icon(Icons.videocam_rounded, size: 15, color: rtsKsMaroon),
                    Text(
                      kamera.nomor > 0 ? '${kamera.nomor}' : '${urutan + 1}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rtsKsMaroon,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      kamera.nama,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: rtsKsTeks,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      kamera.keterangan,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        Text(
                          kamera.kode,
                          style: const TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                        ),
                        if (jarak != null) ...<Widget>[
                          const Text('  -  ', style: TextStyle(fontSize: 10.5, color: rtsKsTeks2)),
                          Icon(
                            Icons.place_outlined,
                            size: 12,
                            color: jarak < 3000 ? rtsKsHijau : rtsKsTeks2,
                          ),
                          Text(
                            ' ${rtsCctvJarakTeks(jarak)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: jarak < 3000 ? rtsKsHijau : rtsKsTeks2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                children: <Widget>[
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: rtsKsMaroon,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      minimumSize: const Size(0, 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _putar(kamera),
                    child: const Text('PUTAR', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(height: 5),
                  GestureDetector(
                    onTap: () => _menuKamera(kamera),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Icon(Icons.more_horiz_rounded, size: 20, color: rtsKsTeks2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _menuKamera(RtsCctvKamera kamera) async {
    final String? pilih = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                kamera.nama,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_circle_outline_rounded),
              title: const Text('Putar di aplikasi'),
              onTap: () => Navigator.of(sheet).pop('putar'),
            ),
            ListTile(
              leading: const Icon(Icons.map_outlined),
              title: const Text('Lihat lokasi kamera (peta)'),
              onTap: () => Navigator.of(sheet).pop('peta'),
            ),
            ListTile(
              leading: const Icon(Icons.copy_rounded),
              title: const Text('Salin tautan video'),
              onTap: () => Navigator.of(sheet).pop('salin'),
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Buka di pemutar lain (VLC / peramban)'),
              onTap: () => Navigator.of(sheet).pop('luar'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || pilih == null) return;

    if (pilih == 'putar') {
      await _putar(kamera);
    } else if (pilih == 'peta') {
      await _peta(kamera);
    } else if (pilih == 'salin') {
      await rtsPetaSalinTeks(kamera.url);
    } else if (pilih == 'luar') {
      await rtsCctvBukaLuar(context, kamera.url);
    }
  }

  Future<void> _putar(RtsCctvKamera kamera) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RtsCctvPutarPage(
          kamera: kamera,
          saya: _saya,
        ),
      ),
    );
  }

  Future<void> _peta(RtsCctvKamera kamera) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RtsCctvPetaPage(kamera: kamera, saya: _saya),
      ),
    );
  }

  Future<void> _bukaKeterangan() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Tentang CCTV Online',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              const Text(
                'Kamera lalu lintas Kota Medan milik Dinas Perhubungan Kota '
                'Medan (ATCS / ITS Kota Medan). Siarannya terbuka untuk umum, '
                'sama seperti membukanya di peramban.',
                style: TextStyle(fontSize: 13, height: 1.55, color: rtsKsTeks),
              ),
              const SizedBox(height: 10),
              const Text(
                'Cara memakai:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Text(
                '1. Ketik nama jalan pada kotak pencarian, atau\n'
                '2. Tekan "Pakai lokasi" supaya kamera terdekat muncul di atas, lalu\n'
                '3. Tekan PUTAR. Di dalam pemutar ada tombol layar penuh, peta '
                'lokasi kamera, dan salin tautan.',
                style: TextStyle(fontSize: 12.5, height: 1.6, color: rtsKsTeks2),
              ),
              const SizedBox(height: 10),
              Text(
                'Sumber daftar: ${_sumber.isEmpty ? 'ATCS Dishub Kota Medan' : _sumber}'
                '\nJumlah kamera: ${_kamera.length}'
                '${_diperbarui.isEmpty ? '' : '\nDiperbarui: $_diperbarui'}',
                style: const TextStyle(fontSize: 12, color: rtsKsTeks2, height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => rtsCctvBukaLuar(context, rtsCctvHalaman),
                      icon: const Icon(Icons.public_rounded, size: 17),
                      label: const Text('Halaman resmi'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                      onPressed: () {
                        Navigator.of(sheet).pop();
                        unawaited(_muat(segarkan: true));
                      },
                      icon: const Icon(Icons.cloud_download_outlined, size: 17),
                      label: const Text('Segarkan'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 2 : PEMUTAR VIDEO                                                 */
/* ------------------------------------------------------------------------- */

class RtsCctvPutarPage extends StatefulWidget {
  const RtsCctvPutarPage({
    super.key,
    required this.kamera,
    this.saya,
  });

  final RtsCctvKamera kamera;
  final Position? saya;

  @override
  State<RtsCctvPutarPage> createState() => _RtsCctvPutarPageState();
}

class _RtsCctvPutarPageState extends State<RtsCctvPutarPage> {
  VideoPlayerController? _kontrol;

  bool _memuat = true;
  bool _siap = false;
  bool _bisu = false;
  bool _penuh = false;
  bool _diam = false;
  String _galat = '';
  String _galatRinci = '';

  @override
  void initState() {
    super.initState();
    unawaited(_buka());
  }

  @override
  void dispose() {
    unawaited(_kembalikanLayar());
    final VideoPlayerController? kontrol = _kontrol;

    _kontrol = null;

    if (kontrol != null) {
      kontrol.removeListener(_dengar);
      unawaited(kontrol.dispose());
    }

    super.dispose();
  }

  void _dengar() {
    if (!mounted) return;

    final VideoPlayerController? kontrol = _kontrol;

    if (kontrol == null) return;

    if (kontrol.value.hasError && _galat.isEmpty) {
      setState(() {
        _galat = 'Kamera sedang tidak tersedia.';
        _galatRinci = '${kontrol.value.errorDescription ?? ''}';
        _siap = false;
        _memuat = false;
      });

      return;
    }

    if (!_diam && kontrol.value.isInitialized) {
      setState(() {});
    }
  }

  Future<void> _lepas() async {
    final VideoPlayerController? kontrol = _kontrol;

    _kontrol = null;

    if (kontrol != null) {
      kontrol.removeListener(_dengar);

      try {
        await kontrol.pause();
        await kontrol.dispose();
      } catch (_) {
        // sudah dilepas
      }
    }
  }

  Future<void> _buka() async {
    setState(() {
      _memuat = true;
      _galat = '';
      _galatRinci = '';
      _siap = false;
    });

    await _lepas();

    final VideoPlayerController kontrol = VideoPlayerController.networkUrl(
      Uri.parse(widget.kamera.url),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );

    _kontrol = kontrol;

    try {
      await kontrol.initialize().timeout(const Duration(seconds: 30));

      await kontrol.setVolume(_bisu ? 0 : 1);
      await kontrol.play();

      if (!mounted) return;

      kontrol.addListener(_dengar);

      setState(() {
        _memuat = false;
        _siap = true;
      });
    } on TimeoutException {
      _tidakTersedia(
        'Kamera tidak menjawab dalam 30 detik. Jaringan lambat atau kamera '
        'sedang dimatikan.',
      );
    } catch (galat) {
      _tidakTersedia('$galat');
    }
  }

  void _tidakTersedia(String rinci) {
    if (!mounted) return;

    setState(() {
      _memuat = false;
      _siap = false;
      _galat = 'Kamera sedang tidak tersedia.';
      _galatRinci = rinci;
    });
  }

  Future<void> _putarHenti() async {
    final VideoPlayerController? kontrol = _kontrol;

    if (kontrol == null || !kontrol.value.isInitialized) return;

    if (kontrol.value.isPlaying) {
      await kontrol.pause();
    } else {
      await kontrol.play();
    }

    if (mounted) setState(() {});
  }

  Future<void> _ubahBisu() async {
    _bisu = !_bisu;

    try {
      await _kontrol?.setVolume(_bisu ? 0 : 1);
    } catch (_) {
      // tidak apa-apa
    }

    if (mounted) setState(() {});
  }

  Future<void> _ubahPenuh() async {
    _penuh = !_penuh;

    if (_penuh) {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await _kembalikanLayar();
    }

    if (mounted) setState(() {});
  }

  Future<void> _kembalikanLayar() async {
    try {
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {
      // tidak apa-apa
    }
  }

  Future<void> _bukaPeta() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RtsCctvPetaPage(kamera: widget.kamera, saya: widget.saya),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _penuh
          ? null
          : AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.kamera.nama,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14.5),
                  ),
                  Text(
                    widget.kamera.keterangan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
      body: SafeArea(
        top: _penuh,
        bottom: !_penuh,
        child: Column(
          children: <Widget>[
            Expanded(child: _layar()),
            if (!_penuh) _kaki(),
          ],
        ),
      ),
    );
  }

  Widget _layar() {
    if (_memuat) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 14),
            Text(
              'Menyambung ke kamera...',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    if (_galat.isNotEmpty || !_siap) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.videocam_off_outlined, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              Text(
                _galat.isEmpty ? 'Kamera sedang tidak tersedia.' : _galat,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Kamera biasanya dimatikan sementara oleh Dishub (pemeliharaan) '
                'atau jaringan sedang lambat. Coba lagi beberapa saat lagi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.55),
              ),
              if (_galatRinci.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _galatRinci,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                    onPressed: _buka,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('COBA LAGI'),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                    onPressed: () => rtsCctvBukaLuar(context, widget.kamera.url),
                    icon: const Icon(Icons.open_in_new_rounded, size: 17),
                    label: const Text('Pemutar lain'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final VideoPlayerController kontrol = _kontrol!;
    final double rasio = kontrol.value.aspectRatio > 0.3 &&
            kontrol.value.aspectRatio < 3.2
        ? kontrol.value.aspectRatio
        : 16 / 9;

    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Center(
          child: AspectRatio(
            aspectRatio: rasio,
            child: VideoPlayer(kontrol),
          ),
        ),
        Positioned(
          left: 10,
          top: 10,
          child: Wrap(
            spacing: 6,
            children: <Widget>[
              _lencana(
                kontrol.value.isPlaying ? 'LIVE' : 'DIHENTIKAN',
                kontrol.value.isPlaying ? rtsKsMerah : Colors.black54,
              ),
              if (kontrol.value.isBuffering)
                _lencana('MEMUAT...', Colors.black54),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _atur(warna: Colors.black.withValues(alpha: 0.55)),
        ),
        if (!kontrol.value.isPlaying)
          Center(
            child: GestureDetector(
              onTap: _putarHenti,
              child: Container(
                width: 74,
                height: 74,
                decoration: const BoxDecoration(
                  color: Color(0xcc000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 46, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _lencana(String teks, Color warna) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: warna,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        teks,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _atur({Color warna = Colors.white}) {
    final VideoPlayerController? kontrol = _kontrol;
    final bool main = kontrol?.value.isPlaying ?? false;

    return Container(
      color: warna,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: main ? 'Hentikan' : 'Putar',
            onPressed: _putarHenti,
            icon: Icon(
              main ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            tooltip: _bisu ? 'Nyalakan suara' : 'Bisukan',
            onPressed: _ubahBisu,
            icon: Icon(
              _bisu ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _buka,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Peta lokasi kamera',
            onPressed: _bukaPeta,
            icon: const Icon(Icons.map_outlined, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Salin tautan',
            onPressed: () => rtsPetaSalinTeks(widget.kamera.url),
            icon: const Icon(Icons.copy_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: _penuh ? 'Keluar layar penuh' : 'Layar penuh',
            onPressed: _ubahPenuh,
            icon: Icon(
              _penuh
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kaki() {
    return Container(
      color: const Color(0xff141110),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.videocam_rounded, size: 16, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Kamera ${widget.kamera.nomor > 0 ? widget.kamera.nomor : ''} - ${widget.kamera.kode}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  onPressed: _bukaPeta,
                  icon: const Icon(Icons.place_outlined, size: 17),
                  label: const Text('Lokasi'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white30),
                  ),
                  onPressed: () => rtsCctvBukaLuar(context, widget.kamera.url),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: const Text('VLC'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Siaran milik Dinas Perhubungan Kota Medan (ATCS / ITS Kota Medan) '
            'dan terbuka untuk umum.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 3 : PETA LOKASI KAMERA                                            */
/* ------------------------------------------------------------------------- */

class RtsCctvPetaPage extends StatefulWidget {
  const RtsCctvPetaPage({
    super.key,
    required this.kamera,
    this.saya,
  });

  final RtsCctvKamera kamera;
  final Position? saya;

  @override
  State<RtsCctvPetaPage> createState() => _RtsCctvPetaPageState();
}

class _RtsCctvPetaPageState extends State<RtsCctvPetaPage> {
  final MapController _kontrol = MapController();

  int _sumber = 0;
  Position? _saya;
  double? _jarak;

  @override
  void initState() {
    super.initState();
    _saya = widget.saya;
    _hitungJarak();
  }

  void _hitungJarak() {
    final Position? saya = _saya;

    if (saya == null || !widget.kamera.adaTitik) return;

    _jarak = rtsPetaJarakMeter(
      saya.latitude,
      saya.longitude,
      widget.kamera.lat,
      widget.kamera.lon,
    );
  }

  Future<void> _ambilLokasi() async {
    final Position? titik = await rtsPetaAmbilLokasi();

    if (!mounted || titik == null) return;

    setState(() {
      _saya = titik;
      _hitungJarak();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool adaTitik = widget.kamera.adaTitik;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lokasi Kamera'),
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            tooltip: 'Ganti tampilan peta',
            onPressed: () => setState(
              () => _sumber = (_sumber + 1) % rtsPetaSumber.length,
            ),
            icon: const Icon(Icons.layers_outlined),
          ),
        ],
      ),
      body: !adaTitik
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Text(
                  'Titik koordinat kamera ini belum ada pada daftar. '
                  'Jalankan periksa_cctv.php?paksa=1&ambil=1 pada website '
                  'supaya koordinatnya ikut terbarui.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: rtsKsTeks, height: 1.55),
                ),
              ),
            )
          : Stack(
              children: <Widget>[
                FlutterMap(
                  mapController: _kontrol,
                  options: MapOptions(
                    initialCenter: widget.kamera.titik,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                  ),
                  children: <Widget>[
                    TileLayer(
                      urlTemplate: rtsPetaSumber[_sumber].url,
                      userAgentPackageName: 'com.bene.rts_panel_app',
                      maxNativeZoom: rtsPetaSumber[_sumber].maksZoom,
                    ),
                    MarkerLayer(
                      markers: <Marker>[
                        Marker(
                          point: widget.kamera.titik,
                          width: 46,
                          height: 46,
                          child: const Icon(
                            Icons.videocam_rounded,
                            size: 34,
                            color: rtsKsMaroon,
                          ),
                        ),
                        if (_saya != null)
                          Marker(
                            point: LatLng(_saya!.latitude, _saya!.longitude),
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.person_pin_circle_rounded,
                              size: 30,
                              color: rtsPetaSaya,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.all(11),
                    decoration: rtsPetaKotak(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.kamera.nama,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: rtsKsTeks,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.kamera.keterangan,
                          style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: <Widget>[
                            Text(
                              '${widget.kamera.lat.toStringAsFixed(6)}, '
                              '${widget.kamera.lon.toStringAsFixed(6)}',
                              style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                            ),
                            const Spacer(),
                            if (_jarak != null)
                              Text(
                                rtsCctvJarakTeks(_jarak!),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: rtsKsHijau,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 64,
                  child: rtsPetaAtribusi(rtsPetaSumber[_sumber].nama),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                          onPressed: () => rtsPetaNavigasi(
                            context,
                            widget.kamera.lat,
                            widget.kamera.lon,
                            widget.kamera.nama,
                          ),
                          icon: const Icon(Icons.directions_rounded, size: 18),
                          label: const Text('BUKA DI GOOGLE MAPS'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: _saya == null ? 'Pakai lokasi saya' : 'Perbarui lokasi',
                        onPressed: _ambilLokasi,
                        icon: const Icon(Icons.my_location_rounded),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        tooltip: 'Salin koordinat',
                        onPressed: () => rtsPetaSalinTeks(
                          '${widget.kamera.lat},${widget.kamera.lon}',
                        ),
                        icon: const Icon(Icons.copy_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
