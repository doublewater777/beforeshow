import Foundation
import SwiftUI

struct FeedbackView: View {
    @State private var message = ""
    @State private var sendState: FeedbackSendState = .idle
    @FocusState private var isMessageFocused: Bool

    private let payloadBuilder = FeedbackPayloadBuilder()

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
                        .onChange(of: message) { _, _ in
                            guard sendState != .sending else { return }
                            sendState = .idle
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
            .disabled(sendState == .sending || sendState == .sent || trimmedMessage.isEmpty)

            switch sendState {
            case .sent:
                Label(BSLocalization.text("已收到，谢谢你的反馈"), systemImage: "checkmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.success)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .failed:
                Label(BSLocalization.text("提交失败，请检查网络后重试"), systemImage: "exclamationmark.circle.fill")
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .idle, .sending:
                EmptyView()
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

    private func submitFeedback() {
        guard let payload = try? payloadBuilder.build(from: FeedbackDraft(message: message)) else {
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
            } catch {
                sendState = .failed
            }
        }
    }
}

enum FeedbackSendState: Equatable {
    case idle
    case sending
    case sent
    case failed
}
