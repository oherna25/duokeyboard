import UIKit
import KeyboardCore

/// Draws a `Face` in one `draw(_:)`, with no per-key views or layers. Moving the keyboard
/// changes the frame, not the face, so a drag never redraws.
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
        // The palette depends on light or dark.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FaceView, _) in view.setNeedsDisplay() }
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ rect: CGRect) {
        guard let face else { return }
        let palette = Palette(traitCollection)
        let faceHeight = face.size.height
        func viewRect<Space>(_ r: MMRect<Space>) -> CGRect { density.viewRect(r, containerHeight: faceHeight) }

        // Rounded at the top like the prototype.
        let outline = viewRect(face.tray).union(viewRect(face.handle))
        palette.tray.setFill()
        UIBezierPath(roundedRect: outline, byRoundingCorners: [.topLeft, .topRight],
                     cornerRadii: CGSize(width: 10, height: 10)).fill()

        drawHandle(face, palette: palette, handle: viewRect(face.handle), flip: viewRect(face.flipButton),
                   resize: viewRect(face.resizeGrip))

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

    private func drawHandle(_ face: Face, palette: Palette, handle: CGRect, flip: CGRect, resize: CGRect) {
        let gripColor = palette.label.withAlphaComponent(face.handleIsActive ? 0.7 : 0.35)
        // Centred on the part of the strip the buttons leave free.
        let buttons = flip.union(resize)
        let free = handle.divided(atDistance: buttons.width, from: face.hand == .right ? .minXEdge : .maxXEdge).remainder
        let grip = CGRect(x: 0, y: 0, width: density.points(8), height: density.points(1.2))
            .offsetBy(dx: free.midX - density.points(4), dy: free.midY - density.points(0.6))
        gripColor.setFill()
        UIBezierPath(roundedRect: grip, cornerRadius: grip.height / 2).fill()
        let symbolSize = min(flip.height * 0.5, 18)
        drawSymbol("arrow.left.and.line.vertical.and.arrow.right", pointSize: symbolSize, in: resize, color: gripColor)
        drawSymbol("arrow.left.arrow.right", pointSize: symbolSize, in: flip, color: gripColor)
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

    // MARK: Accessibility

    /// Activation is the default synthesized tap at the element's centre, so VoiceOver typing
    /// takes the same touch path as a finger.
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

    /// Skips press highlights, which change no label.
    private func invalidateAccessibility(from old: Face?) {
        func spoken(_ face: Face?) -> [String] { face.map { $0.caps.map(Self.spokenName) } ?? [] }
        guard spoken(face) != spoken(old) else { return }
        elements = nil
        UIAccessibility.post(notification: .layoutChanged, argument: nil)
    }
}

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
