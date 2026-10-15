import SwiftUI
import UserNotifications

@main
struct SubCoachApp: App {
    @State private var store = LineupStore()
    @Environment(\.scenePhase) private var scenePhase
    private static let notificationDelegate = NotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = Self.notificationDelegate
    }

    var body: some Scene {
        WindowGroup {
            RootView()
            .environment(store)
            .tint(Theme.accent)
            // Text stays at the standard size whatever the phone's text size setting:
            // the grid and Game Day are laid out for it.
            .dynamicTypeSize(.large)
            .background(StandardTextSize())
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Listens for nearby coaches while open; catches the countdown up when back from the lock screen.
                store.setAppActive(phase == .active)
            }
        }
    }
}

/// Holds the whole window (navigation bars, alerts, menus and sheets too) at the standard
/// text size, which `.dynamicTypeSize` alone doesn't reach.
private struct StandardTextSize: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { WindowTraits() }
    func updateUIView(_ view: UIView, context: Context) {}

    private final class WindowTraits: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            window?.traitOverrides.preferredContentSizeCategory = .large
        }
    }
}
