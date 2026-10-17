import SwiftUI

/// Game clock plus the subs to call at the start of each period.
struct GameDayView: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmEnd = false
    @State private var askName = false
    @State private var nameText = ""
    /// A player tapped on the field, to sub off.
    @State private var subChoice: MakeSubSheet.Choice?

    /// How long a period's card says "SUB NOW" after the change.
    static let subNowSeconds: TimeInterval = 45
    /// Heads-up before a change.
    static let getReadySeconds: TimeInterval = 30

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                let s = store.liveState
                let r = store.liveClock.reading(at: ctx.date, s)
                VStack(spacing: 0) {
                    ClockCard(s: s, r: r, onTap: canSub(r) ? { pos, id in subChoice = .init(off: id, pos: pos) } : nil)
                        .padding(.horizontal)
                        .padding(.top, 4)
                        .padding(.bottom, 8)
                    if store.isBroadcasting {
                        BroadcastStrip()
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    Group {
                        if store.isFollowing {
                            CommandBanner(now: ctx.date)
                        } else {
                            RemoteNoteBanner(now: ctx.date)
                            SubResultBanner(now: ctx.date)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                let upcoming = (0..<s.periods).filter { s.showsCard($0) && showsUpcoming($0, r, s) }
                                if !upcoming.isEmpty || !r.gameOver {
                                    Text("Upcoming subs")
                                        .font(.footnote.weight(.semibold)).textCase(.uppercase)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 4)
                                        .id("top")
                                }
                                ForEach(upcoming, id: \.self) { p in
                                    SubCard(s: s, period: p, status: status(p, r, s),
                                            changed: !store.isFollowing && store.lastSubs?.changedPeriods.contains(p) == true)
                                }
                                if upcoming.isEmpty && !r.gameOver {
                                    Text("No more subs this game.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(14)
                                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                                }
                                PlayingTimeCard(s: s, r: r)
                                    .padding(.top, 8)
                            }
                            .padding([.horizontal, .bottom])
                            .padding(.top, 4)
                        }
                        // Back to the next subs when the lineup changes.
                        .onChange(of: focus(r, s)) { _, _ in
                            withAnimation { proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                }
                .sensoryFeedback(.warning, trigger: r.period) { old, new in
                    if let old, let new { return new > old && s.hasSubs(at: new) }
                    return false
                }
                .sensoryFeedback(.success, trigger: r.halfOver) { _, new in new }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.liveState.title.isEmpty ? "Game Day" : store.liveState.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // The clock keeps running; "Resume game" brings this back.
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close")
                }
                if !store.isFollowing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if store.isBroadcasting {
                                store.setBroadcasting(false)
                            } else if Coach.name.isEmpty {
                                nameText = ""
                                askName = true
                            } else {
                                store.setBroadcasting(true)
                            }
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .symbolEffect(.variableColor.iterative, isActive: store.isBroadcasting)
                                .foregroundStyle(store.isBroadcasting ? Color.blue : Theme.accent)
                        }
                        .accessibilityLabel(store.isBroadcasting ? "Stop broadcasting" : "Broadcast to nearby coaches")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if store.liveClock.phase != .ready {
                            Section("Adjust clock") {
                                Button { store.game(.adjust(seconds: 60)) } label: { Label("Add 1 minute", systemImage: "plus") }
                                Button { store.game(.adjust(seconds: 10)) } label: { Label("Add 10 seconds", systemImage: "plus") }
                                Button { store.game(.adjust(seconds: -10)) } label: { Label("Take off 10 seconds", systemImage: "minus") }
                                Button { store.game(.adjust(seconds: -60)) } label: { Label("Take off 1 minute", systemImage: "minus") }
                            }
                            Button { store.game(.endHalf) } label: { Label("End half now", systemImage: "forward.end") }
                            // Ending the game also ends the broadcast, so only the host can.
                            if !store.isFollowing {
                                Button(role: .destructive) { confirmEnd = true } label: { Label("End game", systemImage: "stop.fill") }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(store.liveClock.phase == .ready || !store.canControlGame)
                    .opacity(store.canControlGame ? 1 : 0)
                    .accessibilityLabel("Clock options")
                }
            }
            .confirmationDialog("End the game?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End game", role: .destructive) {
                    store.resetClock()
                    dismiss()
                }
            } message: {
                Text("The clock stops and the lineup is ready for a new game.")
            }
            .alert("Your name", isPresented: $askName) {
                TextField("e.g. Coach Jeff", text: $nameText)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Broadcast") {
                    Coach.name = nameText
                    store.setBroadcasting(true)
                }
            } message: {
                Text("Shown to coaches nearby when they're asked to follow your game.")
            }
            .sheet(item: $subChoice) { MakeSubSheet(start: $0) }
            .onAppear { store.applyIdleTimer() }
            .onDisappear {
                // Closing after full time ends the game, so the lineup is ready to start again.
                if !store.isFollowing, store.gameLineupID != nil, store.liveGameLineupID() == nil { store.resetClock() }
            }
        }
    }

    /// Subs can be started by tapping a player on the field before full time: on this phone's
    /// game, or a followed one whose host lets followers make changes.
    private func canSub(_ r: GameClock.Reading) -> Bool {
        store.canControlGame && !r.gameOver && !store.liveState.players.isEmpty
    }

    /// Below the field: subs still to call (including ones to call right now). A kickoff
    /// lineup already shown on the field is left out.
    private func showsUpcoming(_ p: Int, _ r: GameClock.Reading, _ s: LineupState) -> Bool {
        switch status(p, r, s) {
        case .done, .now: return false
        case .subNow: return true
        case .next, .upcoming:
            let onFieldNow = !r.started ? 0 : r.halfOver && r.half == 0 ? s.perHalf : nil
            return p != onFieldNow
        }
    }

    /// Changes whenever a new lineup takes the field.
    private func focus(_ r: GameClock.Reading, _ s: LineupState) -> Int {
        if r.halfOver && r.half == 0 { return s.perHalf }
        return onNow(r, s) ?? 0
    }

    /// The card for the lineup on the field now: the current period's, or the last shown
    /// card before it when nothing changed at the start of this period.
    private func onNow(_ r: GameClock.Reading, _ s: LineupState) -> Int? {
        guard let cur = r.period else { return nil }
        return (0...cur).last(where: s.showsCard)
    }

    private func status(_ p: Int, _ r: GameClock.Reading, _ s: LineupState) -> SubCard.Status {
        guard r.started, let now = onNow(r, s) else { return p == 0 ? .next : .upcoming }
        if r.halfOver {
            if r.half == 1 { return .done }
            return p < s.perHalf ? .done : p == s.perHalf ? .next : .upcoming
        }
        if p < now { return .done }
        if p == now {
            return p == r.period && r.periodHasSubs && r.sincePeriodStart < Self.subNowSeconds ? .subNow : .now
        }
        if p == r.nextSubPeriod { return .next }
        return .upcoming
    }
}

// MARK: - Clock

private struct ClockCard: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let s: LineupState
    let r: GameClock.Reading
    /// Tapping a player on the field: nil when subs can't be made from here.
    let onTap: ((_ pos: Int, _ id: String) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Text(statusLine)
                .font(.caption.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Text(Game.clock(seconds: Int(r.elapsed)))
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(store.liveClock.phase == .paused && !r.halfOver ? .secondary : .primary)
                pauseButton
            }
            segments
            if r.started {
                alertLine
                    .frame(minHeight: 30)
            }
            buttons
            LineupField(s: s, r: r, onTap: onTap)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    /// Pause / resume, next to the clock while a half is being played.
    @ViewBuilder private var pauseButton: some View {
        let phase = store.liveClock.phase
        if store.canControlGame, phase != .ready, !r.halfOver {
            let running = phase == .running
            Button {
                store.game(running ? .pause : .resume)
            } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(running ? Theme.accent : Theme.accentText)
                    .background(running ? Theme.accent.opacity(0.15) : Theme.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(running ? "Pause" : "Resume")
        }
    }

    private var statusLine: String {
        guard r.started, let p = r.period else { return "Ready for kickoff" }
        if r.halfOver { return r.half == 0 ? "Half time" : "Full time" }
        let half = r.half == 0 ? "1st half" : "2nd half"
        let paused = store.liveClock.phase == .paused ? " · Paused" : ""
        return "\(half) · Period \(p % s.perHalf + 1) of \(s.perHalf)\(paused)"
    }

    /// One bar per period in this half, filling as the clock runs.
    private var segments: some View {
        HStack(spacing: 4) {
            ForEach(0..<s.perHalf, id: \.self) { k in
                let fill = min(1, max(0, (r.elapsed - Double(k) * s.periodSeconds) / s.periodSeconds))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.benchBG)
                        Capsule().fill(Theme.accent).frame(width: g.size.width * fill)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    @ViewBuilder private var alertLine: some View {
        if !r.started {
            EmptyView()
        } else if r.halfOver {
            Text(r.half == 0 ? "Tap a player to change the 2nd half lineup." : "That's the game.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if let p = r.period, r.periodHasSubs, r.sincePeriodStart < GameDayView.subNowSeconds {
            pill("SUB NOW · Period \(p + 1)", systemImage: "arrow.left.arrow.right", color: .orange)
        } else if let next = r.nextSubAt {
            let left = next - r.elapsed
            if left <= GameDayView.getReadySeconds {
                pill("Get ready · subs in \(Game.clock(seconds: Int(left.rounded(.up))))", systemImage: "bell.fill", color: .orange.opacity(0.85))
            } else {
                Text("Next sub at **\(Game.clock(seconds: Int(next)))** · in \(Game.clock(seconds: Int(left.rounded(.up))))")
                    .font(.subheadline).monospacedDigit()
            }
        } else {
            let left = s.halfSeconds - r.elapsed
            Text("\(r.half == 0 ? "Half" : "Game") ends in \(Game.clock(seconds: Int(left.rounded(.up))))")
                .font(.subheadline).monospacedDigit()
        }
    }

    private func pill(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.headline).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 5)
            .background(color, in: Capsule())
    }

    /// Only for starting a half or ending the game; pausing is next to the clock and subs are
    /// made by tapping a player.
    @ViewBuilder private var buttons: some View {
        if let f = store.following {
            VStack(spacing: 10) {
                if store.canControlGame {
                    if store.liveClock.phase == .ready {
                        bigButton("Kick off", systemImage: "play.fill") { store.game(.kickoff) }
                    } else if r.halfOver && r.half == 0 {
                        bigButton("Start 2nd half", systemImage: "play.fill") { store.game(.startSecondHalf) }
                    }
                }
                FollowerControls(game: f)
            }
        } else if store.liveClock.phase == .ready {
            bigButton("Kick off", systemImage: "play.fill") { store.game(.kickoff) }
        } else if r.halfOver {
            if r.half == 0 {
                bigButton("Start 2nd half", systemImage: "play.fill") { store.game(.startSecondHalf) }
            } else {
                Button {
                    store.resetClock()
                    dismiss()
                } label: {
                    Label("End game", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        }
    }

    private func bigButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent).controlSize(.large)
    }
}

// MARK: - Sub cards

struct SubCard: View {
    enum Status { case done, now, subNow, next, upcoming }
    let s: LineupState
    let period: Int
    let status: Status
    /// Just changed by a re-plan after a sub.
    var changed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if changed && status != .done { tag("Updated", .orange) }
                badge
            }
            // Everyone is off the field at kickoff, so show the lineup, not changes.
            // Names and positions three text sizes up, to read at a glance on the sideline.
            Group {
                if period % s.perHalf == 0 {
                    lineupGrid(period)
                } else {
                    changeRows
                }
                midSubRows
            }
            .dynamicTypeSize(.xxxLarge)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            if status == .subNow || status == .now || status == .next {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(status == .subNow ? Color.orange : status == .now ? Theme.accent : Color(.separator), lineWidth: status == .next ? 1 : 2)
            }
        }
        .opacity(status == .done ? 0.5 : 1)
    }

    private var title: String {
        if period == 0 { return "Kickoff · starting lineup" }
        if period == s.perHalf { return "2nd half kickoff · lineup" }
        return "Period \(period + 1)"
    }

    private var subtitle: String {
        let half = period < s.perHalf ? "1st half" : "2nd half"
        return "\(half) · \(s.startAt(period % s.perHalf))"
    }

    @ViewBuilder private var badge: some View {
        switch status {
        case .done: Label("Done", systemImage: "checkmark").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        case .now: tag("On now", Theme.accent)
        case .subNow: tag("SUB NOW", .orange)
        case .next: tag("Next", .secondary)
        case .upcoming: EmptyView()
        }
    }

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption.weight(.bold))
            .foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(c.opacity(0.15), in: Capsule())
    }

    private func chip(_ pos: Int) -> some View {
        Text(s.positionName(pos))
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .frame(minWidth: 34)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .foregroundStyle(Theme.foreground(group: s.group(pos)))
            .background(Theme.background(group: s.group(pos)), in: RoundedRectangle(cornerRadius: 5))
    }

    private func name(_ p: Player) -> String { p.name.isEmpty ? "Unnamed" : p.name }

    /// Subs made during this period, with the clock time.
    @ViewBuilder private var midSubRows: some View {
        let subs = s.subs(in: period)
        if !subs.isEmpty {
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(subs) { sub in
                    HStack(spacing: 8) {
                        chip(sub.pos)
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                        Text(s.name(sub.on)).font(.subheadline.weight(.semibold))
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red).padding(.leading, 6)
                        Text(s.name(sub.off)).font(.subheadline).foregroundStyle(.secondary)
                        if s.players.first(where: { $0.id == sub.off })?.out == true {
                            Text("out").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                        }
                        Spacer(minLength: 4)
                        Text(Game.clock(seconds: Int(sub.at))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("At \(Game.clock(seconds: Int(sub.at))), \(s.name(sub.on)) in at \(s.positionName(sub.pos)) for \(s.name(sub.off))")
                }
            }
        }
    }

    /// A kickoff lineup in the formation: forwards at the top, the keeper at the bottom, and
    /// each line's positions left to right.
    private func lineupGrid(_ p: Int) -> some View {
        let byPos = Dictionary(s.lineup(at: p).map { ($0.pos, $0.player) }, uniquingKeysWith: { a, _ in a })
        let lines = Array(Set((0..<s.positionCount).map(s.group))).sorted(by: >)
        return VStack(spacing: 10) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 4) {
                    ForEach((0..<s.positionCount).filter { s.group($0) == line }, id: \.self) { pos in
                        VStack(spacing: 3) {
                            chip(pos)
                            Text(byPos[pos].map(name) ?? "Empty")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(byPos[pos] == nil ? .secondary : .primary)
                                .lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder private var changeRows: some View {
        let c = s.changes(at: period)
        if c.isEmpty {
            Text("No changes").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(c.swaps) { sw in
                    HStack(spacing: 8) {
                        chip(sw.pos)
                        Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                        Text(name(sw.player)).font(.subheadline.weight(.semibold))
                        if let out = sw.replacing {
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red).padding(.leading, 6)
                            Text(name(out)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(sw.player)) in at \(s.positionName(sw.pos))" + (sw.replacing.map { ", for \(name($0))" } ?? ""))
                }
                ForEach(c.off) { p in
                    HStack(spacing: 8) {
                        Text("Off").font(.caption.weight(.bold)).frame(minWidth: 34).padding(.horizontal, 5).padding(.vertical, 3)
                            .foregroundStyle(Theme.benchFG).background(Theme.benchBG, in: RoundedRectangle(cornerRadius: 5))
                        Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red)
                        Text(name(p)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(p)) comes off")
                }
                ForEach(c.moves) { m in
                    HStack(spacing: 6) {
                        chip(m.from)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        chip(m.to)
                        Text(name(m.player)).font(.subheadline.weight(.medium)).padding(.leading, 2)
                        Text("moves").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(name(m.player)) moves from \(s.positionName(m.from)) to \(s.positionName(m.to))")
                }
            }
        }
    }
}

// MARK: - Playing time

/// At the bottom of Game Day: each girl's minutes so far against the plan, and the
/// positions she has played.
private struct PlayingTimeCard: View {
    let s: LineupState
    let r: GameClock.Reading

    var body: some View {
        // How much of the game has been played: whole periods, plus the current one so far.
        let (period, at): (Int, TimeInterval?) =
            !r.started ? (0, nil)
            : r.halfOver ? ((r.half + 1) * s.perHalf, nil)
            : (r.period ?? 0, r.elapsed)
        let soFar = s.positionsSoFar(period: period, at: at)
        let planned = s.secondsPlayed(in: 0..<s.periods)
        // Where the game is now on the timelines.
        let now: (half: Int, at: TimeInterval)? =
            !r.started ? nil : r.halfOver ? (r.half, s.halfSeconds) : (r.half, r.elapsed)
        VStack(alignment: .leading, spacing: 0) {
            Text("Playing time").font(.headline)
            Text(r.started ? "Minutes so far, of the minutes planned for the game" : "Minutes planned for the game")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 6)
            HStack(spacing: PlayerTimeline.gap) {
                Text("1st half").frame(maxWidth: .infinity)
                Text("2nd half").frame(maxWidth: .infinity)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.bottom, 2)
            ForEach(s.players.filter { !$0.absent }) { pl in
                row(pl, byPos: soFar[pl.id] ?? [:], planned: planned[pl.id] ?? 0, now: now)
                if pl.id != s.players.last(where: { !$0.absent })?.id { Divider() }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func row(_ pl: Player, byPos: [Int: TimeInterval], planned: TimeInterval,
                     now: (half: Int, at: TimeInterval)?) -> some View {
        let played = byPos.values.reduce(0, +)
        let positions: [(key: Int, value: TimeInterval)] = byPos.filter { $0.value >= 1 }.sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.name(pl.id)).font(.subheadline.weight(.semibold))
                if pl.out { Text("out").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn) }
                Spacer()
                Text(r.started ? "\(Self.minutes(played)) of \(Self.minutes(planned)) min" : "\(Self.minutes(planned)) min")
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            PlayerTimeline(s: s, blocks: s.timeline(pl.id), now: now)
            if !positions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(positions, id: \.key) { item in positionChip(item.key, item.value) }
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func positionChip(_ pos: Int, _ t: TimeInterval) -> some View {
        HStack(spacing: 3) {
            Text(s.positionName(pos)).font(.caption.weight(.bold))
            Text("\(Self.minutes(t))m").font(.caption).monospacedDigit()
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
        .foregroundStyle(Theme.foreground(group: s.group(pos)))
        .background(Theme.background(group: s.group(pos)), in: RoundedRectangle(cornerRadius: 5))
    }

    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded()) }
}

/// One girl's game as a timeline: both halves side by side, a block for each stretch at a
/// position. What's been played is faded; what's still to come is in full color.
private struct PlayerTimeline: View {
    static let gap: CGFloat = 6
    let s: LineupState
    let blocks: [LineupState.TimelineBlock]
    let now: (half: Int, at: TimeInterval)?

    var body: some View {
        GeometryReader { g in
            let halfW = (g.size.width - Self.gap) / 2
            ZStack(alignment: .topLeading) {
                ForEach(0..<2, id: \.self) { h in
                    RoundedRectangle(cornerRadius: 3).fill(Theme.benchBG)
                        .frame(width: halfW)
                        .offset(x: CGFloat(h) * (halfW + Self.gap))
                }
                ForEach(pieces(), id: \.block) { piece in
                    block(piece.block, past: piece.past, halfW: halfW)
                }
                if let now {
                    Capsule().fill(Theme.accent)
                        .frame(width: 2)
                        .offset(x: x(now.half, now.at, halfW) - 1)
                }
            }
        }
        .frame(height: 20)
    }

    private func x(_ half: Int, _ t: TimeInterval, _ halfW: CGFloat) -> CGFloat {
        CGFloat(half) * (halfW + Self.gap) + CGFloat(t / s.halfSeconds) * halfW
    }

    private func block(_ b: LineupState.TimelineBlock, past: Bool, halfW: CGFloat) -> some View {
        let w = max(1, x(b.half, b.end, halfW) - x(b.half, b.start, halfW) - 1)
        return RoundedRectangle(cornerRadius: 3)
            .fill(Theme.background(group: s.group(b.pos)))
            .overlay {
                if w >= 18 {
                    Text(s.positionName(b.pos))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.foreground(group: s.group(b.pos)))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .padding(.horizontal, 1)
                }
            }
            .frame(width: w)
            .opacity(past ? 0.4 : 1)
            .offset(x: x(b.half, b.start, halfW))
    }

    /// Blocks split at the current time into what's been played and what's to come.
    private func pieces() -> [(block: LineupState.TimelineBlock, past: Bool)] {
        guard let now else { return blocks.map { ($0, false) } }
        var out: [(block: LineupState.TimelineBlock, past: Bool)] = []
        for b in blocks {
            if b.half < now.half || (b.half == now.half && b.end <= now.at) {
                out.append((b, true))
            } else if b.half > now.half || b.start >= now.at {
                out.append((b, false))
            } else {
                var before = b, after = b
                before.end = now.at; after.start = now.at
                out.append((before, true)); out.append((after, false))
            }
        }
        return out
    }
}

// MARK: - After a sub

/// Shown under the clock after subs: re-planning, then what changed, with Undo.
private struct SubResultBanner: View {
    @Environment(LineupStore.self) private var store
    let now: Date
    /// How long Undo stays offered for this phone's own subs; a following coach's sub is just
    /// a heads-up, so it goes away sooner like the other notes.
    static let visibleFor: TimeInterval = 120, remoteVisibleFor: TimeInterval = 8

    var body: some View {
        if store.isReplanning {
            HStack(spacing: 8) {
                ProgressView()
                Text("Updating the rest of the game…").font(.subheadline.weight(.medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        } else if let r = store.lastSubs, now.timeIntervalSince(r.made) < (r.madeBy == nil ? Self.visibleFor : Self.remoteVisibleFor) {
            let n = r.changedPeriods.count
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.madeBy.map { "\($0) made a sub" + (n == 0 ? "" : " · rest of game updated") }
                         ?? (n == 0 ? "Sub made" : "Rest of game updated"))
                        .font(.subheadline.weight(.semibold))
                    Text(n == 0 ? "No changes needed to upcoming subs" : "\(n) upcoming \(n == 1 ? "period" : "periods") changed")
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Button("Undo") { store.undoSubs() }
                    .font(.subheadline.weight(.semibold))
                Button { store.dismissSubResult() } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                    .accessibilityLabel("Dismiss")
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Sharing

/// Host: what a following coach just did to the clock, for a few seconds.
private struct RemoteNoteBanner: View {
    @Environment(LineupStore.self) private var store
    let now: Date

    var body: some View {
        if let n = store.remoteNote, now.timeIntervalSince(n.at) < 6 {
            Label(n.text, systemImage: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Follower: a change sent to the host, until it's confirmed (or didn't get through).
private struct CommandBanner: View {
    @Environment(LineupStore.self) private var store
    let now: Date

    var body: some View {
        if let c = store.commandStatus, let host = store.following?.hostName,
           c.state == .sending || now.timeIntervalSince(c.at) < (c.state == .failed ? 10 : 4) {
            HStack(spacing: 8) {
                switch c.state {
                case .sending:
                    ProgressView()
                    Text("Sending to \(host)…")
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                    Text("Done · everyone's phone is updated")
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("Couldn't reach \(host)'s phone. Try again.")
                }
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(c.state == .failed ? Theme.warn : c.state == .done ? Theme.accent : .blue)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background((c.state == .failed ? Theme.warn : c.state == .done ? Theme.accent : .blue).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Host: shown under the clock while broadcasting.
private struct BroadcastStrip: View {
    @Environment(LineupStore.self) private var store

    var body: some View {
        let names = store.followers.map(\.coachName)
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative)
            VStack(alignment: .leading, spacing: 1) {
                Text(names.isEmpty ? "Broadcasting to nearby coaches" : "\(names.count) following: \(names.joined(separator: ", "))")
                    .lineLimit(2)
                Text("Coaches following can make subs and run the clock")
                    .font(.caption).opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Follower: who's being followed, and the way out.
private struct FollowerControls: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let game: FollowedGame

    var body: some View {
        VStack(spacing: 10) {
            if game.ended {
                Label("\(game.hostName) ended the broadcast", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 5)) { ctx in
                    let ago = Int(ctx.date.timeIntervalSince(game.lastUpdate))
                    Label("Following \(game.hostName)" + (ago >= 60 ? " · last update \(ago / 60) min ago" : ""),
                          systemImage: "antenna.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                }
            }
            // The lineup is already in this coach's saved lineups; following again is from there.
            Button(role: game.ended ? nil : .destructive) {
                store.stopFollowing()
                dismiss()
            } label: {
                Text(game.ended ? "Close" : "Stop following").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        }
    }
}
