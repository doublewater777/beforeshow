import SwiftUI

@MainActor
enum CompanionPairHistory {
    static func shows(
        with companionName: String,
        from candidates: [Show],
        now: Date = Date()
    ) -> [Show] {
        let normalizedName = companionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { return [] }

        return candidates
            .filter { show in
                guard show.changeStatus != .canceled,
                      show.companionStatus == .confirmed,
                      CompanionNameList.normalized(show.companionNames).contains(normalizedName) else {
                    return false
                }
                let kind = CurrentShowTimeState(show: show, now: now).kind
                return kind == .postShow || kind == .ended
            }
            .sorted { lhs, rhs in
                if lhs.effectiveDate == rhs.effectiveDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.effectiveDate > rhs.effectiveDate
            }
    }
}

@MainActor
struct CompanionPairFootprintView: View {
    let companionName: String
    let shows: [Show]

    @State private var isShowingShareSheet = false

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
                        .foregroundColor(BSColor.Stage.muted)
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

                    Button {
                        isShowingShareSheet = true
                    } label: {
                        Label(BSLocalization.text("分享共同足迹卡"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BSPrimaryButtonStyle())
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
        .sheet(isPresented: $isShowingShareSheet) {
            if let representative = shows.first {
                CompanionFootprintShareSheet(
                    show: representative,
                    sharedHistory: shows,
                    companionName: companionName
                )
            }
        }
    }

    private var relationshipHeader: some View {
        VStack(alignment: .leading, spacing: BSSpacing.sm) {
            Text(BSLocalization.text("TOGETHER"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundColor(BSColor.Stage.accent)

            Text(BSLocalization.format("我和%@一起看过 %lld 场现场", companionName, Int64(shows.count)))
                .font(BSFont.V3.title2)
                .foregroundColor(BSColor.Stage.foreground)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: BSSpacing.sm) {
                avatar(name: BSLocalization.text("我"), initial: BSLocalization.text("我"))
                Image(systemName: "link")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColor.Stage.accent)
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
                .foregroundColor(BSColor.Stage.background)
                .frame(width: 28, height: 28)
                .background(BSColor.Stage.accent, in: Circle())
            Text(name)
                .font(BSFont.caption.weight(.semibold))
                .foregroundColor(BSColor.Stage.foreground)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    private func relationshipShowRow(_ show: Show) -> some View {
        HStack(spacing: BSSpacing.compact) {
            Image(systemName: "music.note")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 34, height: 34)
                .background(BSColor.Stage.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(show.name)
                    .font(BSFont.headline)
                    .foregroundColor(BSColor.Stage.foreground)
                    .lineLimit(1)
                Text(relationshipShowMetadata(show))
                    .font(BSFont.V3.caption)
                    .foregroundColor(BSColor.Stage.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(BSColor.Stage.dim)
        }
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(RoundedRectangle(cornerRadius: BSRadius.v3Medium).stroke(BSColor.Stage.border))
    }

    private func relationshipShowMetadata(_ show: Show) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = show.timingCalendar()
        formatter.timeZone = formatter.calendar.timeZone
        formatter.dateFormat = "yyyy.MM.dd"
        let date = formatter.string(from: show.effectiveDate)
        return [date, FootprintTextNormalizer.nonEmptyTrimmed(show.city)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
