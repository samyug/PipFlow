import Foundation

/// Streams mono samples into a 16 kHz PCM WAV, keeping filter history between taps.
final class PCMRecording {
    private let file: FileHandle
    private let step: Double
    private let filters: [[Float]]
    private var input = [Float](repeating: 0, count: 15)
    private var position = 15.0
    private var sampleCount: UInt32 = 0
    private var closed = false

    init(url: URL, rate: Double) throws {
        step = rate / 16000
        let cutoff = min(1, 16000 / rate) * 0.94
        filters = (0..<128).map { phase in
            let taps: [Float] = (0..<32).map { i in
                let t = Double(i - 15) - Double(phase) / 128
                let sinc = abs(t) < 1e-9 ? cutoff : sin(.pi * cutoff * t) / (.pi * t)
                return Float(sinc * (0.5 + 0.5 * cos(.pi * t / 16)))
            }
            let sum = taps.reduce(0, +)
            return taps.map { $0 / sum }
        }
        try Data(repeating: 0, count: 44).write(to: url, options: .withoutOverwriting)
        file = try FileHandle(forWritingTo: url)
        try file.seekToEnd()
    }

    @discardableResult
    func append(_ samples: [Float]) throws -> [Int16] {
        input.append(contentsOf: samples)
        var pcm: [Int16] = []
        pcm.reserveCapacity(Int(Double(samples.count) / step) + 1)
        while Int(position) + 16 < input.count {
            let center = Int(position)
            let filter = filters[Int((position - Double(center)) * 128)]
            var value: Float = 0
            for i in 0..<32 { value += input[center - 15 + i] * filter[i] }
            pcm.append(Int16(max(-32768, min(32767, (value.isFinite ? value : 0) * 32768))).littleEndian)
            position += step
        }
        let consumed = min(input.count, max(0, Int(position) - 15))
        input.removeFirst(consumed)
        position -= Double(consumed)
        guard pcm.count <= Int((UInt32.max - 36) / 2 - sampleCount) else { throw CocoaError(.fileWriteOutOfSpace) }
        try pcm.withUnsafeBytes { try file.write(contentsOf: Data($0)) }
        sampleCount += UInt32(pcm.count)
        return pcm
    }

    func close() throws {
        guard !closed else { return }
        closed = true
        defer { try? file.close() }
        try append([Float](repeating: 0, count: 16))
        try file.seek(toOffset: 0)
        try file.write(contentsOf: Self.header(bytes: sampleCount * 2))
    }

    static func header(bytes: UInt32) -> Data {
        var header = Data()
        func tag(_ s: String) { header.append(contentsOf: s.utf8) }
        func number<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        tag("RIFF"); number(bytes + 36); tag("WAVE"); tag("fmt "); number(UInt32(16))
        number(UInt16(1)); number(UInt16(1)); number(UInt32(16000)); number(UInt32(32000))
        number(UInt16(2)); number(UInt16(16)); tag("data"); number(bytes)
        return header
    }
}
