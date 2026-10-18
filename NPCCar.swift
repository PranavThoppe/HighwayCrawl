import SpriteKit

/// A non-player car. `forwardSpeed` is its speed in pt/s (0 for parked cars).
/// Named `forwardSpeed` because `SKNode` already has a `speed` property.
final class NPCCar: SKSpriteNode {
    static let carSize = CGSize(width: 40, height: 70)

    let lane: Int
    /// Mutable so a car can slow down to match the car ahead of it.
    var forwardSpeed: CGFloat
    let isParked: Bool

    init(lane: Int, speed: CGFloat, isParked: Bool = false, color: SKColor) {
        self.lane = lane
        self.forwardSpeed = isParked ? 0 : speed
        self.isParked = isParked
        super.init(texture: nil, color: color, size: NPCCar.carSize)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
