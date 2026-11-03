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

                Text(weather.conditionDescription)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.8))

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
                    .background(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(BSLocalization.format("天气：%1$@，%2$lld度", weather.conditionDescription, Int64(weather.temperatureCelsius)))
        .accessibilityHint(BSLocalization.text("轻点查看现场微气候与穿搭建议"))
    }
}
