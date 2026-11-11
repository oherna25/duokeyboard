import CoreGraphics
import Foundation

// MARK: - Length

/// A physical length, the core's only length unit. A thumb is the same size on the inner and
/// outer screen, so geometry is in millimetres and points exist only at the UIKit boundary.
/// A `CGFloat` cannot be passed where a length is expected, so a missed conversion fails to compile.
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
    public static func / (a: Self, b: Self) -> Double { a.value / b.value }
    public static func < (a: Self, b: Self) -> Bool { a.value < b.value }
}

// MARK: - Coordinate spaces

/// Origin at the bottom-left of the input view, y upward. The view is anchored at its bottom
/// edge, so when a lift grows its height every point measured from the bottom stays put and a
/// drag never jumps under the finger.
public enum KeyboardSpace {}

/// Origin at the bottom-left of the face, y upward. Separate from keyboard space so moving the
/// keyboard changes only `Layout.faceFrame.origin` and never the `Face` value.
public enum FaceSpace {}

/// The phantom `Space` makes hit-testing a keyboard-space touch against face-space rects a
/// compile error.
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

/// `origin` is the bottom-left corner.
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

// MARK: - Points and millimetres

/// Display density, and the only conversion between UIKit points and core millimetres.
/// `value` is finite and > 0. Both directions of the y-flip (UIKit is y-down) live here.
public struct PointsPerMillimetre: Hashable, Sendable {
    public let value: Double

    public init?(_ value: Double) {
        guard value.isFinite, value > 0 else { return nil }
        self.value = value
    }

    /// Duo outer screen, 1398 x 2034 px at 460 ppi and @3x, so 460 / 25.4 / 3 = 6.04 pt/mm.
    public static let duoOuter = PointsPerMillimetre(unchecked: 460.0 / 25.4 / 3.0)

    private init(unchecked value: Double) { self.value = value }

    /// iOS does not expose physical ppi, so known panels are keyed by native pixel size, with
    /// a fallback by scale (@3x is 460 ppi, @2x is 326 ppi) that is right for current iPhone
    /// panels to within a few percent.
    public static func resolve(nativePixelSize: CGSize, scale: CGFloat) -> PointsPerMillimetre {
        let long = max(nativePixelSize.width, nativePixelSize.height)
        let short = min(nativePixelSize.width, nativePixelSize.height)
        if long == 2034, short == 1398 { return .duoOuter }
        let ppi: Double = scale >= 3 ? 460 : scale >= 2 ? 326 : 163
        return PointsPerMillimetre(unchecked: ppi / 25.4 / Double(scale >= 1 ? scale : 1))
    }

    public func points(_ length: Millimetres) -> CGFloat { CGFloat(length.value * value) }
    public func millimetres(_ points: CGFloat) -> Millimetres { Millimetres(Double(points) / value) }

    /// `viewHeight` is the input view's current bounds height, read at the moment of the touch.
    public func keyboardPoint(fromView location: CGPoint, viewHeight: CGFloat) -> KeyboardPoint {
        KeyboardPoint(x: millimetres(location.x), y: millimetres(viewHeight - location.y))
    }

    public func viewRect<Space>(_ rect: MMRect<Space>, containerHeight: Millimetres) -> CGRect {
        let origin = CGPoint(x: points(rect.minX), y: points(containerHeight - rect.maxY))
        let size = CGSize(width: points(rect.size.width), height: points(rect.size.height))
        return CGRect(origin: origin, size: size)
    }
}
