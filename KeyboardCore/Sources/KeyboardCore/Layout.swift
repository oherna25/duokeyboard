import Foundation

// MARK: - Inputs

public enum Hand: String, Hashable, Sendable {
    case left, right
    public var mirrored: Hand { self == .left ? .right : .left }
}

/// Where the user docked the keyboard, in physical terms relative to the thumb.
///
/// Every value is valid by construction. The initialiser clamps `inset` and `lift` to absolute
/// bounds and replaces a non-finite component with the default's.
///
/// This is the user's intent, not a screen-specific position. `Layout` clamps further to the
/// current surface and never writes that back, so moving from the 157 mm inner screen to the
/// 77 mm outer screen and back keeps the position chosen on each.
public struct Placement: Hashable, Sendable {
    /// Flipping mirrors the dock, never the key order.
    public let hand: Hand
    /// Distance from the hand-side screen margin to the tray's key area (the prototype's `pos`).
    public let inset: Millimetres
    /// Height of the key area's bottom above the bottom margin, measured from the physical
    /// screen bottom (the prototype's `lift`). See `Surface.bottomInset`.
    public let lift: Millimetres
    /// Key-area width. Keys scale with it, so a narrower tray trades key size for reach.
    public let width: Millimetres

    /// Larger than any screen the keyboard runs on.
    static let absoluteMax: Millimetres = 200
    /// On a real Duo the prototype's 59 mm tray left q, shift and 123 a stretch even docked
    /// flush, which the user chose over the prototype's 7 mm inset. 50 mm gives 5 mm keys, the
    /// original iPhone SE's pitch, and brings those keys 9 mm closer to the thumb.
    private static let defaultInset: Millimetres = 0
    private static let defaultLift: Millimetres = 9
    private static let defaultWidth: Millimetres = 50
    static let minWidth: Millimetres = 44
    static let maxWidth: Millimetres = 75

    public init(hand: Hand, inset: Millimetres, lift: Millimetres, width: Millimetres) {
        func bounded(_ v: Millimetres, fallback: Millimetres) -> Millimetres {
            v.value.isFinite ? min(max(v, 0), Placement.absoluteMax) : fallback
        }
        self.hand = hand
        self.inset = bounded(inset, fallback: Placement.defaultInset)
        self.lift = bounded(lift, fallback: Placement.defaultLift)
        self.width = width.value.isFinite
            ? min(max(width, Placement.minWidth), Placement.maxWidth) : Placement.defaultWidth
    }

    /// A copy with the given fields replaced.
    public func with(inset: Millimetres? = nil, lift: Millimetres? = nil, width: Millimetres? = nil,
                     hand: Hand? = nil) -> Placement {
        Placement(hand: hand ?? self.hand, inset: inset ?? self.inset, lift: lift ?? self.lift,
                  width: width ?? self.width)
    }

    /// At these the calibrated reach model puts all 31 letter-layer keys in reach (tested).
    public static let `default` = Placement(hand: .right, inset: defaultInset, lift: defaultLift,
                                            width: defaultWidth)
}

/// The surface the keyboard is drawn on.
public struct Surface: Hashable, Sendable {
    public var width: Millimetres
    /// Full screen height. Bounds how far the keyboard may be lifted.
    public var screenHeight: Millimetres
    /// What the host actually granted, which may differ from the height `Layout` requests.
    /// Drawn geometry is fitted to it, but the request never depends on it.
    public var grantedHeight: Millimetres
    /// Distance from the input view's bottom edge to the physical screen bottom, non-zero when
    /// the system draws its own bar below third-party keyboards. Subtracted from the lift so
    /// the keys stay where the thumb expects them. 0 if unknown.
    public var bottomInset: Millimetres
    public var density: PointsPerMillimetre

    /// `grantedHeight` defaults to the full screen height, which never constrains.
    public init(width: Millimetres, screenHeight: Millimetres, grantedHeight: Millimetres? = nil,
                bottomInset: Millimetres, density: PointsPerMillimetre) {
        self.width = width; self.screenHeight = screenHeight; self.grantedHeight = grantedHeight ?? screenHeight
        self.bottomInset = bottomInset; self.density = density
    }

    /// The Duo outer screen, 466 x 678 pt at 6.04 pt/mm, input view flush with the screen bottom.
    public static let duoOuter = Surface(
        width: Millimetres(466 / PointsPerMillimetre.duoOuter.value),
        screenHeight: Millimetres(678 / PointsPerMillimetre.duoOuter.value),
        bottomInset: 0,
        density: .duoOuter)
}

/// Everything about the host that affects layout.
public struct Environment: Hashable, Sendable {
    public var surface: Surface
    /// `UIInputViewController.needsInputModeSwitchKey`.
    public var showsGlobeKey: Bool

    public init(surface: Surface, showsGlobeKey: Bool) {
        self.surface = surface; self.showsGlobeKey = showsGlobeKey
    }
}

/// Reference geometry, transcribed from `gridLayout` and the "compact" variant in
/// prototype/index.html.
enum LayoutSpec {
    /// unit = width / 10; rowH = min(unit * 1.38, 11.5); gx = max(0.8, unit * 0.12); gy = max(1, rowH * 0.16)
    static let unitsPerRow: Double = 10
    static let rowHeightPerUnit: Double = 1.38
    static let maxRowHeight: Millimetres = 11.5
    /// Rows shrink to fit a small grant, but never below a tappable size.
    static let minRowHeight: Millimetres = 5
    static let minGapX: Millimetres = 0.8
    static let gapXPerUnit: Double = 0.12
    static let minGapY: Millimetres = 1
    static let gapYPerRow: Double = 0.16
    /// From the prototype. x0 = W - 2 - cw - pos (right hand); bottom = H - 4 - lift; box = keys + 1.5 on every side.
    static let edgeMargin: Millimetres = 2
    static let bottomMargin: Millimetres = 4
    static let trayPadding: Millimetres = 1.5
    static let handleHeight: Millimetres = 6
    /// The resize grip sits at the handle's far end with the flip button beside it, both away
    /// from the thumb so neither is hit by accident.
    static let flipButtonWidth: Millimetres = 9
    static let resizeGripWidth: Millimetres = 9
    /// How far outside the face a touch still snaps to the nearest key (sides and below).
    static let hitSlop: Millimetres = 3
    /// The face top may rise to at most this fraction of the screen height.
    static let maxFaceTopFraction: Double = 0.6
    /// Lift moves in steps so the host app's layout changes at most once per step, not once
    /// per touch event.
    static let liftStep: Millimetres = 0.5
    static let widthStep: Millimetres = 0.5

    static func unit(width: Millimetres) -> Millimetres { width / unitsPerRow }
    static func rowHeight(width: Millimetres) -> Millimetres { min(unit(width: width) * rowHeightPerUnit, maxRowHeight) }
    static func gapX(width: Millimetres) -> Millimetres { max(minGapX, unit(width: width) * gapXPerUnit) }
    static func gapY(rowHeight: Millimetres) -> Millimetres { max(minGapY, rowHeight * gapYPerRow) }
    /// Every layer has the same row count (tested).
    static func faceHeight(width: Millimetres) -> Millimetres {
        rowHeight(width: width) * Double(Keymap.rows(for: .letters, showsGlobeKey: false).count)
            + trayPadding * 2 + handleHeight
    }
}

extension Placement {
    /// Idempotent. Width first, since the inset and lift bounds depend on it. Lift is limited
    /// by `maxFaceTopFraction`.
    func clamped(to environment: Environment) -> Placement {
        let surface = environment.surface
        let width = max(min(self.width, surface.width - LayoutSpec.edgeMargin * 2), Placement.minWidth)
        let maxInset = max(0, surface.width - LayoutSpec.edgeMargin * 2 - width)
        // faceTop = bottomMargin + lift - bottomInset - trayPadding + faceHeight <= fraction * screenHeight
        let maxLift = max(0, surface.screenHeight * LayoutSpec.maxFaceTopFraction - LayoutSpec.faceHeight(width: width)
            - LayoutSpec.bottomMargin + LayoutSpec.trayPadding + surface.bottomInset)
        return Placement(hand: hand, inset: min(inset, maxInset), lift: min(lift, maxLift), width: width)
    }
}

// MARK: - Output

/// Everything the shell needs to draw and size the keyboard. A pure function of its inputs,
/// derived on demand by the engine and never cached.
public struct Layout: Equatable, Sendable {
    /// The face top in keyboard space at full size. Independent of `Surface.grantedHeight`,
    /// since a host that ignores the request would otherwise pin it at the grant for good.
    public let height: Millimetres
    public let faceFrame: MMRect<KeyboardSpace>
    /// Translation-invariant, so a drag changes `faceFrame` but not this.
    public let face: Face
    /// The placement as drawn, clamped to the surface and fitted to the granted height. A drag
    /// starts from it so it never feels dead.
    public let placement: Placement

    init(placement: Placement, environment: Environment, layer: Layer, shift: ShiftState,
         pressed: HitTarget?) {
        let p = placement.clamped(to: environment)
        let rows = Keymap.rows(for: layer, showsGlobeKey: environment.showsGlobeKey)
        let pad = LayoutSpec.trayPadding
        let surface = environment.surface
        let count = Double(rows.count)
        let fullRowHeight = LayoutSpec.rowHeight(width: p.width)
        let fullFaceHeight = fullRowHeight * count + pad * 2 + LayoutSpec.handleHeight
        let rowHeight = fullFaceHeight <= surface.grantedHeight ? fullRowHeight
            : min(max((surface.grantedHeight - LayoutSpec.handleHeight - pad * 2) / count, LayoutSpec.minRowHeight),
                  fullRowHeight)
        let face = Face(rows: rows, layer: layer, shift: shift, hand: p.hand, pressed: pressed,
                        width: p.width, rowHeight: rowHeight)
        let keyAreaLeft = p.hand == .right
            ? surface.width - LayoutSpec.edgeMargin - p.width - p.inset
            : LayoutSpec.edgeMargin + p.inset
        let keyAreaBottom = LayoutSpec.bottomMargin + p.lift - surface.bottomInset
        let wantedBottom = max(0, keyAreaBottom - pad)
        let faceBottom = min(wantedBottom, max(0, surface.grantedHeight - face.size.height))
        self.placement = p.with(lift: p.lift - (wantedBottom - faceBottom))
        self.face = face
        self.faceFrame = MMRect(origin: MMPoint(x: keyAreaLeft - pad, y: faceBottom), size: face.size)
        self.height = wantedBottom + fullFaceHeight
    }

    public func hitTest(_ point: KeyboardPoint) -> HitTarget {
        face.hitTest(FacePoint(x: point.x - faceFrame.origin.x, y: point.y - faceFrame.origin.y))
    }

    /// Nil when the key is not on this layer.
    public func slot(of key: KeyID) -> MMRect<KeyboardSpace>? {
        guard let cap = face.caps.first(where: { $0.id == key }) else { return nil }
        return MMRect(origin: MMPoint(x: cap.slot.minX + faceFrame.origin.x, y: cap.slot.minY + faceFrame.origin.y),
                      size: cap.slot.size)
    }
}

/// The drawable contents of the keyboard, in face space.
public struct Face: Equatable, Sendable {
    public let size: MMSize
    public let tray: MMRect<FaceSpace>
    public let handle: MMRect<FaceSpace>
    public let flipButton: MMRect<FaceSpace>
    public let resizeGrip: MMRect<FaceSpace>
    public let hand: Hand
    public let handleIsActive: Bool
    /// Rows top to bottom. All rows share `rowHeight` and start at `keysBottom`, so hit-testing
    /// finds the row with one division.
    public let rows: [FaceRow]
    public let keysBottom: Millimetres
    public let rowHeight: Millimetres

    public var caps: some Sequence<KeyCap> { rows.lazy.flatMap(\.caps) }

    /// Nearest-target hit-testing. Slots tile each row edge to edge, so a tap in the gap
    /// between caps hits the nearer one and a tap in a short row's side margin hits the end
    /// key. Beyond `LayoutSpec.hitSlop` past the sides or bottom it is `.none`.
    ///
    /// Total for every point, including NaN.
    public func hitTest(_ point: FacePoint) -> HitTarget {
        let slop = LayoutSpec.hitSlop
        // Written positively so a NaN fails the guard and falls through to .none.
        guard point.x >= .zero - slop, point.x < size.width + slop, point.y >= .zero - slop else { return .none }
        if point.y >= handle.minY {
            if point.x >= resizeGrip.minX && point.x < resizeGrip.maxX { return .resizeGrip }
            return point.x >= flipButton.minX && point.x < flipButton.maxX ? .flipButton : .handle
        }
        let keysTop = keysBottom + rowHeight * Double(rows.count)
        let row = min(max(Int(((keysTop - point.y) / rowHeight).rounded(.down)), 0), rows.count - 1)
        let caps = rows[row].caps
        return .key((caps.first { point.x < $0.slot.maxX } ?? caps[caps.count - 1]).id)
    }

    init(rows specs: [[KeySpec]], layer: Layer, shift: ShiftState, hand: Hand, pressed: HitTarget?,
         width: Millimetres, rowHeight: Millimetres) {
        let pad = LayoutSpec.trayPadding
        let unit = LayoutSpec.unit(width: width)
        let halfGapX = LayoutSpec.gapX(width: width) * 0.5
        let halfGapY = LayoutSpec.gapY(rowHeight: rowHeight) * 0.5
        let count = Double(specs.count)

        let tray = MMRect<FaceSpace>(
            origin: MMPoint(x: 0, y: 0),
            size: MMSize(width: width + pad * 2, height: rowHeight * count + pad * 2))
        let handle = MMRect<FaceSpace>(
            origin: MMPoint(x: 0, y: tray.maxY),
            size: MMSize(width: tray.size.width, height: LayoutSpec.handleHeight))
        let gripX = hand == .right ? Millimetres.zero : tray.size.width - LayoutSpec.resizeGripWidth
        let resizeGrip = MMRect<FaceSpace>(
            origin: MMPoint(x: gripX, y: handle.minY),
            size: MMSize(width: LayoutSpec.resizeGripWidth, height: handle.size.height))
        let flipX = hand == .right ? resizeGrip.maxX : resizeGrip.minX - LayoutSpec.flipButtonWidth
        let flipButton = MMRect<FaceSpace>(
            origin: MMPoint(x: flipX, y: handle.minY),
            size: MMSize(width: LayoutSpec.flipButtonWidth, height: handle.size.height))

        self.rows = specs.enumerated().map { index, spec in
            let total = spec.reduce(0) { $0 + $1.width }
            var x = pad + (width - unit * total) * 0.5
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
        self.resizeGrip = resizeGrip
        self.hand = hand
        self.handleIsActive = pressed == .handle || pressed == .flipButton || pressed == .resizeGrip
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
    /// Slots tile [first.slot.minX, last.slot.maxX) without gaps or overlap.
    public let caps: [KeyCap]
}

public struct KeyCap: Equatable, Sendable {
    public let id: KeyID
    /// Hit region, the cap plus half the gap on each side.
    public let slot: MMRect<FaceSpace>
    public let frame: MMRect<FaceSpace>
    public let label: KeyLabel
    public let style: KeyStyle
    public let isPressed: Bool
}

/// Semantic rather than UIKit, so no framework names leak into the core.
public enum KeyLabel: Equatable, Sendable {
    case text(String)
    case symbol(KeySymbol)
}

public enum KeySymbol: Equatable, Sendable {
    case shift, shiftOnce, capsLock, backspace, globe
}

public enum KeyStyle: Equatable, Sendable {
    case character
    case modifier
    case modifierActive
}

public enum HitTarget: Hashable, Sendable {
    case key(KeyID)
    case handle
    case flipButton
    case resizeGrip
    case none
}
