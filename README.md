# Haneoka

The native Haneoka app for Android, iOS, Windows, macOS and Linux: catalogue,
stories, community, tools and a local save reader, following
[haneoka.org](https://haneoka.org/).
3D chart/story players and the deferred interactive editor/model viewers are
outside the current implementation round.

## Download and installation

Published downloads are on the [releases page](https://github.com/haneoka-gakuen/haneoka-app/releases).
The release workflow now builds these targets; a configured target is not a
claim that its installer has already been published or verified on a device.

| Platform | Architectures | Release formats |
| --- | --- | --- |
| Android 8+ | ARM32, ARM64, x86-64 | universal APK, APK per ABI, AAB |
| Windows 10+ | x64, ARM64 | EXE installer, MSI installer, portable ZIP, MSIX |
| macOS 12+ | Intel x64 and Apple Silicon ARM64 | separate ZIP, DMG, PKG for each architecture |
| Linux with glibc | x64, ARM64 | DEB, RPM, Arch package, AppImage, Snap, Flatpak, tar.gz |
| iOS 15+ | ARM64 iPhone/iPad | standard unsigned IPA; separate TrollStore TIPA |

Linux x64 builds use Ubuntu 22.04; ARM64 builds use Ubuntu 24.04. Packages
require GTK 3, libsecret and MPV; AppImage/Snap/Flatpak include the deployed
media libraries. Unsupported desktop CPU/OS combinations are listed in
[Flutter's deployment matrix](https://docs.flutter.dev/reference/supported-platforms).

The workflow also generates SHA256SUMS, an AltStore source, Scoop/WinGet
manifests and a Homebrew cask from the actual artifact hashes. Store/repository
publication (Microsoft Store, WinGet's public repository, Homebrew, AUR,
Flathub, Snap Store, App Store and Google Play) requires separate publisher
accounts or reviewed submissions. macOS notarization and Windows trusted
signing require the appropriate certificates; EXE/MSI installers are unsigned
unless that release has been signed separately. MSIX uses a configured stable
certificate; without it CI labels the output `-unsigned.msix`, which must be
signed before installation. With the fixed self-signed certificate, first install the accompanying `.cer`
into Local Computer → Trusted People, then open the MSIX. The public
certificate is also in `packaging/windows-signing.cer`; the private key is
held in release secrets. The accompanying `.appinstaller` supports installation
and update checks through Windows App Installer. Windows packages include
the matching Visual C++ runtime. The portable ZIP runs after
extraction and requires no installer. Android tagged releases
require the configured signing key so future APKs can update existing installs.

### iOS installation and direct import

Four named sideloading routes are prepared:

| Method | File | Installation |
| --- | --- | --- |
| [AltStore Classic](https://altstore.io/) | standard IPA | Add the Haneoka source, or import the IPA in My Apps |
| [SideStore](https://sidestore.io/) | standard IPA | Add the same source, or import the IPA |
| [Sideloadly](https://sideloadly.io/) | standard IPA | Select the device and IPA on Windows/macOS, then sign and install |
| [TrollStore](https://github.com/opa334/TrollStore) | privileged TIPA | Install on a compatible device with TrollStore already set up |

After 0.1.0 is published, the stable AltStore Classic / SideStore source URL is:

```text
https://github.com/haneoka-gakuen/haneoka-app/releases/latest/download/altstore-source.json
```

Add it through the installer's Sources screen. Settings also provides a copy
button and links to the four tools. The source reads the version, build number,
minimum iOS version, bundle ID and permissions from the actual standard IPA.
AltStore PAL is a separate notarized marketplace route and is not configured.
Physical-device installation and refresh still need verification.
 Standard iOS installations
import through Files/Share or an exported archive/backup.

The separate `haneoka-ios-trollstore.tipa` enables existing unsandboxed
container access. On a compatible [TrollStore](https://github.com/opa334/TrollStore)
installation, **Import from this device → Read save** locates the matching
Our Notes containers and reads their Documents. The app does not install an
exploit, jailbreak the device or modify game files. Normal iOS signing does
not grant this access. The current Flutter build needs iOS 15+, so the app's
supported versions are the intersection with the tool's supported versions.
This path still requires physical-device verification.

## Your save

The app reads your BanG Dream! Our Notes save straight from the game's own files — no game login, no account password — and shows everything the save holds: cards, character and friendship ranks, band items, items and currencies, every song's high scores and clears per difficulty, the high score rating, events, gacha points, stories read, missions, season and monthly passes, costumes, titles, stamps, skins, memories, live boost and the game's settings.

From there you can copy your cards straight into the [team builder](https://haneoka.org/en/team-builder/) or save the whole save as a JSON file. The file never includes your display name, account IDs, passwords, invitation codes, linked accounts or purchase receipts.

## Getting the save

| Platform | How | What you need |
| --- | --- | --- |
| Android 11 and later | **This phone · Shizuku** | [Shizuku](https://shizuku.rikka.app/) running (wireless debugging, no computer, no root) |
| Android 8 to 12 | **This phone · game folder** | One tap in the system folder picker, which opens on the game's folder |
| Windows, macOS, Linux | **Android phone · USB or Wi-Fi** | ADB is included in desktop distributions; enable USB or wireless debugging and authorize the computer |
| Windows, macOS, Linux | **iPhone or iPad backup** | A local backup from Finder (macOS), Apple Devices or iTunes (Windows), or `idevicebackup2` (Linux); its password if it is encrypted |
| Everywhere | **Files or folder** | The account folder copied off the phone, single save files, a ZIP of them, or an iMazing app export (`.imazingapp`) |

Desktop: **Read connected device** imports immediately when one authorized
phone is connected. **Choose device / wireless pairing** handles multiple
phones, USB authorization and Wi-Fi pairing. The app uses bundled ADB first,
then PATH/SDK/custom ADB as a fallback. Windows may need an
[OEM USB driver](https://developer.android.com/studio/run/oem-usb).

The game stores its saves in `Android/data/<package>/files/<account>/` on Android and in the app's `Documents` on iOS. Since Android 11 only the shell user can read `Android/data`; Shizuku and `adb` both read as that user. Standard iOS installations use Files/shared archives or an exported backup.
The separate privileged installation can directly read an already-accessible
Our Notes container; the import page detects access and offers the appropriate
workflow. [iMazing](https://imazing.com/download),
[Shizuku](https://shizuku.rikka.app/download/) and advanced export tools are
linked with platform-specific instructions on that page.

Supported releases: Global (`com.bilibili.sirius.official`, `com.bilibili.sirius`) and Japan (`com.bushiroad.sirius`), with the same names on iOS.

### macOS

The app reads `~/Library/Application Support/MobileSync/Backup`, which macOS protects: give the app Full Disk Access in System Settings › Privacy & Security, or choose the backup folder yourself.

### Linux and iPhone

```sh
idevicebackup2 backup ~/iphone-backup
```

Then choose that folder under **iPhone or iPad backup**.

## Cache and storage

Settings shows catalogue data, disk images, memory images, imported saves,
settings and temporary files separately. Disk cache size defaults to unlimited.
Manual limits start at 1 GB, with oldest-cache eviction when a finite limit is
selected. Clear data/images/temporary files independently or together.
Imported saves, sign-in and preferences remain intact; temporary-file clearing
is blocked during an active import. Image memory caching remains bounded.

## The save format

[docs/SAVE_FORMAT.md](docs/SAVE_FORMAT.md) describes the files, the cipher and every field.

## Building

Flutter 3.47 or later.

```sh
flutter analyze
flutter build linux      # or windows, macos, apk, ios
python3 scripts/bundle_adb.py --platform linux --arch x64 --dest build/linux/x64/release/bundle/tools/adb
python3 scripts/package_linux.py --bundle build/linux/x64/release/bundle --version 0.1.0 --arch x64 --formats tar,deb,arch
```

Android builds need the NDK version Flutter names in `android/app/build.gradle.kts`.

## Licence

[MPL-2.0](LICENSE)
