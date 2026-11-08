import SwiftUI

struct CurrentShowWeatherCapsule: View {
    let weather: ShowWeatherDTO
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: weather.condition.systemSymbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(weather.tone.primaryTint)

                Text(verbatim: "\(weather.temperatureCelsius)°")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .bsGlassPanel(in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.format("天气：%1$@，%2$lld度", weather.conditionDescription, Int64(weather.temperatureCelsius)))
        .accessibilityHint(BSLocalization.text("轻点查看现场天气与穿搭建议"))
    }
}
