import Foundation
import SwiftData

struct ShowPreparationSection: Equatable, Identifiable {
    let id: UUID
    let title: String
    let suggestions: [ShowPreparationSuggestion]

    init(id: UUID = UUID(), title: String, suggestions: [ShowPreparationSuggestion]) {
        self.id = id
        self.title = title
        self.suggestions = suggestions
    }
}

struct ShowPreparationSuggestion: Equatable, Identifiable {
    let id: UUID
    let text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

struct ShowPreparationGuide {
    func sections(for show: Show) -> [ShowPreparationSection] {
        var comfort = [
            ShowPreparationSuggestion(text: "按当天温度留一件好收纳的外套，排队和散场时会更从容。"),
            ShowPreparationSuggestion(text: "提前确认场馆对水杯、雨具和大件包的规则，少带难处理的东西。")
        ]

        if show.type == .musicFestival {
            comfort.append(
                ShowPreparationSuggestion(text: "音乐节停留时间更长，可以准备防晒、轻便雨具和能坐下休息的小垫子。")
            )
        }

        return [
            ShowPreparationSection(
                title: "天气和体感",
                suggestions: comfort
            ),
            ShowPreparationSection(
                title: "现场礼仪",
                suggestions: [
                    ShowPreparationSuggestion(text: "拍摄时留意身后视线，想记录也别挡住别人看向舞台。"),
                    ShowPreparationSuggestion(text: "散场人多时慢一点，先和同行的人约好汇合点。")
                ]
            ),
            ShowPreparationSection(
                title: "注意事项",
                suggestions: [
                    ShowPreparationSuggestion(text: "把入场凭证、身份证件和必要电量提前确认好，到了门口就不用慌。"),
                    ShowPreparationSuggestion(text: "如果返程还没定，至少先记下散场后的集合点或大致方向。")
                ]
            )
        ]
    }
}

@Model
final class ShowPreparationPlan {
    var id: UUID
    var showID: UUID
    var checkedSuggestionTexts: [String]
    var reminderDate: Date?
    var notes: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        showID: UUID,
        checkedSuggestionTexts: [String] = [],
        reminderDate: Date? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.showID = showID
        self.checkedSuggestionTexts = Self.normalizedCheckedTexts(checkedSuggestionTexts)
        self.reminderDate = reminderDate
        self.notes = Self.trimmedOptional(notes)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func setChecked(_ isChecked: Bool, suggestionText: String) {
        let normalized = suggestionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        var checked = Set(checkedSuggestionTexts)
        if isChecked {
            checked.insert(normalized)
        } else {
            checked.remove(normalized)
        }
        checkedSuggestionTexts = checked.sorted()
        touch()
    }

    func updateReminderDate(_ date: Date?) {
        reminderDate = date
        touch()
    }

    func updateNotes(_ value: String?) {
        notes = Self.trimmedOptional(value)
        touch()
    }

    func isChecked(_ suggestionText: String) -> Bool {
        checkedSuggestionTexts.contains(suggestionText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func touch() {
        updatedAt = Date()
    }

    private static func normalizedCheckedTexts(_ values: [String]) -> [String] {
        Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }

    private static func trimmedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
