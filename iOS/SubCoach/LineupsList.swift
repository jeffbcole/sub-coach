import SwiftUI

/// The saved lineups: tap one to open it. Used in the phone shelf and the iPad sidebar.
struct LineupsList: View {
    @Environment(LineupStore.self) private var store
    /// Called after a lineup is opened (the phone shelf closes itself).
    var onOpen: () -> Void = {}

    @State private var naming: Naming?
    @State private var nameText = ""
    @State private var deleting: SavedLineup?

    var body: some View {
        // Only broadcasts not already in the coach's lineups; saved ones are marked live on their row.
        let live = store.liveBroadcasts.values
            .filter { b in !b.offer.ended && !store.team.lineups.contains { $0.broadcast?.matches(b) == true } }
            .sorted { $0.hostName < $1.hostName }
        List {
            if !live.isEmpty {
                Section("Live nearby") {
                    ForEach(live, id: \.offer.session) { b in liveRow(b) }
                }
            }
            Section {
                lineupRows
            } header: {
                if !live.isEmpty { Text("Lineups") }
            }
        }
        .navigationTitle("Lineups")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { nameText = ""; naming = .new } label: { Label("New lineup", systemImage: "plus") }
            }
        }
        .lineupNameAlert($naming, text: $nameText) { kind, name in
            switch kind {
            case .new: store.newLineup(named: name); onOpen()
            case .rename(let id): store.renameLineup(id, to: name)
            }
        }
        .confirmDelete($deleting)
    }

    private var lineupRows: some View {
        ForEach(store.sortedLineups) { l in
            Button {
                store.selectLineup(l.id)
                onOpen()
            } label: {
                row(l)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button { deleting = l } label: { Label("Delete", systemImage: "trash") }
                    .tint(.red)
                Button { store.duplicateLineup(l.id); onOpen() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .tint(.blue)
            }
            .contextMenu {
                Button { startRename(l) } label: { Label("Rename", systemImage: "pencil") }
                Button { store.duplicateLineup(l.id); onOpen() } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                Button(role: .destructive) { deleting = l } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }

    /// A game another coach is broadcasting nearby: follow it (or get back to it if already following).
    private func liveRow(_ b: LiveBroadcast) -> some View {
        let isFollowed = store.following?.offer.session == b.offer.session
        return HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.blue)
                .symbolEffect(.variableColor.iterative)
            VStack(alignment: .leading, spacing: 3) {
                Text(b.offer.lineup.displayName).font(.headline)
                Text("\(b.hostName) is broadcasting").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(isFollowed ? "Open" : "Follow") {
                if isFollowed { store.presentGameDay = true } else { store.follow(b) }
                onOpen()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func startRename(_ l: SavedLineup) {
        nameText = l.name
        naming = .rename(l.id)
    }

    private func row(_ l: SavedLineup) -> some View {
        let isOpen = l.id == store.team.currentID
        let inGame = l.id == store.gameLineupID
        let here = store.team.roster.count - l.absent.filter { id in store.team.roster.contains { $0.id == id } }.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text("\(here) players · edited \(l.updated.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let link = l.broadcast {
                    let live = store.liveBroadcast(for: l) != nil
                    HStack(spacing: 4) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text(live ? "\(link.hostName)'s broadcast · live" : "From \(link.hostName)'s broadcast")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(live ? Color.blue : Color.secondary)
                }
                if inGame {
                    HStack(spacing: 4) {
                        Image(systemName: "stopwatch")
                        Text("Game in progress")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            if isOpen {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityLabel("Open")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

enum Naming: Identifiable, Equatable {
    case new
    case rename(String)
    var id: String { if case .rename(let id) = self { return id } else { return "new" } }
}

extension View {
    /// "New lineup" / "Rename lineup" alert with a name field.
    func lineupNameAlert(_ naming: Binding<Naming?>, text: Binding<String>, onSave: @escaping (Naming, String) -> Void) -> some View {
        let isNew = naming.wrappedValue == .new
        return alert(isNew ? "New lineup" : "Rename lineup",
                     isPresented: Binding(get: { naming.wrappedValue != nil }, set: { if !$0 { naming.wrappedValue = nil } })) {
            TextField("e.g. vs. Tigers, Sat 10/10", text: text)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button(isNew ? "Create" : "Save") {
                if let kind = naming.wrappedValue {
                    onSave(kind, text.wrappedValue.trimmingCharacters(in: .whitespaces))
                }
            }
        } message: {
            if isNew { Text("Starts empty, with the same half length and periods as the lineup you have open.") }
        }
    }

    /// Ask before deleting a saved lineup.
    func confirmDelete(_ lineup: Binding<SavedLineup?>) -> some View {
        modifier(ConfirmDeleteLineup(lineup: lineup))
    }
}

private struct ConfirmDeleteLineup: ViewModifier {
    @Environment(LineupStore.self) private var store
    @Binding var lineup: SavedLineup?

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Delete \u{201C}\(lineup?.displayName ?? "")\u{201D}?",
            isPresented: Binding(get: { lineup != nil }, set: { if !$0 { lineup = nil } }),
            titleVisibility: .visible,
            presenting: lineup
        ) { l in
            Button("Delete lineup", role: .destructive) { store.deleteLineup(l.id) }
        } message: { l in
            Text(l.id == store.gameLineupID
                 ? "This lineup's game is in progress; deleting it also stops the game clock. Your roster isn't affected."
                 : "This can't be undone. Your roster isn't affected.")
        }
    }
}
