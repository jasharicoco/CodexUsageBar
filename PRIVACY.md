# Privacy

Codex Usage Bar is a local menu bar utility. It does not include analytics,
advertising, telemetry, or a separate account system.

## Data the app reads

The app starts the Codex executable already installed on the Mac and asks its
local app-server for:

- the active account type, so it can require ChatGPT subscription sign-in;
- the Codex weekly usage percentage; and
- the weekly reset time; and
- available earned resets, including their identifiers and expiration times.

The account-status response can contain an email address, but the app only
inspects the account type and does not use, copy, log, or store the email. The
app never receives or stores the user's access token, password, API key,
prompts, source code, or Codex conversations.

## Network access

Codex Usage Bar does not make its own account or analytics requests. The local
Codex process communicates with OpenAI using the user's existing Codex
configuration. After explicit confirmation, the app can ask that process to
consume one earned reset. Buttons in the onboarding screen can open the
official Codex website or the locally installed Codex desktop app.

The app also checks this project's public GitHub release endpoint at startup and
every six hours, unless automatic app update checks are turned off. Manual checks
use the same endpoint. GitHub receives the usual connection information, including
the IP address and a `CodexUsageBar` user agent; no Codex account or usage data is
sent. Clicking **Update and restart** downloads the release ZIP and its checksum
from GitHub and its asset delivery service. No GitHub login is required.

## Storage

Usage values, reset details, and reset idempotency keys are held in memory while
the app is running and are discarded when the app quits.

Theme and automatic update check preferences are saved locally in user defaults.
During an app update, downloaded files and the previous app are staged beside the
installed app. They are removed after a successful update; if installation fails,
a recovery copy may remain there.
