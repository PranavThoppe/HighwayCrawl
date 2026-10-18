import CoreGraphics
import Foundation

/// A car the scene should create once `spawnAt` has been reached.
struct SpawnRequest {
    let lane: Int
    /// Forward speed in pt/s (0 for parked cars).
    let speed: CGFloat
    let isParked: Bool
    /// Game time (seconds since the run started) at which the car appears above the screen.
    let spawnAt: TimeInterval
}

/// Decides when and where NPC cars spawn. Pure logic: it creates no nodes and never looks at
/// the scene. The scene calls `tick(now:)` every frame and builds a car for each returned request.
///
/// Fairness model
/// --------------
/// Fairness is judged by when a car reaches the player's line and how long it blocks its lane
/// there, not by where it spawns. The future is split into slots; each slot has a "safe lane"
/// that no car may block during that slot, and the safe lane moves at most one lane per slot, so
/// a path through the traffic always exists. The calculation assumes the player is at full speed,
/// which is the hardest case.
final class TrafficSpawner {

    // MARK: - Tunables

    /// Seconds from the start of the run with no spawns.
    var gracePeriod: TimeInterval = 3.0
    /// Seconds for the difficulty to climb from 0 to 1.
    var rampDuration: TimeInterval = 120
    /// Time the player needs to notice a car and to change lane. Used to pad blocking windows.
    var reactionTime: TimeInterval = 0.25
    var laneChangeTime: TimeInterval = 0.18

    /// NPC speed range at difficulty 0 and difficulty 1. Always below the player's normal speed.
    var easySpeedRange: ClosedRange<CGFloat> = 320...380
    var hardSpeedRange: ClosedRange<CGFloat> = 250...420

    /// Slot length at difficulty 0 and 1. Never goes below `minimumSlotDuration`.
    var easySlotDuration: TimeInterval = 0.9
    var hardSlotDuration: TimeInterval = 0.5

    /// Seconds between spawn ticks at difficulty 0 and 1.
    var easySpawnInterval: TimeInterval = 1.0
    var hardSpawnInterval: TimeInterval = 0.45

    /// Random lane/speed combinations tried per tick at difficulty 0 and 1.
    var easyAttempts = 3
    var hardAttempts = 8

    /// A shoulder slot is never followed by another one, and at most one starts per this many seconds.
    var shoulderSlotMinGap: TimeInterval = 6.0
    /// Chance that the safe lane steps onto a shoulder when the budget allows it.
    var shoulderSlotChance = 0.2

    /// Distance a faster car behind keeps before it starts following a slower car ahead
    /// (mirrors the scene's car-following rule).
    var followDistance: CGFloat = 40

    var minimumSlotDuration: TimeInterval { reactionTime + laneChangeTime }
    private var windowPadding: TimeInterval { reactionTime + laneChangeTime }

    // MARK: - Geometry

    private let laneCount: Int
    private let playerSpeed: CGFloat
    private let playerHeight: CGFloat
    private let carHeight: CGFloat
    /// Distance from a car's spawn point to the player's line (centre to centre).
    private let spawnDistance: CGFloat
    /// Distance a car travels on screen between spawning and being removed below the screen.
    private let screenTravel: CGFloat
    private let startLane: Int

    // MARK: - State

    private struct Slot {
        let start: TimeInterval
        let end: TimeInterval
        let lane: Int
        var isShoulder: Bool
    }

    private var slots: [Slot] = []
    private var lastShoulderSlotStart: TimeInterval = -.infinity
    private var pending: [SpawnRequest] = []
    private var lastSpawnInLane: [Int: (spawnAt: TimeInterval, speed: CGFloat)] = [:]
    private var nextTickTime: TimeInterval = 0

    /// - Parameters:
    ///   - laneCount: number of asphalt lanes. Lane 0 and `laneCount + 1` are the shoulders.
    ///   - sceneHeight: height of the scene in points.
    ///   - playerY: y position of the player's centre.
    ///   - playerSpeed: the player's normal (full) speed.
    init(
        laneCount: Int,
        sceneHeight: CGFloat,
        playerY: CGFloat,
        playerSpeed: CGFloat = 500,
        playerHeight: CGFloat = 70,
        carHeight: CGFloat = NPCCar.carSize.height,
        startLane: Int = 2
    ) {
        self.laneCount = laneCount
        self.playerSpeed = playerSpeed
        self.playerHeight = playerHeight
        self.carHeight = carHeight
        let spawnY = sceneHeight + carHeight / 2
        self.spawnDistance = spawnY - playerY
        self.screenTravel = spawnY + sceneHeight / 2
        self.startLane = min(max(startLane, 1), laneCount)
        reset()
    }

    /// Clears all state for a new run.
    func reset() {
        slots.removeAll()
        pending.removeAll()
        lastSpawnInLane.removeAll()
        lastShoulderSlotStart = -.infinity
        nextTickTime = gracePeriod
        slots.append(Slot(start: 0, end: slotDuration(at: 0), lane: startLane, isShoulder: false))
    }

    // MARK: - Difficulty

    /// 0 at the start of the run, 1 once `rampDuration` has passed.
    func difficulty(at time: TimeInterval) -> Double {
        guard rampDuration > 0 else { return 1 }
        return min(1, max(0, time / rampDuration))
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private func slotDuration(at time: TimeInterval) -> TimeInterval {
        max(minimumSlotDuration, lerp(easySlotDuration, hardSlotDuration, difficulty(at: time)))
    }

    private func speedRange(at time: TimeInterval) -> ClosedRange<CGFloat> {
        let d = CGFloat(difficulty(at: time))
        let low = easySpeedRange.lowerBound + (hardSpeedRange.lowerBound - easySpeedRange.lowerBound) * d
        let high = easySpeedRange.upperBound + (hardSpeedRange.upperBound - easySpeedRange.upperBound) * d
        return low...min(high, playerSpeed - 1)
    }

    // MARK: - Public API

    /// Call every frame with the time since the run started. Returns the cars that should
    /// appear now.
    func tick(now: TimeInterval) -> [SpawnRequest] {
        pruneSlots(before: now - 1)

        if now >= gracePeriod, now >= nextTickTime {
            let d = difficulty(at: now)
            nextTickTime = now + lerp(easySpawnInterval, hardSpawnInterval, d) * Double.random(in: 0.8...1.2)

            let attempts = Int(lerp(Double(easyAttempts), Double(hardAttempts), d).rounded())
            let range = speedRange(at: now)
            for _ in 0..<max(1, attempts) {
                let lane = Int.random(in: 1...laneCount)
                let speed = CGFloat.random(in: range)
                if schedule(lane: lane, speed: speed, isParked: false, spawnAt: now) { break }
            }
        }

        return popDueSpawns(now: now)
    }

    /// The lane that is guaranteed to stay free of cars at game time `time`.
    func safeLane(at time: TimeInterval) -> Int {
        extendSlots(through: time)
        return slots.first { time >= $0.start && time < $0.end }?.lane ?? slots[slots.count - 1].lane
    }

    /// Checks a car against the corridor and same-lane rules and, if it passes, adds it to the
    /// pending queue. Returns whether the car was accepted. Also used for parked cars and walls.
    @discardableResult
    func schedule(lane: Int, speed: CGFloat, isParked: Bool, spawnAt: TimeInterval) -> Bool {
        let carSpeed = isParked ? 0 : speed
        guard let finalSpeed = resolveSameLaneSpeed(lane: lane, speed: carSpeed, isParked: isParked, spawnAt: spawnAt) else {
            return false
        }
        guard isCorridorClear(lane: lane, speed: finalSpeed, spawnAt: spawnAt) else { return false }

        enqueue(SpawnRequest(lane: lane, speed: finalSpeed, isParked: isParked, spawnAt: spawnAt))
        return true
    }

    /// Adds a request without any checks. For callers that have already validated it.
    func enqueue(_ request: SpawnRequest) {
        let index = pending.firstIndex { $0.spawnAt > request.spawnAt } ?? pending.count
        pending.insert(request, at: index)
        lastSpawnInLane[request.lane] = (request.spawnAt, request.speed)
    }

    // MARK: - Pending queue

    private func popDueSpawns(now: TimeInterval) -> [SpawnRequest] {
        guard let firstFuture = pending.firstIndex(where: { $0.spawnAt > now }) else {
            defer { pending.removeAll() }
            return pending
        }
        let due = Array(pending[..<firstFuture])
        pending.removeFirst(firstFuture)
        return due
    }

    // MARK: - Arrival timing

    /// Speed of a car relative to the player (how fast it moves down the screen).
    private func relativeSpeed(_ carSpeed: CGFloat) -> CGFloat { max(playerSpeed - carSpeed, 1) }

    /// The period during which a car overlaps the player's line, padded by reaction time plus
    /// lane-change time so the player can see it coming and get out of the way.
    private func blockingWindow(speed: CGFloat, spawnAt: TimeInterval) -> (start: TimeInterval, end: TimeInterval) {
        let rel = relativeSpeed(speed)
        let arrival = spawnAt + TimeInterval(spawnDistance / rel)
        let halfBlock = TimeInterval((carHeight + playerHeight) / 2 / rel)
        return (arrival - halfBlock - windowPadding, arrival + halfBlock + windowPadding)
    }

    private func isCorridorClear(lane: Int, speed: CGFloat, spawnAt: TimeInterval) -> Bool {
        let window = blockingWindow(speed: speed, spawnAt: spawnAt)
        extendSlots(through: window.end)
        for slot in slots where slot.lane == lane && slot.start < window.end && slot.end > window.start {
            return false
        }
        return true
    }

    // MARK: - Same-lane rule

    /// The scene makes a faster car slow down once it closes in on a slower car ahead of it
    /// (the car spawned later is the one ahead, since cars appear at the top). That would move
    /// the faster car's planned arrival time, so a new car that would be caught is raised to
    /// the speed of the car behind it instead. If the car behind can't catch it before the
    /// new car leaves the screen, the speed is left alone.
    /// Returns nil if the lane is still too crowded at the spawn point.
    private func resolveSameLaneSpeed(lane: Int, speed: CGFloat, isParked: Bool, spawnAt: TimeInterval) -> CGFloat? {
        guard let last = lastSpawnInLane[lane] else { return speed }

        let elapsed = CGFloat(spawnAt - last.spawnAt)
        let relLast = relativeSpeed(last.speed)
        // Last car already left the screen: nothing to catch or collide with.
        guard relLast * elapsed < screenTravel else { return speed }

        // Distance left between the last car and the new car, nose to tail.
        let gap = relLast * elapsed
        let minSpawnGap = carHeight * 1.5
        guard gap >= minSpawnGap else { return nil }

        // A parked car can't slow down, and a car that isn't slower than the one behind
        // can't be caught.
        guard !isParked, speed < last.speed else { return speed }

        let relNew = relativeSpeed(speed)
        let catchGap = carHeight + followDistance
        let closing = relNew - relLast
        let catchTime = max(0, (gap - catchGap) / closing)
        let leaveTime = screenTravel / relNew
        return catchTime < leaveTime ? last.speed : speed
    }

    // MARK: - Slot timeline

    private func extendSlots(through time: TimeInterval) {
        while let last = slots.last, last.end <= time {
            slots.append(makeSlot(after: last))
        }
    }

    private func pruneSlots(before time: TimeInterval) {
        while slots.count > 1, slots[0].end < time {
            slots.removeFirst()
        }
    }

    private func makeSlot(after previous: Slot) -> Slot {
        let start = previous.end
        let end = start + slotDuration(at: start)
        let lane = nextSafeLane(after: previous, startingAt: start)
        let isShoulder = lane == 0 || lane == laneCount + 1
        if isShoulder { lastShoulderSlotStart = start }
        return Slot(start: start, end: end, lane: lane, isShoulder: isShoulder)
    }

    /// The safe lane moves at most one lane per slot. Shoulders are only allowed within the
    /// budget: never two in a row and at most one starting per `shoulderSlotMinGap`.
    private func nextSafeLane(after previous: Slot, startingAt start: TimeInterval) -> Int {
        let shoulderAllowed = !previous.isShoulder && start - lastShoulderSlotStart >= shoulderSlotMinGap

        var asphalt: [Int] = []
        var shoulders: [Int] = []
        for candidate in [previous.lane - 1, previous.lane, previous.lane + 1] {
            guard candidate >= 0, candidate <= laneCount + 1 else { continue }
            let isShoulder = candidate == 0 || candidate == laneCount + 1
            if isShoulder {
                if shoulderAllowed { shoulders.append(candidate) }
            } else {
                asphalt.append(candidate)
            }
        }

        if let shoulder = shoulders.randomElement(), Double.random(in: 0..<1) < shoulderSlotChance {
            return shoulder
        }
        // Prefer staying put; otherwise step to a neighbour.
        if asphalt.contains(previous.lane), Double.random(in: 0..<1) < 0.4 {
            return previous.lane
        }
        return asphalt.randomElement() ?? previous.lane
    }
}
