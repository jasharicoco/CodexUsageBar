# Codex Usage Bar

A small native macOS app that shows your remaining weekly Codex usage in the menu bar.

![Codex Usage Bar showing the remaining weekly usage](Screenshots/codex-usage-bar.png)

It automatically uses the ChatGPT account already signed in to Codex on your Mac. No separate login or API key is needed.

The interface follows your Mac's preferred language: Swedish when the primary language is Swedish, otherwise English.

Available earned resets and their expiration are shown in the app and can be used after confirmation.

> Independent open-source project. Not affiliated with or endorsed by OpenAI.

## Appearance and refresh

The rounded popup stays attached to the menu bar and uses the same 320-point
width in **Classic** and **Monster**. Classic uses the native macOS menu material
and system accent color, following light/dark mode and accessibility settings.
macOS draws the popup's outer corners; no custom corner radius is applied.
Monster adds a dark plum background and an animated character. Both share the same
header, usage summary, reset controls, and compact footer. Hover over icons for
labels and the last usage refresh time.

Use the palette menu to switch between **Classic** and **Monster**. The choice is
saved between launches. Switching themes adjusts the height while keeping the
popup's top anchored to the menu bar.

The monster reacts to remaining weekly usage:

- **50–100%:** happy, green, and bouncing.
- **20–49%:** peckish and gently moving.
- **1–19%:** pink-orange, sweating and rubbing its hands for more tokens.
- **0%:** purple and asleep.

Animations respect macOS Reduce Motion. Usage is fetched at startup and refreshes
automatically every **60 seconds in both Classic and Monster**. Switching themes
does not change or restart the refresh timer. Manual refresh remains available,
and reset credits require confirmation before use.

## Install

1. Download the latest universal ZIP from [Releases](../../releases/latest).
2. Unzip it and move `CodexUsageBar.app` to **Applications**.
3. Open the app from **Applications**. If macOS blocks an ad-hoc signed build,
   open **System Settings → Privacy & Security**, find the app under **Security**,
   and choose **Open Anyway** after attempting to launch it.

Requires macOS 13 or later and Codex Desktop or Codex CLI. If needed, sign in first with:

```sh
codex login
```

## App updates

The app checks this repository's latest stable GitHub release at startup and every
**six hours**, independently of the one-minute usage refresh. The footer normally
shows only the installed version. When a newer release is available, a small
download symbol appears beside it. Click that symbol to download, verify,
install, and restart the app. A spinner replaces the symbol during installation;
if installation fails, a dialog offers a retry or a link to the release.

Right-click the version number to check manually, turn automatic checks off, or
open GitHub releases. Background checks stay quiet. Updates are installed only
when you click the download symbol.

The first version with this feature must be installed manually. Older versions
cannot discover updates. The app must be in a writable location, normally
Applications; otherwise the error dialog links to the release for manual installation.

Updates use the release's universal ZIP and matching SHA-256 file, both downloaded
over HTTPS from this repository. The app checks the archive, bundle identity,
version, macOS compatibility, architecture, and code signature before replacing
itself. Developer ID builds also require the same signing team. For ad-hoc builds,
the source of trust is this GitHub repository over HTTPS; the checksum detects
corruption and is not an independent publisher signature. The old app is retained
until macOS accepts the new app's launch and restored if launch fails.

To publish an update, run **Actions → Release → Run workflow** on `main` with a
new `major.minor.patch` version (without `v`), or push its `v`-prefixed tag. Keep
published versions immutable and always include both generated release assets.
Merging a pull request runs CI; it does not publish a release.

## Build from source

```sh
swift run ParserChecks
swift run UpdateChecks
./Scripts/build-app.sh
swift run UpdateChecks --app dist/CodexUsageBar.app
open dist/CodexUsageBar.app
```

## License

The source code is available under the [MIT License](LICENSE).

- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

The OpenAI logo is owned by OpenAI and is not covered by the MIT License.
