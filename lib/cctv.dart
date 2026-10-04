// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : CCTV ONLINE (KAMERA LALU LINTAS MEDAN)
//  Berkas : lib/cctv.dart
//  Versi  : 2   (4 Oktober 2026)
//
//  ISI BERKAS INI (dipisah dari main.dart supaya pembaruan berikutnya cukup
//  mengganti satu berkas):
//
//     1. RtsCctvPage      - DAFTAR KAMERA CCTV KOTA MEDAN
//            daftar dibaca dari server (api/cctv.php), dapat DICARI, dapat
//            diurutkan menurut NAMA / NOMOR / JARAK dari posisi HP, dan
//            disimpan di dalam HP supaya tetap terbaca walau tanpa internet.
//            TIGA TAMPILAN (seperti halaman resmi ATCS Dishub, yang memakai
//            tab "Peta" dan "Grid Kamera"), jadi Bapak dapat memilih:
//               DAFTAR  - daftar memanjang, satu kamera satu baris;
//               GRID    - kotak-kotak berisi GAMBAR kamera + tombol PUTAR;
//               PETA    - SEMUA kamera sebagai titik pada satu peta.
//            Di tampilan GRID dan PETA ada lencana SIAP / TIDAK TERSEDIA
//            (sama seperti lencana READY / MAINTENANCE pada situs Dishub),
//            yang diperiksa lewat tombol PERIKSA.
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

/// Kunci penyimpanan hasil pemeriksaan "kamera siap / tidak" di dalam HP.
const String rtsCctvKunciSiap = 'rts_cctv_siap';
const String rtsCctvKunciSiapWaktu = 'rts_cctv_siap_waktu';

/// Alamat gambar (poster) kamera.
///
/// Halaman resmi ATCS menampilkan gambar kamera dengan pola:
///     https://atcsdishub.medan.go.id/poster/<NAMA BERKAS>
/// Jadi nilai poster yang belum berupa alamat penuh ditambahi awalan itu.
/// Gambar hanya pelengkap: bila gagal dimuat, kartu memakai gambar pengganti.
String rtsCctvPosterUrl(String poster) {
  final String nilai = poster.trim();

  if (nilai.isEmpty) return '';
  if (nilai.toLowerCase().startsWith('http')) return nilai;

  final String nama = nilai
      .replaceFirst(RegExp(r'^poster/', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^/+'), '');

  return 'https://atcsdishub.medan.go.id/poster/$nama';
}

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
    this.siap,
  });

  final String kode;
  final int nomor;
  final String nama;
  final String alias;
  final String url;
  final String poster;
  final double lat;
  final double lon;

  /// Hasil pemeriksaan terakhir: true = siap diputar, false = tidak tersedia,
  /// null = belum diperiksa. Dikirim server (api/cctv.php?aksi=hidup).
  final bool? siap;

  /// Alamat gambar kamera (kosong bila belum ada).
  String get posterUrl => rtsCctvPosterUrl(poster);

  /// Titik peta kamera tersedia dan masuk akal.
  bool get adaTitik => rtsPetaTitikSah(lat, lon);

  LatLng get titik => LatLng(lat, lon);

  /// Tulisan untuk daftar: alias dipakai bila ada, kalau tidak nama.
  String get keterangan => alias.trim().isEmpty ? nama : alias;

  /// Judul pada tampilan GRID (sama dengan halaman resmi ATCS: nama alias).
  String get judul => keterangan;

  /// Baris lokasi pada tampilan GRID (kosong bila tidak ada nama lokasi).
  String get lokasi => alias.trim().isEmpty ? '' : nama;

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
      siap: _hidup(isi['hidup']),
    );
  }

  /// Menyalin kamera dengan hasil pemeriksaan (siap/tidak) yang baru.
  RtsCctvKamera salin({bool? siap}) => RtsCctvKamera(
        kode: kode,
        nomor: nomor,
        nama: nama,
        alias: alias,
        url: url,
        poster: poster,
        lat: lat,
        lon: lon,
        siap: siap ?? this.siap,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'kode': kode,
        'nomor': nomor,
        'nama': nama,
        'alias': alias,
        'url': url,
        'poster': poster,
        'lat': lat,
        'lon': lon,
        'hidup': siap == null ? null : (siap! ? 1 : 0),
      };

  static double _angka(Object? nilai) {
    if (nilai is num) return nilai.toDouble();

    return double.tryParse('${nilai ?? ''}') ?? 0;
  }

  /// Membaca nilai hidup (1 = siap, 0 = tidak tersedia, kosong = belum).
  static bool? _hidup(Object? nilai) {
    if (nilai == null || nilai == '') return null;
    if (nilai == true || nilai == 1) return true;
    if (nilai == false || nilai == 0) return false;

    final String teks = '$nilai';
    if (teks == '1' || teks.toLowerCase() == 'true') return true;
    if (teks == '0' || teks.toLowerCase() == 'false') return false;

    return null;
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

  /// Tampilan yang sedang dipakai: Daftar, Grid Kamera, atau Peta.
  String _tampilan = 'Daftar';

  final MapController _kontrolPeta = MapController();

  /// Memeriksa seluruh kamera (tombol PERIKSA seperti tombol READY di situs
  /// resmi ATCS). Hasilnya dititipkan server pada setiap kamera.
  bool _memeriksa = false;

  /// Waktu pemeriksaan terakhir (dari server), ditampilkan di atas tampilan.
  String _diperiksaSiap = '';

  /// Server pernah mengirim penanda siap/tidak (atau gambar sudah ada).
  bool _adaSiapServer = false;

  /// Menampilkan gambar kamera pada tampilan Grid (dapat dimatikan untuk
  /// menghemat kuota data - lencana SIAP dan tombol Play tetap bekerja).
  bool _pakaiGambar = true;

  static const List<String> _pilihanTampilan = <String>[
    'Daftar',
    'Grid',
    'Peta',
  ];

  static const List<String> _pilihanUrut = <String>[
    'Nama',
    'Nomor',
    'Terdekat',
  ];

  /// Berapa kamera yang sudah diperiksa: siap diputar / tidak tersedia.
  int _hitungSiap(bool nilai) {
    int jumlah = 0;

    for (final RtsCctvKamera kamera in _kamera) {
      if (kamera.siap == nilai) jumlah++;
    }

    return jumlah;
  }

  bool get _adaSiap => _kamera.any((RtsCctvKamera k) => k.siap != null);

  @override
  void initState() {
    super.initState();
    unawaited(_mulai());
  }

  @override
  void dispose() {
    _cari.dispose();
    _kontrolPeta.dispose();
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

      // Hasil pemeriksaan siap/tidak juga disimpan supaya lencananya tidak
      // hilang setiap aplikasi dibuka.
      final String siapTeks = sp.getString(rtsCctvKunciSiap) ?? '';
      final String siapWaktu = sp.getString(rtsCctvKunciSiapWaktu) ?? '';

      if (siapTeks.isNotEmpty) {
        try {
          final dynamic uraiSiap = jsonDecode(siapTeks);

          if (uraiSiap is Map) {
            for (int i = 0; i < daftar.length; i++) {
              final dynamic nilai = uraiSiap[daftar[i].kode];

              if (nilai == 1 || nilai == true || '$nilai' == '1') {
                daftar[i] = daftar[i].salin(siap: true);
              } else if (nilai == 0 || nilai == false || '$nilai' == '0') {
                daftar[i] = daftar[i].salin(siap: false);
              }
            }
          }
        } catch (_) {
          // simpanan lama: tidak masalah, nanti diperiksa lagi ke server
        }
      }

      setState(() {
        _kamera = daftar;
        _dariSimpanan = true;
        _diperbarui = sp.getString(rtsCctvKunciWaktu) ?? '';
        _diperiksaSiap = siapWaktu;
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

      await _tulisSiap(daftar, sp);
    } catch (_) {
      // penyimpanan penuh: daftar tetap bisa dipakai selama aplikasi terbuka
    }
  }

  /// Menyimpan hasil pemeriksaan siap/tidak ke dalam HP.
  Future<void> _tulisSiap(
    List<RtsCctvKamera> daftar, [
    SharedPreferences? sp,
  ]) async {
    try {
      final Map<String, int> peta = <String, int>{};

      for (final RtsCctvKamera kamera in daftar) {
        if (kamera.siap == null) continue;

        peta[kamera.kode] = kamera.siap! ? 1 : 0;
      }

      if (peta.isEmpty) return;

      final SharedPreferences simpan =
          sp ?? await SharedPreferences.getInstance();

      await simpan.setString(rtsCctvKunciSiap, jsonEncode(peta));

      if (_diperiksaSiap.isNotEmpty) {
        await simpan.setString(rtsCctvKunciSiapWaktu, _diperiksaSiap);
      }
    } catch (_) {
      // penyimpanan penuh: lencana tetap benar selama aplikasi terbuka
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

      // 45 detik: server sesekali perlu mengambil daftar/gambar terbaru dari
      // situs ATCS lebih dahulu (dilakukan paling banyak sekali setiap 6 jam).
      final http.Response jawab = await http.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 45));

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
        int jumlahSiap = 0;

        for (final RtsCctvKamera kamera in daftar) {
          if (kamera.siap == true) jumlahSiap++;
        }

        _kamera = daftar;
        _memuat = false;
        _menyegarkan = false;
        _galat = '';
        _dariSimpanan = false;
        _sumber = '${data['sumber'] ?? 'ATCS Dishub Kota Medan'}';
        _diperbarui = '${data['diperbarui'] ?? ''}';
        _diperiksaSiap = '${data['hidup_diperiksa'] ?? ''}';
        _adaSiapServer = data.containsKey('hidup_diperiksa') ||
            data.containsKey('ada_poster') ||
            jumlahSiap > 0;
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

  /// Panggilan kecil ke api/cctv.php (dipakai tombol PERIKSA).
  Future<Map<String, dynamic>?> _panggil(
    String aksi, {
    Duration waktu = const Duration(seconds: 60),
  }) async {
    if (widget.baseUrl.isEmpty || widget.token.isEmpty) return null;

    try {
      final http.Response jawab = await http.get(
        Uri.parse('${widget.baseUrl}/cctv.php?aksi=$aksi'),
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(waktu);

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map) return null;

      return urai.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  /// Tombol PERIKSA: meminta server memeriksa seluruh kamera, lalu memakai
  /// hasilnya pada kartu-kartu (lencana SIAP / TIDAK TERSEDIA).
  Future<void> _periksaKamera() async {
    if (_memeriksa) return;

    setState(() => _memeriksa = true);

    final Map<String, dynamic>? balasan = await _panggil(
      'hidup',
      waktu: const Duration(seconds: 90),
    );

    if (!mounted) return;

    if (balasan == null || balasan['success'] != true) {
      setState(() => _memeriksa = false);

      rtsKsPesan(
        context,
        balasan == null
            ? 'Pemeriksaan tidak dapat dijalankan. Periksa sambungan internet.'
            : '${balasan['message'] ?? 'Pemeriksaan gagal.'}',
        galat: true,
      );

      return;
    }

    final Map<String, dynamic> data = (balasan['data'] is Map)
        ? (balasan['data'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final List<dynamic> butir = (data['kamera'] is List)
        ? (data['kamera'] as List<dynamic>)
        : <dynamic>[];

    final Map<String, int> peta = <String, int>{};

    for (final dynamic satu in butir) {
      if (satu is Map) {
        peta['${satu['kode']}'] = satu['hidup'] == true ? 1 : 0;
      }
    }

    final List<RtsCctvKamera> daftar = <RtsCctvKamera>[];

    for (final RtsCctvKamera kamera in _kamera) {
      final int? nilai = peta[kamera.kode];

      daftar.add(
        nilai == null ? kamera : kamera.salin(siap: nilai == 1),
      );
    }

    setState(() {
      _kamera = daftar;
      _memeriksa = false;
      _diperiksaSiap = '${data['diperiksa'] ?? ''}';
      _adaSiapServer = true;
    });

    await _tulisSiap(daftar);

    if (mounted) {
      rtsKsPesan(context, '${balasan['message'] ?? 'Pemeriksaan selesai.'}');
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
          if (_adaSiap)
            IconButton(
              tooltip: 'Periksa kamera siap / tidak',
              onPressed: _memeriksa ? null : _periksaKamera,
              icon: _memeriksa
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering_rounded),
            ),
          IconButton(
            tooltip: 'Segarkan daftar dari server',
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
    // Keterangan dihitung lebih dahulu - menghindari tanda kutip bersarang
    // (lebih mudah dibaca dan lebih aman diperiksa skrip pemeriksa kurung).
    String keterangan;

    if (_tampilan == 'Peta') {
      keterangan = '${_kamera.length} kamera pada peta';

      if (_adaSiap) {
        keterangan = '$keterangan - SIAP ${_hitungSiap(true)}';
        keterangan = '$keterangan - TIDAK TERSEDIA ${_hitungSiap(false)}';
      }

      if (_diperiksaSiap.isNotEmpty) {
        keterangan = '$keterangan - diperiksa $_diperiksaSiap';
      }
    } else {
      keterangan = '$jumlahTampil dari ${_kamera.length} kamera';

      if (_dariSimpanan) {
        keterangan = '$keterangan - tersimpan di HP';
      }

      if (_diperbarui.isNotEmpty) {
        keterangan = '$keterangan - diperbarui $_diperbarui';
      }
    }

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

          // PILIHAN TAMPILAN - sama seperti halaman resmi ATCS Dishub yang
          // memakai "Peta" dan "Grid Kamera". Di sini ditambah "Daftar".
          Row(
            children: <Widget>[
              for (final String pilih in _pilihanTampilan) ...<Widget>[
                Expanded(child: _tombolTampilan(pilih)),
                if (pilih != _pilihanTampilan.last) const SizedBox(width: 7),
              ],
            ],
          ),

          const SizedBox(height: 9),

          // PENYARING - hanya untuk tampilan Daftar dan Grid (peta perlu
          // seluruh kamera supaya titiknya lengkap).
          if (_tampilan != 'Peta') ...<Widget>[
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
                        if (_tampilan == 'Grid') _tombolGambar(),
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
          ],

          // BARIS KETERANGAN + tombol PERIKSA.
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  keterangan,
                  style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                ),
              ),
              if (_adaSiapServer)
                GestureDetector(
                  onTap: _memeriksa ? null : _periksaKamera,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: rtsKsMaroon,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        if (_memeriksa)
                          const SizedBox(
                            width: 11,
                            height: 11,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        else
                          const Icon(
                            Icons.wifi_tethering_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        const SizedBox(width: 5),
                        Text(
                          _memeriksa ? 'MEMERIKSA...' : 'PERIKSA',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
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

  /// Tombol pilihan tampilan (Daftar / Grid / Peta).
  Widget _tombolTampilan(String pilihan) {
    final bool aktif = _tampilan == pilihan;
    final IconData ikon = pilihan == 'Grid'
        ? Icons.grid_view_rounded
        : pilihan == 'Peta'
            ? Icons.map_outlined
            : Icons.view_list_rounded;

    return GestureDetector(
      onTap: () {
        setState(() => _tampilan = pilihan);

        if (pilihan == 'Peta') {
          // Peta digambar dahulu (satu gambar), baru diatur supaya seluruh
          // kamera masuk layar. MapController TIDAK dibuang saat pindah tab -
          // flutter_map hanya membuang controller yang dibuatnya sendiri.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _aturKameraPeta();
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: aktif ? rtsKsMaroon : Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: aktif ? rtsKsMaroon : rtsKsGaris),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(ikon, size: 15, color: aktif ? Colors.white : rtsKsTeks2),
            const SizedBox(width: 6),
            Text(
              pilihan == 'Grid' ? 'Grid Kamera' : pilihan,
              style: TextStyle(
                fontSize: 12,
                fontWeight: aktif ? FontWeight.w800 : FontWeight.w600,
                color: aktif ? Colors.white : rtsKsTeks,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tombol kecil: menampilkan / menyembunyikan gambar kamera (hemat kuota).
  Widget _tombolGambar() {
    return GestureDetector(
      onTap: () => setState(() => _pakaiGambar = !_pakaiGambar),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: _pakaiGambar ? Colors.white : rtsKsKuning.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _pakaiGambar ? rtsKsGaris : rtsKsKuning),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              _pakaiGambar ? Icons.image_rounded : Icons.data_saver_on_rounded,
              size: 14,
              color: _pakaiGambar ? rtsKsTeks2 : rtsKsTeks,
            ),
            const SizedBox(width: 5),
            Text(
              _pakaiGambar ? 'Gambar: TAMPIL' : 'HEMAT KUOTA',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: rtsKsTeks,
              ),
            ),
          ],
        ),
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

    if (_tampilan == 'Peta') {
      return _petaTampilan();
    }

    if (daftar.isEmpty) {
      return const Center(
        child: Text(
          'Tidak ada kamera yang cocok dengan pencarian.',
          style: TextStyle(color: rtsKsTeks2),
        ),
      );
    }

    if (_tampilan == 'Grid') {
      return _grid(daftar);
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

  /* ----------------------------------------------------------------------- */
  /* TAMPILAN GRID KAMERA (kotak berisi gambar kamera - seperti halaman resmi */
  /* ATCS Dishub)                                                            */
  /* ----------------------------------------------------------------------- */

  Widget _grid(List<RtsCctvKamera> daftar) {
    return RefreshIndicator(
      color: rtsKsMaroon,
      onRefresh: () => _muat(segarkan: true, diam: true),
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          childAspectRatio: 0.82,
        ),
        itemCount: daftar.length,
        itemBuilder: (BuildContext context, int i) => _kartuGrid(daftar[i]),
      ),
    );
  }

  Widget _kartuGrid(RtsCctvKamera kamera) {
    final String gambar = kamera.posterUrl;
    final double? jarak = _jarakKe(kamera);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _putar(kamera),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _gambarKamera(gambar),
                  // lapisan gelap supaya tombol PUTAR jelas terbaca
                  Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          Color(0x33000000),
                          Color(0x99000000),
                        ],
                      ),
                    ),
                  ),
                  if (kamera.siap != null)
                    Positioned(
                      left: 8,
                      top: 8,
                      child: _lencanaSiap(kamera.siap!),
                    ),
                  Center(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: rtsKsMaroon,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 7,
                        ),
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _putar(kamera),
                      icon: const Icon(Icons.play_arrow_rounded, size: 19),
                      label: const Text('Play', style: TextStyle(fontSize: 12.5)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    kamera.judul,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: rtsKsTeks,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.place_outlined, size: 12, color: rtsKsTeks2),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          kamera.lokasi,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                        ),
                      ),
                      if (jarak != null)
                        Text(
                          rtsCctvJarakTeks(jarak),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: rtsKsHijau,
                          ),
                        ),
                      GestureDetector(
                        onTap: () => _menuKamera(kamera),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                            Icons.more_horiz_rounded,
                            size: 17,
                            color: rtsKsTeks2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Gambar kamera (poster) dengan gambar pengganti bila gagal / belum ada.
  Widget _gambarKamera(String gambar) {
    const Widget pengganti = ColoredBox(
      color: Color(0xff171414),
      child: Center(
        child: Icon(Icons.videocam_rounded, size: 34, color: Colors.white24),
      ),
    );

    if (gambar.isEmpty || !_pakaiGambar) return pengganti;

    return Image.network(
      gambar,
      fit: BoxFit.cover,
      // Gambar dari situs Dishub berukuran besar. cacheWidth membatasinya
      // supaya tampilan HP tetap ringan (gambar tetap diunduh sekali saja).
      cacheWidth: 420,
      errorBuilder: (_, __, ___) => pengganti,
      loadingBuilder: (
        BuildContext context,
        Widget anak,
        ImageChunkEvent? kemajuan,
      ) {
        if (kemajuan == null) return anak;

        return const ColoredBox(
          color: Color(0xff171414),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
            ),
          ),
        );
      },
    );
  }

  /// Lencana SIAP / TIDAK TERSEDIA (seperti READY / MAINTENANCE di situs ATCS).
  Widget _lencanaSiap(bool siap) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: siap ? rtsKsHijau : rtsKsMerah,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        siap ? 'SIAP' : 'TIDAK TERSEDIA',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  /* ----------------------------------------------------------------------- */
  /* TAMPILAN PETA - seluruh kamera sebagai titik (seperti tab "Peta" pada    */
  /* halaman resmi ATCS Dishub)                                              */
  /* ----------------------------------------------------------------------- */

  /// Pusat peta: rata-rata titik seluruh kamera.
  LatLng _pusatKamera() {
    double lat = 0;
    double lon = 0;
    int jumlah = 0;

    for (final RtsCctvKamera kamera in _kamera) {
      if (!kamera.adaTitik) continue;

      lat += kamera.lat;
      lon += kamera.lon;
      jumlah++;
    }

    if (jumlah == 0) return const LatLng(3.5952, 98.6722); // pusat Kota Medan

    return LatLng(lat / jumlah, lon / jumlah);
  }

  void _aturKameraPeta() {
    final List<LatLng> titik = <LatLng>[];

    for (final RtsCctvKamera kamera in _kamera) {
      if (kamera.adaTitik) titik.add(kamera.titik);
    }

    if (_saya != null) {
      titik.add(LatLng(_saya!.latitude, _saya!.longitude));
    }

    rtsPetaAturKamera(_kontrolPeta, titik);
  }

  Widget _petaTampilan() {
    final List<Marker> penanda = <Marker>[];

    for (final RtsCctvKamera kamera in _kamera) {
      if (!kamera.adaTitik) continue;

      penanda.add(
        Marker(
          point: kamera.titik,
          width: 34,
          height: 34,
          child: GestureDetector(
            onTap: () => _putar(kamera),
            child: Icon(
              Icons.videocam_rounded,
              size: 26,
              color: kamera.siap == null
                  ? rtsKsMaroon
                  : (kamera.siap! ? rtsKsHijau : rtsKsMerah),
            ),
          ),
        ),
      );
    }

    final Position? saya = _saya;

    if (saya != null) {
      penanda.add(
        Marker(
          point: LatLng(saya.latitude, saya.longitude),
          width: 30,
          height: 30,
          child: const Icon(
            Icons.person_pin_circle_rounded,
            size: 26,
            color: rtsPetaSaya,
          ),
        ),
      );
    }

    if (penanda.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(22),
          child: Text(
            'Titik koordinat kamera belum ada pada daftar. Buka '
            'periksa_cctv.php?paksa=1&ambil=1 pada website supaya koordinat '
            'kamera ikut terbarui, lalu tekan SEGARKAN di sini.',
            textAlign: TextAlign.center,
            style: TextStyle(color: rtsKsTeks, height: 1.55),
          ),
        ),
      );
    }

    return Stack(
      children: <Widget>[
        FlutterMap(
          mapController: _kontrolPeta,
          options: MapOptions(
            initialCenter: _pusatKamera(),
            initialZoom: 12.5,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _aturKameraPeta(),
              );
            },
          ),
          children: <Widget>[
            TileLayer(
              urlTemplate: rtsPetaSumber[0].url,
              userAgentPackageName: 'com.bene.rts_panel_app',
              maxNativeZoom: rtsPetaSumber[0].maksZoom,
            ),
            MarkerLayer(markers: penanda),
          ],
        ),
        Positioned(
          right: 10,
          bottom: 76,
          child: rtsPetaAtribusi(rtsPetaSumber[0].nama),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 12,
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                  onPressed: _saya == null ? _pakaiLokasi : _putarTerdekat,
                  icon: Icon(
                    _saya == null
                        ? Icons.my_location_rounded
                        : Icons.near_me_rounded,
                    size: 17,
                  ),
                  label: Text(
                    _saya == null ? 'PAKAI LOKASI' : 'TERDEKAT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              IconButton.filledTonal(
                tooltip: 'Lihat seluruh kamera',
                onPressed: _aturKameraPeta,
                icon: const Icon(Icons.fullscreen_rounded, size: 20),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: 'Segarkan daftar',
                onPressed: _menyegarkan
                    ? null
                    : () => _muat(segarkan: true, diam: true),
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Membuka pemutar untuk kamera paling dekat dari posisi HP.
  Future<void> _putarTerdekat() async {
    final Position? saya = _saya;

    if (saya == null) {
      await _pakaiLokasi();

      return;
    }

    RtsCctvKamera? dekat;
    double jarakDekat = double.infinity;

    for (final RtsCctvKamera kamera in _kamera) {
      if (!kamera.adaTitik) continue;

      final double jarak = rtsPetaJarakMeter(
        saya.latitude,
        saya.longitude,
        kamera.lat,
        kamera.lon,
      );

      if (jarak < jarakDekat) {
        jarakDekat = jarak;
        dekat = kamera;
      }
    }

    if (dekat == null) return;

    await _putar(dekat);
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
                        if (kamera.siap != null) ...<Widget>[
                          _lencanaSiap(kamera.siap!),
                          const SizedBox(width: 6),
                        ],
                        Flexible(
                          child: Text(
                            kamera.kode,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                          ),
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
                'TIGA TAMPILAN (seperti halaman resmi ATCS Dishub):',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Text(
                'DAFTAR - daftar memanjang, satu kamera satu baris.\n'
                'GRID KAMERA - kotak-kotak berisi GAMBAR kamera + tombol Play.\n'
                'PETA - seluruh kamera sebagai titik pada satu peta; ketuk titik '
                'untuk memutar.',
                style: TextStyle(fontSize: 12.5, height: 1.6, color: rtsKsTeks2),
              ),
              const SizedBox(height: 10),
              const Text(
                'Cara memakai:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Text(
                '1. Ketik nama jalan pada kotak pencarian, atau\n'
                '2. Tekan "Pakai lokasi" supaya kamera terdekat muncul di atas, lalu\n'
                '3. Tekan PUTAR / Play. Di dalam pemutar ada tombol layar penuh, '
                'peta lokasi kamera, dan salin tautan.',
                style: TextStyle(fontSize: 12.5, height: 1.6, color: rtsKsTeks2),
              ),
              const SizedBox(height: 10),
              const Text(
                'LENCANA SIAP / TIDAK TERSEDIA:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const Text(
                'Tekan tombol PERIKSA (ikon gelombang di kanan atas). Server '
                'memeriksa seluruh kamera seperti tombol READY pada situs Dishub, '
                'lalu hasilnya disimpan 10 menit. Kamera yang dimatikan Dishub '
                'diberi keterangan TIDAK TERSEDIA - bukan kerusakan aplikasi.',
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

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
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
