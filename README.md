# AgentUsageBar

AgentUsageBar is a lightweight macOS menu bar app for tracking Codex and Claude usage. It shows a single status item for one provider at a time — right-click to switch — with quota windows, reset times, usage pace, local token and cost estimates, and recent model activity.

The project is a focused reimplementation of selected [CodexBar](https://github.com/steipete/CodexBar) behavior for Codex and Claude.

## Features

- One menu bar item, right-click to switch between Codex and Claude
- Session and weekly quota remaining, reset times, and pace indicators measured against the clock at first, then against your own recorded windows once three comparable ones have completed
- Today's and rolling 30-day token and estimated cost totals
- Recent daily usage chart, per-model breakdown, and top-model summary
- Codex credits when the usage endpoint reports them
- Configurable manual or 1, 2, 5, 15, and 30-minute refresh intervals
- Editable per-model pricing overrides, including cache and long-context rates
- Last-known data retained and dimmed when a refresh fails

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode Command Line Tools or Xcode)
- Codex CLI and/or Claude Code signed in locally

AgentUsageBar can show either provider by itself. You do not need to use both.

## Build the app

Clone the repository and package a release build:

```bash
git clone git@github.com:softmaxe/agent-usage-bar.git
cd agent-usage-bar
make app
open build/AgentUsageBar.app
```

`make app` builds the current Mac architecture, assembles `build/AgentUsageBar.app`, and applies an ad-hoc code signature. To install the local build:

```bash
ditto build/AgentUsageBar.app /Applications/AgentUsageBar.app
open /Applications/AgentUsageBar.app
```

The current packaging script is intended for local builds. Public distribution still requires a Developer ID Application signature, hardened runtime, Apple notarization, and a distributable archive such as a signed ZIP or DMG.

## Sign in

AgentUsageBar reuses credentials created by the official CLIs. It does not provide its own login flow.

For Codex:

```bash
codex login
```

Codex credentials are read from `$CODEX_HOME/auth.json`, or `~/.codex/auth.json` when `CODEX_HOME` is unset.

For Claude Code, run the CLI and complete its login flow:

```bash
claude
```

Claude credentials are read from the macOS Keychain entry used by Claude Code.

## Use the menu bar app

Left-click the icon to view the current quota and local cost summary for the provider it shows. The menu provides:

- `Switch provider` to move the item to the other provider
- `Refresh` (`⌘R`) to request fresh provider data
- `Settings…` (`⌘,`) to change refresh frequency and pricing
- `Quit` (`⌘Q`) to stop the app

The menu bar carries one item. **Right-clicking** (or control-clicking) it switches between Codex and Claude, and the choice is remembered across launches; **Settings → General → Menu bar** shows which provider is current. The item stays visible while its provider is signed out or waiting for its first refresh, so the menu can report the current state instead of silently disappearing. Both providers keep refreshing in the background, so switching shows current data immediately.

Whenever the five-hour or weekly window resets, the card plays a one-off animation the next time it is opened. Each window resumes from its last observed pre-reset position and continuously slows into the new full reading, with nothing trailing the head on the way; reaching 100% is the whole event, and the pop, the flash, and a soft glow rising under the bar all land on that beat. The landing has no edges anywhere — what says the quota is full is the whole bar going warm, not a shape drawn where the head stopped. The percentage above the bar arrives with it rather than being already correct while the bar is still charging: it counts on the fill's own easing, blurs while the digits are turning fastest so it resolves into the new reading instead of stopping on it, and takes the same landing beat. The bar owns the only clock — the number renders the frames it publishes, so the two cannot drift apart. Five-hour and weekly resets are tracked independently, ordinary spending never triggers it, and both the last reading and a pending reset survive an app restart. Turning on **System Settings → Accessibility → Display → Reduce motion** replaces it with the ordinary fill. `make demo` replays the shared production animation on demand.

Opening the menu requests one immediate manual refresh without resetting the scheduled timer. Without clicks, the app keeps the configured background cadence; its default interval is five minutes to reduce quota-endpoint rate limiting.

## Cost estimates and pricing

Cost and token totals are estimated from local CLI session logs:

- Codex: `~/.codex/sessions` and `~/.codex/archived_sessions`
- Claude: `$CLAUDE_CONFIG_DIR/projects`, or `~/.claude/projects` and `~/.config/claude/projects` when `CLAUDE_CONFIG_DIR` is unset

The first scan can take longer on a large history. Later scans are incremental and use a cache at:

```text
~/Library/Caches/AgentUsageBar/cost-usage/cost-usage.sqlite
```

Built-in rates are supplemented by the public [models.dev](https://models.dev) catalog, cached for 24 hours; a failed refresh is not retried for an hour, and the pane never waits on one — it draws from the cache and folds a newer catalog in behind it. Rates can be reviewed or overridden under **Settings → Pricing**, which exposes every figure the cost math reads: input, output, five-minute cache write, cache read, the one-hour cache write (empty means twice input, the ratio Anthropic publishes), and the long-context tier — its per-request token threshold plus the rates that apply above it. The table opens with the models the local logs use most at the top; clicking **Model**, **Input**, **Output**, **Cache w**, or **Cache r** sorts by that column and clicking it again reverses it, and the control at the right end of the header row goes back to the default most-used-first order. User overrides are stored at:

```text
~/Library/Application Support/AgentUsageBar/pricing-overrides.json
```

Saved rates apply going forward. Everything already recorded is priced and frozen at the rates in force when it was scanned, so an edit changes future usage only and never rewrites past days.

All displayed costs are estimates. Cache-token accounting, provider billing rules, and changing model prices can make them differ from an invoice.

## Privacy and network access

AgentUsageBar reads local CLI credentials and usage logs. It never writes to them: `auth.json` is read-only to this app, and a refreshed Codex token is held in memory for that run only. Everything it does write lives under its own directories:

```text
~/Library/Application Support/AgentUsageBar/usage-history.json      quota samples, kept 56 days
~/Library/Application Support/AgentUsageBar/pricing-overrides.json  manual rates, when set
~/Library/Caches/AgentUsageBar/cost-usage/cost-usage.sqlite         incremental scan cache
~/Library/Caches/AgentUsageBar/model-pricing/                       models.dev catalog, 24h TTL
```

Settings live in the standard preferences domain for the bundle, `com.agentusagebar.app`. The cost cache stores transcript paths, dates, model names, token counts, and costs — never prompt or response text.

The app makes requests to:

- OpenAI's Codex usage endpoint for Codex quota data
- Anthropic's OAuth usage endpoint for Claude quota data
- `models.dev` for the optional pricing catalog

Claude Keychain access is performed through Apple's `/usr/bin/security` tool and may trigger a macOS access prompt.

## Development

The project uses Swift Package Manager and does not require an Xcode project.

```bash
make build       # Build a debug binary
make run         # Stop an existing instance, build, and run in the foreground
make test        # Run the assertion-based test suite
make probe       # Check both provider integrations from the terminal
make probe-cost  # Rescan the local logs and print cost totals, without credentials or network
make demo        # Replay the quota-recovery animation in a plain window
make demo-number # Compare candidate treatments for the headline percentage
make logs        # Stream app logs
make app         # Build the release .app bundle
make clean       # Remove SwiftPM and app build output
```

`make probe` can expose account and usage metadata in the terminal. Review its output before sharing logs.

## Troubleshooting

### A provider reports that it is not signed in

Run the corresponding CLI login flow, then choose `Refresh`. Use `make probe` from the repository to see the credential or endpoint error directly.

### Data is stale or refreshes return HTTP 429

AgentUsageBar keeps the last good data and dims the menu bar icon. Wait for the provider's rate-limit window, use a longer refresh interval, and avoid repeatedly forcing refreshes.

### Cost totals are missing or incomplete

Confirm that the CLI has local JSONL session logs and that the app can read the paths listed above. Unknown models appear without a price until the catalog or a manual pricing override supplies one.

### Inspect app logs

```bash
make logs
```

The logging subsystem is `com.agentusagebar.app`.

## Current limitations

- The package script produces a host-architecture, ad-hoc-signed local build; universal release packaging and notarization are not automated.
- Claude credentials are not refreshed or written back by AgentUsageBar. Re-authenticate with Claude Code when needed.
- Provider-specific spend controls, additional per-model limits, workspace resolution, and web fallbacks are outside the current scope.
- Cost figures are reconstructed from local logs and are not billing statements.

## Acknowledgements

AgentUsageBar adapts selected ideas and implementation details from CodexBar, Copyright © 2026 Peter Steinberger, under the MIT License. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for attribution and license text.
