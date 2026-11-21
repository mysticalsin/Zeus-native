import AppKit
import CoreLocation
import Foundation

/// Asks for location only after the weather section decides a prompt is allowed.
@MainActor
final class WeatherLocationBridge: NSObject, CLLocationManagerDelegate {
    var onAuthorization: (LocationAuthorization) -> Void = { _ in }
    var onFix: (LocationFix) -> Void = { _ in }
    private let manager = CLLocationManager()
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        manager.delegate = self
        onAuthorization(Self.map(manager.authorizationStatus))
    }

    func requestPrompt() {
        manager.requestWhenInUseAuthorization()
    }

    func requestFix() {
        manager.requestLocation()
    }

    func revealSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorization = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            self.onAuthorization(authorization)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = LocationFix(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            label: "Current location"
        )
        Task { @MainActor in
            self.onFix(fix)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let authorization = Self.map(manager.authorizationStatus)
        Task { @MainActor in
            self.onAuthorization(authorization)
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> LocationAuthorization {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: .allowed
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}
