import Foundation
import SwiftData
import SwiftUI
import UIKit

private enum FootprintDetailTokens {
    static let backgroundGlowRadius: CGFloat = 260
    static let backgroundAccentRadius: CGFloat = 240
    static let heroCornerRadius = BSRadius.sheet
    static let emptyMemoryHeight: CGFloat = 132
    static let avatarSize: CGFloat = 48
    static let infoIconSize: CGFloat = 32
    static let infoTitleWidth: CGFloat = 36
    static let infoRowHeight: CGFloat = 58
    static let shareButtonHeight: CGFloat = 50
    static let shareShellRadius: CGFloat = 22
    static let memoryTileHeight: CGFloat = 168
    static let keepsakeTileHeight: CGFloat = 142

    static let navigationFont = BSFont.headline
    static let eyebrowFont = BSFont.V3.caption.weight(.semibold)
    static let identityDetailFont = BSFont.V3.caption
    static let iconFont = BSFont.caption.weight(.medium)
    static let sectionFont = BSFont.headline
    static let memoryPlayFont = BSFont.heroTitle.weight(.semibold)
    static let memoryBadgeFont = BSFont.V3.caption.weight(.semibold)

    static let backgroundGlow = BSColor.Stage.glowBlue.opacity(0.14)
    static let backgroundAccent = BSColor.Stage.accent.opacity(0.08)
    static let navigationFill = Color.white.opacity(0.055)
    static let heroSecondarySurface = BSColor.Stage.surface.opacity(0.84)
    static let heroBorder = BSColor.Stage.accent.opacity(0.15)
    static let identityFill = Color.white.opacity(0.035)
    static let companionAccent = BSColor.Stage.accent.opacity(0.38)
    static let companionGlow = BSColor.Stage.glowBlue.opacity(0.32)
    static let infoIconFill = Color.white.opacity(0.05)
    static let shareShellFill = BSColor.Stage.surfaceRaised.opacity(0.94)
    static let shareShellBorder = Color.white.opacity(0.11)
    static let shareShadow = Color.black.opacity(0.48)
    static let memoryScrim = Color.black.opacity(0.72)
    static let keepsakeScrim = Color.black.opacity(0.74)
    static let savedKeepsakeText = Color.white.opacity(0.74)
}

private struct FootprintMemoryTarget: Identifiable {
    let fragment: MemoryFragment
    let initialIndex: Int

    var id: UUID { fragment.id }
}

struct FootprintDetailView: View {
    let show: Show
    let archive: FootprintArchiveSnapshot
    var onDetailVisibilityChange: (Bool) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var memoryTarget: FootprintMemoryTarget?
    @State private var showingAssetKind: ShowAssetKind?
    @State private var isShowingShareComposer = false

    private let formatter = ShowDisplayFormatter()

    init(
        show: Show,
        archive: FootprintArchiveSnapshot,
        onDetailVisibilityChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.show = show
        self.archive = archive
        self.onDetailVisibilityChange = onDetailVisibilityChange
        let showID = show.id
        _fragments = Query(
            filter: #Predicate<MemoryFragment> { $0.showID == showID },
            sort: [
                SortDescriptor(\MemoryFragment.createdAt, order: .forward),
                SortDescriptor(\MemoryFragment.id, order: .forward)
            ]
        )
        _assets = Query(
            filter: #Predicate<ShowAsset> { $0.showID == showID },
            sort: [SortDescriptor(\ShowAsset.createdAt, order: .forward)]
        )
    }

    private var identity: FootprintDetailIdentity {
        FootprintDetailIdentityBuilder.make(show: show, archive: archive)
    }

    private var shareMaterials: [FootprintShareMaterial] {
        var sources = fragments.flatMap { fragment -> [FootprintShareSource] in
            let mediaSources = fragment.orderedMediaItems.map { item in
                FootprintShareSource(
                    id: item.id,
                    kind: item.kind == .photo ? .photo : .videoCover,
                    recordedAt: item.createdAt,
                    imageURL: MemoryMediaLocation.applicationSupport().url(
                        for: item.thumbnailRelativePath ?? item.relativePath
                    )
                )
            }
            guard mediaSources.isEmpty else { return mediaSources }
            return [FootprintShareSource(
                id: fragment.id,
                kind: .text,
                recordedAt: fragment.createdAt,
                imageURL: nil
            )]
        }
        if let location = try? ShowAssetMediaLocation.applicationSupport() {
            sources += assets.map { asset in
                FootprintShareSource(
                    id: asset.id,
                    kind: asset.kind == .ticket ? .ticket : .timetable,
                    recordedAt: asset.createdAt,
                    imageURL: location.rootDirectory.appendingPathComponent(asset.relativePath)
                )
            }
        }
        return FootprintShareMaterialBuilder.make(from: sources)
    }

    var body: some View {
        ZStack {
            footprintBackground
            VStack(spacing: 0) {
                navigationBar
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: BSSpacing.lg) {
                        hero
                        memorySection
                        keepsakesSection
                        if show.companionStatus == .confirmed {
                            companionSection
                        }
                        informationSection
                    }
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.sm)
                    .padding(.bottom, shareMaterials.isEmpty ? BSSpacing.xl : BSLayout.tabBarContentInset)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) {
            if !shareMaterials.isEmpty {
                shareButton
            }
        }
        .fullScreenCover(item: $memoryTarget) { target in
            MemoryFragmentReviewView(
                showID: show.id,
                fragment: target.fragment,
                initialIndex: target.initialIndex
            )
        }
        .sheet(item: $showingAssetKind) { kind in
            ShowAssetSheet(
                showID: show.id,
                showName: show.name,
                kind: kind,
                onDetailVisibilityChange: onDetailVisibilityChange,
                keepsParentDetailHidden: true
            )
        }
        .fullScreenCover(isPresented: $isShowingShareComposer) {
            FootprintShareComposerView(
                show: show,
                identity: identity,
                materials: shareMaterials,
                onClose: { isShowingShareComposer = false }
            )
        }
        .onAppear { onDetailVisibilityChange(true) }
        .onDisappear { onDetailVisibilityChange(false) }
        .preferredColorScheme(.dark)
    }

    private var footprintBackground: some View {
        ZStack {
            BSColor.Stage.background.ignoresSafeArea()
            RadialGradient(
                colors: [FootprintDetailTokens.backgroundGlow, .clear],
                center: .topTrailing,
                startRadius: .zero,
                endRadius: FootprintDetailTokens.backgroundGlowRadius
            )
            .ignoresSafeArea()
            RadialGradient(
                colors: [FootprintDetailTokens.backgroundAccent, .clear],
                center: .bottomLeading,
                startRadius: .zero,
                endRadius: FootprintDetailTokens.backgroundAccentRadius
            )
            .ignoresSafeArea()
        }
    }

    private var navigationBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(FootprintDetailTokens.navigationFont)
                    .foregroundColor(BSColor.Stage.foreground)
                    .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                    .background(FootprintDetailTokens.navigationFill, in: Circle())
                    .overlay(Circle().stroke(BSColor.Stage.border))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Spacer()
            Text("足迹详情")
                .font(FootprintDetailTokens.navigationFont)
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            Color.clear.frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.vertical, BSSpacing.xs)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heroEyebrow)
                .font(FootprintDetailTokens.eyebrowFont)
                .tracking(1.7)
                .foregroundColor(BSColor.Stage.accent)
            Text(show.name)
                .font(BSFont.V3.title1)
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(3)
                .padding(.top, BSSpacing.compact)
            Text(FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? "未填写场馆")
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .padding(.top, BSSpacing.sm)

            identityGrid
                .padding(.top, BSSpacing.lg)
        }
        .padding(BSSpacing.roomy)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.surfaceRaised, FootprintDetailTokens.heroSecondarySurface],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: FootprintDetailTokens.heroCornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FootprintDetailTokens.heroCornerRadius)
                .stroke(FootprintDetailTokens.heroBorder)
        )
    }

    private var heroEyebrow: String {
        let date = show.effectiveDate.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        return [date, FootprintTextNormalizer.nonEmptyTrimmed(show.city)?.uppercased()]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var identityGrid: some View {
        let values = identityValues
        return HStack(spacing: BSSpacing.sm) {
            ForEach(values, id: \.headline) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.headline)
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text(item.detail)
                        .font(FootprintDetailTokens.identityDetailFont)
                        .foregroundColor(BSColor.Stage.muted)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(BSSpacing.compact)
                .background(FootprintDetailTokens.identityFill, in: RoundedRectangle(cornerRadius: BSRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BSRadius.md).stroke(BSColor.Stage.border))
            }
        }
    }

    private var identityValues: [(headline: String, detail: String)] {
        var values = [("第 \(identity.showOrdinal) 场", "现场档案")]
        if let cityOrdinal = identity.cityOrdinal {
            values.append((
                "第 \(cityOrdinal) 场",
                "\(FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? "这座城市")现场"
            ))
        }
        if let companionOrdinal = identity.companionOrdinal,
           let companionName = identity.companionName {
            values.append(("第 \(companionOrdinal) 次", "与\(companionName)同行"))
        }
        return values
    }

    private var memorySection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader("记忆碎片", trailing: "\(fragments.count) 条")
            if fragments.isEmpty {
                VStack(spacing: BSSpacing.compact) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(BSFont.title.weight(.light))
                        .foregroundColor(BSColor.Stage.dim)
                    Text("这一晚还没有留下记忆碎片")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }
                .frame(maxWidth: .infinity)
                .frame(height: FootprintDetailTokens.emptyMemoryHeight)
                .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
                .accessibilityElement(children: .combine)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: BSSpacing.sm), GridItem(.flexible())],
                    spacing: BSSpacing.sm
                ) {
                    ForEach(fragments) { fragment in
                        Button {
                            memoryTarget = FootprintMemoryTarget(fragment: fragment, initialIndex: 0)
                        } label: {
                            FootprintMemoryTile(fragment: fragment)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开记忆碎片")
                    }
                }
            }
        }
    }

    private var keepsakesSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader("留下的东西")
            HStack(spacing: BSSpacing.sm) {
                ForEach(ShowAssetKind.allCases) { kind in
                    Button { showingAssetKind = kind } label: {
                        FootprintKeepsakeTile(kind: kind, asset: asset(for: kind))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("管理\(kind.title)，\(asset(for: kind) == nil ? "未添加" : "已保存")")
                }
            }
        }
    }

    private var companionSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader("同行")
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
                        Text(companionInitial)
                            .font(BSFont.headline)
                            .foregroundColor(BSColor.Stage.foreground)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text(FootprintTextNormalizer.nonEmptyTrimmed(show.companionName) ?? "同行者")
                        .font(BSFont.headline)
                        .foregroundColor(BSColor.Stage.foreground)
                    Text("共同留下 \(companionFootprintCount) 场足迹")
                        .font(BSFont.V3.caption)
                        .foregroundColor(BSColor.Stage.muted)
                }
                Spacer()
            }
            .padding(BSSpacing.compact)
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        }
    }

    private var companionInitial: String {
        guard let name = FootprintTextNormalizer.nonEmptyTrimmed(show.companionName),
              let first = name.first else { return "同" }
        return String(first)
    }

    private var companionFootprintCount: Int {
        guard let name = FootprintTextNormalizer.nonEmptyTrimmed(show.companionName) else { return 1 }
        return archive.shows.filter {
            $0.companionStatus == .confirmed
                && $0.endedAt != nil
                && FootprintTextNormalizer.nonEmptyTrimmed($0.companionName) == name
        }.count
    }

    private var informationSection: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            sectionHeader("现场资料")
            VStack(spacing: 0) {
                infoRow(icon: "calendar", title: "时间", value: formatter.dateText(for: show))
                Divider().overlay(BSColor.Stage.border)
                infoRow(
                    icon: "mappin.and.ellipse",
                    title: "场馆",
                    value: FootprintTextNormalizer.nonEmptyTrimmed(show.venueName) ?? "未填写场馆"
                )
                Divider().overlay(BSColor.Stage.border)
                infoRow(
                    icon: "building.2",
                    title: "城市",
                    value: FootprintTextNormalizer.nonEmptyTrimmed(show.city) ?? "未填写城市"
                )
                Divider().overlay(BSColor.Stage.border)
                infoRow(
                    icon: "music.note",
                    title: "艺人",
                    value: FootprintTextNormalizer.nonEmptyTrimmed(show.artist) ?? "未填写艺人"
                )
            }
            .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
            .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
        }
    }

    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: icon)
                .font(FootprintDetailTokens.iconFont)
                .foregroundColor(BSColor.Stage.muted)
                .frame(width: FootprintDetailTokens.infoIconSize, height: FootprintDetailTokens.infoIconSize)
                .background(FootprintDetailTokens.infoIconFill, in: RoundedRectangle(cornerRadius: BSRadius.sm))
            Text(title)
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.dim)
                .frame(width: FootprintDetailTokens.infoTitleWidth, alignment: .leading)
            Text(value)
                .font(BSFont.V3.small.weight(.medium))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, BSSpacing.compact)
        .frame(minHeight: FootprintDetailTokens.infoRowHeight)
        .accessibilityElement(children: .combine)
    }

    private var shareButton: some View {
        Button { isShowingShareComposer = true } label: {
            Label("分享这场回忆", systemImage: "square.and.arrow.up")
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Stage.background)
                .frame(maxWidth: .infinity)
                .frame(height: FootprintDetailTokens.shareButtonHeight)
                .background(BSColor.Stage.accent, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        }
        .buttonStyle(.plain)
        .padding(BSSpacing.sm)
        .background(
            FootprintDetailTokens.shareShellFill,
            in: RoundedRectangle(cornerRadius: FootprintDetailTokens.shareShellRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: FootprintDetailTokens.shareShellRadius)
                .stroke(FootprintDetailTokens.shareShellBorder)
        )
        .shadow(
            color: FootprintDetailTokens.shareShadow,
            radius: BSSpacing.roomy,
            y: BSSpacing.sm
        )
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.bottom, BSSpacing.compact)
    }

    private func sectionHeader(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(FootprintDetailTokens.sectionFont)
                .foregroundColor(BSColor.Stage.foreground)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.dim)
            }
        }
    }

    private func asset(for kind: ShowAssetKind) -> ShowAsset? {
        assets.first { $0.kind == kind }
    }

}

private struct FootprintMemoryTile: View {
    let fragment: MemoryFragment

    private var firstMedia: MemoryMediaItem? { fragment.orderedMediaItems.first }

    var body: some View {
        Group {
            if let media = firstMedia {
                ZStack(alignment: .bottomLeading) {
                    MemoryThumbnail(relativePath: media.thumbnailRelativePath ?? media.relativePath)
                    LinearGradient(
                        colors: [.clear, FootprintDetailTokens.memoryScrim],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    if media.kind == .video {
                        Image(systemName: "play.circle.fill")
                            .font(FootprintDetailTokens.memoryPlayFont)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    HStack {
                        if media.kind == .video {
                            Text(durationText(media.videoDuration))
                        } else {
                            Text("照片")
                        }
                        Spacer()
                        if fragment.orderedMediaItems.count > 1 {
                            Text("\(fragment.orderedMediaItems.count) 项")
                        }
                    }
                    .font(FootprintDetailTokens.memoryBadgeFont)
                    .foregroundColor(.white)
                    .padding(BSSpacing.compact)
                }
            } else {
                VStack(alignment: .leading, spacing: BSSpacing.sm) {
                    Image(systemName: "quote.opening")
                        .font(BSFont.headline.weight(.light))
                        .foregroundColor(BSColor.Stage.accent)
                    Text(fragment.text ?? "")
                        .font(BSFont.caption)
                        .foregroundColor(BSColor.Stage.foreground)
                        .lineLimit(5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text("文字记忆")
                        .font(FootprintDetailTokens.memoryBadgeFont)
                        .foregroundColor(BSColor.Stage.dim)
                }
                .padding(BSSpacing.compact)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.memoryTileHeight)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func durationText(_ duration: TimeInterval?) -> String {
        let total = max(0, Int(duration ?? 0))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

private struct FootprintKeepsakeTile: View {
    let kind: ShowAssetKind
    let asset: ShowAsset?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let asset,
               let location = try? ShowAssetMediaLocation.applicationSupport() {
                FootprintLocalImage(
                    url: location.rootDirectory.appendingPathComponent(asset.relativePath),
                    contentMode: .fill
                )
                LinearGradient(
                    colors: [.clear, FootprintDetailTokens.keepsakeScrim],
                    startPoint: .center,
                    endPoint: .bottom
                )
            } else {
                LinearGradient(
                    colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: kind.iconName)
                    .font(BSFont.title.weight(.light))
                    .foregroundColor(BSColor.Stage.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title)
                    .font(BSFont.caption)
                    .foregroundColor(BSColor.Stage.foreground)
                Text(asset == nil ? "点击添加" : "查看或更换")
                    .font(BSFont.V3.caption)
                    .foregroundColor(asset == nil ? BSColor.Stage.muted : FootprintDetailTokens.savedKeepsakeText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, BSSpacing.compact)
            .padding(.bottom, BSSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FootprintDetailTokens.keepsakeTileHeight)
        .background(BSColor.Stage.surface)
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }
}

private struct FootprintLocalImage: View {
    let url: URL
    let contentMode: ContentMode
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                BSColor.Stage.surface
                    .overlay(Image(systemName: "photo").foregroundColor(BSColor.Stage.dim))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                UIImage(contentsOfFile: url.path)
            }.value
        }
    }
}
