import SpriteKit

class GameScene: SKScene {
    private let player = SKSpriteNode(color: .red, size: CGSize(width: 40, height: 70))
    private var roads: [SKNode] = []
    private var lastTime: TimeInterval = 0
    private let scrollSpeed: CGFloat = 500
    private let laneCount = 4
    private var currentLane = 1

    private let asphaltColor = SKColor(white: 0.22, alpha: 1)
    private let shoulderColor = SKColor(red: 0.16, green: 0.14, blue: 0.10, alpha: 1)

    private var laneWidth: CGFloat { size.width / CGFloat(laneCount + 1) }
    private var shoulderWidth: CGFloat { laneWidth * 0.5 }

    override func didMove(to view: SKView) {
        anchorPoint = .zero
        backgroundColor = asphaltColor

        for i in 0..<2 {
            let road = makeRoadTile()
            road.position = CGPoint(x: 0, y: CGFloat(i) * size.height)
            addChild(road)
            roads.append(road)
        }

        player.position = CGPoint(x: xPosition(forLane: currentLane), y: size.height * 0.2)
        player.zPosition = 10
        addChild(player)
    }

    func changeLane(by delta: Int) {
        let nextLane = currentLane + delta
        guard nextLane >= 0, nextLane < laneCount else { return }

        currentLane = nextLane
        player.removeAction(forKey: "laneChange")
        player.run(SKAction.moveTo(x: xPosition(forLane: currentLane), duration: 0.18), withKey: "laneChange")
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let key = press.key else { continue }
            switch key.keyCode {
            case .keyboardLeftArrow:
                changeLane(by: -1)
                handled = true
            case .keyboardRightArrow:
                changeLane(by: 1)
                handled = true
            default:
                break
            }
        }
        if !handled {
            super.pressesBegan(presses, with: event)
        }
    }

    private func xPosition(forLane lane: Int) -> CGFloat {
        return shoulderWidth + laneWidth * (CGFloat(lane) + 0.5)
    }

    // One screen-height tile of asphalt, shoulders, and lane markings
    private func makeRoadTile() -> SKNode {
        let tile = SKNode()
        let height = size.height

        let asphalt = SKSpriteNode(
            color: asphaltColor,
            size: CGSize(width: laneWidth * CGFloat(laneCount), height: height)
        )
        asphalt.position = CGPoint(x: size.width / 2, y: height / 2)
        tile.addChild(asphalt)

        let leftShoulder = SKSpriteNode(color: shoulderColor, size: CGSize(width: shoulderWidth, height: height))
        leftShoulder.position = CGPoint(x: shoulderWidth / 2, y: height / 2)
        tile.addChild(leftShoulder)

        let rightShoulder = SKSpriteNode(color: shoulderColor, size: CGSize(width: shoulderWidth, height: height))
        rightShoulder.position = CGPoint(x: size.width - shoulderWidth / 2, y: height / 2)
        tile.addChild(rightShoulder)

        let edgeWidth: CGFloat = 6
        let leftEdge = SKSpriteNode(color: .white, size: CGSize(width: edgeWidth, height: height))
        leftEdge.position = CGPoint(x: shoulderWidth, y: height / 2)
        leftEdge.zPosition = 1
        tile.addChild(leftEdge)

        let rightEdge = SKSpriteNode(color: .white, size: CGSize(width: edgeWidth, height: height))
        rightEdge.position = CGPoint(x: size.width - shoulderWidth, y: height / 2)
        rightEdge.zPosition = 1
        tile.addChild(rightEdge)

        let dashes = 10
        let spacing = height / CGFloat(dashes)
        for lane in 1..<laneCount {
            let x = shoulderWidth + laneWidth * CGFloat(lane)
            for d in 0..<dashes {
                let dash = SKSpriteNode(color: .white, size: CGSize(width: 4, height: spacing * 0.5))
                dash.position = CGPoint(x: x, y: CGFloat(d) * spacing + spacing / 2)
                dash.zPosition = 1
                tile.addChild(dash)
            }
        }

        return tile
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastTime == 0 ? 0 : currentTime - lastTime
        lastTime = currentTime

        for road in roads {
            road.position.y -= scrollSpeed * CGFloat(dt)
            if road.position.y <= -size.height {
                road.position.y += size.height * 2
            }
        }
    }
}
