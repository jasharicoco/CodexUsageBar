# Privacy

Codex Usage Bar is a local menu bar utility. It does not include analytics,
advertising, telemetry, or a separate account system.

## Data the app reads

The app starts the Codex executable already installed on the Mac and asks its
local app-server for:

- the active account type, so it can require ChatGPT subscription sign-in;
- the Codex weekly usage percentage; and
- the weekly reset time.

The account-status response can contain an email address, but the app only
inspects the account type and does not use, copy, log, or store the email. The
app never receives or stores the user's access token, password, API key,
prompts, source code, or Codex conversations.

## Network access

Codex Usage Bar does not make its own account or analytics requests. The local
Codex process communicates with OpenAI using the user's existing Codex
configuration. Buttons in the onboarding screen can open the official Codex
website or the locally installed Codex desktop app.

## Storage

Usage values are held in memory while the app is running and are discarded
when the app quits.
