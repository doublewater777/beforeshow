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

    private let selector = CurrentShowSelector()
    private let formatter = ShowDisplayFormatter()

    var body: some View {
        NavigationStack {
            ZStack {
                CurrentShowStageBackground()
                    .ignoresSafeArea()

                if let show = selector.selectCurrentShow(from: shows, manualSelection: selections.first) {
                    CurrentShowContentView(show: show, formatter: formatter)
                } else {
                    CurrentShowEmptyStateView(onAddShow: {
                        isShowingAddShowCoordinator = true
                    })
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingAddShowCoordinator) {
                AddShowCoordinatorSheet()
            }
        }
    }
}

// MARK: - Current Show Content

private struct CurrentShowContentView: View {
    let show: Show
    let formatter: ShowDisplayFormatter

    @AppStorage("homeStyle") private var homeStyleRawValue = SettingsInformation.defaultHomeStyleRawValue

    private var homeStyle: HomeStyle {
        HomeStyle(rawValue: homeStyleRawValue) ?? .halfCover
    }

    private var phase: CurrentShowTimeState {
        CurrentShowTimeState(show: show)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                posterCard
                    .padding(.horizontal, BSSpacing.md)
                    .padding(.top, BSSpacing.xl)

                countdownSection
                    .padding(.top, BSSpacing.xl)
                    .padding(.bottom, 120)
            }
        }
        .scrollIndicators(.hidden)
    }

    private var posterCard: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.2,
                    contentMode: .fill,
                    alignment: .top,
                    enforcesAspectRatio: false,
                    cornerRadius: 32
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .saturation(phase.imageSaturation)
                .opacity(phase.imageOpacity)

                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.45),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    Text(show.name)
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)

                    Text(heroMetadata)
                        .font(BSFont.caption)
                        .foregroundColor(Color.white.opacity(0.70))
                        .lineLimit(2)
                }
                .padding(22)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .aspectRatio(3.0 / 4.2, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 32))
        .overlay(
            RoundedRectangle(cornerRadius: 32)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 32, x: 0, y: 20)
    }

    private var countdownSection: some View {
        ZStack {
            StageOrb()
                .frame(width: 140, height: 140)
                .offset(y: -18)

            VStack(spacing: BSSpacing.sm) {
                phase.countdownView()

                Text(phase.helperText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var heroMetadata: String {
        [
            show.venueName,
            show.city,
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
            let existingNames = try Set(modelContext.fetch(FetchDescriptor<Show>()).map(\.name))
            var insertedShows: [Show] = []

            for draft in sampleDrafts where !existingNames.contains(draft.name) {
                let show = try draft.makeShow()
                modelContext.insert(show)
                insertedShows.append(show)
            }

            if let firstShow = insertedShows.first,
               try modelContext.fetch(FetchDescriptor<CurrentShowSelection>()).isEmpty {
                modelContext.insert(CurrentShowSelection(selectedShowID: firstShow.id))
            }

            try modelContext.save()
        } catch {
            assertionFailure("Failed to seed add-show samples: \(error)")
        }
    }

    private static var sampleDrafts: [ShowDraft] {
        [
            ShowDraft(
                name: "Chris James: Let The Light In! Tour 2026杭州站",
                date: date(2026, 8, 15),
                startTime: time(2026, 8, 15, 20, 0),
                city: "杭州",
                venueName: "CH8 Livehouse(杭州小河店)",
                artist: "Chris James",
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
}
#endif

#Preview {
    RootView()
}
