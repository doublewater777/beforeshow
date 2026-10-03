import SwiftUI

struct FootprintDispersalRitualSection: View {
    let rating: Int?
    let note: String?
    let onEdit: () -> Void
    let onShare: () -> Void
    let onClear: () -> Void

    /// 散场评价区。固定展示，支持直接添加、编辑与卡片分享。
    var body: some View {
        let node = rating.flatMap(DispersalRating.from(rawValue:))
        let note = FootprintTextNormalizer.nonEmptyTrimmed(self.note)
        let hasContent = node != nil || note != nil

        return VStack(alignment: .leading, spacing: BSSpacing.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(BSLocalization.text("散场评价"))
                    .font(FootprintDetailTokens.sectionFont)
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                if hasContent {
                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label(BSLocalization.text("编辑评价"), systemImage: "pencil")
                        }
                        Button {
                            onShare()
                        } label: {
                            Label(BSLocalization.text("分享卡片"), systemImage: "square.and.arrow.up")
                        }
                        Button(role: .destructive) {
                            onClear()
                        } label: {
                            Label(BSLocalization.text("清除评价"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.dim)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("管理散场评价"))
                }
            }

            if hasContent {
                dispersalContentCard(node: node, note: note)
            } else {
                dispersalEmptyCard
            }
        }
    }

    private func dispersalContentCard(node: DispersalRating?, note: String?) -> some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            if let node {
                HStack(alignment: .center, spacing: BSSpacing.compact) {
                    Text(node.emoji)
                        .font(.system(size: 28))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(node.label)
                            .font(BSFont.headline.weight(.bold))
                            .foregroundColor(node.tint)
                        Text(node.sub)
                            .font(BSFont.V3.caption)
                            .foregroundColor(BSColor.Stage.muted)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                Label(BSLocalization.text("散场感想"), systemImage: "quote.bubble.fill")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.muted)
            }

            if let note {
                if node != nil {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.vertical, 2)
                }

                HStack(alignment: .top, spacing: 8) {
                    Text("“")
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundColor((node?.tint ?? BSColor.Stage.accent).opacity(0.5))
                        .offset(y: -4)

                    Text(note)
                        .font(.custom("Songti SC", size: 14, relativeTo: .body))
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    BSColor.Stage.surface,
                    node?.tint.opacity(0.06) ?? FootprintDetailTokens.heroSecondarySurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    node?.tint.opacity(0.24) ?? BSColor.Stage.border,
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            onEdit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                node.map(\.accessibilityLabel),
                note
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
        .accessibilityHint(BSLocalization.text("轻点编辑散场评价"))
    }

    private var dispersalEmptyCard: some View {
        Button {
            onEdit()
        } label: {
            HStack(spacing: BSSpacing.md) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 44, height: 44)
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(BSColor.Stage.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.text("添加散场评价"))
                        .font(BSFont.body.weight(.medium))
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(BSLocalization.text("记录这一场的评分与散场感受"))
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(BSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(BSColor.Stage.border, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("添加散场评价，记录这一场的评分与散场感受"))
    }
}
