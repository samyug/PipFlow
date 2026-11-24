import SwiftUI

/// Keep wrapped item text aligned with its first word. The stored transcript
/// includes its own markers so copying and insertion also work in plain text.
struct TranscriptView: View {
    let text: String
    var preview = false
    @State private var expanded = false
    var body: some View {
        let lines = text.components(separatedBy: "\n")
        let collapsed = preview && !expanded
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(lines.prefix(collapsed ? 3 : lines.count).enumerated()), id: \.offset) { _, line in
                if line.isEmpty { Color.clear.frame(height: 4) }
                else if let space = line.firstIndex(of: " "), Self.isMarker(line[..<space]) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(line[..<space])).foregroundStyle(muted).monospacedDigit()
                        Text(String(line[line.index(after: space)...])).fixedSize(horizontal: false, vertical: true)
                    }
                } else { Text(line).lineLimit(collapsed ? 3 : nil) }
            }
            if preview && lines.count > 3 {
                Button(expanded ? "Show less" : "Show all \(lines.count - lines.filter(\.isEmpty).count) lines") { expanded.toggle() }
                    .font(.caption).foregroundStyle(muted)
            }
        }.lineSpacing(3).textSelection(.enabled)
    }
    private static func isMarker(_ word: Substring) -> Bool {
        word == "•" || (word.last == "." && Int(word.dropLast()) != nil)
    }
}
