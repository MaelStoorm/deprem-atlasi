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

    override init() {
        super.init()
        manager.delegate = self
    }

    func request(_ id: Int) {
        waiters.append(id)
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: reply(nil, code: 1, message: "Konum izni verilmedi.")
        default: manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiters.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: reply(nil, code: 1, message: "Konum izni verilmedi.")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let l = locations.last { reply(l, code: 0, message: "") }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let denied = (error as? CLError)?.code == .denied
        reply(nil, code: denied ? 1 : 2, message: denied ? "Konum izni verilmedi." : "Konum bulunamadı.")
    }

    private func reply(_ l: CLLocation?, code: Int, message: String) {
        let ids = waiters
        waiters.removeAll()
        for id in ids {
            answer?([id, l?.coordinate.latitude ?? 0, l?.coordinate.longitude ?? 0, l?.horizontalAccuracy ?? 0, code, message])
        }
    }
}
