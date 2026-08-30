import AppKit
import FluxaCore

@MainActor
final class URLCleanerService {
    /// Reads the pasteboard, cleans if possible, and writes back only when the URL changed.
    func cleanClipboard() -> Bool {
        let pasteboard = NSPasteboard.general
        guard let contents = pasteboard.string(forType: .string),
              let url = URL(string: contents),
              let cleaned = URLCleaner.cleaned(url)
        else {
            return false
        }

        pasteboard.clearContents()
        return pasteboard.setString(cleaned.absoluteString, forType: .string)
    }
}
