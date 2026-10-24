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

    // Ekran yönü: Info.plist'teki ayara göre
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
    }
}

/// Info.plist'teki "Shell" sözlüğünden okunan uygulama ayarları.
struct ShellConfig {
    static let shared = ShellConfig()

    let background: UIColor
    let startPage: String
    let orientations: UIInterfaceOrientationMask

    init() {
        let d = (Bundle.main.object(forInfoDictionaryKey: "Shell") as? [String: Any]) ?? [:]
        background = UIColor(hex: d["Background"] as? String ?? "#000000")
        startPage = d["StartPage"] as? String ?? "index.html"
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
