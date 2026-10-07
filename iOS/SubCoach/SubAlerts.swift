import UserNotifications

/// Phone notifications at each sub time, so the alert comes even with the phone locked.
enum SubAlerts {
    /// Asks once; calls back on the main thread if alerts are allowed.
    static func requestPermission(then granted: @escaping @MainActor () -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            if ok { Task { @MainActor in granted() } }
        }
    }

    /// Replace any scheduled alerts with ones for the rest of the current half.
    static func reschedule(_ s: LineupState, _ clock: GameClock, now: Date = .now) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard clock.phase == .running else { return }
        let el = clock.elapsed(at: now, halfSeconds: s.halfSeconds)
        func add(_ id: String, at t: TimeInterval, title: String, body: String) {
            guard t - el > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: t - el, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        for j in 1..<max(s.perHalf, 1) {
            let p = clock.half * s.perHalf + j
            if s.changes(at: p).isEmpty { continue } // nothing to call
            add("sub-\(p)", at: Double(j) * s.periodSeconds, title: "Sub time · Period \(p + 1)", body: s.changeSummary(at: p))
        }
        if clock.half == 0 {
            add("half", at: s.halfSeconds, title: "Half time", body: "2nd half lineup: " + s.lineupSummary(at: s.perHalf))
        } else {
            add("full", at: s.halfSeconds, title: "Full time", body: "That's the game.")
        }
    }
}

/// Shows the alerts (with sound) even while the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
