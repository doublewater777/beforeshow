import Foundation
import SwiftUI

// MARK: - Save Bar State

/// 保存栏唯一的状态行：说明还差什么、保存失败原因或额度已满。
/// 错误只在这里出现一次，不再同时弹 toast / 底部说明卡。
enum AddShowSaveBarStatus: Equatable {
    case importing(isLink: Bool)
    case missingName
    case needsDateConfirmation
    case missingStartTime
    case invalidEndTime
    case needsLifecycleChoice
    case atFreeCapacity
    case failure(String)

    struct Input: Equatable {
        var isParsingLink = false
        var isRecognizingScreenshot = false
        var nameIsEmpty = false
        var needsDateConfirmation = false
        var hasStartTime = true
        var hasValidEndTime = true
        var needsLifecycleChoice = false
        var isAtFreeCapacity = false
        var failure: String?
    }

    static func resolve(_ input: Input) -> AddShowSaveBarStatus? {
        if input.isParsingLink || input.isRecognizingScreenshot {
            return .importing(isLink: input.isParsingLink)
        }
        if input.nameIsEmpty { return .missingName }
        if input.needsDateConfirmation { return .needsDateConfirmation }
        if !input.hasStartTime { return .missingStartTime }
        if !input.hasValidEndTime { return .invalidEndTime }
        if input.needsLifecycleChoice { return .needsLifecycleChoice }
        if let failure = input.failure { return .failure(failure) }
        if input.isAtFreeCapacity { return .atFreeCapacity }
        return nil
    }

    /// 额度已满不挡按钮：按钮改为「升级后添加」，直接打开付费页。
    var blocksSave: Bool {
        switch self {
        case .failure, .atFreeCapacity: return false
        default: return true
        }
    }

    var text: String {
        switch self {
        case .importing(let isLink):
            return isLink ? BSLocalization.text("正在解析链接…") : BSLocalization.text("正在识别截图…")
        case .missingName:
            return BSLocalization.text("还差现场名称")
        case .needsDateConfirmation:
            return BSLocalization.text("还差确认开场日期 · 截图没读到日期，已先填今天")
        case .missingStartTime:
            return BSLocalization.text("还差开场时间 · 用于开场前提醒，可先填大概时间")
        case .invalidEndTime:
            return BSLocalization.text("时间范围无效，结束时间需要晚于开始时间")
        case .needsLifecycleChoice:
            return BSLocalization.text("还差确认这场是否已经结束")
        case .atFreeCapacity:
            return ProLimitReason.hardCapLimit.title
        case .failure(let message):
            return message
        }
    }

    var isError: Bool {
        switch self {
        case .invalidEndTime, .failure: return true
        default: return false
        }
    }
}

/// 保存成功后按钮内的一次轻反馈：告诉用户这场去了哪里。
enum AddShowSavedFeedback {
    static func title(for outcome: AddShowSaveOutcome, showDate: Date, calendar: Calendar) -> String {
        switch outcome {
        case .current:
            return BSLocalization.text("已设为当前现场")
        case .footprint:
            return BSLocalization.text("已放进足迹")
        case .future:
            var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return BSLocalization.format("已加入 · %@", showDate.formatted(style))
        }
    }
}

// MARK: - Save Bar

struct AddShowSaveBar: View {
    let status: AddShowSaveBarStatus?
    let isSaving: Bool
    let savedTitle: String?
    let action: () -> Void

    private var title: String {
        if let savedTitle { return savedTitle }
        if isSaving { return BSLocalization.text("正在保存") }
        if status == .atFreeCapacity { return BSLocalization.text("升级后添加") }
        return AddShowConfiguration.saveButtonTitle
    }

    var body: some View {
        VStack(spacing: 10) {
            if let status, savedTitle == nil {
                Text(status.text)
                    .font(BSFont.caption)
                    .foregroundStyle(status.isError ? BSColor.Accent.danger : BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .transition(.opacity)
            }

            Button(action: action) {
                HStack(spacing: BSSpacing.sm) {
                    if savedTitle != nil {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                    } else if isSaving {
                        ProgressView()
                            .tint(BSColor.Stage.background)
                    }
                    Text(title)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .disabled(isSaving || (savedTitle == nil && (status?.blocksSave ?? false)))
            .allowsHitTesting(savedTitle == nil)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .animation(.easeInOut(duration: BSMotion.interface), value: status)
        .animation(.easeInOut(duration: BSMotion.interface), value: savedTitle)
    }
}

// MARK: - Failure Analytics

/// 埋点用的稳定原因码：只用错误类型与错误码，不带链接、名称等用户内容。
enum AddShowFailureReason {
    static func code(for error: Error) -> String {
        if let error = error as? ShowLinkParsingError {
            switch error {
            case .unsupportedSource: return "unsupported_source"
            case .networkFailure: return "network_failure"
            case .invalidResponse: return "invalid_response"
            case .notAShow: return "not_a_show"
            case .parseFailed: return "parse_failed"
            }
        }
        if let error = error as? ShowLinkDraftParser.ParseError {
            switch error {
            case .unsupportedSource: return "unsupported_source"
            case .missingDate: return "missing_date"
            }
        }
        if let error = error as? ShowValidationError {
            return "validation_\(error)"
        }
        let nsError = error as NSError
        return "\(nsError.domain)#\(nsError.code)"
    }
}

extension AddShowSaveBarStatus {
    var analyticsValue: String {
        switch self {
        case .importing: return "importing"
        case .missingName: return "missing_name"
        case .needsDateConfirmation: return "needs_date_confirmation"
        case .missingStartTime: return "missing_start_time"
        case .invalidEndTime: return "invalid_end_time"
        case .needsLifecycleChoice: return "needs_lifecycle_choice"
        case .atFreeCapacity: return "at_free_capacity"
        case .failure: return "save_failed"
        }
    }
}
