import SwiftUI

struct AddShowLinkGuideStepsView: View {
    var onComplete: () -> Void

    @State private var page = 0

    private let steps: [(image: String, title: String, detail: String)] = [
        ("AddLinkHome", "打开平台总览", "以秀动为例，点击搜索栏。"),
        ("AddLinkSearch", "搜索你要添加的演出", "输入艺人或演出名称，点击对应结果。"),
        ("AddLinkDetail", "进入演出详情", "确认是你要添加的演出。"),
        ("AddLinkShare", "点击底部分享", "点击浏览器底部标出的分享按钮。"),
        ("AddLinkCopy", "点击拷贝", "拷贝后关闭浏览器，返回粘贴。")
    ]

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    VStack(spacing: BSSpacing.compact) {
                        Text(BSLocalization.text(steps[index].title))
                            .font(BSFont.title)
                            .foregroundStyle(BSColor.textPrimary)
                        Text(BSLocalization.text(steps[index].detail))
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.textSecondary)
                            .multilineTextAlignment(.center)
                        Image(steps[index].image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(.horizontal, BSSpacing.lg)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: BSSpacing.sm) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == page ? BSColor.Accent.violet : BSColor.border)
                        .frame(width: BSSpacing.sm, height: BSSpacing.sm)
                }
                Text("\(page + 1) / \(steps.count)")
                    .font(BSFont.tag)
                    .foregroundStyle(BSColor.textTertiary)
            }

            Button {
                if page == steps.count - 1 {
                    onComplete()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(BSLocalization.text(page == steps.count - 1 ? "开始添加" : "下一步"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .padding(.horizontal, BSSpacing.lg)
        }
        .padding(.vertical, BSSpacing.md)
    }
}
