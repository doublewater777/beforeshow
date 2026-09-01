import Foundation
import SwiftUI

// MARK: - Add Show Coordinator

enum AddShowSheet: String, Identifiable, Hashable, CaseIterable {
    case manual
    case screenshot
    case link

    var id: String { rawValue }
}

enum AddShowMethodCopy {
    case manual
    case screenshot
    case link

    var subtitle: String {
        switch self {
        case .manual:
            return BSLocalization.text("自己填写现场的基本信息。")
        case .screenshot:
            return BSLocalization.text("选择票务截图，仅在本机识别，图片不会上传。")
        case .link:
            return BSLocalization.text("粘贴支持平台的票务链接，需要联网解析。")
        }
    }
}

struct AddShowCoordinatorSheet: View {
    /// Skip method picker and open a specific flow. Only for tests / deep links — normal entry leaves this nil.
    var initialSheet: AddShowSheet? = nil
    var onShowAdded: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedSheet: AddShowSheet?

    init(
        initialSheet: AddShowSheet? = nil,
        onShowAdded: @escaping (UUID) -> Void = { _ in }
    ) {
        self.initialSheet = initialSheet
        self.onShowAdded = onShowAdded
        _selectedSheet = State(initialValue: initialSheet)
    }

    var body: some View {
        NavigationStack {
            AddShowEntryView(methods: AddShowConfiguration.methodOrder) { sheet in
                selectedSheet = sheet
            }
            .navigationTitle(AddShowConfiguration.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: "取消") { dismiss() }
            }
            .navigationDestination(item: $selectedSheet) { sheet in
                AddShowFlowView(
                    sheet: sheet,
                    onSaved: onShowAdded,
                    onFinished: { dismiss() }
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

enum AddShowConfiguration {
    static let methodOrder: [AddShowSheet] = [.link, .screenshot, .manual]
    static var navigationTitle: String { BSLocalization.text("添加现场") }
    static var saveButtonTitle: String { navigationTitle }

    static func initialManualDraft(now: Date = Date(), calendar: Calendar = .current) -> ShowDraft {
        let today = calendar.startOfDay(for: now)
        let startTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today)
        return ShowDraft(date: today, startTime: startTime, source: .manual)
    }
}

private struct AddShowEntryView: View {
    let methods: [AddShowSheet]
    let onSelect: (AddShowSheet) -> Void

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: BSSpacing.lg) {
                        Text("三种方式任选，识别出的内容保存前都能改。")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textTertiary)
                            .lineSpacing(3)

                        VStack(spacing: BSSpacing.md) {
                            ForEach(methods) { method in
                                AddShowMethodCard(
                                    title: method.navigationTitle,
                                    subtitle: method.methodSubtitle,
                                    iconName: method.iconName,
                                    tint: method.tint
                                ) {
                                    onSelect(method)
                                }
                            }
                        }

                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct AddShowMethodCard: View {
    let title: String
    let subtitle: String
    let iconName: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: BSSpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(tint.opacity(0.13))
                    Image(systemName: iconName)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(maxHeight: .infinity)
            }
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(BSColor.Stage.surface)
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .overlay(
                RoundedRectangle(cornerRadius: 22)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

extension AddShowSheet {
    var navigationTitle: String {
        switch self {
        case .manual: return BSLocalization.text("手动填写")
        case .screenshot: return BSLocalization.text("截图识别")
        case .link: return BSLocalization.text("链接解析")
        }
    }

    var draftSource: ShowDraftSource {
        switch self {
        case .manual: return .manual
        case .screenshot: return .screenshotOCR
        case .link: return .link
        }
    }

    var methodSubtitle: String {
        switch self {
        case .manual: return AddShowMethodCopy.manual.subtitle
        case .screenshot: return AddShowMethodCopy.screenshot.subtitle
        case .link: return AddShowMethodCopy.link.subtitle
        }
    }

    var iconName: String {
        switch self {
        case .manual: return "square.and.pencil"
        case .screenshot: return "camera.fill"
        case .link: return "link"
        }
    }

    var tint: Color {
        switch self {
        case .manual: return BSColor.Accent.prepare
        case .screenshot: return BSColor.Accent.violet
        case .link: return BSColor.Stage.accent
        }
    }
}
