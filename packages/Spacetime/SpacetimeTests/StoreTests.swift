import Foundation
import Testing
@testable import Spacetime

@MainActor
struct SpaceStoreTests {
    private let storage = MemoryStorage()

    private func input(_ name: String, _ collectionIds: [String]) -> PlaceInput {
        PlaceInput(name: name, latitude: 37.78, longitude: -122.41, collectionIds: collectionIds)
    }

    @Test func seedsTheRemindersCollection() {
        #expect(SpaceStore(storage: storage).collections.contains { $0.id == remindersCollectionId })
    }

    @Test func persistsChangesAcrossReloads() {
        let first = SpaceStore(storage: storage)
        let collection = first.addCollection(name: "Coffee", color: "#A2845E")
        first.addPlace(input("Blue Bottle", [collection.id]))
        let second = SpaceStore(storage: storage)
        #expect(second.collections.first { $0.id == collection.id }?.name == "Coffee")
        #expect(second.places.contains { $0.name == "Blue Bottle" })
    }

    @Test func deletesACollectionWithThePlacesOnlyInItButNeverTheRemindersCollection() {
        let store = SpaceStore(storage: storage)
        let collection = store.addCollection(name: "Temp", color: "#8E8E93")
        let other = store.addCollection(name: "Other", color: "#8E8E93")
        let only = store.addPlace(input("Somewhere", [collection.id]))
        let both = store.addPlace(input("Both", [collection.id, other.id]))
        #expect(store.placesOnly(in: collection.id).map(\.id) == [only.id])
        store.deleteCollection(collection.id)
        #expect(!store.places.contains { $0.id == only.id })
        #expect(store.places.first { $0.id == both.id }?.collectionIds == [other.id])
        store.deleteCollection(remindersCollectionId)
        #expect(store.collections.contains { $0.id == remindersCollectionId })
    }

    @Test func movesPlacesSavedInASingleCollectionToAListOfThem() {
        storage.set(##"{"collections":[],"places":[{"latitude":37.78,"longitude":-122.41,"id":"p","collectionId":"c","name":"Old","createdAt":0}]}"##,
                    forKey: SpaceStore.storageKey)
        let store = SpaceStore(storage: storage)
        #expect(store.places.first?.collectionIds == ["c"])
        // The Reminders collection is put back if it's missing.
        #expect(store.collections.first?.id == remindersCollectionId)
    }

    @Test func readsTheReactNativeAppsData() {
        storage.set(##"{"collections":[{"id":"reminders","name":"Reminders","color":"#FF9500","createdAt":1761500000000}],"places":[{"id":"x","collectionIds":["reminders"],"name":"Gym","latitude":1,"longitude":2,"createdAt":1761500000001,"reminder":{"title":"Stretch","trigger":"leave","radius":250,"enabled":true}}]}"##,
                    forKey: SpaceStore.storageKey)
        let place = SpaceStore(storage: storage).places.first
        #expect(place?.reminder?.trigger == .leave)
        #expect(place?.isLegacyReminder == true)
    }

    @Test func deletesAPlaceTakenOutOfEveryCollection() {
        let store = SpaceStore(storage: storage)
        let place = store.addPlace(input("Gone", ["a"]))
        store.updatePlace(place.id) { $0.collectionIds = [] }
        #expect(!store.places.contains { $0.id == place.id })
    }
}

@MainActor
struct ReminderMetaTests {
    private let storage = MemoryStorage()

    private func exists(_ ids: [String]) -> (String) async -> Bool {
        { ids.contains($0) }
    }

    private func address(_ store: ReminderMetaStore, _ id: String, _ externalId: String? = nil) -> String? {
        store.meta(for: ReminderRef(id: id, externalId: externalId)).address
    }

    @Test func persistsAcrossReloadsAndForgetsEmptyMetadata() {
        ReminderMetaStore(storage: storage).set(ReminderMeta(address: "1 Main St"), for: ReminderRef(id: "a"))
        let store = ReminderMetaStore(storage: storage)
        #expect(address(store, "a") == "1 Main St")
        store.set(ReminderMeta(), for: ReminderRef(id: "a"))
        #expect(address(ReminderMetaStore(storage: storage), "a") == nil)
    }

    @Test func findsAReminderByItsExternalIdAfterItsLocalIdChanges() {
        let store = ReminderMetaStore(storage: storage)
        store.set(ReminderMeta(address: "Home"), for: ReminderRef(id: "old", externalId: "X"))
        #expect(address(store, "new", "X") == "Home")
    }

    @Test func picksUpNewIdsFromTheRemindersItSees() async {
        let store = ReminderMetaStore(storage: storage)
        store.set(ReminderMeta(address: "Home"), for: ReminderRef(id: "a"))
        await store.reconcile(seen: [ReminderRef(id: "a", externalId: "X")], exists: exists([]))
        // Now it can be found after a resync changes the local ID.
        #expect(address(store, "b", "X") == "Home")
        await store.reconcile(seen: [ReminderRef(id: "b", externalId: "X")], exists: exists([]))
        #expect(address(store, "b") == "Home")
    }

    @Test func forgetsRemindersThatNoLongerExistButKeepsUnseenOnesThatDo() async {
        let store = ReminderMetaStore(storage: storage)
        store.set(ReminderMeta(address: "Gone"), for: ReminderRef(id: "deleted"))
        store.set(ReminderMeta(address: "Done"), for: ReminderRef(id: "completed"))
        store.set(ReminderMeta(address: "Here"), for: ReminderRef(id: "open"))
        await store.reconcile(seen: [ReminderRef(id: "open")], exists: exists(["completed", "open"]))
        #expect(address(store, "deleted") == nil)
        #expect(address(store, "completed") == "Done")
        #expect(address(store, "open") == "Here")
    }

    @Test func keepsMetadataSavedWhileItWasReconciling() async {
        let store = ReminderMetaStore(storage: storage)
        store.set(ReminderMeta(address: "Gone"), for: ReminderRef(id: "deleted"))
        await store.reconcile(seen: []) { _ in
            store.set(ReminderMeta(address: "Just saved"), for: ReminderRef(id: "new"))
            return false
        }
        #expect(address(store, "new") == "Just saved")
        #expect(address(store, "deleted") == nil)
    }
}

@MainActor
struct SavedSettingsTests {
    private let storage = MemoryStorage()

    @Test func remembersWhereTheMapWasLeft() {
        let region = SearchRegion(latitude: 19.43, longitude: -99.13, latitudeDelta: 0.03, longitudeDelta: 0.03)
        #expect(SpaceStore(storage: storage).savedMapRegion() == nil)
        SpaceStore(storage: storage).saveMapRegion(region)
        #expect(SpaceStore(storage: storage).savedMapRegion() == region)
    }

    @Test func reopensTheTimeTabAtTheLevelItWasLeftOn() {
        TimeNavigation(storage: storage).remember(.day)
        let nav = TimeNavigation(storage: storage)
        nav.openFirstTime()
        #expect(nav.path.count == 2)
        if case .day(let day) = nav.path.last { #expect(Dates.isToday(day)) } else { Issue.record("Not on a day") }
    }

    @Test func remembersTheDayViewsZoomWithinItsLimits() {
        let nav = TimeNavigation(storage: storage)
        #expect(nav.savedHourHeight == Timeline.defaultHourHeight)
        nav.saveHourHeight(100)
        #expect(TimeNavigation(storage: storage).savedHourHeight == 100)
        storage.set("9000", forKey: "spacetime.time.hourHeight")
        #expect(TimeNavigation(storage: storage).savedHourHeight == Timeline.defaultHourHeight)
    }
}
