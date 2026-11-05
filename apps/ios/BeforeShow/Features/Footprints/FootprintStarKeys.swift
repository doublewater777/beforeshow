import SwiftUI
import UIKit

/// The sky's touch surface: every finger plays the star under it, several fingers make a chord,
/// and sliding from star to star runs up or down the scale.
struct FootprintStarKeys: UIViewRepresentable {
    struct Key: Equatable {
        let name: String
        let point: CGPoint
        /// Background dust answers only when no named star is in reach.
        var isDust = false
    }

    let keys: [Key]
    let onPress: (_ finger: Int, _ name: String) -> Void
    let onRelease: (_ finger: Int) -> Void

    func makeUIView(context: Context) -> Surface {
        let surface = Surface()
        surface.isMultipleTouchEnabled = true
        surface.backgroundColor = .clear
        return surface
    }

    func updateUIView(_ surface: Surface, context: Context) {
        surface.keys = keys
        surface.onPress = onPress
        surface.onRelease = onRelease
    }

    final class Surface: UIView {
        var keys: [Key] = []
        var onPress: ((Int, String) -> Void)?
        var onRelease: ((Int) -> Void)?
        private var held: [ObjectIdentifier: (finger: Int, name: String)] = [:]
        private var nextFinger = 0

        /// Fingers are wide; a star answers within a comfortable reach.
        private static let reach: CGFloat = 30

        private func key(at point: CGPoint) -> Key? {
            func nearest(_ candidates: [Key], within reach: CGFloat) -> Key? {
                candidates
                    .map { ($0, hypot($0.point.x - point.x, $0.point.y - point.y)) }
                    .filter { $0.1 <= reach }
                    .min { $0.1 < $1.1 }?.0
            }
            return nearest(keys.filter { !$0.isDust }, within: Self.reach) ?? nearest(keys.filter(\.isDust), within: 18)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let key = key(at: touch.location(in: self)) else { continue }
                nextFinger += 1
                held[ObjectIdentifier(touch)] = (nextFinger, key.name)
                onPress?(nextFinger, key.name)
            }
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            for touch in touches {
                guard let key = key(at: touch.location(in: self)) else { continue }
                let id = ObjectIdentifier(touch)
                if let current = held[id] {
                    guard current.name != key.name else { continue }
                    onRelease?(current.finger)
                }
                nextFinger += 1
                held[id] = (nextFinger, key.name)
                onPress?(nextFinger, key.name)
            }
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { lift(touches) }

        private func lift(_ touches: Set<UITouch>) {
            for touch in touches {
                if let current = held.removeValue(forKey: ObjectIdentifier(touch)) {
                    onRelease?(current.finger)
                }
            }
        }
    }
}
