import SwiftUI

/// Full-page "long screenshot" of the footprint dashboard for sharing.
/// Laid out at a phone-like width so sections keep their on-screen
/// proportions; `FootprintShareImageExport.renderLong` renders it at 3x
/// so text and edges stay pixel-aligned on a Retina phone.
struct FootprintDashboardExportView: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    static let layoutWidth: CGFloat = 420
    static let exportScale: CGFloat = 3

    private var sections: FootprintDashboardSections {
        FootprintDashboardSections(
            archive: archive,
            covers: covers,
            onShowSelected: { _ in },
            onAdd: {},
            onArchiveVisibilityChange: { _ in },
            isForExport: true
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.035, green: 0.047, blue: 0.078)

            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.20), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: Self.layoutWidth * 0.85
            )

            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.18), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: Self.layoutWidth * 0.75
            )

            VStack(alignment: .leading, spacing: 0) {
                masthead

                PassportCardHeroView(archive: archive, covers: covers)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

               if sections.visibility.showsTrend { sections.trendSection }
               sections.artistSection
               sections.citySection
               sections.venueSection
               sections.memorySection
               sections.timelineSection
                   .padding(.bottom, 16)

               footer
            }
        }
        .frame(width: Self.layoutWidth)
    }

    private var masthead: some View {
        HStack(alignment: .center) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(BSColor.Stage.accent)
                Text("BEFORESHOW · LIVE ARCHIVE")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundColor(BSColor.Stage.accent)
            }
            Spacer()
            Text(BSLocalization.text("我的现场足迹"))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BSColor.Stage.dim)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var footer: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BeforeShow 开场前")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.Stage.foreground)
                Text(BSLocalization.text("走过的现场，慢慢长成你的档案"))
                    .font(.system(size: 9.5))
                    .foregroundColor(BSColor.Stage.dim)
            }
            Spacer()
            Text(footprintFullDateText(Date(), calendar: Calendar.current))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(BSColor.Stage.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 30)
        .padding(.bottom, 32)
    }
}

/// Scrollable, scaled-down preview of the full dashboard export used inside
/// the share sheet.
struct FootprintDashboardExportPreview: View {
    let archive: FootprintArchiveSnapshot
    let covers: [UUID: FootprintCover]

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / FootprintDashboardExportView.layoutWidth
            ScrollView {
                FootprintDashboardExportView(archive: archive, covers: covers)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { contentHeight = $0.height }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(
                        width: geometry.size.width,
                        height: contentHeight * scale,
                        alignment: .topLeading
                    )
            }
        }
    }
}
