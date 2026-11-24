import Cocoa
import Carbon
import SwiftUI

struct ToggleShortcut: Codable, Equatable {
    let code: UInt32
    let modifiers: UInt32
    let label: String

    static let standard = ToggleShortcut(code: UInt32(kVK_Space),
        modifiers: UInt32(controlKey | optionKey | shiftKey), label: "⌃⌥⇧Space")

    init(code: UInt32, modifiers: UInt32, label: String) {
        self.code = code
        self.modifiers = modifiers
        self.label = label
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        let named: [Int: String] = [kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_Delete: "Delete", kVK_ForwardDelete: "⌦", kVK_Home: "Home", kVK_End: "End"]
        let functions = [kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,kVK_F11,kVK_F12,kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
        let key: String
        if let index = functions.firstIndex(of: Int(event.keyCode)) {
            key = "F" + String(index + 1)
        } else {
            if let name = named[Int(event.keyCode)] { key = name }
            else if let text = (event.characters(byApplyingModifiers: []) ?? event.charactersIgnoringModifiers), text.count == 1,
                    text.unicodeScalars.allSatisfy(CharacterSet.controlCharacters.inverted.contains) {
                key = text.uppercased()
            } else { return nil }
        }
        var mods: UInt32 = 0
        var symbols = ""
        for (flag, mask, symbol): (NSEvent.ModifierFlags, Int, String) in
            [(.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] where flags.contains(flag) {
            mods |= UInt32(mask)
            symbols += symbol
        }
        self.init(code: UInt32(event.keyCode), modifiers: mods, label: symbols + key)
    }
}

final class ShortcutCaptureButton: NSButton {
    var begin: () -> Void = {}
    var end: () -> Void = {}
    var save: (ToggleShortcut) -> Bool = { _ in false }
    var savedLabel = ""
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(arm)
        setAccessibilityLabel("Choose dictation shortcut")
    }
    required init?(coder: NSCoder) { fatalError("Programmatic control") }

    @objc private func arm() {
        if recording { finish(); return }
        guard window?.makeFirstResponder(self) == true else { return }
        recording = true
        title = "Press your keys…"
        begin()
        NotificationCenter.default.addObserver(self, selector: #selector(finish),
            name: NSWindow.didResignKeyNotification, object: window)
    }

    @objc func finish() {
        guard recording else { return }
        recording = false
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        title = savedLabel
        end()
    }

    override func resignFirstResponder() -> Bool {
        finish()
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { super.flagsChanged(with: event); return }
        let flags = event.modifierFlags
        let labels: [(NSEvent.ModifierFlags, String)] = [(.control,"⌃"), (.option,"⌥"), (.shift,"⇧"), (.command,"⌘")]
        title = labels.filter { flags.contains($0.0) }.map { $0.1 }.joined() + "…"
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self, event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        guard !event.isARepeat else { return }
        if event.keyCode == UInt16(kVK_Escape) { finish(); return }
        guard let candidate = ToggleShortcut(event: event) else {
            title = "Press a key with the modifiers"
            return
        }
        if save(candidate) {
            savedLabel = candidate.label
            finish()
        } else {
            title = "Unavailable · Try again"
        }
    }
}

private struct ShortcutField: NSViewRepresentable {
    @ObservedObject var studio: Studio
    @Environment(\.isEnabled) private var enabled

    func makeNSView(context: Context) -> ShortcutCaptureButton {
        let button = ShortcutCaptureButton(frame: .zero)
        button.begin = studio.beginShortcutCapture
        button.end = studio.endShortcutCapture
        button.save = studio.setToggleShortcut
        return button
    }
    func updateNSView(_ button: ShortcutCaptureButton, context: Context) {
        button.isEnabled = enabled
        if !enabled { button.finish() }
        button.savedLabel = studio.toggleShortcut.label
        if !button.recording { button.title = button.savedLabel }
    }
    static func dismantleNSView(_ button: ShortcutCaptureButton, coordinator: ()) { button.finish() }
}

struct ToggleShortcutControl: View {
    @ObservedObject var studio: Studio
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Dictation shortcut")
                ShortcutField(studio: studio).frame(width: 200, height: 28)
            }
            Text("Press once to start dictating at your cursor. Press again to finish. Click the shortcut to change it.")
                .font(.caption).foregroundStyle(muted)
        }
    }
}
