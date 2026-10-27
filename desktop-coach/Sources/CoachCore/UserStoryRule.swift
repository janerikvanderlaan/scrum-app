import Foundation

/// TEAM-02: backlog items are written as "As a ... I want to ... so that ...".
/// Mode "explain": the coach never blocks, it explains after the person leaves the field.
/// A loose match is enough; Dutch ("Als ... wil ik ... zodat ...") is accepted too.
public enum UserStoryRule {
    public static let ruleID = "TEAM-02"
    public static let source = "Team agreement: \"Product Backlog items and improvements are written as user stories: 'As a … I want to … so that …'.\""

    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are constants; a typo should fail the unit tests, not hide.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
    }

    private static let fullStory = [
        regex(#"^\s*as\s+\S.*?\bi\s+(want|would\s+like|need)\b.*?\S.*?\bso\s+that\s+\S"#),
        regex(#"^\s*als\s+\S.*?\bwil\s+ik\b.*?\S.*?\bzodat\s+\S"#),
    ]
    private static let whoPart = regex(#"\b(as|als)\s+(a|an|the|een|de|het)\b"#)
    private static let wantPart = regex(#"\b(i\s+(want|would\s+like|need)|wil\s+ik)\b"#)
    private static let benefitPart = regex(#"\b(so\s+that|zodat)\b"#)

    private static func matches(_ re: NSRegularExpression, _ text: String) -> Bool {
        re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// The parts of the user story shape that the text does not have yet.
    public static func missingParts(in text: String) -> [String] {
        var missing: [String] = []
        if !matches(whoPart, text) { missing.append("who it's for (\"As a …\")") }
        if !matches(wantPart, text) { missing.append("what they want (\"I want to …\")") }
        if !matches(benefitPart, text) { missing.append("why it matters (\"so that …\")") }
        return missing
    }

    /// Returns a hint when the text is not a user story yet, nil when it is (or is empty).
    public static func check(_ text: String) -> Hint? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if fullStory.contains(where: { matches($0, trimmed) }) { return nil }

        let missing = missingParts(in: trimmed)
        let what: String
        if missing.isEmpty {
            what = "All three parts of a user story are here, in a different order than usual."
        } else {
            what = "This text doesn't have the user story shape yet. It doesn't say \(list(missing))."
        }
        return Hint(
            ruleID: ruleID,
            what: what,
            why: "Your team agreed to write backlog items as user stories, so everyone can see who an item helps and why it matters. That makes it easier to order the backlog and to check the result in the Sprint Review.",
            how: "Try this shape: As a <who> I want to <what> so that <why>. For example: \"As a team member I want to see my open items so that I know what to pick up next.\"",
            source: source
        )
    }

    private static func list(_ parts: [String]) -> String {
        switch parts.count {
        case 1: return parts[0]
        case 2: return "\(parts[0]) or \(parts[1])"
        default: return parts.dropLast().joined(separator: ", ") + ", or " + parts.last!
        }
    }
}
