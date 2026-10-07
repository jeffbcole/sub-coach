import SwiftUI

/// Shown before auto-fill: tick off who is at today's game.
struct AttendanceSheet: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var absent: Set<String> = []

    var body: some View {
        let players = store.state.players
        let here = players.filter { !absent.contains($0.id) }
        NavigationStack {
            List {
                Section {
                    ForEach(Array(players.enumerated()), id: \.element.id) { idx, pl in
                        let isHere = !absent.contains(pl.id)
                        Button {
                            if isHere { absent.insert(pl.id) } else { absent.remove(pl.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isHere ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(isHere ? Theme.accent : Color.secondary)
                                Text(pl.name.isEmpty ? "Player \(idx + 1)" : pl.name)
                                    .foregroundStyle(isHere ? Color.primary : Color.secondary)
                                Spacer()
                                if !isHere {
                                    Text("Not here").font(.subheadline).foregroundStyle(.secondary)
                                } else if !pl.can.contains(true) {
                                    Text("No positions on").font(.subheadline).foregroundStyle(Theme.warn)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isHere ? .isSelected : [])
                    }
                } header: {
                    Text("Who's at the game?")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(here.count) of \(players.count) here. Auto-fill splits the time among the girls who are here.")
                        if here.count < store.state.positionCount {
                            Text("That's fewer than \(store.state.positionCount), so some spots will be empty.")
                                .foregroundStyle(Theme.warn)
                        }
                    }
                }
            }
            .navigationTitle("Auto-fill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("All here") { absent.removeAll() }
                        .disabled(absent.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    let out = absent
                    store.update { s in
                        for i in s.players.indices { s.players[i].absent = out.contains(s.players[i].id) }
                    }
                    store.autofill()
                    dismiss()
                } label: {
                    Label("Build lineup with \(here.count) players", systemImage: "wand.and.stars")
                        .font(.headline)
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(here.isEmpty)
                .padding()
                .background(.bar)
            }
            .onAppear { absent = Set(players.filter(\.absent).map(\.id)) }
        }
    }
}
