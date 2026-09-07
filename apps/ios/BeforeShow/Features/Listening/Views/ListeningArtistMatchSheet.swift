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
                    HStack(spacing: BSSpacing.sm) {
                        Image(systemName: "magnifyingglass").foregroundStyle(BSColor.Stage.muted)
                        TextField(BSLocalization.text("艺人名称"), text: $query)
                            .textInputAutocapitalization(.words).autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                    .padding(.horizontal, BSSpacing.md).frame(minHeight: 52)
                    .background(BSColor.Stage.surfaceRaised.opacity(0.70), in: RoundedRectangle(cornerRadius: BSRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border))

                    if let error = room.errorText {
                        Text(error).font(.caption).foregroundStyle(BSColor.Stage.muted)
                    }
                    if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        stateView(systemImage: "magnifyingglass", text: BSLocalization.text("输入艺人名称进行搜索"))
                    } else if searching {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: BSRadius.lg)
                                .fill(BSColor.Stage.surfaceRaised.opacity(0.60))
                                .frame(height: 78)
                        }
                    } else if failed {
                        stateView(systemImage: "wifi.exclamationmark", text: BSLocalization.text("暂时无法搜索"))
                    } else if candidates.isEmpty {
                        stateView(systemImage: "person.crop.circle.badge.questionmark", text: BSLocalization.text("未找到艺人"))
                    } else {
                        LazyVStack(spacing: BSSpacing.sm) {
                            ForEach(candidates) { candidate in candidateRow(candidate) }
                        }
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.top, BSSpacing.sm)
                .padding(.bottom, BSSpacing.xl)
            }
            .background(BSColor.Stage.background)
            .navigationTitle(BSLocalization.text("连接艺人"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(BSLocalization.text("取消")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(BSLocalization.text("确认")) {
                        guard let selected else { return }
                        confirming = true
                        Task {
                            room.errorText = nil
                            await room.rematch(slotIndex: slotIndex, artist: selected)
                            confirming = false
                            if room.errorText == nil { dismiss() }
                        }
                    }.disabled(selected == nil || confirming)
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
                } catch { if !Task.isCancelled { searching = false; failed = true } }
            }
        }.tint(BSColor.Stage.foreground)
    }

    private func candidateRow(_ candidate: RecognizedArtist) -> some View {
        let selectedCandidate = selected?.id == candidate.id
        return Button { selected = candidate } label: {
            HStack(spacing: BSSpacing.md) {
                ListeningArtistArtwork(url: candidate.avatarURL, name: candidate.canonicalName)
                    .frame(width: 54, height: 54).clipShape(Circle())
                    .overlay(Circle().stroke(selectedCandidate ? BSColor.Stage.accent : BSColor.Stage.border, lineWidth: selectedCandidate ? 2 : 1))
                Text(candidate.canonicalName).font(.headline).foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 0)
                Image(systemName: selectedCandidate ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedCandidate ? BSColor.Stage.accent : BSColor.Stage.dim)
            }
            .padding(BSSpacing.md)
            .background(selectedCandidate ? BSColor.Stage.accent.opacity(0.10) : BSColor.Stage.surface.opacity(0.56), in: RoundedRectangle(cornerRadius: BSRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.lg).stroke(selectedCandidate ? BSColor.Stage.accent.opacity(0.45) : BSColor.Stage.border))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selectedCandidate ? .isSelected : [])
    }

    private func stateView(systemImage: String, text: String) -> some View {
        VStack(spacing: BSSpacing.sm) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(BSColor.Stage.muted)
            Text(text).font(.subheadline).foregroundStyle(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 72)
    }
}
