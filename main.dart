import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'kasir.dart';
import 'kasir_lokal.dart';
import 'peta.dart';

/* ------------------------------------------------------------------------- */
/* KONFIGURASI                                                                */
/* ------------------------------------------------------------------------- */

/// Pilihan server RTS Panel.
/// Produksi : https://rts.benedic-s.com/api   (database benedics_bene_sales)
/// Staging  : https://coba.benedic-s.com/api  (database benedics_coba)
class RtsServer {
  const RtsServer({
    required this.nama,
    required this.baseUrl,
    required this.keterangan,
    required this.database,
  });

  final String nama;
  final String baseUrl;
  final String keterangan;
  final String database;

  bool get produksi => nama == 'Produksi';
}

const List<RtsServer> rtsServers = <RtsServer>[
  RtsServer(
    nama: 'Produksi',
    baseUrl: 'https://rts.benedic-s.com/api',
    keterangan: 'Data asli perusahaan',
    database: 'benedics_bene_sales',
  ),
  RtsServer(
    nama: 'Staging',
    baseUrl: 'https://coba.benedic-s.com/api',
    keterangan: 'Database uji coba',
    database: 'benedics_coba',
  ),
];

/// Pengaturan server yang sedang dipakai aplikasi.
/// Pilihan disimpan di perangkat, sehingga tidak perlu ubah kode untuk berpindah.
class RtsConfig {
  static const String _kunci = 'rts_server_index';

  /// Terhubung ke produksi bila belum pernah diatur.
  static int indeksServer = 0;

  static RtsServer get server => rtsServers[indeksServer];

  static String get baseUrl => server.baseUrl;

  static String get serverLabel => 'Server ${server.nama}';

  static bool get produksi => server.produksi;

  /// Alamat berkas keterangan versi aplikasi di server.
  ///
  /// Berkas ini diatur dari halaman app_versi.php pada website RTS Panel dan
  /// dipakai oleh fitur pembaruan otomatis. Contoh alamat:
  ///   https://rts.benedic-s.com/apk/app_versi.json
  static String get urlVersi {
    final String dasar = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;

    return '$dasar/apk/app_versi.json';
  }

  static Future<void> muat() async {
    try {
      // Batas waktu dipasang supaya aplikasi tidak pernah tertahan pada layar
      // kosong bila penyimpanan perangkat lambat menjawab.
      final SharedPreferences prefs = await SharedPreferences
          .getInstance()
          .timeout(const Duration(seconds: 5));
      final int? tersimpan = prefs.getInt(_kunci);
      if (tersimpan != null && tersimpan >= 0 && tersimpan < rtsServers.length) {
        indeksServer = tersimpan;
      }
    } catch (_) {
      // pengaturan gagal dibaca, pakai bawaan
    }
  }

  static Future<void> simpan(int indeks) async {
    if (indeks < 0 || indeks >= rtsServers.length) return;
    indeksServer = indeks;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kunci, indeks);
    } catch (_) {
      // pengaturan gagal disimpan, tetap dipakai untuk sesi ini
    }
  }
}

/// Menyimpan sesi login di perangkat supaya tidak perlu mengetik password
/// setiap kali aplikasi dibuka.
///
/// Catatan: token disimpan pada penyimpanan pribadi aplikasi
/// (SharedPreferences). Berkas ini tidak dapat dibaca aplikasi lain pada
/// perangkat yang belum di-root. Sesi otomatis dibuang bila server diganti,
/// bila pengguna menekan Keluar, atau bila server menyatakan token tidak
/// berlaku lagi.
class RtsSesi {
  static const String _kunciToken = 'rts_sesi_token';
  static const String _kunciUser = 'rts_sesi_user';
  static const String _kunciServer = 'rts_sesi_server';
  static const String _kunciIngat = 'rts_ingat_saya';

  /// Token yang tersimpan, kosong bila tidak ada.
  static String token = '';

  /// Data akun yang tersimpan, null bila tidak ada.
  static RtsUser? user;

  /// True bila "Ingat saya" dicentang pada login terakhir.
  static bool ingatSaya = false;

  static bool get adaSesi => token.isNotEmpty && user != null;

  /// Membaca sesi tersimpan. Sesi dibuang bila dibuat pada server yang berbeda.
  static Future<void> muat() async {
    try {
      final SharedPreferences prefs = await SharedPreferences
          .getInstance()
          .timeout(const Duration(seconds: 5));

      ingatSaya = prefs.getBool(_kunciIngat) ?? false;

      final int? serverTersimpan = prefs.getInt(_kunciServer);
      final String tokenTersimpan = (prefs.getString(_kunciToken) ?? '').trim();
      final String userTersimpan = prefs.getString(_kunciUser) ?? '';

      if (serverTersimpan != RtsConfig.indeksServer) {
        // Token hanya berlaku pada server tempat ia dibuat.
        if (tokenTersimpan.isNotEmpty || userTersimpan.isNotEmpty) {
          await prefs.remove(_kunciToken);
          await prefs.remove(_kunciUser);
          await prefs.remove(_kunciServer);
        }

        token = '';
        user = null;
        return;
      }

      if (tokenTersimpan.isEmpty || userTersimpan.isEmpty) {
        token = '';
        user = null;
        return;
      }

      final dynamic terurai = jsonDecode(userTersimpan);

      if (terurai is! Map) {
        token = '';
        user = null;
        return;
      }

      token = tokenTersimpan;
      user = RtsUser.fromJson(terurai.cast<String, dynamic>());
    } catch (_) {
      token = '';
      user = null;
    }
  }

  /// Menyimpan sesi setelah login berhasil.
  static Future<void> simpan(String tokenBaru, RtsUser userBaru) async {
    token = tokenBaru;
    user = userBaru;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kunciToken, tokenBaru);
      await prefs.setString(_kunciUser, jsonEncode(userBaru.toJson()));
      await prefs.setInt(_kunciServer, RtsConfig.indeksServer);
      await prefs.setBool(_kunciIngat, true);
    } catch (_) {
      // gagal menyimpan, sesi tetap dipakai untuk pemakaian sekarang
    }

    // Daftarkan HP ini ke server supaya ikut menerima pemberitahuan.
    // Kegagalan di sini tidak menghalangi proses login.
    unawaited(RtsPushFcm.daftarkanToken());
  }

  /// Menghapus sesi tersimpan.
  static Future<void> hapus({bool hapusPilihan = true}) async {
    // HP ini dilepas dari akun SEBELUM token sesi dihapus, supaya pemberitahuan
    // milik akun ini berhenti masuk ke HP ini. Bila gagal, tidak masalah.
    await RtsPushFcm.hapusToken();

    token = '';
    user = null;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kunciToken);
      await prefs.remove(_kunciUser);
      await prefs.remove(_kunciServer);

      if (hapusPilihan) {
        await prefs.setBool(_kunciIngat, false);
        ingatSaya = false;
      }
    } catch (_) {
      // tidak ada yang perlu dilakukan
    }
  }

  /// Mengingat pilihan centang "Ingat saya" walau login belum berhasil.
  static Future<void> simpanPilihanIngat(bool nilai) async {
    ingatSaya = nilai;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kunciIngat, nilai);
    } catch (_) {
      // abaikan
    }
  }
}

const Color rtsMaroon = Color(0xff8e1420);
const Color rtsMaroonDark = Color(0xff640c15);
const Color rtsSurface = Color(0xfff8f5f1);
const Color rtsCardBorder = Color(0xffece5de);
const Color rtsTextPrimary = Color(0xff201c19);
const Color rtsTextSecondary = Color(0xff7c736d);
const Color rtsGreen = Color(0xff1e7a45);
const Color rtsAmber = Color(0xffb3761b);

const String rtsLoginArt = 'assets/images/rts_panel_login_art.png';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bila ada kesalahan pada tampilan, yang muncul adalah keterangan
  // kesalahannya. Tanpa ini aplikasi hanya menampilkan layar kosong tanpa
  // petunjuk apa pun.
  _pasangPenangkapGalat();

  try {
    await RtsConfig.muat();
    await RtsSesi.muat();
  } catch (_) {
    // Pengaturan gagal dibaca: aplikasi tetap dijalankan dengan nilai bawaan.
  }

  // Menyiapkan pemberitahuan HP lewat Firebase: pemberitahuan tetap masuk
  // walau aplikasi sedang ditutup sepenuhnya. Bila Firebase belum
  // disiapkan di server/HP, bagian ini dilewati tanpa mengganggu aplikasi.
  await RtsPushFcm.siapkan();

  // Membaca versi aplikasi yang terpasang di HP. Dipakai oleh fitur
  // pembaruan otomatis untuk membandingkan dengan versi di server.
  await RtsVersi.muat();

  // Membaca tingkat akun (GRATIS / PRO). Akun PRO bebas iklan.
  await RtsTingkatAkun.muat();

  // Menyiapkan mesin iklan. Dijalankan tanpa ditunggu supaya pembukaan
  // aplikasi tetap cepat; kegagalan tidak mengganggu aplikasi.
  unawaited(RtsIklan.siapkan());

  runApp(const RtsPanelApp());

  // Iklan layar pembuka: tampil sekilas saat aplikasi dibuka. Hanya untuk
  // akun GRATIS dan paling sering sekali setiap 4 menit. Kegagalan diabaikan.
  unawaited(RtsIklanBuka.tampilkanSaatDibuka());
}

/// Menampilkan keterangan kesalahan pada layar, agar tidak berupa layar kosong.
void _pasangPenangkapGalat() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: rtsSurface,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: rtsMaroon,
                  size: 44,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Terjadi kesalahan pada tampilan aplikasi',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kirimkan tulisan di bawah ini kepada pengembang supaya dapat '
                  'diperbaiki.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: rtsTextSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: rtsCardBorder),
                  ),
                  child: Text(
                    details.exceptionAsString(),
                    style: const TextStyle(
                      color: Color(0xffa52020),
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };
}

class RtsPanelApp extends StatelessWidget {
  const RtsPanelApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'RTS Panel',
      navigatorKey: rtsNavigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: rtsSurface,
        colorScheme: ColorScheme.fromSeed(seedColor: rtsMaroon),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const SplashPage(),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MODEL                                                                      */
/* ------------------------------------------------------------------------- */

/// Membaca nilai benar dari server yang dapat berbentuk true, 1, "1",
/// atau "true". Dipakai untuk kolom bertipe TINYINT seperti akun_pro.
bool rtsBenar(Object? nilai) {
  if (nilai == true) return true;
  if (nilai == false || nilai == null) return false;

  final String teks = nilai.toString().trim().toLowerCase();

  return teks == '1' || teks == 'true' || teks == 'ya';
}

class RtsUser {
  const RtsUser({
    required this.id,
    required this.username,
    required this.namaLengkap,
    required this.role,
    required this.salesman,
    required this.salesDistrict,
    this.akunPro = false,
    this.fotoProfil = '',
    this.proSelesai = '',
    this.trialAktif = false,
    this.trialTersedia = false,
    this.sisaHari = 0,
    this.sumberLangganan = 'GRATIS',
    this.berlakuSampai = '',
  });

  final int id;
  final String username;
  final String namaLengkap;
  final String role;
  final String salesman;
  final String salesDistrict;

  /// True bila akun ini berlangganan (Akun PRO). Akun PRO bebas iklan.
  ///
  /// Nilai ini datang dari server (kolom akun_pro pada tabel sales_users).
  /// Bila kolomnya belum ada di server, nilainya false sehingga seluruh akun
  /// dianggap GRATIS dan iklan tampil seperti biasa.
  ///
  /// Mulai 30 September 2026, penanda ini dihitung server dari masa berlaku
  /// langganan: akun PRO yang sudah lewat masa berlakunya otomatis menjadi
  /// GRATIS lagi, dan uji coba 7 hari dihitung sebagai PRO.
  final bool akunPro;

  /// Alamat gambar foto pribadi petugas (kosong bila belum memasang foto).
  final String fotoProfil;

  /// Tanggal berakhir langganan PRO (kosong bila tanpa batas waktu).
  final String proSelesai;

  /// True bila akun sedang memakai uji coba gratis 7 hari.
  final bool trialAktif;

  /// True bila uji coba gratis masih tersedia (belum pernah dipakai).
  final bool trialTersedia;

  /// Sisa hari langganan PRO.
  final int sisaHari;

  /// Sumber langganan: PRO, TRIAL, atau GRATIS.
  final String sumberLangganan;

  /// Tanggal berakhir langganan dalam bentuk 30-09-2026.
  final String berlakuSampai;

  factory RtsUser.fromJson(Map<String, dynamic> json) {
    return RtsUser(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      username: (json['username'] ?? '').toString(),
      namaLengkap: (json['nama_lengkap'] ?? '').toString(),
      role: (json['role'] ?? '').toString().toUpperCase(),
      salesman: (json['salesman'] ?? '').toString(),
      salesDistrict: (json['sales_district'] ?? '').toString(),
      akunPro: rtsBenar(json['akun_pro']),
      fotoProfil: (json['foto_profil'] ?? '').toString(),
      proSelesai: (json['pro_selesai'] ?? '').toString(),
      trialAktif: rtsBenar(json['trial_aktif']),
      trialTersedia: rtsBenar(json['trial_tersedia']),
      sisaHari: int.tryParse('${json['sisa_hari'] ?? 0}') ?? 0,
      sumberLangganan:
          (json['sumber_langganan'] ?? 'GRATIS').toString().toUpperCase(),
      berlakuSampai: (json['berlaku_sampai'] ?? '').toString(),
    );
  }

  /// Menyalin data akun dengan beberapa bagian diganti.
  RtsUser copyWith({
    bool? akunPro,
    String? fotoProfil,
    String? proSelesai,
    bool? trialAktif,
    bool? trialTersedia,
    int? sisaHari,
    String? sumberLangganan,
    String? berlakuSampai,
  }) {
    return RtsUser(
      id: id,
      username: username,
      namaLengkap: namaLengkap,
      role: role,
      salesman: salesman,
      salesDistrict: salesDistrict,
      akunPro: akunPro ?? this.akunPro,
      fotoProfil: fotoProfil ?? this.fotoProfil,
      proSelesai: proSelesai ?? this.proSelesai,
      trialAktif: trialAktif ?? this.trialAktif,
      trialTersedia: trialTersedia ?? this.trialTersedia,
      sisaHari: sisaHari ?? this.sisaHari,
      sumberLangganan: sumberLangganan ?? this.sumberLangganan,
      berlakuSampai: berlakuSampai ?? this.berlakuSampai,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'username': username,
      'nama_lengkap': namaLengkap,
      'role': role,
      'salesman': salesman,
      'sales_district': salesDistrict,
      'akun_pro': akunPro,
      'foto_profil': fotoProfil,
      'pro_selesai': proSelesai,
      'trial_aktif': trialAktif,
      'trial_tersedia': trialTersedia,
      'sisa_hari': sisaHari,
      'sumber_langganan': sumberLangganan,
      'berlaku_sampai': berlakuSampai,
    };
  }

  String get displayName {
    final String lengkap = namaLengkap.trim();
    return lengkap.isNotEmpty ? lengkap : username;
  }

  bool get canApprove => role == 'ADMIN' || role == 'ASS';

  String get accessLevel {
    switch (role) {
      case 'ADMIN':
      case 'ASS':
        return 'Penuh • semua district';
      case 'WSS':
      case 'SMST':
        return 'Lihat semua district';
      case 'RTS':
      case 'TF':
        return 'Customer sesuai Sales District';
      default:
        return '-';
    }
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.idCustomer,
    required this.namaToko,
    required this.tipeCustomer,
    required this.salesman,
    required this.salesDistrict,
    required this.alamat,
    required this.kunjungan,
    required this.hari,
    required this.latitude,
    required this.longitude,
    required this.statusAktif,
    this.mapUrl = '',
  });

  final int id;
  final String idCustomer;
  final String namaToko;
  final String tipeCustomer;
  final String salesman;
  final String salesDistrict;
  final String alamat;
  final String kunjungan;
  final String hari;
  final String latitude;
  final String longitude;
  final String statusAktif;
  final String mapUrl;

  bool get isGsp => tipeCustomer.toUpperCase() == 'GSP';
  bool get isAktif => statusAktif.toLowerCase() == 'aktif';
  bool get punyaKoordinat => latitude.trim() != '' && longitude.trim() != '';

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      idCustomer: (json['id_customer'] ?? '').toString(),
      namaToko: (json['nama_toko'] ?? '').toString(),
      tipeCustomer:
          (json['tipe_customer'] ?? 'REGULER').toString().toUpperCase(),
      salesman: (json['salesman'] ?? '').toString(),
      salesDistrict: (json['sales_district'] ?? '').toString(),
      alamat: (json['alamat'] ?? '').toString(),
      kunjungan: (json['kunjungan'] ?? '').toString(),
      hari: (json['hari'] ?? '').toString(),
      latitude: (json['latitude'] ?? '').toString(),
      longitude: (json['longitude'] ?? '').toString(),
      statusAktif: (json['status_aktif'] ?? 'Aktif').toString(),
      mapUrl: (json['map_url'] ?? '').toString(),
    );
  }
}

class CustomerPage {
  const CustomerPage({
    required this.items,
    required this.page,
    required this.total,
    required this.totalPages,
    required this.hasMore,
    this.tipeAvailable = true,
    this.counts = const {'REGULER': 0, 'GSP': 0, 'total': 0},
  });

  final List<Customer> items;
  final int page;
  final int total;
  final int totalPages;
  final bool hasMore;

  /// Bernilai false bila server belum memiliki kolom tipe_customer.
  final bool tipeAvailable;

  /// Jumlah customer per kategori pada pencarian yang sedang aktif.
  final Map<String, int> counts;

  factory CustomerPage.fromJson(Map<String, dynamic> json) {
    final List<Customer> items = ((json['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => Customer.fromJson(item.cast<String, dynamic>()))
        .toList();

    final Map<String, dynamic> meta =
        ((json['meta'] as Map?) ?? const {}).cast<String, dynamic>();

    final Map<String, int> counts = <String, int>{};
    final Object? rawCounts = meta['counts'] ?? json['counts'];

    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        counts[key.toString().toUpperCase()] =
            int.tryParse(value.toString()) ?? 0;
      });
    }

    return CustomerPage(
      items: items,
      page: int.tryParse((meta['page'] ?? '1').toString()) ?? 1,
      total: int.tryParse((meta['total'] ?? '0').toString()) ?? 0,
      totalPages: int.tryParse((meta['total_pages'] ?? '1').toString()) ?? 1,
      hasMore: meta['has_more'] == true,
      tipeAvailable: (meta['tipe_available'] ?? json['tipe_available']) != false,
      counts: counts,
    );
  }
}

/* ------------------------------------------------------------------------- */
/* API CLIENT                                                                 */
/* ------------------------------------------------------------------------- */

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode = 0});

  final String message;
  final int statusCode;
  bool get unauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({this.token = ''});

  final String token;

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, String> get _headers {
    if (token.isEmpty) return _jsonHeaders;
    return {
      ..._jsonHeaders,
      'Authorization': 'Bearer $token',
    };
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String> query = const {},
  ]) async {
    final Uri uri = Uri.parse('${RtsConfig.baseUrl}/$path').replace(
      queryParameters: query.isEmpty ? null : query,
    );

    try {
      final http.Response response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 30));
      return _decode(response, path);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Tidak dapat terhubung ke server. Periksa internet Anda.');
    }
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final Uri uri = Uri.parse('${RtsConfig.baseUrl}/$path');

    try {
      final http.Response response = await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _decode(response, path);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Tidak dapat terhubung ke server. Periksa internet Anda.');
    }
  }

  Map<String, dynamic> _decode(http.Response response, String path) {
    // 404 dari server berarti berkas API belum ada di folder api.
    if (response.statusCode == 404) {
      throw ApiException(
        'Fitur "$path" belum tersedia di server ${RtsConfig.server.nama}. '
        'Pastikan seluruh berkas di folder api sudah di-upload ke '
        '${RtsConfig.baseUrl}.',
        statusCode: 404,
      );
    }

    Map<String, dynamic> body = {};

    if (response.body.trim().isNotEmpty) {
      try {
        final dynamic decoded = jsonDecode(response.body);
        if (decoded is Map) {
          body = decoded.cast<String, dynamic>();
        }
      } catch (_) {
        throw ApiException(
          'Server mengirim data yang tidak dikenali (kode ${response.statusCode}).',
          statusCode: response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      (body['message'] ?? 'Permintaan gagal diproses.').toString(),
      statusCode: response.statusCode,
    );
  }
}

/* ------------------------------------------------------------------------- */
/* KOMPONEN UMUM                                                              */
/* ------------------------------------------------------------------------- */

class RtsBackground extends StatelessWidget {
  const RtsBackground({super.key, this.overlayOpacity = 0.88});

  final double overlayOpacity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            rtsLoginArt,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(color: rtsSurface),
          ),
        ),
        Positioned.fill(
          child: ColoredBox(
            color: Color.fromRGBO(248, 245, 241, overlayOpacity),
          ),
        ),
      ],
    );
  }
}

class RtsSectionTitle extends StatelessWidget {
  const RtsSectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 17,
          decoration: BoxDecoration(
            color: rtsMaroon,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: rtsTextPrimary,
              fontSize: 16.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class RtsCard extends StatelessWidget {
  const RtsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: rtsCardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 44, 34, 0.06),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}

class RtsInfoRow extends StatelessWidget {
  const RtsInfoRow(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: const TextStyle(color: rtsTextSecondary, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value.trim().isEmpty ? '-' : value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: valueColor ?? rtsTextPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RtsDivider extends StatelessWidget {
  const RtsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xfff2ece6));
  }
}

class RtsBadge extends StatelessWidget {
  const RtsBadge(
    this.text, {
    super.key,
    this.background = const Color(0xfffaecee),
    this.foreground = rtsMaroon,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

void rtsShowMessage(BuildContext context, String message,
    {bool success = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? rtsGreen : rtsMaroon,
        duration: const Duration(seconds: 3),
      ),
    );
}

/// Penanda kode aplikasi.
///
/// Dipakai untuk memastikan aplikasi di HP benar-benar dibangun dari kode
/// terbaru. Nilainya ditampilkan pada halaman Pengaturan, pada kartu
/// "Cuaca Beranda" - jadi cukup dilihat di HP, tidak perlu menebak.
/// Setiap kali kode aplikasi diperbarui, angka ini dinaikkan.
const String rtsKodeAplikasi = 'RTS-2026-10-04-17';

/// Tingkat akun: GRATIS (dengan iklan) atau PRO (bebas iklan).
///
/// ATURAN IKLAN (pilihan Bapak - pilihan b):
///   - Akun GRATIS : iklan tampil (banner pada beranda dan iklan bentuk asli
///                   pada setiap menu)
///   - Akun PRO    : iklan TIDAK tampil sama sekali
///
/// Sumber kebenaran: kolom `akun_pro` pada tabel `sales_users`, yang dikirim
/// server lewat login.php dan session_check.php. Selama kolom itu belum ada di
/// server, seluruh akun dianggap GRATIS - jadi memasang bagian ini tidak
/// mengubah apa pun sebelum kolomnya dibuat.
///
/// Tersedia juga saklar UJI COBA (khusus ADMIN, pada halaman Profil) untuk
/// mencoba tampilan bebas iklan tanpa perlu mengubah database.
class RtsTingkatAkun {
  const RtsTingkatAkun._();

  static const String _kunciUji = 'rts_akun_pro_uji';

  static bool _uji = false;

  /// True bila akun ini dianggap PRO menurut data server.
  static bool get dariServer => RtsSesi.user?.akunPro ?? false;

  /// True bila akun ini dianggap PRO (data server atau saklar uji coba).
  static bool get pro => dariServer || _uji;

  /// Nama tingkat akun untuk ditampilkan.
  static String get label => pro ? 'PRO' : 'GRATIS';

  /// Keterangan singkat tingkat akun.
  static String get keterangan {
    if (pro) return 'Bebas iklan - seluruh iklan dimatikan.';
    return 'Dengan iklan - seluruh menu utama tetap dapat dipakai.';
  }

  /// True bila saklar uji coba sedang menyala.
  static bool get ujiMenyala => _uji;

  /// True bila saklar uji coba boleh dipakai (khusus ADMIN).
  static bool get bolehUji =>
      const ['ADMIN', 'ASS'].contains(RtsSesi.user?.role ?? '');

  static Future<void> muat() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      _uji = prefs.getBool(_kunciUji) ?? false;
    } catch (_) {
      _uji = false;
    }
  }

  static Future<void> setUji(bool nilai) async {
    _uji = nilai;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.setBool(_kunciUji, nilai);
    } catch (_) {
      // pengaturan gagal disimpan, tetap dipakai untuk sesi ini
    }
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN PEMBUKA                                                            */
/* ------------------------------------------------------------------------- */

/// Ditampilkan sesaat setelah aplikasi dibuka.
///
/// Bila ada sesi tersimpan dari fitur "Ingat saya", token diperiksa ke server
/// lebih dahulu. Bila masih berlaku, pengguna langsung masuk ke dashboard
/// tanpa mengetik username dan password.
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  String pesan = 'Memeriksa sesi tersimpan...';
  bool gagal = false;
  bool sedangMemeriksa = false;

  @override
  void initState() {
    super.initState();

    // Penting: pemeriksaan dijalankan SETELAH tampilan pertama selesai
    // dibangun. Bila Navigator dipanggil langsung dari initState, Flutter
    // masih dalam proses membangun tampilan dan perpindahan halaman ditolak,
    // sehingga aplikasi berhenti pada layar kosong (layar hitam).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _periksa();
    });
  }

  Future<void> _periksa() async {
    if (sedangMemeriksa) return;

    sedangMemeriksa = true;

    setState(() {
      pesan = 'Memeriksa sesi tersimpan...';
      gagal = false;
    });

    final String token = RtsSesi.token;
    final RtsUser? user = RtsSesi.user;

    if (token.isEmpty || user == null) {
      sedangMemeriksa = false;
      _keLogin();
      return;
    }

    setState(() => pesan = 'Menyambungkan ke ${RtsConfig.server.nama}...');

    try {
      final ApiClient api = ApiClient(token: token);
      final Map<String, dynamic> data = await api.get('session_check.php');

      final RtsUser userTerbaru = RtsUser.fromJson(
        ((data['user'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

      // Keadaan langganan terbaru: masa PRO yang sudah berakhir langsung
      // terlihat dan iklan kembali tampil.
      RtsLangganan.sekarang = RtsLangganan.dariBalasan(data);

      // Data akun diperbarui, misalnya bila role atau district berubah.
      await RtsSesi.simpan(token, userTerbaru);

      if (!mounted) return;

      sedangMemeriksa = false;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DashboardPage(user: userTerbaru, token: token),
        ),
      );
    } on ApiException catch (error) {
      sedangMemeriksa = false;

      if (!mounted) return;

      if (error.unauthorized) {
        // Token ditolak server: sesi dibuang, pengguna login kembali.
        await RtsSesi.hapus(hapusPilihan: false);

        if (!mounted) return;

        rtsShowMessage(context, error.message);
        _keLogin();
      } else {
        setState(() {
          gagal = true;
          pesan = error.message;
        });
      }
    } catch (_) {
      sedangMemeriksa = false;

      if (!mounted) return;

      setState(() {
        gagal = true;
        pesan = 'Tidak dapat memeriksa sesi. Periksa koneksi internet Anda.';
      });
    }
  }

  /// Membuka aplikasi memakai sesi tersimpan TANPA memeriksa ke server.
  ///
  /// Dipakai saat HP tidak ada internet. Seluruh data kasir tersimpan di
  /// dalam HP, sehingga sales tetap dapat mencatat penjualan dan piutang.
  void _lanjutTanpaInternet() {
    final RtsUser? pengguna = RtsSesi.user;
    final String tokenSimpan = RtsSesi.token;

    if (pengguna == null || tokenSimpan.isEmpty) {
      _keLogin();
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => DashboardPage(user: pengguna, token: tokenSimpan),
      ),
    );
  }

  void _keLogin() {
    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RtsUser? user = RtsSesi.user;

    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.86),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 82,
                      height: 82,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [rtsMaroon, rtsMaroonDark],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(74, 14, 20, 0.3),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'R',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 50,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'RTS PANEL',
                      style: TextStyle(
                        color: rtsMaroon,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'BY BENE',
                      style: TextStyle(
                        color: Color(0xff6f625b),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.4,
                      ),
                    ),
                    const SizedBox(height: 34),
                    if (!gagal)
                      const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.6,
                          color: rtsMaroon,
                        ),
                      ),
                    if (gagal)
                      const Icon(
                        Icons.cloud_off_rounded,
                        size: 34,
                        color: rtsTextSecondary,
                      ),
                    const SizedBox(height: 16),
                    if (user != null && !gagal) ...[
                      Text(
                        user.displayName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: rtsTextPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      pesan,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 12.5,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 10),
                    RtsBadge(
                      RtsConfig.server.nama.toUpperCase(),
                      background: RtsConfig.produksi
                          ? const Color(0xffe8f5ec)
                          : const Color(0xfffdf6ec),
                      foreground: RtsConfig.produksi ? rtsGreen : rtsAmber,
                    ),
                    if (gagal) ...[
                      const SizedBox(height: 24),
                      SizedBox(
                        width: 230,
                        height: 50,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: rtsMaroon,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _periksa,
                          icon: const Icon(Icons.refresh_rounded, size: 19),
                          label: const Text(
                            'COBA LAGI',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: 230,
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: rtsMaroon,
                            side: const BorderSide(color: rtsMaroon),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _lanjutTanpaInternet,
                          icon: const Icon(Icons.cloud_off_rounded, size: 18),
                          label: const Text(
                            'LANJUT TANPA INTERNET',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          'Data barang, kasir, dan piutang tersimpan di dalam HP. '
                          'Bila tidak ada internet, Bapak tetap dapat bekerja '
                          'memakai menu Barang Bawaan, Kasir, dan Piutang.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 11.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: () async {
                          await RtsSesi.hapus();
                          _keLogin();
                        },
                        child: const Text(
                          'Masuk manual (hapus sesi tersimpan)',
                          style: TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* LOGIN                                                                      */
/* ------------------------------------------------------------------------- */

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool obscurePassword = true;
  bool rememberMe = RtsSesi.ingatSaya;
  bool isLoading = false;

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> processLogin() async {
    final String username = usernameController.text.trim();
    final String password = passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      rtsShowMessage(context, 'Username dan password wajib diisi.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => isLoading = true);

    try {
      final ApiClient client = ApiClient();
      final Map<String, dynamic> data = await client.post('login.php', {
        'username': username,
        'password': password,
        'device_name': 'Android RTS Panel',
      });

      if (!mounted) return;

      if (data['success'] == true) {
        final RtsUser user = RtsUser.fromJson(
          ((data['user'] as Map?) ?? const {}).cast<String, dynamic>(),
        );
        final String token = (data['token'] ?? '').toString();

        // Keadaan langganan (masa berlaku PRO + uji coba gratis) dari server.
        RtsLangganan.sekarang = RtsLangganan.dariBalasan(data);

        if (rememberMe) {
          await RtsSesi.simpan(token, user);
        } else {
          // Tanpa "Ingat saya", sesi tidak disimpan di HP. Data akun tetap
          // dipegang selama aplikasi terbuka supaya keadaan langganan PRO,
          // foto profil, dan pendaftaran HP untuk pemberitahuan tetap bekerja.
          RtsSesi.token = token;
          RtsSesi.user = user;

          unawaited(RtsPushFcm.daftarkanToken());
        }

        if (!mounted) return;

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => DashboardPage(user: user, token: token),
          ),
        );
      } else {
        rtsShowMessage(context, (data['message'] ?? 'Login gagal.').toString());
      }
    } on ApiException catch (error) {
      if (mounted) rtsShowMessage(context, error.message);
    } catch (_) {
      if (mounted) {
        rtsShowMessage(context, 'Terjadi gangguan saat login. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.82),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 26, 22, 28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      _buildBrand(),
                      const SizedBox(height: 28),
                      _buildLoginCard(),
                      const SizedBox(height: 18),
                      _buildFooterServer(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterServer() {
    final RtsServer server = RtsConfig.server;

    return Column(
      children: [
        Text(
          'RTS Panel By Bene • Versi 1.0.0',
          style: const TextStyle(
            color: Color(0xff8d8279),
            fontSize: 12,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 10),
        TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: RtsConfig.produksi
                ? rtsMaroon
                : const Color(0xff7a5a26),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          ),
          onPressed: () => _pilihServer(),
          icon: Icon(
            RtsConfig.produksi
                ? Icons.verified_user_outlined
                : Icons.science_outlined,
            size: 17,
          ),
          label: Text(
            '${server.nama} • ${server.database}',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pilihServer() async {
    final int? pilihan = await showServerPicker(context);

    if (pilihan == null || pilihan == RtsConfig.indeksServer) return;

    await RtsConfig.simpan(pilihan);
    await RtsSesi.hapus(hapusPilihan: false);

    if (!mounted) return;

    rtsShowMessage(
      context,
      'Server diubah ke ${rtsServers[pilihan].nama}. Silakan login kembali.',
      success: true,
    );

    setState(() {
      usernameController.clear();
      passwordController.clear();
    });
  }

  Widget _buildBrand() {
    return Column(
      children: [
        Container(
          width: 74,
          height: 74,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [rtsMaroon, rtsMaroonDark],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color.fromRGBO(74, 14, 20, 0.28),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'R',
              style: TextStyle(
                color: Colors.white,
                fontSize: 46,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'RTS PANEL',
          style: TextStyle(
            color: rtsMaroon,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.4,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'BY BENE',
          style: TextStyle(
            color: Color(0xff6f625b),
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 3.4,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return RtsCard(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Masuk Akun',
            style: TextStyle(
              color: rtsTextPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Gunakan username dan password website RTS Panel.',
            style: TextStyle(color: rtsTextSecondary, fontSize: 13.5),
          ),
          const SizedBox(height: 24),
          _buildField(
            controller: usernameController,
            label: 'Username',
            hint: 'Masukkan username',
            icon: Icons.person_outline,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 15),
          _buildField(
            controller: passwordController,
            label: 'Password',
            hint: 'Masukkan password',
            icon: Icons.lock_outline,
            obscureText: obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => processLogin(),
            suffix: IconButton(
              splashRadius: 20,
              onPressed: () => setState(() => obscurePassword = !obscurePassword),
              icon: Icon(
                obscurePassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: const Color(0xff6d514a),
                size: 21,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              SizedBox(
                height: 40,
                width: 40,
                child: Checkbox(
                  value: rememberMe,
                  activeColor: rtsMaroon,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) {
                    final bool pilihan = value ?? false;
                    setState(() => rememberMe = pilihan);
                    RtsSesi.simpanPilihanIngat(pilihan);
                  },
                ),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Ingat saya (tidak perlu login ulang)',
                  maxLines: 2,
                  style: TextStyle(color: Color(0xff6f625b), fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 54,
            child: FilledButton(
              onPressed: isLoading ? null : processLogin,
              style: FilledButton.styleFrom(
                backgroundColor: rtsMaroon,
                disabledBackgroundColor: const Color(0xffc9a2a6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'MASUK',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.6,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required TextInputAction textInputAction,
    bool obscureText = false,
    Widget? suffix,
    void Function(String)? onSubmitted,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: const Color(0xff6d514a), size: 21),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xfff8f4ef),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
        labelStyle: const TextStyle(fontSize: 14),
        hintStyle: const TextStyle(fontSize: 14, color: Color(0xffa99d94)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* DASHBOARD                                                                  */
/* ------------------------------------------------------------------------- */

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

/// Beranda RTS Panel.
///
/// Susunannya dibuat rapat dan ringkas supaya tampil rapi pada semua ukuran
/// layar HP:
///   1. Bilah atas    : identitas aplikasi, server, pemberitahuan, keluar
///   2. Kotak akun    : nama, username, laporan cuaca hari ini, district
///   3. Kotak iklan   : iklan banner AdMob
///   4. Menu utama    : enam kartu menu
///   5. Keterangan    : versi aplikasi dan server yang dipakai
///
/// Keterangan lengkap akun dipindahkan ke halaman Profil agar beranda bersih.
class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  RtsUser get user => widget.user;
  String get token => widget.token;

  /// True bila pemeriksaan di HP menyatakan akun ini berhak memakai fitur PRO.
  ///
  /// Dipakai supaya kartu menu PRO langsung terbuka sesudah pembayaran
  /// disetujui ADMIN, walaupun data akun pada sesi masih yang lama.
  bool _proLuring = false;

  /// Menu Utama dan Menu PRO di Beranda dapat dilipat (MINIMIZE) supaya
  /// tampilan HP tidak terlalu penuh. Pilihan ini diingat di HP.
  bool _menuUtamaTerbuka = true;
  bool _menuProTerbuka = true;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    unawaited(_muatLipatMenu());

    // Dijalankan setelah tampilan pertama selesai dibangun, supaya pemeriksaan
    // versi dan laporan cuaca tidak menghambat pembukaan beranda.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      RtsCuaca.muat(paksa: true).then((_) {
        if (mounted) setState(() {});
      });

      RtsPembaruan.periksaOtomatis(context);

      // Sekali saat beranda dibuka: periksa apakah akun sudah berhak PRO.
      unawaited(_periksaHakPro());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Saat aplikasi dibuka kembali dari latar belakang (misalnya sesudah sales
  /// membayar dan ADMIN menyetujui pembayarannya), status PRO langsung
  /// diperiksa ulang supaya menu PRO tidak menunggu lama.
  @override
  void didChangeAppLifecycleState(AppLifecycleState keadaan) {
    if (keadaan != AppLifecycleState.resumed) return;

    unawaited(_periksaHakPro());
  }

  /// Membaca pilihan lipatan menu yang tersimpan di HP.
  Future<void> _muatLipatMenu() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      final bool utama = prefs.getBool('rts_lipat_menu_utama') ?? true;
      final bool pro = prefs.getBool('rts_lipat_menu_pro') ?? true;

      if (!mounted) return;

      setState(() {
        _menuUtamaTerbuka = utama;
        _menuProTerbuka = pro;
      });
    } catch (_) {
      // Simpanan tidak terbaca: menu tetap ditampilkan seluruhnya.
    }
  }

  /// Tombol MINIMIZE / BUKA pada judul bagian menu.
  Widget _tombolLipat({required bool terbuka, required VoidCallback onTap}) {
    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: rtsMaroon,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: const Size(0, 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        terbuka ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
        size: 17,
      ),
      label: Text(
        terbuka ? 'MINIMIZE' : 'BUKA',
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  /// Memeriksa hak PRO dari simpanan di HP / server, lalu menyimpan hasilnya
  /// pada sesi supaya seluruh halaman memakai keadaan yang terbaru.
  Future<void> _periksaHakPro({bool lapor = false}) async {
    if (_akunPro) {
      if (lapor && mounted) {
        rtsShowMessage(
          context,
          'Akun PRO sudah aktif. Seluruh menu PRO dapat dibuka.',
          success: true,
        );
      }

      return;
    }

    bool boleh = false;

    try {
      // Keterangan akun (alamat server + token) diserahkan lebih dahulu
      // supaya pemeriksaan PRO ini dapat menghubungi server.
      await RtsKasirLokal.aku.atur(
        baseUrl: RtsConfig.baseUrl,
        token: token,
        pengguna: user.toJson(),
      );

      final Map<String, dynamic> akses =
          await RtsKasirLokal.aku.akses(paksa: true);

      boleh = akses['boleh'] == true;
    } catch (_) {
      boleh = false;
    }

    // Jawaban di HP masih "belum boleh": bertanya langsung ke server sekali.
    // Inilah penawar utama bila pembayaran sudah disetujui ADMIN tetapi
    // jawaban lama masih tersimpan di HP.
    if (!boleh) {
      boleh = await RtsAkunSegar.periksa(token);
    }

    if (!mounted) return;

    if (!boleh) {
      if (lapor) {
        rtsShowMessage(
          context,
          'Akun ini masih terbaca GRATIS. Pastikan pembayaran sudah disetujui '
          'ADMIN, lalu tekan SINKRON AKUN pada menu Sinkronisasi.',
        );
      }

      return;
    }

    setState(() => _proLuring = true);

    // Data akun pada sesi diperbarui (tersimpan di HP) supaya halaman Kasir,
    // Peta, dan lain-lain juga melihat status PRO ini.
    await RtsSesi.simpan(token, user.copyWith(akunPro: true));

    if (!mounted || !lapor) return;

    rtsShowMessage(
      context,
      'Akun PRO sudah aktif. Seluruh menu PRO dapat dibuka.',
      success: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.9),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 26),
                    children: [
                      _buildMemberCard(),
                      const SizedBox(height: 14),
                      const RtsBannerIklan(),
                      const SizedBox(height: 18),
                      RtsSectionTitle(
                        'Menu Utama',
                        trailing: _tombolLipat(
                          terbuka: _menuUtamaTerbuka,
                          onTap: () {
                            final bool baru = !_menuUtamaTerbuka;

                            setState(() => _menuUtamaTerbuka = baru);
                            unawaited(rtsSimpanLipatMenu('utama', baru));
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (_menuUtamaTerbuka)
                        _buildMenuGrid(context, _menuUtama)
                      else
                        const Text(
                          'Menu Utama disembunyikan agar Beranda lebih ringkas. '
                          'Tekan BUKA untuk menampilkan kembali.',
                          style: TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      const SizedBox(height: 20),
                      RtsSectionTitle(
                        'Menu PRO',
                        trailing: _tombolLipat(
                          terbuka: _menuProTerbuka,
                          onTap: () {
                            final bool baru = !_menuProTerbuka;

                            setState(() => _menuProTerbuka = baru);
                            unawaited(rtsSimpanLipatMenu('pro', baru));
                          },
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (_menuProTerbuka) ...[
                        const Text(
                          'Fitur Barang Bawaan, Kasir, Piutang, Peta Customer, '
                          'Radar Customer, Rute Plan, dan Printer - tersedia '
                          'untuk akun PRO.',
                          style: TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildMenuGrid(context, _menuPro),
                      ] else
                        const Text(
                          'Menu PRO disembunyikan agar Beranda lebih ringkas. '
                          'Tekan BUKA untuk menampilkan kembali.',
                          style: TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      const SizedBox(height: 18),
                      const RtsIklanAsli(),
                      _buildFooterInfo(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [rtsMaroon, rtsMaroonDark],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Text(
                'R',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'RTS PANEL',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                Text(
                  'By Bene',
                  style: TextStyle(
                    color: rtsTextSecondary.withValues(alpha: 0.9),
                    fontSize: 10.5,
                    letterSpacing: 1.4,
                  ),
                ),
              ],
            ),
          ),
          RtsBadge(
            RtsConfig.server.nama.toUpperCase(),
            background: RtsConfig.produksi
                ? const Color(0xffe8f5ec)
                : const Color(0xfffdf6ec),
            foreground: RtsConfig.produksi ? rtsGreen : rtsAmber,
          ),
          RtsBellNotifikasi(user: user, token: token),
          IconButton(
            tooltip: 'Keluar',
            visualDensity: VisualDensity.compact,
            onPressed: () => _confirmLogout(context),
            icon: const Icon(Icons.logout_rounded, color: rtsTextPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(17, 14, 15, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.28),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'AKUN RTS PANEL',
                style: TextStyle(
                  color: Color(0xccffffff),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const Spacer(),
              RtsBadge(
                user.role.isEmpty ? '-' : user.role,
                background: Colors.white.withValues(alpha: 0.18),
                foreground: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              RtsFotoProfil(
                ukuran: 46,
                bolehGanti: true,
                latarBelakang: const Color(0x2effffff),
                garisTepi: const Color(0x4dffffff),
                warnaHuruf: Colors.white,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.username.isEmpty ? '-' : '@${user.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xb3ffffff),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const RtsKotakCuaca(),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildCardInfo(
                  'District',
                  user.salesDistrict.isEmpty
                      ? 'Semua District'
                      : user.salesDistrict,
                ),
              ),
              Container(
                width: 1,
                height: 28,
                color: Colors.white.withValues(alpha: 0.18),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 14),
                  child: _buildCardInfo(
                    'Salesman',
                    user.salesman.isEmpty ? '-' : user.salesman,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCardInfo(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xb3ffffff),
            fontSize: 10.5,
            letterSpacing: 0.7,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  /// Menu UTAMA: fitur yang dipakai semua akun.
  static const List<_MenuData> _menuUtama = <_MenuData>[
    _MenuData(
      title: 'Master Customer',
      subtitle: 'Data toko & GSP',
      icon: Icons.storefront_outlined,
    ),
    _MenuData(
      title: 'Pengajuan',
      subtitle: 'Ajukan & tinjau',
      icon: Icons.assignment_outlined,
    ),
    _MenuData(
      title: 'GSP',
      subtitle: 'Galan Strategist Partner',
      icon: Icons.handshake_outlined,
    ),
    _MenuData(
      title: 'Notifikasi',
      subtitle: 'Pemberitahuan',
      icon: Icons.notifications_none_rounded,
    ),
    _MenuData(
      title: 'Sinkronisasi',
      subtitle: 'Tarik data',
      icon: Icons.sync_rounded,
    ),
    _MenuData(
      title: 'Profil',
      subtitle: 'Akun pengguna',
      icon: Icons.person_outline_rounded,
    ),
    _MenuData(
      title: 'Pengaturan',
      subtitle: 'Server & aplikasi',
      icon: Icons.settings_outlined,
    ),
  ];

  /// Menu PRO: fitur Barang Bawaan, Kasir, Piutang, dan Printer.
  /// Dipisahkan dari Menu Utama dan diletakkan di bawahnya.
  static const List<_MenuData> _menuPro = <_MenuData>[
    _MenuData(
      title: 'Barang Bawaan',
      subtitle: 'Produk & stok',
      icon: Icons.inventory_2_outlined,
      pro: true,
    ),
    _MenuData(
      title: 'Kasir',
      subtitle: 'Jual & cetak struk',
      icon: Icons.point_of_sale_outlined,
      pro: true,
    ),
    _MenuData(
      title: 'Piutang',
      subtitle: 'Utang & titip',
      icon: Icons.request_quote_outlined,
      pro: true,
    ),
    _MenuData(
      title: 'Printer & Struk',
      subtitle: 'Bluetooth & template',
      icon: Icons.print_outlined,
      pro: true,
    ),
    _MenuData(
      title: 'Peta Customer',
      subtitle: 'Sebaran & filter warna',
      icon: Icons.map_outlined,
      pro: true,
    ),
    _MenuData(
      title: 'Radar Customer',
      subtitle: 'Toko terdekat dari saya',
      icon: Icons.radar_rounded,
      pro: true,
    ),
    _MenuData(
      title: 'Rute Plan',
      subtitle: 'Urutan dari kantor & pensil',
      icon: Icons.route_outlined,
      pro: true,
    ),
  ];

  Widget _buildMenuGrid(BuildContext context, List<_MenuData> menus) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: menus.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 110,
      ),
      itemBuilder: (context, index) {
        final _MenuData menu = menus[index];

        return Material(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openMenu(context, menu.title),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: rtsCardBorder),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(74, 44, 34, 0.07),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xfffaecee),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(menu.icon, color: rtsMaroon, size: 19),
                  ),
                  const Spacer(),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          menu.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (menu.pro && !_akunPro)
                        const Padding(
                          padding: EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: rtsTextSecondary,
                          ),
                        ),
                      if (menu.pro)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xfffdf1d8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'PRO',
                            style: TextStyle(
                              color: rtsAmber,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    menu.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFooterInfo() {
    final RtsServer server = RtsConfig.server;
    final bool produksi = server.produksi;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: produksi ? const Color(0xffeef5ef) : const Color(0xfffdf6ec),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: produksi
              ? const Color(0xffd5e6d9)
              : const Color(0xfff0e2cf),
        ),
      ),
      child: Row(
        children: [
          Icon(
            produksi ? Icons.verified_user_outlined : Icons.science_outlined,
            color: produksi ? rtsGreen : const Color(0xff9a6b23),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  color: produksi
                      ? const Color(0xff2f6b45)
                      : const Color(0xff7a5a26),
                  fontSize: 11.5,
                  height: 1.45,
                ),
                children: [
                  TextSpan(text: 'Versi ${RtsVersi.label} • '),
                  TextSpan(
                    text: 'Terhubung ke ${server.nama}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: produksi
                        ? '. Perubahan langsung memengaruhi data asli.'
                        : '. Ini database uji coba, bukan data asli.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// True bila akun ini sedang berhak memakai fitur PRO.
  /// Sumber: data server (login / session_check), keadaan langganan terakhir,
  /// atau pemeriksaan yang tersimpan di HP (30 hari).
  bool get _akunPro =>
      RtsTingkatAkun.pro || RtsLangganan.sekarang.pro || _proLuring;

  /// Memeriksa hak PRO termasuk simpanan pemeriksaan luring.
  ///
  /// Bila hasilnya "boleh", keadaan itu langsung disimpan supaya kunci pada
  /// kartu menu PRO hilang tanpa perlu membuka ulang aplikasi. Inilah yang
  /// membuat akun yang BARU diperpanjang langsung terbuka.
  Future<bool> _bolehPro() async {
    if (_akunPro) return true;

    bool boleh = false;

    try {
      // Keterangan akun diserahkan lebih dahulu supaya pemeriksaan dapat
      // menghubungi server (paksa: true = jangan memakai jawaban lama).
      await RtsKasirLokal.aku.atur(
        baseUrl: RtsConfig.baseUrl,
        token: token,
        pengguna: user.toJson(),
      );

      final Map<String, dynamic> akses =
          await RtsKasirLokal.aku.akses(paksa: true);

      boleh = akses['boleh'] == true;
    } catch (_) {
      boleh = false;
    }

    // Masih "belum boleh": periksa langsung ke server (sesi + langganan).
    if (!boleh) {
      boleh = await RtsAkunSegar.periksa(token);

      if (boleh) {
        try {
          await RtsKasirLokal.aku.atur(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          );

          await RtsKasirLokal.aku.akses(paksa: true);
        } catch (_) {
          // pemeriksaan di HP gagal disegarkan: kartu tetap dibuka
        }
      }
    }

    if (!mounted) return boleh;

    if (!boleh) return false;

    _proLuring = true;
    setState(() {});

    if (!RtsTingkatAkun.pro) {
      unawaited(RtsSesi.simpan(token, user.copyWith(akunPro: true)));
    }

    return true;
  }

  /// Kartu PRO yang ditekan akun GRATIS: dijelaskan dan ditawarkan langganan.
  Future<void> _tawaranPro(BuildContext context, String fitur) async {
    final bool? buka = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const <Widget>[
            Icon(Icons.workspace_premium_rounded, color: rtsAmber),
            SizedBox(width: 9),
            Text(
              'Fitur PRO',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        content: Text(
          'Menu "$fitur" termasuk fitur PRO.\n\n'
          'Akun GRATIS tetap dapat memakai seluruh Menu Utama. Untuk membuka '
          'menu ini, aktifkan Langganan PRO '
          '(Rp${rtsRupiah(RtsLangganan.sekarang.harga)} / '
          '${RtsLangganan.sekarang.durasiHari} hari) atau pakai uji coba '
          '${RtsLangganan.sekarang.trialHari} hari GRATIS.\n\n'
          'Sudah top up / sudah bayar? Buka menu Sinkronisasi lalu tekan '
          'SINKRON AKUN supaya status PRO dari server langsung dibaca.',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('BUKA LANGGANAN PRO'),
          ),
        ],
      ),
    );

    if (buka == true && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LanggananProPage(user: user, token: token),
        ),
      );
    }
  }

  Future<void> _openMenu(BuildContext context, String menu) async {
    // Pengaman Menu PRO: akun GRATIS diarahkan ke halaman Langganan PRO.
    final bool menuPro =
        _menuPro.any((_MenuData satu) => satu.title == menu);

    if (menuPro) {
      final bool boleh = await _bolehPro();

      if (!context.mounted) return;

      if (!boleh) {
        await _tawaranPro(context, menu);
        return;
      }
    }

    if (menu == 'Master Customer') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerListPage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'Pengajuan') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RequestListPage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'GSP') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GspMenuPage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'Barang Bawaan') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsBarangBawaanPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Kasir') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsKasirPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Piutang') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsPiutangPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Printer & Struk') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsPrinterPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Peta Customer') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsPetaCustomerPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Radar Customer') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsRadarPage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Rute Plan') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RtsRutePage(
            baseUrl: RtsConfig.baseUrl,
            token: token,
            pengguna: (RtsSesi.user ?? user).toJson(),
          ),
        ),
      );
      return;
    }

    if (menu == 'Notifikasi') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => NotificationPage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'Profil') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfilePage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'Sinkronisasi') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SyncPage(user: user, token: token),
        ),
      );
      return;
    }

    if (menu == 'Pengaturan') {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsPage(user: user, token: token),
        ),
      );
      return;
    }

    _comingSoon(context, menu);
  }

  void _comingSoon(BuildContext context, String fitur) {
    rtsShowMessage(context, '$fitur sedang disiapkan pada tahap berikutnya.');
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final bool? keluar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Keluar Akun',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Anda yakin ingin keluar dari RTS Panel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('KELUAR'),
          ),
        ],
      ),
    );

    if (keluar == true && context.mounted) {
      await RtsSesi.hapus();

      if (!context.mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => false,
      );
    }
  }
}

/// Mengingat pilihan lipatan menu pada Beranda (Menu Utama / Menu PRO).
Future<void> rtsSimpanLipatMenu(String bagian, bool terbuka) async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      bagian == 'pro' ? 'rts_lipat_menu_pro' : 'rts_lipat_menu_utama',
      terbuka,
    );
  } catch (_) {
    // Gagal menyimpan bukan masalah besar: menu tetap dapat dipakai.
  }
}

class _MenuData {
  const _MenuData({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.pro = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  /// Menu PRO (Barang Bawaan, Kasir, Piutang, Printer) diberi penanda.
  final bool pro;
}

/* ------------------------------------------------------------------------- */
/* MASTER CUSTOMER                                                            */
/* ------------------------------------------------------------------------- */

class CustomerListPage extends StatefulWidget {
  const CustomerListPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<CustomerListPage> createState() => _CustomerListPageState();
}

class _CustomerListPageState extends State<CustomerListPage> {
  static const int _pageSize = 20;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  late final ApiClient api = ApiClient(token: widget.token);

  final List<Customer> customers = [];

  String tipeFilter = '';
  String statusFilter = '';
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  bool tipeAvailable = true;
  int page = 1;
  int total = 0;
  Map<String, int> counts = const {'REGULER': 0, 'GSP': 0, 'total': 0};
  String? errorMessage;

  int get _jumlahReguler => counts['REGULER'] ?? 0;
  int get _jumlahGsp => counts['GSP'] ?? 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final double sisa =
        scrollController.position.maxScrollExtent - scrollController.position.pixels;
    if (sisa < 260) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      loading = true;
      errorMessage = null;
      page = 1;
    });

    try {
      final CustomerPage result = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        customers
          ..clear()
          ..addAll(result.items);
        total = result.total;
        hasMore = result.hasMore;
        page = result.page;
        tipeAvailable = result.tipeAvailable;
        counts = result.counts;
        if (!tipeAvailable) tipeFilter = '';
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.message;
      });
      if (error.unauthorized) await _sesiBerakhir();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Terjadi gangguan saat memuat data customer.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || loading || !hasMore) return;

    setState(() => loadingMore = true);

    try {
      final CustomerPage result = await _fetchPage(page + 1);
      if (!mounted) return;
      setState(() {
        customers.addAll(result.items);
        total = result.total;
        hasMore = result.hasMore;
        page = result.page;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingMore = false);
    }
  }

  Future<CustomerPage> _fetchPage(int targetPage) async {
    final Map<String, dynamic> data = await api.get('customers.php', {
      'q': searchController.text.trim(),
      'tipe': tipeFilter,
      'status': statusFilter,
      'page': targetPage.toString(),
      'limit': _pageSize.toString(),
    });

    return CustomerPage.fromJson(data);
  }

  Future<void> _sesiBerakhir() async {
    await RtsSesi.hapus(hapusPilihan: false);

    if (!mounted) return;

    rtsShowMessage(context, 'Sesi login berakhir. Silakan login kembali.');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsMaroon,
        foregroundColor: Colors.white,
        onPressed: _buatPengajuan,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          'Ajukan',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
        ),
      ),
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _buatPengajuan() async {
    final bool? terkirim = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RequestFormPage(
          user: widget.user,
          token: widget.token,
        ),
      ),
    );

    if (terkirim == true) _loadFirstPage();
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Master Customer',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Data toko dan customer',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loadFirstPage,
            icon: const Icon(Icons.refresh_rounded, color: rtsTextPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadFirstPage(),
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Cari nama toko, ID customer, atau salesman',
                  hintStyle: const TextStyle(fontSize: 13.5),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xff6d514a),
                    size: 21,
                  ),
                  suffixIcon: IconButton(
                    onPressed: _loadFirstPage,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    color: rtsMaroon,
                    tooltip: 'Cari',
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.97),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsCardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildFilters(),
              if (_cakupanTerbatas) ...[
                const SizedBox(height: 10),
                _buildCakupanNotice(),
              ],
              if (!tipeAvailable) ...[
                const SizedBox(height: 10),
                _buildTipeNotice(),
              ],
              const SizedBox(height: 12),
              _buildSummary(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (tipeAvailable) ...[
                _filterChip('Semua Tipe', tipeFilter == '', () {
                  setState(() => tipeFilter = '');
                  _loadFirstPage();
                }),
                const SizedBox(width: 8),
                _filterChip(
                  'Reguler ($_jumlahReguler)',
                  tipeFilter == 'REGULER',
                  () {
                    setState(() => tipeFilter = 'REGULER');
                    _loadFirstPage();
                  },
                ),
                const SizedBox(width: 8),
                _filterChip(
                  'GSP ($_jumlahGsp)',
                  tipeFilter == 'GSP',
                  () {
                    setState(() => tipeFilter = 'GSP');
                    _loadFirstPage();
                  },
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 24, color: rtsCardBorder),
                const SizedBox(width: 8),
              ],
              _filterChip('Semua Status', statusFilter == '', () {
                setState(() => statusFilter = '');
                _loadFirstPage();
              }),
              const SizedBox(width: 8),
              _filterChip('Aktif', statusFilter == 'Aktif', () {
                setState(() => statusFilter = 'Aktif');
                _loadFirstPage();
              }),
              const SizedBox(width: 8),
              _filterChip('Nonaktif', statusFilter == 'Nonaktif', () {
                setState(() => statusFilter = 'Nonaktif');
                _loadFirstPage();
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? rtsMaroon : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? rtsMaroon : rtsCardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : rtsTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildCakupanNotice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xffeaf1fb),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffd3e0f5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.map_outlined,
            color: Color(0xff2b5f9e),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Daftar ini hanya menampilkan customer pada $_cakupanData. '
              'Hubungi Admin bila ada customer yang belum terlihat.',
              style: const TextStyle(
                color: Color(0xff2b5f9e),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipeNotice() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xfffdf6ec),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xfff0e2cf)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xff9a6b23),
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kategori GSP belum terbaca dari server. Kolom tipe_customer belum '
              'terdeteksi pada tabel master_toko, sehingga sementara semua customer '
              'dianggap REGULER. Tambahkan kolom tipe_customer pada database '
              '${RtsConfig.server.database}, lalu tekan muat ulang.',
              style: const TextStyle(
                color: Color(0xff7a5a26),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keterangan cakupan data sesuai peran pengguna.
  String get _cakupanData {
    const List<String> roleSemuaDistrict = ['ADMIN', 'ASS', 'WSS', 'SMST'];

    if (roleSemuaDistrict.contains(widget.user.role)) {
      return 'Semua district';
    }

    final String district = widget.user.salesDistrict.trim();

    if (district.isNotEmpty) {
      return 'District: $district';
    }

    final String salesman = widget.user.salesman.trim();

    if (salesman.isNotEmpty) {
      return 'Salesman: $salesman';
    }

    return 'Belum ada penugasan district';
  }

  /// True bila pengguna hanya melihat sebagian data.
  bool get _cakupanTerbatas =>
      !const ['ADMIN', 'ASS', 'WSS', 'SMST'].contains(widget.user.role);

  Widget _buildSummary() {
    final String cakupan = _cakupanData;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              loading ? 'Memuat data...' : '$total customer ditemukan',
              style: const TextStyle(
                color: rtsTextPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                cakupan,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 11.5,
                ),
              ),
            ),
          ],
        ),
        if (tipeAvailable && !loading) ...[
          const SizedBox(height: 3),
          Text(
            'Reguler $_jumlahReguler • GSP $_jumlahGsp',
            style: const TextStyle(color: rtsTextSecondary, fontSize: 11.5),
          ),
        ],
      ],
    );
  }

  Widget _buildList() {
    if (loading) {
      return const Center(
        child: CircularProgressIndicator(color: rtsMaroon),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 44, color: rtsTextSecondary),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
                onPressed: _loadFirstPage,
                child: const Text('COBA LAGI'),
              ),
            ],
          ),
        ),
      );
    }

    if (customers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 44, color: rtsTextSecondary),
              SizedBox(height: 12),
              Text(
                'Data customer tidak ditemukan.',
                style: TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: rtsMaroon,
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        // Tambahan satu kartu untuk iklan pada urutan paling atas.
        itemCount: customers.length + (loadingMore ? 1 : 0) + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          if (index == 0) return const RtsIklanAsli();

          index -= 1;

          if (index >= customers.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: rtsMaroon,
                  ),
                ),
              ),
            );
          }

          final Customer customer = customers[index];
          return _buildCustomerTile(customer);
        },
      ),
    );
  }

  Widget _buildCustomerTile(Customer customer) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerDetailPage(
                user: widget.user,
                idCustomer: customer.idCustomer,
                token: widget.token,
                preview: customer,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: rtsCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: customer.isGsp
                          ? const Color(0xfffdf3e0)
                          : const Color(0xffeef3fb),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      customer.isGsp
                          ? Icons.local_gas_station_outlined
                          : Icons.storefront_outlined,
                      size: 21,
                      color: customer.isGsp
                          ? rtsAmber
                          : const Color(0xff2b5f9e),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.namaToko.isEmpty ? '-' : customer.namaToko,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          customer.idCustomer.isEmpty
                              ? '-'
                              : customer.idCustomer,
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xffb8aea6),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  RtsBadge(
                    customer.tipeCustomer,
                    background: customer.isGsp
                        ? const Color(0xfffdf3e0)
                        : const Color(0xffeef1f4),
                    foreground: customer.isGsp
                        ? rtsAmber
                        : const Color(0xff5c6b7a),
                  ),
                  const SizedBox(width: 7),
                  RtsBadge(
                    customer.statusAktif,
                    background: customer.isAktif
                        ? const Color(0xffe8f5ec)
                        : const Color(0xfffdeaea),
                    foreground:
                        customer.isAktif ? rtsGreen : const Color(0xffa52020),
                  ),
                  const Spacer(),
                  if (customer.punyaKoordinat)
                    const Icon(
                      Icons.location_on_outlined,
                      size: 17,
                      color: rtsTextSecondary,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              _miniRow(Icons.person_outline_rounded, customer.salesman),
              const SizedBox(height: 5),
              _miniRow(
                Icons.map_outlined,
                customer.salesDistrict.isEmpty
                    ? 'District belum diisi'
                    : customer.salesDistrict,
              ),
              if (customer.alamat.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                _miniRow(Icons.home_outlined, customer.alamat),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xffa99d94)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text.trim().isEmpty ? '-' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* DETAIL CUSTOMER                                                            */
/* ------------------------------------------------------------------------- */

class CustomerDetailPage extends StatefulWidget {
  const CustomerDetailPage({
    super.key,
    required this.user,
    required this.idCustomer,
    required this.token,
    this.preview,
  });

  final RtsUser user;
  final String idCustomer;
  final String token;
  final Customer? preview;

  @override
  State<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends State<CustomerDetailPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  Customer? customer;
  bool loading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    customer = widget.preview;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });

    try {
      final Map<String, dynamic> data = await api.get('customer_detail.php', {
        'id': widget.idCustomer,
      });

      if (!mounted) return;

      setState(() {
        customer = Customer.fromJson(
          ((data['data'] as Map?) ?? const {}).cast<String, dynamic>(),
        );
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Terjadi gangguan saat memuat detail customer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Text(
              'Detail Customer',
              style: TextStyle(
                color: rtsTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded, color: rtsTextPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final Customer? data = customer;

    if (loading && data == null) {
      return const Center(child: CircularProgressIndicator(color: rtsMaroon));
    }

    if (data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  size: 44, color: rtsTextSecondary),
              const SizedBox(height: 12),
              Text(
                errorMessage ?? 'Detail customer tidak tersedia.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
                onPressed: _load,
                child: const Text('COBA LAGI'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        _buildHeaderCard(data),
        const SizedBox(height: 18),
        const RtsSectionTitle('Informasi Toko'),
        const SizedBox(height: 11),
        RtsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              RtsInfoRow('ID Customer', data.idCustomer),
              const RtsDivider(),
              RtsInfoRow('Nama Toko', data.namaToko),
              const RtsDivider(),
              RtsInfoRow('Tipe Customer', data.tipeCustomer),
              const RtsDivider(),
              RtsInfoRow(
                'Status',
                data.statusAktif,
                valueColor: data.isAktif ? rtsGreen : const Color(0xffa52020),
              ),
              const RtsDivider(),
              RtsInfoRow('Alamat', data.alamat),
              const RtsDivider(),
              RtsInfoRow('Hari Kunjungan', data.hari),
              const RtsDivider(),
              RtsInfoRow('Frekuensi Kunjungan', data.kunjungan),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const RtsSectionTitle('Penugasan'),
        const SizedBox(height: 11),
        RtsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              RtsInfoRow('Salesman', data.salesman),
              const RtsDivider(),
              RtsInfoRow('District', data.salesDistrict),
            ],
          ),
        ),
        const SizedBox(height: 18),
        const RtsSectionTitle('Lokasi'),
        const SizedBox(height: 11),
        _buildLocationCard(data),
        const SizedBox(height: 22),
        const RtsIklanAsli(),
        const SizedBox(height: 18),
        _buildAjukanButton(data),
        if (loading) ...[
          const SizedBox(height: 18),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: rtsMaroon),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAjukanButton(Customer data) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: rtsMaroon,
          backgroundColor: Colors.white.withValues(alpha: 0.85),
          side: const BorderSide(color: rtsMaroon, width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        onPressed: () async {
          final bool? terkirim = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => RequestFormPage(
                user: widget.user,
                token: widget.token,
                customer: data,
              ),
            ),
          );

          if (terkirim == true && mounted) {
            rtsShowMessage(
              context,
              'Pengajuan terkirim. Statusnya dapat dilihat pada menu Pengajuan.',
              success: true,
            );
          }
        },
        icon: const Icon(Icons.assignment_add, size: 19),
        label: const Text(
          'AJUKAN PERUBAHAN CUSTOMER',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(Customer data) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.28),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RtsBadge(
                data.tipeCustomer,
                background: Colors.white.withValues(alpha: 0.2),
                foreground: Colors.white,
              ),
              const SizedBox(width: 7),
              RtsBadge(
                data.statusAktif.toUpperCase(),
                background: Colors.white.withValues(alpha: 0.2),
                foreground: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            data.namaToko.isEmpty ? '-' : data.namaToko,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.idCustomer.isEmpty ? '-' : data.idCustomer,
            style: const TextStyle(color: Color(0xb3ffffff), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: Colors.white.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: Color(0xb3ffffff)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  data.salesman.isEmpty ? '-' : data.salesman,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  Widget _buildLocationCard(Customer data) {
    if (!data.punyaKoordinat) {
      return RtsCard(
        child: Row(
          children: [
            const Icon(
              Icons.location_off_outlined,
              color: rtsTextSecondary,
              size: 20,
            ),
            const SizedBox(width: 11),
            const Expanded(
              child: Text(
                'Koordinat lokasi toko belum tersedia.',
                style: TextStyle(color: rtsTextSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RtsInfoRow('Latitude', data.latitude),
          const RtsDivider(),
          RtsInfoRow('Longitude', data.longitude),
          const SizedBox(height: 13),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rtsMaroon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: () => _bukaGoogleMaps(data),
              icon: const Icon(Icons.map_rounded, size: 19),
              label: const Text(
                'BUKA DI GOOGLE MAPS',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.7,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: rtsTextSecondary),
            onPressed: () => _salinKoordinat(data),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text(
              'Salin koordinat',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Membuka aplikasi peta pada titik koordinat customer.
  Future<void> _bukaGoogleMaps(Customer data) async {
    final String lat = data.latitude.trim();
    final String lng = data.longitude.trim();
    final String nama = data.namaToko.trim().isEmpty
        ? 'Customer RTS Panel'
        : data.namaToko.trim();

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
        // lanjut ke alternatif berikutnya
      }
    }

    if (mounted) {
      rtsShowMessage(
        context,
        'Aplikasi peta tidak dapat dibuka. Pastikan Google Maps terpasang.',
      );
    }
  }

  Future<void> _salinKoordinat(Customer data) async {
    final String teks = '${data.latitude.trim()}, ${data.longitude.trim()}';

    await Clipboard.setData(ClipboardData(text: teks));

    if (mounted) {
      rtsShowMessage(context, 'Koordinat disalin: $teks', success: true);
    }
  }
}

/* ------------------------------------------------------------------------- */
/* LAYANAN PEMBERITAHUAN HP                                                   */
/* ------------------------------------------------------------------------- */

/// Kunci navigasi global. Dipakai untuk membuka menu Pemberitahuan saat
/// pemberitahuan pada layar HP ditekan.
final GlobalKey<NavigatorState> rtsNavigatorKey = GlobalKey<NavigatorState>();

/// Menampilkan pemberitahuan pada bar status dan layar kunci HP.
/* ------------------------------------------------------------------------- */
/* PEMBERITAHUAN HP LEWAT FIREBASE                                            */
/* ------------------------------------------------------------------------- */

/// Menangani pemberitahuan yang masuk ketika aplikasi sedang TIDAK dibuka.
///
/// Fungsi ini wajib berada di tingkat paling atas (bukan di dalam kelas) dan
/// diberi penanda vm:entry-point, sebab Android menjalankannya pada proses
/// terpisah saat aplikasi sedang ditutup.
@pragma('vm:entry-point')
Future<void> rtsPesanFirebaseLatar(RemoteMessage pesan) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    return;
  }

  await RtsPushFcm.tandaiDiketahui(pesan);
}

/// Pengingat pembaruan aplikasi yang muncul pada layar HP.
///
/// Dipakai untuk dua hal:
///   1. Memberitahukan adanya versi baru walaupun aplikasi sedang TIDAK
///      dibuka - baik dari pemeriksaan di dalam aplikasi (setiap kali
///      aplikasi dibuka) maupun dari pemberitahuan yang dikirim server
///      ketika Admin mengunggah APK baru.
///   2. Mengingatkan BERULANG setiap jam sampai aplikasi benar-benar
///      diperbarui. Pengingat ini berhenti sendiri setelah versi terpasang
///      sudah sama dengan versi di server.
///
/// Pada layar HP, pemberitahuan ini memuat tombol **UPDATE**. Menekan tombol
/// (atau pemberitahuannya) membuka aplikasi; aplikasi lalu memeriksa versi
/// dan menampilkan kotak pembaruan beserta tombol unduh.
class RtsPengingatPembaruan {
  const RtsPengingatPembaruan._();

  /// Nomor pemberitahuan (tetap, supaya tidak menumpuk di layar HP).
  static const int idSekarang = 9001;

  /// Nomor pengingat berulang.
  static const int idBerkala = 9002;

  /// Menampilkan pengingat pembaruan.
  ///
  /// Bila [info] kosong atau versinya TIDAK lebih baru daripada versi yang
  /// terpasang, seluruh pengingat yang sedang berjalan dibatalkan - inilah
  /// yang membuat pemberitahuan berhenti sendiri setelah aplikasi diperbarui.
  static Future<void> perbarui(RtsInfoVersi? info) async {
    if (info == null || info.kode <= RtsVersi.kode) {
      await hentikan();
      return;
    }

    final String judul = info.wajib
        ? 'Pembaruan WAJIB RTS Panel'
        : 'Versi Baru RTS Panel Tersedia';

    final String pesan = 'Versi terpasang: ${RtsVersi.label}. '
        'Versi terbaru: ${info.nama} (${info.kode}). '
        'Tekan UPDATE untuk memperbarui aplikasi.'
        '${info.catatan.isEmpty ? '' : '\n\n${info.catatan}'}';

    await RtsLayananNotif.tampilkan(
      id: idSekarang,
      judul: judul,
      pesan: pesan,
      tombol: 'UPDATE',
      payload: 'pembaruan',
    );

    await RtsLayananNotif.berkala(
      id: idBerkala,
      judul: judul,
      pesan: pesan,
    );
  }

  /// Membatalkan seluruh pengingat pembaruan.
  static Future<void> hentikan() async {
    await RtsLayananNotif.hentikan(idSekarang);
    await RtsLayananNotif.hentikan(idBerkala);
  }

  /// Dipanggil ketika server mengirim pemberitahuan berisi keterangan versi.
  ///
  /// Keterangan versi itu langsung dipakai - jadi pengingat dan tombol UPDATE
  /// muncul walaupun petugas belum membuka aplikasinya.
  static Future<void> dariServer(Map<String, dynamic> data) async {
    final RtsInfoVersi? info = RtsInfoVersi.fromJson(data);

    if (info == null) return;

    RtsPembaruan.terbaru = info;

    await perbarui(info);

    // Bila aplikasi sedang terbuka, kotak pembaruan langsung ditampilkan
    // supaya petugas dapat langsung menekan tombol unduh.
    final BuildContext? konteks = rtsNavigatorKey.currentContext;

    if (konteks != null && konteks.mounted) {
      await RtsPembaruan.tampilkan(konteks, info);
    }
  }
}

/// Pemberitahuan HP lewat Firebase Cloud Messaging.
///
/// Dipakai untuk pemberitahuan yang harus tetap masuk walaupun aplikasi
/// ditutup sepenuhnya oleh pengguna - hal yang tidak dapat dilakukan oleh
/// pemeriksaan berkala di dalam aplikasi.
///
/// Seluruh bagian di kelas ini dibuat "aman gagal": bila Firebase belum
/// disiapkan, tidak ada google-services.json, atau tidak ada internet,
/// aplikasi tetap berjalan seperti biasa dan pemberitahuan di dalam aplikasi
/// tetap muncul dari pemeriksaan berkala (RtsPemantauNotif).
class RtsPushFcm {
  static bool _siap = false;
  static bool _pernahGagal = false;

  /// Keterangan singkat, ditampilkan pada halaman Pengaturan.
  static String status = 'Belum disiapkan';

  /// Menyiapkan Firebase dan pemantau pemberitahuan. Aman dipanggil berkali-kali.
  static Future<void> siapkan() async {
    if (_siap || _pernahGagal) return;

    try {
      // Saluran pemberitahuan dibuat lebih dahulu, supaya pemberitahuan dari
      // Firebase masuk ke saluran yang sama dengan pemberitahuan aplikasi.
      await RtsLayananNotif.siapkan();

      await Firebase.initializeApp();

      // Penangan pemberitahuan saat aplikasi sedang TIDAK dibuka.
      // Wajib didaftarkan sebelum aplikasi menampilkan layar.
      FirebaseMessaging.onBackgroundMessage(rtsPesanFirebaseLatar);

      final FirebaseMessaging pesan = FirebaseMessaging.instance;

      // Permintaan izin pemberitahuan (Android 13 ke atas).
      await pesan.requestPermission();

      // 1. Pemberitahuan masuk saat aplikasi sedang dibuka.
      //    Android tidak menampilkannya sendiri, jadi ditampilkan dari sini.
      FirebaseMessaging.onMessage.listen((RemoteMessage masuk) {
        unawaited(_tangani(masuk, tampilkan: true));
      });

      // 2. Pemberitahuan ditekan saat aplikasi ada di latar belakang.
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage masuk) {
        unawaited(_tangani(masuk, tampilkan: false));
        unawaited(bukaMenuPemberitahuan());
      });

      // 3. Aplikasi dibuka dari keadaan tertutup karena pemberitahuan ditekan.
      final RemoteMessage? awal = await pesan.getInitialMessage();

      if (awal != null) {
        await _tangani(awal, tampilkan: false);
        unawaited(bukaMenuPemberitahuan());
      }

      // 4. Bila token perangkat berubah (misalnya aplikasi dipasang ulang),
      //    daftarkan ulang ke server.
      pesan.onTokenRefresh.listen((String tokenBaru) {
        unawaited(_simpanKeServer(tokenBaru));
      });

      _siap = true;
      status = 'Aktif (pemberitahuan tetap masuk walau aplikasi ditutup)';
    } catch (galat) {
      _pernahGagal = true;
      final String ringkas = galat.toString().split('\n').first;
      status = 'Belum aktif - $ringkas';
    }
  }

  /// Mendaftarkan HP ini ke server supaya ikut menerima pemberitahuan.
  static Future<void> daftarkanToken() async {
    if (!_siap && !_pernahGagal) {
      await siapkan();
    }

    if (!_siap) return;

    try {
      final String? tokenPerangkat = await FirebaseMessaging.instance.getToken();

      if (tokenPerangkat == null || tokenPerangkat.isEmpty) return;

      await _simpanKeServer(tokenPerangkat);
    } catch (_) {
      // Diabaikan: pendaftaran dicoba lagi pada login berikutnya.
    }
  }

  /// Melepas HP ini dari akun, dipakai saat Keluar.
  static Future<void> hapusToken() async {
    try {
      if (RtsSesi.token.isEmpty) return;

      // Bila Firebase tidak dipakai di HP ini, tidak ada yang perlu dilepas.
      if (!_siap) return;

      final String? tokenPerangkat = await FirebaseMessaging.instance.getToken();

      if (tokenPerangkat == null || tokenPerangkat.isEmpty) return;

      final ApiClient api = ApiClient(token: RtsSesi.token);

      await api
          .post('device_token.php', <String, dynamic>{
            'action': 'hapus',
            'token': tokenPerangkat,
          })
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Diabaikan: Keluar harus tetap berhasil walau bagian ini gagal.
    }
  }

  /// Menandai pemberitahuan sebagai sudah diketahui.
  ///
  /// Kunci yang sama dipakai oleh pemeriksaan berkala di dalam aplikasi
  /// (RtsPemantauNotif), sehingga satu pemberitahuan tidak muncul dua kali.
  static Future<void> tandaiDiketahui(RemoteMessage pesan) async {
    try {
      final String kunci = pesan.data['kunci']?.toString() ?? '';

      if (kunci.isEmpty) return;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> lama =
          prefs.getStringList('rts_notif_diketahui') ?? <String>[];

      if (lama.contains(kunci)) return;

      lama.add(kunci);

      final List<String> disimpan =
          lama.length > 400 ? lama.sublist(lama.length - 400) : lama;

      await prefs.setStringList('rts_notif_diketahui', disimpan);
    } catch (_) {
      // Diabaikan.
    }
  }

  /// Membuka menu Pemberitahuan di dalam aplikasi.
  static Future<void> bukaMenuPemberitahuan() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));

    final RtsUser? user = RtsSesi.user;
    final String token = RtsSesi.token;

    if (user == null || token.isEmpty) return;

    rtsNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => NotificationPage(user: user, token: token),
      ),
    );
  }

  /// Menyimpan token perangkat ke server.
  static Future<void> _simpanKeServer(String tokenPerangkat) async {
    try {
      if (RtsSesi.token.isEmpty) return;

      final ApiClient api = ApiClient(token: RtsSesi.token);

      await api
          .post('device_token.php', <String, dynamic>{
            'token': tokenPerangkat,
            'platform': 'android',
          })
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Diabaikan.
    }
  }

  /// Menampilkan pemberitahuan yang masuk saat aplikasi sedang dibuka.
  static Future<void> _tangani(
    RemoteMessage pesan, {
    required bool tampilkan,
  }) async {
    try {
      await tandaiDiketahui(pesan);

      // Pemberitahuan dari server yang memuat keterangan versi baru:
      // ditangani oleh RtsPengingatPembaruan supaya tombol UPDATE muncul dan
      // kotak pembaruan langsung tampil bila aplikasi sedang dibuka.
      final String tipe = pesan.data['tipe']?.toString() ?? '';

      if (tipe.toLowerCase() == 'versi') {
        await RtsPengingatPembaruan.dariServer(
          pesan.data.map((String kunci, Object? nilai) =>
              MapEntry<String, dynamic>(kunci, nilai)),
        );

        return;
      }

      if (!tampilkan) return;

      final String kunci = pesan.data['kunci']?.toString() ?? '';
      final String judul =
          pesan.notification?.title?.trim().isNotEmpty == true
              ? pesan.notification!.title!.trim()
              : 'Pemberitahuan RTS Panel';
      final String isi = pesan.notification?.body?.trim() ?? '';

      await RtsLayananNotif.tampilkan(
        id: (kunci.isEmpty ? judul.hashCode : kunci.hashCode) & 0x7fffffff,
        judul: judul,
        pesan: isi.isEmpty ? 'Ada pemberitahuan baru dari RTS Panel.' : isi,
        // Tipe dikirim sebagai payload, supaya saat pemberitahuan ditekan
        // aplikasi tahu halaman mana yang harus dibuka (mis. pembayaran
        // Akun PRO -> halaman Kelola Akun PRO untuk ADMIN).
        payload: tipe.toLowerCase(),
      );
    } catch (_) {
      // Diabaikan.
    }
  }
}

class RtsLayananNotif {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _siap = false;
  static bool _dinyatakanGagal = false;

  static const String saluranId = 'rts_panel_pemberitahuan';

  static const AndroidNotificationChannel _saluran = AndroidNotificationChannel(
    saluranId,
    'Pemberitahuan RTS Panel',
    description: 'Pengajuan baru dan hasil pemeriksaan pengajuan.',
    importance: Importance.high,
  );

  /// Menyiapkan saluran pemberitahuan. Aman dipanggil berkali-kali.
  static Future<bool> siapkan() async {
    if (_siap) return true;
    if (_dinyatakanGagal) return false;

    try {
      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings setelan = InitializationSettings(
        android: android,
      );

      await _plugin.initialize(
        setelan,
        onDidReceiveNotificationResponse: _ketuk,
      );

      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_saluran);

      _siap = true;
      return true;
    } catch (_) {
      _dinyatakanGagal = true;
      return false;
    }
  }

  /// Menampilkan permintaan izin "Izinkan Notifikasi" bawaan Android.
  static Future<bool> mintaIzin() async {
    if (!await siapkan()) return false;

    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final bool? hasil = await android?.requestNotificationsPermission();

      return hasil ?? true;
    } catch (_) {
      return false;
    }
  }

  /// Memeriksa apakah pemberitahuan diizinkan pada perangkat ini.
  static Future<bool> izinDiberikan() async {
    if (!await siapkan()) return false;

    try {
      final AndroidFlutterLocalNotificationsPlugin? android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      final bool? aktif = await android?.areNotificationsEnabled();

      return aktif ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Menampilkan satu pemberitahuan.
  ///
  /// [tombol]  : tulisan tombol pada pemberitahuan, contoh "UPDATE".
  ///             Menekan tombol itu membuka aplikasi, sehingga pemeriksaan
  ///             pembaruan dijalankan dan kotak pembaruan tampil.
  /// [payload] : keterangan yang dikirim kembali saat pemberitahuan ditekan.
  static Future<void> tampilkan({
    required int id,
    required String judul,
    required String pesan,
    String tombol = '',
    String payload = '',
  }) async {
    if (!await siapkan()) return;

    try {
      final List<AndroidNotificationAction> aksi = tombol.isEmpty
          ? const <AndroidNotificationAction>[]
          : <AndroidNotificationAction>[
              AndroidNotificationAction(
                'buka',
                tombol,
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ];

      await _plugin.show(
        id,
        judul,
        pesan,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _saluran.id,
            _saluran.name,
            channelDescription: _saluran.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(pesan),
            actions: aksi,
            autoCancel: true,
          ),
        ),
        payload: payload,
      );
    } catch (_) {
      // Pemberitahuan gagal ditampilkan, aplikasi tetap berjalan.
    }
  }

  /// Menampilkan pemberitahuan BERULANG setiap jam sampai dibatalkan.
  ///
  /// Dipakai untuk mengingatkan pembaruan aplikasi: pemberitahuan ini muncul
  /// kembali dengan sendirinya walaupun aplikasi tidak sedang dibuka, sampai
  /// petugas benar-benar memperbarui aplikasinya.
  static Future<void> berkala({
    required int id,
    required String judul,
    required String pesan,
    String tombol = 'UPDATE',
    String payload = 'pembaruan',
  }) async {
    if (!await siapkan()) return;

    try {
      final List<AndroidNotificationAction> aksi = tombol.isEmpty
          ? const <AndroidNotificationAction>[]
          : <AndroidNotificationAction>[
              AndroidNotificationAction(
                'buka',
                tombol,
                showsUserInterface: true,
                cancelNotification: true,
              ),
            ];

      await _plugin.periodicallyShow(
        id,
        judul,
        pesan,
        RepeatInterval.hourly,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _saluran.id,
            _saluran.name,
            channelDescription: _saluran.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
            styleInformation: BigTextStyleInformation(pesan),
            actions: aksi,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      // Diabaikan: pengingat berkala tidak wajib berhasil.
    }
  }

  /// Membatalkan satu pemberitahuan, termasuk pengingat berulangnya.
  static Future<void> hentikan(int id) async {
    if (!await siapkan()) return;

    try {
      await _plugin.cancel(id);
    } catch (_) {
      // Diabaikan.
    }
  }

  /// Pemberitahuan percobaan, untuk memastikan izin dan saluran sudah bekerja.
  static Future<void> tampilkanPercobaan() async {
    await tampilkan(
      id: 1,
      judul: 'Pemberitahuan RTS Panel Aktif',
      pesan: 'Pemberitahuan percobaan. Bila tulisan ini terlihat pada layar HP, '
          'berarti pemberitahuan sudah berjalan dengan baik.',
    );
  }

  static void _ketuk(NotificationResponse respon) {
    final String payload =
        (respon.payload ?? '').trim().toLowerCase();

    // Tombol UPDATE pada pemberitahuan pembaruan: aplikasi sudah dibuka oleh
    // Android; di sini pemeriksaan pembaruan dijalankan supaya kotak
    // pembaruan beserta tombol unduh langsung tampil.
    if (payload == 'pembaruan' || payload == 'versi') {
      Future<void>.delayed(const Duration(milliseconds: 1200), () async {
        final BuildContext? konteks = rtsNavigatorKey.currentContext;

        if (konteks == null || !konteks.mounted) return;

        final RtsInfoVersi? info = RtsPembaruan.terbaru;

        if (info != null && info.kode > RtsVersi.kode) {
          await RtsPembaruan.tampilkan(konteks, info);
          return;
        }

        await RtsPembaruan.periksaManual(konteks);
      });

      return;
    }

    // Pemberitahuan pembayaran Akun PRO: ADMIN langsung dibawa ke halaman
    // Kelola Akun PRO supaya dapat menekan SETUJUI atau TOLAK.
    if (payload == 'pembayaran' && (RtsSesi.user?.role ?? '') == 'ADMIN') {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        final RtsUser? user = RtsSesi.user;
        final String token = RtsSesi.token;

        if (user == null || token.isEmpty) return;

        rtsNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => KelolaProPage(user: user, token: token),
          ),
        );
      });

      return;
    }

    // Pemberitahuan langganan: dibuka halaman Langganan PRO.
    if (payload == 'langganan' || payload == 'pembayaran') {
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        final RtsUser? user = RtsSesi.user;
        final String token = RtsSesi.token;

        if (user == null || token.isEmpty) return;

        rtsNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => LanggananProPage(user: user, token: token),
          ),
        );
      });

      return;
    }

    // Membuka menu Pemberitahuan saat pemberitahuan biasa ditekan.
    Future<void>.delayed(const Duration(milliseconds: 900), () {
      final RtsUser? user = RtsSesi.user;
      final String token = RtsSesi.token;

      if (user == null || token.isEmpty) return;

      rtsNavigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => NotificationPage(user: user, token: token),
        ),
      );
    });
  }
}

/// Satu pemberitahuan yang akan ditampilkan pada layar HP.
class RtsCalonNotif {
  const RtsCalonNotif({
    required this.kunci,
    required this.judul,
    required this.pesan,
  });

  final String kunci;
  final String judul;
  final String pesan;

  /// Nomor pemberitahuan, dipakai agar pemberitahuan yang sama tidak menumpuk.
  int get nomor => kunci.hashCode & 0x7fffffff;
}

/// Memeriksa data terbaru lalu menampilkan pemberitahuan untuk hal yang baru.
class RtsPemantauNotif {
  static const String _kunciDiketahui = 'rts_notif_diketahui';
  static const String _kunciSiap = 'rts_notif_siap';
  static const int _batasSimpan = 400;

  /// Memeriksa dan menampilkan pemberitahuan baru.
  /// Mengembalikan jumlah pemberitahuan baru.
  static Future<int> periksa({bool beriTahu = true}) async {
    final String token = RtsSesi.token;

    if (token.isEmpty) return 0;

    final ApiClient api = ApiClient(token: token);
    Map<String, dynamic> data;

    try {
      data = await api.get('notifications.php');
    } catch (_) {
      // Tidak ada internet atau sesi berakhir: pemeriksaan berikutnya menyusul.
      return 0;
    }

    final RtsNotifikasiData isi = RtsNotifikasiData.fromJson(data);
    final List<RtsCalonNotif> calon = susunCalon(isi);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> lama = prefs.getStringList(_kunciDiketahui) ?? <String>[];
    final Set<String> setLama = lama.toSet();
    final bool pernahSinkron = prefs.getBool(_kunciSiap) ?? false;

    // Pada pemeriksaan pertama, seluruh isi hanya dicatat tanpa diberitahukan,
    // supaya pengguna tidak menerima banyak pemberitahuan sekaligus.
    final List<RtsCalonNotif> baru = pernahSinkron
        ? calon
            .where((RtsCalonNotif satu) => !setLama.contains(satu.kunci))
            .toList()
        : <RtsCalonNotif>[];

    final List<String> gabung = <String>[
      ...lama,
      ...calon.map((RtsCalonNotif satu) => satu.kunci),
    ];

    final List<String> disimpan = gabung.length > _batasSimpan
        ? gabung.sublist(gabung.length - _batasSimpan)
        : gabung;

    await prefs.setStringList(_kunciDiketahui, disimpan);
    await prefs.setBool(_kunciSiap, true);

    if (!beriTahu || baru.isEmpty) return baru.length;

    if (baru.length > 5) {
      await RtsLayananNotif.tampilkan(
        id: 99,
        judul: '${baru.length} pemberitahuan baru',
        pesan: baru
            .take(4)
            .map((RtsCalonNotif satu) => '- ${satu.judul}: ${satu.pesan}')
            .join('\n'),
      );
    } else {
      for (final RtsCalonNotif satu in baru) {
        await RtsLayananNotif.tampilkan(
          id: satu.nomor,
          judul: satu.judul,
          pesan: satu.pesan,
        );
      }
    }

    return baru.length;
  }

  /// Menyusun daftar pemberitahuan dari data API.
  static List<RtsCalonNotif> susunCalon(RtsNotifikasiData isi) {
    final List<RtsCalonNotif> daftar = <RtsCalonNotif>[];

    // 1. Hasil pengajuan sendiri: paling penting bagi sales.
    for (final RtsRingkasPengajuan item in isi.pengajuanSaya) {
      if (item.pending) continue;

      final String status = item.disetujui ? 'DISETUJUI' : 'DITOLAK';
      final String keterangan = item.catatan.trim().isEmpty
          ? ''
          : '\nCatatan: ${item.catatan.trim()}';

      daftar.add(
        RtsCalonNotif(
          kunci: 'HASIL|${item.tipe}|${item.id}|${item.status}',
          judul: item.disetujui ? 'Pengajuan Disetujui' : 'Pengajuan Ditolak',
          pesan: '${item.jenis} untuk ${item.namaToko} telah $status.$keterangan',
        ),
      );
    }

    // 2. Pengajuan yang perlu diperiksa (ADMIN, ASS, WSS, SMST).
    for (final RtsRingkasPengajuan item in isi.perluDiperiksa) {
      final String oleh = item.salesman.trim().isEmpty
          ? ''
          : ' oleh ${item.salesman.trim()}';
      final String wilayah = item.district.trim().isEmpty
          ? ''
          : ' (${item.district.trim()})';

      daftar.add(
        RtsCalonNotif(
          kunci: 'PERIKSA|${item.tipe}|${item.id}',
          judul: 'Pengajuan Baru Perlu Diperiksa',
          pesan: '${item.jenis} - ${item.namaToko}$oleh$wilayah.',
        ),
      );
    }

    // 3. Pemberitahuan dari tabel notifications, bila tabelnya tersedia.
    for (final RtsNotifikasi item in isi.pemberitahuan) {
      daftar.add(
        RtsCalonNotif(
          kunci: 'SISTEM|${item.id}',
          judul: item.judul.trim().isEmpty
              ? 'Pemberitahuan RTS Panel'
              : item.judul.trim(),
          pesan: item.pesan,
        ),
      );
    }

    return daftar;
  }
}

/// Menjalankan pemeriksaan berkala.
///
/// Pemeriksaan pemberitahuan selama aplikasi terbuka.
///
/// Diperiksa setiap 2 menit, dan juga setiap kali aplikasi dibuka kembali dari
/// latar belakang. Pemberitahuan pada layar HP ditampilkan dari pemeriksaan ini.
///
/// Catatan: paket pemeriksa latar (workmanager) sudah dilepas karena belum
/// cocok dengan versi Flutter yang dipakai, sehingga pemeriksaan hanya berjalan
/// selama aplikasi masih hidup di latar belakang HP. Bila pemberitahuan ingin
/// tetap masuk walau aplikasi ditutup sepenuhnya, caranya adalah Firebase
/// Cloud Messaging (lihat panduan bagian 25 huruf G).
class RtsPemantauLatar {
  static const String namaTugas = 'rtsCekPemberitahuan';
  static const String namaUnik = 'rts-cek-pemberitahuan';

  static Timer? _timer;

  /// Pemeriksaan berkala selama aplikasi terbuka.
  static void mulaiDepan() {
    _timer?.cancel();
    _timer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => RtsPemantauNotif.periksa(),
    );
  }

  static void hentikanDepan() {
    _timer?.cancel();
    _timer = null;
  }
}

/* ------------------------------------------------------------------------- */
/* PROFIL                                                                     */
/* ------------------------------------------------------------------------- */

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final ApiClient api = ApiClient(token: widget.token);

  final TextEditingController lamaController = TextEditingController();
  final TextEditingController baruController = TextEditingController();
  final TextEditingController ulangiController = TextEditingController();

  bool lihatLama = false;
  bool lihatBaru = false;
  bool lihatUlangi = false;
  bool menyimpan = false;

  RtsUser get user => widget.user;

  @override
  void dispose() {
    lamaController.dispose();
    baruController.dispose();
    ulangiController.dispose();
    super.dispose();
  }

  Future<void> _gantiPassword() async {
    FocusScope.of(context).unfocus();

    final String lama = lamaController.text;
    final String baru = baruController.text;
    final String ulangi = ulangiController.text;

    if (lama.isEmpty || baru.isEmpty || ulangi.isEmpty) {
      rtsShowMessage(context, 'Ketiga kolom password wajib diisi.');
      return;
    }

    if (baru.length < 6) {
      rtsShowMessage(context, 'Password baru paling sedikit 6 karakter.');
      return;
    }

    if (baru != ulangi) {
      rtsShowMessage(context, 'Ulangi password baru belum sama.');
      return;
    }

    if (baru == lama) {
      rtsShowMessage(context, 'Password baru tidak boleh sama dengan yang lama.');
      return;
    }

    setState(() => menyimpan = true);

    try {
      final Map<String, dynamic> hasil = await api.post('change_password.php', {
        'password_lama': lama,
        'password_baru': baru,
      });

      if (!mounted) return;

      setState(() {
        menyimpan = false;
        lamaController.clear();
        baruController.clear();
        ulangiController.clear();
      });

      rtsShowMessage(
        context,
        (hasil['message'] ?? 'Password berhasil diganti.').toString(),
        success: true,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => menyimpan = false);
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => menyimpan = false);
      rtsShowMessage(context, 'Terjadi gangguan saat mengganti password.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      _buildKartuAkun(),
                      const SizedBox(height: 18),
                      const RtsSectionTitle('Informasi Akun'),
                      const SizedBox(height: 11),
                      RtsCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            RtsInfoRow('Nama', user.displayName),
                            const RtsDivider(),
                            RtsInfoRow('Username', user.username),
                            const RtsDivider(),
                            RtsInfoRow('Role', user.role),
                            const RtsDivider(),
                            RtsInfoRow(
                              'Hak Persetujuan',
                              user.canApprove
                                  ? 'Boleh approve / reject'
                                  : 'Tidak boleh approve',
                              valueColor:
                                  user.canApprove ? rtsGreen : rtsTextPrimary,
                            ),
                            const RtsDivider(),
                            RtsInfoRow('Level Akses', user.accessLevel),
                            const RtsDivider(),
                            RtsInfoRow(
                              'Salesman',
                              user.salesman.isEmpty ? '-' : user.salesman,
                            ),
                            const RtsDivider(),
                            RtsInfoRow(
                              'Sales District',
                              user.salesDistrict.isEmpty
                                  ? '-'
                                  : user.salesDistrict,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      const RtsSectionTitle('Rencana Akun'),
                      const SizedBox(height: 11),
                      RtsKartuRencanaAkun(user: user),
                      const SizedBox(height: 18),
                      const RtsIklanAsli(),
                      const SizedBox(height: 18),
                      const RtsSectionTitle('Ganti Password'),
                      const SizedBox(height: 11),
                      _buildGantiPassword(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Profil',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Akun dan password Anda',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKartuAkun() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.28),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RtsFotoProfil(
                ukuran: 56,
                bolehGanti: true,
                latarBelakang: Color(0x2effffff),
                garisTepi: Color(0x4dffffff),
                warnaHuruf: Colors.white,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      user.username.isEmpty
                          ? '-'
                          : ('@' + user.username),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xb3ffffff),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              RtsBadge(
                user.role.isEmpty ? '-' : user.role,
                background: Colors.white.withValues(alpha: 0.18),
                foreground: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(
                Icons.map_outlined,
                size: 15,
                color: Color(0xb3ffffff),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  user.salesDistrict.isEmpty
                      ? 'Belum ada penugasan district'
                      : user.salesDistrict,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGantiPassword() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Setelah password diganti, sesi login pada perangkat lain akan '
            'diputus dan perlu masuk kembali. Sesi pada HP ini tetap berlaku.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          _buildKolomPassword(
            controller: lamaController,
            label: 'Password Lama',
            lihat: lihatLama,
            onLihat: () => setState(() => lihatLama = !lihatLama),
          ),
          const SizedBox(height: 12),
          _buildKolomPassword(
            controller: baruController,
            label: 'Password Baru',
            lihat: lihatBaru,
            onLihat: () => setState(() => lihatBaru = !lihatBaru),
          ),
          const SizedBox(height: 12),
          _buildKolomPassword(
            controller: ulangiController,
            label: 'Ulangi Password Baru',
            lihat: lihatUlangi,
            onLihat: () => setState(() => lihatUlangi = !lihatUlangi),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rtsMaroon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: menyimpan ? null : _gantiPassword,
              icon: menyimpan
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.lock_reset_rounded, size: 19),
              label: Text(
                menyimpan ? 'MENYIMPAN...' : 'GANTI PASSWORD',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKolomPassword({
    required TextEditingController controller,
    required String label,
    required bool lihat,
    required VoidCallback onLihat,
  }) {
    return TextField(
      controller: controller,
      obscureText: !lihat,
      style: const TextStyle(fontSize: 14.5),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(
          Icons.lock_outline,
          color: Color(0xff6d514a),
          size: 20,
        ),
        suffixIcon: IconButton(
          splashRadius: 20,
          onPressed: onLihat,
          icon: Icon(
            lihat ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            color: const Color(0xff6d514a),
            size: 20,
          ),
        ),
        filled: true,
        fillColor: const Color(0xfff8f4ef),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        labelStyle: const TextStyle(fontSize: 13.5),
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
          borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* SINKRONISASI                                                               */
/* ------------------------------------------------------------------------- */

class SyncPage extends StatefulWidget {
  const SyncPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  static const String _kunciWaktu = 'rts_sinkron_waktu';
  static const String _kunciCustomer = 'rts_sinkron_customer';
  static const String _kunciPengajuan = 'rts_sinkron_pengajuan';
  static const String _kunciNotif = 'rts_sinkron_notif';

  String? waktuTerakhir;
  int? jumlahCustomer;
  int? jumlahPengajuan;
  int? jumlahNotif;
  int? kecepatanMs;
  bool menyinkron = false;
  String? pesanGalat;

  /// Keadaan tombol SINKRON AKUN (status PRO / GRATIS).
  bool menyinkronAkun = false;
  String pesanAkun = '';

  @override
  void initState() {
    super.initState();
    _muatTersimpan();
  }

  Future<void> _muatTersimpan() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        waktuTerakhir = prefs.getString(_kunciWaktu);
        jumlahCustomer = prefs.getInt(_kunciCustomer);
        jumlahPengajuan = prefs.getInt(_kunciPengajuan);
        jumlahNotif = prefs.getInt(_kunciNotif);
      });
    } catch (_) {
      // pengaturan gagal dibaca, halaman tetap tampil
    }
  }

  Future<void> _sinkronkan() async {
    setState(() {
      menyinkron = true;
      pesanGalat = null;
    });

    final DateTime mulai = DateTime.now();

    try {
      // Status akun (PRO / GRATIS) disegarkan lebih dahulu, supaya akun yang
      // baru diperpanjang langsung terbuka lewat tombol ini juga.
      await _sinkronAkun(lapor: false);

      // Data customer pada cakupan akun.
      final Map<String, dynamic> dataCustomer = await api.get('customers.php', {
        'page': '1',
        'limit': '1',
      });

      final CustomerPage halaman = CustomerPage.fromJson(dataCustomer);

      // Data pengajuan pada cakupan akun.
      final Map<String, dynamic> dataPengajuan = await api.get('requests.php', {
        'page': '1',
        'limit': '1',
      });

      final RequestPageData halamanPengajuan =
          RequestPageData.fromJson(dataPengajuan);

      // Pemberitahuan.
      final Map<String, dynamic> dataNotif =
          await api.get('notifications.php');

      final RtsNotifikasiData isiNotif = RtsNotifikasiData.fromJson(dataNotif);

      final int jeda = DateTime.now().difference(mulai).inMilliseconds;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String waktu = RtsWaktu.ringkas(DateTime.now());

      await prefs.setString(_kunciWaktu, waktu);
      await prefs.setInt(_kunciCustomer, halaman.total);
      await prefs.setInt(_kunciPengajuan, halamanPengajuan.total);
      await prefs.setInt(_kunciNotif, isiNotif.angkaLonceng);

      if (!mounted) return;

      setState(() {
        menyinkron = false;
        kecepatanMs = jeda;
        waktuTerakhir = waktu;
        jumlahCustomer = halaman.total;
        jumlahPengajuan = halamanPengajuan.total;
        jumlahNotif = isiNotif.angkaLonceng;
      });

      rtsShowMessage(
        context,
        'Data terbaru berhasil ditarik dari server.',
        success: true,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        menyinkron = false;
        pesanGalat = error.message;
      });
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        menyinkron = false;
        pesanGalat = 'Terjadi gangguan saat menarik data.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final RtsServer server = RtsConfig.server;

    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      _buildKartuAkun(),
                      const SizedBox(height: 14),
                      _buildKartuServer(server),
                      const SizedBox(height: 14),
                      const RtsIklanAsli(),
                      const SizedBox(height: 18),
                      const RtsSectionTitle('Hasil Sinkronisasi'),
                      const SizedBox(height: 11),
                      _buildKartuHasil(),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 54,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: rtsMaroon,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: menyinkron ? null : _sinkronkan,
                          icon: menyinkron
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.sync_rounded, size: 20),
                          label: Text(
                            menyinkron ? 'MENARIK DATA...' : 'SINKRONKAN SEKARANG',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _buildCatatan(server),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Menyegarkan STATUS AKUN dari server.
  ///
  /// Inilah yang dipakai sales sesudah top up dan ADMIN menyetujui: keadaan
  /// langganan (langganan.php lewat session_check.php), data akun, dan izin
  /// PRO yang tersimpan di dalam HP diperiksa ulang, sehingga seluruh menu
  /// PRO langsung terbuka tanpa perlu memasang ulang aplikasi.
  Future<void> _sinkronAkun({bool lapor = true}) async {
    if (menyinkronAkun) return;

    if (mounted) {
      setState(() {
        menyinkronAkun = true;
        pesanAkun = '';
      });
    }

    try {
      final Map<String, dynamic> balasan = await api.get('session_check.php');

      final RtsUser terbaru = RtsUser.fromJson(
        ((balasan['user'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

      final RtsLangganan baru = RtsLangganan.dariBalasan(balasan);

      await RtsSesi.simpan(widget.token, terbaru);
      await RtsLangganan.simpanKeSesi(baru);

      // Pemeriksaan izin PRO yang tersimpan di dalam HP disegarkan supaya
      // jawaban lama ("belum boleh") tidak dipakai lagi. Keterangan akun
      // diserahkan lebih dahulu supaya pemeriksaan ini menghubungi server.
      Map<String, dynamic> akses = <String, dynamic>{};

      try {
        await RtsKasirLokal.aku.atur(
          baseUrl: RtsConfig.baseUrl,
          token: widget.token,
          pengguna: terbaru.toJson(),
        );

        akses = await RtsKasirLokal.aku.akses(paksa: true);
      } catch (_) {
        akses = <String, dynamic>{};
      }

      final bool pro =
          baru.proAktif || baru.trialAktif || akses['boleh'] == true;

      String kabar;

      if (baru.proAktif) {
        final String sampai =
            baru.berlakuSampai.isEmpty ? '' : ' sampai ${baru.berlakuSampai}';
        final String sisa =
            baru.sisaHari > 0 ? ' (sisa ${baru.sisaHari} hari)' : '';

        kabar = 'Akun PRO AKTIF$sampai$sisa. Seluruh menu PRO sudah dapat '
            'dibuka.';
      } else if (baru.trialAktif) {
        final String sisa = baru.sisaTrialHari > 0
            ? ' (sisa ${baru.sisaTrialHari} hari)'
            : '';

        kabar = 'Uji coba PRO masih berjalan$sisa. Seluruh menu PRO dapat '
            'dibuka.';
      } else if (pro) {
        kabar = 'Akun PRO sudah aktif menurut pemeriksaan di HP. Seluruh menu '
            'PRO dapat dibuka.';
      } else {
        kabar = 'Status akun di server masih GRATIS. Bila pembayaran sudah '
            'dikirim, pastikan ADMIN sudah menekan SETUJUI pada halaman '
            'langganan_admin.php, lalu tekan SINKRON AKUN sekali lagi.';
      }

      if (!mounted) return;

      setState(() {
        menyinkronAkun = false;
        pesanAkun = kabar;
      });

      if (lapor) rtsShowMessage(context, kabar, success: pro);
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        menyinkronAkun = false;
        pesanAkun = error.message;
      });

      if (lapor) rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        menyinkronAkun = false;
        pesanAkun = 'Tidak dapat menyegarkan status akun. Periksa sambungan '
            'internet, lalu coba lagi.';
      });

      if (lapor) rtsShowMessage(context, pesanAkun);
    }
  }

  /// Kartu STATUS AKUN + tombol SINKRON AKUN.
  ///
  /// Tombol inilah yang ditekan sales sesudah top up: aplikasi memeriksa
  /// ulang ke server, sehingga akun yang sudah diperpanjang / disetujui ADMIN
  /// langsung terbuka fitur PRO-nya.
  Widget _buildKartuAkun() {
    final RtsLangganan lg = RtsLangganan.sekarang;
    final bool pro = lg.proAktif || lg.trialAktif || RtsTingkatAkun.pro;

    final Color warna = pro ? rtsGreen : rtsMaroon;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: warna.withValues(alpha: 0.35), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                pro
                    ? Icons.workspace_premium_rounded
                    : Icons.lock_outline_rounded,
                color: warna,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Status Akun',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: warna.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  RtsTingkatAkun.label,
                  style: TextStyle(
                    color: warna,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            lg.keteranganMasa,
            style: const TextStyle(color: rtsTextSecondary, fontSize: 12),
          ),
          const SizedBox(height: 7),
          const Text(
            'Sesudah top up, tekan tombol di bawah ini supaya status akun '
            'dibaca ulang dari server. Akun yang sudah disetujui ADMIN '
            'langsung terbuka seluruh menu PRO-nya.',
            style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rtsGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: menyinkronAkun ? null : () => _sinkronAkun(),
              icon: menyinkronAkun
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user_rounded, size: 20),
              label: Text(
                menyinkronAkun ? 'MEMERIKSA STATUS AKUN...' : 'SINKRON AKUN',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
          if (pesanAkun.isNotEmpty) ...[
            const SizedBox(height: 11),
            Text(
              pesanAkun,
              style: TextStyle(
                color: warna,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Sinkronisasi',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Tarik data terbaru + periksa status akun',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKartuServer(RtsServer server) {
    final bool produksi = server.produksi;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: produksi
              ? <Color>[const Color(0xff1e7a45), const Color(0xff146034)]
              : <Color>[rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.25),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SERVER AKTIF',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                produksi
                    ? Icons.verified_user_outlined
                    : Icons.science_outlined,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  server.nama,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (kecepatanMs != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${kecepatanMs} ms',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            'Database: ${server.database}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            server.baseUrl,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKartuHasil() {
    final String waktu = waktuTerakhir ?? 'Belum pernah disinkronkan';

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 18,
                color: rtsTextSecondary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sinkronisasi terakhir',
                      style: TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      waktu,
                      style: const TextStyle(
                        color: rtsTextPrimary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildKotakAngka(
                'Customer',
                jumlahCustomer?.toString() ?? '-',
                const Color(0xff2b5f9e),
                const Color(0xffeaf1fb),
              ),
              const SizedBox(width: 9),
              _buildKotakAngka(
                'Pengajuan',
                jumlahPengajuan?.toString() ?? '-',
                rtsAmber,
                const Color(0xfffdf6ec),
              ),
              const SizedBox(width: 9),
              _buildKotakAngka(
                'Pemberitahuan',
                jumlahNotif?.toString() ?? '-',
                rtsMaroon,
                const Color(0xfffaecee),
              ),
            ],
          ),
          if (pesanGalat != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffdeaea),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xfff0c9c9)),
              ),
              child: Text(
                pesanGalat!,
                style: const TextStyle(
                  color: Color(0xff8a1b1b),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildKotakAngka(
    String label,
    String angka,
    Color warna,
    Color latar,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: warna.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              angka,
              style: TextStyle(
                color: warna,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: rtsTextSecondary,
                fontSize: 10.5,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCatatan(RtsServer server) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xffeaf1fb),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xffd3e0f5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: Color(0xff2b5f9e),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Angka di atas adalah jumlah data pada cakupan akun Anda di '
              '${server.nama}. Data selalu dibaca langsung dari server, '
              'sehingga angka pada halaman ini mengikuti keadaan terbaru.',
              style: const TextStyle(
                color: Color(0xff2b5f9e),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* BANTUAN WAKTU                                                              */
/* ------------------------------------------------------------------------- */

class RtsWaktu {
  static const List<String> _bulan = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  /// Contoh keluaran: 27 Sep 2026, 21.14
  static String ringkas(DateTime waktu) {
    final String jam = waktu.hour.toString().padLeft(2, '0');
    final String menit = waktu.minute.toString().padLeft(2, '0');

    final String tanggal = '${waktu.day} ${_bulan[waktu.month - 1]} ${waktu.year}';

    return '$tanggal, $jam.$menit';
  }

  /// Contoh keluaran: 21.14
  static String jamMenit(DateTime waktu) {
    final String jam = waktu.hour.toString().padLeft(2, '0');
    final String menit = waktu.minute.toString().padLeft(2, '0');

    return '$jam.$menit';
  }
}

/* ------------------------------------------------------------------------- */
/* NOTIFIKASI                                                                 */
/* ------------------------------------------------------------------------- */

/// Satu baris pemberitahuan dari tabel notifications.
class RtsNotifikasi {
  const RtsNotifikasi({
    required this.id,
    required this.judul,
    required this.pesan,
    required this.tipe,
    required this.sudahDibaca,
    required this.waktu,
  });

  final int id;
  final String judul;
  final String pesan;
  final String tipe;
  final bool sudahDibaca;
  final String waktu;

  factory RtsNotifikasi.fromJson(Map<String, dynamic> json) {
    return RtsNotifikasi(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      judul: (json['title'] ?? '').toString(),
      pesan: (json['message'] ?? '').toString(),
      tipe: (json['type'] ?? 'INFO').toString().toUpperCase(),
      sudahDibaca: json['is_read'] == true,
      waktu: (json['created_at'] ?? '').toString(),
    );
  }
}

/// Satu baris ringkasan pengajuan yang dipakai pada halaman notifikasi.
class RtsRingkasPengajuan {
  const RtsRingkasPengajuan({
    required this.id,
    required this.tipe,
    required this.jenis,
    required this.namaToko,
    required this.salesman,
    required this.district,
    required this.status,
    required this.waktu,
    required this.catatan,
  });

  final int id;
  final String tipe;
  final String jenis;
  final String namaToko;
  final String salesman;
  final String district;
  final String status;
  final String waktu;
  final String catatan;

  bool get isGsp => tipe.toUpperCase() == 'GSP';
  bool get pending => status.toLowerCase() == 'pending';
  bool get disetujui => status.toLowerCase() == 'disetujui';

  /// Menghilangkan bagian tanggal yang tidak perlu, contoh: 27 Sep 2026 21:04.
  String get waktuRingkas {
    final String bersih = waktu.trim();

    if (bersih.length >= 16) return bersih.substring(0, 16);

    return bersih;
  }

  factory RtsRingkasPengajuan.fromJson(Map<String, dynamic> json) {
    return RtsRingkasPengajuan(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      tipe: (json['tipe'] ?? 'TOKO').toString().toUpperCase(),
      jenis: (json['jenis_request'] ?? '').toString(),
      namaToko: (json['nama_toko'] ?? '').toString(),
      salesman: (json['salesman'] ?? '').toString(),
      district: (json['district'] ?? '').toString(),
      status: (json['status_approval'] ?? 'Pending').toString(),
      waktu: (json['waktu_proses'] ??
              json['processed_at'] ??
              json['tanggal_request'] ??
              '')
          .toString(),
      catatan: (json['catatan'] ?? '').toString(),
    );
  }
}

/// Isi halaman notifikasi.
class RtsNotifikasiData {
  const RtsNotifikasiData({
    required this.tersedia,
    required this.belumDibaca,
    required this.angkaLonceng,
    required this.jumlahPerluDiperiksa,
    required this.perluDiperiksa,
    required this.jumlahPendingSaya,
    required this.jumlahDisetujuiSaya,
    required this.jumlahDitolakSaya,
    required this.pengajuanSaya,
    required this.pemberitahuan,
  });

  /// Bernilai false bila tabel notifications belum ada di database.
  final bool tersedia;
  final int belumDibaca;
  final int angkaLonceng;
  final int jumlahPerluDiperiksa;
  final List<RtsRingkasPengajuan> perluDiperiksa;
  final int jumlahPendingSaya;
  final int jumlahDisetujuiSaya;
  final int jumlahDitolakSaya;
  final List<RtsRingkasPengajuan> pengajuanSaya;
  final List<RtsNotifikasi> pemberitahuan;

  static int _angka(Object? isi) => int.tryParse((isi ?? '0').toString()) ?? 0;

  static List<RtsRingkasPengajuan> _daftarPengajuan(Object? isi) {
    return ((isi as List?) ?? const [])
        .whereType<Map>()
        .map((item) =>
            RtsRingkasPengajuan.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  factory RtsNotifikasiData.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> perlu =
        ((json['perlu_diperiksa'] as Map?) ?? const {}).cast<String, dynamic>();
    final Map<String, dynamic> saya =
        ((json['pengajuan_saya'] as Map?) ?? const {}).cast<String, dynamic>();

    final List<RtsNotifikasi> pemberitahuan =
        ((json['data'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => RtsNotifikasi.fromJson(item.cast<String, dynamic>()))
            .toList();

    return RtsNotifikasiData(
      tersedia: json['tersedia'] == true,
      belumDibaca: _angka(json['belum_dibaca']),
      angkaLonceng: _angka(json['angka_lonceng']),
      jumlahPerluDiperiksa: _angka(perlu['jumlah']),
      perluDiperiksa: _daftarPengajuan(perlu['data']),
      jumlahPendingSaya: _angka(saya['pending']),
      jumlahDisetujuiSaya: _angka(saya['disetujui']),
      jumlahDitolakSaya: _angka(saya['ditolak']),
      pengajuanSaya: _daftarPengajuan(saya['data']),
      pemberitahuan: pemberitahuan,
    );
  }
}

/// Lonceng pada sudut kanan atas dashboard beserta angka pemberitahuan.
class RtsBellNotifikasi extends StatefulWidget {
  const RtsBellNotifikasi({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<RtsBellNotifikasi> createState() => _RtsBellNotifikasiState();
}

class _RtsBellNotifikasiState extends State<RtsBellNotifikasi>
    with WidgetsBindingObserver {
  late final ApiClient api = ApiClient(token: widget.token);

  int angka = 0;
  bool _sudahMenawarkan = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    _muatAngka();

    // Pemberitahuan pada layar HP.
    RtsPemantauLatar.mulaiDepan();

    WidgetsBinding.instance.addPostFrameCallback((_) => _tawarkanIzin());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    RtsPemantauLatar.hentikanDepan();
    super.dispose();
  }

  /// Saat aplikasi dibuka kembali dari latar belakang, data langsung diperiksa
  /// supaya pemberitahuan tidak menunggu sampai 2 menit berikutnya.
  @override
  void didChangeAppLifecycleState(AppLifecycleState keadaan) {
    if (keadaan != AppLifecycleState.resumed) return;

    _muatAngka();
    RtsPemantauNotif.periksa();
  }

  /// Menawarkan izin pemberitahuan satu kali saja untuk setiap pemasangan.
  Future<void> _tawarkanIzin() async {
    if (_sudahMenawarkan || !mounted) return;
    _sudahMenawarkan = true;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      if (prefs.getBool('rts_notif_ditawarkan') == true) return;

      final bool sudahAktif = await RtsLayananNotif.izinDiberikan();

      if (sudahAktif) {
        await prefs.setBool('rts_notif_ditawarkan', true);
        return;
      }

      if (!mounted) return;

      final bool? mau = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Aktifkan Pemberitahuan?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'RTS Panel dapat mengirim pemberitahuan ke layar HP Anda:',
                style: TextStyle(fontSize: 13.5),
              ),
              SizedBox(height: 10),
              Text(
                '• Pengajuan baru yang perlu diperiksa',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              Text(
                '• Pengajuan Anda disetujui atau ditolak',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                'Android akan menampilkan permintaan izin. Tekan IZINKAN agar '
                'pemberitahuan dapat masuk.',
                style: TextStyle(
                  fontSize: 12,
                  color: rtsTextSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'NANTI',
                style: TextStyle(color: rtsTextSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('IZINKAN'),
            ),
          ],
        ),
      );

      await prefs.setBool('rts_notif_ditawarkan', true);

      if (mau != true) return;

      final bool hasil = await RtsLayananNotif.mintaIzin();

      if (!mounted) return;

      if (hasil) {
        RtsPemantauLatar.mulaiDepan();
        await RtsPemantauNotif.periksa();
        await RtsLayananNotif.tampilkanPercobaan();

        if (!mounted) return;

        rtsShowMessage(
          context,
          'Pemberitahuan HP diaktifkan. Pemberitahuan percobaan dikirim.',
          success: true,
        );
      } else {
        rtsShowMessage(
          context,
          'Izin belum diberikan. Dapat diaktifkan lewat Pengaturan > '
          'Pemberitahuan HP.',
        );
      }
    } catch (_) {
      // Penawaran izin gagal, aplikasi tetap berjalan normal.
    }
  }

  Future<void> _muatAngka() async {
    try {
      final Map<String, dynamic> data = await api.get('notifications.php');
      final RtsNotifikasiData hasil = RtsNotifikasiData.fromJson(data);

      if (!mounted) return;

      setState(() => angka = hasil.angkaLonceng);
    } catch (_) {
      // Angka lonceng bersifat pelengkap, kegagalan tidak perlu ditampilkan.
    }
  }

  Future<void> _buka() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationPage(
          user: widget.user,
          token: widget.token,
        ),
      ),
    );

    if (mounted) _muatAngka();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Pemberitahuan',
          onPressed: _buka,
          icon: const Icon(
            Icons.notifications_none_rounded,
            color: rtsTextPrimary,
          ),
        ),
        if (angka > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: rtsMaroon,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.2),
              ),
              child: Text(
                angka > 99 ? '99+' : angka.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Halaman pemberitahuan.
class NotificationPage extends StatefulWidget {
  const NotificationPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  RtsNotifikasiData? data;
  bool memuat = true;
  bool menandai = false;
  String? pesan;

  bool get bolehProses => widget.user.canApprove;
  bool get lihatSemua =>
      const ['ADMIN', 'ASS', 'WSS', 'SMST'].contains(widget.user.role);

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      memuat = true;
      pesan = null;
    });

    try {
      final Map<String, dynamic> hasil = await api.get('notifications.php');

      if (!mounted) return;

      setState(() {
        data = RtsNotifikasiData.fromJson(hasil);
        memuat = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        memuat = false;
        pesan = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        memuat = false;
        pesan = 'Gagal memuat pemberitahuan.';
      });
    }
  }

  Future<void> _tandaiDibaca({int? id}) async {
    if (menandai) return;

    setState(() => menandai = true);

    try {
      await api.post('notifications.php', <String, dynamic>{
        'action': id == null ? 'read_all' : 'read',
        if (id != null) 'id': id,
      });

      if (!mounted) return;

      setState(() => menandai = false);
      await _muat();
    } catch (_) {
      if (!mounted) return;
      setState(() => menandai = false);
      rtsShowMessage(context, 'Gagal menandai pemberitahuan.');
    }
  }

  Future<void> _bukaPengajuan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RequestListPage(user: widget.user, token: widget.token),
      ),
    );

    if (mounted) _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    final RtsNotifikasiData? isi = data;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Pemberitahuan',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Hasil pengajuan dan pengajuan yang perlu diperiksa',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (isi != null && isi.belumDibaca > 0)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: rtsMaroon),
              onPressed: menandai ? null : () => _tandaiDibaca(),
              child: const Text(
                'TANDAI DIBACA',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
            ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _muat,
            icon: const Icon(Icons.refresh_rounded, color: rtsTextPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (memuat) {
      return const Center(child: CircularProgressIndicator(color: rtsMaroon));
    }

    if (pesan != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 44, color: rtsTextSecondary),
              const SizedBox(height: 12),
              Text(
                pesan!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
                onPressed: _muat,
                child: const Text('COBA LAGI'),
              ),
            ],
          ),
        ),
      );
    }

    final RtsNotifikasiData isi = data!;

    return RefreshIndicator(
      color: rtsMaroon,
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _buildRingkasan(isi),
          const SizedBox(height: 14),
          const RtsIklanAsli(),
          if (isi.perluDiperiksa.isNotEmpty) ...[
            const SizedBox(height: 20),
            RtsSectionTitle(
              lihatSemua ? 'Perlu Diperiksa' : 'Pengajuan Anda',
            ),
            const SizedBox(height: 11),
            for (final RtsRingkasPengajuan item in isi.perluDiperiksa) ...[
              _buildKartuPengajuan(item),
              const SizedBox(height: 10),
            ],
            _buildTombolKePengajuan(
              lihatSemua
                  ? 'BUKA MENU PENGAJUAN UNTUK MEMERIKSA'
                  : 'LIHAT PENGAJUAN SAYA',
            ),
          ],
          if (isi.pengajuanSaya.isNotEmpty) ...[
            const SizedBox(height: 20),
            const RtsSectionTitle('Hasil Pengajuan Saya'),
            const SizedBox(height: 11),
            for (final RtsRingkasPengajuan item in isi.pengajuanSaya) ...[
              _buildKartuPengajuan(item),
              const SizedBox(height: 10),
            ],
          ],
          if (isi.pemberitahuan.isNotEmpty) ...[
            const SizedBox(height: 20),
            const RtsSectionTitle('Pemberitahuan Sistem'),
            const SizedBox(height: 11),
            for (final RtsNotifikasi item in isi.pemberitahuan) ...[
              _buildKartuNotifikasi(item),
              const SizedBox(height: 10),
            ],
          ],
          if (isi.perluDiperiksa.isEmpty &&
              isi.pengajuanSaya.isEmpty &&
              isi.pemberitahuan.isEmpty) ...[
            const SizedBox(height: 50),
            const Center(
              child: Column(
                children: [
                  Icon(Icons.notifications_none_rounded,
                      size: 46, color: rtsTextSecondary),
                  SizedBox(height: 12),
                  Text(
                    'Belum ada pemberitahuan.',
                    style: TextStyle(color: rtsTextPrimary, fontSize: 14),
                  ),
                  SizedBox(height: 6),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      'Pemberitahuan akan muncul di sini setelah Anda mengirim '
                      'pengajuan atau setelah pengajuan diperiksa.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isi.tersedia) ...[
            const SizedBox(height: 22),
            _buildCatatanTabel(),
          ],
        ],
      ),
    );
  }

  Widget _buildRingkasan(RtsNotifikasiData isi) {
    return Row(
      children: [
        _buildKotakAngka(
          lihatSemua ? 'Perlu diperiksa' : 'Menunggu',
          isi.jumlahPerluDiperiksa.toString(),
          rtsAmber,
          const Color(0xfffdf6ec),
        ),
        const SizedBox(width: 10),
        _buildKotakAngka(
          'Disetujui',
          isi.jumlahDisetujuiSaya.toString(),
          rtsGreen,
          const Color(0xffe8f5ec),
        ),
        const SizedBox(width: 10),
        _buildKotakAngka(
          'Ditolak',
          isi.jumlahDitolakSaya.toString(),
          const Color(0xffa52020),
          const Color(0xfffdeaea),
        ),
      ],
    );
  }

  Widget _buildKotakAngka(
    String label,
    String angka,
    Color warna,
    Color latar,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: latar,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: warna.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Text(
              angka,
              style: TextStyle(
                color: warna,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: const TextStyle(
                color: rtsTextSecondary,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKartuPengajuan(RtsRingkasPengajuan item) {
    final Color warnaStatus = item.pending
        ? rtsAmber
        : (item.disetujui ? rtsGreen : const Color(0xffa52020));
    final Color latarStatus = item.pending
        ? const Color(0xfffdf6ec)
        : (item.disetujui
            ? const Color(0xffe8f5ec)
            : const Color(0xfffdeaea));

    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _bukaPengajuan,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rtsCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: item.isGsp
                          ? const Color(0xfffdf3e0)
                          : const Color(0xffeef3fb),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      item.isGsp
                          ? Icons.local_gas_station_outlined
                          : Icons.storefront_outlined,
                      size: 18,
                      color:
                          item.isGsp ? rtsAmber : const Color(0xff2b5f9e),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.namaToko.isEmpty ? '-' : item.namaToko,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${item.jenis} • No. ${item.id}',
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  RtsBadge(
                    item.status.toUpperCase(),
                    background: latarStatus,
                    foreground: warnaStatus,
                  ),
                ],
              ),
              if (item.salesman.isNotEmpty || item.district.isNotEmpty) ...[
                const SizedBox(height: 9),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded,
                        size: 14, color: Color(0xffa99d94)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.district.isEmpty
                            ? item.salesman
                            : '${item.salesman} \u2022 ${item.district}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: rtsTextSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (item.catatan.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xfff8f4ef),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Text(
                    'Catatan: ${item.catatan}',
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded,
                      size: 14, color: Color(0xffa99d94)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.waktuRingkas,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xffb8aea6)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKartuNotifikasi(RtsNotifikasi item) {
    Color warna;
    IconData ikon;

    switch (item.tipe) {
      case 'SUCCESS':
        warna = rtsGreen;
        ikon = Icons.check_circle_outline_rounded;
      case 'WARNING':
        warna = rtsAmber;
        ikon = Icons.warning_amber_rounded;
      case 'DANGER':
        warna = const Color(0xffa52020);
        ikon = Icons.error_outline_rounded;
      default:
        warna = const Color(0xff2b5f9e);
        ikon = Icons.info_outline_rounded;
    }

    return Material(
      color: item.sudahDibaca
          ? Colors.white.withValues(alpha: 0.75)
          : Colors.white.withValues(alpha: 0.98),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: item.sudahDibaca
            ? null
            : () => _tandaiDibaca(id: item.id),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.sudahDibaca ? rtsCardBorder : warna,
              width: item.sudahDibaca ? 1 : 1.3,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(ikon, size: 20, color: warna),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.judul,
                            style: const TextStyle(
                              color: rtsTextPrimary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!item.sudahDibaca)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: rtsMaroon,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.pesan,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.waktu,
                      style: const TextStyle(
                        color: Color(0xffa99d94),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTombolKePengajuan(String label) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: rtsMaroon,
          side: const BorderSide(color: rtsMaroon, width: 1.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: _bukaPengajuan,
        icon: const Icon(Icons.assignment_outlined, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildCatatanTabel() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xfffdf6ec),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xfff0e2cf)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: Color(0xff9a6b23)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Daftar di atas disusun langsung dari data pengajuan, jadi tetap '
              'berfungsi walau tabel notifications belum dibuat di database. '
              'Pemberitahuan sistem akan ikut muncul setelah tabel tersebut '
              'tersedia.',
              style: TextStyle(
                color: Color(0xff7a5a26),
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* MODEL PENGAJUAN                                                            */
/* ------------------------------------------------------------------------- */

class RtsRequest {
  const RtsRequest({
    required this.id,
    required this.tipe,
    required this.tanggalRequest,
    required this.salesman,
    required this.district,
    required this.jenisRequest,
    required this.namaToko,
    required this.idCustomer,
    required this.alamat,
    required this.statusApproval,
    required this.processedBy,
    required this.processedAt,
    required this.approvalNote,
    required this.pic,
    required this.nomorHp,
    required this.koordinat,
    required this.tokoLamaNama,
    required this.tokoBaruNama,
    required this.tokoLamaId,
    required this.tokoBaruId,
    required this.bolehProses,
    required this.bolehHapus,
  });

  final int id;
  final String tipe; // TOKO atau GSP
  final String tanggalRequest;
  final String salesman;
  final String district;
  final String jenisRequest;
  final String namaToko;
  final String idCustomer;
  final String alamat;
  final String statusApproval;
  final String processedBy;
  final String processedAt;
  final String approvalNote;
  final String pic;
  final String nomorHp;
  final String koordinat;
  final String tokoLamaNama;
  final String tokoBaruNama;
  final String tokoLamaId;
  final String tokoBaruId;
  final bool bolehProses;
  final bool bolehHapus;

  bool get isGsp => tipe.toUpperCase() == 'GSP';
  bool get isPending => statusApproval.toLowerCase() == 'pending';
  bool get disetujui => statusApproval.toLowerCase() == 'disetujui';
  bool get ditolak => statusApproval.toLowerCase() == 'ditolak';

  /// Tanggal ringkas, misalnya 27 Sep 2026.
  String get tanggalRingkas {
    final DateTime? waktu = DateTime.tryParse(tanggalRequest.replaceAll(' ', 'T'));
    if (waktu == null) return tanggalRequest;

    const List<String> bulan = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];

    final String jam = waktu.hour.toString().padLeft(2, '0');
    final String menit = waktu.minute.toString().padLeft(2, '0');

    return '${waktu.day} ${bulan[waktu.month - 1]} ${waktu.year} • $jam:$menit';
  }

  factory RtsRequest.fromJson(Map<String, dynamic> json) {
    return RtsRequest(
      id: int.tryParse((json['id'] ?? '0').toString()) ?? 0,
      tipe: (json['tipe'] ?? 'TOKO').toString().toUpperCase(),
      tanggalRequest: (json['tanggal_request'] ?? '').toString(),
      salesman: (json['salesman'] ?? '').toString(),
      district: (json['district'] ?? '').toString(),
      jenisRequest: (json['jenis_request'] ?? '').toString(),
      namaToko: (json['nama_toko'] ?? '').toString(),
      idCustomer: (json['id_customer'] ?? '').toString(),
      alamat: (json['alamat'] ?? '').toString(),
      statusApproval: (json['status_approval'] ?? 'Pending').toString(),
      processedBy: (json['processed_by'] ?? '').toString(),
      processedAt: (json['processed_at'] ?? '').toString(),
      approvalNote: (json['approval_note'] ?? '').toString(),
      pic: (json['pic'] ?? '').toString(),
      nomorHp: (json['nomor_hp'] ?? '').toString(),
      koordinat: (json['koordinat'] ?? '').toString(),
      tokoLamaNama: (json['toko_lama_nama'] ?? '').toString(),
      tokoBaruNama: (json['toko_baru_nama'] ?? '').toString(),
      tokoLamaId: (json['toko_lama_id'] ?? '').toString(),
      tokoBaruId: (json['toko_baru_id'] ?? '').toString(),
      bolehProses: json['boleh_proses'] == true,
      bolehHapus: json['boleh_hapus'] == true,
    );
  }
}

class RequestPageData {
  const RequestPageData({
    required this.items,
    required this.page,
    required this.total,
    required this.hasMore,
    required this.counts,
  });

  final List<RtsRequest> items;
  final int page;
  final int total;
  final bool hasMore;
  final Map<String, int> counts;

  int get jumlahPending => counts['Pending'] ?? 0;
  int get jumlahDisetujui => counts['Disetujui'] ?? 0;
  int get jumlahDitolak => counts['Ditolak'] ?? 0;

  factory RequestPageData.fromJson(Map<String, dynamic> json) {
    final List<RtsRequest> items = ((json['data'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => RtsRequest.fromJson(item.cast<String, dynamic>()))
        .toList();

    final Map<String, dynamic> meta =
        ((json['meta'] as Map?) ?? const {}).cast<String, dynamic>();

    final Map<String, int> counts = <String, int>{};
    final Object? rawCounts = meta['counts'] ?? json['counts'];

    if (rawCounts is Map) {
      rawCounts.forEach((key, value) {
        counts[key.toString()] = int.tryParse(value.toString()) ?? 0;
      });
    }

    return RequestPageData(
      items: items,
      page: int.tryParse((meta['page'] ?? '1').toString()) ?? 1,
      total: int.tryParse((meta['total'] ?? '0').toString()) ?? 0,
      hasMore: meta['has_more'] == true,
      counts: counts,
    );
  }
}

/* ------------------------------------------------------------------------- */
/* HALAMAN DAFTAR PENGAJUAN                                                   */
/* ------------------------------------------------------------------------- */

/* ------------------------------------------------------------------------- */
/* GSP - GALAN STRATEGIST PARTNER                                            */
/* ------------------------------------------------------------------------- */

/// Menu GSP: dua pilihan, yaitu menambah GSP baru atau menghapus GSP
/// (mengembalikan GSP menjadi toko REGULER). Kedua pengajuan dikirim ke ADMIN
/// dan ASS melalui menu Pengajuan, sama seperti Pengajuan Baru biasa.
class GspMenuPage extends StatelessWidget {
  const GspMenuPage({super.key, required this.user, required this.token});

  final RtsUser user;
  final String token;

  Future<void> _buka(BuildContext context, {required bool tambah}) async {
    final bool? terkirim = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RequestFormPage(
          user: user,
          token: token,
          gsp: true,
          gspJenis: tambah ? 'PENAMBAHAN' : 'PENGHAPUSAN',
        ),
      ),
    );

    if (terkirim == true && context.mounted) {
      rtsShowMessage(
        context,
        'Pengajuan GSP sudah dikirim ke ADMIN dan ASS.',
        success: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.93),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: rtsTextPrimary,
                        ),
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'GSP',
                              style: TextStyle(
                                color: rtsTextPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Galan Strategist Partner',
                              style: TextStyle(
                                color: rtsTextSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [
                      _kartu(
                        context,
                        judul: 'Tambahkan GSP',
                        keterangan: 'Usulkan toko dari Master Customer menjadi '
                            'GSP. Wajib melampirkan foto KTP, foto luar toko, '
                            'dan foto dalam toko.',
                        ikon: Icons.add_business_rounded,
                        onTap: () => _buka(context, tambah: true),
                      ),
                      const SizedBox(height: 13),
                      _kartu(
                        context,
                        judul: 'Hapus GSP',
                        keterangan: 'Usulkan GSP dikembalikan menjadi toko '
                            'REGULER. Caranya sama seperti Hapus Toko pada '
                            'Pengajuan Baru.',
                        ikon: Icons.remove_circle_outline_rounded,
                        onTap: () => _buka(context, tambah: false),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pengajuan akan diperiksa ADMIN dan ASS pada menu '
                        'Pengajuan. Sesudah disetujui, status GSP pada Master '
                        'Customer berubah dengan sendirinya.',
                        style: TextStyle(
                          color: rtsTextSecondary,
                          fontSize: 11.5,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const RtsIklanAsli(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartu(
    BuildContext context, {
    required String judul,
    required String keterangan,
    required IconData ikon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rtsCardBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xfffaecee),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(ikon, color: rtsMaroon, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      judul,
                      style: const TextStyle(
                        color: rtsTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      keterangan,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: rtsTextSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class RequestListPage extends StatefulWidget {
  const RequestListPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<RequestListPage> createState() => _RequestListPageState();
}

class _RequestListPageState extends State<RequestListPage> {
  static const int _pageSize = 20;

  final TextEditingController searchController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  late final ApiClient api = ApiClient(token: widget.token);

  final List<RtsRequest> requests = [];

  String statusFilter = '';
  String tipeFilter = '';
  bool loading = true;
  bool loadingMore = false;
  bool hasMore = false;
  int page = 1;
  int total = 0;
  Map<String, int> counts = const {};
  String? errorMessage;

  int get jumlahPending => counts['Pending'] ?? 0;
  int get jumlahDisetujui => counts['Disetujui'] ?? 0;
  int get jumlahDitolak => counts['Ditolak'] ?? 0;

  @override
  void initState() {
    super.initState();
    scrollController.addListener(_onScroll);
    _loadFirstPage();
  }

  @override
  void dispose() {
    scrollController.removeListener(_onScroll);
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!scrollController.hasClients) return;
    final double sisa = scrollController.position.maxScrollExtent -
        scrollController.position.pixels;
    if (sisa < 260) _loadMore();
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      loading = true;
      errorMessage = null;
      page = 1;
    });

    try {
      final RequestPageData result = await _fetchPage(1);
      if (!mounted) return;
      setState(() {
        requests
          ..clear()
          ..addAll(result.items);
        total = result.total;
        hasMore = result.hasMore;
        page = result.page;
        counts = result.counts;
        loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.message;
      });
      if (error.unauthorized) await _sesiBerakhir();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Terjadi gangguan saat memuat pengajuan.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (loadingMore || loading || !hasMore) return;

    setState(() => loadingMore = true);

    try {
      final RequestPageData result = await _fetchPage(page + 1);
      if (!mounted) return;
      setState(() {
        requests.addAll(result.items);
        total = result.total;
        hasMore = result.hasMore;
        page = result.page;
        counts = result.counts;
        loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingMore = false);
    }
  }

  Future<RequestPageData> _fetchPage(int targetPage) async {
    final Map<String, dynamic> data = await api.get('requests.php', {
      'q': searchController.text.trim(),
      'status': statusFilter,
      'type': tipeFilter,
      'page': targetPage.toString(),
      'limit': _pageSize.toString(),
    });

    return RequestPageData.fromJson(data);
  }

  Future<void> _sesiBerakhir() async {
    await RtsSesi.hapus(hapusPilihan: false);

    if (!mounted) return;

    rtsShowMessage(context, 'Sesi login berakhir. Silakan login kembali.');

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _bukaDetail(RtsRequest request) async {
    final bool? berubah = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RequestDetailPage(
          request: request,
          token: widget.token,
          user: widget.user,
        ),
      ),
    );

    if (berubah == true) _loadFirstPage();
  }

  Future<void> _buatPengajuan() async {
    final bool? terkirim = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RequestFormPage(
          user: widget.user,
          token: widget.token,
        ),
      ),
    );

    if (terkirim == true) _loadFirstPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsMaroon,
        foregroundColor: Colors.white,
        onPressed: _buatPengajuan,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: const Text(
          'Pengajuan Baru',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
        ),
      ),
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Pengajuan',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Pengajuan toko dan GSP',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _loadFirstPage,
            icon: const Icon(Icons.refresh_rounded, color: rtsTextPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            children: [
              TextField(
                controller: searchController,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _loadFirstPage(),
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Cari nama toko, ID customer, atau salesman',
                  hintStyle: const TextStyle(fontSize: 13.5),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xff6d514a),
                    size: 21,
                  ),
                  suffixIcon: IconButton(
                    onPressed: _loadFirstPage,
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    color: rtsMaroon,
                    tooltip: 'Cari',
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.97),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsCardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildFilterBar(
                label: 'Status',
                chips: <_FilterChipData>[
                  _FilterChipData('Semua', statusFilter == '', () {
                    setState(() => statusFilter = '');
                    _loadFirstPage();
                  }),
                  _FilterChipData('Pending ($jumlahPending)',
                      statusFilter == 'Pending', () {
                    setState(() => statusFilter = 'Pending');
                    _loadFirstPage();
                  }),
                  _FilterChipData('Disetujui ($jumlahDisetujui)',
                      statusFilter == 'Disetujui', () {
                    setState(() => statusFilter = 'Disetujui');
                    _loadFirstPage();
                  }),
                  _FilterChipData('Ditolak ($jumlahDitolak)',
                      statusFilter == 'Ditolak', () {
                    setState(() => statusFilter = 'Ditolak');
                    _loadFirstPage();
                  }),
                ],
              ),
              const SizedBox(height: 8),
              _buildFilterBar(
                label: 'Jenis',
                chips: <_FilterChipData>[
                  _FilterChipData('Semua Jenis', tipeFilter == '', () {
                    setState(() => tipeFilter = '');
                    _loadFirstPage();
                  }),
                  _FilterChipData('Toko Reguler', tipeFilter == 'TOKO', () {
                    setState(() => tipeFilter = 'TOKO');
                    _loadFirstPage();
                  }),
                  _FilterChipData('GSP', tipeFilter == 'GSP', () {
                    setState(() => tipeFilter = 'GSP');
                    _loadFirstPage();
                  }),
                ],
              ),
              const SizedBox(height: 11),
              _buildSummary(),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildFilterBar({
    required String label,
    required List<_FilterChipData> chips,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            label,
            style: const TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  _filterChip(chips[i].label, chips[i].selected, chips[i].onTap),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? rtsMaroon : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: selected ? rtsMaroon : rtsCardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : rtsTextSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final String cakupan = widget.user.canApprove
        ? 'Boleh approve / reject'
        : (widget.user.role == 'WSS' || widget.user.role == 'SMST'
            ? 'Hanya melihat'
            : 'Hanya pengajuan Anda');

    return Row(
      children: [
        Text(
          loading ? 'Memuat data...' : '$total pengajuan ditemukan',
          style: const TextStyle(
            color: rtsTextPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            cakupan,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(color: rtsTextSecondary, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  Widget _buildList() {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: rtsMaroon));
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 44, color: rtsTextSecondary),
              const SizedBox(height: 12),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
                onPressed: _loadFirstPage,
                child: const Text('COBA LAGI'),
              ),
            ],
          ),
        ),
      );
    }

    if (requests.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.assignment_outlined,
                  size: 44, color: rtsTextSecondary),
              SizedBox(height: 12),
              Text(
                'Belum ada pengajuan pada filter ini.',
                style: TextStyle(color: rtsTextPrimary, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: rtsMaroon,
      onRefresh: _loadFirstPage,
      child: ListView.separated(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        // Tambahan satu kartu untuk iklan pada urutan paling atas.
        itemCount: requests.length + (loadingMore ? 1 : 0) + 1,
        separatorBuilder: (_, __) => const SizedBox(height: 11),
        itemBuilder: (context, index) {
          if (index == 0) return const RtsIklanAsli();

          index -= 1;

          if (index >= requests.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: rtsMaroon,
                  ),
                ),
              ),
            );
          }

          return _buildRequestTile(requests[index]);
        },
      ),
    );
  }

  Widget _buildRequestTile(RtsRequest request) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _bukaDetail(request),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: rtsCardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: request.isGsp
                          ? const Color(0xfffdf3e0)
                          : const Color(0xffeef3fb),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      request.isGsp
                          ? Icons.local_gas_station_outlined
                          : Icons.storefront_outlined,
                      size: 21,
                      color:
                          request.isGsp ? rtsAmber : const Color(0xff2b5f9e),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request.namaToko.isEmpty ? '-' : request.namaToko,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          request.jenisRequest.isEmpty
                              ? request.tipe
                              : request.jenisRequest,
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _statusBadge(request),
                ],
              ),
              const SizedBox(height: 11),
              Row(
                children: [
                  RtsBadge(
                    request.tipe == 'GSP' ? 'GSP' : 'TOKO',
                    background: request.isGsp
                        ? const Color(0xfffdf3e0)
                        : const Color(0xffeef1f4),
                    foreground: request.isGsp
                        ? rtsAmber
                        : const Color(0xff5c6b7a),
                  ),
                  if (request.idCustomer.isNotEmpty) ...[
                    const SizedBox(width: 7),
                    Text(
                      request.idCustomer,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                  const Spacer(),
                  const Icon(Icons.chevron_right_rounded,
                      color: Color(0xffb8aea6)),
                ],
              ),
              const SizedBox(height: 9),
              _miniRow(Icons.person_outline_rounded,
                  '${request.salesman} • ${request.district}'),
              const SizedBox(height: 5),
              _miniRow(Icons.schedule_rounded, request.tanggalRingkas),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(RtsRequest request) {
    if (request.isPending) {
      return const RtsBadge(
        'PENDING',
        background: Color(0xfffdf6ec),
        foreground: rtsAmber,
      );
    }

    if (request.disetujui) {
      return const RtsBadge(
        'DISETUJUI',
        background: Color(0xffe8f5ec),
        foreground: rtsGreen,
      );
    }

    return const RtsBadge(
      'DITOLAK',
      background: Color(0xfffdeaea),
      foreground: Color(0xffa52020),
    );
  }

  Widget _miniRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: const Color(0xffa99d94)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text.trim().isEmpty ? '-' : text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilterChipData {
  const _FilterChipData(this.label, this.selected, this.onTap);

  final String label;
  final bool selected;
  final VoidCallback onTap;
}

/* ------------------------------------------------------------------------- */
/* HALAMAN DETAIL PENGAJUAN                                                   */
/* ------------------------------------------------------------------------- */

class RequestDetailPage extends StatefulWidget {
  const RequestDetailPage({
    super.key,
    required this.request,
    required this.token,
    required this.user,
  });

  final RtsRequest request;
  final String token;
  final RtsUser user;

  @override
  State<RequestDetailPage> createState() => _RequestDetailPageState();
}

class _RequestDetailPageState extends State<RequestDetailPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  late RtsRequest request = widget.request;
  bool sedangProses = false;

  /// Bernilai true bila ada perubahan status, agar daftar di belakang dimuat ulang.
  bool berubah = false;

  Future<void> _proses(String action) async {
    final bool setuju = action == 'approve';
    final TextEditingController catatanController = TextEditingController();

    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          setuju ? 'Setujui Pengajuan' : 'Tolak Pengajuan',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              setuju
                  ? 'Pengajuan ini akan langsung diterapkan ke Master Customer.'
                  : 'Pengajuan ini akan ditandai sebagai ditolak.',
              style: const TextStyle(fontSize: 13.5, color: rtsTextSecondary),
            ),
            if (RtsConfig.produksi) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: const Color(0xfffdeaea),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xfff0c9c9)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Color(0xffa52020),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'Anda sedang memakai SERVER PRODUKSI. Tindakan ini '
                        'langsung mengubah data customer asli.',
                        style: const TextStyle(
                          color: Color(0xff8a1b1b),
                          fontSize: 11.5,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: catatanController,
              maxLines: 3,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Catatan (boleh dikosongkan)',
                filled: true,
                fillColor: const Color(0xfff8f4ef),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: setuju ? rtsGreen : rtsMaroon,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(setuju ? 'SETUJUI' : 'TOLAK'),
          ),
        ],
      ),
    );

    final String catatan = catatanController.text.trim();
    catatanController.dispose();

    if (lanjut != true) return;

    setState(() => sedangProses = true);

    try {
      final Map<String, dynamic> data = await api.post('request_action.php', {
        'type': request.tipe,
        'id': request.id,
        'action': action,
        'note': catatan,
      });

      if (!mounted) return;

      berubah = true;
      setState(() => sedangProses = false);

      rtsShowMessage(
        context,
        (data['message'] ?? 'Pengajuan berhasil diproses.').toString(),
        success: true,
      );

      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => sedangProses = false);
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => sedangProses = false);
      rtsShowMessage(context, 'Terjadi gangguan saat memproses pengajuan.');
    }
  }

  Future<void> _hapus() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Hapus Pengajuan',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Pengajuan ini akan dihapus dari daftar. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('HAPUS'),
          ),
        ],
      ),
    );

    if (lanjut != true) return;

    setState(() => sedangProses = true);

    try {
      final Map<String, dynamic> data = await api.post('request_action.php', {
        'type': request.tipe,
        'id': request.id,
        'action': 'delete',
      });

      if (!mounted) return;

      berubah = true;
      setState(() => sedangProses = false);

      rtsShowMessage(
        context,
        (data['message'] ?? 'Pengajuan berhasil dihapus.').toString(),
        success: true,
      );

      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => sedangProses = false);
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => sedangProses = false);
      rtsShowMessage(context, 'Terjadi gangguan saat menghapus pengajuan.');
    }
  }

  Future<void> _bukaPeta() async {
    final String titik = request.koordinat.trim();
    if (titik.isEmpty) {
      rtsShowMessage(context, 'Koordinat pada pengajuan ini belum diisi.');
      return;
    }

    final Uri geo = Uri.parse('geo:0,0?q=${Uri.encodeComponent(titik)}');
    final Uri web = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(titik)}',
    );

    for (final Uri uri in <Uri>[geo, web]) {
      try {
        final bool dibuka =
            await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (dibuka) return;
      } catch (_) {
        // coba alternatif berikutnya
      }
    }

    if (mounted) {
      rtsShowMessage(
        context,
        'Aplikasi peta tidak dapat dibuka. Pastikan Google Maps terpasang.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(berubah);
      },
      child: Scaffold(
        body: Stack(
          children: [
            const RtsBackground(overlayOpacity: 0.92),
            SafeArea(
              child: Column(
                children: [
                  _buildTopBar(),
                  Expanded(child: _buildBody()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(berubah),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Text(
              'Detail Pengajuan',
              style: TextStyle(
                color: rtsTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (request.bolehHapus && request.isPending)
            IconButton(
              tooltip: 'Hapus',
              onPressed: sedangProses ? null : _hapus,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: rtsMaroon),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: [
        _buildHeaderCard(),
        const SizedBox(height: 18),
        const RtsIklanAsli(),
        const SizedBox(height: 18),
        const RtsSectionTitle('Data Pengajuan'),
        const SizedBox(height: 11),
        RtsCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(children: _buildDetailRows()),
        ),
        if (request.isGsp) ...[
          const SizedBox(height: 18),
          const RtsSectionTitle('Data GSP'),
          const SizedBox(height: 11),
          RtsCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(children: _buildGspRows()),
          ),
        ],
        if (!request.isPending) ...[
          const SizedBox(height: 18),
          const RtsSectionTitle('Hasil Pemeriksaan'),
          const SizedBox(height: 11),
          RtsCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                RtsInfoRow('Status', request.statusApproval),
                const RtsDivider(),
                RtsInfoRow('Diproses oleh',
                    request.processedBy.isEmpty ? '-' : request.processedBy),
                const RtsDivider(),
                RtsInfoRow('Waktu proses',
                    request.processedAt.isEmpty ? '-' : request.processedAt),
                const RtsDivider(),
                RtsInfoRow('Catatan',
                    request.approvalNote.isEmpty ? '-' : request.approvalNote),
              ],
            ),
          ),
        ],
        if (request.bolehProses) ...[
          const SizedBox(height: 20),
          _buildActionButtons(),
        ],
        if (sedangProses) ...[
          const SizedBox(height: 18),
          const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: rtsMaroon,
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildDetailRows() {
    final List<Widget> baris = [
      RtsInfoRow('Nomor Pengajuan', request.id.toString()),
      const RtsDivider(),
      RtsInfoRow('Jenis Pengajuan', request.jenisRequest),
      const RtsDivider(),
      RtsInfoRow('Tanggal', request.tanggalRingkas),
      const RtsDivider(),
      RtsInfoRow('Nama Toko', request.namaToko),
      const RtsDivider(),
      RtsInfoRow('ID Customer', request.idCustomer),
      const RtsDivider(),
      RtsInfoRow('Alamat', request.alamat),
      const RtsDivider(),
      RtsInfoRow('Salesman', request.salesman),
      const RtsDivider(),
      RtsInfoRow('District', request.district),
    ];

    return baris;
  }

  List<Widget> _buildGspRows() {
    final List<Widget> baris = [];

    if (request.tokoLamaNama.isNotEmpty || request.tokoLamaId.isNotEmpty) {
      baris.add(RtsInfoRow('GSP Lama', request.tokoLamaNama));
      baris.add(const RtsDivider());
      baris.add(RtsInfoRow('ID GSP Lama', request.tokoLamaId));
      baris.add(const RtsDivider());
    }

    if (request.tokoBaruNama.isNotEmpty || request.tokoBaruId.isNotEmpty) {
      baris.add(RtsInfoRow('GSP Baru', request.tokoBaruNama));
      baris.add(const RtsDivider());
      baris.add(RtsInfoRow('ID GSP Baru', request.tokoBaruId));
      baris.add(const RtsDivider());
    }

    baris.add(RtsInfoRow('PIC', request.pic));
    baris.add(const RtsDivider());
    baris.add(RtsInfoRow('Nomor HP', request.nomorHp));
    baris.add(const RtsDivider());
    baris.add(RtsInfoRow('Koordinat', request.koordinat));

    if (request.koordinat.trim().isNotEmpty) {
      baris.add(const SizedBox(height: 12));
      baris.add(
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: rtsMaroon,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: _bukaPeta,
            icon: const Icon(Icons.map_rounded, size: 19),
            label: const Text(
              'BUKA DI GOOGLE MAPS',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
              ),
            ),
          ),
        ),
      );
      baris.add(const SizedBox(height: 6));
    }

    return baris;
  }

  Widget _buildHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.28),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RtsBadge(
                request.isGsp ? 'GSP' : 'TOKO REGULER',
                background: Colors.white.withValues(alpha: 0.2),
                foreground: Colors.white,
              ),
              const SizedBox(width: 7),
              RtsBadge(
                request.statusApproval.toUpperCase(),
                background: Colors.white.withValues(alpha: 0.2),
                foreground: Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            request.namaToko.isEmpty ? '-' : request.namaToko,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            request.jenisRequest.isEmpty ? request.tipe : request.jenisRequest,
            style: const TextStyle(color: Color(0xb3ffffff), fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.18)),
          const SizedBox(height: 13),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: Color(0xb3ffffff)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${request.salesman} • ${request.district}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: rtsMaroon,
                side: const BorderSide(color: rtsMaroon, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: sedangProses ? null : () => _proses('reject'),
              icon: const Icon(Icons.close_rounded, size: 19),
              label: const Text(
                'TOLAK',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rtsGreen,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: sedangProses ? null : () => _proses('approve'),
              icon: const Icon(Icons.check_rounded, size: 19),
              label: const Text(
                'SETUJUI',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PEMILIH SERVER                                                             */
/* ------------------------------------------------------------------------- */

/// Menampilkan pilihan server. Mengembalikan indeks pilihan, atau null bila batal.
Future<int?> showServerPicker(BuildContext context) {
  int pilihan = RtsConfig.indeksServer;

  return showDialog<int>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (builderContext, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Pilih Server',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Token login berbeda pada setiap server, jadi Anda perlu login '
              'ulang setelah berpindah server.',
              style: TextStyle(fontSize: 12.5, color: rtsTextSecondary),
            ),
            const SizedBox(height: 14),
            for (int i = 0; i < rtsServers.length; i++)
              _buildServerOption(
                rtsServers[i],
                i,
                pilihan == i,
                (int nilai) => setDialogState(() => pilihan = nilai),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(pilihan),
            child: const Text('GUNAKAN'),
          ),
        ],
      ),
    ),
  );
}

Widget _buildServerOption(
  RtsServer server,
  int indeks,
  bool terpilih,
  void Function(int) onPilih,
) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onPilih(indeks),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: terpilih
              ? (server.produksi
                  ? const Color(0xffeef5ef)
                  : const Color(0xfffdf6ec))
              : const Color(0xfff9f6f2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: terpilih
                ? (server.produksi ? rtsGreen : rtsAmber)
                : rtsCardBorder,
            width: terpilih ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              server.produksi
                  ? Icons.verified_user_outlined
                  : Icons.science_outlined,
              size: 20,
              color: server.produksi ? rtsGreen : rtsAmber,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server.nama,
                    style: const TextStyle(
                      color: rtsTextPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${server.keterangan} • ${server.database}',
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              terpilih
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 20,
              color: terpilih ? rtsMaroon : const Color(0xffb8aea6),
            ),
          ],
        ),
      ),
    ),
  );
}

/* ------------------------------------------------------------------------- */
/* HALAMAN PENGATURAN                                                         */
/* ------------------------------------------------------------------------- */

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.user,
    required this.token,
  });

  final RtsUser user;
  final String token;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool? notifAktif;

  @override
  void initState() {
    super.initState();
    _muatStatusNotif();
  }

  Future<void> _muatStatusNotif() async {
    final bool aktif = await RtsLayananNotif.izinDiberikan();

    if (!mounted) return;

    setState(() => notifAktif = aktif);
  }

  Future<void> _mintaIzinNotif() async {
    final bool hasil = await RtsLayananNotif.mintaIzin();

    await _muatStatusNotif();

    if (!mounted) return;

    if (!hasil) {
      rtsShowMessage(
        context,
        'Izin pemberitahuan belum diberikan. Buka Pengaturan HP > Aplikasi > '
        'RTS Panel > Notifikasi.',
      );
      return;
    }

    RtsPemantauLatar.mulaiDepan();
    await RtsPemantauNotif.periksa();
    await RtsLayananNotif.tampilkanPercobaan();

    if (!mounted) return;

    rtsShowMessage(
      context,
      'Pemberitahuan HP diaktifkan. Pemberitahuan percobaan dikirim.',
      success: true,
    );
  }

  Future<void> _tesNotif() async {
    await RtsLayananNotif.tampilkanPercobaan();

    if (!mounted) return;

    rtsShowMessage(
      context,
      'Pemberitahuan percobaan dikirim. Periksa bagian atas layar HP Anda.',
      success: true,
    );
  }

  Future<void> _gantiServer() async {
    final int? pilihan = await showServerPicker(context);

    if (pilihan == null || pilihan == RtsConfig.indeksServer) return;

    await RtsConfig.simpan(pilihan);
    await RtsSesi.hapus(hapusPilihan: false);

    if (!mounted) return;

    rtsShowMessage(
      context,
      'Server diubah ke ${rtsServers[pilihan].nama}. Silakan login kembali.',
      success: true,
    );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.92),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
                    children: [
                      _buildServerCard(),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Akun'),
                      const SizedBox(height: 11),
                      RtsCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            RtsInfoRow('Nama', widget.user.displayName),
                            const RtsDivider(),
                            RtsInfoRow('Username', widget.user.username),
                            const RtsDivider(),
                            RtsInfoRow('Role', widget.user.role),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Aplikasi'),
                      const SizedBox(height: 11),
                      RtsCard(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            RtsInfoRow('Versi aplikasi', RtsVersi.label),
                            const RtsDivider(),
                            RtsInfoRow('Server', RtsConfig.server.nama),
                            const RtsDivider(),
                            RtsInfoRow('Database', RtsConfig.server.database),
                            const RtsDivider(),
                            RtsInfoRow('Alamat API', RtsConfig.baseUrl),
                            const RtsDivider(),
                            RtsInfoRow(
                              'Ingat saya',
                              RtsSesi.ingatSaya ? 'Aktif' : 'Tidak aktif',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Cuaca Beranda'),
                      const SizedBox(height: 11),
                      const RtsKartuCuaca(),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Pembaruan Aplikasi'),
                      const SizedBox(height: 11),
                      const RtsKartuPembaruan(),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Pemberitahuan HP'),
                      const SizedBox(height: 11),
                      _buildNotifCard(),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Sesi Login'),
                      const SizedBox(height: 11),
                      _buildSesiCard(),
                      const SizedBox(height: 20),
                      const RtsSectionTitle('Diagnosa Data'),
                      const SizedBox(height: 11),
                      _buildDiagnosaCard(),
                      const SizedBox(height: 20),
                      const RtsIklanAsli(),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 52,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: rtsMaroon,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          onPressed: _gantiServer,
                          icon: const Icon(Icons.dns_outlined, size: 19),
                          label: const Text(
                            'GANTI SERVER',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.9,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotifCard() {
    final bool? aktif = notifAktif;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Pemberitahuan muncul pada bagian atas layar HP, sehingga Anda '
            'langsung mengetahui ada pengajuan baru atau pengajuan yang sudah '
            'diperiksa, walau aplikasi sedang tidak dibuka.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: aktif == true
                  ? const Color(0xffe8f5ec)
                  : const Color(0xfff8f4ef),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: aktif == true ? const Color(0xffcfe6d6) : rtsCardBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  aktif == true
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  size: 19,
                  color: aktif == true ? rtsGreen : rtsTextSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        aktif == null
                            ? 'Memeriksa izin...'
                            : (aktif
                                ? 'Pemberitahuan HP aktif'
                                : 'Pemberitahuan HP belum diizinkan'),
                        style: TextStyle(
                          color: aktif == true
                              ? const Color(0xff2f6b45)
                              : rtsTextPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        aktif == true
                            ? 'Pemeriksaan berjalan setiap 2 menit saat '
                                'aplikasi terbuka, dan setiap kali aplikasi '
                                'dibuka kembali.'
                            : 'Tekan tombol di bawah untuk mengizinkan '
                                'pemberitahuan.',
                        style: TextStyle(
                          color: aktif == true
                              ? const Color(0xff3f7a55)
                              : rtsTextSecondary,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                RtsPushFcm.status.startsWith('Aktif')
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 15,
                color: RtsPushFcm.status.startsWith('Aktif')
                    ? const Color(0xff2f6b45)
                    : const Color(0xff9a6b1f),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Firebase: ${RtsPushFcm.status}',
                  style: const TextStyle(
                    color: rtsTextSecondary,
                    fontSize: 11.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rtsMaroon,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _mintaIzinNotif,
              icon: const Icon(Icons.notifications_none_rounded, size: 18),
              label: Text(
                aktif == true
                    ? 'MINTA IZIN ULANG'
                    : 'IZINKAN PEMBERITAHUAN',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: rtsMaroon,
                side: const BorderSide(color: rtsMaroon, width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _tesNotif,
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text(
                'KIRIM PEMBERITAHUAN PERCOBAAN',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfffdf6ec),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xfff0e2cf)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.battery_alert_outlined,
                  size: 18,
                  color: Color(0xff9a6b23),
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Pemberitahuan masuk selama aplikasi masih berjalan di '
                    'latar belakang HP. Buka Pengaturan HP > Baterai > '
                    'RTS Panel, lalu pilih Tidak dibatasi (Unrestricted) agar '
                    'aplikasi tidak dimatikan oleh sistem saat ditutup.',
                    style: TextStyle(
                      color: Color(0xff7a5a26),
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSesiCard() {
    final bool adaSesi = RtsSesi.adaSesi;
    final RtsUser? user = RtsSesi.user;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dengan pilihan Ingat saya, token login disimpan pada penyimpanan '
            'pribadi aplikasi ini, sehingga Anda tidak perlu mengetik username '
            'dan password setiap kali membuka aplikasi. Token otomatis dibuang '
            'bila Anda menekan Keluar, mengganti server, atau bila server '
            'menyatakan sesi sudah berakhir.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: adaSesi
                  ? const Color(0xffe8f5ec)
                  : const Color(0xfff8f4ef),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: adaSesi
                    ? const Color(0xffcfe6d6)
                    : rtsCardBorder,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  adaSesi
                      ? Icons.lock_clock_outlined
                      : Icons.lock_outline_rounded,
                  size: 19,
                  color: adaSesi ? rtsGreen : rtsTextSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        adaSesi
                            ? 'Sesi tersimpan aktif'
                            : 'Tidak ada sesi tersimpan',
                        style: TextStyle(
                          color: adaSesi ? const Color(0xff2f6b45) : rtsTextPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        adaSesi
                            ? 'Dibuka kembali sebagai '
                                '${user?.displayName ?? "-"} pada server '
                                '${RtsConfig.server.nama}.'
                            : 'Aplikasi akan meminta login setiap kali dibuka.',
                        style: TextStyle(
                          color: adaSesi
                              ? const Color(0xff3f7a55)
                              : rtsTextSecondary,
                          fontSize: 11.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (adaSesi) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: rtsMaroon,
                  side: const BorderSide(color: rtsMaroon, width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _lupakanSesi,
                icon: const Icon(Icons.lock_reset_rounded, size: 18),
                label: const Text(
                  'LUPAKAN SESI TERSIMPAN',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _lupakanSesi() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Lupakan Sesi',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text(
          'Sesi tersimpan akan dihapus dan aplikasi menutup sesi ini. Anda '
          'perlu mengetik username dan password lagi saat membuka aplikasi.',
          style: TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('LUPAKAN'),
          ),
        ],
      ),
    );

    if (lanjut != true) return;

    await RtsSesi.hapus();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Widget _buildDiagnosaCard() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Memeriksa apakah cakupan data akun Anda sudah sesuai penugasan. '
            'Berguna bila daftar customer terasa kurang atau lebih.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 13),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: rtsMaroon,
                side: const BorderSide(color: rtsMaroon, width: 1.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _jalankanDiagnosa,
              icon: const Icon(Icons.troubleshoot_rounded, size: 18),
              label: const Text(
                'JALANKAN DIAGNOSA',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _jalankanDiagnosa() async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: CircularProgressIndicator(color: rtsMaroon),
        ),
      ),
    );

    try {
      final ApiClient api = ApiClient(token: widget.token);
      final Map<String, dynamic> data = await api.get('scope_check.php');

      if (!mounted) return;
      Navigator.of(context).pop();

      final Map<String, dynamic> akun =
          ((data['akun'] as Map?) ?? const {}).cast<String, dynamic>();
      final Map<String, dynamic> scope =
          ((data['scope'] as Map?) ?? const {}).cast<String, dynamic>();
      final Map<String, dynamic> hitung =
          ((data['hitungan'] as Map?) ?? const {}).cast<String, dynamic>();

      String nilai(Object? isi) => (isi ?? '0').toString();

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Diagnosa Cakupan Data',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _barisDiagnosa('Role', (akun['role'] ?? '-').toString()),
                _barisDiagnosa('Salesman', (akun['salesman'] ?? '-').toString()),
                _barisDiagnosa(
                  'Sales District',
                  (akun['sales_district'] ?? '-').toString(),
                ),
                _barisDiagnosa('Mode cakupan', (scope['mode'] ?? '-').toString()),
                const Divider(height: 22),
                _barisDiagnosa(
                  'Total seluruh customer',
                  nilai(hitung['total_semua_customer']),
                ),
                _barisDiagnosa(
                  'Cocok district akun',
                  nilai(hitung['cocok_district']),
                ),
                _barisDiagnosa(
                  'Cocok salesman akun',
                  nilai(hitung['cocok_salesman']),
                ),
                _barisDiagnosa(
                  'Customer aktif pada cakupan',
                  nilai(hitung['aktif_pada_cakupan']),
                ),
                _barisDiagnosa(
                  'GSP pada cakupan',
                  nilai(hitung['gsp_pada_cakupan']),
                ),
                _barisDiagnosa(
                  'Pengajuan pending',
                  nilai(hitung['pengajuan_pending']),
                ),
                const Divider(height: 22),
                Text(
                  (data['catatan'] ?? '').toString(),
                  style: const TextStyle(
                    color: rtsTextSecondary,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('TUTUP'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      rtsShowMessage(context, 'Diagnosa gagal dijalankan.');
    }
  }

  Widget _barisDiagnosa(String label, String nilai) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: const TextStyle(color: rtsTextSecondary, fontSize: 12.5),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              nilai,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: rtsTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Text(
              'Pengaturan',
              style: TextStyle(
                color: rtsTextPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerCard() {
    final RtsServer server = RtsConfig.server;
    final bool produksi = server.produksi;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: produksi
              ? <Color>[const Color(0xff1e7a45), const Color(0xff146034)]
              : <Color>[rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.25),
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SERVER AKTIF',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                produksi
                    ? Icons.verified_user_outlined
                    : Icons.science_outlined,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.nama,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      server.keterangan,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 12),
          Text(
            server.baseUrl,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Database: ${server.database}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.75),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* FORM PENGAJUAN DARI ANDROID                                                */
/* ------------------------------------------------------------------------- */

const List<String> rtsJenisPengajuan = <String>[
  'Tambah Baru',
  'Ganti Nama',
  'Ganti Alamat',
  'Hapus Toko',
];

const List<String> rtsHariKunjungan = <String>[
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
];

/// Isi kolom `kunjungan` pada tabel master_toko.
const List<String> rtsFrekuensiKunjungan = <String>[
  'Weekly',
  'Bi-Weekly Ganjil',
  'Bi-Weekly Genap',
];

/// Keterangan tingkat keakuratan titik GPS.
class RtsAkurasi {
  const RtsAkurasi({
    required this.label,
    required this.catatan,
    required this.warna,
    required this.latar,
    required this.garis,
    required this.ikon,
  });

  final String label;
  final String catatan;
  final Color warna;
  final Color latar;
  final Color garis;
  final IconData ikon;
}

RtsAkurasi rtsAkurasiInfo(double? meter) {
  if (meter == null) {
    return const RtsAkurasi(
      label: 'Titik lokasi belum dibaca',
      catatan: 'Centang "Sesuai koordinat sekarang" atau ketuk ikon titik '
          'lokasi pada kolom alamat untuk mengisi alamat dari titik GPS.',
      warna: rtsTextSecondary,
      latar: Color(0xfff8f4ef),
      garis: rtsCardBorder,
      ikon: Icons.location_searching_rounded,
    );
  }

  if (meter <= 10) {
    return const RtsAkurasi(
      label: 'Sangat akurat',
      catatan: 'Titik ini sudah tepat dan aman dipakai sebagai alamat baru.',
      warna: rtsGreen,
      latar: Color(0xffe8f5ec),
      garis: Color(0xffcfe6d6),
      ikon: Icons.gps_fixed_rounded,
    );
  }

  if (meter <= 25) {
    return const RtsAkurasi(
      label: 'Akurat',
      catatan: 'Titik sudah baik. Bila perlu, tunggu beberapa detik lalu '
          'perbarui titik.',
      warna: Color(0xff2b5f9e),
      latar: Color(0xffeaf1fb),
      garis: Color(0xffd3e0f5),
      ikon: Icons.gps_fixed_rounded,
    );
  }

  if (meter <= 60) {
    return const RtsAkurasi(
      label: 'Cukup akurat',
      catatan: 'Sebaiknya berdiri di depan toko atau dekat jalan terbuka lalu '
          'tekan Perbarui Titik.',
      warna: rtsAmber,
      latar: Color(0xfffdf6ec),
      garis: Color(0xfff0e2cf),
      ikon: Icons.gps_not_fixed_rounded,
    );
  }

  return const RtsAkurasi(
    label: 'Kurang akurat',
    catatan: 'Titik masih meleset. Keluar dari dalam bangunan, tunggu beberapa '
        'detik, lalu tekan Perbarui Titik.',
    warna: Color(0xffa52020),
    latar: Color(0xfffdeaea),
    garis: Color(0xfff0c9c9),
    ikon: Icons.gps_off_rounded,
  );
}

class RequestFormPage extends StatefulWidget {
  const RequestFormPage({
    super.key,
    required this.user,
    required this.token,
    this.customer,
    this.jenisAwal,
    this.gsp = false,
    this.gspJenis = 'PENAMBAHAN',
  });

  final RtsUser user;
  final String token;

  /// Bila diisi, pengajuan langsung tertuju ke customer ini.
  final Customer? customer;

  /// Jenis awal yang dipilih, misalnya saat datang dari detail customer.
  final String? jenisAwal;

  /// Mode GSP: isian memakai formulir GSP (foto KTP, luar toko, dalam toko)
  /// dan dikirim ke api/request_create_gsp.php (tabel pengajuan_gsp).
  final bool gsp;

  /// PENAMBAHAN = Tambahkan GSP, PENGHAPUSAN = Hapus GSP.
  final String gspJenis;

  @override
  State<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends State<RequestFormPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  final TextEditingController namaBaruController = TextEditingController();
  final TextEditingController alamatBaruController = TextEditingController();
  final TextEditingController picController = TextEditingController();
  final TextEditingController alasanController = TextEditingController();

  /// Customer yang sedang dituju pengajuan.
  Customer? customer;

  late String jenis;
  String tipeBaru = 'REGULER';
  String hariKunjungan = 'Senin';
  String frekuensi = 'Weekly';

  /// Kolom keterangan yang berasal dari database terkunci sampai dicentang.
  bool bukaHari = false;
  bool bukaFrekuensi = false;

  /// Alamat dari titik GPS.
  bool pakaiKoordinat = false;
  bool sedangCariLokasi = false;
  double? lintang;
  double? bujur;
  double? akurasiMeter;
  String pesanLokasi = '';

  /// Alamat yang diketik manual, disimpan supaya dapat dikembalikan.
  String alamatManual = '';

  bool menyimpan = false;

  /// Penanda mode GSP (Tambahkan GSP / Hapus GSP).
  bool get modeGsp => widget.gsp;

  bool get gspTambah =>
      widget.gsp && widget.gspJenis.toUpperCase() != 'PENGHAPUSAN';

  /// Foto GSP yang dilampirkan: KTP, luar toko, dan dalam toko.
  XFile? fotoKtp;
  XFile? fotoLuar;
  XFile? fotoDalam;

  final TextEditingController nomorHpController = TextEditingController();
  final ImagePicker pemilihFoto = ImagePicker();

  bool get adaCustomer => customer != null;

  @override
  void initState() {
    super.initState();
    customer = widget.customer;
    jenis = _jenisAwal();

    final Customer? awal = customer;
    if (awal != null) _terapkanCustomer(awal);
  }

  @override
  void dispose() {
    namaBaruController.dispose();
    alamatBaruController.dispose();
    picController.dispose();
    alasanController.dispose();
    nomorHpController.dispose();
    super.dispose();
  }

  String _jenisAwal() {
    if (widget.jenisAwal != null &&
        rtsJenisPengajuan.contains(widget.jenisAwal)) {
      return widget.jenisAwal!;
    }

    return customer != null ? 'Ganti Nama' : 'Tambah Baru';
  }

  String _hariRapi(String hari) {
    final String bersih = hari.trim();

    for (final String pilihan in rtsHariKunjungan) {
      if (bersih.toLowerCase() == pilihan.toLowerCase()) return pilihan;
    }

    return bersih.isEmpty ? 'Senin' : bersih;
  }

  /// Mengisi kolom keterangan dari data customer yang dipilih di database.
  void _terapkanCustomer(Customer data) {
    customer = data;

    if (jenis == 'Tambah Baru') jenis = 'Ganti Nama';

    hariKunjungan = _hariRapi(data.hari);
    frekuensi =
        data.kunjungan.trim().isEmpty ? 'Weekly' : data.kunjungan.trim();

    bukaHari = false;
    bukaFrekuensi = false;

    // Alamat baru dimulai dari alamat sekarang supaya mudah disunting.
    alamatManual = data.alamat;
    alamatBaruController.text = data.alamat;
    namaBaruController.text = data.namaToko;

    pakaiKoordinat = false;
    lintang = null;
    bujur = null;
    akurasiMeter = null;
    pesanLokasi = '';
  }

  /// Mengembalikan form ke keadaan pengajuan toko baru.
  void _kosongkanCustomer() {
    setState(() {
      customer = null;
      jenis = 'Tambah Baru';
      namaBaruController.clear();
      alamatBaruController.clear();
      alamatManual = '';
      hariKunjungan = 'Senin';
      frekuensi = 'Weekly';
      bukaHari = false;
      bukaFrekuensi = false;
      pakaiKoordinat = false;
      lintang = null;
      bujur = null;
      akurasiMeter = null;
      pesanLokasi = '';
    });
  }

  /* ----------------------------------------------------------------- pilih toko */

  Future<void> _pilihCustomer() async {
    final Customer? dipilih = await showModalBottomSheet<Customer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomerPickerSheet(
        api: api,
        tipe: modeGsp ? (gspTambah ? 'REGULER' : 'GSP') : '',
        judul: modeGsp
            ? (gspTambah
                ? 'Pilih Toko untuk Dijadikan GSP'
                : 'Pilih Toko GSP yang Dihapus')
            : 'Pilih Toko',
      ),
    );

    if (dipilih == null || !mounted) return;

    setState(() => _terapkanCustomer(dipilih));
  }

  /// Menekan pilihan jenis pengajuan.
  ///
  /// Ganti Nama, Ganti Alamat, dan Hapus Toko memerlukan toko yang dituju,
  /// jadi daftar toko langsung dibuka bila belum ada yang dipilih.
  Future<void> _pilihJenis(String item) async {
    if (item == 'Tambah Baru') {
      _kosongkanCustomer();
      return;
    }

    if (customer == null) {
      await _pilihCustomer();

      if (!mounted || customer == null) return;
    }

    setState(() => jenis = item);
  }

  /* -------------------------------------------------------------- titik GPS */

  /// Mengubah titik koordinat menjadi alamat lengkap.
  /// Mengembalikan teks kosong bila alamat tidak dapat dibaca.
  Future<String> _alamatDariTitik(double lat, double lng) async {
    try {
      final List<Placemark> daftar = await placemarkFromCoordinates(lat, lng);

      if (daftar.isEmpty) return '';

      final Placemark tempat = daftar.first;
      final List<String> bagian = <String>[];

      void tambah(String? nilai) {
        final String bersih = (nilai ?? '').trim();

        if (bersih.isEmpty) return;
        if (bagian.any((String ada) => ada.toLowerCase() == bersih.toLowerCase())) {
          return;
        }

        bagian.add(bersih);
      }

      tambah(tempat.street);
      tambah(tempat.subLocality);
      tambah(tempat.locality);
      tambah(tempat.subAdministrativeArea);
      tambah(tempat.administrativeArea);
      tambah(tempat.postalCode);

      return bagian.join(', ');
    } catch (_) {
      return '';
    }
  }

  /// Mengubah pilihan "Sesuai koordinat sekarang".
  /// Teks alamat yang sedang diketik disimpan lebih dahulu supaya tidak hilang.
  void _ubahPakaiKoordinat(bool dipilih) {
    if (dipilih) {
      alamatManual = alamatBaruController.text.trim();
      setState(() => pakaiKoordinat = true);
      _ambilLokasi();
      return;
    }

    setState(() {
      pakaiKoordinat = false;
      lintang = null;
      bujur = null;
      akurasiMeter = null;
      pesanLokasi = '';
      alamatBaruController.text = alamatManual;
    });
  }

  void _gagalLokasi(String pesan) {
    setState(() {
      sedangCariLokasi = false;
      pakaiKoordinat = false;
      pesanLokasi = pesan;
      alamatBaruController.text = alamatManual;
    });
  }

  Future<void> _ambilLokasi() async {
    setState(() {
      sedangCariLokasi = true;
      pesanLokasi = 'Sedang membaca titik lokasi...';
    });

    try {
      final bool layananAktif = await Geolocator.isLocationServiceEnabled();

      if (!mounted) return;

      if (!layananAktif) {
        _gagalLokasi('GPS belum aktif. Nyalakan Lokasi pada HP, lalu coba lagi.');
        return;
      }

      LocationPermission izin = await Geolocator.checkPermission();

      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      if (izin == LocationPermission.denied) {
        _gagalLokasi(
          'Izin lokasi ditolak. Aplikasi memerlukan izin Lokasi untuk '
          'mengisi alamat dari titik GPS.',
        );
        return;
      }

      if (izin == LocationPermission.deniedForever) {
        _gagalLokasi(
          'Izin lokasi diblokir. Buka Pengaturan > Aplikasi > RTS Panel > '
          'Izin > Lokasi, lalu izinkan.',
        );
        return;
      }

      final Position posisi = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 25),
        ),
      );

      if (!mounted) return;

      setState(() {
        lintang = posisi.latitude;
        bujur = posisi.longitude;
        akurasiMeter = posisi.accuracy;
        pesanLokasi = 'Menerjemahkan titik menjadi alamat...';
      });

      final String alamat = await _alamatDariTitik(
        posisi.latitude,
        posisi.longitude,
      );

      if (!mounted) return;

      final String isi = alamat.isNotEmpty
          ? alamat
          : 'Koordinat: ${posisi.latitude.toStringAsFixed(6)}, '
              '${posisi.longitude.toStringAsFixed(6)}';

      setState(() {
        sedangCariLokasi = false;
        pesanLokasi = alamat.isEmpty
            ? 'Alamat otomatis tidak dapat dibaca (perlu koneksi internet). '
                'Koordinat dipakai sebagai pengganti.'
            : '';
        alamatBaruController.text = isi;
      });
    } catch (_) {
      if (!mounted) return;

      _gagalLokasi(
        'Gagal membaca lokasi. Berdirilah di tempat terbuka, tunggu beberapa '
        'detik, lalu coba lagi.',
      );
    }
  }

  Future<void> _bukaTitikDiMaps() async {
    final double? lat = lintang;
    final double? lng = bujur;

    if (lat == null || lng == null) {
      rtsShowMessage(context, 'Titik lokasi belum dibaca.');
      return;
    }

    final Uri googleMaps = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );

    try {
      final bool dibuka =
          await launchUrl(googleMaps, mode: LaunchMode.externalApplication);
      if (dibuka) return;
    } catch (_) {
      // lanjut ke pesan di bawah
    }

    if (mounted) {
      rtsShowMessage(
        context,
        'Aplikasi peta tidak dapat dibuka. Pastikan Google Maps terpasang.',
      );
    }
  }

  /* -------------------------------------------------------------------- kirim */

  Future<void> _kirim() async {
    FocusScope.of(context).unfocus();

    if (modeGsp) {
      await _kirimGsp();
      return;
    }

    final Customer? data = customer;
    final String alasan = alasanController.text.trim();
    final String namaBaru = namaBaruController.text.trim();
    final String alamatBaru = alamatBaruController.text.trim();

    if (alasan.isEmpty) {
      rtsShowMessage(context, 'Alasan pengajuan wajib diisi.');
      return;
    }

    if (jenis != 'Tambah Baru' && data == null) {
      rtsShowMessage(context, 'Pilih dulu toko yang dituju pada kolom Nama Toko.');
      return;
    }

    if (jenis == 'Tambah Baru' && namaBaru.isEmpty) {
      rtsShowMessage(context, 'Nama toko baru wajib diisi.');
      return;
    }

    if (jenis == 'Ganti Nama') {
      if (namaBaru.isEmpty) {
        rtsShowMessage(context, 'Nama toko baru wajib diisi.');
        return;
      }

      if (namaBaru.toLowerCase() == (data?.namaToko ?? '').trim().toLowerCase()) {
        rtsShowMessage(
          context,
          'Nama baru masih sama dengan nama sekarang. Ubah namanya lebih dulu.',
        );
        return;
      }
    }

    if (jenis == 'Ganti Alamat') {
      if (alamatBaru.isEmpty) {
        rtsShowMessage(context, 'Alamat baru wajib diisi.');
        return;
      }

      if (pakaiKoordinat && (lintang == null || bujur == null)) {
        rtsShowMessage(
          context,
          'Titik lokasi belum terbaca. Tekan Perbarui Titik lebih dulu.',
        );
        return;
      }

      if (alamatBaru == (data?.alamat ?? '').trim()) {
        rtsShowMessage(context, 'Alamat baru masih sama dengan alamat sekarang.');
        return;
      }
    }

    setState(() => menyimpan = true);

    try {
      final Map<String, dynamic> hasil = await api.post('request_create.php', {
        'jenis': jenis,
        'id_customer': data?.idCustomer ?? '',
        'nama_toko_lama': data?.namaToko ?? '',
        'nama_toko_baru':
            (jenis == 'Ganti Nama' || jenis == 'Tambah Baru') ? namaBaru : '',
        'alamat_lama': data?.alamat ?? '',
        'alamat_baru':
            (jenis == 'Ganti Alamat' || jenis == 'Tambah Baru') ? alamatBaru : '',
        'tipe_baru': tipeBaru,
        'visit_day_baru': hariKunjungan,
        'pic': picController.text.trim(),
        'rute_kunjungan': hariKunjungan,
        'week': frekuensi,
        'alasan': alasan,
      });

      if (!mounted) return;
      setState(() => menyimpan = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Pengajuan Terkirim',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            (hasil['message'] ?? 'Pengajuan berhasil dikirim.').toString(),
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => menyimpan = false);
      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => menyimpan = false);
      rtsShowMessage(context, 'Terjadi gangguan saat mengirim pengajuan.');
    }
  }

  /// Mengirim pengajuan GSP beserta foto KTP, luar toko, dan dalam toko.
  ///
  /// Berkas dikirim sebagai form-data (multipart) ke
  /// api/request_create_gsp.php, lalu disimpan pada tabel pengajuan_gsp.
  Future<void> _kirimGsp() async {
    final Customer? data = customer;

    if (data == null) {
      rtsShowMessage(context, 'Pilih dulu toko pada kolom Nama Toko.');
      return;
    }

    if (gspTambah) {
      if (picController.text.trim().isEmpty) {
        rtsShowMessage(context, 'Nama PIC (penanggung jawab) wajib diisi.');
        return;
      }

      if (nomorHpController.text.trim().isEmpty) {
        rtsShowMessage(context, 'Nomor HP PIC wajib diisi.');
        return;
      }

      if (lintang == null || bujur == null) {
        rtsShowMessage(
          context,
          'Titik lokasi belum terbaca. Centang "Sesuai koordinat sekarang" '
          'lalu tunggu sampai titik terbaca.',
        );
        return;
      }

      if (fotoKtp == null || fotoLuar == null || fotoDalam == null) {
        rtsShowMessage(
          context,
          'Foto KTP, foto luar toko, dan foto dalam toko wajib dilampirkan.',
        );
        return;
      }
    }

    setState(() => menyimpan = true);

    try {
      final Uri alamatGsp = Uri.parse(
        '${RtsConfig.baseUrl}/request_create_gsp.php',
      );

      final http.MultipartRequest permintaan =
          http.MultipartRequest('POST', alamatGsp);

      permintaan.headers['Accept'] = 'application/json';
      permintaan.headers['Authorization'] = 'Bearer ${widget.token}';

      permintaan.fields['jenis'] = gspTambah ? 'PENAMBAHAN' : 'PENGHAPUSAN';
      permintaan.fields['id_customer'] = data.idCustomer;
      permintaan.fields['nama_toko'] = data.namaToko;
      permintaan.fields['alamat'] = alamatBaruController.text.trim().isEmpty
          ? data.alamat
          : alamatBaruController.text.trim();
      permintaan.fields['pic'] = picController.text.trim();
      permintaan.fields['nomor_hp'] = nomorHpController.text.trim();
      permintaan.fields['koordinat'] =
          (lintang != null && bujur != null) ? '$lintang,$bujur' : '';
      permintaan.fields['alasan'] = alasanController.text.trim();

      if (gspTambah) {
        permintaan.files.add(
          await http.MultipartFile.fromPath(
            'foto_ktp',
            fotoKtp!.path,
            filename: 'foto_ktp.jpg',
          ),
        );
        permintaan.files.add(
          await http.MultipartFile.fromPath(
            'foto_luar',
            fotoLuar!.path,
            filename: 'foto_luar.jpg',
          ),
        );
        permintaan.files.add(
          await http.MultipartFile.fromPath(
            'foto_dalam',
            fotoDalam!.path,
            filename: 'foto_dalam.jpg',
          ),
        );
      }

      final http.StreamedResponse aliran =
          await permintaan.send().timeout(const Duration(seconds: 120));

      final String isi = await aliran.stream.bytesToString();

      Map<String, dynamic> balasan = <String, dynamic>{};

      if (isi.trim().isNotEmpty) {
        try {
          final dynamic urai = jsonDecode(isi);

          if (urai is Map) balasan = urai.cast<String, dynamic>();
        } catch (_) {
          // Balasan bukan JSON: dipakai keterangan bawaan di bawah.
        }
      }

      if (!mounted) return;
      setState(() => menyimpan = false);

      if (aliran.statusCode < 200 || aliran.statusCode >= 300) {
        rtsShowMessage(
          context,
          (balasan['message'] ??
                  'Pengajuan GSP gagal dikirim (kode ${aliran.statusCode}).')
              .toString(),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Pengajuan GSP Terkirim',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            (balasan['message'] ??
                    'Pengajuan GSP berhasil dikirim dan menunggu pemeriksaan.')
                .toString(),
            style: const TextStyle(fontSize: 13.5),
          ),
          actions: [
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => menyimpan = false);
      rtsShowMessage(
        context,
        'Terjadi gangguan saat mengirim pengajuan GSP. Periksa jaringan '
        'internet lalu coba lagi.',
      );
    }
  }

  /* ------------------------------------------------------------------ tampilan */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.93),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      _buildRingkasanPengirim(),
                      const SizedBox(height: 18),
                      if (modeGsp) ...[
                        RtsSectionTitle(
                          gspTambah
                              ? 'Toko yang Diusulkan Menjadi GSP'
                              : 'Toko GSP yang Diajukan Dihapus',
                        ),
                        const SizedBox(height: 11),
                        _buildKotakPilihToko(),
                        if (adaCustomer) ...[
                          const SizedBox(height: 14),
                          _buildInfoTerkunci(customer!),
                        ],
                        const SizedBox(height: 18),
                        RtsSectionTitle(
                          gspTambah ? 'Data GSP Baru' : 'Data GSP',
                        ),
                        const SizedBox(height: 11),
                        _buildKartuGsp(),
                      ] else ...[
                        const RtsSectionTitle('Jenis Pengajuan'),
                        const SizedBox(height: 11),
                        _buildJenisCard(),
                        const SizedBox(height: 18),
                        const RtsSectionTitle('Data Toko'),
                        const SizedBox(height: 11),
                        _buildDataCard(),
                        if (adaCustomer) ...[
                          const SizedBox(height: 18),
                          const RtsSectionTitle('Perubahan yang Diajukan'),
                          const SizedBox(height: 11),
                          _buildPerubahanCard(),
                        ],
                      ],
                      const SizedBox(height: 18),
                      const RtsSectionTitle('Keterangan'),
                      const SizedBox(height: 11),
                      _buildKeteranganCard(),
                      const SizedBox(height: 18),
                      const RtsIklanAsli(),
                      const SizedBox(height: 20),
                      _buildTombolKirim(),
                      if (RtsConfig.produksi) ...[
                        const SizedBox(height: 14),
                        _buildPeringatanProduksi(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Pengajuan Baru',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Dikirim ke ADMIN dan ASS untuk diperiksa',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRingkasanPengirim() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rtsMaroon, rtsMaroonDark],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(74, 14, 20, 0.25),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PENGIRIM',
            style: TextStyle(
              color: Color(0xccffffff),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 9),
          Text(
            widget.user.displayName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${widget.user.salesman.isEmpty ? "-" : widget.user.salesman}'
            ' • ${widget.user.salesDistrict.isEmpty ? "-" : widget.user.salesDistrict}',
            style: const TextStyle(color: Color(0xb3ffffff), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _buildJenisCard() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final String item in rtsJenisPengajuan)
                _pilihanBulat(
                  label: item,
                  terpilih: jenis == item,
                  onTap: () => _pilihJenis(item),
                ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Pilih Ganti Nama, Ganti Alamat, atau Hapus Toko untuk mengubah '
            'toko yang sudah ada. Pilih Tambah Baru untuk mendaftarkan toko baru.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pilihanBulat({
    required String label,
    required bool terpilih,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: terpilih ? rtsMaroon : Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: terpilih ? rtsMaroon : rtsCardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: terpilih ? Colors.white : rtsTextSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  /* --------------------------------------------------------------- data toko */

  Widget _buildDataCard() {
    final Customer? data = customer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildKotakPilihToko(),
        const SizedBox(height: 14),
        if (data == null) _buildDataTambahBaru() else _buildInfoTerkunci(data),
      ],
    );
  }

  /// Kolom "Nama Toko" yang dibuka sebagai daftar pilihan customer.
  /// Selalu ditampilkan, baik dibuka dari Master Customer maupun dari tombol
  /// melayang, sehingga sales dapat memilih toko pada kedua jalan tersebut.
  Widget _buildKotakPilihToko() {
    final Customer? data = customer;

    if (data == null) {
      return RtsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _pilihCustomer,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                decoration: BoxDecoration(
                  color: const Color(0xfff8f4ef),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: rtsMaroon, width: 1.4),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      size: 20,
                      color: Color(0xff6d514a),
                    ),
                    const SizedBox(width: 11),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Nama Toko',
                            style: TextStyle(
                              color: rtsMaroon,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.4,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Ketuk untuk memilih toko',
                            style: TextStyle(
                              color: rtsTextSecondary,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.expand_more_rounded,
                      color: rtsMaroon,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            const Text(
              'Ketuk kolom di atas untuk mencari toko yang sudah ada. Bila yang '
              'diajukan adalah toko baru, biarkan kosong dan isi data di bawah.',
              style: TextStyle(
                color: rtsTextSecondary,
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
    }

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _pilihCustomer,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xfff8f4ef),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: rtsMaroon, width: 1.4),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.storefront_outlined,
                    size: 20,
                    color: Color(0xff6d514a),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nama Toko',
                          style: TextStyle(
                            color: rtsMaroon,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          data.namaToko.isEmpty ? '-' : data.namaToko,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          data.idCustomer.isEmpty ? '-' : data.idCustomer,
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    children: [
                      const Icon(
                        Icons.expand_more_rounded,
                        color: rtsMaroon,
                        size: 22,
                      ),
                      Text(
                        'Ganti',
                        style: TextStyle(
                          color: rtsMaroon.withValues(alpha: 0.85),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: rtsTextSecondary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              onPressed: _kosongkanCustomer,
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text(
                'Kosongkan (ajukan toko baru)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const Text(
            'Seluruh keterangan di bawah terisi otomatis dari database.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// Data toko yang terkunci, berasal dari database.
  Widget _buildInfoTerkunci(Customer data) {
    return RtsCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: rtsTextSecondary,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'Terisi otomatis dari database dan terkunci',
                  style: TextStyle(
                    color: rtsTextSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              RtsBadge(
                data.isGsp ? 'GSP' : 'REGULER',
                background: data.isGsp
                    ? const Color(0xfffdf3e0)
                    : const Color(0xffeef1f4),
                foreground: data.isGsp ? rtsAmber : const Color(0xff5c6b7a),
              ),
            ],
          ),
          const SizedBox(height: 4),
          RtsInfoRow('ID Customer', data.idCustomer),
          const RtsDivider(),
          RtsInfoRow('Alamat saat ini', data.alamat),
          const RtsDivider(),
          RtsInfoRow('Hari Kunjungan', _hariRapi(data.hari)),
          const RtsDivider(),
          RtsInfoRow(
            'Frekuensi Kunjungan',
            data.kunjungan.trim().isEmpty ? '-' : data.kunjungan,
          ),
          const RtsDivider(),
          RtsInfoRow('Salesman', data.salesman),
          const RtsDivider(),
          RtsInfoRow('District', data.salesDistrict),
          const RtsDivider(),
          RtsInfoRow(
            'Status',
            data.statusAktif,
            valueColor: data.isAktif ? rtsGreen : const Color(0xffa52020),
          ),
          if (data.punyaKoordinat) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: rtsMaroon,
                  side: const BorderSide(color: rtsMaroon, width: 1.3),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => _bukaLokasiToko(data),
                icon: const Icon(Icons.map_outlined, size: 18),
                label: const Text(
                  'LIHAT TITIK TOKO DI GOOGLE MAPS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Future<void> _bukaLokasiToko(Customer data) async {
    final Uri googleMaps = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query='
      '${data.latitude.trim()},${data.longitude.trim()}',
    );

    try {
      final bool dibuka =
          await launchUrl(googleMaps, mode: LaunchMode.externalApplication);
      if (dibuka) return;
    } catch (_) {
      // lanjut ke pesan
    }

    if (mounted) {
      rtsShowMessage(
        context,
        'Aplikasi peta tidak dapat dibuka. Pastikan Google Maps terpasang.',
      );
    }
  }

  /// Form untuk pengajuan Toko Baru, seluruhnya diisi manual.
  Widget _buildDataTambahBaru() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildField(
            controller: namaBaruController,
            label: 'Nama Toko Baru',
            hint: 'Contoh: TOKO SUMBER REJEKI',
            icon: Icons.storefront_outlined,
          ),
          const SizedBox(height: 12),
          _buildField(
            controller: alamatBaruController,
            label: 'Alamat',
            hint: 'Alamat lengkap toko',
            icon: Icons.home_outlined,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          const Text(
            'Kategori',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final String item in <String>['REGULER', 'GSP'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => tipeBaru = item),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: tipeBaru == item
                            ? (item == 'GSP' ? rtsAmber : rtsMaroon)
                            : Colors.white.withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: tipeBaru == item
                              ? (item == 'GSP' ? rtsAmber : rtsMaroon)
                              : rtsCardBorder,
                        ),
                      ),
                      child: Text(
                        item,
                        style: TextStyle(
                          color: tipeBaru == item
                              ? Colors.white
                              : rtsTextSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /* ---------------------------------------------------------- perubahan data */

  Widget _buildPerubahanCard() {
    final Customer data = customer!;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (jenis == 'Ganti Nama')
            _buildField(
              controller: namaBaruController,
              label: 'Nama Toko Baru',
              hint: 'Nama pengganti',
              icon: Icons.edit_outlined,
              catatan: 'Nama sekarang: ${data.namaToko}',
            ),
          if (jenis == 'Ganti Alamat') ...[
            _buildField(
              controller: alamatBaruController,
              label: 'Alamat Baru',
              hint: 'Alamat pengganti',
              icon: Icons.location_on_outlined,
              maxLines: 2,
              readOnly: pakaiKoordinat,
              suffix: pakaiKoordinat
                  ? null
                  : IconButton(
                      tooltip: 'Isi alamat dari titik lokasi sekarang',
                      onPressed: sedangCariLokasi
                          ? null
                          : () => _ubahPakaiKoordinat(true),
                      icon: const Icon(
                        Icons.my_location_rounded,
                        color: rtsMaroon,
                        size: 21,
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            _buildCentangKoordinat(),
            const SizedBox(height: 12),
            _buildPanelLokasi(),
          ],
          if (jenis == 'Hapus Toko')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffdeaea),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xfff0c9c9)),
              ),
              child: const Text(
                'Setelah disetujui, customer ini akan diarsipkan ke '
                'master_toko_deleted lalu dihapus dari Master Customer.',
                style: TextStyle(
                  color: Color(0xff8a1b1b),
                  fontSize: 11.5,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCentangKoordinat() {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: pakaiKoordinat ? rtsMaroon : rtsCardBorder),
      ),
      child: Row(
        children: [
          SizedBox(
            height: 40,
            width: 40,
            child: Checkbox(
              value: pakaiKoordinat,
              activeColor: rtsMaroon,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: sedangCariLokasi
                  ? null
                  : (bool? nilai) => _ubahPakaiKoordinat(nilai ?? false),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: sedangCariLokasi
                  ? null
                  : () => _ubahPakaiKoordinat(!pakaiKoordinat),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sesuai koordinat sekarang',
                    style: TextStyle(
                      color: rtsTextPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pakaiKoordinat
                        ? 'Alamat diisi otomatis dari titik tempat Anda berdiri.'
                        : 'Centang bila Anda tidak mengetahui alamat toko.',
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 11.5,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelLokasi() {
    final RtsAkurasi info = rtsAkurasiInfo(akurasiMeter);
    final double? lat = lintang;
    final double? lng = bujur;
    final double? akurasi = akurasiMeter;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: info.latar,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: info.garis),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (sedangCariLokasi)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: rtsMaroon,
                  ),
                )
              else
                Icon(info.ikon, size: 18, color: info.warna),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sedangCariLokasi ? 'Membaca titik lokasi...' : info.label,
                      style: TextStyle(
                        color: sedangCariLokasi ? rtsMaroon : info.warna,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      info.catatan,
                      style: TextStyle(
                        color: info.warna,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              if (akurasi != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: info.garis),
                  ),
                  child: Text(
                    '\u00b1 ${akurasi.toStringAsFixed(0)} m',
                    style: TextStyle(
                      color: info.warna,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          if (pesanLokasi.isNotEmpty) ...[
            const SizedBox(height: 9),
            Text(
              pesanLokasi,
              style: const TextStyle(
                color: Color(0xffa52020),
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (lat != null && lng != null) ...[
            const SizedBox(height: 10),
            Text(
              'Titik: ${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
              style: const TextStyle(
                color: rtsTextPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: rtsMaroon,
                        backgroundColor: Colors.white.withValues(alpha: 0.9),
                        side: const BorderSide(color: rtsMaroon, width: 1.2),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: sedangCariLokasi ? null : _ambilLokasi,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text(
                        'PERBARUI TITIK',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: rtsMaroon,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      onPressed: _bukaTitikDiMaps,
                      icon: const Icon(Icons.map_rounded, size: 17),
                      label: const Text(
                        'CEK DI MAPS',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 9),
          const Text(
            'Alamat pada kolom di atas terisi dari titik GPS tempat Anda '
            'berdiri. Titiknya tidak ikut dituliskan pada alamat.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------- keterangan */

  /// Kartu isian khusus GSP: PIC, nomor HP, alamat, titik lokasi, dan foto.
  Widget _buildKartuGsp() {
    final Customer? data = customer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RtsCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                gspTambah
                    ? 'Isi data GSP baru (toko pengganti). Foto KTP, foto luar '
                        'toko, dan foto dalam toko wajib dilampirkan.'
                    : 'Toko GSP ini akan diusulkan kembali menjadi toko '
                        'REGULER. Foto tidak diperlukan.',
                style: const TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
              if (data != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Toko: ${data.namaToko} - ${data.idCustomer}',
                  style: const TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 13),
              _buildField(
                controller: picController,
                label: 'Nama PIC',
                hint: 'Penanggung jawab toko',
                icon: Icons.person_outline_rounded,
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: nomorHpController,
                label: 'Nomor HP PIC',
                hint: '08xxxxxxxxxx',
                icon: Icons.phone_outlined,
                maxLines: 1,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildField(
                controller: alamatBaruController,
                label: 'Alamat Lengkap',
                hint: 'Jalan, nomor, kelurahan',
                icon: Icons.location_on_outlined,
                maxLines: 2,
                readOnly: pakaiKoordinat,
                suffix: pakaiKoordinat
                    ? null
                    : IconButton(
                        tooltip: 'Isi alamat dari titik lokasi sekarang',
                        onPressed: sedangCariLokasi
                            ? null
                            : () => _ubahPakaiKoordinat(true),
                        icon: const Icon(
                          Icons.my_location_rounded,
                          color: rtsMaroon,
                          size: 21,
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              _buildCentangKoordinat(),
              const SizedBox(height: 12),
              _buildPanelLokasi(),
            ],
          ),
        ),
        if (gspTambah) ...[
          const SizedBox(height: 16),
          const RtsSectionTitle('Foto GSP'),
          const SizedBox(height: 11),
          RtsCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ketiga foto wajib diisi sebelum pengajuan dapat dikirim.',
                  style: TextStyle(
                    color: rtsTextSecondary,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                _barisFotoGsp(label: 'Foto KTP', kunci: 'ktp', berkas: fotoKtp),
                _barisFotoGsp(
                  label: 'Foto Luar Toko',
                  kunci: 'luar',
                  berkas: fotoLuar,
                ),
                _barisFotoGsp(
                  label: 'Foto Dalam Toko',
                  kunci: 'dalam',
                  berkas: fotoDalam,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Satu baris lampiran foto GSP.
  Widget _barisFotoGsp({
    required String label,
    required String kunci,
    required XFile? berkas,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.97),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: berkas == null ? rtsCardBorder : rtsGreen,
            width: berkas == null ? 1 : 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: const Color(0xfff8f4ef),
                borderRadius: BorderRadius.circular(12),
              ),
              child: berkas == null
                  ? const Icon(
                      Icons.photo_camera_outlined,
                      color: rtsTextSecondary,
                      size: 22,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(berkas.path),
                        fit: BoxFit.cover,
                        width: 46,
                        height: 46,
                      ),
                    ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: rtsTextPrimary,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    berkas == null
                        ? 'Belum ada foto'
                        : 'Foto siap dikirim',
                    style: TextStyle(
                      color: berkas == null ? rtsTextSecondary : rtsGreen,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: menyimpan
                  ? null
                  : () => unawaited(_ambilFotoGsp(kunci, label)),
              child: Text(
                berkas == null ? 'AMBIL' : 'GANTI',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Mengambil satu foto GSP dari kamera atau galeri.
  Future<void> _ambilFotoGsp(String kunci, String label) async {
    final String? pilihan = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                label.toUpperCase(),
                style: const TextStyle(
                  color: rtsTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: rtsMaroon),
              title: const Text('Ambil dari Kamera'),
              onTap: () => Navigator.of(sheetContext).pop('kamera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: rtsMaroon),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.of(sheetContext).pop('galeri'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (pilihan == null) return;

    try {
      final XFile? berkas = await pemilihFoto.pickImage(
        source: pilihan == 'kamera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );

      if (berkas == null || !mounted) return;

      setState(() {
        if (kunci == 'ktp') {
          fotoKtp = berkas;
        } else if (kunci == 'luar') {
          fotoLuar = berkas;
        } else {
          fotoDalam = berkas;
        }
      });
    } catch (_) {
      if (!mounted) return;

      rtsShowMessage(
        context,
        'Tidak dapat membuka kamera/galeri. Periksa izin aplikasi pada '
        'Pengaturan HP.',
      );
    }
  }

  Widget _buildKeteranganCard() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildField(
            controller: picController,
            label: 'PIC di Toko',
            hint: 'Nama penanggung jawab di toko',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: 16),
          _buildKolomKeterangan(
            judul: 'Hari Kunjungan',
            nilai: hariKunjungan,
            bolehDikunci: adaCustomer,
            terbuka: bukaHari,
            onBuka: (bool nilai) => setState(() => bukaHari = nilai),
            anak: _dropdownPilihan(
              nilai: hariKunjungan,
              pilihan: rtsHariKunjungan,
              onPilih: (String nilai) => setState(() => hariKunjungan = nilai),
            ),
          ),
          const SizedBox(height: 14),
          _buildKolomKeterangan(
            judul: 'Frekuensi Kunjungan',
            nilai: frekuensi,
            bolehDikunci: adaCustomer,
            terbuka: bukaFrekuensi,
            onBuka: (bool nilai) => setState(() => bukaFrekuensi = nilai),
            anak: _dropdownPilihan(
              nilai: frekuensi,
              pilihan: rtsFrekuensiKunjungan,
              onPilih: (String nilai) => setState(() => frekuensi = nilai),
            ),
          ),
          const SizedBox(height: 16),
          _buildField(
            controller: alasanController,
            label: 'Alasan Pengajuan',
            hint: 'Contoh: pemilik berganti, toko tutup, dsb',
            icon: Icons.notes_outlined,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  /// Daftar pilihan berbentuk dropdown.
  /// Nilai dari database yang belum ada pada daftar tetap ditampilkan.
  Widget _dropdownPilihan({
    required String nilai,
    required List<String> pilihan,
    required ValueChanged<String> onPilih,
  }) {
    final String bersih = nilai.trim();
    final List<String> daftar = <String>[
      ...pilihan,
      if (bersih.isNotEmpty && !pilihan.contains(bersih)) bersih,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: rtsCardBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: bersih.isEmpty ? daftar.first : bersih,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.expand_more_rounded, color: rtsMaroon),
          style: const TextStyle(
            color: rtsTextPrimary,
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
          ),
          items: <DropdownMenuItem<String>>[
            for (final String item in daftar)
              DropdownMenuItem<String>(value: item, child: Text(item)),
          ],
          onChanged: (String? baru) {
            if (baru != null) onPilih(baru);
          },
        ),
      ),
    );
  }

  /// Kolom keterangan yang berasal dari database.
  /// Terkunci sampai pengguna mencentang kotak "Ubah".
  Widget _buildKolomKeterangan({
    required String judul,
    required String nilai,
    required bool bolehDikunci,
    required bool terbuka,
    required ValueChanged<bool> onBuka,
    required Widget anak,
  }) {
    final bool terkunci = bolehDikunci && !terbuka;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 6, 12, 10),
      decoration: BoxDecoration(
        color: terkunci ? const Color(0xfff1ece7) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: terkunci ? rtsCardBorder : rtsMaroon),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (bolehDikunci)
                SizedBox(
                  height: 40,
                  width: 40,
                  child: Checkbox(
                    value: terbuka,
                    activeColor: rtsMaroon,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (bool? nilaiBaru) => onBuka(nilaiBaru ?? false),
                  ),
                )
              else
                const SizedBox(width: 12),
              Expanded(
                child: Text(
                  judul,
                  style: const TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (bolehDikunci)
                Text(
                  terbuka ? 'diubah' : 'terkunci',
                  style: TextStyle(
                    color: terbuka ? rtsMaroon : rtsTextSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          if (terkunci)
            Padding(
              padding: const EdgeInsets.fromLTRB(40, 2, 4, 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    size: 15,
                    color: rtsTextSecondary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      nilai,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!terkunci)
            Padding(
              padding: EdgeInsets.fromLTRB(bolehDikunci ? 40 : 8, 6, 4, 0),
              child: anak,
            ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------------ kirim */

  Widget _buildTombolKirim() {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: rtsMaroon,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: menyimpan ? null : _kirim,
        icon: menyimpan
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.send_rounded, size: 19),
        label: Text(
          menyimpan ? 'MENGIRIM...' : 'KIRIM PENGAJUAN',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildPeringatanProduksi() {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xfffdeaea),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xfff0c9c9)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xffa52020)),
          SizedBox(width: 9),
          Expanded(
            child: Text(
              'Anda memakai SERVER PRODUKSI. Pengajuan ini akan masuk ke '
              'daftar pemeriksaan data asli dan diproses oleh ADMIN atau ASS.',
              style: TextStyle(
                color: Color(0xff8a1b1b),
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    int maxLines = 1,
    bool readOnly = false,
    TextInputType? keyboardType,
    Widget? suffix,
    String? catatan,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLines: maxLines,
          readOnly: readOnly,
          keyboardType: keyboardType,
          style: TextStyle(
            fontSize: 14.5,
            color: readOnly ? rtsTextSecondary : rtsTextPrimary,
          ),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, color: const Color(0xff6d514a), size: 20),
            suffixIcon: suffix,
            alignLabelWithHint: maxLines > 1,
            filled: true,
            fillColor:
                readOnly ? const Color(0xfff1ece7) : const Color(0xfff8f4ef),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            labelStyle: const TextStyle(fontSize: 13.5),
            hintStyle:
                const TextStyle(fontSize: 13, color: Color(0xffa99d94)),
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
              borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
            ),
          ),
        ),
        if (catatan != null) ...[
          const SizedBox(height: 6),
          Text(
            catatan,
            style: const TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* DAFTAR PILIHAN TOKO                                                        */
/* ------------------------------------------------------------------------- */

/// Lembar pencarian toko. Mengembalikan customer yang dipilih, atau null.
class _CustomerPickerSheet extends StatefulWidget {
  const _CustomerPickerSheet({
    required this.api,
    this.tipe = '',
    this.judul = 'Pilih Toko',
  });

  final ApiClient api;

  /// Penyaring tipe customer: REGULER | GSP. Kosong berarti semua.
  final String tipe;

  /// Judul lembar pemilih toko.
  final String judul;

  @override
  State<_CustomerPickerSheet> createState() => _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends State<_CustomerPickerSheet> {
  final TextEditingController cariController = TextEditingController();
  final ScrollController gulirController = ScrollController();

  Timer? penunda;
  List<Customer> hasil = <Customer>[];
  bool memuat = true;
  String? pesan;

  @override
  void initState() {
    super.initState();
    _cari('', langsung: true);
  }

  @override
  void dispose() {
    penunda?.cancel();
    cariController.dispose();
    gulirController.dispose();
    super.dispose();
  }

  void _ketik(String nilai) {
    penunda?.cancel();
    penunda = Timer(const Duration(milliseconds: 450), () => _cari(nilai));
  }

  Future<void> _cari(String kataKunci, {bool langsung = false}) async {
    if (!langsung) setState(() => memuat = true);

    try {
      final Map<String, dynamic> data = await widget.api.get('customers.php', {
        'q': kataKunci.trim(),
        'page': '1',
        'limit': '30',
        if (widget.tipe.isNotEmpty) 'tipe': widget.tipe,
      });

      if (!mounted) return;

      final CustomerPage halaman = CustomerPage.fromJson(data);

      setState(() {
        hasil = halaman.items;
        memuat = false;
        pesan = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        memuat = false;
        pesan = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        memuat = false;
        pesan = 'Gagal memuat daftar toko.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.86,
        decoration: const BoxDecoration(
          color: rtsSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xffd9d0c8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Icon(Icons.storefront_outlined,
                      color: rtsMaroon, size: 21),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.judul,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          widget.tipe.isEmpty
                              ? 'Cari berdasarkan nama toko, ID customer, atau salesman'
                              : 'Hanya menampilkan tipe ${widget.tipe} - cari nama toko atau ID customer',
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.lock_outline_rounded,
                      color: rtsTextSecondary, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: cariController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _ketik,
                onSubmitted: (String nilai) => _cari(nilai),
                style: const TextStyle(fontSize: 14.5),
                decoration: InputDecoration(
                  hintText: 'Ketik nama toko atau ID customer',
                  hintStyle: const TextStyle(fontSize: 13.5),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xff6d514a),
                    size: 21,
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => _cari(cariController.text),
                    icon: const Icon(Icons.tune_rounded, size: 20),
                    color: rtsMaroon,
                    tooltip: 'Cari',
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsCardBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: const BorderSide(color: rtsMaroon, width: 1.4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(child: _buildDaftar()),
          ],
        ),
      ),
    );
  }

  Widget _buildDaftar() {
    if (memuat) {
      return const Center(child: CircularProgressIndicator(color: rtsMaroon));
    }

    if (pesan != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 40, color: rtsTextSecondary),
              const SizedBox(height: 12),
              Text(
                pesan!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsTextPrimary, fontSize: 13.5),
              ),
              const SizedBox(height: 14),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
                onPressed: () => _cari(cariController.text),
                child: const Text('COBA LAGI'),
              ),
            ],
          ),
        ),
      );
    }

    if (hasil.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 40, color: rtsTextSecondary),
              SizedBox(height: 12),
              Text(
                'Toko tidak ditemukan. Coba kata kunci lain.',
                textAlign: TextAlign.center,
                style: TextStyle(color: rtsTextPrimary, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      controller: gulirController,
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 24),
      itemCount: hasil.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final Customer data = hasil[index];

        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () => Navigator.of(context).pop(data),
            child: Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: rtsCardBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: data.isGsp
                          ? const Color(0xfffdf3e0)
                          : const Color(0xffeef3fb),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      data.isGsp
                          ? Icons.local_gas_station_outlined
                          : Icons.storefront_outlined,
                      size: 19,
                      color: data.isGsp ? rtsAmber : const Color(0xff2b5f9e),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.namaToko.isEmpty ? '-' : data.namaToko,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${data.idCustomer} • ${data.salesDistrict}',
                          style: const TextStyle(
                            color: rtsTextSecondary,
                            fontSize: 11.5,
                          ),
                        ),
                        if (data.alamat.trim().isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            data.alamat,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xffa99d94),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xffb8aea6),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/* ------------------------------------------------------------------------- */
/* IKLAN (GOOGLE ADMOB)                                                       */
/* ------------------------------------------------------------------------- */

/// Pengaturan iklan AdMob RTS Panel.
///
/// KEADAAN SEKARANG (30 September 2026) - SELURUH KODE SUDAH TERPASANG:
///   - Kode aplikasi AdMob  : ca-app-pub-1905352530630884~8932651962
///                            (ditulis ke AndroidManifest oleh skrip)
///   - Iklan Banner beranda : ca-app-pub-1905352530630884/6675189094
///                            nama unit pada AdMob: "BANNER RTS"
///   - Iklan Native menu    : ca-app-pub-1905352530630884/9404285058
///                            nama unit pada AdMob: "RTS Panel Native"
///
/// Catatan: unit iklan baru biasanya perlu beberapa saat (paling lama satu
/// jam) sebelum mulai menampilkan iklan. Selama menunggu, kotak iklan tidak
/// muncul dan aplikasi tetap berjalan normal.
///
/// ATURAN IKLAN (pilihan b - sudah diterapkan):
///   Akun GRATIS : iklan tampil pada beranda dan keenam menu
///   Akun PRO    : iklan tidak tampil sama sekali
///   Saklar utama: ubah saklarIklan menjadi false untuk mematikan semua iklan
///                 tanpa memandang tingkat akun.
class RtsIklan {
  const RtsIklan._();

  /// Kode aplikasi AdMob (akun ca-app-pub-1905352530630884).
  /// Nilai ini dipasang pada android/app/src/main/AndroidManifest.xml oleh
  /// skrip PASANG_FITUR_BARU.ps1, bukan di berkas ini.
  static const String kodeAplikasi = 'ca-app-pub-1905352530630884~8932651962';

  /// Kode unit iklan BANNER milik Bapak (sudah diisi).
  static const String bannerIklan = 'ca-app-pub-1905352530630884/6675189094';

  /// Kode unit iklan NATIVE milik Bapak (sudah diisi).
  ///
  /// Nama unit pada AdMob : "RTS Panel Native"
  /// Format pada AdMob    : Native advanced
  /// Dipakai pada         : keenam menu (Master Customer, Pengajuan,
  ///                        Notifikasi, Sinkronisasi, Profil, Pengaturan)
  static const String nativeIklan = 'ca-app-pub-1905352530630884/9404285058';

  /// Kode unit iklan APP OPEN - iklan yang tampil sekilas saat aplikasi
  /// dibuka (layar pembuka).
  ///
  /// Nama unit pada AdMob : "RTS Panel Buka Aplikasi"
  /// Format pada AdMob    : App open
  /// Dipakai pada         : saat aplikasi dibuka, hanya untuk akun GRATIS
  static const String appOpenIklan = 'ca-app-pub-1905352530630884/8277624384';

  /// Saklar utama. Setel false bila ingin mematikan SELURUH iklan aplikasi,
  /// tanpa memandang tingkat akun.
  static const bool saklarIklan = true;

  /// Iklan hanya dipakai untuk akun GRATIS.
  ///
  /// Akun PRO (berlangganan) bebas iklan, sesuai pilihan Bapak. Tingkat akun
  /// dibaca dari RtsTingkatAkun, yang bersumber dari kolom `akun_pro` pada
  /// tabel sales_users di server.
  static bool get aktif => saklarIklan && !RtsTingkatAkun.pro;

  /// True bila iklan dimatikan karena akun ini PRO.
  static bool get bebasIklan => !RtsTingkatAkun.pro;

  static bool _siap = false;
  static Future<void>? _proses;

  static bool get siap => aktif && _siap;

  /// Menyiapkan mesin iklan. Aman dipanggil berkali-kali; hanya dijalankan
  /// sekali. Kegagalan diabaikan supaya aplikasi tetap dapat dipakai.
  static Future<void> siapkan() {
    if (!aktif) return Future<void>.value();
    if (_siap) return Future<void>.value();
    _proses ??= _mulai();
    return _proses!;
  }

  static Future<void> _mulai() async {
    try {
      await MobileAds.instance.initialize();
      _siap = true;
    } catch (_) {
      _siap = false;
    }
  }
}

/// Iklan banner pada beranda (di bawah kotak akun).
class RtsBannerIklan extends StatefulWidget {
  const RtsBannerIklan({super.key});

  @override
  State<RtsBannerIklan> createState() => _RtsBannerIklanState();
}

class _RtsBannerIklanState extends State<RtsBannerIklan> {
  BannerAd? iklan;
  bool tampil = false;
  bool sudahDiminta = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!sudahDiminta) {
      sudahDiminta = true;
      _muat();
    }
  }

  @override
  void dispose() {
    iklan?.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await RtsIklan.siapkan();

    if (!mounted || !RtsIklan.siap) return;

    try {
      final double lebar = MediaQuery.sizeOf(context).width - 36;

      final AdSize? ukuran =
          await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
        lebar.round(),
      );

      if (!mounted || ukuran == null) return;

      final BannerAd banner = BannerAd(
        adUnitId: RtsIklan.bannerIklan,
        size: ukuran,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (Ad ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }

            setState(() {
              iklan = ad as BannerAd;
              tampil = true;
            });
          },
          onAdFailedToLoad: (Ad ad, LoadAdError galat) {
            ad.dispose();

            if (mounted) setState(() => tampil = false);
          },
        ),
      );

      await banner.load();
    } catch (_) {
      // Iklan tidak dapat dimuat: kotak iklan tidak ditampilkan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final BannerAd? banner = iklan;

    if (!tampil || banner == null) return const SizedBox.shrink();

    return Center(
      child: SizedBox(
        width: banner.size.width.toDouble(),
        height: banner.size.height.toDouble(),
        child: AdWidget(ad: banner),
      ),
    );
  }
}

/// Iklan bentuk asli (native) yang dipakai pada setiap menu.
///
/// Bentuk iklan ini mengikuti gaya tampilan aplikasi, sehingga tidak terlihat
/// seperti kotak iklan biasa. Bila iklan gagal dimuat (misalnya tidak ada
/// internet), kotak iklan tidak ditampilkan sama sekali.
class RtsIklanAsli extends StatefulWidget {
  const RtsIklanAsli({super.key, this.tinggiMinimal = 132});

  final double tinggiMinimal;

  @override
  State<RtsIklanAsli> createState() => _RtsIklanAsliState();
}

class _RtsIklanAsliState extends State<RtsIklanAsli> {
  NativeAd? iklan;
  bool tampil = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    iklan?.dispose();
    super.dispose();
  }

  Future<void> _muat() async {
    await RtsIklan.siapkan();

    if (!mounted || !RtsIklan.siap) return;

    try {
      final NativeAd asli = NativeAd(
        adUnitId: RtsIklan.nativeIklan,
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (Ad ad) {
            if (!mounted) {
              ad.dispose();
              return;
            }

            setState(() {
              iklan = ad as NativeAd;
              tampil = true;
            });
          },
          onAdFailedToLoad: (Ad ad, LoadAdError galat) {
            ad.dispose();

            if (mounted) setState(() => tampil = false);
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.small,
          mainBackgroundColor: Colors.white,
          cornerRadius: 16,
          callToActionTextStyle: NativeTemplateTextStyle(
            textColor: Colors.white,
            backgroundColor: rtsMaroon,
            size: 12,
          ),
          primaryTextStyle: NativeTemplateTextStyle(
            textColor: rtsTextPrimary,
            size: 13,
          ),
          secondaryTextStyle: NativeTemplateTextStyle(
            textColor: rtsTextSecondary,
            size: 11.5,
          ),
          tertiaryTextStyle: NativeTemplateTextStyle(
            textColor: rtsTextSecondary,
            size: 11.5,
          ),
        ),
      );

      await asli.load();
    } catch (_) {
      // Iklan gagal dimuat: tidak ada yang ditampilkan.
    }
  }

  @override
  Widget build(BuildContext context) {
    final NativeAd? asli = iklan;

    if (!tampil || asli == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: widget.tinggiMinimal,
          maxHeight: 420,
        ),
        child: AdWidget(ad: asli),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* LAPORAN CUACA HARI INI                                                     */
/* ------------------------------------------------------------------------- */

/// Cuaca hari ini pada lokasi petugas.
class RtsCuacaHari {
  const RtsCuacaHari({
    required this.suhu,
    required this.kode,
    required this.kota,
    required this.maks,
    required this.min,
    required this.hujan,
  });

  final double suhu;
  final int kode;
  final String kota;
  final double maks;
  final double min;
  final int hujan;

  /// Keterangan cuaca berdasarkan kode resmi WMO.
  String get keterangan {
    if (kode == 0) return 'Cerah';
    if (kode == 1) return 'Cerah Berawan';
    if (kode == 2) return 'Berawan';
    if (kode == 3) return 'Mendung';
    if (kode == 45 || kode == 48) return 'Berkabut';
    if (kode >= 51 && kode <= 57) return 'Gerimis';
    if (kode >= 61 && kode <= 67) return 'Hujan';
    if (kode >= 71 && kode <= 77) return 'Hujan Salju';
    if (kode >= 80 && kode <= 82) return 'Hujan Lebat';
    if (kode >= 85 && kode <= 86) return 'Hujan Salju';
    if (kode >= 95 && kode <= 99) return 'Badai Petir';
    return 'Berawan';
  }

  /// Gambar cuaca.
  IconData get ikon {
    if (kode == 0) return Icons.wb_sunny_rounded;
    if (kode == 1 || kode == 2) return Icons.wb_cloudy_rounded;
    if (kode == 3) return Icons.cloud_rounded;
    if (kode == 45 || kode == 48) return Icons.blur_on_rounded;
    if (kode >= 51 && kode <= 57) return Icons.grain_rounded;
    if (kode >= 61 && kode <= 67) return Icons.water_drop_rounded;
    if (kode >= 71 && kode <= 77) return Icons.ac_unit_rounded;
    if (kode >= 80 && kode <= 82) return Icons.grain_rounded;
    if (kode >= 95) return Icons.flash_on_rounded;
    return Icons.wb_cloudy_rounded;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'suhu': suhu,
        'kode': kode,
        'kota': kota,
        'maks': maks,
        'min': min,
        'hujan': hujan,
      };

  static RtsCuacaHari fromJson(Map<String, dynamic> json) {
    double angka(Object? nilai) =>
        double.tryParse((nilai ?? '0').toString()) ?? 0;

    return RtsCuacaHari(
      suhu: angka(json['suhu']),
      kode: int.tryParse((json['kode'] ?? '0').toString()) ?? 0,
      kota: (json['kota'] ?? '').toString(),
      maks: angka(json['maks']),
      min: angka(json['min']),
      hujan: int.tryParse((json['hujan'] ?? '0').toString()) ?? 0,
    );
  }
}

/// Mengambil laporan cuaca hari ini dari layanan Open-Meteo (tanpa kunci API)
/// berdasarkan titik lokasi petugas. Bila izin lokasi belum diberikan atau
/// titik lokasi tidak tersedia, laporan cuaca tidak ditampilkan.
class RtsCuaca {
  const RtsCuaca._();

  static const String _kunci = 'rts_cuaca_hari';
  static const Duration _masaBerlaku = Duration(minutes: 30);

  static RtsCuacaHari? data;
  static DateTime? diambilPada;
  static bool sedangMemuat = false;

  /// Keterangan keadaan cuaca, dipakai halaman Pengaturan untuk memeriksa
  /// bila laporan cuaca tidak muncul pada beranda.
  static String status = 'Belum diperiksa';

  /// True bila GPS/lokasi HP sedang tidak aktif atau izinnya belum diberikan.
  static bool perluIzinLokasi = false;

  // ---------------------------------------------------------------------
  // Keterangan pemeriksaan - dipakai kartu "Cuaca Beranda" pada Pengaturan
  // dan tombol "SALIN KETERANGAN" supaya hasilnya mudah dikirim kepada
  // pengembang tanpa perlu menebak-nebak.
  // ---------------------------------------------------------------------

  /// Keadaan izin lokasi menurut HP, contoh: "Diizinkan", "Ditolak".
  static String izinLokasi = 'Belum diperiksa';

  /// True bila layanan Lokasi (GPS) pada HP sedang aktif.
  static bool gpsAktif = false;

  /// Titik lokasi terakhir yang berhasil dibaca, contoh: "3.5952, 98.6722".
  static String titikTerakhir = '';

  /// Keterangan teknis dari kegagalan terakhir (bila ada).
  static String pesanTeknis = '';

  /// Waktu percobaan pengambilan laporan yang terakhir.
  static DateTime? dicobaPada;

  /// Jumlah laporan yang berhasil diambil sejak aplikasi dibuka.
  static int jumlahBerhasil = 0;

  static Future<RtsCuacaHari?> muat({bool paksa = false}) async {
    if (sedangMemuat) return data;

    if (!paksa && data != null) {
      final DateTime? waktu = diambilPada;

      if (waktu != null &&
          DateTime.now().difference(waktu) < _masaBerlaku) {
        return data;
      }
    }

    sedangMemuat = true;
    dicobaPada = DateTime.now();
    pesanTeknis = '';

    try {
      if (data == null) await _muatSimpanan();

      final Position? titik = await _titikLokasi();

      if (titik == null) {
        if (status == 'Belum diperiksa') {
          status = 'Titik lokasi tidak tersedia.';
        }

        if (pesanTeknis.isEmpty) {
          pesanTeknis = 'Titik lokasi tidak terbaca. Periksa izin Lokasi dan '
              'pastikan GPS HP aktif.';
        }

        sedangMemuat = false;
        return data;
      }

      titikTerakhir = '${titik.latitude.toStringAsFixed(4)}, '
          '${titik.longitude.toStringAsFixed(4)}';

      final Uri alamat = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': titik.latitude.toStringAsFixed(4),
        'longitude': titik.longitude.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code',
        'daily': 'temperature_2m_max,temperature_2m_min,'
            'precipitation_probability_max',
        'timezone': 'auto',
        'forecast_days': '1',
      });

      final http.Response balasan = await http
          .get(alamat)
          .timeout(const Duration(seconds: 9));

      if (balasan.statusCode != 200) {
        status = 'Layanan cuaca menjawab kode ${balasan.statusCode}.';
        pesanTeknis = 'Open-Meteo menjawab kode ${balasan.statusCode}.';
        sedangMemuat = false;
        return data;
      }

      final Map<String, dynamic> isi =
          (jsonDecode(balasan.body) as Map).cast<String, dynamic>();

      final Map<String, dynamic> sekarang =
          ((isi['current'] as Map?) ?? const {}).cast<String, dynamic>();

      final Map<String, dynamic> harian =
          ((isi['daily'] as Map?) ?? const {}).cast<String, dynamic>();

      double angkaDari(Map<String, dynamic> peta, String kunci) {
        final Object? nilai = peta[kunci];

        if (nilai is List) {
          if (nilai.isEmpty) return 0;
          return double.tryParse(nilai.first.toString()) ?? 0;
        }

        return double.tryParse((nilai ?? '0').toString()) ?? 0;
      }

      String kota = await _namaKota(titik);

      if (kota.isEmpty) kota = data?.kota ?? '';

      final RtsCuacaHari baru = RtsCuacaHari(
        suhu: angkaDari(sekarang, 'temperature_2m'),
        kode: angkaDari(sekarang, 'weather_code').round(),
        kota: kota,
        maks: angkaDari(harian, 'temperature_2m_max'),
        min: angkaDari(harian, 'temperature_2m_min'),
        hujan: angkaDari(harian, 'precipitation_probability_max').round(),
      );

      data = baru;
      diambilPada = DateTime.now();
      sedangMemuat = false;
      jumlahBerhasil++;
      pesanTeknis = '';
      status = 'Laporan cuaca siap - ditampilkan pada beranda '
          '(diperbarui ${RtsWaktu.jamMenit(DateTime.now())}).';
      await _simpan();

      return baru;
    } catch (galat) {
      status = 'Gagal menghubungi layanan cuaca.';
      pesanTeknis = galat.toString();
      sedangMemuat = false;
      return data;
    }
  }

  /// Titik lokasi petugas untuk laporan cuaca.
  ///
  /// Urutannya:
  ///   1. Bila izin lokasi belum diberikan, aplikasi MEMINTA izin (muncul
  ///      kotak "Izinkan RTS Panel mengakses lokasi" pada layar HP)
  ///   2. Bila izin sudah ada, dipakai titik terakhir yang tercatat - jauh
  ///      lebih cepat dan tidak menguras baterai
  ///   3. Bila titik terakhir belum ada, titik GPS dibaca saat itu
  ///
  /// Bila izin ditolak atau GPS HP dimatikan, keterangannya disimpan pada
  /// RtsCuaca.status supaya dapat diperiksa dari halaman Pengaturan.
  static Future<Position?> _titikLokasi() async {
    try {
      // GPS HP mati: tidak ada gunanya meminta izin.
      final bool layananAktif = await Geolocator.isLocationServiceEnabled();

      gpsAktif = layananAktif;

      if (!layananAktif) {
        perluIzinLokasi = true;
        status = 'Lokasi HP belum aktif. Nyalakan Lokasi pada HP.';

        final Position? terakhir = await Geolocator.getLastKnownPosition();

        if (terakhir != null) {
          perluIzinLokasi = false;
          status = 'Memakai titik lokasi terakhir (Lokasi HP belum aktif).';
        }

        return terakhir;
      }

      LocationPermission izin = await Geolocator.checkPermission();

      izinLokasi = izin == LocationPermission.whileInUse
          ? 'Diizinkan saat aplikasi digunakan'
          : (izin == LocationPermission.always
              ? 'Diizinkan selalu'
              : (izin == LocationPermission.denied
                  ? 'Belum diizinkan'
                  : 'Ditolak permanen'));

      // Izin belum pernah diminta: mintakan sekarang.
      if (izin == LocationPermission.denied) {
        izin = await Geolocator.requestPermission();

        izinLokasi = izin == LocationPermission.whileInUse
            ? 'Diizinkan saat aplikasi digunakan'
            : (izin == LocationPermission.always
                ? 'Diizinkan selalu'
                : (izin == LocationPermission.denied
                    ? 'Belum diizinkan'
                    : 'Ditolak permanen'));
      }

      if (izin == LocationPermission.deniedForever) {
        perluIzinLokasi = true;
        status = 'Izin lokasi diblokir. Buka Pengaturan HP - Aplikasi - '
            'RTS Panel - Izin - Lokasi, lalu pilih Izinkan.';

        return await Geolocator.getLastKnownPosition();
      }

      if (izin == LocationPermission.denied) {
        perluIzinLokasi = true;
        status = 'Izin lokasi belum diberikan, laporan cuaca belum dapat '
            'diambil.';

        return await Geolocator.getLastKnownPosition();
      }

      perluIzinLokasi = false;

      final Position? terakhir = await Geolocator.getLastKnownPosition();

      if (terakhir != null) {
        status = 'Memakai titik lokasi terakhir.';
        return terakhir;
      }

      status = 'Membaca titik GPS saat ini...';

      pesanTeknis = 'Membaca titik GPS. Bila lama, pindah ke tempat terbuka '
          '(di dalam ruangan GPS sering tidak mendapat titik).';

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (galat) {
      status = 'Titik lokasi tidak dapat dibaca.';
      pesanTeknis = galat.toString();
      perluIzinLokasi = true;

      return null;
    }
  }

  static Future<String> _namaKota(Position titik) async {
    try {
      final List<Placemark> daftar = await placemarkFromCoordinates(
        titik.latitude,
        titik.longitude,
      ).timeout(const Duration(seconds: 7));

      if (daftar.isEmpty) return '';

      final Placemark tempat = daftar.first;

      final String kota = (tempat.locality ?? '').trim();

      if (kota.isNotEmpty) return kota;

      final String wilayah =
          (tempat.subAdministrativeArea ?? tempat.administrativeArea ?? '')
              .trim();

      return wilayah;
    } catch (_) {
      return '';
    }
  }

  static Future<void> _simpan() async {
    final RtsCuacaHari? isi = data;

    if (isi == null) return;

    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kunci, jsonEncode(isi.toJson()));
      await prefs.setInt(
        '${_kunci}_waktu',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // penyimpanan gagal, cuaca tetap tampil untuk sesi ini
    }
  }

  static Future<void> _muatSimpanan() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? teks = prefs.getString(_kunci);

      if (teks == null || teks.isEmpty) return;

      data = RtsCuacaHari.fromJson(
        (jsonDecode(teks) as Map).cast<String, dynamic>(),
      );

      final int milidetik = prefs.getInt('${_kunci}_waktu') ?? 0;

      if (milidetik > 0) {
        diambilPada = DateTime.fromMillisecondsSinceEpoch(milidetik);
      }
    } catch (_) {
      // data simpanan rusak, diabaikan
    }
  }
}

/* ------------------------------------------------------------------------- */
/* PEMBARUAN APLIKASI OTOMATIS                                                */
/* ------------------------------------------------------------------------- */

/// Versi aplikasi yang sedang terpasang di HP.
class RtsVersi {
  const RtsVersi._();

  static String nama = '1.0.0';
  static int kode = 1;
  static bool siap = false;

  static String get label => '$nama ($kode)';

  static Future<void> muat() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();

      nama = info.version;
      kode = int.tryParse(info.buildNumber) ?? 1;
      siap = true;
    } catch (_) {
      // versi tidak terbaca, dipakai nilai bawaan
    }
  }
}

/// Keterangan versi terbaru yang dibaca dari server
/// (berkas apk/app_versi.json yang diatur lewat halaman app_versi.php).
class RtsInfoVersi {
  const RtsInfoVersi({
    required this.kode,
    required this.nama,
    required this.wajib,
    required this.catatan,
    required this.alamatApk,
    required this.ukuranMb,
    required this.tanggal,
  });

  final int kode;
  final String nama;
  final bool wajib;
  final String catatan;
  final String alamatApk;
  final double ukuranMb;
  final String tanggal;

  static RtsInfoVersi? fromJson(Map<String, dynamic> json) {
    final String alamat = (json['apk'] ?? '').toString().trim();

    if (alamat.isEmpty) return null;

    bool benar(Object? nilai) =>
        nilai == true || nilai == 1 || nilai.toString() == 'true' ||
        nilai.toString() == '1';

    return RtsInfoVersi(
      kode: int.tryParse((json['version_code'] ?? '0').toString()) ?? 0,
      nama: (json['version_name'] ?? '').toString(),
      wajib: benar(json['wajib']),
      catatan: (json['catatan'] ?? '').toString(),
      alamatApk: alamat,
      ukuranMb: double.tryParse((json['ukuran_mb'] ?? '0').toString()) ?? 0,
      tanggal: (json['dipublikasikan'] ?? '').toString(),
    );
  }
}

/// Pemeriksa versi aplikasi di server.
///
/// Cara kerja: setiap aplikasi dibuka, aplikasi membandingkan versinya dengan
/// berkas keterangan versi di server. Bila versi di server lebih baru, muncul
/// kotak pemberitahuan pembaruan beserta tombol unduh.
class RtsPembaruan {
  const RtsPembaruan._();

  static const String _kunciDiabaikan = 'rts_pembaruan_diabaikan';

  static RtsInfoVersi? terbaru;
  static bool sedangMemeriksa = false;
  static String? pesanGalat;

  /// Bernilai true bila server menjawab dengan benar bahwa belum ada versi
  /// aplikasi yang diumumkan. Keadaan ini BUKAN kegagalan: aplikasi memang
  /// sudah versi terbaru yang tersedia, jadi pesannya ditampilkan sebagai
  /// keterangan biasa (hijau), bukan sebagai galat (merah).
  static bool belumAdaVersi = false;

  static bool get adaPembaruan {
    final RtsInfoVersi? info = terbaru;
    if (info == null) return false;
    return info.kode > RtsVersi.kode;
  }

  /// Membaca keterangan versi dari server.
  static Future<RtsInfoVersi?> periksa() async {
    belumAdaVersi = false;

    // ---------------------------------------------------------------------
    // Sumber 1: halaman API (membaca tabel rts_app_versi pada database).
    // Dipakai lebih dahulu karena lebih andal - bila berkas JSON terhapus
    // atau tidak dapat ditulis, keterangan versi tetap terbaca dari database.
    // ---------------------------------------------------------------------
    String? sebabApi;

    try {
      final Uri alamatApi = Uri.parse('${RtsConfig.baseUrl}/app_versi.php');

      final http.Response balasanApi = await http
          .get(alamatApi, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));

      if (balasanApi.statusCode == 200) {
        final Object? isiMentah = jsonDecode(balasanApi.body);

        if (isiMentah is Map) {
          final Map<String, dynamic> isi = isiMentah.cast<String, dynamic>();
          final Object? bagian = isi['versi'];

          if (isi['success'] == true && bagian is Map) {
            final RtsInfoVersi? infoDariApi = RtsInfoVersi.fromJson(
              bagian.cast<String, dynamic>(),
            );

            if (infoDariApi != null) {
              terbaru = infoDariApi;
              pesanGalat = null;

              // Pengingat pembaruan pada layar HP ikut diperbarui: muncul bila
              // ada versi lebih baru, berhenti bila versi sudah terbaru.
              unawaited(RtsPengingatPembaruan.perbarui(infoDariApi));

              return infoDariApi;
            }

            sebabApi = 'Keterangan versi pada server belum lengkap.';
          } else {
            // Server menjawab dengan benar, hanya belum ada versi yang
            // diumumkan. Ini jawaban yang sah, bukan kegagalan koneksi.
            final String pesanServer =
                (isi['message'] ?? '').toString().trim();

            sebabApi = pesanServer.isEmpty
                ? 'Belum ada versi aplikasi yang diumumkan di server.'
                : pesanServer;

            belumAdaVersi = true;

            terbaru = null;
            pesanGalat = sebabApi;

            // Belum ada versi diumumkan: tidak ada pengingat yang perlu jalan.
            unawaited(RtsPengingatPembaruan.perbarui(null));

            return null;
          }
        } else {
          sebabApi = 'Balasan halaman API tidak dikenali.';
        }
      } else if (balasanApi.statusCode == 404) {
        sebabApi = 'Halaman api/app_versi.php belum ada di server.';
      } else {
        sebabApi = 'Halaman API menjawab kode ${balasanApi.statusCode}.';
      }
    } catch (_) {
      sebabApi = 'Halaman API tidak dapat dihubungi.';
    }

    // ---------------------------------------------------------------------
    // Sumber 2: berkas keterangan versi (apk/app_versi.json).
    // Dipakai bila halaman API belum ada atau tidak menjawab.
    // ---------------------------------------------------------------------
    try {
      final Uri alamat = Uri.parse(RtsConfig.urlVersi);

      final http.Response balasan = await http
          .get(alamat, headers: const {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));

      if (balasan.statusCode != 200) {
        pesanGalat = 'Berkas keterangan versi belum ada di server '
            '(kode ${balasan.statusCode}).';
        return null;
      }

      final Object? isiMentah = jsonDecode(balasan.body);

      if (isiMentah is! Map) {
        pesanGalat = 'Isi berkas keterangan versi tidak dikenali.';
        return null;
      }

      final RtsInfoVersi? info =
          RtsInfoVersi.fromJson(isiMentah.cast<String, dynamic>());

      if (info == null) {
        belumAdaVersi = true;
        terbaru = null;
        pesanGalat = 'Belum ada versi aplikasi yang diumumkan di server.';
        unawaited(RtsPengingatPembaruan.perbarui(null));
        return null;
      }

      terbaru = info;
      pesanGalat = null;

      unawaited(RtsPengingatPembaruan.perbarui(info));

      return info;
    } catch (_) {
      // sebabApi sudah pasti terisi pada jalur ini (semua jalur di atas
      // mengembalikan nilai atau mengisinya), tetapi pemeriksaan kosong tetap
      // dipakai supaya keterangannya selalu berguna bagi pengguna.
      final String sebab = (sebabApi ?? '').trim();

      pesanGalat = sebab.isEmpty ? 'Tidak dapat menghubungi server.' : sebab;

      return null;
    }
  }

  /// Pemeriksaan yang dijalankan sendiri saat aplikasi dibuka.
  /// Bila ada versi baru, kotak pembaruan ditampilkan.
  static Future<void> periksaOtomatis(BuildContext context) async {
    if (sedangMemeriksa) return;

    sedangMemeriksa = true;

    try {
      final RtsInfoVersi? info = await periksa();

      if (!context.mounted) return;

      if (info == null || info.kode <= RtsVersi.kode) return;

      if (!info.wajib) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();

        if (prefs.getInt(_kunciDiabaikan) == info.kode) return;
      }

      if (!context.mounted) return;

      await tampilkan(context, info);
    } finally {
      sedangMemeriksa = false;
    }
  }

  /// Pemeriksaan yang dijalankan saat tombol diperiksa ditekan petugas.
  static Future<void> periksaManual(BuildContext context) async {
    if (sedangMemeriksa) return;

    sedangMemeriksa = true;

    try {
      final RtsInfoVersi? info = await periksa();

      if (!context.mounted) return;

      if (info == null) {
        rtsShowMessage(
          context,
          pesanGalat ?? 'Tidak dapat memeriksa pembaruan.',
          success: belumAdaVersi,
        );
        return;
      }

      if (info.kode <= RtsVersi.kode) {
        rtsShowMessage(
          context,
          'Aplikasi sudah memakai versi terbaru (${RtsVersi.label}).',
          success: true,
        );
        return;
      }

      await tampilkan(context, info);
    } finally {
      sedangMemeriksa = false;
    }
  }

  /// Kotak pemberitahuan pembaruan.
  static Future<void> tampilkan(
    BuildContext context,
    RtsInfoVersi info,
  ) async {
    final bool wajib = info.wajib;

    final StringBuffer keterangan = StringBuffer();

    keterangan.writeln('Versi terpasang : ${RtsVersi.label}');
    keterangan.writeln('Versi terbaru   : ${info.nama} (${info.kode})');

    if (info.ukuranMb > 0) {
      keterangan.writeln('Ukuran berkas   : ${info.ukuranMb.toStringAsFixed(1)} MB');
    }

    if (info.tanggal.isNotEmpty) {
      keterangan.writeln('Dipublikasikan  : ${info.tanggal}');
    }

    if (info.catatan.isNotEmpty) {
      keterangan
        ..writeln()
        ..writeln('Catatan pembaruan:')
        ..writeln(info.catatan);
    }

    keterangan
      ..writeln()
      ..writeln(
        'Tekan PERBARUI SEKARANG - aplikasi mengunduh sendiri berkas '
        'pembaruannya, lalu layar Pasang terbuka otomatis. Tidak perlu '
        'membuka Chrome.',
      );

    final bool? lanjut = await showDialog<bool>(
      context: context,
      barrierDismissible: !wajib,
      builder: (dialogContext) => PopScope(
        canPop: !wajib,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.system_update_alt_rounded, color: rtsMaroon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  wajib ? 'Pembaruan Wajib' : 'Pembaruan Tersedia',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Text(
              keterangan.toString().trim(),
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: rtsTextPrimary,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                wajib ? 'TUTUP APLIKASI' : 'NANTI',
                style: const TextStyle(color: rtsTextSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('PERBARUI SEKARANG'),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted) return;

    if (lanjut != true) {
      if (!wajib) {
        try {
          final SharedPreferences prefs =
              await SharedPreferences.getInstance();

          await prefs.setInt(_kunciDiabaikan, info.kode);
        } catch (_) {
          // pengingat tidak dapat disimpan, kotak akan muncul lagi nanti
        }
      }

      return;
    }

    if (!context.mounted) return;

    await bukaUnduhan(context, info);
  }

  /// Mengunduh pembaruan dan memasangnya.
  ///
  /// Urutannya:
  ///   1. Dikerjakan DI DALAM APLIKASI (tanpa Chrome) lewat RtsPasangApk.
  ///   2. Bila HP/perangkat tidak mendukung, atau saluran Android belum
  ///      dipasang, barulah diunduh lewat peramban seperti cara lama.
  ///
  /// Jadi pembaruan selalu dapat dikerjakan, dalam keadaan apa pun.
  static Future<void> bukaUnduhan(
    BuildContext context,
    RtsInfoVersi info,
  ) async {
    final bool selesaiDiAplikasi = await RtsPasangApk.unduhDanPasang(
      context,
      info,
    );

    if (selesaiDiAplikasi) return;

    if (!context.mounted) return;

    await bukaPeramban(context, info);
  }

  /// Cara lama: membuka tautan unduhan pada peramban HP (Chrome).
  ///
  /// Dipakai sebagai cadangan bila pemasangan langsung di dalam aplikasi tidak
  /// dapat dikerjakan pada HP tersebut.
  static Future<void> bukaPeramban(
    BuildContext context,
    RtsInfoVersi info,
  ) async {
    final Uri alamat = Uri.parse(info.alamatApk);

    try {
      final bool bisa = await canLaunchUrl(alamat);

      if (!bisa) {
        if (context.mounted) {
          rtsShowMessage(context, 'Tidak dapat membuka tautan unduhan.');
        }
        return;
      }

      await launchUrl(alamat, mode: LaunchMode.externalApplication);

      if (context.mounted) {
        rtsShowMessage(
          context,
          'Berkas sedang diunduh pada peramban HP. Setelah selesai, buka '
          'berkas itu lalu pilih Pasang.',
          success: true,
        );
      }
    } catch (_) {
      if (context.mounted) {
        rtsShowMessage(context, 'Tidak dapat membuka tautan unduhan.');
      }
    }
  }
}


/* ------------------------------------------------------------------------- */
/* PEMBARUAN LANGSUNG DI DALAM APLIKASI (UNDUH + PASANG TANPA CHROME)         */
/* ------------------------------------------------------------------------- */

/// Mengunduh berkas pembaruan dan membuka layar Pasang Android LANGSUNG dari
/// dalam aplikasi - tanpa membuka Chrome.
///
/// Cara kerjanya:
///   1. Bagian Android (MainActivity.kt) meminta layanan DownloadManager milik
///      Android mengunduh berkas APK ke folder khusus aplikasi. Unduhan tetap
///      berjalan walaupun layar HP dimatikan, dan tidak meminta izin
///      penyimpanan.
///   2. Selagi mengunduh, aplikasi menampilkan besarnya kemajuan (persen).
///   3. Begitu unduhan selesai, layar "Pasang" Android dibuka sendiri.
///
/// Bila HP belum mengizinkan pemasangan dari aplikasi ini (Android 8 ke atas),
/// petugas diarahkan ke halaman pengaturan izin - cukup sekali untuk seterusnya.
///
/// AMAN GAGAL: bila berkas MainActivity.kt di proyek masih versi lama (saluran
/// ini belum ada), seluruh pemanggilan gagal dengan sendirinya dan aplikasi
/// memakai cara lama (membuka peramban). Jadi tidak ada yang rusak.
class RtsPasangApk {
  const RtsPasangApk._();

  /// Nama saluran yang sama dengan yang dipakai MainActivity.kt.
  static const MethodChannel _saluran = MethodChannel('rts/pembaruan');

  /// Menjadi true bila perangkat ini ternyata tidak mendukung cara baru.
  static bool tidakDidukung = false;

  static Map<String, dynamic> _peta(Object? jawab) {
    if (jawab is Map) {
      return jawab.map<String, dynamic>(
        (Object? kunci, Object? nilai) =>
            MapEntry<String, dynamic>(kunci.toString(), nilai),
      );
    }

    return <String, dynamic>{};
  }

  /// Meminta Android mengunduh berkas pembaruan.
  static Future<Map<String, dynamic>> _mintaUnduh(RtsInfoVersi info) async {
    try {
      final Object? jawab = await _saluran.invokeMethod<Object>(
        'pasang',
        <String, dynamic>{
          'url': info.alamatApk,
          'nama': 'rts_panel_update.apk',
        },
      );

      return _peta(jawab);
    } catch (_) {
      tidakDidukung = true;

      return <String, dynamic>{};
    }
  }

  /// Membaca kemajuan unduhan dari bagian Android.
  static Future<Map<String, dynamic>> status() async {
    try {
      final Object? jawab = await _saluran.invokeMethod<Object>('status');

      return _peta(jawab);
    } catch (_) {
      return <String, dynamic>{'status': 'GAGAL', 'pesan': 'Bagian Android tidak menjawab.'};
    }
  }

  /// Memeriksa apakah cara baru ini tersedia pada HP ini.
  static Future<bool> tersedia() async {
    if (tidakDidukung) return false;

    final Map<String, dynamic> jawab = await status();

    if (jawab.isEmpty) return false;

    return true;
  }

  /// Mengunduh berkas pembaruan lalu memasangnya.
  ///
  /// Mengembalikan true bila seluruhnya sudah ditangani di dalam aplikasi.
  /// Mengembalikan false bila pemanggil perlu memakai cara lama (peramban).
  static Future<bool> unduhDanPasang(
    BuildContext context,
    RtsInfoVersi info,
  ) async {
    if (tidakDidukung) return false;

    // ------------------------------------------------------------------
    // Diperiksa lebih dahulu: bila berkas pembaruan SUDAH pernah terunduh,
    // tidak perlu diunduh ulang - cukup diselesaikan pemasangannya.
    // ------------------------------------------------------------------
    final Map<String, dynamic> keadaanAwal = await status();
    final String awal = (keadaanAwal['status'] ?? '').toString();

    if (awal == 'IZIN_DIPERLUKAN') {
      return selesaikanIzin(context);
    }

    if (awal == 'SELESAI') {
      if (context.mounted) {
        rtsShowMessage(
          context,
          'Berkas pembaruan sudah terunduh dan siap dipasang. Bila layar '
          'Pasang belum terbuka, buka pemberitahuan "Pembaruan RTS Panel" '
          'pada layar HP.',
          success: true,
        );
      }

      return true;
    }

    Map<String, dynamic> jawab = await _mintaUnduh(info);

    if (jawab.isEmpty) return false;

    String keadaan = (jawab['status'] ?? '').toString();

    // ------------------------------------------------------------------
    // HP belum mengizinkan pemasangan dari aplikasi ini (Android 8+).
    // ------------------------------------------------------------------
    if (keadaan == 'IZIN_DIPERLUKAN') {
      return selesaikanIzin(context);
    }

    // ------------------------------------------------------------------
    // Unduhan tidak dapat dimulai -> pakai cara lama (peramban).
    // ------------------------------------------------------------------
    if (keadaan != 'DIMULAI' && keadaan != 'MENGUNDUH') {
      final String pesan = (jawab['pesan'] ?? '').toString();

      if (context.mounted && pesan.isNotEmpty) {
        rtsShowMessage(context, pesan);
      }

      return false;
    }

    if (!context.mounted) return true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _RtsKotakUnduhan(),
    );

    return true;
  }

  /// Meminta petugas menghidupkan izin "Instal aplikasi tidak dikenal".
  ///
  /// Dipakai pada dua keadaan:
  ///   1. berkas belum diunduh, tetapi Android sudah menolak pemasangan;
  ///   2. berkas SUDAH terunduh, tinggal menunggu izin pemasangan.
  ///
  /// Mengembalikan true bila sudah ditangani di dalam aplikasi, atau false
  /// bila petugas memilih cara lama (unduh lewat Chrome).
  static Future<bool> selesaikanIzin(BuildContext context) async {
    if (!context.mounted) return true;

    final String? pilihan = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.verified_user_rounded, color: rtsMaroon),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Satu Kali Pengaturan',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: const Text(
          'Supaya pembaruan dapat dipasang langsung dari aplikasi, Android '
          'perlu izin "Instal aplikasi tidak dikenal" untuk RTS Panel.\n\n'
          'Tekan BUKA PENGATURAN, hidupkan izin untuk RTS Panel, lalu tekan '
          'PERBARUI SEKARANG lagi. Cukup SEKALI saja - pembaruan berikutnya '
          'sudah berjalan sendiri.',
          style: TextStyle(fontSize: 12.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop('peramban'),
            child: const Text(
              'UNDUH LEWAT CHROME',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop('setelan'),
            child: const Text('BUKA PENGATURAN'),
          ),
        ],
      ),
    );

    if (pilihan == 'peramban') return false;

    if (pilihan != 'setelan') return true;

    try {
      await _saluran.invokeMethod<Object>('bukaIzin');
    } catch (_) {
      // pengaturan tidak dapat dibuka - pesan di bawah tetap ditampilkan
    }

    if (context.mounted) {
      rtsShowMessage(
        context,
        'Hidupkan izin untuk RTS Panel, lalu tekan PERBARUI SEKARANG lagi - '
        'berkasnya sudah terunduh, jadi tidak perlu menunggu lama.',
        success: true,
      );
    }

    return true;
  }
}

/// Kotak kemajuan unduhan pembaruan.
///
/// Menutup sendiri begitu unduhan selesai (layar Pasang akan terbuka oleh
/// bagian Android) atau bila unduhan gagal.
class _RtsKotakUnduhan extends StatefulWidget {
  const _RtsKotakUnduhan();

  @override
  State<_RtsKotakUnduhan> createState() => _RtsKotakUnduhanState();
}

class _RtsKotakUnduhanState extends State<_RtsKotakUnduhan> {
  Timer? _pemantau;
  double _persen = 0;
  String _pesan = 'Menyiapkan unduhan...';
  int _jumlahDiperiksa = 0;

  @override
  void initState() {
    super.initState();

    _pemantau = Timer.periodic(
      const Duration(milliseconds: 700),
      (Timer _) => _periksa(),
    );
  }

  @override
  void dispose() {
    _pemantau?.cancel();
    super.dispose();
  }

  Future<void> _periksa() async {
    final Map<String, dynamic> jawab = await RtsPasangApk.status();

    if (!mounted) return;

    final String keadaan = (jawab['status'] ?? '').toString();
    final num? persen = jawab['persen'] as num?;

    _jumlahDiperiksa++;

    setState(() {
      if (persen != null) {
        _persen = persen.toDouble().clamp(0, 100);
      }

      if (keadaan == 'MENGUNDUH') {
        _pesan = (jawab['pesan'] ?? 'Mengunduh berkas pembaruan...').toString();
      } else if (keadaan == 'GAGAL') {
        _pesan = (jawab['pesan'] ?? 'Unduhan gagal.').toString();
      } else if (keadaan == 'IZIN_DIPERLUKAN') {
        _pesan = 'Berkas sudah terunduh. Menunggu izin pemasangan.';
      } else if (keadaan == 'SELESAI') {
        _pesan = 'Unduhan selesai. Layar Pasang terbuka...';
      }
    });

    final bool berhenti = keadaan == 'SELESAI' ||
        keadaan == 'GAGAL' ||
        keadaan == 'IZIN_DIPERLUKAN';

    if (berhenti && mounted) {
      _pemantau?.cancel();

      Navigator.of(context).pop();

      if (keadaan == 'IZIN_DIPERLUKAN') {
        // Berkas sudah terunduh; yang kurang hanya izin pemasangan.
        await RtsPasangApk.selesaikanIzin(context);
      }

      return;
    }

    // Pengaman: bila bagian Android tidak pernah menjawab, kotak ditutup
    // supaya petugas tidak tertahan pada layar tunggu.
    if (_jumlahDiperiksa > 150 && mounted) {
      _pemantau?.cancel();

      Navigator.of(context).pop();

      rtsShowMessage(
        context,
        'Unduhan berjalan di latar belakang. Bila sudah selesai, ketuk '
        'pemberitahuan "Pembaruan RTS Panel" pada layar HP.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.download_rounded, color: rtsMaroon),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mengunduh Pembaruan',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _persen <= 0 ? null : _persen / 100,
              minHeight: 9,
              backgroundColor: const Color(0xFFEDE3E1),
              color: rtsMaroon,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _pesan,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: rtsTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${_persen.toStringAsFixed(0)} %',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: rtsMaroon,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Unduhan berjalan di dalam aplikasi. Layar Pasang akan terbuka '
            'sendiri setelah berkas selesai diunduh.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: rtsTextSecondary,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'SEMBUNYIKAN',
            style: TextStyle(color: rtsTextSecondary),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* WIDGET PENDUKUNG BERANDA                                                   */
/* ------------------------------------------------------------------------- */

/// Kotak cuaca kecil pada beranda.
class RtsKotakCuaca extends StatefulWidget {
  const RtsKotakCuaca({super.key});

  @override
  State<RtsKotakCuaca> createState() => _RtsKotakCuacaState();
}

class _RtsKotakCuacaState extends State<RtsKotakCuaca> {
  bool memuat = false;

  /// Menekan kotak cuaca mengambil laporan sekali lagi.
  ///
  /// Bila titik lokasi belum diizinkan, permintaan izin muncul pada saat ini,
  /// sehingga laporan cuaca dapat dihidupkan langsung dari beranda - tidak
  /// harus lewat halaman Pengaturan lebih dahulu.
  Future<void> _ambil() async {
    if (memuat) return;

    setState(() => memuat = true);

    await RtsCuaca.muat(paksa: true);

    if (!mounted) return;

    setState(() => memuat = false);

    final RtsCuacaHari? hari = RtsCuaca.data;

    if (hari == null) {
      // Keterangan sebabnya diambil dari RtsCuaca.status, misalnya:
      // "Izin lokasi belum diberikan." atau "Layanan lokasi HP dimatikan."
      rtsShowMessage(context, RtsCuaca.status);
      return;
    }

    rtsShowMessage(
      context,
      'Cuaca diperbarui: ${hari.suhu.round()} derajat, ${hari.keterangan}.',
      success: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final RtsCuacaHari? hari = RtsCuaca.data;
    final bool sedangMemuat = memuat || RtsCuaca.sedangMemuat;

    final BoxDecoration hiasan = BoxDecoration(
      color: Colors.white.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
    );

    // -----------------------------------------------------------------------
    // Sebelum laporan pertama berhasil, kotak tetap ditampilkan dalam bentuk
    // ringkas bertulisan "Cuaca" supaya petugas tahu tempatnya ada dan dapat
    // menekannya untuk memuat. Bila dibiarkan kosong, petugas tidak tahu
    // bahwa laporan cuaca memang disediakan di situ.
    // -----------------------------------------------------------------------
    if (hari == null) {
      return GestureDetector(
        onTap: _ambil,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: hiasan,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  sedangMemuat
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.wb_cloudy_rounded,
                          color: Colors.white,
                          size: 17,
                        ),
                  const SizedBox(width: 6),
                  const Text(
                    'Cuaca',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                sedangMemuat ? 'Memuat...' : 'Ketuk untuk memuat',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xccffffff),
                  fontSize: 9.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // -----------------------------------------------------------------------
    // Laporan cuaca sudah ada: suhu, gambar cuaca, kota, dan keadaannya.
    // -----------------------------------------------------------------------
    return GestureDetector(
      onTap: _ambil,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: hiasan,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(hari.ikon, color: Colors.white, size: 17),
                const SizedBox(width: 6),
                Text(
                  '${hari.suhu.round()}\u00b0C',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              hari.kota.isEmpty
                  ? hari.keterangan
                  : '${hari.kota} \u2022 ${hari.keterangan}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xccffffff),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu "Cuaca Beranda" pada halaman Pengaturan.
///
/// Dipakai untuk memeriksa bila laporan cuaca tidak muncul pada beranda:
/// menampilkan keterangan keadaan, titik lokasi yang dipakai, dan tombol untuk
/// mengambil ulang laporan cuaca.
class RtsKartuCuaca extends StatefulWidget {
  const RtsKartuCuaca({super.key});

  @override
  State<RtsKartuCuaca> createState() => _RtsKartuCuacaState();
}

class _RtsKartuCuacaState extends State<RtsKartuCuaca> {
  bool memuat = false;

  Future<void> _ambilUlang() async {
    setState(() => memuat = true);

    await RtsCuaca.muat(paksa: true);

    if (!mounted) return;

    setState(() => memuat = false);

    final RtsCuacaHari? hari = RtsCuaca.data;

    if (hari == null) {
      rtsShowMessage(context, RtsCuaca.status);
      return;
    }

    rtsShowMessage(
      context,
      'Laporan cuaca diperbarui: ${hari.suhu.round()} derajat, '
      '${hari.keterangan}${hari.kota.isEmpty ? '' : ' di ${hari.kota}'}.',
      success: true,
    );
  }

  /// Menyusun keterangan lengkap lalu menyalinnya ke papan klip HP.
  ///
  /// Guna: petugas dapat langsung menempelkannya pada pesan kepada pengembang
  /// tanpa perlu mengetik ulang. Aman disalin - tidak memuat password.
  Future<void> _salinKeterangan() async {
    final RtsCuacaHari? hari = RtsCuaca.data;

    final StringBuffer teks = StringBuffer();

    teks.writeln('KETERANGAN CUACA RTS PANEL');
    teks.writeln('Kode aplikasi : $rtsKodeAplikasi');
    teks.writeln('Versi terpasang: ${RtsVersi.label}');
    teks.writeln('Waktu         : ${RtsWaktu.jamMenit(DateTime.now())}');
    teks.writeln('Server        : ${RtsConfig.serverLabel}');
    teks.writeln('');
    teks.writeln('Keadaan       : ${RtsCuaca.status}');
    teks.writeln('Izin lokasi   : ${RtsCuaca.izinLokasi}');
    teks.writeln('GPS aktif     : ${RtsCuaca.gpsAktif ? 'YA' : 'TIDAK'}');
    teks.writeln('Titik lokasi  : ${RtsCuaca.titikTerakhir.isEmpty ? '(belum ada)' : RtsCuaca.titikTerakhir}');

    if (RtsCuaca.dicobaPada != null) {
      teks.writeln('Percobaan     : ${RtsWaktu.jamMenit(RtsCuaca.dicobaPada!)}');
    }

    teks.writeln('Berhasil      : ${RtsCuaca.jumlahBerhasil} kali');

    if (hari != null) {
      teks.writeln('');
      teks.writeln('Suhu          : ${hari.suhu.round()} derajat');
      teks.writeln('Keadaan cuaca : ${hari.keterangan}');
      teks.writeln('Kota          : ${hari.kota.isEmpty ? '(tidak terbaca)' : hari.kota}');
      teks.writeln('Terendah/Tertinggi: ${hari.min.round()} / ${hari.maks.round()}');
      teks.writeln('Peluang hujan : ${hari.hujan}%');
    }

    if (RtsCuaca.pesanTeknis.isNotEmpty) {
      teks.writeln('');
      teks.writeln('Keterangan teknis:');
      teks.writeln(RtsCuaca.pesanTeknis);
    }

    await Clipboard.setData(ClipboardData(text: teks.toString()));

    if (!mounted) return;

    rtsShowMessage(
      context,
      'Keterangan cuaca sudah disalin. Tempelkan pada pesan kepada pengembang.',
      success: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final RtsCuacaHari? hari = RtsCuaca.data;
    final bool perluIzin = RtsCuaca.perluIzinLokasi;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xfffff5f5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xfff0d8d8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_rounded, size: 17, color: rtsMaroon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kode aplikasi terpasang: $rtsKodeAplikasi\n'
                    'Versi: ${RtsVersi.label}',
                    style: const TextStyle(
                      color: rtsMaroon,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 11),
          const Text(
            'Beranda menampilkan suhu dan keadaan cuaca hari ini pada lokasi '
            'petugas. Titik lokasi diambil dari GPS HP; bila belum pernah '
            'diizinkan, aplikasi akan menanyakan izin.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          RtsInfoRow(
            'Keadaan',
            RtsCuaca.status,
            valueColor: perluIzin ? rtsAmber : rtsTextPrimary,
          ),
          const RtsDivider(),
          RtsInfoRow('Izin lokasi', RtsCuaca.izinLokasi),
          const RtsDivider(),
          RtsInfoRow('GPS HP', RtsCuaca.gpsAktif ? 'Aktif' : 'Tidak aktif'),
          const RtsDivider(),
          RtsInfoRow(
            'Titik lokasi',
            RtsCuaca.titikTerakhir.isEmpty ? 'Belum terbaca' : RtsCuaca.titikTerakhir,
          ),
          const RtsDivider(),
          RtsInfoRow(
            'Cuaca terbaca',
            hari == null
                ? 'Belum ada'
                : '${hari.suhu.round()} derajat, ${hari.keterangan}'
                    '${hari.kota.isEmpty ? '' : ' - ${hari.kota}'}',
          ),
          if (hari != null) ...[
            const RtsDivider(),
            RtsInfoRow(
              'Hari ini',
              'Terendah ${hari.min.round()} / Tertinggi ${hari.maks.round()} '
                  'derajat, peluang hujan ${hari.hujan}%',
            ),
          ],
          if (RtsCuaca.pesanTeknis.isNotEmpty) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xfff7f7f9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffe6e6ee)),
              ),
              child: Text(
                'Keterangan teknis:\n${RtsCuaca.pesanTeknis}',
                style: const TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 10.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: rtsMaroon),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: memuat ? null : _ambilUlang,
              icon: memuat
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: rtsMaroon,
                      ),
                    )
                  : const Icon(Icons.my_location_rounded, size: 18),
              label: Text(
                memuat
                    ? 'MENGAMBIL LAPORAN CUACA...'
                    : 'AMBIL LAPORAN CUACA SEKARANG',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rtsMaroon,
                ),
              ),
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xffd8d8e2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: _salinKeterangan,
              icon: const Icon(Icons.copy_all_rounded,
                  size: 17, color: rtsTextSecondary),
              label: const Text(
                'SALIN KETERANGAN (KIRIM KE PENGEMBANG)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: rtsTextSecondary,
                ),
              ),
            ),
          ),
          if (perluIzin) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xfffdf6ec),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xfff0e2cf)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 16, color: Color(0xff9a6b23)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bila pertanyaan izin lokasi tidak muncul lagi, buka '
                      'Pengaturan HP - Aplikasi - RTS Panel - Izin - Lokasi, '
                      'lalu pilih Izinkan. Untuk GPS: Pengaturan HP - Lokasi.',
                      style: TextStyle(
                        color: Color(0xff7a5a26),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Kartu "Rencana Akun" pada halaman Profil.
///
/// Dipakai untuk membedakan akun GRATIS dan akun PRO (berbayar) yang akan
/// ditambahkan pada pembaruan berikutnya.
class RtsKartuRencanaAkun extends StatefulWidget {
  const RtsKartuRencanaAkun({super.key, required this.user});

  final RtsUser user;

  @override
  State<RtsKartuRencanaAkun> createState() => _RtsKartuRencanaAkunState();
}

class _RtsKartuRencanaAkunState extends State<RtsKartuRencanaAkun> {
  @override
  Widget build(BuildContext context) {
    final bool pro = RtsTingkatAkun.pro;
    final bool dariServer = RtsTingkatAkun.dariServer;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: pro
                      ? const Color(0xffe8f5ec)
                      : const Color(0xfffaecee),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  pro
                      ? Icons.workspace_premium_rounded
                      : Icons.workspace_premium_outlined,
                  color: pro ? rtsGreen : rtsMaroon,
                  size: 22,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Akun ${RtsTingkatAkun.label}',
                      style: const TextStyle(
                        color: rtsTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      RtsTingkatAkun.keterangan,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              RtsBadge(
                RtsTingkatAkun.label,
                background: pro
                    ? const Color(0xffe8f5ec)
                    : const Color(0xfffaecee),
                foreground: pro ? rtsGreen : rtsMaroon,
              ),
            ],
          ),
          const SizedBox(height: 13),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfff7f3f2),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: rtsCardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  pro ? Icons.block_rounded : Icons.campaign_outlined,
                  size: 17,
                  color: pro ? rtsGreen : rtsMaroon,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    pro
                        ? 'Iklan dimatikan untuk akun ini, karena Akun PRO '
                            'bebas iklan.'
                        : 'Iklan ditampilkan pada akun ini. Beralih ke Akun PRO '
                            'menghilangkan seluruh iklan.',
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 11.5,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          RtsInfoRow('Masa berlaku', RtsLangganan.sekarang.keteranganMasa),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: pro ? rtsGreen : rtsMaroon,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                      builder: (_) => LanggananProPage(
                        user: widget.user,
                        token: RtsSesi.token,
                      ),
                    ),
                  )
                  .then((_) {
                    if (mounted) setState(() {});
                  }),
              child: Text(
                pro
                    ? 'KELOLA LANGGANAN'
                    : 'LANGGANAN PRO - ${rtsRupiah(RtsLangganan.sekarang.harga)} / '
                        '${RtsLangganan.sekarang.durasiHari} HARI',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
          ),
          if ((RtsSesi.user?.role ?? '') == 'ADMIN') ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: rtsMaroon,
                  side: const BorderSide(color: rtsMaroon),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () => Navigator.of(context)
                    .push(
                      MaterialPageRoute(
                        builder: (_) => KelolaProPage(
                          user: widget.user,
                          token: RtsSesi.token,
                        ),
                      ),
                    )
                    .then((_) {
                      if (mounted) setState(() {});
                    }),
                icon: const Icon(Icons.groups_rounded, size: 18),
                label: const Text(
                  'KELOLA AKUN PRO (ADMIN)',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Setujui pembayaran QRIS petugas dan atur masa PRO langsung dari HP.',
              style: TextStyle(
                color: rtsTextSecondary,
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
          if (RtsTingkatAkun.bolehUji && !dariServer) ...[
            const SizedBox(height: 6),
            const RtsDivider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: rtsMaroon,
              value: RtsTingkatAkun.ujiMenyala,
              onChanged: (bool nilai) async {
                await RtsTingkatAkun.setUji(nilai);

                if (!context.mounted) return;

                setState(() {});

                rtsShowMessage(
                  context,
                  nilai
                      ? 'Uji coba Akun PRO menyala. Iklan disembunyikan - '
                          'berlaku setelah kembali ke beranda atau aplikasi '
                          'dibuka ulang.'
                      : 'Uji coba Akun PRO dimatikan. Iklan tampil kembali.',
                  success: true,
                );
              },
              title: const Text(
                'Uji coba Akun PRO',
                style: TextStyle(
                  color: rtsTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Khusus ADMIN. Menyembunyikan iklan untuk mencoba tampilan '
                'bebas iklan tanpa mengubah database.',
                style: TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}


/// Kartu "Pembaruan Aplikasi" pada halaman Pengaturan.
class RtsKartuPembaruan extends StatefulWidget {
  const RtsKartuPembaruan({super.key});

  @override
  State<RtsKartuPembaruan> createState() => _RtsKartuPembaruanState();
}

class _RtsKartuPembaruanState extends State<RtsKartuPembaruan> {
  @override
  Widget build(BuildContext context) {
    final RtsInfoVersi? info = RtsPembaruan.terbaru;

    final String status;

    if (RtsPembaruan.sedangMemeriksa) {
      status = 'Sedang memeriksa...';
    } else if (info == null) {
      status = 'Pembaruan otomatis aktif saat aplikasi dibuka';
    } else if (info.kode > RtsVersi.kode) {
      status = 'Versi baru tersedia: ${info.nama}';
    } else {
      status = 'Sudah versi terbaru';
    }

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Aplikasi memeriksa versi terbaru setiap kali dibuka. Bila ada '
            'versi baru, muncul pemberitahuan beserta tombol unduh, sehingga '
            'seluruh tim dapat memakai versi yang sama.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          RtsInfoRow('Versi terpasang', RtsVersi.label),
          const RtsDivider(),
          RtsInfoRow(
            'Keadaan',
            status,
            valueColor: info != null && info.kode > RtsVersi.kode
                ? rtsAmber
                : rtsTextPrimary,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: rtsMaroon),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              onPressed: RtsPembaruan.sedangMemeriksa
                  ? null
                  : () async {
                      await RtsPembaruan.periksaManual(context);

                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'PERIKSA PEMBARUAN SEKARANG',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: rtsMaroon,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ========================================================================= */
/* IKLAN LAYAR PEMBUKA (APP OPEN)                                            */
/* ========================================================================= */

/// Iklan layar pembuka: tampil sekilas setiap aplikasi dibuka.
///
/// Kode unit iklan disimpan pada RtsIklan.appOpenIklan. Iklan hanya dipakai
/// akun GRATIS - akun PRO bebas iklan. Bila iklan belum siap, gagal dimuat,
/// atau baru saja ditampilkan (kurang dari 4 menit), aplikasi tetap berjalan
/// seperti biasa tanpa hambatan apa pun.
class RtsIklanBuka {
  const RtsIklanBuka._();

  static const String _kunciWaktu = 'rts_iklan_buka_waktu';

  /// Jeda paling sedikit antar iklan layar pembuka.
  static const Duration jedaMinimal = Duration(minutes: 4);

  static AppOpenAd? _iklan;
  static DateTime? _dimuat;
  static bool _sedangMemuat = false;
  static bool _sudahDicoba = false;

  /// Menyiapkan lalu menampilkan iklan layar pembuka. Dipanggil dari main().
  static Future<void> tampilkanSaatDibuka() async {
    if (!RtsIklan.aktif || _sudahDicoba) return;

    _sudahDicoba = true;

    try {
      if (await _baruSajaTampil()) return;

      await RtsIklan.siapkan();

      if (!RtsIklan.siap) return;

      await _muat();

      // Memberi kesempatan layar pembuka aplikasi tampil lebih dahulu,
      // supaya iklan tidak menutupi proses pemeriksaan sesi.
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      await _tampilkan();
    } catch (_) {
      // Diabaikan: iklan tidak boleh mengganggu jalannya aplikasi.
    }
  }

  static Future<bool> _baruSajaTampil() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final int terakhir = prefs.getInt(_kunciWaktu) ?? 0;

      if (terakhir <= 0) return false;

      return DateTime.now()
              .difference(DateTime.fromMillisecondsSinceEpoch(terakhir)) <
          jedaMinimal;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _catatWaktu() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();

      await prefs.setInt(_kunciWaktu, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Diabaikan.
    }
  }

  static Future<void> _muat() async {
    if (_sedangMemuat) return;

    if (_iklan != null &&
        _dimuat != null &&
        DateTime.now().difference(_dimuat!) < const Duration(hours: 4)) {
      return;
    }

    _sedangMemuat = true;

    final Completer<void> selesai = Completer<void>();

    void tandaiSelesai() {
      if (!selesai.isCompleted) selesai.complete();
    }

    try {
      await AppOpenAd.load(
        adUnitId: RtsIklan.appOpenIklan,
        request: const AdRequest(),
        adLoadCallback: AppOpenAdLoadCallback(
          onAdLoaded: (AppOpenAd iklanBaru) {
            _iklan?.dispose();
            _iklan = iklanBaru;
            _dimuat = DateTime.now();
            tandaiSelesai();
          },
          onAdFailedToLoad: (LoadAdError galat) {
            _iklan = null;
            tandaiSelesai();
          },
        ),
      );
    } catch (_) {
      _iklan = null;
      tandaiSelesai();
    }

    try {
      await selesai.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      // Waktu habis: iklan dilewati supaya aplikasi tidak tertahan.
    }

    _sedangMemuat = false;
  }

  static Future<void> _tampilkan() async {
    final AppOpenAd? iklan = _iklan;

    if (iklan == null) return;

    _iklan = null;

    iklan.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (AppOpenAd ad) {
        ad.dispose();
      },
      onAdFailedToShowFullScreenContent: (AppOpenAd ad, AdError galat) {
        ad.dispose();
      },
    );

    try {
      await iklan.show();
      await _catatWaktu();
    } catch (_) {
      iklan.dispose();
    }
  }
}

/* ========================================================================= */
/* LANGGANAN PRO: masa berlaku 30 hari + uji coba 7 hari                     */
/* ========================================================================= */

/// Menulis angka menjadi rupiah, contoh: 5000 -> Rp5.000.
String rtsRupiah(int angka) {
  final String teks = angka.abs().toString();
  final StringBuffer hasil = StringBuffer();

  for (int i = 0; i < teks.length; i++) {
    if (i > 0 && (teks.length - i) % 3 == 0) hasil.write('.');
    hasil.write(teks[i]);
  }

  return 'Rp${hasil.toString()}';
}

/// Keterangan langganan PRO yang dibaca dari server (api/langganan.php).
class RtsLangganan {
  const RtsLangganan({
    this.pro = false,
    this.proAktif = false,
    this.trialAktif = false,
    this.trialTersedia = false,
    this.trialPernahDipakai = false,
    this.sisaHari = 0,
    this.sisaTrialHari = 0,
    this.berlakuSampai = '',
    this.sumber = 'GRATIS',
    this.harga = 5000,
    this.durasiHari = 30,
    this.trialHari = 7,
    this.nmid = 'ID1026519749489',
    this.namaMerchant = 'BENE-S',
    this.catatan = '',
  });

  /// Membaca balasan server. Balasan berisi dua bagian: `langganan` dan `qris`.
  factory RtsLangganan.dariBalasan(Map<String, dynamic> balasan) {
    final Map<String, dynamic> langganan =
        ((balasan['langganan'] as Map?) ?? const {}).cast<String, dynamic>();

    final Map<String, dynamic> qris =
        ((balasan['qris'] as Map?) ?? const {}).cast<String, dynamic>();

    return RtsLangganan(
      pro: rtsBenar(langganan['pro']),
      proAktif: rtsBenar(langganan['pro_aktif']),
      trialAktif: rtsBenar(langganan['trial_aktif']),
      trialTersedia: rtsBenar(langganan['trial_tersedia']),
      trialPernahDipakai: rtsBenar(langganan['trial_pernah_dipakai']),
      sisaHari: int.tryParse('${langganan['sisa_hari'] ?? 0}') ?? 0,
      sisaTrialHari: int.tryParse('${langganan['sisa_trial_hari'] ?? 0}') ?? 0,
      berlakuSampai: (langganan['berlaku_sampai'] ?? '').toString(),
      sumber: (langganan['sumber'] ?? 'GRATIS').toString().toUpperCase(),
      harga: int.tryParse('${qris['harga'] ?? 5000}') ?? 5000,
      durasiHari: int.tryParse('${qris['durasi_hari'] ?? 30}') ?? 30,
      trialHari: int.tryParse('${qris['trial_hari'] ?? 7}') ?? 7,
      nmid: (qris['nmid'] ?? 'ID1026519749489').toString(),
      namaMerchant: (qris['nama'] ?? 'BENE-S').toString(),
      catatan: (qris['catatan'] ?? '').toString(),
    );
  }

  /// Keadaan langganan terakhir yang diketahui aplikasi.
  static RtsLangganan sekarang = const RtsLangganan();

  /// Letak gambar QRIS di dalam proyek Flutter.
  ///
  /// Nama berkasnya HARUS persis seperti ini. Bapak cukup menyalin gambar QRIS
  /// milik Bapak ke folder `assets/images/` dengan nama `qris_bene_s.jpg`.
  static const String gambarQris = 'assets/images/qris_bene_s.jpg';

  final bool pro;
  final bool proAktif;
  final bool trialAktif;
  final bool trialTersedia;
  final bool trialPernahDipakai;
  final int sisaHari;
  final int sisaTrialHari;
  final String berlakuSampai;
  final String sumber;
  final int harga;
  final int durasiHari;
  final int trialHari;
  final String nmid;
  final String namaMerchant;
  final String catatan;

  String get label {
    if (proAktif) return 'PRO';
    if (trialAktif) return 'PRO (UJI COBA)';
    return 'GRATIS';
  }

  String get keteranganMasa {
    if (proAktif) {
      if (berlakuSampai.isEmpty) return 'Berlaku tanpa batas waktu.';
      return 'Berlaku sampai $berlakuSampai (sisa $sisaHari hari).';
    }

    if (trialAktif) {
      return 'Uji coba gratis, sisa $sisaTrialHari hari.';
    }

    if (trialTersedia) {
      return 'Uji coba gratis $trialHari hari BELUM dipakai - tekan tombol '
          'uji coba di bawah.';
    }

    return 'Masa langganan sudah berakhir. Aktifkan kembali untuk bebas iklan.';
  }

  /// Menyimpan keadaan langganan terakhir + memperbarui data akun pada sesi,
  /// supaya iklan langsung berhenti/berjalan sesuai keadaan terbaru.
  static Future<void> simpanKeSesi(RtsLangganan baru) async {
    sekarang = baru;

    final RtsUser? user = RtsSesi.user;

    if (user == null) return;

    final RtsUser terbaru = user.copyWith(
      akunPro: baru.pro,
      proSelesai: baru.proAktif ? baru.berlakuSampai : '',
      trialAktif: baru.trialAktif,
      trialTersedia: baru.trialTersedia,
      sisaHari: baru.sisaHari,
      sumberLangganan: baru.sumber,
      berlakuSampai: baru.berlakuSampai,
    );

    await RtsSesi.simpan(RtsSesi.token, terbaru);

    // Pemeriksaan PRO yang tersimpan di dalam HP ikut diperbarui, supaya
    // seluruh menu PRO langsung terbuka tanpa menunggu jawaban lama kedaluwarsa.
    try {
      await RtsKasirLokal.aku.atur(
        baseUrl: RtsConfig.baseUrl,
        token: RtsSesi.token,
        pengguna: terbaru.toJson(),
      );

      await RtsKasirLokal.aku.akses(paksa: true);
    } catch (_) {
      // keterangan akun gagal diserahkan: tidak menghalangi pemakaian
    }
  }
}

/* ========================================================================= */
/* PENYEGAR STATUS AKUN (dipakai Beranda & menu Sinkronisasi)                */
/* ========================================================================= */

/// Memeriksa ulang keadaan akun (PRO / GRATIS) LANGSUNG KE SERVER.
///
/// Dipakai saat aplikasi mendapati jawaban lama "belum boleh" padahal
/// pembayaran sudah disetujui ADMIN. Hasilnya disimpan pada sesi dan pada
/// pemeriksaan di dalam HP, sehingga:
///   1. kartu menu PRO langsung terbuka tanpa memasang ulang aplikasi;
///   2. halaman Kasir / Peta yang memakai pemeriksaan di HP juga terbuka.
class RtsAkunSegar {
  const RtsAkunSegar._();

  /// Mengembalikan true bila akun ini PRO menurut server.
  static Future<bool> periksa(String token) async {
    if (token.isEmpty) return false;

    try {
      final ApiClient api = ApiClient(token: token);
      final Map<String, dynamic> balasan = await api.get('session_check.php');

      final RtsUser terbaru = RtsUser.fromJson(
        ((balasan['user'] as Map?) ?? const {}).cast<String, dynamic>(),
      );

      final RtsLangganan baru = RtsLangganan.dariBalasan(balasan);

      await RtsSesi.simpan(token, terbaru);
      await RtsLangganan.simpanKeSesi(baru);

      return baru.proAktif ||
          baru.trialAktif ||
          terbaru.akunPro ||
          RtsTingkatAkun.pro;
    } catch (_) {
      return false;
    }
  }
}

/* ========================================================================= */
/* FOTO PRIBADI PETUGAS                                                      */
/* ========================================================================= */

/// Mengunggah dan menghapus foto pribadi ke server (api/upload_foto.php).
class RtsFotoUnggah {
  const RtsFotoUnggah._();

  /// Mengirim berkas foto. [aksi] diisi 'hapus' untuk menghapus foto.
  static Future<String> kirim({
    required String token,
    XFile? berkas,
    String aksi = '',
  }) async {
    final Uri alamat = Uri.parse('${RtsConfig.baseUrl}/upload_foto.php');

    final http.MultipartRequest permintaan = http.MultipartRequest('POST', alamat);

    permintaan.headers['Accept'] = 'application/json';
    permintaan.headers['Authorization'] = 'Bearer $token';

    if (aksi.isNotEmpty) {
      permintaan.fields['aksi'] = aksi;
    }

    if (aksi.isEmpty) {
      if (berkas == null) {
        throw ApiException('Belum ada foto yang dipilih.');
      }

      permintaan.files.add(
        await http.MultipartFile.fromPath('foto', berkas.path, filename: 'foto.jpg'),
      );
    }

    final http.StreamedResponse aliran =
        await permintaan.send().timeout(const Duration(seconds: 90));

    final String isi = await aliran.stream.bytesToString();

    Map<String, dynamic> balasan = <String, dynamic>{};

    if (isi.trim().isNotEmpty) {
      try {
        final dynamic urai = jsonDecode(isi);

        if (urai is Map) balasan = urai.cast<String, dynamic>();
      } catch (_) {
        // Balasan bukan JSON: dipakai keterangan bawaan di bawah.
      }
    }

    if (aliran.statusCode < 200 || aliran.statusCode >= 300) {
      throw ApiException(
        (balasan['message'] ??
                'Foto gagal diunggah (kode ${aliran.statusCode}).')
            .toString(),
        statusCode: aliran.statusCode,
      );
    }

    return (balasan['foto_url'] ?? '').toString();
  }

  /// Menyimpan alamat foto terbaru pada sesi sehingga seluruh halaman berubah.
  static Future<void> simpanKeSesi(String alamatFoto) async {
    final RtsUser? user = RtsSesi.user;

    if (user == null) return;

    await RtsSesi.simpan(RtsSesi.token, user.copyWith(fotoProfil: alamatFoto));
  }
}

/// Foto pribadi petugas. Bila belum ada foto, ditampilkan huruf awal nama.
///
/// Mengetuk foto (bila [bolehGanti] true) membuka pilihan Ambil dari Kamera,
/// Pilih dari Galeri, atau Hapus Foto. Setelah foto terunggah, tampilan
/// langsung berubah tanpa perlu keluar dari halaman.
class RtsFotoProfil extends StatefulWidget {
  const RtsFotoProfil({
    super.key,
    this.ukuran = 56,
    this.bolehGanti = false,
    this.latarBelakang = Colors.white,
    this.garisTepi,
    this.warnaHuruf = rtsMaroon,
    this.alamatPaksa,
    this.inisialPaksa,
  });

  final double ukuran;
  final bool bolehGanti;
  final Color latarBelakang;
  final Color? garisTepi;
  final Color warnaHuruf;

  /// Alamat foto milik ORANG LAIN (dipakai halaman Kelola Akun PRO oleh Admin).
  /// Bila kosong, dipakai foto pengguna yang sedang masuk.
  final String? alamatPaksa;

  /// Huruf awal milik ORANG LAIN, dipakai bila fotonya belum ada.
  final String? inisialPaksa;

  @override
  State<RtsFotoProfil> createState() => _RtsFotoProfilState();
}

class _RtsFotoProfilState extends State<RtsFotoProfil> {
  String _inisial(RtsUser? user) {
    final String nama = (widget.inisialPaksa ?? user?.displayName ?? '').trim();

    if (nama.isEmpty) return 'R';

    return nama.substring(0, 1).toUpperCase();
  }

  Future<void> _ketuk() async {
    await RtsFotoProfilPilih.tampilkan(context);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final RtsUser? user = RtsSesi.user;
    final String alamat =
        (widget.alamatPaksa ?? user?.fotoProfil ?? '').trim();
    final double lengkung = widget.ukuran * 0.32;

    final TextStyle gayaHuruf = TextStyle(
      color: widget.warnaHuruf,
      fontSize: widget.ukuran * 0.42,
      fontWeight: FontWeight.w800,
    );

    Widget isi;

    if (alamat.isEmpty) {
      isi = Center(child: Text(_inisial(user), style: gayaHuruf));
    } else {
      isi = Image.network(
        alamat,
        width: widget.ukuran,
        height: widget.ukuran,
        fit: BoxFit.cover,
        errorBuilder: (context, galat, tumpukan) =>
            Center(child: Text(_inisial(user), style: gayaHuruf)),
        loadingBuilder: (context, anak, kemajuan) {
          if (kemajuan == null) return anak;

          return Center(
            child: SizedBox(
              width: widget.ukuran * 0.34,
              height: widget.ukuran * 0.34,
              child: const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    final Widget kotak = Container(
      width: widget.ukuran,
      height: widget.ukuran,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: widget.latarBelakang,
        borderRadius: BorderRadius.circular(lengkung),
        border: widget.garisTepi == null
            ? null
            : Border.all(color: widget.garisTepi!),
      ),
      child: isi,
    );

    if (!widget.bolehGanti) return kotak;

    return GestureDetector(
      onTap: _ketuk,
      child: Stack(
        children: [
          kotak,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: rtsMaroon,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.6),
              ),
              child: Icon(
                Icons.photo_camera_rounded,
                size: widget.ukuran * 0.24,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pilihan mengganti foto pribadi: dari kamera, dari galeri, atau dihapus.
class RtsFotoProfilPilih {
  const RtsFotoProfilPilih._();

  static Future<void> tampilkan(BuildContext context) async {
    final String token = RtsSesi.token;

    if (token.isEmpty) {
      rtsShowMessage(context, 'Sesi tidak ditemukan. Silakan masuk kembali.');
      return;
    }

    final String? pilihan = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: rtsCardBorder,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Foto Pribadi',
              style: TextStyle(
                color: rtsTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Foto ini tampil pada kartu akun di beranda dan profil.',
              style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded, color: rtsMaroon),
              title: const Text('Ambil dari Kamera'),
              onTap: () => Navigator.of(sheetContext).pop('kamera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: rtsMaroon),
              title: const Text('Pilih dari Galeri'),
              onTap: () => Navigator.of(sheetContext).pop('galeri'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: rtsTextSecondary),
              title: const Text('Hapus Foto'),
              onTap: () => Navigator.of(sheetContext).pop('hapus'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (pilihan == null) return;

    if (pilihan == 'hapus') {
      await _kirim(context, token: token, aksi: 'hapus');

      return;
    }

    try {
      final ImagePicker pemilih = ImagePicker();

      final XFile? berkas = await pemilih.pickImage(
        source: pilihan == 'kamera' ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 900,
        maxHeight: 900,
        imageQuality: 85,
      );

      if (berkas == null) return;

      await _kirim(context, token: token, berkas: berkas);
    } catch (_) {
      if (!context.mounted) return;

      rtsShowMessage(
        context,
        'Tidak dapat membuka kamera/galeri. Periksa izin aplikasi pada '
        'Pengaturan HP.',
      );
    }
  }

  static Future<void> _kirim(
    BuildContext context, {
    required String token,
    XFile? berkas,
    String aksi = '',
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(height: 12),
                Text(
                  'Mengunggah foto...',
                  style: TextStyle(color: rtsTextPrimary, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final String alamat = await RtsFotoUnggah.kirim(
        token: token,
        berkas: berkas,
        aksi: aksi,
      );

      await RtsFotoUnggah.simpanKeSesi(alamat);

      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      rtsShowMessage(
        context,
        aksi == 'hapus'
            ? 'Foto pribadi berhasil dihapus.'
            : 'Foto pribadi berhasil diganti.',
        success: true,
      );
    } on ApiException catch (error) {
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!context.mounted) return;

      Navigator.of(context, rootNavigator: true).pop();

      rtsShowMessage(context, 'Terjadi gangguan saat mengunggah foto.');
    }
  }
}

/* ========================================================================= */
/* HALAMAN LANGGANAN PRO                                                     */
/* ========================================================================= */

/// Halaman Langganan PRO: keadaan langganan, pembayaran QRIS, dan uji coba.
class LanggananProPage extends StatefulWidget {
  const LanggananProPage({super.key, required this.user, required this.token});

  final RtsUser user;
  final String token;

  @override
  State<LanggananProPage> createState() => _LanggananProPageState();
}

class _LanggananProPageState extends State<LanggananProPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  RtsLangganan data = RtsLangganan.sekarang;
  bool memuat = true;
  bool sedangProses = false;
  String pesanGalat = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (mounted) {
      setState(() {
        memuat = true;
        pesanGalat = '';
      });
    }

    try {
      final Map<String, dynamic> balasan = await api.get('langganan.php');
      final RtsLangganan baru = RtsLangganan.dariBalasan(balasan);

      await RtsLangganan.simpanKeSesi(baru);

      if (!mounted) return;

      setState(() {
        data = baru;
        memuat = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        memuat = false;
        pesanGalat = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        memuat = false;
        pesanGalat = 'Tidak dapat membaca keadaan langganan dari server.';
      });
    }
  }

  Future<void> _jalan(String aksi) async {
    if (sedangProses) return;

    setState(() => sedangProses = true);

    try {
      final Map<String, dynamic> balasan = await api.post(
        'langganan.php',
        <String, dynamic>{'aksi': aksi},
      );

      final RtsLangganan baru = RtsLangganan.dariBalasan(balasan);

      await RtsLangganan.simpanKeSesi(baru);

      if (!mounted) return;

      setState(() {
        data = baru;
        sedangProses = false;
      });

      rtsShowMessage(
        context,
        (balasan['message'] ?? 'Selesai.').toString(),
        success: true,
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() => sedangProses = false);

      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;

      setState(() => sedangProses = false);

      rtsShowMessage(context, 'Terjadi gangguan saat menghubungi server.');
    }
  }

  Future<void> _sudahBayar() async {
    final bool? lanjut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Konfirmasi Pembayaran',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Pastikan pembayaran ${rtsRupiah(data.harga)} sudah berhasil dikirim '
          'melalui QRIS. Setelah ditekan, Admin akan memeriksa pembayaran Anda '
          'lalu mengaktifkan Akun PRO selama ${data.durasiHari} hari.',
          style: const TextStyle(fontSize: 12.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'BATAL',
              style: TextStyle(color: rtsTextSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('YA, SAYA SUDAH BAYAR'),
          ),
        ],
      ),
    );

    if (lanjut == true) await _jalan('klaim');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.93),
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: RefreshIndicator(
                    color: rtsMaroon,
                    onRefresh: _muat,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        _kartuKeadaan(),
                        if (memuat) ...[
                          const SizedBox(height: 14),
                          const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.2),
                            ),
                          ),
                        ],
                        if (pesanGalat.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          RtsCard(
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: rtsMaroon, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    pesanGalat,
                                    style: const TextStyle(
                                      color: rtsTextSecondary,
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const RtsSectionTitle('Pembayaran QRIS'),
                        const SizedBox(height: 11),
                        _kartuQris(),
                        const SizedBox(height: 18),
                        const RtsSectionTitle('Uji Coba Gratis'),
                        const SizedBox(height: 11),
                        _kartuUjiCoba(),
                        if (!data.pro) ...[
                          const SizedBox(height: 18),
                          const RtsIklanAsli(),
                        ],
                        const SizedBox(height: 18),
                        const RtsSectionTitle('Keterangan'),
                        const SizedBox(height: 11),
                        _kartuKeterangan(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Langganan PRO',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Masa berlaku dan pembayaran',
                  style: TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (sedangProses)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  Widget _kartuKeadaan() {
    final bool bebasIklan = data.pro;

    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: bebasIklan
                      ? const Color(0xffe8f5ec)
                      : const Color(0xfffaecee),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  bebasIklan
                      ? Icons.workspace_premium_rounded
                      : Icons.workspace_premium_outlined,
                  color: bebasIklan ? rtsGreen : rtsMaroon,
                  size: 23,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Akun ${RtsTingkatAkun.label}',
                      style: const TextStyle(
                        color: rtsTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      RtsTingkatAkun.keterangan,
                      style: const TextStyle(
                        color: rtsTextSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              RtsBadge(
                data.label,
                background: bebasIklan
                    ? const Color(0xffe8f5ec)
                    : const Color(0xfffaecee),
                foreground: bebasIklan ? rtsGreen : rtsMaroon,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const RtsDivider(),
          RtsInfoRow('Masa berlaku', data.keteranganMasa),
          const RtsDivider(),
          RtsInfoRow(
            'Harga langganan',
            '${rtsRupiah(data.harga)} / ${data.durasiHari} hari',
          ),
          const RtsDivider(),
          RtsInfoRow('Uji coba gratis', '${data.trialHari} hari (sekali saja)'),
        ],
      ),
    );
  }

  Widget _kartuQris() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _gambarQris(),
          const SizedBox(height: 14),
          Center(
            child: Text(
              rtsRupiah(data.harga),
              style: const TextStyle(
                color: rtsTextPrimary,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Center(
            child: Text(
              'untuk ${data.durasiHari} hari bebas iklan',
              style: const TextStyle(color: rtsTextSecondary, fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          RtsInfoRow('Nama usaha', data.namaMerchant),
          const RtsDivider(),
          RtsInfoRow('NMID QRIS', data.nmid),
          const SizedBox(height: 14),
          const Text(
            'Cara berlangganan:',
            style: TextStyle(
              color: rtsTextPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '1. Buka aplikasi bank atau dompet digital, pilih Bayar QRIS.\n'
            '2. Pindai gambar QRIS di atas.\n'
            '3. Bayar sesuai nominal yang tertera.\n'
            '4. Tekan tombol SAYA SUDAH BAYAR di bawah.\n'
            '5. Admin memeriksa pembayaran, lalu Akun PRO aktif selama '
            '${data.durasiHari} hari.',
            style: const TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: rtsMaroon,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: sedangProses ? null : _sudahBayar,
            child: const Text(
              'SAYA SUDAH BAYAR',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Bila sudah pernah menekan tombol ini, pernyataan pembayaran Anda '
            'sedang diperiksa Admin. Mohon ditunggu.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 10.5,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gambarQris() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.asset(
        RtsLangganan.gambarQris,
        width: double.infinity,
        fit: BoxFit.contain,
        errorBuilder: (context, galat, tumpukan) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: rtsSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: rtsCardBorder),
          ),
          child: const Column(
            children: [
              Icon(Icons.qr_code_2_rounded, size: 46, color: rtsMaroon),
              SizedBox(height: 8),
              Text(
                'Gambar QRIS belum dipasang',
                style: TextStyle(
                  color: rtsTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Salin gambar QRIS Bapak ke folder assets/images dengan nama '
                'qris_bene_s.jpg, lalu jalankan flutter clean dan flutter run.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kartuUjiCoba() {
    if (data.proAktif) {
      return RtsCard(
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, color: rtsGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                data.berlakuSampai.isEmpty
                    ? 'Akun PRO Anda aktif tanpa batas waktu. Terima kasih.'
                    : 'Akun PRO Anda aktif sampai ${data.berlakuSampai}. '
                        'Terima kasih.',
                style: const TextStyle(
                  color: rtsTextSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (data.trialAktif) {
      return RtsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.timelapse_rounded, color: rtsAmber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Uji coba gratis sedang berjalan - sisa '
                    '${data.sisaTrialHari} hari. Seluruh iklan dimatikan '
                    'selama uji coba.',
                    style: const TextStyle(
                      color: rtsTextSecondary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: rtsMaroon,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: sedangProses ? null : () => _jalan('klaim'),
              child: const Text(
                'LANJUT BERLANGGANAN',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    if (data.trialTersedia) {
      return RtsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Coba seluruh kelebihan Akun PRO (bebas iklan) selama '
              '7 hari tanpa biaya. Uji coba hanya dapat dipakai sekali.',
              style: TextStyle(
                color: rtsTextSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: rtsGreen,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: sedangProses ? null : () => _jalan('trial'),
              child: Text(
                'COBA GRATIS ${data.trialHari} HARI',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
    }

    return RtsCard(
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: rtsTextSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              data.trialPernahDipakai
                  ? 'Uji coba gratis sudah pernah dipakai akun ini. Silakan '
                      'aktifkan langganan melalui pembayaran QRIS di atas.'
                  : 'Uji coba gratis belum tersedia untuk akun ini. Silakan '
                      'aktifkan langganan melalui pembayaran QRIS di atas.',
              style: const TextStyle(
                color: rtsTextSecondary,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuKeterangan() {
    return RtsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Akun GRATIS: iklan tampil pada beranda dan pada setiap menu.\n'
            'Akun PRO: bebas iklan selama masa berlaku.\n\n'
            'Masa langganan yang masih berjalan akan DITAMBAHKAN, jadi '
            'pembayaran yang lebih awal tidak hangus.\n\n'
            'Pembayaran hanya melalui QRIS di atas. Aplikasi tidak menyimpan '
            'data rekening atau kartu siapa pun.',
            style: TextStyle(
              color: rtsTextSecondary,
              fontSize: 11.5,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}

/* ========================================================================= */
/* KELOLA AKUN PRO - KHUSUS ADMIN (di dalam aplikasi)                        */
/* ========================================================================= */

/// Satu akun pada daftar Kelola Akun PRO.
class RtsAkunPro {
  const RtsAkunPro({
    required this.id,
    required this.username,
    required this.namaLengkap,
    required this.role,
    required this.fotoProfil,
    required this.label,
    required this.berlakuSampai,
    required this.sumber,
    required this.proAktif,
    required this.trialAktif,
    required this.trialTersedia,
    required this.sisaHari,
    required this.sisaTrialHari,
  });

  factory RtsAkunPro.dariJson(Map<String, dynamic> json) {
    return RtsAkunPro(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      username: (json['username'] ?? '').toString(),
      namaLengkap: (json['nama_lengkap'] ?? '').toString(),
      role: (json['role'] ?? '').toString().toUpperCase(),
      fotoProfil: (json['foto_profil'] ?? '').toString(),
      label: (json['label'] ?? 'GRATIS').toString(),
      berlakuSampai: (json['berlaku_sampai'] ?? '').toString(),
      sumber: (json['sumber'] ?? 'GRATIS').toString().toUpperCase(),
      proAktif: rtsBenar(json['pro_aktif']),
      trialAktif: rtsBenar(json['trial_aktif']),
      trialTersedia: rtsBenar(json['trial_tersedia']),
      sisaHari: int.tryParse('${json['sisa_hari'] ?? 0}') ?? 0,
      sisaTrialHari: int.tryParse('${json['sisa_trial_hari'] ?? 0}') ?? 0,
    );
  }

  final int id;
  final String username;
  final String namaLengkap;
  final String role;
  final String fotoProfil;
  final String label;
  final String berlakuSampai;
  final String sumber;
  final bool proAktif;
  final bool trialAktif;
  final bool trialTersedia;
  final int sisaHari;
  final int sisaTrialHari;

  String get namaTampil =>
      namaLengkap.trim().isNotEmpty ? namaLengkap.trim() : username;

  String get keteranganMasa {
    if (proAktif) {
      if (berlakuSampai.isEmpty) return 'PRO tanpa batas waktu';
      return 'PRO sampai $berlakuSampai (sisa $sisaHari hari)';
    }
    if (trialAktif) return 'Uji coba, sisa $sisaTrialHari hari';
    if (trialTersedia) return 'Belum pernah uji coba';
    return 'GRATIS';
  }
}

/// Satu pernyataan pembayaran QRIS dari petugas.
class RtsBayarPro {
  const RtsBayarPro({
    required this.id,
    required this.userId,
    required this.namaLengkap,
    required this.username,
    required this.role,
    required this.jumlah,
    required this.hari,
    required this.catatan,
    required this.status,
    required this.dibuat,
    required this.diprosesPada,
  });

  factory RtsBayarPro.dariJson(Map<String, dynamic> json) {
    return RtsBayarPro(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      userId: int.tryParse('${json['user_id'] ?? 0}') ?? 0,
      namaLengkap: (json['nama_lengkap'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      role: (json['role'] ?? '').toString().toUpperCase(),
      jumlah: int.tryParse('${json['jumlah'] ?? 0}') ?? 0,
      hari: int.tryParse('${json['hari'] ?? 30}') ?? 30,
      catatan: (json['catatan'] ?? '').toString(),
      status: (json['status'] ?? '').toString().toUpperCase(),
      dibuat: (json['dibuat'] ?? '').toString(),
      diprosesPada: (json['diproses_pada'] ?? '').toString(),
    );
  }

  final int id;
  final int userId;
  final String namaLengkap;
  final String username;
  final String role;
  final int jumlah;
  final int hari;
  final String catatan;
  final String status;
  final String dibuat;
  final String diprosesPada;

  bool get menunggu => status == 'MENUNGGU';

  String get namaTampil =>
      namaLengkap.trim().isNotEmpty ? namaLengkap.trim() : username;
}

/// Halaman Kelola Akun PRO - hanya untuk ADMIN.
///
/// Di sinilah ADMIN menyetujui pembayaran QRIS petugas dan memberikan atau
/// menghentikan masa langganan PRO - LANGSUNG DARI HP, tanpa membuka komputer.
class KelolaProPage extends StatefulWidget {
  const KelolaProPage({super.key, required this.user, required this.token});

  final RtsUser user;
  final String token;

  @override
  State<KelolaProPage> createState() => _KelolaProPageState();
}

class _KelolaProPageState extends State<KelolaProPage> {
  late final ApiClient api = ApiClient(token: widget.token);

  List<RtsAkunPro> daftar = <RtsAkunPro>[];
  List<RtsBayarPro> bayar = <RtsBayarPro>[];
  Map<String, bool> kolom = <String, bool>{};
  bool tabelPembayaran = true;

  bool memuat = true;
  bool sedangProses = false;
  String pesanGalat = '';
  String cari = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    if (mounted) {
      setState(() {
        memuat = true;
        pesanGalat = '';
      });
    }

    try {
      final Map<String, dynamic> balasan = await api.get('kelola_pro.php');

      if (!mounted) return;

      setState(() {
        memuat = false;
        _bacaDaftar(balasan);
      });
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() {
        memuat = false;
        pesanGalat = error.message;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        memuat = false;
        pesanGalat = 'Tidak dapat membaca daftar akun dari server.';
      });
    }
  }

  void _bacaDaftar(Map<String, dynamic> balasan) {
    daftar = ((balasan['daftar'] as List?) ?? const [])
        .whereType<Map>()
        .map((Map satu) => RtsAkunPro.dariJson(satu.cast<String, dynamic>()))
        .toList();

    bayar = ((balasan['bayar'] as List?) ?? const [])
        .whereType<Map>()
        .map((Map satu) => RtsBayarPro.dariJson(satu.cast<String, dynamic>()))
        .toList();

    final Map<String, dynamic> kolomBalasan =
        ((balasan['kolom'] as Map?) ?? const {}).cast<String, dynamic>();

    kolom = kolomBalasan.map(
      (String kunci, dynamic nilai) => MapEntry<String, bool>(kunci, rtsBenar(nilai)),
    );

    tabelPembayaran = rtsBenar(balasan['tabel_pembayaran']);
  }

  Future<void> _aksi(
    Map<String, dynamic> kiriman,
    String pesanBerhasil, {
    bool konfirmasi = false,
    String tanya = '',
  }) async {
    if (sedangProses) return;

    if (konfirmasi) {
      final bool? lanjut = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Konfirmasi',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Text(
            tanya,
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'BATAL',
                style: TextStyle(color: rtsTextSecondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsMaroon),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('LANJUTKAN'),
            ),
          ],
        ),
      );

      if (lanjut != true) return;
    }

    setState(() => sedangProses = true);

    try {
      final Map<String, dynamic> balasan = await api.post('kelola_pro.php', kiriman);

      if (!mounted) return;

      setState(() {
        sedangProses = false;
        _bacaDaftar(balasan);
      });

      rtsShowMessage(
        context,
        (balasan['message'] ?? pesanBerhasil).toString(),
        success: true,
      );
    } on ApiException catch (error) {
      if (!mounted) return;

      setState(() => sedangProses = false);

      rtsShowMessage(context, error.message);
    } catch (_) {
      if (!mounted) return;

      setState(() => sedangProses = false);

      rtsShowMessage(context, 'Terjadi gangguan saat menghubungi server.');
    }
  }

  bool get _kolomLengkap =>
      kolom.isNotEmpty && kolom.values.every((bool ada) => ada) && tabelPembayaran;

  @override
  Widget build(BuildContext context) {
    final List<RtsBayarPro> menunggu =
        bayar.where((RtsBayarPro satu) => satu.menunggu).toList();

    final String kunciCari = cari.trim().toLowerCase();

    final List<RtsAkunPro> tampil = kunciCari.isEmpty
        ? daftar
        : daftar
            .where((RtsAkunPro satu) =>
                satu.namaTampil.toLowerCase().contains(kunciCari) ||
                satu.username.toLowerCase().contains(kunciCari) ||
                satu.role.toLowerCase().contains(kunciCari))
            .toList();

    return Scaffold(
      body: Stack(
        children: [
          const RtsBackground(overlayOpacity: 0.93),
          SafeArea(
            child: Column(
              children: [
                _topBar(menunggu.length),
                Expanded(
                  child: RefreshIndicator(
                    color: rtsMaroon,
                    onRefresh: _muat,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      children: [
                        if (!_kolomLengkap && !memuat) ...[
                          RtsCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Kolom/tabel langganan belum lengkap di database. '
                                  'Tekan tombol di bawah sekali saja - proses ini '
                                  'hanya MENAMBAH yang belum ada.',
                                  style: TextStyle(
                                    color: rtsTextSecondary,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: rtsMaroon,
                                    padding: const EdgeInsets.symmetric(vertical: 13),
                                  ),
                                  onPressed: sedangProses
                                      ? null
                                      : () => _aksi(
                                            <String, dynamic>{
                                              'aksi': 'perbarui_database',
                                            },
                                            'Database diperbarui.',
                                          ),
                                  child: const Text(
                                    'PERBARUI DATABASE',
                                    style: TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        if (memuat) ...[
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2.2),
                              ),
                            ),
                          ),
                        ],
                        if (pesanGalat.isNotEmpty) ...[
                          RtsCard(
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    color: rtsMaroon, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    pesanGalat,
                                    style: const TextStyle(
                                      color: rtsTextSecondary,
                                      fontSize: 12,
                                      height: 1.45,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                        ],
                        RtsSectionTitle(
                          menunggu.isEmpty
                              ? 'Pembayaran Menunggu'
                              : 'Pembayaran Menunggu (${menunggu.length})',
                        ),
                        const SizedBox(height: 11),
                        if (menunggu.isEmpty)
                          RtsCard(
                            child: Text(
                              'Belum ada pernyataan pembayaran. Petugas menekan '
                              '"SAYA SUDAH BAYAR" pada halaman Langganan PRO di '
                              'HP-nya, lalu pernyataannya muncul di sini.',
                              style: TextStyle(
                                color: rtsTextSecondary,
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                          )
                        else
                          ...menunggu.map(_kartuBayar),
                        const SizedBox(height: 18),
                        const RtsSectionTitle('Daftar Akun'),
                        const SizedBox(height: 11),
                        TextField(
                          onChanged: (String nilai) => setState(() => cari = nilai),
                          decoration: InputDecoration(
                            hintText: 'Cari nama / username / role',
                            hintStyle: const TextStyle(
                              color: rtsTextSecondary,
                              fontSize: 12.5,
                            ),
                            prefixIcon: const Icon(Icons.search_rounded,
                                size: 20, color: rtsTextSecondary),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: rtsCardBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: rtsCardBorder),
                            ),
                          ),
                          style: const TextStyle(
                            color: rtsTextPrimary,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (!memuat && tampil.isEmpty)
                          const RtsCard(
                            child: Text(
                              'Tidak ada akun yang cocok.',
                              style: TextStyle(color: rtsTextSecondary, fontSize: 12),
                            ),
                          )
                        else
                          ...tampil.map(_kartuAkun),
                        const SizedBox(height: 18),
                        const RtsIklanAsli(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(int jumlahMenunggu) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, color: rtsTextPrimary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Kelola Akun PRO',
                  style: TextStyle(
                    color: rtsTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  jumlahMenunggu > 0
                      ? '$jumlahMenunggu pembayaran menunggu diperiksa'
                      : 'Setujui pembayaran dan atur masa PRO',
                  style: const TextStyle(color: rtsTextSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          if (sedangProses)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            onPressed: memuat ? null : _muat,
            icon: const Icon(Icons.refresh_rounded, color: rtsTextSecondary),
            tooltip: 'Muat ulang',
          ),
        ],
      ),
    );
  }

  Widget _kartuBayar(RtsBayarPro satu) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RtsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xfffff4e0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.receipt_long_rounded,
                      color: rtsAmber, size: 20),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        satu.namaTampil,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: rtsTextPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${satu.username} - ${satu.role} - ${rtsRupiah(satu.jumlah)} '
                        '(${satu.hari} hari)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: rtsTextSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (satu.dibuat.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Dinyatakan: ${satu.dibuat}',
                style: const TextStyle(color: rtsTextSecondary, fontSize: 11),
              ),
            ],
            if (satu.catatan.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Catatan: ${satu.catatan}',
                style: const TextStyle(color: rtsTextSecondary, fontSize: 11),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: rtsGreen,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: sedangProses
                        ? null
                        : () => _aksi(
                              <String, dynamic>{
                                'aksi': 'setujui',
                                'bayar_id': satu.id,
                              },
                              'Pembayaran disetujui.',
                              konfirmasi: true,
                              tanya: 'Setujui pembayaran ${satu.namaTampil} sebesar '
                                  '${rtsRupiah(satu.jumlah)}?\n\nAkun PRO akan aktif '
                                  '${satu.hari} hari ke depan dan seluruh iklan '
                                  'dimatikan. Petugas juga menerima pemberitahuan.',
                            ),
                    child: Text(
                      'SETUJUI + ${satu.hari} HARI',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: rtsTextSecondary,
                      side: const BorderSide(color: rtsCardBorder),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: sedangProses
                        ? null
                        : () => _aksi(
                              <String, dynamic>{
                                'aksi': 'tolak',
                                'bayar_id': satu.id,
                              },
                              'Pernyataan pembayaran ditolak.',
                              konfirmasi: true,
                              tanya: 'Tolak pernyataan pembayaran '
                                  '${satu.namaTampil}?\n\nPetugas tetap GRATIS '
                                  'sampai pembayaran diterima.',
                            ),
                    child: const Text(
                      'TOLAK',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _kartuAkun(RtsAkunPro satu) {
    final bool pro = satu.proAktif;
    final bool trial = satu.trialAktif;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RtsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                RtsFotoProfil(
                  ukuran: 42,
                  alamatPaksa: satu.fotoProfil,
                  inisialPaksa: satu.namaTampil,
                  latarBelakang: const Color(0xfffaf7f5),
                  garisTepi: rtsCardBorder,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        satu.namaTampil,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: rtsTextPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${satu.username} - ${satu.role}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: rtsTextSecondary,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        satu.keteranganMasa,
                        style: const TextStyle(
                          color: rtsTextSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                RtsBadge(
                  satu.label,
                  background: pro
                      ? const Color(0xffe8f5ec)
                      : (trial ? const Color(0xfffff4e0) : const Color(0xfffaecee)),
                  foreground: pro ? rtsGreen : (trial ? rtsAmber : rtsMaroon),
                ),
              ],
            ),
            const SizedBox(height: 11),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tombol(
                  '+${RtsLangganan.sekarang.durasiHari} HARI',
                  rtsGreen,
                  () => _aksi(
                    <String, dynamic>{
                      'aksi': 'aktifkan',
                      'user_id': satu.id,
                      'hari': RtsLangganan.sekarang.durasiHari,
                    },
                    'Masa PRO ditambahkan.',
                    konfirmasi: true,
                    tanya: 'Tambahkan ${RtsLangganan.sekarang.durasiHari} hari PRO '
                        'untuk ${satu.namaTampil}?\n\nBila masa PRO masih berjalan, '
                        'hari barunya DITAMBAHKAN dari tanggal berakhir yang lama.',
                  ),
                ),
                _tombol(
                  '+90 HARI',
                  const Color(0xff1b4d8f),
                  () => _aksi(
                    <String, dynamic>{
                      'aksi': 'aktifkan',
                      'user_id': satu.id,
                      'hari': 90,
                    },
                    'Masa PRO 90 hari ditambahkan.',
                    konfirmasi: true,
                    tanya: 'Tambahkan 90 hari PRO untuk ${satu.namaTampil}?',
                  ),
                ),
                if (satu.trialTersedia)
                  _tombol(
                    'TRIAL ${RtsLangganan.sekarang.trialHari} HARI',
                    rtsAmber,
                    () => _aksi(
                      <String, dynamic>{'aksi': 'trial', 'user_id': satu.id},
                      'Uji coba dimulai.',
                      konfirmasi: true,
                      tanya: 'Mulai uji coba ${RtsLangganan.sekarang.trialHari} hari '
                          'untuk ${satu.namaTampil}? Uji coba hanya dapat dipakai '
                          'sekali untuk setiap akun.',
                    ),
                  ),
                if (pro || trial)
                  _tombol(
                    'HENTIKAN',
                    rtsTextSecondary,
                    () => _aksi(
                      <String, dynamic>{'aksi': 'hentikan', 'user_id': satu.id},
                      'Langganan dihentikan.',
                      konfirmasi: true,
                      tanya: 'Hentikan langganan ${satu.namaTampil}?\n\nAkun akan '
                          'kembali GRATIS dan iklan tampil kembali.',
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _tombol(String tulisan, Color warna, VoidCallback aksi) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: warna,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: sedangProses ? null : aksi,
      child: Text(
        tulisan,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
      ),
    );
  }
}
