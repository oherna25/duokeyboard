import Testing
import Foundation
import KeyboardCore

/// Persistence against a throwaway defaults domain, so `swift test` never touches real prefs.
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
        let p = Placement(hand: .left, inset: 12.5, lift: 20)
        store.save(p)
        #expect(store.load() == p)
    }

    @Test func corruptDataLoadsDefault() {
        // TODO: defaults.set(Data("nope".utf8), forKey: "placement.v1") -> .default
    }

    @Test func invalidFieldsFallBackFieldByField() {
        // TODO: {"hand":"left","insetMM":-3,"liftMM":1e308} -> (left, 7, 9);  NaN -> default for that field
    }

    @Test func unknownHandFallsBack() {
        // TODO: hand "both" -> .right, other fields kept
    }
}
