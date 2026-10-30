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
        XCTAssertFalse(CoachScope.shouldCoach(field(label: "Assignee"), anyApp: false))
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
