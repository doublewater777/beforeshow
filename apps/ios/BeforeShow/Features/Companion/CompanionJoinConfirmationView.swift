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
    @State private var hasDismissedConfirmation = true
    @State private var queuedSuccessMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            if coordinator.isLoadingInvitation && !isJoiningInBackground {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    HStack(spacing: BSSpacing.sm) {
                        ProgressView()
                            .tint(BSColor.Stage.accent)
                        Text(BSLocalization.text("正在加载同行邀请"))
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(BSColor.Stage.foreground)
                    }
                    .padding(.horizontal, BSSpacing.lg)
                    .padding(.vertical, BSSpacing.md)
                    .background(BSColor.Stage.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: BSRadius.md))
                }
                .transition(.opacity)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { coordinator.pendingJoinSession != nil && !isJoiningInBackground },
                set: { if !$0 && !isWorking && !isJoiningInBackground { declineJoin() } }
            ),
            onDismiss: {
                hasDismissedConfirmation = true
                if let message = queuedSuccessMessage {
                    queuedSuccessMessage = nil
                    onJoinSuccess(message)
                }
            }
        ) {
            if let session = coordinator.pendingJoinSession {
                CompanionJoinConfirmationView(
                    session: session,
                    isWorking: isWorking,
                    onJoin: { confirmJoin() },
                    onClose: { declineJoin() }
                )
                .interactiveDismissDisabled()
            }
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
        .onChange(of: coordinator.pendingAcceptMessage, initial: true) { _, message in
            guard !isWorking, !isJoiningInBackground,
                  let message, coordinator.pendingAcceptResult != nil else { return }
            onJoinSuccess(message)
            _ = coordinator.consumePendingAcceptMessage()
            _ = coordinator.consumePendingAcceptResult()
        }
    }

    private func confirmJoin() {
        guard !isWorking else { return }
        isWorking = true
        hasDismissedConfirmation = false
        isJoiningInBackground = true
        Task { @MainActor in
            let succeeded = await coordinator.confirmPendingJoin(in: modelContext)
            if succeeded {
                offerCurrentSwitchForLiveShowIfNeeded()
                if let message = coordinator.consumePendingAcceptMessage() {
                    if hasDismissedConfirmation {
                        onJoinSuccess(message)
                    } else {
                        queuedSuccessMessage = message
                    }
                }
                _ = coordinator.consumePendingAcceptResult()
            } else {
                errorMessage = coordinator.consumeLastErrorMessage() ?? BSLocalization.text("现场还没添加成功，请重试")
            }
            isJoiningInBackground = false
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
    let session: CompanionSessionSnapshot
    let isWorking: Bool
    let onJoin: () -> Void
    let onClose: () -> Void
    @State private var myNickname: String = CompanionUserProfile.nickname ?? ""

    private var isHistorical: Bool {
        guard let show = try? CompanionAcceptedShowMapping.makeShow(from: session.show) else {
            return session.show.wasAddedAsHistorical == true
        }
        return show.wasAddedAsHistorical == true
            || CurrentShowTimeState(show: show).kind == .ended
    }

    private var ownerName: String {
        let trimmed = session.ownerDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return BSLocalization.text("朋友")
    }

    private var locationText: String? {
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
        let names = session.show.artists.map(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " · ")
    }

    private var showTimeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = session.show.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? session.show.timeZoneSecondsFromGMT.flatMap(TimeZone.init(secondsFromGMT:))
            ?? .current
        return formatter.string(from: session.show.showStartTime)
    }

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    showCard
                    members
                    myNameSection
                    action
                }
                .padding(.horizontal, 22)
                .padding(.top, 54)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topTrailing) {
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
            .accessibilityLabel(BSLocalization.text("暂不加入"))
        }
        .preferredColorScheme(.dark)
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

    private var showCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            cover

            VStack(alignment: .leading, spacing: 8) {
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

    private var cover: some View {
        ShowCoverImageView(
            urlString: session.show.coverImageURL,
            aspectRatio: 3.0 / 4.0,
            contentMode: .fill,
            cornerRadius: 18
        )
    }

    private var members: some View {
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

    private var action: some View {
        VStack(spacing: 12) {
            Text(
                isHistorical
                    ? BSLocalization.text("确认后，这场会进入你的足迹，并记录你们一起去过。")
                    : BSLocalization.text("加入后，这场会添加到你的现场，并记录你们同行。")
            )
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
                    Text(isHistorical ? BSLocalization.text("确认一起去过") : BSLocalization.text("加入这场同行"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isWorking)
        }
    }
}
