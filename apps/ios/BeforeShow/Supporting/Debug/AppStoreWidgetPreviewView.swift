import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

#if DEBUG
struct AppStoreWidgetPreviewView: View {
    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Text(BSLocalization.text("小组件"))
                    .font(BSFont.tag)
                    .tracking(3)
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(BSLocalization.text("不用打开，也在靠近"))
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.5)
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)

                Text(BSLocalization.text("主屏幕和锁屏，都替你数着那一天。"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 9)

                Spacer(minLength: 0)

                VStack(spacing: 14) {
                    mediumWidget
                    lockScreenWidget
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .preferredColorScheme(.dark)
    }

    private var mediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离灯亮还有"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.Stage.muted)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("56")
                        .font(.system(size: 44, weight: .semibold))
                        .tracking(-0.5)
                        .foregroundColor(BSColor.Stage.heroIvory)
                        .monospacedDigit()
                    Text(BSLocalization.text("天"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(BSLocalization.text("「夜航」巡演 · 上海站"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(1)
                    Text(BSLocalization.text("10月14日 19:30 · 回声剧场"))
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.Stage.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(width: 86)
                .clipped()
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [Color(red: 0.018, green: 0.018, blue: 0.025), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                }
                .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .frame(height: (UIScreen.main.bounds.width - 44) * (170.0 / 364.0))
        .background {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .overlay(BSColor.Stage.background.opacity(0.82))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.text("主屏幕小组件预览"))
    }

    private var lockScreenWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BSLocalization.format("还有 %lld 天", 56))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("「夜航」巡演 · 上海站 · 10月14日 19:30"))
                .font(.system(size: 10))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.text("锁屏小组件预览"))
    }
}
#endif
