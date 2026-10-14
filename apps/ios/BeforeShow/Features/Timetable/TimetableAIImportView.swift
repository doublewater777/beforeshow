import SwiftUI
import UIKit

/// Copy the recognition prompt, run it in any AI tool with the timetable
/// images, then paste the result back. Pasted text is kept on failure.
struct TimetableAIImportView: View {
    let onImport: (String) throws -> Void

    @State private var text = ""
    @State private var error: TimetableImportError?
    @State private var didCopy = false
    @State private var clipboardSuggestion: String?
    @FocusState private var isEditorFocused: Bool

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let suggestion = clipboardSuggestion, text.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(TimetableStyle.mine)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(BSLocalization.text("检测到剪贴板中含有排期数据"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(TimetableStyle.foreground)
                            Text(BSLocalization.text("轻点直接填入，省去手动粘贴"))
                                .font(.system(size: 11))
                                .foregroundStyle(TimetableStyle.dim)
                        }
                        Spacer(minLength: 0)
                        Button(BSLocalization.text("填入")) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                text = suggestion
                                clipboardSuggestion = nil
                            }
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(TimetableStyle.mine)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(TimetableStyle.mine.opacity(0.18)))
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(TimetableStyle.mine)
                    Text(BSLocalization.text("支持配合外部工具生成排期结果，粘贴后即可一键导入。"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TimetableStyle.dim)
                        .lineSpacing(3)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                step(1, BSLocalization.text("复制识别指令")) {
                    Button(action: copyPrompt) {
                        Label(
                            BSLocalization.text(didCopy ? "已复制识别指令" : "复制识别指令"),
                            systemImage: didCopy ? "checkmark" : "doc.on.doc"
                        )
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TimetableStyle.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                    }
                    .buttonStyle(TimetablePressStyle())
                    .sensoryFeedback(.success, trigger: didCopy) { _, copied in copied }
                }

                step(2, BSLocalization.text("在外部工具中上传时刻表图片并发送指令"))

                step(3, BSLocalization.text("粘贴识别结果")) {
                    editor
                    if let error {
                        Label(Self.message(for: error), systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(TimetableStyle.attention)
                            .padding(.top, 4)
                            .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            Button(action: submit) {
                Text(BSLocalization.text("继续"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TimetableStyle.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(TimetableStyle.foreground))
            }
            .buttonStyle(TimetablePressStyle())
            .disabled(trimmedText.isEmpty)
            .opacity(trimmedText.isEmpty ? 0.35 : 1)
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .background(TimetableStyle.background.ignoresSafeArea())
        .onChange(of: text) { _, _ in error = nil }
        .onAppear {
            checkClipboard()
            #if DEBUG
            if let sample = ProcessInfo.processInfo.environment["BS_TIMETABLE_IMPORT_SAMPLE"] { text = sample }
            #endif
        }
    }

    private func checkClipboard() {
        guard text.isEmpty, UIPasteboard.general.hasStrings, let string = UIPasteboard.general.string else { return }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.contains("timetable") || trimmed.contains("stages") || trimmed.contains("performances") || trimmed.contains("stage")) && trimmed.count > 15 {
            clipboardSuggestion = trimmed
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(BSLocalization.text("将生成的识别结果粘贴到这里"))
                    .foregroundStyle(TimetableStyle.dim)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .focused($isEditorFocused)
                .scrollContentBackground(.hidden)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(TimetableStyle.foreground)
                .padding(.bottom, 44)
        }
        .font(TimetableStyle.mono(13))
        .frame(height: 180)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(TimetableStyle.card))
        .overlay(alignment: .bottomTrailing) {
            PasteButton(payloadType: String.self) { strings in
                guard let pasted = strings.first else { return }
                Task { @MainActor in text = pasted }
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.capsule)
            .tint(Color.white.opacity(0.16))
            .padding(10)
        }
    }

    private func step<Content: View>(
        _ number: Int,
        _ title: String,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)")
                    .font(TimetableStyle.mono(13, weight: .bold))
                    .foregroundStyle(TimetableStyle.background)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(TimetableStyle.foreground))
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
            }
            content()
        }
    }

    private func copyPrompt() {
        UIPasteboard.general.string = TimetableImportPrompt.text
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    private func submit() {
        isEditorFocused = false
        do {
            try onImport(text)
        } catch let importError as TimetableImportError {
            error = importError
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } catch {
            self.error = .invalidFormat
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    static func message(for error: TimetableImportError) -> String {
        let key = switch error {
        case .empty: "请先粘贴识别结果"
        case .noData: "未找到有效的时刻表数据"
        case .invalidFormat: "识别结果格式有误，请重新生成或检查内容"
        case .unsupportedVersion: "当前格式暂不支持，请使用新版识别指令重新生成"
        case .tooLarge: "识别结果内容过多，请分批导入"
        case .invalidTimeZone: "识别结果中的时区无效，请检查内容"
        case .missingDate: "识别结果缺少演出日期，请重新生成或检查内容"
        case .invalidDate: "识别结果中的日期有误，请检查内容"
        case .noSchedule: "识别结果中没有可导入的演出，请检查内容"
        case .conflictingDays: "识别结果中相邻两天的演出时间重叠，请检查内容"
        }
        return BSLocalization.text(key)
    }
}

/// The recognition prompt, localized per app language and kept in step with
/// `TimetableExchangeDocument.supportedVersion`.
enum TimetableImportPrompt {
    static var text: String {
        NSLocalizedString("recognitionPrompt", tableName: "TimetableImport", bundle: .main, comment: "")
    }
}
