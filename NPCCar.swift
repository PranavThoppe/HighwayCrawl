import SpriteKit

/// A non-player car. `forwardSpeed` is its speed in pt/s (0 for parked cars).
/// Named `forwardSpeed` because `SKNode` already has a `speed` property.
final class NPCCar: SKSpriteNode {
    /// Points per art pixel. Keep it a whole number so every pixel stays the same size.
    static let artScale: CGFloat = 2
    /// The cropped jeep art (38×48 px) scaled up, so the frame is also the hitbox.
    static let carSize = CGSize(width: 38 * artScale, height: 48 * artScale)

    private static let jeepTexture: SKTexture = {
        let texture = SKTexture(imageNamed: "jeep.rear")
        // Keeps pixel art crisp instead of blurred when scaled
        texture.filteringMode = .nearest
        return texture
    }()

    let lane: Int
    /// Mutable so a car can slow down to match the car ahead of it.
    var forwardSpeed: CGFloat
    let isParked: Bool

    /// - Parameters:
    ///   - tint: optional colour mixed over the jeep art, used to tell car kinds apart.
    ///   - tintAmount: 0 shows the plain art, 1 paints the car solid `tint`.
    init(lane: Int, speed: CGFloat, isParked: Bool = false, tint: SKColor? = nil, tintAmount: CGFloat = 0.5) {
        self.lane = lane
        self.forwardSpeed = isParked ? 0 : speed
        self.isParked = isParked
        super.init(texture: NPCCar.jeepTexture, color: tint ?? .white, size: NPCCar.carSize)
        colorBlendFactor = tint == nil ? 0 : tintAmount
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
