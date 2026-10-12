import Foundation

/// What changes when a period starts.
struct PeriodChanges {
    struct Swap: Identifiable {
        let pos: Int
        let player: Player
        /// Who had that spot last period and is coming off, if anyone.
        let replacing: Player?
        var id: String { player.id }
    }
    struct Move: Identifiable {
        let player: Player
        let from: Int, to: Int
        var id: String { player.id }
    }
    var swaps: [Swap] = []
    /// Coming off without someone taking her exact spot.
    var off: [Player] = []
    var moves: [Move] = []
    var isEmpty: Bool { swaps.isEmpty && off.isEmpty && moves.isEmpty }
}

extension LineupState {
    var halfSeconds: TimeInterval { TimeInterval(halfMinutes * 60) }
    var periodSeconds: TimeInterval { halfSeconds / Double(perHalf) }

    /// Who is where in period p, in position order.
    func lineup(at p: Int) -> [(pos: Int, player: Player)] {
        (0..<positionCount).compactMap { pos in
            players.first { $0.cell(p) == pos }.map { (pos, $0) }
        }
    }

    func changes(at p: Int) -> PeriodChanges {
        var c = PeriodChanges()
        guard p > 0, p < periods else { return c }
        // Compared with the end of the last period, after any subs made during it.
        let before = positions(atEndOf: p - 1)
        var replaced = Set<String>()
        for pos in 0..<positionCount {
            for x in players where x.cell(p) == pos && before[x.id] == nil {
                let prev = players.first { before[$0.id] == pos && $0.cell(p) == nil && !replaced.contains($0.id) }
                if let prev { replaced.insert(prev.id) }
                c.swaps.append(.init(pos: pos, player: x, replacing: prev))
            }
        }
        c.off = players.filter { before[$0.id] != nil && $0.cell(p) == nil && !replaced.contains($0.id) }
        c.moves = players.compactMap { x -> PeriodChanges.Move? in
            guard let a = before[x.id], let b = x.cell(p), a != b else { return nil }
            return .init(player: x, from: a, to: b)
        }
        .sorted { $0.to < $1.to }
        return c
    }

    /// There are subs to call at the start of period p (a half's kickoff doesn't count).
    func hasSubs(at p: Int) -> Bool { p % perHalf != 0 && p < periods && !changes(at: p).isEmpty }

    /// The first period from `from` up to the end of that half with subs to call.
    func nextSubPeriod(from: Int) -> Int? {
        let end = (from / perHalf + 1) * perHalf
        return (from..<end).first { hasSubs(at: $0) }
    }

    /// Game Day shows a card for each kickoff, each period with subs to call, and any period
    /// with subs made during it. Periods where nothing changes are left out.
    func showsCard(_ p: Int) -> Bool { p % perHalf == 0 || hasSubs(at: p) || !subs(in: p).isEmpty }

    /// e.g. "GK Ava · LD Mia · RD Zoe …"
    func lineupSummary(at p: Int) -> String {
        lineup(at: p).map { "\(positionName($0.pos)) \($0.player.name.isEmpty ? "?" : $0.player.name)" }.joined(separator: " · ")
    }

    /// One-line version for notifications, e.g. "Ava in at LF for Mia · Off: Zoe".
    func changeSummary(at p: Int) -> String {
        let c = changes(at: p)
        if c.isEmpty { return "No changes." }
        func nm(_ x: Player) -> String { x.name.isEmpty ? "?" : x.name }
        var parts = c.swaps.map { s in
            "\(nm(s.player)) in at \(positionName(s.pos))" + (s.replacing.map { " for \(nm($0))" } ?? "")
        }
        if !c.off.isEmpty { parts.append("Off: " + c.off.map(nm).joined(separator: ", ")) }
        parts += c.moves.map { "\(nm($0.player)) \(positionName($0.from)) → \(positionName($0.to))" }
        return parts.joined(separator: " · ")
    }
}

/// The game clock. Counts up within each half, like the referee's watch.
struct GameClock: Codable, Equatable {
    enum Phase: String, Codable { case ready, running, paused }
    var phase: Phase = .ready
    var half = 0
    /// Seconds played in this half before `startedAt`.
    var accumulated: TimeInterval = 0
    var startedAt: Date?
    /// The saved lineup this game is being played with.
    var lineupID: String?

    func elapsed(at now: Date, halfSeconds: TimeInterval) -> TimeInterval {
        var e = accumulated
        if phase == .running, let s = startedAt { e += now.timeIntervalSince(s) }
        return min(max(e, 0), halfSeconds)
    }

    struct Reading: Equatable {
        var started = false
        var half = 0
        var elapsed: TimeInterval = 0
        var halfOver = false
        /// Overall period being played (0-based), nil before kickoff.
        var period: Int?
        /// Clock time of the next sub in this half, if there is one (periods with nothing to
        /// change are skipped).
        var nextSubAt: TimeInterval?
        /// The period that next sub starts.
        var nextSubPeriod: Int?
        /// The current period started with subs to call.
        var periodHasSubs = false
        /// Seconds since the current period started.
        var sincePeriodStart: TimeInterval = 0
        var gameOver: Bool { halfOver && half == 1 }
    }

    func reading(at now: Date, _ s: LineupState) -> Reading {
        guard phase != .ready else {
            let n = s.nextSubPeriod(from: 1)
            return Reading(nextSubAt: n.map { Double($0) * s.periodSeconds }, nextSubPeriod: n)
        }
        let el = elapsed(at: now, halfSeconds: s.halfSeconds)
        let over = el >= s.halfSeconds - 0.001
        let j = min(s.perHalf - 1, Int((el + 0.001) / s.periodSeconds))
        let p = half * s.perHalf + j
        let next = over ? nil : s.nextSubPeriod(from: p + 1)
        return Reading(
            started: true, half: half, elapsed: el, halfOver: over,
            period: p,
            nextSubAt: next.map { Double($0 % s.perHalf) * s.periodSeconds },
            nextSubPeriod: next,
            periodHasSubs: s.hasSubs(at: p),
            sincePeriodStart: el - Double(j) * s.periodSeconds)
    }
}
