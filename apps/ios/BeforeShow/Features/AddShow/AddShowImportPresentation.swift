import SwiftUI
import UIKit

// MARK: - Add Show Import Presentation

struct AddShowLinkFailurePresentation: Equatable {
    let title: String
    let message: String

    static func resolve(_ error: Error) -> Self {
        if let parserError = error as? ShowLinkDraftParser.ParseError {
            switch parserError {
            case .unsupportedSource:
                return Self(
                    title: BSLocalization.text("这个链接暂不支持"),
                    message: BSLocalization.format("目前支持：%@。可以改用手动填写。", ShowLinkPlatformCatalog.supportSummary)
                )
            case .missingDate:
                return Self(
                    title: BSLocalization.text("还缺少现场信息"),
                    message: BSLocalization.text("没有解析到有效日期。可以改用手动填写，把日期补上再保存。")
                )
            }
        }

        guard let parsingError = error as? ShowLinkParsingError else {
            return Self(
                title: BSLocalization.text("链接解析失败"),
                message: BSLocalization.text("暂时没能读出完整信息。可以重试，或改用手动填写。")
            )
        }

        switch parsingError {
        case .unsupportedSource:
            return Self(
                title: BSLocalization.text("这个链接暂不支持"),
                message: BSLocalization.format("目前支持：%@。可以改用手动填写。", ShowLinkPlatformCatalog.supportSummary)
            )
        case .networkFailure:
            return Self(
                title: BSLocalization.text("网络连接失败"),
                message: BSLocalization.text("请检查网络后重试，已经填写的内容会保留。")
            )
        case .invalidResponse:
            return Self(
                title: BSLocalization.text("还缺少现场信息"),
                message: BSLocalization.text("没有解析到有效日期。可以改用手动填写，把日期补上再保存。")
            )
        case .notAShow:
            return Self(
                title: BSLocalization.text("这不是演出链接"),
                message: BSLocalization.text("这个链接指向的是周边商品，没有演出场次信息。可以换个演出链接重试，或改用手动填写。")
            )
        case .parseFailed:
            return Self(
                title: BSLocalization.text("链接解析失败"),
                message: BSLocalization.text("暂时没能读出完整信息。可以重试，或改用手动填写。")
            )
        }
    }
}

struct AddShowPasteboardLinkSuggestion: Equatable {
    let link: String
    let platform: String

    static func resolve(from raw: String?) -> Self? {
        guard let raw else { return nil }
        let candidate = ShowLinkDraftParser.normalizedLink(raw)
        guard !candidate.isEmpty,
              let host = URL(string: candidate)?.host()?.lowercased(),
              let platform = ShowLinkPlatformCatalog.displayName(forHost: host) else { return nil }
        return Self(link: candidate, platform: platform)
    }

    static func pasteableLink(from raw: String?) -> String? {
        if let resolved = resolve(from: raw) {
            return resolved.link
        }
        guard let raw else { return nil }
        let candidate = ShowLinkDraftParser.normalizedLink(raw)
        return candidate.isEmpty ? nil : candidate
    }

    static func shouldOfferClipboardChip(
        hasClipboardText: Bool,
        linkText: String,
        hasImportedDraft: Bool
    ) -> Bool {
        hasClipboardText
            && !hasImportedDraft
            && linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AddShowPasteOffer: Equatable {
    case knownPlatform(AddShowPasteboardLinkSuggestion)
    case clipboardText

    var chipTitle: String {
        switch self {
        case .knownPlatform(let suggestion):
            return BSLocalization.format("粘贴%@链接？", suggestion.platform)
        case .clipboardText:
            return BSLocalization.text("粘贴剪贴板里的链接？")
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .knownPlatform(let suggestion):
            return BSLocalization.format("粘贴%@链接并开始解析", suggestion.platform)
        case .clipboardText:
            return BSLocalization.text("粘贴剪贴板里的链接并开始解析")
        }
    }
}

struct AddShowMultilineInput: View {
    let placeholder: String
    @Binding var text: String
    var minHeight: CGFloat
    var keyboardType: UIKeyboardType = .default

    var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textTertiary.opacity(0.74))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }

            TextEditor(text: $text)
                .font(BSFont.body)
                .foregroundColor(BSColor.textPrimary)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .textContentType(keyboardType == .URL ? .URL : nil)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(minHeight: minHeight)
        }
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}

struct AddShowNoteCard: View {
    let text: String
    let iconName: String

    var body: some View {
        HStack(alignment: .top, spacing: BSSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
                .frame(width: 18, height: 18)
            Text(text)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(BSColor.textTertiary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}

struct AddShowLinkFailureCard: View {
    let failure: AddShowLinkFailurePresentation
    let onRetry: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(BSColor.Accent.danger.opacity(0.14))
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Accent.danger)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(failure.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                    Text(failure.message)
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.textTertiary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Button(action: onRetry) {
                    Text(BSLocalization.text("换个链接重试"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.white.opacity(0.07))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: onManual) {
                    Text(BSLocalization.text("改用手动填写"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(BSColor.Stage.accent.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(BSColor.Stage.accent.opacity(0.30), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Label("已填写的内容会保留，不用重打", systemImage: "checkmark")
                .font(.system(size: 11.5))
                .foregroundColor(BSColor.Accent.prepare)
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.danger.opacity(0.08),
                    BSColor.Accent.danger.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.danger.opacity(0.26), lineWidth: 1)
        )
    }
}

struct AddShowImportedBanner: View {
    let source: AddShowSheet

    private var sourceName: String {
        source == .link ? BSLocalization.text("链接") : BSLocalization.text("截图")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Accent.prepare)

            Text(BSLocalization.format("已从%@识别出信息，请核对；金色标出的还需补充。", sourceName))
                .font(.system(size: 12.5))
                .foregroundColor(Color(red: 0.79, green: 0.92, blue: 0.87))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Accent.prepare.opacity(0.11),
                    BSColor.Stage.accent.opacity(0.06)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(BSColor.Accent.prepare.opacity(0.28), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

struct AddShowOCRStepsView: View {
    /// 当前进行中的步骤（1...4）；0 表示未开始。
    let activeStep: Int

    private let steps = [BSLocalization.text("读取截图"), BSLocalization.text("提取文字"), BSLocalization.text("整理现场信息"), BSLocalization.text("生成可编辑草稿")]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                let step = index + 1
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(stepBackground(for: step))
                        if step < activeStep {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(BSColor.Accent.prepare)
                        } else if step == activeStep {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(BSColor.Accent.violet)
                        } else {
                            Text("\(step)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(BSColor.Stage.dim)
                        }
                    }
                    .frame(width: 26, height: 26)

                    Text(title)
                        .font(.system(size: 13, weight: step == activeStep ? .medium : .regular))
                        .foregroundColor(stepForeground(for: step))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stepBackground(for step: Int) -> Color {
        if step < activeStep {
            return BSColor.Accent.prepare.opacity(0.15)
        } else if step == activeStep {
            return BSColor.Accent.violet.opacity(0.16)
        }
        return Color.white.opacity(0.06)
    }

    private func stepForeground(for step: Int) -> Color {
        if step < activeStep {
            return BSColor.textTertiary
        } else if step == activeStep {
            return BSColor.textPrimary
        }
        return BSColor.Stage.dim
    }
}
