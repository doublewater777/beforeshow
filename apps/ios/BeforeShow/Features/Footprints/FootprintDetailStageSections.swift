import SwiftUI

/// Memory fragments as a strip of film, cut into chapters by when they were taken.
struct FootprintContactSheet: View {
    let fragments: [MemoryFragment]
    let onOpen: (MemoryFragment) -> Void
    let onOpenList: () -> Void
    let onCreate: (MemoryCreateSourceOption) -> Void

    private static let frameSize = CGSize(width: 132, height: 168)

    /// Chapters in the order the night happened; each phase is marked once.
    private var chapters: [(phase: MemoryFragmentPhase, fragments: [MemoryFragment])] {
        [MemoryFragmentPhase.before, .live, .after].compactMap { phase in
            let items = fragments.filter { $0.phase == phase }
            return items.isEmpty ? nil : (phase, items)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(BSLocalization.text("记忆碎片"))
                    .font(FootprintDetailTokens.sectionFont)
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer()
                if !fragments.isEmpty {
                    Button(action: onOpenList) {
                        HStack(spacing: 3) {
                            Text(BSLocalization.format("%lld 条", fragments.count))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        }
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.text("查看全部记忆碎片"))
                }
                createMenu {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.06), in: Circle())
                        .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                }
                .accessibilityLabel(BSLocalization.text("添加记忆碎片"))
            }
            VStack(spacing: 8) {
                sprockets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        if fragments.isEmpty {
                            emptyFrame
                        }
                        ForEach(chapters, id: \.phase) { chapter in
                            chapterMark(chapter.phase)
                            ForEach(chapter.fragments) { fragment in
                                Button { onOpen(fragment) } label: { frame(for: fragment) }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(
                                        FootprintAccessibilityPolicy.memoryLabel(
                                            ordinal: (fragments.firstIndex { $0.id == fragment.id } ?? 0) + 1,
                                            kind: fragment.orderedMediaItems.first.map { $0.kind == .video ? BSLocalization.text("视频") : BSLocalization.text("照片") } ?? BSLocalization.text("文字"),
                                            recordedAt: fragment.createdAt,
                                            text: fragment.text
                                        )
                                    )
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, BSSpacing.roomy)
                }
                .scrollTargetBehavior(.viewAligned)
                sprockets
            }
            .padding(.vertical, 10)
            .background(Color(white: 0.043))
            .padding(.horizontal, -BSSpacing.roomy)
        }
    }

    private func createMenu<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Menu {
            ForEach(MemoryCreateSourceOption.allCases, id: \.self) { option in
                Button(option.title, systemImage: option.iconName) { onCreate(option) }
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }

    /// A chapter label printed sideways on the film edge, like a frame number.
    private func chapterMark(_ phase: MemoryFragmentPhase) -> some View {
        Text(phase.title)
            .font(.system(size: 11, weight: .semibold).width(.condensed))
            .tracking(3)
            .foregroundStyle(phase == .live ? BSColor.Stage.accent : BSColor.Stage.muted)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: 18, height: Self.frameSize.height)
            .accessibilityHidden(true)
    }

    private func frame(for fragment: MemoryFragment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let media = fragment.orderedMediaItems.first {
                    Color.clear
                        .overlay { MemoryThumbnail(relativePath: media.thumbnailRelativePath ?? media.relativePath) }
                        .overlay {
                            if media.kind == .video {
                                Image(systemName: "play.circle.fill").font(.system(size: 26)).foregroundStyle(.white)
                            }
                        }
                        .overlay(alignment: .bottom) {
                            if let text = FootprintTextNormalizer.nonEmptyTrimmed(fragment.text) {
                                Text(text)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                    .bsMaskUserContent()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .padding(.top, 14)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                } else {
                    Text("“\(fragment.text ?? "")”")
                        .font(.system(size: 14, design: .serif))
                        .lineSpacing(5)
                        .foregroundStyle(BSColor.Stage.heroIvory.opacity(0.9))
                        .bsMaskUserContent()
                        .lineLimit(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(12)
                        .background(Color(white: 0.09))
                }
            }
            .frame(width: Self.frameSize.width, height: Self.frameSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(Self.time(fragment.createdAt))
                .font(.system(size: 10, weight: .medium).width(.condensed).monospacedDigit())
                .foregroundStyle(BSColor.Stage.dim)
                .frame(width: Self.frameSize.width, alignment: .leading)
        }
    }

    private var emptyFrame: some View {
        createMenu {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                Text(BSLocalization.text("这一晚还没有留下记忆碎片"))
                    .font(.system(size: 11))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(BSColor.Stage.muted)
            .padding(12)
            .frame(width: Self.frameSize.width, height: Self.frameSize.height)
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        }
    }

    /// Film sprocket holes.
    private var sprockets: some View {
        Canvas { canvas, size in
            var x: CGFloat = 0
            while x < size.width {
                canvas.fill(Path(roundedRect: CGRect(x: x, y: 0, width: 9, height: size.height), cornerRadius: 1.5),
                            with: .color(BSColor.Stage.heroIvory.opacity(0.16)))
                x += 16
            }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }

    private static func time(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.month, .day, .hour, .minute], from: date)
        return String(format: "%02d.%02d %02d:%02d", parts.month ?? 0, parts.day ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Ticket and timetable taped onto cards, like keepsakes pinned to a wall.
struct FootprintKeepsakeShelf: View {
    let entries: [ShowAssetManagementEntry]
    let assetFor: (ShowAssetKind) -> ShowAsset?
    let onSelect: (ShowAssetKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(BSLocalization.text("留下的东西"))
                .font(FootprintDetailTokens.sectionFont)
                .foregroundStyle(BSColor.Stage.foreground)
            HStack(spacing: 12) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    Button { onSelect(entry.kind) } label: {
                        card(entry, tilt: index % 2 == 0 ? -5 : 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(BSLocalization.format("管理%@，%@", entry.kind.title, entry.subtitle))
                }
            }
        }
    }

    private func card(_ entry: ShowAssetManagementEntry, tilt: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let asset = assetFor(entry.kind), let location = try? ShowAssetMediaLocation.applicationSupport() {
                    FootprintTapedImage(url: location.rootDirectory.appendingPathComponent(asset.relativePath))
                        .frame(width: 96, height: 128)
                        .rotationEffect(.degrees(tilt))
                        .padding(.top, 14)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.84, green: 0.77, blue: 0.59).opacity(0.7))
                        .frame(width: 44, height: 14)
                        .rotationEffect(.degrees(tilt * 1.6))
                        .padding(.top, 6)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .frame(width: 96, height: 128)
                        .overlay {
                            Image(systemName: entry.kind.iconName)
                                .font(.system(size: 24, weight: .light))
                                .foregroundStyle(BSColor.Stage.accent)
                        }
                        .padding(.top, 14)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            Spacer(minLength: 0)
            Text(entry.kind.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
            Text(entry.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(BSColor.Stage.muted)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 210)
        .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The night's facts set like a programme: small caps label, plain value.
struct FootprintProgrammeInfo: View {
    struct Row: Identifiable {
        let label: String
        let value: String
        var id: String { label }
    }

    let rows: [Row]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(BSLocalization.text("现场资料"))
                .font(FootprintDetailTokens.sectionFont)
                .foregroundStyle(BSColor.Stage.foreground)
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .medium).width(.condensed))
                            .tracking(2)
                            .foregroundStyle(BSColor.Stage.dim)
                            .frame(width: 58, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 14))
                            .foregroundStyle(BSColor.Stage.foreground.opacity(0.9))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 13)
                    .overlay(alignment: .bottom) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                }
            }
            .overlay(alignment: .top) { Rectangle().fill(BSColor.Stage.border).frame(height: 1) }
        }
    }
}

struct FootprintRoundIconButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.06), in: Circle())
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FootprintTapedImage: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        // Size from the slot, not the image, so tall screenshots crop instead of spilling out.
        Color(white: 0.12)
            .overlay(alignment: .top) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 9, y: 8)
        // 用户导入的票根 / 时刻表一律遮罩。
        .bsMaskUserContent()
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
        }
    }
}

/// Who came along, and how many nights you have shared.
struct FootprintCompanionSection: View {
    let show: Show
    let archive: FootprintArchiveSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            Text(BSLocalization.text("同行"))
                .font(FootprintDetailTokens.sectionFont)
                .foregroundStyle(BSColor.Stage.foreground)
            VStack(spacing: 8) {
                ForEach(Array(companionRows.enumerated()), id: \.offset) { _, row in
                    companionRow(name: row.name, count: row.count)
                }
            }
        }
    }

    private func companionRow(name: String, count: Int) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [FootprintDetailTokens.companionAccent, FootprintDetailTokens.companionGlow],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: FootprintDetailTokens.avatarSize, height: FootprintDetailTokens.avatarSize)
                .overlay(
                    Text(String(name.prefix(1)))
                        .font(BSFont.headline)
                        .foregroundStyle(BSColor.Stage.foreground)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                Text(BSLocalization.format("共同留下 %lld 场足迹", count))
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.muted)
            }
            Spacer()
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private var companionRows: [(name: String, count: Int)] {
        let names = CompanionNameList.normalized(show.companionNames)
        if names.isEmpty {
            return [(BSLocalization.text("同行者"), 1)]
        }
        return names.map { name in
            (name, pairwiseCount(for: name))
        }
    }

    private func pairwiseCount(for name: String) -> Int {
        max(1, archive.shows.filter {
            $0.companionStatus == .confirmed
                && $0.endedAt != nil
                && CompanionNameList.normalized($0.companionNames).contains(name)
        }.count)
    }
}
