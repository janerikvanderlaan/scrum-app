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
            // Every new estimate is its own finding: two items of 10 points both get the tip.
            key: UUID().uuidString,
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

/// TEAM-03: a Sprint starts with a forecast that fits the team's average velocity.
/// For now the total is read from the screen (the backlog header of the Sprint) and the
/// velocity comes from the coach's setting; reading both from Jira itself comes later.
public enum SprintForecastRule {
    public static let ruleID = "TEAM-03"
    public static let source = "Team agreement: \"A Sprint starts only with sized user stories whose total stays within the team's average velocity.\""

    public static func check(total: Double?, averageVelocity: Int, sprintName: String) -> Hint? {
        guard let total, averageVelocity > 0, total > Double(averageVelocity) else { return nil }
        let shown = total.rounded() == total ? String(Int(total)) : String(total)
        return Hint(
            ruleID: ruleID,
            key: sprintName,
            what: "This Sprint's forecast is \(shown) points, more than the team's average velocity of \(averageVelocity).",
            why: "Your team agreed to start a Sprint with a forecast that fits what you usually finish. That keeps the Sprint Goal within reach and leaves room for the unexpected.",
            how: "Consider moving the lowest-ordered items back to the Product Backlog until the total fits, and check the Sprint Goal still holds.",
            source: source
        )
    }
}

/// Finds a Sprint's total estimate in the texts of the backlog page, in reading order.
/// Jira shows it in the Sprint's header, after the Sprint name, in one of two ways:
/// - status badges: "Nog te doen: 22 van 27 (storypoints)", "To Do: 22 of 27 (story points)"
///   (points per status of all points; the second number is the total),
/// - an estimate: "Schatting: 10 van 10" or "Estimate: 10 of 10" (visible items of all items).
public enum SprintTotal {
    private static let estimate = try! NSRegularExpression(
        pattern: #"(?:schatting|estimate)\s*:?\s*([0-9]+(?:[.,][0-9]+)?)(?:\s*(?:van|of)\s*([0-9]+(?:[.,][0-9]+)?))?"#,
        options: [.caseInsensitive]
    )
    private static let badge = try! NSRegularExpression(
        pattern: #"(?:nog te doen|in behandeling|voltooid|to do|in progress|done)\s*:\s*[0-9]+(?:[.,][0-9]+)?\s*(?:van|of)\s*([0-9]+(?:[.,][0-9]+)?)"#,
        options: [.caseInsensitive]
    )

    public static func find(in texts: [String], sprintName: String) -> Double? {
        let name = sprintName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        for (index, text) in texts.enumerated() where text.trimmingCharacters(in: .whitespaces).hasPrefix(name) {
            let window = texts[(index + 1)..<min(texts.count, index + 60)].joined(separator: " ")
            let all = NSRange(window.startIndex..., in: window)
            // Whichever comes first after the Sprint name belongs to this Sprint.
            let found = [badge.firstMatch(in: window, range: all).map { ($0, 1) },
                         estimate.firstMatch(in: window, range: all).map { ($0, $0.range(at: 2).location != NSNotFound ? 2 : 1) }]
                .compactMap { $0 }
                .min { $0.0.range.location < $1.0.range.location }
            guard let found, let range = Range(found.0.range(at: found.1), in: window) else { continue }
            return Double(window[range].replacingOccurrences(of: ",", with: "."))
        }
        return nil
    }
}

/// How a rule acts when it finds something. Most rules explain afterwards; a blocking rule
/// holds the step back until the person fixes it or overrides it with a reason.
public enum RuleMode: Equatable, Sendable {
    case explainAfterwards
    case blockWithOverride
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
/// (Sprint Goal, then the forecast; it applies to every field in it), then story points,
/// then the user story text.
public enum CoachRules {
    /// `changed` is false when the person only passed through the field without editing it;
    /// text rules stay quiet then, the Sprint Goal check doesn't (an empty goal is never typed).
    /// `sprintTotal` is the Sprint's total estimate read from the page (nil when not found).
    /// `askedByUser` is Control-Option-C or the menu: then the Sprint dialog is checked right away.
    /// `anyApp` is the test mode: the user story rule applies to every text field.
    public static func check(field: FieldInfo, text: String, form: [FormField], changed: Bool,
                             settings: CoachSettings, sprintTotal: Double? = nil,
                             askedByUser: Bool = false, anyApp: Bool = false) -> CoachOutcome {
        if SprintGoalRule.goalField(in: form) != nil {
            // The Sprint checks run when the person clicks Start (see sprintStart), not while
            // she moves between the dialog's fields; only when she asks does the coach look now.
            guard askedByUser else { return .notApplicable }
            let hints = sprintStart(form: form, sprintTotal: sprintTotal, settings: settings)
            if let first = hints.first { return .hint(first) }
            return .fine(sprintLooksGood(sprintTotal: sprintTotal, settings: settings),
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

    /// Clicking Start in the Start Sprint dialog: Sprint Goal (SG-150) first, then the
    /// forecast (TEAM-03). Empty when all is well or the form isn't a Sprint dialog.
    public static func sprintStart(form: [FormField], sprintTotal: Double?, settings: CoachSettings) -> [Hint] {
        guard SprintGoalRule.goalField(in: form) != nil else { return [] }
        let sprintName = SprintGoalRule.key(form: form)
        return [
            SprintGoalRule.check(form: form),
            SprintForecastRule.check(total: sprintTotal, averageVelocity: settings.averageVelocity, sprintName: sprintName),
        ].compactMap { $0 }
    }

    static func sprintLooksGood(sprintTotal: Double?, settings: CoachSettings) -> CoachMessage {
        var message = "This Sprint has a Sprint Goal."
        if let sprintTotal {
            let shown = sprintTotal.rounded() == sprintTotal ? String(Int(sprintTotal)) : String(sprintTotal)
            message += " Its forecast of \(shown) points fits within the average velocity of \(settings.averageVelocity)."
        }
        return CoachMessages.fine(message + " Nice work.")
    }

    /// Per rule; SG-150 blocks the Sprint start (Jan Erik, 2026-10-31). Later this becomes a team setting.
    public static func mode(of ruleID: String) -> RuleMode {
        ruleID == SprintGoalRule.ruleID ? .blockWithOverride : .explainAfterwards
    }

    /// Splits Sprint start findings: the ones that hold the start back, and the ones explained
    /// afterwards. A finding the person already overrode (by dedupeKey) no longer holds it back
    /// and isn't explained again.
    public static func gate(_ hints: [Hint], overridden: Set<String>) -> (hold: [Hint], explain: [Hint]) {
        let open = hints.filter { !overridden.contains($0.dedupeKey) }
        return (open.filter { mode(of: $0.ruleID) == .blockWithOverride },
                open.filter { mode(of: $0.ruleID) == .explainAfterwards })
    }

    /// The button that starts the Sprint in Jira's Start Sprint dialog.
    public static func isStartButton(label: String) -> Bool {
        let lower = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["start", "starten", "start sprint", "sprint starten"].contains(lower)
    }

    public static func shortLabel(_ label: String) -> String {
        label.components(separatedBy: " · ").first ?? ""
    }
}
