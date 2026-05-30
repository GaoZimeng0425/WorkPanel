import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleCapture = Self(
        "toggleCapture",
        default: .init(.j, modifiers: [.command, .option])
    )
}

@MainActor
enum HotkeyManager {
    static func register(_ handler: @escaping () -> Void) {
        KeyboardShortcuts.onKeyUp(for: .toggleCapture, action: handler)
    }
}
