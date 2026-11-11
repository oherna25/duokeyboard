# DuoKeyboard v1: candidate 2 — "one value, one view, one touch handler"

## Problem

Ship a one-handed keyboard extension whose geometry is physical (millimetres, from `gridLayout` and the "compact" variant in `prototype/index.html`). The keyboard docks toward the thumb and can be dragged sideways and up, and flipped to the other hand. Taps in the gaps between keys must still hit a key, backspace repeats while held, and shift supports caps lock. Four constraints make the shape non-obvious:

- **The input view resizes under the finger.** Lifting the keyboard grows the height constraint, which moves the view's top edge. UIKit reports touches in y-down view coordinates, so a drag tracked naively jumps every time the height changes.
- **Nearest-key hit-testing is a geometry rule, not a view rule.** Per-view touch targets (UIButton or a SwiftUI view per key) answer "which rect contains this point", which is the wrong question for gaps and short-row margins.
- **The extension has a memory limit of tens of MB, and Swift 6 strict concurrency.** Every framework layer and retained object counts against the limit, and every shared mutable object becomes a concurrency question.
- **Logic must be tested with `swift test` on macOS.** So time, touches and the screen must all be plain inputs to the code. Nothing in the logic may read UIKit or a clock.

## Usage (caller's view)

The core has one caller in production, the extension's view controller, and one in tests. Both drive it the same way:

```swift
import KeyboardCore

var engine = KeyboardEngine(placement: PlacementStore(defaults: .standard).load(),
                            environment: Environment(surface: .duoOuter, showsGlobeKey: true))

// Every UIKit event becomes one input; the engine returns text edits to apply.
let edits = engine.send(.touchEnded(touchID, point, at: instant))   // -> [.insert("h")]

// Everything else is state you read afterwards, never an event you must remember to handle:
engine.layout.height        // Millimetres, for the height constraint
engine.layout.faceFrame     // where the keyboard sits (moves during a drag)
engine.layout.face          // what to draw (unchanged during a drag)
engine.layout.slot(of: .globe)  // where the globe control goes, or nil
engine.nextWake             // when to send .tick (backspace repeat), or nil
engine.placement            // persist when it changes
```

**Call site 1: the extension's loop** (`Keyboard/KeyboardViewController.swift`)

```swift
override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    for t in touches { send(.touchBegan(id(t), point(t), at: instant(t))) }
}

private func send(_ input: KeyboardInput) {
    for edit in engine.send(input) {
        switch edit {
        case .insert(let s): textDocumentProxy.insertText(s)
        case .deleteBackward: textDocumentProxy.deleteBackward()
        }
    }
    reconcile()   // height, face frame, face, globe control, save-if-changed, timer: all from engine properties
}
```

**Call site 2: a test** (`KeyboardCore/Tests/KeyboardCoreTests/EngineTests.swift`)

```swift
var t = Typist()                        // wraps an engine plus a fake clock and a text buffer
t.tap(.shift); t.type("hi")             // taps at engine.layout.slot(of:)!.center
#expect(t.text == "Hi")
#expect(t.engine.shift == .off)
```

**Call site 3: the geometry regression** (`GeometryTests.swift`)

```swift
let layout = KeyboardEngine(placement: .default, environment: outer).layout
#expect(ReachModel.prototype.keysInReach(layout, surface: outer.surface) == 31)
```

## Shape

### Whole shape

```
UITouch ──► KeyboardViewController ──► KeyboardEngine.send(_:) ──► [TextEdit] ──► textDocumentProxy
               (convert, apply,           (reducer; owns layer,
                reconcile)                 shift, placement, the
                    ▲                      one touch in progress)
                    │                              │
                    └──── engine.layout ◄──────────┘  derived on read: Layout(placement, env, layer, shift, pressed)
                          engine.nextWake                     │
                          engine.placement                    ├─► FaceView.draw (one Core Graphics pass)
                                                              └─► Layout.hitTest (row by division, key by scan)
```

From finger to hit-test the path crosses three files: `KeyboardViewController.swift` → `Engine.swift` → `Layout.swift`. There is no per-key view and no custom touch view. `FaceView` has user interaction disabled, so the root `UIInputView` gets every touch and passes it up the responder chain to the controller.

### Data structures first

- **`Millimetres`, `MMPoint<Space>`, `MMRect<Space>`** (Units.swift). Millimetres are the only length unit in the core. The phantom `Space` is `KeyboardSpace` or `FaceSpace`, so hit-testing a touch against rects from the wrong space doesn't compile. **`PointsPerMillimetre`** is the only type that crosses between points and millimetres, and it holds both y-flips (`keyboardPoint(fromView:viewHeight:)` and `viewRect(_:containerHeight:)`). The shell does no coordinate arithmetic of its own. Per encode-lessons-in-structure.
- **Keyboard space is y-up from the input view's bottom edge.** This is the load-bearing decision for dragging. The input view is anchored at its bottom, so a point measured from the bottom stays put when the height changes. The drag delta `lift += dy` needs no sign flip and doesn't jump. It also makes `Placement.lift` mean what the prototype means: height above the bottom.
- **`Placement { hand, inset, lift }`** is the user's intent and is never clamped in storage. `Layout` clamps it against the current `Surface` when it derives geometry. The user's position on the 157 mm inner screen survives a trip to the 77 mm outer screen. Derive, don't sync.
- **`Environment { surface, showsGlobeKey }`** holds every host fact that affects layout, in one `Equatable` value. Changing the environment is one input, and resending an equal environment is a no-op. `Surface.bottomInset` subtracts any system bar below the input view, so the lift stays physical relative to the screen bottom, which is what the reach model assumes.
- **`Layout { height, faceFrame, face, placement }`** is derived on every read from engine state and is never cached. **`Face`** is translation-invariant: dragging changes only `faceFrame.origin`, so the shell moves the view without redrawing it. `Face.rows` is row-major with a uniform `rowHeight`, because hit-testing is the dominant access pattern (every touch event). The row is one division and the key is a scan of at most 10 slots that tile the row edge to edge. Nearest-key falls out of the structure: slots meet at gap midpoints, and clamping to the first or last key covers short-row margins. No index, spatial map or cache is needed later.
- **`KeyID` is both identity and action.** There is no `KeyAction` enum to keep in sync. **`Keymap.rows(for:showsGlobeKey:)`** is the single list of keys, and it is internal. Drawing, hit-testing, globe placement and accessibility all derive from `Layout`, which derives from this one list.
- **`Gesture?`** (private) is the touch in progress. Each case carries exactly its own data (`key(over:)`, `backspace(since:emitted:)`, `handle(start:from:dragged:)`, `flip(over:)`). It is an Optional, not a dictionary, so "at most one tracked touch" is a type fact.

### Interaction rules (the engine's contract)

| Touch | Down | Move | Up | Cancel |
|---|---|---|---|---|
| Character, space, return, shift, 123/ABC | arm the key; commit any held key first (rollover) | re-hit-test; the armed key follows the finger | commit the key under the finger now (nil when off the face) | nothing |
| Backspace | delete once; start the hold | — | stop | stop |
| Handle | arm | past 1 mm slop: drag; lift snaps to 0.5 mm; clamp | drag: commit placement. Tap: a second tap within 0.3 s resets inset and lift | dragged position discarded |
| Flip button | arm | track over or off | if still over: mirror hand | nothing |
| Globe | never reaches the engine (the overlay `UIControl` owns it) | | | |

- **Shift:** off → once → (second tap begins ≤ 0.3 s after the first ends) locked; otherwise off. Locked → off. A committed letter clears `.once`. The layer toggle clears `.once` and keeps `.locked`.
- **Backspace repeat:** deletes owed = 1 before 0.5 s, then 2 + ⌊(elapsed − 0.5) / 0.1⌋. Each tick emits at most one delete and records the owed count, so ticks are idempotent and a stalled timer drops the backlog instead of bursting it. Per make-operations-idempotent.

### Load-bearing decisions

1. **The core is a reducer, and only events are effects.** `send(_:) -> [TextEdit]` is the only mutation. Things that happen once (insert, delete) are returned. Things that are true for a while (layout, `nextWake`, `placement`) are properties the shell reconciles after every input. No "schedule timer" or "cancel timer" effect can arrive out of order, and no "save now" event can be missed. The shell's `reconcile()` compares before it writes, so it can run any number of times.
2. **One drawn view.** `FaceView.draw(_:)` renders a `Face` value with Core Graphics. Drawing is a pure function of a value, so the screen can't drift from engine state, and there is no per-key object tree to diff. Memory is one backing store of about 3.4 MB at @3x for the roughly 374 × 251 pt face. A press redraws about 31 rounded rects and labels. A drag redraws nothing.
3. **The globe key is drawn by the face and touched through a transparent `UIControl`.** That control is wired to `handleInputModeList(from:with:)` with `.allTouchEvents`, which is Apple's documented pattern. Its frame is `layout.slot(of: .globe)`, the same nearest-key region the hit-test would use. It is the only UIKit control in the extension, and it exists because that API wants a real control's event stream.
4. **Persistence lives in the core and is keyed by value change.** `PlacementStore` is the sole owner of the key `"placement.v1"` and of a private `Record` wire type. `load()` is total and falls back field by field. The shell saves when `engine.placement != lastSaved`, and placement changes only at commit points, so a drag never writes per frame. Per boundary-discipline.
5. **Time is an input.** `Instant` uses the system-uptime clock, the same base as `UITouch.timestamp` and `ProcessInfo.systemUptime`. The core never sleeps, schedules or reads a clock, so every timing rule is unit-tested deterministically.

### Concurrency and memory

- Every public core type is a `Sendable` value type with default (nonisolated) isolation. There are no classes, actors, locks or globals except `static let` constants.
- The shell targets build with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. The engine is a value owned by the main-actor controller, so no state is shared. The repeat timer is one main-actor `Task` that is replaced on each reconcile. A stale firing is harmless because `.tick` is idempotent.
- The extension links UIKit and KeyboardCore (Foundation only). It doesn't link SwiftUI or Combine, and it keeps no per-key objects.

### Interface depth

The public surface is one method (`send`), four read-only properties (`layout`, `nextWake`, `placement`, plus `layer`, `shift` and `environment` for tests), and two `Layout` queries (`hitTest`, `slot(of:)`). Behind it sit the prototype geometry, clamping, nearest-key rules, rollover, slide-to-correct, the shift and caps state machine, repeat timing, drag slop and quantisation, flip and reset. The shell learns none of these rules. It converts inputs, applies edits and copies properties onto views. `Keymap`, `LayoutSpec`, `Timing`, `Gesture` and the `Layout` initializer are internal or private, and tests use only the public API (no `@testable`), so no outside caller can import them.

### What it deliberately does not do

It has no SwiftUI in the extension, no per-key views or layers, no stored or cached layout, and no clock in the core. The containing app does not link the core. There is no XCTest bundle target, because all the logic is in the package.

## Module map

```
project.yml                         XcodeGen: 2 targets + local package (see file)
App/                                target DuoKeyboard (application, SwiftUI) — com.oherna25.duokeyboard
  DuoKeyboardApp.swift              @main App + SetupView (steps, Open Settings, try-it TextField)
Keyboard/                           target DuoKeyboardKeyboard (app-extension, UIKit) — com.oherna25.duokeyboard.keyboard
  KeyboardViewController.swift      principal class: touches → engine → proxy; reconcile(); environment; globe control
  FaceView.swift                    draw(Face) with Core Graphics; SF Symbol map; accessibility elements; palette
KeyboardCore/                       local Swift package (Foundation only)
  Package.swift
  Sources/KeyboardCore/
    Units.swift                     Millimetres, MMPoint/MMRect<Space>, PointsPerMillimetre (the only pt↔mm boundary)
    Keymap.swift                    KeyID, Layer, the single key list (internal)
    Layout.swift                    Hand, Placement, Surface, Environment, LayoutSpec, Layout, Face, KeyCap, hit-testing
    Engine.swift                    Instant, TouchID, KeyboardInput, TextEdit, ShiftState, KeyboardEngine (reducer)
    PlacementStore.swift            UserDefaults persistence, versioned record, total load
  Tests/KeyboardCoreTests/          `swift test --package-path KeyboardCore` on macOS
    GeometryTests.swift             prototype numbers, reach model (31/31 at defaults), clamping, hit-testing, conversions
    EngineTests.swift               typing, shift/caps, rollover, slide-to-correct, repeat idempotency, drag/flip/reset
    PlacementStoreTests.swift       round-trip, corrupt and invalid data, throwaway suite
.gitignore                          add *.xcodeproj, KeyboardCore/.build
```

All the core sketches typecheck: `swift build --build-tests` on macOS succeeds, and the shell files typecheck against the iOS 27 simulator SDK with Swift 6 and MainActor default isolation.

## Synthesis decision

Two runners designed the keyboard independently. They converged on the same whole shape: a value reducer with one mutator, time and touches as inputs, one Core Graphics view, millimetres as the domain unit, nearest-key hit-testing, and no SwiftUI in the extension. That convergence is the main evidence for the shape.

This candidate (B) is the base. The cross-judge scored it 27 against candidate A's 24, and I agree, for three reasons:

- A bottom-anchored, y-up keyboard space keeps a drag from jumping while the height constraint changes.
- The globe key uses Apple's documented `UIControl` pattern.
- Handle policy (slop, snapping, reset, flip) lives in the engine, where `swift test` covers it.

Grafts from candidate A:

1. **`Placement` validates itself.** Its fields are `let`, and its only initialiser clamps to absolute bounds and replaces non-finite values with the default. `Layout` still derives a per-surface clamp. `PlacementStore.load` decodes through that initialiser.
2. **`ShiftState.once(armedAt: Instant)`** carries the caps-lock double-tap time. `LastTap` remains only for the handle's double-tap reset.
3. **`viewWillDisappear`** sends a cancel for the tracked touch and cancels the repeat task, so a held backspace stops when the keyboard is dismissed.

One fix found in review:

4. **`Surface.bottomInset` is 0 in v1.** The shell does not measure it. Measuring it with `view.convert(_:to: screen.coordinateSpace)` can feed the input view's own height back into the environment, which would cancel drags and could collapse the lift. Measure the real system-bar height on the simulator before wiring it.

The flush-dock reach test pins 26 of 31 keys, which is what the prototype's formulas produce. The brief has been corrected to match.

## Tradeoffs accepted

- We give up per-key UIKit niceties (highlight animations, per-view accessibility for free) and get one source of truth, nearest-key hit-testing as plain arithmetic, and no view tree to keep in sync. Accessibility is restored by deriving elements from the same `Face`. They activate through synthesized taps, so there is no second commit path.
- We compute `Layout` on every read (about 31 rects for every touch event) and get no cache to invalidate. This is cheap enough that caching would be the premature move.
- We redraw the whole face on every press instead of one key, and get a stateless renderer. The face is small, and drags don't redraw.
- We update the height constraint live during a vertical drag (quantised to 0.5 mm, so at most about 2 host relayouts per mm), and the keyboard follows the finger without clipping. See the open questions if hosts stutter.
- We pin flush-edge reach at **26/31**, what the prototype's formulas actually produce, not the brief's "7 keys outside". This looks like a test that disagrees with the brief. It is deliberate.
- We have no shell unit tests. The shell holds no rules to test. A shell bug shows up as a visibly wrong keyboard in the simulator, not a subtle one.

## Alternatives considered

- **A SwiftUI view per key (the obvious shape).** Each key would carry its own gesture and an observable model would drive the views. This exposes the most complexity to the code around it. Nearest-key hit-testing needs a second invisible gesture layer over the views. Rollover and slide-to-correct across keys fight SwiftUI's per-view gesture arbitration. The touch policy lives inside view code that `swift test` can't run. The hosting stack and view graph also cost memory the extension may not have. It hides little and leaks a lot. Rejected.
- **UIButton or UIControl per key.** Target-action per key spreads policy across 31 objects. UIKit's exclusive-touch and tracking rules decide rollover instead of us, and gaps need an expanded `point(inside:)` on each button, which is a hand-synced copy of the geometry. Rejected for the same depth reason.
- **One touch view plus a CALayer per key.** This is viable, and redraws per key are cheaper. But it reintroduces a retained tree (31 shape layers and 31 text layers) that must be diffed against the `Face` value on every change, a second representation of the same state. Drawing a value is simpler and fast enough. We would revisit it only if profiling shows `draw(_:)` costs a frame.
- **A class engine with a delegate** (`delegate.insertText`, `delegate.scheduleTimer`). Tests would need mocks, there would be reference cycles to manage, and Swift 6 would demand isolation annotations on the core. Ordering between "schedule" and "cancel" callbacks would become the caller's problem. Rejected in favour of a value reducer with derived outputs.
- **Core in points, scaled by density.** The tests could no longer quote the prototype's millimetre numbers, and "fraction of the screen" layouts would become easy to write by accident. Rejected because millimetres are the domain unit.

## Open questions and risks

- **Flush reach count.** The brief says that docked flush, 7 keys fall outside. The prototype's formulas give 26/31 at inset 0 and lift 9 (5 outside). 24/31 is the README's stock-width figure. Which number should the test pin?
- **Does the Duo draw the system globe and dictation bar below third-party keyboards?** If it does, `bottomInset` matters, and so does the question of whether `view.convert(_:to: screen.coordinateSpace)` reports a real offset inside an extension. If it reports 0, keys sit higher than the reach model assumes. Should we measure this on the simulator before trusting the defaults?
- **Inner-screen density.** Is the inner panel also 460 ppi? `PointsPerMillimetre.resolve` needs its native pixel size in the table. Otherwise it falls back to the @3x guess of 6.04 pt/mm.
- **Live height changes during a drag.** If some hosts stutter, should the fallback be to freeze the height at drag start plus the remaining headroom, and settle the height on release?
- **Lift ceiling.** Is a face top at 60% of the screen height (about 23 mm of lift on the outer screen) the right cap? The prototype allowed 50% of the screen as lift alone.
- **Omissions that look like bugs.** v1 has no key-preview callout, auto-capitalisation, double-space period, return-key label from `returnKeyType`, or automatic return to letters after space on the symbols layer. Should any of these land in v1?
- **Flip button at the handle's far end.** It is a deliberate reach, to avoid accidental flips. Is that the right ergonomic call versus putting it near the thumb?

## Next implementation step

Implement `Units.swift`, `Keymap.swift` and `Layout.swift` until `GeometryTests` pass, starting with the reach-model test. It is tight at both ends (`q` at 71.7 of 72 mm, `p` at 20.3 of the 20 mm minimum), so it proves the transcription of `gridLayout` before anything else is built.
