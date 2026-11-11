import Testing
import Foundation
import KeyboardCore

@Suite struct PlacementStoreTests {
    let defaults: UserDefaults
    let store: PlacementStore

    init() {
        let suite = "PlacementStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        store = PlacementStore(defaults: defaults)
    }

    @Test func missingDataLoadsDefault() {
        #expect(store.load() == .default)
    }

    @Test func roundTrips() {
        let p = Placement(hand: .left, inset: 12.5, lift: 20, width: 54)
        store.save(p)
        #expect(store.load() == p)
    }

    private func store(json: String) -> Placement {
        defaults.set(Data(json.utf8), forKey: "placement.v1")
        return store.load()
    }

    @Test func corruptDataLoadsDefault() {
        defaults.set(Data("nope".utf8), forKey: "placement.v1")
        #expect(store.load() == .default)
    }

    @Test func invalidFieldsFallBackFieldByField() {
        #expect(store(json: #"{"hand":"left","insetMM":-3,"liftMM":1e308}"#) == Placement(hand: .left, inset: 0, lift: 9, width: 50))
        #expect(store(json: #"{"hand":"left","insetMM":"nan","liftMM":12}"#) == Placement(hand: .left, inset: 0, lift: 12, width: 50))
        #expect(store(json: #"{"hand":"left","insetMM":"wide","liftMM":12}"#) == Placement(hand: .left, inset: 0, lift: 12, width: 50))
    }

    @Test func unknownHandFallsBack() {
        #expect(store(json: #"{"hand":"both","insetMM":11,"liftMM":12}"#) == Placement(hand: .right, inset: 11, lift: 12, width: 50))
    }

    @Test func storedPositionIsNotClampedToAnyScreen() {
        let wide = Placement(hand: .right, inset: 80, lift: 9, width: 54)
        store.save(wide)
        #expect(store.load() == wide)
    }

    @Test func aRecordFromBeforeWidthKeepsItsPosition() {
        #expect(store(json: #"{"hand":"right","insetMM":0,"liftMM":0}"#) == Placement.default.with(lift: 0))
    }

    @Test func widthOutsideItsBoundsFallsBack() {
        #expect(store(json: #"{"hand":"right","insetMM":3,"liftMM":4,"widthMM":12}"#).width == Placement.default.width)
        #expect(store(json: #"{"hand":"right","insetMM":3,"liftMM":4,"widthMM":"nan"}"#).width == Placement.default.width)
        #expect(store(json: #"{"hand":"right","insetMM":3,"liftMM":4,"widthMM":61.5}"#).width == 61.5)
    }

    @Test func savingTwiceWritesTheSameBytes() {
        let p = Placement(hand: .left, inset: 12.5, lift: 20, width: 54)
        store.save(p)
        let first = defaults.data(forKey: "placement.v1")
        store.save(p)
        #expect(defaults.data(forKey: "placement.v1") == first)
    }
}
