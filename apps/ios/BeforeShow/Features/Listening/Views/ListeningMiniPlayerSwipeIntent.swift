import CoreGraphics

enum ListeningMiniPlayerSwipeAction: Equatable {
    case previous, next
}

enum ListeningMiniPlayerSwipeIntent {
    static let activationDistance: CGFloat = 8
    static let commitDistance: CGFloat = 52
    static let projectedCommitDistance: CGFloat = 88
    static let horizontalDominanceRatio: CGFloat = 1.15
    static let pageTravel: CGFloat = 164
    static let unavailableEdgeResistance: CGFloat = 0.18

    static func isHorizontal(_ translation: CGSize) -> Bool {
        let horizontalDistance = abs(translation.width)
        let verticalDistance = abs(translation.height)
        return horizontalDistance >= activationDistance
            && horizontalDistance > verticalDistance * horizontalDominanceRatio
    }

    static func action(
        for translation: CGSize,
        predictedEndTranslation: CGSize? = nil
    ) -> ListeningMiniPlayerSwipeAction? {
        guard isHorizontal(translation) else { return nil }

        let predicted = predictedEndTranslation ?? translation
        guard abs(translation.width) >= commitDistance
                || abs(predicted.width) >= projectedCommitDistance else {
            return nil
        }

        return translation.width < 0 ? .next : .previous
    }

    static func trackedOffset(for translation: CGSize, canNavigate: Bool) -> CGFloat {
        guard isHorizontal(translation) else { return 0 }

        let maximumTravel = pageTravel * 1.06
        let direct = min(max(translation.width, -maximumTravel), maximumTravel)
        guard !canNavigate else { return direct }

        let resisted = direct * unavailableEdgeResistance
        return min(max(resisted, -18), 18)
    }
}
