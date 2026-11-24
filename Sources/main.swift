import Cocoa
import SwiftUI

private final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class Overlay {
    private let panel: NSPanel
    private var dismissal: DispatchWorkItem?
    init(_ studio: Studio) {
        panel = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: 370, height: 74),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: Bubble(s: studio).preferredColorScheme(.dark))
    }
    func show() {
        dismissal?.cancel()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 22))
        }
        panel.orderFrontRegardless()
    }
    func showNotice() {
        show()
        let work = DispatchWorkItem { [weak self] in self?.panel.orderOut(nil) }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
    func hide() {
        dismissal?.cancel()
        panel.orderOut(nil)
    }
}

struct Bubble: View {
    @ObservedObject var s: Studio
    var body: some View {
        HStack(spacing: 12) {
            if s.phase == .recording {
                VoiceMeter(readings: s.meter).frame(width: 44)
            } else if s.phase == .working {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "info.circle").foregroundStyle(amber)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(s.phase == .idle ? s.message : s.phase == .working ? "Transcribing…" : "Listening")
                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
                if s.phase == .recording || s.phase == .working {
                    Text(s.partial.isEmpty ? s.destinationName : s.partial)
                        .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            if s.phase == .recording {
                Button { s.finish() } label: { Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(amber) }
                    .accessibilityLabel("Finish dictation")
            }
            Button { if s.phase == .idle { s.overlay?.hide() } else { s.cancel() } } label: {
                Image(systemName: "xmark").frame(width: 22, height: 26)
            }.accessibilityLabel(s.phase == .idle ? "Dismiss" : "Discard dictation")
        }
        .buttonStyle(.plain).padding(.horizontal, 16).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.105), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).strokeBorder(.white.opacity(0.16)))
        .padding(4).animation(.easeOut(duration: 0.16), value: s.phase)
    }
}
final class Delegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    var studio: Studio!
    var window: NSWindow!
    var status: NSStatusItem!
    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        studio = Studio()
        studio.overlay = Overlay(studio)
        window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 940,height: 640),styleMask: [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing: .buffered,defer: false)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 790, height: 570)
        window.title = "PipFlow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: StudioView(s: studio).preferredColorScheme(.dark))
        window.center()
        window.setFrameAutosaveName("MurmurStudioWindow")
        let bar = NSMenu()
        let appItem = bar.addItem(withTitle: "PipFlow",action: nil,keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit PipFlow",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "q")
        appItem.submenu = appMenu
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        for (title,selector,key) in [("Cut","cut:","x"),("Copy","copy:","c"),("Paste","paste:","v"),("Select All","selectAll:","a")] {
            edit.addItem(withTitle: title,action: NSSelectorFromString(selector),keyEquivalent: key)
        }
        bar.addItem(withTitle: "Edit",action: nil,keyEquivalent: "").submenu = edit
        let viewMenu = NSMenu(title: "View")
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        fullScreen.target = window
        bar.addItem(withTitle: "View", action: nil, keyEquivalent: "").submenu = viewMenu
        NSApp.mainMenu = bar
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource: "PipMenu", withExtension: "svg"),
           let mark = NSImage(contentsOf: url) {
            mark.size = NSSize(width: 22, height: 16)
            mark.isTemplate = true
            status.button?.image = mark
        }
        status.button?.setAccessibilityLabel("PipFlow dictation")
        let menu = NSMenu()
        menu.addItem(withTitle: "Open PipFlow",action: #selector(show),keyEquivalent: "").target = self
        menu.addItem(withTitle: "Toggle hands-free dictation",action: #selector(record),keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PipFlow",action: #selector(NSApplication.terminate(_:)),keyEquivalent: "")
        status.menu = menu
        show()
    }
    @objc func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(record) || studio.externalDictationEnabled
    }
    @objc func record() { studio.toggle(external: true) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationWillTerminate(_ note: Notification) { studio?.shutDown() }
}
let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
