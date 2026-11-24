import SwiftUI
import Accelerate

/// Measure log-spaced speech bands on the meter queue using a Hann window.
final class VoiceSpectrum {
    static let count = 18
    private let windowLength: Int
    private let kernels: [(real: [Float], imaginary: [Float])]
    private var history: [Float] = []
    private var envelope = Array(repeating: 0.0, count: count)

    init(sampleRate: Double) {
        let n = max(128, Int(sampleRate * 0.05))
        windowLength = n
        let window = (0..<n).map { 0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(n - 1)) }
        kernels = (0..<Self.count).map { i in
            let hz = 80 * pow(min(3600, sampleRate * 0.45) / 80, Double(i) / Double(Self.count - 1))
            let step = 2 * Double.pi * hz / sampleRate
            return (window.indices.map { Float(window[$0] * cos(step * Double($0))) },
                    window.indices.map { Float(window[$0] * sin(step * Double($0))) })
        }
    }

    func measure(_ samples: [Float]) -> [Double] {
        history.append(contentsOf: samples)
        if history.count > windowLength { history.removeFirst(history.count - windowLength) }
        guard !history.isEmpty else { return envelope }
        for (i, kernel) in kernels.enumerated() {
            var real: Float = 0
            var imaginary: Float = 0
            vDSP_dotpr(history, 1, kernel.real, 1, &real, vDSP_Length(history.count))
            vDSP_dotpr(history, 1, kernel.imaginary, 1, &imaginary, vDSP_Length(history.count))
            let power = Double(real * real + imaginary * imaginary)
            let db = 20 * log10(max(0.000001, 4 * sqrt(power) / Double(windowLength)))
            let target = min(1, max(0, (db + 65) / 65))
            envelope[i] += (target - envelope[i]) * (target > envelope[i] ? 0.85 : 0.34)
        }
        return envelope
    }
}

final class MeterReadings: ObservableObject {
    @Published var levels: [Double] = []
}

struct VoiceMeter: View {
    @ObservedObject var readings: MeterReadings
    var body: some View {
        Canvas { context, size in
            let stride = size.width / CGFloat(VoiceSpectrum.count)
            for i in 0..<VoiceSpectrum.count {
                let value = readings.levels.indices.contains(i) ? readings.levels[i] : 0
                let height = 3 + (size.height - 3) * value
                let rect = CGRect(x: CGFloat(i) * stride, y: (size.height - height) / 2,
                                  width: stride * 0.65, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(amber.opacity(0.38 + 0.62 * value)))
            }
        }.frame(idealWidth: 86, maxWidth: 86, minHeight: 23, maxHeight: 23).accessibilityHidden(true)
    }
}
