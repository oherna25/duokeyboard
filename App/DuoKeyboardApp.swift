import SwiftUI

/// The containing app. It exists to (1) ship the extension and (2) let the person enable and try
/// it. It does not link KeyboardCore: nothing here needs geometry or input state, and no data is
/// shared with the extension in v1 (no App Group).
@main
struct DuoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

/// Numbered steps, a button to Settings, and a field to type in.
struct SetupView: View {
    @State private var trial = ""
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section("Turn it on") {
                Text("1. Open Settings > General > Keyboard > Keyboards.")
                Text("2. Tap Add New Keyboard and choose Duo Keyboard.")
                Text("3. In any text field, hold the globe key and pick Duo Keyboard.")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Section("Try it") {
                TextField("Type here", text: $trial, axis: .vertical)
            }
            Section("Move it") {
                Text("Drag the bar above the keys to move them sideways or up. Tap the arrows at the end of the bar to switch hands. Double-tap the bar to reset.")
            }
        }
    }
}
