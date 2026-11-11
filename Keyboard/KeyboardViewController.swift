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
    private var scheduledWake: Instant?
    /// Fingers currently down on the root view, so `viewWillDisappear` can cancel them: the
    /// engine tracks one touch by id and the system sends no cancel when the keyboard is dismissed.
    private var liveTouches: Set<TouchID> = []

    // MARK: Lifecycle

    /// The engine exists from construction (no implicitly unwrapped optional). It starts on the
    /// Duo outer surface; the real environment arrives in viewDidLayoutSubviews before anything
    /// is drawn.
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
        view.isMultipleTouchEnabled = true
        faceView.isUserInteractionEnabled = false
        view.addSubview(faceView)
        globeControl.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        view.addSubview(globeControl)
        refreshEnvironment()
        reconcile()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Installed here, not in viewDidLoad: the system adds its own height constraint on
        // presentation, and ours must exist alongside it at priority 999 to win without an
        // unsatisfiable-constraints log.
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: 0)
            constraint.priority = UILayoutPriority(UILayoutPriority.required.rawValue - 1)
            constraint.isActive = true
            heightConstraint = constraint
        }
        refreshEnvironment()
        reconcile()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // A held backspace must not keep deleting after the keyboard goes away.
        let held = liveTouches
        liveTouches = []
        for id in held { send(.touchCancelled(id)) }
        wakeTask?.cancel()
        wakeTask = nil
        scheduledWake = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Width changes on fold / unfold and rotation. Idempotent: an equal environment is a
        // no-op inside the engine, and reconcile() only touches what changed.
        refreshEnvironment()
        reconcile()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // needsInputModeSwitchKey can change between fields / hosts.
        refreshEnvironment()
    }

    // MARK: Touches -> engine

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            liveTouches.insert(id(touch))
            send(.touchBegan(id(touch), point(touch), at: instant(touch)))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches { send(.touchMoved(id(touch), point(touch), at: instant(touch))) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            liveTouches.remove(id(touch))
            send(.touchEnded(id(touch), point(touch), at: instant(touch)))
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            liveTouches.remove(id(touch))
            send(.touchCancelled(id(touch)))
        }
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

        let height = density.points(layout.height)
        if let heightConstraint, heightConstraint.constant != height { heightConstraint.constant = height }

        // Position from the view's actual bottom edge, the same reference the touch conversion
        // uses, so the face and the finger agree even while the height constraint catches up.
        let container = view.bounds.height > 0 ? density.millimetres(view.bounds.height) : layout.height
        let frame = density.viewRect(layout.faceFrame, containerHeight: container)
        if faceView.frame != frame { faceView.frame = frame }
        faceView.density = density
        faceView.face = layout.face

        let globeSlot = layout.slot(of: .globe)
        let globeFrame = globeSlot.map { density.viewRect($0, containerHeight: container) } ?? .zero
        if globeControl.frame != globeFrame { globeControl.frame = globeFrame }
        globeControl.isHidden = globeSlot == nil

        if engine.placement != lastSaved {
            store.save(engine.placement)
            lastSaved = engine.placement
        }
        scheduleWake(engine.nextWake)
    }

    /// One timer slot, replaced on every reconcile. Correct even if a stale task fires,
    /// because `.tick` is idempotent.
    private func scheduleWake(_ wake: Instant?) {
        guard wake != scheduledWake else { return }
        scheduledWake = wake
        wakeTask?.cancel()
        wakeTask = nil
        guard let wake else { return }
        let delay = max(0, wake.secondsSinceBoot - ProcessInfo.processInfo.systemUptime)
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            // Cleared first: a tick that emits nothing leaves nextWake unchanged, and the
            // reconcile after it must still be allowed to schedule the same deadline again.
            self.scheduledWake = nil
            self.send(.tick(Instant(secondsSinceBoot: ProcessInfo.processInfo.systemUptime)))
        }
    }

    // MARK: Environment

    private func refreshEnvironment() {
        guard let env = measureEnvironment(), env != engine.environment else { return }
        send(.environmentChanged(env))
    }

    /// The only place screen facts are read. Nil until the view has a width.
    ///
    /// `bottomInset` stays 0 in v1. Deriving it from the input view's frame in screen
    /// coordinates feeds the view's own height back into the environment, which would cancel
    /// drags (an environment change cancels the gesture) and could collapse the lift. Measure
    /// the real system-bar height on the device before wiring it.
    private func measureEnvironment() -> Environment? {
        let width = view.bounds.width
        guard width > 0 else { return nil }
        let screen = view.window?.screen
        let density = screen.map {
            PointsPerMillimetre.resolve(nativePixelSize: $0.nativeBounds.size, scale: $0.nativeScale)
        } ?? .duoOuter
        let screenHeight = screen.map { density.millimetres($0.bounds.height) } ?? Surface.duoOuter.screenHeight
        let surface = Surface(width: density.millimetres(width), screenHeight: screenHeight,
                              bottomInset: 0, density: density)
        return Environment(surface: surface, showsGlobeKey: needsInputModeSwitchKey)
    }
}
