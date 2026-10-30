import SwiftUI

struct ListeningDiscPickSheet: View {
    let disc: ListeningDisc?
    let show: Show?
    let canConfirm: Bool
    let canRedraw: Bool
    let exhausted: Bool
    let onConfirm: () -> Void
    let onRedraw: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var slideDirection: CGFloat = 1
    @State private var iconRotation: Double = 0

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let contentWidth = max(proxy.size.width - BSSpacing.lg * 2, 0)
                let coverSize = min(contentWidth * 0.82, 300)

                Group {
                    if exhausted || disc == nil {
                        exhaustedContent
                    } else if let disc {
                        discContent(disc, coverSize: coverSize)
                    }
                }
                .padding(.horizontal, BSSpacing.lg)
                .padding(.top, BSSpacing.roomy)
                .padding(.bottom, BSSpacing.lg)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background(ListeningSheetBackground(tint: BSColor.Stage.accent, intensity: BSListeningTokens.sheetGlowOpacity))
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭")) {
                    onClose()
                }
            }
        }
    }

    @ViewBuilder
    private func discContent(_ disc: ListeningDisc, coverSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(ListeningCopy.text("帮我挑一张"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.bottom, BSSpacing.roomy)

            Spacer(minLength: BSSpacing.sm)

            ZStack {
                Circle()
                    .fill(BSColor.Stage.accent.opacity(0.14))
                    .frame(width: coverSize * 1.12, height: coverSize * 1.12)
                    .blur(radius: 28)

                ListeningDiscCover(disc: disc, show: show)
                    .frame(width: coverSize, height: coverSize)
                    .overlay { ListeningJewelCaseFinish() }
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 8)
                    .shadow(color: BSColor.Stage.accent.opacity(0.12), radius: 26, y: 0)
                    .id(disc.id)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .offset(x: slideDirection * 70).combined(with: .opacity).combined(with: .scale(scale: 0.94)),
                                removal: .offset(x: -slideDirection * 70).combined(with: .opacity).combined(with: .scale(scale: 0.94))
                            )
                    )
                    .offset(x: dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset / 26)))
                    .scaleEffect(1.0 - min(abs(dragOffset) / 2500, 0.04))
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                guard canRedraw else { return }
                                dragOffset = value.translation.width
                            }
                            .onEnded { value in
                                handleDragEnd(value)
                            }
                    )
                    .accessibilityIdentifier("listening.pickDisc.cover")
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, BSSpacing.md)

            VStack(spacing: BSSpacing.xs) {
                Text(disc.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .id("title-\(disc.id)")
                    .transition(.opacity)

                if !disc.artistNames.isEmpty {
                    Text(disc.artistNames.joined(separator: " / "))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(BSColor.Stage.foreground.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .id("artist-\(disc.id)")
                        .transition(.opacity)
                }

                if let meta = metadataSubtitle(for: disc) {
                    Text(meta)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(BSColor.Stage.muted)
                        .multilineTextAlignment(.center)
                        .padding(.top, 2)
                        .id("meta-\(disc.id)")
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, BSSpacing.lg)

            Spacer(minLength: BSSpacing.sm)

            VStack(spacing: BSSpacing.sm) {
                Button(BSLocalization.text("装入播放机"), action: onConfirm)
                    .buttonStyle(BSListeningActionStyle())
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("listening.pickDisc.confirm")

                if canRedraw {
                    Button(action: handleRedrawTap) {
                        HStack(spacing: BSSpacing.xs) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .rotationEffect(.degrees(iconRotation))
                            Text(ListeningCopy.text("换一张"))
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(BSColor.Stage.muted)
                        .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BSListeningPressStyle())
                    .accessibilityIdentifier("listening.pickDisc.redraw")
                }
            }
        }
    }

    private var exhaustedContent: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer(minLength: BSSpacing.xl)
            Image(systemName: "square.stack")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(BSColor.Stage.muted)
            Text(ListeningCopy.text("这排柜子暂时没有可挑的唱片"))
                .font(BSListeningTokens.headline)
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)
            Button(BSLocalization.text("好"), action: onClose)
                .buttonStyle(BSListeningActionStyle())
            Spacer(minLength: BSSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private func metadataSubtitle(for disc: ListeningDisc) -> String? {
        var items: [String] = []
        if !disc.genreNames.isEmpty {
            items.append(disc.genreNames.joined(separator: " · "))
        }
        if let releaseDate = disc.releaseDate {
            items.append(releaseDate.formatted(.dateTime.year()))
        }
        if !disc.tracks.isEmpty {
            items.append(BSLocalization.format("%d 首歌曲", disc.tracks.count))
        }
        return items.isEmpty ? nil : items.joined(separator: " · ")
    }

    private func handleRedrawTap() {
        guard canRedraw else { return }
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        slideDirection = 1
        withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
            iconRotation += 360
        }
        onRedraw()
    }

    private func handleDragEnd(_ value: DragGesture.Value) {
        guard canRedraw else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                dragOffset = 0
            }
            return
        }
        let horizontalDistance = value.translation.width
        let velocity = value.velocity.width
        let shouldRedraw = abs(horizontalDistance) > 70 || abs(velocity) > 350

        if shouldRedraw {
            slideDirection = horizontalDistance < 0 ? 1 : -1
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                dragOffset = horizontalDistance < 0 ? -120 : 120
            }
            onRedraw()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                dragOffset = 0
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                dragOffset = 0
            }
        }
    }
}
