import SwiftUI
import AppKit

final class EditorTools: ObservableObject {
    weak var view: NSTextView?

    func perform(_ action: (NSTextView) -> Void) {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
        action(view)
    }

    func find(replace: Bool) {
        perform { text in
            let item = NSMenuItem()
            item.tag = (replace ? NSTextFinder.Action.showReplaceInterface : .showFindInterface).rawValue
            text.performTextFinderAction(item)
        }
    }

    func list(numbered: Bool) {
        perform { view in
            let source = view.string as NSString
            let range = source.lineRange(for: view.selectedRange())
            let lines = source.substring(with: range).components(separatedBy: "\n")
            let replacement = lines.enumerated().map { index, line in
                if line.isEmpty && index == lines.count - 1 && lines.count > 1 { return "" }
                return (numbered ? "\(index + 1). " : "• ") + line
            }.joined(separator: "\n")
            view.insertText(replacement, replacementRange: range)
        }
    }
}

struct EditorToolbar: View {
    let tools: EditorTools

    var body: some View {
        HStack(spacing: 16) {
            action("Undo", "arrow.uturn.backward") { tools.perform { $0.undoManager?.undo() } }
            action("Redo", "arrow.uturn.forward") { tools.perform { $0.undoManager?.redo() } }
            Divider().frame(height: 14)
            action("Bulleted list", "list.bullet") { tools.list(numbered: false) }
            action("Numbered list", "list.number") { tools.list(numbered: true) }
            Menu("Case") {
                Button("Uppercase") { tools.perform { $0.uppercaseWord(nil) } }
                Button("Lowercase") { tools.perform { $0.lowercaseWord(nil) } }
                Button("Title Case") { tools.perform { $0.capitalizeWord(nil) } }
            }.fixedSize().help("Change capitalization")
            Spacer()
            action("Find", "magnifyingglass") { tools.find(replace: false) }
                .keyboardShortcut("f")
            action("Find and replace", "arrow.triangle.2.circlepath") { tools.find(replace: true) }
        }.foregroundStyle(lilac).padding(.horizontal, 20).frame(height: 36)
    }

    private func action(_ label: String, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) { Image(systemName: icon).frame(minWidth: 18, minHeight: 26) }
            .help(label).accessibilityLabel(label)
    }
}

struct TranscriptEditor: NSViewRepresentable {
    let studio: Studio
    let id: UUID
    let text: String
    let tools: EditorTools

    func makeCoordinator() -> Coordinator { Coordinator(studio, id) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let editor = scroll.documentView as! NSTextView
        editor.isRichText = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.font = .systemFont(ofSize: 17)
        editor.textColor = .labelColor
        editor.insertionPointColor = NSColor(sage)
        editor.drawsBackground = false
        scroll.drawsBackground = false
        editor.textContainerInset = NSSize(width: 18, height: 14)
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.string = text
        editor.setAccessibilityLabel("Transcript editor")
        let end = (text as NSString).length
        let range = studio.cursorRanges[id] ?? NSRange(location: end, length: 0)
        let selection = NSIntersectionRange(range, NSRange(location: 0, length: end))
        editor.setSelectedRange(range.location <= end && NSMaxRange(range) <= end ? range : selection)
        editor.delegate = context.coordinator
        tools.view = editor
        DispatchQueue.main.async { [weak editor] in
            guard let editor else { return }
            editor.scrollRangeToVisible(editor.selectedRange())
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        // Typing already updated the native view. Preserve its selection and undo stack.
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let studio: Studio
        let id: UUID
        let undo = UndoManager()

        init(_ studio: Studio, _ id: UUID) {
            self.studio = studio
            self.id = id
        }

        func undoManager(for view: NSTextView) -> UndoManager? { undo }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            studio.editDocument(view.string, id: id)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            studio.cursorRanges[id] = view.selectedRange()
        }
    }
}
