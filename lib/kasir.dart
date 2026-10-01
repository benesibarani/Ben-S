/// ============================================================================
///  RTS PANEL BY BENE - FITUR PRO : BARANG BAWAAN & KASIR
///  Berkas : lib/kasir.dart
///  Versi  : 1   (1 Oktober 2026)
///
///  ISI BERKAS INI (semua tampilan kasir, dipisah dari main.dart supaya
///  pembaruan berikutnya cukup mengganti satu berkas):
///
///     1. RtsBarangBawaanPage  - 3 tab: PRODUK, STOK, RIWAYAT
///     2. RtsKasirPage         - kasir: scan barcode, keranjang, bayar
///                               CASH / UTANG / TITIP, simpan nota
///     3. RtsNotaPage          - riwayat nota + cetak ulang + batalkan
///     4. RtsPiutangPage       - daftar utang & titip, angsuran sampai lunas
///     5. RtsPrinterPage       - hubungkan printer Bluetooth, UJI CETAK,
///                               dan template struk yang dapat diedit bebas
///     6. RtsPilihBarcodePage  - pemindai barcode memakai kamera HP
///     7. RtsPilihCustomerPage - memilih toko dari Master Customer
///
///  CATATAN PENTING
///  ---------------
///  - Berkas ini TIDAK memanggil berkas lain di dalam proyek (hanya paket
///    Flutter), supaya tidak ada lingkaran impor dengan main.dart.
///    Alamat server dan token dikirim dari main.dart saat halaman dibuka.
///  - Seluruh nama dan pesan memakai Bahasa Indonesia yang mudah dibaca sales.
///  - Printer yang didukung: thermal 58 mm / 80 mm berbahasa ESC/POS melalui
///    Bluetooth (RPP02, Xprinter P323B, EPPOS, Mypos, dan sejenisnya).
/// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Kesalahan yang membawa keterangan tambahan (perlu PRO / server belum siap).
class RtsKasirGalat implements Exception {
  RtsKasirGalat(this.pesan, {this.perluPro = false, this.perluSiap = false});

  final String pesan;
  final bool perluPro;
  final bool perluSiap;

  @override
  String toString() => pesan;
}

/// Penghubung ke api/kasir.php.
class RtsKasirApi {
  RtsKasirApi({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  Future<Map<String, dynamic>> kirim(
    String aksi, [
    Map<String, dynamic> data = const <String, dynamic>{},
  ]) async {
    final Uri uri = Uri.parse('$baseUrl/kasir.php');

    try {
      final http.Response jawab = await http
          .post(
            uri,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(<String, dynamic>{'aksi': aksi, ...data}),
          )
          .timeout(const Duration(seconds: 45));

      final dynamic urai = jsonDecode(jawab.body);

      if (urai is! Map) {
        throw RtsKasirGalat('Jawaban server tidak dikenali.');
      }

      final Map<String, dynamic> peta = urai.cast<String, dynamic>();
      final String pesan = '${peta['message'] ?? 'Permintaan gagal.'}';

      if (peta['perlu_pro'] == true || jawab.statusCode == 403) {
        throw RtsKasirGalat(pesan, perluPro: true);
      }

      if (peta['perlu_siap'] == true || jawab.statusCode == 409) {
        throw RtsKasirGalat(pesan, perluSiap: true);
      }

      if (jawab.statusCode == 401) {
        throw RtsKasirGalat('Sesi berakhir. Silakan masuk kembali.');
      }

      if (peta['success'] != true) {
        throw RtsKasirGalat(pesan);
      }

      return peta;
    } on RtsKasirGalat {
      rethrow;
    } catch (_) {
      throw RtsKasirGalat(
        'Tidak dapat terhubung ke server. Periksa sambungan internet Anda.',
      );
    }
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
    required this.barcodeBatang,
    required this.isiPerPack,
    required this.hargaPack,
    required this.hargaBatang,
    required this.stokPack,
    required this.stokBatang,
    this.aktif = true,
    this.catatan = '',
  });

  final int id;
  final String nama;
  final String merek;
  final String barcodePack;
  final String barcodeBatang;
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
      barcodeBatang: '${j['barcode_batang'] ?? ''}',
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

    // Barcode nomor nota (bila printer mendukung)
    if (template['tampilkan_barcode'] != 0) {
      bytes.addAll(g.feed(1));

      try {
        bytes.addAll(g.barcode(Barcode.code128('${nota['nomor'] ?? ''}')));
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
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);
  late final TabController _tab = TabController(length: 3, vsync: this);

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
    if (_produk.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Belum ada produk. Tekan tombol "Produk" di bawah untuk menambah '
            'barang yang Bapak bawa, lengkap dengan barcodenya.',
            textAlign: TextAlign.center,
            style: TextStyle(color: rtsKsTeks2),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _muat,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        itemCount: _produk.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (BuildContext ctx, int i) {
          final RtsProduk p = _produk[i];

          return _kartu(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                  if (p.barcodePack.isNotEmpty)
                    Text(
                      'Barcode: ${p.barcodePack}',
                      style: const TextStyle(fontSize: 12, color: rtsKsTeks2),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, color: rtsKsMaroon),
                onPressed: () => _formProduk(p),
              ),
            ),
          );
        },
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
                      ],
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
                'Belum ada produk. Tambahkan produk terlebih dahulu pada tab '
                'PRODUK.',
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
  final TextEditingController _barcodePack = TextEditingController();
  final TextEditingController _barcodeBatang = TextEditingController();
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
      _barcodePack.text = p.barcodePack;
      _barcodeBatang.text = p.barcodeBatang;
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
    _barcodePack.dispose();
    _barcodeBatang.dispose();
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
        'barcode_pack': _barcodePack.text.trim(),
        'barcode_batang': _barcodeBatang.text.trim(),
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
          const Text(
            'BARCODE',
            style: TextStyle(fontWeight: FontWeight.w800, color: rtsKsTeks2),
          ),
          const SizedBox(height: 8),
          _barisBarcode(
            label: 'Barcode PACK (bungkus)',
            controller: _barcodePack,
          ),
          const SizedBox(height: 10),
          _barisBarcode(
            label: 'Barcode BATANG (bila ada)',
            controller: _barcodeBatang,
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
              'Harga ini berlaku untuk semua sales. Bila dikosongkan, harga '
              'batang dihitung otomatis dari harga pack dibagi isi per pack.',
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
  final MobileScannerController _kamera = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _sudahDapat = false;
  String _galat = '';

  @override
  void dispose() {
    _kamera.dispose();
    super.dispose();
  }

  void _dapat(BarcodeCapture tangkap) {
    if (_sudahDapat) return;

    final List<Barcode> kode = tangkap.barcodes;

    for (final Barcode b in kode) {
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
                MobileScanner(
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
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);
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
                p.barcodePack.contains(cari) ||
                p.barcodeBatang.contains(cari))
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
/* PILIH TOKO DARI MASTER CUSTOMER                                           */
/* ------------------------------------------------------------------------- */

class RtsPilihCustomerPage extends StatefulWidget {
  const RtsPilihCustomerPage({
    super.key,
    required this.baseUrl,
    required this.token,
  });

  final String baseUrl;
  final String token;

  @override
  State<RtsPilihCustomerPage> createState() => _RtsPilihCustomerPageState();
}

class _RtsPilihCustomerPageState extends State<RtsPilihCustomerPage> {
  final TextEditingController _cari = TextEditingController();
  List<Map<String, dynamic>> _hasil = <Map<String, dynamic>>[];
  bool _memuat = false;
  String _galat = '';

  Future<void> _cariToko() async {
    setState(() {
      _memuat = true;
      _galat = '';
    });

    try {
      final Uri uri = Uri.parse('${widget.baseUrl}/customers.php').replace(
        queryParameters: <String, String>{
          'q': _cari.text.trim(),
          'limit': '30',
        },
      );

      final http.Response jawab = await http.get(
        uri,
        headers: <String, String>{
          'Accept': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
      ).timeout(const Duration(seconds: 30));

      final dynamic urai = jsonDecode(jawab.body);
      final Map<String, dynamic> peta =
          (urai is Map) ? urai.cast<String, dynamic>() : <String, dynamic>{};

      final List<dynamic> items =
          (peta['items'] is List) ? peta['items'] as List<dynamic> : <dynamic>[];

      final List<Map<String, dynamic>> daftar = <Map<String, dynamic>>[];

      for (final dynamic item in items) {
        if (item is! Map) continue;

        final Map<String, dynamic> baris = item.cast<String, dynamic>();

        daftar.add(<String, dynamic>{
          'id': '${baris['id_customer'] ?? baris['id'] ?? baris['kode'] ?? ''}',
          'nama': '${baris['nama_toko'] ?? baris['nama'] ?? baris['nama_customer'] ?? ''}',
          'hp': '${baris['nomor_hp'] ?? baris['hp'] ?? baris['telepon'] ?? ''}',
          'alamat': '${baris['alamat'] ?? ''}',
        });
      }

      if (!mounted) return;

      setState(() {
        _hasil = daftar;
        _memuat = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _memuat = false;
        _galat = 'Daftar toko tidak dapat dibaca. Isi nama toko secara manual '
            'pada halaman kasir.';
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
        title: const Text('Pilih Toko'),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _cari,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _cariToko(),
                    decoration: const InputDecoration(
                      hintText: 'Nama toko atau ID customer',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: rtsKsMaroon),
                    onPressed: _memuat ? null : _cariToko,
                    child: const Text('CARI'),
                  ),
                ),
              ],
            ),
          ),
          if (_galat.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(_galat, style: const TextStyle(color: rtsKsMerah)),
            ),
          if (_memuat) const LinearProgressIndicator(),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _hasil.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext ctx, int i) {
                final Map<String, dynamic> t = _hasil[i];

                return ListTile(
                  title: Text(
                    '${t['nama']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    rtsKsSambung('ID: ${t['id']}', '${t['hp']}'),
                  ),
                  onTap: () => Navigator.of(ctx).pop(t),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/* ------------------------------------------------------------------------- */
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
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

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
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

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
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

  final TextEditingController _cari = TextEditingController();

  List<Map<String, dynamic>> _piutang = <Map<String, dynamic>>[];
  String _jenis = '';
  bool _hanyaBelum = true;
  bool _memuat = true;
  String _galat = '';
  String _belumTeks = '0';

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
                  icon: const Icon(Icons.refresh, color: rtsKsMaroon),
                  onPressed: _muat,
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
  });

  final String baseUrl;
  final String token;

  @override
  State<RtsPrinterPage> createState() => _RtsPrinterPageState();
}

class _RtsPrinterPageState extends State<RtsPrinterPage> {
  late final RtsKasirApi _api =
      RtsKasirApi(baseUrl: widget.baseUrl, token: widget.token);

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
            judul: '1. PRINTER BLUETOOTH',
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
            judul: '2. TEMPLATE STRUK (dapat diubah bebas)',
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
                      child: DropdownButtonFormField<int>(
                        initialValue: _lebar,
                        decoration: const InputDecoration(
                          labelText: 'Lebar kertas',
                          border: OutlineInputBorder(),
                        ),
                        items: const <DropdownMenuItem<int>>[
                          DropdownMenuItem<int>(value: 58, child: Text('58 mm (RPP02)')),
                          DropdownMenuItem<int>(value: 80, child: Text('80 mm')),
                        ],
                        onChanged: (int? nilai) {
                          if (nilai != null) setState(() => _lebar = nilai);
                        },
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
