import SwiftUI
import Cocoa

let ink = Color(white: 0.91)
let paper = Color(white: 0.065)
let surface = Color(red: 0.13, green: 0.13, blue: 0.16)
let sage = Color(red: 0.56, green: 0.85, blue: 0.75)
let lilac = Color(red: 0.76, green: 0.71, blue: 0.94)
let amber = Color(red: 0.95, green: 0.74, blue: 0.52)
let muted = Color(white: 0.66)
let edge = Color.white.opacity(0.12)
func serif(_ size: CGFloat) -> Font { .custom("Georgia", size: size) }
func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
func timeLabel(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds)/60, Int(seconds)%60) }

private let panelTransition = AnyTransition.asymmetric(
    insertion: .offset(y: 9).combined(with: .opacity),
    removal: .opacity
)

struct PipButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.74 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

struct TranscribingIndicator: View {

    var body: some View {
        HStack(spacing: 5) {
            Text("Transcribing")
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { timeline in
                dots(phase: timeline.date.timeIntervalSinceReferenceDate * 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Transcribing")
    }

    private func dots(phase: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                let wave = cos(phase - Double(index) * 0.95)
                Circle().fill(lilac).frame(width: 4, height: 4)
                    .opacity(0.7 + 0.3 * wave)
                    .offset(y: -2.4 * wave)
            }
        }
    }
}

struct Mark: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable().aspectRatio(contentMode: .fit).frame(width: 42, height: 42)
            .accessibilityHidden(true)
    }
}
struct StudioView: View {
    @ObservedObject var s: Studio
    @Namespace private var navigation
    @StateObject private var editor = EditorTools()
    @AppStorage("studioSidebarWidth") private var preferredSidebarWidth = 0.0
    @AppStorage("transcriptColumnWidth") private var transcriptWidth = 864.0
    @State private var renaming: Entry?
    @State private var proposedName = ""
    @State private var deleting: Entry?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var spoken = ""
    @State private var written = ""
    @State private var editing = false
    @State private var trusted = AXIsProcessTrusted()
    var body: some View {
        GeometryReader { geometry in
            let total = geometry.size.width
            let limits: ClosedRange<CGFloat> = 172...max(172, min(500, total - 508))
            let preferred = preferredSidebarWidth > 0 ? preferredSidebarWidth : min(260, total * 0.22)
            let sidebar = min(limits.upperBound, max(limits.lowerBound, preferred))
            workspace(sidebarWidth: sidebar, sidebarLimits: limits, columnSpace: max(1, total - sidebar - 58))
        }
        .tint(sage).foregroundStyle(ink).buttonStyle(PipButtonStyle()).frame(minWidth: 790, minHeight: 570)
        .sheet(item: $renaming) { entry in
            VStack(alignment: .leading, spacing: 16) {
                Text("Rename transcript").font(serif(24))
                TextField("Display name", text: $proposedName)
                HStack {
                    Spacer()
                    Button("Cancel") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button("Save") {
                        s.renameDocument(entry.id, to: proposedName)
                        renaming = nil
                    }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 360)
        }
        .alert("Delete transcript?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { entry in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { s.deleteDocument(entry.id) }
        } message: { entry in
            Text("“" + entry.displayName + "” will be permanently deleted.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in trusted = AXIsProcessTrusted() }
    }

    private func clearSearch() {
        query = ""
        searchFocused = false
    }

    private func workspace(sidebarWidth: CGFloat, sidebarLimits: ClosedRange<CGFloat>, columnSpace: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading,spacing: 0) {
                HStack(spacing: 10) { Mark(); Text("PipFlow").font(serif(24)).lineLimit(1).minimumScaleFactor(0.8) }.padding(.bottom,10)
                Button { clearSearch(); s.openDocument() } label: {
                    Label { Text("New chat") } icon: { Image(systemName: "square.and.pencil").foregroundStyle(sage) }.fontWeight(.medium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).frame(height: 32)
                        .contentShape(Rectangle())
                }.help("Start a new transcript (⌘N)").keyboardShortcut("n").disabled(s.phase != .idle)
                    .padding(.bottom, 10)
                navButton("Dictionary","character.book.closed")
                navButton("Settings","slider.horizontal.3")
                navButton("Help","questionmark.circle")
                Divider().padding(.vertical, 14)
                Text("Transcripts").font(.caption).foregroundStyle(muted)
                    .padding(.horizontal, 10)
                if !s.library.entries.isEmpty {
                    HStack(spacing: 4) {
                        TextField("Search transcripts", text: $query)
                            .focused($searchFocused)
                            .onExitCommand { clearSearch() }
                            .onSubmit { searchFocused = false }
                        if !query.isEmpty {
                            Button { clearSearch() } label: { Image(systemName: "xmark.circle.fill") }
                                .accessibilityLabel("Clear transcript search")
                        }
                    }.textFieldStyle(.roundedBorder).padding(.top, 6)
                }
                let items = s.library.entries.filter {
                    query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) ||
                        $0.title?.localizedCaseInsensitiveContains(query) == true
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        if items.isEmpty && !query.isEmpty && !s.library.entries.isEmpty {
                            Text("No matching transcripts").font(.caption).foregroundStyle(muted)
                        }
                        ForEach(items) { entry in
                            HStack(spacing: 0) {
                                Button { clearSearch(); s.openDocument(entry.id) } label: {
                                    Text(entry.displayName)
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 10).padding(.vertical, 8)
                                        .contentShape(Rectangle())
                                }
                                Button { deleting = entry } label: {
                                    Image(systemName: "trash").font(.system(size: 11))
                                        .foregroundStyle(muted).frame(width: 28, height: 30)
                                        .contentShape(Rectangle())
                                }.accessibilityLabel("Delete " + entry.displayName)
                                    .help("Delete transcript")
                            }
                            .background(s.section == "Studio" && s.phase == .idle && s.documentID == entry.id ? lilac.opacity(0.13) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .disabled(s.phase != .idle)
                            .contextMenu { transcriptActions(entry) }
                        }
                    }
                }.padding(.vertical, 8)
            }.padding(.horizontal,16).padding(.top,8).padding(.bottom,24).frame(width: sidebarWidth).background(Color(white: 0.085))
            ResizeHandle(label: "Resize transcripts sidebar", width: sidebarWidth, limits: sidebarLimits) {
                preferredSidebarWidth = $0
            }.background(paper)
            VStack(alignment: .leading, spacing: 0) {
                if !s.message.isEmpty {
                    HStack {
                        Text(s.message).font(.callout)
                        Spacer()
                        Button { s.message = "" } label: { Image(systemName: "xmark") }.help("Dismiss")
                    }.padding(12).background(surface)
                }
                if !s.shortcutIssue.isEmpty { Text(s.shortcutIssue).font(.callout).foregroundStyle(muted).padding(12) }
                ZStack(alignment: .topLeading) {
                    if s.section == "Studio" {
                        adjustableColumn(space: columnSpace, preferred: $transcriptWidth, label: "Resize transcript") { studio }
                            .transition(panelTransition)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                Text(s.section).font(serif(32))
                                switch s.section {
                                case "Dictionary": dictionary
                                case "Help": helpPage
                                default: settings
                                }
                            }.frame(maxWidth: 864, alignment: .leading).padding(24).frame(maxWidth: .infinity)
                        }.id(s.section).transition(panelTransition)
                    }
                }.clipped().animation(.easeOut(duration: 0.24), value: s.section)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(paper)
        }
    }
    private func adjustableColumn<Content: View>(space: CGFloat, preferred: Binding<Double>, label: String,
                                                  @ViewBuilder content: () -> Content) -> some View {
        let limits = min(420, space)...space
        let width = min(space, max(limits.lowerBound, preferred.wrappedValue))
        return content()
            .frame(width: width)
            .overlay(alignment: .trailing) {
                ResizeHandle(label: label, width: width, limits: limits, multiplier: 2) {
                    preferred.wrappedValue = $0
                }.offset(x: 10)
            }
            .padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func navButton(_ name: String,_ icon: String) -> some View {
        Button { clearSearch(); s.section = name } label: {
            HStack(spacing: 11) { Image(systemName: icon).foregroundStyle(s.section == name ? lilac : muted).frame(width: 19); Text(name).fontWeight(s.section == name ? .semibold : .regular); Spacer() }
                .padding(.horizontal,12).frame(height: 37).background {
                    if s.section == name {
                        RoundedRectangle(cornerRadius: 8).fill(lilac.opacity(0.13))
                            .matchedGeometryEffect(id: "selection", in: navigation)
                    }
                }.contentShape(Rectangle())
        }.padding(.bottom,4).animation(.spring(response: 0.3, dampingFraction: 0.86), value: s.section)
    }
    var studio: some View {
        let saved = s.currentEntry
        let content = s.phase == .idle ? saved?.text ?? "" : s.liveText
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(s.phase == .recording ? "Live transcript" : saved == nil && s.phase == .idle ? "New transcript" : (saved?.title ?? "Transcript")).font(serif(25)).foregroundStyle(s.phase == .recording ? amber : ink).lineLimit(1).truncationMode(.tail)
                    Spacer()
                    if let saved, s.phase == .idle {
                        Text(saved.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(muted)
                        Button { s.copy(saved) } label: {
                            Image(systemName: s.copied == saved.id ? "checkmark" : "doc.on.doc").foregroundStyle(s.copied == saved.id ? sage : muted)
                        }.help("Copy transcript")
                    }
                }.padding(20)
                Divider()
                if s.phase == .idle {
                    EditorToolbar(tools: editor)
                    Divider()
                    ZStack(alignment: .topLeading) {
                        TranscriptEditor(studio: s, id: s.documentID, text: content, tools: editor)
                            .id(s.documentID).transition(panelTransition)
                        if content.isEmpty {
                            Text("Type here or start dictating…").foregroundStyle(muted)
                                .padding(.horizontal, 23).padding(.vertical, 16).allowsHitTesting(false)
                        }
                    }.clipped().animation(.easeOut(duration: 0.2), value: s.documentID)
                } else {
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if content.isEmpty {
                                Text(transcriptPlaceholder).foregroundStyle(muted)
                            } else {
                                TranscriptView(text: content).font(.system(size: 17)).lineSpacing(5)
                            }
                            Color.clear.frame(height: 1).id("tail")
                        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onAppear { reader.scrollTo("tail", anchor: .bottom) }
                    .onChange(of: s.partial) { _ in
                        if s.phase == .recording {
                            withAnimation(.easeOut(duration: 0.18)) {
                                reader.scrollTo("tail", anchor: .bottom)
                            }
                        }
                    }
                }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(white: 0.083), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(edge))
            .animation(.easeInOut(duration: 0.22), value: s.phase)
            HStack(spacing: 12) {
                Text(FileTranscriber.displayName).font(.callout.weight(.medium)).foregroundStyle(lilac)
                Spacer()
                VoiceMeter(readings: s.meter)
                if s.phase == .recording { Text(timeLabel(s.elapsed)).font(mono(12)).foregroundStyle(amber) }
                if s.phase == .recording || s.phase == .working { Button("Discard") { s.cancel() }.foregroundStyle(muted) }
                if s.phase == .working { TranscribingIndicator().font(.callout) }
                else {
                    Button { s.toggle() } label: {
                        Label(s.phase == .recording ? "Finish" : s.phase == .permission ? "Cancel" : "Start",
                              systemImage: s.phase == .recording ? "stop.fill" : s.phase == .permission ? "xmark" : "mic.fill")
                            .font(.system(size: 13, weight: .semibold)).padding(.horizontal, 15).frame(height: 32)
                            .foregroundStyle(paper).background(s.phase == .recording ? amber : sage, in: Capsule())
                    }.help("Hold Control–Option–Space to dictate")
                }
            }.frame(height: 32)
                .animation(.spring(response: 0.32, dampingFraction: 0.84), value: s.phase)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var transcriptPlaceholder: String {
        switch s.phase {
        case .idle: return "Start a dictation to see your transcript here."
        case .permission: return "Opening microphone…"
        case .working: return "Finishing your transcript…"
        case .recording: return "Listening…"
        }
    }

    func empty(_ icon: String,_ title: String,_ detail: String) -> some View {
        VStack(spacing: 9) { Image(systemName: icon).font(.title3).foregroundStyle(sage); Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(muted).multilineTextAlignment(.center) }.frame(maxWidth: .infinity).padding(.vertical,23).overlay(RoundedRectangle(cornerRadius: 12).stroke(edge))
    }
    @ViewBuilder
    private func transcriptActions(_ entry: Entry) -> some View {
        Button("Open") { s.openDocument(entry.id) }.disabled(s.phase != .idle)
        Button("Rename…") {
            proposedName = entry.displayName
            renaming = entry
        }
        Button("Copy transcript") { s.copy(entry) }
        Divider()
        Button("Delete…", role: .destructive) { deleting = entry }.disabled(s.phase != .idle)
    }

    var dictionary: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Give names a preferred spelling, or expand a spoken shortcut into a longer phrase.").foregroundStyle(muted)
            Button { editing = true } label: { Label("Add phrase",systemImage: "plus").padding(10).foregroundStyle(paper).background(sage,in: Capsule()) }
            if s.library.rules.isEmpty { empty("character.book.closed","No phrases yet","Add a spoken phrase and the text you want PipFlow to write.") }
            ForEach(s.library.rules) { rule in HStack { VStack(alignment: .leading) { Text(rule.spoken).font(.caption).foregroundStyle(muted); Text(rule.written).textSelection(.enabled) }; Spacer(); Button { s.library.rules.removeAll { $0.id == rule.id }; s.save() } label: { Image(systemName: "trash") }.help("Delete phrase") }; Divider() }
        }.sheet(isPresented: $editing) {
            VStack(alignment: .leading, spacing: 14) {
                Text("New phrase").font(serif(26)); TextField("Spoken phrase",text: $spoken); TextField("Write this instead",text: $written)
                HStack { Spacer(); Button("Cancel") { editing = false }; Button("Save phrase") { s.library.rules.append(Replacement(spoken: spoken.trimmingCharacters(in: .whitespacesAndNewlines), written: written.trimmingCharacters(in: .whitespacesAndNewlines))); s.save(); editing = false }.keyboardShortcut(.defaultAction).disabled(spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || written.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || s.library.rules.contains { $0.spoken.caseInsensitiveCompare(spoken.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }) }
            }.padding(25).frame(width: 370)
        }.onChange(of: editing) { if !$0 { spoken = ""; written = "" } }
    }
    private func faq(_ question: String, _ answer: String) -> some View {
        DisclosureGroup {
            Text(answer).font(.callout).foregroundStyle(muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled).padding(.vertical, 6)
        } label: {
            Text(question).fixedSize(horizontal: false, vertical: true)
        }
    }

    var settings: some View {
        VStack(alignment: .leading,spacing: 18) {
            Toggle("Format spoken lists and paragraphs", isOn: $s.spokenFormatting).toggleStyle(.switch).tint(sage)
                .disabled(s.phase != .idle)
            DisclosureGroup("Dictation examples") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bullets · “Bullet point, review the draft. Next bullet, send feedback.”")
                    Text("Numbers · “First, review the draft. Second, send feedback.”")
                    Text("Natural lists · “Shopping list: apples, oats, and milk.”")
                    Text("Breaks · Say “new line” or “new paragraph.” Say “end list” to return to prose.")
                }.font(.callout).foregroundStyle(muted).padding(.vertical, 6)
            }
            Toggle("Remove common filler sounds (um, uh)", isOn: $s.cleanFillers).toggleStyle(.switch).tint(sage)
            Divider(); Text("Dictate into other apps").font(serif(23))
            Toggle("Enable dictation in other apps", isOn: $s.externalDictationEnabled)
                .toggleStyle(.switch).tint(sage).disabled(s.phase != .idle)
            ToggleShortcutControl(studio: s).disabled(s.phase != .idle)
            Text("Accessibility access: " + (trusted ? "Enabled" : "Required for insertion")).font(.headline)
            Button("Open Accessibility settings ↗") {
                let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
                NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
            Text("In apps that require paste, PipFlow puts the transcript on your clipboard.").font(.caption).foregroundStyle(muted)
        }
    }

    private var helpPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Frequently asked questions").font(.headline)
            faq("How do I dictate into another app?",
                "Leave PipFlow running and click where you want to type, for example in a Mail draft. Hold Control–Option–Space (⌃⌥Space) while you speak. Release the keys and keep that app focused while PipFlow finishes and inserts the text.")
            faq("Can I dictate without holding the keys?",
                "Press \(s.toggleShortcut.label) once to start. Speak, then press the same shortcut again to finish.")
            faq("Why didn’t my words appear at the cursor?",
                "Control-click your transcript in the sidebar and choose Copy transcript. For the next dictation, choose Settings in the sidebar, click Open Accessibility settings, enable PipFlow, and click an editable field in the destination app. Keep that app in front until insertion finishes.")
            faq("What if the shortcut or microphone doesn’t work?",
                "Open New chat and click Start. If recording works there, check whether another app or a macOS keyboard shortcut uses the same keys. If PipFlow can’t hear you, enable PipFlow under System Settings → Privacy & Security → Microphone and check the input under Sound.")
            faq("Can I dictate offline?",
                "Yes. PipFlow 1.2 transcribes English on your Mac, shows a live draft as you speak, and processes the full recording when you finish.")
            faq("How do I continue a transcript or start a new one?",
                "Open a transcript from the Transcripts sidebar, then click Start to add more at the end. You can also type directly into the editor. For a blank transcript, click New chat or press Command–N (⌘N).")
            faq("How do I rename, copy, or delete a transcript?",
                "Click the trash button beside a transcript to delete it. To rename or copy it, two-finger click or Control-click its name.")
        }
    }
}
