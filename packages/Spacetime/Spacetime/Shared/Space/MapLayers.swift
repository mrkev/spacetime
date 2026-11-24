import Contacts
import Foundation
import MapKit
import OSLog
import Photos

/// What the Space map can show besides places: where photos were taken and contacts' addresses.
nonisolated enum MapLayer: String, CaseIterable, Codable, Sendable {
    case photos, contacts

    var title: String {
        switch self {
        case .photos: "Photos"
        case .contacts: "Contacts"
        }
    }
}

/// Which layers are on, saved as JSON.
nonisolated struct MapLayerSettings: Codable, Equatable, Sendable {
    var enabled: Set<MapLayer> = []
}

// MARK: Photos

/// A photo or video with a location.
nonisolated struct PhotoPoint: Hashable, Sendable {
    var id: String
    var coordinate: Coordinate
    var date: Date?
}

/// Photos taken at about the same spot, newest first.
nonisolated struct PhotoGroup: Identifiable, Hashable, Sendable {
    var id: String
    var coordinate: Coordinate
    var photoIds: [String]
    var newest: Date?
    var oldest: Date?
}

nonisolated enum PhotoGrouping {
    /// Groups photos into cells about `cellMeters` across, each at the average of its photos' spots. A
    /// library has thousands of photos at a handful of places, and the map can't draw them all.
    static func group(_ points: [PhotoPoint], cellMeters: Double = 150) -> [PhotoGroup] {
        let latStep = cellMeters / 111_000
        var cells: [String: [PhotoPoint]] = [:]
        for point in points {
            let row = Int((point.coordinate.latitude / latStep).rounded(.down))
            // Degrees of longitude shrink toward the poles; use the cell's row for a steady width.
            let cosine = max(0.01, cos(Double(row) * latStep * .pi / 180))
            let column = Int((point.coordinate.longitude / (latStep / cosine)).rounded(.down))
            cells["\(row):\(column)", default: []].append(point)
        }
        var groups: [PhotoGroup] = []
        for (key, points) in cells {
            let sorted = points.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            var latitude = 0.0, longitude = 0.0
            for point in points {
                latitude += point.coordinate.latitude
                longitude += point.coordinate.longitude
            }
            let count = Double(points.count)
            groups.append(PhotoGroup(id: "photos:\(key)",
                                     coordinate: Coordinate(latitude: latitude / count, longitude: longitude / count),
                                     photoIds: sorted.map(\.id), newest: sorted.first?.date,
                                     oldest: sorted.last?.date))
        }
        return groups.sorted { $0.id < $1.id }
    }
}

// MARK: Contacts

/// One of a contact's postal addresses, and where it is once it's been looked up.
nonisolated struct ContactAddress: Identifiable, Hashable, Sendable {
    var id: String
    var contactId: String
    var name: String
    /// Like "home" or "work".
    var label: String?
    var address: String
    var coordinate: Coordinate?
}

/// Where addresses were found, so each is looked up once. An address that couldn't be found is tried
/// again after a while, in case it was a hiccup.
nonisolated struct GeocodeCache: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var latitude: Double?
        var longitude: Double?
        /// When it was looked up, in seconds since 1970.
        var at: Double

        var coordinate: Coordinate? {
            guard let latitude, let longitude else { return nil }
            return Coordinate(latitude: latitude, longitude: longitude)
        }
    }

    static let retryAfter: TimeInterval = 30 * 24 * 3600

    var entries: [String: Entry] = [:]

    /// The same address however it's spaced or capitalized.
    static func key(_ address: String) -> String {
        address.lowercased().split(whereSeparator: { $0.isWhitespace || $0 == "," }).joined(separator: " ")
    }

    func coordinate(for address: String) -> Coordinate? {
        entries[Self.key(address)]?.coordinate
    }

    func needsLookup(_ address: String, now: Date = Date()) -> Bool {
        guard let entry = entries[Self.key(address)] else { return true }
        return entry.coordinate == nil && now.timeIntervalSince1970 - entry.at > Self.retryAfter
    }

    mutating func record(_ address: String, _ coordinate: Coordinate?, now: Date = Date()) {
        entries[Self.key(address)] = Entry(latitude: coordinate?.latitude, longitude: coordinate?.longitude,
                                           at: now.timeIntervalSince1970)
    }
}

extension ContactAddress {
    /// A contact's addresses, one line each.
    static func addresses(of contact: CNContact) -> [ContactAddress] {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? (contact.organizationName.isEmpty ? "No Name" : contact.organizationName)
        return contact.postalAddresses.enumerated().compactMap { i, labeled in
            let address = CNPostalAddressFormatter.string(from: labeled.value, style: .mailingAddress)
                .split(separator: "\n").joined(separator: ", ")
            guard !address.isEmpty else { return nil }
            return ContactAddress(id: "contact:\(contact.identifier):\(i)", contactId: contact.identifier, name: name,
                                  label: labeled.label.map { CNLabeledValue<CNPostalAddress>.localizedString(forLabel: $0) },
                                  address: address)
        }
    }
}

// MARK: Store

/// Reads the layers the map shows, once they're turned on: photos' locations from the photo library,
/// and contacts' addresses, looked up on the map as they come.
@Observable
final class MapLayers: NSObject {
    private static let settingsKey = "spacetime.map.layers"
    private static let geocodeKey = "spacetime.contacts.geocoded"

    private(set) var settings: MapLayerSettings
    private(set) var photoGroups: [PhotoGroup] = []
    /// Contacts' addresses that have been found on the map.
    private(set) var contactAddresses: [ContactAddress] = []
    /// How many addresses are left to look up, while some are.
    private(set) var addressesToLookUp = 0
    /// Contacts' thumbnails, by contact ID.
    @ObservationIgnored private(set) var contactThumbnails: [String: Data] = [:]

    @ObservationIgnored private let storage: KeyValueStorage
    @ObservationIgnored private var cache: GeocodeCache
    @ObservationIgnored private var photosGeneration = 0
    @ObservationIgnored private var contactsGeneration = 0
    @ObservationIgnored private var observingPhotos = false
    @ObservationIgnored private var pendingPhotos: Task<Void, Never>?

    init(storage: KeyValueStorage) {
        self.storage = storage
        settings = storage.decode(MapLayerSettings.self, forKey: Self.settingsKey) ?? MapLayerSettings()
        cache = storage.decode(GeocodeCache.self, forKey: Self.geocodeKey) ?? GeocodeCache()
        super.init()
        NotificationCenter.default.addObserver(forName: .CNContactStoreDidChange, object: nil, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.loadContacts() }
        }
    }

    func isEnabled(_ layer: MapLayer) -> Bool {
        settings.enabled.contains(layer)
    }

    /// Whether the layer's data was refused, so turning it on would show nothing until it's allowed in
    /// Settings.
    func isDenied(_ layer: MapLayer) -> Bool {
        switch layer {
        case .photos: [.denied, .restricted].contains(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .contacts: [.denied, .restricted].contains(CNContactStore.authorizationStatus(for: .contacts))
        }
    }

    /// Turns a layer on or off, asking for access first if it hasn't been asked. Returns false if access
    /// was refused, leaving the layer off.
    @discardableResult
    func setEnabled(_ layer: MapLayer, _ on: Bool) async -> Bool {
        if on {
            guard await requestAccess(layer) else { return false }
            settings.enabled.insert(layer)
        } else {
            settings.enabled.remove(layer)
        }
        storage.encode(settings, forKey: Self.settingsKey)
        switch layer {
        case .photos: loadPhotos()
        case .contacts: loadContacts()
        }
        return true
    }

    /// Reads whatever's turned on.
    func load() {
        loadPhotos()
        loadContacts()
    }

    private func requestAccess(_ layer: MapLayer) async -> Bool {
        switch layer {
        case .photos:
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            return status == .authorized || status == .limited
        case .contacts:
            let granted = (try? await CNContactStore().requestAccess(for: .contacts)) ?? false
            return granted || Self.canReadContacts
        }
    }

    // MARK: Photos

    private func loadPhotos() {
        photosGeneration += 1
        let generation = photosGeneration
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard isEnabled(.photos), status == .authorized || status == .limited else {
            photoGroups = []
            return
        }
        if !observingPhotos {
            observingPhotos = true
            PHPhotoLibrary.shared().register(self)
        }
        Task {
            let groups = await Task.detached(priority: .utility) { PhotoGrouping.group(Self.readPhotoPoints()) }.value
            guard generation == photosGeneration else { return }
            photoGroups = groups
        }
    }

    /// Every photo and video with a location. Locations can't be fetched for on their own, so this goes
    /// through the whole library, which takes a moment for a big one.
    private nonisolated static func readPhotoPoints() -> [PhotoPoint] {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        var points: [PhotoPoint] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard let location = asset.location else { return }
            let c = location.coordinate
            // Some cameras write 0,0 when they have no fix.
            guard CLLocationCoordinate2DIsValid(c), c.latitude != 0 || c.longitude != 0 else { return }
            points.append(PhotoPoint(id: asset.localIdentifier, coordinate: Coordinate(c), date: asset.creationDate))
        }
        return points
    }

    // MARK: Contacts

    private func loadContacts() {
        contactsGeneration += 1
        let generation = contactsGeneration
        guard isEnabled(.contacts), Self.canReadContacts else {
            contactAddresses = []
            contactThumbnails = [:]
            addressesToLookUp = 0
            return
        }
        Task {
            let read = await Task.detached(priority: .utility) { Self.readContacts() }.value
            guard generation == contactsGeneration else { return }
            contactThumbnails = read.thumbnails
            let found = read.addresses.map { address in
                var address = address
                address.coordinate = cache.coordinate(for: address.address)
                return address
            }
            contactAddresses = found.filter { $0.coordinate != nil }
            await lookUp(found.filter { $0.coordinate == nil && cache.needsLookup($0.address) }, generation: generation)
        }
    }

    /// Whether some or all contacts can be read. (The iPhone can share only some.)
    private static var canReadContacts: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        #if os(iOS)
        return status == .authorized || status == .limited
        #else
        return status == .authorized
        #endif
    }

    private nonisolated static func readContacts() -> (addresses: [ContactAddress], thumbnails: [String: Data]) {
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
        ]
        var addresses: [ContactAddress] = []
        var thumbnails: [String: Data] = [:]
        do {
            try CNContactStore().enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                let found = ContactAddress.addresses(of: contact)
                guard !found.isEmpty else { return }
                addresses += found
                if let data = contact.thumbnailImageData { thumbnails[contact.identifier] = data }
            }
        } catch {
            Log.places.error("Couldn’t read contacts: \(String(describing: error), privacy: .public)")
        }
        return (addresses, thumbnails)
    }

    /// Looks up addresses one at a time, adding each to the map as it's found. Apple limits how fast
    /// apps can look up addresses, so this goes slowly, and backs off when told to.
    private func lookUp(_ pending: [ContactAddress], generation: Int) async {
        var remaining = pending
        addressesToLookUp = remaining.count
        var failures = 0
        while let next = remaining.first, generation == contactsGeneration {
            let result = await Self.geocode(next.address)
            guard generation == contactsGeneration else { return }
            switch result {
            case .done(let coordinate):
                failures = 0
                cache.record(next.address, coordinate)
                storage.encode(cache, forKey: Self.geocodeKey)
                remaining.removeFirst()
                // Others at the same address (a household) were found too.
                for match in remaining where GeocodeCache.key(match.address) == GeocodeCache.key(next.address) {
                    var found = match
                    found.coordinate = coordinate
                    if coordinate != nil { contactAddresses.append(found) }
                }
                remaining.removeAll { GeocodeCache.key($0.address) == GeocodeCache.key(next.address) }
                if let coordinate {
                    var found = next
                    found.coordinate = coordinate
                    contactAddresses.append(found)
                }
                addressesToLookUp = remaining.count
                try? await Task.sleep(for: .milliseconds(400))
            case .failed:
                failures += 1
                // Likely throttled or offline: wait, and give up for now after a few tries.
                guard failures < 4 else {
                    addressesToLookUp = 0
                    return
                }
                try? await Task.sleep(for: .seconds(20 * failures))
            }
        }
    }

    /// An address looked up: where it is, or nil if there's no such place; or a failure to try again.
    private enum Lookup {
        case done(Coordinate?), failed
    }

    private static func geocode(_ address: String) async -> Lookup {
        #if os(iOS)
        guard let request = MKGeocodingRequest(addressString: address) else { return .done(nil) }
        do {
            let items = try await request.mapItems
            return .done(items.first.map { Coordinate(PlaceResult.coordinate(of: $0)) })
        } catch let error as MKError where error.code == .placemarkNotFound {
            return .done(nil)
        } catch {
            Log.places.error("Couldn’t look up an address: \(String(describing: error), privacy: .public)")
            return .failed
        }
        #else
        return .done(nil)
        #endif
    }
}

extension MapLayers: PHPhotoLibraryChangeObserver {
    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor in
            // Changes come in bursts (an import, iCloud syncing); read the library once they settle.
            pendingPhotos?.cancel()
            pendingPhotos = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                loadPhotos()
            }
        }
    }
}
