import SwiftData
import SwiftUI

/// Every kind of record earns a pin in bronze, silver and gold. New pins drop onto the board once.
struct FootprintBadgeWallView: View {
    let archive: FootprintArchiveSnapshot

    @Query private var setlist: [ShowSetlistMemory]
    @Query private var merch: [MerchItem]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var newIDs: Set<String> = []
    @State private var dropped = false
    @State private var drops = 0

    @Environment(\.footprintBadgeDefaults) private var badgeDefaults
    private var seenStore: FootprintBadgeSeenStore { FootprintBadgeSeenStore(defaults: badgeDefaults) }

    private var badges: [FootprintBadge] {
        FootprintBadgeCatalog.badges(FootprintBadgeCatalog.facts(archive: archive, memories: setlist, merch: merch, fragments: fragments, assets: assets))
    }

    var body: some View {
        let badges = badges
        let selected = badges.first { $0.id == selectedID } ?? badges.first
        let earnedTiers = badges.reduce(0) { $0 + $1.tier }
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 22) {
                ForEach(Array(badges.enumerated()), id: \.element.id) { index, badge in
                    pinButton(badge, index: index, isSelected: badge.id == selected?.id)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 24)
            .bsAdaptiveContentWidth()
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            if let selected { card(selected).id(selected.id).transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 14))) }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.85), value: selected?.id)
        .background { FootprintBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                FootprintArchiveTitle(
                    title: BSLocalization.text("徽章"),
                    subtitle: BSLocalization.format("%1$lld / %2$lld 枚", earnedTiers, FootprintBadgeFamily.allCases.count * 3)
                )
            }
        }
        .sensoryFeedback(.selection, trigger: selectedID)
        .sensoryFeedback(.impact(flexibility: .rigid, intensity: 0.8), trigger: drops)
        .task { await dropNewPins(badges) }
    }

    /// Unseen tiers start above the board and fall into place one by one, then count as seen.
    private func dropNewPins(_ badges: [FootprintBadge]) async {
        guard !dropped else { return }
        newIDs = seenStore.unseen(in: badges)
        seenStore.markSeen(badges)
        let newFamilies = badges.filter { badge in badge.earnedTierIDs.contains(where: newIDs.contains) }
        if let first = newFamilies.first { selectedID = first.id }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        guard !reduceMotion else { return }
        for _ in newFamilies.prefix(4) {
            drops += 1
            try? await Task.sleep(for: .milliseconds(120))
        }
    }

    private func isNew(_ badge: FootprintBadge) -> Bool {
        badge.earnedTierIDs.contains(where: newIDs.contains)
    }

    private func pinButton(_ badge: FootprintBadge, index: Int, isSelected: Bool) -> some View {
        let falling = isNew(badge) && !dropped
        return Button { selectedID = badge.id } label: {
            VStack(spacing: 8) {
                FootprintBadgePin(badge: badge, size: 78, isSelected: isSelected)
                    .overlay(alignment: .topTrailing) {
                        if isNew(badge) {
                            Text(BSLocalization.text("新"))
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(BSColor.Stage.background)
                                .padding(.horizontal, 6)
                                .frame(height: 16)
                                .background(BSColor.Stage.accent, in: Capsule())
                                .offset(x: 4, y: -2)
                        }
                    }
                    .offset(y: falling && !reduceMotion ? -60 : 0)
                    .opacity(falling ? 0 : 1)
                    .animation((reduceMotion ? Animation.easeOut(duration: 0.3) : .spring(response: 0.5, dampingFraction: 0.55)).delay(Double(index % 6) * 0.06), value: dropped)
                Text(badge.family.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(badge.isEarned ? BSColor.Stage.foreground : BSColor.Stage.muted)
                    .lineLimit(1)
                Text(badge.isMaxed ? BSLocalization.text("满级") : BSLocalization.format("还差 %lld", badge.remaining))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility(badge))
    }

    private func accessibility(_ badge: FootprintBadge) -> String {
        badge.isEarned
            ? BSLocalization.format("%1$@，第 %2$lld 档", badge.family.title, badge.tier)
            : BSLocalization.format("%1$@，未解锁", badge.family.title)
    }

    private func card(_ badge: FootprintBadge) -> some View {
        FootprintArchiveCard {
            HStack(alignment: .firstTextBaseline) {
                Text(badge.family.title)
                    .font(.system(size: 20, weight: .black, design: .serif))
                    .foregroundStyle(BSColor.Stage.foreground)
                Spacer(minLength: 8)
                Text(BSLocalization.format("%lld / %lld", badge.tier, badge.family.targets.count))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(BSColor.Stage.accent)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(badge.family.targets.enumerated()), id: \.offset) { index, target in
                    let done = badge.progress >= target
                    HStack(spacing: 10) {
                        Circle()
                            .fill(done ? FootprintRoomPalette.badgeMetals[index] : FootprintRoomPalette.badgeLocked)
                            .frame(width: 10, height: 10)
                        Text(badge.family.requirement(target))
                            .font(.system(size: 13))
                            .foregroundStyle(BSColor.Stage.foreground.opacity(done ? 0.9 : 0.5))
                        Spacer(minLength: 8)
                        if done {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(BSColor.Stage.foreground.opacity(0.6))
                        } else if target == badge.nextTarget {
                            Text("\(badge.progress)/\(target)")
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(BSColor.Stage.foreground.opacity(0.5))
                        }
                    }
                }
            }
            .padding(.top, 12)
        }
    }
}

/// One enamel pin: metal rim by tier, a progress arc toward the next tier, the record's glyph in the middle.
struct FootprintBadgePin: View {
    let badge: FootprintBadge
    var size: CGFloat = 78
    var isSelected = false

    var body: some View {
        let metal = badge.isEarned ? FootprintRoomPalette.badgeMetals[badge.tier - 1] : FootprintRoomPalette.badgeLocked
        ZStack {
            Circle()
                .fill(badge.isEarned
                      ? AnyShapeStyle(LinearGradient(colors: [metal, metal.opacity(0.55), metal], startPoint: .topLeading, endPoint: .bottomTrailing))
                      : AnyShapeStyle(FootprintRoomPalette.badgeLocked))
            Circle()
                .fill(FootprintRoomPalette.badgeEnamel)
                .padding(size * 0.09)
            if !badge.isMaxed {
                Circle()
                    .trim(from: 0, to: badge.fraction)
                    .stroke(BSColor.Stage.accent.opacity(0.85), style: StrokeStyle(lineWidth: size * 0.035, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(size * 0.14)
            }
            Image(systemName: badge.family.symbol)
                .font(.system(size: size * 0.3, weight: .semibold))
                .foregroundStyle(badge.isEarned ? metal : BSColor.Stage.dim)
            if badge.tier == 3 {
                FootprintHologramSheen(phase: 0.5).clipShape(Circle()).opacity(0.6)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.55), radius: 8, y: 6)
        .scaleEffect(isSelected ? 1.06 : 1)
        .accessibilityHidden(true)
    }
}
