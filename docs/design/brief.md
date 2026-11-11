# DuoKeyboard v1 brief

## Goal

Ship the first working build of a one-handed iOS keyboard for the iPhone Duo's outer screen. A person installs the app, enables the keyboard in Settings, and types with one thumb in any app. The keyboard is the "Slide to thumb" layout from the prototype: a compact QWERTY docked toward the thumb, which the person can drag sideways and up, and flip to the other hand.

## In scope for v1

- Containing app (SwiftUI). It explains how to enable the keyboard and has a text field for trying it.
- Keyboard extension (`UIInputViewController`). It contains:
  - Letters layer and numbers/symbols layer.
  - Shift (one-shot) and caps lock (double-tap shift).
  - Backspace that repeats while held.
  - Space, return, and the layer toggle.
  - The next-keyboard (globe) key, shown only when `needsInputModeSwitchKey` is true. It uses `handleInputModeList(from:with:)`.
  - A drag handle that moves the keyboard sideways and up. The position persists across launches. Flipping the hand mirrors the docking side.
- A pure Swift core that holds geometry, key hit-testing, and the input state transitions. It has unit tests that run on the macOS host with `swift test`.

## Out of scope for v1

- Autocorrect, prediction, emoji, swipe typing, haptics, Full Access, and syncing settings between app and extension through an App Group.

## Known facts

- Outer screen: 466 × 678 pt, 6.04 pt per mm (1398 × 2034 px at 460 ppi, @3x). Inner screen in the simulator: 951 × 669 pt.
- Prototype: `prototype/index.html`. Its `gridLayout` and the "Slide to thumb" defaults are the reference geometry.
  - Width 59 mm (356 pt). The prototype adds a fixed 2 mm side margin and 4 mm bottom margin under its sliders, so the keyboard sits 9 mm (2 + 7) in from the hand-side edge and 13 mm (4 + 9) up from the bottom.
  - Unit = width / 10. Row height = min(unit × 1.38, 11.5 mm). Horizontal gap = max(0.8 mm, unit × 0.12). Vertical gap = max(1 mm, rowH × 0.16).
  - Rows: `qwertyuiop`, `asdfghjkl` (centred), shift 1.5u + `zxcvbnm` + backspace 1.5u, then 123 2.5u + space 5u + return 2.5u. When the globe key is needed, the bottom row adds it and shrinks space.
  - The reach model (thumb pivot 6 mm outside the hand-side edge, 32 mm up, 72 mm reach, 20 mm minimum) puts all 31 keys in reach at these defaults. Docked at the 2 mm margin with no lift, 5 keys fall outside.
- Physical size must stay constant across screens. A thumb is the same size on the inner and outer screen, so lay out in points derived from millimetres, not as a fraction of screen width.
- Keyboard extensions:
  - Set the keyboard height with a height constraint on the input view.
  - Extensions get a memory limit of tens of MB, so stay light.
  - Without Full Access an extension can still use its own `UserDefaults.standard`.
  - `textDocumentProxy` does the text operations: `insertText`, `deleteBackward`.
  - Taps that land in the gap between keys must still hit a key. Use nearest-key hit-testing, not strict rects.

## Toolchain

- Xcode 27.1, iOS SDK 27.1, Swift 6.4, and XcodeGen 2.46 are installed. The iPhone Duo simulator (iOS 27.2) is booted. Tuist is not installed.
- The project is generated from a checked-in `project.yml`. The generated `.xcodeproj` is gitignored.
- Bundle IDs: `com.oherna25.duokeyboard` (app) and `com.oherna25.duokeyboard.keyboard` (extension).

## Repo layout today

- `prototype/index.html` is the throwaway HTML prototype. Keep it.
- `scripts/build-site.sh` and `.github/workflows/pages.yml` deploy the prototype to GitHub Pages. Keep them.
