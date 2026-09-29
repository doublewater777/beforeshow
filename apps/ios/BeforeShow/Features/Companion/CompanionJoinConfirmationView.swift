import SwiftData
import SwiftUI

struct CompanionPendingJoinPresentationState: Equatable {
    var isJoiningInBackground = false
    var isDismissedByUser = false

    func isPresented(isLoading: Bool, hasSession: Bool) -> Bool {
        (isLoading || hasSession)
            && !isJoiningInBackground
            && !isDismissedByUser
    }

    func canUserDismiss(
        isLoading: Bool,
        hasSession: Bool,
        isWorking: Bool,
        allowsLoadingDismiss: Bool
    ) -> Bool {
        guard !isWorking, !isJoiningInBackground else { return false }
        if hasSession && !isLoading { return true }
        return isLoading && allowsLoadingDismiss
    }

    mutating func inviteBecameActive() {
        isDismissedByUser = false
    }

    mutating func userDismissed() {
        isDismissedByUser = true
    }

    mutating func beginSuccessfulDismissal() {
        isJoiningInBackground = true
    }

    mutating func didDismiss() {
        isJoiningInBackground = false
    }
}

/// Product confirmation shown after iOS hands a CloudKit invitation to the app, but
/// before the companion relationship is committed and the Show is imported locally.
struct CompanionPendingJoinHost: View {
    let onJoinSuccess: (String) -> Void
    @Environment(\.modelContext) private var modelContext
    @Environment(CompanionSharingCoordinator.self) private var coordinator
    @State private var isWorking = false
    @State private var presentationState = CompanionPendingJoinPresentationState()
    @State private var queuedSuccessMessage: String?
    @State private var queuedCurrentSwitchShowID: UUID?
    @State private var pendingCurrentSwitchShowID: UUID?
    @State private var allowsLoadingDismiss = false
    @State private var errorMessage: String?

    private var isPresented: Bool {
        presentationState.isPresented(
            isLoading: coordinator.isLoadingInvitation,
            hasSession: coordinator.pendingJoinSession != nil
        )
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .fullScreenCover(
                isPresented: Binding(
                    get: { isPresented },
                    set: {
                        if !$0,
                           presentationState.canUserDismiss(
                               isLoading: coordinator.isLoadingInvitation,
                               hasSession: coordinator.pendingJoinSession != nil,
                               isWorking: isWorking,
                               allowsLoadingDismiss: allowsLoadingDismiss
                           ) {
                            handleClose()
                        }
                    }
                ),
                onDismiss: {
                    if let message = queuedSuccessMessage {
                        queuedSuccessMessage = nil
                        onJoinSuccess(message)
                    }
                    presentationState.didDismiss()
                    if let showID = queuedCurrentSwitchShowID {
                        queuedCurrentSwitchShowID = nil
                        pendingCurrentSwitchShowID = showID
                    }
                }
            ) {
                CompanionJoinConfirmationView(
                    session: coordinator.pendingJoinSession,
                    isLoading: coordinator.isLoadingInvitation && coordinator.pendingJoinSession == nil,
                    allowsLoadingDismiss: allowsLoadingDismiss,
                    isWorking: isWorking,
                    onJoin: { strategy in confirmJoin(importStrategy: strategy) },
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
            .onChange(of: coordinator.invitePresentationGeneration, initial: true) { _, _ in
                presentationState.inviteBecameActive()
            }
            .task(id: coordinator.invitePresentationGeneration) {
                allowsLoadingDismiss = false
                guard coordinator.isLoadingInvitation,
                      coordinator.pendingJoinSession == nil else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled,
                      coordinator.isLoadingInvitation,
                      coordinator.pendingJoinSession == nil else { return }
                allowsLoadingDismiss = true
            }
            .onChange(of: coordinator.pendingAcceptMessage, initial: true) { _, message in
                guard !isWorking,
                      let message, coordinator.pendingJoinSession == nil else { return }
                if presentationState.isDismissedByUser {
                    _ = coordinator.consumePendingAcceptMessage()
                    _ = coordinator.consumePendingAcceptResult()
                    return
                }
                onJoinSuccess(message)
                _ = coordinator.consumePendingAcceptMessage()
                _ = coordinator.consumePendingAcceptResult()
            }
            .onChange(of: coordinator.lastErrorMessage) { _, message in
                guard let message, coordinator.pendingJoinSession == nil else { return }
                if presentationState.isDismissedByUser {
                    _ = coordinator.consumeLastErrorMessage()
                    return
                }
                errorMessage = message
                _ = coordinator.consumeLastErrorMessage()
            }
            .confirmationDialog(
                BSLocalization.text("设为当前现场？"),
                isPresented: Binding(
                    get: { pendingCurrentSwitchShowID != nil },
                    set: { if !$0 { pendingCurrentSwitchShowID = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let showID = pendingCurrentSwitchShowID {
                    Button(BSLocalization.text("设为当前")) {
                        pendingCurrentSwitchShowID = nil
                        switchLiveShowToCurrent(showID: showID)
                    }
                }
                Button(BSLocalization.text("保留当前"), role: .cancel) {
                    pendingCurrentSwitchShowID = nil
                }
            }
    }

    private func handleClose() {
        presentationState.userDismissed()
        if coordinator.pendingJoinSession != nil {
            declineJoin()
        }
    }

    private func confirmJoin(importStrategy: CompanionAcceptedImportStrategy) {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await coordinator.confirmPendingJoin(
                in: modelContext,
                importStrategy: importStrategy
            )
            if succeeded {
                queueCurrentSwitchForLiveShowIfNeeded()
                if let message = coordinator.consumePendingAcceptMessage() {
                    queuedSuccessMessage = message
                }
                _ = coordinator.consumePendingAcceptResult()
                presentationState.beginSuccessfulDismissal()
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
    private func queueCurrentSwitchForLiveShowIfNeeded(now: Date = Date()) {
        guard let result = coordinator.pendingAcceptResult,
              let shows = try? modelContext.fetch(FetchDescriptor<Show>()),
              let target = shows.first(where: { $0.id == result.showID }) else {
            return
        }
        let selection: CurrentShowSelection?
        do {
            selection = try CurrentShowSelectionStore(modelContext: modelContext).canonicalSelection()
        } catch {
            return
        }
        let currentShowID = CurrentShowSession()
            .selectCurrentShow(from: shows, manualSelection: selection, now: now)?
            .id
        guard CompanionLiveCurrentPromptPolicy.shouldOffer(
            importResult: result,
            show: target,
            currentShowID: currentShowID,
            now: now
        ) else {
            return
        }

        queuedCurrentSwitchShowID = target.id
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

private enum CompanionDuplicateJoinChoice: Equatable {
    case merge(UUID)
    case keepSeparate
}

private struct CompanionJoinConfirmationView: View {
    let session: CompanionSessionSnapshot?
    let isLoading: Bool
    let allowsLoadingDismiss: Bool
    let isWorking: Bool
    let onJoin: (CompanionAcceptedImportStrategy) -> Void
    let onClose: () -> Void
    @Query private var localShows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @State private var myNickname: String = CompanionUserProfile.nickname ?? ""
    @State private var duplicateChoice: CompanionDuplicateJoinChoice?
    private let showFormatter = ShowDisplayFormatter()

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

    private var selectedImportStrategy: CompanionAcceptedImportStrategy {
        guard case .multiple = localMatch else { return .automatic }
        switch duplicateChoice {
        case .merge(let showID): return .mergeInto(showID)
        case .keepSeparate: return .keepSeparate
        case nil: return .automatic
        }
    }

    private var needsDuplicateChoice: Bool {
        if case .multiple = localMatch { return duplicateChoice == nil }
        return false
    }

    private var hasOtherCurrentShow: Bool {
        guard isLiveNow else { return false }
        let currentID = CurrentShowSession()
            .selectCurrentShow(from: localShows, manualSelection: selections.first)?
            .id
        guard let currentID else { return false }
        if case .single(let match) = localMatch, match.id == currentID {
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
            if (session != nil && !isLoading) || (isLoading && allowsLoadingDismiss) {
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
        .onChange(of: session?.sessionLocator.recordName) { _, _ in
            duplicateChoice = nil
        }
        .onChange(of: localShows.map(\.id)) { _, _ in
            if case .multiple = localMatch {
                duplicateChoice = nil
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
        if case .multiple(let candidates) = localMatch {
            duplicateSelection(candidates)
        }
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
                                Text(BSLocalization.text("已添加这场"))
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
            HStack(spacing: 6) {
                Text(BSLocalization.text("对方看到的名字"))
                    .font(.system(size: 13, weight: .semibold))
                Text(BSLocalization.text("可选"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BSColor.Stage.dim)
            }
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

    private func duplicateSelection(_ candidates: [Show]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.text("选择已有现场"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.muted)

            ForEach(candidates) { candidate in
                Button {
                    duplicateChoice = .merge(candidate.id)
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BSColor.Stage.foreground)
                                .lineLimit(2)
                            Text(showFormatter.dateText(for: candidate))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(BSColor.Stage.muted)
                            if let venue = candidate.venueName?.trimmingCharacters(in: .whitespacesAndNewlines),
                               !venue.isEmpty {
                                Text(venue)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(BSColor.Stage.dim)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: duplicateChoice == .merge(candidate.id) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(duplicateChoice == .merge(candidate.id) ? BSColor.Stage.accent : BSColor.Stage.muted)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Button {
                duplicateChoice = .keepSeparate
            } label: {
                HStack(spacing: 10) {
                    Text(BSLocalization.text("这是另一场，单独保留"))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                    Image(systemName: duplicateChoice == .keepSeparate ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                }
                .foregroundStyle(duplicateChoice == .keepSeparate ? BSColor.Stage.accent : BSColor.Stage.foreground)
                .padding(14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
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
        isHistorical
            ? BSLocalization.text("确认共同足迹")
            : BSLocalization.text("加入同行")
    }

    private var actionNoticeText: String {
        let historical = isHistorical
        let owner = ownerName
        switch localMatch {
        case .single:
            return historical
                ? BSLocalization.format("你已经记录过这场了。确认后会添加%@为共同足迹，不会重复添加。", owner)
                : BSLocalization.format("你已经有这场现场了。加入后会直接添加%@为同行，不会重复添加。", owner)
        case .multiple:
            return BSLocalization.text("看起来你已经添加过类似的现场。先选择要使用的记录，或把它作为另一场保留。")
        case .none:
            if historical {
                return BSLocalization.text("确认后，这场会进入你的足迹，并记录你们一起去过。")
            } else if hasOtherCurrentShow {
                return BSLocalization.text("这场正在进行中。加入后可选择是否设为当前现场。")
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
                onJoin(selectedImportStrategy)
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
            .disabled(isWorking || needsDuplicateChoice)
        }
    }
}
