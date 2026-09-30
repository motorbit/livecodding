import Foundation
import Testing
@testable import TaskClient

struct TaskDTOTests {
    @Test("""
        Given a challenge-shaped task JSON with an id and due date,
        When it is decoded and mapped,
        Then every field maps to the domain task
        """)
    func decodesChallengeShapeIntoDomain() throws {
        let json = Data("""
            {
              "id": "00000000-0000-0000-0000-000000000001",
              "title": "Renew domain registration",
              "notes": "Expires end of month",
              "priority": "High",
              "done": false,
              "due_date": "2026-10-31"
            }
            """.utf8)

        let item = try JSONDecoder().decode(TaskDTO.self, from: json).toDomain()

        #expect(item == TaskItem(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: "Renew domain registration",
            notes: "Expires end of month",
            priority: .high,
            isComplete: false,
            dueDate: utcDay(2026, 10, 31)
        ))
    }

    @Test("""
        Given a task JSON without a due date,
        When it is decoded and mapped,
        Then the domain due date is nil
        """)
    func missingDueDateMapsToNil() throws {
        let json = Data("""
            {"id":"00000000-0000-0000-0000-000000000003","title":"Book dentist","notes":"","priority":"Low","done":true}
            """.utf8)

        let item = try JSONDecoder().decode(TaskDTO.self, from: json).toDomain()

        #expect(item.dueDate == nil)
        #expect(item.isComplete)
        #expect(item.priority == .low)
    }

    @Test("""
        Given every priority,
        When it is mapped to the wire format and back,
        Then it uses the challenge spelling and round-trips
        """)
    func priorityRoundTrips() {
        #expect(TaskPriority.allCases.map { PriorityDTO($0).rawValue } == ["Low", "Medium", "High"])
        for priority in TaskPriority.allCases {
            #expect(PriorityDTO(priority).domain == priority)
        }
    }

    @Test("""
        Given a task with a due date,
        When it is encoded,
        Then due_date is a UTC yyyy-MM-dd string and decoding restores the task
        """)
    func encodesDateOnlyAndRoundTrips() throws {
        let item = TaskItem(
            id: UUID(),
            title: "Pay rent",
            notes: "",
            priority: .medium,
            isComplete: true,
            dueDate: utcDay(2026, 1, 5)
        )

        let data = try JSONEncoder().encode(TaskDTO(item))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["due_date"] as? String == "2026-01-05")
        #expect(object["done"] as? Bool == true)
        #expect(object["priority"] as? String == "Medium")
        #expect(try JSONDecoder().decode(TaskDTO.self, from: data).toDomain() == item)
    }

    @Test("""
        Given a draft,
        When it is mapped to the request body,
        Then its fields and due date are carried over
        """)
    func draftMapsToRequestBody() {
        let draft = TaskDraft(title: "Call", notes: "Mum", priority: .high, dueDate: utcDay(2026, 12, 24))

        #expect(TaskDraftDTO(draft) == TaskDraftDTO(
            title: "Call",
            notes: "Mum",
            priority: .high,
            dueDate: "2026-12-24"
        ))
    }

    @Test("""
        Given a malformed due_date,
        When the DTO is mapped,
        Then it throws the unavailable error
        """)
    func malformedDueDateThrowsUnavailable() {
        let dto = TaskDTO(id: UUID(), title: "Bad", notes: "", priority: .low, done: false, dueDate: "31/10/2026")

        #expect(throws: TaskClientError.unavailable) {
            try dto.toDomain()
        }
    }

    private func utcDay(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
