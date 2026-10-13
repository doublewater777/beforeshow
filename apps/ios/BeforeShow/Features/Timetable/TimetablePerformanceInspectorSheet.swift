import SwiftData
import SwiftUI

/// Compact inspector sheet for inspecting, listening to,
/// switching stage, adjusting time, or deleting a single performance.
/// Changes are staged in local draft state and only committed to the stage
/// after the user taps "完成".
struct TimetablePerformanceInspectorSheet: View {
    let performance: TimetablePerformance
    let day: TimetableDay
    let avatarURL: URL?
    let linker: TimetableArtistLinker
    let timeZone: TimeZone
    let onDelete: () -> Void
    var onPerformanceChanged: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var draftArtistName: String
    @State private var draftAppleMusicArtistID: String?
    @State private var draftArtistAvatarURL: String?
    @State private var draftStageID: UUID?
    @State private var draftStartsAt: Date
    @State private var draftEndsAt: Date

    @State private var artistCandidates: [RecognizedArtist] = []
    @State private var isSearchingLoading = false
    @State private var searchFailure: ArtistSearchFailureMessage?
    @State private var searchAttempt = 0
    /// Set while the user replaces a link, so the exact-name match does not silently relink the same artist.
    @State private var isRelinking = false
    @State private var isConfirmingDelete = false
    @State private var saveErrorMessage: String? = nil
    @FocusState private var isNameFocused: Bool

    init(
        performance: TimetablePerformance,
        day: TimetableDay,
        avatarURL: URL?,
        linker: TimetableArtistLinker,
        timeZone: TimeZone,
        onPerformanceChanged: (() -> Void)? = nil,
        onDelete: @escaping () -> Void
    ) {
        self.performance = performance
        self.day = day
        self.avatarURL = avatarURL
        self.linker = linker
        self.timeZone = timeZone
        self.onPerformanceChanged = onPerformanceChanged
        self.onDelete = onDelete
        _draftArtistName = State(initialValue: performance.artistName)
        _draftAppleMusicArtistID = State(initialValue: performance.appleMusicArtistID)
        _draftArtistAvatarURL = State(initialValue: performance.artistAvatarURL)
        _draftStageID = State(initialValue: performance.stage?.id)
        _draftStartsAt = State(initialValue: performance.startsAt)
        _draftEndsAt = State(initialValue: performance.endsAt)
    }

    private var durationMinutes: Int {
        let seconds = draftEndsAt.timeIntervalSince(draftStartsAt)
        return max(0, Int((seconds / 60).rounded()))
    }

    private var isPlayingPreview: Bool {
        TimetablePreviewPlayer.shared.isPlaying(performanceID: performance.id)
    }

    private var isLoadingPreview: Bool {
        TimetablePreviewPlayer.shared.isLoading(performanceID: performance.id)
    }

    private var activeTrackTitle: String? {
        TimetablePreviewPlayer.shared.currentTrackTitle(for: performance.id)
    }

    private var currentAvatarURL: URL? {
        if let draftArtistAvatarURL, let url = URL(string: draftArtistAvatarURL) {
            return url
        }
        if ArtistNameMatching.normalized(draftArtistName) == ArtistNameMatching.normalized(performance.artistName) {
            return avatarURL
        }
        return nil
    }

    private var artistName: Binding<String> {
        Binding(
            get: { draftArtistName },
            set: { name in
                if ArtistNameMatching.normalized(name) != ArtistNameMatching.normalized(draftArtistName) {
                    draftAppleMusicArtistID = nil
                    draftArtistAvatarURL = nil
                }
                draftArtistName = name
            }
        )
    }

    private var needsArtistSearch: Bool {
        draftAppleMusicArtistID == nil
            && !draftArtistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && draftArtistName != BSLocalization.text("新演出")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let saveErrorMessage {
                        Text(saveErrorMessage)
                            .font(BSFont.caption)
                            .foregroundStyle(TimetableStyle.attention)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    header
                    stageSection
                    timeSection
                    deleteButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollContentBackground(.hidden)
            .task(id: "\(draftArtistName)|\(draftAppleMusicArtistID ?? "")|\(searchAttempt)") {
                await searchArtists()
            }
            .onChange(of: "\(draftArtistName)|\(draftAppleMusicArtistID ?? "")") { _, _ in
                if TimetablePreviewPlayer.shared.activePerformanceID == performance.id {
                    TimetablePreviewPlayer.shared.stop()
                }
            }
            .onDisappear {
                if TimetablePreviewPlayer.shared.activePerformanceID == performance.id {
                    TimetablePreviewPlayer.shared.stop()
                }
            }
            .navigationTitle(BSLocalization.text("演出详情"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .bsClearNavigationContainer()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: commitAndDismiss) {
                        Text(BSLocalization.text("完成"))
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TimetableStyle.mine)
                }
            }
            .alert(
                BSLocalization.text("删除此演出"),
                isPresented: $isConfirmingDelete
            ) {
                Button(BSLocalization.text("删除"), role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button(BSLocalization.text("取消"), role: .cancel) {}
            } message: {
                Text(BSLocalization.text("确定要从时刻表中移除这场演出吗？"))
            }
        }
    }

    // MARK: - Header (Artist, Avatar & Direct Preview)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TimetableArtistAvatar(name: draftArtistName, url: currentAvatarURL, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField(BSLocalization.text("艺人名称"), text: artistName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(TimetableStyle.foreground)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit {
                                isNameFocused = false
                            }

                        if !isNameFocused {
                            Image(systemName: "pencil")
                                .font(.system(size: 12))
                                .foregroundStyle(TimetableStyle.dim)
                        }
                    }

                    if let trackTitle = activeTrackTitle {
                        Label(BSLocalization.format("正在试听 · %@", trackTitle), systemImage: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TimetableStyle.mine)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if let id = draftAppleMusicArtistID, !id.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                isRelinking = true
                                draftAppleMusicArtistID = nil
                                draftArtistAvatarURL = nil
                            } label: {
                                Label(BSLocalization.text("断开 Apple Music 关联"), systemImage: "link.badge.plus")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                Text(BSLocalization.text("已关联 Apple Music"))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(TimetableStyle.mine)
                        }
                    } else {
                        Text(BSLocalization.text("未关联音乐库"))
                            .font(.system(size: 12))
                            .foregroundStyle(TimetableStyle.dim)
                    }
                }

                Spacer()

                Button {
                    TimetablePreviewPlayer.shared.toggle(
                        performanceID: performance.id,
                        artistName: draftArtistName,
                        artistID: draftAppleMusicArtistID
                    )
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPlayingPreview ? TimetableStyle.mine.opacity(0.25) : Color.white.opacity(0.12))
                            .frame(width: 40, height: 40)
                        if isLoadingPreview {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else if isPlayingPreview {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(TimetableStyle.mine)
                        } else {
                            Image(systemName: TimetablePreviewPlayer.shared.failedPerformanceID == performance.id ? "arrow.clockwise" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(BSLocalization.text(isPlayingPreview ? "暂停试听" : "试听"))
            }

            if TimetablePreviewPlayer.shared.failedPerformanceID == performance.id,
               let message = TimetablePreviewPlayer.shared.failureMessage {
                Text(BSLocalization.text(message))
                    .font(.system(size: 12))
                    .foregroundStyle(TimetableStyle.muted)
            }

            if needsArtistSearch {
                Divider()
                    .overlay(Color.white.opacity(0.08))

                ArtistSearchPicker(
                    options: artistCandidates,
                    isLoading: isSearchingLoading,
                    failure: searchFailure,
                    onRecovery: { searchAttempt += 1 },
                    onPick: connectArtist
                )
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(TimetableStyle.card)
        )
    }

    private func connectArtist(_ artist: RecognizedArtist) {
        draftArtistName = artist.canonicalName
        draftAppleMusicArtistID = artist.id
        draftArtistAvatarURL = artist.avatarURL?.absoluteString
        linker.rememberConnectedArtist(artist)
        isRelinking = false
        isNameFocused = false
    }

    private func searchArtists() async {
        artistCandidates = []
        searchFailure = nil
        isSearchingLoading = false
        guard needsArtistSearch else { return }
        let name = draftArtistName
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        artistCandidates = linker.savedCandidates(for: query)
        isSearchingLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let results = try await linker.candidates(for: query, includingRemote: true)
            try Task.checkCancellation()
            guard draftArtistName == name, draftAppleMusicArtistID == nil else { return }
            artistCandidates = results
            isSearchingLoading = false
            if !isRelinking, let match = ArtistNameMatching.uniqueExactMatch(for: query, among: results) {
                draftArtistName = match.canonicalName
                draftAppleMusicArtistID = match.id
                draftArtistAvatarURL = match.avatarURL?.absoluteString
                linker.rememberConnectedArtist(match)
            }
        } catch {
            guard !Task.isCancelled else { return }
            searchFailure = ArtistSearchFailureMessage(error: error)
            isSearchingLoading = false
        }
    }

    // MARK: - Stage Selector

    private var stageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("所属舞台"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TimetableStyle.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if day.orderedStages.count <= 3 {
                    HStack(spacing: 6) {
                        ForEach(day.orderedStages) { stage in
                            let isSelected = draftStageID == stage.id
                            let color = TimetableStageLight.color(stage.sortOrder)
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    draftStageID = stage.id
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    TimetableStageLight.marker(stage.sortOrder)
                                        .fill(color)
                                        .frame(width: 8, height: 8)
                                    Text(stage.name)
                                        .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(isSelected ? color.opacity(0.18) : Color.white.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(isSelected ? color.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                                .foregroundStyle(isSelected ? TimetableStyle.foreground : TimetableStyle.muted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(day.orderedStages) { stage in
                                let isSelected = draftStageID == stage.id
                                let color = TimetableStageLight.color(stage.sortOrder)
                                Button {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        draftStageID = stage.id
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        TimetableStageLight.marker(stage.sortOrder)
                                            .fill(color)
                                            .frame(width: 8, height: 8)
                                        Text(stage.name)
                                            .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(isSelected ? color.opacity(0.2) : Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(isSelected ? color.opacity(0.8) : Color.white.opacity(0.1), lineWidth: 1)
                                    )
                                    .foregroundStyle(isSelected ? TimetableStyle.foreground : TimetableStyle.muted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TimetableStyle.card)
            )
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("演出时段"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TimetableStyle.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                // Starts At Row
                HStack {
                    Label(BSLocalization.text("开始"), systemImage: "clock")
                        .font(.system(size: 15))
                        .foregroundStyle(TimetableStyle.foreground)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { draftStartsAt },
                        set: {
                            if $0 < draftEndsAt {
                                draftStartsAt = $0
                            }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, timeZone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .padding(.leading, 16)
                    .overlay(Color.white.opacity(0.06))

                // Ends At Row
                HStack {
                    Label(BSLocalization.text("结束"), systemImage: "clock.badge.checkmark")
                        .font(.system(size: 15))
                        .foregroundStyle(TimetableStyle.foreground)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { draftEndsAt },
                        set: {
                            if $0 > draftStartsAt {
                                draftEndsAt = $0
                            }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, timeZone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .padding(.leading, 16)
                    .overlay(Color.white.opacity(0.06))

                // Duration Row
                HStack {
                    Text(BSLocalization.text("总时长"))
                        .font(.system(size: 14))
                        .foregroundStyle(TimetableStyle.muted)

                    Text(BSLocalization.format("%d 分钟", durationMinutes))
                        .font(TimetableStyle.mono(14, weight: .semibold))
                        .foregroundStyle(TimetableStyle.mine)

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TimetableStyle.card)
            )
        }
    }

    // MARK: - Confirmation & Committing

    private func commitAndDismiss() {
        let trimmedName = draftArtistName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            saveErrorMessage = BSLocalization.text("请输入艺人名称")
            return
        }

        guard draftStartsAt < draftEndsAt else {
            saveErrorMessage = BSLocalization.text("保存失败，请检查演出时间")
            return
        }

        do {
            var didChange = false

            if performance.artistName != trimmedName
                || performance.appleMusicArtistID != draftAppleMusicArtistID
                || performance.artistAvatarURL != draftArtistAvatarURL
                || performance.startsAt != draftStartsAt
                || performance.endsAt != draftEndsAt {
                try performance.updateDetails(
                    artistName: trimmedName,
                    startsAt: draftStartsAt,
                    endsAt: draftEndsAt,
                    appleMusicArtistID: draftAppleMusicArtistID,
                    artistAvatarURL: draftArtistAvatarURL
                )
                didChange = true
            }

            if let draftStageID,
               draftStageID != performance.stage?.id,
               let targetStage = day.stages.first(where: { $0.id == draftStageID }) {
                performance.moveTo(stage: targetStage)
                didChange = true
            }

            if didChange {
                day.timetable?.show?.updatedAt = Date()
                try modelContext.save()
                onPerformanceChanged?()
            }

            saveErrorMessage = nil
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = BSLocalization.text("保存失败，请检查演出时间")
        }
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button(role: .destructive) {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                Text(BSLocalization.text("删除此演出"))
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(TimetableStyle.now)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TimetableStyle.card)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
}
