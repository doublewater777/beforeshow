import SwiftUI
import UIKit

#if DEBUG
struct LiveAndWidgetShowcaseView: View {
    enum Category: String, CaseIterable, Identifiable {
        case liveActivity = "实时活动"
        case widgets = "桌面小组件"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: Category

    private let now = Date()

    init() {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--preview-widgets") {
            _selectedCategory = State(initialValue: .widgets)
        } else {
            _selectedCategory = State(initialValue: .liveActivity)
        }
    }

    var body: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                // Category Picker
                Picker("", selection: $selectedCategory) {
                    ForEach(Category.allCases) { cat in
                        Text(cat.rawValue).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.bottom, 16)

                // Content
                ScrollView(.vertical, showsIndicators: false) {
                    ScrollViewReader { scrollProxy in
                        VStack(spacing: 24) {
                            if selectedCategory == .liveActivity {
                                liveActivitySection
                            } else {
                                widgetsSection
                            }
                            Color.clear.frame(height: 1).id("bottom-anchor")
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                        .task {
                            if ProcessInfo.processInfo.arguments.contains("--scroll-to-bottom") {
                                try? await Task.sleep(nanoseconds: 1_200_000_000)
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    scrollProxy.scrollTo("bottom-anchor", anchor: .bottom)
                                }
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedCategory == .liveActivity ? "实时活动 & 灵动岛" : "桌面与锁屏小组件")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                Text(selectedCategory == .liveActivity ? "现场多舞台驱动 · 锁屏与灵动岛实时协同" : "倒计时与现场模式自适应收束")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.textSecondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSColor.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(BSColor.surfaceElevated)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Live Activity Section

    private var liveActivitySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Lock screen banner (Live Mode with Timetable)
            sectionTitle(
                "锁屏实时活动 · 现场进行中",
                subtitle: "多舞台正在演出 + 下一场想看优先置顶与 30 分钟临近预警"
            )
            liveFestivalLockScreenBanner

            // 2. Dynamic Island Expanded
            sectionTitle(
                "灵动岛展开态 (Dynamic Island Expanded)",
                subtitle: "长按灵动岛展开，展示当前与下一场演出详情"
            )
            dynamicIslandExpandedView

            // 3. Dynamic Island Compact & Minimal
            sectionTitle(
                "灵动岛紧凑态与最小态",
                subtitle: "后台运行中常驻，高辨识度品牌标记与实时计时"
            )
            dynamicIslandCompactRow

            // 4. Lock screen banner (Pre-show Countdown)
            sectionTitle(
                "锁屏实时活动 · 开场前倒计时",
                subtitle: "临近开场时激活，指引开场倒计时与快速导航路线"
            )
            countdownLockScreenBanner
        }
    }

    // MARK: - Widgets Section

    private var widgetsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // 1. Live mode widget (Medium)
            sectionTitle(
                "中号小组件 · 正在现场",
                subtitle: "到达现场或演出当天，自动切换为现场走秒状态"
            )
            liveModeMediumWidget

            // 2. Countdown widget (Medium)
            sectionTitle(
                "中号小组件 · 远场自然日倒计时",
                subtitle: ">24h 自然日大字号推进，高斯模糊封面氛围"
            )
            countdownMediumWidget

            // 3. Small Widgets Row
            sectionTitle(
                "小号小组件 (System Small)",
                subtitle: "单格极简高对比，现场态与倒计时态"
            )
            HStack(spacing: 14) {
                smallLiveWidget
                smallCountdownWidget
            }

            // 4. Listening Widget (Medium)
            sectionTitle(
                "音乐试听小组件 (Medium)",
                subtitle: "开机即听，现场前专属黑胶质感"
            )
            listeningMediumWidget

            // 5. Lock screen accessory widgets
            sectionTitle(
                "锁屏小组件 (Lock Screen Accessories)",
                subtitle: "长条型与环形刻度，瞥一眼即可获知开场进度"
            )
            lockScreenAccessoryRow
        }
    }

    // MARK: - Section Helpers

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(BSColor.Accent.warm)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(BSColor.textTertiary)
        }
    }

    // MARK: - 1. Live Festival Lock Screen Banner

    private var liveFestivalLockScreenBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            // Row 1: Cover + Timer & Status
            HStack(spacing: 12) {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("01:23:45")
                        .font(.system(size: 23, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.46))

                    Text("已开场")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)
                }
            }

            // Row 2: Detail + Next show + Action Button
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("正在演: King Gizzard & The Lizard Wizard · 爱舞台")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text("下一场: ❤️ 万能青年旅店 (11:44 · 草莓舞台)")
                            .font(.system(size: 12))
                            .foregroundColor(BSColor.textSecondary)
                            .lineLimit(1)
                        Text("· 快开始了")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(BSColor.Accent.warm)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "camera")
                        .font(.system(size: 11, weight: .semibold))
                    Text("记一段记忆")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    // MARK: - 2. Dynamic Island Expanded View

    private var dynamicIslandExpandedView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 1) {
                    Text("草莓音乐节 2026 · 上海站")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BSColor.textSecondary)
                    Text("世博公园")
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.textTertiary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    Text("01:23:45")
                        .font(.system(size: 21, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.46))

                    Text("已开场")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("正在演: King Gizzard & The Lizard Wizard · 爱舞台")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text("下一场: ❤️ 万能青年旅店 (11:44 · 草莓舞台)")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.textSecondary)
                        .lineLimit(1)
                    Text("· 快开始了")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(BSColor.Accent.warm)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.black)
                .overlay(
                    RoundedRectangle(cornerRadius: 32)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
    }

    // MARK: - 3. Dynamic Island Compact Row

    private var dynamicIslandCompactRow: some View {
        HStack(spacing: 20) {
            // Compact pill
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(BSColor.Accent.warm)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        )
                }
                .padding(.leading, 10)

                Spacer(minLength: 16)

                Text("01:23:45")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.46))
                    .padding(.trailing, 10)
            }
            .frame(width: 190, height: 36)
            .background(
                Capsule()
                    .fill(Color.black)
                    .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
            )

            // Minimal circle
            Circle()
                .fill(Color.black)
                .frame(width: 36, height: 36)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .overlay(
                    Circle()
                        .fill(BSColor.Accent.warm)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.black)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 4)
    }

    // MARK: - 4. Countdown Lock Screen Banner

    private var countdownLockScreenBanner: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 12) {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("02:15:30")
                        .font(.system(size: 23, weight: .bold, design: .monospaced))
                        .foregroundColor(BSColor.Accent.warm)

                    Text("距开场")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("「夜航」巡演 · 上海站 · 回声剧场")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text("19:30 开场 · 预计 22:00 散场")
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.textSecondary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    Image(systemName: "map")
                        .font(.system(size: 11, weight: .semibold))
                    Text("路线")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white.opacity(0.14)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    // MARK: - Widgets: Live Mode Medium Widget

    private var liveModeMediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.42, blue: 0.46))
                        .frame(width: 7, height: 7)
                    Text("正在现场")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.81, blue: 0.83))
                }

                Spacer(minLength: 4)

                Text("01:23:45")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(BSColor.textPrimary)

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("草莓音乐节 2026 · 上海站")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)
                    Text("正在演: King Gizzard · 爱舞台")
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.textSecondary)
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
                        colors: [Color(red: 0.03, green: 0.04, blue: 0.07), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 32)
                }
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .frame(height: 155)
        .background(
            Color(red: 0.03, green: 0.04, blue: 0.07)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Widgets: Countdown Medium Widget

    private var countdownMediumWidget: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("距离开场")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.textSecondary)

                Spacer(minLength: 4)

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("56")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundColor(Color(red: 0.96, green: 0.94, blue: 0.89))
                        .monospacedDigit()
                    Text("天")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BSColor.textSecondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text("「夜航」巡演 · 上海站")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)
                    Text("10月14日 19:30 · 回声剧场")
                        .font(.system(size: 10))
                        .foregroundColor(BSColor.textTertiary)
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
                        colors: [Color(red: 0.02, green: 0.02, blue: 0.03), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 36)
                }
        }
        .padding(.leading, 16)
        .padding(.vertical, 14)
        .frame(height: 155)
        .background {
            Image("default_cover")
                .resizable()
                .scaledToFill()
                .blur(radius: 30)
                .overlay(Color(red: 0.02, green: 0.02, blue: 0.03).opacity(0.82))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Widgets: Small Widgets Row

    private var smallLiveWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 1.0, green: 0.42, blue: 0.46))
                    .frame(width: 6, height: 6)
                Text("正在现场")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(red: 1.0, green: 0.81, blue: 0.83))
            }

            Spacer(minLength: 4)

            Text("01:23:45")
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundColor(BSColor.textPrimary)

            Spacer(minLength: 6)

            Text("草莓音乐节")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
            Text("爱舞台")
                .font(.system(size: 10))
                .foregroundColor(BSColor.textSecondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var smallCountdownWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("距离开场")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(BSColor.textSecondary)

            Spacer(minLength: 4)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("56")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(Color(red: 0.96, green: 0.94, blue: 0.89))
                Text("天")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BSColor.textSecondary)
            }

            Spacer(minLength: 6)

            Text("「夜航」巡演")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
            Text("上海站")
                .font(.system(size: 10))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 150)
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Widgets: Listening Medium Widget

    private var listeningMediumWidget: some View {
        HStack(spacing: 14) {
            // Vinyl Record Disc
            ZStack {
                Circle()
                    .fill(Color(white: 0.08))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                Image("default_cover")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("「夜航」预习歌单")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BSColor.Accent.warm)

                Text("山雀 (Live)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)

                Text("万能青年旅店")
                    .font(.system(size: 12))
                    .foregroundColor(BSColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(BSColor.Accent.warm)
                    Text("点击播放")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(height: 110)
        .background(Color(red: 0.04, green: 0.05, blue: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Widgets: Lock Screen Accessory Row

    private var lockScreenAccessoryRow: some View {
        HStack(spacing: 14) {
            // Rectangular
            VStack(alignment: .leading, spacing: 3) {
                Text("还有 56 天")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                Text("「夜航」巡演 · 10月14日 19:30")
                    .font(.system(size: 10))
                    .foregroundColor(BSColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(red: 0.08, green: 0.08, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // Circular
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 3)
                    .frame(width: 50, height: 50)
                Circle()
                    .trim(from: 0, to: 0.65)
                    .stroke(BSColor.Accent.warm, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 50, height: 50)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("56")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                    Text("天")
                        .font(.system(size: 8))
                        .foregroundColor(BSColor.textSecondary)
                }
            }
            .frame(width: 70, height: 70)
            .background(Color(red: 0.08, green: 0.08, blue: 0.11))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }
}
#endif
