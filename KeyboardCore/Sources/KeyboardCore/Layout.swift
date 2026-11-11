import Foundation

// MARK: - Inputs: where the user put it, and what screen we are on

public enum Hand: String, Hashable, Sendable {
    case left, right
    public var mirrored: Hand { self == .left ? .right : .left }
}

/// Where the user docked the keyboard, in physical terms relative to the thumb.
///
/// Invariant: every value is valid by construction (the initialiser clamps to absolute bounds
/// and replaces non-finite components with the default's).
///
/// This is the user's *intent*, not a screen-specific position. Absolute bounds are
/// screen-independent; `Layout` clamps further to the current surface when deriving geometry, so moving from
/// the 157 mm inner screen to the 77 mm outer screen and back does not destroy the position the
/// user chose on either. (A drag starts from the clamped, effective placement, so it never
/// feels dead; see `KeyboardEngine`.)
public struct Placement: Hashable, Sendable {
    /// Which edge the keyboard docks against. Flipping mirrors the dock, never the key order.
    public let hand: Hand
    /// Distance from the hand-side screen margin to the tray's key area
    /// (the prototype's `pos`; the margin itself is `LayoutSpec.edgeMargin`).
    public let inset: Millimetres
    /// Height of the key area's bottom above the bottom margin, measured from the *physical
    /// screen bottom* (the prototype's `lift`). See `Surface.bottomInset`.
    public let lift: Millimetres

    /// Clamps `inset` and `lift` to [0, 200 mm]; a non-finite component takes the default's value.
    public init(hand: Hand, inset: Millimetres, lift: Millimetres) {
        fatalError("not implemented")
    }

    /// "Slide to thumb" defaults from the prototype: right hand, 7 mm in, lifted 9 mm.
    /// At these values the reach model puts all 31 letter-layer keys in reach (tested).
    public static var `default`: Placement { Placement(hand: .right, inset: 7, lift: 9) }
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
}

extension Placement {
    /// The effective placement on `environment`: inset in [0, surface width - margins - tray],
    /// lift in [0, max allowed by `maxFaceTopFraction`]. Pure; idempotent (clamping twice is a no-op).
    func clamped(to environment: Environment) -> Placement { fatalError("not implemented") }
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
        // TODO, in order:
        // 1. let p = placement.clamped(to: environment)
        // 2. unit, rowH, gx, gy from LayoutSpec (see formulas there)
        // 3. rows = Keymap.rows(for: layer, showsGlobeKey: environment.showsGlobeKey)
        // 4. face (face space, y-up, origin = tray box bottom-left):
        //      key area x in [pad, pad + trayWidth], y in [pad, pad + rows.count * rowH]
        //      row i (0 = top) occupies band y = pad + (rows.count - 1 - i) * rowH ..< + rowH
        //      each row centred: x starts at pad + (trayWidth - total * unit) / 2
        //      slot = (x, band, width * unit, rowH); frame = slot.insetBy(gx / 2, gy / 2)
        //      tray = (0, 0, trayWidth + 2 pad, rows.count * rowH + 2 pad)
        //      handle = (0, tray.maxY, tray.width, handleHeight)
        //      flipButton = handle's far end: left end for .right hand, right end for .left
        // 5. faceFrame.origin (keyboard space):
        //      key-area x0 = hand == .right ? width - edgeMargin - trayWidth - inset : edgeMargin + inset
        //      key-area bottom = bottomMargin + lift - surface.bottomInset
        //      origin = (x0 - pad, max(0, bottom - pad))
        // 6. height = faceFrame.maxY
        fatalError("not implemented")
    }

    /// Nearest-target hit-testing for a touch in keyboard space. See `Face.hitTest`.
    public func hitTest(_ point: KeyboardPoint) -> HitTarget { fatalError("not implemented") }

    /// A key's hit slot in keyboard space, or nil when the key is not on this layer.
    /// Used by the shell to place the globe control over exactly the region that would
    /// otherwise hit the globe key, and by tests to synthesize touches.
    public func slot(of key: KeyID) -> MMRect<KeyboardSpace>? { fatalError("not implemented") }
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
    public func hitTest(_ point: FacePoint) -> HitTarget { fatalError("not implemented") }
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
