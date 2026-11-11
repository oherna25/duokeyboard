import Foundation

/// Persists the committed `Placement` in the extension's own `UserDefaults.standard`
/// (no App Group, no Full Access needed).
///
/// Sole owner of the storage key and the on-disk schema: nothing else reads or writes them.
/// Lives in the core (not the shell) so the decode-and-validate path runs under `swift test`
/// against a throwaway `UserDefaults(suiteName:)`.
///
/// Boundary discipline: `load()` is total. Missing, corrupt, future-version or out-of-range data
/// all decode to a valid `Placement` (falling back field-by-field to `Placement.default`), so
/// the engine never sees an invalid placement and has no error path.
public struct PlacementStore {
    private let defaults: UserDefaults

    /// Versioned so a future schema can migrate instead of misreading.
    static let key = "placement.v1"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Validation: hand must parse; inset and lift must be finite and >= 0 and below a sanity
    /// ceiling (200 mm), else that field takes its default. No clamping to any screen here: that
    /// is `Layout`'s job, against the surface it is actually on.
    public func load() -> Placement {
        // TODO: defaults.data(forKey:) -> JSONDecoder().decode(Record.self) -> sanitize -> Placement
        fatalError("not implemented")
    }

    /// Idempotent: saving the same placement twice writes the same bytes.
    public func save(_ placement: Placement) {
        fatalError("not implemented")
    }

    /// The on-disk shape. Separate from `Placement` so renaming a domain field never silently
    /// changes the stored schema. Plain doubles: no wrapper types in the wire format.
    private struct Record: Codable {
        var hand: String
        var insetMM: Double
        var liftMM: Double
    }
}
