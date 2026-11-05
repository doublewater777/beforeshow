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
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                if hasContent {
                    BSRoundIconButton(systemName: "square.and.arrow.up", label: BSLocalization.text("分享卡片"), action: onShare)
                    BSRoundIconButton(systemName: "pencil", label: BSLocalization.text("编辑评价"), action: onEdit)
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
                HStack(alignment: .center, spacing: 10) {
                    // One stage light per level, lit up to tonight's.
                    ForEach(DispersalRating.allCases) { level in
                        let lit = level.rawValue <= node.rawValue
                        Circle()
                            .fill(lit ? AnyShapeStyle(RadialGradient(colors: [.white, node.tint], center: .init(x: 0.4, y: 0.35), startRadius: 0, endRadius: 9)) : AnyShapeStyle(Color.white.opacity(0.08)))
                            .frame(width: 16, height: 16)
                            .shadow(color: lit ? node.tint.opacity(0.7) : .clear, radius: 6)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.label)
                            .font(BSFont.headline.weight(.bold))
                            .foregroundStyle(BSColor.Stage.foreground)
                        Text(node.sub)
                            .font(BSFont.V3.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                    .padding(.leading, 4)

                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
            } else {
                Label(BSLocalization.text("散场感想"), systemImage: "quote.bubble.fill")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundStyle(BSColor.Stage.muted)
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
                        .foregroundStyle(BSColor.Stage.dim)
                        .offset(y: -4)

                    Text(note)
                        .font(.custom("Songti SC", size: 14, relativeTo: .body))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
            }
        }
        .padding(BSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only the lit lights carry the rating's colour; the card itself stays neutral.
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .onTapGesture {
            onEdit()
        }
        .contextMenu {
            Button(role: .destructive) {
                onClear()
            } label: {
                Label(BSLocalization.text("清除评价"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: BSLocalization.text("清除评价"), onClear)
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
                        .foregroundStyle(BSColor.Stage.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.text("添加散场评价"))
                        .font(BSFont.body.weight(.medium))
                        .foregroundStyle(BSColor.Stage.foreground)
                    Text(BSLocalization.text("记录这一场的评分与散场感受"))
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(BSFont.V3.caption.weight(.semibold))
                    .foregroundStyle(BSColor.Stage.dim)
            }
            .padding(BSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BSLocalization.text("添加散场评价，记录这一场的评分与散场感受"))
    }
}
