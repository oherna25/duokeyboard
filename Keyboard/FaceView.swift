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
        didSet {
            guard face != oldValue else { return }
            setNeedsDisplay()
            invalidateAccessibility(from: oldValue)
        }
    }
    var density: PointsPerMillimetre = .duoOuter {
        didSet { if density != oldValue { setNeedsDisplay() } }
    }

    private var elements: [UIAccessibilityElement]?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isUserInteractionEnabled = false
        contentMode = .redraw
        // Palette depends on light/dark; redraw when it changes.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FaceView, _) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Every rect goes through `viewRect(_:containerHeight:)` with the face's own height. That
    /// one call is the only coordinate conversion in this file.
    override func draw(_ rect: CGRect) {
        guard let face else { return }
        let palette = Palette(traitCollection)
        let faceHeight = face.size.height
        func viewRect<Space>(_ r: MMRect<Space>) -> CGRect { density.viewRect(r, containerHeight: faceHeight) }

        // Tray and handle strip share one outline, rounded at the top like the prototype.
        let outline = viewRect(face.tray).union(viewRect(face.handle))
        palette.tray.setFill()
        UIBezierPath(roundedRect: outline, byRoundingCorners: [.topLeft, .topRight],
                     cornerRadii: CGSize(width: 10, height: 10)).fill()

        drawHandle(face, palette: palette, viewRect: viewRect(face.handle), flip: viewRect(face.flipButton))

        for cap in face.caps {
            let frame = viewRect(cap.frame)
            let fill: UIColor
            switch (cap.isPressed, cap.style) {
            case (true, _): fill = palette.pressedKey
            case (false, .character), (false, .modifierActive): fill = palette.characterKey
            case (false, .modifier): fill = palette.modifierKey
            }
            fill.setFill()
            UIBezierPath(roundedRect: frame, cornerRadius: 5).fill()
            drawLabel(cap.label, style: cap.style, in: frame, color: palette.label)
        }
    }

    private func drawHandle(_ face: Face, palette: Palette, viewRect handle: CGRect, flip: CGRect) {
        let gripColor = palette.label.withAlphaComponent(face.handleIsActive ? 0.7 : 0.35)
        // Centred on the part of the strip the flip button leaves free.
        let free = handle.intersection(handle.divided(atDistance: flip.width, from: face.hand == .right ? .minXEdge : .maxXEdge).remainder)
        let grip = CGRect(x: 0, y: 0, width: density.points(8), height: density.points(1.2))
            .offsetBy(dx: free.midX - density.points(4), dy: free.midY - density.points(0.6))
        gripColor.setFill()
        UIBezierPath(roundedRect: grip, cornerRadius: grip.height / 2).fill()
        drawSymbol("arrow.left.and.right", pointSize: min(flip.height * 0.5, 18), in: flip, color: gripColor)
    }

    private func drawLabel(_ label: KeyLabel, style: KeyStyle, in frame: CGRect, color: UIColor) {
        let fontSize = min(max(min(frame.height, frame.width * (style == .character ? 1 : 0.6)) * 0.5, 9), 24)
        switch label {
        case .text(let text):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: color,
            ]
            let size = (text as NSString).size(withAttributes: attributes)
            (text as NSString).draw(at: CGPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2),
                                    withAttributes: attributes)
        case .symbol(let symbol):
            drawSymbol(Self.symbolName(symbol), pointSize: fontSize, in: frame, color: color)
        }
    }

    private func drawSymbol(_ name: String, pointSize: CGFloat, in frame: CGRect, color: UIColor) {
        let configuration = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        guard let image = UIImage(systemName: name, withConfiguration: configuration)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        image.draw(at: CGPoint(x: frame.midX - image.size.width / 2, y: frame.midY - image.size.height / 2))
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

    private static func spokenName(_ cap: KeyCap) -> String {
        switch cap.label {
        case .text(let text): text
        case .symbol(.shift): "Shift"
        case .symbol(.shiftOnce): "Shift, on"
        case .symbol(.capsLock): "Caps lock"
        case .symbol(.backspace): "Delete"
        case .symbol(.globe): "Next keyboard"
        }
    }

    // MARK: Accessibility (derived from the same face; no second key list)

    /// One element per cap, trait `.keyboardKey`, frame from `cap.slot` in this view's space.
    /// Activation is the default (a synthesized tap at the element's centre), so VoiceOver typing
    /// goes through the same touch path as a finger. There is no second way to commit a key.
    override var accessibilityElements: [Any]? {
        get {
            if let elements { return elements }
            guard let face else { return [] }
            let built = face.caps.map { cap -> UIAccessibilityElement in
                let element = UIAccessibilityElement(accessibilityContainer: self)
                element.accessibilityLabel = Self.spokenName(cap)
                element.accessibilityTraits = .keyboardKey
                element.accessibilityFrameInContainerSpace = density.viewRect(cap.slot, containerHeight: face.size.height)
                return element
            }
            elements = built
            return built
        }
        set { }
    }

    /// Only when the set of keys or their labels change (layer switch, shift), not on every
    /// press highlight.
    private func invalidateAccessibility(from old: Face?) {
        func spoken(_ face: Face?) -> [String] { face.map { $0.caps.map(Self.spokenName) } ?? [] }
        guard spoken(face) != spoken(old) else { return }
        elements = nil
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
}

/// Colours for both appearances. Shell-only: the core never knows about colour.
private struct Palette {
    let tray: UIColor
    let characterKey: UIColor
    let modifierKey: UIColor
    let pressedKey: UIColor
    let label: UIColor

    init(_ traits: UITraitCollection) {
        if traits.userInterfaceStyle == .dark {
            tray = UIColor(white: 0.12, alpha: 0.96)
            characterKey = UIColor(white: 0.36, alpha: 1)
            modifierKey = UIColor(white: 0.24, alpha: 1)
            pressedKey = UIColor(white: 0.5, alpha: 1)
            label = .white
        } else {
            tray = UIColor(white: 0.82, alpha: 0.96)
            characterKey = .white
            modifierKey = UIColor(white: 0.68, alpha: 1)
            pressedKey = UIColor(white: 0.58, alpha: 1)
            label = .black
        }
    }
}
