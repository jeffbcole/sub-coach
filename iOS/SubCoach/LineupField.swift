import SwiftUI

/// In the Game Day header: who's on the field right now, laid out in the formation, with the
/// bench underneath. Tapping a player starts a sub for her spot.
struct LineupField: View {
    let s: LineupState
    let r: GameClock.Reading
    /// Nil when subs can't be made from here (following another coach, or after full time).
    let onTap: ((_ pos: Int, _ id: String) -> Void)?

    var body: some View {
        let byPos = s.onField(r)
        let bench = s.players.filter { !$0.absent && !byPos.values.contains($0.id) }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(title).fontWeight(.semibold)
                if onTap != nil {
                    Text(" · Tap a player to sub").foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text(s.formation).foregroundStyle(.secondary)
            }
            .font(.caption)
            .lineLimit(1)
            Pitch(s: s, byPos: byPos, onTap: onTap)
            if !bench.isEmpty {
                benchLine(bench)
            }
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if !r.started { return "Starting lineup" }
        if r.halfOver { return r.half == 0 ? "2nd half lineup" : "At full time" }
        return "On the field"
    }

    private func benchLine(_ bench: [Player]) -> some View {
        let names = bench.map { pl in
            Text(s.name(pl.id)) + (pl.out ? Text(" (out)").foregroundStyle(Theme.warn) : Text(""))
        }
        let list = names.dropFirst().reduce(names[0]) { $0 + Text(" · ") + $1 }
        return (Text("Bench  ").fontWeight(.bold).foregroundStyle(.secondary) + list)
            .font(.caption)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The field, our goal at the bottom, with a marker for each spot in the formation.
private struct Pitch: View {
    let s: LineupState
    let byPos: [Int: String]
    let onTap: ((_ pos: Int, _ id: String) -> Void)?

    static let grass = Color(light: 0x4C9F5F, dark: 0x1F4A2B)
    static let line = Color.white.opacity(0.5)
    static let rowHeight: CGFloat = 56

    var body: some View {
        // Lines of the field, forwards at the top and the keeper at the bottom.
        let lines = Array(Set((0..<s.positionCount).map(s.group))).sorted(by: >)
        GeometryReader { g in
            let w = g.size.width
            ZStack {
                markings
                ForEach(Array(lines.enumerated()), id: \.element) { row, line in
                    // Positions are listed left to right within each line.
                    let spots = (0..<s.positionCount).filter { s.group($0) == line }
                    let slot = w / CGFloat(spots.count)
                    ForEach(Array(spots.enumerated()), id: \.element) { i, pos in
                        marker(pos)
                            .frame(maxWidth: min(slot - 6, 160))
                            .position(x: slot * (CGFloat(i) + 0.5), y: Self.rowHeight * (CGFloat(row) + 0.5))
                    }
                }
            }
        }
        .frame(height: Self.rowHeight * CGFloat(lines.count))
        .padding(.vertical, 2)
        .background(Self.grass, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func marker(_ pos: Int) -> some View {
        let id = byPos[pos]
        // Colored by line, like the position chips and the lineup grid.
        let fg = Theme.foreground(group: s.group(pos))
        let label = VStack(spacing: 0) {
            Text(s.positionName(pos))
                .font(.system(size: 11, weight: .bold))
                .opacity(0.75)
            Text(id.map(s.name) ?? "Empty")
                .font(.title3.weight(.bold))
                .opacity(id == nil ? 0.5 : 1)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .frame(minWidth: 60)
        .background(Theme.background(group: s.group(pos)), in: RoundedRectangle(cornerRadius: 7))
        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
        if let id, let onTap {
            Button { onTap(pos, id) } label: { label }
                .buttonStyle(.plain)
                .accessibilityLabel("\(s.positionName(pos)), \(s.name(id))")
                .accessibilityHint("Make a sub")
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }

    private var markings: some View {
        Canvas { ctx, size in
            let field = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 3)
            var p = Path()
            p.addRect(field)
            p.move(to: CGPoint(x: field.minX, y: field.midY))
            p.addLine(to: CGPoint(x: field.maxX, y: field.midY))
            let r = field.height * 0.16
            p.addEllipse(in: CGRect(x: field.midX - r, y: field.midY - r, width: r * 2, height: r * 2))
            for top in [true, false] {
                for (bw, bh) in [(0.5, 0.13), (0.24, 0.05)] {
                    let bw = field.width * bw, bh = field.height * bh
                    p.addRect(CGRect(x: field.midX - bw / 2, y: top ? field.minY : field.maxY - bh, width: bw, height: bh))
                }
            }
            ctx.stroke(p, with: .color(Self.line), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

extension LineupState {
    /// Who's on the field at this point in the game: position -> player id. Before kickoff
    /// and at half time, the lineup for the coming kickoff.
    func onField(_ r: GameClock.Reading) -> [Int: String] {
        func lineupAt(_ p: Int) -> [Int: String] {
            Dictionary(lineup(at: p).map { ($0.pos, $0.player.id) }, uniquingKeysWith: { a, _ in a })
        }
        if !r.started { return lineupAt(0) }
        if r.halfOver && r.half == 0 { return lineupAt(perHalf) }
        let p = r.halfOver ? periods - 1 : (r.period ?? 0)
        return Dictionary(positions(atEndOf: p).map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
    }
}
