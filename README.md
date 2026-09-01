<p align="center">
  <img src="Resources/AppIcon.png" alt="QuotaBar app logo" width="180">
</p>

<h1 align="center">QuotaBar</h1>

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <a href="README.zh-CN.md"><kbd>简体中文</kbd></a>
</p>

A macOS menu bar app for checking Codex and Claude quota, reset times, local token usage, and estimated cost.

<img src="docs/images/hero.png" width="620" alt="Claude and Codex quota cards">

QuotaBar is a focused rebuild of [CodexBar](https://github.com/steipete/CodexBar). It supports Codex and Claude in one menu bar item.

## Features

- Shows remaining session and weekly quota, reset time, usage pace, and credits when available.
- Charts local Codex and Claude token use and estimated cost by day and model.
- Includes matching OpenCode OpenAI OAuth usage under Codex.
- Switches providers from one menu bar icon and refreshes each provider independently.
- Uses built-in pricing, the public [models.dev](https://models.dev) catalog, and optional manual rate overrides.
- Keeps the last good quota reading when a refresh fails.
- Disables motion when macOS Reduce Motion is enabled.

<img src="docs/images/menu-bar-icons.png" width="440" alt="Menu bar icon states from full quota to stale data">

## Install

QuotaBar requires macOS 14 or later. You need Codex CLI, Claude Code, or both, signed in on the same Mac. Prebuilt releases do not require Xcode or Swift.

### Homebrew

```bash
brew install --cask softmaxe/tap/quota-bar
```

Update or remove it with:

```bash
brew upgrade --cask quota-bar
brew uninstall --cask quota-bar
```

To remove the app and its saved data:

```bash
brew uninstall --zap --cask quota-bar
```

### Manual download

Download the ZIP for your Mac from [GitHub Releases](https://github.com/softmaxe/quota-bar/releases), unzip it, and move `QuotaBar.app` to `/Applications`.

| Mac | Download |
| --- | --- |
| Apple Silicon, M1 or later | `arm64` ZIP |
| Intel | `x86_64` ZIP |

Each ZIP has a matching `.sha256` file. Verify it before unzipping:

```bash
shasum -a 256 -c QuotaBar-1.2.3-macos-arm64.zip.sha256
```

Releases are ad hoc signed, not notarized with an Apple Developer ID. If macOS blocks the first launch, try opening the app once, then go to **System Settings → Privacy & Security** and choose **Open Anyway**. As a fallback, after confirming the app is in `/Applications`, remove quarantine from this app only:

```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
```

## First launch

QuotaBar reuses credentials created by the official CLIs. It has no separate login flow.

```bash
codex login
claude
```

Then open QuotaBar:

- Left-click the menu bar icon to view quota and local cost.
- Right-click it to switch between Codex and Claude.
- Open **Settings** to choose a refresh interval or edit model rates.

Reading Claude credentials may trigger a macOS Keychain prompt. If a manual `Refresh` receives HTTP 401, QuotaBar lets Claude Code attempt one short credential refresh. Automatic refreshes never start Claude Code.

## How quota tracking works

Each available quota window shows the percentage left and its reset time. Click a `Resets in …` label to switch between a countdown and a clock time.

QuotaBar compares consumption with time elapsed. After three comparable weekly windows, it uses your recorded history for the weekly pace instead. Samples are kept for 56 days.

Background refresh can be manual or every 1, 2, 5, 15, or 30 minutes. The default is 5 minutes. Each provider has a one-minute refresh cooldown to avoid repeated requests and HTTP 429 responses.

When a session or weekly window resets, the next open plays a short reset animation. The last reading and pending animation survive an app restart.

<img src="docs/images/quota-reset.gif" width="560" alt="A quota bar animating from its previous reading to a reset quota">

## How cost tracking works

QuotaBar calculates token and cost totals from local session data. It does not use a billing API.

Hover a day in the chart to see its model breakdown. Click the highlighted day to switch the chart between tokens and cost.

| Source | Local data |
| --- | --- |
| Codex | `~/.codex/sessions`, `~/.codex/archived_sessions` |
| Claude | `$CLAUDE_CONFIG_DIR/projects`, or `~/.claude/projects` and `~/.config/claude/projects` |
| OpenCode | `$OPENCODE_DATA_HOME/opencode.db`, `$XDG_DATA_HOME/opencode/opencode.db`, or `~/.local/share/opencode/opencode.db` |

OpenCode data is included only when its `openai` provider uses OAuth and its account ID matches the current Codex account. Other providers, API-key sessions, and account mismatches are ignored. OpenCode totals do not affect quota bars.

The first scan of a large history may take time. Later scans use an incremental SQLite cache. The pricing catalog is cached for 24 hours. Manual rate changes apply to new usage only, so past totals keep the prices used when they were scanned.

<img src="docs/images/settings-pricing.png" width="620" alt="Pricing settings with editable model rates">

Cost totals are estimates. Provider billing rules, cache accounting, and price changes can make them differ from an invoice.

## Privacy and network access

QuotaBar reads CLI credentials and usage logs but does not write to CLI credential stores. It reads token, model, time, and usage metadata. It does not read prompt, response, or reasoning text.

The app stores its own data here:

```text
~/Library/Application Support/QuotaBar/usage-history.json
~/Library/Application Support/QuotaBar/pricing-overrides.json
~/Library/Caches/QuotaBar/cost-usage/cost-usage.sqlite
~/Library/Caches/QuotaBar/model-pricing/
```

It contacts the OpenAI Codex usage and token-refresh endpoints, the Anthropic OAuth usage endpoint, and `models.dev` for model pricing.

## Build and develop

Building requires the Swift 6 toolchain from Xcode or the Command Line Tools. The project uses Swift Package Manager and has no Xcode project.

```bash
git clone https://github.com/softmaxe/quota-bar.git
cd quota-bar
make app
open build/QuotaBar.app
```

Common commands:

```bash
make build          # Build the debug binary
make run            # Build and run in the foreground
make test           # Run assertions and animation verifiers
make probe          # Check both provider integrations
make probe-cost     # Rescan local logs without credentials or network
make logs           # Stream logs for com.quotabar.app
make readme-assets  # Rebuild README images; requires ffmpeg
make clean
```

`make probe` prints account and usage metadata. Review its output before sharing it.

To create a test package, run **Build and Release** from the repository's **Actions** tab. To publish a release, push a tag matching `vMAJOR.MINOR.PATCH`. The workflow tests and packages separate `arm64` and `x86_64` ZIPs, then creates the GitHub Release.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| Provider is not signed in | Run that CLI's login flow, then choose `Refresh`. Use `make probe` for the raw error. |
| Data is stale or refresh returns HTTP 429 | Wait for the provider cooldown and select a longer refresh interval. |
| Cost totals are missing | Confirm the CLI writes session logs to the paths above. A model also needs a catalog price or manual rate. |
| OpenCode usage is missing | Confirm OpenCode uses `openai` OAuth with the same account as Codex. Check **Settings → Pricing** for database or authentication errors. |

## Limitations

- Release ZIPs are architecture-specific, ad hoc signed, and not notarized.
- Claude credential recovery runs only after a manual `Refresh` and may still require opening Claude Code for interactive sign-in.
- Cost figures come from local logs and are not billing statements.
- OpenCode does not save the authentication method for each historical request. QuotaBar cannot reconstruct an OAuth to API key to OAuth switch that happened while it was not running.

## License

QuotaBar is licensed under [AGPL-3.0](LICENSE). Code adapted from CodexBar remains available under its MIT terms. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Acknowledgements

QuotaBar uses ideas and implementation details from CodexBar, Copyright © 2026 Peter Steinberger.
