import EventKit
import Foundation
import Testing
@testable import Spacetime

private let bakery = Coordinate(latitude: 19.4326, longitude: -99.1332)
// About 11 m north of the bakery.
private let nearBakery = Coordinate(latitude: 19.4327, longitude: -99.1332)
// About 1.1 km north.
private let elsewhere = Coordinate(latitude: 19.4426, longitude: -99.1332)

private let collections = [
    PlaceCollection(id: remindersCollectionId, name: "Reminders", color: "#FF9500", createdAt: 0),
    PlaceCollection(id: "food", name: "Food", color: "#34C759", createdAt: 1),
    PlaceCollection(id: "favorites", name: "Favorites", color: "#007AFF", createdAt: 2),
]

@MainActor
private func place(_ id: String, _ collectionIds: [String], at: Coordinate = bakery) -> Place {
    Place(id: id, collectionIds: collectionIds, name: id, latitude: at.latitude, longitude: at.longitude, createdAt: 0)
}

@MainActor
private func reminder(_ id: String = "r1", alarm: LocatedAlarm? = nil) -> CalendarReminder {
    CalendarReminder(key: id, title: id, due: nil, allDay: false, completed: false, color: "#FF9500",
                     listTitle: "Reminders", locatedAlarm: alarm)
}

@MainActor
private func todo(_ id: String, at: Coordinate, placeName: String = "Spot") -> LocationReminder {
    LocationReminder(id: id, title: id, placeName: placeName, latitude: at.latitude, longitude: at.longitude,
                     trigger: .arrive, radius: 100, completed: false, reminder: reminder(id))
}

@MainActor
private func event(_ key: String, at: Coordinate?, title: String = "Spot") -> CalendarEvent {
    CalendarEvent(key: key, title: key, start: Dates.date(year: 2026, month: 11, day: 1, hour: 20),
                  end: Dates.date(year: 2026, month: 11, day: 1, hour: 22), allDay: false, color: "#AF52DE",
                  calendarTitle: "Home", location: at.map { _ in title },
                  place: at.map { EventLocation(title: title, latitude: $0.latitude, longitude: $0.longitude) },
                  editable: true, recurring: false, eventId: key, calendarId: "home")
}

@MainActor
struct PlacesTests {
    @Test func givesSavedPlacesTheTodosNearThem() {
        let mapPlaces = Places.build(places: [place("bakery", ["food"])], todos: [todo("bread", at: nearBakery)])
        #expect(mapPlaces.count == 1)
        #expect(mapPlaces[0].saved?.id == "bakery")
        #expect(mapPlaces[0].todos.map(\.id) == ["bread"])
    }

    @Test func groupsTodosThatArentAtASavedPlaceIntoUnsavedPlaces() {
        let mapPlaces = Places.build(
            places: [place("bakery", ["food"])],
            todos: [todo("a", at: elsewhere, placeName: "Market"), todo("b", at: elsewhere), todo("bread", at: bakery)])
        let unsaved = mapPlaces.filter { $0.saved == nil }
        #expect(unsaved.count == 1)
        #expect(unsaved[0].name == "Market")
        #expect(unsaved[0].todos.map(\.id) == ["a", "b"])
    }

    @Test func putsEventsAtThePlaceTheyreAtOrAnUnsavedOneNamedAfterTheirLocation() {
        let mapPlaces = Places.build(
            places: [place("bakery", ["food"])], todos: [todo("a", at: elsewhere)],
            events: [event("dinner", at: nearBakery), event("party", at: elsewhere), event("call", at: nil)])
        #expect(mapPlaces.count == 2)
        #expect(mapPlaces[0].id == "bakery" && mapPlaces[0].events.map(\.key) == ["dinner"])
        #expect(mapPlaces[1].id.hasPrefix("unsaved:") && mapPlaces[1].events.map(\.key) == ["party"])

        let market = Places.build(places: [place("bakery", ["food"])], todos: [],
                                  events: [event("party", at: elsewhere, title: "Market\nCalle 1\nCDMX")])[1]
        #expect(market.name == "Market")
        #expect(market.address == "Calle 1, CDMX")
    }

    @Test func leavesOutPlacesWaitingToMoveToReminders() {
        #expect(Places.build(places: [place("old", [remindersCollectionId])], todos: []).isEmpty)
    }

    @Test func findsAnUnsavedPlaceByWhereItIsAfterItsIdChanges() {
        let before = Places.build(places: [], todos: [todo("bread", at: bakery)])
        let after = Places.build(places: [place("bakery", ["food"], at: nearBakery)], todos: [todo("bread", at: bakery)])
        #expect(Places.find(after, id: before[0].id)?.id == "bakery")
    }

    @Test func findsARememberedPlaceThatIsntOnTheMapUntilOneIsSavedThere() {
        let shop = Places.unsavedPlace(at: elsewhere, name: "Shop")
        Places.remember(shop)
        #expect(Places.find(Places.build(places: [], todos: []), id: shop.id) == shop)
        let saved = Places.build(places: [place("shop", ["food"], at: elsewhere)], todos: [])
        #expect(Places.find(saved, id: shop.id)?.id == "shop")
    }

    @Test func fallsBackToThePlaceNearestWhereItWas() {
        let mapPlaces = Places.build(places: [place("bakery", ["food"])], todos: [])
        #expect(Places.find(mapPlaces, id: "gone", near: nearBakery)?.id == "bakery")
        #expect(Places.find(mapPlaces, id: "gone", near: elsewhere) == nil)
    }

    @Test func colorsPinsByFirstCollectionOrRemindersForUnsavedPlaces() {
        let mapPlaces = Places.build(places: [place("bakery", ["favorites", "food"])], todos: [todo("a", at: elsewhere)])
        #expect(Places.pinColor(mapPlaces[0], collections: collections, fallback: "#000") == "#007AFF")
        #expect(Places.pinColor(mapPlaces[1], collections: collections, fallback: "#000") == "#FF9500")
    }

    @Test func colorsUnsavedPlacesWithOnlyEventsByTheNextEventsCalendar() {
        let mapPlace = Places.build(places: [], todos: [], events: [event("dinner", at: bakery)])[0]
        #expect(Places.pinColor(mapPlace, collections: collections, fallback: "#000") == "#AF52DE")
    }

    @Test func usesAPickedIconOverThePlacesOwnFromAppleMaps() {
        var own = place("bakery", ["food"])
        own.mapIcon = "image:place-icons/a@3x.png"
        #expect(Places.build(places: [own], todos: [])[0].icon == "image:place-icons/a@3x.png")
        own.icon = "symbol:birthday.cake.fill"
        #expect(Places.build(places: [own], todos: [])[0].icon == "symbol:birthday.cake.fill")
    }

    @Test func putsTheAddressOnTheLineAfterTheNameLikeCalendar() {
        let location = Places.eventLocation(name: "Bakery", address: "Calle 1", at: bakery)
        #expect(location.title == "Bakery\nCalle 1")
        #expect(Places.eventLocation(name: "Bakery", address: nil, at: bakery).title == "Bakery")
        let parsed = Places.parseLocationTitle(location.title)
        #expect(parsed.name == "Bakery" && parsed.address == "Calle 1")
        #expect(Places.parseLocationTitle("  ").name == "Dropped Pin")
    }

    @Test func filtersTheRemindersCollectionByTodos() {
        let mapPlaces = Places.build(places: [place("bakery", ["food"])], todos: [todo("a", at: elsewhere)])
        #expect(!Places.isIn(mapPlaces[0], collection: remindersCollectionId))
        #expect(Places.isIn(mapPlaces[0], collection: "food"))
        #expect(Places.isIn(mapPlaces[1], collection: remindersCollectionId))
    }
}

@MainActor
struct LocationReminderTests {
    private let market = LocatedAlarm(title: "Market", proximity: .leave, radius: 500, latitude: 37.78,
                                      longitude: -122.41)

    @Test func readsThePlaceAndTriggerFromTheLocationAlarm() {
        let location = LocationReminders.from(reminder(alarm: market), meta: nil)
        #expect(location?.id == "r1")
        #expect(location?.placeName == "Market")
        #expect(location?.trigger == .leave)
        #expect(location?.radius == 500)
        #expect(location?.latitude == 37.78 && location?.longitude == -122.41)
    }

    @Test func usesRemindersDefaultsForAMissingRadiusOrProximity() {
        let home = LocatedAlarm(title: "Home", proximity: .none, radius: 0, latitude: 37.78, longitude: -122.41)
        let location = LocationReminders.from(reminder(alarm: home), meta: nil)
        #expect(location?.trigger == .arrive)
        #expect(location?.radius == defaultRadius)
    }

    @Test func ignoresRemindersWithoutALocatedAlarm() {
        #expect(LocationReminders.from(reminder(), meta: nil) == nil)
    }

    @Test func addsALocationAlarmWithTheDefaultsKeepingOtherAlarms() {
        let timed = EKAlarm(relativeOffset: 0)
        let alarms = LocationReminders.movedAlarms(reminder(), alarms: [timed], to: bakery, name: "Bakery",
                                                   defaults: (.arrive, 250))
        #expect(alarms.count == 2)
        #expect(alarms[0] === timed)
        #expect(alarms[1].structuredLocation?.title == "Bakery")
        #expect(alarms[1].proximity == .enter)
        #expect(alarms[1].structuredLocation?.radius == 250)
        #expect(alarms[1].structuredLocation?.geoLocation?.coordinate.latitude == bakery.latitude)
    }

    @Test func replacesALocationKeepingItsTriggerAndRadius() {
        let old = LocationReminders.alarm(placeName: "Market", trigger: .leave, radius: 500, latitude: 37.78,
                                          longitude: -122.41)
        let alarms = LocationReminders.movedAlarms(reminder(alarm: market), alarms: [old], to: bakery,
                                                   name: "Bakery", defaults: (.arrive, 250))
        #expect(alarms.count == 1)
        #expect(alarms[0].structuredLocation?.title == "Bakery")
        #expect(alarms[0].proximity == .leave)
        #expect(alarms[0].structuredLocation?.radius == 500)
    }

    @Test func describesTriggers() {
        #expect(LocationReminders.describeTrigger(trigger: .arrive, radius: 250) == "Arriving · 250 m")
        #expect(LocationReminders.describeTrigger(trigger: .leave, radius: 1000) == "Leaving · 1 km")
    }
}
