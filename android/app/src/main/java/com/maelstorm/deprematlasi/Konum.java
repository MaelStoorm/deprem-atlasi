/*
 * Deprem Atlası — telefonun konum servisinden hızlı konum alma.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
package com.maelstorm.deprematlasi;

import android.content.Context;
import android.location.Location;
import android.location.LocationManager;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;

import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import androidx.core.location.LocationManagerCompat;
import androidx.core.os.CancellationSignal;

import java.util.ArrayList;
import java.util.List;

/**
 * Önce telefonun bildiği son konuma bakar (2 dakikadan yeniyse hemen onu verir); değilse ağ, GPS ve
 * (Android 12+) birleşik konumdan aynı anda ister, ilk gelen kullanılır. 12 saniyede yanıt gelmezse
 * eldeki en iyi eski konum, o da yoksa hata döner.
 */
final class Konum {

    interface Cevap {
        void ver(@Nullable Location konum, int kod, String mesaj);
    }

    private static final long TAZE_MS = 2 * 60 * 1000;
    private static final long SURE_MS = 12 * 1000;

    private Konum() { }

    static void al(Context c, Cevap cevap) {
        LocationManager lm = (LocationManager) c.getSystemService(Context.LOCATION_SERVICE);
        if (lm == null) {
            cevap.ver(null, 2, "Bu cihaz konum bilgisi vermiyor.");
            return;
        }
        if (!LocationManagerCompat.isLocationEnabled(lm)) {
            cevap.ver(null, 2, "Telefonun konumu kapalı. Bildirim panelinden ya da Ayarlar'dan konumu açıp tekrar deneyin.");
            return;
        }

        List<String> saglayicilar = new ArrayList<>();
        if (Build.VERSION.SDK_INT >= 31 && lm.hasProvider(LocationManager.FUSED_PROVIDER)) {
            saglayicilar.add(LocationManager.FUSED_PROVIDER);
        }
        for (String p : new String[]{LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER}) {
            try {
                if (lm.isProviderEnabled(p)) saglayicilar.add(p);
            } catch (RuntimeException ignored) { }
        }

        final Location eski = sonBilinen(lm, saglayicilar);
        if (eski != null && yas(eski) < TAZE_MS) {
            cevap.ver(eski, 0, "");
            return;
        }
        if (saglayicilar.isEmpty()) {
            if (eski != null) cevap.ver(eski, 0, "");
            else cevap.ver(null, 2, "Konum bulunamadı.");
            return;
        }

        final Handler h = new Handler(Looper.getMainLooper());
        final List<CancellationSignal> iptaller = new ArrayList<>();
        final boolean[] bitti = {false};
        final int[] bos = {0};
        final int toplam = saglayicilar.size();

        final Runnable sonuclandir = () -> {
            if (bitti[0]) return;
            bitti[0] = true;
            for (CancellationSignal s : iptaller) s.cancel();
            if (eski != null) cevap.ver(eski, 0, "");
            else cevap.ver(null, 3, "Konum bulunamadı. Açık bir alanda ya da Wi-Fi açıkken tekrar deneyin.");
        };

        for (String p : saglayicilar) {
            CancellationSignal iptal = new CancellationSignal();
            iptaller.add(iptal);
            try {
                LocationManagerCompat.getCurrentLocation(lm, p, iptal, ContextCompat.getMainExecutor(c), konum -> {
                    if (bitti[0]) return;
                    if (konum != null) {
                        bitti[0] = true;
                        h.removeCallbacksAndMessages(null);
                        for (CancellationSignal s : iptaller) s.cancel();
                        cevap.ver(konum, 0, "");
                    } else if (++bos[0] >= toplam) {
                        h.removeCallbacksAndMessages(null);
                        sonuclandir.run();
                    }
                });
            } catch (SecurityException | IllegalArgumentException e) {
                if (++bos[0] >= toplam) {
                    h.removeCallbacksAndMessages(null);
                    sonuclandir.run();
                    return;
                }
            }
        }
        h.postDelayed(sonuclandir, SURE_MS);
    }

    @Nullable
    private static Location sonBilinen(LocationManager lm, List<String> saglayicilar) {
        Location en = null;
        List<String> hepsi = new ArrayList<>(saglayicilar);
        if (!hepsi.contains(LocationManager.PASSIVE_PROVIDER)) hepsi.add(LocationManager.PASSIVE_PROVIDER);
        for (String p : hepsi) {
            try {
                Location l = lm.getLastKnownLocation(p);
                if (l != null && (en == null || l.getElapsedRealtimeNanos() > en.getElapsedRealtimeNanos())) en = l;
            } catch (SecurityException | IllegalArgumentException ignored) { }
        }
        return en;
    }

    private static long yas(Location l) {
        return (SystemClock.elapsedRealtimeNanos() - l.getElapsedRealtimeNanos()) / 1_000_000L;
    }
}
