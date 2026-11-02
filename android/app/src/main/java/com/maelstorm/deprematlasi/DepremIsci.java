/*
 * Deprem Atlası — arka planda son depremleri kontrol eden iş.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
package com.maelstorm.deprematlasi;

import android.content.Context;
import android.content.SharedPreferences;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Sunucudaki Marmara deprem listesini (Kandilli ve AFAD) okur; eşiğin üstünde ve daha önce
 * bildirilmemiş, son 3 saatteki depremler için bildirim gösterir. Bildirimler açıldığında listedeki
 * mevcut depremler "görüldü" sayılır, yalnızca sonrakiler bildirilir.
 */
public class DepremIsci extends Worker {

    static final String LISTE = "https://" + MainActivity.SUNUCU_ALANI + "/depremler";
    private static final long PENCERE_MS = 3L * 60 * 60 * 1000;
    private static final Locale TR = new Locale("tr", "TR");

    public DepremIsci(@NonNull Context c, @NonNull WorkerParameters p) {
        super(c, p);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context c = getApplicationContext();
        if (!Bildirim.acik(c)) return Result.success();
        JSONArray liste;
        try {
            liste = new JSONObject(getir(LISTE)).optJSONArray("depremler");
        } catch (Exception e) {
            return Result.retry();
        }
        if (liste == null) return Result.success();

        SharedPreferences a = Bildirim.ayar(c);
        Set<String> gorulen = new HashSet<>(a.getStringSet("gorulen", new HashSet<>()));
        boolean ilk = a.getBoolean("ilk", true);
        double esik = Bildirim.esik(c);
        long simdi = System.currentTimeMillis();
        List<JSONObject> yeni = new ArrayList<>();

        for (int i = 0; i < liste.length(); i++) {
            JSONObject d = liste.optJSONObject(i);
            if (d == null) continue;
            long t = d.optLong("t", 0);
            String anahtar = anahtar(d);
            if (gorulen.contains(anahtar)) continue;
            gorulen.add(anahtar);
            if (!ilk && t > simdi - PENCERE_MS && enBuyuk(d) >= esik - 1e-9) yeni.add(d);
        }

        // En fazla 3 bildirim; en yenisi en üstte
        yeni.sort((x, y) -> Long.compare(y.optLong("t"), x.optLong("t")));
        for (int i = Math.min(3, yeni.size()) - 1; i >= 0; i--) {
            JSONObject d = yeni.get(i);
            Bildirim.goster(c, (int) (d.optLong("t") / 1000 % 1_000_000_000L), baslik(d), metin(d));
        }

        // Liste büyümesin: yalnızca son 400 anahtar tutulur
        if (gorulen.size() > 400) {
            List<String> l = new ArrayList<>(gorulen);
            l.sort((x, y) -> Long.compare(zaman(y), zaman(x)));
            gorulen = new HashSet<>(l.subList(0, 400));
        }
        a.edit().putStringSet("gorulen", gorulen).putBoolean("ilk", false).apply();
        return Result.success();
    }

    private static String getir(String adres) throws Exception {
        HttpURLConnection b = (HttpURLConnection) new URL(adres).openConnection();
        try {
            b.setConnectTimeout(15000);
            b.setReadTimeout(20000);
            b.setUseCaches(false);
            b.setRequestProperty("Accept", "application/json");
            if (b.getResponseCode() != 200) throw new Exception("sunucu " + b.getResponseCode());
            try (InputStream g = b.getInputStream(); ByteArrayOutputStream o = new ByteArrayOutputStream()) {
                byte[] tampon = new byte[8192];
                int n;
                while ((n = g.read(tampon)) > 0) o.write(tampon, 0, n);
                return o.toString(StandardCharsets.UTF_8.name());
            }
        } finally {
            b.disconnect();
        }
    }

    private static String anahtar(JSONObject d) {
        return d.optLong("t") + "|" + Math.round(d.optDouble("lat", 0) * 100) + "|" + Math.round(d.optDouble("lon", 0) * 100);
    }

    private static long zaman(String anahtar) {
        try {
            return Long.parseLong(anahtar.substring(0, anahtar.indexOf('|')));
        } catch (RuntimeException e) {
            return 0;
        }
    }

    static double enBuyuk(JSONObject d) {
        JSONObject m = d.optJSONObject("mag");
        double en = 0;
        if (m != null) {
            Iterator<String> k = m.keys();
            while (k.hasNext()) {
                double v = m.optDouble(k.next(), 0);
                if (!Double.isNaN(v) && v > en) en = v;
            }
        }
        return en;
    }

    private static String ondalik(double v) {
        return String.format(TR, "%.1f", v);
    }

    private static String yer(JSONObject d) {
        String y = d.optString("yerAfad", "");
        if (y.isEmpty() || "null".equals(y)) y = d.optString("yerKandilli", "");
        if (y.isEmpty() || "null".equals(y)) y = "Marmara";
        return y;
    }

    static String baslik(JSONObject d) {
        return ondalik(enBuyuk(d)) + " büyüklüğünde deprem · " + yer(d);
    }

    static String metin(JSONObject d) {
        StringBuilder s = new StringBuilder();
        s.append(new SimpleDateFormat("HH:mm", TR).format(new Date(d.optLong("t"))));
        JSONObject m = d.optJSONObject("mag");
        if (m != null) {
            if (m.has("kandilli") && !m.isNull("kandilli")) s.append(" · Kandilli ").append(ondalik(m.optDouble("kandilli")));
            if (m.has("afad") && !m.isNull("afad")) s.append(" · AFAD ").append(ondalik(m.optDouble("afad")));
        }
        if (d.has("der") && !d.isNull("der")) s.append(" · derinlik ").append(ondalik(d.optDouble("der"))).append(" km");
        s.append(". Ayrıntılar için dokunun.");
        return s.toString();
    }
}
