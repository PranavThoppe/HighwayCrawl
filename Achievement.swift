import Foundation

struct Achievement {
    let id: String
    let name: String
    let detail: String
}

enum AchievementID {
    static let firstMiles = "first_miles"
    static let firstJump = "first_jump"
    static let firstRoof = "first_roof"
    static let firstWall = "first_wall"
    static let firstAmbulance = "first_ambulance"
    static let score5k = "score_5k"
    static let score10k = "score_10k"
    static let score25k = "score_25k"
    static let score50k = "score_50k"
    static let combo2 = "combo_2"
    static let combo4 = "combo_4"
    static let combo6 = "combo_6"
    static let hopParked = "hop_parked"
    static let hopAmbulance = "hop_ambulance"
    static let lifetimeRoofs25 = "lifetime_roofs_25"
    static let lifetimeRoofs100 = "lifetime_roofs_100"
}

enum AchievementCatalog {
    static let all: [Achievement] = [
        Achievement(id: AchievementID.firstMiles, name: "On the Asphalt", detail: "Finish any run (crash or stall)"),
        Achievement(id: AchievementID.firstJump, name: "Airborne", detail: "Jump once"),
        Achievement(id: AchievementID.firstRoof, name: "Hood Ornament", detail: "Bounce off any car roof"),
        Achievement(id: AchievementID.firstWall, name: "Over the Wall", detail: "Clear a box-truck wall without crashing"),
        Achievement(id: AchievementID.firstAmbulance, name: "Sirens", detail: "Survive the first ambulance pass"),
        Achievement(id: AchievementID.score5k, name: "Rush Hour", detail: "Score 5,000 (ambulance unlock)"),
        Achievement(id: AchievementID.score10k, name: "High Occupancy", detail: "Score 10,000"),
        Achievement(id: AchievementID.score25k, name: "Open Road", detail: "Score 25,000"),
        Achievement(id: AchievementID.score50k, name: "Highway Royalty", detail: "Score 50,000"),
        Achievement(id: AchievementID.combo2, name: "Double Bounce", detail: "2-car roof chain"),
        Achievement(id: AchievementID.combo4, name: "Traffic Hopper", detail: "4-car roof chain"),
        Achievement(id: AchievementID.combo6, name: "Roof Tour", detail: "6-car roof chain"),
        Achievement(id: AchievementID.hopParked, name: "Soft Shoulder", detail: "Bounce off a parked (yellow) shoulder car"),
        Achievement(id: AchievementID.hopAmbulance, name: "Wrong Way EMT", detail: "Bounce off the ambulance"),
        Achievement(id: AchievementID.lifetimeRoofs25, name: "Rooftop Regular", detail: "25 roof bounces lifetime"),
        Achievement(id: AchievementID.lifetimeRoofs100, name: "Interstate Acrobat", detail: "100 roof bounces lifetime")
    ]
}

enum AchievementStore {
    private static let unlockedKey = "HighwayCrawl.unlockedAchievementIDs"
    private static let roofBouncesKey = "HighwayCrawl.lifetimeRoofBounces"
    private static let defaults = UserDefaults.standard

    static func isUnlocked(_ id: String) -> Bool {
        unlockedIDs().contains(id)
    }

    @discardableResult
    static func jumped() -> [Achievement] {
        compactUnlock(AchievementID.firstJump)
    }

    @discardableResult
    static func finishedRun() -> [Achievement] {
        compactUnlock(AchievementID.firstMiles)
    }

    @discardableResult
    static func scored(_ score: Int) -> [Achievement] {
        var newly: [Achievement] = []
        if score >= 5_000 { newly += compactUnlock(AchievementID.score5k) }
        if score >= 10_000 { newly += compactUnlock(AchievementID.score10k) }
        if score >= 25_000 { newly += compactUnlock(AchievementID.score25k) }
        if score >= 50_000 { newly += compactUnlock(AchievementID.score50k) }
        return newly
    }

    @discardableResult
    static func clearedWall() -> [Achievement] {
        compactUnlock(AchievementID.firstWall)
    }

    @discardableResult
    static func survivedAmbulance() -> [Achievement] {
        compactUnlock(AchievementID.firstAmbulance)
    }

    @discardableResult
    static func bounced(combo: Int, isParked: Bool, isAmbulance: Bool, isWall: Bool) -> [Achievement] {
        var newly = compactUnlock(AchievementID.firstRoof)
        if combo >= 2 { newly += compactUnlock(AchievementID.combo2) }
        if combo >= 4 { newly += compactUnlock(AchievementID.combo4) }
        if combo >= 6 { newly += compactUnlock(AchievementID.combo6) }
        if isParked && !isWall { newly += compactUnlock(AchievementID.hopParked) }
        if isAmbulance { newly += compactUnlock(AchievementID.hopAmbulance) }
        if isWall { newly += compactUnlock(AchievementID.firstWall) }

        let bounces = defaults.integer(forKey: roofBouncesKey) + 1
        defaults.set(bounces, forKey: roofBouncesKey)
        if bounces >= 25 { newly += compactUnlock(AchievementID.lifetimeRoofs25) }
        if bounces >= 100 { newly += compactUnlock(AchievementID.lifetimeRoofs100) }
        return newly
    }

    private static func unlockedIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: unlockedKey) ?? [])
    }

    private static func compactUnlock(_ id: String) -> [Achievement] {
        [unlock(id)].compactMap { $0 }
    }

    private static func unlock(_ id: String) -> Achievement? {
        var ids = unlockedIDs()
        guard ids.insert(id).inserted else { return nil }
        defaults.set(Array(ids), forKey: unlockedKey)
        return AchievementCatalog.all.first { $0.id == id }
    }
}

enum HighScoreStore {
    private static let key = "HighwayCrawl.highScore"
    private static let defaults = UserDefaults.standard

    static var best: Int { defaults.integer(forKey: key) }

    /// Saves `max(best, score)`. Returns true only when an existing (non-zero) best was beaten.
    @discardableResult
    static func submit(_ score: Int) -> Bool {
        let previous = best
        if score > previous {
            defaults.set(score, forKey: key)
        }
        return previous > 0 && score > previous
    }

    static func formatted(_ score: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: score)) ?? "\(score)"
    }
}
