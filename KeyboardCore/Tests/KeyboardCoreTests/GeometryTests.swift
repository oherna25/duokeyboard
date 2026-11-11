import Testing
import KeyboardCore

/// Geometry fidelity against prototype/index.html, and hit-testing. Public API only.
@Suite struct GeometryTests {
    let outer = Environment(surface: .duoOuter, showsGlobeKey: false)

    // MARK: Prototype numbers

    @Test func defaultLetterKeysAre5_1mmWide() {
        let layout = KeyboardEngine(placement: .default, environment: outer).layout
        // unit 5.9, gx 0.8 -> cap width 5.1 mm (README "5.1 mm letter keys")
        // TODO: #expect every .character cap frame width ≈ 5.1 mm (±0.001)
        _ = layout
    }

    @Test func defaultRowHeightAndGaps() {
        // TODO: rowHeight ≈ 8.142 mm (5.9 * 1.38); cap height ≈ rowHeight - 1.303 (gy = rowH * 0.16)
    }

    /// The headline finding: at the defaults all 31 keys are in reach. Both ends are tight
    /// ('q' at 71.7 mm of the 72 mm reach; 'p' at 20.3 mm of the 20 mm minimum), so any drift
    /// from the prototype formulas fails this test.
    ///
    /// Flush (inset 0, lift 9): the prototype's own formulas give 26 of 31, not the brief's
    /// "7 keys fall outside" (24 is the README's *stock width* figure). Pinned at 26 until the
    /// brief is corrected; see design.md, open questions.
    @Test(arguments: [(Placement.default, 31), (Placement(hand: .right, inset: 0, lift: 9), 26)])
    func reachModel(placement: Placement, expectedInReach: Int) {
        let layout = KeyboardEngine(placement: placement, environment: outer).layout
        #expect(ReachModel.prototype.keysInReach(layout, surface: outer.surface) == expectedInReach)
    }

    @Test func flippingMirrorsDockNotKeyOrder() {
        // TODO: left-hand layout: tray minX == right-hand tray's (width - maxX); row 0 still q..p left to right.
    }

    @Test func physicalSizeIsConstantAcrossScreens() {
        // TODO: inner surface (951 pt wide at 6.04): same cap sizes in mm, same 7 mm inset from
        // the right edge; only faceFrame.origin.x differs.
    }

    @Test func placementIsClampedButNotForgotten() {
        // TODO: Placement(inset: 80) on outer -> layout.placement.inset == max inset;
        // the engine's committed placement still reads 80 until the user drags.
    }

    @Test func bottomInsetIsSubtractedFromLift() {
        // TODO: bottomInset 5 mm -> faceFrame.minY is 5 mm lower than with bottomInset 0.
    }

    @Test func globeKeyShrinksOnlySpace() {
        // TODO: with showsGlobeKey, 123 and return slots are unchanged; space is 3.5u; globe 1.5u.
    }

    @Test func keymapRowsFitAndIDsAreUnique() {
        // TODO: for each layer x globe: every row <= 10u; slot(of:) non-nil for every cap's id.
    }

    // MARK: Hit-testing

    @Test func gapBetweenKeysHitsNearerKey() {
        // TODO: point 0.1 mm right of 'g' cap's maxX -> .key("g"); 0.1 mm left of 'h' minX -> .key("h")
    }

    @Test func shortRowSideMarginHitsEndKey() {
        // TODO: point left of 'a' (inside the 0.5u margin) -> .key("a")
    }

    @Test func slopBelowTrayHitsBottomRowBeyondItHitsNothing() {
        // TODO: 2 mm below tray -> bottom-row key; 4 mm below -> .none
    }

    @Test func handleStripAndFlipButton() {
        // TODO: centre of handle -> .handle; centre of flip button -> .flipButton;
        // flip button is at the left end for the right hand and the right end for the left hand.
    }

    @Test func viewConversionRoundTrips() {
        // TODO: density.keyboardPoint(fromView:) of the CGRect from viewRect(slot) centre == slot centre
    }
}

/// The prototype's reach model, for tests only (it judges the design; it does not ship).
/// Thumb pivot 6 mm outside the hand-side edge and 32 mm up from the screen bottom; a key is in
/// reach when its centre is on screen and 20 mm <= distance <= 72 mm.
struct ReachModel {
    var pivotOutside: Millimetres = 6
    var pivotUp: Millimetres = 32
    var reach: Millimetres = 72
    var minimum: Millimetres = 20

    static let prototype = ReachModel()

    /// Keyboard space is y-up from the input view bottom; with bottomInset 0 that is the screen
    /// bottom, so the pivot is (width + 6, 32) for the right hand and (-6, 32) for the left.
    func keysInReach(_ layout: Layout, surface: Surface) -> Int {
        // TODO: count caps of layout.face, converting cap.frame.center from face to keyboard
        // space by adding layout.faceFrame.origin.
        fatalError("not implemented")
    }
}
