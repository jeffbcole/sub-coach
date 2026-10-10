import SwiftUI

struct LineupView: View {
    @Environment(LineupStore.self) private var store
    /// Opens the saved-lineups shelf (phone). On iPad the sidebar has its own button.
    var onShowLineups: (() -> Void)? = nil

    @State private var showAttendance = false
    @State private var showRoster = false
    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var gridWidth: CGFloat = 0
    @State private var openSide: Edge.Set = []

    private let nameWidth: CGFloat = 112
    /// Period columns stretch to fit every period on screen when there's room (landscape,
    /// iPad); otherwise they keep the usual width and the grid scrolls sideways.
    private let usualCellWidth: CGFloat = 64, minCellWidth: CGFloat = 52, maxCellWidth: CGFloat = 88
    private let rowHeight: CGFloat = 48
    private let halfRowHeight: CGFloat = 26
    private let periodRowHeight: CGFloat = 40
    private let footHeight: CGFloat = 64

    var body: some View {
        let s = store.state
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { autofillButton(s); gameButton }
                    VStack(spacing: 10) { gameButton; autofillButton(s) }
                }

                if s.players.isEmpty {
                    ContentUnavailableView {
                        Label("No players yet", systemImage: "person.3")
                    } description: {
                        Text("Add your team in the roster.")
                    } actions: {
                        Button("Open roster") { showRoster = true }
                    }
                } else {
                    grid(s)
                    summary(s)
                }

                GameSetupSection()
                    .padding(.top, 12)

                Button { PrintSheet.present(s) } label: {
                    Label("Print lineup", systemImage: "printer")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .padding(.top, 8)
            }
            .padding()
        }
        // In landscape the phone keeps an empty margin on the side away from the camera
        // just to match the camera side. Use it for the lineup.
        .ignoresSafeArea(.container, edges: openSide)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in openSide = Self.sideAwayFromCamera() }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onShowLineups {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onShowLineups) { Image(systemName: "sidebar.left") }
                        .accessibilityLabel("Saved lineups")
                }
            }
            ToolbarItem(placement: .principal) {
                Button { startRename() } label: {
                    HStack(spacing: 4) {
                        Text(store.currentLineup?.displayName ?? "Lineup")
                            .font(.headline).lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.primary)
                }
                .accessibilityHint("Rename this lineup")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showRoster = true } label: { Image(systemName: "person.2") }
                    .accessibilityLabel("Roster")
            }
        }
        .sheet(isPresented: $showAttendance) { AttendanceSheet() }
        .sheet(isPresented: $showRoster) { RosterView() }
        .fullScreenCover(isPresented: Bindable(store).presentGameDay) { GameDayView() }
        .lineupNameAlert($naming, text: $nameText) { _, name in
            if let id = store.currentLineup?.id { store.renameLineup(id, to: name) }
        }
    }

    /// The side away from the camera cutout when a phone with one is in landscape.
    private static func sideAwayFromCamera() -> Edge.Set {
        guard UIDevice.current.userInterfaceIdiom == .phone,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first,
              window.safeAreaInsets.left > 0, window.safeAreaInsets.right > 0 else { return [] }
        switch scene.effectiveGeometry.interfaceOrientation {
        case .landscapeRight: return .trailing // camera on the left
        case .landscapeLeft: return .leading   // camera on the right
        default: return []
        }
    }

    private func columnWidth(_ s: LineupState) -> CGFloat {
        let fit = (gridWidth - nameWidth - 8) / CGFloat(max(s.periods, 1))
        return fit >= minCellWidth ? min(fit, maxCellWidth) : usualCellWidth
    }

    private func startRename() {
        guard let l = store.currentLineup else { return }
        nameText = l.name
        naming = .rename(l.id)
    }

    private func autofillButton(_ s: LineupState) -> some View {
        Button {
            showAttendance = true
        } label: {
            HStack(spacing: 8) {
                if store.isAutoFilling { ProgressView() } else { Image(systemName: "wand.and.stars") }
                Text("Auto-fill").lineLimit(1)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(s.players.isEmpty || store.isAutoFilling)
    }

    /// Start game, or get back to the game in progress.
    private var gameButton: some View {
        let gameID = store.gameLineupID
        let otherGame = gameID.flatMap { id in id == store.team.currentID ? nil : store.team.lineup(id) }
        // "Following" only on the followed game's own lineup; other lineups work as usual.
        let followed = store.isFollowedLineup(store.currentLineup) ? store.following : nil
        // This lineup came from a broadcast that's live nearby: offer to follow it (again).
        let live = followed == nil ? store.liveBroadcast(for: store.currentLineup) : nil
        return Button {
            if let live { store.follow(live); return }
            // Running your own game means no longer following someone else's.
            if followed == nil, store.isFollowing { store.stopFollowing() }
            if followed == nil, let otherGame { store.selectLineup(otherGame.id) }
            store.presentGameDay = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: followed != nil || live != nil ? "antenna.radiowaves.left.and.right" : gameID == nil ? "play.fill" : "stopwatch")
                if let followed {
                    Text("Following \(followed.hostName)").lineLimit(1)
                } else if let live {
                    Text("Follow \(live.hostName)").lineLimit(1)
                } else if let otherGame {
                    Text("Game on: \(otherGame.displayName)").lineLimit(1)
                } else if gameID != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let r = store.clock.reading(at: ctx.date, store.gameState)
                        Text(r.halfOver ? "Resume game" : "Resume · \(Game.clock(seconds: Int(r.elapsed)))")
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                } else {
                    Text("Start game").lineLimit(1)
                }
            }
            .font(.headline)
            .foregroundStyle(Theme.accentText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(followed != nil || live != nil ? .blue : gameID == nil ? Theme.accent : .orange)
    }

    // MARK: Summary

    @ViewBuilder private func summary(_ s: LineupState) -> some View {
        let counts = s.players.filter(\.isAvailable).map(\.periodsPlayed)
        let off = s.players.reduce(0) { n, p in n + p.cells.filter { c in c.map { !p.can[$0] } ?? false }.count }
        VStack(alignment: .leading, spacing: 4) {
            if let lo = counts.min(), let hi = counts.max() {
                if lo == hi {
                    Text("Everyone plays **\(lo) of \(s.periods) periods** (about \(s.minutes(lo)) minutes).")
                } else {
                    Text("Playing time ranges from **\(lo) to \(hi) periods** (about \(s.minutes(lo)) to \(s.minutes(hi)) minutes).")
                }
            }
            let away = s.players.filter(\.absent)
            if !away.isEmpty {
                Text("Not here today: \(away.map { $0.name.isEmpty ? "Unnamed" : $0.name }.joined(separator: ", ")).")
            }
            let stillIn = away.filter { $0.periodsPlayed > 0 }
            if !stillIn.isEmpty {
                Text("\(stillIn.map { $0.name.isEmpty ? "Unnamed" : $0.name }.joined(separator: " and ")) \(stillIn.count == 1 ? "is" : "are") marked not here but still in the lineup. Run auto-fill again.")
                    .foregroundStyle(Theme.warn)
            }
            if off > 0 {
                Text("\(off) \(off == 1 ? "cell has" : "cells have") a girl in a position that is turned off for her (outlined in red).")
                    .foregroundStyle(Theme.warn)
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: Grid

    private func grid(_ s: LineupState) -> some View {
        // counts[period][position] = how many girls are in that spot
        var counts = Array(repeating: Array(repeating: 0, count: s.positionCount), count: s.periods)
        for pl in s.players { for (p, c) in pl.cells.enumerated() { if let c { counts[p][c] += 1 } } }
        let cellWidth = columnWidth(s)

        return HStack(alignment: .top, spacing: 0) {
            // Sticky name column
            VStack(alignment: .leading, spacing: 0) {
                Text("Player")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    .frame(height: halfRowHeight + periodRowHeight, alignment: .bottom)
                    .padding(.bottom, 8)
                    .frame(height: halfRowHeight + periodRowHeight)
                Divider()
                ForEach(Array(s.players.enumerated()), id: \.element.id) { idx, pl in
                    nameCell(pl, index: idx, s: s)
                    Divider()
                }
                Text("Lineup check")
                    .font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                    .frame(height: footHeight)
            }
            .padding(.leading, 12)
            .frame(width: nameWidth, alignment: .leading)
            .overlay(alignment: .trailing) { Rectangle().fill(Color(.separator)).frame(width: 1) }

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        halfHeader("First half", width: cellWidth * CGFloat(s.perHalf))
                        halfHeader("Second half", width: cellWidth * CGFloat(s.perHalf)).overlay(alignment: .leading) { halfLine }
                    }
                    .frame(height: halfRowHeight)
                    HStack(spacing: 0) {
                        ForEach(0..<s.periods, id: \.self) { p in
                            VStack(spacing: 1) {
                                Text("Period \(p + 1)").font(.caption.weight(.semibold))
                                Text("from \(s.startAt(p % s.perHalf))").font(.caption2).foregroundStyle(.secondary)
                            }
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .frame(width: cellWidth, height: periodRowHeight)
                            .overlay(alignment: .leading) { if p == s.perHalf { halfLine } }
                        }
                    }
                    Divider()
                    ForEach(s.players) { pl in
                        HStack(spacing: 0) {
                            ForEach(0..<s.periods, id: \.self) { p in
                                PositionCell(player: pl, period: p, counts: counts[p])
                                    .frame(width: cellWidth, height: rowHeight)
                                    .overlay(alignment: .leading) { if p == s.perHalf { halfLine } }
                            }
                        }
                        Divider()
                    }
                    HStack(spacing: 0) {
                        ForEach(0..<s.periods, id: \.self) { p in
                            check(counts[p], s: s)
                                .frame(width: cellWidth, height: footHeight, alignment: .top)
                                .overlay(alignment: .leading) { if p == s.perHalf { halfLine } }
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
        // The grid has fixed column widths, so cap text size here or headers get cut off.
        .dynamicTypeSize(...DynamicTypeSize.large)
    }

    private var halfLine: some View { Rectangle().fill(Color(.separator)).frame(width: 2) }

    private func halfHeader(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.subheadline.weight(.bold)).textCase(.uppercase)
            .frame(width: width)
            .padding(.top, 6)
    }

    private func nameCell(_ pl: Player, index: Int, s: LineupState) -> some View {
        let n = pl.periodsPlayed
        return VStack(alignment: .leading, spacing: 3) {
            Text(pl.name.isEmpty ? "Player \(index + 1)" : pl.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(pl.name.isEmpty ? .secondary : .primary)
                .lineLimit(1)
            HStack(spacing: 2) {
                ForEach(0..<s.periods, id: \.self) { p in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(pl.cell(p) != nil ? Theme.accent : Theme.benchBG)
                        .frame(width: s.periods > 6 ? 4 : 7, height: 4)
                        .padding(.leading, p == s.perHalf ? 3 : 0)
                }
                Text(pl.absent ? "away" : pl.isAvailable ? "\(s.minutes(n))m" : "out")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .frame(height: rowHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pl.name), \(n) of \(s.periods) periods, \(s.minutes(n)) minutes")
    }

    @ViewBuilder private func check(_ c: [Int], s: LineupState) -> some View {
        let need = (0..<s.positionCount).filter { c[$0] == 0 }.map { s.positionName($0) }
        let dup = (0..<s.positionCount).filter { c[$0] > 1 }.map { "\(c[$0])× \(s.positionName($0))" }
        if need.isEmpty && dup.isEmpty {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).padding(.top, 10)
        } else if c.reduce(0, +) == 0 {
            Text("Empty").font(.caption2).foregroundStyle(.secondary).padding(.top, 8)
        } else {
            Text(((need.isEmpty ? [] : ["Need " + need.joined(separator: ", ")]) + dup).joined(separator: "\n"))
                .font(.caption2).foregroundStyle(Theme.warn)
                .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(0.8)
                .padding(.top, 6).padding(.horizontal, 2)
        }
    }
}

/// One player's spot in one period. Tap to choose a position.
struct PositionCell: View {
    @Environment(LineupStore.self) private var store
    let player: Player
    let period: Int
    let counts: [Int]

    var body: some View {
        let s = store.state
        let c = player.cell(period)
        let dup = c.map { counts.indices.contains($0) && counts[$0] > 1 } ?? false
        let off = c.map { !player.canPlay($0) } ?? false
        Menu {
            Picker("Position", selection: Binding(
                get: { player.cell(period) },
                set: { v in store.updatePlayer(player.id) { if $0.cells.indices.contains(period) { $0.cells[period] = v } } })
            ) {
                Text("Bench").tag(Int?.none)
                ForEach(0..<s.positionCount, id: \.self) { i in
                    Text(optionLabel(i, s)).tag(Int?.some(i))
                }
            }
        } label: {
            Text(c.map { s.positionName($0) } ?? "–")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Theme.foreground(group: c.map(s.group)))
                .background(Theme.background(group: c.map(s.group)), in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if dup || off { RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.warn, lineWidth: 2) }
                }
                .padding(4)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("\(player.name), period \(period + 1)")
        .accessibilityValue(c.map { s.positionName($0) } ?? "Bench")
    }

    /// e.g. "LD", "LD · Ava" when someone else is already there, "GK (off for her)".
    private func optionLabel(_ i: Int, _ s: LineupState) -> String {
        var t = s.positionName(i)
        let others = s.players.filter { $0.id != player.id && $0.cell(period) == i }.map { $0.name.isEmpty ? "?" : $0.name }
        if !others.isEmpty { t += " · " + others.joined(separator: ", ") }
        if !player.canPlay(i) { t += " (off for her)" }
        return t
    }
}
