import SwiftUI

/// The night's facts set like a programme: small caps label, plain value.
struct BSProgrammeInfo: View {
    struct Row: Identifiable {
        let label: String
        let value: String
        var detail: String?
        var actionTitle: String?
        var action: (() -> Void)?
        var id: String { label }
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(BSLocalization.text("现场资料"))
                .font(BSFont.headline)
                .foregroundStyle(BSColor.Stage.foreground)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    content(row)
                        .padding(.vertical, 13)
                        .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
        }
    }

    @ViewBuilder
    private func content(_ row: Row) -> some View {
        let line = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(row.label)
                .font(.system(size: 11, weight: .medium).width(.condensed))
                .tracking(2)
                .foregroundStyle(BSColor.Stage.dim)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.value)
                    .font(.system(size: 14))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.9))
                    .lineSpacing(3)
                if let detail = row.detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.dim)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle = row.actionTitle {
                HStack(spacing: 2) {
                    Text(actionTitle)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BSColor.Stage.accent)
            }
        }
        .contentShape(Rectangle())
        if let action = row.action {
            Button(action: action) { line }
                .buttonStyle(.plain)
        } else {
            line.accessibilityElement(children: .combine)
        }
    }
}

struct BSRoundIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06), in: Circle())
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Press feedback for physical-looking cards: a slight sink and a light tap.
struct BSPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

/// A user's own photo (ticket, timetable) taped to a card.
struct BSTapedImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        // Size from the slot, not the image, so tall screenshots crop instead of spilling out.
        Color(white: 0.12)
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 9, y: 8)
        // 用户导入的票根 / 时刻表一律遮罩。
        .bsMaskUserContent()
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}
