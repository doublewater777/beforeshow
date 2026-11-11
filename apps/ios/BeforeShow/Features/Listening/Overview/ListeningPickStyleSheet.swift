import SwiftUI

/// Picks how 帮我挑一张 lays out the albums, each style shown with the user's own covers.
struct ListeningPickStyleSheet: View {
    let discs: [ListeningDisc]
    let show: Show
    let currentID: String?
    let current: ListeningPickStyle
    /// Free trial opens left for the Pro styles; nil for Pro.
    let trialLeft: Int?
    /// A Pro style can't be chosen: the trial is used up and this open didn't count towards it.
    let isLocked: Bool
    let onChoose: (ListeningPickStyle) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingPaywall = false

    private var position: Double { Double(discs.firstIndex { $0.id == currentID } ?? 0) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: BSSpacing.md)], spacing: BSSpacing.xl) {
                    ForEach(ListeningPickStyle.available()) { style in
                        option(style)
                    }
                }
                .padding(BSSpacing.roomy)
            }
            .background(BSColor.Stage.background.ignoresSafeArea())
            .navigationTitle(ListeningCopy.text("样式"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) { dismiss() }
            }
        }
        .tint(BSColor.Stage.foreground)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $isShowingPaywall) { ProPaywallView() }
    }

    private func option(_ style: ListeningPickStyle) -> some View {
        let locked = style.isPro && isLocked
        let isCurrent = style == current
        return Button {
            if locked {
                isShowingPaywall = true
            } else {
                onChoose(style)
                dismiss()
            }
        } label: {
            VStack(alignment: .leading, spacing: BSSpacing.sm) {
                preview(style)
                    .aspectRatio(0.68, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(isCurrent ? BSColor.Stage.foreground : .white.opacity(0.12), lineWidth: isCurrent ? 2 : 0.5)
                    }
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .frame(width: 28, height: 28)
                                .background(Circle().fill(.black.opacity(0.45)))
                                .padding(BSSpacing.sm)
                        }
                    }
                HStack(spacing: BSSpacing.xs) {
                    Text(style.title).font(.system(size: 15, weight: .bold, design: .rounded))
                    if isCurrent {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                    }
                }
                Text(badge(locked: locked))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(BSColor.Stage.foreground.opacity(0.6))
                    .opacity(style.isPro ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func badge(locked: Bool) -> String {
        guard let trialLeft, !locked else { return "PRO" }
        return ListeningCopy.format("免费试用，剩 %lld 次", trialLeft)
    }

    @ViewBuilder
    private func preview(_ style: ListeningPickStyle) -> some View {
        if style == .feed {
            feedPreview
        } else {
            ZStack {
                ListeningPickShelfBackdrop()
                StylePreviewStage(style: style, discs: discs, show: show, position: position)
            }
            .allowsHitTesting(false)
        }
    }

    /// One album filling the screen, the way 一屏一张 opens.
    private var feedPreview: some View {
        GeometryReader { proxy in
            let disc = discs.first { $0.id == currentID } ?? discs.first
            let cover = proxy.size.width * 0.72
            ZStack(alignment: .bottomLeading) {
                BSColor.Stage.background
                if let disc {
                    ListeningArtwork(url: disc.artworkURL, title: disc.title)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: 24)
                        .opacity(0.6)
                    LinearGradient(colors: [.clear, BSColor.Stage.background.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    ListeningArtwork(url: disc.artworkURL, title: disc.title)
                        .frame(width: cover, height: cover)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: 12, y: 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, proxy.size.height * 0.2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(disc.displayArtistName(for: show))
                            .font(ListeningOverviewStyle.caps(8)).tracking(1.2).textCase(.uppercase)
                            .foregroundStyle(BSColor.Stage.accent)
                        Text(disc.title).font(ListeningOverviewStyle.serif(17)).lineLimit(2)
                    }
                    .padding(BSSpacing.md)
                    .padding(.bottom, proxy.size.height * 0.06)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
    }
}

/// A shelf style playing its opening once, so each preview shows how it moves.
private struct StylePreviewStage: View {
    let style: ListeningPickStyle
    let discs: [ListeningDisc]
    let show: Show
    let position: Double

    @State private var start: Date?
    @State private var isDone = false
    private let duration = 1.6
    /// The 3D preview runs in past a few dozen albums, like the shelf's own opening.
    private var run: Double { min(30, Double(discs.count - 1) - position) }

    var body: some View {
        TimelineView(.animation(paused: isDone)) { context in
            let entrance = start.map { min(1, context.date.timeIntervalSince($0) / duration) } ?? 0
            ListeningPickShelfStage(
                style: style, discs: discs, show: show,
                position: style == .shelf3D ? position + run * (1 - ListeningPickShelfStage.openingRun(entrance)) : position,
                entrance: entrance,
                onReady: { if start == nil { start = .now } }
            )
        }
        // The 3D shelf starts once RealityKit reports ready; the drawn shelves start straight away.
        .onAppear { if style != .shelf3D { start = .now } }
        .task(id: start) {
            guard start != nil else { return }
            try? await Task.sleep(for: .seconds(duration + 0.1))
            isDone = true
        }
    }
}
