import OSLog
import CoreLocation
import MapKit

nonisolated struct Coordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ c: CLLocationCoordinate2D) {
        self.init(latitude: c.latitude, longitude: c.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Anything with a place on the map.
nonisolated protocol Located {
    var latitude: Double { get }
    var longitude: Double { get }
}

extension Located {
    var coordinate: Coordinate { Coordinate(latitude: latitude, longitude: longitude) }
}

extension Coordinate: Located {}

/// A region of the map, as saved and as searches prefer.
nonisolated struct SearchRegion: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
    var latitudeDelta: Double
    var longitudeDelta: Double

    init(latitude: Double, longitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    init(_ region: MKCoordinateRegion) {
        self.init(latitude: region.center.latitude, longitude: region.center.longitude,
                  latitudeDelta: region.span.latitudeDelta, longitudeDelta: region.span.longitudeDelta)
    }

    var mkRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

nonisolated enum Geo {
    /// Great-circle distance in meters.
    static func distanceMeters(_ a: some Located, _ b: some Located) -> Double {
        let r = 6_371_000.0
        func rad(_ deg: Double) -> Double { deg * .pi / 180 }
        let dLat = rad(b.latitude - a.latitude)
        let dLon = rad(b.longitude - a.longitude)
        let h = pow(sin(dLat / 2), 2) + cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2)
        return 2 * r * asin(sqrt(h))
    }

    static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        return String(format: meters < 10_000 ? "%.1f km" : "%.0f km", meters / 1000)
    }
}

/// A place found by search or by its coordinate: its name and one-line address.
struct PlaceResult: Hashable, Located {
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double

    init(name: String, address: String, latitude: Double, longitude: Double) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ item: MKMapItem) {
        let coordinate = Self.coordinate(of: item)
        self.init(name: item.name ?? "", address: Self.address(of: item),
                  latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        #if os(macOS)
        guard #available(macOS 26, *) else { return item.placemark.coordinate }
        #endif
        return item.location.coordinate
    }

    static func address(of item: MKMapItem) -> String {
        #if os(macOS)
        guard #available(macOS 26, *) else { return address(of: item.placemark) }
        #endif
        return item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
            ?? item.address?.fullAddress.replacingOccurrences(of: "\n", with: ", ")
            ?? ""
    }

    #if os(macOS)
    /// A one-line address, before macOS 26's address representations.
    static func address(of placemark: CLPlacemark) -> String {
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let region = [placemark.administrativeArea, placemark.postalCode].compactMap { $0 }.joined(separator: " ")
        return [street, placemark.locality ?? "", region].filter { !$0.isEmpty }.joined(separator: ", ")
    }
    #endif
}

/// An autocomplete suggestion. Search it for the places it stands for.
struct SearchSuggestion: Identifiable, Hashable {
    let id: Int
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}

enum PlaceSearch {
    /// Best-effort reverse geocode into a short name and a one-line address.
    static func describe(_ coordinate: Coordinate) async -> (name: String, address: String)? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        #if os(macOS)
        guard #available(macOS 26, *) else {
            guard let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
            return (placemark.name ?? placemark.locality ?? "Dropped Pin", PlaceResult.address(of: placemark))
        }
        #endif
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        let address = PlaceResult.address(of: item)
        let name = item.name ?? item.addressRepresentations?.cityName ?? "Dropped Pin"
        return (name, address)
    }

    /// Searches Apple Maps for places and addresses, preferring ones in `near`.
    static func search(_ query: String, near: SearchRegion?) async -> [PlaceResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]
        if let near { request.region = near.mkRegion }
        return await run(request)
    }

    /// Places for a suggestion: one for a place or address, several for a query like "Coffee".
    static func search(_ suggestion: SearchSuggestion) async -> [PlaceResult] {
        await run(MKLocalSearch.Request(completion: suggestion.completion))
    }

    private static func run(_ request: MKLocalSearch.Request) async -> [PlaceResult] {
        do {
            return try await MKLocalSearch(request: request).start().mapItems.map(PlaceResult.init)
        } catch {
            // MapKit reports "nothing matched" as an error.
            if (error as? MKError)?.code != .placemarkNotFound {
                Log.places.error("Search failed: \(String(describing: error), privacy: .public)")
            }
            return []
        }
    }

    static func openDirections(to coordinate: Coordinate, name: String) {
        let item: MKMapItem
        #if os(macOS)
        if #available(macOS 26, *) {
            item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                             address: nil)
        } else {
            item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate.clCoordinate))
        }
        #else
        item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude),
                         address: nil)
        #endif
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}

/// Suggestions for a partially typed query, from `MKLocalSearchCompleter`.
@Observable
final class PlaceCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [SearchSuggestion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()
    @ObservationIgnored private var nextId = 0

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(_ query: String, near: SearchRegion?) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let near { completer.region = near.mkRegion }
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
        } else if trimmed != completer.queryFragment {
            completer.queryFragment = trimmed
        }
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated {
            suggestions = completer.results.map { completion in
                nextId += 1
                return SearchSuggestion(id: nextId, title: completion.title, subtitle: completion.subtitle,
                                        completion: completion)
            }
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Partial queries often fail with "not found"; either way there's nothing to suggest.
        MainActor.assumeIsolated { suggestions = [] }
    }
}
