import Testing
import Foundation
import KeyboardCore

/// The input state machine, driven exactly as the shell drives it: touches at points, times as
/// values. No mocks: the engine returns its effects.
@Suite struct EngineTests {

    // MARK: Caller-shaped helpers (the usage the API was designed from)

    struct Typist {
        var engine = KeyboardEngine(placement: .default,
                                    environment: Environment(surface: .duoOuter, showsGlobeKey: false))
        var clock = Instant(secondsSinceBoot: 1_000)
        var text = ""
        private var nextTouch: UInt = 1

        /// Down and up at the centre of `key`, 80 ms apart, then 200 ms idle.
        mutating func tap(_ key: KeyID) {
            let at = engine.layout.slot(of: key)!.center
            let id = TouchID(nextTouch); nextTouch += 1
            apply(engine.send(.touchBegan(id, at, at: clock)))
            clock = clock + 0.08
            apply(engine.send(.touchEnded(id, at, at: clock)))
            clock = clock + 0.2
        }

        func center(_ key: KeyID) -> KeyboardPoint { engine.layout.slot(of: key)!.center }

        mutating func tapHandle() { tap(on: \.handle) }
        mutating func tapFlip() { tap(on: \.flipButton) }

        private mutating func tap(on region: KeyPath<Face, MMRect<FaceSpace>>) {
            let o = engine.layout.faceFrame.origin, c = engine.layout.face[keyPath: region].center
            let at = KeyboardPoint(x: o.x + c.x, y: o.y + c.y)
            let id = TouchID(nextTouch); nextTouch += 1
            apply(engine.send(.touchBegan(id, at, at: clock)))
            clock = clock + 0.05
            apply(engine.send(.touchEnded(id, at, at: clock)))
            clock = clock + 0.1
        }

        mutating func type(_ s: String) { for c in s { tap(.character(c)) } }

        mutating func apply(_ edits: [TextEdit]) {
            for edit in edits {
                switch edit {
                case .insert(let s): text += s
                case .deleteBackward: if !text.isEmpty { text.removeLast() }
                }
            }
        }
    }

    // MARK: Text

    @Test func typesLowercaseAndSpace() {
        var t = Typist()
        t.type("hi"); t.tap(.space)
        #expect(t.text == "hi ")
    }

    @Test func shiftIsOneShot() {
        var t = Typist()
        t.tap(.shift); t.type("hi")
        #expect(t.text == "Hi")
        #expect(t.engine.shift == .off)
    }

    @Test func doubleTapShiftLocksCaps() {
        var t = Typist()
        t.tap(.shift); t.tap(.shift)
        #expect(t.engine.shift == .locked)
        t.type("hi")
        #expect(t.text == "HI")
        t.tap(.shift)
        #expect(t.engine.shift == .off)
        t.type("h")
        #expect(t.text == "HIh")
    }

    @Test func capsLockSurvivesTheLayerRoundTrip() {
        var t = Typist()
        t.tap(.shift); t.tap(.shift)
        t.tap(.layerToggle); t.tap(.layerToggle)
        #expect(t.engine.shift == .locked)
    }

    @Test func slowSecondShiftTapTurnsShiftOff() {
        var t = Typist()
        t.tap(.shift)
        t.clock = t.clock + 0.3
        t.tap(.shift)
        #expect(t.engine.shift == .off)
    }

    @Test func shiftArmedBeforeANonLetterIsNotLocked() {
        var t = Typist()
        t.tap(.shift)
        #expect(t.engine.shift != .off && t.engine.shift != .locked)
        t.tap(.space)
        #expect(t.engine.shift != .locked)
    }

    @Test func layerToggleSwitchesAndClearsOneShotShift() {
        var t = Typist()
        t.tap(.shift); t.tap(.layerToggle)
        #expect(t.engine.layer == .symbols)
        #expect(t.engine.shift == .off)
        t.tap(.character("1"))
        #expect(t.text == "1")
        t.tap(.layerToggle)
        #expect(t.engine.layer == .letters)
    }

    @Test func returnInsertsNewline() {
        var t = Typist()
        t.tap(.return)
        #expect(t.text == "\n")
    }

    // MARK: Touch semantics

    @Test func commitUsesKeyUnderFingerAtLiftOff() {
        var t = Typist()
        let g = t.center(.character("g")), h = t.center(.character("h"))
        let id = TouchID(7)
        t.apply(t.engine.send(.touchBegan(id, g, at: t.clock)))
        t.apply(t.engine.send(.touchMoved(id, h, at: t.clock + 0.05)))
        t.apply(t.engine.send(.touchEnded(id, h, at: t.clock + 0.1)))
        #expect(t.text == "h")
    }

    @Test func slidingOffTheKeyboardCancels() {
        var t = Typist()
        let q = t.center(.character("q"))
        let off = KeyboardPoint(x: t.engine.layout.faceFrame.minX - 20, y: q.y)
        let id = TouchID(7)
        t.apply(t.engine.send(.touchBegan(id, q, at: t.clock)))
        t.apply(t.engine.send(.touchMoved(id, off, at: t.clock + 0.05)))
        t.apply(t.engine.send(.touchEnded(id, off, at: t.clock + 0.1)))
        #expect(t.text == "")
    }

    @Test func rolloverCommitsHeldKeyWhenNextBegins() {
        var t = Typist()
        let a = TouchID(1), b = TouchID(2)
        let h = t.center(.character("h")), i = t.center(.character("i"))
        #expect(t.engine.send(.touchBegan(a, h, at: t.clock)) == [])
        #expect(t.engine.send(.touchBegan(b, i, at: t.clock + 0.05)) == [.insert("h")])
        #expect(t.engine.send(.touchEnded(a, h, at: t.clock + 0.1)) == [])
        #expect(t.engine.send(.touchEnded(b, i, at: t.clock + 0.15)) == [.insert("i")])
    }

    @Test func rolloverHitTestsTheLayoutTheUserSaw() {
        var t = Typist()
        let a = TouchID(1), b = TouchID(2)
        let toggle = t.center(.layerToggle), q = t.center(.character("q"))
        _ = t.engine.send(.touchBegan(a, toggle, at: t.clock))
        // Committing the toggle switches layers, but the second finger aimed at the letters face.
        _ = t.engine.send(.touchBegan(b, q, at: t.clock + 0.05))
        #expect(t.engine.layer == .symbols)
        // The finger is still on the key under it after the redraw: "1" sits where "q" was.
        #expect(t.engine.send(.touchEnded(b, q, at: t.clock + 0.1)) == [.insert("1")])
    }

    @Test func cancelledTouchCommitsNothing() {
        var t = Typist()
        let id = TouchID(1), h = t.center(.character("h"))
        _ = t.engine.send(.touchBegan(id, h, at: t.clock))
        #expect(t.engine.layout.face.caps.contains { $0.isPressed })
        #expect(t.engine.send(.touchCancelled(id)) == [])
        #expect(!t.engine.layout.face.caps.contains { $0.isPressed })
        #expect(t.engine.send(.touchEnded(id, h, at: t.clock + 0.1)) == [])
    }

    // MARK: Backspace repeat

    @Test func backspaceDeletesOnDownThenRepeatsAfterDelay() {
        var t = Typist()
        let id = TouchID(1), at = t.center(.backspace), start = t.clock
        #expect(t.engine.send(.touchBegan(id, at, at: start)) == [.deleteBackward])
        #expect(t.engine.nextWake == start + 0.5)
        #expect(t.engine.send(.tick(start + 0.5)) == [.deleteBackward])
        #expect(t.engine.nextWake == start + 0.6)
        _ = t.engine.send(.touchEnded(id, at, at: start + 0.55))
        #expect(t.engine.nextWake == nil)
    }

    @Test func tickIsIdempotent() {
        var t = Typist()
        let start = t.clock
        _ = t.engine.send(.touchBegan(TouchID(1), t.center(.backspace), at: start))
        #expect(t.engine.send(.tick(start + 0.7)) == [.deleteBackward])
        #expect(t.engine.send(.tick(start + 0.7)) == [])
    }

    @Test func tickBeforeTheDelayDeletesNothing() {
        var t = Typist()
        let start = t.clock
        _ = t.engine.send(.touchBegan(TouchID(1), t.center(.backspace), at: start))
        #expect(t.engine.send(.tick(start + 0.4)) == [])
    }

    @Test func stalledTimerDropsBacklogInsteadOfBursting() {
        var t = Typist()
        let start = t.clock
        _ = t.engine.send(.touchBegan(TouchID(1), t.center(.backspace), at: start))
        #expect(t.engine.send(.tick(start + 3.0)) == [.deleteBackward])
        #expect(t.engine.nextWake! > start + 3.0)
    }

    @Test func spuriousTickWithNoHoldIsHarmless() {
        var t = Typist()
        let before = t.engine.layout
        #expect(t.engine.send(.tick(t.clock)) == [])
        #expect(t.engine.layout == before)
        #expect(t.engine.nextWake == nil)
    }

    @Test func cancelStopsRepeat() {
        var t = Typist()
        let id = TouchID(1), start = t.clock
        _ = t.engine.send(.touchBegan(id, t.center(.backspace), at: start))
        #expect(t.engine.nextWake != nil)
        _ = t.engine.send(.touchCancelled(id))
        #expect(t.engine.nextWake == nil)
        #expect(t.engine.send(.tick(start + 2)) == [])
    }

    @Test func aSecondFingerStopsTheRepeat() {
        var t = Typist()
        let start = t.clock
        _ = t.engine.send(.touchBegan(TouchID(1), t.center(.backspace), at: start))
        _ = t.engine.send(.touchBegan(TouchID(2), t.center(.character("h")), at: start + 0.2))
        #expect(t.engine.nextWake == nil)
    }

    // MARK: Placement

    /// Down on the handle, then drag by (dx, dy) mm in keyboard space (y up) in two moves.
    private func drag(_ t: inout Typist, dx: Double, dy: Double, end: Bool = true) {
        let id = TouchID(9)
        let o = t.engine.layout.faceFrame.origin, c = t.engine.layout.face.handle.center
        let start = KeyboardPoint(x: o.x + c.x, y: o.y + c.y)
        let stop = KeyboardPoint(x: start.x + Millimetres(dx), y: start.y + Millimetres(dy))
        _ = t.engine.send(.touchBegan(id, start, at: t.clock))
        _ = t.engine.send(.touchMoved(id, KeyboardPoint(x: (start.x + stop.x) * 0.5, y: (start.y + stop.y) * 0.5), at: t.clock + 0.05))
        _ = t.engine.send(.touchMoved(id, stop, at: t.clock + 0.1))
        if end { _ = t.engine.send(.touchEnded(id, stop, at: t.clock + 0.15)) }
        t.clock = t.clock + 0.5
    }

    @Test func dragMovesFaceLiveAndCommitsOnEnd() {
        var t = Typist()
        drag(&t, dx: -5, dy: 5, end: false)
        #expect(t.engine.layout.placement == Placement(hand: .right, inset: 12, lift: 14))
        #expect(t.engine.placement == .default)
        _ = t.engine.send(.touchEnded(TouchID(9), KeyboardPoint(x: 0, y: 0), at: t.clock))
        #expect(t.engine.placement == Placement(hand: .right, inset: 12, lift: 14))
    }

    @Test func draggingKeepsTheFaceContentsUnchanged() {
        var t = Typist()
        let before = t.engine.layout.face
        drag(&t, dx: -10, dy: 5, end: false)
        #expect(t.engine.layout.face.rows == before.rows)
    }

    @Test func leftHandDragMovesTheOtherWay() {
        var t = Typist()
        t.engine = KeyboardEngine(placement: Placement(hand: .left, inset: 7, lift: 9), environment: t.engine.environment)
        drag(&t, dx: 4, dy: 0)
        #expect(t.engine.placement.inset == 11)
    }

    @Test func liftSnapsToHalfMillimetres() {
        var t = Typist()
        drag(&t, dx: 0, dy: 3.3)
        #expect(t.engine.placement.lift == 12.5)
    }

    @Test func dragNeverExceedsBounds() {
        var t = Typist()
        drag(&t, dx: -200, dy: 200)
        let maxInset = t.engine.environment.surface.width - 4 - 59
        #expect(abs((t.engine.placement.inset - maxInset).value) < 1e-9)
        #expect(abs((t.engine.layout.height - t.engine.environment.surface.screenHeight * 0.6).value) < 1e-9)
        drag(&t, dx: 200, dy: -200)
        #expect(t.engine.placement.inset == 0)
        #expect(t.engine.placement.lift == 0)
    }

    @Test func handleTapBelowSlopDoesNotMove() {
        var t = Typist()
        drag(&t, dx: 0.5, dy: 0)
        #expect(t.engine.placement == .default)
    }

    @Test func cancelledDragKeepsCommittedPlacement() {
        var t = Typist()
        drag(&t, dx: -10, dy: 5, end: false)
        _ = t.engine.send(.touchCancelled(TouchID(9)))
        #expect(t.engine.placement == .default)
        #expect(t.engine.layout.placement == .default)
    }

    @Test func flipMirrorsHandKeepsInsetAndLift() {
        var t = Typist()
        t.tapFlip()
        #expect(t.engine.placement == Placement(hand: .left, inset: 7, lift: 9))
    }

    @Test func flipReleasedOffTheButtonDoesNothing() {
        var t = Typist()
        let id = TouchID(3), o = t.engine.layout.faceFrame.origin, c = t.engine.layout.face.flipButton.center
        let on = KeyboardPoint(x: o.x + c.x, y: o.y + c.y)
        let off = KeyboardPoint(x: on.x + 30, y: on.y)
        _ = t.engine.send(.touchBegan(id, on, at: t.clock))
        _ = t.engine.send(.touchMoved(id, off, at: t.clock + 0.05))
        _ = t.engine.send(.touchEnded(id, off, at: t.clock + 0.1))
        #expect(t.engine.placement == .default)
    }

    @Test func doubleTapHandleResetsPositionKeepsHand() {
        var t = Typist()
        drag(&t, dx: -5, dy: 5)
        t.tapFlip()
        #expect(t.engine.placement.hand == .left)
        t.tapHandle(); t.tapHandle()
        #expect(t.engine.placement == Placement(hand: .left, inset: 7, lift: 9))
    }

    @Test func slowSecondHandleTapDoesNotReset() {
        var t = Typist()
        drag(&t, dx: -5, dy: 5)
        t.tapHandle()
        t.clock = t.clock + 1
        t.tapHandle()
        #expect(t.engine.placement == Placement(hand: .right, inset: 12, lift: 14))
    }

    @Test func dragStartsFromClampedPlacement() {
        var t = Typist()
        t.engine = KeyboardEngine(placement: Placement(hand: .right, inset: 80, lift: 9), environment: t.engine.environment)
        let maxInset = t.engine.layout.placement.inset
        drag(&t, dx: 1, dy: 0)
        #expect(abs((t.engine.placement.inset - (maxInset - 1)).value) < 1e-9)
    }

    // MARK: Placement validation

    @Test func nonFinitePlacementFallsBackToDefault() {
        let p = Placement(hand: .left, inset: Millimetres(.nan), lift: Millimetres(Double.infinity))
        #expect(p.hand == .left)
        #expect(p.inset == Placement.default.inset)
        #expect(p.lift == Placement.default.lift)
        let engine = KeyboardEngine(placement: p, environment: Environment(surface: .duoOuter, showsGlobeKey: false))
        #expect(engine.layout.height.value.isFinite)
    }

    @Test func placementClampsToAbsoluteBounds() {
        let p = Placement(hand: .right, inset: -5, lift: 1e9)
        #expect(p.inset == 0)
        #expect(p.lift == 200)
    }

    // MARK: Environment

    @Test func equalEnvironmentIsNoOp() {
        var t = Typist()
        let id = TouchID(1), h = t.center(.character("h"))
        _ = t.engine.send(.touchBegan(id, h, at: t.clock))
        _ = t.engine.send(.environmentChanged(t.engine.environment))
        #expect(t.engine.send(.touchEnded(id, h, at: t.clock + 0.1)) == [.insert("h")])
    }

    @Test func environmentChangeCancelsGesture() {
        var t = Typist()
        let id = TouchID(1), h = t.center(.character("h"))
        _ = t.engine.send(.touchBegan(id, h, at: t.clock))
        var surface = Surface.duoOuter
        surface.width = surface.width * 2
        _ = t.engine.send(.environmentChanged(Environment(surface: surface, showsGlobeKey: false)))
        #expect(t.engine.send(.touchEnded(id, h, at: t.clock + 0.1)) == [])
    }
}
