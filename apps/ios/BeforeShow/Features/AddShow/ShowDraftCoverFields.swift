import PhotosUI
import SwiftUI

// MARK: - Draft Cover Fields

struct AddShowCoverActions: View {
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var showsLinkField: Bool
    let isImporting: Bool
    let message: String?
    let messageIsError: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItem, matching: .images) {
                    AddShowCoverActionChip(
                        icon: isImporting ? nil : "photo.on.rectangle.angled",
                        title: BSLocalization.text("从相册选择"),
                        isActive: false,
                        showsSpinner: isImporting
                    )
                }
                .buttonStyle(.plain)
                .disabled(isImporting)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(BSLocalization.text("从相册选择"))
                .accessibilityValue(isImporting ? BSLocalization.text("正在导入…") : "")

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showsLinkField.toggle()
                    }
                } label: {
                    AddShowCoverActionChip(
                        icon: "link",
                        title: showsLinkField ? BSLocalization.text("收起链接") : BSLocalization.text("图片链接"),
                        isActive: showsLinkField,
                        showsSpinner: false
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }

            if let message, !message.isEmpty {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(messageIsError ? BSColor.Accent.danger : BSColor.Accent.prepare)
            }
        }
    }
}

private struct AddShowCoverActionChip: View {
    let icon: String?
    let title: String
    let isActive: Bool
    let showsSpinner: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsSpinner {
                ProgressView()
                    .controlSize(.small)
                    .tint(BSColor.Accent.violet)
                    .accessibilityHidden(true)
            } else if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isActive ? BSColor.Stage.accent : BSColor.Accent.violet)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? BSColor.Stage.accent : BSColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background(
            isActive
                ? BSColor.Stage.accent.opacity(0.10)
                : Color.white.opacity(0.045)
        )
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(
                    isActive
                        ? BSColor.Stage.accent.opacity(0.35)
                        : BSColor.borderProminent,
                    lineWidth: 1
                )
        )
    }
}

struct ShowDraftCoverPreview: View {
    let urlString: String

    var body: some View {
        ZStack {
            ShowCoverImageView(
                urlString: urlString,
                aspectRatio: 16.0 / 9.0,
                contentMode: .fill,
                enforcesAspectRatio: false,
                cornerRadius: 14
            )
            .blur(radius: 20)
            .overlay(Color.black.opacity(0.42))

            ShowCoverImageView(
                urlString: urlString,
                aspectRatio: 3.0 / 4.0,
                contentMode: .fit,
                cornerRadius: 10
            )
            .frame(height: 186)
            .shadow(color: .black.opacity(0.55), radius: 14, x: 0, y: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 216)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .overlay(alignment: .topLeading) {
            Text("当前封面")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(BSColor.textSecondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .padding(10)
        }
        .accessibilityHidden(true)
    }
}
