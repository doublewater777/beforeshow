import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct FeedbackView: View {
    @State private var message = ""
    @State private var includesDiagnostics = false
    @State private var validationMessage: String?
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()
    private let shareTextBuilder = FeedbackShareTextBuilder()

    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: nil,
            bottomPadding: BSSpacing.xl
        ) {
            BSSettingsSurface(padding: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    HStack(alignment: .firstTextBaseline, spacing: BSSpacing.xs) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                        Text(BSLocalization.text("被采纳的反馈会获得奖励"))
                            .font(BSFont.caption.weight(.semibold))
                    }
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("例如：在哪一步遇到了什么，期待结果是什么")
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.dim)
                                .padding(.horizontal, 19)
                                .padding(.vertical, 20)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(BSFont.V3.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .bsInputField()
                            .focused($isMessageFocused)
                            .accessibilityLabel("反馈内容，必填")
                            .accessibilityHint("请说明遇到的问题或建议")
                            .onChange(of: message) {
                                if !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    validationMessage = nil
                                }
                            }
                    }

                    if let validationMessage {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(BSFont.V3.body)
                            .foregroundColor(BSColor.Stage.danger)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    Toggle(BSLocalization.text("附上 App 版本与系统版本"), isOn: $includesDiagnostics)
                        .tint(BSColor.Stage.accent)
                        .foregroundColor(BSColor.Stage.muted)
                        .font(BSFont.V3.body)

                    Text("不会自动包含现场内容、截图、照片或视频。")
                        .font(BSFont.V3.body)
                        .foregroundColor(BSColor.Stage.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isMessageFocused = false
                }
            }

            Button {
                prepareFeedback()
            } label: {
                Label(
                    sendState == .sent ? "已唤起邮件 app" : "通过邮件发送反馈",
                    systemImage: sendState == .sent ? "checkmark.circle.fill" : "envelope.fill"
                )
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(sendState == .sending || sendState == .sent)
            .accessibilityHint("打开系统邮件 app，并预填反馈内容")

            if case .failed(let reason) = sendState {
                Label(reason, systemImage: "exclamationmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.danger)
                    .accessibilityAddTraits(.isStaticText)
                    .padding(.top, BSSpacing.xs)
            }
        }
       .toolbar {
           ToolbarItemGroup(placement: .keyboard) {
               Spacer()

                Button("完成") {
                    isMessageFocused = false
                }
            }
        }
        .navigationTitle(BSLocalization.text("意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepareFeedback() {
        do {
            let payload = try payloadBuilder.build(from: FeedbackDraft(
                message: message,
                includesDiagnostics: includesDiagnostics
            ))
            validationMessage = nil
            Task { @MainActor in
                await presentMailto(shareTextBuilder.build(from: payload))
            }
        } catch {
            validationMessage = BSLocalization.text("请先填写反馈内容")
        }
    }

    @MainActor
    private func presentMailto(_ text: String) async {
        sendState = .sending
        guard let url = FeedbackDestination.mailtoURL(prefilledBody: text) else {
            sendState = .failed(BSLocalization.text("无法生成邮件链接"))
            return
        }
        let accepted = await FeedbackMailOpener.open(url: url)
        // 两种 accepted=false 场景：设备没装邮件 app / 装但未配账户。`open(mailto:)`
        // 对两者都返回 false，文案上给出唯一可执行的引导（去系统设置查看账户/添加 app）。
        sendState = accepted ? .sent : .failed(BSLocalization.text("无法唤起邮件 app，请检查系统邮件账户或 App Store 安装"))
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed(String)
}
