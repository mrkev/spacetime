import Contacts
import Foundation
import Testing
@testable import Spacetime

@MainActor
struct PhotoGroupingTests {
    private func point(_ id: String, _ latitude: Double, _ longitude: Double, day: Int? = nil) -> PhotoPoint {
        PhotoPoint(id: id, coordinate: Coordinate(latitude: latitude, longitude: longitude),
                   date: day.map { Dates.date(year: 2026, month: 11, day: $0) })
    }

    @Test func groupsPhotosTakenAtTheSameSpot() {
        // About 10 meters apart, and about 5 km away.
        let groups = PhotoGrouping.group([
            point("a", 40.74410, -73.98800),
            point("b", 40.74419, -73.98805),
            point("c", 40.78000, -73.96000),
        ])
        #expect(groups.count == 2)
        #expect(groups.map { Set($0.photoIds) }.contains(["a", "b"]))
        #expect(groups.map(\.photoIds).contains(["c"]))
    }

    @Test func putsAGroupAtItsPhotosAverageSpot() {
        let groups = PhotoGrouping.group([point("a", 40.74410, -73.98800), point("b", 40.74420, -73.98810)])
        let group = try! #require(groups.first)
        #expect(abs(group.coordinate.latitude - 40.74415) < 1e-9)
        #expect(abs(group.coordinate.longitude + 73.98805) < 1e-9)
    }

    @Test func ordersAGroupsPhotosNewestFirst() {
        let groups = PhotoGrouping.group([
            point("old", 40.7441, -73.988, day: 1),
            point("new", 40.7441, -73.988, day: 20),
            point("undated", 40.7441, -73.988),
            point("middle", 40.7441, -73.988, day: 10),
        ])
        #expect(groups.first?.photoIds == ["new", "middle", "old", "undated"])
        #expect(groups.first?.newest == Dates.date(year: 2026, month: 11, day: 20))
    }

    @Test func keepsGroupsAboutAsWideNearThePoles() {
        // 150 m cells: at 70° north, where a degree of longitude is about 38 km, two photos 100 m apart
        // east-west share one, and two 400 m apart don't.
        let near = PhotoGrouping.group([point("a", 70.00001, 19.99665), point("b", 70.00001, 19.99929)])
        let far = PhotoGrouping.group([point("a", 70.00001, 19.99665), point("b", 70.00001, 20.00719)])
        #expect(near.count == 1)
        #expect(far.count == 2)
    }

    @Test func givesTheSameGroupTheSameIdEachTime() {
        let points = [point("a", 40.7441, -73.988), point("b", 51.5, -0.12)]
        #expect(PhotoGrouping.group(points).map(\.id) == PhotoGrouping.group(points.reversed()).map(\.id))
    }
}

@MainActor
struct GeocodeCacheTests {
    @Test func remembersAnAddressHoweverItsWritten() {
        var cache = GeocodeCache()
        cache.record("1 Main St, Springfield", Coordinate(latitude: 1, longitude: 2))
        #expect(cache.coordinate(for: "1  main st,springfield") == Coordinate(latitude: 1, longitude: 2))
        #expect(!cache.needsLookup("1 MAIN ST, SPRINGFIELD"))
        #expect(cache.needsLookup("2 Main St, Springfield"))
    }

    @Test func triesAnAddressThatWasntFoundAgainLater() {
        var cache = GeocodeCache()
        let then = Date(timeIntervalSince1970: 1_000_000)
        cache.record("Nowhere", nil, now: then)
        #expect(cache.coordinate(for: "Nowhere") == nil)
        #expect(!cache.needsLookup("Nowhere", now: then.addingTimeInterval(24 * 3600)))
        #expect(cache.needsLookup("Nowhere", now: then.addingTimeInterval(GeocodeCache.retryAfter + 1)))
    }

    @Test func savesAndReadsBack() throws {
        var cache = GeocodeCache()
        cache.record("1 Main St", Coordinate(latitude: 1, longitude: 2))
        cache.record("Nowhere", nil)
        let decoded = try JSONDecoder().decode(GeocodeCache.self, from: JSONEncoder().encode(cache))
        #expect(decoded == cache)
    }
}

@MainActor
struct ContactAddressTests {
    @Test func listsEachOfAContactsAddressesOnOneLine() {
        let contact = CNMutableContact()
        contact.givenName = "Ada"
        contact.familyName = "Lovelace"
        let home = CNMutablePostalAddress()
        home.street = "12 St James's Square"
        home.city = "London"
        home.postalCode = "SW1Y 4JH"
        home.country = "United Kingdom"
        let empty = CNMutablePostalAddress()
        contact.postalAddresses = [
            CNLabeledValue(label: CNLabelHome, value: home),
            CNLabeledValue(label: CNLabelWork, value: empty),
        ]
        let addresses = ContactAddress.addresses(of: contact)
        #expect(addresses.count == 1)
        let address = try! #require(addresses.first)
        #expect(address.name == "Ada Lovelace")
        #expect(address.label == CNLabeledValue<CNPostalAddress>.localizedString(forLabel: CNLabelHome))
        #expect(address.address.contains("12 St James's Square"))
        #expect(address.address.contains("London"))
        #expect(!address.address.contains("\n"))
        #expect(address.contactId == contact.identifier)
    }

    @Test func namesACompanyByItsName() {
        let contact = CNMutableContact()
        contact.organizationName = "Apple"
        let address = CNMutablePostalAddress()
        address.street = "1 Apple Park Way"
        address.city = "Cupertino"
        contact.postalAddresses = [CNLabeledValue(label: CNLabelWork, value: address)]
        #expect(ContactAddress.addresses(of: contact).first?.name == "Apple")
    }
}

@MainActor
struct MapLayerSettingsTests {
    @Test func savesWhatsTurnedOn() async {
        let storage = MemoryStorage()
        let layers = MapLayers(storage: storage)
        #expect(!layers.isEnabled(.photos) && !layers.isEnabled(.contacts))
        // Turning a layer off doesn't ask for anything.
        await layers.setEnabled(.contacts, false)
        storage.encode(MapLayerSettings(enabled: [.photos]), forKey: "spacetime.map.layers")
        let reopened = MapLayers(storage: storage)
        #expect(reopened.isEnabled(.photos) && !reopened.isEnabled(.contacts))
    }
}
