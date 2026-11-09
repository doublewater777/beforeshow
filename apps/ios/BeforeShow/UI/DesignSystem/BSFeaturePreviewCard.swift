import SwiftUI

/// 空状态里的一张小卡：一行一个能做的事，只展示不交互。
struct BSFeaturePreviewCard: View {
    struct Row: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    let rows: [Row]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
            ForEach(rows) { row in
                GridRow {
                    Image(systemName: row.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06), in: Circle())
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .lineLimit(1)
                    Text(row.detail)
                        .font(.system(size: 13))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 10)
                if row.id != rows.last?.id {
                    Rectangle().fill(BSColor.Stage.border).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.border))
    }
}
