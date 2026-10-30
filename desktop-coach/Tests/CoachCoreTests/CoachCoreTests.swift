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

    func testTestModeCoachesAnyTextField() {
        XCTAssertTrue(CoachScope.shouldCoach(field(url: nil, label: ""), anyApp: true))
    }
}

final class PlanningRulesTests: XCTestCase {
    private let jira = FieldInfo(appBundleID: "com.apple.Safari", pageURL: "https://leanig.atlassian.net/jira",
                                 role: "AXTextField", subrole: nil, label: "")
    private let settings = CoachSettings(averageVelocity: 10)

    private func outcome(label: String, text: String, form: [FormField] = [], changed: Bool = true,
                         nextLabel: String? = nil) -> CoachOutcome {
        var field = jira
        field.label = label
        return CoachRules.check(field: field, text: text, form: form, changed: changed, settings: settings,
                                nextLabel: nextLabel)
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

    func testEmptySprintGoalGetsAHintFromAnyDialogField() throws {
        // The goal is never typed, so the check runs even when the field left wasn't changed.
        let found = try XCTUnwrap(hint(outcome(label: "Sprint name", text: "CT Sprint 4", form: startSprintDialog, changed: false)))
        XCTAssertEqual(found.ruleID, "SG-150")
        XCTAssertEqual(found.dedupeKey, "SG-150|CT Sprint 4")
    }

    func testFilledSprintGoalIsFine() {
        var form = startSprintDialog
        form[2] = FormField(label: "Sprint goal", text: "Customers can pay with iDEAL")
        XCTAssertNil(SprintGoalRule.check(form: form))
        if case .fine = outcome(label: "Sprint goal", text: "Customers can pay with iDEAL", form: form) {} else { XCTFail("expected fine") }
    }

    // Test round 1 (2026-10-30)

    func testClickingIntoTheEmptyGoalFieldWaits() {
        // Issue 2: clicking the Sprint goal field right away means she's about to fill it in.
        XCTAssertEqual(outcome(label: "Sprint name", text: "CT Sprint 4", form: startSprintDialog,
                               changed: false, nextLabel: "Sprint goal"), .notApplicable)
        // Leaving the goal field empty, or tabbing to another field, still gets the tip.
        XCTAssertNotNil(hint(outcome(label: "Sprint goal", text: "", form: startSprintDialog,
                                     changed: false, nextLabel: "Start date")))
    }

    func testFilledGoalReportsTheSameKeySoADeletedGoalIsExplainedAgain() throws {
        // Issue 1: add a goal, delete it, tab on: the tip comes back.
        let first = try XCTUnwrap(hint(outcome(label: "Sprint name", text: "CT Sprint 4", form: startSprintDialog, changed: false)))
        var filled = startSprintDialog
        filled[2] = FormField(label: "Sprint goal", text: "Customers can pay with iDEAL")
        guard case .fine(_, let key) = outcome(label: "Sprint goal", text: "Customers can pay with iDEAL", form: filled) else {
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
        ]
        for found in hints {
            // The source line quotes the Guide verbatim; the coach's own words must stay friendly.
            let own = [found.what, found.why, found.how].joined(separator: " ").lowercased()
            for blame in ["you forgot", "wrong", "error", "failed", "must", "not allowed"] {
                XCTAssertFalse(own.contains(blame), "\(found.ruleID) unfriendly word: \(blame)")
            }
            XCTAssertTrue(found.source.contains("Scrum Guide 2020"))
        }
    }
}
