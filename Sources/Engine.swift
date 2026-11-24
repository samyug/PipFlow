import Cocoa
import AVFoundation
import Carbon

struct Entry: Identifiable, Codable {
    var id = UUID()
    var date = Date()
    var text: String
    var seconds: Double
    var title: String?

    var displayName: String {
        if let title { return title }
        let preview = text.prefix(100).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return preview.isEmpty ? "Untitled transcript" : preview
    }
}
struct Replacement: Identifiable, Codable {
    var id = UUID()
    var spoken: String
    var written: String
}
struct LibraryData: Codable {
    var entries: [Entry] = []
    var rules: [Replacement] = []
}
enum Phase { case idle, permission, recording, working }
final class Studio: NSObject, ObservableObject {
    @Published var spokenFormatting = UserDefaults.standard.object(forKey: "spokenFormatting") as? Bool ?? true {
        didSet { UserDefaults.standard.set(spokenFormatting, forKey: "spokenFormatting") }
    }
    @Published var cleanFillers = UserDefaults.standard.object(forKey: "cleanFillers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(cleanFillers, forKey: "cleanFillers") }
    }
    private var recordingFile: PCMRecording?
    private var recordingURL: URL?
    private var transcriptionProcess: Process?
    @Published var phase = Phase.idle
    @Published var library = LibraryData()
    @Published var message = ""
    let meter = MeterReadings()
    private let meterQueue = DispatchQueue(label: "local.murmur.meter", qos: .userInitiated)
    @Published var elapsed = 0.0
    @Published var shortcutIssue = ""
    @Published var section = "Studio"
    @Published private(set) var documentID = UUID()
    var cursorRanges: [UUID: NSRange] = [:]
    private var recordingDocument = UUID()
    private var pendingEditSave: DispatchWorkItem?

    var currentEntry: Entry? { library.entries.first { $0.id == documentID } }

    func openDocument(_ id: UUID = UUID()) {
        guard phase == .idle else { return }
        documentID = id
        section = "Studio"
    }

    func editDocument(_ text: String, id: UUID) {
        guard phase == .idle, id == documentID else { return }
        if let index = library.entries.firstIndex(where: { $0.id == id }) {
            library.entries[index].text = text
        } else if !text.isEmpty {
            library.entries.insert(Entry(id: id, text: text, seconds: 0), at: 0)
        }
        pendingEditSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingEditSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func renameDocument(_ id: UUID, to name: String) {
        guard let index = library.entries.firstIndex(where: { $0.id == id }) else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        library.entries[index].title = title.isEmpty ? nil : title
        save()
    }

    func deleteDocument(_ id: UUID) {
        guard phase == .idle else { return }
        library.entries.removeAll { $0.id == id }
        cursorRanges[id] = nil
        if documentID == id { documentID = UUID() }
        save()
    }

    func flushEdits() {
        if pendingEditSave != nil { save() }
    }

    static func appending(_ addition: String, to base: String) -> String {
        guard !base.isEmpty, !addition.isEmpty else { return base + addition }
        return base + (base.last?.isWhitespace == true ? "" : "\n") + addition
    }

    var liveText: String {
        Self.appending(partial, to: recordingDocument == documentID ? currentEntry?.text ?? "" : "")
    }
    @Published var copied: UUID?
    @Published var partial = ""
    private var capture: AVAudioEngine?
    private var started = Date()
    private let speechQueue = DispatchQueue(label: "local.murmur.speech", qos: .userInitiated)
    // Access only from speechQueue.
    private var processingID: UUID?
    private var preview: RollingPreview?
    private var target: NSRunningApplication?
    private var targetField: AXUIElement?
    var destinationName: String { target?.localizedName ?? "PipFlow" }
    private var token = UUID()
    private var blockedSave = false
    @Published var externalDictationEnabled = UserDefaults.standard.object(forKey: "externalDictationEnabled") as? Bool ?? true {
        didSet {
            guard oldValue != externalDictationEnabled else { return }
            UserDefaults.standard.set(externalDictationEnabled, forKey: "externalDictationEnabled")
            if !externalDictationEnabled && target != nil { cancel() }
            updateHotkeys()
        }
    }
    private var hotkeys: [EventHotKeyRef] = []
    @Published private(set) var toggleShortcut: ToggleShortcut = {
        guard let data = UserDefaults.standard.data(forKey: "crossAppToggleShortcut"),
              let saved = try? JSONDecoder().decode(ToggleShortcut.self, from: data) else { return .standard }
        return saved
    }()
    private var dictationHotkey: EventHotKeyRef?
    private var holdActive = false
    private let dataURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Murmur/library.json")
    var overlay: Overlay?
    override init() {
        super.init()
        if FileManager.default.fileExists(atPath: dataURL.path) {
            do {
                try prepareLibraryDirectory()
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
                library = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: dataURL))
            }
            catch { blockedSave = true; message = "Your library could not be read. New changes will last for this session." }
        }
        installHotkeyHandler()
        updateHotkeys()
    }

    private var capturingShortcut = false

    func beginShortcutCapture() {
        guard !capturingShortcut else { return }
        if holdActive { cancel() }
        capturingShortcut = true
        if let dictationHotkey { UnregisterEventHotKey(dictationHotkey) }
        dictationHotkey = nil
        for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }
        hotkeys.removeAll()
    }

    func endShortcutCapture() {
        guard capturingShortcut else { return }
        capturingShortcut = false
        updateHotkeys()
    }

    func setToggleShortcut(_ candidate: ToggleShortcut) -> Bool {
        if candidate.code == UInt32(kVK_Space),
           candidate.modifiers == UInt32(controlKey | optionKey) { return false }
        if dictationHotkey != nil && candidate == toggleShortcut { return true }
        var replacement: EventHotKeyRef?
        let status = RegisterEventHotKey(candidate.code, candidate.modifiers,
            EventHotKeyID(signature: 0x4d55524d, id: 3), GetApplicationEventTarget(), 0, &replacement)
        guard status == noErr, let replacement else { return false }
        if let dictationHotkey { UnregisterEventHotKey(dictationHotkey) }
        dictationHotkey = replacement
        toggleShortcut = candidate
        UserDefaults.standard.set(try? JSONEncoder().encode(candidate), forKey: "crossAppToggleShortcut")

        return true
    }
    private func prepareLibraryDirectory() throws {
        let folder = dataURL.deletingLastPathComponent()
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true,
                                  attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
    }

    func save() {
        pendingEditSave?.cancel()
        pendingEditSave = nil
        guard !blockedSave else { return }
        do {
            try prepareLibraryDirectory()
            try JSONEncoder().encode(library).write(to: dataURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        } catch { message = "Your library could not be saved. Check available disk space." }
    }
    func copy(_ item: Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.text, forType: .string)
        copied = item.id
        DispatchQueue.main.asyncAfter(deadline: .now()+2) { if self.copied == item.id { self.copied = nil } }
    }
    func toggle(external: Bool = false) {
        guard !external || externalDictationEnabled else { return }
        switch phase {
        case .idle: start(external)
        case .recording: finish()
        case .permission: cancel()
        case .working: break
        }
    }
    func start(_ external: Bool) {
        guard !external || externalDictationEnabled else { return }
        guard phase == .idle else { return }
        overlay?.hide()
        target = external ? NSWorkspace.shared.frontmostApplication : nil
        if target?.processIdentifier == ProcessInfo.processInfo.processIdentifier { target = nil }
        targetField = target.flatMap { Self.focusedField(in: $0) }
        recordingDocument = external && target != nil ? UUID() : documentID
        let id = UUID()
        token = id
        message = ""
        phase = .permission
        func beginIfAllowed(_ allowed: Bool) {
            guard self.token == id else { return }
            guard allowed else {
                self.cancel()
                self.message = "Allow PipFlow microphone access in System Settings → Privacy & Security → Microphone."
                if external { self.overlay?.showNotice() }
                return
            }
            do {
                try self.startCapture(id: id)
                if external { self.overlay?.show() }
            } catch {
                self.cancel()
                self.message = "Could not open the microphone. Check your input device and try again."
                if external { self.overlay?.showNotice() }
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: beginIfAllowed(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async { beginIfAllowed(allowed) }
            }
        default: beginIfAllowed(false)
        }
    }

    private func startCapture(id: UUID) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate.isFinite, format.sampleRate > 0,
              let resources = Bundle.main.resourceURL,
              let tapFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: format.sampleRate,
                                            channels: format.channelCount, interleaved: false) else {
            throw CocoaError(.fileReadUnknown)
        }
        let spectrum = VoiceSpectrum(sampleRate: format.sampleRate)
        let url = try FileTranscriber.makeWorkspace().appendingPathComponent("recording.wav")
        recordingURL = url
        let writer = try PCMRecording(url: url, rate: format.sampleRate)
        recordingFile = writer
        speechQueue.async {
            self.preview = RollingPreview(resources: resources, queue: self.speechQueue) { [weak self] draft in
                DispatchQueue.main.async {
                    guard let self, self.token == id, self.phase == .recording else { return }
                    self.partial = self.spokenFormatting ? SpokenLayout.format(draft) : draft
                }
            }
            self.processingID = id
        }
        input.installTap(onBus: 0, bufferSize: 2048, format: tapFormat) { [weak self] buffer, _ in
            guard let self, let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
            self.meterQueue.async {
                let levels = spectrum.measure(samples)
                DispatchQueue.main.async {
                    guard self.token == id, self.phase == .recording else { return }
                    self.meter.levels = levels
                    let seconds = floor(Date().timeIntervalSince(self.started))
                    if self.elapsed != seconds { self.elapsed = seconds }
                }
            }
            self.speechQueue.async {
                guard self.processingID == id else { return }
                do {
                    let pcm = try writer.append(samples)
                    self.preview?.append(pcm)
                } catch { self.reportFailure(error, id: id) }
            }
        }
        capture = engine
        engine.prepare()
        try engine.start()
        started = Date()
        elapsed = 0
        partial = ""
        phase = .recording
    }

    private func reportFailure(_ error: Error, id: UUID) {
        processingID = nil
        preview?.stop(); preview = nil
        DispatchQueue.main.async {
            guard self.token == id else { return }
            self.cancel()
            self.message = error.localizedDescription
        }
    }

    private func stopCapture() {
        guard let engine = capture else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        capture = nil
    }

    func cancel() {
        let id = token
        token = UUID()
        stopCapture()
        if transcriptionProcess?.isRunning == true { transcriptionProcess?.terminate() }
        transcriptionProcess = nil
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        }
        recordingURL = nil
        recordingFile = nil
        speechQueue.async {
            if self.processingID == id {
                self.preview?.stop(); self.preview = nil
                self.processingID = nil
            }
        }
        target = nil
        targetField = nil
        phase = .idle
        meter.levels = []
        partial = ""
        holdActive = false
        overlay?.hide()
    }

    func shutDown() {
        flushEdits()
        cancel()
        // Wait for queued preview cleanup before the application exits.
        speechQueue.sync {}
    }

    func finish() {
        guard phase == .recording else { return }
        let duration = Date().timeIntervalSince(started)
        stopCapture()
        guard duration > 0.28 else { cancel(); message = "Recording was too short. Hold the shortcut while you speak."; return }
        phase = .working
        let id = token
        guard let writer = recordingFile else {
            cancel()
            message = "Could not find the recording."
            return
        }
        speechQueue.async {
            guard self.processingID == id else { return }
            do {
                self.preview?.stop(); self.preview = nil
                try writer.close()
                self.processingID = nil
                DispatchQueue.main.async {
                    if self.token == id { self.transcribeFile(id: id, duration: duration) }
                }
            } catch { self.reportFailure(error, id: id) }
        }
    }
    private func transcribeFile(id: UUID, duration: Double) {
        guard let url = recordingURL, let resources = Bundle.main.resourceURL else {
            cancel(); message = "Could not find the recording."; return
        }
        do {
            transcriptionProcess = try FileTranscriber.run(audio: url, resources: resources) { result in
                DispatchQueue.main.async {
                    guard self.token == id else { return }
                    switch result {
                    case .success(let text): self.complete(text, id: id, duration: duration)
                    case .failure: self.cancel(); self.message = "\(FileTranscriber.displayName) could not transcribe this recording."
                    }
                }
            }
        } catch { cancel(); message = "\(FileTranscriber.displayName) could not start." }

    }

    private func complete(_ raw: String, id: UUID, duration: Double) {
        guard token == id else { return }
        let destination = target
        let field = targetField
        let text = Self.format(raw, rules: library.rules, cleanup: cleanFillers, structure: spokenFormatting)
        cancel()
        guard !text.isEmpty else { message = "No speech detected. Check your microphone and try again."; return }
        if let index = library.entries.firstIndex(where: { $0.id == recordingDocument }) {
            library.entries[index].text = Self.appending(text, to: library.entries[index].text)
            library.entries[index].seconds += duration
        } else {
            library.entries.insert(Entry(id: recordingDocument, text: text, seconds: duration), at: 0)
        }
        if destination == nil {
            documentID = recordingDocument
            cursorRanges[documentID] = nil
        }
        if let destination { insert(text, into: destination, expectedField: field) }
        save()
    }

    static func format(_ raw: String, rules: [Replacement], cleanup: Bool, structure: Bool) -> String {
        var text = raw.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !["[BLANK_AUDIO]", "[ Silence ]", "(silence)"].contains($0) }.joined(separator: " ")
        if cleanup {
            text = text.replacingOccurrences(of: #"(?i)(?<![\p{L}\p{N}])(um+|uh+)(?![\p{L}\p{N}])[, ]*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let first = text.first { text = first.uppercased() + String(text.dropFirst()) }
        }
        if structure { text = SpokenLayout.format(text) }
        for rule in rules where !rule.spoken.isEmpty {
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: rule.spoken) + "(?![\\p{L}\\p{N}])"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: NSRegularExpression.escapedTemplate(for: rule.written))
            }
        }
        return text
    }
    private static func focusedField(in app: NSRunningApplication) -> AXUIElement? {
        guard AXIsProcessTrusted() else { return nil }
        var value: CFTypeRef?
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 0.25)
        guard AXUIElementCopyAttributeValue(ax, kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func insert(_ text: String, into app: NSRunningApplication, expectedField: AXUIElement?) {
        func notice(_ description: String) {
            message = description
            overlay?.showNotice()
        }
        func copyForPaste() -> Bool {
            NSPasteboard.general.clearContents()
            return NSPasteboard.general.setString(text, forType: .string)
        }
        guard !app.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            notice("Focus changed. Find your transcript under Transcripts in PipFlow.")
            return
        }
        guard AXIsProcessTrusted() else {
            notice(copyForPaste() ? "Copied. Press ⌘V to paste. Enable PipFlow in Accessibility for automatic insertion." : "Find your transcript under Transcripts in PipFlow.")

            return
        }
        let field = Self.focusedField(in: app)
        if let expectedField, field.map({ CFEqual(expectedField, $0) }) != true {
            notice("The text field changed. Find your transcript under Transcripts in PipFlow.")
            return
        }
        if let field {
            var subrole: CFTypeRef?
            if AXUIElementCopyAttributeValue(field, kAXSubroleAttribute as CFString, &subrole) == .success,
               (subrole as? String) == kAXSecureTextFieldSubrole {
                notice("PipFlow kept the transcript out of the secure text field.")
                return
            }
            if AXUIElementSetAttributeValue(field, kAXSelectedTextAttribute as CFString, text as CFString) == .success { return }
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
            notice("Focus changed. Find your transcript under Transcripts in PipFlow.")
            return
        }
        guard copyForPaste() else {
            notice("Clipboard unavailable. Find your transcript under Transcripts in PipFlow.")
            return
        }
        let source = CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false) else {
            notice("Transcript copied. Press ⌘V to paste.")
            return
        }
        for event in [down, up] {
            event.flags = .maskCommand
            event.postToPid(app.processIdentifier)
        }
        notice("Paste sent to \(app.localizedName ?? "the active app"). Transcript copied.")
    }
    private func installHotkeyHandler() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)), EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            let studio = Unmanaged<Studio>.fromOpaque(context).takeUnretainedValue()
            guard !studio.capturingShortcut else { return noErr }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout.size(ofValue: id), nil, &id)
            let down = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            guard id.signature == 0x4d55524d else { return OSStatus(eventNotHandledErr) }
            guard studio.externalDictationEnabled else { return noErr }
            if id.id == 1 {
                if down && studio.phase == .idle { studio.holdActive = true; studio.start(true) }
                if !down && studio.holdActive {
                    studio.holdActive = false
                    if studio.phase == .permission { studio.cancel() } else { studio.finish() }
                }
            } else if id.id == 3 && !down { studio.toggle(external: true) }
            return noErr
        }, 2, &types, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    private func updateHotkeys() {
        for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }
        hotkeys.removeAll()
        if let dictationHotkey { UnregisterEventHotKey(dictationHotkey) }
        dictationHotkey = nil
        shortcutIssue = ""
        guard externalDictationEnabled, !capturingShortcut else { return }
        if !setToggleShortcut(toggleShortcut) {
            shortcutIssue = "The dictation shortcut is unavailable. Choose another in Settings."
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x4d55524d, id: 1), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { hotkeys.append(ref) }
        else { shortcutIssue += " Hold-to-talk is unavailable. Check your macOS keyboard shortcuts." }
    }
}
