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
            .onChange(of: scenePhase, initial: true) { _, phase in
                // Listens for nearby coaches while open; catches the countdown up when back from the lock screen.
                store.setAppActive(phase == .active)
            }
        }
    }
}
