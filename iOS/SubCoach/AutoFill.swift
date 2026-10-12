import Foundation

/// Builds the rotation in two steps, many times over, and keeps the best result:
/// 1. A quick greedy pass picks the keepers and a fair first draft.
/// 2. A search then trades blocks of periods between girls to cut down on subbing
///    in and out, so bench time comes in longer stretches.
/// Ranked by, most important first: every position filled, no one-period stints in
/// the middle of a half (with 4+ periods per half), fair playing time (adjusted by weight), few in/out changes
/// within a half, few position changes for girls staying on, similar time in each
/// half, then variety across defense / midfield / forward.
enum AutoFill {
    static let unfilledCost = 1000.0
    static let islandCost = 400.0        // per single period on the field mid-half (off before and after)
    static let fairnessCost = 60.0       // per (period off from fair share)²
    static let switchCost = 25.0         // per time a girl goes in or comes out mid-half
    static let balanceCost = 12.0        // per (difference between halves)²
    /// Per time a girl staying on moves to a new spot, with "Fewer position changes" on or off.
    static let fewerMovesCost = 100.0, movesCost = 4.0
    /// Re-planning mid-game: per girl per period that differs from the plan coaches already have.
    static let changeCost = 20.0

    /// The search is sized for up to 10 periods; games with more periods get a proportionally
    /// bigger search so the results stay as good.
    static func run(_ st: inout LineupState, fewerMoves: Bool = true, restarts: Int? = nil, steps: Int? = nil) {
        let scale = max(1, Double(st.periods) / 10)
        let restarts = restarts ?? Int(100 * scale), steps = steps ?? Int(4000 * scale)
        guard !st.players.isEmpty, restarts > 0 else { return }
        guard let best = search(st, fixed: nil, fewerMoves: fewerMoves, restarts: restarts, steps: steps) else { return }
        for i in st.players.indices { st.players[i].cells = best[i] }
    }

    /// Re-plans periods `lock` onward after subs made during the game, changing as little of
    /// the existing plan as the usual rules allow. Playing time already played (counting
    /// partial periods) is taken into account; earlier periods stay exactly as they are.
    static func replan(_ st: inout LineupState, from lock: Int, fewerMoves: Bool = true) {
        guard lock > 0, lock < st.periods, !st.players.isEmpty else { return }
        // Longer stretches of game left need a longer search to settle.
        let left = Double(st.periods - lock) / 10
        let steps = Int(4000 * max(0.5, left) * max(1, left))
        guard let best = search(st, fixed: Fixed(st, lock: lock), fewerMoves: fewerMoves, restarts: 60, steps: steps) else { return }
        for i in st.players.indices {
            for p in lock..<st.periods { st.players[i].cells[p] = best[i][p] }
        }
    }

    private static func search(_ st: LineupState, fixed: Fixed?, fewerMoves: Bool, restarts: Int, steps: Int) -> [[Int?]]? {
        var results = [(cells: [[Int?]], score: Double)?](repeating: nil, count: restarts)
        // Each restart is independent, so spread them across the CPU cores.
        // Every restart gets its own copy of the inputs and its own random numbers
        // so the threads don't slow each other down.
        results.withUnsafeMutableBufferPointer { out in
            DispatchQueue.concurrentPerform(iterations: restarts) { i in
                var rng = FastRandom()
                var plan = Plan(st, moveCost: fewerMoves ? fewerMovesCost : movesCost, fixed: fixed, rng: &rng)
                plan.improve(steps: steps, rng: &rng)
                out[i] = plan.finish(rng: &rng)
            }
        }
        return results.compactMap { $0 }.min { $0.score < $1.score }?.cells
    }

    /// What's already happened when re-planning mid-game.
    struct Fixed {
        /// Periods before this are played (or under way) and stay as they are.
        let lock: Int
        /// Periods each girl has played by the end of period `lock - 1`, counting partial periods.
        let played: [Double], playedFirst: [Double]
        /// Where each girl is at the end of period `lock - 1` (0 = in goal, nil = bench).
        let lastCells: [Int?]
        /// The plan before the change.
        let origCells: [[Int?]]
        let out: [Bool]
        /// Kept goal at some point already, so isn't held to an even split between halves.
        let wasKeeper: [Bool]

        init(_ st: LineupState, lock: Int) {
            let P = st.players
            self.lock = lock
            let secs = st.secondsPlayed(in: 0..<lock), first = st.secondsPlayed(in: 0..<min(lock, st.perHalf))
            played = P.map { (secs[$0.id] ?? 0) / st.periodSeconds }
            playedFirst = P.map { (first[$0.id] ?? 0) / st.periodSeconds }
            let end = st.positions(atEndOf: lock - 1)
            lastCells = P.map { end[$0.id] }
            origCells = P.map { pl in (0..<st.periods).map { pl.cell($0) } }
            out = P.map(\.out)
            wasKeeper = P.map { pl in (0..<lock).contains { pl.cell($0) == 0 } || st.subs.contains { $0.on == pl.id && $0.pos == 0 } }
        }

        func lastSeat(_ x: Int) -> Int { max(lastCells[x] ?? 0, 0) }
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

        /// Seats a girl in an open spot she can play.
        mutating func seat(_ x: Int, at pos: Int) -> Bool {
            guard pos < size, masks[x] & (1 << pos) != 0, seats[pos] == 0xFF else { return false }
            seats[pos] = UInt8(x)
            count += 1
            return true
        }

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
        /// Not held to an even split between halves (keepers).
        let noBalance: [Bool]
        let moveCost: Double
        /// Mid-game: the part of the game that's fixed, and the plan to stay close to.
        let fixed: Fixed?
        let lock: Int
        var on: [[Bool]]          // [player][period], on the field (not in goal)
        var unfilled: [Int]       // per period
        var moves: [Int]          // per half, girls staying on who change spots
        var playerCost: [Double]  // per player
        var score = 0.0

        init(_ st: LineupState, moveCost: Double, fixed: Fixed? = nil, rng: inout FastRandom) {
            self.moveCost = moveCost
            self.fixed = fixed
            lock = fixed?.lock ?? 0
            let P = st.players
            n = P.count; periods = st.periods; perHalf = st.perHalf
            let out = fixed?.out ?? Array(repeating: false, count: n)
            let m = P.indices.map { out[$0] ? 0 : AutoFill.mask(P[$0]) }
            let av = P.indices.map { P[$0].isAvailable && !out[$0] }, fo = m.map { $0 & AutoFill.fieldBits != 0 }
            masks = m; avail = av; fieldOk = fo
            size = st.positionCount
            groups = (0..<st.positionCount).map(st.group)
            let w = P.map { $0.weight > 0 ? $0.weight : 1 }
            let availIdx = P.indices.filter { av[$0] }
            let sumW = availIdx.reduce(0.0) { $0 + w[$1] }
            let periodCount = Double(periods)
            if let fixed {
                // Girls who are out keep what they played; everyone else shares the rest.
                let present = P.indices.filter { !P[$0].absent && P[$0].can.contains(true) }
                let outPlayed = P.indices.filter { out[$0] }.reduce(0.0) { $0 + fixed.played[$1] }
                let slots = Double(min(st.positionCount, present.count)) * periodCount - outPlayed
                fair = P.indices.map { av[$0] ? min(periodCount, slots * w[$0] / sumW) : 0 }
            } else {
                let slots = Double(min(st.positionCount, availIdx.count)) * periodCount
                fair = P.indices.map { av[$0] ? min(periodCount, slots * w[$0] / sumW) : 0 }
            }

            if let fixed {
                let g = Self.keepers(fixed, n: n, perHalf: perHalf, avail: av, masks: m)
                gks = g
                on = Self.draft(fixed, gks: g, n: n, periods: periods, perHalf: perHalf, size: size, fieldOk: fo, weights: w, rng: &rng)
                noBalance = (0..<n).map { g.contains($0) || fixed.wasKeeper[$0] }
                unfilled = Array(repeating: 0, count: periods); moves = [0, 0]; playerCost = []
                for h in 0..<2 { moves[h] = seatHalf(h) }
                playerCost = (0..<n).map { costOf($0) }
                score = Double(unfilled.reduce(0, +)) * unfilledCost + Double(moves.reduce(0, +)) * moveCost
                    + playerCost.reduce(0, +)
                return
            }

            // First draft: period by period, the girls with the least time so far play.
            let k = AutoFill.pickKeepers(st, rng: &rng), keepers = [k.0, k.1]
            gks = keepers
            noBalance = (0..<n).map { keepers.contains($0) }
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
            unfilled = Array(repeating: 0, count: periods); moves = [0, 0]; playerCost = []
            for h in 0..<2 { moves[h] = seatHalf(h) }
            playerCost = (0..<n).map { costOf($0) }
            score = Double(unfilled.reduce(0, +)) * unfilledCost + Double(moves.reduce(0, +)) * moveCost
                + playerCost.reduce(0, +)
        }

        /// Mid-game keepers: whoever's in goal now for the half under way, the planned keeper
        /// for a half still to come (unless she's out), otherwise who has played least.
        static func keepers(_ f: Fixed, n: Int, perHalf: Int, avail: [Bool], masks: [UInt16]) -> [Int] {
            var g = [-1, -1]
            for h in 0..<2 {
                let start = h * perHalf
                guard start + perHalf > f.lock else { continue } // half already played
                if start < f.lock {
                    g[h] = f.lastCells.firstIndex(of: 0) ?? -1
                } else if let o = (0..<n).first(where: { f.origCells[$0][start] == 0 }), avail[o] {
                    g[h] = o
                }
                if g[h] < 0 {
                    let keepers = (0..<n).filter { avail[$0] && masks[$0] & 1 != 0 }
                    let pool = keepers.isEmpty ? (0..<n).filter { avail[$0] } : keepers
                    g[h] = pool.min { f.played[$0] < f.played[$1] } ?? -1
                }
            }
            return g
        }

        /// Mid-game first draft: the existing plan, minus anyone out or now in goal, topped up
        /// (or trimmed) to a full field with whoever has played least.
        static func draft(_ f: Fixed, gks: [Int], n: Int, periods: Int, perHalf: Int, size: Int,
                          fieldOk: [Bool], weights w: [Double], rng: inout FastRandom) -> [[Bool]] {
            var on = Array(repeating: Array(repeating: false, count: periods), count: n)
            var est = f.played
            for p in f.lock..<periods {
                let gk = gks[p / perHalf]
                var count = 0
                for x in 0..<n where (f.origCells[x][p] ?? 0) > 0 && x != gk && fieldOk[x] { on[x][p] = true; count += 1 }
                let byTime = (0..<n).shuffled(using: &rng).sorted { est[$0] / w[$0] < est[$1] / w[$1] }
                for x in byTime.reversed() where count > size - 1 && on[x][p] { on[x][p] = false; count -= 1 }
                for x in byTime where count < size - 1 && !on[x][p] && x != gk && fieldOk[x] { on[x][p] = true; count += 1 }
                for x in 0..<n where on[x][p] || x == gk { est[x] += 1 }
            }
            return on
        }

        func playing(_ x: Int, _ p: Int) -> Bool { on[x][p] || gks[p / perHalf] == x }

        /// On the field in period p; for the last fixed period, at its end.
        func was(_ x: Int, _ p: Int) -> Bool {
            if p < lock, let fixed { return fixed.lastCells[x] != nil }
            return playing(x, p)
        }

        /// Seats one half period by period the way `finish` does (girls staying on keep
        /// their spot unless someone coming on can only fit there). Updates `unfilled`
        /// for the half and returns how many times a girl staying on had to move.
        mutating func seatHalf(_ h: Int) -> Int {
            var seat = [Int](repeating: 0, count: n), moved = 0
            for q in h * perHalf ..< (h + 1) * perHalf {
                if q < lock {
                    // Already played: just carry where everyone ends up into the next period.
                    if q == lock - 1, let fixed { for x in 0..<n { seat[x] = fixed.lastSeat(x) } }
                    unfilled[q] = 0
                    continue
                }
                var m = Matcher(masks: masks, size: size)
                for x in 0..<n where on[x][q] && seat[x] > 0 { _ = m.seat(x, at: seat[x]) }
                for x in 0..<n where on[x][q] && seat[x] == 0 { _ = m.place(x) }
                for x in 0..<n { if !on[x][q] { seat[x] = 0 } }
                for pos in 1..<size {
                    let x = m.holder(pos)
                    guard x >= 0 else { continue }
                    if seat[x] > 0 && seat[x] != pos { moved += 1 }
                    seat[x] = pos
                }
                // Someone who didn't fit at all (spot count short) starts fresh next period.
                for x in 0..<n where on[x][q] && seat[x] > 0 && m.holder(seat[x]) != x { seat[x] = 0 }
                unfilled[q] = size - 1 - m.count + (gks[h] < 0 ? 1 : 0)
            }
            return moved
        }

        func costOf(_ x: Int) -> Double {
            guard avail[x] else { return 0 }
            var played = 0.0, switches = 0, islands = 0, first = 0.0, second = 0.0, changed = 0
            if let fixed {
                played = fixed.played[x]; first = fixed.playedFirst[x]; second = played - first
            }
            for p in lock..<periods {
                let a = playing(x, p), j = p % perHalf
                if a { played += 1; if p < perHalf { first += 1 } else { second += 1 } }
                if j != 0 && a != was(x, p - 1) { switches += 1 }
                // In for a single period with bench on both sides. One period at the
                // start or end of a half is fine, and with 3 or fewer periods per half
                // there's no room to avoid it, so it's allowed there too.
                if perHalf > 3 && a && j != 0 && j != perHalf - 1 && !was(x, p - 1) && !playing(x, p + 1) { islands += 1 }
                if let fixed, a != (fixed.origCells[x][p] != nil) { changed += 1 }
            }
            let d = played - fair[x]
            var c = d * d * fairnessCost + Double(switches) * switchCost + Double(islands) * islandCost
                + Double(changed) * changeCost
            if !noBalance[x] {
                let b = first - second
                c += b * b * balanceCost
            }
            return c
        }

        /// Simulated annealing: swap a girl on the field with one on the bench
        /// for a run of periods, keep the change if it helps (or sometimes if it
        /// only hurts a little, early on, to escape dead ends).
        mutating func improve(steps: Int, rng: inout FastRandom) {
            guard steps > 0, lock < periods else { return }
            var ins = [Int](), outs = [Int]()
            ins.reserveCapacity(n); outs.reserveCapacity(n)
            for step in 0..<steps {
                let temp = 40.0 * pow(0.01, Double(step) / Double(steps))
                let p = Int.random(in: lock..<periods, using: &rng)
                let h = p / perHalf, gk = gks[h]
                ins.removeAll(keepingCapacity: true); outs.removeAll(keepingCapacity: true)
                for x in 0..<n {
                    if on[x][p] { ins.append(x) } else if x != gk && fieldOk[x] { outs.append(x) }
                }
                guard let x = ins.randomElement(using: &rng), let y = outs.randomElement(using: &rng) else { continue }
                // Extend the swap over neighboring periods in this half where it still applies.
                let start = max(h * perHalf, lock), end = h * perHalf + perHalf
                var lo = p, hi = p
                func ok(_ q: Int) -> Bool { q >= start && q < end && on[x][q] && !on[y][q] }
                for _ in 0..<Int.random(in: 0..<perHalf, using: &rng) {
                    if Bool.random(using: &rng) { if ok(hi + 1) { hi += 1 } else if ok(lo - 1) { lo -= 1 } }
                    else { if ok(lo - 1) { lo -= 1 } else if ok(hi + 1) { hi += 1 } }
                }
                let oldX = playerCost[x], oldY = playerCost[y], oldMoves = moves[h]
                let oldUnfilled = Array(unfilled[start..<end])
                for q in lo...hi { on[x][q] = false; on[y][q] = true }
                moves[h] = seatHalf(h)
                var delta = Double(moves[h] - oldMoves) * moveCost
                for q in start..<end { delta += Double(unfilled[q] - oldUnfilled[q - start]) * unfilledCost }
                let newX = costOf(x), newY = costOf(y)
                delta += newX - oldX + newY - oldY
                if delta <= 0 || Double.random(in: 0..<1, using: &rng) < exp(-delta / temp) {
                    playerCost[x] = newX; playerCost[y] = newY
                    score += delta
                } else {
                    for q in lo...hi { on[x][q] = true; on[y][q] = false }
                    unfilled.replaceSubrange(start..<end, with: oldUnfilled)
                    moves[h] = oldMoves
                }
            }
        }

        /// Assign positions: keep a girl in the same spot while she stays on,
        /// otherwise steer her toward the part of the field she has played least.
        func finish(rng: inout FastRandom) -> (cells: [[Int?]], score: Double) {
            var cells = Array(repeating: [Int?](repeating: nil, count: periods), count: n)
            var grp = Array(repeating: [0, 0, 0, 0], count: n)
            var changes = 0
            if let fixed { for x in 0..<n { cells[x][lock - 1] = fixed.lastCells[x] } }
            for p in lock..<periods {
                let gk = gks[p / perHalf]
                if gk >= 0 { cells[gk][p] = 0; grp[gk][0] += 1 }
                let stay = p % perHalf != 0
                var prefs = Array(repeating: [Int](), count: n)
                for x in 0..<n where on[x][p] {
                    var l = (1..<size).filter { masks[x] & (1 << $0) != 0 }.shuffled(using: &rng)
                    l.sort { grp[x][groups[$0]] < grp[x][groups[$1]] }
                    // Mid-game, keep her where the plan already had her if possible.
                    if let o = fixed?.origCells[x][p], o > 0, let i = l.firstIndex(of: o) {
                        l.remove(at: i); l.insert(o, at: 0)
                    }
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
            // The search estimated the moves; score what the final seating actually has.
            return (cells, score + Double(variety) + Double(changes - moves.reduce(0, +)) * moveCost)
        }
    }
}
