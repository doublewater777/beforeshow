import PostHog
import SwiftData
import SwiftUI

enum OnboardingCompletionStore {
    static let appStorageKey = "has_completed_feature_onboarding_v1"

    static func hasCompleted(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: appStorageKey)
    }

    static func markCompleted(in defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: appStorageKey)
    }
}

enum OnboardingRoutingPolicy {
    static func shouldPresent(hasCompleted: Bool, hasShows: Bool) -> Bool {
        !hasCompleted && !hasShows
    }

    static func shouldMigrateExistingUser(hasCompleted: Bool, hasShows: Bool) -> Bool {
        !hasCompleted && hasShows
    }
}

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case beforeShow
    case listening
    case showDay
    case afterShow
    case start

    var id: Int { rawValue }

    var analyticsValue: String {
        switch self {
        case .beforeShow: "before_show"
        case .listening: "listening"
        case .showDay: "show_day"
        case .afterShow: "after_show"
        case .start: "start"
        }
    }

    func phaseText(for snapshot: CompanionInviteSnapshot? = nil) -> String {
        switch self {
        case .beforeShow: return BSLocalization.text("开场前")
        case .listening: return BSLocalization.text("听")
        case .showDay: return BSLocalization.text("现场当天")
        case .afterShow: return BSLocalization.text("散场以后")
        case .start:
            if let snapshot {
                let isPast = snapshot.showStartTime < Date()
                return isPast
                    ? BSLocalization.text("共同记忆")
                    : BSLocalization.text("同行约定")
            }
            return BSLocalization.text("现在开始")
        }
    }

    var phaseText: String { phaseText(for: nil) }

    func title(for snapshot: CompanionInviteSnapshot? = nil) -> String {
        switch self {
        case .beforeShow: return BSLocalization.text("不用打开，也在靠近")
        case .listening: return BSLocalization.text("把歌听熟，把期待留给现场")
        case .showDay: return BSLocalization.text("重要的内容，抬手就能找到")
        case .afterShow: return BSLocalization.text("把这一晚，轻轻留住")
        case .start:
            if let snapshot {
                let isPast = snapshot.showStartTime < Date()
                return isPast
                    ? BSLocalization.text("记录这场共同回忆")
                    : BSLocalization.text("一起去现场")
            }
            return BSLocalization.text("从下一场开始，慢慢靠近")
        }
    }

    var title: String { title(for: nil) }

    func bodyText(for snapshot: CompanionInviteSnapshot? = nil) -> String {
        switch self {
        case .listening:
            return BSLocalization.text("从唱片柜选一张 CD，提前熟悉演出的歌，留下你想现场听的那一首。")
        case .beforeShow:
            return BSLocalization.text("主屏幕和锁屏都替你数着那一天，再在几个值得记一下的节点轻轻提醒。")
        case .showDay:
            return BSLocalization.text("选择一张演出流程、阵容安排或时间图片，保存到这场现场，需要时快速打开。")
        case .afterShow:
            return BSLocalization.text("照片、视频和小记按现场阶段收在一起，散场时再用五档情绪评价，为这一晚收尾。")
        case .start:
            if let snapshot {
                let isPast = snapshot.showStartTime < Date()
                if isPast {
                    return BSLocalization.format(
                        "加入这场现场，和 %@ 一起收录当晚的照片、视频和小记，留住共同的现场记忆。",
                        snapshot.ownerName
                    )
                } else {
                    return BSLocalization.format(
                        "加入这场现场，和 %@ 一起倒数、听歌、记录现场，散场后留住共同的记忆。",
                        snapshot.ownerName
                    )
                }
            }
            return BSLocalization.text("开场前的期待、现场当天的重要内容和散场后的记忆，都收在同一场现场里。")
        }
    }

    var bodyText: String { bodyText(for: nil) }
}

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var modelContext
    let invitedSnapshot: CompanionInviteSnapshot?
    let onCompleted: () -> Void

    init(
        invitedSnapshot: CompanionInviteSnapshot? = nil,
        initialPage: OnboardingPage = .beforeShow,
        onCompleted: @escaping () -> Void
    ) {
        self.invitedSnapshot = invitedSnapshot
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--onboarding-page-start") {
            _page = State(initialValue: .start)
        } else {
            _page = State(initialValue: initialPage)
        }
        #else
        _page = State(initialValue: initialPage)
        #endif
        self.onCompleted = onCompleted
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: OnboardingPage = .beforeShow
    @State private var isShowingAddShow = false
    @State private var hasCapturedStart = false

    var body: some View {
        ZStack {
            onboardingBackground

            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { item in
                    OnboardingPageView(
                        page: item,
                        invitedSnapshot: invitedSnapshot,
                        onAddShow: {
                            isShowingAddShow = true
                            PostHogSDK.shared.capture("onboarding_add_show_tapped")
                        },
                        onJoinInvite: { _ in
                            guard let snapshot = invitedSnapshot else { return (false, nil) }
                            PostHogSDK.shared.capture(
                                "onboarding_invite_accepted",
                                properties: ["token": snapshot.token, "show": snapshot.showName]
                            )
                            let outcome = await CompanionInviteClipboardDetector.acceptDirectly(
                                snapshot: snapshot,
                                in: modelContext
                            )
                            if outcome.success {
                                completeOnboarding(method: "invite_join")
                            }
                            return outcome
                        }
                    )
                    .tag(item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            chrome
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingAddShow) {
            AddShowCoordinatorSheet { _ in
                completeOnboarding(method: "add_show")
            }
        }
        .onAppear {
            guard !hasCapturedStart else { return }
            hasCapturedStart = true
            PostHogSDK.shared.capture("onboarding_started")
        }
        .onChange(of: page) { _, newPage in
            PostHogSDK.shared.capture(
                "onboarding_page_viewed",
                properties: ["page": newPage.analyticsValue]
            )
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            BSColor.Stage.background
            Image("splash_bg")
                .resizable()
                .scaledToFill()
                .saturation(0.72)
                .brightness(-0.28)
                .opacity(0.50)
                .accessibilityHidden(true)
            LinearGradient(
                colors: [
                    BSColor.Stage.background.opacity(0.18),
                    BSColor.Stage.background.opacity(0.64),
                    BSColor.Stage.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack {
                Text("开场前")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2.6)
                    .foregroundColor(BSColor.Stage.foreground)

                Spacer()

                Button(action: skipOnboarding) {
                    Text(invitedSnapshot != nil ? BSLocalization.text("暂不加入") : BSLocalization.text("跳过"))
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .frame(minWidth: 64, minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, BSSpacing.xl + BSSpacing.md)

            Spacer()

            HStack(spacing: BSSpacing.md) {
                if invitedSnapshot == nil {
                    pageIndicator
                }
                Spacer()
                if page != .start {
                    Button(BSLocalization.text("继续"), action: advance)
                        .buttonStyle(OnboardingContinueButtonStyle())
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, BSSpacing.xl + BSSpacing.lg)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingPage.allCases) { item in
                Capsule()
                    .fill(item == page ? BSColor.Stage.foreground : Color.white.opacity(0.20))
                    .frame(width: item == page ? 22 : 6, height: 6)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: page)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            BSLocalization.format(
                "第 %lld 页，共 %lld 页",
                Int64(page.rawValue + 1),
                Int64(OnboardingPage.allCases.count)
            )
        )
    }

    private func advance() {
        guard let next = OnboardingPage(rawValue: page.rawValue + 1) else { return }
        move(to: next)
    }

    private func move(to destination: OnboardingPage) {
        if reduceMotion {
            page = destination
        } else {
            withAnimation(.easeInOut(duration: 0.28)) {
                page = destination
            }
        }
    }

    private func skipOnboarding() {
        if let snapshot = invitedSnapshot {
            CompanionInviteClipboardDetector.markTokenProcessed(snapshot.token)
        }
        PostHogSDK.shared.capture(
            "onboarding_skipped",
            properties: ["from_page": page.analyticsValue]
        )
        completeOnboarding(method: "skip")
    }

    private func completeOnboarding(method: String) {
        OnboardingCompletionStore.markCompleted()
        PostHogSDK.shared.capture(
            "onboarding_completed",
            properties: ["method": method]
        )
        onCompleted()
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    var invitedSnapshot: CompanionInviteSnapshot? = nil
    let onAddShow: () -> Void
    var onJoinInvite: ((String) async -> (success: Bool, errorMessage: String?))? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visualAppeared = false
    @State private var textAppeared = false
    @State private var bodyAppeared = false
    @State private var nickname: String = CompanionUserProfile.nickname ?? ""
    @State private var isJoining = false
    @State private var joinErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                switch page {
                case .beforeShow:
                    OnboardingWidgetFeatureVisual()
                case .listening:
                    OnboardingListeningVisual()
                case .showDay:
                    OnboardingTimetableFeatureVisual()
                case .afterShow:
                    OnboardingMemoryFeatureVisual()
                case .start:
                    if let snapshot = invitedSnapshot {
                        OnboardingInvitedFeatureVisual(snapshot: snapshot)
                    } else {
                        OnboardingStartFeatureVisual()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: page == .start ? (invitedSnapshot != nil ? 340 : 405) : 430)
            .scaleEffect(visualAppeared ? 1 : 0.92)
            .opacity(visualAppeared ? 1 : 0)

            Spacer(minLength: 0)

            Text(page.phaseText(for: invitedSnapshot))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.3)
                .foregroundColor(BSColor.Stage.accent)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)

            Text(page.title(for: invitedSnapshot))
                .font(.custom("Songti SC", size: (page == .start && invitedSnapshot != nil) ? 28 : (page == .start ? 36 : 32), relativeTo: .largeTitle))
                .foregroundColor(BSColor.Stage.foreground)
                .lineSpacing(3)
                .lineLimit(page == .start && invitedSnapshot != nil ? 2 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)
                .opacity(textAppeared ? 1 : 0)
                .offset(y: textAppeared ? 0 : 12)

            Text(page.bodyText(for: invitedSnapshot))
                .font(.system(size: 13))
                .foregroundColor(BSColor.Stage.muted)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .opacity(bodyAppeared ? 1 : 0)
                .offset(y: bodyAppeared ? 0 : 10)

            if page == .start {
                if let _ = invitedSnapshot {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 4) {
                                Text(BSLocalization.text("你的称呼"))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(BSColor.Stage.foreground)
                                Text(BSLocalization.text("· 同行成员可见，可选"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BSColor.Stage.dim)
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(BSColor.Stage.accent)
                                TextField(BSLocalization.text("输入你的昵称"), text: $nickname)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(BSColor.Stage.foreground)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(BSColor.Stage.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BSColor.Stage.border))
                        }

                        if let joinErrorMessage {
                            Text(joinErrorMessage)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        Button {
                            guard !isJoining else { return }
                            isJoining = true
                            joinErrorMessage = nil
                            let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                CompanionUserProfile.nickname = trimmed
                            }
                            Task {
                                if let onJoinInvite {
                                    let result = await onJoinInvite(trimmed)
                                    if !result.success {
                                        joinErrorMessage = result.errorMessage
                                        isJoining = false
                                    }
                                }
                            }
                        } label: {
                            if isJoining {
                                ProgressView()
                                    .tint(.black)
                                    .frame(maxWidth: .infinity)
                            } else {
                                Text(BSLocalization.text("接受邀请，进入现场"))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                        .disabled(isJoining)

                        Button(action: onAddShow) {
                            Text(BSLocalization.text("或者，添加我自己的现场"))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(BSColor.Stage.muted)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.top, 16)
                    .opacity(bodyAppeared ? 1 : 0)
                    .offset(y: bodyAppeared ? 0 : 10)
                } else {
                    Button(BSLocalization.text("添加我的第一个现场"), action: onAddShow)
                        .buttonStyle(BSPrimaryButtonStyle())
                        .padding(.top, 26)
                        .opacity(bodyAppeared ? 1 : 0)
                        .offset(y: bodyAppeared ? 0 : 10)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, (page == .start && invitedSnapshot != nil) ? 44 : 58)
        .padding(.bottom, BSSpacing.xl * 3 + BSSpacing.sm)
        .accessibilityElement(children: .contain)
        .onAppear { runEntrance() }
        .onChange(of: page) { _, _ in runEntrance() }
    }

    private func runEntrance() {
        guard !reduceMotion else {
            visualAppeared = true
            textAppeared = true
            bodyAppeared = true
            return
        }
        visualAppeared = false
        textAppeared = false
        bodyAppeared = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            visualAppeared = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.easeOut(duration: 0.25)) {
                textAppeared = true
            }
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.easeOut(duration: 0.2)) {
                bodyAppeared = true
            }
        }
    }
}

private struct OnboardingContinueButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 22)
            .frame(minWidth: 92, minHeight: BSLayout.minTouchTarget)
            .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 15))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
