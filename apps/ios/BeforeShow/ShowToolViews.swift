import AVFoundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import WebKit

private final class PhotoLibrarySaveDelegate: NSObject, @unchecked Sendable {
    let completion: (Error?) -> Void

    init(completion: @escaping (Error?) -> Void) {
        self.completion = completion
    }

    @objc func image(
        _ image: UIImage,
        didFinishSavingWithError error: Error?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        completion(error)
    }
}

struct CurrentAllToolsRow: View {
    let summary: String

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Text("全部工具")
                .font(BSFont.headline)
                .foregroundColor(BSColor.textSecondary)

            Spacer(minLength: BSSpacing.sm)

            Text(summary)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

private struct BSTipPromptCard: View {
    let iconName: String
    let eyebrow: String
    let message: String
    var accent: Color = BSColor.Accent.music
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.22))
                    .frame(width: 38, height: 38)
                    .blur(radius: 12)

                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundColor(BSColor.textTertiary)
                    .textCase(.uppercase)

                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BSColor.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.88))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(BSColor.brandGradientSoft))
                    .clipShape(Capsule())
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
        )
    }
}

struct CurrentShowAllToolsView: View {
    let show: Show

    /// 打开时固定方向；nil 表示 sheet 关闭。
    @State private var travelSheetDirection: RoundTripDirection?

    private let columns = [
        GridItem(.flexible(), spacing: BSSpacing.md),
        GridItem(.flexible(), spacing: BSSpacing.md)
    ]

    var body: some View {
        ZStack {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text("全部工具")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(BSColor.textPrimary)
                        Text("围绕这场现场，你可以做的准备和记录。")
                            .font(BSFont.body)
                            .foregroundColor(BSColor.textTertiary)
                    }

                    LazyVGrid(columns: columns, spacing: BSSpacing.md) {
                        Button {
                            travelSheetDirection = RoundTripPlanDirectionResolver.resolve(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "tram.fill",
                                title: "怎么去",
                                subtitle: "怎么去、几点到",
                                accent: BSColor.Accent.travel
                            )
                        }

                        NavigationLink {
                            // Empty single-artist catalog auto-generates inside the sheet.
                            CandidateSongsView(show: show, launch: .generate)
                        } label: {
                            CurrentToolTile(
                                iconName: "mic.fill",
                                title: "歌单猜想",
                                subtitle: "猜本场可能会唱什么",
                                accent: BSColor.Accent.candidate
                            )
                        }

                        NavigationLink {
                            ShowPreparationView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "sparkles",
                                title: "现场准备",
                                subtitle: "准备事项和提醒",
                                accent: BSColor.Accent.prepare
                            )
                        }

                        NavigationLink {
                            ShowFragmentListView(show: show)
                        } label: {
                            CurrentToolTile(
                                iconName: "sparkles.rectangle.stack",
                                title: "现场碎片",
                                subtitle: "照片、视频和语音",
                                accent: BSColor.Accent.fragment
                            )
                        }
                    }
                    .buttonStyle(.plain)

                    Text("这些工具都围绕当前现场展开")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary.opacity(0.74))
                        .frame(maxWidth: .infinity)
                        .padding(.top, BSSpacing.lg)
                }
                .padding(BSSpacing.md)
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollIndicators(.hidden)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $travelSheetDirection) { direction in
            RoundTripPlanView(show: show, direction: direction)
                .presentationDragIndicator(.hidden)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(BSRadius.sheet)
                .presentationBackground(BSColor.Stage.surfaceRaised)
        }
    }
}

private struct CurrentToolTile: View {
    let iconName: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Image(systemName: iconName)
                .font(.system(size: 19, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.13))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

            Text(title)
                .font(BSFont.headline)
                .foregroundColor(BSColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(subtitle)
                .font(BSFont.caption)
                .foregroundColor(BSColor.textTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

enum SetlistSheetLaunch: Equatable {
    case browse
    /// Open sheet and immediately run 歌单生成 (prototype card CTA / 生成歌单 chip).
    case generate
    case edit
    case share

    /// Whether opening an empty catalog should start generation without a second tap.
    /// Single-artist (concert / livehouse): yes for browse/generate.
    /// Festival: only when launch is `.generate` (then lineup pick first).
    static func shouldAutoStartEmptyGeneration(
        launch: SetlistSheetLaunch,
        isFestival: Bool,
        catalogIsEmpty: Bool,
        didAutoGenerate: Bool
    ) -> Bool {
        guard catalogIsEmpty, !didAutoGenerate else { return false }
        if isFestival {
            return launch == .generate
        }
        switch launch {
        case .browse, .generate:
            return true
        case .edit, .share:
            return false
        }
    }
}

/// 歌单猜想 sheet（浏览 + 就地编辑 + 生成/重生成）。
struct CandidateSongsView: View {
    let show: Show
    var launch: SetlistSheetLaunch = .browse

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var candidateGroups: [CandidateSongGroup]
    @Query private var candidateSongs: [CandidateSong]
    @Query private var artistInterests: [ArtistInterestItem]
    @AppStorage(ProEntitlementStorage.appStorageKey) private var entitlementRawValue = ""
    @AppStorage(ProUsageStorage.usedFreeGenerationFeaturesKey) private var usedFreeGenerationFeaturesRawValue = ""

    @State private var isGenerating = false
    @State private var lastGenerationFailed = false
    @State private var showsReplacementConfirmation = false
    @State private var showsProLimit = false
    @State private var showsProMembership = false
    @State private var isEditingSetlist = false
    @State private var didApplyLaunch = false
    @State private var showsLineupEdit = false
    @State private var showsLineupRegenConfirm = false
    @State private var showsSetlistShareSheet = false
    @State private var showsSongAddSheet = false
    @State private var songPendingRemoval: CandidateSong?
    @State private var toast: BSToastPayload?
    @State private var genStatusIndex = 0
    @State private var revealNewList = false
    @State private var didAutoGenerate = false
    /// Multi-artist first generate: pick artists (default all on).
    @State private var isPickingLineupForGenerate = false
    @State private var lineupPickSelection: Set<UUID> = []
    /// Snapshot for pick UI (avoids @Query lag right after seed/add).
    @State private var lineupPickArtists: [ArtistInterestItem] = []
    @State private var lineupAddName = ""
    /// Setlist sheet stays large by default (add / lineup / empty / filled).
    @State private var sheetDetent: PresentationDetent = .large
    /// Custom long-press reorder (not system onDrag — that left a stuck lift visual after drop).
    @State private var setlistDrag: SetlistManualDragState?
    @State private var photoSaveDelegate: PhotoLibrarySaveDelegate?
    @State private var isSavingShareImage = false
    /// Sole in-flight generation task; cancelled on dismiss or when starting a new one.
    @State private var generationTask: Task<Void, Never>?
    @State private var generationRunID: UUID?

    private let gate = ProFeatureGate()
    private var session: CandidateSongsSession { CandidateSongsSession(show: show) }
    private var isFestival: Bool { show.type == .musicFestival }

    /// Festival first generate always goes through lineup pick (seed from 艺人/阵容 first).
    private var needsLineupPickBeforeGenerate: Bool {
        isFestival
    }

    private var orderedLineupArtists: [ArtistInterestItem] {
        showArtistInterests.sorted { $0.order < $1.order }
    }

    private var isEmptyCatalog: Bool {
        allSongs.isEmpty
    }

    private var sheetDetents: Set<PresentationDetent> {
        [.large]
    }

    private var showGroups: [CandidateSongGroup] {
        candidateGroups.filter { $0.showID == show.id }
    }

    private var showArtistInterests: [ArtistInterestItem] {
        artistInterests.filter { $0.showID == show.id }
    }

    private var allSongs: [CandidateSong] {
        session.orderedSongs(groups: showGroups, songs: candidateSongs)
    }

    private var artistNames: [String] {
        session.artistNames(in: allSongs)
    }

    private var isMultiArtist: Bool { artistNames.count > 1 }

    private var fallbackArtistName: String {
        session.fallbackArtistName(showArtist: show.artist, songArtists: artistNames)
    }

    private var addSongArtistOptions: [String] {
        let options = showArtistInterests
            .filter { $0.status != .notInterested }
            .sorted { $0.order < $1.order }
            .map(\.artistName)
        return options.isEmpty ? artistNames : options
    }

    private var entitlement: ProEntitlementState {
        ProEntitlementStorage.decode(entitlementRawValue)
    }

    private var canGenerate: Bool {
        gate.canGenerate(
            feature: .candidateSongs,
            hasUsedFreeAllowance: ProUsageStorage
                .decodeUsedFreeGenerationFeatures(usedFreeGenerationFeaturesRawValue)
                .contains(.candidateSongs),
            entitlement: entitlement
        )
    }

    private var shareHeadline: String {
        session.shareHeadline(showName: show.name, artistFilter: nil)
    }

    private var sheetNote: String {
        // Prototype setlistSheetNoteText: show · city · (artists) · 按本场信息猜测
        let artist = show.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = [show.name]
        if !city.isEmpty { parts.append(city) }
        if isFestival {
            let n = showArtistInterests.filter { $0.status != .notInterested }.count
            if n > 0 { parts.append("\(n) 组艺人") }
        } else if !artist.isEmpty {
            parts.insert(artist, at: 0)
        }
        parts.append("按本场信息猜测")
        return parts.joined(separator: " · ")
    }

    private var genStatusLines: [String] {
        let city = show.city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let place = city.isEmpty ? show.name : city
        if isFestival {
            let n = max(1, showArtistInterests.filter { $0.status != .notInterested }.count)
            return [
                "正在读取 \(show.name) · \(place)（\(n) 组艺人）…",
                "比对各艺人近期现场…",
                "按阵容生成歌单猜想…"
            ]
        }
        let guestHint = artistNames.count > 1 || !(show.artist?.isEmpty ?? true) ? "（含嘉宾）" : ""
        return [
            "正在读取 \(show.name) · \(place)\(guestHint)…",
            "比对本轮巡演近期场次…",
            "生成歌单猜想…"
        ]
    }

    /// Festival sheet: group rows by artist with prototype headers (mrnv1rxl multi-artist).
    private var sheetListSections: [(artist: String?, songs: [(offset: Int, song: CandidateSong)])] {
        // Group whenever multi-artist catalog (festival or multi-name list).
        guard isMultiArtist else {
            return [(nil, allSongs.enumerated().map { ($0.offset, $0.element) })]
        }
        var sections: [(artist: String, songs: [(offset: Int, song: CandidateSong)])] = []
        for (index, song) in allSongs.enumerated() {
            if sections.last?.artist != song.artist {
                sections.append((artist: song.artist, songs: []))
            }
            sections[sections.count - 1].songs.append((offset: index, song: song))
        }
        return sections.map { (artist: $0.artist, songs: $0.songs) }
    }

    var body: some View {
        // Prototype setlist-sheet: head → gen-status → scroll list → sticky foot
        ZStack {
            LinearGradient(
                colors: [
                    SetlistProto.surfaceRaised.opacity(0.98),
                    SetlistProto.surface
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                SetlistProtoSheetHeader(
                    title: sheetHeaderTitle,
                    note: sheetHeaderNote,
                    onClose: {
                        if showsSongAddSheet {
                            showsSongAddSheet = false
                        } else {
                            cancelGenerationTask()
                            dismiss()
                        }
                    }
                )
                .padding(.horizontal, 20)

                if showsSongAddSheet {
                    CandidateSongsAddSheet(
                        isFestival: isFestival,
                        artistOptions: addSongArtistOptions,
                        defaultArtist: fallbackArtistName,
                        onCancel: { showsSongAddSheet = false },
                        onAdd: { name, artist in
                            if addSong(name: name, artist: artist) {
                                showsSongAddSheet = false
                            }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                } else if isPickingLineupForGenerate {
                    lineupPickForGenerateBody
                } else if isGenerating {
                    // HTML: gen-status under head; body empty until apply.
                    SetlistProtoGenStatus(
                        text: genStatusLines[min(genStatusIndex, genStatusLines.count - 1)],
                        reduceMotion: reduceMotion
                    )
                    .padding(.horizontal, 20)
                    .transition(.opacity)

                    if isEmptyCatalog {
                        Spacer(minLength: 0)
                    } else {
                        filledOrEditingBody
                    }
                } else if isEmptyCatalog, !isEditingSetlist {
                    emptyGenerateState
                } else {
                    filledOrEditingBody
                }
            }
        }
        .presentationDetents(sheetDetents, selection: $sheetDetent)
        .toolbar(.hidden, for: .navigationBar)
        .alert("重新生成歌单猜想？", isPresented: $showsReplacementConfirmation) {
            Button("取消", role: .cancel) {}
            Button("重新生成", role: .destructive) {
                startGenerationTask { runID in
                    await generateCandidateSongs(runID: runID)
                }
            }
        } message: {
            Text("会用新的猜想替换生成曲目，保留你手加的歌和最想看标记。")
        }
        .alert("按新阵容重新生成？", isPresented: $showsLineupRegenConfirm) {
            Button("取消", role: .cancel) {}
            Button("重新生成", role: .destructive) {
                startGenerationTask { runID in
                    await generateCandidateSongs(runID: runID)
                }
            }
        } message: {
            Text("阵容已保存。重新生成会替换生成曲目，并保留手加与最想看。")
        }
        .confirmationDialog(
            "从歌单移除？",
            isPresented: Binding(
                get: { songPendingRemoval != nil },
                set: { if !$0 { songPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                if let song = songPendingRemoval {
                    remove(song)
                }
                songPendingRemoval = nil
            }
            Button("取消", role: .cancel) {
                songPendingRemoval = nil
            }
        }
        .sheet(isPresented: $showsLineupEdit) {
            FestivalLineupEditSheet(
                interests: showArtistInterests,
                onCancel: { showsLineupEdit = false },
                onSave: { applyLineupSelection($0) }
            )
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsSetlistShareSheet) {
            ZStack {
                LinearGradient(
                    colors: [SetlistProto.surfaceRaised.opacity(0.98), SetlistProto.surface],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    SetlistProtoSheetHeader(
                        title: "分享歌单猜想",
                        note: "发给一起去现场的人 · 各自猜，开场对答案",
                        onClose: { showsSetlistShareSheet = false }
                    )
                    .padding(.horizontal, 20)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SetlistProtoShareCard(
                                title: shareHeadline,
                                meta: show.city.map { "\($0) · 共 \(allSongs.count) 首" } ?? "共 \(allSongs.count) 首",
                                rows: allSongs.map {
                                    .init(
                                        name: $0.songName,
                                        artist: isMultiArtist ? $0.artist : nil,
                                        isMostWanted: $0.isMostWanted
                                    )
                                }
                            )
                            .frame(height: shareCardHeight(songCount: allSongs.count))

                            SetlistProtoShareActions(
                                onCopy: { copyPlaylist() },
                                onSave: { saveShareImageToPhotos() },
                                isSaving: isSavingShareImage
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.hidden)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showsProMembership) {
            ProMembershipSheetView()
        }
        .sheet(isPresented: $showsProLimit) {
            BSProLimitSheet(
                title: ProLimitReason.candidateSongsRegeneration.title,
                message: ProLimitReason.candidateSongsRegeneration.message,
                onPrimary: {
                    showsProLimit = false
                    showsProMembership = true
                },
                onSecondary: {
                    showsProLimit = false
                }
            )
        }
        .bsToastOverlay(toast)
        .onAppear {
            if !allSongs.isEmpty {
                try? session.deduplicateSongs(songs: allSongs, groups: showGroups, in: modelContext)
            }
            // Legacy generations often stored all-mid + empty hints; fill shape once without API.
            try? session.repairLegacyTiersAndHintsIfNeeded(songs: allSongs, in: modelContext)
            // 音乐节：把现场「艺人 / 阵容」拆成艺人关注项（添加时已有名单，这里补建关注项）。
            if isFestival {
                seedFestivalInterestsIfNeeded()
            }

            sheetDetent = .large

            guard !didApplyLaunch else { return }
            didApplyLaunch = true
            switch launch {
            case .browse:
                break
            case .generate:
                break
            case .edit:
                isEditingSetlist = true
            case .share:
                if !allSongs.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        showsSetlistShareSheet = true
                    }
                }
            }
        }
        // Prefer `.task` over onAppear for first generate — runs after sheet is presented.
        // Single-artist empty: auto-start (一键触发，不再多点一次「猜一份歌单」).
        // Festival empty: only when launch == .generate → lineup pick first.
        .task(id: "\(launch)-\(show.id.uuidString)") {
            guard SetlistSheetLaunch.shouldAutoStartEmptyGeneration(
                launch: launch,
                isFestival: isFestival,
                catalogIsEmpty: allSongs.isEmpty,
                didAutoGenerate: didAutoGenerate
            ) else { return }
            didAutoGenerate = true
            if isFestival {
                seedFestivalInterestsIfNeeded()
                beginLineupPickForGenerate()
            } else {
                startGenerationTask { runID in
                    await startEmptyGeneration(runID: runID)
                }
            }
        }
        .onDisappear {
            cancelGenerationTask()
        }
    }

    private var sheetHeaderTitle: String {
        if showsSongAddSheet { return "加一首" }
        if isPickingLineupForGenerate { return "调整阵容" }
        if isEditingSetlist { return "编辑歌单猜想" }
        return "歌单猜想"
    }

    private var sheetHeaderNote: String {
        if showsSongAddSheet { return "歌名 + 艺人，加进对应分组；重新生成会保留" }
        if isPickingLineupForGenerate {
            return "保留想看或待定的艺人 · 至少留 1 组"
        }
        if isEditingSetlist { return "增删、排序都会直接保存到歌单" }
        return sheetNote
    }

    /// Multi-artist step before first generate: check artists (default all on).
    private var lineupPickForGenerateBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(
                lineupPickArtists.isEmpty
                    ? "本场还没有艺人名单 · 先加几组再猜"
                    : "关掉不打算看的艺人，再按阵容猜想"
            )
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(SetlistProto.dim)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(lineupPickArtists, id: \.id) { interest in
                        let on = lineupPickSelection.contains(interest.id)
                        Button {
                            toggleLineupPick(interest.id)
                        } label: {
                            HStack(spacing: 12) {
                                Text(interest.artistName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(on ? SetlistProto.fg : SetlistProto.dim.opacity(0.55))
                                Spacer(minLength: 0)
                                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 22, weight: .regular))
                                    .foregroundColor(on ? SetlistProto.accent : SetlistProto.dim)
                            }
                            .padding(.horizontal, 2)
                            .frame(minHeight: 52)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(interest.artistName) \(on ? "参与" : "不看")")
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            // Always allow adding artists (seed may be empty or incomplete).
            HStack(spacing: 8) {
                TextField("加一组艺人", text: $lineupAddName)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 15))
                    .foregroundColor(SetlistProto.fg)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .onSubmit { addArtistToLineupPick() }

                Button(action: addArtistToLineupPick) {
                    Text("添加")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(SetlistProto.accent)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(SetlistProto.accent.opacity(0.14))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(SetlistProto.accent.opacity(0.35), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)

            HStack {
                Spacer(minLength: 0)
                Button {
                    confirmLineupPickAndGenerate()
                } label: {
                    Text("按此阵容猜想")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(SetlistProto.inkOnAccent)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(SetlistProto.accent))
                }
                .buttonStyle(.plain)
                .disabled(lineupPickSelection.isEmpty)
                .opacity(lineupPickSelection.isEmpty ? 0.45 : 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
            .overlay(alignment: .top) {
                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Filled list + optional edit/add + foot (HTML setlist-sheet body + foot when generated).
    @ViewBuilder
    private var filledOrEditingBody: some View {
        ScrollView {
            // VStack while editing: stable frames for long-press drag.
            Group {
                if isEmptyCatalog {
                    Text("歌单空了 · 在下面加一首，或重新生成")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(SetlistProto.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 2)
                } else if isEditingSetlist {
                    VStack(spacing: 0) {
                        ForEach(Array(sheetListSections.enumerated()), id: \.offset) { sectionIndex, section in
                            if let artist = section.artist {
                                SetlistProtoArtistGroupHeader(
                                    name: artist,
                                    count: section.songs.count,
                                    isFirst: sectionIndex == 0
                                )
                            }
                            ForEach(section.songs, id: \.song.id) { item in
                                trackRow(item)
                            }
                        }
                    }
                    .coordinateSpace(name: Self.setlistEditDragSpace)
                } else {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        ForEach(Array(sheetListSections.enumerated()), id: \.offset) { sectionIndex, section in
                            if let artist = section.artist {
                                SetlistProtoArtistGroupHeader(
                                    name: artist,
                                    count: section.songs.count,
                                    isFirst: sectionIndex == 0
                                )
                            }
                            ForEach(section.songs, id: \.song.id) { item in
                                trackRow(item)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 12)
            // While streaming progressive batches, keep rows readable (not heavily dimmed).
            .opacity(isGenerating && !reduceMotion ? (isEmptyCatalog ? 0.35 : 0.92) : 1)
            .animation(.easeOut(duration: 0.42), value: isGenerating)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(setlistDrag != nil)

        // HTML: foot only after generated (setlistSheetFoot.hidden = !st.generated)
        if !isGenerating, !isEmptyCatalog || isEditingSetlist {
            footerActions
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
        }
    }

    private static let setlistEditDragSpace = "setlistEditDrag"
    private static let setlistRowStride: CGFloat = 52

    @ViewBuilder
    private func trackRow(_ item: (offset: Int, song: CandidateSong)) -> some View {
        let songID = item.song.id
        let isDraggingThis = setlistDrag?.songID == songID
        let row = SetlistProtoTrackRow(
            song: item.song,
            isEditing: isEditingSetlist,
            revealDelay: Double(item.offset) * 0.09,
            reveal: revealNewList && !reduceMotion,
            isDragPlaceholder: isDraggingThis,
            onToggleMostWanted: { toggleMostWanted(item.song) },
            onMoveUp: item.offset > 0 ? {
                moveGlobally(from: IndexSet(integer: item.offset), to: item.offset - 1)
            } : nil,
            onMoveDown: item.offset < allSongs.count - 1 ? {
                moveGlobally(from: IndexSet(integer: item.offset), to: item.offset + 2)
            } : nil,
            onDelete: { songPendingRemoval = item.song }
        )

        if isEditingSetlist {
            row
                .offset(y: isDraggingThis ? (setlistDrag?.translationY ?? 0) : 0)
                .zIndex(isDraggingThis ? 10 : 0)
                .shadow(
                    color: isDraggingThis ? Color.black.opacity(0.35) : .clear,
                    radius: isDraggingThis ? 10 : 0,
                    y: isDraggingThis ? 4 : 0
                )
                .gesture(setlistRowDragGesture(songID: songID, index: item.offset))
        } else {
            row
        }
    }

    /// Long-press then drag. Visual follows finger; order commits once on finger-up (no system onDrag).
    private func setlistRowDragGesture(songID: UUID, index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.setlistEditDragSpace)))
            .onChanged { value in
                switch value {
                case .second(true, let drag?):
                    if setlistDrag == nil {
                        setlistDrag = SetlistManualDragState(
                            songID: songID,
                            originIndex: index,
                            lastIndex: index,
                            translationY: 0
                        )
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                    guard setlistDrag?.songID == songID else { return }
                    // Do not mutate list order mid-gesture — that cancels the gesture and used to
                    // leave a stuck lift. Commit once in onEnded.
                    setlistDrag = SetlistManualDragState(
                        songID: songID,
                        originIndex: setlistDrag?.originIndex ?? index,
                        lastIndex: setlistDrag?.lastIndex ?? index,
                        translationY: drag.translation.height
                    )
                default:
                    break
                }
            }
            .onEnded { _ in
                defer { setlistDrag = nil }
                guard let session = setlistDrag, session.songID == songID else { return }
                let proposed = session.originIndex + Int(
                    (session.translationY / Self.setlistRowStride).rounded()
                )
                let clamped = min(max(0, proposed), max(0, allSongs.count - 1))
                guard clamped != session.originIndex,
                      let from = allSongs.firstIndex(where: { $0.id == songID }),
                      from != clamped else {
                    return
                }
                let destination = from < clamped ? clamped + 1 : clamped
                withAnimation(.snappy(duration: 0.22)) {
                    moveGlobally(from: IndexSet(integer: from), to: destination)
                }
            }
    }

    private func endSetlistDragSession() {
        setlistDrag = nil
    }

    private var emptyGenerateState: some View {
        // Fallback only (gen failed / opened empty without generate). HTML home CTA is on the card.
        VStack(alignment: .leading, spacing: 14) {
            if lastGenerationFailed {
                Text("这次没猜出来")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SetlistProto.fg)
                Text("网络或服务有点问题 · 再试一次")
                    .font(.system(size: 12.5, weight: .regular))
                    .foregroundColor(SetlistProto.muted)
                SetlistProtoPrimaryCTA(title: "再试一次") {
                    beginGenerateFlowFromEmpty()
                }
            } else {
                Text("这场可能会唱什么")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(SetlistProto.fg)
                Text(
                    needsLineupPickBeforeGenerate
                        ? "先勾选要猜的艺人 · 默认全选"
                        : "按本场信息猜想 · 可手动调整"
                )
                .font(.system(size: 12.5, weight: .regular))
                .foregroundColor(SetlistProto.muted)
                SetlistProtoPrimaryCTA(
                    title: needsLineupPickBeforeGenerate ? "选艺人再猜" : "猜一份歌单",
                    action: beginGenerateFlowFromEmpty
                )
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func beginGenerateFlowFromEmpty() {
        if isFestival {
            seedFestivalInterestsIfNeeded()
            beginLineupPickForGenerate()
        } else {
            startGenerationTask { runID in
                await startEmptyGeneration(runID: runID)
            }
        }
    }

    private func seedFestivalInterestsIfNeeded() {
        guard isFestival else { return }
        do {
            _ = try session.seedFestivalInterestsIfNeeded(
                existing: showArtistInterests,
                in: modelContext
            )
        } catch {
            // Non-fatal; user can add artists manually on pick screen.
        }
    }

    private func beginLineupPickForGenerate() {
        // wantToSee / undecided selected; notInterested stays off unless user re-checks.
        let interests = fetchInterestsForShow()
        lineupPickArtists = interests
        lineupPickSelection = CandidateSongsSession.defaultLineupPickSelection(interests: interests)
        isPickingLineupForGenerate = true
        sheetDetent = .large
    }

    /// Cancel any in-flight generation and start a single new task.
    private func startGenerationTask(_ work: @escaping @MainActor (UUID) async -> Void) {
        generationTask?.cancel()
        let runID = UUID()
        generationRunID = runID
        generationTask = Task { @MainActor in
            await work(runID)
            if generationRunID == runID {
                generationTask = nil
            }
        }
    }

    private func cancelGenerationTask() {
        generationRunID = nil
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    private func fetchInterestsForShow() -> [ArtistInterestItem] {
        let showID = show.id
        let descriptor = FetchDescriptor<ArtistInterestItem>(
            predicate: #Predicate { $0.showID == showID }
        )
        let fetched = (try? modelContext.fetch(descriptor)) ?? showArtistInterests
        return fetched.sorted { $0.order < $1.order }
    }

    private func toggleLineupPick(_ id: UUID) {
        if lineupPickSelection.contains(id) {
            if lineupPickSelection.count <= 1 {
                presentToast(.neutral, message: "至少保留 1 组艺人")
                return
            }
            lineupPickSelection.remove(id)
        } else {
            lineupPickSelection.insert(id)
        }
    }

    private func addArtistToLineupPick() {
        let name = lineupAddName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let item = try session.makeFestivalArtistDraft(
                name: name,
                existing: lineupPickArtists
            )
            if !lineupPickArtists.contains(where: { $0.id == item.id }) {
                lineupPickArtists.append(item)
                lineupPickArtists.sort { $0.order < $1.order }
            }
            lineupPickSelection.insert(item.id)
            lineupAddName = ""
        } catch {
            presentToast(.failure, message: "添加艺人失败")
        }
    }

    private func confirmLineupPickAndGenerate() {
        guard !lineupPickSelection.isEmpty else {
            presentToast(.neutral, message: "先勾选至少 1 组艺人")
            return
        }
        guard canGenerate else {
            showsProLimit = true
            return
        }
        let persistedIDs = Set(fetchInterestsForShow().map(\.id))
        for interest in lineupPickArtists {
            if !persistedIDs.contains(interest.id) {
                modelContext.insert(interest)
            }
            interest.status = lineupPickSelection.contains(interest.id) ? .wantToSee : .notInterested
        }
        do {
            try modelContext.save()
            isPickingLineupForGenerate = false
            startGenerationTask { runID in
                await startEmptyGeneration(runID: runID)
            }
        } catch {
            presentToast(.failure, message: "阵容保存失败")
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingSetlist {
                Button {
                    showsSongAddSheet = true
                    sheetDetent = .large
                } label: {
                    Label("加一首", systemImage: "plus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(SetlistProto.muted)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加一首")

                SetlistProtoChip(title: "完成", isPrimary: true) {
                    endSetlistDragSession()
                    isEditingSetlist = false
                }
            } else {
                // Prototype `.gen-note`
                Text("模型按本场演出信息猜测 · 实际以现场为准")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(SetlistProto.dim)
                    .fixedSize(horizontal: false, vertical: true)

                // Prototype `.gen-actions` flex-wrap (~30% min → ~3 per row)
                let columns = [
                    GridItem(.flexible(minimum: 88), spacing: 8),
                    GridItem(.flexible(minimum: 88), spacing: 8),
                    GridItem(.flexible(minimum: 88), spacing: 8)
                ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    if isFestival {
                        SetlistProtoChip(title: "调整阵容") { showsLineupEdit = true }
                    }
                    SetlistProtoChip(title: "编辑歌单猜想") { isEditingSetlist = true }
                    SetlistProtoChip(title: "分享歌单猜想") { sharePlaylist() }
                    SetlistProtoChip(
                        title: lastGenerationFailed ? "重试" : "重新生成",
                        isLoading: isGenerating,
                        action: requestGeneration
                    )
                    .disabled(isGenerating)
                }
            }
        }
        .padding(.top, 16)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Actions

    private func copyPlaylist() {
        UIPasteboard.general.string = session.copyText(
            headline: shareHeadline,
            scope: "全部",
            songs: allSongs
        )
        presentToast(.success, message: "已复制歌单猜想")
    }

    private func sharePlaylist() {
        showsSetlistShareSheet = true
    }

    @MainActor
    private func renderShareCardImage(songs: [CandidateSong]) -> UIImage? {
        let card = SetlistProtoShareCard(
            title: shareHeadline,
            meta: show.city.map { "\($0) · 共 \(songs.count) 首" } ?? "共 \(songs.count) 首",
            rows: songs.map {
                .init(name: $0.songName, artist: isMultiArtist ? $0.artist : nil, isMostWanted: $0.isMostWanted)
            }
        )
        .frame(width: 320, height: shareCardHeight(songCount: songs.count))
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }

    private func shareCardHeight(songCount: Int) -> CGFloat {
        max(426, 180 + CGFloat(songCount) * 24)
    }

    private func saveShareImageToPhotos() {
        guard !isSavingShareImage else { return }
        isSavingShareImage = true

        guard let image = renderShareCardImage(songs: allSongs) else {
            isSavingShareImage = false
            presentToast(.failure, message: "生成海报失败")
            return
        }

        let delegate = PhotoLibrarySaveDelegate { error in
            Task { @MainActor in
                photoSaveDelegate = nil
                isSavingShareImage = false
                if error == nil {
                    presentToast(.success, message: "海报已保存到相册")
                } else {
                    presentToast(.failure, message: "海报保存失败，请稍后再试")
                }
            }
        }
        photoSaveDelegate = delegate

        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            Task { @MainActor in
                guard status == .authorized || status == .limited else {
                    photoSaveDelegate = nil
                    isSavingShareImage = false
                    presentToast(.failure, message: "无法保存海报，请在设置中允许相册访问")
                    return
                }
                UIImageWriteToSavedPhotosAlbum(
                    image,
                    delegate,
                    #selector(PhotoLibrarySaveDelegate.image(_:didFinishSavingWithError:contextInfo:)),
                    nil
                )
            }
        }
    }

    /// Apply festival 艺人关注项 from lineup editor. Does not silently rewrite songs.
    private func applyLineupSelection(_ participatingIDs: Set<UUID>) {
        guard !participatingIDs.isEmpty else {
            presentToast(.failure, message: "至少保留 1 组艺人")
            return
        }
        for interest in showArtistInterests {
            interest.status = participatingIDs.contains(interest.id) ? .wantToSee : .notInterested
        }
        do {
            try modelContext.save()
            showsLineupEdit = false
            if allSongs.isEmpty {
                presentToast(.success, message: "阵容已更新 · \(participatingIDs.count) 组艺人")
            } else {
                showsLineupRegenConfirm = true
            }
        } catch {
            presentToast(.failure, message: "阵容保存失败")
        }
    }

    @discardableResult
    private func addSong(name: String, artist: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !artist.isEmpty else { return false }
        guard allSongs.count < 24 else {
            presentToast(.neutral, message: "歌单最多 24 首 · 先删掉几首")
            return false
        }

        do {
            try session.addUserSong(
                name: name,
                artist: artist,
                groups: showGroups,
                currentSongs: allSongs,
                artistInterests: showArtistInterests,
                in: modelContext
            )
            presentToast(.success, message: "已添加")
            return true
        } catch CandidateSongValidationError.duplicateSong {
            presentToast(.neutral, message: "这首歌已经在歌单里")
            return false
        } catch {
            presentToast(.failure, message: "添加失败")
            return false
        }
    }

    private func remove(_ song: CandidateSong) {
        do {
            try session.remove(song, previouslyOrdered: allSongs, in: modelContext)
            presentToast(.neutral, message: "已移除")
        } catch {
            presentToast(.failure, message: "移除失败")
        }
    }

    private func moveGlobally(from source: IndexSet, to destination: Int) {
        do {
            try session.move(
                previouslyOrdered: allSongs,
                from: source,
                to: destination,
                in: modelContext
            )
        } catch {
            presentToast(.failure, message: "移动失败")
        }
    }

    private func toggleMostWanted(_ song: CandidateSong) {
        do {
            let next = !song.isMostWanted
            try session.setMostWanted(song, isMostWanted: next, in: modelContext)
            presentToast(.neutral, message: next ? "已标记最想看「\(song.songName)」" : "已取消最想看")
        } catch {
            presentToast(.failure, message: "标记失败")
        }
    }

    private func requestGeneration() {
        guard canGenerate else {
            showsProLimit = true
            return
        }
        if allSongs.isEmpty {
            beginGenerateFlowFromEmpty()
        } else {
            // Product: confirm before replace (HTML skips confirm; we keep confirm for real data).
            showsReplacementConfirmation = true
        }
    }

    /// HTML `generateSetlist(false)`: sheet already open → gen-status → apply list.
    @MainActor
    private func startEmptyGeneration(runID: UUID) async {
        guard generationRunID == runID else { return }
        guard canGenerate else {
            showsProLimit = true
            isGenerating = false
            return
        }
        // Flip UI to generating immediately so empty CTA never flashes (match HTML).
        isGenerating = true
        genStatusIndex = 0
        sheetDetent = .large
        await generateCandidateSongs(runID: runID, isFirstEmptyGenerate: true)
    }

    @MainActor
    private func generateCandidateSongs(runID: UUID, isFirstEmptyGenerate: Bool = false) async {
        guard generationRunID == runID else { return }
        guard canGenerate else {
            showsProLimit = true
            isGenerating = false
            return
        }

        let wasEmpty = allSongs.isEmpty
        if !isGenerating {
            isGenerating = true
            genStatusIndex = 0
        }
        revealNewList = false
        defer {
            if generationRunID == runID {
                isGenerating = false
            }
        }

        // Status animation in parallel (HTML stepThrough); network may finish earlier or later.
        let statusTask: Task<Void, Never>? = reduceMotion
            ? nil
            : Task { @MainActor in
                let lines = genStatusLines
                for index in lines.indices where !Task.isCancelled {
                    genStatusIndex = index
                    try? await Task.sleep(nanoseconds: index == 0 ? 920_000_000 : 860_000_000)
                }
            }

        let interestsForGenerate = fetchInterestsForShow()
        if isFestival {
            let included = interestsForGenerate.filter { $0.status != .notInterested }
            guard !included.isEmpty else {
                lastGenerationFailed = true
                presentToast(.failure, message: "先勾选至少 1 组艺人")
                if isFestival { beginLineupPickForGenerate() }
                return
            }
        }

        do {
            try Task.checkCancellation()
            guard generationRunID == runID else { throw CancellationError() }
            var receivedSnapshot = false
            try await session.generateAndReplace(
                artistInterests: interestsForGenerate,
                existingGroups: showGroups,
                existingSongs: candidateSongs,
                in: modelContext,
                onSnapshot: { _ in
                    // Progressive snapshots are temporary UI only (not yet persisted).
                    if !receivedSnapshot {
                        receivedSnapshot = true
                        statusTask?.cancel()
                        withAnimation(.easeInOut(duration: 0.28)) {
                            sheetDetent = .large
                        }
                        if !reduceMotion {
                            revealNewList = true
                        }
                    }
                }
            )

            try Task.checkCancellation()
            guard generationRunID == runID else { throw CancellationError() }

            if let statusTask, !receivedSnapshot {
                // One-shot generate still waits out the status strip (no empty flash).
                _ = await statusTask.result
            } else {
                statusTask?.cancel()
            }

            usedFreeGenerationFeaturesRawValue = ProUsageStorage.markUsed(
                .candidateSongs,
                in: usedFreeGenerationFeaturesRawValue
            )
            lastGenerationFailed = false
            withAnimation(.easeInOut(duration: 0.28)) {
                sheetDetent = .large
            }
            if !reduceMotion, !receivedSnapshot {
                revealNewList = true
            }
            presentToast(
                .success,
                message: wasEmpty || isFirstEmptyGenerate
                    ? "猜好了 · 点爱心标记最想看的"
                    : "已重新猜想 · 最想看的歌保留"
            )
        } catch is CancellationError {
            // Dismiss / superseded task: silent — no toast, no usage burn, no data write.
            statusTask?.cancel()
        } catch {
            lastGenerationFailed = true
            presentToast(.failure, message: "生成失败 · 再试一次")
            statusTask?.cancel()
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}

// MARK: - Setlist row / edit sheets

/// In-edit long-press reorder session (fully owned; no system drag lift leftovers).
private struct SetlistManualDragState: Equatable {
    let songID: UUID
    let originIndex: Int
    var lastIndex: Int
    var translationY: CGFloat
}

/// Music-festival 歌单阵容调整：读写艺人关注项（参与 vs 不看）。
private struct FestivalLineupEditSheet: View {
    let interests: [ArtistInterestItem]
    let onCancel: () -> Void
    let onSave: (Set<UUID>) -> Void

    @State private var participating: Set<UUID> = []

    private var ordered: [ArtistInterestItem] {
        interests.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("关掉不打算看的艺人。若已有歌单，保存后会询问是否按新阵容重新生成。")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(BSColor.Home.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if ordered.isEmpty {
                    Text("本场还没有艺人关注项。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BSColor.Home.dim)
                        .padding(20)
                    Spacer()
                } else {
                    List {
                        ForEach(ordered, id: \.id) { interest in
                            let on = participating.contains(interest.id)
                            Button {
                                toggle(interest.id)
                            } label: {
                                HStack {
                                    Text(interest.artistName)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(on ? BSColor.Home.foreground : BSColor.Home.dim)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(on ? BSColor.Home.accent : BSColor.Home.dim)
                                        .font(.system(size: 20, weight: .semibold))
                                }
                                .frame(minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .accessibilityLabel("\(interest.artistName) \(on ? "参与" : "不看")")
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(BSColor.Home.background.ignoresSafeArea())
            .navigationTitle("调整阵容")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(participating)
                    }
                    .fontWeight(.semibold)
                    .disabled(participating.isEmpty)
                }
            }
            .onAppear {
                participating = Set(
                    ordered
                        .filter { $0.status != .notInterested }
                        .map(\.id)
                )
                if participating.isEmpty, let first = ordered.first {
                    participating = [first.id]
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if participating.contains(id) {
            if participating.count <= 1 { return }
            participating.remove(id)
        } else {
            participating.insert(id)
        }
    }
}

/// Wraps footer chips so they wrap on narrow widths (prototype gen-actions row).
private struct FlowFooterActions<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        // Simple wrapping via flexible stack; chips stay tappable at 36pt min height.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { content }
            VStack(alignment: .leading, spacing: 10) { content }
        }
    }
}

private struct SetlistSongRow: View {
    let song: CandidateSong
    let showsArtist: Bool
    let isEditing: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onToggleMostWanted: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(tierColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.songName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(BSColor.Home.foreground)
                    .lineLimit(1)
                if !isEditing {
                    HStack(spacing: 8) {
                        Text(tierLabel)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(tierLabelColor)
                        if let hint = song.shortHint, !hint.isEmpty {
                            Text(hint)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(BSColor.Home.dim)
                                .lineLimit(1)
                        } else if showsArtist {
                            Text(song.artist)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(BSColor.Home.dim)
                                .lineLimit(1)
                        } else if song.tier == .guest {
                            Text("嘉宾 · \(song.artist)")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(BSColor.Home.dim)
                                .lineLimit(1)
                        }
                    }
                } else if isMultiArtistMeta {
                    Text(song.artist)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(BSColor.Home.dim)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isEditing {
                HStack(spacing: 2) {
                    editAct(systemName: "arrow.up", enabled: canMoveUp, label: "上移 \(song.songName)", action: onMoveUp)
                    editAct(systemName: "arrow.down", enabled: canMoveDown, label: "下移 \(song.songName)", action: onMoveDown)
                    editAct(systemName: "xmark", enabled: true, label: "删除 \(song.songName)", destructive: true, action: onDelete)
                }
            } else {
                Button(action: onToggleMostWanted) {
                    Image(systemName: song.isMostWanted ? "heart.fill" : "heart")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(song.isMostWanted ? BSColor.Home.accent : BSColor.Home.dim)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(song.isMostWanted ? "取消最想看 \(song.songName)" : "最想看 \(song.songName)")
            }
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 52)
        .overlay(alignment: .bottom) {
            BSColor.Home.foreground.opacity(0.06).frame(height: 1)
        }
    }

    private var isMultiArtistMeta: Bool { showsArtist }

    private func editAct(
        systemName: String,
        enabled: Bool,
        label: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(
                    enabled
                        ? (destructive ? BSColor.Home.live : BSColor.Home.muted)
                        : BSColor.Home.dim.opacity(0.35)
                )
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var tierLabel: String {
        switch song.tier {
        case .high: return "高可能"
        case .mid: return "较可能"
        case .guest: return "嘉宾"
        case .encore: return "返场"
        }
    }

    private var tierLabelColor: Color {
        switch song.tier {
        case .high: return BSColor.Home.accent
        case .mid, .guest, .encore: return BSColor.Home.dim
        }
    }

    private var tierColor: Color {
        switch song.tier {
        case .high: return BSColor.Home.accent
        case .mid: return BSColor.Home.prepare.opacity(0.95)
        case .guest: return BSColor.Home.fragment
        case .encore: return BSColor.Home.route
        }
    }
}

private struct CandidateSongsAddSheet: View {
    let isFestival: Bool
    let artistOptions: [String]
    let defaultArtist: String
    let onCancel: () -> Void
    let onAdd: (String, String) -> Void

    @State private var songName = ""
    @State private var selectedArtist = ""

    private var canSubmit: Bool {
        !songName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!isFestival || !selectedArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("歌名", text: $songName)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(SetlistProto.fg)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .onChange(of: songName) { _, value in
                    if value.count > 80 {
                        songName = String(value.prefix(80))
                    }
                }

            if isFestival {
                VStack(alignment: .leading, spacing: 8) {
                    Text("选择艺人")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(Color.white.opacity(0.72))

                    // HTML packs foot under chips. Avoid expandable ScrollView (it leaves a tall empty band).
                    // Only wrap when the lineup is large enough to need a scroll region.
                    let chips = FlowArtistChips(
                        artists: artistOptions,
                        selected: $selectedArtist
                    )
                    if artistOptions.count > 16 {
                        ScrollView(.vertical) {
                            chips
                        }
                        .scrollIndicators(.hidden)
                        .frame(maxHeight: 220, alignment: .top)
                    } else {
                        chips
                    }
                }
                .padding(.top, 16)
            }

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                SetlistProtoChip(title: "取消", expands: false, compact: true, action: onCancel)
                SetlistProtoChip(title: "加入歌单", isPrimary: true, expands: false, compact: true) {
                    onAdd(songName, isFestival ? selectedArtist : defaultArtist)
                }
                .disabled(!canSubmit)
            }
            .padding(.top, 16)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, 20)
        .onAppear {
            if selectedArtist.isEmpty {
                selectedArtist = artistOptions.first(where: { $0 == defaultArtist })
                    ?? artistOptions.first
                    ?? defaultArtist
            }
        }
    }

}

struct CurrentFeatureRow: View {
    let iconName: String
    let title: String
    let subtitle: String
    let accent: Color

    init(
        iconName: String,
        title: String,
        subtitle: String,
        accent: Color = BSColor.textPrimary
    ) {
        self.iconName = iconName
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
    }

    var body: some View {
        HStack(spacing: BSSpacing.md) {
            Image(systemName: iconName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text(title)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text(subtitle)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.textTertiary)
        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.borderProminent, lineWidth: 1)
        )
    }
}


struct ShowPreparationView: View {
    let show: Show

    @Environment(\.modelContext) private var modelContext
    @Query private var plans: [ShowPreparationPlan]
    @State private var notes = ""
    @State private var reminderEnabled = false
    @State private var reminderDate = Date()
    @State private var didLoadPlan = false
    @State private var message: String?
    @State private var toast: BSToastPayload?

    private let guide = ShowPreparationGuide()

    private var plan: ShowPreparationPlan? {
        plans.first { $0.showID == show.id }
    }

    var body: some View {
        BSStageScaffold(title: "现场准备", subtitle: show.name) {
            BSTipPromptCard(
                iconName: "sparkles",
                eyebrow: "Tips · 出门前",
                message: "出门前轻轻看几眼，心里有数就行，不用照着做完。",
                accent: BSColor.Accent.prepare
            )

            VStack(alignment: .leading, spacing: BSSpacing.md) {
                BSSectionHeader(title: "出门前可以看看")

                ForEach(guide.sections(for: show)) { section in
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text(section.title)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textSecondary)
                        ForEach(section.suggestions) { suggestion in
                            preparationSuggestionRow(suggestion)
                        }
                    }
                }
            }

            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Toggle(isOn: $reminderEnabled) {
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text("准备提醒")
                                .font(BSFont.headline)
                                .foregroundColor(BSColor.textPrimary)
                            Text("出门前轻轻提醒一下")
                                .font(BSFont.caption)
                                .foregroundColor(BSColor.textTertiary)
                        }
                    }
                    .tint(BSColor.Accent.prepare)

                    if reminderEnabled {
                        DatePicker("提醒时间", selection: $reminderDate)
                            .datePickerStyle(.compact)
                            .foregroundColor(BSColor.textSecondary)
                    }

                    Button("保存提醒") {
                        mutablePlan().updateReminderDate(reminderEnabled ? reminderDate : nil)
                        try? modelContext.save()
                        message = "准备提醒时间已保存在本机。"
                        presentToast(.success, message: "提醒已保存")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "个人备注")
                TextField("给自己留一点准备备注", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
                    .bsInputField()
                Button("保存备注") {
                    mutablePlan().updateNotes(notes)
                    try? modelContext.save()
                    message = "准备备注已保存在本机。"
                    presentToast(.success, message: "备注已保存")
                }
                .buttonStyle(BSSecondaryButtonStyle())
            }

            if let message {
                Text(message)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textSecondary)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadPlanIfNeeded)
        .onChange(of: reminderEnabled) { _, newValue in
            if !newValue {
                mutablePlan().updateReminderDate(nil)
                try? modelContext.save()
            }
        }
        .onChange(of: reminderDate) { _, newValue in
            guard reminderEnabled else { return }
            mutablePlan().updateReminderDate(newValue)
            try? modelContext.save()
        }
        .bsToastOverlay(toast)
    }

    private func preparationSuggestionRow(_ suggestion: ShowPreparationSuggestion) -> some View {
        Text(suggestion.text)
            .font(BSFont.body)
            .foregroundColor(BSColor.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: BSRadius.md)
                    .stroke(BSColor.border, lineWidth: 1)
            )
    }

    private func mutablePlan() -> ShowPreparationPlan {
        if let plan {
            return plan
        }

        let plan = ShowPreparationPlan(showID: show.id)
        modelContext.insert(plan)
        return plan
    }

    private func loadPlanIfNeeded() {
        guard !didLoadPlan else { return }
        didLoadPlan = true
        guard let plan else { return }
        notes = plan.notes ?? ""
        if let savedReminderDate = plan.reminderDate {
            reminderEnabled = true
            reminderDate = savedReminderDate
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }
}

struct ShowFragmentListView: View {
    private enum ComposerMode {
        case text
        case media
        case audio
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var fragments: [ShowFragment]

    let show: Show
    let opensComposerOnAppear: Bool
    @State private var text = ""
    @State private var selectedMediaItems: [PhotosPickerItem] = []
    @State private var pendingGalleryReferences: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)] = []
    @State private var pendingMediaPreviews: [PendingFragmentMediaPreview] = []
    @StateObject private var audioRecorder = FragmentAudioRecorder()
    @State private var pendingAudioRelativePath: String?
    @State private var pendingAudioDuration: TimeInterval?
    @State private var pendingAudioURL: URL?
    @State private var isShowingAudioDrawer = false
    @State private var composerExpanded = false
    @State private var composerMode: ComposerMode?
    @State private var message: String?
    @State private var editingFragment: ShowFragment?
    @State private var deletingFragment: ShowFragment?
    @State private var pendingDelete: ShowFragment?
    @State private var toast: BSToastPayload?
    @State private var hasOpenedComposerOnAppear = false
    @State private var showsMicPermissionAlert = false

    private var isRecordingAudio: Bool { audioRecorder.isRecording }
    private var session: ShowFragmentSession { ShowFragmentSession(show: show) }

    private var showFragments: [ShowFragment] {
        fragments
    }

    init(show: Show, opensComposerOnAppear: Bool = false) {
        self.show = show
        self.opensComposerOnAppear = opensComposerOnAppear
        let id = show.id
        _fragments = Query(
            filter: #Predicate<ShowFragment> { $0.show.id == id },
            sort: \ShowFragment.createdAt, order: .reverse
        )
    }

    var body: some View {
        BSStageScaffold(title: "现场碎片", subtitle: show.name, bottomPadding: 96) {
            composer
                .onChange(of: selectedMediaItems) { _, newItems in
                    if !newItems.isEmpty {
                        composerExpanded = true
                        composerMode = .media
                    }
                    Task {
                        await updatePendingMedia(from: newItems)
                    }
                }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "留下来的瞬间")
                if showFragments.isEmpty {
                    BSEmptyPanel(
                        iconName: "sparkles.rectangle.stack",
                        title: "还给这场留一点痕迹",
                        message: "OOTD、路上吃到的、朋友合照、散场那句话……只属于这一场。",
                        buttonTitle: "记一笔",
                        buttonIconName: "plus"
                    ) {
                        openComposer()
                    }
                } else {
                    ForEach(showFragments) { fragment in
                        FragmentTimelineCard(
                            fragment: fragment,
                            onEdit: {
                                editingFragment = fragment
                            },
                            onDelete: {
                                deletingFragment = fragment
                            }
                        )
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 首页 Tips「记一笔」进入时，appear 一次即直接展开新建，复位后避免返回再弹。
            guard opensComposerOnAppear, !hasOpenedComposerOnAppear else { return }
            hasOpenedComposerOnAppear = true
            openComposer()
        }
        .sheet(item: $editingFragment) { fragment in
            FragmentEditorSheet(fragment: fragment) {
                presentToast(.success, message: "碎片已更新")
            } onFailed: {
                presentToast(.failure, message: "更新失败")
            }
        }
        .sheet(item: $deletingFragment, onDismiss: {
            // 等 sheet 完全 dismiss 后再执行删除，避免动画期间修改 ModelContext 导致崩溃。
            if let fragment = pendingDelete {
                pendingDelete = nil
                delete(fragment)
            }
        }) { fragment in
            BSDangerConfirmationSheet(
                title: "删除现场碎片？",
                message: "这条文字、相册引用和本地语音文件都会从 BeforeShow 中移除。",
                destructiveTitle: "删除",
                onConfirm: {
                    pendingDelete = fragment
                    deletingFragment = nil
                },
                onCancel: {
                    deletingFragment = nil
                }
            )
        }
        .sheet(isPresented: $isShowingAudioDrawer, onDismiss: {
            // 录音中禁止 interactive dismiss；若仍关闭则丢弃未保存录音。
            if audioRecorder.isRecording {
                audioRecorder.stop()
                audioRecorder.discard()
                pendingAudioURL = nil
                pendingAudioRelativePath = nil
                pendingAudioDuration = nil
            }
        }) {
            FragmentAudioCaptureSheet(
                audioRecorder: audioRecorder.avAudioRecorder,
                pendingAudioURL: pendingAudioURL,
                pendingAudioDuration: pendingAudioDuration,
                isRecordingAudio: isRecordingAudio,
                showsMicPermissionAlert: $showsMicPermissionAlert,
                onStart: startAudioRecording,
                onStop: stopAudioRecording,
                onDismiss: {
                    isShowingAudioDrawer = false
                }
            )
            .interactiveDismissDisabled(isRecordingAudio)
        }
        .bsToastOverlay(toast)
    }

    private var composer: some View {
        BSGlassPanel {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: BSSpacing.xs) {
                        Text("留下一点这一刻")
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.textPrimary)
                        Text("不用整理好，先留下就好。")
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            composerExpanded.toggle()
                            if composerExpanded && composerMode == nil {
                                composerMode = .text
                            }
                        }
                    } label: {
                        Image(systemName: composerExpanded ? "chevron.up" : "plus")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(BSColor.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                    }
                }

                HStack(spacing: BSSpacing.sm) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            composerExpanded = true
                            composerMode = .text
                        }
                    } label: {
                        Label("写一句", systemImage: "text.bubble")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    PhotosPicker(
                        selection: $selectedMediaItems,
                        maxSelectionCount: 12,
                        matching: .any(of: [.images, .videos])
                    ) {
                        Label("照片", systemImage: "photo.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())

                    Button {
                        composerExpanded = true
                        composerMode = .audio
                        isShowingAudioDrawer = true
                    } label: {
                        Label("语音", systemImage: "mic.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(BSSecondaryButtonStyle())
                }

                if composerExpanded {
                    if composerMode == .text || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        TextField("写下一点这一场里的瞬间", text: $text, axis: .vertical)
                            .lineLimit(3...6)
                            .bsInputField()
                            .accessibilityLabel("现场碎片文字")
                    }

                    if !pendingMediaPreviews.isEmpty {
                        PendingMediaPreviewStrip(previews: pendingMediaPreviews)
                    }

                    if composerMode == .audio && pendingAudioURL == nil && !isRecordingAudio {
                        Button {
                            isShowingAudioDrawer = true
                        } label: {
                            Label("开始录一段声音", systemImage: "mic.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BSPrimaryButtonStyle())
                    } else if isRecordingAudio {
                        FragmentAudioPlaybackRow(
                            title: "正在录音",
                            subtitle: "录完后可以试听",
                            audioURL: nil,
                            duration: audioRecorder.avAudioRecorder?.currentTime,
                            isRecording: true,
                            audioRecorder: audioRecorder.avAudioRecorder
                        )
                    } else if let pendingAudioURL {
                        FragmentAudioPlaybackRow(
                            title: "语音片段",
                            subtitle: "保存前可以试听",
                            audioURL: pendingAudioURL,
                            duration: pendingAudioDuration,
                            isRecording: false
                        )
                    }

                    Button("保存碎片") {
                        saveFragment()
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
                    .disabled(!canSaveFragment || isRecordingAudio)

                    if let message {
                        Text(message)
                            .font(BSFont.caption)
                            .foregroundColor(BSColor.textTertiary)
                    }
                }
            }
        }
    }

    private var canSaveFragment: Bool {
        session.canSave(
            text: text,
            galleryReferenceCount: pendingGalleryReferences.count,
            hasAudio: pendingAudioRelativePath != nil
        )
    }

    private func saveFragment() {
        do {
            try session.create(
                text: text,
                galleryReferences: pendingGalleryReferences,
                audioRelativePath: pendingAudioRelativePath,
                audioDuration: pendingAudioDuration,
                in: modelContext
            )
            text = ""
            selectedMediaItems = []
            pendingGalleryReferences = []
            pendingMediaPreviews = []
            pendingAudioRelativePath = nil
            pendingAudioDuration = nil
            pendingAudioURL = nil
            // 文件已由碎片引用，转移所有权但不删除。
            audioRecorder.detach()
            composerExpanded = false
            composerMode = nil
            message = "这一刻留下来了。"
            presentToast(.success, message: "碎片已保存")
        } catch {
            message = "请先写一点内容，或添加照片、视频、语音片段。"
            presentToast(.failure, message: "保存失败")
        }
    }

    private func delete(_ fragment: ShowFragment) {
        do {
            try session.delete(fragment, in: modelContext)
            message = "现场碎片已删除。"
            presentToast(.neutral, message: "碎片已删除")
        } catch {
            message = "删除失败，请稍后再试。"
            presentToast(.failure, message: "删除失败")
        }
    }

    private func presentToast(_ tone: BSToastTone, message: String) {
        let payload = BSToastPayload(tone: tone, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if toast == payload {
                toast = nil
            }
        }
    }

    private func openComposer() {
        withAnimation(.easeInOut(duration: 0.22)) {
            composerExpanded = true
            composerMode = .text
        }
    }

    private func startAudioRecording() {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            beginRecording()
        case .undetermined:
            Task { @MainActor in
                let granted = await Self.requestMicrophonePermission()
                if granted {
                    beginRecording()
                } else {
                    handleMicPermissionDenied()
                }
            }
        case .denied:
            handleMicPermissionDenied()
        @unknown default:
            handleMicPermissionDenied()
        }
    }

    private func beginRecording() {
        do {
            try audioRecorder.start()
            pendingAudioRelativePath = audioRecorder.currentRelativePath
            pendingAudioURL = audioRecorder.currentURL
            pendingAudioDuration = nil
            message = "正在录音。"
        } catch {
            message = "无法开始录音，请检查麦克风权限。"
            presentToast(.failure, message: "无法开始录音")
        }
    }

    private func handleMicPermissionDenied() {
        // 无麦克风权限时引导去系统设置，不静默失败。
        showsMicPermissionAlert = true
    }

    private static func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func stopAudioRecording() {
        if let snapshot = audioRecorder.stop() {
            pendingAudioURL = snapshot.url
            pendingAudioRelativePath = snapshot.relativePath
            pendingAudioDuration = snapshot.duration
        }
        message = "语音片段已添加，保存后会留在这个现场碎片里。"
    }

    @MainActor
    private func updatePendingMedia(from items: [PhotosPickerItem]) async {
        var references: [(localIdentifier: String, kind: ShowFragmentGalleryMediaKind)] = []
        var previews: [PendingFragmentMediaPreview] = []

        for item in items {
            let kind: ShowFragmentGalleryMediaKind = item.supportedContentTypes.contains { type in
                type.conforms(to: .movie)
            } ? .video : .photo

            if let localIdentifier = item.itemIdentifier {
                references.append((localIdentifier, kind))
            }

            let image = await loadPreviewImage(from: item)
            previews.append(PendingFragmentMediaPreview(kind: kind, image: image))
        }

        pendingGalleryReferences = references
        pendingMediaPreviews = previews
    }

    private func loadPreviewImage(from item: PhotosPickerItem) async -> UIImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }

        return UIImage(data: data)
    }
}

private struct PendingFragmentMediaPreview: Identifiable {
    let id = UUID()
    let kind: ShowFragmentGalleryMediaKind
    let image: UIImage?
}

private struct PendingMediaPreviewStrip: View {
    let previews: [PendingFragmentMediaPreview]

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.xs) {
                Image(systemName: "photo.stack")
                Text("已选择 \(previews.count) 个照片/视频")
            }
            .font(BSFont.caption)
            .foregroundColor(BSColor.textTertiary)

            ScrollView(.horizontal) {
                HStack(spacing: BSSpacing.sm) {
                    ForEach(previews) { preview in
                        FragmentMediaThumbnail(image: preview.image, kind: preview.kind)
                            .frame(width: 78, height: 78)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct FragmentAudioCaptureSheet: View {
    let audioRecorder: AVAudioRecorder?
    let pendingAudioURL: URL?
    let pendingAudioDuration: TimeInterval?
    let isRecordingAudio: Bool
    @Binding var showsMicPermissionAlert: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        BSDrawerSheet(detent: .height(312)) {
            VStack(alignment: .leading, spacing: BSSpacing.xs) {
                Text("语音片段")
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.textPrimary)
                Text(isRecordingAudio ? "正在收录这一刻的声音" : "录完后可以先试听，再保存到现场碎片。")
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FragmentAudioPlaybackRow(
                title: isRecordingAudio ? "录音中" : "语音预览",
                subtitle: isRecordingAudio ? "点击停止后可试听" : "点击试听",
                audioURL: pendingAudioURL,
                duration: pendingAudioDuration,
                isRecording: isRecordingAudio,
                audioRecorder: audioRecorder,
                waveformWidth: 188
            )

            HStack(spacing: BSSpacing.sm) {
                Button(action: isRecordingAudio ? onStop : onStart) {
                    Label(isRecordingAudio ? "停止录音" : "开始录音", systemImage: isRecordingAudio ? "stop.circle.fill" : "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BSPrimaryButtonStyle())

                Button("完成") {
                    onDismiss()
                }
                .buttonStyle(BSSecondaryButtonStyle())
                .disabled(isRecordingAudio)
            }
        }
        .alert("无法录音", isPresented: $showsMicPermissionAlert) {
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("BeforeShow 需要麦克风权限才能录制现场声音。去系统设置开启后回来再试。")
        }
    }
}

private struct FragmentEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let fragment: ShowFragment
    var onSaved: () -> Void
    var onFailed: () -> Void

    @State private var text: String
    @State private var message: String?

    init(fragment: ShowFragment, onSaved: @escaping () -> Void, onFailed: @escaping () -> Void) {
        self.fragment = fragment
        self.onSaved = onSaved
        self.onFailed = onFailed
        _text = State(initialValue: fragment.text ?? "")
    }

    var body: some View {
        BSDrawerSheet(detents: [.medium, .large]) {
            VStack(alignment: .leading, spacing: BSSpacing.md) {
                VStack(alignment: .leading, spacing: BSSpacing.xs) {
                    Text("编辑现场碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)
                    Text("只修改这条碎片的文字，照片、视频和语音会继续保留。")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TextField("写下一点这一场里的瞬间", text: $text, axis: .vertical)
                    .lineLimit(4...8)
                    .bsInputField()

                if let message {
                    Text(message)
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Accent.fragment)
                }
            }

            HStack(spacing: BSSpacing.sm) {
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(BSSecondaryButtonStyle())

                Button("保存") {
                    save()
                }
                .buttonStyle(BSPrimaryButtonStyle())
            }
        }
    }

    private func save() {
        do {
            try fragment.updateText(text)
            try modelContext.save()
            onSaved()
            dismiss()
        } catch {
            message = "文字不能为空。"
            onFailed()
        }
    }
}

private extension ShowFragmentAudioReference {
    var durationText: String {
        guard let duration else { return "" }
        return "\(Int(duration.rounded())) 秒"
    }
}

private struct FragmentTimelineCard: View {
    let fragment: ShowFragment
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            HStack(spacing: BSSpacing.sm) {
                Text(fragment.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary.opacity(0.78))

                Spacer(minLength: BSSpacing.sm)

                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Circle())
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑现场碎片")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BSColor.Accent.fragment)
                        .frame(width: 32, height: 32)
                        .background(BSColor.Accent.fragment.opacity(0.10))
                        .clipShape(Circle())
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除现场碎片")
            }

            if let text = fragment.text {
                Text(text)
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !fragment.galleryMediaReferences.isEmpty {
                HStack(spacing: BSSpacing.xs) {
                    ForEach(fragment.galleryMediaReferences.prefix(6)) { reference in
                        GalleryMediaThumbnailView(reference: reference)
                            .frame(width: 58, height: 58)
                    }
                }
            }

            if let audioReference = fragment.audioReference {
                FragmentAudioPlaybackRow(
                    title: "语音片段",
                    subtitle: audioReference.durationText,
                    audioURL: ShowFragmentAudioStorage.applicationSupport().url(for: audioReference),
                    duration: audioReference.duration,
                    isRecording: false
                )
            }

        }
        .padding(BSSpacing.md)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }
}

private struct FragmentMediaThumbnail: View {
    let image: UIImage?
    let kind: ShowFragmentGalleryMediaKind
    var isMissing: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if isMissing {
                missingPlaceholder
            } else {
                loadingPlaceholder
            }

            // 失效媒体不显示播放角标，避免误导可播放。
            if kind == .video, !isMissing {
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                    .frame(width: 22, height: 22)
                    .background(Color.black.opacity(0.52))
                    .clipShape(Circle())
                    .padding(5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(BSColor.border, lineWidth: 1)
        )
    }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.055))
            .overlay(
                Image(systemName: kind == .video ? "video.fill" : "photo.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(BSColor.textTertiary)
            )
    }

    private var missingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.055))
            .overlay(
                VStack(spacing: 3) {
                    Image(systemName: kind == .video ? "video.fill" : "photo.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("原相册内容可能已删除")
                        .font(.system(size: 7, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.7)
                }
                .foregroundColor(BSColor.textTertiary)
                .padding(3)
            )
    }
}

private struct GalleryMediaThumbnailView: View {
    let reference: ShowFragmentGalleryMediaReference
    @State private var image: UIImage?
    @State private var requestedAssetLocalIdentifier: String?
    @State private var didFailLoading = false

    var body: some View {
        FragmentMediaThumbnail(image: image, kind: reference.kind, isMissing: didFailLoading)
            .task(id: reference.assetLocalIdentifier) {
                guard requestedAssetLocalIdentifier != reference.assetLocalIdentifier else { return }
                requestedAssetLocalIdentifier = reference.assetLocalIdentifier
                let loaded = await loadThumbnail()
                image = loaded
                didFailLoading = (loaded == nil)
            }
    }

    private func loadThumbnail() async -> UIImage? {
        await withCheckedContinuation { continuation in
            let result = PHAsset.fetchAssets(
                withLocalIdentifiers: [reference.assetLocalIdentifier],
                options: nil
            )
            guard let asset = result.firstObject else {
                continuation.resume(returning: nil)
                return
            }

            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 180, height: 180),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }
}

private struct FragmentAudioPlaybackRow: View {
    let title: String
    let subtitle: String
    let audioURL: URL?
    let duration: TimeInterval?
    let isRecording: Bool
    var audioRecorder: AVAudioRecorder?
    var waveformWidth: CGFloat = 112

    @StateObject private var player = FragmentAudioPlayerController()
    @State private var waveformSamples: [Double] = []

    var body: some View {
        HStack(spacing: BSSpacing.sm) {
            Button {
                player.toggle(url: audioURL)
            } label: {
                Image(systemName: isRecording ? "waveform" : (player.isPlaying ? "pause.fill" : "play.fill"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(audioURL == nil || isRecording)
            .accessibilityLabel(player.isPlaying ? "暂停语音片段" : "试听语音片段")

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BSColor.textSecondary)
                Text(detailText)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.textTertiary)
            }

            Spacer(minLength: 0)

            if isRecording {
                RecordingWaveformView(recorder: audioRecorder)
                    .frame(width: waveformWidth, height: 28)
            } else {
                AudioWaveformView(samples: waveformSamples, isActive: player.isPlaying)
                    .frame(width: waveformWidth, height: 28)
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.md)
                .stroke(BSColor.border, lineWidth: 1)
        )
        .task(id: audioURL) {
            await loadWaveformSamples()
        }
    }

    private var detailText: String {
        if isRecording {
            return "录音中"
        }
        if !subtitle.isEmpty {
            return subtitle
        }
        guard let duration else {
            return "点击试听"
        }
        return "\(Int(duration.rounded())) 秒"
    }

    @MainActor
    private func loadWaveformSamples() async {
        guard let audioURL else {
            waveformSamples = []
            return
        }

        do {
            waveformSamples = try AudioWaveformSampler().samples(from: audioURL, bucketCount: 28)
        } catch {
            waveformSamples = []
        }
    }
}

private struct RecordingWaveformView: View {
    let recorder: AVAudioRecorder?
    @State private var samples = Array(repeating: 0.12, count: 28)
    @State private var tick = 0

    var body: some View {
        AudioWaveformView(samples: samples, isActive: true)
            .task {
                while !Task.isCancelled {
                    let normalized: Double
                    if let recorder {
                        recorder.updateMeters()
                        let power = recorder.averagePower(forChannel: 0)
                        normalized = max(0.08, min(1.0, Double((power + 54) / 54)))
                    } else {
                        let phase = Double(tick) * 0.72
                        normalized = 0.18 + 0.58 * abs(sin(phase))
                    }

                    samples.removeFirst()
                    samples.append(normalized)
                    tick += 1
                    try? await Task.sleep(nanoseconds: 90_000_000)
                }
            }
    }
}

private struct AudioWaveformView: View {
    let samples: [Double]
    var isActive = false

    private var displaySamples: [Double] {
        samples.isEmpty
            ? [0.26, 0.48, 0.32, 0.62, 0.38, 0.55, 0.30, 0.45, 0.36, 0.58, 0.31, 0.50, 0.28, 0.40]
            : samples
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(displaySamples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(isActive ? BSColor.Accent.fragment.opacity(0.92) : BSColor.textTertiary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(5, CGFloat(sample) * 26))
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

#if DEBUG
struct DebugFragmentPreviewStateView: View {
    var body: some View {
        BSStageScaffold(title: "现场碎片", subtitle: "预览状态", bottomPadding: 96) {
            BSGlassPanel {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    Text("添加新的现场碎片")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.textPrimary)

                    Text("排队时听到里面在试音，鼓点一响整个人就紧张了。")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.045))
                        .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))

                    PendingMediaPreviewStrip(previews: [
                        PendingFragmentMediaPreview(kind: .photo, image: nil),
                        PendingFragmentMediaPreview(kind: .video, image: nil),
                        PendingFragmentMediaPreview(kind: .photo, image: nil)
                    ])

                    FragmentAudioPlaybackRow(
                        title: "语音片段",
                        subtitle: "12 秒",
                        audioURL: nil,
                        duration: 12,
                        isRecording: false,
                        waveformWidth: 168
                    )

                    Button("保存碎片") {}
                        .buttonStyle(BSPrimaryButtonStyle())
                }
            }

            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                BSSectionHeader(title: "已保存")
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    Text("散场后回头看了一眼灯牌，觉得这场会记很久。")
                        .font(BSFont.body)
                        .foregroundColor(BSColor.textPrimary)

                    HStack(spacing: BSSpacing.xs) {
                        FragmentMediaThumbnail(image: nil, kind: .photo)
                            .frame(width: 58, height: 58)
                        FragmentMediaThumbnail(image: nil, kind: .video)
                            .frame(width: 58, height: 58)
                    }

                    FragmentAudioPlaybackRow(
                        title: "语音片段",
                        subtitle: "8 秒",
                        audioURL: nil,
                        duration: 8,
                        isRecording: false,
                        waveformWidth: 168
                    )
                }
                .padding(BSSpacing.md)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.lg)
                        .stroke(BSColor.border, lineWidth: 1)
                )
            }
        }
    }
}

struct DebugFragmentAudioDrawerPreviewView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            CurrentShowStageBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                Spacer()
                Text("现场碎片")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(BSColor.textPrimary)
                Text("语音片段从底部抽屉开始录制。")
                    .font(BSFont.body)
                    .foregroundColor(BSColor.textTertiary)
                Spacer()
            }
            .padding(.horizontal, BSSpacing.md)

            FragmentAudioCaptureSheet(
                audioRecorder: nil,
                pendingAudioURL: nil,
                pendingAudioDuration: nil,
                isRecordingAudio: true,
                showsMicPermissionAlert: .constant(false),
                onStart: {},
                onStop: {},
                onDismiss: {}
            )
            .background(Color.black)
        }
        .preferredColorScheme(.dark)
    }
}
#endif
