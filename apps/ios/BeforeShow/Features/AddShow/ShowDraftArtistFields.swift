import Foundation
import SwiftUI

// MARK: - Draft Artist Fields

private struct ArtistSearchPicker: View {
    let options: [RecognizedArtist]
    let isLoading: Bool
    let onPick: (RecognizedArtist) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "music.note")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BSColor.textTertiary)
                Text("iTunes 候选")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BSColor.textTertiary)
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BSColor.textTertiary)
                }
            }
            .padding(.horizontal, 4)

            if options.isEmpty && !isLoading {
                Text("暂无匹配，可直接保存手输名字")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BSColor.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        if index > 0 {
                            Divider()
                                .background(BSColor.borderProminent.opacity(0.5))
                                .padding(.leading, 44)
                        }
                        ArtistSearchRow(
                            option: option,
                            onPick: { onPick(option) }
                        )
                    }
                }
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: BSRadius.md)
                        .stroke(BSColor.borderProminent, lineWidth: 1)
                )
            }
        }
        .padding(.top, 2)
    }
}

private struct ArtistSearchRow: View {
    let option: RecognizedArtist
    let onPick: () -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 10) {
                Text(option.canonicalName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(BSColor.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(BSColor.Stage.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

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
    /// 选中候选项后,parent 通过 binding 写回新名字,onChange 会再次触发新一轮搜索。
    /// 用这个 flag 吃掉那次多余的搜索,让 picker 真收起。
    @State private var suppressNextSearch = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                TextField(BSLocalization.text("艺人名称"), text: $name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                        if suppressNextSearch {
                            suppressNextSearch = false
                            return
                        }
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

            if isSearching || !recognizedOptions.isEmpty {
                ArtistSearchPicker(
                    options: recognizedOptions,
                    isLoading: isSearching,
                    onPick: handlePick
                )
            }
        }
        .onDisappear { searchTask?.cancel() }
    }

    @MainActor
    private func handlePick(_ option: RecognizedArtist) {
        searchTask?.cancel()
        recognizedOptions = []
        isSearching = false
        suppressNextSearch = true
        onPick(option)
    }

    @MainActor
    private func scheduleSearch(for rawQuery: String) {
        searchTask?.cancel()
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = false
        guard !trimmed.isEmpty else {
            recognizedOptions = []
            return
        }
        let service = artistSearch
        searchTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let results = try await service.searchArtists(query: trimmed)
                if Task.isCancelled { return }
                recognizedOptions = Array(results.prefix(5))
                isSearching = false
            } catch {
                if Task.isCancelled { return }
                recognizedOptions = []
                isSearching = false
            }
        }
    }
}
