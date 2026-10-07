import SwiftUI

/// Game clock plus the subs to call at the start of each period.
struct GameDayView: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var askName = false
    @State private var nameText = ""

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
                    ClockCard(s: s, r: r)
                        .padding([.horizontal, .top])
                        .padding(.bottom, 8)
                    if store.isBroadcasting {
                        BroadcastStrip()
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(0..<s.periods, id: \.self) { p in
                                    SubCard(s: s, period: p, status: status(p, r, s)).id(p)
                                }
                            }
                            .padding([.horizontal, .bottom])
                            .padding(.top, 4)
                        }
                        .onChange(of: focus(r, s)) { _, p in
                            withAnimation { proxy.scrollTo(p, anchor: .top) }
                        }
                        .onAppear { proxy.scrollTo(focus(r, s), anchor: .top) }
                    }
                }
                .sensoryFeedback(.warning, trigger: r.period) { old, new in
                    if let old, let new { return new > old }
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
                        if store.clock.phase != .ready {
                            Section("Adjust clock") {
                                Button { store.adjustClock(by: 60) } label: { Label("Add 1 minute", systemImage: "plus") }
                                Button { store.adjustClock(by: 10) } label: { Label("Add 10 seconds", systemImage: "plus") }
                                Button { store.adjustClock(by: -10) } label: { Label("Take off 10 seconds", systemImage: "minus") }
                                Button { store.adjustClock(by: -60) } label: { Label("Take off 1 minute", systemImage: "minus") }
                            }
                            Button { store.endHalfNow() } label: { Label("End half now", systemImage: "forward.end") }
                            Button(role: .destructive) { confirmReset = true } label: { Label("Reset clock", systemImage: "arrow.counterclockwise") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(store.clock.phase == .ready || store.isFollowing)
                    .opacity(store.isFollowing ? 0 : 1)
                    .accessibilityLabel("Clock options")
                }
            }
            .confirmationDialog("Reset the game clock?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset clock", role: .destructive) { store.resetClock() }
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
            .onAppear { store.applyIdleTimer() }
        }
    }

    /// Which card to keep scrolled to the top.
    private func focus(_ r: GameClock.Reading, _ s: LineupState) -> Int {
        if r.halfOver && r.half == 0 { return s.perHalf }
        return r.period ?? 0
    }

    private func status(_ p: Int, _ r: GameClock.Reading, _ s: LineupState) -> SubCard.Status {
        guard r.started, let cur = r.period else { return p == 0 ? .next : .upcoming }
        if r.halfOver {
            if r.half == 1 { return .done }
            return p < s.perHalf ? .done : p == s.perHalf ? .next : .upcoming
        }
        if p < cur { return .done }
        if p == cur {
            return p % s.perHalf != 0 && r.sincePeriodStart < Self.subNowSeconds ? .subNow : .now
        }
        if p == cur + 1 && p % s.perHalf != 0 { return .next }
        return .upcoming
    }
}

// MARK: - Clock

private struct ClockCard: View {
    @Environment(LineupStore.self) private var store
    let s: LineupState
    let r: GameClock.Reading

    var body: some View {
        VStack(spacing: 8) {
            Text(statusLine)
                .font(.footnote.weight(.semibold)).textCase(.uppercase)
                .foregroundStyle(.secondary)
            Text(Game.clock(seconds: Int(r.elapsed)))
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(store.liveClock.phase == .paused && !r.halfOver ? .secondary : .primary)
            segments
            if r.started {
                alertLine
                    .frame(minHeight: 34)
            }
            buttons
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
                .frame(height: 6)
            }
        }
    }

    @ViewBuilder private var alertLine: some View {
        if !r.started {
            EmptyView()
        } else if r.halfOver {
            Text(r.half == 0 ? "Second half lineup is below." : "That's the game.")
                .font(.subheadline).foregroundStyle(.secondary)
        } else if let p = r.period, p % s.perHalf != 0, r.sincePeriodStart < GameDayView.subNowSeconds {
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
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(color, in: Capsule())
    }

    @ViewBuilder private var buttons: some View {
        let phase = store.liveClock.phase
        if let f = store.following {
            FollowerControls(game: f)
        } else if phase == .ready {
            bigButton("Kick off", systemImage: "play.fill") { store.startGame() }
        } else if r.halfOver {
            if r.half == 0 {
                bigButton("Start 2nd half", systemImage: "play.fill") { store.startSecondHalf() }
            } else {
                Button { store.resetClock() } label: {
                    Label("New game", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
        } else if phase == .running {
            Button { store.pauseClock() } label: {
                Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).controlSize(.large)
        } else {
            bigButton("Resume", systemImage: "play.fill") { store.resumeClock() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                badge
            }
            // Everyone is off the field at kickoff, so show the lineup, not changes.
            if period % s.perHalf == 0 {
                lineupGrid(period)
            } else {
                changeRows
            }
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

    private func lineupGrid(_ p: Int) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(s.lineup(at: p), id: \.pos) { item in
                HStack(spacing: 8) {
                    chip(item.pos)
                    Text(name(item.player)).font(.subheadline.weight(.medium)).lineLimit(1)
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

// MARK: - Sharing

/// Host: shown under the clock while broadcasting.
private struct BroadcastStrip: View {
    @Environment(LineupStore.self) private var store

    var body: some View {
        let names = store.followers.map(\.coachName)
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative)
            Text(names.isEmpty ? "Broadcasting to nearby coaches" : "\(names.count) following: \(names.joined(separator: ", "))")
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.blue)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Follower: in place of the clock buttons. Only the host can run the clock.
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
