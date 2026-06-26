import XCTest
@testable import DayBarCore

final class HabitReminderMappingTests: XCTestCase {
    private let templateId = UUID()

    func testNotesMarkerRoundTrip() {
        let notes = HabitReminderMapping.buildNotes(templateId: templateId, cueText: "After coffee")
        XCTAssertTrue(notes.contains(HabitReminderMapping.notesPrefix))
        XCTAssertEqual(HabitReminderMapping.parseTemplateId(from: notes), templateId)
    }

    func testShouldApplyRemoteWhenLocalMissing() {
        let template = HabitTemplate(id: templateId, title: "Read")
        let dto = HabitReminderDTO(
            externalIdentifier: "ext-1",
            templateId: templateId,
            title: "Read more",
            modifiedAt: Date()
        )
        XCTAssertTrue(HabitReminderMapping.shouldApplyRemote(dto, over: template))
    }

    func testApplyCompletionMarksLogCompleted() {
        let log = HabitLog(templateId: templateId, day: .now, status: .pending)
        HabitReminderMapping.applyCompletion(remoteCompleted: true, completionDate: .now, to: log, today: .now)
        XCTAssertTrue(log.isCompleted)
    }
}