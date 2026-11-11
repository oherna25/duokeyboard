import CoreGraphics
import Foundation

// MARK: - Length

/// A physical length. The core's only length unit.
///
/// Invariant: physical size is what must stay constant across screens (a thumb is the same
/// size on the inner and outer screen), so every geometric quantity in the core is specified
/// and computed in millimetres. Points exist only at the UIKit boundary, and the only way to
/// cross it is `PointsPerMillimetre`. A `CGFloat` cannot be passed where a length is expected,
/// so "forgot to convert" is a compile error, not a layout bug.
public struct Millimetres: Hashable, Comparable, Sendable, AdditiveArithmetic,
    ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral
{
    public var value: Double

    public init(_ value: Double) { self.value = value }
    public init(floatLiteral value: Double) { self.value = value }
    public init(integerLiteral value: Int) { self.value = Double(value) }

    public static let zero: Millimetres = 0
    public static func + (a: Self, b: Self) -> Self { Self(a.value + b.value) }
    public static func - (a: Self, b: Self) -> Self { Self(a.value - b.value) }
    public static func * (a: Self, k: Double) -> Self { Self(a.value * k) }
    public static func / (a: Self, k: Double) -> Self { Self(a.value / k) }
    /// Ratio of two lengths (dimensionless).
    public static func / (a: Self, b: Self) -> Double { a.value / b.value }
    public static func < (a: Self, b: Self) -> Bool { a.value < b.value }
}

// MARK: - Coordinate spaces

/// Keyboard space: origin at the bottom-left corner of the input view, x rightward, **y upward**.
///
/// Why y-up: the input view is anchored at its bottom edge. When the user lifts the keyboard
/// its height constraint grows and its top edge moves, but every point measured from the
/// bottom stays put. A drag in progress therefore never "jumps" when the view resizes under
/// the finger. This is the space touches arrive in and the space placement is expressed in.
public enum KeyboardSpace {}

/// Face space: origin at the bottom-left corner of the face (tray plus drag-handle strip),
/// y upward.
///
/// Why a second space: the face's contents are translation-invariant. Moving the keyboard
/// changes only `Layout.faceFrame.origin`, never the `Face` value, so the shell can move the
/// face view without redrawing it on every drag frame.
public enum FaceSpace {}

/// A point in a named space. The phantom `Space` makes it a compile error to hit-test a
/// keyboard-space touch against face-space rects without converting.
public struct MMPoint<Space>: Hashable, Sendable {
    public var x: Millimetres
    public var y: Millimetres
    public init(x: Millimetres, y: Millimetres) { self.x = x; self.y = y }

    public func distance(to other: Self) -> Millimetres {
        Millimetres(hypot((x - other.x).value, (y - other.y).value))
    }
}

public struct MMSize: Hashable, Sendable {
    public var width: Millimetres
    public var height: Millimetres
    public init(width: Millimetres, height: Millimetres) { self.width = width; self.height = height }
}

/// An axis-aligned rect in a named space. `origin` is the bottom-left corner (both spaces are y-up).
public struct MMRect<Space>: Hashable, Sendable {
    public var origin: MMPoint<Space>
    public var size: MMSize
    public init(origin: MMPoint<Space>, size: MMSize) { self.origin = origin; self.size = size }

    public var minX: Millimetres { origin.x }
    public var minY: Millimetres { origin.y }
    public var maxX: Millimetres { origin.x + size.width }
    public var maxY: Millimetres { origin.y + size.height }
    public var center: MMPoint<Space> {
        MMPoint(x: origin.x + size.width * 0.5, y: origin.y + size.height * 0.5)
    }

    /// Half-open on the max edges so adjacent slots never both contain a boundary point.
    public func contains(_ p: MMPoint<Space>) -> Bool {
        p.x >= minX && p.x < maxX && p.y >= minY && p.y < maxY
    }

    public func insetBy(dx: Millimetres, dy: Millimetres) -> Self {
        Self(origin: MMPoint(x: origin.x + dx, y: origin.y + dy),
             size: MMSize(width: size.width - dx * 2, height: size.height - dy * 2))
    }
}

public typealias KeyboardPoint = MMPoint<KeyboardSpace>
public typealias FacePoint = MMPoint<FaceSpace>

// MARK: - The one boundary: points <-> millimetres

/// Display density, and the only conversion between UIKit points and core millimetres.
///
/// Invariant: `value` is finite and > 0 (checked once, in `init?`).
/// Both directions of the y-flip (UIKit is y-down, the core is y-up) live here and nowhere
/// else, so the shell never does coordinate arithmetic of its own.
public struct PointsPerMillimetre: Hashable, Sendable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite, value > 0 else { return nil }
        self.value = value
    }

    /// iPhone Duo outer screen: 1398 x 2034 px at 460 ppi, @3x -> 460 / 25.4 / 3 = 6.04 pt/mm.
    public static let duoOuter = PointsPerMillimetre(unchecked: 460.0 / 25.4 / 3.0)

    private init(unchecked value: Double) { self.value = value }

    /// Resolves density from the screen's native pixel size and scale.
    ///
    /// iOS does not expose physical ppi, so this is a small table of known panels keyed by
    /// native pixel size (the Duo outer panel, and the inner panel once its ppi is known),
    /// with a fallback by scale (@3x -> 460 ppi, @2x -> 326 ppi), which is right for every
    /// current iPhone panel to within a few percent.
    public static func resolve(nativePixelSize: CGSize, scale: CGFloat) -> PointsPerMillimetre {
        let long = max(nativePixelSize.width, nativePixelSize.height)
        let short = min(nativePixelSize.width, nativePixelSize.height)
        if long == 2034, short == 1398 { return .duoOuter }
        let ppi: Double = scale >= 3 ? 460 : scale >= 2 ? 326 : 163
        return PointsPerMillimetre(unchecked: ppi / 25.4 / Double(scale >= 1 ? scale : 1))
    }

    public func points(_ length: Millimetres) -> CGFloat { CGFloat(length.value * value) }
    public func millimetres(_ points: CGFloat) -> Millimetres { Millimetres(Double(points) / value) }

    /// UIKit view location (y-down, points) -> keyboard space (y-up, mm).
    /// `viewHeight` is the input view's *current* bounds height, read at the moment of the touch.
    public func keyboardPoint(fromView location: CGPoint, viewHeight: CGFloat) -> KeyboardPoint {
        KeyboardPoint(x: millimetres(location.x), y: millimetres(viewHeight - location.y))
    }

    /// A y-up rect inside a container of height `containerHeight` -> a y-down UIKit rect in
    /// that container's coordinates. Used for the face view's frame (keyboard space, container =
    /// input view), the globe control's frame, and every rect FaceView draws (face space,
    /// container = face).
    public func viewRect<Space>(_ rect: MMRect<Space>, containerHeight: Millimetres) -> CGRect {
        let origin = CGPoint(x: points(rect.minX), y: points(containerHeight - rect.maxY))
        let size = CGSize(width: points(rect.size.width), height: points(rect.size.height))
        return CGRect(origin: origin, size: size)
    }
}
