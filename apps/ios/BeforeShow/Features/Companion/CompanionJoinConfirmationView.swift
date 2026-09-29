import SwiftData
import SwiftUI

/// Product confirmation shown after iOS hands a CloudKit invitation to the app, but
/// before the companion relationship is committed and the Show is imported locally.
struct CompanionPendingJoinHost: View {
    let onJoinSuccess: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(CompanionSharingCoordinator.self) private var coordinator
    @State private var isWorking = false
    @State private var isJoiningInBackground = false
    @State private var isDismissedByUser = false
    @State private var queuedSuccessMessage: String?
    @State private var errorMessage: String?

    private var isPresented: Bool {
        (coordinator.isLoadingInvitation || coordinator.pendingJoinSession != nil)
            && !isJoiningInBackground
            && !isDismissedByUser
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .fullScreenCover(
                isPresented: Binding(
                    get: { isPresented },
                    set: {
                        if !$0,
                           !isWorking,
                           !isJoiningInBackground,
                           coordinator.pendingJoinSession != nil {
                            handleClose()
                        }
                    }
                ),
                onDismiss: {
                    if let message = queuedSuccessMessage {
                        queuedSuccessMessage = nil
                        onJoinSuccess(message)
                    }
                    isJoiningInBackground = false
                }
            ) {
                CompanionJoinConfirmationView(
                    session: coordinator.pendingJoinSession,
                    isLoading: coordinator.isLoadingInvitation && coordinator.pendingJoinSession == nil,
                    isWorking: isWorking,
                    onJoin: { confirmJoin() },
                    onClose: { handleClose() }
                )
                .interactiveDismissDisabled(isWorking || coordinator.isLoadingInvitation)
            }
            .alert(
                BSLocalization.text("同行邀请"),
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button(BSLocalization.text("知道了"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onChange(of: coordinator.isLoadingInvitation) { _, isLoading in
                if isLoading {
                    isDismissedByUser = false
                }
            }
            .onChange(of: coordinator.pendingJoinSession) { _, session in
                if session != nil {
                    isDismissedByUser = false
                }
            }
            .onChange(of: coordinator.pendingAcceptMessage, initial: true) { _, message in
                guard !isWorking,
                      let message, coordinator.pendingJoinSession == nil else { return }
                onJoinSuccess(message)
                _ = coordinator.consumePendingAcceptMessage()
                _ = coordinator.consumePendingAcceptResult()
            }
            .onChange(of: coordinator.lastErrorMessage) { _, message in
                if let message, coordinator.pendingJoinSession == nil {
                    errorMessage = message
                    _ = coordinator.consumeLastErrorMessage()
                }
            }
    }

    private func handleClose() {
        isDismissedByUser = true
        if coordinator.pendingJoinSession != nil {
            declineJoin()
        }
    }

    private func confirmJoin() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await coordinator.confirmPendingJoin(in: modelContext)
            if succeeded {
                offerCurrentSwitchForLiveShowIfNeeded()
                if let message = coordinator.consumePendingAcceptMessage() {
                    queuedSuccessMessage = message
                }
                _ = coordinator.consumePendingAcceptResult()
                isJoiningInBackground = true
            } else {
                errorMessage = coordinator.consumeLastErrorMessage() ?? BSLocalization.text("现场还没添加成功，请重试")
            }
            isWorking = false
        }
    }

    private func declineJoin() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await coordinator.declinePendingJoin(in: modelContext)
            if !succeeded {
                errorMessage = coordinator.lastErrorMessage ?? BSLocalization.text("暂时无法关闭这份邀请，请重试")
            }
            isWorking = false
        }
    }

    @MainActor
    private func offerCurrentSwitchForLiveShowIfNeeded(now: Date = Date()) {
        guard let result = coordinator.pendingAcceptResult,
              let shows = try? modelContext.fetch(FetchDescriptor<Show>()),
              let target = shows.first(where: { $0.id == result.showID }),
              let selection = try? CurrentShowSelectionStore(modelContext: modelContext).canonicalSelection(),
              CompanionLiveCurrentPromptPolicy.shouldOffer(
                  importResult: result,
                  show: target,
                  selectedShowID: selection.selectedShowID,
                  now: now
              ) else {
            return
        }

        switchLiveShowToCurrent(showID: target.id)
    }

    private func switchLiveShowToCurrent(showID: UUID) {
        Task { @MainActor in
            do {
                let shows = try modelContext.fetch(FetchDescriptor<Show>())
                let selections = try modelContext.fetch(FetchDescriptor<CurrentShowSelection>())
                let notificationStates = try modelContext.fetch(FetchDescriptor<NotificationSchedulingState>())
                _ = try await ShowMutationCoordinator.selectCurrentShow(
                    showID: showID,
                    shows: shows,
                    selections: selections,
                    notificationStates: notificationStates,
                    in: modelContext
                )
            } catch {
                modelContext.rollback()
            }
        }
    }
}

private struct CompanionJoinConfirmationView: View {
    let session: CompanionSessionSnapshot?
    let isLoading: Bool
    let isWorking: Bool
    let onJoin: () -> Void
    let onClose: () -> Void
    @Query private var localShows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var myNickname: String = CompanionUserProfile.nickname ?? ""

    private var localMatch: CompanionLocalMatchResult {
        guard let session else { return .none }
        return CompanionAcceptedShowMapping.matchLocalShows(for: session, in: localShows)
    }

    private var isHistorical: Bool {
        guard let session else { return false }
        guard let show = try? CompanionAcceptedShowMapping.makeShow(from: session.show) else {
            return session.show.wasAddedAsHistorical == true
        }
        return show.wasAddedAsHistorical == true
            || CurrentShowTimeState(show: show).kind == .ended
    }

    private var ownerName: String {
        guard let session else { return BSLocalization.text("朋友") }
        let trimmed = session.ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return BSLocalization.text("朋友")
    }

    private var locationText: String? {
        guard let session else { return nil }
        let values = [session.show.venueName, session.show.city]
            .compactMap { value -> String? in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed?.isEmpty == false ? trimmed : nil
            }
        if !values.isEmpty { return values.joined(separator: " · ") }
        let legacy = session.show.showLocation?.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacy?.isEmpty == false ? legacy : nil
    }

    private var artistText: String? {
        guard let session else { return nil }
        let names = session.show.artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private var showTimeText: String {
        guard let session else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = session.show.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? session.show.timeZoneSecondsFromGMT.flatMap(TimeZone.init(secondsFromGMT:))
            ?? .current
        return formatter.string(from: session.show.showStartTime)
    }

    private var isLiveNow: Bool {
        guard let session,
              let show = try? CompanionAcceptedShowMapping.makeShow(from: session.show) else {
            return false
        }
        let state = CurrentShowTimeState(show: show)
        guard state.kind == .today,
              let start = state.effectiveStartTime,
              let end = state.endBoundary else {
            return false
        }
        let now = Date()
        return now >= start && now < end
    }

    private var hasOtherCurrentShow: Bool {
        guard isLiveNow,
              let activeID = selections.first?.selectedShowID else {
            return false
        }
        if case .single(let match) = localMatch, match.id == activeID {
            return false
        }
        return true
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    if let session {
                        readyContent(session: session)
                    } else {
                        loadingContent
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 36)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: session != nil)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
            if session != nil && !isLoading {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground)
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .disabled(isWorking)
                .padding(.top, 12)
                .padding(.trailing, 16)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var loadingContent: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                Text(BSLocalization.text("同行邀请"))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)

                Text(BSLocalization.text("正在加载同行邀请"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(BSColor.Stage.surface.opacity(0.35))
                        .aspectRatio(3.0 / 4.0, contentMode: .fit)

                    ProgressView()
                        .tint(BSColor.Stage.accent)
                        .scaleEffect(1.2)
                }

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(BSColor.Stage.surface.opacity(0.3))
                        .frame(height: 22)
                        .frame(maxWidth: 220)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(BSColor.Stage.surface.opacity(0.2))
                        .frame(height: 14)
                        .frame(maxWidth: 160)
                }
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    @ViewBuilder
    private func readyContent(session: CompanionSessionSnapshot) -> some View {
        header
        showCard(session: session)
        members(session: session)
        myNameSection
        action
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text(
                isHistorical
                    ? BSLocalization.text("一起去过这场吗？")
                    : BSLocalization.format("%@ 邀请你一起去", ownerName)
            )
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .foregroundStyle(BSColor.Stage.foreground)
            .multilineTextAlignment(.center)

            if isHistorical {
                Text(BSLocalization.format("%@ 邀请你确认这段共同足迹", ownerName))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func showCard(session: CompanionSessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            cover(session: session)

            VStack(alignment: .leading, spacing: 8) {
                if hasBadges {
                    HStack(spacing: 8) {
                        if case .single = localMatch {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                Text(BSLocalization.text("已在你的现场中"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(BSColor.Stage.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(BSColor.Stage.accent.opacity(0.14), in: Capsule())
                        } else if case .multiple(let candidates) = localMatch {
                            HStack(spacing: 4) {
                                Image(systemName: "rectangle.2.swap")
                                    .font(.system(size: 11, weight: .bold))
                                Text(BSLocalization.format("本地有 %d 场相似记录", candidates.count))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(BSColor.Stage.muted)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                        }

                        if isLiveNow {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(Color(red: 0.98, green: 0.35, blue: 0.35))
                                    .frame(width: 6, height: 6)
                                Text(BSLocalization.text("正在进行"))
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(BSColor.Stage.foreground)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }

                Text(session.show.showName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(BSColor.Stage.foreground)

                if let artistText {
                    Text(artistText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.accent)
                }

                Label(
                    showTimeText,
                    systemImage: "calendar"
                )
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BSColor.Stage.muted)

                if let locationText {
                    Label(locationText, systemImage: "mappin.and.ellipse")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var hasBadges: Bool {
        if case .none = localMatch {
            return isLiveNow
        }
        return true
    }

    private func cover(session: CompanionSessionSnapshot) -> some View {
        ShowCoverImageView(
            urlString: session.show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            cornerRadius: 18
        )
    }

    private func members(session: CompanionSessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(BSLocalization.text("同行"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.muted)

            HStack(spacing: 10) {
                member(ownerName)
                ForEach(CompanionNameList.normalized(session.participantDisplayNames), id: \.self) { name in
                    member(name)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var myNameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("我的称呼"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.muted)

            HStack(spacing: 10) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(BSColor.Stage.accent)
                TextField(BSLocalization.text("输入你的昵称"), text: $myNickname)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BSColor.Stage.foreground)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func member(_ name: String) -> some View {
        HStack(spacing: 7) {
            Text(String(name.prefix(1)))
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .foregroundStyle(BSColor.Stage.background)
                .background(BSColor.Stage.accent, in: Circle())
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
        }
        .padding(.trailing, 8)
    }

    private var actionButtonTitle: String {
        let historical = isHistorical
        switch localMatch {
        case .single:
            return historical
                ? BSLocalization.text("确认共同足迹")
                : BSLocalization.text("关联并成为同行")
        case .multiple, .none:
            return historical
                ? BSLocalization.text("确认一起去过")
                : BSLocalization.text("加入这场同行")
        }
    }

    private var actionNoticeText: String {
        let historical = isHistorical
        let owner = ownerName
        switch localMatch {
        case .single:
            return historical
                ? BSLocalization.format("检测到你已记录过这场演出，确认后将绑定与%@的共同足迹，不会创建重复现场。", owner)
                : BSLocalization.format("检测到你已记录过这场演出，确认后将直接绑定与%@的同行关系，不会创建重复现场。", owner)
        case .multiple:
            return BSLocalization.text("检测到你本地有多场相似记录，确认加入后可选择合并目标。")
        case .none:
            if historical {
                return BSLocalization.text("确认后，这场会进入你的足迹，并记录你们一起去过。")
            } else if hasOtherCurrentShow {
                return BSLocalization.text("这场正在进行中，加入后将设为你的当前现场。")
            } else {
                return BSLocalization.text("加入后可在现场页看到彼此状态，并共同记录足迹。")
            }
        }
    }

    private var action: some View {
        VStack(spacing: 12) {
            Text(actionNoticeText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BSColor.Stage.muted)
                .multilineTextAlignment(.center)

            Button {
                let trimmed = myNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    CompanionUserProfile.nickname = trimmed
                }
                onJoin()
            } label: {
                if isWorking {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(actionButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isWorking)
        }
    }
}
