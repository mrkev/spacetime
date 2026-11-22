import Foundation

/// The built-in collection of places with todos, which are location reminders in Apple Reminders
/// (see `LocationReminders.swift`). Places can't be added to it; only its name and color are stored.
nonisolated let remindersCollectionId = "reminders"

nonisolated struct PlaceCollection: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var color: String
    var createdAt: Double
}

nonisolated enum ReminderTrigger: String, Codable, Hashable, Sendable {
    case arrive, leave
}

/// A location reminder from before they moved to Apple Reminders.
nonisolated struct LegacyReminder: Codable, Hashable, Sendable {
    var title: String
    var trigger: ReminderTrigger
    var radius: Double
    var enabled: Bool
}

/// A saved place: one that's in at least one collection.
nonisolated struct Place: Codable, Identifiable, Hashable, Sendable, Located {
    var id: String
    /// In the order the user sorted them. The first one colors the place's pin.
    var collectionIds: [String]
    var name: String
    var address: String?
    var notes: String?
    var latitude: Double
    var longitude: Double
    /// An icon picked for it (see `PlaceIcon`), which takes the place of `mapIcon`.
    var icon: String?
    /// Its own icon on Apple's map, if it was saved from there.
    var mapIcon: String?
    var createdAt: Double
    /// Only on places saved in the Reminders collection by older versions, until they're moved.
    var reminder: LegacyReminder?

    init(id: String, collectionIds: [String], name: String, address: String? = nil, notes: String? = nil,
         latitude: Double, longitude: Double, icon: String? = nil, mapIcon: String? = nil,
         createdAt: Double = Date().timeIntervalSince1970 * 1000, reminder: LegacyReminder? = nil) {
        self.id = id
        self.collectionIds = collectionIds
        self.name = name
        self.address = address
        self.notes = notes
        self.latitude = latitude
        self.longitude = longitude
        self.icon = icon
        self.mapIcon = mapIcon
        self.createdAt = createdAt
        self.reminder = reminder
    }

    private enum CodingKeys: String, CodingKey {
        case id, collectionIds, collectionId, name, address, notes, latitude, longitude, icon, mapIcon, createdAt,
             reminder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // Places used to be in a single collection.
        if let ids = try c.decodeIfPresent([String].self, forKey: .collectionIds) {
            collectionIds = ids
        } else {
            collectionIds = (try c.decodeIfPresent(String.self, forKey: .collectionId)).map { [$0] } ?? []
        }
        name = try c.decode(String.self, forKey: .name)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        mapIcon = try c.decodeIfPresent(String.self, forKey: .mapIcon)
        createdAt = try c.decodeIfPresent(Double.self, forKey: .createdAt) ?? 0
        reminder = try c.decodeIfPresent(LegacyReminder.self, forKey: .reminder)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(collectionIds, forKey: .collectionIds)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(address, forKey: .address)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(mapIcon, forKey: .mapIcon)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encodeIfPresent(reminder, forKey: .reminder)
    }

    /// A place in the Reminders collection, from before location reminders moved to Apple Reminders.
    var isLegacyReminder: Bool { collectionIds.contains(remindersCollectionId) }
}

/// What a new place is made from.
struct PlaceInput {
    var name: String
    var address: String?
    var notes: String?
    var latitude: Double
    var longitude: Double
    var collectionIds: [String]
    var icon: String?
    var mapIcon: String?
}

private nonisolated struct SpaceState: Codable {
    var collections: [PlaceCollection]
    var places: [Place]
}

/// Collections and the places saved in them, kept on this device.
@Observable
final class SpaceStore {
    static let storageKey = "spacetime.space.v1"

    private(set) var collections: [PlaceCollection]
    private(set) var places: [Place]
    @ObservationIgnored private let storage: KeyValueStorage

    init(storage: KeyValueStorage) {
        self.storage = storage
        if var state = storage.decode(SpaceState.self, forKey: Self.storageKey) {
            if !state.collections.contains(where: { $0.id == remindersCollectionId }) {
                state.collections.insert(Self.seed().collections[0], at: 0)
            }
            collections = state.collections
            places = state.places
        } else {
            let seed = Self.seed()
            collections = seed.collections
            places = seed.places
        }
    }

    private static func seed() -> SpaceState {
        let now = Date().timeIntervalSince1970 * 1000
        return SpaceState(
            collections: [
                PlaceCollection(id: remindersCollectionId, name: "Reminders", color: "#FF9500", createdAt: now),
                PlaceCollection(id: createId(), name: "Favorites", color: "#007AFF", createdAt: now + 1),
                PlaceCollection(id: createId(), name: "Want to Go", color: "#34C759", createdAt: now + 2),
            ],
            places: [])
    }

    private func save() {
        storage.encode(SpaceState(collections: collections, places: places), forKey: Self.storageKey)
    }

    var remindersCollection: PlaceCollection? {
        collections.first { $0.id == remindersCollectionId }
    }

    /// The Reminders collection's color, which todos' pins and geofences use.
    var reminderColor: String { remindersCollection?.color ?? Theme.tintHex }

    // MARK: Collections

    @discardableResult
    func addCollection(name: String, color: String) -> PlaceCollection {
        let collection = PlaceCollection(id: createId(), name: name, color: color,
                                         createdAt: Date().timeIntervalSince1970 * 1000)
        collections.append(collection)
        save()
        return collection
    }

    func updateCollection(_ id: String, name: String? = nil, color: String? = nil) {
        guard let i = collections.firstIndex(where: { $0.id == id }) else { return }
        if let name { collections[i].name = name }
        if let color { collections[i].color = color }
        save()
    }

    /// Deletes a collection, and the places that were only in it. The Reminders collection can't be
    /// deleted.
    func deleteCollection(_ id: String) {
        guard id != remindersCollectionId else { return }
        collections.removeAll { $0.id == id }
        places = places.compactMap { place in
            guard place.collectionIds.contains(id) else { return place }
            var place = place
            place.collectionIds.removeAll { $0 == id }
            return place.collectionIds.isEmpty ? nil : place
        }
        save()
    }

    /// The places that are only in this collection, which deleting it deletes.
    func placesOnly(in id: String) -> [Place] {
        places.filter { $0.collectionIds == [id] }
    }

    // MARK: Places

    @discardableResult
    func addPlace(_ input: PlaceInput) -> Place {
        let place = Place(id: createId(), collectionIds: input.collectionIds, name: input.name,
                          address: input.address, notes: input.notes, latitude: input.latitude,
                          longitude: input.longitude, icon: input.icon, mapIcon: input.mapIcon)
        places.append(place)
        save()
        return place
    }

    /// Updates a place. Taking it out of every collection deletes it.
    func updatePlace(_ id: String, _ change: (inout Place) -> Void) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        var place = places[i]
        change(&place)
        if place.collectionIds.isEmpty {
            deletePlace(id)
            return
        }
        places[i] = place
        save()
    }

    func deletePlace(_ id: String) {
        places.removeAll { $0.id == id }
        save()
    }
}
