import SwiftUI

struct OnboardingWidgetFeatureVisual: View {
    var body: some View {
        VStack(spacing: BSSpacing.compact) {
            mediumWidget
            lockScreenWidget
            reminder
                .offset(x: 12, y: -2)
        }
        .frame(maxWidth: 320)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            BSLocalization.text("小组件显示现场倒计时，锁屏显示日期，开场前会在重要节点提醒")
        )
    }

    private var mediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(BSLocalization.text("距离灯亮还有"))
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.1)
                    .foregroundColor(BSColor.Stage.muted)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("56")
                        .font(.system(size: 43, weight: .semibold))
                        .foregroundColor(BSColor.Stage.heroIvory)
                        .monospacedDigit()
                    Text(BSLocalization.text("天"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(BSColor.Stage.muted)
                }
                .padding(.top, 10)

                Spacer(minLength: 5)

                Text(BSLocalization.text("「夜航」巡演 · 上海站"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(BSLocalization.text("10月14日 19:30 · 回声剧场"))
                    .font(.system(size: 8.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .lineLimit(1)
            }
            .padding(.leading, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(width: 86)
                .clipped()
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [BSColor.Stage.background, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                }
        }
        .frame(height: 150)
        .background(BSColor.Stage.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.30), radius: 26, y: 14)
    }

    private var lockScreenWidget: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BSLocalization.format("还有 %lld 天", Int64(56)))
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("「夜航」巡演 · 上海站 · 10月14日 19:30"))
                .font(.system(size: 9))
                .foregroundColor(BSColor.Stage.dim)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BSColor.Stage.surface.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
    }

    private var reminder: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BSLocalization.text("开场之前，我来提醒你"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("在几个值得记一下的节点轻轻提醒，不推销任何东西。"))
                .font(.system(size: 9))
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BSColor.Stage.surfaceRaised.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.24), radius: 18, y: 9)
    }
}

struct OnboardingTimetableFeatureVisual: View {
    private let rows = [
        ("17:30", "开始入场"),
        ("18:40", "暖场"),
        ("19:30", "夜航"),
        ("21:20", "预计散场")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(BSLocalization.text("时刻表"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Spacer()
                Text(BSLocalization.text("已保存"))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(BSColor.glowBlueFallback)
            }
            .padding(.bottom, 15)

            ZStack(alignment: .top) {
                timetableImage
                Text(BSLocalization.text("保存的图片"))
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.76))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.56), in: Capsule())
                    .padding(.top, 6)
            }

            Spacer(minLength: 14)

            Text(BSLocalization.text("查看原图"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border))
        }
        .padding(18)
        .frame(maxWidth: 280)
        .frame(height: 368)
        .background(BSColor.Stage.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.32), radius: 28, y: 16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.text("已保存一张时刻表图片，可以快速查看原图"))
    }

    private var timetableImage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text("演出时刻表"))
                .font(.custom("Songti SC", size: 19, relativeTo: .headline))
                .foregroundColor(Color(red: 0.09, green: 0.075, blue: 0.06))
            Text("OCT 04 · LEGACY TERA")
                .font(.system(size: 8))
                .foregroundColor(Color.black.opacity(0.48))
                .padding(.top, 3)
                .padding(.bottom, 10)

            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 9) {
                    Text(row.0)
                        .foregroundColor(Color.black.opacity(0.48))
                        .frame(width: 38, alignment: .leading)
                    Text(BSLocalization.text(row.1))
                        .fontWeight(.semibold)
                }
                .font(.system(size: 9))
                .foregroundColor(Color.black.opacity(0.82))
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .frame(height: 1)
                }
            }
        }
        .padding(15)
        .background(Color(red: 0.94, green: 0.91, blue: 0.86))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .rotationEffect(.degrees(-1.3))
    }
}

struct OnboardingMemoryFeatureVisual: View {
    private let selectedRating = DispersalRating.golden

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            Text(BSLocalization.format("%@ · %@", BSLocalization.text("记忆碎片"), BSLocalization.text("散场以后")))
                .font(.system(size: 9, weight: .bold))
                .tracking(1)
                .foregroundColor(BSColor.Stage.accent)

            HStack(spacing: 10) {
                photoTile
                textTile
            }

            ratingCard
        }
        .frame(maxWidth: 304)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            BSLocalization.text("记忆碎片包含照片和文字，散场评价当前选择人上人，明显高于预期")
        )
    }

    private var photoTile: some View {
        VStack(spacing: 0) {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .frame(height: 148)
                .clipped()
            memoryMetadata(kind: BSLocalization.text("照片"), time: "20:48")
        }
        .frame(maxWidth: .infinity)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
    }

    private var textTile: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("“")
                .font(.custom("Songti SC", size: 24, relativeTo: .headline))
                .foregroundColor(BSColor.Stage.accent)
            Text(BSLocalization.text("最后一首歌结束的时候，灯亮得特别慢。"))
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.foreground)
                .lineSpacing(4)
                .padding(.top, 7)
            Spacer(minLength: 0)
            memoryMetadata(kind: BSLocalization.text("文字"), time: "22:06")
                .padding(.horizontal, -12)
                .padding(.bottom, -12)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .frame(height: 184)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border))
    }

    private func memoryMetadata(kind: String, time: String) -> some View {
        HStack {
            Text(kind)
            Spacer()
            Text(time)
        }
        .font(.system(size: 8.5, weight: .medium))
        .foregroundColor(BSColor.Stage.dim)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(Color.black.opacity(0.18))
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Text(selectedRating.emoji)
                    .font(.system(size: 27))
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedRating.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(selectedRating.tint)
                    Text(selectedRating.sub)
                        .font(.system(size: 8.5))
                        .foregroundColor(BSColor.Stage.dim)
                }
            }

            HStack(spacing: 0) {
                ForEach(DispersalRating.allCases) { rating in
                    let selected = rating == selectedRating
                    VStack(spacing: 3) {
                        Circle()
                            .fill(selected ? rating.tint : Color(red: 0.165, green: 0.188, blue: 0.251))
                            .frame(width: 11, height: 11)
                            .overlay(Circle().stroke(selected ? rating.tint : Color.white.opacity(0.14), lineWidth: 1.5))
                        Text(rating.emoji)
                            .font(.system(size: 12))
                            .grayscale(selected ? 0 : 0.75)
                            .opacity(selected ? 1 : 0.55)
                        Text(rating.label)
                            .font(.system(size: 7.5, weight: selected ? .bold : .medium))
                            .foregroundColor(selected ? BSColor.Stage.foreground : BSColor.Stage.dim)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 3)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
                    .zIndex(-1)
            }
        }
        .padding(14)
        .background(BSColor.Stage.surfaceRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(BSColor.Stage.border))
        .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
    }
}

struct OnboardingStartFeatureVisual: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(BSColor.Stage.glowBlue.opacity(0.16))
                .frame(width: 210, height: 210)
                .blur(radius: 45)
            Circle()
                .fill(BSColor.Stage.accent.opacity(0.12))
                .frame(width: 150, height: 150)
                .offset(x: 62, y: 45)
                .blur(radius: 42)
        }
        .accessibilityHidden(true)
    }
}

private extension BSColor {
    static let glowBlueFallback = Color(red: 0.49, green: 0.81, blue: 1.0)
}
