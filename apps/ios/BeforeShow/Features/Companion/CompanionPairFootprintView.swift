import SwiftUI

/// Every footprint shared with one person, whoever else came (ADR 0027 name matching).
@MainActor
struct CompanionPairFootprintView: View {
    let companionName: String
    let shows: [Show]

    private var archive: FootprintArchiveSnapshot {
        FootprintArchiveBuilder.make(shows: shows)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: BSSpacing.lg) {
                relationshipHeader

                if shows.isEmpty {
                    Text(BSLocalization.text("散场后，你们一起看过的现场会出现在这里。"))
                        .font(BSFont.caption)
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(BSSpacing.lg)
                        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
                } else {
                    VStack(spacing: BSSpacing.sm) {
                        ForEach(shows) { show in
                            NavigationLink {
                                FootprintDetailView(show: show, archive: archive)
                            } label: {
                                relationshipShowRow(show)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, BSSpacing.roomy)
            .padding(.top, BSSpacing.md)
            .padding(.bottom, BSLayout.tabBarContentInset)
        }
        .background(CurrentShowStageBackground().ignoresSafeArea())
        .navigationTitle(BSLocalization.format("与%@的共同足迹", companionName))
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }

    private var relationshipHeader: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text("TOGETHER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(BSColor.Stage.accent)

            Text(BSLocalization.format("我和%@一起看过 %lld 场现场", companionName, Int64(shows.count)))
                .font(BSFont.V3.title2)
                .foregroundStyle(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BSSpacing.sm) {
                avatar(name: BSLocalization.text("我"), initial: BSLocalization.text("我"))
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.accent)
                avatar(name: companionName, initial: String(companionName.prefix(1)))
            }
            .padding(.top, BSSpacing.xs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.lg)
        .background(
            LinearGradient(
                colors: [BSColor.Stage.accent.opacity(0.14), BSColor.Stage.surface],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(BSColor.Stage.accent.opacity(0.2)))
    }

    private func avatar(name: String, initial: String) -> some View {
        HStack(spacing: 7) {
            Text(initial)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(BSColor.Stage.background)
                .frame(width: 28, height: 28)
                .background(BSColor.Stage.accent, in: Circle())
            Text(name)
                .font(BSFont.caption.weight(.semibold))
                .foregroundStyle(BSColor.Stage.foreground)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func relationshipShowRow(_ show: Show) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BSColor.Stage.accent)
                .frame(width: 34, height: 34)
                .background(BSColor.Stage.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(BSFont.headline)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(relationshipShowMetadata(show))
                    .font(BSFont.V3.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BSColor.Stage.dim)
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func relationshipShowMetadata(_ show: Show) -> String {
        let date = BSDateFormat.dottedDate(show.effectiveDate, calendar: show.timingCalendar())
        return [date, FootprintTextNormalizer.nonEmptyTrimmed(show.city)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
