import UIKit
import KeyboardCore

/// The extension shell. Holds no policy, which lives in the engine.
///
/// `FaceView` has user interaction disabled, so every touch hit-tests to the root `UIInputView`
/// and reaches this controller up the responder chain.
///
/// The extension target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so this type and
/// FaceView are main-actor without annotations.
final class KeyboardViewController: UIInputViewController {

    private let store: PlacementStore
    private var engine: KeyboardEngine
    private var lastSaved: Placement

    private let faceView = FaceView()
    /// Transparent control over the globe key's slot. `handleInputModeList(from:with:)` needs
    /// target-action on `.allTouchEvents` for tap-to-switch and long-press-for-list to work.
    private let globeControl = UIControl()
    private var heightConstraint: NSLayoutConstraint?
    private var wakeTask: Task<Void, Never>?
    private var scheduledWake: Instant?
    /// The system sends no cancel when the keyboard is dismissed, so `viewWillDisappear`
    /// cancels these itself.
    private var liveTouches: Set<TouchID> = []

    // MARK: Lifecycle

    /// Starts on the Duo outer surface. The real environment arrives in viewDidLayoutSubviews
    /// before anything is drawn.
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // The host ignores height requests made before the input view first draws (per an Apple engineer on the developer forums).
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
        // The system sends no cancel on dismissal, and a held backspace would keep deleting.
        let held = liveTouches
        liveTouches = []
        for id in held { send(.touchCancelled(id)) }
        wakeTask?.cancel()
        wakeTask = nil
        scheduledWake = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Width changes on fold, unfold and rotation.
        refreshEnvironment()
        reconcile()
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        // needsInputModeSwitchKey can change between fields and hosts.
        refreshEnvironment()
    }

    // MARK: Touches

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

    /// Idempotent. Every step compares before writing.
    private func reconcile() {
        let layout = engine.layout
        let density = engine.environment.surface.density

        let height = density.points(layout.height)
        if let heightConstraint, heightConstraint.constant != height { heightConstraint.constant = height }

        // Positioned from the view's actual bottom edge, as touches are, so the face and the
        // finger agree while the height constraint catches up.
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

    /// A stale task firing is harmless because `.tick` is idempotent.
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
            // Cleared first, since a tick that emits nothing leaves nextWake unchanged and the
            // reconcile after it must still reschedule that deadline.
            self.scheduledWake = nil
            self.send(.tick(Instant(secondsSinceBoot: ProcessInfo.processInfo.systemUptime)))
        }
    }

    // MARK: Environment

    private func refreshEnvironment() {
        guard let env = measureEnvironment(), env != engine.environment else { return }
        send(.environmentChanged(env))
    }

    /// Nil until the view has a width.
    ///
    /// `bottomInset` stays 0 in v1. Deriving it from the input view's frame in screen
    /// coordinates feeds the view's own height back into the environment, which cancels drags
    /// and could collapse the lift. Measure the real system bar height on a device first.
    private func measureEnvironment() -> Environment? {
        let width = view.bounds.width
        guard width > 0 else { return nil }
        let screen = view.window?.screen
        let density = screen.map {
            PointsPerMillimetre.resolve(nativePixelSize: $0.nativeBounds.size, scale: $0.nativeScale)
        } ?? .duoOuter
        let screenHeight = screen.map { density.millimetres($0.bounds.height) } ?? Surface.duoOuter.screenHeight
        let height = view.bounds.height
        let granted = height > 0 ? density.millimetres(height) : engine.layout.height
        let surface = Surface(width: density.millimetres(width), screenHeight: screenHeight,
                              grantedHeight: granted, bottomInset: 0, density: density)
        return Environment(surface: surface, showsGlobeKey: needsInputModeSwitchKey)
    }
}
