import CoreLocation

/// Location access and the user's position, for the map.
@Observable
final class LocationModel: NSObject, CLLocationManagerDelegate {
    private(set) var authorization: CLAuthorizationStatus
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var waiting: [CheckedContinuation<CLLocation?, Never>] = []

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var granted: Bool {
        #if os(iOS)
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
        #else
        authorization == .authorizedAlways
        #endif
    }

    func requestAccess() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() }
    }

    /// A recent position (from the last ten minutes) if there is one, or else a fresh one.
    func currentLocation(maxAge: TimeInterval = 600) async -> CLLocation? {
        guard granted else { return nil }
        if let last = manager.location, -last.timestamp.timeIntervalSinceNow < maxAge { return last }
        return await freshLocation()
    }

    func freshLocation() async -> CLLocation? {
        guard granted else { return nil }
        return await withCheckedContinuation { continuation in
            waiting.append(continuation)
            if waiting.count == 1 { manager.requestLocation() }
        }
    }

    private func settle(_ location: CLLocation?) {
        let pending = waiting
        waiting = []
        pending.forEach { $0.resume(returning: location) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { authorization = status }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        MainActor.assumeIsolated { settle(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { settle(manager.location) }
    }
}
