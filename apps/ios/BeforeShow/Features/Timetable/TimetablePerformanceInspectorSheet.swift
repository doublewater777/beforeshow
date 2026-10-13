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
    /// Set while the user replaces a link, so the exact-name match does not silently relink the same artist.
    @State private var isRelinking = false
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
                VStack(spacing: 16) {
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
            .task(id: "\(performance.artistName)|\(performance.appleMusicArtistID ?? "")|\(searchAttempt)") {
                await searchArtists()
            }
            .onChange(of: "\(performance.artistName)|\(performance.appleMusicArtistID ?? "")") { _, _ in
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
                ToolbarItem(placement: .confirmationAction) {
                    Button(BSLocalization.text("完成")) {
                        dismiss()
                    }
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
                TimetableArtistAvatar(name: performance.artistName, url: avatarURL, size: 52)

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
                                try? modelContext.save()
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
                    } else if let id = performance.appleMusicArtistID, !id.isEmpty {
                        Menu {
                            Button(role: .destructive) {
                                isRelinking = true
                                performance.disconnectArtist()
                                try? modelContext.save()
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
                        artistName: performance.artistName,
                        artistID: performance.appleMusicArtistID
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
        performance.connectArtist(artist)
        linker.rememberConnectedArtist(artist)
        isRelinking = false
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
            if !isRelinking, let match = ArtistNameMatching.uniqueExactMatch(for: query, among: results) {
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
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TimetableStyle.muted)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                if day.orderedStages.count <= 3 {
                    HStack(spacing: 6) {
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
                    .environment(\.timeZone, timeZone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
                    .padding(.leading, 16)
                    .overlay(Color.white.opacity(0.06))

                // Duration & Shifting Row
                HStack {
                    Text(BSLocalization.text("总时长"))
                        .font(.system(size: 14))
                        .foregroundStyle(TimetableStyle.muted)

                    Text(BSLocalization.format("%d 分钟", durationMinutes))
                        .font(TimetableStyle.mono(14, weight: .semibold))
                        .foregroundStyle(TimetableStyle.mine)

                    Spacer()

                    HStack(spacing: 6) {
                        shiftButton(minutes: -10)
                        shiftButton(minutes: 10)
                    }
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

    private func shiftButton(minutes: Int) -> some View {
        Button {
            withAnimation(.snappy) {
                performance.shiftTimes(by: TimeInterval(minutes * 60))
                try? modelContext.save()
            }
        } label: {
            Text("\(minutes > 0 ? "+" : "")\(minutes)m")
                .font(TimetableStyle.mono(12, weight: .semibold))
                .foregroundStyle(TimetableStyle.foreground)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
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
