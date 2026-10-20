import Foundation
import SwiftUI

// MARK: - Add Show Coordinator

enum AddShowSheet: String, Identifiable, Hashable, CaseIterable {
    case manual
    case screenshot
    case link

    var id: String { rawValue }
}

struct AddShowCoordinatorSheet: View {
    /// Open a specific import method for deep links; normal entry starts with the unified importer.
    var initialSheet: AddShowSheet? = nil
    var onShowAdded: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AddShowFlowView(
                sheet: initialSheet ?? .link,
                onSaved: { showID in
                    onShowAdded(showID)
                    dismiss()
                }
            )
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: "取消", placement: .topBarTrailing) { dismiss() }
            }
            // $screen 上报放在 NavigationStack 这一层：AddShowFlowView 已到行数上限。
            // initialSheet ?? .link 与 AddShowFlowView 的实际初始 method 一致。
            .bsScreenView("add_show_\((initialSheet ?? .link).rawValue)")
        }
        .preferredColorScheme(.dark)
    }
}

enum AddShowConfiguration {
    static var navigationTitle: String { BSLocalization.text("添加现场") }
    static var saveButtonTitle: String { navigationTitle }

    static func initialManualDraft(now: Date = Date(), calendar: Calendar = .current) -> ShowDraft {
        let today = calendar.startOfDay(for: now)
        let startTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today)
        return ShowDraft(date: today, startTime: startTime, source: .manual)
    }
}

extension AddShowSheet {
    var draftSource: ShowDraftSource {
        switch self {
        case .manual: return .manual
        case .screenshot: return .screenshotOCR
        case .link: return .link
        }
    }
}
