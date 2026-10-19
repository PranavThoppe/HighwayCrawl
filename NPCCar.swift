import SpriteKit

/// A non-player car. `forwardSpeed` is its speed in pt/s (0 for parked cars).
/// Named `forwardSpeed` because `SKNode` already has a `speed` property.
final class NPCCar: SKSpriteNode {
    /// Points per art pixel. Keep it a whole number so every pixel stays the same size.
    static let artScale: CGFloat = 2

    /// A car model and the colours its art comes in. `weight` sets how often it is picked
    /// relative to the other models, regardless of how many colours it has.
    private struct Model {
        let imageNames: [String]
        let weight: Double
    }

    /// Regular and parked traffic.
    private static let trafficModels: [Model] = [
        Model(imageNames: ["civic.black", "civic.blue", "civic.brown", "civic.red"], weight: 1),
        Model(imageNames: ["hatchback.black", "hatchback.blue", "hatchback.magenta", "hatchback.yellow"], weight: 1),
        Model(imageNames: ["jeep.rear", "jeep.blue", "jeep.green", "jeep.red"], weight: 1)
    ]

    /// Box trucks only appear in jump-required walls.
    private static let wallModels: [Model] = [
        Model(imageNames: [
            "boxtruck.black", "boxtruck.blue", "boxtruck.brown", "boxtruck.green",
            "boxtruck.magenta", "boxtruck.red", "boxtruck.yellow"
        ], weight: 1)
    ]

    private static let textures: [String: SKTexture] = {
        var textures: [String: SKTexture] = [:]
        for name in (trafficModels + wallModels).flatMap(\.imageNames) {
            let texture = SKTexture(imageNamed: name)
            // Keeps pixel art crisp instead of blurred when scaled
            texture.filteringMode = .nearest
            textures[name] = texture
        }
        return textures
    }()

    /// On-screen size of a texture; the frame is also the hitbox, so art must be cropped tight.
    private static func size(of texture: SKTexture) -> CGSize {
        let pixels = texture.size()
        return CGSize(width: pixels.width * artScale, height: pixels.height * artScale)
    }

    /// Height of the tallest car. The spawner plans with this so its timing holds for every model.
    static let maxCarHeight: CGFloat = textures.values.map { size(of: $0).height }.max() ?? 0

    private static func randomTexture(from models: [Model]) -> SKTexture {
        let total = models.reduce(0) { $0 + $1.weight }
        var roll = Double.random(in: 0..<total)
        let model = models.first { model in
            roll -= model.weight
            return roll < 0
        } ?? models[0]
        return textures[model.imageNames.randomElement()!]!
    }

    let lane: Int
    /// Mutable so a car can slow down to match the car ahead of it.
    var forwardSpeed: CGFloat
    let isParked: Bool

    /// - Parameters:
    ///   - isWall: wall cars are drawn as box trucks; everything else uses regular traffic art.
    ///   - tint: optional colour mixed over the car art, used to tell car kinds apart.
    ///   - tintAmount: 0 shows the plain art, 1 paints the car solid `tint`.
    init(
        lane: Int, speed: CGFloat, isParked: Bool = false, isWall: Bool = false,
        tint: SKColor? = nil, tintAmount: CGFloat = 0.5
    ) {
        self.lane = lane
        self.forwardSpeed = isParked ? 0 : speed
        self.isParked = isParked
        let texture = NPCCar.randomTexture(from: isWall ? NPCCar.wallModels : NPCCar.trafficModels)
        super.init(texture: texture, color: tint ?? .white, size: NPCCar.size(of: texture))
        colorBlendFactor = tint == nil ? 0 : tintAmount
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
