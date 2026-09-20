import SwiftUI
import SwiftData

struct FootprintListeningMemorySection: View {
    let show: Show
    @Environment(\.modelContext) private var context
    @State private var coordinator: FootprintListeningCoordinator?
    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.md) {
            if let coordinator {
                ForEach(coordinator.tiers) { tier in
                    if let resolved = ListeningFamiliarityTier(rawValue: tier.tierRawValue) {
                        VStack(alignment: .leading, spacing: BSSpacing.xs) {
                            Text(BSLocalization.text("去见 TA 时") + " · " + tier.artistNameAtCapture).font(.caption)
                            Text(BSLocalization.text(resolved.localizationKey)).font(.title3)
                        }
                    }
                }
                if !WantsLivePolicy.isMutable(show: show) && coordinator.wantedCount > 0 {
                    Label(BSLocalization.text("开场前想现场听") + " · " + String(coordinator.wantedCount), systemImage: "heart.fill")
                        .font(.subheadline)
                }
                if !coordinator.memories.isEmpty {
                    Text(BSLocalization.text("现场听到了")).font(.headline)
                    ForEach(coordinator.memories) { memory in
                        HStack {
                            ListeningArtwork(url: coordinator.artwork(memory), title: coordinator.title(memory)).frame(width: 44, height: 44)
                            VStack(alignment: .leading) {
                                if memory.isMostSurprising { Label(BSLocalization.text("最惊喜"), systemImage: "sparkle").font(.caption) }
                                Text(coordinator.title(memory)).font(.body)
                                Text(coordinator.artist(memory)).font(.caption).foregroundStyle(BSColor.Stage.muted)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
            .task { let owner = FootprintListeningCoordinator(context: context, show: show); owner.reload(); coordinator = owner }
    }
}
