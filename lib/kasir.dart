// RTS-PANEL-ROUND: 18K - penanda putaran RTS Panel (diperiksa PERIKSA_KODE_APLIKASI.ps1)
// ============================================================================
//  RTS PANEL BY BENE - FITUR PRO : BARANG BAWAAN & KASIR
//  Berkas : lib/kasir.dart
//  Versi  : 1   (1 Oktober 2026)
//
//  ISI BERKAS INI (semua tampilan kasir, dipisah dari main.dart supaya
//  pembaruan berikutnya cukup mengganti satu berkas):
//
//     1. RtsBarangBawaanPage  - 3 tab: PRODUK, STOK, RIWAYAT
//     2. RtsKasirPage         - kasir: scan barcode, keranjang, bayar
//                               CASH / UTANG / TITIP, simpan nota
//     3. RtsNotaPage          - riwayat nota + cetak ulang + batalkan
//     4. RtsPiutangPage       - daftar utang & titip, angsuran sampai lunas
//     5. RtsPrinterPage       - hubungkan printer Bluetooth, UJI CETAK,
//                               dan template struk yang dapat diedit bebas
//     6. RtsPilihBarcodePage  - pemindai barcode memakai kamera HP
//     7. RtsPilihCustomerPage - memilih toko dari Master Customer
//
//  CATATAN PENTING
//  ---------------
//  - Berkas ini TIDAK memanggil berkas lain di dalam proyek (hanya paket
//    Flutter), supaya tidak ada lingkaran impor dengan main.dart.
//    Alamat server dan token dikirim dari main.dart saat halaman dibuka.
//  - Seluruh nama dan pesan memakai Bahasa Indonesia yang mudah dibaca sales.
//  - Printer yang didukung: thermal 58 mm / 80 mm berbahasa ESC/POS melalui
//    Bluetooth (RPP02, Xprinter P323B, EPPOS, Mypos, dan sejenisnya).
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
// mobile_scanner diberi nama pendek "ms" karena paket ini juga memuat
// kelas bernama Barcode - sama dengan nama kelas pada paket printer
// (esc_pos_utils_plus). Bila keduanya diimpor tanpa nama pendek, Flutter
// melaporkan galat "'Barcode' is imported from both ...". Dengan "ms",
// semua nama dari paket pemindai ditulis ms.Nama sehingga tidak bentrok.
import 'package:mobile_scanner/mobile_scanner.dart' as ms;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'kasir_lokal.dart';

/* ------------------------------------------------------------------------- */
/* WARNA - sama dengan halaman lain supaya tampilannya seragam               */
/* ------------------------------------------------------------------------- */

const Color rtsKsMaroon = Color(0xff8e1420);
const Color rtsKsMaroonDark = Color(0xff640c15);
const Color rtsKsHijau = Color(0xff1e7a45);
const Color rtsKsKuning = Color(0xffb3761b);
const Color rtsKsMerah = Color(0xffc0392b);
const Color rtsKsTeks = Color(0xff201c19);
const Color rtsKsTeks2 = Color(0xff7c736d);
const Color rtsKsGaris = Color(0xffece5de);
const Color rtsKsLatar = Color(0xfff8f5f1);

/* ------------------------------------------------------------------------- */
/* BANTUAN                                                                   */
/* ------------------------------------------------------------------------- */

/// Membaca angka dari nilai apa pun (angka, teks, null).
double rtsKsAngka(dynamic nilai) {
  if (nilai is num) return nilai.toDouble();

  final String teks = '${nilai ?? ''}'.replaceAll(RegExp(r'[^0-9,.\-]'), '');

  if (teks.isEmpty) return 0;

  if (teks.contains(',')) {
    return double.tryParse(teks.replaceAll('.', '').replaceAll(',', '.')) ?? 0;
  }

  return double.tryParse(teks) ?? 0;
}

int rtsKsBulat(dynamic nilai) => rtsKsAngka(nilai).round();

/// Tulisan rupiah untuk ditampilkan, contoh: 32000 -> "32.000".
String rtsKsUang(dynamic nilai) {
  final double angka = rtsKsAngka(nilai);
  final bool bulat = (angka - angka.round()).abs() < 0.005;
  final bool negatif = angka < 0;

  final String teks = bulat
      ? angka.abs().round().toString()
      : angka.abs().toStringAsFixed(2).replaceAll('.', ',');

  final List<String> bagian = teks.split(',');

  final String kiri = _titikRibuan(bagian[0]);
  final String hasil = bagian.length > 1 ? '$kiri,${bagian[1]}' : kiri;

  return negatif ? '-$hasil' : hasil;
}

/// Menambahkan titik sebagai pemisah ribuan: 32000 -> 32.000
String _titikRibuan(String angka) {
  final StringBuffer hasil = StringBuffer();
  final int panjang = angka.length;

  for (int i = 0; i < panjang; i++) {
    final int sisa = panjang - i;

    hasil.write(angka[i]);

    if (sisa > 1 && sisa % 3 == 1) hasil.write('.');
  }

  return hasil.toString();
}

/// Mengubah tulisan rupiah kembali menjadi angka, contoh "32.000" -> 32000.
double rtsKsDariUang(String teks) => rtsKsAngka(teks);

/// Tanggal + jam sampai detik, contoh: 01-10-2026 14:22:07.
String rtsKsWaktuLengkap(String waktu) {
  final DateTime? t = DateTime.tryParse(waktu.replaceAll(' ', 'T'));

  if (t == null) return waktu;

  return '${_dua(t.day)}-${_dua(t.month)}-${t.year} '
      '${_dua(t.hour)}:${_dua(t.minute)}:${_dua(t.second)}';
}

/// Tanggal ringkas, contoh: 01-10-2026.
String rtsKsTanggal(String waktu) {
  final DateTime? t = DateTime.tryParse(waktu.replaceAll(' ', 'T'));

  if (t == null) return waktu;

  return '${_dua(t.day)}-${_dua(t.month)}-${t.year}';
}

String _dua(int angka) => angka < 10 ? '0$angka' : '$angka';

/// Menyambung dua keterangan: yang kedua hanya ditulis bila ada isinya.
String rtsKsSambung(String utama, String tambahan, {String pemisah = ' - '}) =>
    tambahan.trim().isEmpty ? utama : '$utama$pemisah$tambahan';

/// Keterangan satu barang pada nota, contoh: "Sampoerna Mild (2 pack)".
String rtsKsItemTeks(Map<dynamic, dynamic> item) {
  final String satuan = '${item['satuan']}'.toUpperCase() == 'BATANG'
      ? 'batang'
      : 'pack';
  final String jumlah =
      satuan == 'batang' ? '${item['batang']}' : '${item['pack']}';

  return '${item['nama_produk']} ($jumlah $satuan)';
}

/// Pesan singkat di bawah layar.
void rtsKsPesan(BuildContext context, String teks, {bool galat = false}) {
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(teks),
      backgroundColor: galat ? rtsKsMerah : rtsKsHijau,
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: galat ? 5 : 3),
    ),
  );
}

/* ------------------------------------------------------------------------- */
/* API KASIR                                                                 */
/* ------------------------------------------------------------------------- */

/// Catatan: kelas kesalahan RtsKasirGalat kini berada pada berkas
/// kasir_lokal.dart, sebab mesin lokal (SQLite di dalam HP) yang memakainya.
/// Berkas ini memakainya lewat impor di atas.

/// Penghubung halaman kasir ke MESIN LOKAL.
///
/// Sejak 1 Oktober 2026 seluruh data kasir (stok, penjualan, piutang,
/// template struk) disimpan DI DALAM HP memakai SQLite. Karena itu kelas ini
/// kini hanya meneruskan perintah ke RtsKasirLokal - seluruh halaman kasir
/// tidak perlu diubah dan tetap bekerja seperti sebelumnya.
///
/// Internet hanya dipakai untuk: masuk (login), memeriksa status Akun PRO
/// (hasilnya disimpan untuk pemakaian luring), dan Sinkron Produk.
class RtsKasirApi {
  RtsKasirApi({
    required this.baseUrl,
    required this.token,
    Map<String, dynamic>? pengguna,
  }) {
    // Keterangan akun langsung disimpan (tidak ditunggu) supaya setiap
    // perintah berikutnya sudah mengenal pemilik datanya.
    unawaited(
      RtsKasirLokal.aku.atur(
        baseUrl: baseUrl,
        token: token,
        pengguna: pengguna,
      ),
    );
  }

  final String baseUrl;
  final String token;

  Future<Map<String, dynamic>> kirim(
    String aksi, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) {
    return RtsKasirLokal.aku.kirim(aksi, data);
  }
}

/* ------------------------------------------------------------------------- */
/* MODEL SEDERHANA                                                           */
/* ------------------------------------------------------------------------- */

/// Satu produk barang bawaan.
class RtsProduk {
  RtsProduk({
    required this.id,
    required this.nama,
    required this.merek,
    required this.barcodePack,
    required this.isiPerPack,
    required this.hargaPack,
    required this.hargaBatang,
    required this.stokPack,
    required this.stokBatang,
    this.sku = '',
    this.aktif = true,
    this.catatan = '',
  });

  final int id;
  final String nama;
  final String merek;
  final String barcodePack;

  /// Kode produk pada daftar produk bersama (boleh dikosongkan).
  final String sku;

  /// Barcode hanya ada pada bungkus (pack). Tidak ada barcode batang.
  final int isiPerPack;
  final double hargaPack;
  final double hargaBatang;
  final int stokPack;
  final int stokBatang;
  final bool aktif;
  final String catatan;

  String get stokTeks => rtsKsStokTeks(stokPack, stokBatang);

  String get ringkas => isiPerPack > 0
      ? 'Isi $isiPerPack batang - Rp ${rtsKsUang(hargaPack)}/pack'
      : 'Rp ${rtsKsUang(hargaPack)}/pack';

  factory RtsProduk.fromJson(Map<String, dynamic> j) {
    return RtsProduk(
      id: rtsKsBulat(j['id']),
      nama: '${j['nama'] ?? ''}',
      merek: '${j['merek'] ?? ''}',
      barcodePack: '${j['barcode_pack'] ?? ''}',
      sku: '${j['sku'] ?? ''}',
      isiPerPack: rtsKsBulat(j['isi_per_pack']),
      hargaPack: rtsKsAngka(j['harga_pack']),
      hargaBatang: rtsKsAngka(j['harga_batang']),
      stokPack: rtsKsBulat(j['stok_pack']),
      stokBatang: rtsKsBulat(j['stok_batang']),
      aktif: j['aktif'] != false,
      catatan: '${j['catatan'] ?? ''}',
    );
  }
}

/// Tulisan stok, contoh "10 pack 3 batang".
String rtsKsStokTeks(int pack, int batang) {
  final List<String> bagian = <String>[];

  if (pack != 0) bagian.add('$pack pack');
  if (batang != 0 || pack == 0) bagian.add('$batang batang');

  return bagian.join(' ');
}

/// Satu barang di dalam keranjang kasir.
class RtsKeranjang {
  RtsKeranjang({required this.produk, this.pack = 0, this.batang = 0});

  final RtsProduk produk;
  int pack;
  int batang;

  double get subtotal =>
      pack * produk.hargaPack + batang * produk.hargaBatang;

  int get totalBatang => pack * produk.isiPerPack + batang;

  bool get kosong => pack <= 0 && batang <= 0;
}

/* ------------------------------------------------------------------------- */
/* KUNCI FITUR PRO                                                           */
/* ------------------------------------------------------------------------- */

class RtsKunciPro extends StatelessWidget {
  const RtsKunciPro({super.key, required this.pesan});

  final String pesan;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.workspace_premium_rounded,
                size: 72, color: rtsKsKuning),
            const SizedBox(height: 16),
            const Text(
              'Fitur PRO',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: rtsKsTeks,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              pesan.isEmpty
                  ? 'Fitur Barang Bawaan & Kasir tersedia untuk Akun PRO.'
                  : pesan,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: rtsKsTeks2),
            ),
            const SizedBox(height: 18),
            const Text(
              'Buka menu "Langganan PRO" pada halaman Beranda untuk '
              'mengaktifkannya. Masa uji coba 7 hari GRATIS untuk akun yang '
              'belum pernah mencoba.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: rtsKsTeks2),
            ),
          ],
        ),
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* CETAK STRUK (ESC/POS lewat BLUETOOTH)                                     */
/* ------------------------------------------------------------------------- */

/// Pengaturan printer yang disimpan pada HP (alamat Bluetooth printer).
class RtsPrinter {
  static const String _kunciMac = 'rts_ks_printer_mac';
  static const String _kunciNama = 'rts_ks_printer_nama';

  /// Membaca printer yang tersimpan.
  static Future<Map<String, String>> tersimpan() async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();

      return <String, String>{
        'mac': p.getString(_kunciMac) ?? '',
        'nama': p.getString(_kunciNama) ?? '',
      };
    } catch (_) {
      return <String, String>{'mac': '', 'nama': ''};
    }
  }

  /// Menyimpan pilihan printer.
  static Future<void> simpan(String mac, String nama) async {
    try {
      final SharedPreferences p = await SharedPreferences.getInstance();
      await p.setString(_kunciMac, mac);
      await p.setString(_kunciNama, nama);
    } catch (_) {
      // gagal menyimpan tidak menghalangi pencetakan
    }
  }

  /// Meminta izin Bluetooth (wajib pada Android 12 ke atas).
  static Future<bool> izinBluetooth() async {
    try {
      final bool sudah = await PrintBluetoothThermal.isPermissionBluetoothGranted;

      if (sudah) return true;

      final PermissionStatus status = await Permission.bluetoothConnect.request();

      return status.isGranted;
    } catch (_) {
      return true;
    }
  }

  /// Menyambung ke printer. Bila mac kosong, dipakai printer yang tersimpan.
  static Future<bool> sambung([String mac = '']) async {
    try {
      final bool hidup = await PrintBluetoothThermal.bluetoothEnabled;

      if (!hidup) return false;

      String alamat = mac;

      if (alamat.isEmpty) {
        alamat = (await tersimpan())['mac'] ?? '';
      }

      if (alamat.isEmpty) return false;

      final bool sudah = await PrintBluetoothThermal.connectionStatus;

      if (sudah) return true;

      return await PrintBluetoothThermal.connect(macPrinterAddress: alamat);
    } catch (_) {
      return false;
    }
  }
}

/// Penyusun dan pengirim struk.
class RtsStruk {
  /// Menyusun perintah cetak (ESC/POS) dari sebuah nota dan template.
  static Future<List<int>> bangun(
    Map<String, dynamic> nota,
    Map<String, dynamic> template,
  ) async {
    final CapabilityProfile profile = await CapabilityProfile.load();

    final int lebarMm = rtsKsBulat(template['lebar_kertas'] ?? 58);
    final PaperSize ukuran = lebarMm >= 76 ? PaperSize.mm80 : PaperSize.mm58;

    final Generator g = Generator(ukuran, profile);
    final List<int> bytes = <int>[];

    final String huruf = '${template['ukuran_huruf'] ?? 'SEDANG'}'.toUpperCase();
    final PosTextSize besar = huruf == 'BESAR'
        ? PosTextSize.size2
        : (huruf == 'KECIL' ? PosTextSize.size1 : PosTextSize.size1);

    final String garisTanda = '${template['garis'] ?? '-'}';
    final String garisIsi = garisTanda.isEmpty ? '-' : garisTanda;

    final String judul = '${template['judul'] ?? 'RTS PANEL'}';

    bytes.addAll(g.text(
      judul,
      styles: PosStyles(
        align: PosAlign.center,
        bold: template['header_tebal'] != 0,
        height: besar,
        width: besar,
      ),
    ));

    for (final String kunci in <String>['baris1', 'baris2', 'baris3']) {
      final String isi = '${template[kunci] ?? ''}'.trim();

      if (isi.isNotEmpty) {
        bytes.addAll(g.text(isi, styles: const PosStyles(align: PosAlign.center)));
      }
    }

    bytes.addAll(_garis(g, 32, garisIsi));

    // Keterangan nota
    bytes.addAll(g.text('No   : ${nota['nomor'] ?? '-'}'));
    bytes.addAll(g.text('Waktu: ${rtsKsWaktuLengkap('${nota['tanggal'] ?? ''}')}'));
    bytes.addAll(g.text('Sales: ${nota['nama_sales'] ?? '-'}'));

    final String customer = '${nota['nama_customer'] ?? ''}'.trim();

    if (customer.isNotEmpty) {
      bytes.addAll(g.text('Toko : $customer'));
    }

    final String idCustomer = '${nota['customer_id'] ?? ''}'.trim();

    if (idCustomer.isNotEmpty) {
      bytes.addAll(g.text('ID   : $idCustomer'));
    }

    final String hp = '${nota['hp_customer'] ?? ''}'.trim();

    if (hp.isNotEmpty && template['tampilkan_hp'] != 0) {
      bytes.addAll(g.text('HP   : $hp'));
    }

    bytes.addAll(_garis(g, 32, garisIsi));

    // Barang
    final List<dynamic> items =
        (nota['items'] is List) ? nota['items'] as List<dynamic> : <dynamic>[];

    for (final dynamic item in items) {
      if (item is! Map) continue;

      final String satuan =
          '${item['satuan'] ?? 'PACK'}'.toUpperCase() == 'BATANG' ? 'batang' : 'pack';
      final int jumlah = satuan == 'batang'
          ? rtsKsBulat(item['batang'])
          : rtsKsBulat(item['pack']);
      final double harga = rtsKsAngka(item['harga_satuan']);
      final double subtotal = rtsKsAngka(item['subtotal']);

      bytes.addAll(g.text('${item['nama_produk'] ?? ''}'));

      bytes.addAll(g.row(<PosColumn>[
        PosColumn(
          text: '$jumlah $satuan x Rp ${rtsKsUang(harga)}',
          width: 8,
        ),
        PosColumn(
          text: 'Rp ${rtsKsUang(subtotal)}',
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]));
    }

    bytes.addAll(_garis(g, 32, garisIsi));

    bytes.addAll(g.row(<PosColumn>[
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: 'Rp ${rtsKsUang(nota['total'])}',
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]));

    final String metode = '${nota['metode'] ?? 'CASH'}'.toUpperCase();

    if (template['tampilkan_metode'] != 0) {
      if (metode == 'CASH') {
        bytes.addAll(g.row(<PosColumn>[
          PosColumn(text: 'TUNAI', width: 6),
          PosColumn(
            text: 'Rp ${rtsKsUang(nota['bayar'])}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]));
        bytes.addAll(g.row(<PosColumn>[
          PosColumn(text: 'KEMBALI', width: 6),
          PosColumn(
            text: 'Rp ${rtsKsUang(nota['kembali'])}',
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]));
      } else {
        bytes.addAll(g.text(metode == 'UTANG'
            ? 'Dibayar kemudian (UTANG)'
            : 'Barang dititipkan (TITIP)'));

        final Map<String, dynamic>? piutang =
            (nota['piutang'] is Map) ? (nota['piutang'] as Map).cast<String, dynamic>() : null;

        if (piutang != null && '${piutang['jatuh_tempo'] ?? ''}'.isNotEmpty) {
          bytes.addAll(g.text(
            'Jatuh tempo: ${rtsKsTanggal('${piutang['jatuh_tempo']}')}',
          ));
        }
      }
    }

    // Barcode nomor nota (bila printer mendukung).
    //
    // CATATAN PENTING dari paket printer (esc_pos_utils_plus):
    //   Isi barcode HARUS berupa DAFTAR KARAKTER, bukan tulisan biasa, dan
    //   WAJIB diawali penanda jenis huruf:
    //       {A = huruf besar/angka, {B = huruf biasa, {C = angka saja
    //   Karena itu nomor nota disusun menjadi "{BKS-20261001-0001" lalu
    //   dipecah menjadi huruf satu per satu sebelum dikirim ke printer.
    //   (Kode lama mengirim tulisan biasa sehingga Flutter menampilkan galat
    //    "The argument type 'String' can't be assigned to the parameter type
    //    'List<dynamic>'".)
    if (template['tampilkan_barcode'] != 0) {
      bytes.addAll(g.feed(1));

      try {
        final String nomorNota = '${nota['nomor'] ?? ''}'.trim();

        if (nomorNota.length >= 2) {
          final String isiBarcode = '{B$nomorNota';

          bytes.addAll(g.barcode(Barcode.code128(isiBarcode.split(''))));
        }
      } catch (_) {
        // printer tidak mendukung barcode: bagian ini dilewati
      }
    }

    if (template['tampilkan_ttd'] != 0) {
      bytes.addAll(g.feed(1));
      bytes.addAll(g.text('Tanda tangan: ______________'));
    }

    bytes.addAll(_garis(g, 32, garisIsi));

    for (final String kunci in <String>['footer1', 'footer2', 'footer3']) {
      final String isi = '${template[kunci] ?? ''}'.trim();

      if (isi.isNotEmpty) {
        bytes.addAll(g.text(isi, styles: const PosStyles(align: PosAlign.center)));
      }
    }

    final String catatanKaki = '${template['catatan_kaki'] ?? ''}'.trim();

    if (catatanKaki.isNotEmpty) {
      bytes.addAll(g.feed(1));
      bytes.addAll(g.text(catatanKaki, styles: const PosStyles(align: PosAlign.center)));
    }

    bytes.addAll(g.feed(2));
    bytes.addAll(g.cut());

    return bytes;
  }

  static List<int> _garis(Generator g, int jumlah, String tanda) {
    final String isi = List<String>.filled(jumlah, tanda).join();

    return g.text(isi);
  }

  /// Mengirim struk ke printer Bluetooth.
  ///
  /// Mengembalikan keterangan kosong bila berhasil, atau pesan kesalahan
  /// yang dapat langsung ditampilkan kepada sales.
  static Future<String> cetak(
    Map<String, dynamic> nota,
    Map<String, dynamic> template,
  ) async {
    try {
      if (!await RtsPrinter.izinBluetooth()) {
        return 'Izin Bluetooth belum diberikan. Buka Pengaturan HP - Aplikasi - '
            'RTS Panel - Izin - Perangkat di sekitar (Bluetooth) - Izinkan.';
      }

      if (!await RtsPrinter.sambung()) {
        return 'Printer belum tersambung. Buka menu "Printer & Struk" lalu '
            'hubungkan printer terlebih dahulu.';
      }

      final List<int> bytes = await bangun(nota, template);
      final int salinan = rtsKsBulat(template['jumlah_salinan'] ?? 1);

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
}

/* ------------------------------------------------------------------------- */
/* BARANG BAWAAN - 3 TAB (PRODUK, STOK, RIWAYAT)                             */
/* ------------------------------------------------------------------------- */

class RtsBarangBawaanPage extends StatefulWidget {
  const RtsBarangBawaanPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsBarangBawaanPage> createState() => _RtsBarangBawaanPageState();
}

class _RtsBarangBawaanPageState extends State<RtsBarangBawaanPage>
    with SingleTickerProviderStateMixin {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);
  late final TabController _tab = TabController(length: 3, vsync: this);

  final TextEditingController _cariProduk = TextEditingController();

  List<RtsProduk> _produk = <RtsProduk>[];
  List<Map<String, dynamic>> _riwayat = <Map<String, dynamic>>[];
  bool _memuat = true;
  String _galat = '';
  bool _perluPro = false;
  bool _perluSiap = false;
  String _nilaiStok = '0';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cariProduk.dispose();
    _tab.dispose();
    super.dispose();
  }

  bool get _pengelola =>
      <String>['ADMIN', 'ASS'].contains('${widget.pengguna['role']}'.toUpperCase());

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('stok_daftar');

      final List<dynamic> isi =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      final List<RtsProduk> daftar = isi
          .whereType<Map>()
          .map((Map<dynamic, dynamic> e) =>
              RtsProduk.fromJson(e.cast<String, dynamic>()))
          .toList();

      final Map<String, dynamic> riwayat = await _api.kirim('stok_riwayat');
      final List<dynamic> isiRiwayat = (riwayat['items'] is List)
          ? riwayat['items'] as List<dynamic>
          : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _produk = daftar;
        _riwayat = isiRiwayat
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
        _nilaiStok = '${hasil['nilai_teks'] ?? '0'}';
        _memuat = false;
      });
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
        _perluSiap = e.perluSiap;
      });
    }
  }

  /// Menghapus (menolkkan) stok satu produk.
  Future<void> _hapusStok(RtsProduk produk) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus stok?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Stok ${produk.nama} yang sekarang ${produk.stokTeks} akan dihapus '
          '(menjadi 0).\n\nRiwayatnya tetap tercatat, dan produknya TIDAK '
          'dihapus dari daftar produk.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS STOK'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('stok_hapus', <String, dynamic>{
        'produk_id': produk.id,
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Stok dihapus.'}');
      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Menghapus stok SELURUH produk (khusus ADMIN / ASS).
  Future<void> _hapusSemuaStok() async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Hapus SEMUA stok?',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text(
          'Seluruh sisa stok pada HP ini akan dijadikan 0. Riwayatnya tetap '
          'tercatat. Daftar produk tidak terhapus.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('HAPUS SEMUA'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('stok_hapus_semua');

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Stok dihapus.'}');
      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Membuka halaman cadangan (backup) & pulihkan.
  void _bukaCadangan() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RtsCadanganPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          pengguna: widget.pengguna,
        ),
      ),
    );
  }

  Future<void> _siapkanData() async {
    try {
      final Map<String, dynamic> hasil = await _api.kirim('siapkan');

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Data kasir disiapkan.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _ubahStok(RtsProduk produk, {required bool masuk}) async {
    final TextEditingController pack = TextEditingController(text: '0');
    final TextEditingController batang = TextEditingController(text: '0');
    final TextEditingController keterangan = TextEditingController();

    String jenis = masuk ? 'MASUK' : 'RUSAK';

    final bool? jalan = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) ubah) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: Text(
              masuk ? 'Barang Masuk' : 'Barang Keluar',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    produk.nama,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sisa saat ini: ${produk.stokTeks}',
                    style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                  ),
                  const SizedBox(height: 12),
                  if (!masuk)
                    DropdownButtonFormField<String>(
                      initialValue: jenis,
                      decoration: const InputDecoration(
                        labelText: 'Jenis',
                        border: OutlineInputBorder(),
                      ),
                      items: const <DropdownMenuItem<String>>[
                        DropdownMenuItem<String>(
                          value: 'RUSAK',
                          child: Text('Rusak / pecah'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'KEMBALI',
                          child: Text('Kembali ke gudang'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'OPNAME',
                          child: Text('Hasil hitung fisik (opname)'),
                        ),
                      ],
                      onChanged: (String? nilai) {
                        if (nilai != null) ubah(() => jenis = nilai);
                      },
                    ),
                  if (!masuk) const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: pack,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Pack',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: batang,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Batang',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: keterangan,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan (opsional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (jenis == 'OPNAME' && !masuk)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Catatan: pada opname, angka yang diisi adalah SISA '
                        'sebenarnya hasil hitung.',
                        style: TextStyle(fontSize: 12, color: rtsKsKuning),
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
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('SIMPAN'),
              ),
            ],
          );
        },
      ),
    );

    if (jalan != true) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('stok_gerak', <String, dynamic>{
        'produk_id': produk.id,
        'jenis': masuk ? 'MASUK' : jenis,
        'pack': rtsKsBulat(pack.text),
        'batang': rtsKsBulat(batang.text),
        'keterangan': keterangan.text.trim(),
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Stok diperbarui.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _formProduk([RtsProduk? produk]) async {
    final bool? tersimpan = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => RtsFormProdukPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          produk: produk,
        ),
      ),
    );

    if (tersimpan == true) _muat();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Barang Bawaan'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Server & Cadangan',
            icon: const Icon(Icons.cloud_sync_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RtsCadanganPage(
                  baseUrl: widget.baseUrl,
                  token: widget.token,
                  pengguna: widget.pengguna,
                ),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const <Widget>[
            Tab(text: 'PRODUK'),
            Tab(text: 'STOK'),
            Tab(text: 'RIWAYAT'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        onPressed: () => _formProduk(),
        icon: const Icon(Icons.add),
        label: const Text('Produk'),
      ),
      body: _bangunIsi(),
    );
  }

  Widget _bangunIsi() {
    if (_perluPro) {
      return RtsKunciPro(pesan: _galat);
    }

    if (_memuat) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_perluSiap) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.storage_rounded, size: 64, color: rtsKsMaroon),
              const SizedBox(height: 14),
              const Text(
                'Data kasir belum disiapkan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                _galat,
                textAlign: TextAlign.center,
                style: const TextStyle(color: rtsKsTeks2),
              ),
              const SizedBox(height: 18),
              if (_pengelola)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                  onPressed: _siapkanData,
                  icon: const Icon(Icons.playlist_add_check_rounded),
                  label: const Text('SIAPKAN DATA KASIR'),
                )
              else
                const Text(
                  'Minta ADMIN membuka menu ini pada HP-nya, lalu tekan '
                  '"SIAPKAN DATA KASIR".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: rtsKsTeks2),
                ),
            ],
          ),
        ),
      );
    }

    if (_galat.isNotEmpty && _produk.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.cloud_off_rounded, size: 56, color: rtsKsTeks2),
              const SizedBox(height: 12),
              Text(_galat, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _muat, child: const Text('COBA LAGI')),
            ],
          ),
        ),
      );
    }

    return TabBarView(
      controller: _tab,
      children: <Widget>[
        _tabProduk(),
        _tabStok(),
        _tabRiwayat(),
      ],
    );
  }

  Widget _tabProduk() {
    final String cari = _cariProduk.text.trim().toLowerCase();
    final List<RtsProduk> daftar = cari.isEmpty
        ? _produk
        : _produk
            .where((RtsProduk p) =>
                p.nama.toLowerCase().contains(cari) ||
                p.merek.toLowerCase().contains(cari) ||
                p.sku.toLowerCase().contains(cari) ||
                p.barcodePack.contains(cari))
            .toList();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: <Widget>[
          _kartu(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Row(
                    children: <Widget>[
                      Icon(Icons.storefront_outlined, color: rtsKsMaroon),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Daftar Produk Bersama',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Produk di sini dipakai BERSAMA semua user. Tambah / ubah '
                    'produk dari HP mana saja; daftar seluruh HP disamakan '
                    'lewat menu SINKRONISASI pada menu utama (tombol '
                    'SINKRONKAN SEKARANG). Harga berlaku sama untuk semua sales.',
                    style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _cariProduk,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Cari nama, merek, SKU, atau barcode bungkus',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _cariProduk.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _cariProduk.clear()),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_produk.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Belum ada produk pada daftar di HP ini.\n\n'
                'Buka MENU UTAMA -> SINKRONISASI -> SINKRONKAN SEKARANG '
                'untuk mengunduh daftar produk bersama dari server, atau '
                'tekan tombol "Produk" di bawah untuk menambah produk baru.',
                textAlign: TextAlign.center,
                style: TextStyle(color: rtsKsTeks2),
              ),
            )
          else if (daftar.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Tidak ada produk yang cocok dengan pencarian.',
                textAlign: TextAlign.center,
                style: TextStyle(color: rtsKsTeks2),
              ),
            ),
          for (final RtsProduk p in daftar)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _kartu(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  leading: CircleAvatar(
                    backgroundColor: rtsKsMaroon.withValues(alpha: 0.10),
                    child: const Icon(Icons.inventory_2_outlined, color: rtsKsMaroon),
                  ),
                  title: Text(
                    p.nama,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(p.ringkas),
                      if (p.sku.isNotEmpty)
                        Text(
                          'SKU: ${p.sku}',
                          style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                      if (p.barcodePack.isNotEmpty)
                        Text(
                          'Barcode bungkus: ${p.barcodePack}',
                          style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                    ],
                  ),
                  trailing: IconButton(
                    tooltip: 'Ubah produk',
                    icon: const Icon(Icons.edit_outlined, color: rtsKsMaroon),
                    onPressed: () => _formProduk(p),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabStok() {
    final List<RtsProduk> ada = _produk
        .where((RtsProduk p) => p.stokPack > 0 || p.stokBatang > 0)
        .toList();

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: <Widget>[
          _kartu(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.shopping_bag_outlined, color: rtsKsMaroon),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${ada.length} produk dibawa',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Nilai stok: Rp $_nilaiStok',
                          style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Stok tersimpan DI DALAM HP (jalan tanpa internet) '
                          'dan dapat dihapus, dicadangkan, serta dipulihkan.',
                          style: TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          _kartu(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'CADANGAN DATA KASIR',
                    style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Cadangkan seluruh data kasir di HP ini (produk, stok, nota, '
                    'piutang, template struk) menjadi satu berkas, atau '
                    'pulihkan dari berkas cadangan.',
                    style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _bukaCadangan,
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('CADANGKAN'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _bukaCadangan,
                          icon: const Icon(Icons.settings_backup_restore, size: 18),
                          label: const Text('PULIHKAN'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (_pengelola)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: rtsKsMerah,
                side: const BorderSide(color: rtsKsMerah),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _hapusSemuaStok,
              icon: const Icon(Icons.delete_sweep_outlined, size: 18),
              label: const Text('HAPUS SEMUA STOK (JADIKAN 0)'),
            ),
          const SizedBox(height: 10),
          if (_produk.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Belum ada produk. Buka MENU UTAMA -> SINKRONISASI -> '
                'SINKRONKAN SEKARANG untuk mengunduh daftar produk bersama.',
                textAlign: TextAlign.center,
                style: TextStyle(color: rtsKsTeks2),
              ),
            ),
          for (final RtsProduk p in _produk)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _kartu(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.nama,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Sisa: ${p.stokTeks}',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: (p.stokPack > 0 || p.stokBatang > 0)
                              ? rtsKsHijau
                              : rtsKsMerah,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: rtsKsHijau,
                                side: const BorderSide(color: rtsKsHijau),
                              ),
                              onPressed: () => _ubahStok(p, masuk: true),
                              icon: const Icon(Icons.add_box_outlined, size: 18),
                              label: const Text('MASUK'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: rtsKsKuning,
                                side: const BorderSide(color: rtsKsKuning),
                              ),
                              onPressed: () => _ubahStok(p, masuk: false),
                              icon: const Icon(Icons.remove_circle_outline, size: 18),
                              label: const Text('KELUAR'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: rtsKsMerah),
                          onPressed: (p.stokPack == 0 && p.stokBatang == 0)
                              ? null
                              : () => _hapusStok(p),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('HAPUS STOK PRODUK INI'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tabRiwayat() {
    if (_riwayat.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada perubahan stok.',
          style: TextStyle(color: rtsKsTeks2),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _riwayat.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext ctx, int i) {
          final Map<String, dynamic> r = _riwayat[i];

          return _kartu(
            child: ListTile(
              title: Text(
                '${r['nama_produk'] ?? '-'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('${r['jenis'] ?? ''} - ${r['perubahan'] ?? ''}'),
                  Text(
                    'Sisa: ${r['saldo'] ?? ''}',
                    style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                  ),
                  if ('${r['keterangan'] ?? ''}'.trim().isNotEmpty)
                    Text(
                      '${r['keterangan']}',
                      style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                    ),
                ],
              ),
              trailing: Text(
                rtsKsWaktuLengkap('${r['tanggal'] ?? ''}'),
                style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
                textAlign: TextAlign.right,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _kartu({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rtsKsGaris),
      ),
      child: child,
    );
  }
}

/* ------------------------------------------------------------------------- */
/* FORM PRODUK                                                               */
/* ------------------------------------------------------------------------- */

class RtsFormProdukPage extends StatefulWidget {
  const RtsFormProdukPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.produk,
  });

  final String baseUrl;
  final String token;
  final RtsProduk? produk;

  @override
  State<RtsFormProdukPage> createState() => _RtsFormProdukPageState();
}

class _RtsFormProdukPageState extends State<RtsFormProdukPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

  final TextEditingController _nama = TextEditingController();
  final TextEditingController _merek = TextEditingController();
  final TextEditingController _sku = TextEditingController();
  final TextEditingController _barcodePack = TextEditingController();
  final TextEditingController _isi = TextEditingController(text: '16');
  final TextEditingController _hargaPack = TextEditingController();
  final TextEditingController _hargaBatang = TextEditingController();
  final TextEditingController _catatan = TextEditingController();

  bool _simpan = false;

  @override
  void initState() {
    super.initState();

    final RtsProduk? p = widget.produk;

    if (p != null) {
      _nama.text = p.nama;
      _merek.text = p.merek;
      _sku.text = p.sku;
      _barcodePack.text = p.barcodePack;
      _isi.text = '${p.isiPerPack}';
      _hargaPack.text = p.hargaPack > 0 ? rtsKsUang(p.hargaPack) : '';
      _hargaBatang.text = p.hargaBatang > 0 ? rtsKsUang(p.hargaBatang) : '';
      _catatan.text = p.catatan;
    }
  }

  @override
  void dispose() {
    _nama.dispose();
    _merek.dispose();
    _sku.dispose();
    _barcodePack.dispose();
    _isi.dispose();
    _hargaPack.dispose();
    _hargaBatang.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _pindai(TextEditingController tujuan) async {
    // Izin kamera diminta lebih dahulu supaya sales langsung tahu bila ditolak.
    try {
      final PermissionStatus izin = await Permission.camera.request();

      if (!izin.isGranted) {
        if (!mounted) return;

        rtsKsPesan(
          context,
          'Izin kamera belum diberikan. Buka Pengaturan HP - Aplikasi - '
          'RTS Panel - Izin - Kamera - Izinkan.',
          galat: true,
        );

        return;
      }
    } catch (_) {
      // bila pemeriksaan izin gagal, pemindai tetap dibuka
    }

    if (!mounted) return;

    final String? kode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => const RtsPilihBarcodePage(),
      ),
    );

    if (kode != null && kode.isNotEmpty) {
      setState(() => tujuan.text = kode);
    }
  }

  Future<void> _kirim() async {
    if (_nama.text.trim().length < 2) {
      rtsKsPesan(context, 'Nama produk terlalu pendek.', galat: true);
      return;
    }

    setState(() => _simpan = true);

    try {
      final Map<String, dynamic> hasil = await _api.kirim('produk_simpan', <String, dynamic>{
        'id': widget.produk?.id ?? 0,
        'nama': _nama.text.trim(),
        'merek': _merek.text.trim(),
        'sku': _sku.text.trim(),
        'barcode_pack': _barcodePack.text.trim(),
        'isi_per_pack': rtsKsBulat(_isi.text),
        'harga_pack': rtsKsDariUang(_hargaPack.text),
        'harga_batang': rtsKsDariUang(_hargaBatang.text),
        'catatan': _catatan.text.trim(),
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Produk tersimpan.'}');
      Navigator.of(context).pop(true);
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _simpan = false);
      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool baru = widget.produk == null;

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: Text(baru ? 'Produk Baru' : 'Ubah Produk'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _nama,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama produk',
              hintText: 'Contoh: Sampoerna Mild 16',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _merek,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Merek (opsional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _sku,
            decoration: const InputDecoration(
              labelText: 'Kode produk / SKU (opsional)',
              hintText: 'Contoh: SMP-MILD-16',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'BARCODE BUNGKUS',
            style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
          ),
          const SizedBox(height: 8),
          _barisBarcode(
            label: 'Barcode pada bungkus (pack)',
            controller: _barcodePack,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Barcode hanya ada pada bungkus. Tidak ada kolom barcode batang.',
              style: TextStyle(fontSize: 12, color: rtsKsTeks2),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'HARGA & ISI',
            style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _isi,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Isi per pack (batang)',
              hintText: 'Contoh: 16',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hargaPack,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Harga per pack (Rp)',
              hintText: 'Contoh: 32.000',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _hargaBatang,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Harga per batang (Rp, boleh dikosongkan)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _catatan,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
              border: OutlineInputBorder(),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text(
              'Harga ini berlaku untuk SEMUA sales (daftar produk bersama). '
              'Bila dikosongkan, harga batang dihitung otomatis dari harga '
              'bungkus dibagi isi per bungkus.',
              style: TextStyle(fontSize: 12, color: rtsKsTeks2),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: rtsKsMaroon,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _simpan ? null : _kirim,
            icon: _simpan
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_simpan ? 'MENYIMPAN...' : 'SIMPAN PRODUK'),
          ),
        ],
      ),
    );
  }

  Widget _barisBarcode({
    required String label,
    required TextEditingController controller,
  }) {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroonDark),
            onPressed: () => _pindai(controller),
            child: const Icon(Icons.qr_code_scanner_rounded),
          ),
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PEMINDAI BARCODE (KAMERA HP)                                              */
/* ------------------------------------------------------------------------- */

class RtsPilihBarcodePage extends StatefulWidget {
  const RtsPilihBarcodePage({super.key});

  @override
  State<RtsPilihBarcodePage> createState() => _RtsPilihBarcodePageState();
}

class _RtsPilihBarcodePageState extends State<RtsPilihBarcodePage> {
  final ms.MobileScannerController _kamera = ms.MobileScannerController(
    detectionSpeed: ms.DetectionSpeed.normal,
    facing: ms.CameraFacing.back,
  );

  bool _sudahDapat = false;
  String _galat = '';

  @override
  void dispose() {
    _kamera.dispose();
    super.dispose();
  }

  void _dapat(ms.BarcodeCapture tangkap) {
    if (_sudahDapat) return;

    final List<ms.Barcode> kode = tangkap.barcodes;

    for (final ms.Barcode b in kode) {
      final String? nilai = b.rawValue;

      if (nilai != null && nilai.trim().isNotEmpty) {
        _sudahDapat = true;
        Navigator.of(context).pop(nilai.trim());
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Scan Barcode'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: () => _kamera.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _kamera.switchCamera(),
          ),
        ],
      ),
      body: _galat.isNotEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _galat,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            )
          : Stack(
              children: <Widget>[
                ms.MobileScanner(
                  controller: _kamera,
                  onDetect: _dapat,
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Arahkan kamera ke barcode pada bungkus produk.',
                      style: TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* KASIR                                                                     */
/* ------------------------------------------------------------------------- */

class RtsKasirPage extends StatefulWidget {
  const RtsKasirPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsKasirPage> createState() => _RtsKasirPageState();
}

class _RtsKasirPageState extends State<RtsKasirPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);
  final TextEditingController _cari = TextEditingController();
  final TextEditingController _namaToko = TextEditingController();
  final TextEditingController _idToko = TextEditingController();
  final TextEditingController _hpToko = TextEditingController();
  final TextEditingController _catatan = TextEditingController();
  final TextEditingController _uangDiterima = TextEditingController();

  List<RtsProduk> _produk = <RtsProduk>[];
  final List<RtsKeranjang> _keranjang = <RtsKeranjang>[];
  Map<String, dynamic> _ringkas = <String, dynamic>{};
  Map<String, dynamic> _struk = <String, dynamic>{};
  String _metode = 'CASH';
  String _galat = '';
  bool _memuat = true;
  bool _perluPro = false;
  bool _perluSiap = false;
  bool _menyimpan = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    _namaToko.dispose();
    _idToko.dispose();
    _hpToko.dispose();
    _catatan.dispose();
    _uangDiterima.dispose();
    super.dispose();
  }

  double get _total {
    double jumlah = 0;

    for (final RtsKeranjang k in _keranjang) {
      jumlah += k.subtotal;
    }

    return jumlah;
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> stok = await _api.kirim('stok_daftar');
      final Map<String, dynamic> ringkas = await _api.kirim('ringkas');
      final Map<String, dynamic> struk = await _api.kirim('struk_baca');

      final List<dynamic> isi =
          (stok['items'] is List) ? stok['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _produk = isi
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) =>
                RtsProduk.fromJson(e.cast<String, dynamic>()))
            .toList();
        _ringkas = (ringkas['ringkas'] is Map)
            ? (ringkas['ringkas'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        _struk = (struk['struk'] is Map)
            ? (struk['struk'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        _memuat = false;
      });
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
        _perluPro = e.perluPro;
        _perluSiap = e.perluSiap;
      });
    }
  }

  Future<void> _pindaiBarcode() async {
    try {
      final PermissionStatus izin = await Permission.camera.request();

      if (!izin.isGranted) {
        if (!mounted) return;

        rtsKsPesan(
          context,
          'Izin kamera belum diberikan. Buka Pengaturan HP - Aplikasi - '
          'RTS Panel - Izin - Kamera - Izinkan.',
          galat: true,
        );

        return;
      }
    } catch (_) {
      // bila pemeriksaan izin gagal, pemindai tetap dibuka
    }

    if (!mounted) return;

    final String? kode = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const RtsPilihBarcodePage()),
    );

    if (kode == null || kode.isEmpty) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'produk_barcode',
        <String, dynamic>{'barcode': kode},
      );

      final Map<String, dynamic> produk = (hasil['produk'] is Map)
          ? (hasil['produk'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final RtsProduk p = RtsProduk.fromJson(produk);
      final String satuan = '${hasil['satuan'] ?? 'PACK'}'.toUpperCase();

      if (!mounted) return;

      _tambah(p, batang: satuan == 'BATANG' ? 1 : 0, pack: satuan == 'BATANG' ? 0 : 1);
      rtsKsPesan(
        context,
        'Ditambahkan: ${p.nama} (${satuan == 'BATANG' ? '1 batang' : '1 pack'})',
      );
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  void _tambah(RtsProduk produk, {int pack = 0, int batang = 0}) {
    setState(() {
      final int posisi =
          _keranjang.indexWhere((RtsKeranjang k) => k.produk.id == produk.id);

      if (posisi >= 0) {
        _keranjang[posisi].pack += pack;
        _keranjang[posisi].batang += batang;
      } else {
        _keranjang.add(RtsKeranjang(produk: produk, pack: pack, batang: batang));
      }

      _keranjang.removeWhere((RtsKeranjang k) => k.kosong);
    });
  }

  void _ubahJumlah(RtsKeranjang item, {required bool pack, required int tambah}) {
    setState(() {
      if (pack) {
        item.pack += tambah;
        if (item.pack < 0) item.pack = 0;
      } else {
        item.batang += tambah;
        if (item.batang < 0) item.batang = 0;
      }

      _keranjang.removeWhere((RtsKeranjang k) => k.kosong);
    });
  }

  Future<void> _pilihCustomer() async {
    final Map<String, dynamic>? toko = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => RtsPilihCustomerPage(
          baseUrl: widget.baseUrl,
          token: widget.token,
          pengguna: widget.pengguna,
        ),
      ),
    );

    if (toko == null || !mounted) return;

    setState(() {
      _namaToko.text = '${toko['nama'] ?? ''}';
      _idToko.text = '${toko['id'] ?? ''}';
      _hpToko.text = '${toko['hp'] ?? ''}';
    });
  }

  Future<void> _simpanNota() async {
    if (_keranjang.isEmpty) {
      rtsKsPesan(context, 'Keranjang masih kosong.', galat: true);
      return;
    }

    final double total = _total;
    double bayar = total;

    if (_metode == 'CASH') {
      bayar = rtsKsDariUang(_uangDiterima.text);

      if (_uangDiterima.text.trim().isEmpty) bayar = total;

      if (bayar + 0.01 < total) {
        rtsKsPesan(
          context,
          'Uang diterima Rp ${rtsKsUang(bayar)} kurang dari total '
          'Rp ${rtsKsUang(total)}.',
          galat: true,
        );
        return;
      }
    }

    setState(() => _menyimpan = true);

    try {
      final List<Map<String, dynamic>> items = _keranjang
          .map((RtsKeranjang k) => <String, dynamic>{
                'produk_id': k.produk.id,
                'pack': k.pack,
                'batang': k.batang,
              })
          .toList();

      final Map<String, dynamic> hasil = await _api.kirim('kasir_simpan', <String, dynamic>{
        'metode': _metode,
        'bayar': bayar,
        'nama_customer': _namaToko.text.trim(),
        'customer_id': _idToko.text.trim(),
        'hp_customer': _hpToko.text.trim(),
        'catatan': _catatan.text.trim(),
        'items': items,
      });

      if (!mounted) return;

      setState(() {
        _menyimpan = false;
        _keranjang.clear();
        _uangDiterima.clear();
        _catatan.clear();
      });

      final Map<String, dynamic> nota = (hasil['nota'] is Map)
          ? (hasil['nota'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      await _tampilkanSelesai(nota, '${hasil['message'] ?? 'Nota tersimpan.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _menyimpan = false);
      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _tampilkanSelesai(Map<String, dynamic> nota, String pesan) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: <Widget>[
            Icon(Icons.check_circle_rounded, color: rtsKsHijau),
            SizedBox(width: 8),
            Text('Nota Tersimpan', style: TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(pesan),
            const SizedBox(height: 8),
            Text('Nomor : ${nota['nomor'] ?? '-'}'),
            Text('Total : Rp ${rtsKsUang(nota['total'])}'),
            if ('${nota['metode']}'.toUpperCase() == 'CASH')
              Text('Kembali: Rp ${rtsKsUang(nota['kembali'])}')
            else
              Text(
                '${nota['metode']}'.toUpperCase() == 'UTANG'
                    ? 'Dibayar kemudian (UTANG) - tercatat pada menu Piutang.'
                    : 'Barang dititipkan (TITIP) - tercatat pada menu Piutang.',
              ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('SELESAI', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _cetak(nota);
            },
            icon: const Icon(Icons.print_rounded),
            label: const Text('CETAK STRUK'),
          ),
        ],
      ),
    );
  }

  Future<void> _cetak(Map<String, dynamic> nota) async {
    final String galat = await RtsStruk.cetak(nota, _struk);

    if (!mounted) return;

    if (galat.isEmpty) {
      rtsKsPesan(context, 'Struk dikirim ke printer.');

      if (rtsKsBulat(nota['id']) > 0) {
        try {
          await _api.kirim('kasir_cetak', <String, dynamic>{'id': rtsKsBulat(nota['id'])});
        } catch (_) {
          // penanda cetak tidak penting
        }
      }
    } else {
      rtsKsPesan(context, galat, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Kasir'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Riwayat nota',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RtsNotaPage(
                  baseUrl: widget.baseUrl,
                  token: widget.token,
                  pengguna: widget.pengguna,
                  struk: _struk,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _bangunIsi(),
    );
  }

  Widget _bangunIsi() {
    if (_perluPro) return RtsKunciPro(pesan: _galat);

    if (_memuat) return const Center(child: CircularProgressIndicator());

    if (_perluSiap || (_galat.isNotEmpty && _produk.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.point_of_sale_rounded, size: 56, color: rtsKsMaroon),
              const SizedBox(height: 12),
              Text(_galat, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _muat, child: const Text('COBA LAGI')),
            ],
          ),
        ),
      );
    }

    final String cari = _cari.text.trim().toLowerCase();
    final List<RtsProduk> tersaring = cari.isEmpty
        ? _produk
        : _produk
            .where((RtsProduk p) =>
                p.nama.toLowerCase().contains(cari) ||
                p.sku.toLowerCase().contains(cari) ||
                p.barcodePack.contains(cari))
            .toList();

    return Column(
      children: <Widget>[
        _bagianRingkas(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: TextField(
                      controller: _cari,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        hintText: 'Cari nama produk atau barcode',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: rtsKsMaroonDark),
                      onPressed: _pindaiBarcode,
                      child: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_keranjang.isNotEmpty) _bagianKeranjang(),
              const SizedBox(height: 10),
              const Text(
                'DAFTAR BARANG',
                style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
              ),
              const SizedBox(height: 6),
              for (final RtsProduk p in tersaring) _barisProduk(p),
            ],
          ),
        ),
        _bagianBayar(),
      ],
    );
  }

  Widget _bagianRingkas() {
    return Container(
      width: double.infinity,
      color: rtsKsMaroon,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _angka('Nota', '${_ringkas['jumlah_nota'] ?? 0}'),
              _angka('Penjualan', 'Rp ${_ringkas['total_jual_teks'] ?? '0'}'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              _angka('Tunai', 'Rp ${_ringkas['cash_teks'] ?? '0'}'),
              _angka('Piutang', 'Rp ${_ringkas['piutang_belum_teks'] ?? '0'}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _angka(String judul, String nilai) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            judul.toUpperCase(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
              letterSpacing: 0.6,
            ),
          ),
          Text(
            nilai,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _bagianKeranjang() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rtsKsGaris),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'KERANJANG',
            style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
          ),
          const SizedBox(height: 6),
          for (final RtsKeranjang k in _keranjang)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          k.produk.nama,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      Text(
                        'Rp ${rtsKsUang(k.subtotal)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: rtsKsMerah),
                        onPressed: () => setState(() =>
                            _keranjang.removeWhere((RtsKeranjang x) => x == k)),
                      ),
                    ],
                  ),
                  Row(
                    children: <Widget>[
                      _pengatur('Pack', k.pack, (int d) => _ubahJumlah(k, pack: true, tambah: d)),
                      const SizedBox(width: 10),
                      if (k.produk.isiPerPack > 0)
                        _pengatur('Batang', k.batang, (int d) => _ubahJumlah(k, pack: false, tambah: d)),
                    ],
                  ),
                  const Divider(height: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _pengatur(String label, int nilai, void Function(int) ubah) {
    return Row(
      children: <Widget>[
        Text('$label: ', style: const TextStyle(fontSize: 12, color: rtsKsTeks2)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
          onPressed: () => ubah(-1),
        ),
        Text(
          '$nilai',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 20),
          onPressed: () => ubah(1),
        ),
      ],
    );
  }

  Widget _barisProduk(RtsProduk p) {
    final bool adaStok = p.stokPack > 0 || p.stokBatang > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: rtsKsGaris),
      ),
      child: ListTile(
        title: Text(p.nama, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Rp ${rtsKsUang(p.hargaPack)}/pack - sisa ${p.stokTeks}',
          style: TextStyle(
            fontSize: 12,
            color: adaStok ? rtsKsTeks2 : rtsKsMerah,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Tambah 1 pack',
              icon: const Icon(Icons.add_box, color: rtsKsMaroon),
              onPressed: () => _tambah(p, pack: 1),
            ),
            if (p.isiPerPack > 0)
              IconButton(
                tooltip: 'Tambah 1 batang',
                icon: const Icon(Icons.add_circle, color: rtsKsMaroonDark),
                onPressed: () => _tambah(p, batang: 1),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bagianBayar() {
    final double total = _total;
    final double bayar = _uangDiterima.text.trim().isEmpty
        ? total
        : rtsKsDariUang(_uangDiterima.text);
    final double kembali = bayar > total ? bayar - total : 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: rtsKsGaris)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w800)),
              const Spacer(),
              Text(
                'Rp ${rtsKsUang(total)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: rtsKsMaroon,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor:
                        _metode == 'CASH' ? const Color(0xfff3eee9) : Colors.white,
                  ),
                  onPressed: () => setState(() => _metode = 'CASH'),
                  child: const Text('CASH'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor:
                        _metode == 'UTANG' ? const Color(0xfff3eee9) : Colors.white,
                  ),
                  onPressed: () => setState(() => _metode = 'UTANG'),
                  child: const Text('UTANG'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    backgroundColor:
                        _metode == 'TITIP' ? const Color(0xfff3eee9) : Colors.white,
                  ),
                  onPressed: () => setState(() => _metode = 'TITIP'),
                  child: const Text('TITIP'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_metode == 'CASH')
            TextField(
              controller: _uangDiterima,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Uang diterima (Rp)',
                hintText: 'Kosongkan bila uang pas',
                helperText: 'Kembalian: Rp ${rtsKsUang(kembali)}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          if (_metode != 'CASH')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Barang diserahkan, uang menyusul. Tercatat pada menu PIUTANG '
                'dan dapat diangsur.',
                style: TextStyle(fontSize: 12, color: rtsKsKuning),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pilihCustomer,
                  icon: const Icon(Icons.storefront_outlined, size: 18),
                  label: Text(
                    _namaToko.text.trim().isEmpty ? 'PILIH TOKO' : 'GANTI TOKO',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: rtsKsMaroon,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_keranjang.isEmpty || _menyimpan) ? null : _simpanNota,
                  icon: _menyimpan
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_alt_rounded),
                  label: Text(_menyimpan ? 'MENYIMPAN...' : 'SIMPAN NOTA'),
                ),
              ),
            ],
          ),
          if (_namaToko.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Toko: ${_namaToko.text}'
                '${_idToko.text.trim().isEmpty ? '' : ' (${_idToko.text})'}',
                style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
              ),
            ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* SALES DISTRICT (penyaring data customer pada seluruh menu PRO)            */
/* ------------------------------------------------------------------------- */

/// Daftar Sales District pada salinan toko di HP + district yang sedang dipilih.
///
/// Dipakai menu Kasir, Peta Customer, Radar Customer, Rute Plan, dan Program.
/// Tujuannya: data customer yang dibaca dan digambar cukup SATU district saja,
/// supaya aplikasi tetap ringan walaupun master_toko di server memuat ribuan
/// toko (3186 toko sekaligus pernah membuat peta berat / lambat).
///
/// Aturan hak akses (mengikuti aturan DATA CUSTOMER di server):
///   - RTS & TF  : TERKUNCI pada Sales District akunnya.
///   - WSS, SMST, ADMIN, ASS : bebas memilih SEMUA DISTRICT atau satu district.
class RtsDistrict {
  const RtsDistrict({
    this.daftar = const <Map<String, dynamic>>[],
    this.district = '',
    this.terkunci = false,
    this.jumlah = 0,
    this.districtSaya = '',
    this.sinkronPada = '',
  });

  /// Daftar district yang ada di salinan HP: [{district, jumlah}].
  final List<Map<String, dynamic>> daftar;

  /// District yang sedang dipilih ('' = SEMUA DISTRICT).
  final String district;

  /// True = tidak dapat diganti (akun RTS / TF).
  final bool terkunci;

  /// Jumlah seluruh toko pada salinan HP (semua district).
  final int jumlah;

  /// Sales District pada akun yang sedang masuk.
  final String districtSaya;

  /// Kapan daftar toko terakhir disalin dari server.
  final String sinkronPada;

  /// Membaca daftar district + pilihan yang tersimpan. Tidak pernah gagal:
  /// bila data belum ada, hasilnya kosong dan halaman tetap dapat dibuka.
  static Future<RtsDistrict> muat() async {
    try {
      final Map<String, dynamic> hasil =
          await RtsKasirLokal.aku.kirim('toko_district');

      final List<Map<String, dynamic>> daftar = <Map<String, dynamic>>[];

      if (hasil['items'] is List) {
        for (final dynamic satu in hasil['items'] as List<dynamic>) {
          if (satu is! Map) continue;

          final Map<String, dynamic> d = satu.cast<String, dynamic>();

          daftar.add(<String, dynamic>{
            'district': '${d['district'] ?? ''}',
            'jumlah': int.tryParse('${d['jumlah'] ?? 0}') ?? 0,
          });
        }
      }

      return RtsDistrict(
        daftar: daftar,
        district: '${hasil['pilihan'] ?? ''}'.toUpperCase(),
        terkunci: hasil['terkunci'] == true,
        jumlah: int.tryParse('${hasil['jumlah'] ?? 0}') ?? 0,
        districtSaya: '${hasil['district_saya'] ?? ''}',
        sinkronPada: '${hasil['sinkron_pada'] ?? ''}',
      );
    } on RtsKasirGalat {
      return const RtsDistrict();
    }
  }

  /// Menyimpan pilihan supaya seluruh menu PRO memakai pilihan yang sama.
  static Future<void> simpan(String district) async {
    try {
      await RtsKasirLokal.aku.kirim('district_pilih', <String, dynamic>{
        'district': district,
      });
    } on RtsKasirGalat {
      // gagal menyimpan pilihan tidak menghalangi pemakaian halaman
    }
  }

  /// Jumlah toko pada district yang sedang dipilih (0 = semua district).
  int get jumlahTampil {
    if (district.isEmpty) return jumlah;

    for (final Map<String, dynamic> d in daftar) {
      if ('${d['district']}' == district) {
        return int.tryParse('${d['jumlah'] ?? 0}') ?? 0;
      }
    }

    return 0;
  }
}

/// Baris pilihan SALES DISTRICT yang dipakai pada menu PRO.
///
/// Bila akun RTS / TF, baris ini hanya menampilkan keterangan (terkunci).
/// Bila akun WSS / SMST / ADMIN / ASS, baris ini dapat digeser ke samping dan
/// berisi tombol SEMUA DISTRICT serta nama-nama district beserta jumlah tokonya.
class RtsDistrictBar extends StatelessWidget {
  const RtsDistrictBar({
    super.key,
    required this.info,
    required this.onUbah,
    this.judul = 'Sales District',
  });

  final RtsDistrict info;

  /// Dipanggil setiap pilihan district diganti ('' = SEMUA DISTRICT).
  final void Function(String district) onUbah;

  final String judul;

  @override
  Widget build(BuildContext context) {
    final String saya = info.districtSaya.isEmpty
        ? '(belum diisi di Kelola Akun Tim)'
        : info.districtSaya;

    if (info.terkunci) {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xffeef4ff),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xffcfe0ff)),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.lock_outline_rounded,
                size: 15, color: Color(0xff1d5bbf)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$judul terkunci pada akun: $saya',
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff1d5bbf),
                ),
              ),
            ),
            Text(
              '${info.jumlahTampil} toko',
              style: const TextStyle(fontSize: 10, color: Color(0xff1d5bbf)),
            ),
          ],
        ),
      );
    }

    if (info.daftar.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Icon(Icons.location_city_outlined,
                size: 15, color: rtsKsMaroon),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                info.district.isEmpty
                    ? '$judul: SEMUA DISTRICT (${info.jumlah} toko)'
                    : '$judul: ${info.district} (${info.jumlahTampil} toko)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: rtsKsTeks,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Text(
              'geser ->',
              style: TextStyle(fontSize: 9.5, color: rtsKsTeks2),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              _chip(
                'SEMUA DISTRICT',
                info.district.isEmpty,
                () => onUbah(''),
              ),
              for (final Map<String, dynamic> d in info.daftar)
                _chip(
                  '${d['district']}'.isEmpty
                      ? 'TANPA DISTRICT (${d['jumlah']})'
                      : '${d['district']} (${d['jumlah']})',
                  info.district == '${d['district']}',
                  () => onUbah('${d['district']}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _chip(String teks, bool aktif, VoidCallback tekan) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
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
        selectedColor: rtsKsMaroon,
        backgroundColor: Colors.white,
        side: BorderSide(color: aktif ? rtsKsMaroon : rtsKsGaris),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PILIH TOKO DARI MASTER CUSTOMER (tabel master_toko di server)              */
/* ------------------------------------------------------------------------- */

class RtsPilihCustomerPage extends StatefulWidget {
  const RtsPilihCustomerPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsPilihCustomerPage> createState() => _RtsPilihCustomerPageState();
}

/// Pemilih toko untuk menu Kasir.
///
/// Sumber datanya adalah tabel `master_toko` pada database server (lewat
/// api/customers.php). Daftarnya disalin ke HP, sehingga pemilihan toko tetap
/// dapat dipakai saat tidak ada internet.
class _RtsPilihCustomerPageState extends State<RtsPilihCustomerPage> {
  late final RtsKasirApi _api = RtsKasirApi(
    baseUrl: widget.baseUrl,
    token: widget.token,
    pengguna: widget.pengguna,
  );

  final TextEditingController _cari = TextEditingController();

  List<Map<String, dynamic>> _daftar = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _hasil = <Map<String, dynamic>>[];
  bool _memuat = true;
  bool _menyalin = false;
  String _galat = '';
  String _sinkronPada = '';

  /// Penyaring SALES DISTRICT: daftar toko yang dibaca cukup satu district,
  /// supaya halaman ini tetap ringan (bukan 3000+ toko sekaligus).
  RtsDistrict _district = const RtsDistrict();

  // ---- Toko TERDEKAT (point 3) -------------------------------------------
  // Begitu halaman ini dibuka, posisi HP dibaca sekali. Daftar toko disusun
  // ulang dari yang paling dekat, sehingga DUA baris teratas adalah toko
  // terdekat dari keberadaan Sales - tidak perlu mencari nama toko lagi.
  Position? _posisi;
  bool _mencariLokasi = false;
  String _catatanLokasi = '';

  @override
  void initState() {
    super.initState();
    _muat();
    _ambilLokasi();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  /// Membaca salinan daftar toko di HP, lalu (bila belum ada) menyalin dari
  /// master_toko di server.
  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      // Penyaring district dibaca lebih dulu supaya daftar toko langsung
      // dipotong sesuai pilihan (aplikasi tidak berat).
      if (_district.daftar.isEmpty) {
        _district = await RtsDistrict.muat();

        if (!mounted) return;
      }

      final Map<String, dynamic> hasil = await _api.kirim('toko_daftar', <String, dynamic>{
        'batas': 300,
        'district': _district.district,
      });

      final List<Map<String, dynamic>> daftar = _baca(hasil);

      if (!mounted) return;

      setState(() {
        _daftar = daftar;
        _hasil = daftar;
        _sinkronPada = '${hasil['sinkron_pada'] ?? ''}';
        _memuat = false;
      });

      // Bila posisi HP sudah terbaca, daftar langsung disusun dari yang
      // terdekat (tanpa menunggu tombol TERDEKAT ditekan).
      if (_posisi != null) _urutkanTerdekat();

      // Salinan di HP masih kosong: coba salin dari master_toko sekarang.
      if (_daftar.isEmpty) {
        await _segarkan(diam: true);
      }
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = e.pesan;
      });
    }
  }

  /// Mengganti penyaring SALES DISTRICT: pilihan disimpan (dipakai bersama
  /// seluruh menu PRO), lalu daftar toko dibaca ulang.
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

  /// Menyalin ulang daftar toko dari tabel master_toko di server.
  Future<void> _segarkan({bool diam = false}) async {
    setState(() {
      _menyalin = true;

      if (!diam) _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('toko_segarkan');

      if (!mounted) return;

      setState(() => _menyalin = false);

      if (!diam) {
        rtsKsPesan(context, '${hasil['message'] ?? 'Daftar toko diperbarui.'}');
      }

      await _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _menyalin = false;
        _galat = _daftar.isEmpty
            ? 'Daftar toko belum pernah disalin ke HP dan server tidak dapat '
                'dihubungi. Sambungkan internet lalu tekan MUAT DARI MASTER_TOKO. '
                '(${e.pesan})'
            : 'Daftar toko dari HP dipakai (tanpa internet). '
                'Tekan MUAT DARI MASTER_TOKO bila ingin memperbarui. (${e.pesan})';
      });
    }
  }

  List<Map<String, dynamic>> _baca(Map<String, dynamic> hasil) {
    final List<dynamic> items =
        (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

    return items
        .whereType<Map>()
        .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
        .toList();
  }

  /// Membaca posisi HP, lalu mengurutkan daftar dari toko yang TERDEKAT.
  Future<void> _ambilLokasi() async {
    if (_mencariLokasi) return;

    setState(() {
      _mencariLokasi = true;
      _catatanLokasi = '';
    });

    final Position? p = await rtsKsAmbilLokasi();

    if (!mounted) return;

    setState(() {
      _mencariLokasi = false;
      _posisi = p;
      _catatanLokasi = p == null
          ? 'Posisi HP belum terbaca. Isi izin Lokasi lalu tekan TERDEKAT.'
          : '';
    });

    if (p != null) _urutkanTerdekat();
  }

  /// Mengurutkan daftar toko: paling dekat di atas, yang belum bertitik di
  /// bawah. Jaraknya disimpan pada setiap baris ('jarak_meter', 'jarak_teks')
  /// supaya dapat ditampilkan pada layar.
  void _urutkanTerdekat() {
    final Position? p = _posisi;

    if (p == null) return;

    final List<Map<String, dynamic>> urut =
        List<Map<String, dynamic>>.from(_daftar);

    for (final Map<String, dynamic> t in urut) {
      final double lat = _angkaAtau(t['latitude']);
      final double lng = _angkaAtau(t['longitude']);

      if (lat != 0 && lng != 0) {
        final double jarak = rtsKsJarakMeter(
          p.latitude,
          p.longitude,
          lat,
          lng,
        );

        t['jarak_meter'] = jarak;
        t['jarak_teks'] = rtsKsJarakTeks(jarak);
      } else {
        t['jarak_meter'] = -1.0;
        t['jarak_teks'] = '';
      }
    }

    urut.sort((Map<String, dynamic> a, Map<String, dynamic> b) {
      final double ja = _angkaAtau(a['jarak_meter']);
      final double jb = _angkaAtau(b['jarak_meter']);

      final bool adaA = ja >= 0;
      final bool adaB = jb >= 0;

      if (adaA != adaB) return adaA ? -1 : 1;
      if (!adaA && !adaB) {
        return '${a['nama']}'.toLowerCase().compareTo(
              '${b['nama']}'.toLowerCase(),
            );
      }

      return ja.compareTo(jb);
    });

    _daftar = urut;
    _saring(_cari.text);
  }

  /// Angka dari nilai apa pun (double, int, atau teks dari server).
  double _angkaAtau(dynamic nilai) {
    if (nilai is num) return nilai.toDouble();
    return double.tryParse('${nilai ?? ''}'.replaceAll(',', '.')) ?? 0;
  }

  void _saring(String kata) {
    final String cari = kata.trim().toLowerCase();

    setState(() {
      _hasil = cari.isEmpty
          ? _daftar
          : _daftar.where((Map<String, dynamic> t) {
              return '${t['nama']}'.toLowerCase().contains(cari) ||
                  '${t['id']}'.toLowerCase().contains(cari) ||
                  '${t['alamat']}'.toLowerCase().contains(cari) ||
                  '${t['district']}'.toLowerCase().contains(cari);
            }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Pilih Toko (master_toko)'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Muat dari master_toko',
            icon: const Icon(Icons.cloud_download_outlined),
            onPressed: _menyalin ? null : () => _segarkan(),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _cari,
                  onChanged: _saring,
                  decoration: InputDecoration(
                    hintText: 'Cari nama toko, ID customer, atau district',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _cari.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _cari.clear();
                              _saring('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                RtsDistrictBar(
                  info: _district,
                  onUbah: (String d) => unawaited(_ubahDistrict(d)),
                ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                        onPressed: _menyalin ? null : () => _segarkan(),
                        icon: const Icon(Icons.sync_rounded, size: 18),
                        label: Text(
                          _menyalin ? 'MENYALIN...' : 'MUAT DARI MASTER_TOKO',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: rtsKsMaroon,
                          side: const BorderSide(color: rtsKsMaroon),
                        ),
                        onPressed: _mencariLokasi ? null : _ambilLokasi,
                        icon: _mencariLokasi
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18),
                        label: Text(
                          _mencariLokasi ? 'MENCARI...' : 'TERDEKAT',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _sinkronPada.isEmpty
                      ? 'Salinan daftar toko belum ada di HP.'
                      : 'Salinan terakhir dari master_toko: '
                          '${rtsKsWaktuLengkap(_sinkronPada)}'
                          ' - dapat dipakai tanpa internet.',
                  style: const TextStyle(fontSize: 11.5, color: rtsKsTeks2),
                ),
                if (_catatanLokasi.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    _catatanLokasi,
                    style: const TextStyle(fontSize: 11.5, color: rtsKsMerah),
                  ),
                ],
              ],
            ),
          ),
          if (_galat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_galat, style: const TextStyle(color: rtsKsMerah)),
            ),
          if (_memuat || _menyalin) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _posisi == null
                    ? '${_hasil.length} dari ${_daftar.length} toko'
                    : '${_hasil.length} dari ${_daftar.length} toko - '
                        '2 baris teratas adalah toko TERDEKAT dari posisi Anda',
                style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _hasil.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext ctx, int i) {
                final Map<String, dynamic> t = _hasil[i];
                final double jarak = _angkaAtau(t['jarak_meter']);
                final String jarakTeks = '${t['jarak_teks'] ?? ''}';
                // Dua baris teratas adalah toko terdekat dari posisi Sales.
                final bool terdekat = _posisi != null && jarak >= 0 && i < 2;

                return ListTile(
                  leading: terdekat
                      ? CircleAvatar(
                          backgroundColor: rtsKsMaroon,
                          foregroundColor: Colors.white,
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        )
                      : null,
                  title: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${t['nama']}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (terdekat)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: rtsKsMaroon,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'TERDEKAT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(rtsKsSambung('ID: ${t['id']}', '${t['hp']}')),
                      if ('${t['district']}'.isNotEmpty ||
                          '${t['salesman']}'.isNotEmpty)
                        Text(
                          rtsKsSambung('${t['district']}', '${t['salesman']}'),
                          style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                      if (jarakTeks.isNotEmpty)
                        Text(
                          'Jarak ${jarakTeks} dari posisi Anda',
                          style: const TextStyle(
                            fontSize: 12,
                            color: rtsKsMaroon,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  onTap: () => Navigator.of(ctx).pop(<String, dynamic>{
                    'id': '${t['id']}',
                    'nama': '${t['nama']}',
                    'hp': '${t['hp']}',
                    'alamat': '${t['alamat']}',
                    'district': '${t['district']}',
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Jarak antara dua titik di permukaan bumi (meter).
///
/// Rumus Haversine - sama dengan yang dipakai menu Peta, tetapi ditulis ulang
/// di sini supaya berkas ini TIDAK memanggil peta.dart (menghindari impor
/// berputar, karena peta.dart justru memanggil kasir.dart).
double rtsKsJarakMeter(double lat1, double lng1, double lat2, double lng2) {
  const double bumi = 6371000.0;
  const double derajat = math.pi / 180.0;

  final double dLat = (lat2 - lat1) * derajat;
  final double dLng = (lng2 - lng1) * derajat;

  final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1 * derajat) *
          math.cos(lat2 * derajat) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);

  return bumi * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

/// Tulisan jarak yang ringkas (contoh: 250 m, 1,3 km).
String rtsKsJarakTeks(double meter) {
  if (meter < 1000) return '${meter.round()} m';

  final String angka = (meter / 1000).toStringAsFixed(1).replaceAll('.', ',');

  return '$angka km';
}

/// Mengambil posisi HP saat ini (izin lokasi diminta sekali).
///
/// Sama seperti rtsPetaAmbilLokasi pada peta.dart, tetapi ditulis ulang di
/// sini supaya berkas ini tetap berdiri sendiri. Bila lokasi tidak dapat
/// dibaca, hasilnya null - daftar toko tetap tampil seperti biasa.
Future<Position?> rtsKsAmbilLokasi() async {
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

/* RIWAYAT NOTA                                                              */
/* ------------------------------------------------------------------------- */

class RtsNotaPage extends StatefulWidget {
  const RtsNotaPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
    required this.struk,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;
  final Map<String, dynamic> struk;

  @override
  State<RtsNotaPage> createState() => _RtsNotaPageState();
}

class _RtsNotaPageState extends State<RtsNotaPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);

  List<Map<String, dynamic>> _nota = <Map<String, dynamic>>[];
  Map<String, dynamic> _ringkas = <String, dynamic>{};
  bool _memuat = true;
  String _galat = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('kasir_daftar');
      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _nota = items
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
        _ringkas = hasil;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Riwayat Nota'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: rtsKsGaris),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('${_ringkas['jumlah'] ?? 0} nota terakhir'),
                      Text('Total: Rp ${_ringkas['total_teks'] ?? '0'}'),
                      Text('Tunai: Rp ${_ringkas['cash_teks'] ?? '0'}'),
                    ],
                  ),
                ),
                if (_galat.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_galat, style: const TextStyle(color: rtsKsMerah)),
                  ),
                const SizedBox(height: 10),
                for (final Map<String, dynamic> n in _nota)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: rtsKsGaris),
                    ),
                    child: ListTile(
                      title: Text(
                        '${n['nomor']} - Rp ${n['total_teks']}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            rtsKsSambung(
                              rtsKsWaktuLengkap('${n['tanggal'] ?? ''}'),
                              '${n['nama_customer']}',
                            ),
                          ),
                          Text(
                            '${n['metode']} - ${n['status']}'
                            '${n['dibatalkan'] == true ? ' - DIBATALKAN' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: n['dibatalkan'] == true
                                  ? rtsKsMerah
                                  : (n['status'] == 'LUNAS' ? rtsKsHijau : rtsKsKuning),
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => RtsNotaDetailPage(
                              baseUrl: widget.baseUrl,
                              token: widget.token,
                              pengguna: widget.pengguna,
                              struk: widget.struk,
                              id: rtsKsBulat(n['id']),
                            ),
                          ),
                        );

                        if (mounted) _muat();
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class RtsNotaDetailPage extends StatefulWidget {
  const RtsNotaDetailPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
    required this.struk,
    required this.id,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;
  final Map<String, dynamic> struk;
  final int id;

  @override
  State<RtsNotaDetailPage> createState() => _RtsNotaDetailPageState();
}

class _RtsNotaDetailPageState extends State<RtsNotaDetailPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);

  Map<String, dynamic> _nota = <String, dynamic>{};
  bool _memuat = true;
  String _galat = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('kasir_ambil', <String, dynamic>{'id': widget.id});

      final Map<String, dynamic> nota = (hasil['nota'] is Map)
          ? (hasil['nota'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _nota = nota;
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

  Future<void> _cetakUlang() async {
    final String galat = await RtsStruk.cetak(_nota, widget.struk);

    if (!mounted) return;

    if (galat.isEmpty) {
      rtsKsPesan(context, 'Struk dikirim ke printer.');

      try {
        await _api.kirim('kasir_cetak', <String, dynamic>{'id': widget.id});
      } catch (_) {
        // diabaikan
      }
    } else {
      rtsKsPesan(context, galat, galat: true);
    }
  }

  Future<void> _batalkan() async {
    final TextEditingController alasan = TextEditingController();

    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Batalkan Nota?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text(
              'Stok barang pada nota ini akan dikembalikan seperti semula.',
            ),
            const SizedBox(height: 10),
            TextField(
              controller: alasan,
              decoration: const InputDecoration(
                labelText: 'Alasan (opsional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('TIDAK', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMerah),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('BATALKAN'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('kasir_batal', <String, dynamic>{
        'id': widget.id,
        'alasan': alasan.text.trim(),
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Nota dibatalkan.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> items =
        (_nota['items'] is List) ? _nota['items'] as List<dynamic> : <dynamic>[];
    final bool dibatalkan = _nota['dibatalkan'] == true;

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: Text('${_nota['nomor'] ?? 'Nota'}'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : _galat.isNotEmpty
              ? Center(child: Text(_galat))
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: <Widget>[
                    if (dibatalkan)
                      Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: rtsKsMerah.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'NOTA INI SUDAH DIBATALKAN',
                          style: TextStyle(
                            color: rtsKsMerah,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    _baris('Waktu', rtsKsWaktuLengkap('${_nota['tanggal'] ?? ''}')),
                    _baris('Sales', '${_nota['nama_sales'] ?? ''}'),
                    _baris('Toko', '${_nota['nama_customer'] ?? '(tanpa toko)'}'),
                    _baris('Metode', '${_nota['metode'] ?? ''}'),
                    _baris('Status', '${_nota['status'] ?? ''}'),
                    const Divider(height: 22),
                    for (final dynamic item in items)
                      if (item is Map)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  rtsKsItemTeks(item.cast<dynamic, dynamic>()),
                                ),
                              ),
                              Text('Rp ${item['subtotal_teks']}'),
                            ],
                          ),
                        ),
                    const Divider(height: 22),
                    _baris('TOTAL', 'Rp ${_nota['total_teks'] ?? '0'}', tebal: true),
                    if ('${_nota['metode']}'.toUpperCase() == 'CASH') ...<Widget>[
                      _baris('Tunai', 'Rp ${_nota['bayar_teks'] ?? '0'}'),
                      _baris('Kembali', 'Rp ${_nota['kembali_teks'] ?? '0'}'),
                    ] else if (_nota['piutang'] is Map) ...<Widget>[
                      _baris(
                        'Sisa piutang',
                        'Rp ${rtsKsUang((_nota['piutang'] as Map)['sisa'])}',
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                      onPressed: _cetakUlang,
                      icon: const Icon(Icons.print_rounded),
                      label: const Text('CETAK ULANG STRUK'),
                    ),
                    const SizedBox(height: 8),
                    if (!dibatalkan)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: rtsKsMerah),
                        onPressed: _batalkan,
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('BATALKAN NOTA'),
                      ),
                  ],
                ),
    );
  }

  Widget _baris(String judul, String nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(judul, style: const TextStyle(color: rtsKsTeks2)),
          ),
          Expanded(
            child: Text(
              nilai,
              style: TextStyle(
                fontWeight: tebal ? FontWeight.w900 : FontWeight.w600,
                fontSize: tebal ? 16 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PIUTANG (UTANG & TITIP)                                                   */
/* ------------------------------------------------------------------------- */

class RtsPiutangPage extends StatefulWidget {
  const RtsPiutangPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.pengguna,
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsPiutangPage> createState() => _RtsPiutangPageState();
}

class _RtsPiutangPageState extends State<RtsPiutangPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);

  final TextEditingController _cari = TextEditingController();

  List<Map<String, dynamic>> _piutang = <Map<String, dynamic>>[];
  String _jenis = '';
  bool _hanyaBelum = true;
  bool _memuat = true;
  String _galat = '';
  String _belumTeks = '0';

  // Toko yang sedang dibuka piutangnya (dipilih dari daftar TERDEKAT).
  String _tokoNama = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    _cari.dispose();
    super.dispose();
  }

  /// Membuka pemilih toko (diurutkan dari yang TERDEKAT dengan posisi HP),
  /// lalu menampilkan piutang toko tersebut. Dipakai pada menu Piutang supaya
  /// Sales tidak perlu mengetik nama toko.
  Future<void> _pilihTokoTerdekat() async {
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

    setState(() {
      _cari.text = '${toko['id']}';
      _tokoNama = '${toko['nama']}';
    });

    await _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('piutang_daftar', <String, dynamic>{
        'jenis': _jenis,
        'cari': _cari.text.trim(),
        'batas': 150,
      });

      final List<dynamic> items =
          (hasil['items'] is List) ? hasil['items'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _piutang = items
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .where((Map<String, dynamic> e) =>
                !_hanyaBelum || !<String>['LUNAS', 'BATAL'].contains('${e['status']}'))
            .toList();
        _belumTeks = '${hasil['belum_teks'] ?? '0'}';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Piutang: Utang & Titip'),
      ),
      body: Column(
        children: <Widget>[
          Container(
            color: rtsKsMaroonDark,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'BELUM DITERIMA',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 0.6,
                  ),
                ),
                Text(
                  'Rp $_belumTeks',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _cari,
                    onSubmitted: (_) => _muat(),
                    decoration: const InputDecoration(
                      hintText: 'Cari nama toko / nomor',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Pilih toko TERDEKAT dari posisi Anda',
                  icon: const Icon(Icons.my_location_rounded, color: rtsKsMaroon),
                  onPressed: _pilihTokoTerdekat,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: rtsKsMaroon),
                  onPressed: _muat,
                ),
              ],
            ),
          ),
          if (_tokoNama.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.storefront_rounded, size: 16, color: rtsKsMaroon),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Toko terdekat: $_tokoNama',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: rtsKsMaroon,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _cari.clear();
                        _tokoNama = '';
                      });
                      _muat();
                    },
                    child: const Text('HAPUS FILTER'),
                  ),
                ],
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: <Widget>[
                _saring('SEMUA', _jenis.isEmpty, () {
                  setState(() => _jenis = '');
                  _muat();
                }),
                _saring('UTANG', _jenis == 'UTANG', () {
                  setState(() => _jenis = 'UTANG');
                  _muat();
                }),
                _saring('TITIP', _jenis == 'TITIP', () {
                  setState(() => _jenis = 'TITIP');
                  _muat();
                }),
                _saring(_hanyaBelum ? 'BELUM LUNAS' : 'SEMUA STATUS', _hanyaBelum, () {
                  setState(() => _hanyaBelum = !_hanyaBelum);
                  _muat();
                }),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: _galat.isNotEmpty
                ? Center(child: Text(_galat))
                : _piutang.isEmpty
                    ? const Center(
                        child: Text(
                          'Tidak ada piutang pada saringan ini.',
                          style: TextStyle(color: rtsKsTeks2),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _muat,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _piutang.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (BuildContext ctx, int i) {
                            final Map<String, dynamic> p = _piutang[i];

                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: rtsKsGaris),
                              ),
                              child: ListTile(
                                title: Text(
                                  '${p['nama_customer']}'.trim().isEmpty
                                      ? '(tanpa nama)'
                                      : '${p['nama_customer']}',
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      '${p['jenis']} - ${p['nomor']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Text(
                                      'Sisa Rp ${p['sisa_teks']} dari Rp ${p['total_teks']}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    Row(
                                      children: <Widget>[
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _warnaStatus('${p['status']}')
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            '${p['status']}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _warnaStatus('${p['status']}'),
                                            ),
                                          ),
                                        ),
                                        if (p['terlambat'] == true)
                                          const Padding(
                                            padding: EdgeInsets.only(left: 6),
                                            child: Text(
                                              'TERLAMBAT',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: rtsKsMerah,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await Navigator.of(context).push<void>(
                                    MaterialPageRoute<void>(
                                      builder: (_) => RtsPiutangDetailPage(
                                        baseUrl: widget.baseUrl,
                                        token: widget.token,
                                        id: rtsKsBulat(p['id']),
                                      ),
                                    ),
                                  );

                                  if (mounted) _muat();
                                },
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Color _warnaStatus(String status) {
    switch (status.toUpperCase()) {
      case 'LUNAS':
        return rtsKsHijau;
      case 'SEBAGIAN':
        return rtsKsKuning;
      case 'BATAL':
        return rtsKsTeks2;
      default:
        return rtsKsMerah;
    }
  }

  Widget _saring(String label, bool aktif, VoidCallback tekan) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: aktif,
        selectedColor: rtsKsMaroon.withValues(alpha: 0.15),
        onSelected: (_) => tekan(),
      ),
    );
  }
}

class RtsPiutangDetailPage extends StatefulWidget {
  const RtsPiutangDetailPage({
    super.key,
    required this.baseUrl,
    required this.token,
    required this.id,
  });

  final String baseUrl;
  final String token;
  final int id;

  @override
  State<RtsPiutangDetailPage> createState() => _RtsPiutangDetailPageState();
}

class _RtsPiutangDetailPageState extends State<RtsPiutangDetailPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

  Map<String, dynamic> _piutang = <String, dynamic>{};
  bool _memuat = true;
  String _galat = '';
  String _metode = 'CASH';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil =
          await _api.kirim('piutang_ambil', <String, dynamic>{'id': widget.id});

      final Map<String, dynamic> piutang = (hasil['piutang'] is Map)
          ? (hasil['piutang'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _piutang = piutang;
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

  Future<void> _bayar() async {
    final TextEditingController jumlah =
        TextEditingController(text: rtsKsUang(_piutang['sisa']));
    final TextEditingController catatan = TextEditingController();

    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, void Function(void Function()) ubah) =>
            AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text(
            'Catat Pembayaran',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Sisa saat ini: Rp ${_piutang['sisa_teks']}'),
              const SizedBox(height: 12),
              TextField(
                controller: jumlah,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Jumlah dibayar (Rp)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _metode == 'CASH' ? const Color(0xfff3eee9) : Colors.white,
                      ),
                      onPressed: () => ubah(() => _metode = 'CASH'),
                      child: const Text('CASH'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor: _metode == 'TRANSFER'
                            ? const Color(0xfff3eee9)
                            : Colors.white,
                      ),
                      onPressed: () => ubah(() => _metode = 'TRANSFER'),
                      child: const Text('TRANSFER'),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        backgroundColor:
                            _metode == 'QRIS' ? const Color(0xfff3eee9) : Colors.white,
                      ),
                      onPressed: () => ubah(() => _metode = 'QRIS'),
                      child: const Text('QRIS'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: catatan,
                decoration: const InputDecoration(
                  labelText: 'Catatan (opsional)',
                  border: OutlineInputBorder(),
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
      ),
    );

    if (setuju != true) return;

    try {
      final Map<String, dynamic> hasil = await _api.kirim('piutang_bayar', <String, dynamic>{
        'id': widget.id,
        'jumlah': rtsKsDariUang(jumlah.text),
        'metode': _metode,
        'catatan': catatan.text.trim(),
      });

      if (!mounted) return;

      rtsKsPesan(context, '${hasil['message'] ?? 'Pembayaran tersimpan.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<dynamic> bayar =
        (_piutang['pembayaran'] is List) ? _piutang['pembayaran'] as List<dynamic> : <dynamic>[];

    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: Text('${_piutang['nomor'] ?? 'Piutang'}'),
      ),
        body: _memuat
            ? const Center(child: CircularProgressIndicator())
            : _galat.isNotEmpty
                ? Center(child: Text(_galat))
                : ListView(
                    padding: const EdgeInsets.all(14),
                    children: <Widget>[
                      _baris('Jenis', '${_piutang['jenis']}'),
                      _baris('Tanggal', rtsKsWaktuLengkap('${_piutang['tanggal'] ?? ''}')),
                      if ('${_piutang['jatuh_tempo'] ?? ''}'.trim().isNotEmpty)
                        _baris('Jatuh tempo', rtsKsTanggal('${_piutang['jatuh_tempo']}')),
                      _baris('Toko', '${_piutang['nama_customer'] ?? '(tanpa toko)'}'),
                      _baris('ID Customer', '${_piutang['customer_id'] ?? '-'}'),
                      _baris('HP', '${_piutang['hp_customer'] ?? '-'}'),
                      _baris('Sales', '${_piutang['nama_sales'] ?? ''}'),
                      const Divider(height: 22),
                      Text(
                        'Barang: ${_piutang['rincian'] ?? '-'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const Divider(height: 22),
                      _baris('Total', 'Rp ${_piutang['total_teks'] ?? '0'}'),
                      _baris('Sudah dibayar', 'Rp ${_piutang['dibayar_teks'] ?? '0'}'),
                      _baris('SISA', 'Rp ${_piutang['sisa_teks'] ?? '0'}', tebal: true),
                      _baris('Status', '${_piutang['status']}'),
                      const SizedBox(height: 14),
                      if (!<String>['LUNAS', 'BATAL'].contains('${_piutang['status']}'))
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: rtsKsMaroon,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _bayar,
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('CATAT PEMBAYARAN'),
                        ),
                      const SizedBox(height: 16),
                      const Text(
                        'RIWAYAT PEMBAYARAN',
                        style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
                      ),
                      const SizedBox(height: 6),
                      if (bayar.isEmpty)
                        const Text(
                          'Belum ada pembayaran.',
                          style: TextStyle(color: rtsKsTeks2),
                        ),
                      for (final dynamic b in bayar)
                        if (b is Map)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        rtsKsWaktuLengkap('${b['tanggal']}'),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      Text(
                                        rtsKsSambung(
                                          '${b['metode']}',
                                          '${b['catatan']}',
                                        ),
                                        style: const TextStyle(
                                            fontSize: 12, color: rtsKsTeks2),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: <Widget>[
                                    Text(
                                      'Rp ${b['jumlah_teks']}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    Text(
                                      'sisa Rp ${b['sisa_sesudah_teks']}',
                                      style: const TextStyle(
                                          fontSize: 11, color: rtsKsTeks2),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                  ],
                ),
    );
  }

  Widget _baris(String judul, String nilai, {bool tebal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(judul, style: const TextStyle(color: rtsKsTeks2)),
          ),
          Expanded(
            child: Text(
              nilai,
              style: TextStyle(
                fontWeight: tebal ? FontWeight.w900 : FontWeight.w600,
                fontSize: tebal ? 16 : 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
/* PRINTER & TEMPLATE STRUK                                                  */
/* ------------------------------------------------------------------------- */

class RtsPrinterPage extends StatefulWidget {
  const RtsPrinterPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsPrinterPage> createState() => _RtsPrinterPageState();
}

class _RtsPrinterPageState extends State<RtsPrinterPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token, pengguna: widget.pengguna);

  List<BluetoothInfo> _perangkat = <BluetoothInfo>[];
  String _terhubung = '';
  String _tersimpan = '';
  bool _memuat = false;
  Map<String, dynamic> _struk = <String, dynamic>{};
  bool _siap = false;

  final TextEditingController _judul = TextEditingController();
  final TextEditingController _baris1 = TextEditingController();
  final TextEditingController _baris2 = TextEditingController();
  final TextEditingController _baris3 = TextEditingController();
  final TextEditingController _footer1 = TextEditingController();
  final TextEditingController _footer2 = TextEditingController();
  final TextEditingController _footer3 = TextEditingController();

  int _lebar = 58;
  String _jenis = '58';
  int _roll = 40;
  String _huruf = 'SEDANG';
  String _garis = '-';
  int _salinan = 1;
  bool _barcode = true;
  bool _hp = true;
  bool _ttd = false;
  bool _metode = true;

  @override
  void initState() {
    super.initState();
    _muatStruk();
    _muatPrinter();
  }

  @override
  void dispose() {
    _judul.dispose();
    _baris1.dispose();
    _baris2.dispose();
    _baris3.dispose();
    _footer1.dispose();
    _footer2.dispose();
    _footer3.dispose();
    super.dispose();
  }

  Future<void> _muatStruk() async {
    try {
      final Map<String, dynamic> hasil = await _api.kirim('struk_baca');

      final Map<String, dynamic> struk = (hasil['struk'] is Map)
          ? (hasil['struk'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      if (!mounted) return;

      setState(() {
        _struk = struk;
        _judul.text = '${struk['judul'] ?? 'RTS PANEL'}';
        _baris1.text = '${struk['baris1'] ?? ''}';
        _baris2.text = '${struk['baris2'] ?? ''}';
        _baris3.text = '${struk['baris3'] ?? ''}';
        _footer1.text = '${struk['footer1'] ?? ''}';
        _footer2.text = '${struk['footer2'] ?? ''}';
        _footer3.text = '${struk['footer3'] ?? ''}';
        _lebar = rtsKsBulat(struk['lebar_kertas'] ?? 58);
        _jenis = '${struk['jenis_printer'] ?? (_lebar >= 76 ? '80' : '58')}';
        _roll = rtsKsBulat(struk['diameter_roll'] ?? 40);
        _huruf = '${struk['ukuran_huruf'] ?? 'SEDANG'}';
        _garis = '${struk['garis'] ?? '-'}';
        _salinan = rtsKsBulat(struk['jumlah_salinan'] ?? 1);
        _barcode = rtsKsBulat(struk['tampilkan_barcode'] ?? 1) == 1;
        _hp = rtsKsBulat(struk['tampilkan_hp'] ?? 1) == 1;
        _ttd = rtsKsBulat(struk['tampilkan_ttd'] ?? 0) == 1;
        _metode = rtsKsBulat(struk['tampilkan_metode'] ?? 1) == 1;
        _siap = true;
      });
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() {
        _siap = false;
        _struk = <String, dynamic>{'pesan': e.pesan};
      });
    }
  }

  Future<void> _muatPrinter() async {
    setState(() => _memuat = true);

    try {
      final bool hidup = await PrintBluetoothThermal.bluetoothEnabled;

      if (!hidup) {
        if (!mounted) return;

        setState(() {
          _memuat = false;
          _perangkat = <BluetoothInfo>[];
        });

        rtsKsPesan(
          context,
          'Bluetooth HP sedang mati. Nyalakan Bluetooth terlebih dahulu.',
          galat: true,
        );

        return;
      }

      final List<BluetoothInfo> daftar =
          await PrintBluetoothThermal.pairedBluetooths;
      final bool tersambung = await PrintBluetoothThermal.connectionStatus;
      final Map<String, String> simpan = await RtsPrinter.tersimpan();

      if (!mounted) return;

      setState(() {
        _perangkat = daftar;
        _terhubung = tersambung ? (simpan['nama'] ?? '') : '';
        _tersimpan = simpan['mac'] ?? '';
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _perangkat = <BluetoothInfo>[];
      });
    }
  }

  Future<void> _sambungkan(BluetoothInfo alat) async {
    try {
      if (!await RtsPrinter.izinBluetooth()) {
        if (!mounted) return;

        rtsKsPesan(context, 'Izin Bluetooth belum diberikan.', galat: true);

        return;
      }

      final bool ok = await PrintBluetoothThermal.connect(
        macPrinterAddress: alat.macAdress,
      );

      if (!mounted) return;

      if (ok) {
        await RtsPrinter.simpan(alat.macAdress, alat.name);

        if (!mounted) return;

        setState(() {
          _terhubung = alat.name;
          _tersimpan = alat.macAdress;
        });
        rtsKsPesan(context, 'Tersambung ke ${alat.name}.');
      } else {
        rtsKsPesan(context, 'Gagal menyambung ke ${alat.name}.', galat: true);
      }
    } catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, 'Gagal menyambung: $e', galat: true);
    }
  }

  /// Diameter roll yang tersedia untuk jenis printer yang dipilih.
  List<int> get _daftarRoll => _jenis == '80'
      ? <int>[40, 47, 80, 100, 140]
      : <int>[30, 38, 40, 45, 50];

  /// Mengubah jenis printer: lebar kertas ikut menyesuaikan.
  void _ubahJenis(String? nilai) {
    if (nilai == null) return;

    setState(() {
      _jenis = nilai;
      _lebar = nilai == '80' ? 80 : 58;

      if (!_daftarRoll.contains(_roll)) {
        _roll = _daftarRoll.first;
      }
    });
  }

  Future<void> _simpanTemplate() async {
    try {
      final Map<String, dynamic> hasil = await _api.kirim('struk_simpan', <String, dynamic>{
        'judul': _judul.text.trim(),
        'baris1': _baris1.text.trim(),
        'baris2': _baris2.text.trim(),
        'baris3': _baris3.text.trim(),
        'footer1': _footer1.text.trim(),
        'footer2': _footer2.text.trim(),
        'footer3': _footer3.text.trim(),
        'lebar_kertas': _lebar,
        'jenis_printer': _jenis,
        'diameter_roll': _roll,
        'ukuran_huruf': _huruf,
        'garis': _garis,
        'jumlah_salinan': _salinan,
        'tampilkan_barcode': _barcode ? 1 : 0,
        'tampilkan_hp': _hp ? 1 : 0,
        'tampilkan_ttd': _ttd ? 1 : 0,
        'tampilkan_metode': _metode ? 1 : 0,
      });

      if (!mounted) return;

      final Map<String, dynamic> struk = (hasil['struk'] is Map)
          ? (hasil['struk'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      setState(() => _struk = struk);
      rtsKsPesan(context, '${hasil['message'] ?? 'Template disimpan.'}');
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  Future<void> _ujiCetak() async {
    try {
      final Map<String, dynamic> hasil = await _api.kirim('struk_contoh');

      final Map<String, dynamic> nota = (hasil['nota'] is Map)
          ? (hasil['nota'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      final String galat = await RtsStruk.cetak(nota, _struk);

      if (!mounted) return;

      rtsKsPesan(
        context,
        galat.isEmpty ? 'Contoh struk dikirim ke printer.' : galat,
        galat: galat.isNotEmpty,
      );
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  String get _contoh {
    final int kolom = _lebar >= 76 ? 48 : 32;
    final String garis = List<String>.filled(kolom, _garis.isEmpty ? '-' : _garis).join();
    final StringBuffer t = StringBuffer();

    t.writeln(_judul.text.trim().isEmpty ? 'RTS PANEL' : _judul.text.trim().toUpperCase());

    for (final String b in <String>[_baris1.text, _baris2.text, _baris3.text]) {
      if (b.trim().isNotEmpty) t.writeln(b.trim());
    }

    t.writeln(garis);
    t.writeln('No   : KS-CONTOH-0001');
    t.writeln('Waktu: ${rtsKsWaktuLengkap(DateTime.now().toString())}');
    t.writeln('Toko : TOKO CONTOH');
    t.writeln(garis);
    t.writeln('Produk Contoh 16');
    t.writeln('2 pack x Rp 32.000      Rp 64.000');
    t.writeln('3 batang x Rp 2.200      Rp 6.600');
    t.writeln(garis);
    t.writeln('TOTAL                   Rp 70.600');
    t.writeln('TUNAI                  Rp 100.000');
    t.writeln('KEMBALI                 Rp 29.400');
    t.writeln(garis);

    for (final String f in <String>[_footer1.text, _footer2.text, _footer3.text]) {
      if (f.trim().isNotEmpty) t.writeln(f.trim());
    }

    return t.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: rtsKsLatar,
      appBar: AppBar(
        backgroundColor: rtsKsMaroon,
        foregroundColor: Colors.white,
        title: const Text('Printer & Template Struk'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: <Widget>[
          _kartu(
            judul: '1. JENIS PRINTER & UKURAN KERTAS',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                DropdownButtonFormField<String>(
                  initialValue: _jenis,
                  decoration: const InputDecoration(
                    labelText: 'Jenis printer',
                    border: OutlineInputBorder(),
                  ),
                  items: const <DropdownMenuItem<String>>[
                    DropdownMenuItem<String>(
                      value: '58',
                      child: Text('58 mm - Mini / Mobile Printer'),
                    ),
                    DropdownMenuItem<String>(
                      value: '80',
                      child: Text('80 mm - Desktop / POS Printer'),
                    ),
                  ],
                  onChanged: _ubahJenis,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _daftarRoll.contains(_roll) ? _roll : _daftarRoll.first,
                  decoration: const InputDecoration(
                    labelText: 'Diameter roll kertas',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (final int mm in _daftarRoll)
                      DropdownMenuItem<int>(
                        value: mm,
                        child: Text('$mm mm'),
                      ),
                  ],
                  onChanged: (int? nilai) {
                    if (nilai != null) setState(() => _roll = nilai);
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  _jenis == '80'
                      ? 'Printer 80 mm (Desktop / POS): lebar kertas 80 mm, '
                          'umumnya 48 huruf per baris. Diameter roll tersedia: '
                          '40, 47, 80, 100, dan 140 mm.'
                      : 'Printer 58 mm (Mini / Mobile): lebar kertas 58 mm, '
                          'umumnya 32 huruf per baris. Diameter roll tersedia: '
                          '30, 38, 40, 45, dan 50 mm.',
                  style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pilihan ini dipakai untuk menyesuaikan struk dengan printer '
                  'yang Bapak pakai (lebar kertas: $_lebar mm, roll: $_roll mm).',
                  style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _kartu(
            judul: '2. PRINTER BLUETOOTH',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      _terhubung.isEmpty
                          ? Icons.print_disabled_outlined
                          : Icons.print_rounded,
                      color: _terhubung.isEmpty ? rtsKsTeks2 : rtsKsHijau,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _terhubung.isEmpty
                            ? 'Belum tersambung ke printer'
                            : 'Tersambung: $_terhubung',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: rtsKsMaroon),
                      onPressed: _memuat ? null : _muatPrinter,
                    ),
                  ],
                ),
                const Text(
                  'Pasangkan printer terlebih dahulu pada Pengaturan Bluetooth '
                  'HP (PIN biasanya 0000 atau 1234), lalu tekan namanya di '
                  'bawah ini.',
                  style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                ),
                const SizedBox(height: 10),
                if (_memuat) const LinearProgressIndicator(),
                if (_perangkat.isEmpty && !_memuat)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Belum ada perangkat Bluetooth yang dipasangkan dengan HP '
                      'ini.',
                      style: TextStyle(color: rtsKsTeks2),
                    ),
                  ),
                for (final BluetoothInfo alat in _perangkat)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      alat.macAdress == _tersimpan
                          ? Icons.check_circle_rounded
                          : Icons.bluetooth_rounded,
                      color: alat.macAdress == _tersimpan ? rtsKsHijau : rtsKsMaroon,
                    ),
                    title: Text(alat.name),
                    subtitle: Text(
                      alat.macAdress,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: OutlinedButton(
                      onPressed: () => _sambungkan(alat),
                      child: const Text('SAMBUNG'),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await PrintBluetoothThermal.disconnect;

                          if (!mounted) return;

                          setState(() => _terhubung = '');
                          rtsKsPesan(context, 'Sambungan printer diputuskan.');
                        },
                        icon: const Icon(Icons.link_off, size: 18),
                        label: const Text('PUTUSKAN'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                        onPressed: _ujiCetak,
                        icon: const Icon(Icons.receipt_long_rounded, size: 18),
                        label: const Text('UJI CETAK'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _kartu(
            judul: '3. TEMPLATE STRUK (dapat diubah bebas)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _judul,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Judul struk',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _baris1,
                  decoration: const InputDecoration(
                    labelText: 'Baris 1 (nama perusahaan)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _baris2,
                  decoration: const InputDecoration(
                    labelText: 'Baris 2 (alamat / telepon)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _baris3,
                  decoration: const InputDecoration(
                    labelText: 'Baris 3',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Lebar kertas',
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          _jenis == '80' ? '80 mm' : '58 mm',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _huruf,
                        decoration: const InputDecoration(
                          labelText: 'Ukuran huruf',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: 'KECIL', child: Text('Kecil')),
                          DropdownMenuItem<String>(value: 'SEDANG', child: Text('Sedang')),
                          DropdownMenuItem<String>(value: 'BESAR', child: Text('Besar')),
                        ],
                        onChanged: (String? nilai) {
                          if (nilai != null) setState(() => _huruf = nilai);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _salinan,
                        decoration: const InputDecoration(
                          labelText: 'Jumlah salinan',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<int>>[
                          DropdownMenuItem<int>(value: 1, child: Text('1 lembar')),
                          DropdownMenuItem<int>(value: 2, child: Text('2 lembar')),
                          DropdownMenuItem<int>(value: 3, child: Text('3 lembar')),
                        ],
                        onChanged: (int? nilai) {
                          if (nilai != null) setState(() => _salinan = nilai);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _garis,
                        decoration: const InputDecoration(
                          labelText: 'Garis pemisah',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<String>>[
                          DropdownMenuItem<String>(value: '-', child: Text('- - - -')),
                          DropdownMenuItem<String>(value: '=', child: Text('= = = =')),
                          DropdownMenuItem<String>(value: '*', child: Text('* * * *')),
                        ],
                        onChanged: (String? nilai) {
                          if (nilai != null) setState(() => _garis = nilai);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan barcode nomor nota'),
                  value: _barcode,
                  activeThumbColor: rtsKsMaroon,
                  onChanged: (bool nilai) => setState(() => _barcode = nilai),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan nomor HP toko'),
                  value: _hp,
                  activeThumbColor: rtsKsMaroon,
                  onChanged: (bool nilai) => setState(() => _hp = nilai),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan baris tanda tangan'),
                  value: _ttd,
                  activeThumbColor: rtsKsMaroon,
                  onChanged: (bool nilai) => setState(() => _ttd = nilai),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tampilkan metode bayar'),
                  value: _metode,
                  activeThumbColor: rtsKsMaroon,
                  onChanged: (bool nilai) => setState(() => _metode = nilai),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _footer1,
                  decoration: const InputDecoration(
                    labelText: 'Penutup baris 1',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _footer2,
                  decoration: const InputDecoration(
                    labelText: 'Penutup baris 2',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _footer3,
                  decoration: const InputDecoration(
                    labelText: 'Penutup baris 3',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: rtsKsMaroon,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _siap ? _simpanTemplate : null,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('SIMPAN TEMPLATE'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _kartu(
            judul: '3. CONTOH TAMPILAN STRUK',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfff4f1ee),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _contoh,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _kartu({required String judul, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rtsKsGaris),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            judul,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: rtsKsMaroon,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}


/* ------------------------------------------------------------------------- */
/* SERVER & CADANGAN (Sinkron Produk + Cadangkan/Pulihkan data kasir)        */
/* ------------------------------------------------------------------------- */

/// Halaman pengelolaan data kasir yang tersimpan di dalam HP:
///   - SINKRONISASI   : menu utama "SINKRONISASI" (tombol SINKRONKAN
///     SEKARANG) yang mengirim produk baru ke server sekaligus mengunduh
///     daftar SKU + harga serta daftar toko terbaru.
///   - CADANGKAN      : menyalin seluruh database kasir ke sebuah berkas.
///   - PULIHKAN       : mengembalikan data dari berkas cadangan.
class RtsCadanganPage extends StatefulWidget {
  const RtsCadanganPage({
    super.key,
    required this.baseUrl,
    required this.token,
    this.pengguna = const <String, dynamic>{},
  });

  final String baseUrl;
  final String token;
  final Map<String, dynamic> pengguna;

  @override
  State<RtsCadanganPage> createState() => _RtsCadanganPageState();
}

class _RtsCadanganPageState extends State<RtsCadanganPage> {
  late final RtsKasirApi _api = RtsKasirApi(
    baseUrl: widget.baseUrl,
    token: widget.token,
    pengguna: widget.pengguna,
  );

  Map<String, dynamic> _info = <String, dynamic>{};
  List<Map<String, dynamic>> _berkas = <Map<String, dynamic>>[];
  bool _memuat = true;
  bool _kerja = false;
  String _galat = '';

  @override
  void initState() {
    super.initState();
    _muat();
  }

  Future<void> _muat() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Map<String, dynamic> hasil = await _api.kirim('cadangan_info');

      final List<dynamic> berkas =
          (hasil['berkas'] is List) ? hasil['berkas'] as List<dynamic> : <dynamic>[];

      if (!mounted) return;

      setState(() {
        _info = hasil;
        _berkas = berkas
            .whereType<Map>()
            .map((Map<dynamic, dynamic> e) => e.cast<String, dynamic>())
            .toList();
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

  Future<void> _cadangkan() async {
    setState(() => _kerja = true);

    try {
      final Map<String, dynamic> hasil = await _api.kirim('cadangkan');

      if (!mounted) return;

      setState(() => _kerja = false);

      await showDialog<void>(
        context: context,
        builder: (BuildContext ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: <Widget>[
              Icon(Icons.check_circle_rounded, color: rtsKsHijau),
              SizedBox(width: 8),
              Text('Cadangan Dibuat', style: TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Berkas: ${hasil['nama'] ?? '-'}'),
              const SizedBox(height: 8),
              const Text(
                'Berkas cadangan disimpan pada folder aplikasi di HP. Supaya '
                'aman bila HP hilang atau rusak, salin berkas itu ke Google '
                'Drive / WhatsApp dengan cara:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '1. Buka aplikasi "Files" / "File Manager" pada HP.\n'
                '2. Cari folder Android/data/com.example.rts_panel_app/files/cadangan\n'
                '3. Tekan lama berkas cadangan, pilih Bagikan, kirim ke\n'
                '   WhatsApp (diri sendiri) atau unggah ke Google Drive.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              Text(
                'Lokasi: ${hasil['jalur'] ?? hasil['folder'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();

                _kirim(<String, dynamic>{
                  'nama': hasil['nama'],
                  'jalur': hasil['jalur'],
                });
              },
              child: const Text('KIRIM SEKARANG'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('MENGERTI'),
            ),
          ],
        ),
      );

      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _kerja = false);
      rtsKsPesan(context, e.pesan, galat: true);
    }
  }

  /// Membuka layar "Bagikan" Android supaya berkas cadangan dapat dikirim ke
  /// WhatsApp (diri sendiri) atau diunggah ke Google Drive.
  ///
  /// Bila bagian Android (MainActivity.kt) belum diperbarui, aplikasi tidak
  /// mengalami galat - petugas hanya menerima petunjuk menyalin berkas manual.
  Future<void> _kirim(Map<String, dynamic> berkas) async {
    final String jalur = '${berkas['jalur'] ?? ''}';

    if (jalur.isEmpty) {
      rtsKsPesan(
        context,
        'Berkas ${berkas['nama'] ?? ''} tidak dapat dikirim dari aplikasi. '
        'Salin berkasnya melalui aplikasi Files.',
        galat: true,
      );
      return;
    }

    try {
      await const MethodChannel('rts/pembaruan').invokeMethod<dynamic>(
        'bagikan',
        <String, dynamic>{
          'path': jalur,
          'judul': 'Kirim Cadangan RTS Panel',
          'teks': 'Cadangan data kasir RTS Panel (${berkas['nama'] ?? ''}). '
              'Simpan berkas ini di Google Drive atau kirim ke diri sendiri.',
        },
      );
    } on MissingPluginException {
      if (!mounted) return;

      _petunjukSalinManual('${berkas['nama'] ?? ''}');
    } on PlatformException catch (e) {
      if (!mounted) return;

      rtsKsPesan(context, e.message ?? 'Cadangan tidak dapat dikirim.', galat: true);
    }
  }

  void _petunjukSalinManual(String nama) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Kirim Cadangan',
            style: TextStyle(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              'Aplikasi di HP ini belum memuat bagian pengiriman berkas. '
              'Salin berkas cadangan dengan cara berikut:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              '1. Buka aplikasi Files / File Manager.\n'
              '2. Cari folder Android/data/com.example.rts_panel_app/files/cadangan\n'
              '3. Tekan lama berkas $nama, pilih Bagikan, lalu kirim ke '
              'WhatsApp (diri sendiri) atau unggah ke Google Drive.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text(
              'Lokasi folder: ${_info['folder'] ?? ''}',
              style: const TextStyle(fontSize: 11, color: rtsKsTeks2),
            ),
          ],
        ),
        actions: <Widget>[
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('MENGERTI'),
          ),
        ],
      ),
    );
  }

  Future<void> _pulihkan(Map<String, dynamic> berkas) async {
    final bool? setuju = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Pulihkan Data?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text(
          'Seluruh data kasir di HP ini akan diganti dengan isi berkas '
          '${berkas['nama']}. Data yang sekarang tetap disimpan sebagai '
          'berkas .sebelum bila diperlukan.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('BATAL', style: TextStyle(color: rtsKsTeks2)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('PULIHKAN'),
          ),
        ],
      ),
    );

    if (setuju != true) return;

    setState(() => _kerja = true);

    try {
      final Map<String, dynamic> hasil = await _api.kirim(
        'pulihkan',
        <String, dynamic>{'berkas': berkas['nama']},
      );

      if (!mounted) return;

      setState(() => _kerja = false);
      rtsKsPesan(context, '${hasil['message'] ?? 'Data dipulihkan.'}');
      _muat();
    } on RtsKasirGalat catch (e) {
      if (!mounted) return;

      setState(() => _kerja = false);
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
        title: const Text('Server & Cadangan'),
      ),
      body: _memuat
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(14),
              children: <Widget>[
                _kartu(
                  judul: 'DATA DI DALAM HP INI',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _baris('Jumlah produk', '${_info['jumlah_produk'] ?? 0}'),
                      _baris('Jumlah nota', '${_info['jumlah_nota'] ?? 0}'),
                      _baris('Jumlah piutang', '${_info['jumlah_piutang'] ?? 0}'),
                      _baris(
                        'Sinkron terakhir',
                        '${_info['sinkron_terakhir'] ?? ''}'.trim().isEmpty
                            ? 'belum pernah'
                            : '${_info['sinkron_terakhir']}',
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Seluruh stok, penjualan, piutang, dan template struk '
                        'tersimpan di dalam HP ini. Aplikasi tetap dapat '
                        'dipakai tanpa internet.',
                        style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _kartu(
                  judul: 'PRODUK DARI SERVER (SKU & HARGA)',
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Server menyimpan daftar produk (nama, barcode, isi per '
                        'pack) beserta harganya, dan seluruh HP disamakan '
                        'lewat menu SINKRONISASI pada menu utama (tombol '
                        'SINKRONKAN SEKARANG). Perlu internet sesekali saja.',
                        style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _kartu(
                  judul: 'CADANGAN DATA (PENTING)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Data kasir hanya ada di HP. Bila HP hilang, rusak, '
                        'atau aplikasi dihapus, datanya ikut hilang. Lakukan '
                        'cadangan sekurangnya sekali seminggu, lalu tekan '
                        'KIRIM supaya salinannya tersimpan di Google Drive '
                        'atau WhatsApp.',
                        style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: rtsKsHijau,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                        onPressed: _kerja ? null : _cadangkan,
                        icon: const Icon(Icons.save_alt_rounded),
                        label: const Text('CADANGKAN SEKARANG'),
                      ),
                      const SizedBox(height: 12),
                      if (_berkas.isEmpty)
                        const Text(
                          'Belum ada berkas cadangan.',
                          style: TextStyle(fontSize: 12, color: rtsKsTeks2),
                        ),
                      for (final Map<String, dynamic> b in _berkas)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.description_outlined,
                              color: rtsKsMaroon),
                          title: Text(
                            '${b['nama']}',
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Text(
                            '${b['waktu']} - ${b['ukuran_teks']}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: rtsKsHijau,
                                  side: const BorderSide(color: rtsKsHijau),
                                ),
                                onPressed: _kerja ? null : () => _kirim(b),
                                child: const Text('KIRIM'),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                onPressed: _kerja ? null : () => _pulihkan(b),
                                child: const Text('PULIHKAN'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                if (_galat.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_galat, style: const TextStyle(color: rtsKsMerah)),
                  ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Widget _baris(String judul, String nilai) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(judul, style: const TextStyle(color: rtsKsTeks2, fontSize: 13)),
          ),
          Expanded(
            child: Text(nilai, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _kartu({required String judul, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: rtsKsGaris),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            judul,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: rtsKsMaroon,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
