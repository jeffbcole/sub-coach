import Foundation

enum Game {
    static let defaultHalfMinutes = 25
    static let defaultPerHalf = 5
    static let halfLengthChoices = [10, 12, 15, 20, 25, 30, 35, 40, 45]
    static let defaultPositions = ["GK", "LD", "RD", "LM", "RM", "LF", "RF"]
    static let weights: [(value: Double, label: String)] = [(0.75, "Less"), (1, "Normal"), (1.25, "More"), (1.5, "Most")]

    /// 0 = goalkeeper, 1 = defense, 2 = midfield, 3 = forward
    static func group(_ pos: Int) -> Int { pos == 0 ? 0 : pos <= 2 ? 1 : pos <= 4 ? 2 : 3 }

    static func clock(seconds t: Int) -> String { String(format: "%d:%02d", t / 60, t % 60) }

    /// Every field position on, keeper off.
    static func defaultCan(_ count: Int = 7) -> [Bool] { [false] + Array(repeating: true, count: max(0, count - 1)) }

    static func newID() -> String { String(UUID().uuidString.prefix(8)).lowercased() }
}

struct Player: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Position index for each period, nil when on the bench.
    var cells: [Int?]
    /// Which of the 7 positions she can play.
    var can: [Bool]
    var weight: Double
    /// Not at today's game: auto-fill leaves her out.
    var absent = false

    /// Auto-fill can use her: she's here and has at least one position turned on.
    var isAvailable: Bool { !absent && can.contains(true) }
    var periodsPlayed: Int { cells.compactMap { $0 }.count }

    /// Position in a period, nil when benched or past the end of the plan. Views use this because
    /// a cell being removed (fewer periods or positions) can still redraw once against the new plan.
    func cell(_ period: Int) -> Int? { cells.indices.contains(period) ? cells[period] : nil }
    func canPlay(_ pos: Int) -> Bool { can.indices.contains(pos) && can[pos] }
}

extension LineupState {
    // Older saves don't have every field (e.g. halfMinutes); fall back to defaults.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        perHalf = try c.decodeIfPresent(Int.self, forKey: .perHalf) ?? perHalf
        halfMinutes = try c.decodeIfPresent(Int.self, forKey: .halfMinutes) ?? halfMinutes
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? title
        gk1 = try c.decodeIfPresent(String.self, forKey: .gk1) ?? gk1
        gk2 = try c.decodeIfPresent(String.self, forKey: .gk2) ?? gk2
        positions = try c.decodeIfPresent([String].self, forKey: .positions) ?? positions
        players = try c.decodeIfPresent([Player].self, forKey: .players) ?? players
    }
}

extension Player {
    // Rosters saved before `absent` existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        cells = try c.decode([Int?].self, forKey: .cells)
        can = try c.decode([Bool].self, forKey: .can)
        weight = try c.decode(Double.self, forKey: .weight)
        absent = try c.decodeIfPresent(Bool.self, forKey: .absent) ?? false
    }
}

struct LineupState: Codable, Equatable {
    var perHalf: Int = Game.defaultPerHalf
    var halfMinutes: Int = Game.defaultHalfMinutes
    var title: String = ""
    var gk1: String = ""
    var gk2: String = ""
    var positions: [String] = Game.defaultPositions
    /// Line for each position slot (0 keeper, 1 defense, 2 midfield, 3 forward), from the formation.
    var groups: [Int] = Formation.standard.roles.map(\.group)
    var formation: String = Formation.standard.id
    var players: [Player] = []

    var periods: Int { perHalf * 2 }
    /// Players on the field, keeper included.
    var positionCount: Int { positions.count }

    func group(_ pos: Int) -> Int { groups.indices.contains(pos) ? groups[pos] : Game.group(pos) }

    func positionName(_ i: Int) -> String {
        let t = positions.indices.contains(i) ? positions[i].trimmingCharacters(in: .whitespaces) : ""
        return t.isEmpty ? "?" : String(t.prefix(12))
    }

    func minutes(_ periods: Int) -> Int {
        Int((Double(periods * halfMinutes) / Double(perHalf)).rounded())
    }

    /// Start time of period j within a half, e.g. "8:20".
    func startAt(_ j: Int) -> String {
        Game.clock(seconds: Int((Double(j * halfMinutes * 60) / Double(perHalf)).rounded()))
    }

    /// Girls who can be picked as keeper: those here and marked for GK, or everyone here if nobody is.
    var keeperChoices: [Player] {
        let here = players.filter { !$0.absent }
        let marked = here.filter { $0.can[0] }
        return marked.isEmpty ? here : marked
    }

    /// Clamp everything to valid shapes, like the web version's normalize().
    mutating func normalize() {
        perHalf = (1...6).contains(perHalf) ? perHalf : Game.defaultPerHalf
        halfMinutes = (5...60).contains(halfMinutes) ? halfMinutes : Game.defaultHalfMinutes
        if positions.isEmpty { positions = Game.defaultPositions }
        let size = positions.count
        title = String(title.prefix(80))
        let n = periods
        for i in players.indices {
            var c = players[i].cells.map { v -> Int? in
                guard let v, (0..<size).contains(v) else { return nil }
                return v
            }
            if c.count < n { c += Array(repeating: nil, count: n - c.count) }
            players[i].cells = Array(c.prefix(n))
            if players[i].can.count != size { players[i].can = Game.defaultCan(size) }
            if !Game.weights.contains(where: { $0.value == players[i].weight }) { players[i].weight = 1 }
            players[i].name = String(players[i].name.prefix(40))
        }
        let ids = Set(keeperChoices.map(\.id))
        if !gk1.isEmpty && !ids.contains(gk1) { gk1 = "" }
        if !gk2.isEmpty && !ids.contains(gk2) { gk2 = "" }
    }

    /// Keep the current plan and stretch it across a new number of periods per half.
    mutating func setPerHalf(_ n: Int) {
        let old = perHalf
        guard n != old, (1...6).contains(n) else { return }
        for i in players.indices {
            var c: [Int?] = []
            for h in 0..<2 {
                for j in 0..<n {
                    let k = h * old + j * old / n
                    c.append(players[i].cells.indices.contains(k) ? players[i].cells[k] : nil)
                }
            }
            players[i].cells = c
        }
        perHalf = n
    }

    /// A new install's sample team: 11 players and an empty plan (tap Auto-fill to build one).
    static func starter() -> LineupState {
        var s = LineupState()
        s.players = (1...11).map { i in
            Player(id: Game.newID(), name: "Player \(i)", cells: [], can: Game.defaultCan(), weight: 1)
        }
        return s
    }
}
