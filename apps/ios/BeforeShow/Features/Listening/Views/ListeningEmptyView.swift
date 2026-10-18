import SwiftUI

struct ListeningEmptyView: View {
    let hasShows: Bool
    let onAddShow: () -> Void
    let onOpenShowLibrary: () -> Void

    private var action: () -> Void {
        hasShows ? onOpenShowLibrary : onAddShow
    }

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                ListeningPageHeader {
                    HStack(spacing: BSSpacing.sm) {
                        if hasShows {
                            ListeningHeaderActionButton(
                                icon: "list.bullet.rectangle",
                                accessibilityLabel: BSLocalization.text("全部现场"),
                                action: onOpenShowLibrary
                            )
                        }
                        ListeningHeaderActionButton(
                            icon: "plus",
                            accessibilityLabel: BSLocalization.text("添加现场"),
                            action: onAddShow
                        )
                    }
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ListeningRackSkeleton(animates: false)
                            .padding(.horizontal, -BSSpacing.roomy)
                            .frame(height: ListeningRackLayout.slotHeight, alignment: .top)
                            .listeningFrame("cabinet")
                            .padding(.top, BSSpacing.sm)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: action)

                        let geometry = CDPlayerConfiguration.standard.geometry
                        let availableWidth = min(proxy.size.width - BSSpacing.roomy * 2, BSLayout.maxPlayerWidth)
                        let scale = availableWidth * BSListeningTokens.playerWidthFraction / geometry.body.width

                        ListeningPreparingMachineView(scale: scale)
                            .listeningFrame("stage")
                            .frame(width: availableWidth)
                            .padding(.top, -(geometry.viewportTop + BSListeningTokens.stageTopOffset) * scale)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: action)

                        Color.clear.frame(height: BSLayout.minTouchTarget)
                            .padding(.top, -BSSpacing.lg)
                    }
                    .coordinateSpace(name: "listeningContent")
                    .padding(.horizontal, BSSpacing.roomy)
                    .padding(.top, BSSpacing.xs)
                }
                .scrollDisabled(true)
            }
            .bsAdaptiveContentWidth()
        }
        .foregroundStyle(BSColor.Stage.foreground)
        .background(BSColor.Stage.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}
