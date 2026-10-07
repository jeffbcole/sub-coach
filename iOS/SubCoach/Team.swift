import Foundation

/// A player on the team roster, shared by every saved lineup.
struct RosterPlayer: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    /// Role name -> can she play it. Roles never set are guessed from the rest of that line.
    var prefs: [String: Bool]
    var weight: Double

    func canPlay(_ r: Role) -> Bool {
        prefs[r.rawValue] ?? r.lineMates.contains { prefs[$0.rawValue] == true }
    }
}

extension RosterPlayer {
    private enum OldKeys: String, CodingKey { case can }

    // Saves from before formations stored a 7-item `can` list in 2-2-2 order.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        weight = try c.decodeIfPresent(Double.self, forKey: .weight) ?? 1
        if let p = try c.decodeIfPresent([String: Bool].self, forKey: .prefs) {
            prefs = p
        } else {
            let old = try decoder.container(keyedBy: OldKeys.self)
            let can = try old.decodeIfPresent([Bool].self, forKey: .can) ?? Game.defaultCan()
            prefs = [:]
            for (i, r) in Formation.standard.roles.enumerated() where can.indices.contains(i) { prefs[r.rawValue] = can[i] }
        }
    }
}

/// One saved lineup: the plan and game-day choices for one game.
struct SavedLineup: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var updated: Date
    var perHalf: Int
    var halfMinutes: Int
    var formation: String = Formation.standard.id
    var gk1: String = ""
    var gk2: String = ""
    /// Players not at this game.
    var absent: [String] = []
    /// Player id -> position for each period (nil = bench).
    var cells: [String: [Int?]] = [:]
    /// Set when this lineup came from another coach's broadcast; lets the coach follow it again.
    var broadcast: BroadcastLink? = nil

    var displayName: String {
        let t = name.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Untitled lineup" : t
    }
}

extension SavedLineup {
    // Fields added later (like formation) fall back to defaults for older saves.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        updated = try c.decodeIfPresent(Date.self, forKey: .updated) ?? .now
        perHalf = try c.decodeIfPresent(Int.self, forKey: .perHalf) ?? 3
        halfMinutes = try c.decodeIfPresent(Int.self, forKey: .halfMinutes) ?? Game.defaultHalfMinutes
        formation = try c.decodeIfPresent(String.self, forKey: .formation) ?? Formation.standard.id
        gk1 = try c.decodeIfPresent(String.self, forKey: .gk1) ?? ""
        gk2 = try c.decodeIfPresent(String.self, forKey: .gk2) ?? ""
        absent = try c.decodeIfPresent([String].self, forKey: .absent) ?? []
        cells = try c.decodeIfPresent([String: [Int?]].self, forKey: .cells) ?? [:]
        broadcast = try c.decodeIfPresent(BroadcastLink.self, forKey: .broadcast)
    }
}

/// Which broadcast a followed lineup belongs to.
struct BroadcastLink: Codable, Equatable {
    var session: String
    var hostID: String
    var hostName: String
}

/// Everything the app saves: the roster plus all saved lineups.
struct TeamData: Codable, Equatable {
    var roster: [RosterPlayer] = []
    var lineups: [SavedLineup] = []
    var currentID: String = ""

    func lineup(_ id: String) -> SavedLineup? { lineups.first { $0.id == id } }

    /// The working copy the screens and auto-fill use: roster + one lineup combined.
    func state(for id: String) -> LineupState? {
        guard let l = lineup(id) else { return nil }
        let away = Set(l.absent)
        var s = LineupState()
        s.perHalf = l.perHalf
        s.halfMinutes = l.halfMinutes
        s.title = l.name
        s.gk1 = l.gk1
        s.gk2 = l.gk2
        let f = Formation.named(l.formation)
        s.formation = f.id
        s.positions = f.roles.map(\.name)
        s.groups = f.roles.map(\.group)
        s.players = roster.map { r in
            Player(id: r.id, name: r.name, cells: l.cells[r.id] ?? [], can: f.roles.map(r.canPlay), weight: r.weight, absent: away.contains(r.id))
        }
        s.normalize()
        return s
    }

    /// Store an edited working copy back: players go to the roster, the rest to the lineup.
    mutating func apply(_ s: LineupState, to id: String, now: Date = .now) {
        guard let i = lineups.firstIndex(where: { $0.id == id }) else { return }
        // Only record a preference when it differs from what's already there (or guessed),
        // so roles this formation doesn't use keep following the rest of their line.
        let roles = Formation.named(lineups[i].formation).roles
        let before = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, $0) })
        roster = s.players.map { p in
            var r = before[p.id] ?? RosterPlayer(id: p.id, name: p.name, prefs: [:], weight: p.weight)
            r.name = p.name
            r.weight = p.weight
            for (slot, role) in roles.enumerated() where p.can.indices.contains(slot) {
                if before[p.id] == nil || r.canPlay(role) != p.can[slot] { r.prefs[role.rawValue] = p.can[slot] }
            }
            return r
        }
        var l = lineups[i]
        l.name = s.title
        l.perHalf = s.perHalf
        l.halfMinutes = s.halfMinutes
        l.gk1 = s.gk1
        l.gk2 = s.gk2
        l.absent = s.players.filter(\.absent).map(\.id)
        l.cells = Dictionary(uniqueKeysWithValues: s.players.map { ($0.id, $0.cells) })
        if l != lineups[i] { l.updated = now }
        lineups[i] = l
    }

    /// Switch a lineup's formation. Girls keep their spot if the new formation has it,
    /// otherwise move to a free spot in the same line; anyone left over goes to the bench.
    mutating func setFormation(_ newID: String, for id: String) {
        guard let i = lineups.firstIndex(where: { $0.id == id }) else { return }
        let old = Formation.named(lineups[i].formation), new = Formation.named(newID)
        guard old != new else { return }
        var cells = lineups[i].cells
        let periods = lineups[i].perHalf * 2
        for p in 0..<periods {
            var taken = Set<Int>()
            var leftover: [(String, Role)] = []
            for (pid, c) in cells.sorted(by: { $0.key < $1.key }) {
                guard c.indices.contains(p), let slot = c[p], old.roles.indices.contains(slot) else { continue }
                let role = old.roles[slot]
                if let n = new.roles.firstIndex(of: role), !taken.contains(n) {
                    cells[pid]![p] = n
                    taken.insert(n)
                } else {
                    leftover.append((pid, role))
                }
            }
            for (pid, role) in leftover {
                if let n = new.roles.indices.first(where: { new.roles[$0].group == role.group && !taken.contains($0) }) {
                    cells[pid]![p] = n
                    taken.insert(n)
                } else {
                    cells[pid]![p] = nil
                }
            }
        }
        lineups[i].cells = cells
        lineups[i].formation = new.id
        lineups[i].updated = .now
    }

    /// Make sure there is always at least one lineup and a valid current one.
    mutating func repair() {
        if lineups.isEmpty {
            lineups = [SavedLineup(id: Game.newID(), name: "Lineup 1", updated: .now, perHalf: 3, halfMinutes: Game.defaultHalfMinutes)]
        }
        if lineup(currentID) == nil {
            currentID = lineups.max { $0.updated < $1.updated }!.id
        }
    }

    /// Turn a save from before saved lineups existed into a roster + one lineup.
    static func migrating(from old: LineupState) -> TeamData {
        var t = TeamData()
        let id = Game.newID()
        var s = old
        if s.title.trimmingCharacters(in: .whitespaces).isEmpty { s.title = "Lineup 1" }
        t.lineups = [SavedLineup(id: id, name: s.title, updated: .now, perHalf: s.perHalf, halfMinutes: s.halfMinutes)]
        t.currentID = id
        t.apply(s, to: id)
        return t
    }
}

extension TeamData {
    // Older saves have extra keys (like positions) or are missing newer ones.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        roster = try c.decodeIfPresent([RosterPlayer].self, forKey: .roster) ?? []
        lineups = try c.decodeIfPresent([SavedLineup].self, forKey: .lineups) ?? []
        currentID = try c.decodeIfPresent(String.self, forKey: .currentID) ?? ""
    }
}
