import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LineupWidgetBundle: WidgetBundle {
    var body: some Widget { GameLiveActivity() }
}

private let green = Color(red: 0.30, green: 0.77, blue: 0.45)
private let orange = Color.orange

struct GameLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GameActivityAttributes.self) { context in
            LockScreenView(team: context.attributes.teamName, s: context.state, stale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(green)
        } dynamicIsland: { context in
            let s = context.state, stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(halfLabel(s)).font(.caption2).foregroundStyle(.secondary)
                        Text(periodLabel(s, stale: stale)).font(.headline)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GameClockText(s: s)
                        .font(.title2.weight(.bold).monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    NextSubView(s: s, stale: stale, compact: true)
                        .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "figure.soccer").foregroundStyle(green)
            } compactTrailing: {
                CountdownText(s: s, stale: stale)
                    .frame(maxWidth: 48)
            } minimal: {
                CountdownText(s: s, stale: stale, short: true)
                    .frame(maxWidth: 36)
            }
            .keylineTint(green)
        }
    }
}

private func halfLabel(_ s: GameActivityAttributes.ContentState) -> String {
    s.half == 0 ? "1st half" : "2nd half"
}

/// Once the next sub is due (stale) the app may not have run yet, so show the new period.
private func periodLabel(_ s: GameActivityAttributes.ContentState, stale: Bool = false) -> String {
    switch s.phase {
    case .halftime: return "Half time"
    case .fulltime: return "Full time"
    default:
        let p = stale && s.phase == .running ? (s.nextPeriod ?? s.period) : s.period
        return "Period \(p) of \(s.periodsPerHalf)"
    }
}

/// The game clock, counting up on its own while running.
private struct GameClockText: View {
    let s: GameActivityAttributes.ContentState
    var body: some View {
        if s.phase == .running, let start = s.halfStart, let end = s.halfEnd {
            Text(timerInterval: start...end, countsDown: false)
                .multilineTextAlignment(.trailing)
        } else {
            Text(GameActivityAttributes.clock(s.elapsed))
        }
    }
}

/// Time left until the next sub (or the end of the half).
private struct CountdownText: View {
    let s: GameActivityAttributes.ContentState
    let stale: Bool
    var short = false
    var body: some View {
        switch s.phase {
        case .halftime: Text("HT").font(.caption.weight(.bold)).foregroundStyle(green)
        case .fulltime: Text("FT").font(.caption.weight(.bold)).foregroundStyle(green)
        case .paused: Image(systemName: "pause.fill").foregroundStyle(.secondary)
        case .running:
            if stale {
                Text(s.nextSubAt == nil ? "HT" : "SUB").font(.caption.weight(.heavy)).foregroundStyle(orange)
            } else if let target = s.nextSubAt ?? s.halfEnd {
                Text(timerInterval: min(Date.now, target)...target, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(s.nextSubAt == nil ? Color.primary : green)
            }
        }
    }
}

/// Who goes in and out at the next change.
private struct NextSubView: View {
    let s: GameActivityAttributes.ContentState
    let stale: Bool
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            switch s.phase {
            case .halftime:
                Text("2nd half lineup").font(.subheadline.weight(.semibold))
                if let note = s.note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
            case .fulltime:
                Text("That's the game.").font(.subheadline.weight(.semibold))
            case .paused, .running:
                header
                if s.nextSubAt != nil || (s.phase == .paused && s.nextSubClock != nil) {
                    names("arrow.up.circle.fill", green, s.nextIn)
                    names("arrow.down.circle.fill", .red, s.nextOut)
                    if !s.nextMoves.isEmpty {
                        names("arrow.left.arrow.right.circle.fill", .secondary, s.nextMoves)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var header: some View {
        let hasNext = s.nextSubClock != nil
        if s.phase == .paused {
            Text(hasNext ? "Paused · next sub at \(s.nextSubClock!)" : "Paused")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
        } else if stale && hasNext {
            HStack(spacing: 6) {
                Text("SUB NOW · Period \(s.nextPeriod ?? 0)").font(compact ? .subheadline.weight(.heavy) : .title3.weight(.heavy)).foregroundStyle(orange)
                Spacer()
                if let later = s.laterSubClock {
                    Text("then \(later)").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else if stale {
            Text("Half over").font(.headline).foregroundStyle(orange)
        } else if let next = s.nextSubAt, let clock = s.nextSubClock {
            HStack(alignment: .firstTextBaseline) {
                Text("Next sub at \(clock)").font(.subheadline.weight(.semibold))
                Spacer()
                Text(timerInterval: min(Date.now, next)...next, countsDown: true)
                    .font(compact ? .headline.monospacedDigit() : .system(size: 28, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(green)
                    .multilineTextAlignment(.trailing)
                    .frame(width: compact ? 60 : 96, alignment: .trailing)
            }
        } else if let end = s.halfEnd {
            HStack(alignment: .firstTextBaseline) {
                Text(s.half == 0 ? "No more subs · half ends in" : "No more subs · game ends in").font(.subheadline.weight(.semibold))
                Spacer()
                Text(timerInterval: min(Date.now, end)...end, countsDown: true)
                    .font(.headline.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private func names(_ icon: String, _ color: Color, _ list: [String]) -> some View {
        if !list.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text(list.joined(separator: ", ")).font(compact ? .caption : .subheadline).lineLimit(2)
            }
        }
    }
}

private struct LockScreenView: View {
    let team: String
    let s: GameActivityAttributes.ContentState
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "figure.soccer").foregroundStyle(green)
                Text(team).font(.caption.weight(.semibold)).lineLimit(1)
                Text("· \(halfLabel(s)) · \(periodLabel(s, stale: stale))").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                GameClockText(s: s)
                    .font(.headline.monospacedDigit())
                    .frame(maxWidth: 64, alignment: .trailing)
            }
            NextSubView(s: s, stale: stale)
        }
        .foregroundStyle(.white)
        .padding(14)
    }
}
