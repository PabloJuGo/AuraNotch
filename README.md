<div align="center">

<img src="Docs/images/icon.png" width="112" alt="Aura Notch icon">

# Aura Notch

**Turn the MacBook notch into a useful, quiet panel.**
Now-playing controls, a temporary file shelf, your next events, a timer, volume, battery and clipboard history, one hover away.

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [简体中文](README.zh-CN.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue)
![Status beta](https://img.shields.io/badge/status-beta-yellow)

<img src="Docs/images/closed.png" width="420" alt="Collapsed notch while music plays">

</div>

Aura Notch is a native macOS app written in Swift (SwiftUI + AppKit) with no third-party dependencies. It sits in the notch, stays out of the way, and opens into a panel when you point at it. Everything runs locally: no account, no analytics, no telemetry.

<div align="center">
<img src="Docs/images/home.png" width="720" alt="Home panel with now playing, today, clipboard and shelf">
</div>

## Features

- **Collapsed notch with live activity.** An animated equalizer and the track title appear beside the notch while something plays, a timer shows its countdown, and short alerts (upcoming meeting, charger connected, timer finished) slide in. The collapsed shape has a fixed, symmetric width, so it never grows with the song title and covers as little of your menu bar as possible.
- **Home.** Today's date and battery, now playing with cover and transport controls, today's events, recent clipboard items and your shelf, in one glance.
- **Media.** Music and Spotify: title, artist, progress and seeking, play/pause/next/previous in macOS style. Swipe two fingers over the collapsed notch to skip tracks. Spotify cover art is optional and is the only thing the app ever downloads.
- **Shelf.** Drag files or links toward the notch and it opens to catch them. The shelf stores references, never moves or deletes your originals. Open, reveal in Finder, copy the path, share or send by AirDrop, and drag items back out. Persistence across sessions is opt-in.
- **Calendar.** Your next events, read-only, using EventKit with explicit permission.
- **Widgets.** Timer, volume, battery, date and quick actions, laid out on a tidy two-column grid.
- **Clipboard history (opt-in).** Text, links and images, kept in memory only. It ignores items marked as concealed or transient (such as password managers) and is off until you enable it.
- **Themes and languages.** Pick an accent color and the size of the collapsed notch. The interface is available in English, Spanish, French, German, Brazilian Portuguese and Simplified Chinese.
- **Good citizen.** Non-activating panel that never steals focus, global shortcut (`⌃⌥N`), menu bar icon, launch at login, honours *Reduce Motion*, hides over full-screen apps (configurable), and idles at about 0% CPU.
- **Works without a notch.** On Macs and displays without a notch it becomes a small floating pill at the top center of the screen.

<div align="center">
<img src="Docs/images/media.png" width="360" alt="Media panel"> <img src="Docs/images/clipboard.png" width="360" alt="Clipboard panel">
</div>

## Install

1. Download `AuraNotch.zip` from the [latest release](https://github.com/PabloJuGo/AuraNotch/releases/latest) and unzip it.
2. Drag **AuraNotch.app** to your Applications folder.
3. The first time, **right-click the app and choose Open**, then confirm. The app is ad-hoc signed but not notarized (notarization needs a paid Apple developer account), so macOS asks you to approve it once. If macOS still refuses, run:
   ```sh
   xattr -dr com.apple.quarantine /Applications/AuraNotch.app
   ```
4. Look for the notch strip at the top of the screen (and the icon in the menu bar). Hover or click it, or press `⌃⌥N`.

**Requirements:** macOS 14 or later. It was developed and tested on a notched MacBook running macOS 27; other setups should work but have had less testing.

## Settings

Open **Settings** from the gear in the panel header or the menu bar icon.

| Section | What you can change |
|---|---|
| General | Launch at login, display mode, **interface language**, accent color, collapsed notch size |
| Interaction | Open on hover, on click or with the global shortcut; hover delay; full-screen behavior; title in the collapsed notch; swipe to skip; alerts |
| Animations | Motion (follow the system, reduced or none) |
| Modules | Enable, disable and reorder Home, Media, Shelf, Calendar, Widgets and Clipboard |
| Privacy | Keep the shelf between sessions, history limit, Spotify cover art, erase all data |

Changing the language takes effect after a restart; the app offers a **Restart Now** button.

## Privacy and permissions

- No account, no analytics, no telemetry, no update checks.
- **Network:** the only request is the Spotify cover image, from the address Spotify itself exposes. You can turn it off in Settings → Privacy.
- **Permissions are requested only when you use the feature that needs them:** *Automation* to control Music and Spotify (seeing what plays needs no permission), and *Calendars* to list your events (read-only).
- The shelf keeps references to your files, the clipboard history lives in memory only, and **Settings → Privacy → Erase all data** wipes everything.

More detail in [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) (both in Spanish for now).

## Build from source

You only need the Swift 6 toolchain (the Xcode Command Line Tools are enough).

```sh
git clone https://github.com/PabloJuGo/AuraNotch.git
cd AuraNotch
swift build
swift run AuraSelfTests            # test suite with detailed failures
swift run AuraNotch                # run without packaging (no Calendar/Automation prompts)
Scripts/package-app.sh             # builds dist/AuraNotch.app (release, ad-hoc signed)
```

Useful flags: `--skip-onboarding`, `--start-module=<home|media|shelf|calendar|widgets|clipboard>`.

Architecture notes live in [ARCHITECTURE.md](ARCHITECTURE.md), design decisions in [Docs/decisions](Docs/decisions) (Spanish).

## Status and known limitations

Aura Notch is a **beta**. Things worth knowing:

- Not notarized (see Install). There is no auto-update.
- The Calendar and AirDrop flows rely on system permissions and dialogs and have had limited testing on real hardware.
- External displays, multiple displays and VoiceOver have had little hands-on testing.
- Spotify's Automation permission prompt can be slow to appear on recent macOS versions; macOS then asks the first time you press a control.
- Translations other than English and Spanish were produced with machine assistance and have not been reviewed by native speakers. Corrections are very welcome.
- Some project documents (architecture notes, decisions, privacy) are still in Spanish.

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md). To fix or add a translation, edit `Resources/<language>.lproj/Localizable.strings` and run `Scripts/check-localizations.py`.

## License

[GPL-3.0](LICENSE). Aura Notch is an independent project and is not affiliated with Apple, Spotify or any other app mentioned here.
