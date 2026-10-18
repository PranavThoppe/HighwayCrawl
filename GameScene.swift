import SpriteKit

class GameScene: SKScene {
    private let player = SKSpriteNode(color: .red, size: CGSize(width: 40, height: 70))
    private var roads: [SKNode] = []
    private var lastTime: TimeInterval = 0
    private let normalSpeed: CGFloat = 500
    private let deceleration: CGFloat = 140
    private let acceleration: CGFloat = 220
    private var scrollSpeed: CGFloat = 500
    private var isGameOver = false
    private let laneCount = 4
    // 0 = left shoulder, 1...laneCount = asphalt, laneCount+1 = right shoulder
    private var currentLane = 2

    private let asphaltColor = SKColor(white: 0.22, alpha: 1)
    private let shoulderColor = SKColor(red: 0.16, green: 0.14, blue: 0.10, alpha: 1)

    /// Called when the player taps the retry button after a game over.
    var onRetry: (() -> Void)?
    private let retryButtonName = "retryButton"

    // NPC traffic
    private var npcs: [NPCCar] = []
    private var isPlayerAirborne = false
    private let maxDeltaTime: TimeInterval = 1.0 / 30.0
    private let npcSpeedRange: ClosedRange<CGFloat> = 250...420
    private let gracePeriod: TimeInterval = 3.0
    private var elapsedTime: TimeInterval = 0
    private var nextSpawnTime: TimeInterval = 0
    private let trafficColor = SKColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
    private let parkedColor = SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1)

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
        guard !isGameOver else { return }
        let nextLane = currentLane + delta
        guard nextLane >= 0, nextLane <= laneCount + 1 else { return }

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

    private var isOnShoulder: Bool {
        currentLane == 0 || currentLane == laneCount + 1
    }

    private func xPosition(forLane lane: Int) -> CGFloat {
        if lane == 0 {
            return shoulderWidth / 2
        }
        if lane == laneCount + 1 {
            return size.width - shoulderWidth / 2
        }
        return shoulderWidth + laneWidth * (CGFloat(lane - 1) + 0.5)
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
        // Clamp dt so a frame spike can't skip a collision
        let rawDt = lastTime == 0 ? 0 : currentTime - lastTime
        let dt = min(rawDt, maxDeltaTime)
        lastTime = currentTime
        guard !isGameOver, dt > 0 else { return }
        elapsedTime += dt

        if isOnShoulder {
            scrollSpeed = max(0, scrollSpeed - deceleration * CGFloat(dt))
            if scrollSpeed <= 0 {
                endGame()
                return
            }
        } else if scrollSpeed < normalSpeed {
            scrollSpeed = min(normalSpeed, scrollSpeed + acceleration * CGFloat(dt))
        }

        for road in roads {
            road.position.y -= scrollSpeed * CGFloat(dt)
            if road.position.y <= -size.height {
                road.position.y += size.height * 2
            }
        }

        spawnPlaceholderTraffic()
        updateNPCs(dt: dt)
        checkCollisions()
    }

    // MARK: - NPC cars

    // Placeholder spawner: random cars, replaced by TrafficSpawner later
    private func spawnPlaceholderTraffic() {
        guard elapsedTime >= gracePeriod, elapsedTime >= nextSpawnTime else { return }
        nextSpawnTime = elapsedTime + TimeInterval.random(in: 0.8...1.6)

        let car: NPCCar
        if Int.random(in: 0..<5) == 0 {
            let lane = Bool.random() ? 0 : laneCount + 1
            guard isSpawnClear(lane: lane) else { return }
            car = NPCCar(lane: lane, speed: 0, isParked: true, color: parkedColor)
        } else {
            let lane = Int.random(in: 1...laneCount)
            guard isSpawnClear(lane: lane) else { return }
            car = NPCCar(lane: lane, speed: CGFloat.random(in: npcSpeedRange), color: trafficColor)
        }
        car.position = CGPoint(x: xPosition(forLane: car.lane), y: size.height + car.size.height / 2)
        car.zPosition = 5
        addChild(car)
        npcs.append(car)
    }

    private func updateNPCs(dt: TimeInterval) {
        let removeBelow = -size.height / 2
        let removeAbove = size.height * 4
        matchSpeedsWithCarsAhead()
        for car in npcs {
            // Parked cars have speed 0, so they move at the full scroll speed
            car.position.y -= (scrollSpeed - car.forwardSpeed) * CGFloat(dt)
        }
        npcs.removeAll { car in
            let offscreen = car.position.y < removeBelow || car.position.y > removeAbove
            if offscreen { car.removeFromParent() }
            return offscreen
        }
    }

    // NPCs drive up the screen, so the car "ahead" has the larger y.
    // A faster car that closes within `followDistance` of the car ahead slows to its speed.
    private func matchSpeedsWithCarsAhead() {
        let followDistance: CGFloat = 40
        let carHeight = NPCCar.carSize.height
        let moving = npcs.filter { !$0.isParked }
        for lane in 1...laneCount {
            let inLane = moving.filter { $0.lane == lane }.sorted { $0.position.y < $1.position.y }
            guard inLane.count > 1 else { continue }
            // Walk from the front car backwards so a slowed car passes its speed on down the line
            for i in stride(from: inLane.count - 2, through: 0, by: -1) {
                let behind = inLane[i]
                let ahead = inLane[i + 1]
                let gap = ahead.position.y - behind.position.y - carHeight
                if gap < followDistance, behind.forwardSpeed > ahead.forwardSpeed {
                    behind.forwardSpeed = ahead.forwardSpeed
                }
            }
        }
    }

    // Don't spawn on top of a car that's still near the spawn point in the same lane
    private func isSpawnClear(lane: Int) -> Bool {
        let spawnY = size.height + NPCCar.carSize.height / 2
        let minGap = NPCCar.carSize.height * 1.5
        return !npcs.contains { $0.lane == lane && spawnY - $0.position.y < minGap }
    }

    private func checkCollisions() {
        guard !isPlayerAirborne else { return }
        let hitbox = player.frame.insetBy(dx: 4, dy: 6)
        for car in npcs where hitbox.intersects(car.frame) {
            endGame()
            return
        }
    }

    private func endGame() {
        isGameOver = true
        scrollSpeed = 0

        let label = SKLabelNode(text: "GAME OVER")
        label.fontName = "AvenirNext-Bold"
        label.fontSize = 48
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: size.width / 2, y: size.height / 2)
        label.zPosition = 20
        addChild(label)

        let buttonSize = CGSize(width: 160, height: 52)
        let button = SKShapeNode(rectOf: buttonSize, cornerRadius: 12)
        button.name = retryButtonName
        button.fillColor = SKColor(white: 0.15, alpha: 0.9)
        button.strokeColor = .white
        button.lineWidth = 3
        button.position = CGPoint(x: size.width / 2, y: size.height / 2 - 70)
        button.zPosition = 20

        let title = SKLabelNode(text: "RETRY")
        title.name = retryButtonName
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 28
        title.fontColor = .white
        title.verticalAlignmentMode = .center
        title.horizontalAlignmentMode = .center
        button.addChild(title)
        addChild(button)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isGameOver, let touch = touches.first else { return }
        let tapped = nodes(at: touch.location(in: self))
        if tapped.contains(where: { $0.name == retryButtonName }) {
            onRetry?()
        }
    }
}
