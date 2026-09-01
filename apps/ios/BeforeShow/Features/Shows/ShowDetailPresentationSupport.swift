import SwiftUI
import SwiftData
import UIKit

enum ShowDetailInformationPolicy {
    static func venueDetail(address: String?, city: String?) -> String? {
        let value = [address, city].compactMap { $0 }.joined(separator: " · ")
        return value.isEmpty ? nil : value
    }
}

enum ShowDetailExperienceAction: String, CaseIterable {
    case companion = "同行"
    case memoryFragments = "记忆碎片"

    var iconName: String {
        switch self {
        case .companion: return "person.2"
        case .memoryFragments: return "photo.on.rectangle.angled"
        }
    }
}

struct ShowDetailExperienceTile: View {
    let action: ShowDetailExperienceAction
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: BSSpacing.xs) {
            Image(systemName: action.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(BSColor.Stage.accent)

            Text(title)
                .font(BSFont.V3.small.weight(.medium))
                .foregroundColor(BSColor.Stage.foreground)
                .lineLimit(1)

            Text(subtitle)
                .font(BSFont.V3.caption)
                .foregroundColor(BSColor.Stage.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BSSpacing.compact)
        .background(BSColor.Stage.surface, in: RoundedRectangle(cornerRadius: BSRadius.v3Medium))
        .overlay(
            RoundedRectangle(cornerRadius: BSRadius.v3Medium)
                .stroke(BSColor.Stage.border, lineWidth: 1)
        )
    }
}
