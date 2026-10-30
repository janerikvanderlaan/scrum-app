import Foundation

/// Another text field in the same dialog or form as the focused field.
public struct FormField: Equatable, Sendable {
    public let label: String
    public let text: String

    public init(label: String, text: String) {
        self.label = label
        self.text = text
    }
}

private func labelMatches(_ label: String, any needles: [String], none excluded: [String] = []) -> Bool {
    let lower = label.lowercased()
    return needles.contains { lower.contains($0) } && !excluded.contains { lower.contains($0) }
}

/// SG-200: an item is ready for a Sprint when the team can finish it within one Sprint.
/// The coach uses the team's average velocity as the measure, like the scrum-app web app.
public enum StoryPointsRule {
    public static let ruleID = "SG-200"
    public static let source = "\"Product Backlog items that can be Done by the Scrum Team within one Sprint are deemed ready for selection in a Sprint Planning event.\" (Scrum Guide 2020)"

    public static func appliesTo(label: String) -> Bool {
        labelMatches(label,
                     any: ["story point", "storypoint", "schatting", "estimate", "punten"],
                     none: ["original", "remaining", "oorspronkelijk", "resterend", "time", "tijd"])
    }

    public static func points(in text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    /// nil when the estimate fits (or isn't a number); a hint when it is above the average velocity.
    public static func check(_ text: String, averageVelocity: Int) -> Hint? {
        guard let value = points(in: text), averageVelocity > 0, value > Double(averageVelocity) else { return nil }
        let shown = value.rounded() == value ? String(Int(value)) : String(value)
        return Hint(
            ruleID: ruleID,
            key: shown,
            what: "This item is estimated at \(shown) points, more than the team's average velocity of \(averageVelocity). It probably won't fit in one Sprint.",
            why: "Items the team can finish within one Sprint are ready for Sprint Planning. Smaller items give feedback sooner and make the forecast more reliable.",
            how: "Try splitting it into smaller stories that each still deliver something useful, for example one per step in the workflow, one per type of user, or the simple case first.",
            source: source
        )
    }
}

/// SG-150: Sprint Planning ends with a Sprint Goal. In Jira that's the Sprint goal
/// field of the Start Sprint dialog, so this rule looks at the whole dialog.
public enum SprintGoalRule {
    public static let ruleID = "SG-150"
    public static let source = "\"The Sprint Goal must be finalized prior to the end of Sprint Planning.\" (Scrum Guide 2020)"

    public static func isGoalField(label: String) -> Bool {
        labelMatches(label, any: ["sprint goal", "sprintdoel", "sprint-doel", "doel van de sprint"])
    }

    private static func isNameField(label: String) -> Bool {
        labelMatches(label, any: ["sprint name", "sprintnaam", "naam van de sprint", "naam"], none: ["goal", "doel"])
    }

    /// The Sprint goal field of the dialog, if this form is a Sprint dialog.
    public static func goalField(in form: [FormField]) -> FormField? {
        form.first { isGoalField(label: $0.label) }
    }

    /// One finding per Sprint: the Sprint name from the dialog.
    public static func key(form: [FormField]) -> String {
        form.first { isNameField(label: $0.label) }?.text ?? ""
    }

    /// nil when the form has no Sprint goal field or the goal is filled in.
    public static func check(form: [FormField]) -> Hint? {
        guard let goal = goalField(in: form),
              CoachScope.writtenText(goal.text, placeholder: nil).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return Hint(
            ruleID: ruleID,
            key: key(form: form),
            what: "This Sprint doesn't have a Sprint Goal yet.",
            why: "The Sprint Goal gives the Developers one shared focus for the Sprint. When work turns out different than planned, it helps the team decide together what matters most.",
            how: "Before you start the Sprint, write one sentence in the Sprint goal field on what this Sprint achieves and why that's valuable. For example: \"Customers can pay with iDEAL, so fewer orders are abandoned.\"",
            source: source
        )
    }
}

/// What the coach concluded about one field.
public enum CoachOutcome: Equatable, Sendable {
    /// No rule looks at this field.
    case notApplicable
    /// A rule looked and everything is fine; the message is shown only when the person asked.
    /// `key` is the dedupeKey a hint about the same thing would have, so a later
    /// regression (a goal filled in, then deleted) is explained again.
    case fine(CoachMessage, key: String)
    case hint(Hint)
}

public struct CoachSettings: Equatable, Sendable {
    public var averageVelocity: Int

    public init(averageVelocity: Int = 10) {
        self.averageVelocity = averageVelocity
    }
}

/// Picks the rule that fits the field. The order matters: the Sprint dialog first
/// (it applies to every field in it), then story points, then the user story text.
public enum CoachRules {
    /// `changed` is false when the person only passed through the field without editing it;
    /// text rules stay quiet then, the Sprint Goal check doesn't (an empty goal is never typed).
    /// `nextLabel` is the label of the field that got the focus: moving into the Sprint goal
    /// field means the person is about to fill it in, so the coach waits.
    /// `anyApp` is the test mode: the user story rule applies to every text field.
    public static func check(field: FieldInfo, text: String, form: [FormField], changed: Bool,
                             settings: CoachSettings, nextLabel: String? = nil, anyApp: Bool = false) -> CoachOutcome {
        if SprintGoalRule.goalField(in: form) != nil {
            if let hint = SprintGoalRule.check(form: form) {
                if let nextLabel, SprintGoalRule.isGoalField(label: nextLabel) { return .notApplicable }
                return .hint(hint)
            }
            return .fine(CoachMessages.fine("This Sprint has a Sprint Goal. Nice work."),
                         key: "\(SprintGoalRule.ruleID)|\(SprintGoalRule.key(form: form))")
        }
        if StoryPointsRule.appliesTo(label: field.label) {
            guard StoryPointsRule.points(in: text) != nil else { return .notApplicable }
            if changed, let hint = StoryPointsRule.check(text, averageVelocity: settings.averageVelocity) {
                return .hint(hint)
            }
            return .fine(CoachMessages.fine("This estimate fits within the team's average velocity of \(settings.averageVelocity) points."),
                         key: "\(StoryPointsRule.ruleID)|\(text)")
        }
        if anyApp || CoachScope.isStoryField(label: field.label) {
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notApplicable }
            if changed, let hint = UserStoryRule.check(text) { return .hint(hint) }
            return .fine(CoachMessages.allGood(fieldLabel: shortLabel(field.label)),
                         key: "\(UserStoryRule.ruleID)|\(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return .notApplicable
    }

    public static func shortLabel(_ label: String) -> String {
        label.components(separatedBy: " · ").first ?? ""
    }
}
