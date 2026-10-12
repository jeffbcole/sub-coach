import Foundation

/// A substitution made during a period, off the plan: `on` takes `off`'s spot at clock time `at`.
struct MidSub: Codable, Equatable, Identifiable {
    var period: Int
    /// Seconds into the half.
    var at: TimeInterval
    var off: String
    var on: String
    var pos: Int
    var id: String { "\(period)-\(off)-\(on)-\(Int(at))" }
}

extension LineupState {
    func subs(in p: Int) -> [MidSub] { subs.filter { $0.period == p } }
    func subOn(_ id: String, in p: Int) -> MidSub? { subs.first { $0.period == p && $0.on == id } }
    func subOff(_ id: String, in p: Int) -> MidSub? { subs.first { $0.period == p && $0.off == id } }

    /// Who's where at the end of period p (keeper included), after any subs during it.
    func positions(atEndOf p: Int) -> [String: Int] {
        var byPos: [Int: String] = [:]
        for pl in players { if let c = pl.cell(p) { byPos[c] = pl.id } }
        for s in subs(in: p) { byPos[s.pos] = s.on }
        return Dictionary(byPos.map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Seconds each girl is on the field (keeper included) during period p, up to clock
    /// time `until` within the half if given.
    func secondsOnField(in p: Int, until: TimeInterval? = nil) -> [String: TimeInterval] {
        secondsByPosition(in: p, until: until).mapValues { $0.values.reduce(0, +) }
    }

    /// Like `secondsOnField`, split by position: player id -> position -> seconds.
    func secondsByPosition(in p: Int, until: TimeInterval? = nil) -> [String: [Int: TimeInterval]] {
        let start = Double(p % perHalf) * periodSeconds
        let end = min(start + periodSeconds, until ?? .infinity)
        guard end > start else { return [:] }
        var since: [String: (pos: Int, at: TimeInterval)] = [:], total: [String: [Int: TimeInterval]] = [:]
        for pl in players { if let c = pl.cell(p) { since[pl.id] = (c, start) } }
        for s in subs(in: p) where s.at < end {
            let t = max(s.at, start)
            if let from = since.removeValue(forKey: s.off) { total[s.off, default: [:]][from.pos, default: 0] += t - from.at }
            if since[s.on] == nil { since[s.on] = (s.pos, t) }
        }
        for (id, from) in since { total[id, default: [:]][from.pos, default: 0] += end - from.at }
        return total
    }

    /// Seconds by position played so far: whole periods before `period`, plus period `period`
    /// up to clock time `at` (nil: none of it).
    func positionsSoFar(period: Int, at: TimeInterval?) -> [String: [Int: TimeInterval]] {
        var total: [String: [Int: TimeInterval]] = [:]
        func add(_ part: [String: [Int: TimeInterval]]) {
            for (id, byPos) in part { for (pos, t) in byPos { total[id, default: [:]][pos, default: 0] += t } }
        }
        for q in 0..<min(period, periods) { add(secondsByPosition(in: q)) }
        if let at, period < periods { add(secondsByPosition(in: period, until: at)) }
        return total
    }

    /// Seconds played in periods `range`.
    func secondsPlayed(in range: Range<Int>) -> [String: TimeInterval] {
        var total: [String: TimeInterval] = [:]
        for p in range where p >= 0 && p < periods {
            for (id, t) in secondsOnField(in: p) { total[id, default: 0] += t }
        }
        return total
    }

    /// Seconds a girl plays over the whole game as planned, counting subs made during periods.
    func secondsPlayed(_ id: String) -> TimeInterval { secondsPlayed(in: 0..<periods)[id] ?? 0 }

    /// Seconds played so far: whole periods before `period`, plus period `period` up to `at`.
    func secondsSoFar(period: Int, at: TimeInterval?) -> [String: TimeInterval] {
        var total = secondsPlayed(in: 0..<period)
        if let at { for (id, t) in secondsOnField(in: period, until: at) { total[id, default: 0] += t } }
        return total
    }
}
