import SwiftData
import SwiftUI

/// Product confirmation shown after iOS hands a CloudKit invitation to the app, but
/// before the companion relationship is committed and the Show is imported locally.
struct CompanionPendingJoinHost: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CompanionSharingCoordinator.self) private var coordinator
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var liveSwitchShowID: UUID?

    var body: some View {
        ZStack {
            if let session = coordinator.pendingJoinSession {
                CompanionJoinConfirmationView(
                    session: session,
                    isWorking: isWorking,
                    onJoin: { confirmJoin() },
                    onClose: { declineJoin() }
                )
                .transition(.opacity)
                .zIndex(1000)
                .alert(
                    BSLocalization.text("同行邀请"),
                    isPresented: Binding(
                        get: { errorMessage != nil },
                        set: { if !$0 { errorMessage = nil } }
                    )
                ) {
                    Button(BSLocalization.text("知道了"), role: .cancel) {
                        errorMessage = nil
                    }
                } message: {
                    Text(errorMessage ?? "")
                }
            }
        }
        .alert(
            BSLocalization.text("这场正在进行"),
            isPresented: Binding(
                get: { liveSwitchShowID != nil },
                set: { if !$0 { liveSwitchShowID = nil } }
            )
        ) {
            Button(BSLocalization.text("设为当前")) {
                switchLiveShowToCurrent()
            }
            Button(BSLocalization.text("暂不切换"), role: .cancel) {
                liveSwitchShowID = nil
            }
        } message: {
            Text(BSLocalization.text("是否把刚加入的这场设为当前现场？"))
        }
    }

    private func confirmJoin() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await coordinator.confirmPendingJoin(in: modelContext)
            if succeeded {
                offerCurrentSwitchForLiveShowIfNeeded()
            } else {
                errorMessage = coordinator.lastErrorMessage ?? BSLocalization.text("现场还没添加成功，请重试")
            }
            isWorking = false
        }
    }

    private func declineJoin() {
        guard !isWorking else { return }
        isWorking = true
        Task { @MainActor in
            let succeeded = await coordinator.declinePendingJoin()
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

        liveSwitchShowID = target.id
        // This confirmation owns the live-switch decision. Avoid also showing the
        // generic root acceptance alert underneath it.
        _ = coordinator.consumePendingAcceptMessage()
        _ = coordinator.consumePendingAcceptResult()
    }

    private func switchLiveShowToCurrent() {
        guard let showID = liveSwitchShowID, !isWorking else { return }
        isWorking = true
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
                liveSwitchShowID = nil
            } catch {
                modelContext.rollback()
                errorMessage = BSLocalization.text("切换失败，请重试")
            }
            isWorking = false
        }
    }
}

private struct CompanionJoinConfirmationView: View {
    let session: CompanionSessionSnapshot
    let isWorking: Bool
    let onJoin: () -> Void
    let onClose: () -> Void

    private var isHistorical: Bool {
        guard let show = try? CompanionAcceptedShowMapping.makeShow(from: session.show) else {
            return session.show.showStartTime < Date()
        }
        switch CurrentShowTimeState(show: show).kind {
        case .postShow, .ended:
            return true
        default:
            return false
        }
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

    var body: some View {
        ZStack {
            CurrentShowStageBackground().ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {
                    header
                    showCard
                    members
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
            Text(isHistorical ? BSLocalization.text("一起去过这场吗？") : BSLocalization.text("一起去这场吧"))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(
                isHistorical
                    ? BSLocalization.format("%@ 邀请你确认这段共同足迹", ownerName)
                    : BSLocalization.format("%@ 邀请你加入同行", ownerName)
            )
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(BSColor.Stage.muted)
            .multilineTextAlignment(.center)
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
                    session.show.showStartTime.formatted(date: .abbreviated, time: .shortened),
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

    @ViewBuilder
    private var cover: some View {
        if let raw = session.show.coverImageURL,
           let url = URL(string: raw) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                coverPlaceholder
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            coverPlaceholder
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [BSColor.Stage.accent.opacity(0.55), BSColor.Stage.glowBlue.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "music.note")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

            Button(action: onJoin) {
                if isWorking {
                    ProgressView()
                        .tint(.black)
                        .frame(maxWidth: .infinity)
                } else {
                    Text(isHistorical ? BSLocalization.text("确认一起去过") : BSLocalization.text("加入同行"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isWorking)
        }
    }
}
