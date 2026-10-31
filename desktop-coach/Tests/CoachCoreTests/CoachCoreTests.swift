import XCTest
@testable import CoachCore

final class UserStoryRuleTests: XCTestCase {
    func testAcceptsAUserStory() {
        XCTAssertNil(UserStoryRule.check("As a team member I want to see my open items so that I know what to pick up next"))
    }

    func testAcceptsLooseVariants() {
        XCTAssertNil(UserStoryRule.check("as an admin, I would like to export the backlog, so that I can share it"))
        XCTAssertNil(UserStoryRule.check("As a PO I need a filter so that I find items faster"))
        XCTAssertNil(UserStoryRule.check("As a Developer\nI want to rerun tests\nso that I trust the build"))
    }

    func testAcceptsDutch() {
        XCTAssertNil(UserStoryRule.check("Als teamlid wil ik mijn open items zien zodat ik weet wat ik oppak"))
    }

    func testIgnoresEmptyText() {
        XCTAssertNil(UserStoryRule.check(""))
        XCTAssertNil(UserStoryRule.check("   \n "))
    }

    func testHintsOnATaskTitle() throws {
        let hint = try XCTUnwrap(UserStoryRule.check("Fix login bug"))
        XCTAssertEqual(hint.ruleID, "TEAM-02")
        XCTAssertTrue(hint.what.contains("who it's for"))
        XCTAssertTrue(hint.what.contains("what they want"))
        XCTAssertTrue(hint.what.contains("why it matters"))
    }

    func testNamesOnlyTheMissingPart() throws {
        let hint = try XCTUnwrap(UserStoryRule.check("As a user I want to log in"))
        XCTAssertEqual(UserStoryRule.missingParts(in: "As a user I want to log in"), ["why it matters (\"so that …\")"])
        XCTAssertFalse(hint.what.contains("who it's for"))
    }

    func testAllPartsInAnotherOrder() throws {
        let hint = try XCTUnwrap(UserStoryRule.check("So that I know what to do, as a user I want a list"))
        XCTAssertTrue(hint.what.contains("different order"))
    }

    func testWordsInsideOtherWordsDoNotCount() {
        // "Ask" starts with "as" but is not "As a ...".
        XCTAssertEqual(UserStoryRule.missingParts(in: "Ask the team").count, 3)
    }

    func testHintIsFriendlyAndQuotesTheSource() throws {
        let message = try XCTUnwrap(UserStoryRule.check("Fix login bug")).message
        let all = ([message.title] + message.sections.map(\.text)).joined(separator: " ").lowercased()
        for blame in ["you forgot", "wrong", "error", "failed", "must"] {
            XCTAssertFalse(all.contains(blame), "unfriendly word: \(blame)")
        }
        XCTAssertTrue(all.contains("team agreement"))
    }
}

final class CoachScopeTests: XCTestCase {
    private func field(url: String? = "https://acme.atlassian.net/jira/software/projects/OW/boards/1",
                       role: String = "AXTextField", subrole: String? = nil, label: String = "Summary") -> FieldInfo {
        FieldInfo(appBundleID: "com.apple.Safari", pageURL: url, role: role, subrole: subrole, label: label)
    }

    func testCoachesJiraStoryFields() {
        XCTAssertTrue(CoachScope.shouldCoach(field(), anyApp: false))
        XCTAssertTrue(CoachScope.shouldCoach(field(role: "AXTextArea", label: "Description"), anyApp: false))
        XCTAssertTrue(CoachScope.shouldCoach(field(url: "https://jira.example.com/browse/OW-1"), anyApp: false))
    }

    func testSkipsOtherPagesAndFields() {
        XCTAssertFalse(CoachScope.shouldCoach(field(url: "https://example.com"), anyApp: false))
        XCTAssertFalse(CoachScope.shouldCoach(field(url: nil), anyApp: false))
        XCTAssertFalse(CoachScope.shouldCoach(field(role: "AXButton"), anyApp: false))
    }

    func testNeverReadsPasswordOrSearchFields() {
        XCTAssertFalse(CoachScope.shouldCoach(field(subrole: "AXSecureTextField"), anyApp: true))
        XCTAssertFalse(CoachScope.shouldCoach(field(subrole: "AXSearchField"), anyApp: true))
    }

    func testIgnoresJiraEditorPrompt() {
        let prompt = "Typ /ai om het aan Rovo te vragen of @ om iemand te vermelden en op de hoogte te brengen."
        XCTAssertEqual(CoachScope.writtenText(prompt, placeholder: nil), "")
        XCTAssertEqual(CoachScope.writtenText("Type /ai to ask Rovo", placeholder: nil), "")
        XCTAssertNil(UserStoryRule.check(CoachScope.writtenText(prompt, placeholder: nil)))
    }

    func testIgnoresPlaceholderShownAsValue() {
        XCTAssertEqual(CoachScope.writtenText("Omschrijf wat er moet gebeuren", placeholder: "Omschrijf wat er moet gebeuren"), "")
    }

    func testKeepsWhatThePersonWrote() {
        XCTAssertEqual(CoachScope.writtenText("Fix login bug", placeholder: "Omschrijf wat er moet gebeuren"), "Fix login bug")
        XCTAssertEqual(CoachScope.writtenText("Fix login bug", placeholder: nil), "Fix login bug")
    }

    func testCoachesJiraNumberInputs() {
        // Test round 1, issue 4: Jira's inline story point editor is a number input (AXIncrementor).
        XCTAssertTrue(CoachScope.shouldCoach(field(role: "AXIncrementor", label: "Story point estimate"), anyApp: false))
    }

    func testTestModeCoachesAnyTextField() {
        XCTAssertTrue(CoachScope.shouldCoach(field(url: nil, label: ""), anyApp: true))
    }
}

final class PlanningRulesTests: XCTestCase {
    private let jira = FieldInfo(appBundleID: "com.apple.Safari", pageURL: "https://leanig.atlassian.net/jira",
                                 role: "AXTextField", subrole: nil, label: "")
    private let settings = CoachSettings(averageVelocity: 10)

    private func outcome(label: String, text: String, form: [FormField] = [], changed: Bool = true,
                         askedByUser: Bool = false) -> CoachOutcome {
        var field = jira
        field.label = label
        return CoachRules.check(field: field, text: text, form: form, changed: changed, settings: settings,
                                askedByUser: askedByUser)
    }

    private func hint(_ outcome: CoachOutcome) -> Hint? {
        if case .hint(let hint) = outcome { return hint }
        return nil
    }

    // SG-200

    func testStoryPointsAboveVelocityGetAHint() throws {
        let found = try XCTUnwrap(hint(outcome(label: "Story point estimate", text: "13")))
        XCTAssertEqual(found.ruleID, "SG-200")
        XCTAssertTrue(found.what.contains("13 points"))
        XCTAssertTrue(found.what.contains("average velocity of 10"))
    }

    func testStoryPointsWithinVelocityAreFine() {
        XCTAssertNil(hint(outcome(label: "Story point estimate", text: "10")))
        XCTAssertNil(hint(outcome(label: "Schatting", text: "5")))
        if case .fine = outcome(label: "Schatting", text: "5") {} else { XCTFail("expected fine") }
    }

    func testDutchLabelAndDecimalComma() throws {
        let found = try XCTUnwrap(hint(outcome(label: "Schatting van storypoints", text: "10,5")))
        XCTAssertTrue(found.what.contains("10.5 points"))
    }

    func testTimeEstimatesAreNotStoryPoints() {
        XCTAssertFalse(StoryPointsRule.appliesTo(label: "Original estimate"))
        XCTAssertFalse(StoryPointsRule.appliesTo(label: "Oorspronkelijke schatting"))
        XCTAssertEqual(outcome(label: "Remaining estimate", text: "40"), .notApplicable)
    }

    func testUnchangedEstimateStaysQuiet() {
        XCTAssertNil(hint(outcome(label: "Story point estimate", text: "13", changed: false)))
    }

    func testEmptyOrNonNumberEstimateIsNotChecked() {
        XCTAssertEqual(outcome(label: "Story point estimate", text: ""), .notApplicable)
        XCTAssertEqual(outcome(label: "Story point estimate", text: "big"), .notApplicable)
    }

    // SG-150

    private let startSprintDialog = [
        FormField(label: "Sprint name", text: "CT Sprint 4"),
        FormField(label: "Duration", text: "2 weeks"),
        FormField(label: "Sprint goal", text: ""),
    ]

    func testEmptySprintGoalGetsAHintOnStart() throws {
        let found = try XCTUnwrap(CoachRules.sprintStart(form: startSprintDialog, sprintTotal: nil, settings: settings).first)
        XCTAssertEqual(found.ruleID, "SG-150")
        XCTAssertEqual(found.dedupeKey, "SG-150|CT Sprint 4")
    }

    func testFilledSprintGoalIsFine() {
        var form = startSprintDialog
        form[2] = FormField(label: "Sprint goal", text: "Customers can pay with iDEAL")
        XCTAssertNil(SprintGoalRule.check(form: form))
        XCTAssertEqual(CoachRules.sprintStart(form: form, sprintTotal: nil, settings: settings), [])
        if case .fine = outcome(label: "Sprint goal", text: "Customers can pay with iDEAL", form: form, askedByUser: true) {} else { XCTFail("expected fine") }
    }

    // Test round 1 (2026-10-30)

    func testMovingBetweenDialogFieldsStaysQuiet() {
        // Round 2 issue 1: the Sprint checks wait for Start; moving between fields never triggers them.
        XCTAssertEqual(outcome(label: "Sprint name", text: "CT Sprint 4", form: startSprintDialog, changed: false), .notApplicable)
        XCTAssertEqual(outcome(label: "Sprint goal", text: "", form: startSprintDialog, changed: false), .notApplicable)
        XCTAssertEqual(outcome(label: "Sprint goal", text: "Draft", form: startSprintDialog, changed: true), .notApplicable)
        // Asking with Control-Option-C still checks the dialog right away.
        XCTAssertEqual(hint(outcome(label: "Sprint goal", text: "", form: startSprintDialog, askedByUser: true))?.ruleID, "SG-150")
    }

    func testOnlyTheStartButtonRunsTheSprintChecks() {
        for label in ["Start", "Starten", "Start sprint", "Sprint starten", " starten "] {
            XCTAssertTrue(CoachRules.isStartButton(label: label), label)
        }
        for label in ["Annuleren", "Cancel", "Start date", "Startdatum", ""] {
            XCTAssertFalse(CoachRules.isStartButton(label: label), label)
        }
    }

    func testFilledGoalReportsTheSameKeySoADeletedGoalIsExplainedAgain() throws {
        // Issue 1: add a goal, delete it, tab on: the tip comes back.
        let first = try XCTUnwrap(CoachRules.sprintStart(form: startSprintDialog, sprintTotal: nil, settings: settings).first)
        var filled = startSprintDialog
        filled[2] = FormField(label: "Sprint goal", text: "Customers can pay with iDEAL")
        guard case .fine(_, let key) = outcome(label: "Sprint goal", text: "Customers can pay with iDEAL", form: filled, askedByUser: true) else {
            return XCTFail("expected fine")
        }
        XCTAssertEqual(key, first.dedupeKey)
    }

    func testStoryPointsRuleIsPerItem() {
        // Issue 3: two items of 5 in a Sprint with velocity 8: each item fits, so SG-200 stays quiet.
        let eight = CoachSettings(averageVelocity: 8)
        XCTAssertNil(StoryPointsRule.check("5", averageVelocity: eight.averageVelocity))
        XCTAssertNotNil(StoryPointsRule.check("10", averageVelocity: eight.averageVelocity))
    }

    func testEveryLargeItemGetsItsOwnTip() throws {
        // Round 2 issue 3: a second item with the same estimate was skipped as "already explained".
        let first = try XCTUnwrap(StoryPointsRule.check("10", averageVelocity: 8))
        let second = try XCTUnwrap(StoryPointsRule.check("10", averageVelocity: 8))
        XCTAssertNotEqual(first.dedupeKey, second.dedupeKey)
    }

    // TEAM-03 (screen only for now)

    func testSprintTotalFromTheBacklogHeader() {
        let page = ["Backlog", "CT Sprint 3", "12 okt – 26 okt", "4 van 4 werkitems zichtbaar", "Schatting: 6 van 6",
                    "CT Sprint 4", "27 okt – 10 nov", "4 van 4 werkitems zichtbaar", "|", "Schatting:", "10", "van", "12"]
        XCTAssertEqual(SprintTotal.find(in: page, sprintName: "CT Sprint 4"), 12)
        XCTAssertEqual(SprintTotal.find(in: page, sprintName: "CT Sprint 3"), 6)
        XCTAssertEqual(SprintTotal.find(in: ["OW Sprint 1", "Estimate: 7.5 of 9"], sprintName: "OW Sprint 1"), 9)
        XCTAssertNil(SprintTotal.find(in: page, sprintName: "CT Sprint 9"))
        XCTAssertNil(SprintTotal.find(in: page, sprintName: ""))
    }

    func testSprintTotalFromTheStatusBadges() {
        // Round 2 issue 2, seen with CoachProbe: this Jira shows status badges, not "Schatting".
        let page = ["CT Sprint 4", "27 okt – 10 nov", "(4 werkitems)",
                    "Nog te doen: 22 van 27 (storypoints)", "22",
                    "In behandeling: 5 van 27 (storypoints)", "5",
                    "Voltooid: 0 van 27 (storypoints)", "0", "Sprint starten"]
        XCTAssertEqual(SprintTotal.find(in: page, sprintName: "CT Sprint 4"), 27)
        XCTAssertEqual(SprintTotal.find(in: ["OW Sprint 1", "To Do: 3 of 8 (story points)"], sprintName: "OW Sprint 1"), 8)
        // A status word without "of N" is not a total.
        XCTAssertNil(SprintTotal.find(in: ["OW Sprint 1", "Done: 3"], sprintName: "OW Sprint 1"))
    }

    private var goalFilled: [FormField] {
        var form = startSprintDialog
        form[2] = FormField(label: "Sprint goal", text: "Customers can pay with iDEAL")
        return form
    }

    func testForecastAboveVelocityGetsATip() throws {
        let eight = CoachSettings(averageVelocity: 8)
        let found = try XCTUnwrap(CoachRules.sprintStart(form: goalFilled, sprintTotal: 10, settings: eight).first)
        XCTAssertEqual(found.ruleID, "TEAM-03")
        XCTAssertTrue(found.what.contains("10 points"))
        XCTAssertTrue(found.what.contains("average velocity of 8"))
        XCTAssertEqual(found.dedupeKey, "TEAM-03|CT Sprint 4")
    }

    func testForecastWithinVelocityIsFine() {
        XCTAssertEqual(CoachRules.sprintStart(form: goalFilled, sprintTotal: 10, settings: settings), [])
        let result = CoachRules.check(field: jira, text: "CT Sprint 4", form: goalFilled, changed: false,
                                      settings: settings, sprintTotal: 10, askedByUser: true)
        guard case .fine(let message, _) = result else { return XCTFail("expected fine") }
        XCTAssertTrue(message.sections[0].text.contains("fits within the average velocity of 10"))
    }

    func testStartShowsBothTipsGoalFirst() throws {
        // Round 2 issue 2: clicking Start with no goal and too much work gives both tips in one message.
        let hints = CoachRules.sprintStart(form: startSprintDialog, sprintTotal: 10, settings: CoachSettings(averageVelocity: 8))
        XCTAssertEqual(hints.map(\.ruleID), ["SG-150", "TEAM-03"])
        let message = try XCTUnwrap(CoachMessages.tips(hints))
        XCTAssertEqual(message.title, "A few small tips")
        XCTAssertTrue(message.sections.contains { $0.text.contains("Sprint Goal") })
        XCTAssertTrue(message.sections.contains { $0.text.contains("10 points") })
        XCTAssertEqual(CoachMessages.tips([hints[0]]), hints[0].message)
        XCTAssertNil(CoachMessages.tips([]))
    }

    func testStartOutsideASprintDialogDoesNothing() {
        XCTAssertEqual(CoachRules.sprintStart(form: [FormField(label: "Summary", text: "")], sprintTotal: 50, settings: settings), [])
    }

    func testUnknownTotalStaysQuiet() {
        XCTAssertNil(SprintForecastRule.check(total: nil, averageVelocity: 8, sprintName: "CT Sprint 4"))
    }

    func testDutchSprintDialog() {
        let form = [FormField(label: "Sprintnaam", text: "CT Sprint 4"), FormField(label: "Sprintdoel", text: "  ")]
        XCTAssertEqual(SprintGoalRule.check(form: form)?.ruleID, "SG-150")
    }

    func testFormsWithoutAGoalFieldAreIgnored() {
        XCTAssertNil(SprintGoalRule.check(form: [FormField(label: "Summary", text: "")]))
        XCTAssertNil(SprintGoalRule.check(form: []))
    }

    // Routing and wording

    func testOtherJiraFieldsAreNotChecked() {
        XCTAssertEqual(outcome(label: "Assignee", text: "Jan Erik"), .notApplicable)
    }

    func testUserStoryRuleStillRunsOnSummary() {
        XCTAssertEqual(hint(outcome(label: "Work item summary", text: "Fix login bug"))?.ruleID, "TEAM-02")
        XCTAssertEqual(outcome(label: "Work item summary", text: ""), .notApplicable)
    }

    func testNewHintsAreFriendly() throws {
        let hints = [
            try XCTUnwrap(StoryPointsRule.check("21", averageVelocity: 10)),
            try XCTUnwrap(SprintGoalRule.check(form: startSprintDialog)),
            try XCTUnwrap(SprintForecastRule.check(total: 12, averageVelocity: 8, sprintName: "CT Sprint 4")),
        ]
        for found in hints {
            // The source line quotes the Guide verbatim; the coach's own words must stay friendly.
            let own = [found.what, found.why, found.how].joined(separator: " ").lowercased()
            for blame in ["you forgot", "wrong", "error", "failed", "must", "not allowed"] {
                XCTAssertFalse(own.contains(blame), "\(found.ruleID) unfriendly word: \(blame)")
            }
            // Guide rules quote the Scrum Guide, team rules quote the team agreement.
            let expected = found.ruleID.hasPrefix("SG-") ? "Scrum Guide 2020" : "Team agreement"
            XCTAssertTrue(found.source.contains(expected), "\(found.ruleID) source: \(found.source)")
        }
    }
}

final class ProbeFormatTests: XCTestCase {
    func testNamedKeysAndModifiers() {
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 48), "Tab")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 48, shift: true), "Shift-Tab")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 36), "Return")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 53), "Escape")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 122), "F-key")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 8, control: true, option: true), "Control-Option-character")
    }

    func testTypedCharactersAreNeverNamed() {
        // "a" is key code 0, "1" is 18: both are only "character", also with Shift (no hint of capitals).
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 0), "character")
        XCTAssertEqual(ProbeFormat.keyName(keyCode: 18, shift: true), "character")
    }

    func testPreviewCutsAndHides() {
        XCTAssertEqual(ProbeFormat.preview("10", showText: true), "\"10\"")
        XCTAssertEqual(ProbeFormat.preview("line one\nline two", showText: true), "\"line one⏎line two\"")
        XCTAssertEqual(ProbeFormat.preview(String(repeating: "x", count: 70), showText: true, limit: 5), "\"xxxxx…\"")
        XCTAssertEqual(ProbeFormat.preview("secret plan", showText: false), "(11 chars)")
        XCTAssertEqual(ProbeFormat.preview(nil, showText: true), "-")
    }

    func testLineHasTimeAndAlignedTag() {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 30
        parts.hour = 13; parts.minute = 5; parts.second = 7; parts.nanosecond = 250_400_000
        let date = Calendar.current.date(from: parts)!
        XCTAssertEqual(ProbeFormat.line(at: date, tag: "key", "Tab"), "13:05:07.250 key     Tab")
    }
}

final class SprintGateTests: XCTestCase {
    private let emptyGoal = [FormField(label: "Sprintnaam", text: "CT Sprint 4"), FormField(label: "Sprintdoel", text: "")]
    private let eight = CoachSettings(averageVelocity: 8)

    func testEmptyGoalHoldsTheStartAndTheForecastIsExplained() {
        // Round 3: SG-150 blocks the start; TEAM-03 still explains afterwards.
        let hints = CoachRules.sprintStart(form: emptyGoal, sprintTotal: 27, settings: eight)
        let gate = CoachRules.gate(hints, overridden: [])
        XCTAssertEqual(gate.hold.map(\.ruleID), ["SG-150"])
        XCTAssertEqual(gate.explain.map(\.ruleID), ["TEAM-03"])
    }

    func testAnOverrideLetsTheStartThroughOnce() {
        let hints = CoachRules.sprintStart(form: emptyGoal, sprintTotal: 27, settings: eight)
        let gate = CoachRules.gate(hints, overridden: ["SG-150|CT Sprint 4"])
        XCTAssertEqual(gate.hold, [])
        XCTAssertEqual(gate.explain.map(\.ruleID), ["TEAM-03"])
        // The override is for this Sprint only.
        let other = [FormField(label: "Sprintnaam", text: "CT Sprint 5"), FormField(label: "Sprintdoel", text: "")]
        let next = CoachRules.gate(CoachRules.sprintStart(form: other, sprintTotal: nil, settings: eight), overridden: ["SG-150|CT Sprint 4"])
        XCTAssertEqual(next.hold.map(\.ruleID), ["SG-150"])
    }

    func testAGoalLetsTheStartThrough() {
        let filled = [FormField(label: "Sprintnaam", text: "CT Sprint 4"), FormField(label: "Sprintdoel", text: "Pay with iDEAL")]
        XCTAssertEqual(CoachRules.gate(CoachRules.sprintStart(form: filled, sprintTotal: 6, settings: eight), overridden: []).hold, [])
    }

    func testOnlyTheSprintGoalBlocksForNow() {
        XCTAssertEqual(CoachRules.mode(of: "SG-150"), .blockWithOverride)
        for id in ["SG-200", "TEAM-02", "TEAM-03"] { XCTAssertEqual(CoachRules.mode(of: id), .explainAfterwards, id) }
    }

    func testHeldMessageIsFriendlyAndOffersAWayOn() throws {
        let hint = try XCTUnwrap(SprintGoalRule.check(form: emptyGoal))
        let message = try XCTUnwrap(CoachMessages.held([hint]))
        XCTAssertEqual(message.secondaryButtonTitle, "Start anyway…")
        let text = message.sections.map(\.text).joined(separator: " ").lowercased()
        for blame in ["you forgot", "wrong", "error", "not allowed", "denied"] {
            XCTAssertFalse(text.contains(blame), blame)
        }
        XCTAssertTrue(text.contains("reason"))
        XCTAssertNil(CoachMessages.held([]))
    }
}
