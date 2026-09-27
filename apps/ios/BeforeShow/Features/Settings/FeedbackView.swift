import SwiftData
import SwiftUI
import UIKit
import UserNotifications

struct FeedbackView: View {
    @State private var message = ""
    @State private var sendState: FeedbackSendState = .idle
    @State private var copiedAddress = false
    @State private var copiedMessage = false
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()
    private let shareTextBuilder = FeedbackShareTextBuilder()

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: nil,
            bottomPadding: BSSpacing.xl
        ) {
            BSSettingsSurface(padding: BSSpacing.md) {
                ZStack(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(BSLocalization.text("写下你的问题或建议"))
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
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isMessageFocused = false
                }
            }

            Button {
                prepareFeedback()
            } label: {
                Label(BSLocalization.text("打开邮件发送"), systemImage: "envelope.fill")
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(sendState == .sending || trimmedMessage.isEmpty)

            Text(BSLocalization.text("内容会自动填好，打开邮件后直接发送即可"))
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: .infinity, alignment: .center)

            if case .failed(let reason) = sendState {
                VStack(spacing: BSSpacing.sm) {
                    Label(reason, systemImage: "exclamationmark.circle.fill")
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: BSSpacing.sm) {
                        Button(copiedAddress ? BSLocalization.text("已复制") : BSLocalization.text("复制邮箱")) {
                            copyAddress()
                        }
                        .buttonStyle(BSSecondaryButtonStyle())

                        Button(copiedMessage ? BSLocalization.text("已复制") : BSLocalization.text("复制反馈内容")) {
                            copyMessage()
                        }
                        .buttonStyle(BSSecondaryButtonStyle())
                    }
                }
                .padding(.top, BSSpacing.xs)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()

                Button(BSLocalization.text("完成")) {
                    isMessageFocused = false
                }
            }
        }
        .navigationTitle(BSLocalization.text("意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func prepareFeedback() {
        guard let payload = try? payloadBuilder.build(from: FeedbackDraft(message: message)) else {
            return
        }

        Task { @MainActor in
            await presentMailto(shareTextBuilder.build(from: payload))
        }
    }

    @MainActor
    private func presentMailto(_ text: String) async {
        sendState = .sending
        guard let url = FeedbackDestination.mailtoURL(prefilledBody: text) else {
            sendState = .failed(BSLocalization.text("无法打开邮件，请复制邮箱和反馈内容后手动发送。"))
            return
        }

        let accepted = await FeedbackMailOpener.open(url: url)
        sendState = accepted
            ? .idle
            : .failed(BSLocalization.text("无法打开邮件，请复制邮箱和反馈内容后手动发送。"))
    }

    @MainActor
    private func copyAddress() {
        UIPasteboard.general.string = FeedbackDestination.address
        copiedAddress = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedAddress = false
        }
    }

    @MainActor
    private func copyMessage() {
        UIPasteboard.general.string = trimmedMessage
        copiedMessage = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedMessage = false
        }
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case failed(String)
}
