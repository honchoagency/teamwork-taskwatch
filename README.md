# TaskWatch

A macOS menu bar app that watches Teamwork tasks and alerts you in Slack when a
new comment is posted. Polls the Teamwork API every 15 minutes. No backend —
fully self-contained.

## Install (team members)

Download the latest `TaskWatch-x.y.z.dmg` from the
[Releases](../../releases) page, open it, and drag **TaskWatch** to Applications.

TaskWatch is ad-hoc signed, not notarized, so macOS Gatekeeper blocks it on first
launch. Clear the quarantine flag once in Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/TaskWatch.app"
```

(Or open it once and use **System Settings → Privacy & Security → Open Anyway**.)

Then open TaskWatch from the menu bar and fill in Preferences (see below).

## Requirements (development)

- macOS 13+
- Xcode Command Line Tools (`xcode-select --install`) — full Xcode not required

## Build & run

```bash
./build.sh              # native build → TaskWatch.app (fast, for dev)
open TaskWatch.app

UNIVERSAL=1 ./build.sh   # universal arm64 + x86_64 (what releases ship)
./package-dmg.sh 1.2.3   # package the built app into a DMG
```

The app lives in the menu bar (no Dock icon). Click the eye icon to open the
popover. The sources have no third-party dependencies and are compiled directly
with `swiftc`; `Package.swift` is kept only for editor/SourceKit support.

## Releasing

Pushing a git tag triggers [`.github/workflows/release.yml`](.github/workflows/release.yml),
which builds a universal binary on a macOS runner, packages a DMG, and attaches
it to a GitHub Release:

```bash
git tag 1.2.3
git push origin 1.2.3
```

The release notes include the first-launch quarantine instructions for teammates.

## First launch

If credentials are missing, Preferences opens automatically. Fill in:

| Field | Stored in | Example |
| --- | --- | --- |
| Teamwork API token | macOS Keychain | `tw_xxx…` |
| Teamwork site URL | UserDefaults | `https://yourcompany.teamwork.com` |
| Slack bot token | macOS Keychain | `xoxb-…` |
| Your Slack email | UserDefaults | `you@company.com` |

The Teamwork token is sent via HTTP Basic auth (token as username, `X` as
password).

## Slack setup (per-user DMs)

Notifications are sent as a **direct message** to each user — there is no shared
channel. Each person running TaskWatch gets alerts for the tasks *they* watch,
in their own Slack.

This uses a Slack **bot token**, not an incoming webhook (webhooks can't DM).
For a team, create **one** Slack app for the workspace and share its bot token;
each teammate just enters their own email.

One-time workspace setup (admin):

1. Create a Slack app at <https://api.slack.com/apps> → *From scratch*.
2. **OAuth & Permissions** → add Bot Token Scopes: `chat:write` and
   `users:read.email`.
3. **Install to Workspace**, then copy the **Bot User OAuth Token** (`xoxb-…`).
4. Share that token with the team (it's a shared secret — keep it internal;
   rotate by reinstalling if it leaks).

Each teammate then enters the shared `xoxb-…` token plus their own work email in
Preferences. The app resolves the email to a Slack member id
(`users.lookupByEmail`) and DMs that person. The message lands under **Apps** in
their Slack sidebar.

## Usage

- **Watch a task** — paste a task URL (e.g. `https://yourco.teamwork.com/tasks/12345`)
  into the popover and click **Watch**. On add, the task name is fetched and the
  newest existing comment is recorded as a baseline, so you're only alerted on
  *new* comments.
- **Polling** — every 15 minutes each watched task is checked for new comments
  (→ Slack) and for completion (→ removed from the list + a macOS notification).
- **Cap** — up to 10 watched tasks.

## Behaviour notes

- Poll failures (network, 401, etc.) are logged to the console and otherwise
  ignored — tasks are never removed or re-baselined on error.
- Completed tasks fire a local notification:
  `TaskWatch: [Task Name] is complete and has been removed from your watch list.`
- The menu bar icon shows a badge (`bell.badge.fill`) after a comment alert
  fires; opening the popover clears it.
