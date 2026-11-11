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

    /// Validation: hand must parse; inset and lift must be finite and in [0, 200 mm], else that
    /// field takes its default. No clamping to any screen here: that is `Layout`'s job, against
    /// the surface it is actually on.
    public func load() -> Placement {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let record = try? decoder.decode(Record.self, from: data) else { return .default }
        func valid(_ v: Double?, fallback: Millimetres) -> Millimetres {
            guard let v, v.isFinite, v >= 0, v <= Placement.absoluteMax.value else { return fallback }
            return Millimetres(v)
        }
        return Placement(
            hand: record.hand.flatMap(Hand.init(rawValue:)) ?? Placement.default.hand,
            inset: valid(record.insetMM, fallback: Placement.default.inset),
            lift: valid(record.liftMM, fallback: Placement.default.lift))
    }

    /// Idempotent: saving the same placement twice writes the same bytes.
    public func save(_ placement: Placement) {
        let record = Record(hand: placement.hand.rawValue, insetMM: placement.inset.value, liftMM: placement.lift.value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// The on-disk shape. Separate from `Placement` so renaming a domain field never silently
    /// changes the stored schema. Plain doubles: no wrapper types in the wire format. Each field
    /// decodes independently, so one bad field costs only that field.
    private struct Record: Codable {
        var hand: String?
        var insetMM: Double?
        var liftMM: Double?

        init(hand: String?, insetMM: Double?, liftMM: Double?) {
            self.hand = hand; self.insetMM = insetMM; self.liftMM = liftMM
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hand = try? c.decode(String.self, forKey: .hand)
            insetMM = try? c.decode(Double.self, forKey: .insetMM)
            liftMM = try? c.decode(Double.self, forKey: .liftMM)
        }
    }
}
