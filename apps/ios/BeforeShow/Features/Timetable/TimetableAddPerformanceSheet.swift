import SwiftData
import SwiftUI

/// Adds one performance to a timetable. Nothing is written until 添加 is tapped, so
/// closing or canceling the sheet leaves the timetable exactly as it was.
struct TimetableAddPerformanceSheet: View {
    let day: TimetableDay
    let linker: TimetableArtistLinker
    let avatarURL: ((TimetablePerformance) -> URL?)?
    let timeZone: TimeZone
    var onPerformanceAdded: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var artistName = ""
    @State private var stageID: UUID
    @State private var startsAt: Date
    @State private var endsAt: Date
    @State private var connectedArtist: RecognizedArtist?
    @State private var artistCandidates: [RecognizedArtist] = []
    @State private var isSearchingLoading = false
    @State private var searchFailure: ArtistSearchFailureMessage?
    @State private var searchAttempt = 0
    @State private var previewSessionID = UUID()
    @State private var saveErrorMessage: String? = nil
    /// 保存成功后 sheet 退场期间不能再次提交。
    @State private var hasCommitted = false
    @FocusState private var isNameFocused: Bool

    init(
        day: TimetableDay,
        stage: TimetableStage,
        start: Date,
        end: Date,
        linker: TimetableArtistLinker = TimetableArtistLinker(),
        avatarURL: ((TimetablePerformance) -> URL?)? = nil,
        timeZone: TimeZone,
        onPerformanceAdded: (() -> Void)? = nil
    ) {
        self.day = day
        self.linker = linker
        self.avatarURL = avatarURL
        self.timeZone = timeZone
        self.onPerformanceAdded = onPerformanceAdded
        _stageID = State(initialValue: stage.id)
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: end)
    }

    private var trimmedName: String { artistName.trimmingCharacters(in: .whitespacesAndNewlines) }
    /// An end earlier than or equal to the start means the set runs past midnight.
    private var resolvedEnd: Date { endsAt > startsAt ? endsAt : endsAt.addingTimeInterval(24 * 3600) }
    private var durationMinutes: Int {
        let seconds = resolvedEnd.timeIntervalSince(startsAt)
        return max(0, Int((seconds / 60).rounded()))
    }

    private var isPlayingPreview: Bool {
        TimetablePreviewPlayer.shared.isPlaying(performanceID: previewSessionID)
    }

    private var isLoadingPreview: Bool {
        TimetablePreviewPlayer.shared.isLoading(performanceID: previewSessionID)
    }

    private var activeTrackTitle: String? {
        TimetablePreviewPlayer.shared.currentTrackTitle(for: previewSessionID)
    }

    private var artistNameBinding: Binding<String> {
        Binding(
            get: { artistName },
            set: { name in
                if let current = connectedArtist,
                   ArtistNameMatching.normalized(name) != ArtistNameMatching.normalized(current.canonicalName) {
                    connectedArtist = nil
                }
                artistName = name
            }
        )
    }

    private var needsArtistSearch: Bool {
        connectedArtist == nil
            && !trimmedName.isEmpty
            && trimmedName != BSLocalization.text("新演出")
    }

    private var currentAvatarURL: URL? {
        if let url = connectedArtist?.avatarURL {
            return url
        }
        if let avatarURL, !trimmedName.isEmpty {
            let dummy = try? TimetablePerformance(
                artistName: trimmedName,
                startsAt: startsAt,
                endsAt: resolvedEnd,
                appleMusicArtistID: connectedArtist?.id,
                artistAvatarURL: connectedArtist?.avatarURL?.absoluteString
            )
            if let dummy {
                return avatarURL(dummy)
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    stageSection
                    timeSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .overlay(alignment: .top) {
                errorBanner
            }
            .task(id: "\(artistName)|\(connectedArtist?.id ?? "")|\(searchAttempt)") {
                await searchArtists()
            }
            .onChange(of: "\(artistName)|\(connectedArtist?.id ?? "")") { _, _ in
                if TimetablePreviewPlayer.shared.activePerformanceID == previewSessionID {
                    TimetablePreviewPlayer.shared.stop()
                }
            }
            .onDisappear {
                if TimetablePreviewPlayer.shared.activePerformanceID == previewSessionID {
                    TimetablePreviewPlayer.shared.stop()
                }
            }
            .navigationTitle(BSLocalization.text("添加演出"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .bsClearNavigationContainer()
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("取消")) {
                    dismiss()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: add) {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel(BSLocalization.text("添加"))
                    .foregroundStyle(TimetableStyle.foreground)
                    .disabled(trimmedName.isEmpty || hasCommitted)
                    .opacity(trimmedName.isEmpty ? 0.35 : 1)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            isNameFocused = true
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let saveErrorMessage {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TimetableStyle.attention)
                Text(saveErrorMessage)
                    .font(BSFont.caption.weight(.medium))
                    .foregroundStyle(TimetableStyle.foreground)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.96))
                    .shadow(color: Color.black.opacity(0.35), radius: 10, y: 4)
            )
            .overlay(
                Capsule()
                    .strokeBorder(TimetableStyle.attention.opacity(0.35), lineWidth: 1)
            )
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.saveErrorMessage = nil
                }
            }
            .task(id: saveErrorMessage) {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.saveErrorMessage = nil
                }
            }
        }
    }

    // MARK: - Header (Artist, Avatar & Direct Preview)

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TimetableArtistAvatar(name: trimmedName, url: currentAvatarURL, size: 52)

                VStack(alignment: .leading, spacing: 2) {
                    TextField(BSLocalization.text("艺人名称"), text: artistNameBinding)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TimetableStyle.foreground)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isNameFocused = false
                            if !trimmedName.isEmpty {
                                add()
                            }
                        }

                    if let trackTitle = activeTrackTitle {
                        Label(BSLocalization.format("正在试听 · %@", trackTitle), systemImage: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TimetableStyle.mine)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if let id = connectedArtist?.id, !id.isEmpty {
                        Label(BSLocalization.text("已关联 Apple Music"), systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TimetableStyle.mine)
                    }
                }

                Spacer()

                Button {
                    TimetablePreviewPlayer.shared.toggle(
                        performanceID: previewSessionID,
                        artistName: trimmedName,
                        artistID: connectedArtist?.id
                    )
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPlayingPreview ? TimetableStyle.mine.opacity(0.28) : Color.white.opacity(0.14))
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
                            Image(systemName: TimetablePreviewPlayer.shared.failedPerformanceID == previewSessionID ? "arrow.clockwise" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .offset(x: 1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(trimmedName.isEmpty)
                .opacity(trimmedName.isEmpty ? 0.35 : 1)
                .accessibilityLabel(BSLocalization.text(isPlayingPreview ? "暂停试听" : "试听"))
            }

            if TimetablePreviewPlayer.shared.failedPerformanceID == previewSessionID,
               let message = TimetablePreviewPlayer.shared.failureMessage {
                Text(BSLocalization.text(key: message))
                    .font(.system(size: 12))
                    .foregroundStyle(TimetableStyle.muted)
            }

            if needsArtistSearch {
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TimetableStyle.card)
        )
    }

    private func connectArtist(_ artist: RecognizedArtist) {
        connectedArtist = artist
        artistName = artist.canonicalName
        linker.rememberConnectedArtist(artist)
        isNameFocused = false
    }

    private func searchArtists() async {
        artistCandidates = []
        searchFailure = nil
        isSearchingLoading = false
        guard needsArtistSearch else { return }
        let name = artistName
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        artistCandidates = linker.savedCandidates(for: query)
        isSearchingLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let results = try await linker.candidates(for: query, includingRemote: true)
            try Task.checkCancellation()
            guard artistName == name, connectedArtist == nil else { return }
            artistCandidates = results
            isSearchingLoading = false
            if let match = ArtistNameMatching.uniqueExactMatch(for: query, among: results) {
                connectArtist(match)
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TimetableStyle.muted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(day.orderedStages) { stage in
                        let isSelected = stage.id == stageID
                        let color = TimetableStageLight.color(stage.sortOrder)
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                stageID = stage.id
                            }
                        } label: {
                            HStack(spacing: 6) {
                                TimetableStageLight.marker(stage.sortOrder)
                                    .fill(color)
                                    .frame(width: 8, height: 8)
                                Text(stage.name)
                                    .font(.system(size: 14, weight: isSelected ? .bold : .medium))
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
            }
        }
    }

    // MARK: - Time Section

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(BSLocalization.text("演出时段"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                Spacer()
                Text(BSLocalization.format("%d 分钟", durationMinutes))
                    .font(TimetableStyle.mono(13, weight: .medium))
                    .foregroundStyle(TimetableStyle.dim)
            }

            VStack(spacing: 0) {
                // Starts At Row
                HStack {
                    Label(BSLocalization.text("开始"), systemImage: "clock")
                        .font(.system(size: 15))
                        .foregroundStyle(TimetableStyle.foreground)
                    Spacer()
                    DatePicker("", selection: Binding(
                        get: { startsAt },
                        set: { newStart in
                            let duration = resolvedEnd.timeIntervalSince(startsAt)
                            startsAt = newStart
                            if endsAt <= newStart {
                                endsAt = newStart.addingTimeInterval(max(15 * 60, duration))
                            }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.timeZone, timeZone)
                }
                .padding(.vertical, 8)

                Divider()
                    .overlay(Color.white.opacity(0.08))

                // Ends At Row
                HStack {
                    Label(BSLocalization.text("结束"), systemImage: "clock.badge.checkmark")
                        .font(.system(size: 15))
                        .foregroundStyle(TimetableStyle.foreground)
                    Spacer()
                    DatePicker("", selection: $endsAt, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.timeZone, timeZone)
                }
                .padding(.vertical, 8)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TimetableStyle.card)
        )
    }

    private func add() {
        guard !hasCommitted else { return }
        guard !trimmedName.isEmpty else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                saveErrorMessage = BSLocalization.text("请输入艺人名称")
            }
            return
        }
        guard let stage = day.stages.first(where: { $0.id == stageID }) else { return }

        let end = resolvedEnd > startsAt ? resolvedEnd : startsAt.addingTimeInterval(45 * 60)
        guard startsAt < end else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                saveErrorMessage = BSLocalization.text("保存失败，请检查演出时间")
            }
            return
        }

        do {
            let performance = try TimetablePerformance(
                artistName: trimmedName,
                startsAt: startsAt,
                endsAt: end,
                appleMusicArtistID: connectedArtist?.id,
                artistAvatarURL: connectedArtist?.avatarURL?.absoluteString
            )
            modelContext.insert(performance)
            performance.stage = stage
            if let connectedArtist {
                linker.rememberConnectedArtist(connectedArtist)
            }
            day.timetable?.show?.updatedAt = Date()
            try modelContext.save()
            hasCommitted = true
            saveErrorMessage = nil
            onPerformanceAdded?()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            dismiss()
        } catch {
            modelContext.rollback()
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                saveErrorMessage = BSLocalization.text("保存失败，请检查演出时间")
            }
        }
    }
}
