import SwiftUI

struct ListeningDiscPickSheet: View {
    let disc: ListeningDisc?
    let nextDisc: ListeningDisc?
    let previousDisc: ListeningDisc?
    let show: Show?
    @Binding var filter: ListeningDiscPickFilter
    let canConfirm: Bool
    let canRedraw: Bool
    let exhausted: Bool
    let onConfirm: () -> Void
    let onRedraw: () -> Void
    let onPrevious: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGSize = .zero
    @State private var isCommitting = false
    @State private var iconRotation: Double = 0

    var body: some View {
        NavigationStack {
            Group {
                if exhausted || disc == nil {
                    exhaustedContent
                        .padding(.horizontal, BSSpacing.roomy)
                } else if let disc {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            GeometryReader { deck in
                                cardDeck(disc, size: deck.size)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            actionSection(width: proxy.size.width)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if let disc {
                    ListeningDiscBackdrop(
                        artworkURL: disc.artworkURL,
                        tint: ListeningSleeveIdentity(disc: disc).color
                    )
                    .id(disc.id)
                    .transition(.opacity)
                } else {
                    ListeningSheetBackground()
                }
            }
            .navigationTitle(ListeningCopy.text("帮我挑一张"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                BSChromeToolbarCloseButton(accessibilityLabel: BSLocalization.text("关闭"), placement: .topBarLeading) {
                    onClose()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker(ListeningCopy.text("筛选唱片"), selection: $filter) {
                            ForEach(ListeningDiscPickFilter.allCases, id: \.self) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    } label: {
                        Label(ListeningCopy.text("筛选唱片"), systemImage: "line.3.horizontal.decrease")
                    }
                    .disabled(isCommitting)
                    .accessibilityIdentifier("listening.pickDisc.filter")
                }
            }
            .tint(BSColor.Stage.foreground)
        }
        .onDisappear { isCommitting = false }
    }

    private func cardDeck(_ disc: ListeningDisc, size: CGSize) -> some View {
        let width = size.width
        let cardWidth = max(width - BSSpacing.roomy * 2, 0)
        let cardHeight = max(min(size.height - BSSpacing.lg * 2, cardWidth + BSSpacing.lg * 6), 0)
        let progress = min(abs(dragOffset.width) / (width * 0.4), 1)
        let revealedDisc = dragOffset.width < 0 ? previousDisc : nextDisc
        return ZStack {
            if let revealedDisc {
                discCard(revealedDisc, width: cardWidth, height: cardHeight)
                    .scaleEffect(reduceMotion ? 1 : 0.94 + progress * 0.06)
                    .offset(y: reduceMotion ? 0 : BSSpacing.md * (1 - progress))
                    .opacity(reduceMotion ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            discCard(disc, width: cardWidth, height: cardHeight)
                .offset(x: reduceMotion ? 0 : dragOffset.width,
                        y: reduceMotion ? 0 : dragOffset.height * 0.12)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(dragOffset.width / width) * 16), anchor: .bottom)
                .opacity(reduceMotion && isCommitting ? 0 : 1)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("listening.pickDisc.card")
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard !isCommitting,
                                  abs(value.translation.width) > abs(value.translation.height) else { return }
                            let canMove = value.translation.width < 0 ? previousDisc != nil : canRedraw
                            dragOffset = CGSize(width: value.translation.width * (canMove ? 1 : 0.15),
                                                height: value.translation.height)
                        }
                        .onEnded { value in
                            handleDragEnd(value, width: width)
                        }
                )
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.vertical, BSSpacing.lg)
    }

    private func discCard(_ disc: ListeningDisc, width: CGFloat, height: CGFloat) -> some View {
        let artworkSize = max(min(width - BSSpacing.md * 2, height - BSSpacing.lg * 8), 0)
        return VStack(spacing: BSSpacing.md) {
            ListeningDiscCover(disc: disc, show: show)
                .frame(width: artworkSize, height: artworkSize)
                .id(disc.id)

            VStack(spacing: BSSpacing.sm) {
                Text(disc.title)
                    .font(BSListeningTokens.discTitle)
                    .foregroundStyle(BSColor.Stage.foreground)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
                    .accessibilityIdentifier("listening.discDetail.title")
                ListeningDiscArtistCredits(
                    links: ListeningDiscArtistLinks.links(for: disc, lineup: show?.artists ?? [])
                )
                .frame(height: BSLayout.minTouchTarget)
                Text(metadataSubtitle(for: disc))
                    .font(BSListeningTokens.caption)
                    .foregroundStyle(BSColor.Stage.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2, reservesSpace: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(BSSpacing.md)
        .frame(width: width, height: height)
        .background {
            ListeningDiscBackdrop(artworkURL: disc.artworkURL, tint: ListeningSleeveIdentity(disc: disc).color)
                .id(disc.id)
        }
        .clipShape(RoundedRectangle(cornerRadius: BSRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: BSRadius.lg)
                .strokeBorder(BSColor.Stage.border, lineWidth: BSListeningTokens.hairline)
        }
        .shadow(color: .black.opacity(0.3), radius: BSSpacing.md, y: BSSpacing.sm)
        .contentShape(RoundedRectangle(cornerRadius: BSRadius.lg))
    }

    private func actionSection(width: CGFloat) -> some View {
        VStack(spacing: BSSpacing.sm) {
            Button(action: onConfirm) {
                Label(BSLocalization.text("装入播放机"), systemImage: "opticaldisc")
            }
            .buttonStyle(BSListeningActionStyle())
            .disabled(!canConfirm || isCommitting)
            .accessibilityIdentifier("listening.pickDisc.confirm")

            if canRedraw {
                Button { commitSwipe(direction: 1, width: width) } label: {
                    HStack(spacing: BSSpacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .rotationEffect(.degrees(iconRotation))
                        Text(ListeningCopy.text("换一张"))
                    }
                    .font(BSListeningTokens.body.weight(.medium))
                    .foregroundStyle(BSColor.Stage.foreground)
                    .frame(maxWidth: .infinity, minHeight: BSLayout.minTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BSListeningPressStyle())
                .disabled(isCommitting)
                .accessibilityIdentifier("listening.pickDisc.redraw")
            }
        }
        .padding(.horizontal, BSSpacing.roomy)
        .padding(.vertical, BSSpacing.md)
        .background {
            LinearGradient(
                stops: [
                    .init(color: BSColor.Stage.background.opacity(0), location: 0),
                    .init(color: BSColor.Stage.background.opacity(0.9), location: 0.45),
                    .init(color: BSColor.Stage.background, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.top, -BSSpacing.xl)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private var exhaustedContent: some View {
        VStack(spacing: BSSpacing.md) {
            Spacer(minLength: BSSpacing.xl)
            Image(systemName: "square.stack")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(BSColor.Stage.muted)
            Text(ListeningCopy.text(filter == .all ? "这排柜子暂时没有可挑的唱片" : "没有符合筛选条件的唱片"))
                .accessibilityIdentifier("listening.pickDisc.empty")
                .font(BSListeningTokens.headline)
                .foregroundStyle(BSColor.Stage.foreground)
                .multilineTextAlignment(.center)
            Button(BSLocalization.text("好"), action: onClose)
                .buttonStyle(BSListeningActionStyle())
            Spacer(minLength: BSSpacing.xl)
        }
        .frame(maxWidth: .infinity)
    }

    private func metadataSubtitle(for disc: ListeningDisc) -> String {
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
        let duration = disc.tracks.compactMap(\.duration).reduce(0, +)
        if duration > 0 {
            items.append("\(Int(duration) / 60) \(BSLocalization.text("分钟"))")
        }
        return items.joined(separator: " · ")
    }

    private func handleDragEnd(_ value: DragGesture.Value, width: CGFloat) {
        guard !isCommitting else { return }
        let horizontal = abs(value.translation.width) > abs(value.translation.height)
        let projected = value.predictedEndTranslation.width
        let canMove = value.translation.width < 0 ? previousDisc != nil : canRedraw
        if canMove, horizontal,
           abs(value.translation.width) > width * 0.24 || abs(projected) > width * 0.55 {
            commitSwipe(direction: value.translation.width < 0 ? -1 : 1, width: width)
        } else {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.76)) {
                dragOffset = .zero
            }
        }
    }

    private func commitSwipe(direction: CGFloat, width: CGFloat) {
        let canMove = direction < 0 ? previousDisc != nil : canRedraw
        guard canMove, !isCommitting else { return }
        isCommitting = true
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        #endif
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .easeOut(duration: 0.22),
                      completionCriteria: .removed) {
            dragOffset.width = direction * width * 1.4
            iconRotation += 360
        } completion: {
            guard isCommitting else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if direction < 0 { onPrevious() } else { onRedraw() }
                dragOffset = .zero
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                isCommitting = false
            }
        }
    }
}
