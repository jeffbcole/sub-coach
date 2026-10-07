<img src="iOS/SubCoach/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="96" alt="Sub Coach icon" align="left">

# Sub Coach: Soccer Lineups

Soccer substitutions & game timer for youth coaches, on iPhone and iPad.

<br clear="left">

Sub Coach plans fair rotations for youth soccer and runs them on game day. It tells you when it's time to sub and exactly who goes in and out, on the lock screen as well as in the app.

## Features

- **Auto-fill rotations:** even playing time, with each player's bench time grouped together instead of constant in-and-out. Respects the positions each player can play, a goalkeeper per half, playing-time preferences, and who's at today's game.
- **Game Day:** a game clock, a card for every substitution, alerts at each sub, and a lock screen and Dynamic Island countdown (Live Activity).
- **Any team size:** 4 to 11 players on the field, with formations for each size, any half length, and 1 to 6 sub periods per half.
- **Saved lineups:** keep a lineup for each game, with a shared team roster.
- **Coach-to-coach sharing:** share your roster, or broadcast a live game, to coaches standing nearby over Bluetooth. Followers get the same alerts even with their phones locked.
- **Print:** a one-page landscape lineup for the sideline.

No accounts, no servers, no ads, no tracking. See the [privacy policy](https://jeffbcole.github.io/sub-coach/privacy.html).

## Building

Requires Xcode 27 or later; the app runs on iOS 17 and later.

1. Open `iOS/SubCoach.xcodeproj`.
2. For both the **SubCoach** and **LineupWidget** targets, set **Signing & Capabilities → Team** to your own team.
3. Change the bundle identifier (`com.gamesbypost.subcoach`) to your own, and the widget's to the same followed by `.widget`.
4. Run on a device or simulator. Bluetooth sharing needs real devices; the simulator has no Bluetooth.

More detail, including a map of the source files, is in [iOS/README.md](iOS/README.md).

## Project layout

| Path | What it is |
| --- | --- |
| `iOS/` | The SwiftUI app, the lock screen widget extension, and code shared between them |
| `docs/` | The website (GitHub Pages): home, support and privacy pages |
| `AppStore/` | App Store listing notes and the script that draws the icon |
| `soccer-lineup-planner.html` | The original single-page web version the app grew out of |

## Contributing

Bug reports and ideas are welcome in [Issues](https://github.com/jeffbcole/sub-coach/issues). Pull requests are welcome too.

## License

The code is available under the [MIT License](LICENSE).

The **Sub Coach** name and app icon identify the official app. If you publish your own build, please give it a different name and icon.
