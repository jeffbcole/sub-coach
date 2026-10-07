import SwiftUI

/// Goalkeepers and game format, at the bottom of the Lineup screen (they shape auto-fill).
struct GameSetupSection: View {
    @Environment(LineupStore.self) private var store

    var body: some View {
        let s = store.state
        VStack(alignment: .leading, spacing: 22) {
            group("Goalkeepers") {
                row("First half") { keeperPicker("First half", \.gk1) }
                Divider().padding(.leading, 16)
                row("Second half") { keeperPicker("Second half", \.gk2) }
            }
            group("Game format") {
                row("Players on the field") {
                    Picker("Players on the field", selection: Binding(
                        get: { store.state.positionCount },
                        set: { store.setFieldSize($0) })
                    ) {
                        ForEach(Formation.fieldSizes, id: \.self) { n in
                            Text("\(n) (incl. keeper)").tag(n)
                        }
                    }
                }
                Divider().padding(.leading, 16)
                row("Half length") {
                    Picker("Half length", selection: Binding(
                        get: { store.state.halfMinutes },
                        set: { m in store.update { $0.halfMinutes = m } })
                    ) {
                        // Keep an unusual saved length selectable too.
                        ForEach(Array(Set(Game.halfLengthChoices + [s.halfMinutes])).sorted(), id: \.self) { m in
                            Text("\(m) minutes").tag(m)
                        }
                    }
                }
                Divider().padding(.leading, 16)
                row("Periods per half") {
                    Picker("Periods per half", selection: Binding(
                        get: { store.state.perHalf },
                        set: { n in store.update { $0.setPerHalf(n) } })
                    ) {
                        ForEach(1...6, id: \.self) { n in
                            Text("\(n) (\(Game.clock(seconds: Int((s.halfSeconds / Double(n)).rounded()))) each)").tag(n)
                        }
                    }
                }
            }
            group("Formation") {
                row("Formation") {
                    Picker("Formation", selection: Binding(
                        get: { store.state.formation },
                        set: { store.setFormation($0) })
                    ) {
                        ForEach(Formation.options(size: s.positionCount)) { f in
                            Text(f.name).tag(f.id)
                        }
                    }
                }
                Divider().padding(.leading, 16)
                FormationDiagram(formation: Formation.named(s.formation))
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Looks like an inset grouped list section, so it sits naturally under the grid.
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.footnote).textCase(.uppercase).foregroundStyle(.secondary)
                .padding(.leading, 16)
            VStack(spacing: 0) { content() }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// A picker row: label on the left, current choice on the right.
    /// With large text the label and choice may not fit side by side; then the choice goes underneath.
    private func row<P: View>(_ label: String, @ViewBuilder picker: () -> P) -> some View {
        let choice = picker().pickerStyle(.menu).labelsHidden().fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack {
                Text(label).fixedSize()
                Spacer(minLength: 12)
                choice
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                choice.padding(.leading, -10) // line the choice's text up with the label
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(minHeight: 44)
    }

    private func keeperPicker(_ label: String, _ key: WritableKeyPath<LineupState, String>) -> some View {
        Picker(label, selection: Binding(
            get: { store.state[keyPath: key] },
            set: { v in store.update { $0[keyPath: key] = v } })
        ) {
            Text("Auto").tag("")
            ForEach(store.state.keeperChoices) { p in
                Text(p.name.isEmpty ? "Unnamed" : p.name).tag(p.id)
            }
        }
    }
}

/// A small picture of the formation: one row per line, forwards at the top.
struct FormationDiagram: View {
    let formation: Formation

    var body: some View {
        VStack(spacing: 10) {
            ForEach([3, 2, 1, 0], id: \.self) { g in
                HStack(spacing: 10) {
                    ForEach(formation.roles.filter { $0.group == g }, id: \.self) { r in
                        Text(r.name)
                            .font(.caption.weight(.bold))
                            .frame(width: 40, height: 26)
                            .foregroundStyle(Theme.foreground(group: g))
                            .background(Theme.background(group: g), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Formation \(formation.name): \(formation.summary)")
    }
}
