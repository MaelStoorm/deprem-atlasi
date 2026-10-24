/*
 * Uygulamanın tek ekranı: atlasın index.html sayfasını açar; sayfanın konum isteklerini ("Konumum")
 * telefonun konum servisine (ShellLocation), "Son depremler" ve adres arama isteklerini uygulamanın
 * sunucusuna (SiteScheme) iletir. Dış bağlantılar (belediye, AFAD, harita, SMS) telefonda açılır.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import UIKit
import WebKit

final class ShellViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

    private let config = ShellConfig.shared
    private var web: WKWebView!
    private let location = ShellLocation()

    // Sayfa telefonun açık/koyu temasına uyduğu için durum çubuğu da temaya uyar
    override var preferredStatusBarStyle: UIStatusBarStyle { .default }
    override var prefersHomeIndicatorAutoHidden: Bool { config.orientations == .landscape }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { config.orientations }

    // MARK: - Kurulum

    override func loadView() {
        let content = WKUserContentController()
        content.add(WeakHandler(self), name: "shell")
        for js in userScripts() {
            content.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = content
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.dataDetectorTypes = []
        cfg.websiteDataStore = .default()
        let site = Bundle.main.url(forResource: "site", withExtension: nil) ?? Bundle.main.bundleURL
        cfg.setURLSchemeHandler(SiteScheme(root: site), forURLScheme: SiteScheme.scheme)

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = config.background
        web.scrollView.backgroundColor = config.background
        // Sayfa güvenli alan boşluklarını kendisi veriyor (viewport-fit=cover + env(safe-area-inset-*))
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        if #available(iOS 16.4, *) { web.isInspectable = false }
        view = web
        view.backgroundColor = config.background
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        location.answer = { [weak self] args in self?.call("window.__shellLocation", args) }
        web.load(URLRequest(url: URL(string: "\(SiteScheme.scheme)://\(SiteScheme.host)/\(config.startPage)")!))
    }

    private func userScripts() -> [String] {
        // Sayfa hataları cihaz günlüğüne yazılır ("[kabuk]" ile başlar); sorun ararken işe yarar
        var list: [String] = ["""
        (function () {
          function send(k, a) { try { webkit.messageHandlers.shell.postMessage({ op: 'log', text: k + ': ' + Array.prototype.map.call(a, String).join(' ') }); } catch (e) {} }
          window.addEventListener('error', function (e) { send('hata', [e.message, (e.filename || '') + ':' + (e.lineno || '')]); });
          window.addEventListener('unhandledrejection', function (e) { send('söz', [e.reason]); });
          document.addEventListener('securitypolicyviolation', function (e) { send('csp', [e.violatedDirective, e.blockedURI]); });
          var ce = console.error; console.error = function () { send('console', arguments); return ce.apply(console, arguments); };
          window.addEventListener('DOMContentLoaded', function () { send('hazır', [location.href, document.title]); });
        })();
        """]
        // Sayfa iki parmakla büyümesin: yakınlaştırmayı sayfanın kendisi (harita) yapar
        list.append("""
        document.addEventListener('DOMContentLoaded', function () {
          var m = document.querySelector('meta[name=viewport]');
          if (!m) { m = document.createElement('meta'); m.name = 'viewport'; document.head.appendChild(m); }
          var c = (m.content || 'width=device-width,initial-scale=1,viewport-fit=cover')
            .split(',').map(function (s) { return s.trim(); })
            .filter(function (s) { return s && !/^(maximum-scale|minimum-scale|user-scalable)/.test(s); });
          m.content = c.concat(['maximum-scale=1', 'minimum-scale=1', 'user-scalable=no']).join(',');
        });
        """)
        // Sunucuya giden istekler (son depremler, adres arama) uygulamanın kendi adresi üzerinden iletilir
        list.append("""
        (function () {
          var O = "\(SiteScheme.server)", P = "\(SiteScheme.proxyPrefix)", f = window.fetch;
          window.fetch = function (input, init) {
            try {
              var u = typeof input === 'string' ? input : (input && input.url) || String(input);
              if (u.indexOf(O) === 0) {
                var n = P + u.slice(O.length);
                input = (typeof input === 'string' || !(input instanceof Request)) ? n : new Request(n, input);
              }
            } catch (e) {}
            return f.call(this, input, init);
          };
        })();
        """)
        // Konum telefonun kendi konum servisinden alınır
        list.append("""
        (function () {
          var waiting = {}, n = 0;
          function ask(ok, fail) {
            var id = ++n; waiting[id] = { ok: ok, fail: fail };
            webkit.messageHandlers.shell.postMessage({ op: 'location', id: id });
            return id;
          }
          window.__shellLocation = function (id, lat, lon, acc, code, msg) {
            var w = waiting[id]; if (!w) return; delete waiting[id];
            if (code) { if (w.fail) w.fail({ code: code, message: msg, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }); return; }
            if (w.ok) w.ok({ coords: { latitude: lat, longitude: lon, accuracy: acc, altitude: null, altitudeAccuracy: null, heading: null, speed: null }, timestamp: Date.now() });
          };
          var geo = {
            getCurrentPosition: function (ok, fail) { ask(ok, fail); },
            watchPosition: function (ok, fail) { return ask(ok, fail); },
            clearWatch: function () {}
          };
          try { Object.defineProperty(navigator, 'geolocation', { value: geo, configurable: true }); } catch (e) {}
        })();
        """)
        return list
    }

    // MARK: - Sayfa ve bağlantılar

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("[kabuk] yüklenemedi: %@", error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("[kabuk] sayfa hatası: %@", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("[kabuk] sayfa motoru kapandı, yeniden açılıyor")
        // Sayfa motoru kapanırsa (bellek vb.) sayfayı yeniden aç; kayıtlar korunur
        webView.reload()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.cancel) }
        if scheme == SiteScheme.scheme || ["about", "data", "blob", "javascript"].contains(scheme) {
            return decisionHandler(.allow)
        }
        // Telefon, SMS, e-posta, harita ve web bağlantıları telefonun kendi uygulamalarında açılır
        if action.targetFrame == nil || action.targetFrame?.isMainFrame == true {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            if url.scheme == SiteScheme.scheme { webView.load(action.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    // alert / confirm / prompt pencereleri
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler() })
        presentAlert(a, otherwise: completionHandler)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler(true) })
        presentAlert(a) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "Vazgeç", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "Tamam", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        presentAlert(a) { completionHandler(nil) }
    }

    private func presentAlert(_ a: UIAlertController, otherwise: @escaping () -> Void) {
        guard presentedViewController == nil else { return otherwise() }
        present(a, animated: true)
    }

    // MARK: - Köprü

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let op = body["op"] as? String else { return }
        switch op {
        case "location":
            if let id = body["id"] as? Int { location.request(id) }
        case "log":
            NSLog("[kabuk] %@", body["text"] as? String ?? "")
        default:
            break
        }
    }

    func call(_ function: String, _ args: [Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: args),
              let list = String(data: json, encoding: .utf8) else { return }
        web.evaluateJavaScript("\(function) && \(function).apply(null, \(list))", completionHandler: nil)
    }
}

/// Betik işleyicisi güçlü tutulur; döngü olmasın diye araya zayıf bir aracı konur.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        target?.userContentController(c, didReceive: m)
    }
}
