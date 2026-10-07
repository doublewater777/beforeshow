import SwiftUI

struct AddShowLinkGuideStepsView: View {
    var completionTitle = "前往购票平台"
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
            // 顶栏：随时可返回平台列表，右侧显示当前步骤进度
            HStack {
                Button {
                    onComplete()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text(BSLocalization.text("平台列表"))
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(BSColor.Accent.violet)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text("返回平台列表"))

                Spacer()

                HStack(spacing: 4) {
                    Text(BSLocalization.text("秀动示例"))
                        .foregroundStyle(BSColor.textTertiary)
                    Text("·")
                        .foregroundStyle(BSColor.textTertiary)
                    Text("\(page + 1) / \(steps.count)")
                        .foregroundStyle(BSColor.Accent.violet)
                }
                .font(BSFont.tag)
            }
            .padding(.horizontal, BSSpacing.lg)
            .padding(.top, BSSpacing.xs)

            TabView(selection: $page) {
                ForEach(steps.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: BSSpacing.compact) {
                        Text(BSLocalization.text(steps[index].title))
                            .font(BSFont.headline)
                            .foregroundStyle(BSColor.textPrimary)
                        Text(BSLocalization.text(steps[index].detail))
                            .font(BSFont.caption)
                            .foregroundStyle(BSColor.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(steps[index].image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                            .overlay(
                                RoundedRectangle(cornerRadius: BSRadius.lg)
                                    .stroke(BSColor.border, lineWidth: 1)
                            )
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
            }

            Button {
                if page == steps.count - 1 {
                    onComplete()
                } else {
                    withAnimation { page += 1 }
                }
            } label: {
                Text(BSLocalization.text(page == steps.count - 1 ? completionTitle : "下一步"))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EditShowSaveButtonStyle())
            .padding(.horizontal, BSSpacing.lg)
        }
        .padding(.bottom, BSSpacing.md)
    }
}
