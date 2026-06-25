import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var hasFinishedSplash = false
    @State private var selectedTab: BeforeShowTab = .current
    @State private var isShowingFirstShowAdd = false

    var body: some View {
        ZStack {
            if !hasCompletedOnboarding && shows.isEmpty {
                OnboardingPlaceholderView(
                    onStartFirstShow: { isShowingFirstShowAdd = true },
                    onSkip: { hasCompletedOnboarding = true }
                )
                .opacity(hasFinishedSplash ? 1 : 0)
            } else {
                mainTabView
                    .opacity(hasFinishedSplash ? 1 : 0)
            }

            if !hasFinishedSplash {
                SplashView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        hasFinishedSplash = true
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(!hasFinishedSplash)
        .sheet(isPresented: $isShowingFirstShowAdd, onDismiss: {
            hasCompletedOnboarding = true
        }) {
            AddShowCoordinatorSheet()
        }
        #if DEBUG
        .task {
            DebugSampleShowSeeder.seedIfRequested(in: modelContext)
        }
        #endif
    }

    @Query(sort: \Show.date) private var shows: [Show]

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            CurrentShowHomeView()
                .tabItem {
                    Label(BeforeShowTab.current.rawValue, systemImage: BeforeShowTab.current.iconName)
                }
                .tag(BeforeShowTab.current)

            MyShowsListView()
                .tabItem {
                    Label(BeforeShowTab.myShows.rawValue, systemImage: BeforeShowTab.myShows.iconName)
                }
                .tag(BeforeShowTab.myShows)

            SettingsView()
                .tabItem {
                    Label(BeforeShowTab.settings.rawValue, systemImage: BeforeShowTab.settings.iconName)
                }
                .tag(BeforeShowTab.settings)
        }
        .tint(.white)
    }
}

// MARK: - Onboarding Placeholder

private struct OnboardingPlaceholderView: View {
    let onStartFirstShow: () -> Void
    let onSkip: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: BSSpacing.lg) {
                Spacer()

                Text("开场前")
                    .font(.system(size: 48, weight: .light))
                    .tracking(6)
                    .bsGradientText()

                Text("把要去的现场放进来，\n慢慢靠近那一场。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textSecondary)
                    .multilineTextAlignment(.center)

                Button(action: onStartFirstShow) {
                    Text("添加第一场现场")
                        .font(BSFont.caption)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                }
                .padding(.horizontal, 48)

                Button("先逛逛", action: onSkip)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)

                Spacer()
            }
        }
    }
}

// MARK: - Current Show Home

private struct CurrentShowHomeView: View {
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var isShowingAddShowCoordinator = false
    @State private var isShowingToolsSheet = false

    private let selector = CurrentShowSelector()
    private let formatter = ShowDisplayFormatter()

    private var currentShow: Show? {
        selector.selectCurrentShow(from: shows, manualSelection: selections.first)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground()
                    .ignoresSafeArea()

                if let show = currentShow {
                    CurrentShowContentView(show: show, formatter: formatter)
                } else {
                    CurrentShowEmptyStateView(onAddShow: {
                        isShowingAddShowCoordinator = true
                    })
                }
            }
            .overlay(alignment: .top) {
                homeHeader
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet()
            }
            .sheet(isPresented: $isShowingToolsSheet) {
                if let show = currentShow {
                    CurrentShowToolsSheet(show: show)
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                }
            }
        }
    }

    @ViewBuilder
    private var homeHeader: some View {
        HStack(alignment: .center) {
            Text("当前现场")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(BSColor.textSecondary)

            Spacer()

            HStack(spacing: 12) {
                homeToolbarButton(
                    systemImage: "plus",
                    accessibilityLabel: "添加现场",
                    action: { isShowingAddShowCoordinator = true }
                )

                if currentShow != nil {
                    homeToolbarButton(
                        systemImage: "ellipsis",
                        accessibilityLabel: "全部功能",
                        action: { isShowingToolsSheet = true }
                    )
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }

    private func homeToolbarButton(
        systemImage: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.textPrimary)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.10))
                .clipShape(Circle())
        }
        .accessibilityLabel(accessibilityLabel)
    }

}

// MARK: - Tools Sheet

private struct CurrentShowToolsSheet: View {
    let show: Show
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground()
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: BSSpacing.md) {
                        Text("这场现场")
                            .font(BSFont.tag)
                            .tracking(1.4)
                            .foregroundColor(BSColor.textTertiary)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        toolLink(
                            destination: CandidateSongsView(show: show),
                            iconName: "mic.fill",
                            title: "候选曲目",
                            subtitle: "编辑推测歌单",
                            accent: BSColor.Accent.candidate
                        )

                        toolLink(
                            destination: RoundTripPlanView(show: show),
                            iconName: "tram.fill",
                            title: "往返计划",
                            subtitle: "去程和返程安排",
                            accent: BSColor.Accent.travel
                        )

                        toolLink(
                            destination: ShowVideosView(show: show),
                            iconName: "play.rectangle.fill",
                            title: "现场视频",
                            subtitle: "开场前先看几场真正的现场",
                            accent: BSColor.Accent.video
                        )

                        toolLink(
                            destination: ShowFragmentListView(show: show),
                            iconName: "sparkles.rectangle.stack",
                            title: "现场碎片",
                            subtitle: "照片、视频和语音",
                            accent: BSColor.Accent.fragment
                        )
                    }
                    .padding(BSSpacing.md)
                    .padding(.top, BSSpacing.lg)
                    .padding(.bottom, BSSpacing.xl)
                }
                .scrollIndicators(.hidden)
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textPrimary)
                }
            }
        }
    }

    private func toolLink<Destination: View>(
        destination: Destination,
        iconName: String,
        title: String,
        subtitle: String,
        accent: Color
    ) -> some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: BSSpacing.md) {
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text(title)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)

                    Text(subtitle)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.textTertiary)
            }
            .padding(BSSpacing.md)
            .background(Color.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.lg)
                    .stroke(BSColor.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Current Show Content

private struct CurrentShowContentView: View {
    let show: Show
    let formatter: ShowDisplayFormatter

    private var phase: CurrentShowTimeState {
        CurrentShowTimeState(show: show)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    posterCardGlow
                    posterCard
                }
                .padding(.horizontal, 18)
                .padding(.top, 76)

                countdownSection
                    .padding(.top, 8)
                    .offset(y: -6)
                    .padding(.bottom, BSLayout.floatingTabBarClearance + 30)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var posterCardGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.70, green: 0.53, blue: 1.0).opacity(0.22),
                        Color(red: 0.49, green: 0.81, blue: 1.0).opacity(0.10),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 430)
            .blur(radius: 44)
            .offset(y: -10)
    }

    private var posterCard: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fit,
                    alignment: .center,
                    enforcesAspectRatio: false,
                    cornerRadius: 32
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(Color.black)
                .saturation(phase.imageSaturation)
                .opacity(phase.imageOpacity)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.10),
                        Color.black.opacity(0.70),
                        Color.black.opacity(0.96)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.94),
                        Color.black
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: proxy.size.height * 0.34)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                VStack(alignment: .leading, spacing: 10) {
                    Text(show.name)
                        .font(.system(size: 25, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.72)

                    Text(heroMetadata)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.70))
                        .lineLimit(2)
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 32, x: 0, y: 20)
    }

    private var countdownSection: some View {
        VStack(spacing: 8) {
            phase.countdownView()

            Text(phase.helperText)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(BSColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var heroMetadata: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityText = {
            guard let city, !city.isEmpty else { return nil as String? }
            guard let venue, !venue.localizedCaseInsensitiveContains(city) else { return nil as String? }
            return city
        }()

        return [
            venue,
            cityText,
            formatter.dateText(for: show)
        ]
        .compactMap { value in
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return value
        }
        .joined(separator: " · ")
    }
}

// MARK: - Empty State

private struct CurrentShowEmptyStateView: View {
    let onAddShow: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "music.note.house")
                .font(.system(size: 34, weight: .light))
                .bsGradientText()
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )

            Text("先添加一场现场")
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.textPrimary)
                .multilineTextAlignment(.center)

            Text("把要去的音乐现场放进来，\n慢慢靠近那一场。")
                .font(BSFont.body)
                .foregroundColor(BSColor.textSecondary)
                .multilineTextAlignment(.center)

            Button(action: onAddShow) {
                Text("添加现场")
                    .font(BSFont.caption)
                    .foregroundColor(.black)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 13)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            }
            .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
    }
}

// MARK: - Countdown View

private extension CurrentShowTimeState {
    @MainActor
    @ViewBuilder
    func countdownView() -> some View {
        switch kind {
        case .today:
            Text("就是今天")
                .font(.system(size: 40, weight: .light))
                .tracking(1)
                .bsGradientText()
        case .ended:
            Text("已结束")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .canceled:
            Text("已取消")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .postponed:
            Text("待定")
                .font(.system(size: 44, weight: .light))
                .bsGradientText()
        default:
            HStack(alignment: .lastTextBaseline, spacing: BSSpacing.sm) {
                Text(countdownNumber)
                    .font(BSFont.display)
                    .bsGradientText()
                    .minimumScaleFactor(0.6)

                Text(countdownUnit)
                    .font(BSFont.title)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
    }
}

// MARK: - Splash

private struct SplashView: View {
    let onFinish: () -> Void

    @State private var backgroundOpacity = 0.0
    @State private var titleOpacity = 0.0
    @State private var englishNameOpacity = 0.0
    @State private var sloganOpacity = 0.0
    @State private var wholeOpacity = 1.0
    @State private var canAccelerate = false
    @State private var didFinish = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geometry in
                Image("splash_bg")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .opacity(backgroundOpacity)
                    .accessibilityHidden(true)
            }
            .ignoresSafeArea()

            VStack(spacing: 16) {
                Spacer()

                Text("开场前")
                    .font(.system(size: 52, weight: .light))
                    .tracking(6)
                    .foregroundStyle(brandGradient)
                    .opacity(titleOpacity)
                    .accessibilityAddTraits(.isHeader)

                Text("BeforeShow")
                    .font(.system(size: 16, weight: .light))
                    .tracking(8)
                    .foregroundStyle(brandGradient.opacity(0.7))
                    .opacity(englishNameOpacity)

                Text("灯亮之前，先进入状态")
                    .font(.system(size: 14, weight: .light))
                    .tracking(3)
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(sloganOpacity)
                    .padding(.top, 34)

                Spacer()
                    .frame(height: 142)
            }
            .padding(.horizontal, 28)
        }
        .opacity(wholeOpacity)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canAccelerate else { return }
            finish()
        }
        .onAppear(perform: startAnimation)
        .accessibilityElement(children: .combine)
    }

    private func startAnimation() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeOut(duration: 0.8)) {
                backgroundOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.8))
            withAnimation(.easeInOut(duration: 0.4)) {
                titleOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                englishNameOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.3))
            withAnimation(.easeInOut(duration: 0.4)) {
                sloganOpacity = 1
            }

            try? await Task.sleep(for: .seconds(0.2))
            canAccelerate = true

            try? await Task.sleep(for: .seconds(0.4))
            finish()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        withAnimation(.easeInOut(duration: 0.32)) {
            wholeOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.32))
            onFinish()
        }
    }
}

private var brandGradient: LinearGradient {
    LinearGradient(
        colors: [
            Color(red: 0.49, green: 0.81, blue: 1.0),
            Color(red: 0.70, green: 0.53, blue: 1.0),
            Color(red: 1.0, green: 0.70, blue: 0.28)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// MARK: - Debug Sample Seeder

#if DEBUG
@MainActor
private enum DebugSampleShowSeeder {
    static func seedIfRequested(in modelContext: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("--seed-add-show-samples") else {
            return
        }

        do {
            let existingShows = try modelContext.fetch(FetchDescriptor<Show>())
            var showsByName = Dictionary(uniqueKeysWithValues: existingShows.map { ($0.name, $0) })
            var seededShows: [Show] = []

            for draft in sampleDrafts {
                if let show = showsByName[draft.name] {
                    apply(draft, to: show)
                    seededShows.append(show)
                } else {
                    let show = try draft.makeShow()
                    modelContext.insert(show)
                    showsByName[show.name] = show
                    seededShows.append(show)
                }
            }

            if let firstShow = seededShows.first {
                let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
                if let selection = selections.first {
                    selection.select(showID: firstShow.id)
                } else {
                    modelContext.insert(CurrentShowSelection(selectedShowID: firstShow.id))
                }
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed add-show samples: \(error)")
        }
    }

    private static var sampleDrafts: [ShowDraft] {
        [
            ShowDraft(
                name: "康士坦的变化球「犬的视线」2026 巡演 杭州站",
                date: date(2026, 7, 11),
                startTime: time(2026, 7, 11, 19, 0),
                city: "杭州",
                venueName: "杭州 MAO Livehouse",
                artist: "康士坦的变化球",
                coverImageURL: "https://s2.showstart.com/img/2026/0512/18/30/0481358705194e86ad435fd75209d6df_1280_1792_511845.0x0.JPG?imageMogr2/thumbnail/!600x800r/gravity/Center/crop/!600x800",
                type: .livehouse,
                source: .link
            ),
            ShowDraft(
                name: "绿洲音乐节2.0·湖州吴兴站",
                date: date(2026, 6, 27),
                city: "湖州",
                venueName: "吴乐湾音乐广场",
                artist: "刘雨昕, 姚琛, 二手玫瑰, DOUDOU, 椿乐队, 裁缝铺, 麻园诗人, 梅卡德尔, 石岩, 声音碎片, 声音玩具",
                type: .musicFestival,
                source: .link
            )
        ]
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func time(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func apply(_ draft: ShowDraft, to show: Show) {
        show.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        show.date = draft.date
        show.startTime = draft.startTime
        show.endDate = draft.endDate
        show.endTime = draft.endTime
        show.city = draft.city.trimmingCharacters(in: .whitespacesAndNewlines)
        show.venueName = draft.venueName.trimmingCharacters(in: .whitespacesAndNewlines)
        show.artist = draft.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        show.seatSection = draft.seatSection.trimmingCharacters(in: .whitespacesAndNewlines)
        show.coverImageURL = draft.coverImageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        show.artistAvatarURLs = draft.artistAvatarURLs
        show.type = draft.type
        show.changeStatus = .scheduled
    }
}
#endif

#Preview {
    RootView()
}
