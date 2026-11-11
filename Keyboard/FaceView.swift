import UIKit
import KeyboardCore

/// Draws a `Face` with Core Graphics in one `draw(_:)`. No subviews, no layers per key, no touch
/// handling (user interaction is disabled; the controller handles touches).
///
/// Why one drawn view: the face is a value; drawing it is a pure function of that value. There
/// is no retained per-key object tree to keep in sync with it, so the view can never show a
/// state the engine is not in. Memory is one backing store (face ~374 x 251 pt, @3x ~ 3.4 MB).
///
/// Redraw policy: `face` and `density` redraw only when they change. Moving the keyboard changes
/// the view's frame, not its face, so a drag never redraws.
final class FaceView: UIView {

    var face: Face? {
        didSet { if face != oldValue { setNeedsDisplay(); invalidateAccessibility() } }
    }
    var density: PointsPerMillimetre = .duoOuter {
        didSet { if density != oldValue { setNeedsDisplay() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        // Palette depends on light/dark; redraw when it changes.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FaceView, _) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// For each rect: `density.viewRect(rect, containerHeight: face.size.height)`. That one call
    /// is the only coordinate conversion in this file.
    ///
    /// TODO:
    /// - tray: rounded rect (top corners 10 pt, as the prototype), palette.tray
    /// - handle: grip pill centred in `face.handle`; flip glyph ("arrow.left.and.right") in
    ///   `face.flipButton`; highlighted when `face.handleIsActive`
    /// - each cap: rounded rect (5 pt) in `cap.frame`, fill by `cap.style` / `cap.isPressed`;
    ///   label: `.text` drawn with the system font sized as in the prototype
    ///   (min(h, w * (character ? 1 : 0.6)) * 0.5, clamped to [9, 24] pt);
    ///   `.symbol` via `UIImage(systemName:)` from `Self.symbolName`
    override func draw(_ rect: CGRect) {
        fatalError("not implemented")
    }

    /// The only map from the core's semantic symbols to SF Symbols.
    private static func symbolName(_ symbol: KeySymbol) -> String {
        switch symbol {
        case .shift: "shift"
        case .shiftOnce: "shift.fill"
        case .capsLock: "capslock.fill"
        case .backspace: "delete.left"
        case .globe: "globe"
        }
    }

    // MARK: Accessibility (derived from the same face; no second key list)

    /// One `UIAccessibilityElement` per cap: label from `cap.label`, trait `.keyboardKey`, frame
    /// from `cap.slot` converted to screen coordinates. Activation uses the default (a
    /// synthesized tap at the element's centre), so VoiceOver typing goes through the same touch
    /// path as a finger. There is no second way to commit a key.
    override var accessibilityElements: [Any]? {
        get { fatalError("not implemented") }
        set { }
    }

    private func invalidateAccessibility() {
        // TODO: UIAccessibility.post(notification: .layoutChanged, argument: nil) when the
        // set of keys changes (layer switch), not on every press highlight.
    }
}

/// Colours for both appearances. Shell-only: the core never knows about colour.
private struct Palette {
    let tray: UIColor
    let characterKey: UIColor
    let modifierKey: UIColor
    let pressedKey: UIColor
    let label: UIColor

    init(_ traits: UITraitCollection) { fatalError("not implemented") }
}
