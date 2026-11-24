import Foundation

/// Convert recognized English dictation cues before applying personal dictionary rules.
enum SpokenLayout {
    private static let markers = try! NSRegularExpression(pattern:
        #"(?i)\b(?:next bullet(?: point)?|bullet point|new bullet|next item|end (?:the )?list|new paragraph|new line|(?:number|point|step) (?:one|two|three|four|five|six|seven|eight|nine|ten)|first(?:ly)?|second(?:ly)?|third(?:ly)?|fourth|fifth|sixth|seventh|eighth|ninth|tenth|one|two|three|four|five|six|seven|eight|nine|ten|[1-9]|10)\b"#)
    private static let numbers = ["one","two","three","four","five","six","seven","eight","nine","ten"]
    private static let ordinals = ["first","second","third","fourth","fifth","sixth","seventh","eighth","ninth","tenth"]
    private static let intro = try! NSRegularExpression(pattern:
        #"(?i)^(.*?\b(?:shopping list|grocery list|to[- ]do list|(?:two|three|four|five|some|a few|the following) (?:things|points|items|tasks|steps|pointers|priorities)))\s*(?:[.:;—-]|\bare\b)\s*(.+)$"#)
    private static func ordinal(_ word: String) -> Int? {
        let w = word.replacingOccurrences(of: #"^(number|point|step) "#, with: "", options: .regularExpression).replacingOccurrences(of: "ly$", with: "", options: .regularExpression)
        return Int(w) ?? (ordinals.firstIndex(of: w) ?? numbers.firstIndex(of: w)).map { $0 + 1 }
    }
    private static func capitalize(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    static func format(_ text: String) -> String {
        let request = #"(?i)^(?:(?:please )?(?:make|create|start|give me) (?:me )?(?:a |some )?(?:bullet points|pointers|bulleted list|bullet list|numbered list)\b|(?:bullet points|pointers|bulleted list|bullet list|numbered list)(?=\s*[:.,—-]))[\s:,.—-]*"#
        if let command = text.range(of: request, options: .regularExpression) {
            let ordered = text[command].lowercased().contains("numbered")
            let remainder = String(text[command.upperBound...])
            guard !remainder.isEmpty else { return "" }
            // Parse spoken markers, or a short enumeration with an explicit list introduction.
            let parsed = formatBody(remainder)
            let list = parsed.contains("\n") || parsed.hasPrefix("• ") || parsed.hasPrefix("1. ") ? parsed : formatBody("Shopping list: " + remainder)
            let body = list.hasPrefix("Shopping list:\n") ? String(list.dropFirst("Shopping list:\n".count)) : (list.hasPrefix("Shopping list: ") ? remainder : list)
            var numbering = 0
            var inList = true
            return body.components(separatedBy: "\n").map { line in
                if line.isEmpty { inList = false; return "" }
                guard inList else { return line }
                numbering += 1
                let value = line.replacingOccurrences(of: #"^(?:•|[0-9]+\.)\s+"#, with: "", options: .regularExpression)
                return (ordered ? "\(numbering). " : "• ") + capitalize(value)
            }.joined(separator: "\n")
        }
        return formatBody(text)
    }

    private static func formatBody(_ text: String) -> String {
        let ns = text as NSString
        let matches = markers.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var cursor = 0
        var output = ""
        var prefix = ""
        var separator = ""
        var listNumber: Int?
        func flush(_ end: Int, beforeCue: Bool) {
            var content = ns.substring(with: NSRange(location: cursor, length: end - cursor))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if beforeCue { content = content.trimmingCharacters(in: CharacterSet(charactersIn: ",; ")) }
            guard !content.isEmpty else { return }
            output += (output.isEmpty ? "" : separator) + prefix + (prefix.isEmpty && separator.isEmpty ? content : capitalize(content))
        }
        for (i, m) in matches.enumerated() {
            let word = ns.substring(with: m.range).lowercased()
            let start = m.range.location
            let end = NSMaxRange(m.range)
            let preceding = ns.substring(to: start).trimmingCharacters(in: .whitespacesAndNewlines)
            let boundary = preceding.isEmpty || preceding.last.map { ".?!:;,—".contains($0) } == true
            let after = ns.substring(from: end)
            if let n = ordinal(word) {
                let next = matches.dropFirst(i + 1).first { ordinal(ns.substring(with: $0.range).lowercased()) != nil }
                let nextNumber = next.flatMap { ordinal(ns.substring(with: $0.range).lowercased()) }
                let namedCue = ["number ", "point ", "step "].contains { word.hasPrefix($0) }
                let numericCue = word.hasPrefix("number ") || word.first?.isNumber == true || numbers.contains(word)
                let cueLike = !numericCue || namedCue || after.first.map { ".,:)".contains($0) } == true
                let sequenceStart = n == 1 && nextNumber == 2 && (boundary || namedCue)
                guard cueLike, sequenceStart || (listNumber.map { n == $0 + 1 } == true) else { continue }
                flush(start, beforeCue: true)
                listNumber = n
                prefix = "\(n). "
                separator = "\n"
            } else {
                // Embedded mentions such as "the next item is expensive" are prose.
                let explicit = ["next bullet", "next bullet point", "new bullet", "new paragraph", "new line"].contains(word)
                guard boundary || (explicit && !preceding.lowercased().hasSuffix("the") && !preceding.lowercased().hasSuffix("a")) || ((word == "next item" || word.hasPrefix("end ")) && !prefix.isEmpty) else { continue }
                if word == "end list" || word == "end the list" { guard !prefix.isEmpty else { continue } }
                flush(start, beforeCue: true)
                if word == "new paragraph" || word.hasPrefix("end ") || word == "new line" {
                    prefix = ""; listNumber = nil
                    separator = word == "new line" ? "\n" : "\n\n"
                } else if word == "next item", let number = listNumber {
                    listNumber = number + 1; prefix = "\(number + 1). "; separator = "\n"
                } else {
                    listNumber = nil; prefix = "• "; separator = "\n"
                }
            }
            cursor = end
            while cursor < ns.length, let scalar = UnicodeScalar(ns.character(at: cursor)),
                  CharacterSet(charactersIn: " ,.:;)—-\t").contains(scalar) { cursor += 1 }
        }
        flush(ns.length, beforeCue: false)
        // Infer a comma-separated list only after an explicit list introduction.
        if !output.contains("\n"), let m = intro.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)) {
            let source = output as NSString
            let title = source.substring(with: m.range(at: 1))
            let body = source.substring(with: m.range(at: 2))
            var items = body.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if items.count >= 2, let last = items.last {
                if last.lowercased().hasPrefix("and ") { items[items.count-1] = String(last.dropFirst(4)) }
                else if let r = last.range(of: " and ", options: .caseInsensitive) {
                    items.removeLast(); items += [String(last[..<r.lowerBound]), String(last[r.upperBound...])]
                }
                if items.allSatisfy({ !$0.isEmpty && $0.split(separator: " ").count <= 12 }),
                   !body.dropLast().contains(where: { ".!?".contains($0) }) {
                    return title + ":\n" + items.map { "• " + capitalize($0) }.joined(separator: "\n")
                }
            }
        }
        return output
    }
}
