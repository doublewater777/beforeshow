import SwiftUI

struct FootprintDashboardView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]
    let onShowSelected: (Show) -> Void
    let onAdd: () -> Void
    let onSearch: () -> Void
    let onShare: () -> Void
    let onArchiveVisibilityChange: (Bool) -> Void

    private var sections: FootprintDashboardSections {
        FootprintDashboardSections(
            archive: archive,
            covers: covers,
            onShowSelected: onShowSelected,
            onAdd: onAdd,
            onArchiveVisibilityChange: onArchiveVisibilityChange
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                header
                hero
                if sections.visibility.showsTrend {
                    sections.trendSection
                }
                sections.artistSection
                sections.citySection
                sections.venueSection
                sections.memorySection
                sections.timelineSection
            }
            .padding(.bottom, BSLayout.compactChromeContentInset)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private var header: some View {
        HStack {
            Text(BSLocalization.text("足迹"))
                .font(BSFont.pageTitle)
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                dashboardIcon("plus", label: BSLocalization.text("添加现场"), action: onAdd)
                dashboardIcon("magnifyingglass", label: BSLocalization.text("搜索足迹"), action: onSearch)
                dashboardIcon("square.and.arrow.up", label: BSLocalization.text("分享足迹"), action: onShare)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }

    private func dashboardIcon(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(BSColor.Stage.foreground)
                .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
                .background(Color.white.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var hero: some View {
        PassportCardHeroView(archive: archive, covers: covers)
            .padding(.horizontal, 20)
            .padding(.top, 16)
    }

    private func dashboardMetric(_ value: Int, _ label: String) -> some View { dashboardMetric("\(value)", label) }

    private func dashboardMetric(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(.system(size: 16, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(.system(size: 11)).foregroundColor(BSColor.Stage.muted)
        }
    }

    private var statsSection: some View {
        HStack(spacing: 8) {
            footprintStat(value: archive.artistArchiveItems.count, label: BSLocalization.text("看过的艺人"))
            footprintStat(value: archive.cityArchiveItems.count, label: BSLocalization.text("去过的城市"))
            footprintStat(value: archive.venueArchiveItems.count, label: BSLocalization.text("到过的场馆"))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func footprintStat(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)").font(.system(size: 20, weight: .semibold)).foregroundColor(BSColor.Stage.foreground)
            Text(label).font(.system(size: 10)).foregroundColor(BSColor.Stage.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BSColor.Stage.border))
    }
}
