import SwiftUI
import WidgetKit

// MARK: - Cabinet Widget Views
// 设计语言严格对齐 BeforeShow 实体唱片柜:立体托梁(Rack Beam & Lip)、多张并列唱片封套与半抽镭射光盘。
// 支持在主屏幕上陈列当前现场的唱片集合(合辑与专辑)，一键直达 App 选碟开听。

struct CabinetWidgetView: View {
    let entry: ListeningEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemMedium:
            MediumCabinetView(entry: entry)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
                .widgetURL(URL(string: "beforeshow://listen"))
        case .systemSmall:
            SmallCabinetView(entry: entry)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
                .widgetURL(URL(string: "beforeshow://listen"))
        case .systemLarge:
            LargeCabinetView(entry: entry)
                .containerBackground(for: .widget) {
                    CoverAmbientBloom(ambient: entry.ambientColor)
                }
                .widgetURL(URL(string: "beforeshow://listen"))
        default:
            EmptyView()
        }
    }
}

// MARK: - 拟物托梁 (Rack Beam & Lip)
// 对齐 DesignBaseline: 4pt 高深暗立体导轨托梁与顶部 1pt 暖金边缘反光，赋予唱片稳固的物理着陆感。

struct CabinetRackBeamView: View {
    var body: some View {
        VStack(spacing: 0) {
            // 顶部 1pt 暖金反光导轨 (Lip)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            WidgetTheme.accent.opacity(0.15),
                            WidgetTheme.accent.opacity(0.55),
                            WidgetTheme.accent.opacity(0.15)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            // 下方 3pt 深暗立体导轨托梁 (Beam)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            WidgetTheme.surfaceRaised,
                            WidgetTheme.surface
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 3)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 柜内单张唱片卡片 (Cabinet Disc Item)

struct CabinetSleeveItemView: View {
    let disc: WidgetCabinetDiscItem
    let fallbackCoverPath: String?
    let cardSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 封套 + 右侧露出的 CD
            ZStack(alignment: .leading) {
                // 露出的微型镭射光盘
                LaserCDDiscView(
                    size: cardSize * 0.90,
                    coverImagePath: fallbackCoverPath,
                    isPlaying: disc.isLoaded
                )
                .offset(x: cardSize * 0.18)

                // 实体封套封面
                sleeveCover
            }
            .frame(width: cardSize * 1.15, height: cardSize)

            // 底部唱片标题与机内装载指示
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    if disc.isLoaded {
                        Circle()
                            .fill(WidgetTheme.heroWarmGold)
                            .frame(width: 4, height: 4)
                    }
                    Text(disc.title)
                        .font(.system(size: 10, weight: disc.isLoaded ? .bold : .semibold))
                        .foregroundStyle(disc.isLoaded ? WidgetTheme.heroWarmGold : WidgetTheme.foreground)
                        .lineLimit(1)
                }

                Text(subtitleText)
                    .font(.system(size: 8))
                    .foregroundStyle(WidgetTheme.dim)
                    .lineLimit(1)
            }
            .frame(width: cardSize * 1.12, alignment: .leading)
        }
    }

    private var subtitleText: String {
        if let artist = disc.artistName, !artist.isEmpty {
            return artist
        }
        return "\(disc.trackCount) 首"
    }

    private var sleeveCover: some View {
        Group {
            if let path = fallbackCoverPath, let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("default_cover")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: cardSize, height: cardSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(disc.isLoaded ? WidgetTheme.accent.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 4, x: 0, y: 2)
    }
}

// MARK: - 中号唱片柜组件 (SystemMedium 364×170)

private struct MediumCabinetView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var discs: [WidgetCabinetDiscItem] { snapshot?.cabinetDiscs ?? [] }

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题行: [唱片柜] 演出名 · 数量
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(BSLocalization.text("唱片柜"))
                            .font(.system(size: 9, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(WidgetTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .foregroundStyle(WidgetTheme.accent)

                    Text(snapshot.showName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    HStack(spacing: 2) {
                        Text("\(max(discs.count, 3)) 张唱片")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(WidgetTheme.muted)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(WidgetTheme.dim)
                    }
                }
                .padding(.bottom, 6)

                Spacer(minLength: 0)

                // 中间 3 张并列展示的陈列架
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(displayDiscs.prefix(3)) { disc in
                        CabinetSleeveItemView(
                            disc: disc,
                            fallbackCoverPath: entry.coverImagePath,
                            cardSize: 66
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // 底部立体托梁
                CabinetRackBeamView()
                    .padding(.top, 2)
            }
        } else {
            CabinetEmptyWidgetView()
        }
    }

    private var displayDiscs: [WidgetCabinetDiscItem] {
        if !discs.isEmpty { return discs }
        return [
            WidgetCabinetDiscItem(id: "compilation-01", title: "热门合辑 01", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: true),
            WidgetCabinetDiscItem(id: "compilation-02", title: "热门合辑 02", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-03", title: "热门合辑 03", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false)
        ]
    }
}

// MARK: - 小号唱片柜组件 (SystemSmall 170×170)

private struct SmallCabinetView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var discs: [WidgetCabinetDiscItem] { snapshot?.cabinetDiscs ?? [] }

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题
                HStack(spacing: 3) {
                    Image(systemName: "square.stack.3d.down.right.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(BSLocalization.text("唱片柜"))
                        .font(.system(size: 9, weight: .bold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(WidgetTheme.surfaceRaised)
                .clipShape(Capsule())
                .foregroundStyle(WidgetTheme.accent)

                Spacer(minLength: 4)

                // 2 张叠落陈列的封套
                HStack(alignment: .bottom, spacing: -14) {
                    if let first = displayDiscs.first {
                        CabinetSleeveItemView(
                            disc: first,
                            fallbackCoverPath: entry.coverImagePath,
                            cardSize: 62
                        )
                        .zIndex(2)
                    }
                    if displayDiscs.count > 1 {
                        CabinetSleeveItemView(
                            disc: displayDiscs[1],
                            fallbackCoverPath: entry.coverImagePath,
                            cardSize: 56
                        )
                        .opacity(0.85)
                        .zIndex(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 4)

                // 托梁
                CabinetRackBeamView()

                // 演出名
                Text(snapshot.showName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetTheme.foreground)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
        } else {
            CabinetEmptyWidgetView()
        }
    }

    private var displayDiscs: [WidgetCabinetDiscItem] {
        if !discs.isEmpty { return discs }
        return [
            WidgetCabinetDiscItem(id: "compilation-01", title: "热门合辑 01", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: true),
            WidgetCabinetDiscItem(id: "compilation-02", title: "热门合辑 02", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false)
        ]
    }
}

// MARK: - 大号唱片柜组件 (SystemLarge 364×382)

private struct LargeCabinetView: View {
    let entry: ListeningEntry

    private var snapshot: WidgetListeningSnapshot? { entry.snapshot }
    private var discs: [WidgetCabinetDiscItem] { snapshot?.cabinetDiscs ?? [] }

    var body: some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题
                HStack(alignment: .center, spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(BSLocalization.text("现场唱片柜"))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(WidgetTheme.surfaceRaised)
                    .clipShape(Capsule())
                    .foregroundStyle(WidgetTheme.accent)

                    Text(snapshot.showName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(WidgetTheme.foreground)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(max(discs.count, 6)) 张唱片")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetTheme.muted)
                }
                .padding(.bottom, 12)

                // 第一层陈列架
                shelfRow(discs: Array(displayDiscs.prefix(3)))

                Spacer(minLength: 12)

                // 第二层陈列架
                shelfRow(discs: Array(displayDiscs.dropFirst(3).prefix(3)))
            }
        } else {
            CabinetEmptyWidgetView()
        }
    }

    private func shelfRow(discs: [WidgetCabinetDiscItem]) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(discs) { disc in
                    CabinetSleeveItemView(
                        disc: disc,
                        fallbackCoverPath: entry.coverImagePath,
                        cardSize: 74
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            CabinetRackBeamView()
        }
    }

    private var displayDiscs: [WidgetCabinetDiscItem] {
        if !discs.isEmpty { return discs }
        return [
            WidgetCabinetDiscItem(id: "compilation-01", title: "热门合辑 01", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: true),
            WidgetCabinetDiscItem(id: "compilation-02", title: "热门合辑 02", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-03", title: "热门合辑 03", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-04", title: "热门合辑 04", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-05", title: "热门合辑 05", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false),
            WidgetCabinetDiscItem(id: "compilation-06", title: "热门合辑 06", artistName: nil, coverImageURL: nil, trackCount: 12, isLoaded: false)
        ]
    }
}

// MARK: - 空态视图

private struct CabinetEmptyWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "square.stack.3d.down.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text(BSLocalization.text("唱片柜尚无现场"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetTheme.foreground)
            Text(BSLocalization.text("打开开场前添加现场，唱片柜将自动陈列演出唱片"))
                .font(.system(size: 10))
                .foregroundStyle(WidgetTheme.dim)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
