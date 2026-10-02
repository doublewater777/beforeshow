import SwiftUI

struct ListeningArtistMatchSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    let slotIndex: Int
    @State var query: String
    @State private var candidates: [RecognizedArtist] = []
    @State private var selected: RecognizedArtist?
    @State private var searching = true
    @State private var failure: ArtistSearchFailureMessage?
    @State private var confirming = false
    @State private var searchAttempt = 0
    @State private var debouncing = false
    @State private var waitingForSettings = false
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private var sourceName: String {
        room.browseArtists.first { $0.slotIndex == slotIndex }?.name ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.lg) {
                    VStack(alignment: .leading, spacing: BSSpacing.sm) {
                        Text(sourceName)
                            .font(BSListeningTokens.detailTitle)
                            .foregroundStyle(BSColor.Stage.foreground)
                        Text(ListeningCopy.text("选择对应的 Apple Music 艺人"))
                            .font(BSListeningTokens.caption)
                            .foregroundStyle(BSColor.Stage.muted)
                    }
                    .padding(.top, BSSpacing.md)
                    searchBar
                    if let error = room.errorText {
                        Text(error)
                            .font(BSListeningTokens.caption)
                            .foregroundStyle(BSColor.Stage.danger)
                    }
                    results
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.bottom, BSSpacing.xl)
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(confirming)
            .background(ListeningSheetBackground())
            .safeAreaInset(edge: .bottom) {
                Button(action: confirmSelection) {
                    if confirming {
                        ProgressView().tint(BSListeningTokens.ink)
                    } else {
                        Label(BSLocalization.text("连接艺人"), systemImage: "link")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(BSListeningActionStyle())
                .disabled(selected == nil || confirming || searching)
                .accessibilityIdentifier("listening.confirmArtist")
                .padding(BSSpacing.roomy)
                .background(BSColor.Stage.background)
            }
            .navigationTitle(BSLocalization.text("连接艺人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("取消")) { dismiss() }
            }
            .task(id: "\(ArtistNameMatching.normalized(query))|\(searchAttempt)") { await search() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active, waitingForSettings {
                    waitingForSettings = false
                    debouncing = false
                    searchAttempt += 1
                }
            }
        }
        .tint(BSColor.Stage.foreground)
    }

    @ViewBuilder
    private var results: some View {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ListeningStateMessage(icon: "magnifyingglass", title: BSLocalization.text("输入艺人名称进行搜索"))
        } else if searching {
            ListeningStateMessage(icon: "magnifyingglass", title: ListeningCopy.text("正在搜索艺人…"), isLoading: true)
        } else if let failure {
            ListeningStateMessage(icon: failure.icon, title: BSLocalization.text(failure.title),
                                  subtitle: BSLocalization.text(failure.detail),
                                  actionTitle: failure.actionTitle, action: recoverSearch)
        } else if candidates.isEmpty {
            ListeningStateMessage(icon: "person.crop.circle.badge.questionmark", title: BSLocalization.text("未找到匹配的艺人"),
                                  subtitle: BSLocalization.text("试试艺人在 Apple Music 中的名称。"),
                                  actionTitle: ListeningCopy.text("换个名字搜索"), action: clearSearch)
        } else {
            LazyVStack(spacing: BSSpacing.sm) {
                ForEach(candidates) { candidate in
                    ListeningArtistCandidateRow(candidate: candidate, isSelected: selected?.id == candidate.id) {
                        selected = candidate
                        searchFocused = false
                    }
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: BSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(BSColor.Stage.muted)
            TextField(BSLocalization.text("艺人名称"), text: $query)
                .font(BSListeningTokens.body)
                .foregroundStyle(BSColor.Stage.foreground)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit {
                    searchFocused = false
                    if debouncing || (!searching && candidates.isEmpty) {
                        debouncing = false
                        searchAttempt += 1
                    }
                }
                .onChange(of: query) { old, new in
                    guard ArtistNameMatching.normalized(old) != ArtistNameMatching.normalized(new) else { return }
                    selected = nil
                    candidates = []
                    failure = nil
                    searching = !new.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    debouncing = searching
                }
                .accessibilityIdentifier("listening.artistSearch")
            if !query.isEmpty {
                Button(action: clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .buttonStyle(BSListeningPressStyle())
                .accessibilityLabel(ListeningCopy.text("清除搜索"))
                .accessibilityIdentifier("listening.clearArtistSearch")
            }
        }
        .padding(.leading, BSSpacing.md)
        .padding(.trailing, BSSpacing.xs)
        .frame(minHeight: BSListeningTokens.actionHeight)
        .background(BSColor.Stage.surfaceRaised, in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.md)
                .strokeBorder(searchFocused ? BSColor.Stage.accent.opacity(BSListeningTokens.selectionBorderOpacity) : BSColor.Stage.border,
                              lineWidth: BSListeningTokens.hairline)
        }
    }

    private func clearSearch() {
        query = ""
        searchFocused = true
    }

    private func recoverSearch() {
        guard let recovery = failure?.recovery else { return }
        searchFocused = false
        debouncing = false
        switch recovery {
        case .retry:
            searchAttempt += 1
        case .authorize:
            searching = true
            Task {
                await room.authorize()
                searchAttempt += 1
            }
        case .openSettings:
            waitingForSettings = true
            room.performListeningRecovery(.openSettings)
        }
    }

    private func confirmSelection() {
        guard let selected, !confirming, !searching else { return }
        searchFocused = false
        confirming = true
        Task {
            room.errorText = nil
            await room.rematch(slotIndex: slotIndex, artist: selected)
            confirming = false
            if room.errorText == nil { dismiss() }
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        selected = nil
        candidates = []
        failure = nil
        searching = !trimmed.isEmpty
        guard !trimmed.isEmpty else { return }
        do {
            if debouncing { try await Task.sleep(for: .milliseconds(300)) }
            try Task.checkCancellation()
            debouncing = false
            let result = try await room.searchArtists(query: trimmed)
            try Task.checkCancellation()
            candidates = result
            searching = false
        } catch {
            guard !Task.isCancelled else { return }
            debouncing = false
            searching = false
            failure = ArtistSearchFailureMessage(error: error)
        }
    }
}
