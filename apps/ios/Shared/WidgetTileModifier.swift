import SwiftUI
import WidgetKit

extension View {
    /// 模拟桌面小组件的外形（尺寸、圆角、内边距与微边框）
    @ViewBuilder
    func widgetTile<Background: View>(family: WidgetFamily, @ViewBuilder background: () -> Background) -> some View {
        switch family {
        case .systemSmall:
            self
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .aspectRatio(1, contentMode: .fit)
                .background(background())
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        case .systemMedium:
            self
                .padding(.leading, 16)
                .padding(.vertical, 14)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 155)
                .background(background())
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        default:
            self
                .background(background())
        }
    }
}
