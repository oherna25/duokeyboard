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
        // TODO: shift down/up, second down 0.1 s after first up -> .locked; "hi" -> "HI"; shift again -> .off
    }

    @Test func slowSecondShiftTapTurnsShiftOff() {
        // TODO: second tap begins 0.5 s after first ends -> .off, not .locked
    }

    @Test func layerToggleSwitchesAndClearsOneShotShift() {
        // TODO: shift, 123 -> layer .symbols, shift .off; "1" inserts "1"; ABC -> .letters
    }

    @Test func returnInsertsNewline() {
        var t = Typist()
        t.tap(.return)
        #expect(t.text == "\n")
    }

    // MARK: Touch semantics

    @Test func commitUsesKeyUnderFingerAtLiftOff() {
        // TODO: down on 'g', move to 'h' centre, up -> "h"
    }

    @Test func slidingOffTheKeyboardCancels() {
        // TODO: down on 'q', move 20 mm left of the face, up -> no edit
    }

    @Test func rolloverCommitsHeldKeyWhenNextBegins() {
        // TODO: A down 'h'; B down 'i' -> edits == [.insert("h")]; A up -> []; B up -> [.insert("i")]
    }

    @Test func cancelledTouchCommitsNothing() {
        // TODO: down 'h', .touchCancelled -> no edits, no pressed key in layout.face
    }

    // MARK: Backspace repeat

    @Test func backspaceDeletesOnDownThenRepeatsAfterDelay() {
        // TODO: down at t -> [.deleteBackward]; nextWake == t + 0.5;
        // tick(t + 0.5) -> one delete; nextWake == t + 0.6; up -> nextWake == nil
    }

    @Test func tickIsIdempotent() {
        // TODO: tick(t + 0.7) twice -> second returns []
    }

    @Test func stalledTimerDropsBacklogInsteadOfBursting() {
        // TODO: hold, first tick at t + 3.0 -> exactly one delete; nextWake > t + 3.0
    }

    @Test func spuriousTickWithNoHoldIsHarmless() {
        // TODO: tick with nothing held -> [], state unchanged
    }

    // MARK: Placement

    @Test func dragMovesFaceLiveAndCommitsOnEnd() {
        // TODO: down on handle, move 10 mm left and 5 mm up:
        //   layout.placement.inset == 17, lift == 14 during the drag; engine.placement unchanged;
        //   on end engine.placement == (right, 17, 14)
    }

    @Test func dragNeverExceedsBounds() {
        // TODO: drag 200 mm left / up -> inset == max inset, lift == max lift for the outer surface
    }

    @Test func handleTapBelowSlopDoesNotMove() {
        // TODO: move 0.5 mm, end -> placement unchanged
    }

    @Test func cancelledDragKeepsCommittedPlacement() {
        // TODO: drag then .touchCancelled -> engine.placement == before
    }

    @Test func flipMirrorsHandKeepsInsetAndLift() {
        // TODO: tap flip button -> hand .left, inset 7, lift 9
    }

    @Test func doubleTapHandleResetsPositionKeepsHand() {
        // TODO: after drag and flip, double-tap handle -> (left, 7, 9)
    }

    @Test func dragStartsFromClampedPlacement() {
        // TODO: engine with inset 80 on outer; drag 1 mm -> inset == max inset - 1 (not 79)
    }

    // MARK: Environment

    @Test func equalEnvironmentIsNoOp() {
        // TODO: send same environment while a key is held -> key still commits on up
    }

    @Test func environmentChangeCancelsGesture() {
        // TODO: hold 'h', unfold (new surface) -> up commits nothing
    }
}
