import Foundation

/// Persists the committed `Placement` in the extension's own `UserDefaults.standard`, which
/// needs no App Group or Full Access.
///
/// `load()` is total. Missing, corrupt, future-version or out-of-range data falls back field by
/// field to `Placement.default`, so the engine never sees an invalid placement.
public struct PlacementStore {
    private let defaults: UserDefaults

    /// Versioned so a future schema can migrate instead of misreading.
    static let key = "placement.v1"

    public init(defaults: UserDefaults) { self.defaults = defaults }

    /// Inset and lift must be finite and in [0, 200 mm], and width in its own bounds. A record
    /// saved before width existed keeps its position and gets the default width. Clamping to a
    /// screen is `Layout`'s job.
    public func load() -> Placement {
        guard let data = defaults.data(forKey: Self.key) else { return .default }
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        guard let record = try? decoder.decode(Record.self, from: data) else { return .default }
        func valid(_ v: Double?, in range: ClosedRange<Millimetres> = 0...Placement.absoluteMax,
                   fallback: Millimetres) -> Millimetres {
            guard let v, v.isFinite, range.contains(Millimetres(v)) else { return fallback }
            return Millimetres(v)
        }
        return Placement(
            hand: record.hand.flatMap(Hand.init(rawValue:)) ?? Placement.default.hand,
            inset: valid(record.insetMM, fallback: Placement.default.inset),
            lift: valid(record.liftMM, fallback: Placement.default.lift),
            width: valid(record.widthMM, in: Placement.minWidth...Placement.maxWidth, fallback: Placement.default.width))
    }

    public func save(_ placement: Placement) {
        let record = Record(hand: placement.hand.rawValue, insetMM: placement.inset.value, liftMM: placement.lift.value,
                            widthMM: placement.width.value)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(record) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Separate from `Placement` so renaming a domain field never changes the stored schema.
    /// Each field decodes independently, so one bad field costs only that field.
    private struct Record: Codable {
        var hand: String?
        var insetMM: Double?
        var liftMM: Double?
        var widthMM: Double?

        init(hand: String?, insetMM: Double?, liftMM: Double?, widthMM: Double?) {
            self.hand = hand; self.insetMM = insetMM; self.liftMM = liftMM; self.widthMM = widthMM
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hand = try? c.decode(String.self, forKey: .hand)
            insetMM = try? c.decode(Double.self, forKey: .insetMM)
            liftMM = try? c.decode(Double.self, forKey: .liftMM)
            widthMM = try? c.decode(Double.self, forKey: .widthMM)
        }
    }
}
