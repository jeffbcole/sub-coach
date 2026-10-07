import Foundation

/// Builds the rotation in two steps, many times over, and keeps the best result:
/// 1. A quick greedy pass picks the keepers and a fair first draft.
/// 2. A search then trades blocks of periods between girls to cut down on subbing
///    in and out, so bench time comes in longer stretches.
/// Ranked by, most important first: every position filled, fair playing time
/// (adjusted by weight), few in/out changes within a half, similar time in each
/// half, then variety across defense / midfield / forward.
enum AutoFill {
    static let unfilledCost = 1000.0
    static let fairnessCost = 60.0       // per (period off from fair share)²
    static let switchCost = 25.0         // per time a girl goes in or comes out mid-half
    static let balanceCost = 12.0        // per (difference between halves)²
    static let positionChangeCost = 4.0  // staying on but moving to a new spot

    static func run(_ st: inout LineupState, restarts: Int = 60, steps: Int = 2500) {
        guard !st.players.isEmpty, restarts > 0 else { return }
        let snapshot = st
        var results = [(cells: [[Int?]], score: Double)?](repeating: nil, count: restarts)
        // Each restart is independent, so spread them across the CPU cores.
        // Every restart gets its own copy of the inputs and its own random numbers
        // so the threads don't slow each other down.
        results.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: restarts) { i in
                var rng = FastRandom()
                var plan = Plan(snapshot, rng: &rng)
                plan.improve(steps: steps, rng: &rng)
                out[i] = plan.finish(rng: &rng)
            }
        }
        guard let best = results.compactMap({ $0 }).min(by: { $0.score < $1.score }) else { return }
        for i in st.players.indices { st.players[i].cells = best.cells[i] }
    }

    /// Small, fast random generator (SplitMix64), one per thread.
    struct FastRandom: RandomNumberGenerator {
        private var state = UInt64.random(in: .min ... .max)
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func pickKeepers(_ st: LineupState, rng: inout FastRandom) -> (Int, Int) {
        let P = st.players, n = P.count
        func idx(_ id: String) -> Int { P.firstIndex { $0.id == id } ?? -1 }
        var elig = (0..<n).filter { P[$0].can[0] && !P[$0].absent }
        if elig.isEmpty { elig = (0..<n).filter { P[$0].isAvailable } }
        if elig.isEmpty { return (-1, -1) }
        var a = idx(st.gk1), b = idx(st.gk2)
        if a < 0 && b < 0 {
            let o = elig.shuffled(using: &rng)
            a = o[0]; b = o.count > 1 ? o[1] : o[0]
        } else if a < 0 {
            a = elig.filter { $0 != b }.randomElement(using: &rng) ?? b
        } else if b < 0 {
            b = elig.filter { $0 != a }.randomElement(using: &rng) ?? a
        }
        return (a, b)
    }

    /// Positions a girl can play, as bits (bit k = position k).
    static func mask(_ p: Player) -> UInt16 {
        guard !p.absent else { return 0 }
        var m: UInt16 = 0
        for k in p.can.indices where p.can[k] { m |= 1 << k }
        return m
    }

    /// Every position except the keeper's (bit 0).
    static let fieldBits: UInt16 = ~1

    /// Matches girls to field positions they can play. Placing a girl may move
    /// others to make room; the search is breadth-first so it moves as few as possible.
    /// There are at most 11 positions, so the bookkeeping lives in fixed 16-slot
    /// vectors to avoid allocating while searching.
    struct Matcher {
        let masks: [UInt16]
        /// Positions in the formation, keeper included.
        let size: Int
        private var seats = SIMD16<UInt8>(repeating: 0xFF) // slot k = player at position k, 0xFF = open
        var count = 0

        init(masks: [UInt16], size: Int) {
            self.masks = masks
            self.size = size
        }

        func holder(_ pos: Int) -> Int { let b = seats[pos]; return b == 0xFF ? -1 : Int(b) }

        /// `order` lists positions in the order this girl would like them;
        /// `prefs` does the same for anyone who has to move.
        mutating func place(_ x: Int, order: [Int]? = nil, prefs: [[Int]]? = nil) -> Bool {
            let unvisited: UInt8 = 0xFF, start: UInt8 = 0xFE
            var cameFrom = SIMD16<UInt8>(repeating: unvisited)
            var queue = SIMD16<UInt8>(repeating: 0)
            var tail = 0, head = 0
            func visit(_ q: Int, from: UInt8, _ who: Int) {
                guard q < size, masks[who] & (1 << q) != 0, cameFrom[q] == unvisited else { return }
                cameFrom[q] = from
                queue[tail] = UInt8(q); tail += 1
            }
            if let order { for q in order { visit(q, from: start, x) } }
            else { for q in 1..<size { visit(q, from: start, x) } }
            while head < tail {
                let pos = Int(queue[head]); head += 1
                let h = holder(pos)
                if h < 0 {
                    // Open spot: shift everyone along the chain, then seat x.
                    var cur = pos
                    while cameFrom[cur] != start {
                        let prev = Int(cameFrom[cur])
                        seats[cur] = seats[prev]
                        cur = prev
                    }
                    seats[cur] = UInt8(x)
                    count += 1
                    return true
                }
                if let p = prefs?[h] { for q in p { visit(q, from: UInt8(pos), h) } }
                else { for q in 1..<size { visit(q, from: UInt8(pos), h) } }
            }
            return false
        }
    }

    /// Who is on the field each period, improved by local search.
    struct Plan {
        let n: Int, periods: Int, perHalf: Int
        let masks: [UInt16]
        /// Positions in the formation, keeper included.
        let size: Int
        /// Line of each position slot in this formation.
        let groups: [Int]
        let gks: [Int]
        let fair: [Double]
        let avail: [Bool], fieldOk: [Bool]
        var on: [[Bool]]          // [player][period], on the field (not in goal)
        var unfilled: [Int]       // per period
        var playerCost: [Double]  // per player
        var score = 0.0

        init(_ st: LineupState, rng: inout FastRandom) {
            let P = st.players
            n = P.count; periods = st.periods; perHalf = st.perHalf
            let m = P.map(AutoFill.mask), av = P.map(\.isAvailable), fo = m.map { $0 & AutoFill.fieldBits != 0 }
            masks = m; avail = av; fieldOk = fo
            size = st.positionCount
            groups = (0..<st.positionCount).map(st.group)
            let w = P.map { $0.weight > 0 ? $0.weight : 1 }
            let availIdx = P.indices.filter { av[$0] }
            let sumW = availIdx.reduce(0.0) { $0 + w[$1] }
            let periodCount = Double(periods)
            let slots = Double(min(st.positionCount, availIdx.count)) * periodCount
            fair = P.indices.map { av[$0] ? min(periodCount, slots * w[$0] / sumW) : 0 }

            // First draft: period by period, the girls with the least time so far play.
            let k = AutoFill.pickKeepers(st, rng: &rng), keepers = [k.0, k.1]
            gks = keepers
            var draft = Array(repeating: Array(repeating: false, count: periods), count: n)
            var played = Array(repeating: 0, count: n)
            // The second-half keeper sits a bit more in the first half to even out her time.
            let bonus = 1 + Int.random(in: 0..<perHalf, using: &rng)
            for p in 0..<periods {
                let h = p / perHalf, gk = keepers[h]
                func commit(_ x: Int) -> Int { played[x] + (h == 0 && x == keepers[1] && keepers[0] != keepers[1] ? bonus : 0) }
                var pool = (0..<n).filter { $0 != gk && fo[$0] }.shuffled(using: &rng)
                // Least time first; on a tie, keep whoever was already on.
                pool.sort { a, b in
                    let ka = (Double(commit(a)) + 0.5) / w[a], kb = (Double(commit(b)) + 0.5) / w[b]
                    if ka != kb { return ka < kb }
                    return p > 0 && draft[a][p - 1] && !draft[b][p - 1]
                }
                var matcher = Matcher(masks: m, size: st.positionCount)
                for x in pool where matcher.count < st.positionCount - 1 {
                    if matcher.place(x) { draft[x][p] = true }
                }
                // Top up a short period so later swaps can still find a full lineup.
                var count = matcher.count
                for x in pool where count < st.positionCount - 1 && !draft[x][p] { draft[x][p] = true; count += 1 }
                if gk >= 0 { played[gk] += 1 }
                for x in 0..<n where draft[x][p] { played[x] += 1 }
            }
            on = draft
            unfilled = []; playerCost = []
            unfilled = (0..<periods).map { periodUnfilled($0) }
            playerCost = (0..<n).map { costOf($0) }
            score = Double(unfilled.reduce(0, +)) * unfilledCost + playerCost.reduce(0, +)
        }

        func playing(_ x: Int, _ p: Int) -> Bool { on[x][p] || gks[p / perHalf] == x }

        func periodUnfilled(_ p: Int) -> Int {
            var m = Matcher(masks: masks, size: size)
            for x in 0..<n where on[x][p] { _ = m.place(x) }
            return size - 1 - m.count + (gks[p / perHalf] < 0 ? 1 : 0)
        }

        func costOf(_ x: Int) -> Double {
            guard avail[x] else { return 0 }
            var played = 0, switches = 0, first = 0, second = 0
            for p in 0..<periods {
                let a = playing(x, p)
                if a { played += 1; if p < perHalf { first += 1 } else { second += 1 } }
                if p % perHalf != 0 && a != playing(x, p - 1) { switches += 1 }
            }
            let d = Double(played) - fair[x]
            var c = d * d * fairnessCost + Double(switches) * switchCost
            if x != gks[0] && x != gks[1] {
                let b = Double(first - second)
                c += b * b * balanceCost
            }
            return c
        }

        /// Simulated annealing: swap a girl on the field with one on the bench
        /// for a run of periods, keep the change if it helps (or sometimes if it
        /// only hurts a little, early on, to escape dead ends).
        mutating func improve(steps: Int, rng: inout FastRandom) {
            guard steps > 0 else { return }
            var ins = [Int](), outs = [Int]()
            ins.reserveCapacity(n); outs.reserveCapacity(n)
            for step in 0..<steps {
                let temp = 40.0 * pow(0.01, Double(step) / Double(steps))
                let p = Int.random(in: 0..<periods, using: &rng)
                let h = p / perHalf, gk = gks[h]
                ins.removeAll(keepingCapacity: true); outs.removeAll(keepingCapacity: true)
                for x in 0..<n {
                    if on[x][p] { ins.append(x) } else if x != gk && fieldOk[x] { outs.append(x) }
                }
                guard let x = ins.randomElement(using: &rng), let y = outs.randomElement(using: &rng) else { continue }
                // Extend the swap over neighboring periods in this half where it still applies.
                let start = h * perHalf, end = start + perHalf
                var lo = p, hi = p
                func ok(_ q: Int) -> Bool { q >= start && q < end && on[x][q] && !on[y][q] }
                for _ in 0..<Int.random(in: 0..<perHalf, using: &rng) {
                    if Bool.random(using: &rng) { if ok(hi + 1) { hi += 1 } else if ok(lo - 1) { lo -= 1 } }
                    else { if ok(lo - 1) { lo -= 1 } else if ok(hi + 1) { hi += 1 } }
                }
                let oldX = playerCost[x], oldY = playerCost[y]
                let oldUnfilled = Array(unfilled[lo...hi])
                for q in lo...hi { on[x][q] = false; on[y][q] = true }
                var delta = 0.0
                for q in lo...hi {
                    let u = periodUnfilled(q)
                    delta += Double(u - unfilled[q]) * unfilledCost
                    unfilled[q] = u
                }
                let newX = costOf(x), newY = costOf(y)
                delta += newX - oldX + newY - oldY
                if delta <= 0 || Double.random(in: 0..<1, using: &rng) < exp(-delta / temp) {
                    playerCost[x] = newX; playerCost[y] = newY
                    score += delta
                } else {
                    for q in lo...hi { on[x][q] = true; on[y][q] = false }
                    unfilled.replaceSubrange(lo...hi, with: oldUnfilled)
                }
            }
        }

        /// Assign positions: keep a girl in the same spot while she stays on,
        /// otherwise steer her toward the part of the field she has played least.
        func finish(rng: inout FastRandom) -> (cells: [[Int?]], score: Double) {
            var cells = Array(repeating: [Int?](repeating: nil, count: periods), count: n)
            var grp = Array(repeating: [0, 0, 0, 0], count: n)
            var changes = 0
            for p in 0..<periods {
                let gk = gks[p / perHalf]
                if gk >= 0 { cells[gk][p] = 0; grp[gk][0] += 1 }
                let stay = p % perHalf != 0
                var prefs = Array(repeating: [Int](), count: n)
                for x in 0..<n where on[x][p] {
                    var l = (1..<size).filter { masks[x] & (1 << $0) != 0 }.shuffled(using: &rng)
                    l.sort { grp[x][groups[$0]] < grp[x][groups[$1]] }
                    if stay, let prev = cells[x][p - 1], prev > 0, let i = l.firstIndex(of: prev) {
                        l.remove(at: i); l.insert(prev, at: 0)
                    }
                    prefs[x] = l
                }
                var m = Matcher(masks: masks, size: size)
                // Girls staying on choose first so they keep their spot.
                let order = (0..<n).filter { on[$0][p] }.shuffled(using: &rng).sorted { a, b in
                    stay && cells[a][p - 1] != nil && cells[b][p - 1] == nil
                }
                for x in order { _ = m.place(x, order: prefs[x], prefs: prefs) }
                for pos in 1..<size where m.holder(pos) >= 0 {
                    let x = m.holder(pos)
                    cells[x][p] = pos
                    grp[x][groups[pos]] += 1
                    if stay, let prev = cells[x][p - 1], prev > 0, prev != pos { changes += 1 }
                }
            }
            let variety = grp.reduce(0) { $0 + $1[1] * $1[1] + $1[2] * $1[2] + $1[3] * $1[3] }
            return (cells, score + Double(variety) + Double(changes) * positionChangeCost)
        }
    }
}
