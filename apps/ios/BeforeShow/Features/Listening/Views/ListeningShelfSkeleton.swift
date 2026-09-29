import SwiftUI

struct ListeningShelfSkeleton: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<ListeningDisplayProjector.Shelf.visibleCount, id: \.self) { index in
                ListeningCabinetDiscPlaceholder(index: index)
                if index < ListeningDisplayProjector.Shelf.visibleCount - 1 {
                    Spacer(minLength: BSSpacing.compact)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, BSSpacing.sm)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BSLocalization.text("正在准备唱片"))
        .accessibilityIdentifier("listening.shelfSkeleton")
    }
}

private struct ListeningCabinetDiscPlaceholder: View {
    let index: Int

    var jacketSize: CGFloat = BSListeningTokens.shelfArtwork
    private var discSize: CGFloat { jacketSize * BSListeningTokens.detailDiscFraction }
    var peekOffset: CGFloat = 18

    private var titleWidth: CGFloat {
        switch index % 3 {
        case 0: return 72
        case 1: return 82
        default: return 66
        }
    }

    var body: some View {
        VStack(spacing: BSListeningTokens.shelfItemSpacing) {
            ZStack(alignment: .leading) {
                // 抽出的 CD 光盘暗色轮廓
                ListeningPeekingDiscPlaceholder(size: discSize)
                    .offset(x: jacketSize - discSize + peekOffset)

                // 唱片封套暗色轮廓
                ListeningSleeveJacketPlaceholder(size: jacketSize)
            }
            .frame(width: jacketSize + peekOffset, height: jacketSize, alignment: .leading)
            .background(alignment: .bottom) {
                Ellipse()
                    .fill(Color.black.opacity(BSListeningTokens.selectionRestingOpacity))
                    .frame(height: BSListeningTokens.shelfShadowHeight)
                    .blur(radius: BSListeningTokens.shelfShadowBlur)
                    .offset(y: BSSpacing.xs)
            }

            // 单行标题骨架条
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(BSColor.Stage.surfaceRaised)
                .frame(width: titleWidth, height: 11)
                .frame(width: jacketSize + 16, height: BSListeningTokens.shelfLabelHeight, alignment: .top)
        }
        .listeningShimmer()
        .accessibilityHidden(true)
    }
}

private struct ListeningPeekingDiscPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // 暗色金属盘片底色
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.17),
                            Color(white: 0.12),
                            Color(white: 0.18),
                            Color(white: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 微弱暗部激光彩虹微光
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.white.opacity(0.04),
                    Color(red: 0.40, green: 0.65, blue: 0.85).opacity(0.08),
                    Color(red: 0.72, green: 0.52, blue: 0.90).opacity(0.08),
                    Color.white.opacity(0.04),
                    Color(red: 0.38, green: 0.78, blue: 0.72).opacity(0.08),
                    Color.white.opacity(0.04)
                ]),
                center: .center,
                angle: .degrees(35)
            )
            .clipShape(Circle())

            // 外盘同心圆数据轨道
            Circle()
                .strokeBorder(Color.white.opacity(0.08), lineWidth: size * 0.18)
                .padding(size * 0.12)

            Circle()
                .strokeBorder(Color.white.opacity(0.05), lineWidth: size * 0.08)
                .padding(size * 0.25)

            // 盘片外圈高光轮廓
            Circle()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)

            // Spindle Hub 中心轴孔外环
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .frame(width: size * 0.28, height: size * 0.28)

            // 中心轴孔
            Circle()
                .fill(Color(white: 0.06))
                .frame(width: size * 0.18, height: size * 0.18)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.4), radius: 3, x: -1, y: 1)
    }
}

private struct ListeningSleeveJacketPlaceholder: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.15),
                            Color(white: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            // 唱片中央压印暗纹
            Circle()
                .stroke(Color.white.opacity(0.04), lineWidth: 1)
                .frame(width: size * 0.52, height: size * 0.52)

            // 书脊微光折痕
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.black.opacity(0.25), Color.clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 3.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous))

            // 精致细边框
            RoundedRectangle(cornerRadius: BSRadius.sm, style: .continuous)
                .stroke(Color.white.opacity(0.09), lineWidth: BSListeningTokens.hairline)
        }
        .frame(width: size, height: size)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 1, y: 2)
    }
}

struct ListeningShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    let bandWidth: CGFloat = max(width, height) * 0.8

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: Color.white.opacity(0.12), location: 0.5),
                            .init(color: .clear, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .rotationEffect(.degrees(22))
                    .offset(x: phase * (width + bandWidth * 2) - bandWidth)
                    .allowsHitTesting(false)
                }
            }
            .mask(content)
            .onAppear {
                withAnimation(
                    .linear(duration: 1.7)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1.0
                }
            }
    }
}

extension View {
    func listeningShimmer() -> some View {
        modifier(ListeningShimmerModifier())
    }
}
