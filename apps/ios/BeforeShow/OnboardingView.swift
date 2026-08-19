import SwiftData
import SwiftUI
import UIKit

// MARK: - Onboarding
//
// 六页长流程（原型：apps/ios/prototypes/onboarding-v4.html）：
//   P1-P3 价值三幕 —— 视觉区是产品自身的界面切片（首页倒计时卡 / 现场状态卡
//         + 记忆碎片 / 足迹统计 + 仪式卡），演示数据全部虚构，避免侵权。
//   P4     小组件 —— 复刻 medium / 锁屏长条的真实样式做静态预览。
//   P5     偏好选择 ——  chips 落 @AppStorage，画像卡即时生成（选择即回报）。
//   P6     第一场现场 —— 三个入口直接复用 AddShowCoordinatorSheet 对应流程。
//   P7     第一个倒计时 —— 展示刚创建的真实现场；提醒卡接真实通知权限状态。
struct OnboardingView: View {
    let onFinish: () -> Void

    @Query(sort: \Show.date) private var shows: [Show]
    @AppStorage("onboardingPreferredGenres") private var preferredGenresRaw = "[]"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    @State private var page = 0
    @State private var addShowSheet: OnboardingAddShowRequest?
    @State private var starsLit = false
    @State private var notificationAuthorization: NotificationAuthorizationState = .notDetermined

    private static let lastPage = 6
    /// 偏好选择页：「跳过」直接落到这页。
    private static let personalizationPageIndex = 4
    private static let firstShowPageIndex = 5

    var body: some View {
        // 背景用 .background 挂，内容 VStack 保持在安全区内
        // （ZStack 叠一个 ignoresSafeArea 的背景会把内容一起顶进状态栏区域）。
        VStack(spacing: 0) {
            topBar

            TabView(selection: $page) {
                valuePageAnticipation.tag(0)
                valuePageLive.tag(1)
                valuePageAfterglow.tag(2)
                widgetPage.tag(3)
                personalizationPage.tag(4)
                firstShowPage.tag(5)
                firstCountdownPage.tag(6)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            footer
        }
        .background(onboardingBackground)
        .onChange(of: page) { _, newPage in
            // P3 熄灯仪式演示：进入时星标逐个点亮，离开即复位。
            if newPage == 2 {
                starsLit = false
                withAnimation(reduceMotion ? .none : .easeOut(duration: 0.3).delay(0.5)) {
                    starsLit = true
                }
            } else {
                starsLit = false
            }
        }
        .sheet(item: $addShowSheet) { request in
            AddShowCoordinatorSheet(initialSheet: request.initialSheet) {
                addShowSheet = nil
                withAnimation(.easeInOut(duration: 0.3)) {
                    page = Self.lastPage
                }
            }
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.arguments.contains("--open-add-show-manual") {
                addShowSheet = OnboardingAddShowRequest(initialSheet: .manual)
            }
        }
        #endif
    }

    // MARK: - Scaffold

    private var onboardingBackground: some View {
        ZStack {
            BSColor.Stage.background

            Image("default_cover")
                .resizable()
                .scaledToFill()
                .opacity(0.20)
                .accessibilityHidden(true)

            LinearGradient(
                stops: [
                    .init(color: BSColor.Stage.background.opacity(0.62), location: 0.00),
                    .init(color: BSColor.Stage.background.opacity(0.30), location: 0.34),
                    .init(color: BSColor.Stage.background.opacity(0.55), location: 0.66),
                    .init(color: BSColor.Stage.background.opacity(0.96), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // P3 熄灯：只压环境光，内容在其之上保持点亮。
            Color.black.opacity(page == 2 ? 0.55 : 0)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: reduceMotion ? 0 : 1.1), value: page == 2)
    }

    private var topBar: some View {
        HStack {
            Spacer(minLength: 0)
            if page <= 2 {
                Button(BSLocalization.text("跳过")) {
                    withAnimation(.easeInOut(duration: 0.3)) { page = Self.personalizationPageIndex }
                }
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.dim)
                .padding(.horizontal, BSSpacing.xs)
                .frame(minHeight: BSLayout.minTouchTarget)
            }
        }
        .frame(height: 40)
        .padding(.horizontal, BSSpacing.roomy)
    }

    private var footer: some View {
        VStack(spacing: BSSpacing.sm) {
            pageDots
                .padding(.bottom, BSSpacing.xs)

            Button(action: primaryAction) {
                Text(primaryTitle)
            }
            .buttonStyle(BSPrimaryButtonStyle())

            if page == Self.firstShowPageIndex {
                Button(BSLocalization.text("先逛逛"), action: onFinish)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 30)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0...Self.lastPage, id: \.self) { index in
                Capsule()
                    .fill(index == page ? BSColor.Stage.accent : Color.white.opacity(0.18))
                    .frame(width: index == page ? 20 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: page)
        .accessibilityHidden(true)
    }

    private var primaryTitle: String {
        switch page {
        case Self.firstShowPageIndex: return BSLocalization.text("把下一场放进来")
        case Self.lastPage: return BSLocalization.text("进入开场前")
        default: return BSLocalization.text("继续")
        }
    }

    private func primaryAction() {
        switch page {
        case Self.firstShowPageIndex:
            addShowSheet = OnboardingAddShowRequest(initialSheet: nil)
        case Self.lastPage:
            onFinish()
        default:
            withAnimation(.easeInOut(duration: 0.3)) { page = min(page + 1, Self.lastPage) }
        }
    }

    // MARK: - Page Head

    private func pageHead(kicker: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BSLocalization.text(kicker))
                .font(BSFont.tag)
                .tracking(3)
                .foregroundColor(BSColor.Stage.accent)

            Text(BSLocalization.text(title))
                .font(.system(size: 30, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)
                .padding(.top, 10)

            Text(BSLocalization.text(subtitle))
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .lineSpacing(5)
                .padding(.top, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: - P1 · 开场前

    private var valuePageAnticipation: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "开场前",
                title: "把期待变成倒计时",
                subtitle: "要去的现场放进来，慢慢靠近那一天。"
            )

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 232)
                    .clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(BSColor.Stage.border, lineWidth: 1)
                    )
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    HStack {
                        onboardingBadge(dot: BSColor.Stage.accent, text: BSLocalization.text("开场前"))
                        Spacer(minLength: 0)
                        Text("COUNTDOWN")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(2)
                            .foregroundColor(BSColor.Stage.dim)
                    }

                    Text(BSLocalization.text("「夜航」巡演 · 上海站"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    Text(BSLocalization.text("2026.10.13 周二 19:30 · 回声剧场"))
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("56")
                            .font(.system(size: 76, weight: .light))
                            .foregroundColor(BSColor.Stage.heroIvory)
                            .monospacedDigit()
                        Text(BSLocalization.text("天"))
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.muted)
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 6)

                    HStack(spacing: 8) {
                        onboardingQuickIcon("ticket")
                        onboardingQuickIcon("clock")
                        onboardingQuickIcon("person.2")
                        onboardingQuickIcon("map")
                    }
                    .padding(.top, 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 15)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    // MARK: - P2 · 灯亮时

    private var valuePageLive: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "灯亮时",
                title: "把当下留住",
                subtitle: "灯亮的时候，值得留一点下来。"
            )

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    HStack {
                        onboardingBadge(dot: BSColor.Stage.live, text: BSLocalization.text("正在现场"), pulsing: true)
                        Spacer(minLength: 0)
                        Text("ON STAGE")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(2)
                            .foregroundColor(BSColor.Stage.dim)
                    }

                    Text(BSLocalization.text("「晚风」专场"))
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    Text(BSLocalization.text("2026.08.14 周五 20:00 · 南岸 Livehouse"))
                        .font(.system(size: 12.5))
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)

                    Rectangle()
                        .fill(BSColor.Stage.border)
                        .frame(height: 1)
                        .padding(.top, 14)

                    HStack {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(BSColor.Stage.live)
                                .frame(width: 8, height: 8)
                                .modifier(OnboardingPulseModifier())
                            Text(BSLocalization.text("正在现场"))
                                .font(BSFont.body)
                                .foregroundColor(BSColor.Stage.foreground)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("1:25:52")
                                .font(.system(size: 26, weight: .light))
                                .monospacedDigit()
                                .foregroundColor(BSColor.Stage.foreground)
                            Text(BSLocalization.text("已开场"))
                                .font(.system(size: 11))
                                .foregroundColor(BSColor.Stage.dim)
                        }
                    }
                    .padding(.top, 13)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )

                VStack(spacing: 0) {
                    onboardingCardKicker("记忆碎片")

                    HStack(spacing: 8) {
                        Image("default_cover")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 96)
                            .brightness(0.1)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        Image("default_cover")
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 96)
                            .hueRotation(.degrees(30))
                            .saturation(1.15)
                            .brightness(0.12)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .accessibilityHidden(true)
                    .padding(.top, 11)

                    Text(BSLocalization.text("「安可前的大合唱，整片手机灯海。」"))
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 11)

                    HStack {
                        Text("21:47")
                        Spacer(minLength: 0)
                        Text(BSLocalization.text("仅自己可见"))
                    }
                    .font(.system(size: 11))
                    .foregroundColor(BSColor.Stage.dim)
                    .padding(.top, 8)
                }
                .padding(14)
                .background(BSColor.Stage.surface)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    // MARK: - P3 · 散场后

    private var valuePageAfterglow: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "散场后",
                title: "每场奔赴都算数",
                subtitle: "熄灯仪式落幕，足迹替你数着每一场。"
            )

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 22) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("3")
                            .font(.system(size: 72, weight: .light))
                            .monospacedDigit()
                            .foregroundColor(BSColor.Stage.foreground)
                        Text(BSLocalization.text("场"))
                            .font(BSFont.body)
                            .foregroundColor(BSColor.Stage.muted)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        onboardingStatRow(value: "2", label: "今年")
                        onboardingStatRow(value: "2", label: "城市")
                        onboardingStatRow(value: "2", label: "位艺人")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)

                VStack(spacing: 0) {
                    onboardingCardKicker("散场仪式 · 已落幕")

                    Text(BSLocalization.format("第 %lld 场现场", 3))
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 13)

                    Text(BSLocalization.text("「晚风」专场 · 2026.08.14"))
                        .font(.system(size: 12))
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 5)

                    HStack(spacing: 7) {
                        ForEach(0..<5, id: \.self) { index in
                            Image(systemName: "star.fill")
                                .font(.system(size: 15))
                                .foregroundColor(index < 4 ? BSColor.Stage.accent : Color.white.opacity(0.14))
                                .scaleEffect(starsLit ? 1 : 0.6)
                                .opacity(starsLit ? 1 : 0)
                                .animation(
                                    reduceMotion ? .none : .spring(response: 0.4, dampingFraction: 0.6).delay(Double(index) * 0.17),
                                    value: starsLit
                                )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 13)

                    Rectangle()
                        .fill(BSColor.Stage.border)
                        .frame(height: 1)
                        .padding(.top, 15)

                    HStack {
                        Text(BSLocalization.text("第一场现场：2025.11 · 雾屿乐队"))
                            .font(.system(size: 12))
                            .foregroundColor(BSColor.Stage.dim)
                        Spacer(minLength: 0)
                        Text(BSLocalization.text("查看足迹 →"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BSColor.Stage.accent)
                    }
                    .padding(.top, 13)
                }
                .padding(18)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private func onboardingStatRow(value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Text(value)
                .font(BSFont.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text(label))
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
        }
    }

    // MARK: - P4 · 小组件

    /// 复刻真实小组件（CountdownWidgetViews 的 medium / 锁屏长条）的静态预览，
    /// 演示数据与 P1 同一场「夜航」巡演，封面用自有 default_cover。
    private var widgetPage: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "小组件",
                title: "不用打开，也在靠近",
                subtitle: "主屏幕和锁屏，都替你数着那一天。"
            )

            Spacer(minLength: 0)

            VStack(spacing: 14) {
                mediumWidgetMock
                lockScreenWidgetMock

                Text(BSLocalization.text("长按主屏幕，搜索「开场前」添加。"))
                    .font(.system(size: 11.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var mediumWidgetMock: some View {
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
                    Text(BSLocalization.text("10月13日 19:30 · 回声剧场"))
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
    }

    private var lockScreenWidgetMock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(BSLocalization.format("还有 %lld 天", 56))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("「夜航」巡演 · 上海站 · 10月13日 19:30"))
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
    }

    // MARK: - P5 · 为你调校（偏好 → 现场画像）

    private var personalizationPage: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "为你调校",
                title: "你常去哪种现场？",
                subtitle: "先记下来，之后慢慢调。"
            )

            OnboardingGenreFlow(spacing: 10) {
                ForEach(OnboardingGenre.allCases) { genre in
                    Button {
                        toggleGenre(genre)
                    } label: {
                        Text(BSLocalization.text(genre.titleKey))
                            .font(BSFont.body)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(
                                selectedGenres.contains(genre)
                                    ? BSColor.Stage.accent.opacity(0.10)
                                    : BSColor.Stage.surface
                            )
                            .foregroundColor(
                                selectedGenres.contains(genre)
                                    ? BSColor.Stage.accent
                                    : BSColor.Stage.muted
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedGenres.contains(genre)
                                            ? BSColor.Stage.accent.opacity(0.55)
                                            : BSColor.Stage.border,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 22)

            VStack(spacing: 0) {
                onboardingCardKicker("你的现场画像")

                Text(personaText)
                    .font(.system(size: 17))
                    .foregroundColor(
                        selectedGenres.isEmpty ? BSColor.Stage.dim : BSColor.Stage.foreground
                    )
                    .lineSpacing(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 13)
                    .animation(.easeInOut(duration: 0.25), value: personaText)

                if !selectedGenres.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(selectedGenres) { genre in
                            Text(BSLocalization.text(genre.titleKey))
                                .font(.system(size: 11))
                                .tracking(1)
                                .foregroundColor(BSColor.Stage.muted)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 4)
                                .overlay(
                                    Capsule().stroke(BSColor.Stage.border, lineWidth: 1)
                                )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 11)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 17)
            .background(BSColor.Stage.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
            .padding(.top, 24)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private var selectedGenres: [OnboardingGenre] {
        let raws = (try? JSONDecoder().decode([String].self, from: Data(preferredGenresRaw.utf8))) ?? []
        return OnboardingGenre.allCases.filter { raws.contains($0.rawValue) }
    }

    private func toggleGenre(_ genre: OnboardingGenre) {
        var raws = selectedGenres.map(\.rawValue)
        if let index = raws.firstIndex(of: genre.rawValue) {
            raws.remove(at: index)
        } else {
            raws.append(genre.rawValue)
        }
        preferredGenresRaw = String(decoding: (try? JSONEncoder().encode(raws)) ?? Data("[]".utf8), as: UTF8.self)
    }

    private var personaText: String {
        let phrases = selectedGenres.map { BSLocalization.text($0.personaKey) }
        guard !phrases.isEmpty else { return BSLocalization.text("还没有偏好，先去逛逛也好。") }
        return phrases.joined(separator: "，") + "。"
    }

    // MARK: - P6 · 第一场现场

    private var firstShowPage: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "第一场",
                title: "把下一场放进来",
                subtitle: "只要名称和日期就成立，其余之后慢慢补。"
            )

            VStack(spacing: 0) {
                onboardingAddEntryRow(
                    icon: "square.and.pencil",
                    title: "手动填写",
                    subtitle: "自己填写现场的基本信息。",
                    sheet: .manual
                )
                Rectangle().fill(BSColor.Stage.border).frame(height: 1)
                onboardingAddEntryRow(
                    icon: "photo.on.rectangle",
                    title: "截图识别",
                    subtitle: "选择票务截图，仅在本机识别，图片不会上传。",
                    sheet: .screenshot
                )
                Rectangle().fill(BSColor.Stage.border).frame(height: 1)
                onboardingAddEntryRow(
                    icon: "link",
                    title: "链接解析",
                    subtitle: "粘贴支持平台的票务链接，需要联网解析。",
                    sheet: .link
                )
            }
            .background(BSColor.Stage.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
            .padding(.top, 22)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
    }

    private func onboardingAddEntryRow(icon: String, title: String, subtitle: String, sheet: AddShowSheet) -> some View {
        Button {
            addShowSheet = OnboardingAddShowRequest(initialSheet: sheet)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(width: 34, height: 34)
                    .background(BSColor.Stage.accent.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(BSLocalization.text(title))
                        .font(BSFont.body)
                        .fontWeight(.medium)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(BSLocalization.text(subtitle))
                        .font(.system(size: 11.5))
                        .foregroundColor(BSColor.Stage.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.Stage.dim)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - P7 · 你的第一个倒计时

    /// 刚创建的第一场现场：最近的未来场。
    private var firstShow: Show? {
        let now = Date()
        return shows.first(where: { $0.date >= now }) ?? shows.last
    }

    private var firstCountdownPage: some View {
        VStack(spacing: 0) {
            pageHead(
                kicker: "准备就绪",
                title: "你的第一个倒计时",
                subtitle: "从现在起，慢慢靠近那一天。"
            )

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                VStack(spacing: 0) {
                    HStack {
                        onboardingBadge(dot: BSColor.Stage.accent, text: BSLocalization.text("已放入当前现场"))
                        Spacer(minLength: 0)
                        Text("COUNTDOWN")
                            .font(.system(size: 10, weight: .medium))
                            .tracking(2)
                            .foregroundColor(BSColor.Stage.dim)
                    }

                    Text(firstShow?.name ?? "")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(BSColor.Stage.foreground)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 12)

                    if let firstShow {
                        Text(firstShowMeta(firstShow))
                            .font(.system(size: 12.5))
                            .foregroundColor(BSColor.Stage.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 5)

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(daysUntil(firstShow.date))")
                                .font(.system(size: 72, weight: .light))
                                .foregroundColor(BSColor.Stage.heroIvory)
                                .monospacedDigit()
                            Text(BSLocalization.text("天"))
                                .font(BSFont.body)
                                .foregroundColor(BSColor.Stage.muted)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 15)
                .background(BSColor.Stage.surfaceRaised)
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.Stage.border, lineWidth: 1)
                )

                notificationReminderCard
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .task(id: page) {
            // 每次进到这页都重读一次：添加流程里的 primer 可能刚改过授权状态。
            guard page == Self.lastPage else { return }
            notificationAuthorization = await LocalNotificationCenter.shared.authorizationState()
        }
    }

    /// 接真实通知权限状态：已授权展示确认态；未决定给「开启」（此时系统弹窗还没用过，
    /// 比如用户在添加流程的 primer 里选了「暂时不用」）；被拒绝则跳系统设置。
    private var notificationReminderCard: some View {
        HStack(spacing: 13) {
            Image(systemName: notificationAuthorization == .authorized ? "bell.badge.fill" : "bell.badge")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 34, height: 34)
                .background(BSColor.Stage.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(BSLocalization.text("开场提醒"))
                    .font(BSFont.body)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(reminderSubtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(BSColor.Stage.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)

            switch notificationAuthorization {
            case .authorized, .provisional:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(BSColor.Stage.accent)
            case .notDetermined:
                Button {
                    Task { @MainActor in
                        _ = await LocalNotificationCenter.shared.requestAuthorization()
                        notificationAuthorization = await LocalNotificationCenter.shared.authorizationState()
                    }
                } label: {
                    Text(BSLocalization.text("开启"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(BSColor.Stage.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            case .denied:
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    openURL(url)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BSColor.Stage.dim)
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(BSColor.Stage.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }

    private var reminderSubtitle: String {
        switch notificationAuthorization {
        case .authorized, .provisional:
            return BSLocalization.text("已开启，重要的节点会提醒你。")
        case .denied:
            return BSLocalization.text("未开启，去系统设置打开。")
        case .notDetermined:
            return BSLocalization.text("在重要的节点，轻轻提醒你。")
        }
    }

    private func firstShowMeta(_ show: Show) -> String {
        // date 的时分是脏数据（表单 DatePicker 只改日期），时刻要取 startTime，和首页卡片一致。
        let calendar = show.timingCalendar()
        let dayFormatter = DateFormatter()
        dayFormatter.locale = AppLanguageManager.persisted.locale
        dayFormatter.calendar = calendar
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateFormat = "yyyy.MM.dd E"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = AppLanguageManager.persisted.locale
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"
        let moment = "\(dayFormatter.string(from: show.effectiveDate)) \(timeFormatter.string(from: show.startTime))"
        let venue = HomeShowIdentityPresentation.venueSummary(venue: show.venueName, city: show.city)
        return [moment, venue].compactMap { $0 }.joined(separator: " · ")
    }

    private func daysUntil(_ date: Date) -> Int {
        let calendar = Calendar.current
        let from = calendar.startOfDay(for: Date())
        let to = calendar.startOfDay(for: date)
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    // MARK: - Shared bits

    private func onboardingBadge(dot: Color, text: String, pulsing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if pulsing {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
                    .modifier(OnboardingPulseModifier())
            } else {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(BSColor.Stage.foreground)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(BSColor.Stage.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private func onboardingCardKicker(_ text: String) -> some View {
        HStack(spacing: 8) {
            Text(BSLocalization.text(text))
                .font(.system(size: 11, weight: .medium))
                .tracking(2)
                .foregroundColor(BSColor.Stage.accent)
            Rectangle()
                .fill(BSColor.Stage.border)
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func onboardingQuickIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(BSColor.Stage.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(BSColor.Stage.surface)
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.Stage.border, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Genre model

private enum OnboardingGenre: String, CaseIterable, Identifiable {
    case livehouse, festival, arena, theater, talkshow, club

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .livehouse: return "Livehouse"
        case .festival: return "音乐节"
        case .arena: return "体育馆演唱会"
        case .theater: return "剧场"
        case .talkshow: return "脱口秀"
        case .club: return "电子俱乐部"
        }
    }

    var personaKey: String {
        switch self {
        case .livehouse: return "离音箱最近的那排"
        case .festival: return "夕阳下的压轴"
        case .arena: return "万人大合唱的看台"
        case .theater: return "灯暗下来的那一刻"
        case .talkshow: return "前排被 cue 的风险区"
        case .club: return "低频穿过胸口的位置"
        }
    }
}

// MARK: - Add show request

private struct OnboardingAddShowRequest: Identifiable {
    let id = UUID()
    let initialSheet: AddShowSheet?
}

// MARK: - Flow layout for genre chips

private struct OnboardingGenreFlow: Layout {
    var spacing: CGFloat = 10

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Pulse modifier

private struct OnboardingPulseModifier: ViewModifier {
    @State private var pulsing = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulsing ? 1.25 : 1)
            .opacity(pulsing ? 0.7 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

