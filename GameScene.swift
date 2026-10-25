import SpriteKit
import UIKit

class GameScene: SKScene {
    private static let driveTexture: SKTexture = {
        let texture = SKTexture(imageNamed: "roadster.white")
        texture.filteringMode = .linear
        return texture
    }()
    private static let driveSize: CGSize = {
        let pixels = driveTexture.size()
        // Keep the same on-screen height as the old 57px * artScale sprite.
        let targetHeight: CGFloat = 57 * NPCCar.artScale
        let scale = targetHeight / pixels.height
        return CGSize(width: (pixels.width * scale).rounded(), height: targetHeight)
    }()
    private let player = SKSpriteNode(texture: GameScene.driveTexture, size: GameScene.driveSize)

    /// Barrel-roll frames, played across a jump from the ground (not roof bounces).
    /// Every image in the atlas is used, in name order, so frames can be added or removed freely.
    /// Frame names must not contain dots: atlas lookup treats everything after the last dot as an extension.
    private static let rollTextures: [SKTexture] = {
        let atlas = SKTextureAtlas(named: "RoadsterJump")
        return atlas.textureNames.sorted().map { atlas.textureNamed($0) }
    }()
    /// Points per pixel of the roll art, chosen so its car body matches the driving sprite's size.
    private let rollPointsPerPixel: CGFloat = 0.4
    private var isRolling = false
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
    /// Swipe distance that counts as a lane change or jump.
    private let swipeThreshold: CGFloat = 40
    private var swipeOrigin: CGPoint?
    private var didConsumeSwipe = false

    private let asphaltColor = SKColor(white: 0.22, alpha: 1)
    private let shoulderColor = SKColor(red: 0.16, green: 0.14, blue: 0.10, alpha: 1)

    /// Called when the player taps the retry button after a game over.
    var onRetry: (() -> Void)?
    /// Called when the player taps the back button after a game over.
    var onBackToMenu: (() -> Void)?
    /// Called when gameplay stops (crash or shoulder) so the host can hide its controls.
    var onGameOver: (() -> Void)?
    private let retryButtonName = "retryButton"
    private let backButtonName = "backButton"

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
    private let jumpPeakScale: CGFloat = 1.75
    private let playerGroundZ: CGFloat = 4
    private let playerAirZ: CGFloat = 10
    /// Extra speed while airborne. Kept separate from `scrollSpeed` so the shoulder
    /// acceleration/deceleration logic is untouched; added to get the effective speed.
    private var jumpBoost: CGFloat = 0
    private var jumpTimeRemaining: TimeInterval = 0
    /// Counts down from `jumpCooldown`, starting the moment a jump begins.
    private var jumpCooldownRemaining: TimeInterval = 0
    private let cooldownBarBackground = SKSpriteNode(color: SKColor(white: 0, alpha: 0.5), size: CGSize(width: 120, height: 14))
    private let cooldownBarFill = SKSpriteNode(color: .orange, size: CGSize(width: 116, height: 10))
    private let cooldownReadyColor = SKColor(red: 0.3, green: 0.9, blue: 0.4, alpha: 1)

    // Roof bounce and score
    private let bounceAirtime: TimeInterval = 0.35
    private let bouncePeakScale: CGFloat = 1.25
    private let roofBonus = 250
    private let ambulanceBonus = 1000
    /// Distance units earned per point travelled.
    private let pointsPerDistance: CGFloat = 0.1
    /// Duration and peak scale of the hop currently in progress (jump or bounce).
    private var currentAirtime: TimeInterval = 0.85
    private var currentPeakScale: CGFloat = 1.5
    /// Roofs landed on in the current airborne chain; 0 when on the ground.
    private var comboCount = 0
    private var lastBouncedCar: NPCCar?
    /// Set while airborne if the player overlaps a jump-required box-truck wall.
    private var crossedWallWhileAirborne = false
    private var distanceScore: CGFloat = 0
    private var bonusScore = 0
    private var lastScoreCheck = -1
    private var toastAnchor = CGPoint.zero
    private var nextAchievementToastSlot = 0
    private var activeAchievementToasts = 0
    private static let achievementGold = SKColor(red: 0.96, green: 0.78, blue: 0.22, alpha: 1)
    private static let trophyTexture: SKTexture = {
        let config = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        let symbol = UIImage(systemName: "trophy.fill", withConfiguration: config)!
            .withTintColor(UIColor(red: 0.96, green: 0.78, blue: 0.22, alpha: 1), renderingMode: .alwaysOriginal)
        let rendered = UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
        return SKTexture(image: rendered)
    }()

    // Ambulance: after the unlock score, every interval has a chance to send one
    // from behind in the player's lane. The only warning is a red lane flash.
    private let ambulanceUnlockScore = 5000
    private let ambulanceScoreInterval = 1000
    private let ambulanceChance = 0.30
    private let ambulanceWarningTime: TimeInterval = 0.85
    private var nextAmbulanceCheckScore = 0
    private var ambulanceWarningRemaining: TimeInterval = 0
    private var ambulanceLane = 0
    private var laneFlash: SKSpriteNode?

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
        setupToastAnchor(in: view)
        nextAmbulanceCheckScore = ambulanceUnlockScore
    }

    private func setupToastAnchor(in view: SKView) {
        let insets = view.safeAreaInsets
        toastAnchor = CGPoint(
            x: size.width - max(16, insets.right + 16),
            y: size.height - max(24, insets.top + 24)
        )
    }

    private var totalScore: Int { Int(distanceScore) + bonusScore }

    private func checkScoreProgress() {
        let score = totalScore
        guard score != lastScoreCheck else { return }
        lastScoreCheck = score
        showAchievementToasts(AchievementStore.scored(score))
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
        crossedWallWhileAirborne = false
        showAchievementToasts(AchievementStore.jumped())

        player.zPosition = playerAirZ
        isRolling = true
        showRollFrame(0)
        cooldownBarFill.removeAction(forKey: "ready")
        cooldownBarFill.alpha = 1
        cooldownBarFill.color = .orange
        cooldownBarFill.xScale = 0
        onJumpReadyChanged?(false)
        GameHaptics.jump()
    }

    private func updateJump(dt: TimeInterval) {
        if isPlayerAirborne {
            jumpTimeRemaining -= dt
            if jumpTimeRemaining <= 0 {
                endRoll()
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
                if isRolling {
                    showRollFrame(min(Int(progress * CGFloat(Self.rollTextures.count)), Self.rollTextures.count - 1))
                }
                noteWallCrossingIfNeeded()
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

    private func showRollFrame(_ index: Int) {
        let texture = Self.rollTextures[index]
        guard player.texture !== texture else { return }
        let pixels = texture.size()
        player.texture = texture
        player.size = CGSize(width: pixels.width * rollPointsPerPixel, height: pixels.height * rollPointsPerPixel)
    }

    /// Back to the driving sprite. Must run before anything reads the player's size as a hitbox.
    private func endRoll() {
        guard isRolling else { return }
        isRolling = false
        player.texture = Self.driveTexture
        player.size = Self.driveSize
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
            let bonus = car.isAmbulance ? ambulanceBonus : roofBonus * comboCount
            bonusScore += bonus
            checkScoreProgress()
            showBonusLabel(bonus: bonus, combo: car.isAmbulance ? 1 : comboCount)
            showAchievementToasts(AchievementStore.bounced(
                combo: comboCount,
                isParked: car.isParked,
                isAmbulance: car.isAmbulance,
                isWall: car.isWall
            ))
        }
        lastBouncedCar = car

        jumpTimeRemaining = bounceAirtime
        currentAirtime = bounceAirtime
        currentPeakScale = bouncePeakScale
        jumpBoost = jumpBoostSpeed
        player.setScale(1)
        player.zPosition = playerAirZ
        GameHaptics.bounce()
    }

    private func showAchievementToasts(_ achievements: [Achievement]) {
        for achievement in achievements {
            let slot = nextAchievementToastSlot
            nextAchievementToastSlot += 1
            activeAchievementToasts += 1
            presentAchievementToast(achievement, slot: slot)
        }
    }

    /// Gold trophy + name, stacked in the top-right. Several can appear at once.
    private func presentAchievementToast(_ achievement: Achievement, slot: Int) {
        let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
        name.text = achievement.name
        name.fontSize = 16
        name.fontColor = Self.achievementGold
        name.horizontalAlignmentMode = .right
        name.verticalAlignmentMode = .center

        let toast = SKNode()
        toast.addChild(name)

        let icon = SKSpriteNode(texture: Self.trophyTexture)
        icon.anchorPoint = CGPoint(x: 1, y: 0.5)
        icon.position = CGPoint(x: -name.frame.width - 8, y: 0)
        toast.addChild(icon)
        toast.alpha = 0
        toast.zPosition = 32
        toast.position = CGPoint(
            x: toastAnchor.x,
            y: toastAnchor.y - 8 - CGFloat(slot) * 26
        )
        addChild(toast)

        toast.run(SKAction.sequence([
            SKAction.group([
                SKAction.fadeIn(withDuration: 0.15),
                SKAction.moveBy(x: 0, y: 8, duration: 0.2)
            ]),
            SKAction.wait(forDuration: 1.6),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.run { [weak self, weak toast] in
                toast?.removeFromParent()
                guard let self else { return }
                self.activeAchievementToasts -= 1
                if self.activeAchievementToasts == 0 {
                    self.nextAchievementToastSlot = 0
                }
            }
        ]))
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
        if crossedWallWhileAirborne {
            showAchievementToasts(AchievementStore.clearedWall())
        }
        isPlayerAirborne = false
        jumpTimeRemaining = 0
        jumpBoost = 0
        comboCount = 0
        lastBouncedCar = nil
        crossedWallWhileAirborne = false
        // The cooldown may have run out mid-air (e.g. a long bounce chain)
        if jumpCooldownRemaining <= 0 && !isGameOver { onJumpReadyChanged?(true) }
        player.setScale(1)
        player.zPosition = playerGroundZ
    }

    private func flashCooldownBar() {
        guard !GameSettings.reduceFlashing else { return }
        let flash = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.2, duration: 0.08),
            SKAction.fadeAlpha(to: 1, duration: 0.08)
        ])
        cooldownBarFill.run(SKAction.repeat(flash, count: 3), withKey: "ready")
    }

    func changeLane(by delta: Int) {
        guard !isGameOver else { return }
        let nextLane = currentLane + delta
        guard nextLane >= 0, nextLane <= laneCount + 1 else { return }

        currentLane = nextLane
        player.removeAction(forKey: "laneChange")
        player.run(SKAction.moveTo(x: xPosition(forLane: currentLane), duration: 0.18), withKey: "laneChange")
        GameHaptics.laneChange()
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
        if isCrashing {
            stepCrash(dt: dt)
            return
        }
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
        checkScoreProgress()

        for road in roads {
            road.position.y -= effectiveSpeed * CGFloat(dt)
            if road.position.y <= -size.height {
                road.position.y += size.height * 2
            }
        }

        spawnTraffic()
        updateAmbulance(dt: dt)
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

    // MARK: - Ambulance

    private var hasActiveAmbulance: Bool {
        ambulanceWarningRemaining > 0 || npcs.contains { $0.isAmbulance }
    }

    /// Locks the player's lane at warning time. A shoulder becomes the nearest asphalt lane.
    private func lockedAmbulanceLane() -> Int {
        if currentLane == 0 { return 1 }
        if currentLane == laneCount + 1 { return laneCount }
        return currentLane
    }

    private func updateAmbulance(dt: TimeInterval) {
        while totalScore >= nextAmbulanceCheckScore {
            if !hasActiveAmbulance, Double.random(in: 0..<1) < ambulanceChance {
                startAmbulanceWarning()
            }
            nextAmbulanceCheckScore += ambulanceScoreInterval
        }

        guard ambulanceWarningRemaining > 0 else { return }
        ambulanceWarningRemaining -= dt
        if ambulanceWarningRemaining <= 0 {
            ambulanceWarningRemaining = 0
            spawnAmbulance()
        }
    }

    private func startAmbulanceWarning() {
        ambulanceLane = lockedAmbulanceLane()
        ambulanceWarningRemaining = ambulanceWarningTime
        clearLaneFlash()

        let flash = SKSpriteNode(
            color: SKColor(red: 1, green: 0.12, blue: 0.1, alpha: 0.5),
            size: CGSize(width: laneWidth, height: size.height)
        )
        flash.position = CGPoint(x: xPosition(forLane: ambulanceLane), y: size.height / 2)
        flash.zPosition = 2
        addChild(flash)
        laneFlash = flash
        GameHaptics.ambulanceWarning()

        if GameSettings.reduceFlashing {
            flash.alpha = 0.28
        } else {
            flash.alpha = 0.5
            let pulse = SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.18, duration: 0.1),
                SKAction.fadeAlpha(to: 0.55, duration: 0.1)
            ]))
            flash.run(pulse, withKey: "pulse")
        }
    }

    private func spawnAmbulance() {
        clearLaneFlash()
        let car = NPCCar(
            lane: ambulanceLane,
            speed: normalSpeed * 2,
            isAmbulance: true
        )
        car.position = CGPoint(x: xPosition(forLane: ambulanceLane), y: -car.size.height / 2)
        car.zPosition = 6
        addChild(car)
        npcs.append(car)
    }

    private func clearLaneFlash() {
        laneFlash?.removeAllActions()
        laneFlash?.removeFromParent()
        laneFlash = nil
    }

    private func updateNPCs(dt: TimeInterval, playerSpeed: CGFloat) {
        let removeBelow = -size.height / 2
        let removeAbove = size.height * 4
        matchSpeedsWithCarsAhead()
        clearLaneForAmbulance()
        for car in npcs {
            // Parked cars have speed 0, so they move at the full scroll speed
            car.position.y -= (playerSpeed - car.forwardSpeed) * CGFloat(dt)
        }
        npcs.removeAll { car in
            let offscreen = car.position.y < removeBelow || car.position.y > removeAbove
            if offscreen { car.removeFromParent() }
            return offscreen
        }
        if npcs.contains(where: { $0.isAmbulance && $0.position.y > player.position.y }) {
            showAchievementToasts(AchievementStore.survivedAmbulance())
        }
    }

    private func noteWallCrossingIfNeeded() {
        guard !crossedWallWhileAirborne else { return }
        let box = player.frame.insetBy(dx: 4, dy: 6)
        if npcs.contains(where: { $0.isWall && box.intersects($0.frame) }) {
            crossedWallWhileAirborne = true
        }
    }

    /// Cars in the ambulance's lane match its speed so it does not rear-end them.
    /// Also runs during the warning so the lane is already moving when it appears.
    private func clearLaneForAmbulance() {
        let lane: Int
        if let ambulance = npcs.first(where: { $0.isAmbulance }) {
            lane = ambulance.lane
        } else if ambulanceWarningRemaining > 0 {
            lane = ambulanceLane
        } else {
            return
        }

        let speed = normalSpeed * 2
        for car in npcs where car.lane == lane && !car.isAmbulance && !car.isParked {
            if car.forwardSpeed < speed {
                car.forwardSpeed = speed
            }
        }
    }

    // NPCs drive up the screen, so the car "ahead" has the larger y.
    // A faster car that closes within `followDistance` of the car ahead slows to its speed.
    private func matchSpeedsWithCarsAhead() {
        let followDistance: CGFloat = 40
        let moving = npcs.filter { !$0.isParked && !$0.isAmbulance }
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
        let hits = npcs.filter { hitbox.intersects($0.frame) }
        if !hits.isEmpty {
            beginCrash(with: hits, hitbox: hitbox)
        }
    }

    /// Unit push direction away from `car`, along the axis the two overlap least (the side that was hit).
    private func hitDirection(from car: NPCCar, hitbox: CGRect) -> CGVector {
        let overlap = hitbox.intersection(car.frame)
        let dx = player.position.x - car.position.x
        let dy = player.position.y - car.position.y
        if overlap.width < overlap.height {
            return CGVector(dx: dx >= 0 ? 1 : -1, dy: 0)
        }
        return CGVector(dx: 0, dy: dy >= 0 ? 1 : -1)
    }

    /// Short knockback: the hit cars get shoved away (further than the roadster), then the game ends.
    private func beginCrash(with cars: [NPCCar], hitbox: CGRect) {
        stopGameplay()
        player.removeAction(forKey: "laneChange")
        endRoll()
        player.setScale(1)
        player.zPosition = playerAirZ

        // Slide distance = speed / crashDrag, so these give ~130 pt for cars and ~70 pt for the roadster
        let carSpeed = 130 * crashDrag
        let playerSpeed = 70 * crashDrag
        var push = CGVector.zero

        crashBodies = [CrashBody(node: player)]
        crashElapsed = 0
        crashFadeStarted = false
        crashPairs = []
        for car in cars {
            let dir = hitDirection(from: car, hitbox: hitbox)
            push.dx += dir.dx
            push.dy += dir.dy
            let body = CrashBody(node: car)
            body.velocity = CGVector(dx: -dir.dx * carSpeed, dy: -dir.dy * carSpeed)
            body.spin = (dir.dx != 0 ? -dir.dx : dir.dy) * .pi * crashDrag
            crashBodies.append(body)
            // Already handled by the initial hit
            crashPairs.insert([ObjectIdentifier(player), ObjectIdentifier(car)].sorted { $0.hashValue < $1.hashValue })
        }

        // Opposing pushes (a car on each side) cancel, leaving the roadster to sit between them
        let length = max(hypot(push.dx, push.dy), 1)
        let playerBody = crashBodies[0]
        playerBody.velocity = CGVector(dx: push.dx / length * playerSpeed, dy: push.dy / length * playerSpeed)
        playerBody.spin = (push.dx != 0 ? push.dx : -push.dy) / length * 2 * .pi * crashDrag
        isCrashing = true
    }

    /// A node moving during the crash animation.
    private final class CrashBody {
        let node: SKNode
        var velocity = CGVector.zero
        var spin: CGFloat = 0
        init(node: SKNode) { self.node = node }
        var speed: CGFloat { hypot(velocity.dx, velocity.dy) }
    }

    private var isCrashing = false
    private var crashBodies: [CrashBody] = []
    private var crashPairs: Set<[ObjectIdentifier]> = []
    private var crashElapsed: TimeInterval = 0
    private var crashFadeStarted = false
    /// Exponential slowdown rate (1/s) of the crash slide and spin.
    private let crashDrag: CGFloat = 6
    /// Hold on the crash before the screen fades to black.
    private let crashFadeDelay: TimeInterval = 1.0
    private let crashFadeDuration: TimeInterval = 0.4

    private func stepCrash(dt: TimeInterval) {
        let dt = CGFloat(dt)
        crashElapsed += TimeInterval(dt)
        let damping = exp(-crashDrag * dt)

        for body in crashBodies {
            body.node.position.x += body.velocity.dx * dt
            body.node.position.y += body.velocity.dy * dt
            body.node.zRotation += body.spin * dt
            body.velocity.dx *= damping
            body.velocity.dy *= damping
            body.spin *= damping
        }
        resolveCrashChain()

        if !crashFadeStarted, crashElapsed >= crashFadeDelay {
            crashFadeStarted = true
            fadeToGameOver()
        }
    }

    /// Fade the screen to black, then show the game-over UI on top.
    private func fadeToGameOver() {
        let overlay = SKSpriteNode(color: .black, size: size)
        overlay.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlay.zPosition = 40
        overlay.alpha = 0
        addChild(overlay)
        overlay.run(SKAction.sequence([
            SKAction.fadeIn(withDuration: crashFadeDuration),
            SKAction.run { [weak self] in
                self?.isCrashing = false
                self?.showGameOverUI()
            }
        ]))
    }

    /// Unrotated footprint, so a spinning car's bounding box doesn't cause phantom hits.
    private func footprint(of node: SKNode) -> CGRect {
        let size = (node as? SKSpriteNode)?.size ?? .zero
        return CGRect(x: node.position.x - size.width / 2, y: node.position.y - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// A moving car that runs into another car passes some of its momentum on and bounces back a little.
    /// Each pair only collides once.
    private func resolveCrashChain() {
        let bodies = crashBodies
        for mover in bodies where mover.speed > 40 {
            let moverBox = footprint(of: mover.node)
            for other in npcs where other !== mover.node {
                let key = [ObjectIdentifier(mover.node), ObjectIdentifier(other)].sorted { $0.hashValue < $1.hashValue }
                guard !crashPairs.contains(key) else { continue }
                let otherBox = footprint(of: other)
                guard moverBox.intersects(otherBox) else { continue }
                crashPairs.insert(key)

                let overlap = moverBox.intersection(otherBox)
                let dx = other.position.x - mover.node.position.x
                let dy = other.position.y - mover.node.position.y
                let dir = overlap.width < overlap.height
                    ? CGVector(dx: dx >= 0 ? 1 : -1, dy: 0)
                    : CGVector(dx: 0, dy: dy >= 0 ? 1 : -1)

                let hitSpeed = max(mover.speed * 0.8, 60)
                let target = crashBodies.first { $0.node === other } ?? {
                    let body = CrashBody(node: other)
                    crashBodies.append(body)
                    return body
                }()
                target.velocity = CGVector(dx: dir.dx * hitSpeed, dy: dir.dy * hitSpeed)
                target.spin = (dir.dx != 0 ? -dir.dx : dir.dy) * .pi * crashDrag * 0.6

                // The mover rebounds off the car it hit
                let along = mover.velocity.dx * dir.dx + mover.velocity.dy * dir.dy
                mover.velocity.dx -= dir.dx * along * 1.3
                mover.velocity.dy -= dir.dy * along * 1.3
            }
        }
    }

    private func stopGameplay() {
        guard !isGameOver else { return }
        isGameOver = true
        scrollSpeed = 0
        jumpBoost = 0
        cooldownBarFill.removeAction(forKey: "ready")
        ambulanceWarningRemaining = 0
        clearLaneFlash()
        onJumpReadyChanged?(false)
        onGameOver?()
        GameHaptics.crash()
        showAchievementToasts(AchievementStore.finishedRun())
    }

    private func endGame() {
        stopGameplay()
        // Same blackout as a crash death, without the knockback hold
        fadeToGameOver()
    }

    private func showGameOverUI() {
        let bannerTexture = SKTexture(imageNamed: "game.over")
        bannerTexture.filteringMode = .nearest
        let banner = SKSpriteNode(texture: bannerTexture)

        let scoreNode = SKLabelNode(fontNamed: "AvenirNext-Bold")
        scoreNode.text = Self.formattedScore(totalScore)
        scoreNode.fontSize = 36
        scoreNode.fontColor = .white
        scoreNode.horizontalAlignmentMode = .center
        scoreNode.verticalAlignmentMode = .center

        let backButton = makeGameOverButton(systemName: "chevron.left", name: backButtonName)
        let retryButton = makeGameOverButton(systemName: "arrow.clockwise", name: retryButtonName)

        // Fit banner above the score and retry icon so the whole stack stays on screen
        let gap: CGFloat = 20
        let scoreGap: CGFloat = 16
        let retryHeight = retryButton.size.height
        let scoreHeight = max(scoreNode.frame.height, 36)
        let maxStackHeight = size.height * 0.72
        let maxBannerHeight = max(40, maxStackHeight - retryHeight - gap - scoreHeight - scoreGap)
        let maxBannerWidth = size.width * 0.55
        let bannerScale = min(
            maxBannerWidth / max(banner.size.width, 1),
            maxBannerHeight / max(banner.size.height, 1)
        )
        banner.setScale(bannerScale)

        let stackHeight = banner.frame.height + gap + scoreHeight + scoreGap + retryHeight
        let stackTop = size.height / 2 + stackHeight / 2
        banner.position = CGPoint(x: size.width / 2, y: stackTop - banner.frame.height / 2)
        scoreNode.position = CGPoint(
            x: size.width / 2,
            y: banner.position.y - banner.frame.height / 2 - gap - scoreHeight / 2
        )
        retryButton.position = CGPoint(
            x: size.width / 2,
            y: scoreNode.position.y - scoreHeight / 2 - scoreGap - retryHeight / 2
        )

        let insets = view?.safeAreaInsets ?? .zero
        let backPaddingX = max(16, insets.left + 16)
        let backPaddingY = max(24, insets.top + 24)
        backButton.position = CGPoint(
            x: backPaddingX + backButton.size.width / 2,
            y: size.height - backPaddingY - backButton.size.height / 2
        )

        banner.zPosition = 50
        scoreNode.zPosition = 50
        backButton.zPosition = 50
        retryButton.zPosition = 50
        banner.alpha = 0
        scoreNode.alpha = 0
        backButton.alpha = 0
        retryButton.alpha = 0
        addChild(banner)
        addChild(scoreNode)
        addChild(backButton)
        addChild(retryButton)
        banner.run(SKAction.fadeIn(withDuration: 0.25))
        scoreNode.run(SKAction.fadeIn(withDuration: 0.25))
        backButton.run(SKAction.fadeIn(withDuration: 0.25))
        retryButton.run(SKAction.fadeIn(withDuration: 0.25))
    }

    private static func formattedScore(_ score: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: score)) ?? "\(score)"
    }

    /// Plain SF Symbol used as a game-over control.
    /// Rasterized first — SpriteKit often draws template SF Symbols as blank.
    private func makeGameOverButton(systemName: String, name: String) -> SKSpriteNode {
        let config = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        let symbol = UIImage(systemName: systemName, withConfiguration: config)!
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        let rendered = UIGraphicsImageRenderer(size: symbol.size).image { _ in
            symbol.draw(at: .zero)
        }
        let hitSize: CGFloat = 64
        let button = SKSpriteNode(color: .clear, size: CGSize(width: hitSize, height: hitSize))
        button.name = name
        let icon = SKSpriteNode(texture: SKTexture(image: rendered))
        button.addChild(icon)
        return button
    }

    private func resetSwipeTracking() {
        swipeOrigin = nil
        didConsumeSwipe = false
    }

    /// One action per swipe, as soon as the finger travels far enough.
    /// Sideways changes lanes; up jumps. Scene Y increases toward the top of the screen.
    private func handleSwipe(to location: CGPoint) {
        guard !isGameOver, !didConsumeSwipe, let origin = swipeOrigin else { return }
        let dx = location.x - origin.x
        let dy = location.y - origin.y
        guard max(abs(dx), abs(dy)) >= swipeThreshold else { return }

        if abs(dx) > abs(dy) {
            changeLane(by: dx > 0 ? 1 : -1)
        } else if dy > 0 {
            jump()
        } else {
            return
        }
        didConsumeSwipe = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

        if isGameOver {
            let tapped = nodes(at: touch.location(in: self))
            if tapped.contains(where: { $0.name == retryButtonName }) {
                onRetry?()
            } else if tapped.contains(where: { $0.name == backButtonName }) {
                onBackToMenu?()
            }
            return
        }

        swipeOrigin = touch.location(in: self)
        didConsumeSwipe = false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        handleSwipe(to: touch.location(in: self))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let touch = touches.first {
            handleSwipe(to: touch.location(in: self))
        }
        resetSwipeTracking()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        resetSwipeTracking()
    }
}
