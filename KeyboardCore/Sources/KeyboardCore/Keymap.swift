/// Identity of a key, which is also its action. There is no separate `KeyAction` type: what a
/// key does is fully determined by which key it is (plus engine state such as shift), so a
/// second enum would be a hand-synced list.
public enum KeyID: Hashable, Sendable {
    /// A character key. Letters are stored lowercase; the engine uppercases on commit when
    /// shift is active. On the symbols layer the character is inserted as-is.
    case character(Character)
    case shift
    case backspace
    /// "123" on letters, "ABC" on symbols.
    case layerToggle
    /// Next-keyboard key. Present only when `Environment.showsGlobeKey`. The engine never
    /// acts on it: the shell routes its touches to `handleInputModeList(from:with:)`.
    case globe
    case space
    case `return`
}

public enum Layer: Hashable, Sendable {
    case letters
    case symbols
}

/// One key in a row spec. `width` is in key units: 1u = tray width / 10.
struct KeySpec: Hashable, Sendable {
    let id: KeyID
    let width: Double
}

/// The single list of keys. Layout derives every rect from it; drawing and hit-testing derive
/// from the layout; accessibility derives from the face. Adding a key means editing only here.
///
/// Internal on purpose: callers see keys only through `Layout`, so nothing outside the core can
/// grow a second list.
enum Keymap {
    /// Rows top to bottom. Mirrors `ALPHA`, `NUM` and `BOTTOM_WIDE` in prototype/index.html.
    ///
    /// - letters: `qwertyuiop` / `asdfghjkl` (9u, centred) / shift 1.5u + `zxcvbnm` + backspace 1.5u
    /// - symbols: `1234567890` / `-/:;()$&@"` / `. , ? ! '` at 1.4u each + backspace 1.5u (8.5u, centred)
    /// - bottom:  123 2.5u, space 5u, return 2.5u
    /// - bottom with globe: 123 2.5u, globe 1.5u, space 3.5u, return 2.5u (only space shrinks,
    ///   so the 123 and return targets stay where the thumb learned them)
    ///
    /// Invariant (tested): no row is wider than 10u, and `KeyID`s are unique within a layer,
    /// so `Layout.slot(of:)` is well defined.
    static func rows(for layer: Layer, showsGlobeKey: Bool) -> [[KeySpec]] {
        fatalError("not implemented")
    }
}
