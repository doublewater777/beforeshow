import SwiftUI

struct ListeningArtistMatchSheet: View {
    @Bindable var room: ListeningRoomCoordinator
    let slotIndex: Int
    @State var query: String
    @State private var candidates: [RecognizedArtist] = []
    @State private var selected: RecognizedArtist?
    @State private var searching = false
    @State private var failed = false
    @State private var confirming = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpacing.md) {
                    searchBar

                    if let error = room.errorText {
                        Text(error).font(.caption).foregroundStyle(BSColor.Stage.muted)
                    }

                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        stateView(systemImage: "magnifyingglass", text: BSLocalization.text("输入艺人名称进行搜索"))
                    } else if searching {
                        VStack(spacing: BSSpacing.sm) {
                            ForEach(0..<3, id: \.self) { _ in
                                candidateSkeleton
                            }
                        }
                    } else if failed {
                        stateView(systemImage: "wifi.exclamationmark", text: BSLocalization.text("暂时无法搜索"))
                    } else if candidates.isEmpty {
                        stateView(systemImage: "person.crop.circle.badge.questionmark", text: BSLocalization.text("未找到艺人"))
                    } else {
                        LazyVStack(spacing: BSSpacing.sm) {
                            ForEach(candidates) { candidate in
                                candidateRow(candidate)
                            }
                        }
                    }
                }
                .padding(.horizontal, BSSpacing.roomy)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
            .background(BSColor.Stage.background)
            .navigationTitle(BSLocalization.text("连接艺人"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("取消")) { dismiss() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard let selected else { return }
                        confirming = true
                        Task {
                            room.errorText = nil
                            await room.rematch(slotIndex: slotIndex, artist: selected)
                            confirming = false
                            if room.errorText == nil { dismiss() }
                        }
                    } label: {
                        if confirming {
                            ProgressView()
                                .tint(BSColor.Stage.accent)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(selected == nil ? BSColor.Stage.dim : BSColor.Stage.accent)
                        }
                    }
                    .disabled(selected == nil || confirming)
                    .accessibilityLabel(BSLocalization.text("确认"))
                }
            }
            .task(id: query) {
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    selected = nil; candidates = []; searching = false; failed = false
                    return
                }
                selected = nil; candidates = []; searching = true; failed = false
                do {
                    try await Task.sleep(for: .milliseconds(300))
                    let result = try await AppleMusicArtistSearchService().searchArtists(query: trimmed)
                    try Task.checkCancellation()
                    candidates = result; searching = false
                } catch {
                    if !Task.isCancelled { searching = false; failed = true }
                }
            }
        }
        .tint(BSColor.Stage.foreground)
    }

    private var searchBar: some View {
        HStack(spacing: BSSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(BSColor.Stage.muted)
            TextField(BSLocalization.text("艺人名称"), text: $query)
                .font(BSFont.body)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(BSColor.Stage.dim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(BSColor.Stage.surfaceRaised.opacity(0.70), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border))
    }

    private var candidateSkeleton: some View {
        HStack(spacing: BSSpacing.compact) {
            Circle()
                .fill(BSColor.Stage.surfaceRaised)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 76, height: 9)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BSColor.Stage.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: BSRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border))
    }

    private func candidateRow(_ candidate: RecognizedArtist) -> some View {
        let selectedCandidate = selected?.id == candidate.id
        return Button { selected = candidate } label: {
            HStack(spacing: BSSpacing.compact) {
                ListeningArtistArtwork(url: candidate.avatarURL, name: candidate.canonicalName)
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(selectedCandidate ? BSColor.Stage.accent : BSColor.Stage.border, lineWidth: selectedCandidate ? 2 : 1))
                Text(candidate.canonicalName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 0)
                Image(systemName: selectedCandidate ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(selectedCandidate ? BSColor.Stage.accent : BSColor.Stage.dim)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(selectedCandidate ? BSColor.Stage.accent.opacity(0.10) : BSColor.Stage.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: BSRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(selectedCandidate ? BSColor.Stage.accent.opacity(0.45) : BSColor.Stage.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCandidate ? .isSelected : [])
    }

    private func stateView(systemImage: String, text: String) -> some View {
        VStack(spacing: BSSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(BSColor.Stage.accent)
                .frame(width: 64, height: 64)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))
            Text(text)
                .font(BSFont.body)
                .foregroundStyle(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
    }
}
