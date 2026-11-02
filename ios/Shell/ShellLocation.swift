/*
 * Konum köprüsü: sayfanın navigator.geolocation isteklerini ("Konumum" düğmesi, "İyiyim" mesajı)
 * telefonun konum servisine iletir. İzin, kullanıcı konum isteyen bir düğmeye ilk dokunduğunda sorulur.
 * Telif Hakkı (c) 2026 Egemen Çalıkoğlu. Tüm hakları saklıdır.
 */
import CoreLocation
import Foundation

final class ShellLocation: NSObject, CLLocationManagerDelegate {
    var answer: (([Any]) -> Void)?
    private let manager = CLLocationManager()
    private var waiters: [Int] = []

    private var timer: Timer?

    override init() {
        super.init()
        manager.delegate = self
        // Mahalle bulmak için 100 m yeterli; en hassas konumu beklemek (GPS) iç mekânda çok uzun sürüyor
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(_ id: Int) {
        waiters.append(id)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: reply(nil, code: 1, message: "Konum izni verilmedi.")
        default: start()
        }
    }

    /// Telefonun bildiği konum 2 dakikadan yeniyse hemen onu ver; değilse yeni konum iste ve en çok 12 saniye bekle.
    private func start() {
        if let l = manager.location, -l.timestamp.timeIntervalSinceNow < 120, l.horizontalAccuracy >= 0, l.horizontalAccuracy < 1500 {
            reply(l, code: 0, message: "")
            return
        }
        manager.requestLocation()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            guard let self = self, !self.waiters.isEmpty else { return }
            self.manager.stopUpdatingLocation()
            if let l = self.manager.location { self.reply(l, code: 0, message: "") }
            else { self.reply(nil, code: 3, message: "Konum bulunamadı. Açık bir alanda ya da Wi-Fi açıkken tekrar deneyin.") }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiters.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: start()
        case .denied, .restricted: reply(nil, code: 1, message: "Konum izni verilmedi.")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { reply(l, code: 0, message: "") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        if !denied, let l = manager.location { reply(l, code: 0, message: ""); return }
        // Geçici hata (konum henüz bilinmiyor): süre dolana kadar bekle
        if !denied, (error as? CLError)?.code == .locationUnknown { return }
        reply(nil, code: denied ? 1 : 2, message: denied ? "Konum izni verilmedi." : "Konum bulunamadı. Telefonun konum servislerinin açık olduğundan emin olun.")
    }

    private func reply(_ l: CLLocation?, code: Int, message: String) {
        timer?.invalidate()
        timer = nil
        let ids = waiters
        waiters.removeAll()
        for id in ids {
            answer?([id, l?.coordinate.latitude ?? 0, l?.coordinate.longitude ?? 0, l?.horizontalAccuracy ?? 0, code, message])
        }
    }
}
