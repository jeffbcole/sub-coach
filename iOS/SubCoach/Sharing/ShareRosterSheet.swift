import SwiftUI

/// Host: shares the roster with every nearby coach for as long as this is open.
struct ShareRosterSheet: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = Coach.name

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .symbolEffect(.variableColor.iterative, isActive: store.sharingRoster != nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.sharingRoster == nil ? "Enter your name to share" : "Sharing \(store.team.roster.count) players")
                                .font(.headline)
                            Text("Coaches nearby with Sub Coach open get asked to accept it.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Your name") {
                    TextField("e.g. Coach Jeff", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit(start)
                        .disabled(store.sharingRoster != nil)
                    if store.sharingRoster == nil {
                        Button("Start sharing", action: start)
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                Section("Coaches") {
                    let replies = store.rosterShareReplies
                    if replies.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for coaches nearby…").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(replies, id: \.coachID) { r in
                        HStack {
                            Text(r.coachName)
                            Spacer()
                            status(r.status)
                        }
                    }
                }
            }
            .navigationTitle("Share roster")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: start)
            .onDisappear { store.stopSharingRoster() }
        }
    }

    private func start() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, store.sharingRoster == nil else { return }
        Coach.name = name
        store.startSharingRoster()
    }

    @ViewBuilder private func status(_ s: ShareReply.Status) -> some View {
        switch s {
        case .accepted: Label("Accepted", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent)
        case .declined: Label("Declined", systemImage: "xmark.circle").foregroundStyle(.secondary)
        default: Label("Asked", systemImage: "ellipsis.circle").foregroundStyle(.secondary)
        }
    }
}
