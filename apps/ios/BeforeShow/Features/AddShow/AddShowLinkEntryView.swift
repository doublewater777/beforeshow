import SwiftUI
import UIKit

// MARK: - Link Entry

/// 粘贴进来的是受支持平台的完整链接时直接开始解析；逐字输入不会触发。
enum AddShowLinkPasteDetection {
    static func shouldAutoParse(previous: String, current: String) -> Bool {
        previous.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && AddShowPasteboardLinkSuggestion.resolve(from: current) != nil
    }
}

struct AddShowLinkEntryView: View {
    @Binding var linkText: String
    let isParsingLink: Bool
    let failure: AddShowLinkFailurePresentation?
    let onParse: () -> Void
    let onRetry: () -> Void
    let onManual: () -> Void
    let onOpenGuide: () -> Void

    @State private var showsEmptyClipboardHint = false

    private var detectedLinkSource: String? {
        AddShowPasteboardLinkSuggestion.resolve(from: linkText)?.platform
    }

    private var hasText: Bool {
        !linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            EditShowFormCard(
                title: BSLocalization.text("粘贴购票链接"),
                icon: "link",
                tint: BSColor.Stage.foreground
            ) {
                if !hasText {
                    AddShowLinkHowToSteps()
                }

                AddShowMultilineInput(
                    placeholder: BSLocalization.text("在这里粘贴链接"),
                    text: $linkText,
                    minHeight: 64,
                    keyboardType: .URL
                )
                .disabled(isParsingLink)
                .opacity(isParsingLink ? 0.55 : 1)

                if let detectedLinkSource {
                    Label(
                        BSLocalization.format("已识别来源：%@", detectedLinkSource),
                        systemImage: "checkmark"
                    )
                    .font(BSFont.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                }

                if hasText {
                    Button(action: onParse) {
                        HStack(spacing: BSSpacing.sm) {
                            if isParsingLink {
                                ProgressView()
                                    .tint(BSColor.Stage.background)
                            }
                            Text(isParsingLink ? BSLocalization.text("正在识别…") : BSLocalization.text("识别链接"))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditShowSaveButtonStyle())
                    .disabled(isParsingLink)
                } else {
                    Button(action: pasteFromClipboard) {
                        Label(BSLocalization.text("粘贴链接"), systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(EditShowSaveButtonStyle())

                    if showsEmptyClipboardHint {
                        Text(BSLocalization.text("剪贴板里还没有链接，先在购票 App 里复制"))
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.Stage.accent)
                    }
                }

                AddShowLinkGuideRow(onOpenGuide: onOpenGuide)
            }

            if let failure, !isParsingLink {
                AddShowLinkFailureCard(failure: failure, onRetry: onRetry, onManual: onManual)
            }
        }
    }
}

extension AddShowLinkEntryView {
    /// 只在用户点按钮时读剪贴板；系统可能询问一次是否允许粘贴。
    private func pasteFromClipboard() {
        guard let pasted = AddShowPasteboardLinkSuggestion.pasteableLink(from: UIPasteboard.general.string) else {
            showsEmptyClipboardHint = true
            return
        }
        showsEmptyClipboardHint = false
        linkText = pasted
    }
}

/// 用户心智是「我在购票 App 里」，所以步骤从那里讲起，而不是从本页讲起。
private struct AddShowLinkHowToSteps: View {
    private let steps = [
        BSLocalization.text("在购票 App 打开演出页"),
        BSLocalization.text("点「分享」，再点「复制链接」"),
        BSLocalization.text("回到这里粘贴")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .frame(width: 20, height: 20)
                        .background(BSColor.Stage.surfaceRaised, in: Circle())
                        .overlay(Circle().strokeBorder(BSColor.Stage.border, lineWidth: 1))
                    Text(step)
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AddShowLinkGuideRow: View {
    let onOpenGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Text(BSLocalization.format("目前支持：%@", ShowLinkPlatformCatalog.supportSummary))
                .font(BSFont.caption)
                .foregroundStyle(BSColor.Stage.dim)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenGuide) {
                HStack(spacing: 6) {
                    Text(BSLocalization.text("还没有链接？去购票平台找"))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BSColor.Stage.foreground)
                .frame(minHeight: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
