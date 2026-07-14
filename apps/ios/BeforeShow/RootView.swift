import SwiftData
import SwiftUI
import UIKit

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
                CurrentShowAmbientBackground(coverImageURL: currentShow?.coverImageURL)

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

enum HomeLayoutMetrics {
    static let horizontalInset: CGFloat = 18

    static func contentWidth(for containerWidth: CGFloat, viewportWidth: CGFloat) -> CGFloat {
        max(0, min(containerWidth, viewportWidth) - (horizontalInset * 2))
    }
}

private struct CurrentShowContentView: View {
    let show: Show
    let formatter: ShowDisplayFormatter

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var roundTripPlans: [RoundTripPlan]
    @Query private var preparationPlans: [ShowPreparationPlan]

    private var phase: CurrentShowTimeState {
        CurrentShowTimeState(show: show)
    }

    @State private var activeToolSheet: ToolSheet?
    @State private var managementSheet: ManagementSheet?

    enum ToolSheet: Identifiable {
        case candidateSongs, roundTrip, preparation, fragments
        var id: Self { self }
    }

    enum ManagementSheet: Identifiable {
        case edit, delete
        var id: Self { self }
    }

    private struct HomeToolItem: Identifiable {
        let id: ToolSheet
        let icon: String
        let title: String
        let status: String
        let accent: Color
        let priority: Int

        var accessibilityLabel: String {
            "\(title)，\(status)"
        }
    }

    private var summary: ShowToolSummary {
        ShowToolSummary(
            show: show,
            candidateGroups: candidateGroups,
            candidateSongs: candidateSongs,
            roundTripPlans: roundTripPlans,
            preparationPlans: preparationPlans
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
        if let url = DeparturePlanSession.appleMapsDirectionsURL(origin: plan.departureOrigin, destination: plan.departureDestination) {
            UIApplication.shared.open(url)
        }
    }

    private var homeToolItems: [HomeToolItem] {
        [
            candidateSongsToolItem,
            roundTripToolItem,
            preparationToolItem,
            fragmentsToolItem
        ]
        .sorted { first, second in
            if first.priority == second.priority {
                return first.title < second.title
            }
            return first.priority < second.priority
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = HomeLayoutMetrics.contentWidth(
                for: geometry.size.width,
                viewportWidth: UIScreen.main.bounds.width
            )
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    posterStage(contentWidth: contentWidth)
                        .padding(.top, 8)

                    // 18pt VStack spacing + 2pt = 20pt cover-to-countdown pause.
                    countdownHero
                        .padding(.top, 2)

                    if showsDepartureAssistant {
                        departureAssistantCard
                            .padding(.top, 6)
                    }

                    toolsScrollSection(contentWidth: contentWidth)
                        .padding(.top, 0)
                }
                .padding(.horizontal, HomeLayoutMetrics.horizontalInset)
                .padding(.bottom, BSLayout.tabBarContentInset + 28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .sheet(item: $managementSheet) { sheet in
                switch sheet {
                case .edit:
                    ShowDraftEditorView(
                        title: "编辑现场",
                        draft: ShowDraft(show: show),
                        saveTitle: "保存"
                    ) { draft in
                        apply(draft)
                    }
                case .delete:
                    BSDangerConfirmationSheet(
                        title: "删除现场",
                        message: "删除后，这场现场的碎片、候选曲目、去程计划和准备事项也会一起删除；相册里的原图不会被删。删除后无法恢复。",
                        destructiveTitle: "删除",
                        onConfirm: {
                            managementSheet = nil
                            deleteShow()
                        },
                        onCancel: {
                            managementSheet = nil
                        }
                    )
                }
            }
        }
        .sheet(item: $activeToolSheet) { tool in
            NavigationStack {
                Group {
                    switch tool {
                    case .candidateSongs: CandidateSongsView(show: show)
                    case .roundTrip: RoundTripPlanView(show: show)
                    case .preparation: ShowPreparationView(show: show)
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
        case .showFragments: return .fragments
        }
    }

    private func posterStage(contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            NavigationLink {
                ShowDetailView(show: show)
            } label: {
                coverVisual(contentWidth: contentWidth)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("现场封面，\(show.name)，点按进入详情")
            .accessibilityAddTraits(.isButton)

            overflowMenu
                .padding(12)
        }
    }

    private func coverVisual(contentWidth: CGFloat) -> some View {
        let coverWidth = contentWidth
        let coverHeight = coverWidth * 4.0 / 3.0
        return ShowCoverImageView(
            urlString: show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            alignment: .center,
            enforcesAspectRatio: false,
            cornerRadius: 0
        )
        .frame(width: coverWidth, height: coverHeight)
        .overlay {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.42), location: 0.00),
                    .init(color: .clear, location: 0.20),
                    .init(color: .clear, location: 0.46),
                    .init(color: Color.black.opacity(0.28), location: 0.62),
                    .init(color: Color.black.opacity(0.86), location: 0.90),
                    .init(color: Color.black.opacity(0.96), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottomLeading) {
            coverMetadata
                .padding(18)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
    }

    private var coverMetadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(show.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.80)
                .shadow(color: .black.opacity(0.6), radius: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(formatter.dateText(for: show))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if !locationText.isEmpty {
                    Text(locationText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
            }
        }
    }

    private var overflowMenu: some View {
        Menu {
            Button {
                managementSheet = .edit
            } label: {
                Label("编辑现场", systemImage: "square.and.pencil")
            }
            if shows.count > 1 {
                Menu {
                    ForEach(otherShows) { other in
                        Button {
                            selectCurrent(other)
                        } label: {
                            Text(other.name)
                        }
                    }
                } label: {
                    Label("切换当前现场", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            Button(role: .destructive) {
                managementSheet = .delete
            } label: {
                Label("删除现场", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color.white.opacity(0.92))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                )
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.035))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        }
        .accessibilityLabel("更多现场操作")
    }

    private var otherShows: [Show] {
        shows.filter { $0.id != show.id }
    }

    private func selectCurrent(_ other: Show) {
        let selection = selections.first ?? CurrentShowSelection()
        if selections.isEmpty {
            modelContext.insert(selection)
        }
        selection.select(showID: other.id)
        try? modelContext.save()
    }

    private func apply(_ draft: ShowDraft) {
        show.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        show.date = draft.date
        show.startTime = draft.startTime
        show.endDate = draft.endDate
        show.endTime = draft.endTime
        show.city = trimmedOptional(draft.city)
        show.venueName = trimmedOptional(draft.venueName)
        show.venueAddress = trimmedOptional(draft.venueAddress)
        show.artist = trimmedOptional(draft.artist)
        show.seatSection = trimmedOptional(draft.seatSection)
        show.coverImageURL = trimmedOptional(draft.coverImageURL)
        show.artistAvatarURLs = draft.artistAvatarURLs
        show.type = draft.type
        try? modelContext.save()
    }

    private func deleteShow() {
        do {
            try LocalAppDataDeletionService(audioStorage: .applicationSupport())
                .deleteShow(show, in: modelContext)
            try? modelContext.save()
        } catch {
            // Silent: failure leaves the show in place; home has nothing to dismiss.
        }
    }

    private func trimmedOptional(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var countdownHero: some View {
        countdownDisplay
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(countdownAccessibilityLabel)
    }

    private var countdownAccessibilityLabel: String {
        switch phase.kind {
        case .today:
            return "就是今天"
        case .ended:
            return "已结束"
        case .canceled:
            return "已取消"
        case .postponed:
            return "待定"
        default:
            return "距离开场还有 \(phase.countdownNumber) \(phase.countdownUnit)"
        }
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
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(phase.countdownNumber)
                    .font(.system(size: 74, weight: .light))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .bsGradientText()

                Text(phase.countdownUnit)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.78))
                    .offset(y: -6)
            }
        }
    }

    private func toolsScrollSection(contentWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tips surface is ShowTipsResolver only: message + button + action.
            // nil ⇒ hide (never invent tool-item copy as Tips).
            if let tip {
                homeTipCard(tip, contentWidth: contentWidth)
            }

            VStack(alignment: .leading, spacing: 9) {
                Text("也可以顺手看看")
                    .font(BSFont.tag)
                    .tracking(1.2)
                    .foregroundColor(BSColor.textTertiary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    alignment: .leading,
                    spacing: 10
                ) {
                    ForEach(homeToolItems) { item in
                        toolShortcutCard(item)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: contentWidth, alignment: .leading)
    }

    private func homeTipCard(_ tip: ShowTip, contentWidth: CGFloat) -> some View {
        let chrome = tipChrome(for: tip.action)
        return Button {
            activeToolSheet = toolSheet(for: tip.action)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    toolIcon(chrome.icon, accent: chrome.accent, size: 38, iconSize: 15)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tips · \(phase.title)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.2)
                            .foregroundColor(BSColor.textTertiary)
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.88)

                        Text(tip.message)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BSColor.textSecondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(tip.buttonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(BSColor.brandGradientSoft))
                    .clipShape(Capsule())
            }
            .frame(width: max(0, contentWidth - 20), alignment: .leading)
            .padding(10)
            .homeGlass(cornerRadius: 18, fillOpacity: 0.06, strokeOpacity: 0.10)
        }
        .frame(width: contentWidth)
        .buttonStyle(HomeToolButtonStyle())
        .accessibilityLabel("\(tip.message)，点按\(tip.buttonTitle)")
    }

    private func tipChrome(for action: ShowTip.ShowTipAction) -> (icon: String, accent: Color) {
        switch action {
        case .candidateSongs:
            return ("mic.fill", BSColor.Accent.candidate)
        case .outboundPlan:
            return ("tram.fill", BSColor.Accent.travel)
        case .showPreparation:
            return ("sparkles", BSColor.Accent.prepare)
        case .showFragments:
            return ("sparkles.rectangle.stack", BSColor.Accent.fragment)
        }
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
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
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

    private var candidateSongsToolItem: HomeToolItem {
        let hasSongs = summary.hasCandidateSongs
        return HomeToolItem(
            id: .candidateSongs,
            icon: "mic.fill",
            title: "候选曲目",
            status: summary.candidateSongsStatus,
            accent: BSColor.Accent.candidate,
            priority: candidateSongsPriority(hasSongs: hasSongs)
        )
    }

    private var roundTripToolItem: HomeToolItem {
        let hasPlan = summary.hasOutboundPlan
        return HomeToolItem(
            id: .roundTrip,
            icon: "tram.fill",
            title: "去程计划",
            status: summary.roundTripStatus,
            accent: BSColor.Accent.travel,
            priority: roundTripPriority(hasPlan: hasPlan)
        )
    }

    private var preparationToolItem: HomeToolItem {
        let hasCheckedAll = summary.hasCheckedAllPreparation
        return HomeToolItem(
            id: .preparation,
            icon: "sparkles",
            title: "现场准备",
            status: summary.preparationStatus,
            accent: BSColor.Accent.prepare,
            priority: preparationPriority(isComplete: hasCheckedAll)
        )
    }

    private var fragmentsToolItem: HomeToolItem {
        let hasFragments = summary.hasFragments
        return HomeToolItem(
            id: .fragments,
            icon: "sparkles.rectangle.stack",
            title: "现场碎片",
            status: summary.fragmentsStatus,
            accent: BSColor.Accent.fragment,
            priority: fragmentsPriority(hasFragments: hasFragments)
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
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
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
                name: "周杰伦嘉年华世界巡回演唱会 · 南京站",
                date: date(2026, 9, 24),
                startTime: time(2026, 9, 24, 19, 30),
                city: "南京",
                venueName: "南京奥体中心体育场",
                artist: "周杰伦",
                coverImageURL: "https://img.alicdn.com/bao/uploaded/https://img.alicdn.com/imgextra/i2/2251059038/O1CN01nWPQm82GdSnG5tWAW_!!2251059038.jpg_q60.jpg_.webp",
                type: .concert,
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
