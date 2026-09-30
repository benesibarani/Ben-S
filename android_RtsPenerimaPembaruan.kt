package com.example.rts_panel_app

/*
 * ============================================================================
 *  RTS PANEL BY BENE - MEMBUKA APLIKASI SESUDAH PEMBARUAN TERPASANG
 *  Berkas : RtsPenerimaPembaruan.kt
 *
 *  Letak berkas ini di proyek Flutter Bapak:
 *      D:\Project\rts_panel_app\android\app\src\main\kotlin\
 *          com\example\rts_panel_app\RtsPenerimaPembaruan.kt
 *
 *  Berkas ini bekerja bersama MainActivity.kt dan file_paths.xml.
 *
 *  APA YANG DIKERJAKAN
 *  -------------------
 *  Sesudah Android selesai memasang pembaruan, Android mengirim pesan
 *  "MY_PACKAGE_REPLACED" kepada aplikasi yang baru diperbarui. Berkas ini
 *  menerima pesan itu, lalu:
 *
 *      1. BERUSAHA MEMBUKA APLIKASI SENDIRI supaya petugas tidak perlu
 *         mencari ikonnya. (Pada layar pemasangan Android, tombol BUKA juga
 *         tersedia - keduanya sah.)
 *
 *      2. Bila Android menolak pembukaan otomatis - sejak Android 10, aplikasi
 *         yang sedang tidak tampil di layar dibatasi untuk membuka layar baru -
 *         maka berkas ini menampilkan PEMBERITAHUAN
 *         "Pembaruan RTS Panel Selesai". Menekan pemberitahuan itu membuka
 *         aplikasi. Penolakan itu bukan kerusakan; itulah aturan keamanan
 *         Android yang tidak dapat dilewati aplikasi biasa.
 *
 *  Keterangan: pada banyak HP, langkah 1 berhasil sehingga aplikasi langsung
 *  terbuka memakai versi barunya. Pada sebagian HP, pemberitahuan pada langkah
 *  2 yang muncul. Keduanya membuat petugas tetap dapat masuk dengan satu
 *  sentuhan, tanpa mencari ikon di layar.
 *
 *  AMAN GAGAL
 *  ----------
 *  Seluruh isinya dibungkus penangkap kesalahan. Bila berkas ini tidak
 *  dipasang pun, aplikasi tetap berjalan normal - hanya pembukaan otomatis
 *  sesudah pembaruan yang tidak ada.
 * ============================================================================
 */

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build

import androidx.core.app.NotificationCompat

class RtsPenerimaPembaruan : BroadcastReceiver() {

    companion object {
        /** Nama saluran pemberitahuan pembaruan (sama dengan aplikasi). */
        private const val SALURAN = "rts_pembaruan"

        /** Nomor tetap supaya pemberitahuan tidak menumpuk. */
        private const val NOMOR = 9003
    }

    override fun onReceive(konteks: Context, niat: Intent) {
        if (niat.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        // ---------------------------------------------------------------
        // 1. Berusaha membuka aplikasi sendiri.
        // ---------------------------------------------------------------
        try {
            val buka = Intent(konteks, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra("rts_pembaruan_selesai", true)
            }

            konteks.startActivity(buka)

            return
        } catch (_: Exception) {
            // Android menolak pembukaan otomatis - lanjut ke langkah 2.
        }

        // ---------------------------------------------------------------
        // 2. Pemberitahuan: menekannya membuka aplikasi.
        // ---------------------------------------------------------------
        try {
            tampilkanPemberitahuan(konteks)
        } catch (_: Exception) {
            // pemberitahuan tidak dapat ditampilkan - diabaikan
        }
    }

    private fun tampilkanPemberitahuan(konteks: Context) {
        val pengelola = konteks.getSystemService(Context.NOTIFICATION_SERVICE)
            as? NotificationManager ?: return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val saluran = NotificationChannel(
                SALURAN,
                "Pembaruan Aplikasi",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Pemberitahuan sesudah aplikasi diperbarui."
            }

            pengelola.createNotificationChannel(saluran)
        }

        val bukaAplikasi = Intent(konteks, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            putExtra("rts_pembaruan_selesai", true)
        }

        val penanti = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.getActivity(
                konteks,
                NOMOR,
                bukaAplikasi,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                konteks,
                NOMOR,
                bukaAplikasi,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        val lambang = try {
            konteks.applicationInfo.icon
        } catch (_: Exception) {
            android.R.drawable.stat_sys_download_done
        }

        val pemberitahuan = NotificationCompat.Builder(konteks, SALURAN)
            .setSmallIcon(lambang)
            .setContentTitle("Pembaruan RTS Panel Selesai")
            .setContentText("Tekan untuk membuka aplikasi versi terbaru.")
            .setAutoCancel(true)
            .setContentIntent(penanti)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()

        pengelola.notify(NOMOR, pemberitahuan)
    }
}
