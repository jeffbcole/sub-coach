import ActivityKit
import Foundation

/// The lock screen / Dynamic Island game clock. Shared by the app and the widget extension.
struct GameActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable { case running, paused, halftime, fulltime }
        var phase: Phase
        /// 0 = first half, 1 = second half.
        var half: Int
        /// Period being played, counted within the half (1-based).
        var period: Int
        var periodsPerHalf: Int
        /// While running: when this half's clock read 0:00, so the clock can count up on its own.
        var halfStart: Date?
        var halfEnd: Date?
        /// Clock reading when paused.
        var elapsed: TimeInterval
        /// When the next sub is due (nil in the last period of a half).
        var nextSubAt: Date?
        var nextSubClock: String?
        var nextPeriod: Int?
        var nextIn: [String] = []
        var nextOut: [String] = []
        var nextMoves: [String] = []
        /// The sub after that, e.g. "15:00", shown once the next one is due.
        var laterSubClock: String?
        /// Half-time: the second half lineup.
        var note: String?
    }

    var teamName: String

    static func clock(_ seconds: TimeInterval) -> String {
        let t = max(0, Int(seconds))
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}
