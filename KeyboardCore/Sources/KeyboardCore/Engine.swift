import Foundation

// MARK: - Inputs and outputs

/// A moment on the system uptime clock, which `UITouch.timestamp` and
/// `ProcessInfo.systemUptime` share. The core never reads a clock.
public struct Instant: Hashable, Comparable, Sendable {
    public var secondsSinceBoot: Double
    public init(secondsSinceBoot: Double) { self.secondsSinceBoot = secondsSinceBoot }
    public static func + (t: Instant, seconds: Double) -> Instant { Instant(secondsSinceBoot: t.secondsSinceBoot + seconds) }
    public static func - (a: Instant, b: Instant) -> Double { a.secondsSinceBoot - b.secondsSinceBoot }
    public static func < (a: Instant, b: Instant) -> Bool { a.secondsSinceBoot < b.secondsSinceBoot }
}

/// Identity of one finger for the life of its touch. UIKit keeps the same `UITouch` object
/// from began to ended.
public struct TouchID: Hashable, Sendable {
    public let raw: UInt
    public init(_ raw: UInt) { self.raw = raw }
}

public enum KeyboardInput: Sendable {
    case touchBegan(TouchID, KeyboardPoint, at: Instant)
    case touchMoved(TouchID, KeyboardPoint, at: Instant)
    case touchEnded(TouchID, KeyboardPoint, at: Instant)
    /// The system took the touch, for example a screen-edge gesture. Never commits anything.
    case touchCancelled(TouchID)
    /// Spurious, early, late and duplicate ticks are all harmless.
    case tick(Instant)
    case environmentChanged(Environment)
}

/// Events the shell applies to `textDocumentProxy` in order. State is read from properties instead.
public enum TextEdit: Hashable, Sendable {
    case insert(String)
    case deleteBackward
}

public enum ShiftState: Hashable, Sendable {
    case off
    /// `armedAt` is when the shift tap ended. A second tap beginning within
    /// `Timing.doubleTapWindow` of it locks caps.
    case once(armedAt: Instant)
    case locked
}

enum Timing {
    /// Second tap must *begin* within this long after the first tap *ended*.
    static let doubleTapWindow: Double = 0.30
    static let repeatDelay: Double = 0.50
    static let repeatInterval: Double = 0.10
    /// A handle touch becomes a drag only after moving this far, so taps never nudge it.
    static let dragSlop: Millimetres = 1
}

// MARK: - The engine

/// The whole keyboard as a value. `send(_:)` is the only mutation and everything else is derived.
///
/// Invariants
/// - At most one tracked touch. A new touch while a key is held commits the held key first
///   (rollover, as in the system keyboard). A new touch while backspace is held stops the
///   repeat, and a new touch during a drag is ignored.
/// - `placement` changes only at commit points (drag end, flip, handle double-tap), so the
///   shell persists exactly when it changes. A drag lives in `gesture`, so a cancelled drag
///   leaves the saved placement untouched.
/// - `tick` is idempotent. Deletes owed are a function of hold start and now, and the engine
///   records how many it has emitted. Missed repeats are dropped, not burst.
/// - Characters, space, return, shift and the layer toggle commit on touch up, using the key
///   under the finger then, so sliding to a neighbour corrects a miss and sliding off cancels.
///   Backspace acts on touch down and repeats while held.
public struct KeyboardEngine: Sendable {

    public private(set) var placement: Placement
    public private(set) var layer: Layer = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var environment: Environment

    private var gesture: Gesture?
    private var lastTap: LastTap?

    public init(placement: Placement, environment: Environment) {
        self.placement = placement
        self.environment = environment
    }

    /// During a drag this reflects the dragged position, so the face moves live.
    public var layout: Layout {
        Layout(placement: gesture?.draggedPlacement ?? placement, environment: environment,
               layer: layer, shift: shift, pressed: gesture?.pressedTarget)
    }

    /// When the shell should next send `.tick`, or nil for no timer.
    public var nextWake: Instant? {
        guard case let .backspace(_, since, emitted) = gesture else { return nil }
        return since + (Timing.repeatDelay + Double(emitted - 1) * Timing.repeatInterval)
    }

    /// Total. Every input is valid in every state.
    public mutating func send(_ input: KeyboardInput) -> [TextEdit] {
        switch input {
        case let .touchBegan(id, point, at): return touchBegan(id, point, at)
        case let .touchMoved(id, point, at): touchMoved(id, point, at); return []
        case let .touchEnded(id, point, at): return touchEnded(id, point, at)
        case let .touchCancelled(id): touchCancelled(id); return []
        case let .tick(now): return tick(now)
        case let .environmentChanged(env): environmentChanged(env); return []
        }
    }

    // MARK: Transitions

    /// A `.globe` hit is ignored because the shell's globe control sits on top of it.
    private mutating func touchBegan(_ id: TouchID, _ point: KeyboardPoint, _ at: Instant) -> [TextEdit] {
        // Hit-test against what the user saw, before a rollover commit can change the layer.
        let current = layout
        let target = current.hitTest(point)
        var edits: [TextEdit] = []
        switch gesture {
        case let .key(_, began, over?):
            edits = commit(over, began: began, ended: at)
        case .handle, .flip:
            return []
        case .key, .backspace, nil:
            break
        }
        gesture = nil
        switch target {
        case .key(.backspace):
            edits.append(.deleteBackward)
            gesture = .backspace(id, since: at, emitted: 1)
        case .key(.globe), .none:
            break
        case .key(let key):
            gesture = .key(id, began: at, over: key)
        case .handle:
            gesture = .handle(id, start: point, from: current.placement, dragged: nil)
        case .flipButton:
            gesture = .flip(id, over: true)
        }
        return edits
    }

    /// The dragged placement is `from` moved by the delta. Right hand inset -= dx, left hand
    /// inset += dx, and lift += dy with no sign flip since y is up. Lift snaps to
    /// `LayoutSpec.liftStep`, then clamps.
    private mutating func touchMoved(_ id: TouchID, _ point: KeyboardPoint, _ at: Instant) {
        guard let current = gesture, current.touch == id else { return }
        switch current {
        case let .key(_, began, _):
            gesture = .key(id, began: began, over: Self.committableKey(layout.hitTest(point)))
        case let .handle(_, start, from, dragged):
            let dx = point.x - start.x, dy = point.y - start.y
            guard dragged != nil || hypot(dx.value, dy.value) >= Timing.dragSlop.value else { return }
            let inset = from.hand == .right ? from.inset - dx : from.inset + dx
            let lift = Millimetres(((from.lift + dy) / LayoutSpec.liftStep).rounded()) * LayoutSpec.liftStep.value
            let moved = Placement(hand: from.hand, inset: inset, lift: lift).clamped(to: environment)
            gesture = .handle(id, start: start, from: from, dragged: moved)
        case .flip:
            gesture = .flip(id, over: layout.hitTest(point) == .flipButton)
        case .backspace:
            break
        }
    }

    /// Backspace acts on touch down and the globe belongs to the shell's control, so neither
    /// can be the target of a slide.
    private static func committableKey(_ target: HitTarget) -> KeyID? {
        guard case .key(let key) = target, key != .backspace, key != .globe else { return nil }
        return key
    }

    /// A double-tap on the handle resets inset and lift but keeps the hand. A flip commits
    /// `layout.placement` mirrored, so a clamped position flips as seen.
    private mutating func touchEnded(_ id: TouchID, _ point: KeyboardPoint, _ at: Instant) -> [TextEdit] {
        guard let ending = gesture, ending.touch == id else { return [] }
        let target = layout.hitTest(point)
        let effective = layout.placement
        gesture = nil
        switch ending {
        case let .key(_, began, _):
            guard let key = Self.committableKey(target) else { return [] }
            return commit(key, began: began, ended: at)
        case .backspace:
            return []
        case let .handle(_, _, _, dragged):
            if let dragged {
                placement = dragged
                lastTap = nil
            } else if let previous = lastTap, previous.target == .handle,
                      at - previous.ended <= Timing.doubleTapWindow {
                placement = Placement(hand: effective.hand, inset: Placement.default.inset, lift: Placement.default.lift)
                lastTap = nil
            } else {
                lastTap = LastTap(target: .handle, ended: at)
            }
            return []
        case let .flip(_, over):
            if over && target == .flipButton {
                placement = Placement(hand: effective.hand.mirrored, inset: effective.inset, lift: effective.lift)
            }
            return []
        }
    }

    private mutating func touchCancelled(_ id: TouchID) {
        if gesture?.touch == id { gesture = nil }
    }

    /// Deletes owed are 1 before `repeatDelay`, then 2 + floor((held - repeatDelay) / repeatInterval).
    /// Emits at most one and drops any backlog.
    private mutating func tick(_ now: Instant) -> [TextEdit] {
        guard case let .backspace(id, since, emitted) = gesture else { return [] }
        let held = now - since
        // The epsilon keeps a tick scheduled exactly on a boundary from rounding down.
        let owed = held < Timing.repeatDelay
            ? 1 : 2 + Int(((held - Timing.repeatDelay) / Timing.repeatInterval + 1e-9).rounded(.down))
        guard owed > emitted else { return [] }
        gesture = .backspace(id, since: since, emitted: owed)
        return [.deleteBackward]
    }

    /// A changed environment cancels the gesture, since its geometry is gone. The exception is
    /// a change to only the granted height. A host that honors our height request resizes
    /// during a lift drag, and keyboard space is anchored at the bottom, so the gesture stays valid.
    private mutating func environmentChanged(_ env: Environment) {
        guard env != environment else { return }
        var comparable = env
        comparable.surface.grantedHeight = environment.surface.grantedHeight
        if comparable != environment { gesture = nil }
        environment = env
    }

    /// `.backspace` and `.globe` are never committed here. `.locked` shift survives a layer toggle.
    private mutating func commit(_ key: KeyID, began: Instant, ended: Instant) -> [TextEdit] {
        switch key {
        case .character(let c):
            let upper = layer == .letters && shift != .off
            if case .once = shift { shift = .off }
            return [.insert(upper ? String(c).uppercased() : String(c))]
        case .space:
            return [.insert(" ")]
        case .return:
            return [.insert("\n")]
        case .shift:
            switch shift {
            case .off: shift = .once(armedAt: ended)
            case .once(let armedAt):
                shift = began - armedAt <= Timing.doubleTapWindow ? .locked : .off
            case .locked: shift = .off
            }
            return []
        case .layerToggle:
            layer = layer == .letters ? .symbols : .letters
            if case .once = shift { shift = .off }
            return []
        case .backspace, .globe:
            return []
        }
    }
}

private enum Gesture: Sendable {
    case key(TouchID, began: Instant, over: KeyID?)
    case backspace(TouchID, since: Instant, emitted: Int)
    case handle(TouchID, start: KeyboardPoint, from: Placement, dragged: Placement?)
    case flip(TouchID, over: Bool)

    var touch: TouchID {
        switch self {
        case .key(let id, _, _), .backspace(let id, _, _), .handle(let id, _, _, _), .flip(let id, _): id
        }
    }

    var draggedPlacement: Placement? {
        guard case .handle(_, _, _, let dragged) = self else { return nil }
        return dragged
    }

    var pressedTarget: HitTarget? {
        switch self {
        case .key(_, _, let over): over.map { .key($0) }
        case .backspace: .key(.backspace)
        case .handle: .handle
        case .flip(_, let over): over ? .flipButton : nil
        }
    }
}

private struct LastTap: Sendable {
    let target: HitTarget
    let ended: Instant
}
