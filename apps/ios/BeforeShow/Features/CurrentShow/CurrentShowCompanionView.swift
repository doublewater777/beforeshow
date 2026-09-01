import Foundation
import SwiftData
import SwiftUI

// MARK: - Current Show Companion Presentation

enum CompanionSharedHistory {
    /// Group-level history: completed, confirmed shows whose companion name
    /// sets match exactly. Pairwise counts belong to footprint identity, not here.
    static func shows(matching show: Show, from candidates: [Show]) -> [Show] {
        let names = CompanionNameList.normalized(show.companionNames)
        guard !names.isEmpty else {
            if show.companionStatus == .confirmed, show.endedAt != nil {
                return [show]
            }
            return []
        }

        return candidates
            .filter { candidate in
                candidate.companionStatus == .confirmed
                    && candidate.endedAt != nil
                    && CompanionNameList.isSameGroup(candidate.companionNames, names)
            }
            .sorted { ($0.endedAt ?? .distantPast) > ($1.endedAt ?? .distantPast) }
    }
}

enum CompanionHomeMessagePolicy {
    static func message(accepted: String?, backgroundError _: String?) -> String? {
        accepted
    }
}

struct CompanionQuickActionPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let companionName: String?
    let companionNames: [String]
    let showsPendingIndicator: Bool
    let showsAvatars: Bool

    init(status: ShowCompanionStatus, companionName: String?, isEnded: Bool) {
        self.init(
            status: status,
            companionNames: CompanionNameList.normalized([companionName].compactMap { $0 }),
            isEnded: isEnded
        )
    }

    init(status: ShowCompanionStatus, companionNames: [String], isEnded: Bool) {
        let names = CompanionNameList.normalized(companionNames)
        let joined = CompanionNameList.joined(names)
        self.companionNames = names
        self.companionName = joined
        switch status {
        case .none:
            title = BSLocalization.text("同行")
            accessibilityLabel = BSLocalization.text("同行，邀请朋友")
            showsPendingIndicator = false
            showsAvatars = false
        case .pending:
            title = BSLocalization.text("待确认")
            accessibilityLabel = joined.map { BSLocalization.format("同行，等待%@确认", $0) } ?? BSLocalization.text("同行，待确认")
            showsPendingIndicator = true
            showsAvatars = false
        case .confirmed:
            let displayName = joined ?? BSLocalization.text("同行者")
            title = isEnded ? BSLocalization.text("共同足迹") : BSLocalization.format("与%@", displayName)
            accessibilityLabel = isEnded
                ? (joined.map { BSLocalization.format("同行，与%@的共同足迹", $0) } ?? BSLocalization.text("同行，共同足迹"))
                : BSLocalization.format("同行，与%@已确认", displayName)
            showsPendingIndicator = false
            showsAvatars = true
        case .canceled:
            title = BSLocalization.text("重新邀请")
            accessibilityLabel = joined.map { BSLocalization.format("同行，重新邀请%@", $0) } ?? BSLocalization.text("同行，重新邀请")
            showsPendingIndicator = false
            showsAvatars = false
        }
    }
}

struct CurrentShowCompanionSheet: View {
    let show: Show
    let sharedHistory: [Show]
    let isEnded: Bool
    let coordinator: CompanionSharingCoordinator

    @Environment(\.modelContext) private var modelContext
    @State private var isShowingHistory = false
    @State private var isPreparingInvite = false
    @State private var isRefreshing = false
    @State private var isCanceling = false
    @State private var errorMessage: String?

    init(
        show: Show,
        sharedHistory: [Show],
        isEnded: Bool,
        coordinator: CompanionSharingCoordinator
    ) {
        self.show = show
        self.sharedHistory = sharedHistory
        self.isEnded = isEnded
        self.coordinator = coordinator
    }

    var body: some View {
        BSDrawerSheet(
            detents: [.medium, .large],
            fitsContent: true
        ) {
            ScrollView {
                VStack(spacing: BSSpacing.lg) {
                    switch show.companionStatus {
                    case .none:
                        invitationContent(isRetry: false)
                    case .pending:
                        pendingContent
                    case .confirmed:
                        confirmedContent
                    case .canceled:
                        invitationContent(isRetry: true)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .overlay {
                if isPreparingInvite {
                    preparingOverlay
                }
            }
            .animation(.easeOut(duration: 0.18), value: isPreparingInvite)
        }
        .alert(
            "同行邀请",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            guard show.companionCloudRecordName != nil else { return }
            await coordinator.refreshCompanion(for: show, in: modelContext)
            if let error = coordinator.consumeLastErrorMessage() {
                errorMessage = error
            }
        }
    }

    private func invitationContent(isRetry: Bool) -> some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "person.2",
                title: isRetry ? BSLocalization.text("邀请未接受") : BSLocalization.text("邀请同行"),
                subtitle: isRetry
                    ? BSLocalization.text("可以通过系统分享重新发送邀请，对方点开链接后加入这场同行。")
                    : BSLocalization.text("通过系统分享邀请朋友。对方接受后，会加入这场同行。")
            )

            Button {
                Task { await sendInvitation(isRetry: isRetry) }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text(CompanionInvitePreparingPresentation.primaryActionTitle(
                            isPreparing: true,
                            isRetry: isRetry
                        ))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(
                        CompanionInvitePreparingPresentation.primaryActionTitle(
                            isPreparing: false,
                            isRetry: isRetry
                        ),
                        systemImage: "square.and.arrow.up"
                    )
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isPreparingInvite)
        }
    }

    private var pendingContent: some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "hourglass",
                title: pendingTitle,
                subtitle: BSLocalization.text("已通过系统分享发出邀请。对方点开链接并接受后，这里会自动变成已确认。")
            )

            Button {
                Task { await resendInvitation() }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(BSColor.Stage.foreground)
                        Text(CompanionInvitePreparingPresentation.overlayTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(BSLocalization.text("再次发送"), systemImage: "paperplane")
                }
            }
            .buttonStyle(BSSecondaryButtonStyle())
            .disabled(isPreparingInvite || show.companionShareRecordName == nil)

            Button {
                Task { await refreshStatus() }
            } label: {
                if isRefreshing {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Label(BSLocalization.text("刷新状态"), systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isRefreshing)

            destructiveButton("取消邀请") {
                Task { await cancelInvitation() }
            }
            .disabled(isCanceling)
        }
    }

    @ViewBuilder
    private var confirmedContent: some View {
        if isEnded {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "person.2.fill",
                    title: BSLocalization.text("共同足迹"),
                    subtitle: BSLocalization.text("这场现场已经收进你们共同的记录。")
                )

                sharedMemoryCard

                ShareLink(item: sharedFootprintShareText) {
                    Label(BSLocalization.text("分享共同足迹"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        } else {
            VStack(spacing: BSSpacing.md) {
                BSStageSheetHeader(
                    icon: "person.2.fill",
                    title: BSLocalization.format("与%@同行", displayName),
                    subtitle: BSLocalization.text("这场现场已确认同行。")
                )

                companionMembers

                Text(BSLocalization.format("你们共同看过 %lld 场现场", sharedHistory.count))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.muted)

                if isShowingHistory {
                    historyList
                } else {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isShowingHistory = true
                        }
                    } label: {
                        Label(BSLocalization.text("查看共同足迹"), systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                }

                if show.companionIsOwner != false {
                    Button {
                        Task { await resendInvitation() }
                    } label: {
                        if isPreparingInvite {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Label(BSLocalization.text("邀请更多"), systemImage: "person.badge.plus")
                        }
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                    .disabled(isPreparingInvite || show.companionShareRecordName == nil)
                }

                destructiveButton(show.companionIsOwner == false ? "退出同行" : "取消同行") {
                    Task { await cancelInvitation() }
                }
                .disabled(isCanceling)
            }
        }
    }

    private var companionMembers: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.md) {
                person(name: BSLocalization.text("你"), initial: BSLocalization.text("我"))
                ForEach(Array(memberNames.enumerated()), id: \.offset) { _, name in
                    person(name: name, initial: String(name.prefix(1)))
                }
            }
            .padding(.vertical, BSSpacing.sm)
        }
    }

    private func person(name: String, initial: String) -> some View {
        VStack(spacing: 6) {
            Text(initial)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(BSColor.Stage.background)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [BSColor.Stage.accent, BSColor.Stage.glowBlue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(Circle())
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text("已确认")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(BSColor.Stage.prepare)
        }
    }

    private var sharedMemoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.format("TOGETHER · %@", String(format: "%02d", sharedHistory.count)))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.accent)
            Text(BSLocalization.format("我们一起看的\n第 %lld 场现场", max(1, sharedHistory.count)))
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Text(show.name)
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.lg)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.accent.opacity(0.15), BSColor.Stage.surface],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.accent.opacity(0.20), lineWidth: 1))
    }

    @ViewBuilder
    private var historyList: some View {
        if sharedHistory.isEmpty {
            Text("散场后，共同足迹会从这里开始。")
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, BSSpacing.md)
        } else {
            VStack(spacing: 8) {
                ForEach(sharedHistory.prefix(3)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "music.note")
                            .foregroundColor(BSColor.Stage.accent)
                        Text(item.name)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.Stage.foreground)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(12)
                    .background(BSColor.Stage.surface.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    private func destructiveButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(BSFont.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
        }
        .foregroundColor(BSColor.Stage.liveTitle)
    }

    private var memberNames: [String] {
        CompanionNameList.normalized(show.companionNames)
    }

    private var displayName: String {
        CompanionNameList.joined(memberNames) ?? BSLocalization.text("同行者")
    }

    private var pendingTitle: String {
        if let names = CompanionNameList.joined(memberNames) {
            return BSLocalization.format("等待%@确认", names)
        }
        return BSLocalization.text("等待确认")
    }

    private var sharedFootprintShareText: String {
        BSLocalization.format("我和%@一起看了 %@。\n这是我们共同记录的第 %lld 场现场。", displayName, show.name, max(1, sharedHistory.count))
    }

    private var preparingOverlay: some View {
        ZStack {
            Color.black.opacity(0.38)
            VStack(spacing: BSSpacing.sm) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.08)
                Text(CompanionInvitePreparingPresentation.overlayTitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(CompanionInvitePreparingPresentation.overlayTitle)
        }
        .allowsHitTesting(true)
        .transition(.opacity)
    }

    @MainActor
    private func sendInvitation(isRetry: Bool, alreadyPreparing: Bool = false) async {
        if !alreadyPreparing {
            guard !isPreparingInvite else { return }
            isPreparingInvite = true
        }
        if isRetry, show.companionShareLocator != nil {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("请先完成取消同步，再重新邀请")
            return
        }
        if show.companionShareLocator != nil {
            await resendInvitation(alreadyPreparing: true)
            return
        }
        guard show.companionCloudRecordName == nil else {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("这场现场已有同行邀请，请先刷新状态")
            return
        }
        await coordinator.refreshAllLinkedShows(in: modelContext)
        if CompanionInviteGate.blocksNewInvite(coordinator.lastErrorKind) {
            isPreparingInvite = false
            errorMessage = coordinator.consumeLastErrorMessage()
            return
        }
        _ = coordinator.consumeLastErrorMessage()
        if show.companionShareLocator != nil {
            await resendInvitation(alreadyPreparing: true)
            return
        }
        do {
            let prepared = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: nil,
                ownerDisplayName: nil,
                in: modelContext
            )
            presentPreparedShare(prepared.shareSystemFields)
        } catch {
            isPreparingInvite = false
            CompanionDebugLog.write("sendInvitation failed: \(error)")
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func resendInvitation(alreadyPreparing: Bool = false) async {
        if !alreadyPreparing {
            guard !isPreparingInvite else { return }
            isPreparingInvite = true
        }
        do {
            let data = try await coordinator.shareSystemFieldsForResend(show: show)
            presentPreparedShare(data)
        } catch let error as CompanionSharingError where error == .sessionNotFound {
            // Only recreate when CloudKit positively reports the share is gone.
            await sendInvitation(isRetry: true, alreadyPreparing: true)
        } catch {
            isPreparingInvite = false
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func presentPreparedShare(_ data: Data) {
        let presented = SystemCloudSharePresenter.present(
            shareData: data,
            containerIdentifier: CloudKitCompanionSharingService.defaultContainerIdentifier,
            onEvent: { event, share, error in
                Task { @MainActor in
                    switch event {
                    case .didSave:
                        await coordinator.handleShareControllerDidSave(
                            share: share,
                            for: show,
                            in: modelContext
                        )
                    case .didStopSharing:
                        await coordinator.handleShareControllerDidStopSharing(
                            for: show,
                            in: modelContext
                        )
                    case .failedToSave:
                        if let error {
                            coordinator.handleShareControllerFailure(error)
                            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
                        }
                    }
                }
            },
            onDismiss: {
                isPreparingInvite = false
                if let error = coordinator.consumeLastErrorMessage() {
                    errorMessage = error
                }
            },
            onPresented: {
                isPreparingInvite = false
            }
        )
        if !presented {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("无法打开系统分享")
        }
    }

    @MainActor
    private func refreshStatus() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await coordinator.refreshCompanion(for: show, in: modelContext)
        if let error = coordinator.consumeLastErrorMessage() {
            errorMessage = error
        }
    }

    @MainActor
    private func cancelInvitation() async {
        isCanceling = true
        defer { isCanceling = false }
        do {
            try await coordinator.cancelCompanion(for: show, in: modelContext)
        } catch {
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }
}
