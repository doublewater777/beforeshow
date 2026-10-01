import SwiftUI
import WidgetKit

// MARK: - Cabinet Widget

struct CabinetWidget: Widget {
    let kind = BeforeShowWidgetKind.homeCabinet

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ListeningTimelineProvider()) { entry in
            CabinetWidgetView(entry: entry)
        }
        .configurationDisplayName("现场唱片柜")
        .description("立体陈列当前现场的合辑与专辑唱片，随时随地挑选与翻看。")
        .supportedFamilies([
            .systemMedium,
            .systemSmall,
            .systemLarge,
        ])
    }
}
