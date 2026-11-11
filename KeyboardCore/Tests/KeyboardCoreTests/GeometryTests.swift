import CoreGraphics
import Testing
import KeyboardCore

/// Geometry fidelity against prototype/index.html, and hit-testing. Public API only.
@Suite struct GeometryTests {
    let outer = Environment(surface: .duoOuter, showsGlobeKey: false)
    let outerWithGlobe = Environment(surface: .duoOuter, showsGlobeKey: true)

    func layout(_ placement: Placement = .default, _ environment: Environment? = nil) -> Layout {
        KeyboardEngine(placement: placement, environment: environment ?? outer).layout
    }

    func near(_ a: Millimetres, _ b: Millimetres, _ tolerance: Double = 0.001) -> Bool {
        abs(a.value - b.value) <= tolerance
    }

    func caps(_ layout: Layout) -> [KeyCap] { Array(layout.face.caps) }

    // MARK: Prototype numbers

    @Test func defaultLetterKeysAre5_1mmWide() {
        // unit 5.9, gx 0.8 -> cap width 5.1 mm (README "5.1 mm letter keys")
        let letters = caps(layout()).filter { if case .character = $0.id { return true } else { return false } }
        #expect(letters.count == 26)
        for cap in letters { #expect(near(cap.frame.size.width, 5.1)) }
    }

    @Test func defaultRowHeightAndGaps() {
        let face = layout().face
        // unit 5.9 -> rowH 8.142; gy = rowH * 0.16 = 1.30272
        #expect(near(face.rowHeight, 8.142))
        let q = caps(layout())[0]
        #expect(near(q.frame.size.height, 8.142 - 8.142 * 0.16))
        #expect(near(q.slot.size.height, 8.142))
    }

    /// The headline finding: at the defaults all 31 keys are in reach. Both ends are tight
    /// ('q' at 71.7 mm of the 72 mm reach; 'p' at 20.3 mm of the 20 mm minimum), so any drift
    /// from the prototype formulas fails this test.
    ///
    /// Flush (inset 0, lift 9): the prototype's own formulas give 26 of 31. The brief says 5 outside
    /// at the 2 mm margin with no lift; this pins what the formulas produce at lift 9.
    @Test(arguments: [(Placement.default, 31), (Placement(hand: .right, inset: 0, lift: 9), 26)])
    func reachModel(placement: Placement, expectedInReach: Int) {
        let l = layout(placement)
        #expect(ReachModel.prototype.keysInReach(l, surface: outer.surface) == expectedInReach)
    }

    @Test func flippingMirrorsDockNotKeyOrder() {
        let right = layout(Placement(hand: .right, inset: 7, lift: 9))
        let left = layout(Placement(hand: .left, inset: 7, lift: 9))
        let width = outer.surface.width
        #expect(near(left.faceFrame.minX, width - right.faceFrame.maxX))
        for l in [right, left] {
            let row0 = l.face.rows[0].caps.map(\.id)
            #expect(row0 == "qwertyuiop".map { KeyID.character($0) })
        }
        #expect(right.face.flipButton.minX == 0)
        #expect(left.face.flipButton.maxX == left.face.tray.maxX)
    }

    @Test func physicalSizeIsConstantAcrossScreens() {
        let density = PointsPerMillimetre.duoOuter
        let inner = Environment(
            surface: Surface(width: Millimetres(951 / density.value), screenHeight: Millimetres(669 / density.value),
                             bottomInset: 0, density: density),
            showsGlobeKey: false)
        let a = layout(.default, outer), b = layout(.default, inner)
        #expect(a.face == b.face)
        #expect(near(a.faceFrame.minX + a.faceFrame.size.width, outer.surface.width - 2 - 7 + 1.5))
        #expect(near(b.faceFrame.minX + b.faceFrame.size.width, inner.surface.width - 2 - 7 + 1.5))
    }

    @Test func placementIsClampedButNotForgotten() {
        let far = Placement(hand: .right, inset: 80, lift: 9)
        let engine = KeyboardEngine(placement: far, environment: outer)
        let maxInset = outer.surface.width - 2 * 2 - 59
        #expect(near(engine.layout.placement.inset, maxInset))
        #expect(engine.placement.inset == 80)
        #expect(near(engine.layout.faceFrame.minX, 2 - 1.5))
    }

    @Test func liftIsCappedAtSixtyPercentOfScreenHeight() {
        let l = layout(Placement(hand: .right, inset: 7, lift: 150))
        #expect(near(l.height, outer.surface.screenHeight * 0.6))
        #expect(near(l.faceFrame.maxY, l.height))
    }

    @Test func bottomInsetIsSubtractedFromLift() {
        var surface = Surface.duoOuter
        let flat = layout(.default, outer).faceFrame.minY
        surface.bottomInset = 5
        let raised = layout(.default, Environment(surface: surface, showsGlobeKey: false)).faceFrame.minY
        #expect(near(flat - raised, 5))
    }

    @Test func globeKeyShrinksOnlySpace() {
        let plain = layout(.default, outer), withGlobe = layout(.default, outerWithGlobe)
        for key in [KeyID.layerToggle, .return] {
            #expect(plain.slot(of: key) == withGlobe.slot(of: key))
        }
        #expect(plain.slot(of: .globe) == nil)
        #expect(near(withGlobe.slot(of: .globe)!.size.width, 1.5 * 5.9))
        #expect(near(withGlobe.slot(of: .space)!.size.width, 3.5 * 5.9))
        #expect(near(plain.slot(of: .space)!.size.width, 5 * 5.9))
    }

    @Test func keymapRowsFitAndIDsAreUnique() {
        for layer in [Layer.letters, .symbols] {
            for globe in [false, true] {
                var engine = KeyboardEngine(placement: .default,
                                            environment: Environment(surface: .duoOuter, showsGlobeKey: globe))
                if layer == .symbols { toggle(&engine) }
                let face = engine.layout.face
                #expect(face.rows.count == 4)
                var seen: Set<KeyID> = []
                for row in face.rows {
                    let width = row.caps.reduce(Millimetres.zero) { $0 + $1.slot.size.width }
                    #expect(width.value <= 59 + 0.0001)
                    for cap in row.caps {
                        #expect(seen.insert(cap.id).inserted)
                        #expect(engine.layout.slot(of: cap.id) != nil)
                    }
                }
            }
        }
    }

    /// Switches to the symbols layer by tapping the layer toggle.
    private func toggle(_ engine: inout KeyboardEngine) {
        let at = engine.layout.slot(of: .layerToggle)!.center
        let id = TouchID(1), t = Instant(secondsSinceBoot: 1)
        _ = engine.send(.touchBegan(id, at, at: t))
        _ = engine.send(.touchEnded(id, at, at: t + 0.05))
        #expect(engine.layer == .symbols)
    }

    // MARK: Hit-testing

    @Test func gapBetweenKeysHitsNearerKey() {
        let l = layout()
        let g = caps(l).first { $0.id == .character("g") }!
        let h = caps(l).first { $0.id == .character("h") }!
        let origin = l.faceFrame.origin
        let y = g.frame.center.y + origin.y
        // The gap is 0.8 mm; 0.1 mm into it from either side still belongs to the nearer cap.
        #expect(l.hitTest(KeyboardPoint(x: g.frame.maxX + origin.x + 0.1, y: y)) == .key(.character("g")))
        #expect(l.hitTest(KeyboardPoint(x: h.frame.minX + origin.x - 0.1, y: y)) == .key(.character("h")))
    }

    @Test func shortRowSideMarginHitsEndKey() {
        let l = layout()
        let a = caps(l).first { $0.id == .character("a") }!
        let origin = l.faceFrame.origin
        let p = KeyboardPoint(x: a.slot.minX + origin.x - 1.5, y: a.slot.center.y + origin.y)
        #expect(l.hitTest(p) == .key(.character("a")))
    }

    @Test func slopBelowTrayHitsBottomRowBeyondItHitsNothing() {
        let l = layout()
        let x = l.slot(of: .space)!.center.x
        #expect(l.hitTest(KeyboardPoint(x: x, y: l.faceFrame.minY - 2)) == .key(.space))
        #expect(l.hitTest(KeyboardPoint(x: x, y: l.faceFrame.minY - 4)) == .none)
        #expect(l.hitTest(KeyboardPoint(x: l.faceFrame.minX - 4, y: l.faceFrame.minY + 10)) == .none)
    }

    @Test func handleStripAndFlipButton() {
        for hand in [Hand.right, .left] {
            let l = layout(Placement(hand: hand, inset: 7, lift: 9))
            let o = l.faceFrame.origin
            let handle = l.face.handle.center, flip = l.face.flipButton.center
            #expect(l.hitTest(KeyboardPoint(x: handle.x + o.x, y: handle.y + o.y)) == .handle)
            #expect(l.hitTest(KeyboardPoint(x: flip.x + o.x, y: flip.y + o.y)) == .flipButton)
            // Far end from the thumb: left end for the right hand, right end for the left.
            #expect((flip.x < handle.x) == (hand == .right))
        }
    }

    @Test func hitTestIsTotal() {
        let l = layout()
        for x in [-1e9, 0, 1e9, Double.nan, Double.infinity] {
            for y in [-1e9, 0, 1e9, Double.nan, -Double.infinity] {
                _ = l.hitTest(KeyboardPoint(x: Millimetres(x), y: Millimetres(y)))
            }
        }
    }

    @Test func viewConversionRoundTrips() {
        let l = layout()
        let density = outer.surface.density
        let slot = l.slot(of: .character("g"))!
        let viewHeight = l.height
        let rect = density.viewRect(slot, containerHeight: viewHeight)
        let back = density.keyboardPoint(fromView: CGPoint(x: rect.midX, y: rect.midY),
                                         viewHeight: CGFloat(viewHeight.value * density.value))
        #expect(near(back.x, slot.center.x))
        #expect(near(back.y, slot.center.y))
    }

    @Test func resolveKnowsTheDuoOuterPanel() {
        #expect(PointsPerMillimetre.resolve(nativePixelSize: CGSize(width: 1398, height: 2034), scale: 3) == .duoOuter)
        #expect(PointsPerMillimetre.resolve(nativePixelSize: CGSize(width: 2034, height: 1398), scale: 3) == .duoOuter)
        let unknownAt2x = PointsPerMillimetre.resolve(nativePixelSize: CGSize(width: 828, height: 1792), scale: 2)
        #expect(abs(unknownAt2x.value - 326 / 25.4 / 2) < 1e-9)
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
        let pivot = KeyboardPoint(
            x: layout.placement.hand == .right ? surface.width + pivotOutside : .zero - pivotOutside,
            y: pivotUp)
        return layout.face.caps.filter { cap in
            let c = KeyboardPoint(x: cap.frame.center.x + layout.faceFrame.origin.x,
                                  y: cap.frame.center.y + layout.faceFrame.origin.y)
            let d = c.distance(to: pivot)
            return c.x > .zero && c.x < surface.width && d >= minimum && d <= reach
        }.count
    }
}
