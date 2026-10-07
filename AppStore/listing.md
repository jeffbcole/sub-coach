# App Store listing — Sub Coach

| Field | Value | Limit |
|---|---|---|
| App name | Sub Coach: Soccer Lineups | 25 / 30 |
| Subtitle | Soccer substitutions & timer | 28 / 30 |
| Home screen name | Sub Coach | |
| Bundle ID | com.gamesbypost.subcoach (widget: com.gamesbypost.subcoach.widget) | (not shown to users) |

Icon: done (AppStore/make-icon.swift draws it; standard, dark and tinted).

Privacy policy URL: https://cribbageclassic.com/sub-coach/privacy.html
Support URL: https://cribbageclassic.com/sub-coach/support.html
Marketing URL: https://cribbageclassic.com/sub-coach/

Description: AppStore/description.txt (1,557 / 4,000)
Promotional text: AppStore/promotional-text.txt (128 / 170; can be changed any time without an app update)
Keywords: AppStore/keywords.txt (95 / 100)

Screenshots: AppStore/screenshots/iphone (6, 1320x2868, for 6.9" iPhone) and AppStore/screenshots/ipad (5, 2064x2752, for 13" iPad).
Raw captures in *-raw; re-frame with: swift AppStore/make-screenshots.swift <raw dir> <out dir>

## Store settings

| Setting | Answer |
|---|---|
| Primary category | Sports |
| Secondary category | Productivity |
| Age rating | 4+ (answer "None" / "No" to every questionnaire item) |
| Kids category | Not in Kids category |
| Price | (to decide) |
| App Privacy | Data Not Collected |
| Encryption | No non-exempt encryption (set in Info.plist, so uploads skip the question) |
| Copyright | 2026 Games By Post LLC |

## Notes for App Review

> Sub Coach is a lineup and substitution planner for youth soccer coaches. No account or sign-in is needed; tap "Start game" then "Kick off" to see the game clock and substitution alerts.
>
> Bluetooth (bluetooth-central and bluetooth-peripheral background modes) is used only for coach-to-coach sharing: a coach can share their roster or broadcast a live game to other coaches standing nearby. The background modes keep a coach who is following a game up to date with the lock screen countdown and substitution alerts while their phone is locked in their pocket during the game. Nothing is sent to any server. Testing it needs two devices running the app: on one, open the roster (top right) and tap the broadcast icon, or start a game and tap the broadcast icon in Game Day; the other device is asked to accept.

Still to do: create the app in App Store Connect, upload a build, submit.
