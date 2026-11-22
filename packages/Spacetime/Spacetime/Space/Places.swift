import Foundation

/// How close (in meters) a todo or event has to be to a place to belong to it.
let linkRadius: Double = 30

private let unsavedPrefix = "unsaved:"

/// A pin on the map: a saved place, or a spot with todos or upcoming events that isn't saved in any
/// collection. Todos (location reminders) and events belong to the nearest place within
/// `linkRadius`.
struct MapPlace: Identifiable, Hashable, Located {
    /// The saved place's ID, or `unsaved:<latitude>,<longitude>`.
    var id: String
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    /// Its icon for the pin (see `PlaceIcon`): one picked for it, or its own on Apple's map.
    var icon: String?
    var mapIcon: String?
    /// Nil if the place only exists because of its todos or events.
    var saved: Place?
    var collectionIds: [String]
    var todos: [LocationReminder] = []
    /// Upcoming events here, soonest first.
    var events: [CalendarEvent] = []

    /// Changes when the place itself does (not its todos or events).
    var signature: String {
        "\(id)|\(name)|\(address ?? "")|\(latitude)|\(longitude)"
    }

    /// The same place with nothing at it, e.g. after it's deleted.
    var emptied: MapPlace {
        var place = self
        place.saved = nil
        place.collectionIds = []
        place.todos = []
        place.events = []
        return place
    }
}

enum Places {
    static func build(places: [Place], todos: [LocationReminder], events: [CalendarEvent] = []) -> [MapPlace] {
        var saved = places.filter { !$0.isLegacyReminder }.map { place in
            MapPlace(id: place.id, name: place.name, address: place.address, latitude: place.latitude,
                     longitude: place.longitude, icon: place.icon ?? place.mapIcon, mapIcon: place.mapIcon,
                     saved: place, collectionIds: place.collectionIds)
        }
        var unsaved: [MapPlace] = []

        func add(at point: some Located, name: String, address: String?, _ attach: (inout MapPlace) -> Void) {
            if let i = nearestIndex(saved, to: point) {
                attach(&saved[i])
            } else if let i = nearestIndex(unsaved, to: point) {
                attach(&unsaved[i])
            } else {
                var place = unsavedPlace(at: point.coordinate, name: name, address: address)
                attach(&place)
                unsaved.append(place)
            }
        }

        for todo in todos {
            add(at: todo, name: todo.placeName, address: todo.address) { $0.todos.append(todo) }
        }
        for event in events {
            guard let place = event.place else { continue }
            let (name, address) = parseLocationTitle(place.title)
            add(at: place, name: name, address: address) { $0.events.append(event) }
        }
        return saved + unsaved
    }

    /// All the pins on the map, from saved places, todos, and upcoming events.
    static func all(space: SpaceStore, calendar: CalendarStore) -> [MapPlace] {
        build(places: space.places, todos: LocationReminders.all(calendar), events: calendar.upcomingEvents)
    }

    /// An event's location for a place. Like Calendar, it's the name with the address on the next line.
    static func eventLocation(name: String, address: String?, at point: some Located) -> EventLocation {
        let title = address.map { $0.isEmpty ? name : "\(name)\n\($0)" } ?? name
        return EventLocation(title: title, latitude: point.latitude, longitude: point.longitude)
    }

    static func eventLocation(_ place: MapPlace) -> EventLocation {
        eventLocation(name: place.name, address: place.address, at: place)
    }

    /// When an event is, for a list of a place's events: "Tomorrow · 8:00 PM · Repeats".
    static func describeEventTime(_ event: CalendarEvent) -> String {
        [Dates.formatRelativeDay(event.start), event.allDay ? "All Day" : Dates.formatTime(event.start),
         event.recurring ? "Repeats" : nil]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The name and address in an event's location (see `eventLocation`).
    static func parseLocationTitle(_ title: String) -> (name: String, address: String?) {
        let lines = title.components(separatedBy: "\n")
        let name = lines[0].trimmingCharacters(in: .whitespaces)
        let address = lines.dropFirst().joined(separator: ", ").trimmingCharacters(in: .whitespaces)
        return (name.isEmpty ? "Dropped Pin" : name, address.isEmpty ? nil : address)
    }

    /// A place that isn't saved and has nothing at it yet, with its icon if it's on Apple's map.
    static func unsavedPlace(at point: Coordinate, name: String, address: String? = nil,
                             mapIcon: String? = nil) -> MapPlace {
        MapPlace(id: unsavedPrefix + String(format: "%.6f,%.6f", point.latitude, point.longitude),
                 name: name, address: address, latitude: point.latitude, longitude: point.longitude,
                 icon: mapIcon, mapIcon: mapIcon, saved: nil, collectionIds: [])
    }

    /// Places opened from the map that aren't on it (yet), like a shop on Apple's map, by ID.
    private static var shown: [String: MapPlace] = [:]

    /// Lets `find` find a place that isn't on the map, so it can be opened.
    static func remember(_ place: MapPlace) {
        shown[place.id] = place
    }

    private static func nearestIndex(_ candidates: [MapPlace], to point: some Located) -> Int? {
        var best: Int?
        var bestDistance = linkRadius
        for (i, candidate) in candidates.enumerated() {
            let distance = Geo.distanceMeters(candidate, point)
            if distance <= bestDistance {
                best = i
                bestDistance = distance
            }
        }
        return best
    }

    static func nearest(_ candidates: [MapPlace], to point: some Located) -> MapPlace? {
        nearestIndex(candidates, to: point).map { candidates[$0] }
    }

    /// Finds a place by ID or, failing that, the place nearest `near`. A place's ID changes when it's
    /// saved or unsaved, but it stays where it was. Places passed to `remember` are found too.
    static func find(_ mapPlaces: [MapPlace], id: String, near: Coordinate? = nil) -> MapPlace? {
        if let found = mapPlaces.first(where: { $0.id == id }) { return found }
        if let anchor = near ?? parseUnsavedId(id), let found = nearest(mapPlaces, to: anchor) {
            return found
        }
        return shown[id]
    }

    private static func parseUnsavedId(_ id: String) -> Coordinate? {
        guard id.hasPrefix(unsavedPrefix) else { return nil }
        let parts = id.dropFirst(unsavedPrefix.count).split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? Coordinate(latitude: parts[0], longitude: parts[1]) : nil
    }

    /// The place's collections, in its order, skipping any that were deleted.
    static func collections(of collectionIds: [String], in collections: [PlaceCollection]) -> [PlaceCollection] {
        collectionIds.compactMap { id in collections.first { $0.id == id } }
    }

    /// Its first collection's color. If it's in none: the Reminders collection's if it has todos, or
    /// else its next event's calendar's.
    static func pinColor(_ place: MapPlace, collections: [PlaceCollection], fallback: String = Theme.tintHex) -> String {
        if let first = Self.collections(of: place.collectionIds, in: collections).first { return first.color }
        if place.todos.isEmpty, let event = place.events.first { return event.color }
        return collections.first { $0.id == remindersCollectionId }?.color ?? fallback
    }

    /// Its pin's color, or blue for a place that's only been found (with nothing at it yet).
    static func badgeColor(_ place: MapPlace, collections: [PlaceCollection]) -> String {
        let found = place.saved == nil && place.todos.isEmpty && place.events.isEmpty
        return found ? Theme.blueHex : pinColor(place, collections: collections)
    }

    /// Whether the place shows when the map is filtered to a collection.
    static func isIn(_ place: MapPlace, collection id: String) -> Bool {
        if id == remindersCollectionId { return !place.todos.isEmpty }
        return place.collectionIds.contains(id)
    }

    /// Adds a place to a collection, saving it if it wasn't.
    static func add(_ place: MapPlace, toCollection id: String, space: SpaceStore) {
        guard !place.collectionIds.contains(id) else { return }
        if let saved = place.saved {
            space.updatePlace(saved.id) { $0.collectionIds.append(id) }
            return
        }
        space.addPlace(PlaceInput(name: place.name, address: place.address, latitude: place.latitude,
                                  longitude: place.longitude, collectionIds: [id], mapIcon: place.mapIcon))
    }

    /// Sets a saved place's collections. Taking it out of all of them unsaves it.
    static func setCollections(_ place: MapPlace, _ ids: [String], space: SpaceStore) {
        guard let saved = place.saved else { return }
        space.updatePlace(saved.id) { $0.collectionIds = ids }
    }

    /// Moves a place's todos along with it, and keeps their place name and address in sync.
    static func syncTodos(_ todos: [LocationReminder], name: String, address: String?, at point: Coordinate,
                          calendar: CalendarStore) throws {
        for todo in todos {
            try LocationReminders.update(
                todo,
                LocationReminderInput(title: todo.title, placeName: name, address: address, notes: todo.notes,
                                      trigger: todo.trigger, radius: todo.radius, latitude: point.latitude,
                                      longitude: point.longitude),
                calendar: calendar)
        }
    }

    /// Its collections (or address, if it's in none), its next event, and how many todos it has, e.g.
    /// "Favorites, Food · Dinner, Tomorrow · 2 todos".
    static func describe(_ place: MapPlace, collections: [PlaceCollection]) -> String {
        let names = Self.collections(of: place.collectionIds, in: collections).map(\.name)
        let todos = place.todos.count
        let next = place.events.first
        let saved: String = names.isEmpty
            ? (place.address?.isEmpty == false ? place.address! : "Not saved")
            : names.joined(separator: ", ")
        let parts: [String?] = [
            saved,
            next.map { "\($0.title), \(Dates.formatRelativeDay($0.start))" },
            todos > 0 ? "\(todos) \(todos == 1 ? "todo" : "todos")" : nil,
        ]
        return parts
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}
