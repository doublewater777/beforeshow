import SwiftUI

/// Ticket and timetable taped onto cards, with the record rows underneath. Show detail and
/// footprint detail use this same block, so one show looks the same on both pages.
struct ShowKeepsakeSection: View {
    let title: String
    let show: Show
    let entries: [ShowAssetManagementEntry]
    let assetFor: (ShowAssetKind) -> ShowAsset?
    let recordKinds: [CurrentShowRecordKind]
    var recordPhase: HomeShowPhase = .ended
    let onSelect: (ShowAssetKind) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
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
            if !recordKinds.isEmpty {
                ShowRecordRows(show: show, kinds: recordKinds, phase: recordPhase)
                    .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.07)))
            }
        }
    }

    private func card(_ entry: ShowAssetManagementEntry, tilt: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let asset = assetFor(entry.kind), let location = try? ShowAssetMediaLocation.applicationSupport() {
                    BSTapedImage(url: location.rootDirectory.appendingPathComponent(asset.relativePath))
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

/// Who came along. Footprint detail adds how many nights you have shared; an upcoming show has none yet.
struct ShowCompanionSection: View {
    let names: [String]
    var sharedCount: ((String) -> Int)?
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.compact) {
            Text(BSLocalization.text("同行"))
                .font(FootprintDetailTokens.sectionFont)
                .foregroundStyle(BSColor.Stage.foreground)
            Button(action: onEdit) {
                VStack(spacing: 8) {
                    if names.isEmpty {
                        emptyRow
                    }
                    ForEach(Array(names.enumerated()), id: \.offset) { _, name in
                        companionRow(name: name, count: sharedCount?(name))
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyRow: some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(BSColor.Stage.muted)
                .frame(width: FootprintDetailTokens.avatarSize, height: FootprintDetailTokens.avatarSize)
            Text(BSLocalization.text("和谁去"))
                .font(BSFont.headline)
                .foregroundStyle(BSColor.Stage.muted)
            Spacer()
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func companionRow(name: String, count: Int?) -> some View {
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
                if let count {
                    Text(BSLocalization.format("共同留下 %lld 场足迹", count))
                        .font(BSFont.V3.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                }
            }
            Spacer()
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }
}
