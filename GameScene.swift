import SpriteKit

class GameScene: SKScene {
    private let player: SKSpriteNode = {
        let texture = SKTexture(imageNamed: "roadster.white")
        // Keeps pixel art crisp instead of blurred when scaled
        texture.filteringMode = .nearest
        let pixels = texture.size()
        let size = CGSize(width: pixels.width * NPCCar.artScale, height: pixels.height * NPCCar.artScale)
        return SKSpriteNode(texture: texture, size: size)
    }()
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
    private var elapsedTime: TimeInterval = 0
    private var spawner: TrafficSpawner!
    // Parked cars are tinted yellow; wall cars use plain box-truck art.
    private let parkedColor = SKColor(red: 0.9, green: 0.75, blue: 0.2, alpha: 1)

    // Jump
    private let jumpAirtime: TimeInterval = 0.85
    private let jumpBoostSpeed: CGFloat = 200
    private let jumpCooldown: TimeInterval = 3.0
    private let jumpPeakScale: CGFloat = 1.5
    private let playerGroundZ: CGFloat = 4
    private let playerAirZ: CGFloat = 10
    /// Extra speed while airborne. Kept separate from `scrollSpeed` so the shoulder
    /// acceleration/deceleration logic is untouched; added to get the effective speed.
    private var jumpBoost: CGFloat = 0
    private var jumpTimeRemaining: TimeInterval = 0
    /// Counts down from `jumpCooldown`, starting the moment a jump begins.
    private var jumpCooldownRemaining: TimeInterval = 0
    private lazy var shadow = SKShapeNode(ellipseOf: player.size)
    private let cooldownBarBackground = SKSpriteNode(color: SKColor(white: 0, alpha: 0.5), size: CGSize(width: 120, height: 14))
    private let cooldownBarFill = SKSpriteNode(color: .orange, size: CGSize(width: 116, height: 10))
    private let cooldownReadyColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)

    // Roof bounce and score
    private let bounceAirtime: TimeInterval = 0.35
    private let bouncePeakScale: CGFloat = 1.25
    private let roofBonus = 250
    /// Distance units earned per point travelled.
    private let pointsPerDistance: CGFloat = 0.1
    /// Duration and peak scale of the hop currently in progress (jump or bounce).
    private var currentAirtime: TimeInterval = 0.85
    private var currentPeakScale: CGFloat = 1.5
    /// Roofs landed on in the current airborne chain; 0 when on the ground.
    private var comboCount = 0
    private var lastBouncedCar: NPCCar?
    private var distanceScore: CGFloat = 0
    private var bonusScore = 0
    private var shownScore = -1
    private let scoreLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")

    /// Called whenever the jump becomes ready (true) or goes on cooldown (false).
    var onJumpReadyChanged: ((Bool) -> Void)?

    var isJumpReady: Bool {
        !isGameOver && !isPlayerAirborne && jumpCooldownRemaining <= 0
    }

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
        player.zPosition = playerGroundZ

        shadow.fillColor = .black
        shadow.strokeColor = .clear
        shadow.alpha = 0.35
        shadow.zPosition = playerGroundZ - 1
        shadow.isHidden = true
        shadow.position = player.position
        addChild(shadow)
        addChild(player)

        spawner = TrafficSpawner(
            laneCount: laneCount,
            sceneHeight: size.height,
            playerY: player.position.y,
            playerSpeed: normalSpeed,
            playerHeight: player.size.height,
            startLane: currentLane
        )
        spawner.jumpCooldown = jumpCooldown
        spawner.isJumpReady = { [weak self] in self?.isJumpReady ?? false }

        setupCooldownBar(in: view)
        setupScoreLabel(in: view)
    }

    private func setupScoreLabel(in view: SKView) {
        let insets = view.safeAreaInsets
        scoreLabel.fontSize = 24
        scoreLabel.fontColor = .white
        scoreLabel.horizontalAlignmentMode = .right
        scoreLabel.verticalAlignmentMode = .center
        scoreLabel.position = CGPoint(
            x: size.width - max(16, insets.right + 16),
            y: size.height - max(24, insets.top + 24)
        )
        scoreLabel.zPosition = 30
        addChild(scoreLabel)
        refreshScoreLabel()
    }

    private var totalScore: Int { Int(distanceScore) + bonusScore }

    private func refreshScoreLabel() {
        let score = totalScore
        guard score != shownScore else { return }
        shownScore = score
        scoreLabel.text = "\(score)"
    }

    private func setupCooldownBar(in view: SKView) {
        let insets = view.safeAreaInsets
        let origin = CGPoint(
            x: max(16, insets.left + 16),
            y: size.height - max(24, insets.top + 24)
        )

        cooldownBarBackground.anchorPoint = CGPoint(x: 0, y: 0.5)
        cooldownBarBackground.position = origin
        cooldownBarBackground.zPosition = 30
        addChild(cooldownBarBackground)

        cooldownBarFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        cooldownBarFill.position = CGPoint(x: 2, y: 0)
        cooldownBarFill.color = cooldownReadyColor
        cooldownBarFill.zPosition = 1
        cooldownBarBackground.addChild(cooldownBarFill)
    }

    // MARK: - Jump

    func jump() {
        guard isJumpReady else { return }
        isPlayerAirborne = true
        jumpTimeRemaining = jumpAirtime
        jumpCooldownRemaining = jumpCooldown
        jumpBoost = jumpBoostSpeed
        currentAirtime = jumpAirtime
        currentPeakScale = jumpPeakScale
        comboCount = 0
        lastBouncedCar = nil

        player.zPosition = playerAirZ
        shadow.isHidden = false
        cooldownBarFill.removeAction(forKey: "ready")
        cooldownBarFill.alpha = 1
        cooldownBarFill.color = .orange
        cooldownBarFill.xScale = 0
        onJumpReadyChanged?(false)
    }

    private func updateJump(dt: TimeInterval) {
        if isPlayerAirborne {
            jumpTimeRemaining -= dt
            if jumpTimeRemaining <= 0 {
                if let roof = carUnderPlayer() {
                    bounce(off: roof)
                } else {
                    landPlayer()
                }
            } else {
                // Grow then shrink over the airtime
                let progress = CGFloat(1 - jumpTimeRemaining / currentAirtime)
                let height = sin(progress * .pi)
                player.setScale(1 + (currentPeakScale - 1) * height)
                shadow.setScale(1 - 0.25 * height)
                shadow.alpha = 0.35 - 0.15 * height
            }
        }

        if jumpCooldownRemaining > 0 {
            jumpCooldownRemaining -= dt
            if jumpCooldownRemaining <= 0 {
                jumpCooldownRemaining = 0
                cooldownBarFill.xScale = 1
                cooldownBarFill.color = cooldownReadyColor
                flashCooldownBar()
                // Still airborne (cooldown shorter than airtime) means not ready yet
                if !isPlayerAirborne { onJumpReadyChanged?(true) }
            } else {
                cooldownBarFill.xScale = CGFloat(1 - jumpCooldownRemaining / jumpCooldown)
            }
        }
    }

    /// The car the player's hitbox overlaps at the moment a hop ends, if any.
    private func carUnderPlayer() -> NPCCar? {
        // Use the unscaled footprint so the end of a hop isn't judged at a stretched size
        let box = CGRect(
            x: player.position.x - player.size.width / 2,
            y: player.position.y - player.size.height / 2,
            width: player.size.width,
            height: player.size.height
        ).insetBy(dx: 4, dy: 6)
        return npcs.first { box.intersects($0.frame) }
    }

    /// Landed on a roof: start a forward mini-hop and award a combo bonus.
    /// Doesn't touch the jump cooldown.
    private func bounce(off car: NPCCar) {
        // A hop that ends on the same car (slow car, short hop) keeps the combo but pays nothing new
        if car !== lastBouncedCar {
            comboCount += 1
            let bonus = roofBonus * comboCount
            bonusScore += bonus
            refreshScoreLabel()
            showBonusLabel(bonus: bonus, combo: comboCount)
        }
        lastBouncedCar = car

        jumpTimeRemaining = bounceAirtime
        currentAirtime = bounceAirtime
        currentPeakScale = bouncePeakScale
        jumpBoost = jumpBoostSpeed
        player.setScale(1)
        player.zPosition = playerAirZ
    }

    private func showBonusLabel(bonus: Int, combo: Int) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = combo > 1 ? "+\(bonus) x\(combo)" : "+\(bonus)"
        label.fontSize = 28
        label.fontColor = SKColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
        label.verticalAlignmentMode = .center
        label.horizontalAlignmentMode = .center
        label.position = CGPoint(x: player.position.x, y: player.position.y + player.size.height)
        label.zPosition = 25
        addChild(label)
        label.run(SKAction.sequence([
            SKAction.group([
                SKAction.moveBy(x: 0, y: 80, duration: 0.8),
                SKAction.sequence([
                    SKAction.wait(forDuration: 0.4),
                    SKAction.fadeOut(withDuration: 0.4)
                ])
            ]),
            SKAction.removeFromParent()
        ]))
    }

    private func landPlayer() {
        isPlayerAirborne = false
        jumpTimeRemaining = 0
        jumpBoost = 0
        comboCount = 0
        lastBouncedCar = nil
        // The cooldown may have run out mid-air (e.g. a long bounce chain)
        if jumpCooldownRemaining <= 0 && !isGameOver { onJumpReadyChanged?(true) }
        player.setScale(1)
        player.zPosition = playerGroundZ
        shadow.isHidden = true
        shadow.setScale(1)
        shadow.alpha = 0.35
    }

    private func flashCooldownBar() {
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.2, duration: 0.08),
            SKAction.fadeAlpha(to: 1, duration: 0.08)
        ])
        cooldownBarFill.run(SKAction.repeat(flash, count: 3), withKey: "ready")
    }

    override func didEvaluateActions() {
        // Keep the shadow under the player while the lane-change action moves it
        shadow.position = player.position
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
            case .keyboardSpacebar, .keyboardUpArrow:
                jump()
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

        updateJump(dt: dt)
        let effectiveSpeed = scrollSpeed + jumpBoost
        distanceScore += effectiveSpeed * CGFloat(dt) * pointsPerDistance
        refreshScoreLabel()

        for road in roads {
            road.position.y -= effectiveSpeed * CGFloat(dt)
            if road.position.y <= -size.height {
                road.position.y += size.height * 2
            }
        }

        spawnTraffic()
        updateNPCs(dt: dt, playerSpeed: effectiveSpeed)
        checkCollisions()
    }

    // MARK: - NPC cars

    // TrafficSpawner decides what appears and when; the scene only builds the nodes
    private func spawnTraffic() {
        for request in spawner.tick(now: elapsedTime) {
            let car = NPCCar(
                lane: request.lane,
                speed: request.speed,
                isParked: request.isParked,
                isWall: request.isWall,
                tint: request.isParked && !request.isWall ? parkedColor : nil
            )
            car.position = CGPoint(x: xPosition(forLane: car.lane), y: size.height + car.size.height / 2)
            car.zPosition = 5
            addChild(car)
            npcs.append(car)
        }
    }

    private func updateNPCs(dt: TimeInterval, playerSpeed: CGFloat) {
        let removeBelow = -size.height / 2
        let removeAbove = size.height * 4
        matchSpeedsWithCarsAhead()
        for car in npcs {
            // Parked cars have speed 0, so they move at the full scroll speed
            car.position.y -= (playerSpeed - car.forwardSpeed) * CGFloat(dt)
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
        let moving = npcs.filter { !$0.isParked }
        for lane in 1...laneCount {
            let inLane = moving.filter { $0.lane == lane }.sorted { $0.position.y < $1.position.y }
            guard inLane.count > 1 else { continue }
            // Walk from the front car backwards so a slowed car passes its speed on down the line
            for i in stride(from: inLane.count - 2, through: 0, by: -1) {
                let behind = inLane[i]
                let ahead = inLane[i + 1]
                let gap = ahead.position.y - behind.position.y - (ahead.size.height + behind.size.height) / 2
                if gap < followDistance, behind.forwardSpeed > ahead.forwardSpeed {
                    behind.forwardSpeed = ahead.forwardSpeed
                }
            }
        }
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
        jumpBoost = 0
        cooldownBarFill.removeAction(forKey: "ready")
        onJumpReadyChanged?(false)

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
