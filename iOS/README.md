# Sub Coach: Soccer Lineups (iOS)

Sub Coach — youth soccer lineup, substitution planner and game timer for coaches. iPhone and iPad, iOS 17+.

## Run it on your iPhone

1. Open `SubCoach.xcodeproj` in Xcode.
2. Select the **SubCoach** target → **Signing & Capabilities** → choose your Apple ID under **Team**
   (Xcode → Settings → Accounts to add one; a free account works).
   Do the same for the **LineupWidget** target (the lock screen countdown).
   If Xcode says the bundle ID is taken, change `com.gamesbypost.subcoach` to something unique,
   and the widget's to the same thing followed by `.widget`.
3. Plug in your phone (or pick it from the device list over Wi‑Fi) and press **Run** (⌘R).
4. First time only, on the phone: Settings → General → VPN & Device Management → trust your developer certificate.
   You may also need Settings → Privacy & Security → Developer Mode → On.

With a free account the app stops opening after 7 days; just Run it again from Xcode.
A paid Apple Developer account ($99/yr) lasts a year and allows TestFlight.

## Files

| File | What it does |
| --- | --- |
| `Model.swift` | Player / game data, starter roster, period math |
| `AutoFill.swift` | The rotation builder: fair time, bench time grouped together, position variety |
| `Formation.swift` | Field positions and formations for 4 to 11 players on the field |
| `Team.swift` | Saved data: the team roster plus every saved lineup |
| `LineupStore.swift` | Saving to the device, undo, saved lineups, game clock |
| `RootView.swift` | Main layout: Lineup screen with the lineups shelf (iPhone) or sidebar (iPad) |
| `LineupsList.swift` | Saved lineups: open, new, rename, duplicate, delete |
| `LineupView.swift` | Lineup screen: top bar, Start game, grid |
| `GameDayView.swift` | Game Day (full screen): game clock and the subs to call each period |
| `Substitutions.swift` | Works out who goes in / off / moves each period; the game clock |
| `SubAlerts.swift` | Phone notifications at each sub time |
| `RosterView.swift` | Roster sheet: names, positions each girl can play (per formation), playing time |
| `GameSetupSection.swift` | Goalkeepers, players on the field, half length, periods, formation (bottom of the Lineup screen) |
| `PrintSheet.swift` | One-page landscape printout / PDF |
| `AttendanceSheet.swift` | "Who's at the game?" check-list shown before auto-fill |
| `LiveGame.swift` | Starts and updates the lock screen / Dynamic Island countdown |
| `../Shared/GameActivityAttributes.swift` | What the countdown shows (shared by the app and widget) |
| `../LineupWidget/GameLiveActivity.swift` | The lock screen and Dynamic Island layouts |
