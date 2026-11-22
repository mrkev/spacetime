import Testing
@testable import Spacetime

struct RecentKeysTests {
    @Test func dropsTheLeastRecentlyUsedKeys() {
        var recent = RecentKeys(limit: 2)
        #expect(recent.use("a") == [])
        #expect(recent.use("b") == [])
        #expect(recent.use("a") == [])
        #expect(recent.use("c") == ["b"])
        #expect(recent.keys == ["a", "c"])
    }
}
