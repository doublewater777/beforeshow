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

/// 从购票平台回来时，剪贴板换过内容且还没填链接，就去读一次（系统会询问是否允许粘贴）。
enum AddShowLinkReturnPaste {
    static func shouldRequest(seenChangeCount: Int, changeCount: Int, hasPasteable: Bool, linkText: String, isParsing: Bool) -> Bool {
        changeCount != seenChangeCount
            && hasPasteable
            && linkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isParsing
    }
}

struct AddShowLinkEntryView: View {
    @Binding var linkText: String
    let isParsingLink: Bool
    let failure: AddShowLinkFailurePresentation?
    let onParse: () -> Void
    let onRetry: () -> Void
    let onManual: () -> Void

    @State private var showsEmptyClipboardHint = false
    @State private var showsGuide = false
    @State private var seenPasteboardChange = UIPasteboard.general.changeCount

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

                AddShowLinkGuideRow {
                    dismissKeyboard()
                    showsGuide = true
                }
            }

            if let failure, !isParsingLink {
                AddShowLinkFailureCard(failure: failure, onRetry: onRetry, onManual: onManual)
            }
        }
        .sheet(isPresented: $showsGuide, onDismiss: pasteLinkCopiedElsewhere) {
            AddShowLinkGuideView()
        }
        // 在 sheet 里 scenePhase 不可靠，回到前台以应用通知为准。
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            guard !showsGuide else { return }
            pasteLinkCopiedElsewhere()
        }
    }
}

extension AddShowLinkEntryView {
    private func pasteLinkCopiedElsewhere() {
        let pasteboard = UIPasteboard.general
        guard AddShowLinkReturnPaste.shouldRequest(
            seenChangeCount: seenPasteboardChange,
            changeCount: pasteboard.changeCount,
            hasPasteable: pasteboard.hasStrings || pasteboard.hasURLs,
            linkText: linkText,
            isParsing: isParsingLink
        ) else { return }
        seenPasteboardChange = pasteboard.changeCount
        guard let copied = AddShowPasteboardLinkSuggestion.resolve(from: pasteboard.string ?? pasteboard.url?.absoluteString) else { return }
        showsEmptyClipboardHint = false
        linkText = copied.link
    }

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
