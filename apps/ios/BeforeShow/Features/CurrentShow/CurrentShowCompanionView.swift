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
    /// Legacy semantic title retained for existing presentation tests/callers.
    let title: String
    /// Product-facing title used by the quick-action tile.
    let displayTitle: String
    let accessibilityLabel: String
    let companionName: String?
    let companionNames: [String]
    let showsPendingIndicator: Bool
    let displayShowsPendingIndicator: Bool
    let showsAvatars: Bool

    init(status: ShowCompanionStatus, companionName: String?, isEnded: Bool, isInvitationShared: Bool = true) {
        self.init(
            status: status,
            companionNames: CompanionNameList.normalized([companionName].compactMap { $0 }),
            isEnded: isEnded,
            isInvitationShared: isInvitationShared
        )
    }

    init(status: ShowCompanionStatus, companionNames: [String], isEnded: Bool, isInvitationShared: Bool = true) {
        let names = CompanionNameList.normalized(companionNames)
        let joined = CompanionNameList.joined(names)
        self.companionNames = names
        self.companionName = joined

        switch status {
        case .none:
            title = BSLocalization.text("同行")
            displayTitle = BSLocalization.text("添加同行")
            accessibilityLabel = BSLocalization.text("同行，邀请朋友")
            showsPendingIndicator = false
            displayShowsPendingIndicator = false
            showsAvatars = false
        case .pending:
            title = BSLocalization.text("待确认")
            if isInvitationShared {
                displayTitle = BSLocalization.text("等待同行")
                accessibilityLabel = BSLocalization.text("同行，等待朋友加入")
                showsPendingIndicator = true
            } else {
                displayTitle = BSLocalization.text("继续分享")
                accessibilityLabel = BSLocalization.text("同行，邀请链接已就绪")
                showsPendingIndicator = false
            }
            displayShowsPendingIndicator = false
            showsAvatars = false
        case .confirmed:
            let displayName = joined ?? BSLocalization.text("同行者")
            title = isEnded ? BSLocalization.text("共同足迹") : BSLocalization.format("与%@", displayName)
            if names.count == 1, let name = names.first {
                displayTitle = BSLocalization.format("与%@同行", name)
            } else if names.count > 1 {
                displayTitle = BSLocalization.format("%lld 人同行", Int64(names.count + 1))
            } else {
                displayTitle = BSLocalization.text("同行")
            }
            accessibilityLabel = isEnded
                ? (joined.map { BSLocalization.format("同行，与%@的共同足迹", $0) } ?? BSLocalization.text("同行，共同足迹"))
                : BSLocalization.format("同行，与%@已确认", displayName)
            showsPendingIndicator = false
            displayShowsPendingIndicator = false
            showsAvatars = true
        case .canceled:
            title = BSLocalization.text("重新邀请")
            displayTitle = BSLocalization.text("添加同行")
            accessibilityLabel = joined.map { BSLocalization.format("同行，重新邀请%@", $0) } ?? BSLocalization.text("同行，重新邀请")
            showsPendingIndicator = false
            displayShowsPendingIndicator = false
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
    @Query(sort: \Show.date) private var allShows: [Show]
    @State private var isShowingHistory = false
    @State private var isShowingShareSheet = false
    @State private var selectedPairName: String?
    @State private var isPreparingInvite = false
    @State private var errorMessage: String?
    @State private var currentUserName: String = BSLocalization.text("我")
    @State private var isEditingMyNickname = false
    @State private var editingMyNickname = ""
    @State private var editingMember: CompanionMember?
    @State private var editingCompanionName = ""
    @State private var isShowingRevokeConfirmation = false
    @State private var isShowingEndCompanionConfirmation = false
    @State private var isShowingLeaveCompanionConfirmation = false
    @State private var isCancelingCompanion = false

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
                    case .none, .canceled:
                        invitationContent
                    case .pending:
                        pendingInvitationContent
                    case .confirmed:
                        confirmedContent
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .sheet(isPresented: $isShowingShareSheet) {
            CompanionFootprintShareSheet(show: show, sharedHistory: sharedHistory)
        }
        .sheet(
            isPresented: Binding(
                get: { selectedPairName != nil },
                set: { if !$0 { selectedPairName = nil } }
            )
        ) {
            if let selectedPairName {
                NavigationStack {
                    CompanionPairFootprintView(
                        companionName: selectedPairName,
                        shows: CompanionPairHistory.shows(
                            with: selectedPairName,
                            from: allShows
                        )
                    )
                }
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
        .alert(BSLocalization.text("设置我的昵称"), isPresented: $isEditingMyNickname) {
            TextField(BSLocalization.text("输入你的昵称"), text: $editingMyNickname)
            Button(BSLocalization.text("取消"), role: .cancel) {}
            Button(BSLocalization.text("保存")) {
                let trimmed = editingMyNickname.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    CompanionUserProfile.nickname = trimmed
                    currentUserName = trimmed
                } else {
                    CompanionUserProfile.nickname = nil
                    currentUserName = BSLocalization.text("我")
                }
            }
        } message: {
            Text(BSLocalization.text("同行成员和邀请卡片将展示该昵称。"))
        }
        .alert(
            BSLocalization.text("修改同行人备注"),
            isPresented: Binding(
                get: { editingMember != nil },
                set: { if !$0 { editingMember = nil } }
            )
        ) {
            TextField(BSLocalization.text("备注名称"), text: $editingCompanionName)
            Button(BSLocalization.text("取消"), role: .cancel) { editingMember = nil }
            Button(BSLocalization.text("保存")) {
                guard let member = editingMember else { return }
                show.setCompanionAlias(editingCompanionName, for: member.id)
                try? modelContext.save()
                editingMember = nil
            }
        } message: {
            Text(BSLocalization.text("仅在本地修改该同行者的展示名称。"))
        }
        .alert(
            BSLocalization.text("撤销同行邀请？"),
            isPresented: $isShowingRevokeConfirmation
        ) {
            Button(BSLocalization.text("撤销邀请"), role: .destructive) {
                Task { await cancelCompanion() }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("撤销后，之前分享的邀请链接将失效。"))
        }
        .alert(
            BSLocalization.text("结束同行？"),
            isPresented: $isShowingEndCompanionConfirmation
        ) {
            Button(BSLocalization.text("结束同行"), role: .destructive) {
                Task { await cancelCompanion() }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("结束同行后，将解散本次同行记录，所有成员的同行状态都将被取消。"))
        }
        .alert(
            BSLocalization.text("退出同行？"),
            isPresented: $isShowingLeaveCompanionConfirmation
        ) {
            Button(BSLocalization.text("退出同行"), role: .destructive) {
                Task { await cancelCompanion() }
            }
            Button(BSLocalization.text("取消"), role: .cancel) {}
        } message: {
            Text(BSLocalization.text("退出后，你将不再参与这场现场的同行记录。"))
        }
        .task {
            if let name = await coordinator.fetchCurrentUserDisplayName() {
                currentUserName = name
            }
            guard show.companionCloudRecordName != nil else { return }
            await coordinator.refreshCompanion(for: show, in: modelContext)
            if let error = coordinator.consumeLastErrorMessage() {
                errorMessage = error
            }
        }
    }

    @MainActor
    private func cancelCompanion() async {
        guard !isCancelingCompanion else { return }
        isCancelingCompanion = true
        defer { isCancelingCompanion = false }
        do {
            try await coordinator.cancelCompanion(for: show, in: modelContext)
        } catch {
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    private var invitationContent: some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "person.2",
                title: BSLocalization.text("添加同行"),
                subtitle: BSLocalization.text("邀请朋友一起去这场现场。")
            )

            nicknameEditor

            Button {
                Task { await sendInvitation(isRetry: show.companionStatus == .canceled) }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text(inviteActionTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(inviteActionTitle, systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isPreparingInvite)
        }
    }

    private var pendingInvitationContent: some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "person.2",
                title: show.companionInvitationShared
                    ? BSLocalization.text("等待朋友加入")
                    : BSLocalization.text("邀请已就绪"),
                subtitle: show.companionInvitationShared
                    ? BSLocalization.text("朋友接受邀请后，会出现在这里。")
                    : BSLocalization.text("邀请链接已生成，分享给朋友即可加入。")
            )

            Button {
                Task { await sendInvitation(isRetry: false) }
            } label: {
                if isPreparingInvite {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.black)
                        Text(inviteActionTitle)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(inviteActionTitle, systemImage: "square.and.arrow.up")
                }
            }
            .buttonStyle(BSPrimaryButtonStyle())
            .disabled(isPreparingInvite || isCancelingCompanion)

            nicknameEditor

            Button {
                isShowingRevokeConfirmation = true
            } label: {
                if isCancelingCompanion {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(BSColor.Stage.danger)
                        Text(BSLocalization.text("正在撤销"))
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Text(BSLocalization.text("撤销邀请"))
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(BSDangerButtonStyle())
            .disabled(isPreparingInvite || isCancelingCompanion)
        }
    }

    private var nicknameEditor: some View {
        HStack(spacing: 8) {
            Text(BSLocalization.text("我的称呼"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BSColor.Stage.muted)
            Spacer()
            TextField(
                BSLocalization.text("输入你的昵称"),
                text: Binding(
                    get: { currentUserName == BSLocalization.text("我") ? "" : currentUserName },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            CompanionUserProfile.nickname = trimmed
                            currentUserName = trimmed
                        } else {
                            CompanionUserProfile.nickname = nil
                            currentUserName = BSLocalization.text("我")
                        }
                    }
                )
            )
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(BSColor.Stage.foreground)
            .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var confirmedContent: some View {
        VStack(spacing: BSSpacing.md) {
            BSStageSheetHeader(
                icon: "person.2.fill",
                title: companionTitle,
                subtitle: BSLocalization.text("这场现场已记录同行。")
            )

            companionMembers

            if isEnded {
                sharedMemoryCard

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
                    .buttonStyle(BSSecondaryButtonStyle())
                }

                Button {
                    isShowingShareSheet = true
                } label: {
                    Label(BSLocalization.text("分享共同足迹卡"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }

            if show.companionIsOwner != false {
                inviteMoreButton
            }

            if show.companionIsOwner ?? true {
                Button {
                    isShowingEndCompanionConfirmation = true
                } label: {
                    if isCancelingCompanion {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(BSColor.Stage.danger)
                            Text(BSLocalization.text("正在结束"))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(BSLocalization.text("结束同行"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(BSDangerButtonStyle())
                .disabled(isPreparingInvite || isCancelingCompanion)
            } else {
                Button {
                    isShowingLeaveCompanionConfirmation = true
                } label: {
                    if isCancelingCompanion {
                        HStack(spacing: 8) {
                            ProgressView()
                                .tint(BSColor.Stage.danger)
                            Text(BSLocalization.text("正在退出"))
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(BSLocalization.text("退出同行"))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(BSDangerButtonStyle())
                .disabled(isPreparingInvite || isCancelingCompanion)
            }
        }
    }

    private var inviteMoreButton: some View {
        Button {
            Task { await resendInvitation() }
        } label: {
            if isPreparingInvite {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(BSLocalization.text("邀请更多"))
                }
                .frame(maxWidth: .infinity)
            } else {
                Label(BSLocalization.text("邀请更多"), systemImage: "person.badge.plus")
            }
        }
        .buttonStyle(BSSecondaryButtonStyle())
        .disabled(isPreparingInvite || show.companionShareRecordName == nil || isCancelingCompanion)
    }

    private var companionMembersList: [CompanionMember] {
        if !show.companionMembers.isEmpty {
            return show.companionMembers
        }
        return show.companionNames.enumerated().map { idx, name in
            CompanionMember(id: "fallback-\(idx)", name: name)
        }
    }

    private var companionMembers: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpacing.md) {
                Button {
                    editingMyNickname = (currentUserName == BSLocalization.text("我")) ? "" : currentUserName
                    isEditingMyNickname = true
                } label: {
                    person(name: currentUserName, initial: BSLocalization.text("我"), isMe: true)
                }
                .buttonStyle(.plain)

                ForEach(companionMembersList) { member in
                    let name = member.displayName
                    if isEnded {
                        Button {
                            selectedPairName = name
                        } label: {
                            person(name: name, initial: String(name.prefix(1)), isMe: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingMember = member
                                editingCompanionName = member.alias ?? member.name
                            } label: {
                                Label(BSLocalization.text("修改备注"), systemImage: "pencil")
                            }
                        }
                        .accessibilityHint(BSLocalization.text("查看你们的共同足迹"))
                    } else {
                        Button {
                            editingMember = member
                            editingCompanionName = member.alias ?? member.name
                        } label: {
                            person(name: name, initial: String(name.prefix(1)), isMe: false)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingMember = member
                                editingCompanionName = member.alias ?? member.name
                            } label: {
                                Label(BSLocalization.text("修改备注"), systemImage: "pencil")
                            }
                        }
                    }
                }
            }
            .padding(.vertical, BSSpacing.sm)
        }
    }

    private func person(name: String, initial: String, isMe: Bool = false) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
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

                if isMe {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(BSColor.Stage.background)
                        .frame(width: 16, height: 16)
                        .background(BSColor.Stage.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(BSColor.Stage.surface, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
        }
    }

    private var sharedMemoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(BSLocalization.format("TOGETHER · %@", String(format: "%02d", sharedHistory.count)))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.accent)
            Text(
                BSLocalization.format(
                    "我们 %lld 人一起看过 %lld 场现场",
                    Int64(max(2, memberNames.count + 1)),
                    Int64(sharedHistory.count)
                )
            )
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
            Text(BSLocalization.text("共同足迹会从这里开始。"))
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

    private var memberNames: [String] {
        companionMembersList.map(\.displayName)
    }

    private var companionTitle: String {
        if memberNames.count == 1, let name = memberNames.first {
            return BSLocalization.format("与%@同行", name)
        }
        if memberNames.count > 1 {
            return BSLocalization.format("%lld 人同行", Int64(memberNames.count + 1))
        }
        return BSLocalization.text("同行")
    }

    private var inviteActionTitle: String {
        if isPreparingInvite {
            return BSLocalization.text("正在准备邀请")
        }
        if show.companionStatus == .pending {
            return show.companionInvitationShared
                ? BSLocalization.text("再次分享")
                : BSLocalization.text("继续分享")
        }
        return CompanionInvitePreparingPresentation.actionTitle(
            hasExistingShare: show.companionStatus == .pending
        )
    }

    @MainActor
    private func sendInvitation(isRetry: Bool, alreadyPreparing: Bool = false) async {
        if !alreadyPreparing {
            guard !isPreparingInvite else { return }
            isPreparingInvite = true
        }
        if isRetry, show.companionShareLocator != nil {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("正在重置上一份邀请，请稍候再试")
            return
        }
        if show.companionShareLocator != nil {
            await resendInvitation(alreadyPreparing: true)
            return
        }
        guard show.companionCloudRecordName == nil else {
            isPreparingInvite = false
            errorMessage = BSLocalization.text("这场现场已有正在进行的同行邀请，请稍候再试")
            return
        }
        await coordinator.refreshAllLinkedShows(in: modelContext, refreshLinks: false)
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
            let ownerName = currentUserName == BSLocalization.text("我") ? nil : currentUserName
            let coverImageTask = Task { await loadCoverImage(for: show.coverImageURL) }
            defer { coverImageTask.cancel() }
            let prepared = try await coordinator.prepareInvitation(
                for: show,
                preferredParticipantName: nil,
                ownerDisplayName: ownerName,
                in: modelContext
            )
            let coverImage = await coverImageTask.value
            presentPreparedShare(prepared.shareSystemFields, coverImage: coverImage)
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
            let coverImageTask = Task { await loadCoverImage(for: show.coverImageURL) }
            defer { coverImageTask.cancel() }
            let data = try await coordinator.shareSystemFieldsForResend(show: show)
            let coverImage = await coverImageTask.value
            presentPreparedShare(data, coverImage: coverImage)
        } catch let error as CompanionSharingError where error == .sessionNotFound {
            await sendInvitation(isRetry: true, alreadyPreparing: true)
        } catch {
            isPreparingInvite = false
            errorMessage = CompanionSharingCoordinator.userMessage(for: error)
        }
    }

    @MainActor
    private func loadCoverImage(for rawURL: String?) async -> UIImage? {
        guard let raw = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw) else {
            return nil
        }
        if url.isFileURL {
            if let data = try? Data(contentsOf: url), let image = UIImage(data: data) {
                return image
            }
        }
        return await ShowCoverImageCache.shared.image(from: url)
    }

    @MainActor
    private func presentPreparedShare(_ data: Data, coverImage: UIImage? = nil) {
        let presented = SystemCloudSharePresenter.present(
            shareData: data,
            show: CompanionShowSnapshot(show: show),
            containerIdentifier: CloudKitCompanionSharingService.defaultContainerIdentifier,
            coverImage: coverImage,
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
            onDismiss: { completed in
                isPreparingInvite = false
                if completed {
                    show.companionInvitationShared = true
                    try? modelContext.save()
                }
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
}
