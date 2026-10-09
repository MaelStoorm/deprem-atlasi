/*
 * Uygulamanın tek ekranı: sitenin index.html sayfasını açar ve sayfanın Android'de kullandığı
 * köprüleri iOS karşılıklarıyla tanımlar (dosya aç/kaydet, kopyala, konum, dış bağlantılar).
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import CoreLocation
import UIKit
import UniformTypeIdentifiers
import WebKit

final class ShellViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                                 UIDocumentPickerDelegate, CLLocationManagerDelegate {

    private let config = ShellConfig.shared
    private var web: WKWebView!
    private var pageReady = false
    private var pendingFiles: [URL] = []

    private enum PickMode { case textFiles, binaryFile }
    private var pickMode: PickMode = .textFiles
    private var exportFile: URL?

    private let location = CLLocationManager()
    private var locationWaiters: [Int] = []

    override var preferredStatusBarStyle: UIStatusBarStyle {
        config.autoStatusBar ? .default : (config.lightStatusBar ? .lightContent : .darkContent)
    }
    override var prefersHomeIndicatorAutoHidden: Bool { config.orientations == .landscape }

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
        cfg.setURLSchemeHandler(SiteScheme(root: site, proxyOrigin: config.proxyOrigin), forURLScheme: SiteScheme.scheme)

        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.isOpaque = false
        web.backgroundColor = config.background
        web.scrollView.backgroundColor = config.background
        // Sayfalar güvenli alan boşluklarını kendileri veriyor (viewport-fit=cover + env(safe-area-inset-*))
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.bounces = false
        web.allowsLinkPreview = false
        if #available(iOS 16.4, *) { web.isInspectable = false }
        view = web
        view.backgroundColor = config.background
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        location.delegate = self
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
        if config.bridge == "files" {
            list.append("""
            window.AndroidBridge = {
              pickFiles: function () { webkit.messageHandlers.shell.postMessage({ op: 'pickText' }); },
              pickNcz: function () { webkit.messageHandlers.shell.postMessage({ op: 'pickBinary' }); },
              saveFile: function (n, d) { webkit.messageHandlers.shell.postMessage({ op: 'save', name: String(n), data: String(d) }); },
              saveFileBase64: function (n, d) { webkit.messageHandlers.shell.postMessage({ op: 'save', name: String(n), b64: String(d) }); },
              copy: function (t) { webkit.messageHandlers.shell.postMessage({ op: 'copy', text: String(t) }); }
            };
            """)
        }
        if let origin = config.proxyOrigin {
            // Sunucuya giden fetch istekleri uygulamanın kendi adresi üzerinden iletilir
            let o = origin.replacingOccurrences(of: "\"", with: "")
            list.append("""
            (function () {
              var O = "\(o)", P = "\(SiteScheme.proxyPrefix)", f = window.fetch;
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
        }
        if config.geolocation {
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
        }
        return list
    }

    // MARK: - Sayfa ve bağlantılar

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        flushPendingFiles()
    }

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
        case "pickText": pick(.textFiles)
        case "pickBinary": pick(.binaryFile)
        case "save":
            let name = body["name"] as? String ?? "dosya.txt"
            if let b64 = body["b64"] as? String {
                save(name: name, data: Data(base64Encoded: b64, options: .ignoreUnknownCharacters) ?? Data())
            } else {
                save(name: name, data: Data((body["data"] as? String ?? "").utf8))
            }
        case "copy":
            UIPasteboard.general.string = body["text"] as? String ?? ""
        case "location":
            if let id = body["id"] as? Int { requestLocation(id) }
        case "log":
            NSLog("[kabuk] %@", body["text"] as? String ?? "")
        default:
            break
        }
    }

    private func pick(_ mode: PickMode) {
        pickMode = mode
        exportFile = nil
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = mode == .textFiles
        picker.delegate = self
        present(picker, animated: true)
    }

    private func save(name: String, data: Data) {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = dir.appendingPathComponent(safe.isEmpty ? "dosya.txt" : safe)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: file)
        } catch {
            return toast("Dosya yazılamadı.")
        }
        exportFile = file
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let f = exportFile {
            toast("\(f.lastPathComponent) kaydedildi.")
            finishExport()
        } else {
            pendingFiles.append(contentsOf: urls)
            flushPendingFiles()
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        if exportFile != nil {
            toast("Kaydetme iptal edildi.")
            finishExport()
        }
    }

    private func finishExport() {
        if let f = exportFile { try? FileManager.default.removeItem(at: f.deletingLastPathComponent()) }
        exportFile = nil
    }

    // MARK: - Dosyaları sayfaya ver

    func openIncoming(_ url: URL) {
        guard config.incoming != "none" else { return }
        pickMode = config.incoming == "binary" ? .binaryFile : .textFiles
        pendingFiles.append(url)
        flushPendingFiles()
    }

    private func flushPendingFiles() {
        guard pageReady, !pendingFiles.isEmpty else { return }
        var files = pendingFiles
        pendingFiles.removeAll()
        if pickMode == .binaryFile, let last = files.last { files = [last] }  // görüntüleyici tek dosya açar
        for url in files {
            guard let data = read(url) else {
                toast("Dosya okunamadı: \(url.lastPathComponent)")
                continue
            }
            if pickMode == .binaryFile {
                call("window.onNativeFile", [url.lastPathComponent, data.base64EncodedString()])
            } else {
                call("window.__addFileFromApp", [url.lastPathComponent, text(data)])
            }
        }
    }

    private func read(_ url: URL) -> Data? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    private func text(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        // Netcad dosyaları çoğunlukla Windows Türkçe kod sayfasındadır (windows-1254)
        let cp1254 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.windowsLatin5.rawValue)))
        return String(data: data, encoding: cp1254) ?? String(decoding: data, as: UTF8.self)
    }

    private func toast(_ message: String) { call("window.__toast", [message]) }

    private func call(_ function: String, _ args: [Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: args),
              let list = String(data: json, encoding: .utf8) else { return }
        web.evaluateJavaScript("\(function) && \(function).apply(null, \(list))", completionHandler: nil)
    }

    // MARK: - Konum

    private func requestLocation(_ id: Int) {
        locationWaiters.append(id)
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .denied, .restricted: answerLocation(nil, code: 1, message: "Konum izni verilmedi.")
        default: location.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !locationWaiters.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: answerLocation(nil, code: 1, message: "Konum izni verilmedi.")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { answerLocation(l, code: 0, message: "") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        answerLocation(nil, code: denied ? 1 : 2, message: denied ? "Konum izni verilmedi." : "Konum bulunamadı.")
    }

    private func answerLocation(_ l: CLLocation?, code: Int, message: String) {
        let ids = locationWaiters
        locationWaiters.removeAll()
        for id in ids {
            call("window.__shellLocation", [id, l?.coordinate.latitude ?? 0, l?.coordinate.longitude ?? 0,
                                            l?.horizontalAccuracy ?? 0, code, message])
        }
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
