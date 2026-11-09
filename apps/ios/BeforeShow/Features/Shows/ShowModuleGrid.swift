import SwiftUI

/// 一项内容简单的占半卡，有东西可看的占整行。首页、现场详情、足迹详情共用。
enum ShowModuleWidth: Hashable {
    case half
    case full
}

/// 半卡按顺序两两成对；落单的半卡把后面最近的一张半卡拉上来，实在没有就独占一行。
enum ShowModuleGridLayout {
    enum Row<ID: Hashable>: Hashable {
        case full(ID)
        case pair(ID, ID)
        case single(ID)
    }

    static func rows<ID: Hashable>(_ items: [(ID, ShowModuleWidth)]) -> [Row<ID>] {
        var rows: [Row<ID>] = []
        var used = Set<Int>()
        for (index, item) in items.enumerated() where !used.contains(index) {
            used.insert(index)
            guard item.1 == .half else {
                rows.append(.full(item.0))
                continue
            }
            if let partner = items.indices.first(where: { $0 > index && !used.contains($0) && items[$0].1 == .half }) {
                used.insert(partner)
                rows.append(.pair(item.0, items[partner].0))
            } else {
                rows.append(.single(item.0))
            }
        }
        return rows
    }
}

struct ShowModuleGrid<ID: Hashable, Content: View>: View {
    let items: [(ID, ShowModuleWidth)]
    @ViewBuilder let content: (ID) -> Content

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ShowModuleGridLayout.rows(items), id: \.self) { row in
                switch row {
                case .full(let id), .single(let id):
                    content(id)
                case .pair(let first, let second):
                    HStack(alignment: .top, spacing: 10) {
                        content(first).frame(maxHeight: .infinity)
                        content(second).frame(maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// 首页卡片是磨砂玻璃；详情页是深色底。
enum ShowModuleSurface {
    case glass
    case plain
}

extension View {
    @ViewBuilder
    func showModuleCard(_ surface: ShowModuleSurface, tint: Color? = nil) -> some View {
        switch surface {
        case .glass:
            contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .bsGlassCard(cornerRadius: 20, tint: tint)
        case .plain:
            contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
        }
    }
}

/// 名字、有内容时的状态、一个不上色的动作词。
struct ShowModuleHeader: View {
    let title: String
    var status: String?
    var action: String?
    var emphasizesAction = true
    var titleColor: Color = BSColor.Stage.foreground

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(titleColor)
                if let status {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(BSColor.Stage.muted)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if let action {
                Text(action)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(emphasizesAction ? 0.75 : 0.4))
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// 只有一个状态的半卡：名字和动作在上，淡淡的图标在下。
struct ShowModuleIconCard: View {
    let title: String
    var status: String?
    let action: String
    var emphasizesAction = true
    let iconName: String
    let surface: ShowModuleSurface

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShowModuleHeader(title: title, status: status, action: action, emphasizesAction: emphasizesAction)
            Spacer(minLength: 12)
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(BSColor.Stage.foreground.opacity(0.35))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: .infinity, alignment: .topLeading)
        .showModuleCard(surface)
    }
}

/// 同行：头像叠在一起，没人时只有「我」。
struct ShowCompanionCard: View {
    let names: [String]
    let surface: ShowModuleSurface

    var body: some View {
        let normalized = CompanionNameList.normalized(names)
        VStack(alignment: .leading, spacing: 0) {
            ShowModuleHeader(
                title: BSLocalization.text("同行"),
                status: CompanionNameList.joined(normalized),
                action: normalized.isEmpty ? BSLocalization.text("和谁去") : "›",
                emphasizesAction: normalized.isEmpty
            )
            Spacer(minLength: 12)
            CompanionAvatarStack(names: normalized)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 116, maxHeight: .infinity, alignment: .topLeading)
        .showModuleCard(surface)
    }
}

/// 票根、时刻表就是存一张图：存了贴在卡上，没存是虚线框。
struct ShowAssetPhotoCard: View {
    let kind: ShowAssetKind
    let asset: ShowAsset?
    /// 时刻表已导入成结构化数据但没存图时，不再提示去存。
    var hasContentWithoutImage = false
    var tilt: Double = -4
    let surface: ShowModuleSurface

    private var isEmpty: Bool { asset == nil && !hasContentWithoutImage }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .top) {
                if let asset, let location = try? ShowAssetMediaLocation.applicationSupport() {
                    BSTapedImage(url: location.rootDirectory.appendingPathComponent(asset.relativePath))
                        .frame(width: 92, height: 120)
                        .rotationEffect(.degrees(tilt))
                        .padding(.top, 10)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(red: 0.84, green: 0.77, blue: 0.59).opacity(0.7))
                        .frame(width: 40, height: 13)
                        .rotationEffect(.degrees(tilt * 1.6))
                        .padding(.top, 3)
                } else if hasContentWithoutImage {
                    Image(systemName: kind.iconName)
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(BSColor.Stage.foreground.opacity(0.35))
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 134)
            ShowModuleHeader(
                title: kind.title,
                action: isEmpty ? BSLocalization.text("存一张") : "›",
                emphasizesAction: isEmpty
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .showModuleCard(surface)
    }
}

struct CompanionAvatarStack: View {
    let names: [String]

    private static let maxVisibleOthers = 3
    private static let palettes: [[Color]] = [
        [BSColor.Stage.accent, BSColor.Stage.glowBlue],
        [BSColor.Accent.violet, BSColor.Stage.accent],
        [BSColor.Accent.warm, BSColor.Accent.violet],
        [BSColor.Stage.glowBlue, BSColor.Accent.warm]
    ]

    var body: some View {
        let visible = Array(CompanionNameList.normalized(names).prefix(Self.maxVisibleOthers))
        let overflow = max(0, CompanionNameList.normalized(names).count - visible.count)
        return HStack(spacing: -8) {
            avatar(BSLocalization.text("我"), colors: Self.palettes[0])
            ForEach(Array(visible.enumerated()), id: \.offset) { index, name in
                avatar(initial(name), colors: Self.palettes[(index + 1) % Self.palettes.count])
            }
            if overflow > 0 {
                avatar("+\(overflow)", colors: [BSColor.Stage.muted, BSColor.Stage.dim])
            }
        }
        .accessibilityHidden(true)
    }

    private func initial(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? BSLocalization.text("友") : String(trimmed.prefix(1))
    }

    private func avatar(_ text: String, colors: [Color]) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(BSColor.Stage.background)
            .frame(width: 25, height: 25)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Circle())
            .overlay(Circle().stroke(BSColor.Stage.surface, lineWidth: 2))
    }
}
