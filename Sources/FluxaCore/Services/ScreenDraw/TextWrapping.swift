import Foundation

// MARK: - TextWrapping

/// Algorithmic text formatting and word wrapping for screen annotations.
package enum TextWrapping {

    /// Wraps text into multiple lines such that no line exceeds `maxCharactersPerLine`
    /// (wrapping at word boundaries where possible), while preserving explicit newlines.
    package static func wrap(text: String, maxCharactersPerLine: Int = 45) -> String {
        let maxChars = max(10, maxCharactersPerLine)
        let paragraphs = text.components(separatedBy: "\n")
        var wrappedParagraphs: [String] = []

        for paragraph in paragraphs {
            let words = paragraph.components(separatedBy: " ")
            guard !words.isEmpty else {
                wrappedParagraphs.append("")
                continue
            }

            var currentLine = ""
            for word in words {
                if currentLine.isEmpty {
                    currentLine = word
                } else if currentLine.count + 1 + word.count <= maxChars {
                    currentLine += " " + word
                } else {
                    wrappedParagraphs.append(currentLine)
                    currentLine = word
                }
            }
            if !currentLine.isEmpty {
                wrappedParagraphs.append(currentLine)
            }
        }

        return wrappedParagraphs.joined(separator: "\n")
    }
}
