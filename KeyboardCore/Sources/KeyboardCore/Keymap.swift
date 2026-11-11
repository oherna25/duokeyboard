/// Identity of a key, which is also its action.
public enum KeyID: Hashable, Sendable {
    /// Letters are stored lowercase and uppercased on commit when shift is active.
    case character(Character)
    case shift
    case backspace
    case layerToggle
    /// Present only when `Environment.showsGlobeKey`. The engine never acts on it. The shell
    /// routes its touches to `handleInputModeList(from:with:)`.
    case globe
    case space
    case `return`
}

public enum Layer: Hashable, Sendable {
    case letters
    case symbols
}

/// `width` is in key units, where 1u is tray width / 10.
struct KeySpec: Hashable, Sendable {
    let id: KeyID
    let width: Double
}

/// The single list of keys. Internal so callers see keys only through `Layout`.
enum Keymap {
    /// Rows top to bottom. Mirrors `ALPHA`, `NUM` and `BOTTOM_WIDE` in prototype/index.html.
    /// With the globe only space shrinks, so the 123 and return targets stay where the thumb
    /// learned them.
    ///
    /// No row is wider than 10u and `KeyID`s are unique within a layer, so `Layout.slot(of:)`
    /// is well defined.
    static func rows(for layer: Layer, showsGlobeKey: Bool) -> [[KeySpec]] {
        func chars(_ s: String, width: Double = 1) -> [KeySpec] {
            s.map { KeySpec(id: .character($0), width: width) }
        }
        let backspace = KeySpec(id: .backspace, width: 1.5)
        let upper: [[KeySpec]]
        switch layer {
        case .letters:
            upper = [
                chars("qwertyuiop"),
                chars("asdfghjkl"),
                [KeySpec(id: .shift, width: 1.5)] + chars("zxcvbnm") + [backspace],
            ]
        case .symbols:
            upper = [
                chars("1234567890"),
                chars("-/:;()$&@\""),
                chars(".,?!'", width: 1.4) + [backspace],
            ]
        }
        let toggle = KeySpec(id: .layerToggle, width: 2.5)
        let enter = KeySpec(id: .return, width: 2.5)
        let bottom = showsGlobeKey
            ? [toggle, KeySpec(id: .globe, width: 1.5), KeySpec(id: .space, width: 3.5), enter]
            : [toggle, KeySpec(id: .space, width: 5), enter]
        return upper + [bottom]
    }
}
