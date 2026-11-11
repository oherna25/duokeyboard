import Foundation

// MARK: - Inputs and outputs

/// A moment on the system uptime clock: the clock `UITouch.timestamp` and
/// `ProcessInfo.systemUptime` both use, so touch times and timer ticks are comparable.
/// The core never reads a clock; time is always an input.
public struct Instant: Hashable, Comparable, Sendable {
    public var secondsSinceBoot: Double
    public init(secondsSinceBoot: Double) { self.secondsSinceBoot = secondsSinceBoot }
    public static func + (t: Instant, seconds: Double) -> Instant { Instant(secondsSinceBoot: t.secondsSinceBoot + seconds) }
    public static func - (a: Instant, b: Instant) -> Double { a.secondsSinceBoot - b.secondsSinceBoot }
    public static func < (a: Instant, b: Instant) -> Bool { a.secondsSinceBoot < b.secondsSinceBoot }
}

/// Opaque identity of one finger for the life of its touch. The shell builds it from
/// `ObjectIdentifier(uiTouch)`; UIKit keeps the same `UITouch` object from began to ended.
public struct TouchID: Hashable, Sendable {
    public let raw: UInt
    public init(_ raw: UInt) { self.raw = raw }
}

/// Everything that can happen to the keyboard. The engine's only entry point takes one of these.
public enum KeyboardInput: Sendable {
    case touchBegan(TouchID, KeyboardPoint, at: Instant)
    case touchMoved(TouchID, KeyboardPoint, at: Instant)
    case touchEnded(TouchID, KeyboardPoint, at: Instant)
    /// The system took the touch (e.g. a screen-edge gesture). Never commits anything.
    case touchCancelled(TouchID)
    /// The shell's timer fired. Spurious, early, late and duplicate ticks are all harmless.
    case tick(Instant)
    /// Surface or globe-key need changed. Re-sending an equal environment is a no-op.
    case environmentChanged(Environment)
}

/// Text operations, applied by the shell to `textDocumentProxy` in order.
/// These are *events* (they happen once), so they are returned. Everything that is *state*
/// (layout, placement, next wake time) is a property the shell reads after each input.
public enum TextEdit: Hashable, Sendable {
    case insert(String)
    case deleteBackward
}

public enum ShiftState: Hashable, Sendable {
    case off
    /// Next letter is uppercased, then shift turns off. `armedAt` is when the shift tap ended;
    /// a second tap beginning within `Timing.doubleTapWindow` of it locks caps.
    case once(armedAt: Instant)
    /// Caps lock: entered by tapping shift twice within `Timing.doubleTapWindow`.
    case locked
}

/// Interaction timing. One home for every duration the engine uses.
enum Timing {
    /// Second tap must *begin* within this long after the first tap *ended*.
    static let doubleTapWindow: Double = 0.30
    static let repeatDelay: Double = 0.50
    static let repeatInterval: Double = 0.10
    /// A handle touch becomes a drag only after moving this far (so taps never nudge it).
    static let dragSlop: Millimetres = 1
}

// MARK: - The engine

/// The whole keyboard as a value: layer, shift, placement, and the touch in progress.
///
/// Shape: a reducer. `send(_:)` is the only mutation; it returns the text edits to apply, and
/// every other output is a derived, read-only property. The shell's loop is
/// "convert UIKit event -> send -> apply edits -> reconcile views from properties".
///
/// Invariants:
/// - At most one tracked touch (`gesture` is an Optional, not a dictionary). A new touch while
///   a key is held commits the held key first (rollover, as in the system keyboard); a new
///   touch while backspace is held stops the repeat; a new touch during a drag is ignored.
/// - `placement` changes only at commit points (drag end, flip, handle double-tap), so the
///   shell persists exactly when it changes. A drag in progress lives in `gesture`, never in
///   `placement`; a cancelled drag therefore leaves the saved placement untouched.
/// - `tick` is idempotent: the number of deletes owed is a function of (hold start, now), and
///   the engine records how many it has emitted, so a tick at the same instant twice emits
///   nothing the second time. Missed repeats (main thread stalled) are dropped, not burst.
/// - Characters, space, return, shift and the layer toggle commit on touch *up*, using the key
///   under the finger at that moment (sliding to a neighbour before lifting corrects a miss;
///   sliding off the keyboard cancels). Backspace acts on touch *down* and repeats while held.
public struct KeyboardEngine: Sendable {

    /// The committed placement. Persist it whenever it changes.
    public private(set) var placement: Placement
    public private(set) var layer: Layer = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var environment: Environment

    private var gesture: Gesture?
    /// For double-tap detection on shift (caps lock) and on the handle (reset placement).
    private var lastTap: LastTap?

    public init(placement: Placement, environment: Environment) {
        self.placement = placement
        self.environment = environment
    }

    /// Current geometry and face. Derived on every read from state; never stale.
    /// During a drag it reflects the dragged position, so the shell moves the face live.
    public var layout: Layout {
        Layout(placement: gesture?.draggedPlacement ?? placement, environment: environment,
               layer: layer, shift: shift, pressed: gesture?.pressedTarget)
    }

    /// When the shell should next send `.tick`, or nil for no timer. The shell reconciles a
    /// single timer to this value after every input (derive, don't sync: there is no
    /// "schedule" / "cancel" effect to get out of order).
    public var nextWake: Instant? {
        guard case let .backspace(_, since, emitted) = gesture else { return nil }
        return since + (Timing.repeatDelay + Double(emitted - 1) * Timing.repeatInterval)
    }

    /// The single entry point. Total: every input is valid in every state.
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

    // MARK: Transitions (private: the reducer is the interface)

    /// - If a key is held: commit it (rollover). If backspace is held: stop. If dragging or on
    ///   the flip button: ignore this touch entirely.
    /// - Then by `layout.hitTest(point)`:
    ///   `.key(.backspace)` -> emit `.deleteBackward`, start `.backspace(since: at, emitted: 1)`
    ///   `.key(.globe)`     -> ignore (unreachable in practice: the shell's globe control sits on top)
    ///   `.key(k)`          -> `.key(over: k)`
    ///   `.handle`          -> `.handle(start: point, from: layout.placement, ...)`
    ///   `.flipButton`      -> `.flip(over: true)`
    ///   `.none`            -> nothing
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

    /// Only the tracked touch matters. `.key`: re-hit-test, `over` becomes the key under the
    /// finger or nil. `.handle`: past `Timing.dragSlop`, becomes a drag; the dragged placement
    /// is `from` moved by the delta (right hand: inset -= dx; left: inset += dx; lift += dy,
    /// y-up so no sign flip), lift snapped to `LayoutSpec.liftStep`, then clamped.
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

    /// The key a held touch would commit: backspace acts on touch down and the globe belongs to
    /// the shell's control, so neither can be the target of a slide.
    private static func committableKey(_ target: HitTarget) -> KeyID? {
        guard case .key(let key) = target, key != .backspace, key != .globe else { return nil }
        return key
    }

    /// `.key`: commit the key under `point` (re-hit-tested; nil commits nothing).
    /// `.backspace`: stop. `.handle`: a drag commits its placement; a tap is recorded in
    /// `lastTap`, and a second tap within the window resets inset and lift to the defaults
    /// (keeping the hand). `.flip`: if still over the button, commit
    /// `layout.placement` with the hand mirrored (so a clamped position flips as seen).
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

    /// Backspace repeat. Deletes owed by `now` for a hold starting at `since`:
    ///   1                                                     if now < since + repeatDelay
    ///   2 + floor((now - since - repeatDelay) / repeatInterval) otherwise
    /// Emit one `.deleteBackward` if owed > emitted, then set emitted = owed (dropping any
    /// backlog). Otherwise emit nothing.
    private mutating func tick(_ now: Instant) -> [TextEdit] {
        guard case let .backspace(id, since, emitted) = gesture else { return [] }
        let held = now - since
        // The epsilon keeps a tick scheduled exactly on a boundary from rounding down to the
        // previous count.
        let owed = held < Timing.repeatDelay
            ? 1 : 2 + Int(((held - Timing.repeatDelay) / Timing.repeatInterval + 1e-9).rounded(.down))
        guard owed > emitted else { return [] }
        gesture = .backspace(id, since: since, emitted: owed)
        return [.deleteBackward]
    }

    /// No-op when equal. Otherwise store it and cancel any gesture (its geometry is gone),
    /// except when only the granted height moved: a host that honors our height request resizes
    /// during a lift drag, and keyboard space is anchored at the bottom, so the gesture stays valid.
    private mutating func environmentChanged(_ env: Environment) {
        guard env != environment else { return }
        var comparable = env
        comparable.surface.grantedHeight = environment.surface.grantedHeight
        if comparable != environment { gesture = nil }
        environment = env
    }

    /// Applies one key's action.
    /// - `.character(c)`: insert `c` (uppercased on letters when shift != .off); `.once` -> `.off`.
    /// - `.space` -> " ", `.return` -> "\n".
    /// - `.shift`: `.off` -> `.once`; `.once` -> `.locked` if this tap began within the
    ///   double-tap window of the previous shift tap's end, else `.off`; `.locked` -> `.off`.
    /// - `.layerToggle`: flip layer; `.once` -> `.off` (`.locked` survives the round trip).
    /// - `.backspace`, `.globe`: never committed here (see touchBegan).
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

/// The touch in progress. One case per kind of thing a finger can be doing, each carrying
/// exactly the data that kind needs, so there are no optional fields "always set in practice".
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

    /// Non-nil only while a handle drag is past the slop.
    var draggedPlacement: Placement? {
        guard case .handle(_, _, _, let dragged) = self else { return nil }
        return dragged
    }

    /// What the face draws as pressed.
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
