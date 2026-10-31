/// What the coach shows in its hint window. Wording lives here, not in the UI,
/// so every message is friendly, describes the situation (never the person)
/// and can be checked by unit tests.
public struct CoachMessage: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public let heading: String?
        public let text: String

        public init(heading: String?, text: String) {
            self.heading = heading
            self.text = text
        }
    }

    public let title: String
    public let sections: [Section]
    public let buttonTitle: String

    public init(title: String, sections: [Section], buttonTitle: String = "Thanks") {
        self.title = title
        self.sections = sections
        self.buttonTitle = buttonTitle
    }
}

/// A rule finding: what was noticed, why it matters, and one next step.
public struct Hint: Equatable, Sendable {
    public let ruleID: String
    /// What this finding is about (the text, the estimate, the Sprint), so it isn't repeated.
    public let key: String
    public let what: String
    public let why: String
    public let how: String
    public let source: String

    public var dedupeKey: String { "\(ruleID)|\(key)" }

    public var message: CoachMessage {
        CoachMessage(
            title: "A small tip",
            sections: [
                .init(heading: "What I noticed", text: what),
                .init(heading: "Why it helps", text: why),
                .init(heading: "A next step", text: how),
                .init(heading: nil, text: "\(ruleID) · \(source)"),
            ],
            buttonTitle: "Thanks"
        )
    }
}

public enum CoachMessages {
    public static func allGood(fieldLabel: String) -> CoachMessage {
        let field = fieldLabel.isEmpty ? "This field" : "The \(fieldLabel) field"
        return CoachMessage(
            title: "Looks good",
            sections: [.init(heading: nil, text: "\(field) reads like a user story: who it's for, what they want, and why. Nice work.")],
            buttonTitle: "Thanks"
        )
    }

    /// One hint as usual; several (such as Sprint Goal and forecast at Sprint start) in one window.
    public static func tips(_ hints: [Hint]) -> CoachMessage? {
        guard let first = hints.first else { return nil }
        guard hints.count > 1 else { return first.message }
        return CoachMessage(
            title: "A few small tips",
            sections: hints.enumerated().flatMap { index, hint in [
                CoachMessage.Section(heading: "\(index + 1). What I noticed", text: hint.what),
                CoachMessage.Section(heading: "Why it helps", text: hint.why),
                CoachMessage.Section(heading: "A next step", text: hint.how),
                CoachMessage.Section(heading: nil, text: "\(hint.ruleID) · \(hint.source)"),
            ] },
            buttonTitle: "Thanks"
        )
    }

    public static func fine(_ text: String) -> CoachMessage {
        CoachMessage(title: "Looks good", sections: [.init(heading: nil, text: text)], buttonTitle: "Thanks")
    }

    public static let nothingToCheck = CoachMessage(
        title: "Nothing to check here",
        sections: [.init(
            heading: nil,
            text: "In Jira I look at story fields (such as Summary or Description), story points and the Sprint goal. Click into one of those and ask again, or switch on \"Coach in every app\" in the menu to try it anywhere."
        )],
        buttonTitle: "OK"
    )

    public static let cannotRead = CoachMessage(
        title: "I can't see a field",
        sections: [.init(
            heading: nil,
            text: "I couldn't find a text field with the keyboard focus. Click into the field you want me to look at, then press Control-Option-C."
        )],
        buttonTitle: "OK"
    )

    public static let needsAccess = CoachMessage(
        title: "One step before I can help",
        sections: [.init(
            heading: nil,
            text: "To see which field you're in, macOS needs to allow Accessibility access. Open System Settings > Privacy & Security > Accessibility and switch on the app that started the coach (Terminal, if you used swift run). I never take screenshots or record anything."
        )],
        buttonTitle: "OK"
    )
}
