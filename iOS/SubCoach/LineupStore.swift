import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class LineupStore {
    /// Roster plus every saved lineup; this is what gets saved.
    private(set) var team: TeamData
    /// Working copy of the open lineup (roster + that lineup combined).
    private(set) var state: LineupState
    private(set) var undoStack: [TeamData] = []
    var canUndo: Bool { !undoStack.isEmpty }

    /// Opens the full-screen Game Day view (also opened when a coach follows a broadcast).
    var presentGameDay = false

    // MARK: Sharing state (logic is in LineupStore+Sharing.swift)

    let shareHost = ShareHost()
    let shareClient = ShareClient()
    /// Host: the roster being shared right now.
    var sharingRoster: RosterOffer?
    /// Host: the current broadcast's session, nil when not broadcasting.
    var broadcastSession: String?
    var broadcastRev = 0
    /// Host: a just-ended broadcast, still sent briefly so followers hear it ended.
    var endedBroadcast: GameOffer?
    /// Host: latest reply from each coach, by coach id.
    var shareReplies: [String: ShareReply] = [:]
    /// Receiver: popups waiting for an answer.
    var pendingRoster: PendingRoster?
    var pendingGame: PendingGame?
    /// Receiver: the broadcast being followed.
    var following: FollowedGame?
    /// Receiver: broadcasts currently heard nearby, by session (whether followed or not).
    var liveBroadcasts: [String: LiveBroadcast] = [:]
    /// Receiver: when the followed broadcast was last missing from range, while the app was open.
    var followedMissingSince: Date?
    var followCheckTimer: Timer?
    /// Receiver: shares and broadcasts already answered, so nobody is asked twice.
    var handledSessions: [String] = []

    private static let dir: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()
    private static let fileURL = dir.appendingPathComponent("team.json")
    /// Single-lineup save from earlier versions; read once to migrate, then left alone.
    private static let oldFileURL = dir.appendingPathComponent("lineup.json")

    init() {
        var t: TeamData
        var migrated = false
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(TeamData.self, from: data) {
            t = saved
        } else if let data = try? Data(contentsOf: Self.oldFileURL),
                  let old = try? JSONDecoder().decode(LineupState.self, from: data),
                  !old.players.isEmpty {
            var o = old
            o.normalize()
            t = TeamData.migrating(from: o)
            migrated = true
        } else {
            var s = LineupState.starter()
            s.normalize()
            t = TeamData.migrating(from: s)
        }
        t.repair()
        team = t
        state = t.state(for: t.currentID) ?? LineupState()
        if let data = UserDefaults.standard.data(forKey: Self.clockKey),
           let saved = try? JSONDecoder().decode(GameClock.self, from: data) {
            clock = saved
            // A game from before saved lineups belongs to the lineup we just migrated.
            if clock.phase != .ready && clock.lineupID == nil { clock.lineupID = t.currentID }
        }
        if migrated { save() }
        setUpSharing()
    }

    func setTeam(_ t: TeamData) {
        var t = t
        t.repair()
        team = t
        state = t.state(for: t.currentID) ?? LineupState()
    }

    private func pushUndo() {
        undoStack.append(team)
        if undoStack.count > 30 { undoStack.removeFirst() }
    }

    /// Change the open lineup (or the roster). Undoable changes push a snapshot first.
    func update(undoable: Bool = true, _ change: (inout LineupState) -> Void) {
        var next = state
        change(&next)
        next.normalize()
        guard next != state else { return }
        if undoable { pushUndo() }
        var t = team
        t.apply(next, to: t.currentID)
        setTeam(t)
        save()
    }

    func clearUndo() { undoStack.removeAll() }

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        setTeam(prev)
        save()
    }

    // MARK: Saved lineups

    /// Most recently edited first.
    var sortedLineups: [SavedLineup] { team.lineups.sorted { $0.updated > $1.updated } }
    var currentLineup: SavedLineup? { team.lineup(team.currentID) }

    func selectLineup(_ id: String) {
        guard id != team.currentID, team.lineup(id) != nil else { return }
        var t = team
        t.currentID = id
        undoStack.removeAll() // undo works within one lineup
        setTeam(t)
        save()
    }

    /// Today's date as a starting name, e.g. "Lineup 10/24", numbered if that's taken.
    func suggestedLineupName(on date: Date = .now) -> String {
        let base = "Lineup " + date.formatted(.dateTime.month(.defaultDigits).day())
        let taken = Set(team.lineups.map(\.displayName))
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base) (\($0))" }.first { !taken.contains($0) }!
    }

    /// A new, empty lineup using the game format of the open one.
    @discardableResult
    func newLineup(named name: String) -> String {
        let id = Game.newID()
        var t = team
        let base = currentLineup
        t.lineups.append(SavedLineup(id: id, name: name, updated: .now,
                                     perHalf: base?.perHalf ?? Game.defaultPerHalf, halfMinutes: base?.halfMinutes ?? Game.defaultHalfMinutes))
        t.currentID = id
        undoStack.removeAll()
        setTeam(t)
        save()
        return id
    }

    func duplicateLineup(_ id: String) {
        guard var copy = team.lineup(id) else { return }
        copy.id = Game.newID()
        copy.broadcast = nil // the copy is the coach's own
        copy.name = copy.displayName + " copy"
        copy.updated = .now
        var t = team
        t.lineups.append(copy)
        t.currentID = copy.id
        undoStack.removeAll()
        setTeam(t)
        save()
    }

    /// Can this roster player play this role? (Unset center roles follow the rest of their line.)
    func canPlay(_ playerID: String, _ role: Role) -> Bool {
        team.roster.first { $0.id == playerID }?.canPlay(role) ?? false
    }

    /// Set a roster preference for one role; it applies in every formation that uses that role.
    func setCanPlay(_ playerID: String, _ role: Role, _ on: Bool) {
        guard let i = team.roster.firstIndex(where: { $0.id == playerID }) else { return }
        pushUndo()
        var t = team
        t.roster[i].prefs[role.rawValue] = on
        setTeam(t)
        save()
    }

    /// Change how many play at once; switches to that size's first formation.
    func setFieldSize(_ size: Int) {
        guard size != state.positionCount, let f = Formation.options(size: size).first else { return }
        setFormation(f.id)
    }

    /// Change the open lineup's formation, moving girls to matching spots where possible.
    func setFormation(_ formationID: String) {
        guard currentLineup?.formation != formationID else { return }
        pushUndo()
        var t = team
        t.setFormation(formationID, for: t.currentID)
        setTeam(t)
        save()
    }

    func renameLineup(_ id: String, to name: String) {
        var t = team
        guard let i = t.lineups.firstIndex(where: { $0.id == id }) else { return }
        t.lineups[i].name = String(name.prefix(80))
        t.lineups[i].updated = .now
        setTeam(t)
        save()
    }

    func deleteLineup(_ id: String) {
        var t = team
        t.lineups.removeAll { $0.id == id }
        if t.currentID == id { t.currentID = "" } // repair() picks the most recent one
        undoStack.removeAll()
        setTeam(t)
        save()
        if clock.lineupID == id { resetClock() }
    }

    // MARK: Game clock

    private static let clockKey = "gameClock"
    private(set) var clock = GameClock()

    /// The lineup the game in progress is using (nil before kickoff).
    var gameLineupID: String? {
        guard clock.phase != .ready else { return nil }
        let id = clock.lineupID ?? team.currentID
        return team.lineup(id) != nil ? id : nil
    }

    /// The lineup whose game is under way: kicked off and not yet at full time.
    func liveGameLineupID(at now: Date = .now) -> String? {
        guard let id = gameLineupID, !clock.reading(at: now, gameState).gameOver else { return nil }
        return id
    }

    /// What Game Day, alerts and the lock screen show: the game's lineup, or the open one before kickoff.
    var gameState: LineupState {
        if let id = gameLineupID, id != team.currentID, let s = team.state(for: id) { return s }
        return state
    }

    /// A new game on the open lineup: forget subs (and who was out) from the last time it
    /// was played. They stay on the grid after a game ends until then.
    func clearLastGame() {
        if var s = team.state(for: team.currentID), !s.subs.isEmpty || s.players.contains(where: \.out) {
            s.subs = []
            for i in s.players.indices { s.players[i].out = false }
            setLineupState(s, for: team.currentID)
        }
    }

    func startGame() {
        clearLastGame()
        setClock(GameClock(phase: .running, half: 0, startedAt: .now, lineupID: team.currentID))
        // The first time, alerts can only be scheduled once permission is given.
        SubAlerts.requestPermission { [weak self] in
            guard let self else { return }
            SubAlerts.reschedule(self.liveState, self.liveClock)
        }
    }

    func pauseClock() {
        guard clock.phase == .running else { return }
        var c = clock
        c.accumulated = c.elapsed(at: .now, halfSeconds: gameState.halfSeconds)
        c.startedAt = nil
        c.phase = .paused
        setClock(c)
    }

    func resumeClock() {
        guard clock.phase == .paused else { return }
        var c = clock
        c.startedAt = .now
        c.phase = .running
        setClock(c)
    }

    /// Nudge the clock to match the referee's (or a late tap on Start).
    func adjustClock(by seconds: TimeInterval) {
        guard clock.phase != .ready else { return }
        var c = clock
        let half = gameState.halfSeconds
        c.accumulated = min(half, max(0, c.elapsed(at: .now, halfSeconds: half) + seconds))
        if c.phase == .running { c.startedAt = .now }
        setClock(c)
    }

    /// For when the referee ends the half early.
    func endHalfNow() {
        var c = clock
        c.accumulated = gameState.halfSeconds
        c.startedAt = nil
        c.phase = .paused
        setClock(c)
    }

    func startSecondHalf() {
        setClock(GameClock(phase: .running, half: 1, startedAt: .now, lineupID: gameLineupID ?? team.currentID))
    }

    /// Ends the game (in progress or finished) so any lineup can start a new one.
    func resetClock() {
        // A new game ends any broadcast of the old one.
        if broadcastSession != nil { setBroadcasting(false) }
        lastSubs = nil
        setClock(GameClock())
    }

    /// The game this phone's alerts, lock screen and Game Day follow: another coach's broadcast
    /// if following one, otherwise this phone's own game.
    var liveState: LineupState { following?.state ?? gameState }
    var liveClock: GameClock { following?.clock ?? clock }
    var isFollowing: Bool { following != nil }

    /// Keep the screen awake while the clock runs.
    func applyIdleTimer() { UIApplication.shared.isIdleTimerDisabled = liveClock.phase == .running }

    private func setClock(_ c: GameClock) {
        clock = c
        if let data = try? JSONEncoder().encode(c) { UserDefaults.standard.set(data, forKey: Self.clockKey) }
        refreshGameOutputs()
        pushBroadcast()
    }

    /// Re-do alerts, keep-awake and the lock screen countdown for whatever game is live.
    func refreshGameOutputs() {
        SubAlerts.reschedule(liveState, liveClock)
        applyIdleTimer()
        refreshLiveActivity()
    }

    private var boundaryTask: Task<Void, Never>?

    /// Update the lock screen countdown now, and again at the next sub while the app is open.
    func refreshLiveActivity() {
        let s = liveState, clock = liveClock
        LiveGame.sync(s, clock)
        boundaryTask?.cancel()
        guard clock.phase == .running else { return }
        let r = clock.reading(at: .now, s)
        guard !r.halfOver else { return }
        // Next period change (with or without subs), so the period shown stays current.
        let boundary = r.period.map { Double($0 % s.perHalf + 1) * s.periodSeconds } ?? s.halfSeconds
        let wait = min(boundary, s.halfSeconds) - r.elapsed + 0.5
        boundaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.refreshLiveActivity()
        }
    }

    // MARK: Lineup editing

    private(set) var isAutoFilling = false

    /// Runs the search off the main thread so the screen stays responsive.
    func autofill(fewerMoves: Bool) {
        guard !isAutoFilling else { return }
        isAutoFilling = true
        let snapshot = state
        let lineupID = team.currentID
        Task {
            let filled = await Task.detached(priority: .userInitiated) { () -> LineupState in
                var s = snapshot
                // A fresh plan: subs made during an earlier game no longer apply.
                s.subs = []
                for i in s.players.indices { s.players[i].out = false }
                AutoFill.run(&s, fewerMoves: fewerMoves)
                return s
            }.value
            isAutoFilling = false
            // Skip if the plan was edited (or another lineup opened) while auto-fill was working.
            guard state == snapshot, team.currentID == lineupID else { return }
            update { $0 = filled }
        }
    }

    func player(_ id: String) -> Player? { state.players.first { $0.id == id } }

    /// Save a working copy to a lineup that may not be the open one (e.g. the game's).
    func setLineupState(_ s: LineupState, for id: String) {
        var t = team
        t.apply(s, to: id)
        setTeam(t)
        save()
    }

    // MARK: Subs during the game

    /// When subs made now take effect: changing the lineup for the next kickoff (before the
    /// game or at half time), or a sub during a period. Nil after full time.
    enum SubMoment: Equatable {
        case kickoff(period: Int)
        case live(period: Int, at: TimeInterval)
        var period: Int { switch self { case .kickoff(let p), .live(let p, _): p } }
    }

    func subMoment(at now: Date = .now) -> SubMoment? {
        let s = gameState
        guard !s.players.isEmpty else { return nil }
        if clock.phase == .ready { return .kickoff(period: 0) }
        let r = clock.reading(at: now, s)
        if r.gameOver { return nil }
        if r.halfOver { return .kickoff(period: s.perHalf) }
        guard let p = r.period else { return nil }
        return .live(period: p, at: r.elapsed)
    }

    /// Who's on the field at that moment: player id -> position.
    func field(at m: SubMoment) -> [String: Int] {
        let s = gameState
        switch m {
        case .kickoff(let p):
            return Dictionary(s.players.compactMap { pl in pl.cell(p).map { (pl.id, $0) } }, uniquingKeysWith: { a, _ in a })
        case .live(let p, _):
            return s.positions(atEndOf: p)
        }
    }

    /// The last subs made, until they're undone or the coach moves on.
    struct SubResult {
        let lineupID: String
        let before: LineupState
        /// Upcoming periods the re-plan changed.
        var changedPeriods: Set<Int>
        let made: Date
    }
    private(set) var lastSubs: SubResult?
    private(set) var isReplanning = false

    /// Record subs (off -> on) at this moment, mark anyone out for the game, then re-plan the
    /// rest of the game around them in the background.
    func makeSubs(_ swaps: [(off: String, on: String)], out: Set<String>) {
        guard !isFollowing, !swaps.isEmpty, let m = subMoment() else { return }
        let id = gameLineupID ?? team.currentID
        guard var s = team.state(for: id) else { return }
        let before = s
        for sw in swaps {
            let p = m.period
            switch m {
            case .kickoff:
                guard let i = s.players.firstIndex(where: { $0.id == sw.off }), let j = s.players.firstIndex(where: { $0.id == sw.on }),
                      let pos = s.players[i].cell(p) else { continue }
                s.players[j].cells[p] = pos
                s.players[i].cells[p] = nil
                if pos == 0 { replaceKeeper(&s, half: p / s.perHalf, off: sw.off, on: sw.on) }
            case .live(_, let at):
                guard let pos = s.positions(atEndOf: p)[sw.off] else { continue }
                s.subs.append(MidSub(period: p, at: at, off: sw.off, on: sw.on, pos: pos))
                if pos == 0 { replaceKeeper(&s, half: p / s.perHalf, off: sw.off, on: sw.on) }
            }
        }
        let comingOn = Set(swaps.map(\.on))
        for i in s.players.indices {
            if out.contains(s.players[i].id) { s.players[i].out = true }
            if comingOn.contains(s.players[i].id) { s.players[i].out = false } // back in after all
        }
        s.normalize()
        // Save the subs right away; the rest of the game follows in a moment.
        setLineupState(s, for: id)
        lastSubs = SubResult(lineupID: id, before: before, changedPeriods: [], made: .now)
        let lock = m.period + 1
        guard lock < s.periods else { return }
        isReplanning = true
        let recorded = s
        Task {
            let planned = await Task.detached(priority: .userInitiated) { () -> LineupState in
                var t = recorded
                AutoFill.replan(&t, from: lock)
                return t
            }.value
            isReplanning = false
            // Skip if the lineup was changed again while re-planning.
            guard team.state(for: id) == recorded else { return }
            setLineupState(planned, for: id)
            // Periods where the subs to call (or the half's kickoff lineup) differ from what the
            // coach had before making the sub.
            let changed = (lock..<planned.periods).filter { p in
                p % planned.perHalf == 0 ? before.lineupSummary(at: p) != planned.lineupSummary(at: p)
                                         : before.changeSummary(at: p) != planned.changeSummary(at: p)
            }
            lastSubs?.changedPeriods = Set(changed)
        }
    }

    /// The keeper changed: if that half's keeper was picked by name, follow the change.
    private func replaceKeeper(_ s: inout LineupState, half: Int, off: String, on: String) {
        if half == 0, s.gk1 == off { s.gk1 = on }
        if half == 1, s.gk2 == off { s.gk2 = on }
    }

    func undoSubs() {
        guard let r = lastSubs, team.lineup(r.lineupID) != nil else { return }
        setLineupState(r.before, for: r.lineupID)
        lastSubs = nil
    }

    func dismissSubResult() { lastSubs = nil }

    func updatePlayer(_ id: String, undoable: Bool = true, _ change: @escaping (inout Player) -> Void) {
        update(undoable: undoable) { s in
            if let i = s.players.firstIndex(where: { $0.id == id }) { change(&s.players[i]) }
        }
    }

    @discardableResult
    func addPlayer() -> String {
        let id = Game.newID()
        update { s in
            s.players.append(Player(id: id, name: "", cells: Array(repeating: nil, count: s.periods), can: Game.defaultCan(s.positionCount), weight: 1))
        }
        return id
    }

    func save() {
        // Lineup changed mid-game: refresh the alerts and lock screen, and tell followers.
        if !isFollowing {
            if clock.phase == .running { SubAlerts.reschedule(gameState, clock) }
            if clock.phase != .ready { LiveGame.sync(gameState, clock) }
        }
        rosterChanged()
        pushBroadcast()
        do {
            try JSONEncoder().encode(team).write(to: Self.fileURL, options: .atomic)
        } catch {
            print("Could not save team: \(error)")
        }
    }
}
