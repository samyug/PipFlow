import Foundation

/// One local decode. Both the preview and the final pass use the selected engine.
enum FileTranscriber {
    static let displayName = "PipFlow 1.2"
    // Keep both the recording and the decoder output inside a private directory.
    static func makeWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pipflow-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        return url
    }

    @discardableResult
    static func run(audio: URL, resources: URL,
                    done: @escaping (Result<String, Error>) -> Void) throws -> Process {
        let process = Process()
        let helpers = resources.deletingLastPathComponent().appendingPathComponent("Helpers")
        let resultURL = audio.deletingPathExtension().appendingPathExtension("txt")
        process.executableURL = helpers.appendingPathComponent("transcribe-cli")
        process.arguments = ["-q", "-m", resources.appendingPathComponent("granite-q8.gguf").path,
                             "--threads", "4", "-o", resultURL.path, audio.path]
        // Never inherit loader overrides or developer-shell credentials.
        process.environment = [:]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { try? FileManager.default.removeItem(at: resultURL) }
            process.waitUntilExit()
            do {
                guard process.terminationStatus == 0 else { throw CocoaError(.fileReadUnknown) }
                let data = try Data(contentsOf: resultURL)
                let text = String(decoding: data, as: UTF8.self)
                    .replacingOccurrences(of: "<|nospeech|>", with: "")
                    .replacingOccurrences(of: "[BLANK_AUDIO]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                done(.success(text))
            } catch { done(.failure(error)) }
        }
        return process
    }
}

/// Call from queue. A single preview worker revises the current phrase; new
/// samples accumulate while it is busy. The final pass uses the original WAV.
final class RollingPreview {
    private let resources: URL
    private let queue: DispatchQueue
    private let publish: (String) -> Void
    private var samples: [Int16] = []
    private var previousCount = 0
    private var committed = ""
    private var worker: Process?
    private var workspace: URL?
    private var stopped = false
    private let interval = 24_000   // 1.5 seconds at 16 kHz
    private let window = 112_000   // seven seconds per committed draft segment

    init(resources: URL, queue: DispatchQueue, publish: @escaping (String) -> Void) {
        self.resources = resources; self.queue = queue; self.publish = publish
    }

    func append(_ pcm: [Int16]) {
        guard !stopped else { return }
        samples.append(contentsOf: pcm)
        // The final recording contains all audio. Keep previews close to live
        // if inference is slower than capture on this machine.
        let backlog = window * 2
        if samples.count > backlog {
            if worker == nil {
                samples.removeFirst(samples.count - backlog)
                previousCount = 0
            } else {
                samples.removeSubrange(window..<(samples.count - window))
            }
        }
        schedule()
    }

    private func schedule() {
        guard !stopped, worker == nil, samples.count - previousCount >= interval else { return }
        let count = min(samples.count, window)
        let committing = count == window
        let chunk = Array(samples.prefix(count))
        previousCount = count
        do {
            let directory = try FileTranscriber.makeWorkspace()
            workspace = directory
            let url = directory.appendingPathComponent("preview.wav")
            var data = PCMRecording.header(bytes: UInt32(count * 2))
            chunk.withUnsafeBytes { data.append(contentsOf: $0) }
            try data.write(to: url, options: .withoutOverwriting)
            worker = try FileTranscriber.run(audio: url, resources: resources) { [weak self] result in
                try? FileManager.default.removeItem(at: directory)
                guard let self else { return }
                self.queue.async {
                    self.worker = nil
                    self.workspace = nil
                    guard !self.stopped else { return }
                    if case let .success(text) = result {
                        let draft = [self.committed, text].filter { !$0.isEmpty }.joined(separator: " ")
                        self.publish(draft)
                        if committing { self.committed = draft }
                    }
                    if committing {
                        self.samples.removeFirst(count)
                        self.previousCount = 0
                    }
                    self.schedule()
                }
            }
        } catch {
            stop()
        }
    }

    func stop() {
        stopped = true
        if worker?.isRunning == true { worker?.terminate() }
        if let workspace { try? FileManager.default.removeItem(at: workspace) }
        workspace = nil
        samples.removeAll()
    }
}
