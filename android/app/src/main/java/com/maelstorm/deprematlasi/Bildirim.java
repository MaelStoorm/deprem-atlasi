/*
 * Deprem Atlası — deprem bildirimleri (uygulamanın kendi bildirimi).
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
package com.maelstorm.deprematlasi;

import android.Manifest;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.os.Build;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;
import androidx.core.content.ContextCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.NetworkType;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import java.util.concurrent.TimeUnit;

/**
 * Bildirim ayarları ve gösterimi. Kontrol, WorkManager ile yaklaşık 15 dakikada bir yapılır
 * (Android'in izin verdiği en kısa aralık; telefon uzun süre kullanılmazsa daha seyrek olabilir).
 */
final class Bildirim {

    static final String KANAL = "depremler";
    private static final String IS = "deprem-kontrol";
    private static final String AYAR = "bildirim";

    private Bildirim() { }

    static SharedPreferences ayar(Context c) {
        return c.getSharedPreferences(AYAR, Context.MODE_PRIVATE);
    }

    static boolean acik(Context c) {
        return ayar(c).getBoolean("acik", false);
    }

    static double esik(Context c) {
        return Double.longBitsToDouble(ayar(c).getLong("esik", Double.doubleToLongBits(4.0)));
    }

    static void esikYaz(Context c, double v) {
        ayar(c).edit().putLong("esik", Double.doubleToLongBits(v)).apply();
    }

    static boolean izinVar(Context c) {
        if (Build.VERSION.SDK_INT >= 33
                && ContextCompat.checkSelfPermission(c, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) return false;
        return NotificationManagerCompat.from(c).areNotificationsEnabled();
    }

    static void kanalKur(Context c) {
        if (Build.VERSION.SDK_INT < 26) return;
        NotificationManager nm = c.getSystemService(NotificationManager.class);
        if (nm == null || nm.getNotificationChannel(KANAL) != null) return;
        NotificationChannel k = new NotificationChannel(KANAL, c.getString(R.string.kanal_adi),
                NotificationManager.IMPORTANCE_HIGH);
        k.setDescription(c.getString(R.string.kanal_aciklama));
        nm.createNotificationChannel(k);
    }

    static void ac(Context c, double esik) {
        esikYaz(c, esik);
        ayar(c).edit().putBoolean("acik", true).putBoolean("ilk", true).apply();
        kanalKur(c);
        Constraints k = new Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build();
        PeriodicWorkRequest is = new PeriodicWorkRequest.Builder(DepremIsci.class, 15, TimeUnit.MINUTES)
                .setConstraints(k).build();
        WorkManager.getInstance(c).enqueueUniquePeriodicWork(IS, ExistingPeriodicWorkPolicy.UPDATE, is);
    }

    static void kapat(Context c) {
        ayar(c).edit().putBoolean("acik", false).apply();
        WorkManager.getInstance(c).cancelUniqueWork(IS);
    }

    static void goster(Context c, int no, String baslik, String metin) {
        if (!izinVar(c)) return;
        kanalKur(c);
        Intent ac = new Intent(c, MainActivity.class)
                .putExtra(MainActivity.DEPREM_EKRANI, true)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent pi = PendingIntent.getActivity(c, no, ac,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        NotificationCompat.Builder b = new NotificationCompat.Builder(c, KANAL)
                .setSmallIcon(R.drawable.bildirim_simge)
                .setContentTitle(baslik)
                .setContentText(metin)
                .setStyle(new NotificationCompat.BigTextStyle().bigText(metin))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setContentIntent(pi);
        try {
            NotificationManagerCompat.from(c).notify(no, b.build());
        } catch (SecurityException ignored) { }
    }
}
