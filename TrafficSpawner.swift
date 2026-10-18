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
    /// True for the cars of a jump-required wall, so the scene can give them a distinct look.
    var isWall: Bool = false
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

    // Parked cars (shoulders only)

    /// Chance per spawn tick of trying a parked car on a shoulder, at difficulty 0 and 1.
    var easyParkedChance = 0.25
    var hardParkedChance = 0.5

    // Walls

    /// The jump cooldown the player has. A wall is never closer than `wallMinGap` to the previous one.
    var jumpCooldown: TimeInterval = 3.0
    /// Extra spacing between walls on top of the cooldown, so the jump is surely ready again.
    var wallSpacingMargin: TimeInterval = 1.5
    /// Earliest arrival of the first wall in a run.
    var firstWallArrival: TimeInterval = 12
    /// Extra seconds between walls at difficulty 0 and 1 (walls are rare early, frequent later).
    var easyWallExtraGap: TimeInterval = 20
    var hardWallExtraGap: TimeInterval = 0
    /// Chance that one shoulder holds a parked car in a wall. The other shoulder is always empty.
    var wallShoulderCarChance = 0.75
    /// Regular traffic pauses this long before a wall can be scheduled, so lanes are clear for it.
    var wallPrepTime: TimeInterval = 2.0
    /// Whether the player's jump is ready right now. Set by the scene; a wall is only scheduled
    /// while this returns true.
    var isJumpReady: () -> Bool = { true }

    /// Distance a faster car behind keeps before it starts following a slower car ahead
    /// (mirrors the scene's car-following rule).
    var followDistance: CGFloat = 40

    var minimumSlotDuration: TimeInterval { reactionTime + laneChangeTime }
    /// A wall is at least one cooldown plus a margin after the previous wall.
    var wallMinGap: TimeInterval { jumpCooldown + wallSpacingMargin }
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
        var end: TimeInterval
        let lane: Int
        var isShoulder: Bool
    }

    private var slots: [Slot] = []
    private var lastShoulderSlotStart: TimeInterval = -.infinity
    private var pending: [SpawnRequest] = []
    private var lastSpawnInLane: [Int: (spawnAt: TimeInterval, speed: CGFloat)] = [:]
    private var nextTickTime: TimeInterval = 0
    /// Blocking windows (padded) of every car scheduled so far, any lane.
    private var scheduledWindows: [(start: TimeInterval, end: TimeInterval)] = []
    /// Time ranges (wall plus landing slot) in which no regular car may block the player's line.
    private var wallZones: [(start: TimeInterval, end: TimeInterval)] = []
    /// Earliest time at which the next wall may reach the player's line.
    private var wallEarliestArrival: TimeInterval = 0

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
        scheduledWindows.removeAll()
        wallZones.removeAll()
        wallEarliestArrival = firstWallArrival
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
        scheduledWindows.removeAll { $0.end < now - 1 }
        wallZones.removeAll { $0.end < now - 1 }

        if now >= gracePeriod, now >= nextTickTime {
            let d = difficulty(at: now)
            nextTickTime = now + lerp(easySpawnInterval, hardSpawnInterval, d) * Double.random(in: 0.8...1.2)

            // Walls take priority: while one is due, regular traffic holds back so the lanes
            // are clear for it.
            var holdTraffic = false
            if isJumpReady() {
                switch scheduleWall(now: now) {
                case .scheduled:
                    holdTraffic = true
                case .blocked:
                    holdTraffic = true
                case .notDue:
                    holdTraffic = isWallApproaching(now: now)
                }
            }

            if !holdTraffic {
                spawnRegularTraffic(now: now, difficulty: d)
            }
        }

        return popDueSpawns(now: now)
    }

    private func spawnRegularTraffic(now: TimeInterval, difficulty d: Double) {
        let attempts = Int(lerp(Double(easyAttempts), Double(hardAttempts), d).rounded())
        let range = speedRange(at: now)
        for _ in 0..<max(1, attempts) {
            let lane = Int.random(in: 1...laneCount)
            let speed = CGFloat.random(in: range)
            if schedule(lane: lane, speed: speed, isParked: false, spawnAt: now) { break }
        }

        // Parked cars only ever appear on the shoulders. They go through the same corridor check,
        // so a shoulder that is the safe lane of a slot never holds one during that slot.
        if Double.random(in: 0..<1) < lerp(easyParkedChance, hardParkedChance, d) {
            let shoulders = [0, laneCount + 1].shuffled()
            for lane in shoulders {
                if schedule(lane: lane, speed: 0, isParked: true, spawnAt: now) { break }
            }
        }
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
        if request.spawnAt >= (lastSpawnInLane[request.lane]?.spawnAt ?? -.infinity) {
            lastSpawnInLane[request.lane] = (request.spawnAt, request.speed)
        }
        let window = blockingWindow(speed: request.speed, spawnAt: request.spawnAt)
        scheduledWindows.append((window.start, window.end))
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
        if wallZones.contains(where: { $0.start < window.end && $0.end > window.start }) { return false }
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

        // The lane's latest request is a future spawn (a wall car). This car appears below it,
        // so it must not be faster (it would catch the wall car and end up in the wall) and
        // must leave room at the moment the wall car appears.
        if spawnAt < last.spawnAt {
            guard speed <= last.speed else { return nil }
            let room = relativeSpeed(speed) * CGFloat(last.spawnAt - spawnAt)
            return room >= carHeight * 1.5 ? speed : nil
        }

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

    // MARK: - Walls

    private enum WallResult {
        case notDue
        case scheduled
        case blocked
    }

    /// Typical time a wall car needs from its spawn point to the player's line.
    private func typicalWallTravel(at time: TimeInterval) -> TimeInterval {
        let range = speedRange(at: time)
        let slowHalfMid = (range.lowerBound + (range.lowerBound + range.upperBound) / 2) / 2
        return TimeInterval(spawnDistance / relativeSpeed(slowHalfMid))
    }

    /// True shortly before a wall becomes due, while regular traffic should already hold back.
    private func isWallApproaching(now: TimeInterval) -> Bool {
        now + typicalWallTravel(at: now) + wallPrepTime >= wallEarliestArrival
    }

    /// Tries to schedule a wall: all asphalt lanes blocked by cars of one speed, plus (usually)
    /// a parked car on one shoulder. The other shoulder stays empty. All cars reach the player's
    /// line together because each gets its own spawn time. Everything is rejected together if
    /// any part of it conflicts with traffic already scheduled.
    private func scheduleWall(now: TimeInterval) -> WallResult {
        let range = speedRange(at: now)
        let slowHalf = range.lowerBound...((range.lowerBound + range.upperBound) / 2)
        let wallSpeed = CGFloat.random(in: slowHalf)
        let movingTravel = TimeInterval(spawnDistance / relativeSpeed(wallSpeed))
        let parkedTravel = TimeInterval(spawnDistance / relativeSpeed(0))

        // Not yet: the spacing rule says the wall would reach the line later than its natural lead time.
        let earliest = now + movingTravel
        guard wallEarliestArrival <= earliest + 0.25 else { return .notDue }
        let arrival = max(earliest, wallEarliestArrival)

        var requests: [SpawnRequest] = []
        for lane in 1...laneCount {
            requests.append(SpawnRequest(
                lane: lane, speed: wallSpeed, isParked: false,
                spawnAt: arrival - movingTravel, isWall: true
            ))
        }
        // At least one shoulder is always left without a car.
        if Double.random(in: 0..<1) < wallShoulderCarChance {
            let lane = Bool.random() ? 0 : laneCount + 1
            requests.append(SpawnRequest(
                lane: lane, speed: 0, isParked: true,
                spawnAt: arrival - parkedTravel, isWall: true
            ))
        }

        // Every wall car must keep its planned speed (no car ahead for it to catch) and have room.
        for request in requests {
            guard let speed = resolveSameLaneSpeed(
                lane: request.lane, speed: request.speed, isParked: request.isParked, spawnAt: request.spawnAt
            ), abs(speed - request.speed) < 0.001 else { return .blocked }
        }

        // The zone runs from the start of the wall's first blocking window to the end of the last,
        // plus a completely clear slot so the player has somewhere to land.
        let windows = requests.map { blockingWindow(speed: $0.speed, spawnAt: $0.spawnAt) }
        let zoneStart = windows.map(\.start).min() ?? arrival
        let landing = slotDuration(at: arrival)
        let zoneEnd = (windows.map(\.end).max() ?? arrival) + landing

        // No traffic already scheduled may reach the line inside the zone.
        if scheduledWindows.contains(where: { $0.start < zoneEnd && $0.end > zoneStart }) { return .blocked }
        if wallZones.contains(where: { $0.start < zoneEnd && $0.end > zoneStart }) { return .blocked }

        for request in requests { enqueue(request) }
        wallZones.append((zoneStart, zoneEnd))
        holdSafeLane(from: zoneStart, to: zoneEnd)

        let d = difficulty(at: now)
        let extra = lerp(easyWallExtraGap, hardWallExtraGap, d) * Double.random(in: 0.8...1.2)
        wallEarliestArrival = arrival + wallMinGap + extra
        return .scheduled
    }

    /// Replaces the slot timeline over a wall zone with a single slot that keeps the previous
    /// safe lane, so the timeline picks up from a sensible lane once the wall has passed.
    private func holdSafeLane(from start: TimeInterval, to end: TimeInterval) {
        extendSlots(through: start)
        let baseLane = slots.last(where: { $0.start < start })?.lane ?? startLane
        slots.removeAll { $0.start >= start }
        if var last = slots.last, last.end > start {
            last.end = start
            slots[slots.count - 1] = last
        }
        let lane = min(max(baseLane, 1), laneCount)
        slots.append(Slot(start: start, end: end, lane: lane, isShoulder: false))
        lastShoulderSlotStart = slots.filter(\.isShoulder).map(\.start).max() ?? -.infinity
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
