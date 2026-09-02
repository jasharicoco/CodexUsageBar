# Codex Usage Bar

A small native macOS app that shows your remaining weekly Codex usage in the menu bar.

![Codex Usage Bar showing the remaining weekly usage](Screenshots/codex-usage-bar.png)

It automatically uses the ChatGPT account already signed in to Codex on your Mac. No separate login or API key is needed.

The interface follows your Mac's preferred language: Swedish when the primary language is Swedish, otherwise English.

> Independent open-source project. Not affiliated with or endorsed by OpenAI.

## Install

1. Download the latest universal ZIP from [Releases](../../releases/latest).
2. Unzip it and move `CodexUsageBar.app` to **Applications**.
3. Open the app. If macOS blocks it, right-click it and select **Open**.

Requires macOS 13 or later and Codex Desktop or Codex CLI. If needed, sign in first with:

```sh
codex login
```

## Build from source

```sh
swift run ParserChecks
./Scripts/build-app.sh
open dist/CodexUsageBar.app
```

## License

The source code is available under the [MIT License](LICENSE).

- [Privacy](PRIVACY.md)
- [Security](SECURITY.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

The OpenAI logo is owned by OpenAI and is not covered by the MIT License.
