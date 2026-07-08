import SwiftData
import XCTest
@testable import BeforeShow

final class ShowPreparationTests: XCTestCase {
    func testPreparationSuggestionsProvideChecklistItems() throws {
        let show = try Show(name: "准备测试现场", date: Date(), startTime: Date(), type: .concert)
        let sections = ShowPreparationGuide().sections(for: show)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertTrue(sections.allSatisfy { !$0.suggestions.isEmpty })
        XCTAssertTrue(sections.flatMap(\.suggestions).allSatisfy { !$0.text.isEmpty })
    }

    @MainActor
    func testPreparationPlanPersistsCheckedItemsReminderAndNotes() throws {
        let show = try Show(name: "音乐节", date: Date(), startTime: Date(), type: .musicFestival)
        let reminderDate = Date(timeIntervalSince1970: 1_779_552_000)
        let plan = ShowPreparationPlan(showID: show.id)
        let suggestion = ShowPreparationGuide()
            .sections(for: show)
            .flatMap(\.suggestions)
            .first!

        plan.setChecked(true, suggestionText: suggestion.text)
        plan.updateReminderDate(reminderDate)
        plan.updateNotes("  记得带身份证和耳塞  ")

        let container = try ModelContainer(
            for: Show.self, ShowPreparationPlan.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(show)
        container.mainContext.insert(plan)
        try container.mainContext.save()

        let plans = try container.mainContext.fetch(FetchDescriptor<ShowPreparationPlan>())
        XCTAssertEqual(plans[0].showID, show.id)
        XCTAssertTrue(plans[0].isChecked(suggestion.text))
        XCTAssertEqual(plans[0].reminderDate, reminderDate)
        XCTAssertEqual(plans[0].notes, "记得带身份证和耳塞")
    }
}
