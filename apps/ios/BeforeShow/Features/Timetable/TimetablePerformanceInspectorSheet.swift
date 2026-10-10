import SwiftData
import SwiftUI

/// Compact inspector sheet for inspecting, listening to,
/// shifting time, switching stage, or deleting a single performance.
struct TimetablePerformanceInspectorSheet: View {
    @Bindable var performance: TimetablePerformance
    let day: TimetableDay
    let avatarURL: URL?
    let linker: TimetableArtistLinker
    let timeZone: TimeZone
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var artistCandidates: [RecognizedArtist] = []
    @State private var isSearchingLoading = false
    @State private var searchFailure: ArtistSearchFailureMessage?
    @State private var searchAttempt = 0
    @State private var isConfirmingDelete = false
    @FocusState private var isNameFocused: Bool

    private var durationMinutes: Int {
        let seconds = performance.endsAt.timeIntervalSince(performance.startsAt)
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

    private var artistName: Binding<String> {
        Binding(
            get: { performance.artistName },
            set: { name in
                if ArtistNameMatching.normalized(name) != ArtistNameMatching.normalized(performance.artistName) {
                    performance.disconnectArtist()
                }
                performance.artistName = name
            }
        )
    }

    private var needsArtistSearch: Bool {
        performance.appleMusicArtistID == nil
            && !performance.artistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && performance.artistName != BSLocalization.text("新演出")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    stageSection
                    timeSection
                    deleteButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
            .task(id: "\(performance.artistName)|\(performance.appleMusicArtistID ?? "")|\(searchAttempt)") {
                await searchArtists()
            }
            .onChange(of: "\(performance.artistName)|\(performance.appleMusicArtistID ?? "")") { _, _ in
                if TimetablePreviewPlayer.shared.activePerformanceID == performance.id {
                    TimetablePreviewPlayer.shared.stop()
                }
            }
            .navigationTitle(BSLocalization.text("演出检视"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .bsClearNavigationContainer()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(BSLocalization.text("完成")) {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(TimetableStyle.foreground)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                TimetableArtistAvatar(name: performance.artistName, url: avatarURL, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    TextField(BSLocalization.text("艺人名称"), text: artistName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(TimetableStyle.foreground)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isNameFocused = false
                            try? modelContext.save()
                        }

                    if let trackTitle = activeTrackTitle {
                        Label(BSLocalization.format("正在试听 · %@", trackTitle), systemImage: "music.note")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(TimetableStyle.mine)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else if let id = performance.appleMusicArtistID, !id.isEmpty {
                        Label(BSLocalization.text("已关联 Apple Music"), systemImage: "checkmark.seal.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(TimetableStyle.mine)
                    }
                }

                Spacer()

                Button {
                    TimetablePreviewPlayer.shared.toggle(
                        performanceID: performance.id,
                        artistName: performance.artistName,
                        artistID: performance.appleMusicArtistID
                    )
                } label: {
                    ZStack {
                        Circle()
                            .fill(isPlayingPreview ? TimetableStyle.mine.opacity(0.28) : Color.white.opacity(0.12))
                            .frame(width: 34, height: 34)
                        if isLoadingPreview {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else if isPlayingPreview {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(TimetableStyle.mine)
                        } else {
                            Image(systemName: TimetablePreviewPlayer.shared.failedPerformanceID == performance.id ? "arrow.clockwise" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
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
        performance.connectArtist(artist)
        linker.rememberConnectedArtist(artist)
        isNameFocused = false
        try? modelContext.save()
    }

    private func searchArtists() async {
        artistCandidates = []
        searchFailure = nil
        isSearchingLoading = false
        guard needsArtistSearch else { return }
        let name = performance.artistName
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        artistCandidates = linker.savedCandidates(for: query)
        isSearchingLoading = true
        do {
            try await Task.sleep(for: .milliseconds(350))
            let results = try await linker.candidates(for: query, includingRemote: true)
            try Task.checkCancellation()
            guard performance.artistName == name, performance.appleMusicArtistID == nil else { return }
            artistCandidates = results
            isSearchingLoading = false
            if let match = ArtistNameMatching.uniqueExactMatch(for: query, among: results) {
                performance.connectArtist(match)
                linker.rememberConnectedArtist(match)
            }
            try? modelContext.save()
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
                        let isSelected = performance.stage?.id == stage.id
                        let color = TimetableStageLight.color(stage.sortOrder)
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                performance.moveTo(stage: stage)
                                try? modelContext.save()
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(BSLocalization.text("演出时段"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TimetableStyle.muted)
                Spacer()
                Text(BSLocalization.format("%d 分钟", durationMinutes))
                    .font(TimetableStyle.mono(13))
                    .foregroundStyle(TimetableStyle.dim)
            }

            // Quick shift buttons
            HStack(spacing: 8) {
                ForEach([-15, -5, 5, 15], id: \.self) { minutes in
                    Button {
                        withAnimation(.snappy) {
                            performance.shiftTimes(by: TimeInterval(minutes * 60))
                            try? modelContext.save()
                        }
                    } label: {
                        Text("\(minutes > 0 ? "+" : "")\(minutes)分")
                            .font(TimetableStyle.mono(13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
                            .foregroundStyle(TimetableStyle.foreground)
                    }
                    .buttonStyle(TimetablePressStyle())
                }
            }

            // Pickers
            HStack {
                HStack(spacing: 8) {
                    Text(BSLocalization.text("开始"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TimetableStyle.muted)
                    DatePicker("", selection: Binding(
                        get: { performance.startsAt },
                        set: {
                            if $0 < performance.endsAt {
                                performance.startsAt = $0
                                try? modelContext.save()
                            }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.timeZone, timeZone)
                }

                Spacer()

                HStack(spacing: 8) {
                    Text(BSLocalization.text("结束"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TimetableStyle.muted)
                    DatePicker("", selection: Binding(
                        get: { performance.endsAt },
                        set: {
                            if $0 > performance.startsAt {
                                performance.endsAt = $0
                                try? modelContext.save()
                            }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.timeZone, timeZone)
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TimetableStyle.card)
        )
    }

    // MARK: - Delete

    private var deleteButton: some View {
        Button {
            isConfirmingDelete = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "trash")
                Text(BSLocalization.text("删除此演出"))
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(TimetableStyle.now)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(TimetableStyle.now.opacity(0.12)))
        }
        .buttonStyle(TimetablePressStyle())
        .padding(.top, 4)
    }
}
