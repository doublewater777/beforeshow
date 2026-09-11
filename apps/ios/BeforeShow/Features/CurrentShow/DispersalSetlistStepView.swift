import SwiftUI

struct DispersalSetlistStepView: View {
    @Bindable var coordinator: FootprintListeningCoordinator
    let onBack: () -> Void
    let onSkip: () -> Void
    let onFinish: () -> Void
    let onClose: () -> Void

    @State private var customTitle = ""
    @State private var customArtist = ""
    @State private var showingManualInput = false
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ritualHead
                    if !coordinator.catalogChoices.isEmpty {
                        searchBar
                            .padding(.top, 16)
                    }
                    catalogSection
                        .padding(.top, 14)
                    manualAddSection
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, BSSpacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            DispersalSheetBottomBar(
                secondaryTitle: BSLocalization.text("跳过"),
                primaryTitle: BSLocalization.text("生成散场卡"),
                onSecondary: onSkip,
                onPrimary: onFinish
            )
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack {
            BSChromeIconButton(
                systemName: "chevron.left",
                accessibilityLabel: BSLocalization.text("返回"),
                action: onBack
            )
            Spacer()
            Text(BSLocalization.text("回记现场歌曲"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            BSChromeIconButton(
                systemName: "xmark",
                accessibilityLabel: BSLocalization.text("跳过并回到现场"),
                action: onClose
            )
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var ritualHead: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(BSLocalization.text("今晚听到了什么"))
                .font(.system(size: 10.5, weight: .bold))
                .tracking(1.2)
                .foregroundColor(BSColor.Stage.accent)
            Text(BSLocalization.text("现场唱了哪些歌？"))
                .font(.system(size: 26, weight: .semibold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)
            Text(BSLocalization.text("勾选当晚演出的歌曲，点亮星标设为最惊喜。"))
                .font(BSFont.caption)
                .foregroundColor(BSColor.Stage.muted)
                .padding(.top, 2)
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(BSColor.Stage.dim)
                .font(.system(size: 13, weight: .medium))
            TextField(BSLocalization.text("搜索演出曲目或艺人"), text: $searchText)
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.foreground)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(BSColor.Stage.dim)
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(BSColor.Stage.border, lineWidth: 1))
    }

    private var filteredChoices: [CatalogSong] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return coordinator.catalogChoices }
        return coordinator.catalogChoices.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.artistName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if coordinator.catalogChoices.isEmpty && coordinator.memories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(BSColor.Stage.dim)
                    Text(BSLocalization.text("尚未关联预习曲目，可以直接在下方手动添加现场歌曲。"))
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 16)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border, lineWidth: 1))
            } else if filteredChoices.isEmpty && !searchText.isEmpty {
                VStack(spacing: 8) {
                    Text(BSLocalization.text("未找到匹配歌曲，可在下方手动添加"))
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border, lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredChoices.enumerated()), id: \.element.id) { index, song in
                        let memory = coordinator.memories.first { $0.catalogSongID == song.appleMusicSongID }
                        let isSelected = memory != nil
                        let isSurprising = memory?.isMostSurprising == true
                        let isHeard = coordinator.heardSongIDs.contains(song.appleMusicSongID)

                        HStack(spacing: 12) {
                            Button {
                                toggleSong(song, existing: memory)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20))
                                        .foregroundColor(isSelected ? BSColor.Stage.accent : BSColor.Stage.dim)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(song.title)
                                                .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(isSelected ? BSColor.Stage.foreground : BSColor.Stage.muted)
                                                .lineLimit(1)
                                            if isHeard {
                                                Text(BSLocalization.text("预习听过"))
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(BSColor.Stage.accent)
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 1.5)
                                                    .background(BSColor.Stage.accent.opacity(0.12), in: Capsule())
                                            }
                                        }
                                        Text(song.artistName)
                                            .font(.system(size: 12))
                                            .foregroundColor(BSColor.Stage.dim)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if let memory {
                                Button {
                                    coordinator.toggleSurprising(memory)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: isSurprising ? "sparkle" : "sparkles")
                                            .font(.system(size: 13, weight: isSurprising ? .bold : .medium))
                                        if isSurprising {
                                            Text(BSLocalization.text("最惊喜"))
                                                .font(.system(size: 11, weight: .bold))
                                        }
                                    }
                                    .foregroundColor(isSurprising ? Color.black : BSColor.Stage.dim)
                                    .padding(.horizontal, isSurprising ? 9 : 6)
                                    .padding(.vertical, 5)
                                    .background(
                                        isSurprising ? BSColor.Stage.accent : Color.white.opacity(0.06),
                                        in: Capsule()
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(isSurprising ? BSLocalization.text("最惊喜歌曲") : BSLocalization.text("设为最惊喜"))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)

                        if index < filteredChoices.count - 1 {
                            Divider()
                                .overlay(BSColor.Stage.border.opacity(0.6))
                                .padding(.leading, 46)
                        }
                    }

                    // Manually added songs in this session
                    ForEach(coordinator.memories.filter { $0.catalogSongID == nil }) { manual in
                        Divider()
                            .overlay(BSColor.Stage.border.opacity(0.6))
                            .padding(.leading, 46)

                        HStack(spacing: 12) {
                            Button {
                                coordinator.delete(manual)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(BSColor.Stage.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(coordinator.title(manual))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(BSColor.Stage.foreground)
                                        if !coordinator.artist(manual).isEmpty {
                                            Text(coordinator.artist(manual))
                                                .font(.system(size: 12))
                                                .foregroundColor(BSColor.Stage.dim)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                coordinator.toggleSurprising(manual)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: manual.isMostSurprising ? "sparkle" : "sparkles")
                                        .font(.system(size: 13, weight: manual.isMostSurprising ? .bold : .medium))
                                    if manual.isMostSurprising {
                                        Text(BSLocalization.text("最惊喜"))
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                }
                                .foregroundColor(manual.isMostSurprising ? Color.black : BSColor.Stage.dim)
                                .padding(.horizontal, manual.isMostSurprising ? 9 : 6)
                                .padding(.vertical, 5)
                                .background(
                                    manual.isMostSurprising ? BSColor.Stage.accent : Color.white.opacity(0.06),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                }
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(BSColor.Stage.border, lineWidth: 1))
            }
        }
    }

    private var manualAddSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingManualInput {
                VStack(spacing: 10) {
                    TextField(BSLocalization.text("歌名"), text: $customTitle)
                        .font(BSFont.body)
                        .padding(10)
                        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 10))
                    TextField(BSLocalization.text("艺人名称（可选）"), text: $customArtist)
                        .font(BSFont.body)
                        .padding(10)
                        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 10))

                    HStack {
                        Button(BSLocalization.text("取消")) {
                            showingManualInput = false
                            customTitle = ""
                            customArtist = ""
                        }
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)

                        Spacer()

                        Button(BSLocalization.text("添加")) {
                            coordinator.add(title: customTitle, artist: customArtist)
                            if coordinator.error == nil {
                                customTitle = ""
                                customArtist = ""
                                showingManualInput = false
                            }
                        }
                        .font(BSFont.caption.weight(.semibold))
                        .foregroundColor(Color.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? BSColor.Stage.dim
                                : BSColor.Stage.accent,
                            in: Capsule()
                        )
                        .disabled(customTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(12)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(BSColor.Stage.border, lineWidth: 1))
            } else {
                Button {
                    showingManualInput = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13, weight: .semibold))
                        Text(BSLocalization.text("没在歌单里？手动添加现场歌曲"))
                            .font(BSFont.caption)
                    }
                    .foregroundColor(BSColor.Stage.accent)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggleSong(_ song: CatalogSong, existing: ShowSetlistMemory?) {
        if let existing {
            coordinator.delete(existing)
        } else {
            coordinator.add(songID: song.appleMusicSongID)
        }
    }
}
