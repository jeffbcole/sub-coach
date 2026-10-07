import SwiftUI

/// The Lineup screen, with saved lineups in a slide-out shelf (phone) or a sidebar (iPad).
struct RootView: View {
    @Environment(LineupStore.self) private var store
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var shelfOpen = false
    @State private var sidebar = NavigationSplitViewVisibility.all

    var body: some View {
        layout
            .alert("Accept \(store.pendingRoster?.hostName ?? "")'s roster?",
                   isPresented: Binding(get: { store.pendingRoster != nil }, set: { if !$0 { store.declineRoster() } })) {
                Button("Not now", role: .cancel) { store.declineRoster() }
                Button("Accept") { store.acceptRoster() }
            } message: {
                Text("\(store.pendingRoster?.offer.players.count ?? 0) players with their positions. This replaces your roster; your saved lineups stay.")
            }
            .alert("Follow \(store.pendingGame?.hostName ?? "")'s game?",
                   isPresented: Binding(get: { store.pendingGame != nil && store.pendingRoster == nil },
                                        set: { if !$0 && store.pendingGame != nil { store.declineGame() } })) {
                Button("Not now", role: .cancel) { store.declineGame() }
                Button("Follow") { store.acceptGame() }
            } message: {
                Text("\(store.pendingGame?.offer.lineup.displayName ?? ""). You'll get the sub alerts and lock screen countdown on this phone.")
            }
    }

    @ViewBuilder private var layout: some View {
        if sizeClass == .regular {
            NavigationSplitView(columnVisibility: $sidebar) {
                LineupsList()
            } detail: {
                NavigationStack { LineupView() }
            }
        } else {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    NavigationStack {
                        LineupView(onShowLineups: { setShelf(true) })
                    }
                    if shelfOpen {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { setShelf(false) }
                            .transition(.opacity)
                            .accessibilityLabel("Close lineups")
                            .accessibilityAddTraits(.isButton)
                        NavigationStack {
                            LineupsList(onOpen: { setShelf(false) })
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button { setShelf(false) } label: { Image(systemName: "xmark") }
                                            .accessibilityLabel("Close")
                                    }
                                }
                        }
                        .frame(width: min(340, geo.size.width * 0.85))
                        .shadow(color: .black.opacity(0.25), radius: 16)
                        .transition(.move(edge: .leading))
                        .gesture(DragGesture().onEnded { v in
                            if v.translation.width < -60 { setShelf(false) }
                        })
                        .zIndex(1)
                    }
                }
            }
        }
    }

    private func setShelf(_ open: Bool) {
        withAnimation(.snappy(duration: 0.28)) { shelfOpen = open }
    }
}
