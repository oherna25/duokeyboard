import Foundation

// MARK: - Inputs: where the user put it, and what screen we are on

public enum Hand: String, Hashable, Sendable {
    case left, right
    public var mirrored: Hand { self == .left ? .right : .left }
}

/// Where the user docked the keyboard, in physical terms relative to the thumb.
///
/// Invariant: every value is valid by construction. The only initialiser clamps `inset` and `lift`
/// to absolute bounds and replaces a non-finite component with the default's, so persisted or
/// computed garbage can never reach the engine.
///
/// This is the user's *intent*, not a screen-specific position. The absolute bounds are
/// screen-independent; `Layout` clamps further to the current surface when deriving geometry and
/// never writes that back. Moving from the 157 mm inner screen to the 77 mm outer screen and back
/// therefore does not destroy the position the user chose on either. (A drag starts from the
/// clamped, effective placement, so it never feels dead; see `KeyboardEngine`.)
public struct Placement: Hashable, Sendable {
    /// Which edge the keyboard docks against. Flipping mirrors the dock, never the key order.
    public let hand: Hand
    /// Distance from the hand-side screen margin to the tray's key area
    /// (the prototype's `pos`; the margin itself is `LayoutSpec.edgeMargin`).
    public let inset: Millimetres
    /// Height of the key area's bottom above the bottom margin, measured from the *physical
    /// screen bottom* (the prototype's `lift`). See `Surface.bottomInset`.
    public let lift: Millimetres

    /// Larger than any screen the keyboard runs on; only a sanity bound.
    static let absoluteMax: Millimetres = 200
    private static let defaultInset: Millimetres = 7
    private static let defaultLift: Millimetres = 9

    public init(hand: Hand, inset: Millimetres, lift: Millimetres) {
        func bounded(_ v: Millimetres, fallback: Millimetres) -> Millimetres {
            v.value.isFinite ? min(max(v, 0), Placement.absoluteMax) : fallback
        }
        self.hand = hand
        self.inset = bounded(inset, fallback: Placement.defaultInset)
        self.lift = bounded(lift, fallback: Placement.defaultLift)
    }

    /// "Slide to thumb" defaults from the prototype: right hand, 7 mm in, lifted 9 mm.
    /// At these values the reach model puts all 31 letter-layer keys in reach (tested).
    public static let `default` = Placement(hand: .right, inset: defaultInset, lift: defaultLift)
}

/// The surface the keyboard is drawn on. Rebuilt by the shell whenever the input view's size,
/// the screen, or its position changes (fold / unfold, rotation).
public struct Surface: Hashable, Sendable {
    /// Input view width.
    public var width: Millimetres
    /// Full screen height. Bounds how far the keyboard may be lifted.
    public var screenHeight: Millimetres
    /// Distance from the input view's bottom edge to the physical screen bottom: non-zero when
    /// the system draws its own bar (globe / dictation) below third-party keyboards. Subtracted
    /// from the lift so the keys stay where the thumb expects them physically. 0 if unknown.
    public var bottomInset: Millimetres
    public var density: PointsPerMillimetre

    public init(width: Millimetres, screenHeight: Millimetres, bottomInset: Millimetres, density: PointsPerMillimetre) {
        self.width = width; self.screenHeight = screenHeight; self.bottomInset = bottomInset; self.density = density
    }

    /// The Duo outer screen, 466 x 678 pt at 6.04 pt/mm, input view flush with the screen bottom.
    public static let duoOuter = Surface(
        width: Millimetres(466 / PointsPerMillimetre.duoOuter.value),
        screenHeight: Millimetres(678 / PointsPerMillimetre.duoOuter.value),
        bottomInset: 0,
        density: .duoOuter)
}

/// Everything about the host that affects layout. One value, so "the environment changed" is a
/// single engine input and a single equality check.
public struct Environment: Hashable, Sendable {
    public var surface: Surface
    /// `UIInputViewController.needsInputModeSwitchKey`.
    public var showsGlobeKey: Bool

    public init(surface: Surface, showsGlobeKey: Bool) {
        self.surface = surface; self.showsGlobeKey = showsGlobeKey
    }
}

/// Reference geometry, transcribed from `gridLayout` and the "compact" variant in
/// prototype/index.html. Every constant has exactly one home: here.
enum LayoutSpec {
    /// Key-area width ("cw"). Fixed in v1; only position is user-adjustable.
    static let trayWidth: Millimetres = 59
    /// unit = width / 10; rowH = min(unit * 1.38, 11.5); gx = max(0.8, unit * 0.12); gy = max(1, rowH * 0.16)
    static let unitsPerRow: Double = 10
    static let rowHeightPerUnit: Double = 1.38
    static let maxRowHeight: Millimetres = 11.5
    static let minGapX: Millimetres = 0.8
    static let gapXPerUnit: Double = 0.12
    static let minGapY: Millimetres = 1
    static let gapYPerRow: Double = 0.16
    /// Prototype: x0 = W - 2 - cw - pos (right hand); bottom = H - 4 - lift; box = keys + 1.5 on every side.
    static let edgeMargin: Millimetres = 2
    static let bottomMargin: Millimetres = 4
    static let trayPadding: Millimetres = 1.5
    /// The drag-handle strip above the tray. ~36 pt.
    static let handleHeight: Millimetres = 6
    /// Flip button at the handle's far end (away from the thumb, so a flip is deliberate).
    static let flipButtonWidth: Millimetres = 9
    /// How far outside the face a touch still snaps to the nearest key (sides and below).
    static let hitSlop: Millimetres = 3
    /// The face top may rise to at most this fraction of the screen height.
    static let maxFaceTopFraction: Double = 0.6
    /// Drag moves lift in steps so the input view's height (and the host app's layout) changes
    /// at most once per step, not once per touch event.
    static let liftStep: Millimetres = 0.5

    // Derived from the constants above, which are fixed in v1.
    static let unit = trayWidth / unitsPerRow
    static let rowHeight = min(unit * rowHeightPerUnit, maxRowHeight)
    static let gapX = max(minGapX, unit * gapXPerUnit)
    static let gapY = max(minGapY, rowHeight * gapYPerRow)
    /// Every layer has the same row count (tested), so the face height is layer-independent.
    static let faceHeight = rowHeight * Double(Keymap.rows(for: .letters, showsGlobeKey: false).count)
        + trayPadding * 2 + handleHeight
}

extension Placement {
    /// The effective placement on `environment`: inset in [0, surface width - margins - tray],
    /// lift in [0, max allowed by `maxFaceTopFraction`]. Pure; idempotent (clamping twice is a no-op).
    func clamped(to environment: Environment) -> Placement {
        let surface = environment.surface
        let maxInset = max(0, surface.width - LayoutSpec.edgeMargin * 2 - LayoutSpec.trayWidth)
        // faceTop = bottomMargin + lift - bottomInset - trayPadding + faceHeight <= fraction * screenHeight
        let maxLift = max(0, surface.screenHeight * LayoutSpec.maxFaceTopFraction - LayoutSpec.faceHeight
            - LayoutSpec.bottomMargin + LayoutSpec.trayPadding + surface.bottomInset)
        return Placement(hand: hand, inset: min(inset, maxInset), lift: min(lift, maxLift))
    }
}

// MARK: - Output: one derived value, two consumers (drawing and hit-testing)

/// Everything the shell needs to draw and size the keyboard, derived from engine state.
///
/// Invariant: a `Layout` is a pure function of (effective placement, environment, layer, shift,
/// pressed target). It is never mutated or cached by anyone, so it can never be stale.
/// Computing one is ~31 rect calculations; the engine derives it on demand.
public struct Layout: Equatable, Sendable {
    /// Height for the input view's height constraint: face top in keyboard space.
    public let height: Millimetres
    /// Where the face sits, in keyboard space. Changes during a drag; `face` does not.
    public let faceFrame: MMRect<KeyboardSpace>
    /// The translation-invariant contents. The shell redraws only when this changes.
    public let face: Face
    /// The clamped placement that produced this layout (drag starts from it).
    public let placement: Placement

    /// Built only by the engine; callers get layouts from `KeyboardEngine.layout`.
    init(placement: Placement, environment: Environment, layer: Layer, shift: ShiftState,
         pressed: HitTarget?) {
        let p = placement.clamped(to: environment)
        let rows = Keymap.rows(for: layer, showsGlobeKey: environment.showsGlobeKey)
        let face = Face(rows: rows, layer: layer, shift: shift, hand: p.hand, pressed: pressed)
        let pad = LayoutSpec.trayPadding
        let surface = environment.surface
        let keyAreaLeft = p.hand == .right
            ? surface.width - LayoutSpec.edgeMargin - LayoutSpec.trayWidth - p.inset
            : LayoutSpec.edgeMargin + p.inset
        let keyAreaBottom = LayoutSpec.bottomMargin + p.lift - surface.bottomInset
        self.placement = p
        self.face = face
        self.faceFrame = MMRect(origin: MMPoint(x: keyAreaLeft - pad, y: max(0, keyAreaBottom - pad)),
                                size: face.size)
        self.height = faceFrame.maxY
    }

    /// Nearest-target hit-testing for a touch in keyboard space. See `Face.hitTest`.
    public func hitTest(_ point: KeyboardPoint) -> HitTarget {
        face.hitTest(FacePoint(x: point.x - faceFrame.origin.x, y: point.y - faceFrame.origin.y))
    }

    /// A key's hit slot in keyboard space, or nil when the key is not on this layer.
    /// Used by the shell to place the globe control over exactly the region that would
    /// otherwise hit the globe key, and by tests to synthesize touches.
    public func slot(of key: KeyID) -> MMRect<KeyboardSpace>? {
        guard let cap = face.caps.first(where: { $0.id == key }) else { return nil }
        return MMRect(origin: MMPoint(x: cap.slot.minX + faceFrame.origin.x, y: cap.slot.minY + faceFrame.origin.y),
                      size: cap.slot.size)
    }
}

/// The drawable contents of the keyboard, in face space.
public struct Face: Equatable, Sendable {
    public let size: MMSize
    /// The rounded tray behind the keys.
    public let tray: MMRect<FaceSpace>
    /// The drag strip above the tray, including the flip button.
    public let handle: MMRect<FaceSpace>
    public let flipButton: MMRect<FaceSpace>
    public let hand: Hand
    /// True while the handle or flip button is held (drawn highlighted).
    public let handleIsActive: Bool
    /// Rows top to bottom.
    ///
    /// Data-structure choice: hit-testing is the dominant access pattern (every touch event),
    /// and it is row-major. All rows share `rowHeight` and start at `keysBottom`, so the row
    /// index is one division; the key within a row is a scan of at most 10 sorted slots.
    public let rows: [FaceRow]
    public let keysBottom: Millimetres
    public let rowHeight: Millimetres

    /// Every key cap, top-left to bottom-right (drawing and accessibility order).
    public var caps: some Sequence<KeyCap> { rows.lazy.flatMap(\.caps) }

    /// Nearest-target hit-testing in face space.
    ///
    /// - In the handle strip: `.flipButton` if inside it, else `.handle`.
    /// - Otherwise the row is chosen by y (clamped to the top / bottom row), then the key by x
    ///   within that row (a slot containing x, else the first or last key). Slots tile each row
    ///   edge to edge, so a tap in the gap between two caps hits the nearer one, and a tap in a
    ///   short row's side margin (left of "a") hits the end key.
    /// - Beyond `LayoutSpec.hitSlop` outside the face's sides or below it: `.none`.
    ///
    /// Total for every point; never traps.
    public func hitTest(_ point: FacePoint) -> HitTarget {
        let slop = LayoutSpec.hitSlop
        // Negated comparisons so a NaN falls through to .none.
        guard point.x >= .zero - slop, point.x < size.width + slop, point.y >= .zero - slop else { return .none }
        if point.y >= handle.minY {
            return point.x >= flipButton.minX && point.x < flipButton.maxX ? .flipButton : .handle
        }
        let keysTop = keysBottom + rowHeight * Double(rows.count)
        let row = min(max(Int(((keysTop - point.y) / rowHeight).rounded(.down)), 0), rows.count - 1)
        let caps = rows[row].caps
        return .key((caps.first { point.x < $0.slot.maxX } ?? caps[caps.count - 1]).id)
    }

    init(rows specs: [[KeySpec]], layer: Layer, shift: ShiftState, hand: Hand, pressed: HitTarget?) {
        let pad = LayoutSpec.trayPadding
        let unit = LayoutSpec.unit, rowHeight = LayoutSpec.rowHeight
        let halfGapX = LayoutSpec.gapX * 0.5, halfGapY = LayoutSpec.gapY * 0.5
        let count = Double(specs.count)

        let tray = MMRect<FaceSpace>(
            origin: MMPoint(x: 0, y: 0),
            size: MMSize(width: LayoutSpec.trayWidth + pad * 2, height: rowHeight * count + pad * 2))
        let handle = MMRect<FaceSpace>(
            origin: MMPoint(x: 0, y: tray.maxY),
            size: MMSize(width: tray.size.width, height: LayoutSpec.handleHeight))
        let flipX = hand == .right ? Millimetres.zero : tray.size.width - LayoutSpec.flipButtonWidth
        let flipButton = MMRect<FaceSpace>(
            origin: MMPoint(x: flipX, y: handle.minY),
            size: MMSize(width: LayoutSpec.flipButtonWidth, height: handle.size.height))

        self.rows = specs.enumerated().map { index, spec in
            let total = spec.reduce(0) { $0 + $1.width }
            var x = pad + (LayoutSpec.trayWidth - unit * total) * 0.5
            let y = pad + rowHeight * (count - 1 - Double(index))
            return FaceRow(caps: spec.map { key in
                let width = unit * key.width
                let slot = MMRect<FaceSpace>(origin: MMPoint(x: x, y: y), size: MMSize(width: width, height: rowHeight))
                x = x + width
                let (label, style) = Face.appearance(of: key.id, layer: layer, shift: shift)
                return KeyCap(id: key.id, slot: slot, frame: slot.insetBy(dx: halfGapX, dy: halfGapY),
                              label: label, style: style, isPressed: pressed == .key(key.id))
            })
        }
        self.size = MMSize(width: tray.size.width, height: handle.maxY)
        self.tray = tray
        self.handle = handle
        self.flipButton = flipButton
        self.hand = hand
        self.handleIsActive = pressed == .handle || pressed == .flipButton
        self.keysBottom = pad
        self.rowHeight = rowHeight
    }

    private static func appearance(of key: KeyID, layer: Layer, shift: ShiftState) -> (KeyLabel, KeyStyle) {
        switch key {
        case .character(let c):
            let shifted = layer == .letters && shift != .off
            return (.text(shifted ? String(c).uppercased() : String(c)), .character)
        case .space: return (.text("space"), .character)
        case .return: return (.text("return"), .modifier)
        case .backspace: return (.symbol(.backspace), .modifier)
        case .globe: return (.symbol(.globe), .modifier)
        case .layerToggle: return (.text(layer == .letters ? "123" : "ABC"), .modifier)
        case .shift:
            switch shift {
            case .off: return (.symbol(.shift), .modifier)
            case .once: return (.symbol(.shiftOnce), .modifierActive)
            case .locked: return (.symbol(.capsLock), .modifierActive)
            }
        }
    }
}

public struct FaceRow: Equatable, Sendable {
    /// Caps left to right; slots tile [first.slot.minX, last.slot.maxX) without gaps or overlap.
    public let caps: [KeyCap]
}

public struct KeyCap: Equatable, Sendable {
    public let id: KeyID
    /// Hit region: the cap plus half the gap on each side.
    public let slot: MMRect<FaceSpace>
    /// Drawn region: the slot inset by half the gaps.
    public let frame: MMRect<FaceSpace>
    public let label: KeyLabel
    public let style: KeyStyle
    public let isPressed: Bool
}

/// What to draw on a cap. Semantic, not UIKit: the shell maps symbols to SF Symbols, so no
/// framework names leak into the core.
public enum KeyLabel: Equatable, Sendable {
    case text(String)
    case symbol(KeySymbol)
}

public enum KeySymbol: Equatable, Sendable {
    case shift, shiftOnce, capsLock, backspace, globe
}

public enum KeyStyle: Equatable, Sendable {
    /// Characters and space.
    case character
    /// Shift (off), backspace, layer toggle, globe, return.
    case modifier
    /// Shift while `.once` or `.locked`.
    case modifierActive
}

public enum HitTarget: Hashable, Sendable {
    case key(KeyID)
    case handle
    case flipButton
    case none
}
