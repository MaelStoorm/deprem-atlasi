/*
 * Uygulamanın içindeki site dosyalarını app://site/ adresinden sunar.
 * Gerçek bir web kaynağı gibi davrandığı için kayıtlar (localStorage, IndexedDB) kalıcıdır ve
 * sayfa kendi dosyalarını fetch ile okuyabilir. İstenirse belirli bir sunucuya giden istekler de
 * buradan iletilir (/__vekil__/...): sunucu, uygulamanın adresine izin vermese de yanıt sayfaya ulaşır.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import Foundation
import WebKit

final class SiteScheme: NSObject, WKURLSchemeHandler {
    static let scheme = "app"
    static let host = "site"
    static let proxyPrefix = "/__vekil__"

    private let root: URL
    private let proxyOrigin: String?
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    init(root: URL, proxyOrigin: String?) {
        self.root = root.standardizedFileURL
        self.proxyOrigin = proxyOrigin
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return }
        var path = url.path
        if let origin = proxyOrigin, path.hasPrefix(Self.proxyPrefix) {
            forward(task, to: origin + String(path.dropFirst(Self.proxyPrefix.count)), query: url.query)
            return
        }
        if path.isEmpty || path.hasSuffix("/") { path += "index.html" }
        let file = root.appendingPathComponent(String(path.drop(while: { $0 == "/" }))).standardizedFileURL
        guard file.path.hasPrefix(root.path), let data = try? Data(contentsOf: file) else {
            reply(task, url: url, status: 404, mime: "text/plain", data: Data())
            return
        }
        reply(task, url: url, status: 200, mime: Self.mime(file.pathExtension), data: data)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }

    private func isStopped(_ task: WKURLSchemeTask) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped.contains(ObjectIdentifier(task))
    }

    private func reply(_ task: WKURLSchemeTask, url: URL, status: Int, mime: String, data: Data) {
        let headers = ["Content-Type": mime, "Content-Length": String(data.count), "Cache-Control": "no-cache",
                       "Access-Control-Allow-Origin": "*"]
        let res = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(res)
        task.didReceive(data)
        task.didFinish()
    }

    private func forward(_ task: WKURLSchemeTask, to target: String, query: String?) {
        guard let pageURL = task.request.url,
              let url = URL(string: target + (query.map { "?" + $0 } ?? "")) else { return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        req.httpMethod = task.request.httpMethod ?? "GET"
        req.httpBody = task.request.httpBody
        for h in ["Accept", "Accept-Language", "Content-Type"] {
            if let v = task.request.value(forHTTPHeaderField: h) { req.setValue(v, forHTTPHeaderField: h) }
        }
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self, !self.isStopped(task) else { return }
                if let error = error {
                    task.didFailWithError(error)
                    return
                }
                let http = response as? HTTPURLResponse
                let mime = (http?.value(forHTTPHeaderField: "Content-Type")) ?? "application/octet-stream"
                self.reply(task, url: pageURL, status: http?.statusCode ?? 200, mime: mime, data: data ?? Data())
            }
        }.resume()
    }

    static func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "webmanifest": return "application/json"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "woff2": return "font/woff2"
        case "woff": return "font/woff"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "wasm": return "application/wasm"
        case "mp3": return "audio/mpeg"
        case "ogg": return "audio/ogg"
        case "wav": return "audio/wav"
        case "m4a": return "audio/mp4"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}
