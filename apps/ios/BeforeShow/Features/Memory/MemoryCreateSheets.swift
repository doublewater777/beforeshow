import SwiftUI

struct MemoryCreateSourceSheet: View {
    let onSelect: (MemoryCreateSourceOption) -> Void

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large], fitsContent: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(MemoryCreateSourcePresentation.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(MemoryCreateSourcePresentation.message)
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 6)

                HStack(spacing: 10) {
                    ForEach(MemoryCreateSourceOption.allCases, id: \.self) { option in
                        MemorySourceOptionCard(
                            title: option.title,
                            icon: option.iconName,
                            action: { onSelect(option) }
                        )
                    }
                }
                .padding(.top, 17)
            }
        }
    }
}

struct MemoryAddMediaSheet: View {
    let onCamera: () -> Void
    let onLibrary: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(292), fitsContent: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("继续添加")
                    .font(.system(size: 18, weight: .semibold))
                Text("给当前这条记忆增加媒体")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.Stage.muted)
                    .padding(.top, 6)
                HStack(spacing: 10) {
                    MemorySourceOptionCard(
                        title: BSLocalization.text("继续拍照"),
                        icon: "camera",
                        action: onCamera
                    )
                    MemorySourceOptionCard(
                        title: BSLocalization.text("从图库选择"),
                        icon: "photo.on.rectangle",
                        action: onLibrary
                    )
                }
                .padding(.top, 17)
            }
        }
    }
}

struct MemoryMediaActionsSheet: View {
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(278), fitsContent: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("管理这条记忆"))
                    .font(.system(size: 18, weight: .semibold))

                VStack(spacing: 10) {
                    Button(BSLocalization.text("编辑记忆"), action: onEdit)
                        .buttonStyle(BSSecondaryButtonStyle())
                    Button(BSLocalization.text("删除这条记忆"), role: .destructive, action: onDelete)
                        .buttonStyle(BSDangerButtonStyle())
                }
                .padding(.top, 17)
            }
        }
    }
}

private struct MemorySourceOptionCard: View {
    let title: String
    let icon: String
    var height: CGFloat = 105
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 42, height: 42)
                    .background(BSColor.Stage.accent.opacity(0.10), in: Circle())
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(BSColor.Stage.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
