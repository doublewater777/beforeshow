import SwiftUI
import WidgetKit

// MARK: - 锁屏 inline(单色,平台强制)

struct InlineCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        statusText
            .font(.headline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
    }

    // ponytail: 锁屏单行只放纯状态,演出名放不下;识别靠点进 app
    @ViewBuilder
    private var statusText: some View {
        switch presentation.hero {
        case .far(let days):
            Text(BSLocalization.format("还有 %lld 天", days))
        case .near(let start):
            Text(timerInterval: widgetCountdownRange(to: start), countsDown: true)
                .monospacedDigit()
        case .live(let start):
            Text("正在现场 · \(Text(start, style: .timer))")
        case .ended:
            Text(presentation.endedTitle)
        case .endUnconfirmed:
            Text("散场待确认")
        case .inactive(let title):
            Text(title)
        case .empty:
            Text("开场前")
        }
    }
}

// MARK: - 锁屏圆形

struct CircularCountdownView: View {
    let presentation: CountdownPresentation

    /// 预习期 14 天窗口:环随临近填满,正在现场满环。
    private var progress: Double {
        switch presentation.hero {
        case .live: return 1
        case .ended, .endUnconfirmed, .inactive, .empty: return 0
        default:
            let window: Double = 14 * 86_400
            return 1 - min(max(Double(presentation.remainingSeconds), 0), window) / window
        }
    }

    var body: some View {
        Gauge(value: progress, in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            centerLabel
        }
        .gaugeStyle(.accessoryCircular)
    }

    @ViewBuilder
    private var centerLabel: some View {
        switch presentation.hero {
        case .far(let days):
            VStack(spacing: 1) {
                Text("\(days)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.78)
                Text(BSLocalization.format("天（按天数）", days))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        case .near(let start):
            VStack(spacing: 1) {
                Text(timerInterval: widgetCountdownRange(to: start), countsDown: true)
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.78)
                if presentation.isStartToday {
                    Text("今天")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        case .live:
            VStack(spacing: 1) {
                Circle().frame(width: 6, height: 6)
                if let start = presentation.startDate {
                    // TimelineView 60s 一跳,系统侧渲染,不走原生秒级 timer
                    TimelineView(.periodic(from: start, by: 60)) { context in
                        Text(LockScreenCountdownCopy.circularLiveElapsed(
                            elapsedSeconds: Int(context.date.timeIntervalSince(start))
                        ))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.78)
                    }
                }
            }
        case .ended:
            Text(presentation.endedTitle)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        case .endUnconfirmed:
            Text("待确认")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        case .inactive(let title):
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
        case .empty:
            Text("--")
                .font(.headline.weight(.bold))
                .monospacedDigit()
        }
    }
}

// MARK: - 锁屏长条
// 三行:状态 / 演出名 / 时间。与音乐节锁屏同一结构。

struct RectangularCountdownView: View {
    let presentation: CountdownPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch presentation.hero {
            case .far(let days):
                lines(Text(presentation.phaseTag), Text(presentation.showName),
                      Text(verbatim: "\(BSLocalization.format("还有 %lld 天", days)) · \(presentation.dateLine)"))
            case .near(let start):
                lines(Text(presentation.phaseTag), Text(presentation.showName),
                      Text(timerInterval: widgetCountdownRange(to: start), countsDown: true))
            case .live(let start):
                lines(Text("\(Image(systemName: "waveform")) 正在现场"), Text(presentation.showName),
                      Text("已开场 · \(Text(start, style: .timer))"))
            case .ended:
                lines(nil, Text(presentation.endedTitle), Text(presentation.showName))
            case .endUnconfirmed:
                lines(nil, Text("散场待确认"), Text(presentation.showName))
            case .inactive(let title):
                lines(nil, Text(title), Text(presentation.showName))
            case .empty:
                lines(nil, Text("还没有现场"), Text("打开开场前，添加下一场"))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lines(_ top: Text?, _ title: Text, _ bottom: Text) -> some View {
        if let top {
            top.font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
        }
        title.font(.headline.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
        bottom.font(.caption).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.78)
    }
}
