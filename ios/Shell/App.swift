/*
 * iOS kabuğu: uygulamanın web sayfasını tam ekran açar.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    }

    // Ekran yönü: Info.plist'teki ayara göre (oyun sırasında sayfa da değiştirebilir)
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        ShellConfig.shared.orientations
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private let page = ShellViewController()

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: windowScene)
        w.backgroundColor = ShellConfig.shared.background
        w.rootViewController = page
        w.makeKeyAndVisible()
        window = w
        for ctx in options.urlContexts { page.openIncoming(ctx.url) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for ctx in URLContexts { page.openIncoming(ctx.url) }
    }
}

/// Info.plist'teki "Shell" sözlüğünden okunan uygulama ayarları.
struct ShellConfig {
    static let shared = ShellConfig()

    let background: UIColor
    let lightStatusBar: Bool
    /// Durum çubuğu telefonun açık/koyu temasına uysun (sayfa temaya göre renk değiştiriyorsa)
    let autoStatusBar: Bool
    let startPage: String
    /// Sayfanın https ile çağırdığı sunucu (ör. https://ornek.workers.dev). İstekler uygulama üzerinden iletilir.
    let proxyOrigin: String?
    /// "files": Jalon/Pafta tarzı window.AndroidBridge (dosya aç/kaydet/kopyala)
    let bridge: String
    /// Dışarıdan gelen dosyalar: "text" (metin, birden çok) ya da "binary" (tek dosya, base64)
    let incoming: String
    let geolocation: Bool
    let orientations: UIInterfaceOrientationMask
    /// Sayfanın rahat sığdığı yükseklik (CSS piksel). Ekran daha alçaksa sayfa bu kadar uzaklaştırılır (0: kapalı)
    let fitHeight: CGFloat
    /// Uygulamaya özel ek CSS (ör. uygulamada anlamı olmayan bir kutuyu gizlemek için)
    let extraCSS: String
    /// "pati": Pati oyunlarının ihtiyaç bildirimleri (izin sorulur, oyun kapanınca hatırlatma kurulur)
    let reminders: String

    init() {
        let d = (Bundle.main.object(forInfoDictionaryKey: "Shell") as? [String: Any]) ?? [:]
        background = UIColor(hex: d["Background"] as? String ?? "#000000")
        lightStatusBar = d["LightStatusBar"] as? Bool ?? true
        autoStatusBar = d["AutoStatusBar"] as? Bool ?? false
        startPage = d["StartPage"] as? String ?? "index.html"
        let p = (d["ProxyOrigin"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        proxyOrigin = p.isEmpty ? nil : p
        bridge = d["Bridge"] as? String ?? "none"
        incoming = d["Incoming"] as? String ?? "none"
        geolocation = d["Geolocation"] as? Bool ?? false
        fitHeight = CGFloat((d["FitHeight"] as? NSNumber)?.doubleValue ?? 0)
        extraCSS = d["ExtraCSS"] as? String ?? ""
        reminders = d["Reminders"] as? String ?? ""
        switch d["Orientation"] as? String ?? "portrait" {
        case "landscape": orientations = .landscape
        case "all": orientations = .allButUpsideDown
        default: orientations = .portrait
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}
