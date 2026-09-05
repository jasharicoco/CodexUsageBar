# Codex Usage Bar

A small native macOS app that shows your remaining weekly Codex usage in the menu bar.

![Codex Usage Bar showing the remaining weekly usage](Screenshots/codex-usage-bar.png)

It automatically uses the ChatGPT account already signed in to Codex on your Mac. No separate login or API key is needed.

The interface follows your Mac's preferred language: Swedish when the primary language is Swedish, otherwise English.

Available earned resets and their expiration are shown in the app and can be used after confirmation.

> Independent open-source project. Not affiliated with or endorsed by OpenAI.

## Appearance and refresh

The menu bar panel includes a compact **Monster** theme with a dark plum
background, colorful character, and icon-only controls. Hover over controls for
labels. **Classic** retains the original panel layout, labels, colors, and controls.
Use the palette menu in either theme to switch between **Classic** and **Monster**.
The choice is saved between launches.

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
3. Open the app. If macOS blocks it, right-click it and select **Open**.

Requires macOS 13 or later and Codex Desktop or Codex CLI. If needed, sign in first with:

```sh
codex login
```

## App updates

The app checks this repository's latest stable GitHub release at startup and every
**six hours**, independently of the one-minute usage refresh. An **↑** in the menu
bar and an update row in both themes indicate a
new version. Choose **Update and restart** to download, verify, install, and reopen
the app. You can also check manually or turn automatic checks off in the update
row's options menu. Updates are installed only when you click the button.

The first version with this feature must be installed manually. Older versions
cannot discover updates. The app must be in a writable location, normally
Applications; otherwise the update row links to the release for manual installation.

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
