import XCTest
@testable import DayBarCore

final class HabitNotifySignatureTests: XCTestCase {
    func testSignatureStableForUnchangedInputs() {
        let template = HabitTemplate(title: "Read", anchorHour: 9, anchorMinute: 0, notifyEnabled: true)
        let log = HabitLog(templateId: template.id, day: .now, status: .pending)
        let first = HabitNotifySignature.make(
            templates: [template], todayLogs: [log], habitNotifyEnabled: true
        )
        let second = HabitNotifySignature.make(
            templates: [template], todayLogs: [log], habitNotifyEnabled: true
        )
        XCTAssertEqual(first, second)
    }

    func testSignatureChangesWhenLogCompleted() {
        let template = HabitTemplate(title: "Read")
        let pending = HabitLog(templateId: template.id, day: .now, status: .pending)
        let completed = HabitLog(templateId: template.id, day: .now, status: .completed)
        let before = HabitNotifySignature.make(
            templates: [template], todayLogs: [pending], habitNotifyEnabled: true
        )
        let after = HabitNotifySignature.make(
            templates: [template], todayLogs: [completed], habitNotifyEnabled: true
        )
        XCTAssertNotEqual(before, after)
    }
}