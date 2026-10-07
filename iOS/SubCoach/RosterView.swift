import SwiftUI

struct RosterView: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: String?
    /// Which formation's positions the chips show. Starts on the open lineup's; changing it here
    /// doesn't change the lineup.
    @State private var formationID: String?
    @State private var sharing = false

    /// Falls back to the lineup's formation if the one picked here is for a different team size.
    private var formation: Formation {
        if let id = formationID, Formation.named(id).size == store.state.positionCount { return Formation.named(id) }
        return Formation.named(store.state.formation)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Picker("Formation", selection: Binding(
                            get: { formation.id },
                            set: { formationID = $0 })
                        ) {
                            ForEach(Formation.options(size: store.state.positionCount)) { f in Text(f.name).tag(f.id) }
                        }
                        .pickerStyle(.menu)
                    }

                    Section {
                        ForEach(Array(store.state.players.enumerated()), id: \.element.id) { idx, pl in
                            row(pl, index: idx).id(pl.id)
                                .swipeActions(edge: .leading) {
                                    Button {
                                        store.updatePlayer(pl.id) { $0.absent.toggle() }
                                    } label: {
                                        Label(pl.absent ? "Here" : "Not here", systemImage: pl.absent ? "person.fill.checkmark" : "person.fill.xmark")
                                    }
                                    .tint(pl.absent ? Theme.accent : .orange)
                                }
                        }
                        .onDelete { offsets in store.update { $0.players.remove(atOffsets: offsets) } }
                        .onMove { from, to in store.update { $0.players.move(fromOffsets: from, toOffset: to) } }
                    } footer: {
                        Text("Tap a position to turn it on or off for that player. Auto-fill only puts a girl in positions that are turned on. Turn on \(store.state.positionName(0)) for your two goalies. Swipe right on a player to mark her not here for \u{201C}\(store.currentLineup?.displayName ?? "this lineup")\u{201D} (auto-fill also asks who's here). Swipe left to remove her from the team.")
                    }
                }
                .navigationTitle("Roster")
                .sheet(isPresented: $sharing) { ShareRosterSheet() }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button { sharing = true } label: {
                            Label("Share", systemImage: "antenna.radiowaves.left.and.right")
                        }
                        .disabled(store.team.roster.isEmpty)
                    }
                    ToolbarItemGroup(placement: .topBarLeading) {
                        EditButton()
                        Button {
                            let id = store.addPlayer()
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                            focused = id
                        } label: {
                            Label("Add player", systemImage: "plus")
                        }
                    }
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") { focused = nil }
                    }
                }
            }
        }
    }

    private func row(_ pl: Player, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Player \(index + 1)", text: Binding(
                    get: { pl.name },
                    set: { v in store.updatePlayer(pl.id, undoable: false) { $0.name = v } })
                )
                .font(.headline)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focused, equals: pl.id)

                if pl.absent {
                    Button {
                        store.updatePlayer(pl.id) { $0.absent = false }
                    } label: {
                        Text("Not here")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Marks her as here")
                }

                Menu {
                    Picker("Playing time", selection: Binding(
                        get: { pl.weight },
                        set: { v in store.updatePlayer(pl.id) { $0.weight = v } })
                    ) {
                        ForEach(Game.weights, id: \.value) { w in Text(w.label).tag(w.value) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                        Text(Game.weights.first { $0.value == pl.weight }?.label ?? "Normal")
                    }
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                }
                .accessibilityLabel("Playing time")
            }
            // Up to 7 chips per row; bigger formations wrap to a second row.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: min(7, formation.roles.count)), spacing: 5) {
                ForEach(formation.roles, id: \.self) { role in
                    chip(pl, role)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(pl.isAvailable ? 1 : 0.6)
    }

    private func chip(_ pl: Player, _ role: Role) -> some View {
        let on = store.canPlay(pl.id, role)
        let g = role.group
        return Button {
            store.setCanPlay(pl.id, role, !on)
        } label: {
            Text(role.name)
                .font(.footnote.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 32)
                .foregroundStyle(on ? Theme.foreground(group: g) : Color.secondary)
                .background(on ? Theme.background(group: g) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    if !on {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("\(pl.name.isEmpty ? "Player" : pl.name) can play \(role.name)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
