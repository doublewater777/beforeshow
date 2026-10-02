import Foundation
import SwiftUI

// MARK: - Draft Artist Fields

struct ArtistInputRow: View {
    let index: Int
    @Binding var name: String
    @Binding var avatar: String?
    let artistSearch: any ArtistSearchServicing
    let canDelete: Bool
    let onPick: (RecognizedArtist) -> Void
    let onDelete: () -> Void
    let onTextChange: () -> Void

    @State private var searchTask: Task<Void, Never>?
    @State private var recognizedOptions: [RecognizedArtist] = []
    @State private var isSearching = false
    @State private var debouncing = false
    @FocusState private var focused: Bool
    @State private var failure: ArtistSearchFailureMessage?
    @State private var showsResults = false
    @State private var pickedName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(BSLocalization.text("艺人名称"), text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit {
                        focused = false
                        if debouncing || (!isSearching && recognizedOptions.isEmpty) {
                            scheduleSearch(for: name, debounce: false)
                        }
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(BSColor.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .fill(BSColor.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md)
                            .stroke(BSColor.border, lineWidth: 1)
                    )
                    .onChange(of: name) { _, newValue in
                        if pickedName == newValue {
                            pickedName = nil
                            return
                        }
                        pickedName = nil
                        onTextChange()
                        scheduleSearch(for: newValue)
                    }

                if let avatar, let url = URL(string: avatar) {
                    ArtistAvatarThumb(url: url, size: 28)
                }

                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(BSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
                .opacity(canDelete ? 1 : 0.35)
            }

            if showsResults {
                ArtistSearchPicker(
                    options: recognizedOptions,
                    isLoading: isSearching,
                    failure: failure,
                    onRecovery: recoverSearch,
                    onPick: handlePick
                )
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    private func recoverSearch() {
        focused = false
        scheduleSearch(for: name, debounce: false)
    }

    @MainActor
    private func handlePick(_ option: RecognizedArtist) {
        searchTask?.cancel()
        focused = false
        debouncing = false
        recognizedOptions = []
        isSearching = false
        failure = nil
        showsResults = false
        pickedName = option.canonicalName
        onPick(option)
    }

    @MainActor
    private func scheduleSearch(for rawQuery: String, debounce: Bool = true) {
        searchTask?.cancel()
        failure = nil
        recognizedOptions = []
        debouncing = debounce
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debouncing = false
            isSearching = false
            showsResults = false
            return
        }
        isSearching = true
        showsResults = true
        let service = artistSearch
        searchTask = Task { @MainActor in
            do {
                if debounce { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                debouncing = false
                let results = try await service.searchArtists(query: trimmed)
                if Task.isCancelled { return }
                recognizedOptions = results
                isSearching = false
            } catch {
                if Task.isCancelled { return }
                recognizedOptions = []
                failure = ArtistSearchFailureMessage(error: error)
                isSearching = false
            }
        }
    }
}
