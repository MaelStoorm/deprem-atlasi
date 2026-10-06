package com.maelstorm.deprematlasi;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.GeolocationPermissions;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.activity.EdgeToEdge;
import androidx.activity.OnBackPressedCallback;
import androidx.activity.SystemBarStyle;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowInsetsCompat;
import androidx.webkit.ServiceWorkerClientCompat;
import androidx.webkit.ServiceWorkerControllerCompat;
import androidx.webkit.WebViewAssetLoader;
import androidx.webkit.WebViewFeature;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * Deprem Atlası'nı uygulamanın içindeki kopyadan açan tek ekran.
 * Site dosyaları derleme sırasında assets/site klasörüne kopyalanır ve
 * https://appassets.androidplatform.net/ adresiyle (gerçek bir https kaynağı gibi) açılır.
 */
public class MainActivity extends ComponentActivity {

    static final String VARLIK_ALANI = WebViewAssetLoader.DEFAULT_DOMAIN;
    static final String VARLIK_KOKU = "https://" + VARLIK_ALANI;
    static final String BASLANGIC = VARLIK_KOKU + "/index.html";

    /** Deprem listesi ve adres arama sunucusu; index.html'deki BILDIRIM_URL ile aynı olmalı. */
    static final String SUNUCU_ALANI = "deprem-atlasi.egementughan.workers.dev";

    /** Sayfada açık bir ekran ya da mahalle paneli var mı? (1: var, 0: yok, -1: bilinmiyor) */
    private static final String ACIK_MI =
            "(function(){try{return (acikSayfa||secili)?1:0}catch(e){return -1}})()";
    private static final String KAPAT =
            "(function(){try{if(acikSayfa)sayfaKapat(acikSayfa);else if(secili)paneliKapat();}catch(e){}})()";

    private FrameLayout kok;
    private WebView web;
    private volatile WebViewAssetLoader yukleyici;
    private volatile String tarayiciKimligi;

    @Nullable private GeolocationPermissions.Callback bekleyenKonum;
    @Nullable private String bekleyenKaynak;

    private final ActivityResultLauncher<String[]> konumIzni = registerForActivityResult(
            new ActivityResultContracts.RequestMultiplePermissions(), sonuc -> {
                boolean verildi = Boolean.TRUE.equals(sonuc.get(Manifest.permission.ACCESS_FINE_LOCATION))
                        || Boolean.TRUE.equals(sonuc.get(Manifest.permission.ACCESS_COARSE_LOCATION))
                        || konumIzniVar();
                if (bekleyenKonum != null) bekleyenKonum.invoke(bekleyenKaynak, verildi, false);
                bekleyenKonum = null;
                bekleyenKaynak = null;
            });

    @Override
    protected void onCreate(@Nullable Bundle kayit) {
        EdgeToEdge.enable(this, SystemBarStyle.dark(Color.TRANSPARENT), SystemBarStyle.dark(Color.TRANSPARENT));
        super.onCreate(kayit);

        if ((getApplicationInfo().flags & ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
            WebView.setWebContentsDebuggingEnabled(true);
        }

        final WebViewAssetLoader.AssetsPathHandler varliklar = new WebViewAssetLoader.AssetsPathHandler(this);
        yukleyici = new WebViewAssetLoader.Builder()
                .setDomain(VARLIK_ALANI)
                .addPathHandler("/", yol -> {
                    if (yol.isEmpty() || yol.endsWith("/")) yol = yol + "index.html";
                    WebResourceResponse y = varliklar.handle("site/" + yol);
                    return (y == null || y.getData() == null) ? bulunamadi() : y;
                })
                .build();

        // Service worker'ın istekleri de aynı yerden karşılansın (sw.js uygulamada yok; kayıt sessizce düşer)
        if (WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_BASIC_USAGE)
                && WebViewFeature.isFeatureSupported(WebViewFeature.SERVICE_WORKER_SHOULD_INTERCEPT_REQUEST)) {
            ServiceWorkerControllerCompat.getInstance().setServiceWorkerClient(new ServiceWorkerClientCompat() {
                @Nullable
                @Override
                public WebResourceResponse shouldInterceptRequest(@NonNull WebResourceRequest r) {
                    return istegiKarsila(r);
                }
            });
        }

        kok = new FrameLayout(this);
        kok.setBackgroundColor(ContextCompat.getColor(this, R.color.sistem_cubugu));
        setContentView(kok);

        // Durum çubuğu, gezinme çubuğu, çentik ve klavye kadar boşluk bırak
        ViewCompat.setOnApplyWindowInsetsListener(kok, (v, ic) -> {
            Insets b = ic.getInsets(WindowInsetsCompat.Type.systemBars() | WindowInsetsCompat.Type.displayCutout());
            Insets k = ic.getInsets(WindowInsetsCompat.Type.ime());
            v.setPadding(b.left, b.top, b.right, Math.max(b.bottom, k.bottom));
            return WindowInsetsCompat.CONSUMED;
        });

        web = yeniSayfa();
        if (kayit == null || web.restoreState(kayit) == null) web.loadUrl(BASLANGIC);

        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                geriGit(this);
            }
        });
    }

    @SuppressLint("SetJavaScriptEnabled")
    private WebView yeniSayfa() {
        WebView w = new WebView(this);
        w.setBackgroundColor(ContextCompat.getColor(this, R.color.sayfa_zemin));
        kok.addView(w, new FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT));

        WebSettings a = w.getSettings();
        a.setJavaScriptEnabled(true);
        a.setDomStorageEnabled(true);          // localStorage: ayarlar, çanta listesi, son depremler
        a.setGeolocationEnabled(true);
        a.setTextZoom(100);                    // yazı boyutunu uygulamanın kendi ayarı belirler
        a.setAllowFileAccess(false);
        a.setAllowContentAccess(false);
        a.setSupportMultipleWindows(false);    // target="_blank" bağlantılar aşağıda yakalanır
        a.setJavaScriptCanOpenWindowsAutomatically(false);
        a.setUserAgentString(a.getUserAgentString() + " DepremAtlasi-Android");
        tarayiciKimligi = a.getUserAgentString();

        w.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest r) {
                return disaridaAcilacakMi(r.getUrl(), r.isForMainFrame());
            }

            @Nullable
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest r) {
                return istegiKarsila(r);
            }

            @Override
            public boolean onRenderProcessGone(WebView v, RenderProcessGoneDetail d) {
                // Sayfa motoru çökerse uygulama kapanmasın: ekranı baştan kur
                if (v == web) {
                    kok.removeView(v);
                    v.destroy();
                    web = null;
                    recreate();
                }
                return true;
            }
        });

        w.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onGeolocationPermissionsShowPrompt(String kaynak, GeolocationPermissions.Callback cb) {
                konumSor(kaynak, cb);
            }

            @Override
            public void onGeolocationPermissionsHidePrompt() {
                bekleyenKonum = null;
                bekleyenKaynak = null;
            }
        });
        return w;
    }

    /* ---------------- Dosyalar ve sunucu istekleri ---------------- */

    @Nullable
    private WebResourceResponse istegiKarsila(WebResourceRequest r) {
        Uri u = r.getUrl();
        String alan = u.getHost();
        if (VARLIK_ALANI.equalsIgnoreCase(alan)) {
            WebViewAssetLoader y = yukleyici;
            return y == null ? null : y.shouldInterceptRequest(u);
        }
        if (SUNUCU_ALANI.equalsIgnoreCase(alan) && "https".equalsIgnoreCase(u.getScheme())
                && "GET".equalsIgnoreCase(r.getMethod())) {
            return sunucudanGetir(r);
        }
        return null;
    }

    /**
     * Deprem listesi ve adres arama (GET) istekleri uygulama tarafından iletilir; böylece sunucunun
     * izin verdiği kaynak listesinde uygulamanın adresi olmasa da yanıt sayfaya ulaşır.
     * Hata olursa null döner ve istek WebView'in kendisine bırakılır.
     */
    @Nullable
    private WebResourceResponse sunucudanGetir(WebResourceRequest r) {
        HttpURLConnection b = null;
        try {
            b = (HttpURLConnection) new URL(r.getUrl().toString()).openConnection();
            b.setConnectTimeout(15000);
            b.setReadTimeout(30000);
            b.setUseCaches(false);
            String kimlik = tarayiciKimligi;
            if (kimlik != null) b.setRequestProperty("User-Agent", kimlik);
            Map<String, String> istekBasliklari = r.getRequestHeaders();
            if (istekBasliklari != null) {
                for (Map.Entry<String, String> e : istekBasliklari.entrySet()) {
                    String ad = e.getKey();
                    if ("Accept".equalsIgnoreCase(ad) || "Accept-Language".equalsIgnoreCase(ad)) {
                        b.setRequestProperty(ad, e.getValue());
                    }
                }
            }
            int kod = b.getResponseCode();
            if (kod < 200 || kod > 599 || (kod >= 300 && kod < 400)) {
                b.disconnect();
                return null;
            }
            InputStream govde = kod >= 400 ? b.getErrorStream() : b.getInputStream();
            if (govde == null) govde = new ByteArrayInputStream(new byte[0]);

            String mime = "application/octet-stream";
            String karakter = null;
            String tur = b.getContentType();
            if (tur != null) {
                String[] parca = tur.split(";");
                if (!parca[0].trim().isEmpty()) mime = parca[0].trim();
                for (int i = 1; i < parca.length; i++) {
                    String p = parca[i].trim();
                    if (p.toLowerCase(Locale.ROOT).startsWith("charset=")) {
                        karakter = p.substring(8).replace("\"", "").trim();
                    }
                }
            }
            Map<String, String> basliklar = new HashMap<>();
            basliklar.put("Access-Control-Allow-Origin", VARLIK_KOKU);
            basliklar.put("Cache-Control", "no-store");
            String neden = b.getResponseMessage();
            if (neden == null || neden.trim().isEmpty()) neden = kod < 400 ? "OK" : "Error";
            return new WebResourceResponse(mime, karakter, kod, neden, basliklar, govde);
        } catch (IOException | RuntimeException e) {
            if (b != null) b.disconnect();
            return null;
        }
    }

    private static WebResourceResponse bulunamadi() {
        return new WebResourceResponse("text/plain", "utf-8", 404, "Not Found",
                new HashMap<>(), new ByteArrayInputStream(new byte[0]));
    }

    /* ---------------- Dış bağlantılar: telefon, SMS, harita, tarayıcı ---------------- */

    private boolean disaridaAcilacakMi(Uri u, boolean anaCerceve) {
        String sema = u.getScheme() == null ? "" : u.getScheme().toLowerCase(Locale.ROOT);
        if ((sema.equals("https") || sema.equals("http")) && VARLIK_ALANI.equalsIgnoreCase(u.getHost())) {
            return false; // uygulamanın kendi sayfaları (ör. gizlilik.html) içeride açılır
        }
        if (sema.equals("about") || sema.equals("data") || sema.equals("blob") || sema.equals("javascript")) {
            return false;
        }
        if (anaCerceve) disariAc(u);
        return true;
    }

    private void disariAc(Uri u) {
        String sema = u.getScheme() == null ? "" : u.getScheme().toLowerCase(Locale.ROOT);
        try {
            switch (sema) {
                case "tel":
                    // Arama ekranı numara yazılı açılır; ek izin gerekmez
                    startActivity(new Intent(Intent.ACTION_DIAL, u));
                    break;
                case "sms":
                case "smsto":
                case "mms":
                case "mmsto":
                    smsAc(u);
                    break;
                case "mailto":
                    startActivity(new Intent(Intent.ACTION_SENDTO, u));
                    break;
                case "intent":
                    intentAc(u);
                    break;
                case "http":
                case "https": {
                    Intent i = new Intent(Intent.ACTION_VIEW, u);
                    i.addCategory(Intent.CATEGORY_BROWSABLE);
                    startActivity(i);
                    break;
                }
                default:
                    // geo: ve diğerleri (harita uygulaması vb.)
                    startActivity(new Intent(Intent.ACTION_VIEW, u));
            }
        } catch (ActivityNotFoundException | SecurityException e) {
            Toast.makeText(this, R.string.uygulama_yok, Toast.LENGTH_LONG).show();
        }
    }

    /** sms:NUMARA?body=METİN (ya da sms:?&body=METİN) → telefonun mesaj uygulaması, metin yazılı. */
    private void smsAc(Uri u) {
        String ham = u.toString();
        String geri = ham.substring(ham.indexOf(':') + 1);
        String alici = geri;
        String metin = null;
        int soru = geri.indexOf('?');
        if (soru >= 0) {
            alici = geri.substring(0, soru);
            for (String p : geri.substring(soru + 1).split("&")) {
                if (p.toLowerCase(Locale.ROOT).startsWith("body=")) metin = Uri.decode(p.substring(5));
            }
        }
        alici = Uri.decode(alici).replaceFirst("^/+", "");
        Intent i = new Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:" + Uri.encode(alici, "+,;")));
        if (metin != null) i.putExtra("sms_body", metin);
        try {
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            if (metin == null) throw e;
            // Mesaj uygulaması olmayan cihazlar (ör. tablet): metni başka bir uygulamayla paylaş
            Intent paylas = new Intent(Intent.ACTION_SEND);
            paylas.setType("text/plain");
            paylas.putExtra(Intent.EXTRA_TEXT, metin);
            startActivity(Intent.createChooser(paylas, getString(R.string.mesaji_gonder)));
        }
    }

    private void intentAc(Uri u) {
        Intent i;
        try {
            i = Intent.parseUri(u.toString(), Intent.URI_INTENT_SCHEME);
        } catch (java.net.URISyntaxException e) {
            throw new ActivityNotFoundException();
        }
        i.addCategory(Intent.CATEGORY_BROWSABLE);
        i.setComponent(null);
        i.setSelector(null);
        try {
            startActivity(i);
        } catch (ActivityNotFoundException e) {
            String yedek = i.getStringExtra("browser_fallback_url");
            if (yedek == null || !(yedek.startsWith("https://") || yedek.startsWith("http://"))) throw e;
            Intent t = new Intent(Intent.ACTION_VIEW, Uri.parse(yedek));
            t.addCategory(Intent.CATEGORY_BROWSABLE);
            startActivity(t);
        }
    }

    /* ---------------- Konum ---------------- */

    private boolean konumIzniVar() {
        return ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION)
                == PackageManager.PERMISSION_GRANTED
                || ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION)
                == PackageManager.PERMISSION_GRANTED;
    }

    /** Konum izni yalnızca sayfa konum istediğinde sorulur. */
    private void konumSor(String kaynak, GeolocationPermissions.Callback cb) {
        Uri k = kaynak == null ? null : Uri.parse(kaynak);
        if (k == null || !VARLIK_ALANI.equalsIgnoreCase(k.getHost())) {
            cb.invoke(kaynak, false, false);
            return;
        }
        if (konumIzniVar()) {
            cb.invoke(kaynak, true, false);
            return;
        }
        if (bekleyenKonum != null) bekleyenKonum.invoke(bekleyenKaynak, false, false);
        bekleyenKonum = cb;
        bekleyenKaynak = kaynak;
        konumIzni.launch(new String[]{
                Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION});
    }

    /* ---------------- Geri tuşu ---------------- */

    /**
     * Önce sayfada açık olan ekranı / mahalle panelini kapatır (sayfanın kendi geçmişiyle),
     * haritadayken uygulamadan çıkar.
     */
    private void geriGit(OnBackPressedCallback cb) {
        final WebView w = web;
        if (w == null) {
            cik(cb);
            return;
        }
        w.evaluateJavascript(ACIK_MI, sonuc -> {
            if (w != web) return;
            if ("0".equals(sonuc)) {
                cik(cb);
            } else if (w.canGoBack()) {
                w.goBack();
            } else if ("1".equals(sonuc)) {
                w.evaluateJavascript(KAPAT, null);
            } else {
                cik(cb);
            }
        });
    }

    private void cik(OnBackPressedCallback cb) {
        cb.setEnabled(false);
        getOnBackPressedDispatcher().onBackPressed();
        cb.setEnabled(true);
    }

    /* ---------------- Yaşam döngüsü ---------------- */

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) web.onResume();
    }

    @Override
    protected void onPause() {
        if (web != null) web.onPause();
        super.onPause();
    }

    @Override
    protected void onSaveInstanceState(@NonNull Bundle durum) {
        super.onSaveInstanceState(durum);
        if (web != null) web.saveState(durum);
    }

    @Override
    protected void onDestroy() {
        if (web != null) {
            kok.removeView(web);
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
