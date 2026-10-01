import Foundation
import SwiftUI

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var messageLength: Int {
        FeedbackPayloadBuilder.messageLength(message)
    }

    private var isMessageOverLimit: Bool {
        messageLength > FeedbackPayloadBuilder.maximumMessageLength
    }

    var body: some View {
        BSStageScaffold(
            title: "",
            subtitle: nil,
            bottomPadding: BSSpacing.xl
        ) {
            BSSettingsSurface(padding: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(BSLocalization.text("写下你的问题或建议"))
                                .font(BSFont.V3.body)
                                .foregroundColor(BSColor.Stage.dim)
                                .padding(.horizontal, BSSpacing.lg)
                                .padding(.vertical, BSSpacing.lg)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(BSFont.V3.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 150)
                            .bsInputField()
                            .focused($isMessageFocused)
                            .onChange(of: message) { _, _ in
                                guard sendState != .sending else { return }
                                sendState = .idle
                            }
                    }

                    HStack {
                        if isMessageOverLimit {
                            Text(BSLocalization.text("反馈最多 2000 字"))
                                .font(BSFont.V3.caption)
                                .foregroundColor(BSColor.Stage.danger)
                        }

                        Spacer()

                        Text("\(messageLength) / \(FeedbackPayloadBuilder.maximumMessageLength)")
                            .font(BSFont.V3.caption)
                            .foregroundColor(
                                isMessageOverLimit
                                    ? BSColor.Stage.danger
                                    : BSColor.Stage.muted
                            )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isMessageFocused = false
                }
            }

            Button {
                submitFeedback()
            } label: {
                if sendState == .sending {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Label(
                        sendState == .sent
                            ? BSLocalization.text("已提交")
                            : BSLocalization.text("提交反馈"),
                        systemImage: sendState == .sent ? "checkmark.circle.fill" : "paperplane.fill"
                    )
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(
                sendState == .sending ||
                sendState == .sent ||
                trimmedMessage.isEmpty ||
                isMessageOverLimit
            )

            switch sendState {
            case .sent:
                Label(BSLocalization.text("已收到，谢谢你的反馈"), systemImage: "checkmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed(let error):
                Label(failureCopy(for: error), systemImage: "exclamationmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .sending:
                EmptyView()
            }
        }
        .navigationTitle(BSLocalization.text("意见反馈"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func submitFeedback() {
        let payload: FeedbackPayload
        do {
            payload = try payloadBuilder.build(from: FeedbackDraft(message: message))
        } catch FeedbackValidationError.messageTooLong {
            sendState = .failed(.messageTooLong)
            return
        } catch {
            return
        }

        isMessageFocused = false
        sendState = .sending

        Task { @MainActor in
            do {
                let service = RemoteFeedbackSubmissionService(
                    client: BeforeShowCloudClient.production()
                )
                try await service.submit(payload)
                sendState = .sent
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                message = ""
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                dismiss()
            } catch let error as FeedbackSubmissionError {
                sendState = .failed(error)
            } catch {
                sendState = .failed(.rejected)
            }
        }
    }

    private func failureCopy(for error: FeedbackSubmissionError) -> String {
        switch error {
        case .networkFailure:
            return BSLocalization.text("提交失败，请检查网络后重试")
        case .messageTooLong:
            return BSLocalization.text("反馈最多 2000 字")
        case .rateLimited:
            return BSLocalization.text("提交有点频繁，请稍后再试")
        case .rejected:
            return BSLocalization.text("暂时没能提交，请稍后重试")
        }
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed(FeedbackSubmissionError)
}
