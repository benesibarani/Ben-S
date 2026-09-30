package com.example.rts_panel_app

/*
 * ============================================================================
 *  RTS PANEL BY BENE - PEMBARUAN LANGSUNG DI DALAM APLIKASI
 *  Berkas : MainActivity.kt
 *
 *  Letak berkas ini di proyek Flutter Bapak:
 *      D:\Project\rts_panel_app\android\app\src\main\kotlin\
 *          com\example\rts_panel_app\MainActivity.kt
 *
 *  Gantilah isi berkas MainActivity.kt yang ada dengan berkas ini
 *  (seluruh isinya, bukan sebagian).
 *
 *  APA YANG DITAMBAHKAN
 *  --------------------
 *  Sebelumnya, menekan tombol UPDATE membuka Google Chrome: berkas diunduh
 *  oleh Chrome, lalu petugas harus mencari berkas itu dan menekan Pasang
 *  sendiri. Dengan berkas ini, seluruh proses dikerjakan OLEH APLIKASI:
 *
 *     1. UNDUH   - aplikasi meminta Android (layanan DownloadManager)
 *                  mengunduh berkas APK. Unduhan berjalan di latar belakang,
 *                  tidak terputus walau layar HP dimatikan, dan TIDAK
 *                  memerlukan izin penyimpanan (berkas disimpan pada folder
 *                  khusus aplikasi).
 *     2. KEMAJUAN- aplikasi menampilkan persen unduhan, dan pemberitahuan
 *                  Android juga memuat bilah kemajuan.
 *     3. PASANG  - begitu unduhan selesai, layar "Pasang" Android dibuka
 *                  SENDIRI oleh aplikasi - walaupun kotak kemajuan sudah
 *                  ditutup petugas, sebab pemeriksa kemajuan dijalankan dari
 *                  bagian Android ini. Petugas cukup menekan PASANG sekali.
 *     4. TERBUKA - sesudah pemasangan selesai, aplikasi berusaha membuka
 *                  dirinya sendiri lewat RtsPenerimaPembaruan.kt. Bila Android
 *                  menolak (aturan keamanan Android 10 ke atas), petugas cukup
 *                  menekan tombol BUKA pada layar pemasangan.
 *
 *  IZIN YANG DIPERLUKAN (sekali saja untuk seterusnya)
 *  ---------------------------------------------------
 *  Android 8 ke atas mewajibkan izin "Instal aplikasi tidak dikenal" untuk
 *  aplikasi yang memasang APK. Bila izin itu belum diberikan, berkas ini
 *  mengembalikan keadaan IZIN_DIPERLUKAN, dan aplikasi menampilkan tombol
 *  yang membuka halaman pengaturan izin tersebut.
 *
 *  AMAN GAGAL
 *  ----------
 *  Bila berkas ini TIDAK dipasang (proyek masih memakai MainActivity lama),
 *  aplikasi tetap berjalan seperti biasa: tombol UPDATE memakai cara lama,
 *  yaitu membuka peramban (Chrome). Jadi tidak ada yang rusak.
 *
 *  BERKAS YANG BERKAITAN
 *  --------------------
 *    RtsPenerimaPembaruan.kt  - membuka aplikasi sesudah pembaruan terpasang
 *    file_paths.xml           - daftar folder untuk aplikasi pemasang Android
 *    AndroidManifest.xml      - izin REQUEST_INSTALL_PACKAGES + <provider>
 *                               + <receiver> untuk pembaruan
 * ============================================================================
 */

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    /** Nama saluran penghubung ke bagian Dart (main.dart). */
    private val saluran = "rts/pembaruan"

    /** Nama berkas hasil unduhan pada folder khusus aplikasi. */
    private val namaBerkas = "rts_panel_update.apk"

    /** Nomor unduhan yang sedang berjalan (-1 = belum ada). */
    private var idUnduhan: Long = -1L

    /** Keterangan kegagalan yang terakhir terjadi. */
    private var pesanGalat = ""

    /** Bernilai true bila layar Pasang sudah pernah dibuka untuk unduhan ini. */
    private var sudahMemasang = false

    /** Pengatur waktu untuk memeriksa kemajuan unduhan secara berkala. */
    private val penjadwal = Handler(Looper.getMainLooper())

    /**
     * Pemeriksa kemajuan unduhan.
     *
     * Berjalan sendiri selama aplikasi hidup, sehingga layar "Pasang" tetap
     * terbuka OTOMATIS begitu unduhan selesai - walau petugas menekan
     * SEMBUNYIKAN pada kotak kemajuan, atau berpindah ke menu lain.
     */
    private val pemantau = object : Runnable {
        override fun run() {
            if (idUnduhan <= 0L) return

            val keadaan = keadaanUnduhan()
            val status = keadaan["status"]?.toString() ?: ""

            if (status == "DIMULAI" || status == "MENGUNDUH") {
                penjadwal.postDelayed(this, 700L)
            }
            // SELESAI / GAGAL / IZIN_DIPERLUKAN / TIDAK ADA: pemeriksaan berhenti.
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, saluran)
            .setMethodCallHandler { panggilan, hasil ->
                try {
                    tanganiPermintaan(panggilan, hasil)
                } catch (galat: Exception) {
                    hasil.success(petaGagal("Gagal menyiapkan pembaruan: "
                        + (galat.message ?: "sebab tidak diketahui")))
                }
            }
    }

    /* ---------------------------------------------------------------------- */
    /* Penanganan permintaan dari Dart                                        */
    /* ---------------------------------------------------------------------- */

    private fun tanganiPermintaan(panggilan: MethodCall, hasil: MethodChannel.Result) {
        when (panggilan.method) {
            "pasang" -> {
                val alamat = panggilan.argument<String>("url") ?: ""

                if (alamat.isEmpty()) {
                    hasil.success(petaGagal("Alamat unduhan pembaruan kosong."))
                    return
                }

                if (!bolehPasang()) {
                    hasil.success(peta("status" to "IZIN_DIPERLUKAN",
                        "pesan" to "Android memerlukan izin pemasangan untuk aplikasi ini."))
                    return
                }

                hasil.success(mulaiUnduh(alamat))
            }

            "status" -> hasil.success(keadaanUnduhan())

            "bukaIzin" -> {
                bukaSetelanIzin()
                hasil.success(true)
            }

            "pasangTersimpan" -> hasil.success(pasangBerkasTersimpan())

            else -> hasil.notImplemented()
        }
    }

    /* ---------------------------------------------------------------------- */
    /* 1. MENGUNDUH                                                           */
    /* ---------------------------------------------------------------------- */

    private fun mulaiUnduh(alamat: String): Map<String, Any> {
        val pengelola = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            ?: return petaGagal("Layanan unduhan Android tidak tersedia pada HP ini.")

        // Unduhan lama dibersihkan supaya berkas yang tersimpan selalu yang baru.
        if (idUnduhan > 0L) {
            try {
                pengelola.remove(idUnduhan)
            } catch (_: Exception) {
                // diabaikan
            }
        }

        val berkasLama = File(folderUnduhan(), namaBerkas)

        if (berkasLama.exists()) {
            berkasLama.delete()
        }

        val permintaan = DownloadManager.Request(Uri.parse(alamat))
            .setTitle("Pembaruan RTS Panel")
            .setDescription("Mengunduh versi terbaru RTS Panel...")
            .setMimeType("application/vnd.android.package-archive")
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED
            )
            .setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, namaBerkas)

        pesanGalat = ""
        sudahMemasang = false

        idUnduhan = try {
            pengelola.enqueue(permintaan)
        } catch (galat: Exception) {
            return petaGagal("Unduhan tidak dapat dimulai: "
                + (galat.message ?: "sebab tidak diketahui"))
        }

        if (idUnduhan <= 0L) {
            return petaGagal("Unduhan tidak dapat dimulai.")
        }

        // Pemeriksa kemajuan dijalankan sendiri oleh bagian Android. Dengan
        // begitu layar Pasang dapat terbuka otomatis walaupun kotak kemajuan
        // pada aplikasi sudah ditutup oleh petugas.
        penjadwal.removeCallbacks(pemantau)
        penjadwal.postDelayed(pemantau, 700L)

        return peta("status" to "DIMULAI", "pesan" to "Unduhan dimulai.")
    }

    /**
     * Sesudah petugas menghidupkan izin pemasangan pada Pengaturan Android dan
     * kembali ke aplikasi, pemeriksaan dilanjutkan supaya layar Pasang langsung
     * terbuka tanpa menekan PERBARUI SEKARANG lagi.
     */
    override fun onResume() {
        super.onResume()

        if (idUnduhan > 0L && !sudahMemasang) {
            penjadwal.removeCallbacks(pemantau)
            penjadwal.postDelayed(pemantau, 400L)
        }
    }

    override fun onDestroy() {
        penjadwal.removeCallbacks(pemantau)

        super.onDestroy()
    }

    /* ---------------------------------------------------------------------- */
    /* 2. MEMERIKSA KEMAJUAN UNDUHAN                                          */
    /* ---------------------------------------------------------------------- */

    private fun keadaanUnduhan(): Map<String, Any> {
        if (idUnduhan == -1L) {
            return peta("status" to "TIDAK ADA")
        }

        if (idUnduhan < 0L) {
            return petaGagal(pesanGalat.ifEmpty { "Unduhan gagal." })
        }

        val pengelola = getSystemService(Context.DOWNLOAD_SERVICE) as? DownloadManager
            ?: return petaGagal("Layanan unduhan Android tidak tersedia.")

        val kursor = try {
            pengelola.query(DownloadManager.Query().setFilterById(idUnduhan))
        } catch (galat: Exception) {
            null
        }

        if (kursor == null) {
            return petaGagal("Kemajuan unduhan tidak dapat dibaca.")
        }

        if (!kursor.moveToFirst()) {
            kursor.close()

            return peta("status" to "TIDAK ADA")
        }

        val keadaan = kursor.getInt(
            kursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
        )

        val terunduh = kursor.getLong(
            kursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
        )

        var total = kursor.getLong(
            kursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
        )

        val sebab = kursor.getInt(
            kursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
        )

        kursor.close()

        if (total <= 0L) {
            total = -1L
        }

        val persen = if (total > 0L) {
            ((terunduh * 100) / total).toInt().coerceIn(0, 100)
        } else {
            0
        }

        if (keadaan == DownloadManager.STATUS_SUCCESSFUL) {
            if (!sudahMemasang) {
                // Izin pemasangan diperiksa LEBIH DAHULU. Bila belum diizinkan,
                // keadaan IZIN_DIPERLUKAN dikembalikan lagi pada pemeriksaan
                // berikutnya, sehingga sesudah petugas menghidupkan izinnya,
                // layar Pasang langsung terbuka tanpa mengunduh ulang.
                if (!bolehPasang()) {
                    return peta("status" to "IZIN_DIPERLUKAN",
                        "pesan" to "Izinkan pemasangan untuk aplikasi RTS Panel.",
                        "persen" to 100)
                }

                if (pasangBerkasTersimpan()) {
                    sudahMemasang = true
                } else {
                    return petaGagal(pesanGalat.ifEmpty { "Layar pemasangan tidak dapat dibuka." })
                }
            }

            return peta("status" to "SELESAI", "terunduh" to total,
                "total" to total, "persen" to 100)
        }

        if (keadaan == DownloadManager.STATUS_FAILED) {
            return petaGagal(sebabUnduhan(sebab))
        }

        if (keadaan == DownloadManager.STATUS_PAUSED) {
            return peta("status" to "MENGUNDUH", "terunduh" to terunduh,
                "total" to total, "persen" to persen,
                "pesan" to "Unduhan tertunda, menunggu sambungan internet.")
        }

        return peta("status" to "MENGUNDUH", "terunduh" to terunduh,
            "total" to total, "persen" to persen)
    }

    /* ---------------------------------------------------------------------- */
    /* 3. MEMBUKA LAYAR PASANG                                                */
    /* ---------------------------------------------------------------------- */

    private fun pasangBerkasTersimpan(): Boolean {
        val berkas = File(folderUnduhan(), namaBerkas)

        if (!berkas.exists() || berkas.length() <= 0L) {
            pesanGalat = "Berkas pembaruan tidak ditemukan pada HP."

            return false
        }

        val alamat: Uri = try {
            FileProvider.getUriForFile(this, "$packageName.rtsberkas", berkas)
        } catch (galat: Exception) {
            pesanGalat = "Berkas pembaruan tidak dapat dibuka: "
                + (galat.message ?: "sebab tidak diketahui")

            return false
        }

        val niat = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(alamat, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            startActivity(niat)

            true
        } catch (galat: Exception) {
            pesanGalat = "Layar pemasangan tidak dapat dibuka. "

            false
        }
    }

    /* ---------------------------------------------------------------------- */
    /* Penunjang                                                              */
    /* ---------------------------------------------------------------------- */

    private fun folderUnduhan(): File {
        val folder = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(filesDir, "unduhan")

        if (!folder.exists()) {
            folder.mkdirs()
        }

        return folder
    }

    /** Android 8 ke atas: pemasangan APK memerlukan izin dari pengguna. */
    private fun bolehPasang(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    /** Membuka halaman pengaturan "Instal aplikasi tidak dikenal". */
    private fun bukaSetelanIzin() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }

        try {
            val niat = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:$packageName"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

            startActivity(niat)
        } catch (_: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
            } catch (_: Exception) {
                // diabaikan
            }
        }
    }

    /** Keterangan kegagalan unduhan dari Android. */
    private fun sebabUnduhan(sebab: Int): String {
        return when (sebab) {
            DownloadManager.ERROR_INSUFFICIENT_SPACE ->
                "Penyimpanan HP tidak cukup untuk mengunduh pembaruan."
            DownloadManager.ERROR_DEVICE_NOT_FOUND ->
                "Kartu penyimpanan tidak ditemukan."
            DownloadManager.ERROR_HTTP_DATA_ERROR ->
                "Sambungan internet terputus saat mengunduh. Coba lagi."
            DownloadManager.ERROR_TOO_MANY_REDIRECTS ->
                "Alamat unduhan berubah terlalu banyak kali. Hubungi Admin."
            DownloadManager.ERROR_FILE_ERROR ->
                "Berkas pembaruan gagal disimpan pada HP."
            DownloadManager.ERROR_UNHANDLED_HTTP_CODE ->
                "Server menolak permintaan unduhan (berkas tidak ditemukan)."
            DownloadManager.ERROR_CANNOT_RESUME ->
                "Unduhan tidak dapat dilanjutkan. Coba lagi dari awal."
            else ->
                "Unduhan gagal (kode $sebab). Periksa sambungan internet."
        }
    }

    private fun peta(vararg pasangan: Pair<String, Any>): Map<String, Any> {
        val hasil = HashMap<String, Any>()

        for (pasanganSatu in pasangan) {
            hasil[pasanganSatu.first] = pasanganSatu.second
        }

        return hasil
    }

    private fun petaGagal(pesan: String): Map<String, Any> {
        pesanGalat = pesan

        return peta("status" to "GAGAL", "pesan" to pesan)
    }
}
