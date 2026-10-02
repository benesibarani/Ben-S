// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : PETA CUSTOMER, RADAR, RUTE PLAN
//  Berkas : lib/peta.dart
//  Versi  : 1   (3 Oktober 2026)
//
//  ISI BERKAS INI (semua tampilan peta, dipisah dari main.dart supaya
//  pembaruan berikutnya cukup mengganti satu berkas):
//
//     1. RtsPetaCustomerPage - PETA CUSTOMER (OpenStreetMap)
//            seluruh toko tampil sebagai penanda, dapat disaring menurut
//            HARI kunjungan dan FREKUENSI KUNJUNGAN (Weekly / Bi-Weekly
//            Ganjil / Bi-Weekly Genap), warna penanda dapat dipilih:
//            menurut HARI atau menurut FREKUENSI.
//     2. RtsRadarPage        - RADAR CUSTOMER
//            daftar toko di sekitar titik GPS petugas, urut dari yang
//            paling dekat, lengkap dengan jarak (nama, alamat, jarak).
//     3. RtsRutePage         - RUTE PLAN
//            urutan kunjungan dari titik KANTOR sampai terjauh, ditambah
//            PENSIL untuk menggambar garis rute perjalanan, dan daftar
//            rencana yang dapat DISALIN (nama customer + id customer).
//     4. RtsKantorPage       - LOKASI KANTOR / MITRA (khusus ADMIN & ASS)
//            titik kantor dipakai sebagai awal perhitungan RUTE PLAN.
//
//  CATATAN PENTING
//  ---------------
//  - Peta memakai OpenStreetMap (gratis, tanpa kunci API). Ubin peta diunduh
//    dari internet. Titik toko, titik kantor, catatan kunjungan, dan goresan
//    pensil disimpan DI DALAM HP (SQLite lewat kasir_lokal.dart), jadi daftar
//    dan perhitungan jarak tetap bekerja walau tanpa internet.
//  - Berkas ini memakai warna dan pesan dari kasir.dart supaya tampilannya
//    sama dengan menu Kasir (satu gaya untuk seluruh Menu PRO).
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'kasir.dart';
import 'kasir_lokal.dart';

/* ------------------------------------------------------------------------- */
/* WARNA TAMBAHAN                                                            */
/* ------------------------------------------------------------------------- */

const Color rtsPetaWeekly = Color(0xff1e7a45);
const Color rtsPetaGanjil = Color(0xff1d6fb8);
const Color rtsPetaGenap = Color(0xff8a4bbd);
const Color rtsPetaKosong = Color(0xff8b817a);
const Color rtsPetaSenin = Color(0xffc0392b);
const Color rtsPetaSelasa = Color(0xffd0691f);
const Color rtsPetaRabu = Color(0xffb3761b);
const Color rtsPetaKamis = Color(0xff1e7a45);
const Color rtsPetaJumat = Color(0xff1d6fb8);
const Color rtsPetaSabtu = Color(0xff6b3fa0);
const Color rtsPetaMinggu = Color(0xff0f7a7a);
const Color rtsPetaKantor = Color(0xff201c19);
const Color rtsPetaSaya = Color(0xff0b62d6);
const Color rtsPetaAir = Color(0xffe5ded6);

const TextStyle rtsPetaJudulKecil = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w800,
  color: rtsKsTeks,
);

const TextStyle rtsPetaIsiKecil = TextStyle(fontSize: 12, color: rtsKsTeks2);

/// Kotak putih dengan sudut membulat - dipakai seluruh halaman peta.
BoxDecoration rtsPetaKotak({Color warna = Colors.white}) {
  return BoxDecoration(
    color: warna,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: rtsKsGaris),
    boxShadow: const <BoxShadow>[
      BoxShadow(
        color: Color.fromRGBO(74, 44, 34, 0.06),
        blurRadius: 10,
        offset: Offset(0, 4),
      ),
    ],
  );
}

/* ------------------------------------------------------------------------- */
/* SUMBER UBIN PETA (OpenStreetMap)                                          */
/* ------------------------------------------------------------------------- */

/// Satu pilihan ubin peta. Semuanya dari OpenStreetMap - tidak perlu kunci API
/// dan tidak ada biaya bulanan.
class RtsSumberPeta {
  const RtsSumberPeta({
    required this.nama,
    required this.url,
    required this.keterangan,
    required this.atribusi,
    this.maksZoom = 19,
  });

  final String nama;
  final String url;
  final String keterangan;
  final String atribusi;
  final int maksZoom;
}

const List<RtsSumberPeta> rtsPetaSumber = <RtsSumberPeta>[
  RtsSumberPeta(
    nama: 'OpenStreetMap',
    url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    keterangan: 'Peta jalan biasa (paling ringan)',
    atribusi: 'OpenStreetMap',
  ),
  RtsSumberPeta(
    nama: 'OSM Bantuan',
    url: 'https://a.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
    keterangan: 'Nama jalan lebih tegas - mudah dibaca di HP',
    atribusi: 'OpenStreetMap - Humanitarian',
  ),
  RtsSumberPeta(
    nama: 'OpenTopoMap',
    url: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    keterangan: 'Menampilkan bentuk tanah dan ketinggian',
    atribusi: 'OpenTopoMap (CC-BY-SA)',
    maksZoom: 17,
  ),
];

const String rtsPetaHakCipta = 'https://www.openstreetmap.org/copyright';

/* ------------------------------------------------------------------------- */
/* PILIHAN PENYARING                                                         */
/* ------------------------------------------------------------------------- */

const List<String> rtsPetaHari = <String>[
  'Semua',
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

const List<String> rtsPetaFrekuensi = <String>[
  'Semua',
  'Weekly',
  'Bi-Weekly Ganjil',
  'Bi-Weekly Genap',
  'Belum diisi',
];

const List<String> rtsPetaJenis = <String>[
  'Semua',
  'REGULER',
  'GSP',
];

const List<String> rtsPetaStatusKunjungan = <String>[
  'Semua',
  'Belum dikunjungi hari ini',
  'Sudah dikunjungi hari ini',
];

const List<String> rtsPetaCaraWarna = <String>['HARI', 'KUNJUNGAN'];

/// Radius RADAR dalam meter (0 = semua toko).
const List<int> rtsPetaRadius = <int>[100, 250, 500, 1000, 3000, 5000, 0];

/// Warna pensil rute yang dapat dipilih sales (disimpan sebagai angka).
const List<int> rtsPetaWarnaPensilNilai = <int>[
  0xff1d6fb8,
  0xffc0392b,
  0xff1e7a45,
  0xff6b3fa0,
  0xff201c19,
];

/// Warna pensil menurut pilihan yang tersimpan di HP.
Color rtsPetaPensilWarna(int pilihan) {
  if (pilihan < 0 || pilihan >= rtsPetaWarnaPensilNilai.length) {
    return Color(rtsPetaWarnaPensilNilai.first);
  }

  return Color(rtsPetaWarnaPensilNilai[pilihan]);
}

/* ------------------------------------------------------------------------- */
/* BANTUAN UMUM                                                              */
/* ------------------------------------------------------------------------- */

const double rtsPetaBumi = 6371000.0;

/// Jarak dua titik di permukaan bumi (meter) - rumus haversine.
double rtsPetaJarakMeter(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const double derajatKeRad = math.pi / 180.0;

  final double dLat = (lat2 - lat1) * derajatKeRad;
  final double dLng = (lng2 - lng1) * derajatKeRad;
  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * derajatKeRad) *
          math.cos(lat2 * derajatKeRad) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  return 2 * rtsPetaBumi * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Tulisan jarak yang mudah dibaca: "320 m" atau "1,4 km".
String rtsPetaJarakTeks(double meter) {
  if (meter.isNaN || meter < 0) return '-';

  if (meter < 1000) return '${meter.round()} m';

  final String angka = (meter / 1000).toStringAsFixed(1).replaceAll('.', ',');

  return '$angka km';
}

/// Arah mata angin dari utara (0-360 derajat).
String rtsPetaArah(double derajat) {
  const List<String> arah = <String>[
    'Utara',
    'Timur Laut',
    'Timur',
    'Tenggara',
    'Selatan',
    'Barat Daya',
    'Barat',
    'Barat Laut',
  ];

  double d = derajat % 360;

  if (d < 0) d += 360;

  final int posisi = ((d + 22.5) ~/ 45) % 8;

  return arah[posisi];
}

/// Arah mata angin dari titik 1 ke titik 2 (derajat dari utara).
double rtsPetaBearing(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const double derajatKeRad = math.pi / 180.0;

  final double t1 = lat1 * derajatKeRad;
  final double t2 = lat2 * derajatKeRad;
  final double dLng = (lng2 - lng1) * derajatKeRad;

  final double y = math.sin(dLng) * math.cos(t2);
  final double x = math.cos(t1) * math.sin(t2) -
      math.sin(t1) * math.cos(t2) * math.cos(dLng);

  return math.atan2(y, x) / derajatKeRad;
}

String rtsPetaDua(int angka) => angka < 10 ? '0$angka' : '$angka';

String rtsPetaTanggalTeks(DateTime t) =>
    '${rtsPetaDua(t.day)}-${rtsPetaDua(t.month)}-${t.year}';

/// Nama hari Indonesia dari DateTime (Minggu .. Sabtu).
String rtsPetaNamaHari(DateTime t) {
  const List<String> nama = <String>[
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  return nama[t.weekday % 7];
}

/// Nomor pekan dalam tahun (untuk membedakan pekan GANJIL dan GENAP).
int rtsPetaPekan(DateTime t) {
  final DateTime awal = DateTime(t.year, 1, 1);
  final int geser = awal.weekday % 7;
  final int hariKe = t.difference(awal).inDays + 1;

  return ((hariKe + geser - 1) ~/ 7) + 1;
}

bool rtsPetaPekanGanjil(DateTime t) => rtsPetaPekan(t).isOdd;

/// Menyeragamkan tulisan frekuensi kunjungan yang tersimpan pada master_toko.
/// Contoh yang dikenali: "Weekly", "Mingguan", "Bi-Weekly Ganjil",
/// "BIWEEKLY GENAP", "bi weekly ganjil".
String rtsPetaFrekuensiNormal(String nilai) {
  final String t = nilai
      .toLowerCase()
      .replaceAll('-', ' ')
      .replaceAll('_', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (t.isEmpty) return '';

  final bool bi = t.contains('bi ') ||
      t.contains('biweek') ||
      t.contains('dua minggu') ||
      t.contains('2 minggu');

  if (t.contains('ganjil')) return 'GANJIL';
  if (t.contains('genap')) return 'GENAP';
  if (bi) return 'BIWEEKLY';
  if (t.contains('week') || t.contains('minggu')) return 'WEEKLY';

  return t.toUpperCase();
}

Color rtsPetaWarnaFrekuensi(String kunjungan) {
  switch (rtsPetaFrekuensiNormal(kunjungan)) {
    case 'WEEKLY':
      return rtsPetaWeekly;
    case 'GANJIL':
      return rtsPetaGanjil;
    case 'GENAP':
      return rtsPetaGenap;
  }

  return rtsPetaKosong;
}

Color rtsPetaWarnaHari(String hari) {
  final String h = hari.toLowerCase();

  if (h.contains('senin')) return rtsPetaSenin;
  if (h.contains('selasa')) return rtsPetaSelasa;
  if (h.contains('rabu')) return rtsPetaRabu;
  if (h.contains('kamis')) return rtsPetaKamis;
  if (h.contains('jumat') || h.contains("jum'at")) return rtsPetaJumat;
  if (h.contains('sabtu')) return rtsPetaSabtu;
  if (h.contains('minggu')) return rtsPetaMinggu;

  return rtsPetaKosong;
}

bool rtsPetaHariCocok(String nilai, String hari) {
  if (hari == 'Semua') return true;

  return nilai.toLowerCase().contains(hari.toLowerCase());
}

bool rtsPetaFrekuensiCocok(String nilai, String pilihan) {
  if (pilihan == 'Semua') return true;

  final String normal = rtsPetaFrekuensiNormal(nilai);

  if (pilihan == 'Belum diisi') return normal.isEmpty;
  if (pilihan == 'Weekly') return normal == 'WEEKLY';

  return normal == rtsPetaFrekuensiNormal(pilihan);
}

/// Membuka aplikasi peta HP (Google Maps) menuju satu titik toko.
Future<void> rtsPetaNavigasi(
  BuildContext context,
  double lat,
  double lng,
  String nama,
) async {
  final Uri googleMaps = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
  );
  final Uri geoMaps = Uri.parse(
    'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(nama)})',
  );

  for (final Uri uri in <Uri>[googleMaps, geoMaps]) {
    try {
      final bool dibuka = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (dibuka) return;
    } catch (_) {
      // lanjut ke pilihan berikutnya
    }
  }

  if (context.mounted) {
    rtsKsPesan(
      context,
      'Aplikasi peta tidak dapat dibuka. Pastikan Google Maps terpasang.',
      galat: true,
    );
  }
}

/// Membuka halaman hak cipta OpenStreetMap (kewajiban pemakaian peta gratis).
Future<void> rtsPetaHakCiptaBuka() async {
  try {
    await launchUrl(
      Uri.parse(rtsPetaHakCipta),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // tidak ada aplikasi peramban: tidak apa-apa
  }
}

/* ------------------------------------------------------------------------- */
/* MODEL DATA                                                                */
/* ------------------------------------------------------------------------- */

/// Satu toko beserta titik koordinat dan jadwal kunjungannya.
class RtsToko {
  RtsToko({
    required this.idCustomer,
    required this.nama,
    required this.alamat,
    required this.district,
    required this.salesman,
    required this.tipe,
    required this.kunjungan,
    required this.hari,
    required this.latitude,
    required this.longitude,
  });

  final String idCustomer;
  final String nama;
  final String alamat;
  final String district;
  final String salesman;
  final String tipe;
  final String kunjungan;
  final String hari;
  final double latitude;
  final double longitude;

  bool get adaTitik => latitude != 0 && longitude != 0;
  bool get isGsp => tipe.toUpperCase() == 'GSP';
  LatLng get titik => LatLng(latitude, longitude);

  String get frekuensiTeks =>
      kunjungan.trim().isEmpty ? 'Belum diisi' : kunjungan.trim();

  String get hariTeks => hari.trim().isEmpty ? 'Belum diisi' : hari.trim();

  factory RtsToko.dariPeta(Map<String, dynamic> j) {
    return RtsToko(
      idCustomer: '${j['id_customer'] ?? ''}',
      nama: '${j['nama'] ?? ''}',
      alamat: '${j['alamat'] ?? ''}',
      district: '${j['district'] ?? ''}',
      salesman: '${j['salesman'] ?? ''}',
      tipe: '${j['tipe'] ?? 'REGULER'}',
      kunjungan: '${j['kunjungan'] ?? ''}',
      hari: '${j['hari'] ?? ''}',
      latitude: rtsKsAngka(j['latitude']),
      longitude: rtsKsAngka(j['longitude']),
    );
  }
}

/// Titik lokasi kantor / mitra (awal perhitungan RUTE PLAN).
class RtsKantor {
  RtsKantor({
    required this.id,
    required this.idServer,
    required this.nama,
    required this.alamat,
    required this.district,
    required this.latitude,
    required this.longitude,
    required this.catatan,
    required this.diubahPada,
  });

  final int id;
  final int idServer;
  final String nama;
  final String alamat;
  final String district;
  final double latitude;
  final double longitude;
  final String catatan;
  final String diubahPada;

  bool get adaTitik => latitude != 0 && longitude != 0;
  LatLng get titik => LatLng(latitude, longitude);

  factory RtsKantor.dariPeta(Map<String, dynamic> j) {
    return RtsKantor(
      id: rtsKsBulat(j['id']),
      idServer: rtsKsBulat(j['id_server']),
      nama: '${j['nama'] ?? ''}',
      alamat: '${j['alamat'] ?? ''}',
      district: '${j['district'] ?? ''}',
      latitude: rtsKsAngka(j['latitude']),
      longitude: rtsKsAngka(j['longitude']),
      catatan: '${j['catatan'] ?? ''}',
      diubahPada: '${j['diubah_pada'] ?? ''}',
    );
  }
}

/// Satu goresan rute hasil PENSIL pada peta.
class RtsGoresan {
  RtsGoresan({
    required this.id,
    required this.nama,
    required this.warna,
    required this.tebal,
    required this.titik,
    this.tampil = true,
  });

  final int id;
  final String nama;
  final int warna;
  final double tebal;
  final List<LatLng> titik;
  bool tampil;

  Color get warnaAsli {
    if (warna == 0) return rtsPetaPensilWarna(0);

    return Color(warna);
  }

  /// Membaca goresan yang disimpan di HP (titik disimpan sebagai teks JSON).
  static List<RtsGoresan> dariDaftar(List<dynamic> items) {
    final List<RtsGoresan> hasil = <RtsGoresan>[];

    for (final dynamic satu in items) {
      if (satu is! Map) continue;

      final Map<dynamic, dynamic> m = satu;
      final List<LatLng> titik = <LatLng>[];

      try {
        final dynamic urai = jsonDecode('${m['titik'] ?? ''}');

        if (urai is List) {
          for (final dynamic t in urai) {
            if (t is! List || t.length < 2) continue;

            titik.add(LatLng(rtsKsAngka(t[0]), rtsKsAngka(t[1])));
          }
        }
      } catch (_) {
        // goresan tidak terbaca: dilewati
      }

      if (titik.length < 2) continue;

      hasil.add(
        RtsGoresan(
          id: rtsKsBulat(m['id']),
          nama: '${m['nama'] ?? ''}',
          warna: rtsKsBulat(m['warna']),
          tebal: rtsKsAngka(m['tebal']) <= 0 ? 4 : rtsKsAngka(m['tebal']),
          titik: titik,
        ),
      );
    }

    return hasil;
  }
}

/* ------------------------------------------------------------------------- */
/* KETERANGAN AKUN (dipakai seluruh halaman)                                 */
/* ------------------------------------------------------------------------- */

/// Kunci penyimpanan pilihan sumber peta & warna pensil di HP.
const String rtsPetaKunciSumber = 'rts_peta_sumber';
const String rtsPetaKunciPensil = 'rts_peta_warna_pensil';

Future<void> rtsPetaSiapkanAkun({
  required String baseUrl,
  required String token,
  required Map<String, dynamic> pengguna,
}) async {
  await RtsKasirLokal.aku.atur(
    baseUrl: baseUrl,
    token: token,
    pengguna: pengguna,
  );
}

Future<int> rtsPetaBacaAngka(String kunci, int bawaan) async {
  try {
    final SharedPreferences p = await SharedPreferences.getInstance();

    return p.getInt(kunci) ?? bawaan;
  } catch (_) {
    return bawaan;
  }
}

Future<void> rtsPetaTulisAngka(String kunci, int nilai) async {
  try {
    final SharedPreferences p = await SharedPreferences.getInstance();

    await p.setInt(kunci, nilai);
  } catch (_) {
    // pilihan tidak tersimpan: tetap dipakai untuk sesi ini
  }
}

/* ------------------------------------------------------------------------- */
/* PENANDA PETA                                                              */
/* ------------------------------------------------------------------------- */

/// Penanda toko pada peta: bulat untuk REGULER, kotak untuk GSP.
/// Bila toko sudah dikunjungi hari ini, diberi tanda centang putih.
Widget rtsPetaPenanda({
  required String label,
  required Color warna,
  bool terpilih = false,
  bool gsp = false,
  bool sudah = false,
  bool kantor = false,
  bool saya = false,
}) {
  final double ukuran = terpilih ? 40 : 32;

  if (saya) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: rtsPetaSaya,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, 0.35),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  if (kantor) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: rtsPetaKantor,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(Icons.business_rounded, color: Colors.white, size: 18),
        ),
      ),
    );
  }

  return SizedBox(
    width: 46,
    height: 46,
    child: Center(
      child: Container(
        width: ukuran,
        height: ukuran,
        decoration: BoxDecoration(
          color: warna,
          shape: gsp ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: gsp ? BorderRadius.circular(9) : null,
          border: Border.all(color: Colors.white, width: terpilih ? 3 : 2),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.28),
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: terpilih ? 16 : 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Kartu kecil di atas peta: keterangan warna yang sedang dipakai.
Widget rtsPetaLegenda({
  required List<MapEntry<String, Color>> isi,
  String judul = 'Warna',
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: rtsPetaKotak(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(judul, style: rtsPetaJudulKecil),
        const SizedBox(height: 5),
        Wrap(
          spacing: 10,
          runSpacing: 5,
          children: isi.map((MapEntry<String, Color> e) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: e.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  e.key,
                  style: const TextStyle(fontSize: 10.5, color: rtsKsTeks2),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    ),
  );
}

/// Tulisan hak cipta peta - wajib ditampilkan pada pemakaian ubin
/// OpenStreetMap.
Widget rtsPetaAtribusi(String namaSumber) {
  return GestureDetector(
    onTap: () => unawaited(rtsPetaHakCiptaBuka()),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: rtsKsGaris),
      ),
      child: Text(
        'Peta: $namaSumber',
        style: const TextStyle(fontSize: 9.5, color: rtsKsTeks2),
      ),
    ),
  );
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 1 : PETA CUSTOMER                                                 */
/* ------------------------------------------------------------------------- */

class RtsPetaCustomerPage extends StatefulWidget {
  const RtsPetaCustomerPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsPetaCustomerPage> createState() => _RtsPetaCustomerPageState();
}

class _RtsPetaCustomerPageState extends State<RtsPetaCustomerPage> {
  final MapController _kontrol = MapController();

  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  bool _perluPro = false;

  List<RtsToko> _toko = <RtsToko>[];
  List<RtsKantor> _kantor = <RtsKantor>[];
  Set<String> _sudah = <String>{};

  String _hari = 'Semua';
  String _frekuensi = 'Semua';
  String _tipe = 'Semua';
  String _status = 'Semua';
  String _cari = '';
  String _caraWarna = 'KUNJUNGAN';

  int _sumber = 0;
  double? _sayaLat;
  double? _sayaLng;
  RtsToko? _terpilih;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mulai();
    });
  }

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  Future<void> _mulai() async {
    await rtsPetaSiapkanAkun(
      baseUrl: widget.baseUrl,
      token: widget.token,
      pengguna: widget.pengguna,
    );

    _sumber = await rtsPetaBacaAngka(rtsPetaKunciSumber, 0);

    if (!mounted) return;

    await _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await RtsKasirLokal.aku.kirim('toko_peta');
      final List<dynamic> items =
          hasil['items'] is List ? hasil['items'] as List<dynamic> : <dynamic>[];

      final List<RtsToko> daftar = <RtsToko>[];

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        daftar.add(RtsToko.dariPeta(satu.cast<String, dynamic>()));
      }

      final Map<String, dynamic> kunjungan =
          await RtsKasirLokal.aku.kirim('kunjungan_hari_ini');

      final List<dynamic> idKunjungan = kunjungan['id_customer'] is List
          ? kunjungan['id_customer'] as List<dynamic>
          : <dynamic>[];

      List<RtsKantor> kantor = <RtsKantor>[];

      try {
        final Map<String, dynamic> hasilKantor =
            await RtsKasirLokal.aku.kirim('kantor_daftar');

        kantor = _kantorDari(hasilKantor['items']);
      } catch (_) {
        kantor = <RtsKantor>[];
      }

      if (!mounted) return;

      setState(() {
        _toko = daftar;
        _kantor = kantor;
        _sudah = idKunjungan.map((dynamic e) => '$e').toSet();
        _memuat = false;
      });

      // Salinan di HP masih kosong: tarik dari master_toko sekali.
      if (daftar.isEmpty) {
        await _segarkanToko(diam: true);
      } else {
        _aturTampilan();
      }
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
      });
    }
  }

  List<RtsKantor> _kantorDari(dynamic items) {
    final List<RtsKantor> hasil = <RtsKantor>[];

    if (items is List) {
      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        hasil.add(RtsKantor.dariPeta(satu.cast<String, dynamic>()));
      }
    }

    return hasil;
  }

  /// Menarik salinan master_toko terbaru (beserta titik koordinat) ke HP.
  Future<void> _segarkanToko({bool diam = false}) async {
    if (!diam) setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('toko_segarkan');

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Daftar toko tersimpan.'}');

      setState(() => _sibuk = false);

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
      });
    }
  }

  /// Mengatur peta supaya seluruh penanda yang tampil masuk ke layar.
  void _aturTampilan() {
    final List<RtsToko> daftar = _tampil;

    if (daftar.isEmpty) return;

    double minLat = daftar.first.latitude;
    double maksLat = daftar.first.latitude;
    double minLng = daftar.first.longitude;
    double maksLng = daftar.first.longitude;

    for (final RtsToko t in daftar) {
      minLat = math.min(minLat, t.latitude);
      maksLat = math.max(maksLat, t.latitude);
      minLng = math.min(minLng, t.longitude);
      maksLng = math.max(maksLng, t.longitude);
    }

    final LatLng pusat = LatLng((minLat + maksLat) / 2, (minLng + maksLng) / 2);
    final double sebaran = math.max(maksLat - minLat, maksLng - minLng);

    double zoom = 15;

    if (sebaran > 1.5) {
      zoom = 8;
    } else if (sebaran > 0.7) {
      zoom = 9;
    } else if (sebaran > 0.35) {
      zoom = 10;
    } else if (sebaran > 0.18) {
      zoom = 11;
    } else if (sebaran > 0.09) {
      zoom = 12;
    } else if (sebaran > 0.045) {
      zoom = 13;
    } else if (sebaran > 0.02) {
      zoom = 14;
    }

    try {
      _kontrol.move(pusat, zoom);
    } catch (_) {
      // peta belum siap: pengaturan tampilan dilewati
    }
  }

  List<RtsToko> get _tampil {
    final String kunci = _cari.trim().toLowerCase();

    return _toko.where((RtsToko t) {
      if (!t.adaTitik) return false;
      if (!rtsPetaHariCocok(t.hari, _hari)) return false;
      if (!rtsPetaFrekuensiCocok(t.kunjungan, _frekuensi)) return false;
      if (_tipe != 'Semua' && t.tipe.toUpperCase() != _tipe) return false;

      final bool sudah = _sudah.contains(t.idCustomer);

      if (_status == 'Sudah dikunjungi hari ini' && !sudah) return false;
      if (_status == 'Belum dikunjungi hari ini' && sudah) return false;

      if (kunci.isNotEmpty) {
        final bool cocok = t.nama.toLowerCase().contains(kunci) ||
            t.idCustomer.toLowerCase().contains(kunci) ||
            t.alamat.toLowerCase().contains(kunci);

        if (!cocok) return false;
      }

      return true;
    }).toList();
  }

  int get _tanpaTitik => _toko.where((RtsToko t) => !t.adaTitik).length;

  RtsSumberPeta get _sumberPeta {
    final int i = _sumber < 0 || _sumber >= rtsPetaSumber.length ? 0 : _sumber;

    return rtsPetaSumber[i];
  }

  Color _warna(RtsToko t) {
    if (_caraWarna == 'HARI') return rtsPetaWarnaHari(t.hari);

    return rtsPetaWarnaFrekuensi(t.kunjungan);
  }

  double? _jarakKantor(RtsToko t) {
    for (final RtsKantor k in _kantor) {
      if (k.adaTitik) {
        return rtsPetaJarakMeter(k.latitude, k.longitude, t.latitude, t.longitude);
      }
    }

    return null;
  }

  double? _jarakSaya(RtsToko t) {
    if (_sayaLat == null || _sayaLng == null) return null;

    return rtsPetaJarakMeter(_sayaLat!, _sayaLng!, t.latitude, t.longitude);
  }

  Future<void> _lokasiSaya() async {
    setState(() => _sibuk = true);

    final Position? posisi = await rtsPetaAmbilLokasi();

    if (!mounted) return;

    setState(() {
      _sibuk = false;

      if (posisi != null) {
        _sayaLat = posisi.latitude;
        _sayaLng = posisi.longitude;
      }
    });

    if (posisi == null) {
      rtsKsPesan(
        context,
        'Titik GPS belum dapat dibaca. Nyalakan Lokasi pada HP dan beri izin '
        'Lokasi untuk RTS Panel.',
        galat: true,
      );
      return;
    }

    rtsKsPesan(context, 'Titik lokasi Anda sudah dibaca.');

    try {
      _kontrol.move(LatLng(posisi.latitude, posisi.longitude), 15);
    } catch (_) {
      // peta belum siap
    }
  }

  Future<void> _bukaLembarSaring() async {
    final Map<String, dynamic>? hasil = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => _RtsLembarSaring(
        hari: _hari,
        frekuensi: _frekuensi,
        tipe: _tipe,
        status: _status,
        cari: _cari,
        caraWarna: _caraWarna,
      ),
    );

    if (hasil == null || !mounted) return;

    setState(() {
      _hari = '${hasil['hari']}';
      _frekuensi = '${hasil['frekuensi']}';
      _tipe = '${hasil['tipe']}';
      _status = '${hasil['status']}';
      _cari = '${hasil['cari']}';
      _caraWarna = '${hasil['caraWarna']}';
    });

    _aturTampilan();
  }

  Future<void> _bukaLembarSumber() async {
    final int? pilih = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text('PILIH TAMPILAN PETA', style: rtsPetaJudulKecil),
              ),
              for (int i = 0; i < rtsPetaSumber.length; i++)
                ListTile(
                  leading: Icon(
                    i == _sumber
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: i == _sumber ? rtsKsMaroon : rtsKsTeks2,
                  ),
                  title: Text(rtsPetaSumber[i].nama),
                  subtitle: Text(rtsPetaSumber[i].keterangan),
                  onTap: () => Navigator.of(ctx).pop(i),
                ),
            ],
          ),
        );
      },
    );

    if (pilih == null || !mounted) return;

    setState(() => _sumber = pilih);

    await rtsPetaTulisAngka(rtsPetaKunciSumber, pilih);
  }

  void _bukaKartu(RtsToko t) {
    setState(() => _terpilih = t);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => _RtsKartuToko(
        toko: t,
        sudah: _sudah.contains(t.idCustomer),
        jarakKantor: _jarakKantor(t),
        jarakSaya: _jarakSaya(t),
        caraWarna: _caraWarna,
        onNavigasi: () {
          Navigator.of(ctx).pop();
          unawaited(rtsPetaNavigasi(context, t.latitude, t.longitude, t.nama));
        },
        onKunjungi: () async {
          Navigator.of(ctx).pop();
          await _tandaiKunjungan(t);
        },
        onSalin: () async {
          await rtsPetaSalinTeks(
            '${t.nama} - ${t.idCustomer} - '
            '${t.latitude},${t.longitude} - ${t.alamat}',
          );

          if (mounted) rtsKsPesan(context, 'Keterangan toko disalin.');
        },
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _terpilih = null);
    });
  }

  Future<void> _tandaiKunjungan(RtsToko t) async {
    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kunjungan_simpan', <String, dynamic>{
        'id_customer': t.idCustomer,
        'nama': t.nama,
        'latitude': _sayaLat ?? 0,
        'longitude': _sayaLng ?? 0,
      });

      if (!mounted) return;

      setState(() {
        _sudah = <String>{..._sudah, t.idCustomer};
      });

      rtsKsPesan(context, '${hasil['message'] ?? 'Kunjungan tercatat.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  List<MapEntry<String, Color>> _isiLegenda() {
    if (_caraWarna == 'HARI') {
      return <MapEntry<String, Color>>[
        MapEntry<String, Color>('Senin', rtsPetaSenin),
        MapEntry<String, Color>('Selasa', rtsPetaSelasa),
        MapEntry<String, Color>('Rabu', rtsPetaRabu),
        MapEntry<String, Color>('Kamis', rtsPetaKamis),
        MapEntry<String, Color>('Jumat', rtsPetaJumat),
        MapEntry<String, Color>('Sabtu', rtsPetaSabtu),
        MapEntry<String, Color>('Minggu', rtsPetaMinggu),
        MapEntry<String, Color>('Belum diisi', rtsPetaKosong),
      ];
    }

    return <MapEntry<String, Color>>[
      MapEntry<String, Color>('Weekly', rtsPetaWeekly),
      MapEntry<String, Color>('BW Ganjil', rtsPetaGanjil),
      MapEntry<String, Color>('BW Genap', rtsPetaGenap),
      MapEntry<String, Color>('Belum diisi', rtsPetaKosong),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Peta Customer'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Penyaring',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: _bukaLembarSaring,
          ),
          IconButton(
            tooltip: 'Tampilan peta',
            icon: const Icon(Icons.layers_outlined),
            onPressed: _bukaLembarSumber,
          ),
        ],
      ),
      body: _bangunIsi(),
    );
  }

  Widget _bangunIsi() {
    if (_perluPro) return RtsKunciPro(pesan: _galat);

    if (_galat.isNotEmpty && _toko.isEmpty) {
      return RtsPesanUlang(pesan: _galat, onCoba: _muat);
    }

    final List<RtsToko> daftar = _tampil;

    return Column(
      children: <Widget>[
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      _memuat
                          ? 'Membaca daftar toko...'
                          : '${daftar.length} toko tampil dari ${_toko.length} '
                              'toko di HP',
                      style: rtsPetaJudulKecil,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _sibuk ? null : () => _segarkanToko(),
                    icon: const Icon(Icons.sync_rounded, size: 17),
                    label: const Text('SEGARKAN', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              if (_tanpaTitik > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Catatan: $_tanpaTitik toko belum memiliki titik koordinat '
                    '(latitude/longitude) pada Master Customer, jadi belum dapat '
                    'tampil di peta. Minta Admin melengkapi titiknya.',
                    style: const TextStyle(fontSize: 11, color: rtsKsKuning),
                  ),
                ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: rtsPetaLegenda(
                      isi: _isiLegenda(),
                      judul: _caraWarna == 'HARI'
                          ? 'Warna menurut HARI'
                          : 'Warna menurut FREKUENSI',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: <Widget>[
              FlutterMap(
                mapController: _kontrol,
                options: MapOptions(
                  initialCenter: _pusatAwal(),
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 18,
                  backgroundColor: rtsPetaAir,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: <Widget>[
                  TileLayer(
                    key: ValueKey<String>('ubin-peta-$_sumber'),
                    urlTemplate: _sumberPeta.url,
                    userAgentPackageName: 'com.bene.rts_panel_app',
                    maxNativeZoom: _sumberPeta.maksZoom,
                  ),
                  MarkerLayer(markers: _penanda(daftar)),
                ],
              ),
              Positioned(
                right: 10,
                bottom: 12,
                child: rtsPetaAtribusi(_sumberPeta.nama),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: Column(
                  children: <Widget>[
                    _tombolBulat(
                      ikon: Icons.my_location_rounded,
                      keterangan: 'Titik saya',
                      onTap: _sibuk ? null : _lokasiSaya,
                    ),
                    const SizedBox(height: 8),
                    _tombolBulat(
                      ikon: Icons.fullscreen_rounded,
                      keterangan: 'Tampilkan semua',
                      onTap: _aturTampilan,
                    ),
                    const SizedBox(height: 8),
                    _tombolBulat(
                      ikon: Icons.add,
                      keterangan: 'Perbesar',
                      onTap: () => _zoom(1),
                    ),
                    const SizedBox(height: 8),
                    _tombolBulat(
                      ikon: Icons.remove,
                      keterangan: 'Perkecil',
                      onTap: () => _zoom(-1),
                    ),
                  ],
                ),
              ),
              if (_memuat || _sibuk)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),
        ),
      ],
    );
  }

  LatLng _pusatAwal() {
    for (final RtsKantor k in _kantor) {
      if (k.adaTitik) return k.titik;
    }

    for (final RtsToko t in _toko) {
      if (t.adaTitik) return t.titik;
    }

    // Titik tengah Kota Medan - dipakai sebelum data selesai dibaca.
    return const LatLng(3.5952, 98.6722);
  }

  void _zoom(double tambah) {
    try {
      final MapCamera kamera = _kontrol.camera;

      _kontrol.move(kamera.center, (kamera.zoom + tambah).clamp(4, 18));
    } catch (_) {
      // peta belum siap
    }
  }

  List<Marker> _penanda(List<RtsToko> daftar) {
    final List<Marker> penanda = <Marker>[];

    for (final RtsKantor k in _kantor) {
      if (!k.adaTitik) continue;

      penanda.add(
        Marker(
          point: k.titik,
          width: 44,
          height: 44,
          child: rtsPetaPenanda(
            label: '',
            warna: rtsPetaKantor,
            kantor: true,
          ),
        ),
      );
    }

    if (_sayaLat != null && _sayaLng != null) {
      penanda.add(
        Marker(
          point: LatLng(_sayaLat!, _sayaLng!),
          width: 44,
          height: 44,
          child: rtsPetaPenanda(label: '', warna: rtsPetaSaya, saya: true),
        ),
      );
    }

    for (final RtsToko t in daftar) {
      final Color warna = _warna(t);

      penanda.add(
        Marker(
          point: t.titik,
          width: 46,
          height: 46,
          child: GestureDetector(
            onTap: () => _bukaKartu(t),
            child: rtsPetaPenanda(
              label: t.isGsp ? 'G' : '',
              warna: warna,
              gsp: t.isGsp,
              terpilih: _terpilih?.idCustomer == t.idCustomer,
              sudah: _sudah.contains(t.idCustomer),
            ),
          ),
        ),
      );
    }

    return penanda;
  }

  Widget _tombolBulat({
    required IconData ikon,
    required String keterangan,
    required VoidCallback? onTap,
  }) {
    return Tooltip(
      message: keterangan,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(),
        elevation: 2,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(ikon, size: 20, color: rtsKsMaroon),
          ),
        ),
      ),
    );
  }
}

/// Lembar penyaring PETA CUSTOMER.
class _RtsLembarSaring extends StatefulWidget {
  const _RtsLembarSaring({
    required this.hari,
    required this.frekuensi,
    required this.tipe,
    required this.status,
    required this.cari,
    required this.caraWarna,
  });

  final String hari;
  final String frekuensi;
  final String tipe;
  final String status;
  final String cari;
  final String caraWarna;

  @override
  State<_RtsLembarSaring> createState() => _RtsLembarSaringState();
}

class _RtsLembarSaringState extends State<_RtsLembarSaring> {
  late String _hari = widget.hari;
  late String _frekuensi = widget.frekuensi;
  late String _tipe = widget.tipe;
  late String _status = widget.status;
  late String _caraWarna = widget.caraWarna;
  late TextEditingController _cari = TextEditingController(text: widget.cari);

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  Widget _pilihan(
    String judul,
    List<String> daftar,
    String nilai,
    ValueChanged<String> ubah,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(judul, style: rtsPetaJudulKecil),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: daftar.map((String satu) {
            final bool aktif = satu == nilai;

            return ChoiceChip(
              label: Text(satu, style: TextStyle(fontSize: 11.5)),
              selected: aktif,
              onSelected: (_) => setState(() => ubah(satu)),
              selectedColor: rtsKsMaroon,
              labelStyle: TextStyle(
                color: aktif ? Colors.white : rtsKsTeks,
                fontSize: 11.5,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(color: aktif ? rtsKsMaroon : rtsKsGaris),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'PENYARING PETA CUSTOMER',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: rtsKsTeks,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _pilihan('Hari kunjungan', rtsPetaHari, _hari,
                  (String n) => _hari = n),
              _pilihan('Frekuensi kunjungan', rtsPetaFrekuensi, _frekuensi,
                  (String n) => _frekuensi = n),
              _pilihan('Jenis customer', rtsPetaJenis, _tipe,
                  (String n) => _tipe = n),
              _pilihan('Status kunjungan', rtsPetaStatusKunjungan, _status,
                  (String n) => _status = n),
              _pilihan('Warna penanda', rtsPetaCaraWarna, _caraWarna,
                  (String n) => _caraWarna = n),
              TextField(
                controller: _cari,
                decoration: const InputDecoration(
                  labelText: 'Cari nama / kode / alamat toko',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                // Catatan: isi kota pencarian dibaca dari _cari.text saat
                // tombol TERAPKAN ditekan, jadi tidak perlu onChanged.
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).pop(<String, dynamic>{
                          'hari': 'Semua',
                          'frekuensi': 'Semua',
                          'tipe': 'Semua',
                          'status': 'Semua',
                          'cari': '',
                          'caraWarna': _caraWarna,
                        });
                      },
                      child: const Text('BERSIHKAN'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: rtsKsMaroon,
                      ),
                      onPressed: () {
                        Navigator.of(context).pop(<String, dynamic>{
                          'hari': _hari,
                          'frekuensi': _frekuensi,
                          'tipe': _tipe,
                          'status': _status,
                          'cari': _cari.text.trim(),
                          'caraWarna': _caraWarna,
                        });
                      },
                      child: const Text('TERAPKAN'),
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

/// Kartu keterangan satu toko (muncul saat penanda ditekan).
class _RtsKartuToko extends StatelessWidget {
  const _RtsKartuToko({
    required this.toko,
    required this.sudah,
    required this.jarakKantor,
    required this.jarakSaya,
    required this.caraWarna,
    required this.onNavigasi,
    required this.onKunjungi,
    required this.onSalin,
  });

  final RtsToko toko;
  final bool sudah;
  final double? jarakKantor;
  final double? jarakSaya;
  final String caraWarna;
  final VoidCallback onNavigasi;
  final VoidCallback onKunjungi;
  final VoidCallback onSalin;

  Widget _baris(String judul, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 108,
            child: Text(judul, style: rtsPetaIsiKecil),
          ),
          Expanded(
            child: Text(
              nilai,
              style: const TextStyle(
                fontSize: 12.5,
                color: rtsKsTeks,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color warna = caraWarna == 'HARI'
        ? rtsPetaWarnaHari(toko.hari)
        : rtsPetaWarnaFrekuensi(toko.kunjungan);

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: warna,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      toko.nama,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: rtsKsTeks,
                      ),
                    ),
                  ),
                  RtsBadgeToko(toko.tipe),
                ],
              ),
              const SizedBox(height: 10),
              _baris('Kode Customer', toko.idCustomer),
              _baris('Alamat', toko.alamat.isEmpty ? '-' : toko.alamat),
              _baris('Hari Kunjungan', toko.hariTeks),
              _baris('Frekuensi', toko.frekuensiTeks),
              _baris('Sales District', toko.district.isEmpty ? '-' : toko.district),
              _baris('Salesman', toko.salesman.isEmpty ? '-' : toko.salesman),
              _baris(
                'Jarak dari Kantor',
                jarakKantor == null ? '-' : rtsPetaJarakTeks(jarakKantor!),
              ),
              _baris(
                'Jarak dari Saya',
                jarakSaya == null ? '-' : rtsPetaJarakTeks(jarakSaya!),
              ),
              _baris(
                'Kunjungan hari ini',
                sudah ? 'Sudah dikunjungi' : 'Belum dikunjungi',
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onSalin,
                      icon: const Icon(Icons.copy_all_rounded, size: 17),
                      label: const Text('SALIN', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: sudah ? rtsKsHijau : rtsKsMaroon,
                      ),
                      onPressed: onKunjungi,
                      icon: Icon(
                        sudah
                            ? Icons.check_circle_rounded
                            : Icons.add_location_alt_outlined,
                        size: 17,
                      ),
                      label: Text(
                        sudah ? 'SUDAH' : 'KUNJUNGI',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: rtsPetaSaya,
                      ),
                      onPressed: onNavigasi,
                      icon: const Icon(Icons.navigation_rounded, size: 17),
                      label: const Text('NAVIGASI', style: TextStyle(fontSize: 12)),
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

/// Tampilan bila daftar toko belum dapat dibaca (mis. belum sinkron / luring).
class RtsPesanUlang extends StatelessWidget {
  const RtsPesanUlang({super.key, required this.pesan, required this.onCoba});

  final String pesan;
  final Future<void> Function() onCoba;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.map_outlined, size: 62, color: rtsKsTeks2),
            const SizedBox(height: 14),
            Text(
              pesan.isEmpty
                  ? 'Daftar toko belum dapat dibaca.'
                  : pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: rtsKsTeks2),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () => unawaited(onCoba()),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('COBA LAGI'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lencana kecil REGULER / GSP.
class RtsBadgeToko extends StatelessWidget {
  const RtsBadgeToko(this.tipe, {super.key});

  final String tipe;

  @override
  Widget build(BuildContext context) {
    final bool gsp = tipe.toUpperCase() == 'GSP';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: gsp ? const Color(0xfffff3e0) : const Color(0xffeef5ee),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: gsp ? rtsKsKuning : rtsKsHijau),
      ),
      child: Text(
        gsp ? 'GSP' : 'REGULER',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: gsp ? rtsKsKuning : rtsKsHijau,
        ),
      ),
    );
  }
}

/// Menyalin teks ke papan klip HP (untuk ditempel ke WhatsApp dan lain-lain).
Future<void> rtsPetaSalinTeks(String teks) async {
  try {
    await Clipboard.setData(ClipboardData(text: teks));
  } catch (_) {
    // papan klip tidak dapat dipakai
  }
}

/// Membaca titik GPS petugas (dipakai RADAR dan RUTE PLAN).
Future<Position?> rtsPetaAmbilLokasi() async {
  try {
    final bool layanan = await Geolocator.isLocationServiceEnabled();

    if (!layanan) return await Geolocator.getLastKnownPosition();

    LocationPermission izin = await Geolocator.checkPermission();

    if (izin == LocationPermission.denied) {
      izin = await Geolocator.requestPermission();
    }

    if (izin == LocationPermission.denied ||
        izin == LocationPermission.deniedForever) {
      return await Geolocator.getLastKnownPosition();
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
  } catch (_) {
    try {
      return await Geolocator.getLastKnownPosition();
    } catch (_) {
      return null;
    }
  }
}

/* ------------------------------------------------------------------------- */
/* BARIS TOKO (dipakai RADAR dan RUTE PLAN)                                  */
/* ------------------------------------------------------------------------- */

class RtsBarisToko extends StatelessWidget {
  const RtsBarisToko({
    super.key,
    required this.nomor,
    required this.toko,
    required this.warna,
    required this.jarak,
    this.jarakSebelum,
    this.arah = '',
    this.sudah = false,
    this.selesai = false,
    this.onNavigasi,
    this.onKunjungi,
    this.onNaik,
    this.onTurun,
    this.onSalin,
  });

  final String nomor;
  final RtsToko toko;
  final Color warna;
  final double jarak;
  final double? jarakSebelum;
  final String arah;
  final bool sudah;
  final bool selesai;
  final VoidCallback? onNavigasi;
  final VoidCallback? onKunjungi;
  final VoidCallback? onNaik;
  final VoidCallback? onTurun;
  final VoidCallback? onSalin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 9),
      decoration: rtsPetaKotak(
        warna: selesai ? const Color(0xfff2f8f3) : Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: warna,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    nomor,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      toko.nama,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: rtsKsTeks,
                        decoration:
                            selesai ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${toko.idCustomer} - ${toko.tipe.toUpperCase()}',
                      style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                    ),
                    if (toko.alamat.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          toko.alamat,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        'Jarak ${rtsPetaJarakTeks(jarak)}'
                        '${arah.isEmpty ? '' : ' - $arah'}'
                        '${jarakSebelum == null ? '' : ' - +${rtsPetaJarakTeks(jarakSebelum!)} dari titik sebelumnya'}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: rtsKsMaroon,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${toko.hariTeks} - ${toko.frekuensiTeks}'
                        '${sudah ? ' - SUDAH DIKUNJUNGI HARI INI' : ''}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: sudah ? rtsKsHijau : rtsKsTeks2,
                          fontWeight:
                              sudah ? FontWeight.w700 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (onNaik != null || onTurun != null)
                Column(
                  children: <Widget>[
                    InkWell(
                      onTap: onNaik,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.keyboard_arrow_up_rounded,
                            size: 20, color: rtsKsTeks2),
                      ),
                    ),
                    InkWell(
                      onTap: onTurun,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.keyboard_arrow_down_rounded,
                            size: 20, color: rtsKsTeks2),
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (onSalin != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSalin,
                    icon: const Icon(Icons.copy_all_rounded, size: 16),
                    label: const Text('SALIN', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              if (onSalin != null) const SizedBox(width: 7),
              if (onKunjungi != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onKunjungi,
                    icon: Icon(
                      sudah
                          ? Icons.check_circle_rounded
                          : Icons.add_location_alt_outlined,
                      size: 16,
                    ),
                    label: Text(
                      sudah ? 'SUDAH' : 'KUNJUNGI',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              if (onKunjungi != null) const SizedBox(width: 7),
              if (onNavigasi != null)
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: rtsPetaSaya),
                    onPressed: onNavigasi,
                    icon: const Icon(Icons.navigation_rounded, size: 16),
                    label: const Text('NAVIGASI', style: TextStyle(fontSize: 11.5)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 2 : RADAR CUSTOMER                                                */
/* ------------------------------------------------------------------------- */

class RtsRadarPage extends StatefulWidget {
  const RtsRadarPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsRadarPage> createState() => _RtsRadarPageState();
}

class _RtsRadarPageState extends State<RtsRadarPage> {
  final MapController _kontrol = MapController();

  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  bool _perluPro = false;

  List<RtsToko> _toko = <RtsToko>[];
  Set<String> _sudah = <String>{};
  Position? _posisi;
  int _radius = 500;
  String _pesanLokasi = '';
  int _sumber = 0;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mulai();
    });
  }

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  Future<void> _mulai() async {
    await rtsPetaSiapkanAkun(
      baseUrl: widget.baseUrl,
      token: widget.token,
      pengguna: widget.pengguna,
    );

    _sumber = await rtsPetaBacaAngka(rtsPetaKunciSumber, 0);

    if (!mounted) return;

    await _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await RtsKasirLokal.aku.kirim('toko_peta');
      final List<dynamic> items =
          hasil['items'] is List ? hasil['items'] as List<dynamic> : <dynamic>[];

      final List<RtsToko> daftar = <RtsToko>[];

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        final RtsToko t = RtsToko.dariPeta(satu.cast<String, dynamic>());

        if (t.adaTitik) daftar.add(t);
      }

      final Map<String, dynamic> kunjungan =
          await RtsKasirLokal.aku.kirim('kunjungan_hari_ini');

      final List<dynamic> idKunjungan = kunjungan['id_customer'] is List
          ? kunjungan['id_customer'] as List<dynamic>
          : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _toko = daftar;
        _sudah = idKunjungan.map((dynamic e) => '$e').toSet();
        _memuat = false;
      });

      await _perbaruiLokasi();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
      });
    }
  }

  Future<void> _perbaruiLokasi() async {
    setState(() {
      _sibuk = true;
      _pesanLokasi = 'Membaca titik GPS...';
    });

    final Position? posisi = await rtsPetaAmbilLokasi();

    if (!mounted) return;

    setState(() {
      _sibuk = false;
      _posisi = posisi ?? _posisi;
      _pesanLokasi = posisi == null
          ? 'Titik GPS belum dapat dibaca. Nyalakan Lokasi pada HP, lalu tekan '
              'PERBARUI LOKASI.'
          : 'Titik GPS terbaca (ketepatan +-${posisi.accuracy.round()} m).';
    });

    if (posisi != null) {
      try {
        _kontrol.move(LatLng(posisi.latitude, posisi.longitude), 15);
      } catch (_) {
        // peta belum siap
      }
    }
  }

  /// Daftar toko beserta jarak dari titik GPS petugas, urut paling dekat.
  List<MapEntry<RtsToko, double>> get _dekat {
    final Position? p = _posisi;

    if (p == null) return <MapEntry<RtsToko, double>>[];

    final List<MapEntry<RtsToko, double>> daftar = <MapEntry<RtsToko, double>>[];

    for (final RtsToko t in _toko) {
      final double jarak =
          rtsPetaJarakMeter(p.latitude, p.longitude, t.latitude, t.longitude);

      if (_radius > 0 && jarak > _radius) continue;

      daftar.add(MapEntry<RtsToko, double>(t, jarak));
    }

    daftar.sort((MapEntry<RtsToko, double> a, MapEntry<RtsToko, double> b) =>
        a.value.compareTo(b.value));

    return daftar;
  }

  Future<void> _tandaiKunjungan(RtsToko t) async {
    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kunjungan_simpan', <String, dynamic>{
        'id_customer': t.idCustomer,
        'nama': t.nama,
        'latitude': _posisi?.latitude ?? 0,
        'longitude': _posisi?.longitude ?? 0,
      });

      if (!mounted) return;

      setState(() => _sudah = <String>{..._sudah, t.idCustomer});

      rtsKsPesan(context, '${hasil['message'] ?? 'Kunjungan tercatat.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  String _teksRadius() {
    if (_radius <= 0) return 'semua toko';

    return rtsPetaJarakTeks(_radius.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Radar Customer'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Perbarui lokasi',
            icon: const Icon(Icons.my_location_rounded),
            onPressed: _sibuk ? null : _perbaruiLokasi,
          ),
        ],
      ),
      body: _bangunIsi(),
    );
  }

  Widget _bangunIsi() {
    if (_perluPro) return RtsKunciPro(pesan: _galat);

    if (_memuat) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_galat.isNotEmpty && _toko.isEmpty) {
      return RtsPesanUlang(pesan: _galat, onCoba: _muat);
    }

    final List<MapEntry<RtsToko, double>> dekat = _dekat;
    final Position? p = _posisi;

    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.radar_rounded, color: rtsKsMaroon, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      p == null
                          ? 'Titik GPS belum ada'
                          : 'Lokasi saya: ${p.latitude.toStringAsFixed(5)}, '
                              '${p.longitude.toStringAsFixed(5)}',
                      style: rtsPetaJudulKecil,
                    ),
                  ),
                  TextButton(
                    onPressed: _sibuk ? null : _perbaruiLokasi,
                    child: const Text('PERBARUI', style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              if (_pesanLokasi.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    _pesanLokasi,
                    style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                  ),
                ),
              Text(
                'Jarak maksimal: ${_teksRadius()} - ${dekat.length} toko ditemukan',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: rtsKsMaroon,
                ),
              ),
              const SizedBox(height: 7),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: rtsPetaRadius.map((int r) {
                    final bool aktif = r == _radius;

                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(
                          r == 0 ? 'Semua' : rtsPetaJarakTeks(r.toDouble()),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: aktif ? Colors.white : rtsKsTeks,
                          ),
                        ),
                        selected: aktif,
                        onSelected: (_) => setState(() => _radius = r),
                        selectedColor: rtsKsMaroon,
                        backgroundColor: Colors.white,
                        side: BorderSide(
                          color: aktif ? rtsKsMaroon : rtsKsGaris,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: Stack(
            children: <Widget>[
              FlutterMap(
                mapController: _kontrol,
                options: MapOptions(
                  initialCenter: p == null
                      ? const LatLng(3.5952, 98.6722)
                      : LatLng(p.latitude, p.longitude),
                  initialZoom: 14,
                  minZoom: 4,
                  maxZoom: 18,
                  backgroundColor: rtsPetaAir,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: <Widget>[
                  TileLayer(
                    key: ValueKey<String>('ubin-radar-$_sumber'),
                    urlTemplate: rtsPetaSumber[
                            _sumber < 0 || _sumber >= rtsPetaSumber.length
                                ? 0
                                : _sumber]
                        .url,
                    userAgentPackageName: 'com.bene.rts_panel_app',
                    maxNativeZoom: 19,
                  ),
                  if (p != null && _radius > 0)
                    CircleLayer(
                      circles: <CircleMarker<Object>>[
                        CircleMarker<Object>(
                          point: LatLng(p.latitude, p.longitude),
                          radius: _radius.toDouble(),
                          useRadiusInMeter: true,
                          color: const Color.fromRGBO(29, 111, 184, 0.13),
                          borderColor: rtsPetaSaya,
                          borderStrokeWidth: 1.5,
                        ),
                      ],
                    ),
                  MarkerLayer(markers: _penanda(p, dekat)),
                ],
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: rtsPetaAtribusi(
                  rtsPetaSumber[_sumber < 0 || _sumber >= rtsPetaSumber.length
                          ? 0
                          : _sumber]
                      .nama,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: dekat.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      p == null
                          ? 'Titik GPS belum terbaca. Tekan PERBARUI LOKASI '
                              'supaya daftar toko terdekat dapat dihitung.'
                          : 'Belum ada toko dalam jarak ${_teksRadius()}. '
                              'Pilih jarak yang lebih besar atau tekan PERBARUI '
                              'LOKASI.',
                      textAlign: TextAlign.center,
                      style: rtsPetaIsiKecil,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                  itemCount: dekat.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final RtsToko t = dekat[i].key;
                    final double jarak = dekat[i].value;
                    final String arah = p == null
                        ? ''
                        : rtsPetaArah(rtsPetaBearing(p.latitude, p.longitude,
                            t.latitude, t.longitude));

                    return RtsBarisToko(
                      nomor: '${i + 1}',
                      toko: t,
                      warna: rtsPetaWarnaFrekuensi(t.kunjungan),
                      jarak: jarak,
                      arah: arah,
                      sudah: _sudah.contains(t.idCustomer),
                      onSalin: () async {
                        await rtsPetaSalinTeks(
                          '${t.nama} - ${t.idCustomer} - '
                          '${rtsPetaJarakTeks(jarak)}',
                        );

                        if (mounted) {
                          rtsKsPesan(context, 'Keterangan toko disalin.');
                        }
                      },
                      onKunjungi: () => _tandaiKunjungan(t),
                      onNavigasi: () => unawaited(
                        rtsPetaNavigasi(context, t.latitude, t.longitude, t.nama),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  List<Marker> _penanda(
    Position? p,
    List<MapEntry<RtsToko, double>> dekat,
  ) {
    final List<Marker> penanda = <Marker>[];

    if (p != null) {
      penanda.add(
        Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 44,
          height: 44,
          child: rtsPetaPenanda(label: '', warna: rtsPetaSaya, saya: true),
        ),
      );
    }

    final int maks = dekat.length > 80 ? 80 : dekat.length;

    for (int i = 0; i < maks; i++) {
      final RtsToko t = dekat[i].key;

      penanda.add(
        Marker(
          point: t.titik,
          width: 46,
          height: 46,
          child: rtsPetaPenanda(
            label: t.isGsp ? 'G' : '',
            warna: rtsPetaWarnaFrekuensi(t.kunjungan),
            gsp: t.isGsp,
            sudah: _sudah.contains(t.idCustomer),
          ),
        ),
      );
    }

    return penanda;
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 3 : RUTE PLAN                                                     */
/* ------------------------------------------------------------------------- */

class RtsRutePage extends StatefulWidget {
  const RtsRutePage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsRutePage> createState() => _RtsRutePageState();
}

class _RtsRutePageState extends State<RtsRutePage> {
  final MapController _kontrol = MapController();

  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  bool _perluPro = false;

  List<RtsToko> _toko = <RtsToko>[];
  List<RtsKantor> _kantor = <RtsKantor>[];
  Set<String> _sudah = <String>{};
  Set<String> _selesai = <String>{};

  int _pilihKantor = 0;
  late String _hari = rtsPetaNamaHari(DateTime.now());
  String _frekuensi = 'Semua';
  String _caraWarna = 'KUNJUNGAN';
  bool _dariKantor = true;

  List<String> _urutanManual = <String>[];

  bool _pensil = false;
  int _warnaPensil = 0;
  List<LatLng> _goresan = <LatLng>[];
  List<RtsGoresan> _coretan = <RtsGoresan>[];
  List<RtsGoresan> _tersimpan = <RtsGoresan>[];
  Offset? _layarTerakhir;
  int _sumber = 0;

  double? _sayaLat;
  double? _sayaLng;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mulai();
    });
  }

  @override
  void dispose() {
    _kontrol.dispose();
    super.dispose();
  }

  Future<void> _mulai() async {
    await rtsPetaSiapkanAkun(
      baseUrl: widget.baseUrl,
      token: widget.token,
      pengguna: widget.pengguna,
    );

    _sumber = await rtsPetaBacaAngka(rtsPetaKunciSumber, 0);
    _warnaPensil = await rtsPetaBacaAngka(rtsPetaKunciPensil, 0);

    if (!mounted) return;

    await _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await RtsKasirLokal.aku.kirim('toko_peta');
      final List<dynamic> items =
          hasil['items'] is List ? hasil['items'] as List<dynamic> : <dynamic>[];

      final List<RtsToko> daftar = <RtsToko>[];

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        final RtsToko t = RtsToko.dariPeta(satu.cast<String, dynamic>());

        if (t.adaTitik) daftar.add(t);
      }

      final Map<String, dynamic> kunjungan =
          await RtsKasirLokal.aku.kirim('kunjungan_hari_ini');

      final List<dynamic> idKunjungan = kunjungan['id_customer'] is List
          ? kunjungan['id_customer'] as List<dynamic>
          : <dynamic>[];

      final Map<String, dynamic> hasilKantor =
          await RtsKasirLokal.aku.kirim('kantor_daftar');
      final Map<String, dynamic> hasilGores =
          await RtsKasirLokal.aku.kirim('gores_daftar');

      final List<RtsGoresan> goresan = RtsGoresan.dariDaftar(
        hasilGores['items'] is List
            ? hasilGores['items'] as List<dynamic>
            : <dynamic>[],
      );

      if (!mounted) return;

      setState(() {
        _toko = daftar;
        _kantor = _kantorDari(hasilKantor['items']);
        _sudah = idKunjungan.map((dynamic e) => '$e').toSet();
        _tersimpan = goresan;
        _memuat = false;
      });

      if (daftar.isEmpty) {
        await _segarkanToko(diam: true);
      } else {
        _aturTampilan();
      }
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
      });
    }
  }

  List<RtsKantor> _kantorDari(dynamic items) {
    final List<RtsKantor> hasil = <RtsKantor>[];

    if (items is List) {
      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        hasil.add(RtsKantor.dariPeta(satu.cast<String, dynamic>()));
      }
    }

    return hasil;
  }

  Future<void> _segarkanToko({bool diam = false}) async {
    if (!diam) setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('toko_segarkan');

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Daftar toko tersimpan.'}');

      setState(() => _sibuk = false);

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
      });
    }
  }

  Future<void> _segarkanKantor({bool diam = false}) async {
    if (!diam) setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kantor_segarkan');

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _kantor = _kantorDari(hasil['items']);
      });

      if (!diam) {
        rtsKsPesan(context, '${hasil['message'] ?? 'Titik kantor disegarkan.'}');
      }
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      if (!diam) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  RtsKantor? get _kantorDipilih {
    final List<RtsKantor> ada = _kantor.where((RtsKantor k) => k.adaTitik).toList();

    if (ada.isEmpty) return null;

    final int i = _pilihKantor < 0 || _pilihKantor >= ada.length ? 0 : _pilihKantor;

    return ada[i];
  }

  /// Toko yang masuk rencana rute (sudah disaring menurut hari & frekuensi).
  List<RtsToko> _saring() {
    return _toko.where((RtsToko t) {
      if (!rtsPetaHariCocok(t.hari, _hari)) return false;
      if (!rtsPetaFrekuensiCocok(t.kunjungan, _frekuensi)) return false;

      return true;
    }).toList();
  }

  /// Daftar rencana rute: urut dari titik kantor (atau dari lokasi petugas),
  /// toko yang sudah ditandai SELESAI turun ke bawah.
  List<RtsToko> get _rencana {
    final List<RtsToko> daftar = _saring();
    final RtsKantor? kantor = _kantorDipilih;

    double jarak(RtsToko t) {
      if (_dariKantor && kantor != null) {
        return rtsPetaJarakMeter(
          kantor.latitude,
          kantor.longitude,
          t.latitude,
          t.longitude,
        );
      }

      if (_sayaLat != null && _sayaLng != null) {
        return rtsPetaJarakMeter(_sayaLat!, _sayaLng!, t.latitude, t.longitude);
      }

      if (kantor != null) {
        return rtsPetaJarakMeter(
          kantor.latitude,
          kantor.longitude,
          t.latitude,
          t.longitude,
        );
      }

      return 0;
    }

    daftar.sort((RtsToko a, RtsToko b) {
      if (_urutanManual.isEmpty) {
        return jarak(a).compareTo(jarak(b));
      }

      final int ia = _urutanManual.indexOf(a.idCustomer);
      final int ib = _urutanManual.indexOf(b.idCustomer);

      if (ia < 0 && ib < 0) return jarak(a).compareTo(jarak(b));
      if (ia < 0) return 1;
      if (ib < 0) return -1;

      return ia.compareTo(ib);
    });

    final List<RtsToko> belum = <RtsToko>[];
    final List<RtsToko> sudah = <RtsToko>[];

    for (final RtsToko t in daftar) {
      if (_selesai.contains(t.idCustomer)) {
        sudah.add(t);
      } else {
        belum.add(t);
      }
    }

    return <RtsToko>[...belum, ...sudah];
  }

  double _jarakKe(RtsToko t) {
    final RtsKantor? kantor = _kantorDipilih;

    if (_dariKantor && kantor != null) {
      return rtsPetaJarakMeter(
        kantor.latitude,
        kantor.longitude,
        t.latitude,
        t.longitude,
      );
    }

    if (_sayaLat != null && _sayaLng != null) {
      return rtsPetaJarakMeter(_sayaLat!, _sayaLng!, t.latitude, t.longitude);
    }

    if (kantor != null) {
      return rtsPetaJarakMeter(
        kantor.latitude,
        kantor.longitude,
        t.latitude,
        t.longitude,
      );
    }

    return 0;
  }

  double _panjangRute(List<RtsToko> rencana) {
    if (rencana.isEmpty) return 0;

    final RtsKantor? kantor = _kantorDipilih;
    double total = 0;
    double? latSebelum;
    double? lngSebelum;

    if (kantor != null && _dariKantor) {
      latSebelum = kantor.latitude;
      lngSebelum = kantor.longitude;
    }

    for (final RtsToko t in rencana) {
      if (latSebelum != null && lngSebelum != null) {
        total += rtsPetaJarakMeter(latSebelum, lngSebelum, t.latitude, t.longitude);
      }

      latSebelum = t.latitude;
      lngSebelum = t.longitude;
    }

    return total;
  }

  void _aturTampilan() {
    final List<LatLng> titik = <LatLng>[];

    final RtsKantor? kantor = _kantorDipilih;

    if (kantor != null) titik.add(kantor.titik);

    for (final RtsToko t in _rencana) {
      titik.add(t.titik);
    }

    if (titik.isEmpty) return;

    double minLat = titik.first.latitude;
    double maksLat = titik.first.latitude;
    double minLng = titik.first.longitude;
    double maksLng = titik.first.longitude;

    for (final LatLng l in titik) {
      minLat = math.min(minLat, l.latitude);
      maksLat = math.max(maksLat, l.latitude);
      minLng = math.min(minLng, l.longitude);
      maksLng = math.max(maksLng, l.longitude);
    }

    final LatLng pusat = LatLng((minLat + maksLat) / 2, (minLng + maksLng) / 2);
    final double sebaran = math.max(maksLat - minLat, maksLng - minLng);

    double zoom = 15;

    if (sebaran > 1.5) {
      zoom = 8;
    } else if (sebaran > 0.7) {
      zoom = 9;
    } else if (sebaran > 0.35) {
      zoom = 10;
    } else if (sebaran > 0.18) {
      zoom = 11;
    } else if (sebaran > 0.09) {
      zoom = 12;
    } else if (sebaran > 0.045) {
      zoom = 13;
    } else if (sebaran > 0.02) {
      zoom = 14;
    }

    try {
      _kontrol.move(pusat, zoom);
    } catch (_) {
      // peta belum siap
    }
  }

  Color _warnaToko(RtsToko t) {
    if (_selesai.contains(t.idCustomer)) return rtsKsHijau;
    if (_sudah.contains(t.idCustomer)) return rtsPetaWeekly;

    if (_caraWarna == 'HARI') return rtsPetaWarnaHari(t.hari);

    return rtsPetaWarnaFrekuensi(t.kunjungan);
  }

  /* ------------------------------------------------------------- kunjungan */

  Future<void> _tandaiKunjungan(RtsToko t) async {
    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kunjungan_simpan', <String, dynamic>{
        'id_customer': t.idCustomer,
        'nama': t.nama,
        'latitude': _sayaLat ?? 0,
        'longitude': _sayaLng ?? 0,
      });

      if (!mounted) return;

      setState(() {
        _sudah = <String>{..._sudah, t.idCustomer};
        _selesai = <String>{..._selesai, t.idCustomer};
      });

      rtsKsPesan(context, '${hasil['message'] ?? 'Kunjungan tercatat.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  void _ubahUrutan(int index, int geser) {
    final List<RtsToko> rencana = _rencana;
    final int tujuan = index + geser;

    if (tujuan < 0 || tujuan >= rencana.length) return;

    final List<String> urutan = <String>[
      for (final RtsToko t in rencana) t.idCustomer,
    ];

    final String pindah = urutan[index];

    urutan[index] = urutan[tujuan];
    urutan[tujuan] = pindah;

    setState(() => _urutanManual = urutan);
  }

  /* ---------------------------------------------------------------- pensil */

  LatLng? _titikLayar(Offset pos) {
    try {
      return _kontrol.camera.screenOffsetToLatLng(pos);
    } catch (_) {
      return null;
    }
  }

  void _mulaiGores(Offset pos) {
    final LatLng? titik = _titikLayar(pos);

    if (titik == null) return;

    setState(() {
      _goresan = <LatLng>[titik];
      _layarTerakhir = pos;
    });
  }

  void _lanjutGores(Offset pos) {
    final Offset? terakhir = _layarTerakhir;

    if (terakhir != null && (pos - terakhir).distance < 3) return;

    final LatLng? titik = _titikLayar(pos);

    if (titik == null) return;

    setState(() {
      _goresan = <LatLng>[..._goresan, titik];
      _layarTerakhir = pos;
    });
  }

  void _selesaiGores() {
    if (_goresan.length < 2) {
      setState(() {
        _goresan = <LatLng>[];
        _layarTerakhir = null;
      });
      return;
    }

    setState(() {
      _coretan = <RtsGoresan>[
        ..._coretan,
        RtsGoresan(
          id: 0,
          nama: 'Goresan baru ${_coretan.length + 1}',
          warna: rtsPetaWarnaPensilNilai[
              _warnaPensil % rtsPetaWarnaPensilNilai.length],
          tebal: 4,
          titik: List<LatLng>.from(_goresan),
        ),
      ];
      _goresan = <LatLng>[];
      _layarTerakhir = null;
    });
  }

  void _batalkanGoresTerakhir() {
    if (_goresan.isNotEmpty) {
      setState(() {
        _goresan = <LatLng>[];
        _layarTerakhir = null;
      });
      return;
    }

    if (_coretan.isNotEmpty) {
      setState(() {
        _coretan = _coretan.sublist(0, _coretan.length - 1);
      });
      return;
    }

    if (_tersimpan.isNotEmpty) {
      setState(() {
        _tersimpan = _tersimpan.sublist(0, _tersimpan.length - 1);
      });

      rtsKsPesan(context, 'Goresan terakhir disembunyikan dari peta.');
      return;
    }

    rtsKsPesan(context, 'Belum ada goresan untuk dibatalkan.');
  }

  Future<void> _simpanGoresan() async {
    if (_coretan.isEmpty) {
      rtsKsPesan(
        context,
        'Belum ada goresan baru. Geser jari pada peta untuk menggambar rute.',
        galat: true,
      );
      return;
    }

    final TextEditingController nama = TextEditingController(
      text: 'Rute ${rtsPetaTanggalTeks(DateTime.now())}',
    );

    final bool? jalan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Simpan Goresan Rute',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${_coretan.length} goresan akan disimpan di HP dan dapat '
              'dimuat kembali kapan saja.',
              style: rtsPetaIsiKecil,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nama,
              decoration: const InputDecoration(
                labelText: 'Nama goresan',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('SIMPAN'),
          ),
        ],
      ),
    );

    if (jalan != true) return;

    setState(() => _sibuk = true);

    try {
      int jumlah = 0;

      for (int i = 0; i < _coretan.length; i++) {
        final RtsGoresan g = _coretan[i];

        await RtsKasirLokal.aku.kirim('gores_simpan', <String, dynamic>{
          'nama': _coretan.length == 1
              ? nama.text.trim()
              : '${nama.text.trim()} ${i + 1}',
          'warna': g.warna,
          'tebal': g.tebal,
          'titik': <List<double>>[
            for (final LatLng l in g.titik) <double>[l.latitude, l.longitude],
          ],
        });

        jumlah++;
      }

      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('gores_daftar');

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _coretan = <RtsGoresan>[];
        _tersimpan = RtsGoresan.dariDaftar(
          hasil['items'] is List ? hasil['items'] as List<dynamic> : <dynamic>[],
        );
      });

      rtsKsPesan(context, '$jumlah goresan rute tersimpan di HP.');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _hapusGoresan() async {
    if (_coretan.isEmpty && _tersimpan.isEmpty) {
      rtsKsPesan(context, 'Belum ada goresan pada peta.');
      return;
    }

    final String? pilih = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus Goresan Rute',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Pilih HAPUS DARI LAYAR untuk menyembunyikan goresan sementara, '
          'atau HAPUS DARI HP untuk membuang seluruh goresan yang tersimpan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('BATAL'),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('LAYAR'),
            child: const Text('HAPUS DARI LAYAR'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop('HP'),
            child: const Text('HAPUS DARI HP'),
          ),
        ],
      ),
    );

    if (pilih == null || pilih == 'BATAL') return;

    if (pilih == 'LAYAR') {
      setState(() {
        _coretan = <RtsGoresan>[];
        _goresan = <LatLng>[];
        for (final RtsGoresan g in _tersimpan) {
          g.tampil = false;
        }
      });

      rtsKsPesan(context, 'Goresan disembunyikan dari peta.');
      return;
    }

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('gores_hapus_semua');

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _coretan = <RtsGoresan>[];
        _goresan = <LatLng>[];
        _tersimpan = <RtsGoresan>[];
      });

      rtsKsPesan(context, '${hasil['message'] ?? 'Goresan dihapus.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _bukaGoresanTersimpan() async {
    if (_tersimpan.isEmpty) {
      rtsKsPesan(context, 'Belum ada goresan rute yang tersimpan di HP.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter ubah) {
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('GORESAN RUTE TERSIMPAN', style: rtsPetaJudulKecil),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    'Ketuk nama goresan untuk menampilkan atau '
                    'menyembunyikannya pada peta.',
                    style: rtsPetaIsiKecil,
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _tersimpan.map((RtsGoresan g) {
                      return ListTile(
                        leading: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: g.warnaAsli,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: Text(
                          g.nama.isEmpty ? 'Goresan' : g.nama,
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: Text(
                          '${g.titik.length} titik',
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(
                              g.tampil
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              color: g.tampil ? rtsKsHijau : rtsKsTeks2,
                            ),
                            IconButton(
                              tooltip: 'Hapus',
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: rtsKsMerah),
                              onPressed: () async {
                                try {
                                  await RtsKasirLokal.aku.kirim(
                                    'gores_hapus',
                                    <String, dynamic>{'id': g.id},
                                  );

                                  if (!mounted) return;

                                  setState(() {
                                    _tersimpan = _tersimpan
                                        .where((RtsGoresan x) => x.id != g.id)
                                        .toList();
                                  });

                                  ubah(() {});
                                } on RtsKasirGalat catch (e) {
                                  rtsKsPesan(ctx2, e.pesan, galat: true);
                                }
                              },
                            ),
                          ],
                        ),
                        onTap: () {
                          setState(() => g.tampil = !g.tampil);
                          ubah(() {});
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /* ----------------------------------------------------------- daftar plan */

  String _teksRencana(List<RtsToko> rencana, {required bool lengkap}) {
    final RtsKantor? kantor = _kantorDipilih;
    final StringBuffer tulis = StringBuffer();

    if (lengkap) {
      tulis.writeln('RENCANA RUTE KUNJUNGAN');
      tulis.writeln('Tanggal    : ${rtsPetaTanggalTeks(DateTime.now())} '
          '(${rtsPetaNamaHari(DateTime.now())})');
      tulis.writeln('Sales      : ${RtsKasirLokal.aku.namaSales} '
          '(${RtsKasirLokal.aku.idSales})');
      tulis.writeln('Kantor     : ${kantor == null ? 'belum dititikkan' : kantor.nama}');

      if (kantor != null) {
        tulis.writeln('Titik awal : ${kantor.latitude.toStringAsFixed(5)}, '
            '${kantor.longitude.toStringAsFixed(5)}');
      }

      tulis.writeln('Hari       : $_hari');
      tulis.writeln('Frekuensi  : $_frekuensi');
      tulis.writeln('Jumlah     : ${rencana.length} toko');
      tulis.writeln('Panjang rute: +-${rtsPetaJarakTeks(_panjangRute(rencana))}');
      tulis.writeln('');

      double? latSebelum = kantor != null && _dariKantor ? kantor.latitude : null;
      double? lngSebelum = kantor != null && _dariKantor ? kantor.longitude : null;

      for (int i = 0; i < rencana.length; i++) {
        final RtsToko t = rencana[i];
        final StringBuffer baris = StringBuffer();

        baris.write('${i + 1}. ${t.nama}  |  ${t.idCustomer}');

        if (latSebelum != null && lngSebelum != null) {
          final double jarak = rtsPetaJarakMeter(
            latSebelum,
            lngSebelum,
            t.latitude,
            t.longitude,
          );

          baris.write('  |  ${rtsPetaJarakTeks(jarak)} dari titik sebelumnya');
        }

        tulis.writeln(baris.toString());
        tulis.writeln('    ${t.alamat.isEmpty ? '-' : t.alamat}');
        tulis.writeln('    ${t.hariTeks} - ${t.frekuensiTeks}'
            '${_selesai.contains(t.idCustomer) ? ' - SUDAH' : ''}');

        latSebelum = t.latitude;
        lngSebelum = t.longitude;
      }

      return tulis.toString();
    }

    tulis.writeln('DAFTAR TOKO KUNJUNGAN');
    tulis.writeln('Hari: $_hari - Frekuensi: $_frekuensi');
    tulis.writeln('');

    for (int i = 0; i < rencana.length; i++) {
      tulis.writeln('${i + 1}. ${rencana[i].nama} | ${rencana[i].idCustomer}');
    }

    return tulis.toString();
  }

  Future<void> _bukaDaftarPlan() async {
    final List<RtsToko> rencana = _rencana;

    if (rencana.isEmpty) {
      rtsKsPesan(
        context,
        'Belum ada toko pada rencana rute. Ubah pilihan hari atau frekuensi.',
        galat: true,
      );
      return;
    }

    final TextEditingController lengkap =
        TextEditingController(text: _teksRencana(rencana, lengkap: true));
    final TextEditingController ringkas =
        TextEditingController(text: _teksRencana(rencana, lengkap: false));

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Daftar Rencana Rute',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 380,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: <Widget>[
                const TabBar(
                  labelColor: rtsKsMaroon,
                  indicatorColor: rtsKsMaroon,
                  tabs: <Widget>[
                    Tab(text: 'LENGKAP'),
                    Tab(text: 'NAMA & KODE'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      SingleChildScrollView(
                        child: TextField(
                          controller: lengkap,
                          maxLines: null,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                      SingleChildScrollView(
                        child: TextField(
                          controller: ringkas,
                          maxLines: null,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () async {
              await rtsPetaSalinTeks(lengkap.text);

              if (ctx.mounted) rtsKsPesan(ctx, 'Daftar lengkap disalin.');
            },
            child: const Text('SALIN LENGKAP'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () async {
              await rtsPetaSalinTeks(ringkas.text);

              if (ctx.mounted) rtsKsPesan(ctx, 'Nama & kode disalin.');
            },
            child: const Text('SALIN NAMA & KODE'),
          ),
        ],
      ),
    );

    lengkap.dispose();
    ringkas.dispose();
  }

  Future<void> _bukaRuteGoogle(List<RtsToko> rencana) async {
    final RtsKantor? kantor = _kantorDipilih;

    if (rencana.isEmpty) {
      rtsKsPesan(context, 'Belum ada toko pada rencana rute.', galat: true);
      return;
    }

    if (kantor == null) {
      rtsKsPesan(
        context,
        'Titik kantor belum ada, jadi rute belum dapat dibuka. Minta Admin '
        'menitikkan Lokasi Kantor lebih dahulu.',
        galat: true,
      );
      return;
    }

    final List<RtsToko> pakai = rencana.take(10).toList();

    final List<String> jalan = <String>[];

    for (int i = 0; i < pakai.length - 1; i++) {
      jalan.add('${pakai[i].latitude},${pakai[i].longitude}');
    }

    final Uri uri = Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'origin': '${kantor.latitude},${kantor.longitude}',
      'destination': pakai.length == 1
          ? '${pakai.first.latitude},${pakai.first.longitude}'
          : '${pakai.last.latitude},${pakai.last.longitude}',
      'travelmode': 'driving',
      if (jalan.isNotEmpty) 'waypoints': jalan.join('|'),
    });

    try {
      final bool dibuka =
          await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (dibuka) return;
    } catch (_) {
      // lanjut ke pesan
    }

    if (!mounted) return;

    rtsKsPesan(
      context,
      'Rute tidak dapat dibuka. Pastikan Google Maps terpasang di HP.',
      galat: true,
    );
  }

  /* ------------------------------------------------------------------ peta */

  List<Polyline<Object>> _garisRute(List<RtsToko> rencana) {
    final List<Polyline<Object>> garis = <Polyline<Object>>[];
    final RtsKantor? kantor = _kantorDipilih;

    // Garis goresan pensil (tersimpan + yang baru digambar).
    for (final RtsGoresan g in _tersimpan) {
      if (!g.tampil || g.titik.length < 2) continue;

      garis.add(
        Polyline<Object>(
          points: g.titik,
          color: g.warnaAsli,
          strokeWidth: g.tebal,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      );
    }

    for (final RtsGoresan g in _coretan) {
      if (g.titik.length < 2) continue;

      garis.add(
        Polyline<Object>(
          points: g.titik,
          color: g.warnaAsli,
          strokeWidth: g.tebal,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      );
    }

    if (_goresan.length >= 2) {
      garis.add(
        Polyline<Object>(
          points: List<LatLng>.from(_goresan),
          color: rtsPetaPensilWarna(_warnaPensil),
          strokeWidth: 4,
          borderColor: Colors.white,
          borderStrokeWidth: 1,
        ),
      );
    }

    // Garis rencana kunjungan (kantor -> toko 1 -> toko 2 -> ...).
    final List<LatLng> rencana = <LatLng>[];

    if (kantor != null) rencana.add(kantor.titik);

    for (final RtsToko t in _rencana) {
      if (_selesai.contains(t.idCustomer)) continue;

      rencana.add(t.titik);
    }

    if (rencana.length >= 2) {
      garis.add(
        Polyline<Object>(
          points: rencana,
          color: rtsKsMaroon,
          strokeWidth: 4,
          borderColor: Colors.white,
          borderStrokeWidth: 1.5,
        ),
      );
    }

    return garis;
  }

  List<Marker> _penanda(List<RtsToko> rencana) {
    final List<Marker> penanda = <Marker>[];
    final RtsKantor? kantor = _kantorDipilih;

    if (kantor != null) {
      penanda.add(
        Marker(
          point: kantor.titik,
          width: 46,
          height: 46,
          child: rtsPetaPenanda(
            label: 'K',
            warna: rtsPetaKantor,
            kantor: true,
          ),
        ),
      );
    }

    if (_sayaLat != null && _sayaLng != null) {
      penanda.add(
        Marker(
          point: LatLng(_sayaLat!, _sayaLng!),
          width: 44,
          height: 44,
          child: rtsPetaPenanda(label: '', warna: rtsPetaSaya, saya: true),
        ),
      );
    }

    for (int i = 0; i < rencana.length; i++) {
      final RtsToko t = rencana[i];

      penanda.add(
        Marker(
          point: t.titik,
          width: 46,
          height: 46,
          child: rtsPetaPenanda(
            label: '${i + 1}',
            warna: _warnaToko(t),
            gsp: t.isGsp,
            sudah: _sudah.contains(t.idCustomer),
          ),
        ),
      );
    }

    return penanda;
  }

  /* -------------------------------------------------------------------- ui */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Rute Plan'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Pensil rute',
            icon: Icon(
              _pensil ? Icons.edit_rounded : Icons.edit_outlined,
              color: _pensil ? rtsKsKuning : Colors.white,
            ),
            onPressed: () => setState(() => _pensil = !_pensil),
          ),
          IconButton(
            tooltip: 'Lokasi kantor',
            icon: const Icon(Icons.business_rounded),
            onPressed: () => unawaited(_bukaLokasiKantor()),
          ),
          IconButton(
            tooltip: 'Segarkan',
            icon: const Icon(Icons.sync_rounded),
            onPressed: _sibuk ? null : () => _segarkanToko(),
          ),
        ],
      ),
      body: _bangunIsi(),
    );
  }

  Future<void> _bukaLokasiKantor() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => RtsKantorPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          pengguna: widget.pengguna,
          districtTersedia: _toko
              .map((RtsToko t) => t.district.trim())
              .where((String d) => d.isNotEmpty)
              .toSet()
              .toList(),
        ),
      ),
    );

    if (!mounted) return;

    await _segarkanKantor(diam: true);
  }

  Widget _bangunIsi() {
    if (_perluPro) return RtsKunciPro(pesan: _galat);

    if (_memuat) return const Center(child: CircularProgressIndicator());

    if (_galat.isNotEmpty && _toko.isEmpty) {
      return RtsPesanUlang(pesan: _galat, onCoba: _muat);
    }

    final List<RtsToko> rencana = _rencana;
    final RtsKantor? kantor = _kantorDipilih;

    return Column(
      children: <Widget>[
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(Icons.business_rounded,
                      size: 17, color: rtsPetaKantor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      kantor == null
                          ? 'Titik kantor belum ada'
                          : 'Awal rute: ${kantor.nama}',
                      style: rtsPetaJudulKecil,
                    ),
                  ),
                  TextButton(
                    onPressed: _sibuk ? null : () => _segarkanKantor(),
                    child: const Text('MUAT KANTOR',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
              if (kantor == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    RtsKasirLokal.aku.pengelola
                        ? 'ADMIN perlu menitikkan Lokasi Kantor / Mitra lebih '
                            'dahulu (tombol gedung di kanan atas). Sesudah itu '
                            'urutan toko dari kantor dapat dihitung.'
                        : 'Lokasi kantor / mitra belum dititikkan ADMIN. Minta '
                            'ADMIN mengisi titik kantor supaya urutan rute dari '
                            'kantor dapat dihitung.',
                    style: const TextStyle(fontSize: 11, color: rtsKsKuning),
                  ),
                ),
              if (_kantor.length > 1)
                DropdownButton<int>(
                  isExpanded: true,
                  value: _pilihKantor,
                  style: const TextStyle(fontSize: 12, color: rtsKsTeks),
                  items: _kantor.where((RtsKantor k) => k.adaTitik).toList()
                      .asMap()
                      .entries
                      .map((MapEntry<int, RtsKantor> e) {
                    return DropdownMenuItem<int>(
                      value: e.key,
                      child: Text('Kantor: ${e.value.nama}'),
                    );
                  }).toList(),
                  onChanged: (int? nilai) {
                    if (nilai == null) return;

                    setState(() {
                      _pilihKantor = nilai;
                      _urutanManual = <String>[];
                    });

                    _aturTampilan();
                  },
                ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final String h in rtsPetaHari)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            h,
                            style: TextStyle(
                              fontSize: 11,
                              color: _hari == h ? Colors.white : rtsKsTeks,
                            ),
                          ),
                          selected: _hari == h,
                          onSelected: (_) {
                            setState(() {
                              _hari = h;
                              _urutanManual = <String>[];
                            });
                            _aturTampilan();
                          },
                          selectedColor: rtsKsMaroon,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _hari == h ? rtsKsMaroon : rtsKsGaris,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (final String f in rtsPetaFrekuensi)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(
                            f == 'Bi-Weekly Ganjil' ? 'BW Ganjil' : (f == 'Bi-Weekly Genap' ? 'BW Genap' : f),
                            style: TextStyle(
                              fontSize: 11,
                              color: _frekuensi == f ? Colors.white : rtsKsTeks,
                            ),
                          ),
                          selected: _frekuensi == f,
                          onSelected: (_) {
                            setState(() {
                              _frekuensi = f;
                              _urutanManual = <String>[];
                            });
                            _aturTampilan();
                          },
                          selectedColor: rtsPetaGanjil,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: _frekuensi == f ? rtsPetaGanjil : rtsKsGaris,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${rencana.length} toko - panjang rute '
                      '+-${rtsPetaJarakTeks(_panjangRute(rencana))}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: rtsKsMaroon,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _caraWarna = _caraWarna == 'HARI' ? 'KUNJUNGAN' : 'HARI';
                    }),
                    icon: const Icon(Icons.palette_outlined, size: 16),
                    label: Text(
                      _caraWarna == 'HARI' ? 'WARNA: HARI' : 'WARNA: FREKUENSI',
                      style: const TextStyle(fontSize: 10.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_pensil)
          Container(
            width: double.infinity,
            color: const Color(0xfffff4e0),
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'MODE PENSIL MENYALA - geser jari pada peta untuk menggambar '
                  'garis rute perjalanan. Peta tidak dapat digeser; pakai '
                  'tombol + dan - untuk memperbesar.',
                  style: TextStyle(fontSize: 11, color: rtsKsKuning),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    for (int i = 0; i < rtsPetaWarnaPensilNilai.length; i++)
                      GestureDetector(
                        onTap: () async {
                          setState(() => _warnaPensil = i);

                          await rtsPetaTulisAngka(rtsPetaKunciPensil, i);
                        },
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Color(rtsPetaWarnaPensilNilai[i]),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _warnaPensil == i
                                  ? rtsKsTeks
                                  : Colors.white,
                              width: _warnaPensil == i ? 3 : 2,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Text(
                      '${_coretan.length} goresan baru',
                      style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _tombolPensil('BATALKAN', Icons.undo_rounded,
                          _batalkanGoresTerakhir),
                      _tombolPensil('SIMPAN GORESAN', Icons.save_outlined,
                          () => unawaited(_simpanGoresan())),
                      _tombolPensil('GORESAN TERSIMPAN', Icons.folder_open_rounded,
                          () => unawaited(_bukaGoresanTersimpan())),
                      _tombolPensil('HAPUS GORESAN', Icons.delete_outline_rounded,
                          () => unawaited(_hapusGoresan())),
                    ],
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          flex: 5,
          child: Stack(
            children: <Widget>[
              FlutterMap(
                mapController: _kontrol,
                options: MapOptions(
                  initialCenter: kantor?.titik ?? const LatLng(3.5952, 98.6722),
                  initialZoom: 12,
                  minZoom: 4,
                  maxZoom: 18,
                  backgroundColor: rtsPetaAir,
                  interactionOptions: InteractionOptions(
                    flags: _pensil
                        ? InteractiveFlag.none
                        : InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: <Widget>[
                  TileLayer(
                    key: ValueKey<String>('ubin-rute-$_sumber'),
                    urlTemplate: rtsPetaSumber[
                            _sumber < 0 || _sumber >= rtsPetaSumber.length
                                ? 0
                                : _sumber]
                        .url,
                    userAgentPackageName: 'com.bene.rts_panel_app',
                    maxNativeZoom: 19,
                  ),
                  PolylineLayer<Object>(polylines: _garisRute(rencana)),
                  MarkerLayer(markers: _penanda(rencana)),
                ],
              ),
              if (_pensil)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (DragStartDetails d) => _mulaiGores(d.localPosition),
                    onPanUpdate: (DragUpdateDetails d) => _lanjutGores(d.localPosition),
                    onPanEnd: (DragEndDetails d) => _selesaiGores(),
                    onTapUp: (TapUpDetails d) {
                      _mulaiGores(d.localPosition);
                      _selesaiGores();
                    },
                  ),
                ),
              Positioned(
                right: 8,
                bottom: 8,
                child: rtsPetaAtribusi(
                  rtsPetaSumber[_sumber < 0 || _sumber >= rtsPetaSumber.length
                          ? 0
                          : _sumber]
                      .nama,
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Column(
                  children: <Widget>[
                    _tombolBulat(
                      ikon: Icons.my_location_rounded,
                      onTap: _perbaruiLokasiSaya,
                    ),
                    const SizedBox(height: 7),
                    _tombolBulat(ikon: Icons.fullscreen_rounded, onTap: _aturTampilan),
                    const SizedBox(height: 7),
                    _tombolBulat(ikon: Icons.add, onTap: () => _zoom(1)),
                    const SizedBox(height: 7),
                    _tombolBulat(ikon: Icons.remove, onTap: () => _zoom(-1)),
                  ],
                ),
              ),
              Positioned(
                left: 8,
                top: 8,
                child: rtsPetaLegenda(
                  judul: _caraWarna == 'HARI' ? 'Warna: HARI' : 'Warna: FREKUENSI',
                  isi: _caraWarna == 'HARI'
                      ? <MapEntry<String, Color>>[
                          MapEntry<String, Color>('Senin', rtsPetaSenin),
                          MapEntry<String, Color>('Selasa', rtsPetaSelasa),
                          MapEntry<String, Color>('Rabu', rtsPetaRabu),
                          MapEntry<String, Color>('Kamis', rtsPetaKamis),
                          MapEntry<String, Color>('Jumat', rtsPetaJumat),
                          MapEntry<String, Color>('Sabtu', rtsPetaSabtu),
                        ]
                      : <MapEntry<String, Color>>[
                          MapEntry<String, Color>('Weekly', rtsPetaWeekly),
                          MapEntry<String, Color>('BW Ganjil', rtsPetaGanjil),
                          MapEntry<String, Color>('BW Genap', rtsPetaGenap),
                          MapEntry<String, Color>('Selesai', rtsKsHijau),
                        ],
                ),
              ),
              if (_sibuk)
                const Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: LinearProgressIndicator(minHeight: 3),
                ),
            ],
          ),
        ),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                  onPressed: () => unawaited(_bukaDaftarPlan()),
                  icon: const Icon(Icons.copy_all_rounded, size: 17),
                  label: const Text('SALIN DAFTAR PLAN',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => unawaited(_bukaRuteGoogle(rencana)),
                  icon: const Icon(Icons.navigation_rounded, size: 17),
                  label: const Text('BUKA RUTE', style: TextStyle(fontSize: 11.5)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 6,
          child: rencana.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Text(
                      'Belum ada toko untuk hari $_hari dengan frekuensi '
                      '$_frekuensi. Pilih hari atau frekuensi lain di atas.',
                      textAlign: TextAlign.center,
                      style: rtsPetaIsiKecil,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                  itemCount: rencana.length,
                  itemBuilder: (BuildContext ctx, int i) {
                    final RtsToko t = rencana[i];

                    double? sebelumnya;

                    if (i == 0) {
                      sebelumnya = null;
                    } else {
                      sebelumnya = rtsPetaJarakMeter(
                        rencana[i - 1].latitude,
                        rencana[i - 1].longitude,
                        t.latitude,
                        t.longitude,
                      );
                    }

                    return RtsBarisToko(
                      nomor: '${i + 1}',
                      toko: t,
                      warna: _warnaToko(t),
                      jarak: _jarakKe(t),
                      jarakSebelum: sebelumnya,
                      sudah: _sudah.contains(t.idCustomer),
                      selesai: _selesai.contains(t.idCustomer),
                      onNaik: () => _ubahUrutan(i, -1),
                      onTurun: () => _ubahUrutan(i, 1),
                      onSalin: () async {
                        await rtsPetaSalinTeks('${t.nama} | ${t.idCustomer}');

                        if (mounted) rtsKsPesan(context, 'Nama & kode disalin.');
                      },
                      onKunjungi: () => _tandaiKunjungan(t),
                      onNavigasi: () => unawaited(
                        rtsPetaNavigasi(context, t.latitude, t.longitude, t.nama),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _tombolPensil(String teks, IconData ikon, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(ikon, size: 15),
        label: Text(teks, style: const TextStyle(fontSize: 10.5)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          minimumSize: const Size(0, 32),
        ),
      ),
    );
  }

  Widget _tombolBulat({required IconData ikon, required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(ikon, size: 19, color: rtsKsMaroon),
        ),
      ),
    );
  }

  void _zoom(double tambah) {
    try {
      final MapCamera kamera = _kontrol.camera;

      _kontrol.move(kamera.center, (kamera.zoom + tambah).clamp(4, 18));
    } catch (_) {
      // peta belum siap
    }
  }

  Future<void> _perbaruiLokasiSaya() async {
    final Position? posisi = await rtsPetaAmbilLokasi();

    if (!mounted) return;

    if (posisi == null) {
      rtsKsPesan(
        context,
        'Titik GPS belum dapat dibaca. Nyalakan Lokasi pada HP dan beri izin '
        'Lokasi untuk RTS Panel.',
        galat: true,
      );
      return;
    }

    setState(() {
      _sayaLat = posisi.latitude;
      _sayaLng = posisi.longitude;
      _urutanManual = <String>[];
    });

    rtsKsPesan(context, 'Titik lokasi Anda sudah dibaca.');

    try {
      _kontrol.move(LatLng(posisi.latitude, posisi.longitude), 15);
    } catch (_) {
      // peta belum siap
    }
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN 4 : LOKASI KANTOR / MITRA (ADMIN & ASS)                           */
/* ------------------------------------------------------------------------- */

class RtsKantorPage extends StatefulWidget {
  const RtsKantorPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
    this.districtTersedia = const <String>[],
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;
  final List<String> districtTersedia;

  @override
  State<RtsKantorPage> createState() => _RtsKantorPageState();
}

class _RtsKantorPageState extends State<RtsKantorPage> {
  bool _memuat = true;
  bool _sibuk = false;
  String _galat = '';
  List<RtsKantor> _kantor = <RtsKantor>[];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mulai();
    });
  }

  Future<void> _mulai() async {
    await rtsPetaSiapkanAkun(
      baseUrl: widget.baseUrl,
      token: widget.token,
      pengguna: widget.pengguna,
    );

    await _muat();

    if (mounted && _kantor.isEmpty) {
      await _segarkan(diam: true);
    }
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kantor_daftar');

      final List<dynamic> items =
          hasil['items'] is List ? hasil['items'] as List<dynamic> : <dynamic>[];

      final List<RtsKantor> daftar = <RtsKantor>[];

      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        daftar.add(RtsKantor.dariPeta(satu.cast<String, dynamic>()));
      }

      if (!mounted) return;

      setState(() {
        _kantor = daftar;
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

  Future<void> _segarkan({bool diam = false}) async {
    if (!diam) setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kantor_segarkan');

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _kantor = _kantorDari(hasil['items']);
      });

      if (!diam) {
        rtsKsPesan(context, '${hasil['message'] ?? 'Titik kantor disegarkan.'}');
      }
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      if (!diam) rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  List<RtsKantor> _kantorDari(dynamic items) {
    final List<RtsKantor> hasil = <RtsKantor>[];

    if (items is List) {
      for (final dynamic satu in items) {
        if (satu is! Map) continue;

        hasil.add(RtsKantor.dariPeta(satu.cast<String, dynamic>()));
      }
    }

    return hasil;
  }

  Future<void> _form([RtsKantor? kantor]) async {
    final TextEditingController nama =
        TextEditingController(text: kantor?.nama ?? '');
    final TextEditingController alamat =
        TextEditingController(text: kantor?.alamat ?? '');
    final TextEditingController catatan =
        TextEditingController(text: kantor?.catatan ?? '');
    final TextEditingController lintang = TextEditingController(
      text: kantor == null || !kantor.adaTitik
          ? ''
          : kantor.latitude.toStringAsFixed(6),
    );
    final TextEditingController bujur = TextEditingController(
      text: kantor == null || !kantor.adaTitik
          ? ''
          : kantor.longitude.toStringAsFixed(6),
    );

    final TextEditingController districtBebas =
        TextEditingController(text: kantor?.district ?? '');

    String district = kantor?.district ?? '';
    String pesanTitik = '';

    final bool? simpan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter ubah) {
            Future<void> ambilTitik() async {
              ubah(() => pesanTitik = 'Membaca titik GPS...');

              final Position? posisi = await rtsPetaAmbilLokasi();

              if (posisi == null) {
                ubah(() {
                  pesanTitik = 'Titik GPS tidak terbaca. Nyalakan Lokasi pada '
                      'HP dan beri izin Lokasi untuk RTS Panel.';
                });
                return;
              }

              lintang.text = posisi.latitude.toStringAsFixed(6);
              bujur.text = posisi.longitude.toStringAsFixed(6);

              ubah(() {
                pesanTitik = 'Titik dibaca (ketepatan '
                    '+-${posisi.accuracy.round()} m).';
              });
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              title: Text(
                kantor == null ? 'Tambah Lokasi Kantor' : 'Ubah Lokasi Kantor',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    TextField(
                      controller: nama,
                      decoration: const InputDecoration(
                        labelText: 'Nama kantor / mitra',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: alamat,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Alamat kantor',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Sales District yang dilayani',
                      style: rtsPetaIsiKecil,
                    ),
                    const SizedBox(height: 3),
                    if (widget.districtTersedia.isEmpty)
                      TextField(
                        controller: districtBebas,
                        decoration: const InputDecoration(
                          hintText: 'Contoh: MEDAN',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          border: Border.all(color: rtsKsGaris),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: DropdownButton<String>(
                          value: district.isEmpty
                              ? widget.districtTersedia.first
                              : district,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          style: const TextStyle(
                            fontSize: 13,
                            color: rtsKsTeks,
                          ),
                          items: widget.districtTersedia
                              .map((String d) => DropdownMenuItem<String>(
                                    value: d,
                                    child: Text(d),
                                  ))
                              .toList(),
                          onChanged: (String? nilai) {
                            if (nilai != null) district = nilai;
                          },
                        ),
                      ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: catatan,
                      decoration: const InputDecoration(
                        labelText: 'Catatan (opsional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextField(
                            controller: lintang,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Lintang',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: bujur,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Bujur',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(ambilTitik()),
                      icon: const Icon(Icons.my_location_rounded, size: 17),
                      label: const Text(
                        'AMBIL TITIK DARI LOKASI SAYA',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                    if (pesanTitik.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          pesanTitik,
                          style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                        ),
                      ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                  onPressed: () => Navigator.of(ctx2).pop(true),
                  child: const Text('SIMPAN'),
                ),
              ],
            );
          },
        );
      },
    );

    if (simpan != true) {
      nama.dispose();
      alamat.dispose();
      catatan.dispose();
      lintang.dispose();
      bujur.dispose();
      districtBebas.dispose();
      return;
    }

    if (!mounted) return;

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kantor_simpan', <String, dynamic>{
        'id': kantor?.id ?? 0,
        'id_server': kantor?.idServer ?? 0,
        'nama': nama.text.trim(),
        'alamat': alamat.text.trim(),
        'district': widget.districtTersedia.isEmpty
            ? districtBebas.text.trim()
            : district,
        'latitude': rtsKsAngka(lintang.text.replaceAll(',', '.')),
        'longitude': rtsKsAngka(bujur.text.replaceAll(',', '.')),
        'catatan': catatan.text.trim(),
      });

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _kantor = _kantorDari(hasil['items']);
      });

      rtsKsPesan(context, '${hasil['message'] ?? 'Titik kantor tersimpan.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      rtsKsPesan(context, e.pesan, galat: true);
    }

    nama.dispose();
    alamat.dispose();
    catatan.dispose();
    lintang.dispose();
    bujur.dispose();
    districtBebas.dispose();
  }

  Future<void> _hapus(RtsKantor kantor) async {
    final bool? jalan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Hapus Lokasi Kantor',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Titik "${kantor.nama}" akan dihapus dari server dan dari HP. '
          'RUTE PLAN tidak lagi memakai kantor ini sebagai titik awal.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (jalan != true || !mounted) return;

    setState(() => _sibuk = true);

    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('kantor_hapus', <String, dynamic>{
        'id': kantor.id,
        'id_server': kantor.idServer,
      });

      if (!mounted) return;

      setState(() {
        _sibuk = false;
        _kantor = _kantorDari(hasil['items']);
      });

      rtsKsPesan(context, '${hasil['message'] ?? 'Titik kantor dihapus.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _sibuk = false);

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Lokasi Kantor / Mitra'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat dari server',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _sibuk ? null : () => _segarkan(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => unawaited(_form()),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Kantor'),
      ),
      body: Column(
        children: <Widget>[
          if (_sibuk || _memuat)
            const LinearProgressIndicator(minHeight: 3)
          else
            const SizedBox(height: 3),
          Expanded(
            child: _galat.isNotEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        _galat,
                        textAlign: TextAlign.center,
                        style: rtsPetaIsiKecil,
                      ),
                    ),
                  )
                : _kantor.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              const Icon(Icons.business_rounded,
                                  size: 56, color: rtsKsTeks2),
                              const SizedBox(height: 12),
                              const Text(
                                'Belum ada titik lokasi kantor / mitra.',
                                style: rtsPetaJudulKecil,
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Tekan tombol KANTOR di kanan bawah, isi nama '
                                'kantor, lalu tekan AMBIL TITIK DARI LOKASI '
                                'SAYA saat berada di kantor. Titik ini menjadi '
                                'awal perhitungan RUTE PLAN.',
                                textAlign: TextAlign.center,
                                style: rtsPetaIsiKecil,
                              ),
                              const SizedBox(height: 14),
                              OutlinedButton.icon(
                                onPressed: _sibuk ? null : () => _segarkan(),
                                icon: const Icon(Icons.cloud_download_outlined,
                                    size: 17),
                                label: const Text('MUAT DARI SERVER'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 90),
                        itemCount: _kantor.length,
                        itemBuilder: (BuildContext ctx, int i) {
                          final RtsKantor k = _kantor[i];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 9),
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            decoration: rtsPetaKotak(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    const Icon(Icons.business_rounded,
                                        size: 18, color: rtsPetaKantor),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        k.nama.isEmpty ? 'Kantor' : k.nama,
                                        style: rtsPetaJudulKecil,
                                      ),
                                    ),
                                    if (!k.adaTitik)
                                      const Text(
                                        'TITIK BELUM ADA',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: rtsKsMerah,
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  k.alamat.isEmpty ? '-' : k.alamat,
                                  style: rtsPetaIsiKecil,
                                ),
                                Text(
                                  'District: '
                                  '${k.district.isEmpty ? 'semua' : k.district}',
                                  style: rtsPetaIsiKecil,
                                ),
                                Text(
                                  k.adaTitik
                                      ? 'Titik: ${k.latitude.toStringAsFixed(5)}, '
                                          '${k.longitude.toStringAsFixed(5)}'
                                      : 'Titik belum diambil',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: rtsKsMaroon,
                                  ),
                                ),
                                if (k.catatan.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(k.catatan, style: rtsPetaIsiKecil),
                                  ),
                                const SizedBox(height: 8),
                                Row(
                                  children: <Widget>[
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => unawaited(_form(k)),
                                        icon: const Icon(Icons.edit_outlined,
                                            size: 16),
                                        label: const Text('UBAH',
                                            style: TextStyle(fontSize: 11.5)),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: k.adaTitik
                                            ? () => unawaited(
                                                  rtsPetaNavigasi(
                                                    context,
                                                    k.latitude,
                                                    k.longitude,
                                                    k.nama,
                                                  ),
                                                )
                                            : null,
                                        icon: const Icon(Icons.navigation_rounded,
                                            size: 16),
                                        label: const Text('NAVIGASI',
                                            style: TextStyle(fontSize: 11.5)),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    IconButton(
                                      tooltip: 'Hapus',
                                      onPressed: () => unawaited(_hapus(k)),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: rtsKsMerah,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
