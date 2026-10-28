import Contacts
import ExpoModulesCore
import MapKit

public class PlaceSearchModule: Module {
  // MapKit's search classes aren't thread-safe, so every function runs on the main queue.
  private lazy var completer = Completer()

  public func definition() -> ModuleDefinition {
    Name("PlaceSearch")

    AsyncFunction("searchAsync") { (query: String, region: SearchRegion?, promise: Promise) in
      let request = MKLocalSearch.Request()
      request.naturalLanguageQuery = query
      request.resultTypes = [.address, .pointOfInterest]
      if let region {
        request.region = region.coordinateRegion
      }
      runSearch(request, promise: promise)
    }.runOnQueue(.main)

    AsyncFunction("completeAsync") { (query: String, region: SearchRegion?, promise: Promise) in
      self.completer.complete(query, region: region?.coordinateRegion, promise: promise)
    }.runOnQueue(.main)

    AsyncFunction("searchSuggestionAsync") { (id: String, promise: Promise) in
      guard let completion = self.completer.completion(for: id) else {
        promise.reject(SuggestionNotFoundException(id))
        return
      }
      runSearch(MKLocalSearch.Request(completion: completion), promise: promise)
    }.runOnQueue(.main)
  }
}

struct SearchRegion: Record {
  @Field var latitude: Double = 0
  @Field var longitude: Double = 0
  @Field var latitudeDelta: Double = 0
  @Field var longitudeDelta: Double = 0

  var coordinateRegion: MKCoordinateRegion {
    MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
      span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    )
  }
}

final class SuggestionNotFoundException: GenericException<String> {
  override var reason: String {
    "No search suggestion with id '\(param)'"
  }
}

final class SearchFailedException: GenericException<String> {
  override var reason: String {
    "Place search failed: \(param)"
  }
}

private func runSearch(_ request: MKLocalSearch.Request, promise: Promise) {
  let search = MKLocalSearch(request: request)
  // The handler holds on to the search so it isn't released (and cancelled) before it finishes.
  search.start { [search] response, error in
    _ = search
    if let error {
      // MapKit reports "nothing matched" as an error.
      if (error as? MKError)?.code == .placemarkNotFound {
        promise.resolve([] as [[String: Any]])
      } else {
        promise.reject(SearchFailedException(error.localizedDescription))
      }
      return
    }
    promise.resolve(response?.mapItems.map(serialize) ?? [])
  }
}

private func serialize(_ item: MKMapItem) -> [String: Any] {
  let coordinate: CLLocationCoordinate2D
  let address: String?
  if #available(iOS 26.0, *) {
    coordinate = item.location.coordinate
    address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true)
  } else {
    coordinate = item.placemark.coordinate
    address = item.placemark.postalAddress.map {
      CNPostalAddressFormatter.string(from: $0, style: .mailingAddress)
        .replacingOccurrences(of: "\n", with: ", ")
    }
  }
  return [
    "name": item.name ?? "",
    "address": address ?? "",
    "latitude": coordinate.latitude,
    "longitude": coordinate.longitude,
  ]
}

/// Adapts `MKLocalSearchCompleter`, which reports through a delegate, to one promise per query.
private final class Completer: NSObject, MKLocalSearchCompleterDelegate {
  private let completer = MKLocalSearchCompleter()
  private var pending: Promise?
  /// Every completion handed to JS, so a tapped suggestion can be searched. Cleared with the query.
  private var completions: [String: MKLocalSearchCompletion] = [:]
  private var nextId = 0

  override init() {
    super.init()
    completer.delegate = self
    completer.resultTypes = [.address, .pointOfInterest, .query]
  }

  func complete(_ query: String, region: MKCoordinateRegion?, promise: Promise) {
    // Only the newest query matters, so settle the one it replaces with no suggestions.
    settle(with: [])
    if let region {
      completer.region = region
    }
    if query.isEmpty {
      completer.cancel()
      completions.removeAll()
      promise.resolve([] as [[String: Any]])
    } else if query == completer.queryFragment && !completer.isSearching {
      // Setting the same fragment again wouldn't call the delegate.
      promise.resolve(serialize(completer.results))
    } else {
      pending = promise
      completer.queryFragment = query
    }
  }

  func completion(for id: String) -> MKLocalSearchCompletion? {
    completions[id]
  }

  func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
    settle(with: serialize(completer.results))
  }

  func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
    // Partial queries often fail with "not found"; either way there's nothing to suggest.
    settle(with: [])
  }

  private func settle(with suggestions: [[String: Any]]) {
    pending?.resolve(suggestions)
    pending = nil
  }

  private func serialize(_ results: [MKLocalSearchCompletion]) -> [[String: Any]] {
    results.map { completion in
      nextId += 1
      let id = String(nextId)
      completions[id] = completion
      return ["id": id, "title": completion.title, "subtitle": completion.subtitle]
    }
  }
}
