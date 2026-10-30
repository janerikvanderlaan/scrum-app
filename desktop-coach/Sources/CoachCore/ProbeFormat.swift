import Foundation

/// Wording for CoachProbe, the event logger used to learn how focus and values move
/// in an app (such as Jira in Safari). Pure functions, so the log format is unit tested.
public enum ProbeFormat {
    /// A key by what it does, never by what was typed: letters, digits and symbols are all "character".
    public static func keyName(keyCode: UInt16, shift: Bool = false, control: Bool = false,
                               option: Bool = false, command: Bool = false) -> String {
        let named: [UInt16: String] = [
            36: "Return", 76: "Enter", 48: "Tab", 53: "Escape", 49: "Space", 51: "Backspace", 117: "Delete",
            123: "Left", 124: "Right", 125: "Down", 126: "Up", 115: "Home", 119: "End", 116: "PageUp", 121: "PageDown",
        ]
        let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        let key = named[keyCode] ?? (functionKeys.contains(keyCode) ? "F-key" : "character")
        var modifiers: [String] = []
        if control { modifiers.append("Control") }
        if option { modifiers.append("Option") }
        if command { modifiers.append("Command") }
        // Shift only matters for named keys (Shift-Tab goes back); for a character it would hint at what was typed.
        if shift && key != "character" { modifiers.append("Shift") }
        return (modifiers + [key]).joined(separator: "-")
    }

    /// Text shown in the log: cut to a preview, line breaks shown as ⏎, or only its length when text is hidden.
    public static func preview(_ text: String?, showText: Bool, limit: Int = 60) -> String {
        guard let text else { return "-" }
        guard showText else { return "(\(text.count) chars)" }
        let flat = text.replacingOccurrences(of: "\n", with: "⏎")
        let cut = flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
        return "\"\(cut)\""
    }

    /// One log line: time with milliseconds, a fixed-width tag, then the details.
    public static func line(at date: Date, tag: String, _ details: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        let padded = tag.count < 7 ? tag + String(repeating: " ", count: 7 - tag.count) : tag
        return "\(formatter.string(from: date)) \(padded) \(details)"
    }
}
