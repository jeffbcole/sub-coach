import SwiftUI

/// "Make a sub" during the game: pick who's coming off, then who's going in. Several subs can
/// be queued before confirming; the rest of the game is then re-planned around them.
struct MakeSubSheet: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var swaps: [Swap] = []
    /// Players coming off for the rest of the game.
    @State private var out: Set<String> = []
    @State private var path: [Choice]

    /// `start`: go straight to picking who goes in for that player (tapped on the field).
    init(start: Choice? = nil) {
        _path = State(initialValue: start.map { [$0] } ?? [])
    }

    struct Swap: Identifiable, Equatable {
        let off: String, on: String, pos: Int
        var id: String { off + on }
    }
    struct Choice: Hashable, Identifiable {
        let off: String, pos: Int
        var id: Self { self }
    }

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                if let m = store.subMoment(at: ctx.date) {
                    picker(m)
                } else {
                    ContentUnavailableView("The game is over", systemImage: "flag.checkered",
                                           description: Text("Subs can be made until full time."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeButton }
            .navigationDestination(for: Choice.self) { c in
                if let m = store.subMoment() {
                    IncomingList(choice: c, moment: m, onField: Set(field(m).values),
                                 queuedOn: Set(swaps.map(\.on)), isOut: out.contains(c.off)) { on, isOut in
                        swaps.append(Swap(off: c.off, on: on, pos: c.pos))
                        if isOut { out.insert(c.off) } else { out.remove(c.off) }
                        path.removeAll()
                    }
                    .toolbar { closeButton }
                }
            }
        }
    }

    /// Top right on every step: closes the sheet without making any of the subs.
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Close")
        }
    }

    /// Who's on the field, with the queued subs already made: position -> player id.
    private func field(_ m: LineupStore.SubMoment) -> [Int: String] {
        var byPos = Dictionary(store.field(at: m).map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        for sw in swaps { byPos[sw.pos] = sw.on }
        return byPos
    }

    private func picker(_ m: LineupStore.SubMoment) -> some View {
        let s = store.liveState
        let soFar = s.secondsSoFar(m)
        let isKickoff: Bool = if case .kickoff = m { true } else { false }
        return List {
            if !swaps.isEmpty {
                Section("Subs to make") {
                    ForEach(swaps) { sw in
                        HStack(spacing: 8) {
                            PositionChip(s: s, pos: sw.pos)
                            Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                            Text(s.name(sw.on)).fontWeight(.semibold)
                            Image(systemName: "arrow.down.circle.fill").foregroundStyle(.red).padding(.leading, 4)
                            Text(s.name(sw.off)).foregroundStyle(.secondary)
                            if out.contains(sw.off) {
                                Text("out").font(.caption.weight(.semibold)).foregroundStyle(Theme.warn)
                            }
                        }
                    }
                    .onDelete { rows in
                        for i in rows { out.remove(swaps[i].off) }
                        swaps.remove(atOffsets: rows)
                    }
                }
            }
            Section {
                ForEach(field(m).sorted { $0.key < $1.key }, id: \.key) { pos, id in
                    NavigationLink(value: Choice(off: id, pos: pos)) {
                        HStack(spacing: 10) {
                            PositionChip(s: s, pos: pos)
                            Text(s.name(id))
                            Spacer()
                            Text(Self.minutes(soFar[id])).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                }
            } header: {
                Text(swaps.isEmpty ? "Who's coming off?" : "Another sub? Who's coming off?")
            } footer: {
                if isKickoff { Text("Changes the lineup for kickoff, then re-plans the rest of the game.") }
            }
        }
        .navigationTitle(isKickoff ? "Change lineup" : "Make a sub")
        .safeAreaInset(edge: .bottom) {
            if !swaps.isEmpty { confirmButton(m) }
        }
    }

    private func confirmButton(_ m: LineupStore.SubMoment) -> some View {
            Button {
                store.game(.subs(swaps: swaps.map { .init(off: $0.off, on: $0.on) }, out: Array(out)))
                dismiss()
            } label: {
                Group {
                    if case .live(_, let at) = m {
                        Text("Sub now at \(Game.clock(seconds: Int(at)))").monospacedDigit()
                    } else {
                        Text(swaps.count > 1 ? "Make these changes" : "Make this change")
                    }
                }
                .font(.headline)
                .foregroundStyle(Theme.accentText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
    }

    static func minutes(_ seconds: TimeInterval?) -> String {
        "\(Int(((seconds ?? 0) / 60).rounded())) min"
    }
}

/// Second step: who goes in for the girl coming off.
private struct IncomingList: View {
    @Environment(LineupStore.self) private var store
    let choice: MakeSubSheet.Choice
    let moment: LineupStore.SubMoment
    let onField: Set<String>
    let queuedOn: Set<String>
    @State var isOut: Bool
    let pick: (String, Bool) -> Void

    var body: some View {
        let s = store.liveState
        let soFar = s.secondsSoFar(moment)
        // Girls who can play the spot first, least time played first; anyone out at the end.
        let bench = s.players
            .filter { !$0.absent && !onField.contains($0.id) && !queuedOn.contains($0.id) && $0.id != choice.off }
            .sorted { a, b in
                let ra = a.out ? 2 : a.canPlay(choice.pos) ? 0 : 1, rb = b.out ? 2 : b.canPlay(choice.pos) ? 0 : 1
                if ra != rb { return ra < rb }
                return (soFar[a.id] ?? 0) < (soFar[b.id] ?? 0)
            }
        let suggested = bench.first { !$0.out && $0.canPlay(choice.pos) }?.id
        let posName = s.positionName(choice.pos)
        List {
            Section {
                Picker("Coming off", selection: $isOut) {
                    Text("Resting").tag(false)
                    Text("Out for the game").tag(true)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("\(s.name(choice.off)) is")
            } footer: {
                Text(isOut ? "She won't be planned back in. Pick her as a sub later to bring her back."
                           : "She can be planned back in later.")
            }
            Section("Who's going in at \(posName)?") {
                ForEach(bench) { pl in
                    Button { pick(pl.id, isOut) } label: {
                        HStack(spacing: 8) {
                            Text(s.name(pl.id))
                                .fontWeight(pl.id == suggested ? .semibold : .regular)
                                .foregroundStyle(pl.out || !pl.canPlay(choice.pos) ? .secondary : .primary)
                            ForEach(lines(pl, s), id: \.self) { g in LineChip(group: g) }
                            Spacer()
                            if pl.id == suggested {
                                Text("Suggested").font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
                            } else if pl.out {
                                Text("Out").font(.caption.weight(.bold)).foregroundStyle(Theme.warn)
                            } else if !pl.canPlay(choice.pos) {
                                Text("Doesn't play \(posName)").font(.caption).foregroundStyle(.secondary)
                            }
                            Text(MakeSubSheet.minutes(soFar[pl.id])).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("In for \(s.name(choice.off))")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The lines she plays (0 keeper, 1 defense, 2 midfield, 3 forward).
    private func lines(_ pl: Player, _ s: LineupState) -> [Int] {
        Array(Set((0..<s.positionCount).filter { pl.canPlay($0) }.map(s.group))).sorted()
    }
}

struct PositionChip: View {
    let s: LineupState
    let pos: Int

    var body: some View {
        Text(s.positionName(pos))
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .frame(minWidth: 34)
            .padding(.horizontal, 5).padding(.vertical, 3)
            .foregroundStyle(Theme.foreground(group: s.group(pos)))
            .background(Theme.background(group: s.group(pos)), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A small letter for a line of the field she plays: GK, D, M or F.
private struct LineChip: View {
    let group: Int

    var body: some View {
        Text(["GK", "D", "M", "F"][min(group, 3)])
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .foregroundStyle(Theme.foreground(group: group))
            .background(Theme.background(group: group), in: RoundedRectangle(cornerRadius: 4))
    }
}

extension LineupState {
    func name(_ id: String) -> String {
        let n = players.first { $0.id == id }?.name ?? ""
        return n.isEmpty ? "Unnamed" : n
    }

    func secondsSoFar(_ m: LineupStore.SubMoment) -> [String: TimeInterval] {
        switch m {
        case .kickoff(let p): secondsSoFar(period: p, at: nil)
        case .live(let p, let at): secondsSoFar(period: p, at: at)
        }
    }
}
