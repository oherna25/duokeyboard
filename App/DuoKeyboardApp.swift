import SwiftUI

/// Ships the extension and lets the person enable and try it. Does not link KeyboardCore, and
/// shares no data with the extension in v1 (no App Group).
@main
struct DuoKeyboardApp: App {
    var body: some Scene {
        WindowGroup { SetupView() }
    }
}

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
                Text("Drag the bar above the keys to move them sideways or up. Drag the grip at the far end of the bar to make the keys narrower or wider. Tap the arrows beside it to switch hands. Double-tap the bar to reset.")
            }
        }
    }
}
