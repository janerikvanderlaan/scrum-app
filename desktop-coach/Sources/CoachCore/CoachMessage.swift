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
    /// A second button, such as "Start anyway…" on a blocked step; nil for none.
    public let secondaryButtonTitle: String?

    public init(title: String, sections: [Section], buttonTitle: String = "Thanks", secondaryButtonTitle: String? = nil) {
        self.title = title
        self.sections = sections
        self.buttonTitle = buttonTitle
        self.secondaryButtonTitle = secondaryButtonTitle
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

    /// A step the coach held back (a blocking rule): the same What / Why / How, and the
    /// person stays in charge: she can fix it, or carry on and say why.
    public static func held(_ hints: [Hint]) -> CoachMessage? {
        guard !hints.isEmpty else { return nil }
        let numbered = hints.count > 1
        return CoachMessage(
            title: "Before this Sprint starts",
            sections: hints.enumerated().flatMap { index, hint in [
                CoachMessage.Section(heading: numbered ? "\(index + 1). What I noticed" : "What I noticed", text: hint.what),
                CoachMessage.Section(heading: "Why it helps", text: hint.why),
                CoachMessage.Section(heading: "A next step", text: hint.how),
                CoachMessage.Section(heading: nil, text: "\(hint.ruleID) · \(hint.source)"),
            ] } + [
                CoachMessage.Section(heading: nil, text: "I paused the start so you can have a look first. Your team decides: if you'd like to start anyway, choose Start anyway and add a short reason. The team can talk about it in the Retrospective."),
            ],
            buttonTitle: "I'll fix it",
            secondaryButtonTitle: "Start anyway…"
        )
    }

    /// After a reason was given: how to carry on.
    public static let overrideNoted = CoachMessage(
        title: "Noted",
        sections: [.init(heading: nil, text: "Thanks, I noted your reason for the Retrospective. Click Start again to start the Sprint.")],
        buttonTitle: "OK"
    )

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
