import UIKit
import KeyboardCore

/// The whole extension shell. Owns the engine and does four things, none of them policy:
/// 1. converts UIKit touches to `KeyboardInput` (the only place `UITouch` is read),
/// 2. applies returned `TextEdit`s to `textDocumentProxy`,
/// 3. reconciles views, the height constraint, the repeat timer and persistence from engine
///    properties after every input (`reconcile()`),
/// 4. measures the environment and sends it when it changes.
///
/// Touch routing: there is no per-key view and no custom touch view. `FaceView` has user
/// interaction disabled, so every touch in the input view hit-tests to the root `UIInputView`,
/// which forwards unhandled touches up the responder chain to this controller. One touch
/// handler, three files from finger to hit-test (this, Engine.swift, Layout.swift).
///
/// Isolation: the extension target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so
/// this type, its timer task and FaceView are main-actor without annotations. The engine is a
/// Sendable value owned here; nothing else holds it, so there is no shared mutable state.
final class KeyboardViewController: UIInputViewController {

    private let store: PlacementStore
    private var engine: KeyboardEngine
    /// What is on disk. `reconcile()` saves when `engine.placement` differs from it.
    private var lastSaved: Placement

    private let faceView = FaceView()
    /// Transparent control over the globe key's hit slot. Wired with the Apple-documented
    /// target-action for `handleInputModeList(from:with:)` (`.allTouchEvents`), so tap-to-switch
    /// and long-press-for-list behave exactly as the system expects. The face draws the key;
    /// this control only owns its touches.
    private let globeControl = UIControl()
    private var heightConstraint: NSLayoutConstraint?
    private var wakeTask: Task<Void, Never>?

    // MARK: Lifecycle

    /// The engine exists from construction (no implicitly unwrapped optional). It starts on the
    /// Duo outer surface; the real environment arrives in viewDidLoad before anything is drawn.
    override init(nibName: String?, bundle: Bundle?) {
        store = PlacementStore(defaults: .standard)
        lastSaved = store.load()
        engine = KeyboardEngine(placement: lastSaved,
                                environment: Environment(surface: .duoOuter, showsGlobeKey: true))
        super.init(nibName: nibName, bundle: bundle)
    }

    required init?(coder: NSCoder) { fatalError("not used: the extension instantiates the principal class in code") }

    override func viewDidLoad() {
        super.viewDidLoad()
        // TODO:
        // view.isMultipleTouchEnabled = true          // rollover needs the second finger
        // faceView.isUserInteractionEnabled = false; view.addSubview(faceView)  (frame-positioned, no Auto Layout)
        // globeControl.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        // view.addSubview(globeControl)
        // refreshEnvironment(); reconcile()
        fatalError("not implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Install the height constraint here, not in viewDidLoad: the system adds its own
        // height constraint on presentation, and ours must exist alongside it at priority 999
        // to win without an unsatisfiable-constraints log.
        // TODO: heightConstraint = view.heightAnchor.constraint(equalToConstant: ...); priority = .required - 1; isActive = true
        refreshEnvironment()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Width changes on fold / unfold and rotation. Idempotent: an equal environment is a
        // no-op inside the engine, and reconcile() only touches what changed.
        refreshEnvironment()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // needsInputModeSwitchKey can change between fields / hosts.
        refreshEnvironment()
    }

    // MARK: Touches -> engine

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { send(.touchBegan(id(touch), point(touch), at: instant(touch))) }
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { send(.touchMoved(id(touch), point(touch), at: instant(touch))) }
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { send(.touchEnded(id(touch), point(touch), at: instant(touch))) }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { send(.touchCancelled(id(touch))) }
    }

    private func id(_ touch: UITouch) -> TouchID { TouchID(UInt(bitPattern: ObjectIdentifier(touch))) }
    private func instant(_ touch: UITouch) -> Instant { Instant(secondsSinceBoot: touch.timestamp) }
    private func point(_ touch: UITouch) -> KeyboardPoint {
        engine.environment.surface.density.keyboardPoint(fromView: touch.location(in: view), viewHeight: view.bounds.height)
    }

    // MARK: The loop

    private func send(_ input: KeyboardInput) {
        for edit in engine.send(input) {
            switch edit {
            case .insert(let text): textDocumentProxy.insertText(text)
            case .deleteBackward: textDocumentProxy.deleteBackward()
            }
        }
        reconcile()
    }

    /// Makes the UIKit side match the engine. Every step compares before writing, so calling it
    /// any number of times is harmless (idempotent).
    private func reconcile() {
        let layout = engine.layout
        let density = engine.environment.surface.density
        // TODO:
        // 1. heightConstraint?.constant = density.points(layout.height)     (if different)
        // 2. faceView.frame = density.viewRect(layout.faceFrame, containerHeight: layout.height)
        //    (moves during a drag; no redraw)
        // 3. faceView.face = layout.face; faceView.density = density   (FaceView redraws only on change)
        // 4. globeControl: frame = layout.slot(of: .globe).map { density.viewRect($0, containerHeight: layout.height) },
        //    isHidden = (slot == nil)
        // 5. if engine.placement != lastSaved { store.save(engine.placement); lastSaved = engine.placement }
        // 6. scheduleWake(engine.nextWake)
        _ = (layout, density)
        fatalError("not implemented")
    }

    /// One timer slot, replaced on every reconcile. Correct even if a stale task fires,
    /// because `.tick` is idempotent.
    private func scheduleWake(_ wake: Instant?) {
        // TODO: if unchanged, return. wakeTask?.cancel(); guard let wake else { return }
        // wakeTask = Task { try? await Task.sleep(for: .seconds(wake - now)); guard !Task.isCancelled else { return }
        //                   send(.tick(Instant(secondsSinceBoot: ProcessInfo.processInfo.systemUptime))) }
        fatalError("not implemented")
    }

    // MARK: Environment

    private func refreshEnvironment() {
        let env = measureEnvironment()
        if env != engine.environment { send(.environmentChanged(env)) }
    }

    /// The only place screen facts are read.
    /// - density: `PointsPerMillimetre.resolve(nativePixelSize: screen.nativeBounds.size, scale: screen.nativeScale)`
    ///   where `screen = view.window?.windowScene?.screen` (fallback `.duoOuter` before the view is in a window)
    /// - width: `view.bounds.width`; screenHeight: `screen.bounds.height`
    /// - bottomInset: screen bottom minus the input view's bottom, via
    ///   `view.convert(view.bounds, to: screen.coordinateSpace)`, clamped >= 0 (0 if unavailable)
    /// - showsGlobeKey: `needsInputModeSwitchKey`
    private func measureEnvironment() -> Environment {
        fatalError("not implemented")
    }
}
