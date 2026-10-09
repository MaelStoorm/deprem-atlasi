/*
 * Pati oyunlarının ihtiyaç bildirimleri ("Karnım acıktı!", "Çok susadım!"...), Android'deki Reminder ile aynı kurallar:
 * oyun açılırken bildirim izni istenir; oyun arka plana geçerken oyundan her ihtiyacın kaç dakika sonra azalacağı
 * alınır ve buna göre yerel bildirimler kurulur; oyun açılınca hepsi iptal edilir. Hiçbir veri cihazdan çıkmaz.
 * Çocuklar için: 21:30 - 08:00 arası bildirim gelmez, iki bildirim arası en az 1 saat, en fazla 3 bildirim.
 * Yalnızca Info.plist'te Shell > Reminders = "pati" olan uygulamada çalışır.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import UIKit
import UserNotifications
import WebKit

final class ShellReminders {
    static let maxCount = 3
    private let center = UNUserNotificationCenter.current()
    private weak var web: WKWebView?

    // Oyundaki ihtiyaçların ne zaman eşiğin altına ineceği (dakika); Android sürümüyle aynı hesap
    private static let stateJS = """
    (function(){try{window.patiPause&&patiPause()}catch(e){}
    try{const f=S.sleeping?.3:.5,T={food:25,water:25,energy:20,fun:25,clean:30},o=[];
    for(const k in T){if(k==='energy'&&S.sleeping)continue;const r=rate(k)*f;o.push({k,m:S[k]<=T[k]?0:(S[k]-T[k])/r})}
    return JSON.stringify({n:S.name,a:!!S.adopted,needs:o})}catch(e){return null}})()
    """

    init(web: WKWebView) {
        self.web = web
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(background), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(foreground), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    /// Oyun açılırken bir kez sorulur; reddedilirse oyun aynen çalışır, sadece hatırlatma gelmez.
    func askPermission() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    @objc private func foreground() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    @objc private func background() {
        guard let web = web else { return }
        // Arka planda kısa bir süre çalışmaya devam etmek için izin al (sayfadan durumu okumaya yetecek kadar)
        var task: UIBackgroundTaskIdentifier = .invalid
        task = UIApplication.shared.beginBackgroundTask { UIApplication.shared.endBackgroundTask(task) }
        web.evaluateJavaScript(Self.stateJS) { [weak self] result, _ in
            defer { UIApplication.shared.endBackgroundTask(task) }
            guard let self = self, let json = result as? String,
                  let data = json.data(using: .utf8),
                  let st = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            self.schedule(st)
        }
    }

    private func schedule(_ st: [String: Any]) {
        center.removeAllPendingNotificationRequests()
        guard st["a"] as? Bool == true, let needs = st["needs"] as? [[String: Any]] else { return }
        let name = (st["n"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Pati"
        let now = Date()
        var events: [(Date, String)] = []
        for n in needs {
            guard let k = n["k"] as? String, let m = (n["m"] as? NSNumber)?.doubleValue, m >= 0, m <= 24 * 60 else { continue }
            events.append((Self.daytime(now.addingTimeInterval(max(30, m) * 60)), k))
        }
        events.sort { $0.0 < $1.0 }
        var last = Date.distantPast
        var count = 0
        for (t0, k) in events {
            let t = Self.daytime(max(t0, last.addingTimeInterval(3600)))
            last = t
            guard let text = Self.text(k) else { continue }
            let c = UNMutableNotificationContent()
            c.title = "\(name): \(text.0)"
            c.body = text.1
            c.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(60, t.timeIntervalSince(now)), repeats: false)
            center.add(UNNotificationRequest(identifier: "ihtiyac-\(count)", content: c, trigger: trigger))
            count += 1
            if count >= Self.maxCount { break }
        }
    }

    /// Gece saatine düşen bildirimi sabah 08:00'e kaydırır
    static func daytime(_ t: Date) -> Date {
        let cal = Calendar.current
        let h = cal.component(.hour, from: t), mi = cal.component(.minute, from: t)
        let min = h * 60 + mi
        if min >= 8 * 60 && min < 21 * 60 + 30 { return t }
        var day = cal.startOfDay(for: t)
        if min >= 21 * 60 + 30 { day = cal.date(byAdding: .day, value: 1, to: day) ?? day }
        return cal.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? t
    }

    static func text(_ k: String) -> (String, String)? {
        switch k {
        case "food": return ("Karnım acıktı!", "Mama kabım boşaldı. Gelip bana mama verir misin?")
        case "water": return ("Çok susadım!", "Su kabıma taze su koyar mısın?")
        case "energy": return ("Uykum geldi...", "Gözlerim kapanıyor. Beni yatağıma götürüp ışığı kapatır mısın?")
        case "fun": return ("Canım sıkıldı!", "Benimle oynar mısın? Yeni mini oyunlar var!")
        case "clean": return ("Tüylerim karıştı!", "Beni tarayıp banyo yaptırır mısın?")
        default: return nil
        }
    }
}
