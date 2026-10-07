import ActivityKit
import Foundation

/// Keeps the lock screen / Dynamic Island Live Activity in step with the game clock.
@MainActor
enum LiveGame {
    static func sync(_ s: LineupState, _ clock: GameClock, now: Date = .now) {
        let running = Activity<GameActivityAttributes>.activities
        guard clock.phase != .ready, let state = content(s, clock, now: now) else {
            end()
            return
        }
        let staleDate = state.phase == .running ? (state.nextSubAt ?? state.halfEnd) : nil
        let content = ActivityContent(state: state, staleDate: staleDate, relevanceScore: 100)
        if let activity = running.first {
            Task {
                if state.phase == .fulltime {
                    await activity.end(content, dismissalPolicy: .after(now.addingTimeInterval(15 * 60)))
                } else {
                    await activity.update(content)
                }
            }
        } else if state.phase != .fulltime, ActivityAuthorizationInfo().areActivitiesEnabled {
            let team = s.title.isEmpty ? "Game" : s.title
            _ = try? Activity.request(attributes: GameActivityAttributes(teamName: team), content: content, pushType: nil)
        }
    }

    static func end() {
        for activity in Activity<GameActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    static func content(_ s: LineupState, _ clock: GameClock, now: Date) -> GameActivityAttributes.ContentState? {
        let r = clock.reading(at: now, s)
        guard r.started, let p = r.period else { return nil }
        let isRunning = clock.phase == .running
        let halfStart = isRunning ? now.addingTimeInterval(-r.elapsed) : nil
        var st = GameActivityAttributes.ContentState(
            phase: r.halfOver ? (r.half == 0 ? .halftime : .fulltime) : isRunning ? .running : .paused,
            half: r.half,
            period: p % s.perHalf + 1,
            periodsPerHalf: s.perHalf,
            halfStart: halfStart,
            halfEnd: halfStart?.addingTimeInterval(s.halfSeconds),
            elapsed: r.elapsed)
        if r.halfOver {
            if r.half == 0 { st.note = s.lineupSummary(at: s.perHalf) }
            return st
        }
        if let next = r.nextSubAt {
            let c = s.changes(at: p + 1)
            func nm(_ x: Player) -> String { x.name.isEmpty ? "?" : x.name }
            st.nextSubAt = halfStart?.addingTimeInterval(next)
            st.nextSubClock = GameActivityAttributes.clock(next)
            st.nextPeriod = (p + 1) % s.perHalf + 1
            st.nextIn = c.swaps.map { "\(nm($0.player)) (\(s.positionName($0.pos)))" }
            st.nextOut = c.swaps.compactMap { $0.replacing.map(nm) } + c.off.map(nm)
            st.nextMoves = c.moves.map { "\(nm($0.player)) \(s.positionName($0.from))→\(s.positionName($0.to))" }
            let later = next + s.periodSeconds
            st.laterSubClock = later < s.halfSeconds - 1 ? GameActivityAttributes.clock(later) : nil
        }
        return st
    }
}
