# Haneoka

The Haneoka app for Android, iOS, Windows, macOS and Linux. It reads your BanG Dream! Our Notes save straight from the game's own files — no game login, no account password — and shows everything the save holds: cards, character and friendship ranks, band items, items and currencies, every song's high scores and clears per difficulty, the high score rating, events, gacha points, stories read, missions, season and monthly passes, costumes, titles, stamps, skins, memories, live boost and the game's settings.

From there you can copy your cards straight into the [team builder](https://haneoka.org/en/team-builder/) or save the whole save as a JSON file. The file never includes your display name, account IDs, passwords, invitation codes, linked accounts or purchase receipts.

## Getting the save

| Platform | How | What you need |
| --- | --- | --- |
| Android 11 and later | **This phone · Shizuku** | [Shizuku](https://shizuku.rikka.app/) running (wireless debugging, no computer, no root) |
| Android 8 to 12 | **This phone · game folder** | One tap in the system folder picker, which opens on the game's folder |
| Windows, macOS, Linux | **Android phone · USB or Wi-Fi** | [Platform tools](https://developer.android.com/tools/releases/platform-tools) (`adb`) and USB or wireless debugging on the phone |
| Windows, macOS, Linux | **iPhone or iPad backup** | A local backup from Finder (macOS), Apple Devices or iTunes (Windows), or `idevicebackup2` (Linux); its password if it is encrypted |
| Everywhere | **Files or folder** | The account folder copied off the phone, single save files, or a ZIP of them |

The game stores its saves in `Android/data/<package>/files/<account>/` on Android and in the app's `Documents` on iOS. Since Android 11 only the shell user can read `Android/data`; Shizuku and `adb` both read as that user. An iPhone does not let one app read another's files, so on iOS the save comes from a backup made on a computer, or from files you already have.

Supported releases: Global (`com.bilibili.sirius.official`, `com.bilibili.sirius`) and Japan (`com.bushiroad.sirius`), with the same names on iOS.

### macOS

The app reads `~/Library/Application Support/MobileSync/Backup`, which macOS protects: give the app Full Disk Access in System Settings › Privacy & Security, or choose the backup folder yourself.

### Linux and iPhone

```sh
idevicebackup2 backup ~/iphone-backup
```

Then choose that folder under **iPhone or iPad backup**.

## The save format

[docs/SAVE_FORMAT.md](docs/SAVE_FORMAT.md) describes the files, the cipher and every field.

## Building

Flutter 3.47 or later.

```sh
flutter test
flutter build linux      # or windows, macos, apk, ios
```

Android builds need the NDK version Flutter names in `android/app/build.gradle.kts`.

## Licence

[MPL-2.0](LICENSE)
