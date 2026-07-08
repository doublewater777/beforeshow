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

    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var roundTripPlans: [RoundTripPlan]
    @Query private var preparationPlans: [ShowPreparationPlan]
    @Query private var videos: [ShowVideo]

    private var phase: CurrentShowTimeState {
        CurrentShowTimeState(show: show)
    }

    @State private var activeToolSheet: ToolSheet?

    enum ToolSheet: Identifiable {
        case candidateSongs, roundTrip, preparation, videos, fragments
        var id: Self { self }
    }

    private struct HomeToolItem: Identifiable {
        let id: ToolSheet
        let icon: String
        let title: String
        let status: String
        let detail: String
        let actionTitle: String
        let accent: Color
        let priority: Int
        let isComplete: Bool

        var accessibilityLabel: String {
            "\(title)，\(status)，\(detail)，点按\(actionTitle)"
        }
    }

    private var summary: ShowToolSummary {
        ShowToolSummary(
            show: show,
            candidateGroups: candidateGroups,
            candidateSongs: candidateSongs,
            roundTripPlans: roundTripPlans,
            preparationPlans: preparationPlans,
            videos: videos
        )
    }

    private var tip: ShowTip? {
        ShowTipsResolver.resolve(
            phase: phase,
            hasCandidateSongs: summary.hasCandidateSongs,
            hasOutboundPlan: summary.hasOutboundPlan,
            hasFragments: summary.hasFragments
        )
    }

    private var roundTripPlan: RoundTripPlan? {
        roundTripPlans.first { $0.showID == show.id }
    }

    private var showsDepartureAssistant: Bool {
        guard phase.kind == .today,
              let plan = roundTripPlan,
              plan.hasSavedDeparturePlan,
              let startTime = phase.effectiveStartTime else {
            return false
        }
        return Date() < startTime
    }

    private var isDepartureOverdue: Bool {
        guard let leaveAt = roundTripPlan?.departureLeaveAt else { return false }
        return Date() > leaveAt
    }

    @ViewBuilder
    private var departureAssistantCard: some View {
        if let plan = roundTripPlan,
           let leaveAt = plan.departureLeaveAt,
           let mode = plan.savedDepartureMode,
           let duration = plan.departureDurationMinutes,
           let arriveAt = plan.departureArriveAt {
            Button {
                openDepartureMap(plan)
            } label: {
                HStack(spacing: 12) {
                    toolIcon(mode.iconName, accent: BSColor.Accent.travel, size: 38, iconSize: 15)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("出行小助手")
                                .font(.system(size: 11, weight: .semibold))
                                .tracking(1.2)
                                .foregroundColor(BSColor.textTertiary)
                                .textCase(.uppercase)
                            if isDepartureOverdue {
                                Text("已过出门时间")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(BSColor.Accent.fragment)
                            }
                        }
                        Text(isDepartureOverdue
                             ? "该出门了，\(mode.displayName)约 \(duration) 分钟"
                             : "今天 \(timeText(leaveAt)) 出门，\(mode.displayName)约 \(duration) 分钟")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BSColor.textSecondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("预计 \(timeText(arriveAt)) 到场")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(BSColor.textTertiary)
                    }

                    Spacer(minLength: 0)

                    Text("打开地图")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.black.opacity(0.88))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(BSColor.brandGradientSoft))
                        .clipShape(Capsule())
                }
                .padding(13)
                .homeGlass(cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10)
            }
            .buttonStyle(HomeToolButtonStyle())
            .accessibilityLabel("出行小助手，今天\(timeText(leaveAt))出门")
        }
    }

    @MainActor
    private func openDepartureMap(_ plan: RoundTripPlan) {
        if let url = plan.savedDepartureNavigationURL {
            UIApplication.shared.open(url)
            return
        }
        if let url = RoundTripPlanView.appleMapsDirectionsURL(origin: plan.departureOrigin, destination: plan.departureDestination) {
            UIApplication.shared.open(url)
        }
    }

    private var homeToolItems: [HomeToolItem] {
        [
            candidateSongsToolItem,
            roundTripToolItem,
            preparationToolItem,
            videosToolItem,
            fragmentsToolItem
        ]
        .sorted { first, second in
            if first.priority == second.priority {
                return first.title < second.title
            }
            return first.priority < second.priority
        }
    }

    private var recommendedToolItem: HomeToolItem {
        if let tip,
           let matching = homeToolItems.first(where: { $0.id == toolSheet(for: tip.action) }) {
            return matching
        }

        return homeToolItems.first(where: { !$0.isComplete }) ?? homeToolItems[0]
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    compactHeader
                        .padding(.horizontal, 18)
                        .padding(.top, 18)

                    countdownHero
                        .padding(.top, 8)

                    if showsDepartureAssistant {
                        departureAssistantCard
                            .padding(.horizontal, 18)
                            .padding(.top, 6)
                    }

                    toolsScrollSection
                        .padding(.top, 6)

                    Spacer(minLength: BSLayout.floatingTabBarClearance + 20)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .sheet(item: $activeToolSheet) { tool in
            NavigationStack {
                Group {
                    switch tool {
                    case .candidateSongs: CandidateSongsView(show: show)
                    case .roundTrip: RoundTripPlanView(show: show)
                    case .preparation: ShowPreparationView(show: show)
                    case .videos: ShowVideosView(show: show)
                    case .fragments: ShowFragmentListView(show: show)
                    }
                }
                .toolbarBackground(.hidden, for: .navigationBar)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func toolSheet(for action: ShowTip.ShowTipAction) -> ToolSheet {
        switch action {
        case .candidateSongs: return .candidateSongs
        case .outboundPlan: return .roundTrip
        case .showPreparation: return .preparation
        case .showVideos: return .videos
        case .showFragments: return .fragments
        }
    }

    private var compactHeader: some View {
        NavigationLink {
            ShowDetailView(show: show)
        } label: {
            HStack(spacing: 12) {
                ShowCoverImageView(
                    urlString: show.coverImageURL,
                    aspectRatio: 3.0 / 4.0,
                    contentMode: .fill,
                    alignment: .center,
                    enforcesAspectRatio: false,
                    cornerRadius: 12
                )
                .frame(width: 52, height: 69)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.30), radius: 9, y: 5)

                VStack(alignment: .leading, spacing: 6) {
                    Text(show.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    VStack(alignment: .leading, spacing: 3) {
                        labeledMetadata(icon: "calendar", text: formatter.dateText(for: show))
                        if !locationText.isEmpty {
                            labeledMetadata(icon: "mappin.and.ellipse", text: locationText)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(minHeight: 90)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.135),
                                Color.white.opacity(0.060)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.22), radius: 13, y: 7)
        }
        .buttonStyle(.plain)
    }

    private var countdownHero: some View {
        ZStack {
            HomeStageLightRig()
                .frame(height: 344)
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                Text(countdownEyebrow)
                    .font(.system(size: 31, weight: .light))
                    .tracking(1.0)
                    .bsGradientText()

                countdownDisplay
            }
            .offset(y: -4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 344)
    }

    @ViewBuilder
    private var countdownDisplay: some View {
        switch phase.kind {
        case .today:
            Text("就是今天")
                .font(.system(size: 54, weight: .light))
                .tracking(1)
                .bsGradientText()
        case .ended:
            Text("已结束")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .canceled:
            Text("已取消")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(BSColor.textTertiary)
        case .postponed:
            Text("待定")
                .font(.system(size: 74, weight: .light))
                .bsGradientText()
        default:
            HStack(alignment: .lastTextBaseline, spacing: 18) {
                Text(phase.countdownNumber)
                    .font(.system(size: 178, weight: .light))
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                    .bsGradientText()

                Text(phase.countdownUnit)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(Color.white.opacity(0.78))
                    .offset(y: -18)
            }
        }
    }

    private func labeledMetadata(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
                .frame(width: 14)

            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(BSColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var toolsScrollSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            homeHintCard(recommendedToolItem)
                .padding(.horizontal, 18)

            VStack(alignment: .leading, spacing: 9) {
                Text("也可以顺手看看")
                    .font(BSFont.tag)
                    .tracking(1.2)
                    .foregroundColor(BSColor.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(homeToolItems) { item in
                            toolShortcutCard(item)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func homeHintCard(_ item: HomeToolItem) -> some View {
        Button {
            activeToolSheet = item.id
        } label: {
            HStack(spacing: 12) {
                toolIcon(item.icon, accent: item.accent, size: 38, iconSize: 15)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("Tips · \(phase.title)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(BSColor.textTertiary)
                            .textCase(.uppercase)
                            .lineLimit(1)

                        statusPill(item.status, accent: item.accent)
                    }

                    Text(item.detail)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BSColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(item.actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(BSColor.brandGradientSoft))
                    .clipShape(Capsule())
            }
            .padding(13)
            .homeGlass(cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10)
        }
        .buttonStyle(HomeToolButtonStyle())
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func toolShortcutCard(_ item: HomeToolItem) -> some View {
        Button {
            activeToolSheet = item.id
        } label: {
            HStack(spacing: 10) {
                toolIcon(item.icon, accent: item.accent, size: 36, iconSize: 14)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textPrimary)
                        .lineLimit(1)

                    Text(item.status)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BSColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 10)
            .frame(width: 154, height: 64, alignment: .leading)
            .homeGlass(cornerRadius: 17, fillOpacity: 0.045, strokeOpacity: 0.085)
        }
        .buttonStyle(HomeToolButtonStyle())
        .accessibilityLabel(item.accessibilityLabel)
    }

    private func toolIcon(_ icon: String, accent: Color, size: CGFloat, iconSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: size + 4, height: size + 4)
                .blur(radius: 12)

            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: size, height: size)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: size * 0.30))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.30)
                        .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                )
        }
    }

    private func statusPill(_ status: String, accent: Color) -> some View {
        Text(status)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(accent)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(accent.opacity(0.12)))
    }

    private var candidateSongsToolItem: HomeToolItem {
        let hasSongs = summary.hasCandidateSongs
        return HomeToolItem(
            id: .candidateSongs,
            icon: "mic.fill",
            title: "候选曲目",
            status: summary.candidateSongsStatus,
            detail: hasSongs ? "公开信息推测，可继续删改顺序。" : "先生成一版推测歌单，开场前更有期待感。",
            actionTitle: hasSongs ? "查看" : "生成",
            accent: BSColor.Accent.candidate,
            priority: candidateSongsPriority(hasSongs: hasSongs),
            isComplete: hasSongs
        )
    }

    private var roundTripToolItem: HomeToolItem {
        let hasPlan = summary.hasOutboundPlan
        return HomeToolItem(
            id: .roundTrip,
            icon: "tram.fill",
            title: "去程计划",
            status: summary.roundTripStatus,
            detail: summary.savedDepartureReminderText
                ?? (hasPlan ? "出门方案已在本机保存，出发前可再核对。" : "补出发地，生成公共交通、驾车和打车参考。"),
            actionTitle: hasPlan ? "查看" : "补充",
            accent: BSColor.Accent.travel,
            priority: roundTripPriority(hasPlan: hasPlan),
            isComplete: hasPlan
        )
    }

    private var preparationToolItem: HomeToolItem {
        let hasReminder = summary.hasPreparationReminder
        let hasCheckedAll = summary.hasCheckedAllPreparation
        let status = summary.preparationStatus
        let detail = hasReminder
            ? "已设置准备提醒，继续确认装备和注意事项。"
            : "确认票证、电量、场馆规则，可顺手设提醒。"

        return HomeToolItem(
            id: .preparation,
            icon: "sparkles",
            title: "现场准备",
            status: status,
            detail: detail,
            actionTitle: hasCheckedAll ? "复查" : "检查",
            accent: BSColor.Accent.prepare,
            priority: preparationPriority(isComplete: hasCheckedAll),
            isComplete: hasCheckedAll
        )
    }

    private var videosToolItem: HomeToolItem {
        let hasVideos = summary.hasVideos
        return HomeToolItem(
            id: .videos,
            icon: "play.rectangle.fill",
            title: "现场视频",
            status: summary.videosStatus,
            detail: hasVideos ? "开场前先看几场真正的现场。" : "整理可打开的 B站现场，给这场预热。",
            actionTitle: hasVideos ? "观看" : "整理",
            accent: BSColor.Accent.video,
            priority: videosPriority(hasVideos: hasVideos),
            isComplete: hasVideos
        )
    }

    private var fragmentsToolItem: HomeToolItem {
        let hasFragments = summary.hasFragments
        return HomeToolItem(
            id: .fragments,
            icon: "sparkles.rectangle.stack",
            title: "现场碎片",
            status: summary.fragmentsStatus,
            detail: hasFragments ? "照片、文字和声音会留在这场现场里。" : "演出当天把照片、文字或语音留住。",
            actionTitle: hasFragments ? "查看" : "添加",
            accent: BSColor.Accent.fragment,
            priority: fragmentsPriority(hasFragments: hasFragments),
            isComplete: hasFragments
        )
    }

    private func candidateSongsPriority(hasSongs: Bool) -> Int {
        if hasSongs { return 62 }
        switch phase.kind {
        case .before where phase.dayDistance >= 8:
            return 12
        case .before:
            return 34
        default:
            return 72
        }
    }

    private func roundTripPriority(hasPlan: Bool) -> Int {
        if hasPlan { return 54 }
        switch phase.kind {
        case .today:
            return 8
        case .before where phase.dayDistance <= 7:
            return 10
        case .before:
            return 28
        default:
            return 68
        }
    }

    private func preparationPriority(isComplete: Bool) -> Int {
        if isComplete { return 58 }
        switch phase.kind {
        case .today:
            return 9
        case .before where phase.dayDistance <= 1:
            return 11
        case .before where phase.dayDistance <= 7:
            return 22
        default:
            return 46
        }
    }

    private func videosPriority(hasVideos: Bool) -> Int {
        if hasVideos { return 64 }
        switch phase.kind {
        case .before:
            return 36
        case .today:
            return 52
        default:
            return 76
        }
    }

    private func fragmentsPriority(hasFragments: Bool) -> Int {
        if hasFragments {
            switch phase.kind {
            case .postShow, .ended:
                return 18
            default:
                return 56
            }
        }

        switch phase.kind {
        case .today, .postShow:
            return 7
        case .ended:
            return 20
        default:
            return 82
        }
    }

    private func timeText(_ date: Date) -> String {
        Self.timeFormatter.string(from: date)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var countdownEyebrow: String {
        switch phase.kind {
        case .before:
            return "还有"
        case .today:
            return "就是今天"
        case .postShow:
            return "散场后"
        case .ended:
            return "记忆已收好"
        case .canceled:
            return "现场变更"
        case .postponed:
            return "时间待定"
        }
    }

    private var locationText: String {
        let venue = show.venueName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityText = {
            guard let city, !city.isEmpty else { return nil as String? }
            guard let venue, !venue.localizedCaseInsensitiveContains(city) else { return nil as String? }
            return city
        }()

        return [
            venue,
            cityText
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

private extension View {
    func homeGlass(cornerRadius: CGFloat, fillOpacity: Double, strokeOpacity: Double) -> some View {
        self
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(fillOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(strokeOpacity), lineWidth: 0.75)
            )
    }
}

private struct HomeToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct HomeStageLightRig: View {
    var body: some View {
        GeometryReader { geometry in
            Image("splash_bg")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .saturation(1.08)
                .contrast(1.05)
                .opacity(0.78)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.48),
                            Color.black.opacity(0.05),
                            Color.black.opacity(0.36)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .compositingGroup()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .white, location: 0.16),
                    .init(color: .white, location: 0.82),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.00),
                    .init(color: .white, location: 0.10),
                    .init(color: .white, location: 0.90),
                    .init(color: .clear, location: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
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
        show.venueAddress = draft.venueAddress.trimmingCharacters(in: .whitespacesAndNewlines)
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
