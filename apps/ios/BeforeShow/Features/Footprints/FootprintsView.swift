import SwiftData
import SwiftUI

// MARK: - Footprints Root Presentation

struct FootprintsView: View {
    var onArchiveVisibilityChange: (Bool) -> Void = { _ in }
    /// 外部 push 入口：仪式结束（散场卡生成/跳过 share）后由 RootView 写入，
    /// FootprintsView 在 onChange 时把它转成本地 `detailTarget` 触发 push。
    /// 双向但只读外部更安全 —— 内部源仍是本视图状态。
    var pendingDetailTarget: FootprintDetailDestination?
    @Query(sort: \Show.date) private var shows: [Show]
    @Query private var selections: [CurrentShowSelection]
    @Query private var fragments: [MemoryFragment]
    @Query private var assets: [ShowAsset]
    @State private var isAddingShow = false
    @State private var detailTarget: FootprintDetailDestination?
    @State private var activeSheet: FootprintSheet?
    @State private var toast: BSToastPayload?
    @State private var prepared: PreparedFootprint?
    private let currentShowSession = CurrentShowSession()

    var body: some View {
        NavigationStack {
            if let prepared {
                timelineContent(
                    prepared,
                    hasCurrentShow: currentShowSession.selectCurrentShow(
                        from: shows,
                        manualSelection: selections.first
                    ) != nil
                )
            } else {
                FootprintPreparingView()
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .task(id: preparationFingerprint()) {
            // Build archive + covers in one pass, then commit atomically so
            // the dashboard's first paint already has the cover it ends with.
            // (Previously the two pieces landed in two `@State` writes and
            // produced a visible two-stage layout jump on cold start.)
            let archive = FootprintArchiveBuilder.make(shows: shows)
            let covers = FootprintCoverResolver.resolve(
                shows: archive.shows,
                fragments: fragments,
                assets: assets
            )
            prepared = PreparedFootprint(archive: archive, covers: covers)
        }
        .onChange(of: pendingDetailTarget) { _, newValue in
            if let newValue, shows.contains(where: { $0.id == newValue.id }) {
                detailTarget = newValue
            }
        }
    }

    private func timelineContent(
        _ prepared: PreparedFootprint,
        hasCurrentShow: Bool
    ) -> some View {
        let archive = prepared.archive
        let covers = prepared.covers
        return ZStack {
            FootprintBackground()
            if archive.shows.isEmpty {
                FootprintEmptyView(
                    content: FootprintEmptyStateCopy.content(hasCurrentShow: hasCurrentShow),
                    onAdd: { isAddingShow = true }
                )
            } else {
                content(prepared)
            }
        }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $detailTarget) { target in
                FootprintDetailView(
                    show: target.show,
                    archive: archive,
                    onDetailVisibilityChange: onArchiveVisibilityChange
                )
            }
            .sheet(isPresented: $isAddingShow) {
                AddShowCoordinatorSheet()
                .presentationDetents([.large])
                .presentationCornerRadius(26)
                .presentationDragIndicator(.visible)
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .search:
                    FootprintSearchSheet(archive: archive, covers: covers) { show in
                        activeSheet = nil
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(280))
                            detailTarget = .init(show: show)
                        }
                    }
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                case .share:
                    FootprintShareSheet(
                        archive: archive,
                        covers: covers,
                        onSaved: { presentToast(BSLocalization.text("足迹图片已保存")) }
                    )
                    .presentationDetents([.large])
                    .presentationCornerRadius(26)
                    .presentationDragIndicator(.visible)
                }
            }
            .bsToastOverlay(toast, bottomPadding: 100)
    }

    private func content(_ prepared: PreparedFootprint) -> some View {
        return FootprintDashboardView(
            archive: prepared.archive,
            covers: prepared.covers,
            onShowSelected: { detailTarget = FootprintDetailDestination(show: $0) },
            onAdd: { isAddingShow = true },
            onSearch: { activeSheet = .search },
            onShare: {
                activeSheet = .share
            },
            onArchiveVisibilityChange: onArchiveVisibilityChange
        )
    }

    private func preparationFingerprint() -> FootprintsPreparationFingerprint {
        FootprintsPreparationFingerprint.make(
            shows: shows,
            fragments: fragments,
            assets: assets
        )
    }


    private func presentToast(_ message: String) {
        let payload = BSToastPayload(tone: .success, message: message)
        toast = payload
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if toast == payload { toast = nil }
        }
    }

}

private enum FootprintSheet: String, Identifiable {
    case search
    case share
    var id: String { rawValue }
}

private struct FootprintPreparingView: View {
    var body: some View {
        ZStack {
            FootprintBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    passportShell
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
        }
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack {
            Text(BSLocalization.text("足迹"))
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                shellHeaderIcon("plus")
                shellHeaderIcon("magnifyingglass")
                shellHeaderIcon("square.and.arrow.up")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, BSLayout.pageHeaderTopPadding)
    }

    private func shellHeaderIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(BSColor.Stage.foreground.opacity(0.55))
            .frame(width: BSLayout.minTouchTarget, height: BSLayout.minTouchTarget)
            .background(Color.white.opacity(0.07), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var passportShell: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            HStack(alignment: .center, spacing: BSSpacing.roomy) {
                RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                    .fill(Color.white.opacity(0.055))
                    .frame(width: 78, height: 104)
                    .overlay(
                        RoundedRectangle(cornerRadius: BSRadius.md, style: .continuous)
                            .stroke(BSColor.Stage.accent.opacity(0.12), lineWidth: 0.75)
                    )
                    .padding(.leading, 6)
                    .padding(.trailing, 2)

                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(BSColor.Stage.accent.opacity(0.16))
                        .frame(width: 118, height: 34)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.white.opacity(0.055))
                        .frame(width: 148, height: 12)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(BSColor.Stage.accent.opacity(0.10))
                        .frame(width: 104, height: 11)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: BSSpacing.sm) {
                metricShell
                metricShell
                metricShell
            }
        }
        .padding(BSSpacing.roomy)
        .background(shellBackground)
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            BSColor.Stage.accent.opacity(0.22),
                            BSColor.Stage.border,
                            BSColor.Stage.glowBlue.opacity(0.12)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
    }

    private var metricShell: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(BSColor.Stage.accent.opacity(0.13))
                .frame(width: 34, height: 19)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 48, height: 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shellBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [BSColor.Stage.surfaceRaised, BSColor.Stage.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RadialGradient(
                colors: [BSColor.Stage.accent.opacity(0.10), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 190
            )
            RadialGradient(
                colors: [BSColor.Stage.glowBlue.opacity(0.07), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 220
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg, style: .continuous))
    }
}

struct FootprintBackground: View {
    var body: some View {
        ZStack {
            BSColor.Stage.background
            RadialGradient(colors: [BSColor.Stage.glowBlue.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 330)
            RadialGradient(colors: [BSColor.Stage.accent.opacity(0.09), .clear], center: .topTrailing, startRadius: 0, endRadius: 300)
        }
        .ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct FootprintEmptyView: View {
    let content: FootprintEmptyStateCopy.Content
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer()

            Image(systemName: "flag")
                .font(.system(size: 34, weight: .light))
                .foregroundColor(BSColor.Stage.accent)
                .frame(width: 80, height: 80)
                .background(Color.white.opacity(0.045), in: Circle())
                .overlay(Circle().stroke(BSColor.Stage.border))

            Text(content.title)
                .font(BSFont.heroTitle)
                .tracking(BSFont.titleTracking)
                .foregroundColor(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)

            Text(content.message)
                .font(BSFont.body)
                .foregroundColor(BSColor.Stage.muted)
                .multilineTextAlignment(.center)

            Button(action: onAdd) {
                Text(content.actionTitle ?? BSLocalization.text("添加现场"))
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(BSColor.Stage.background)
                    .frame(width: BSLayout.emptyStateActionWidth, height: BSLayout.emptyStateActionHeight)
                    .background(BSColor.Stage.foreground, in: RoundedRectangle(cornerRadius: 16))
                    .contentShape(RoundedRectangle(cornerRadius: 16))
            }
                .padding(.top, BSSpacing.sm)

            Spacer()
        }
        .padding(.horizontal, BSSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            Text(BSLocalization.text("足迹"))
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.5)
                .foregroundColor(BSColor.Stage.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, BSLayout.pageHeaderTopPadding)
        }
    }
}
