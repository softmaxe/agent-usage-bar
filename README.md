<p align="center">
  <img src="Resources/AppIcon.png" alt="QuotaBar app logo" width="180">
</p>

<h1 align="center">QuotaBar</h1>

<p align="center">
  <a href="README.md"><kbd>English</kbd></a>
  <a href="README.zh-CN.md"><kbd>简体中文</kbd></a>
</p>

A macOS menu bar app that tells you how much Codex and Claude quota you have left, what you spent
locally, and when the window resets.

It is a trimmed rebuild of [CodexBar](https://github.com/steipete/CodexBar). CodexBar tracks a long
list of agent CLIs; this one tracks two, Codex and Claude, and spends the room it saved on the parts
you actually look at. One status item instead of a row of them. One card that fits on screen. Motion
that comes from one curve rather than five.

<img src="docs/images/hero.png" width="620" alt="The Claude and Codex cards side by side">

## What "trimmed" means

Every file adapted from CodexBar says in its header what it kept and what it dropped. The short
version:

| Kept | Dropped |
| --- | --- |
| Codex `wham/usage`, Claude `/api/oauth/usage` | Gemini, Antigravity, Factory, Warp |
| Session and weekly windows, credits | Spend controls, per-model rate limits, workspace resolution |
| Linear and historical pace models | Workday-weighted progress, run-out risk percentage |
| Local cost scan for both CLIs | Profile lookup, extra-usage billing, the web fallback |
| The capsule icon and its two decorations | Blink, wiggle, tilt, status overlays, the morph cache |

What replaced them is motion. CodexBar's bar jumps to its new value; this one charges into it, and
the number above it charges with it.

## The menu bar item

<img src="docs/images/menu-bar-icons.png" width="440" alt="Menu bar icon states">

Claude on the top row, Codex on the bottom. Left to right: full, half spent, nearly out, session
window only, and stale after a failed refresh. The icon draws on an 18pt pixel grid at 2x, so the
edges land on pixel boundaries instead of blurring.

There is one item, never two. Right-click it to move it to the other provider; the choice survives
a relaunch. Only the provider on screen refreshes, and each one holds a cooldown of its own, so
switching back and forth does not fetch either twice inside a minute.

## The reset animation

When a five-hour or weekly window rolls over, the card plays this the next time you open it.

<img src="docs/images/quota-reset.gif" width="560" alt="A quota window resetting: the bar charges to full, pops, flashes, and blooms">

The bar resumes from the last reading it saw before the reset and slows continuously into the new
one. Nothing trails the head on the way. Reaching 100% is the whole event, so the pop, the flash and
the glow under the bar all land on that one beat, and the landing has no edges anywhere: what says
the quota is full is the whole bar going warm, not a shape drawn where the head stopped.

The percentage arrives with the fill rather than being already correct while the bar is still
charging. It counts on the fill's own easing, blurs while the digits are turning fastest so it
resolves into the reading instead of stopping on it, and takes the same landing beat. The bar owns
the only clock and publishes the frames it draws; the number renders those. They cannot drift apart.

Five-hour and weekly resets are tracked separately. Ordinary spending never triggers it. Both the
last reading and a pending reset survive a restart. Five clicks on a bar replays it if you want to
see it again.

## Everything else that moves

Same vocabulary throughout. One exponential decay for "this is charging", one damped sine for
"this landed", shortened from a celebration to the length of a click.

**The settings tabs** are drawn rather than handed to AppKit, because the system tab bar has
nowhere to put a curve. The selection is one pill whose two edges run the same easing over
different durations: the edge facing the destination leaves first, the one behind it catches up, so
the pill briefly spans both segments and then contracts onto the new one. It is never in two places
and never between them covering neither. The assertion suite walks the curve and checks the shape
at every frame.

<img src="docs/images/tab-switch.gif" width="420" alt="The settings tab pill stretching across both segments and contracting onto the destination">

**The pricing table** opens its groups and its per-model rows on the fill's easing, staggered 35ms
apart so a group unrolls from under its header instead of appearing all at once. The chevron turns
a quarter turn rather than being swapped for a second glyph. Only the control springs: a table that
overshoots its own height pushes every row below it, which reads as a bug rather than as a beat.

A press is answered at the size of what was pressed. A model row's chevron is a 9pt glyph, so it
dips to 0.86 and comes back on the settle spring. A provider header is a full-width row, and the
same dip on something that wide reads as the table flinching, so it dips to 0.985 over 100ms and
comes back on an ease-out that cannot overshoot. It was picked over a chevron-only dip, a tint,
and no press at all.

<img src="docs/images/disclosure.gif" width="500" alt="A pricing group unrolling four rows one beat apart">

**The cost chart** lifts the highlighted bar 5pt and opens its per-model breakdown. A move between
bars is chasing the pointer, so it rides a fast spring; the trip home to today is not a move anyone
aimed at anything, so it is longer and critically damped, and the highlight settles onto today
instead of springing onto it.

<img src="docs/images/chart-motion.gif" width="440" alt="The chart highlight moving between bars and settling back onto today">

Hovering a bar opens what that day was actually made of:

<img src="docs/images/chart-hover.gif" width="500" alt="Each bar's per-model breakdown">

Clicking the highlighted bar swaps its label between tokens and cost, and rescales the chart under
it:

<img src="docs/images/label-toggle.gif" width="440" alt="The label blurring out of 37M into $37 while every bar rescales from the token metric to the cost one">

The unit is the chart's height metric too. Each bar is measured in whatever the label reads, against
the tallest day in that same unit, so a click changes both the bars and the scale they are drawn
against. A week where a cheap model spent most of the tokens is a different shape in dollars, and
that difference is the reason to ask. The heights run to their new proportions on the 260ms curve
the reading resolves on, so the chart and the number arrive together.

The reading itself does not move. The click lands on a bar the pointer is already on, so the swap
has no distance to cover: the old reading blurs out and the new one resolves out of the blur in its
place. That is what says the two readings are one quantity counted twice. Sliding one number aside
for the other would say the label had been replaced. Tokens is the starting unit, the choice is
remembered, and a click that lands in the gap between two bars does nothing.

**A rate field** in the pricing table marks focus with a one-pixel border in the system accent
color, faded in over 90ms. The field is the same size focused as unfocused and the border is drawn
inside the frame it already had, because four of these sit on every row and a ring that took its
own space would nudge the row it landed in. It was picked over an inner ring, a wash, an underline
and the stock `.roundedBorder` field it replaced.

**The pointer** moves too. The Codex card is taller than the Claude card, and a menu can only grow
downwards, so a provider switch slides every row out from under a pointer that never moved. The
pointer moves by the same amount and keeps pointing at the row it was on.

Turn on **System Settings → Accessibility → Display → Reduce motion** and all of it becomes a cut.
Not a slower animation, a cut.

## The card

Left-click the icon. Each quota window shows what is left, when it resets, and how that compares to
spending it evenly against the clock. "9% in reserve" means you are under; a red pace marker means
you are over. Once three comparable windows have completed, the weekly line stops measuring against
the clock and measures against your own recorded weeks instead.

Click any **`Resets in …`** label to swap the countdown for the wall-clock time it is counting down
to: `Resets 3:30 PM` today, `Resets Sat 9:00 AM` further out.

<img src="docs/images/reset-toggle.gif" width="500" alt="Clicking the session reset label swaps both windows between a countdown and a clock time">

The label brightens under the pointer. Nothing else on the card outside the chart reacts to the
pointer at all, so that lift is the whole of what says the line is a switch. One click changes both
windows, because the face belongs to the card rather than to the row you happened to click, and the
choice survives a relaunch. Which face is useful changes during the day: a countdown answers "how
much longer", a clock time answers "can I finish this before it goes".

The menu carries `Switch provider`, `Refresh`, `Settings` (⌘,) and `Quit` (⌘Q). Refresh is subject
to a one-minute cooldown and counts it down on the row rather than dropping your click without a
word. Opening the menu requests one refresh of the provider on screen without resetting the
scheduled timer.

<img src="docs/images/settings-general.png" width="620" alt="The General settings pane">

Background refresh runs manually or every 1, 2, 5, 15 or 30 minutes. Five is the default, because
the quota endpoints are shared with the CLIs and will rate-limit you.

## Cost and pricing

<img src="docs/images/settings-pricing.png" width="620" alt="The pricing pane with a model row unfolded">

Token and cost totals come from the CLIs' own session logs, never from a billing API:

- Codex: `~/.codex/sessions` and `~/.codex/archived_sessions`
- Claude: `$CLAUDE_CONFIG_DIR/projects`, or `~/.claude/projects` and `~/.config/claude/projects`

The first scan of a large history takes a while. Later ones are incremental against a SQLite cache.

Built-in rates are topped up from the public [models.dev](https://models.dev) catalog, cached for 24
hours. A failed refresh is not retried for an hour, and the pane never waits on one: it draws from
the cache and folds a newer catalog in behind it.

**Settings → Pricing** exposes every figure the cost math reads. Input, output, five-minute cache
write, cache read, the one-hour cache write (leave it empty to bill it at twice input, the ratio
Anthropic publishes), and the long-context tier with its own per-request threshold. The table opens
in provider groups with the API models in their published order, and anything else your logs turned
up below them, most-used first. Click a column to sort by it, click again to reverse, and use the
control at the right end of the header to go back. It stays lit while that default order is the
one in force, the way a sorted column's title does.

A row folds the one-hour cache write and the long-context tier away behind a chevron. The model
name opens the row as well, so the target is the whole left half of it rather than a 9pt glyph.

Saved rates apply going forward only. Everything already scanned keeps the prices it was scanned
with, so an edit never rewrites past days.

All of it is an estimate. Cache accounting, provider billing rules and price changes will make it
differ from an invoice.

## Requirements

- macOS 14 or later
- Swift 6 toolchain (Xcode or the Command Line Tools)
- Codex CLI and/or Claude Code signed in locally

One provider is enough. You do not need both.

## Install

### Homebrew

If you already use Homebrew, this is the cleanest way to keep the app current.

```bash
brew tap softmaxe/tap
brew install --cask quota-bar
```

That fetches the ZIP that matches your Mac, checks the SHA, and places `QuotaBar.app` in `/Applications`. You do not need Xcode or `make`.

Update later with:

```bash
brew update
brew upgrade --cask quota-bar
```

You can also skip the tap step:

```bash
brew install --cask softmaxe/tap/quota-bar
```

The cask version tracks the GitHub tag, so `brew upgrade` follows new releases. The release workflow bumps the cask automatically from the `.sha256` files, so the SHA usually stays in sync without a manual edit.

To remove it:

```bash
brew uninstall --cask quota-bar
brew uninstall --zap --cask quota-bar  # also clears ~/Library/Application Support/QuotaBar and caches
```

### Manual download

Download the ZIP for your Mac from [GitHub Releases](https://github.com/softmaxe/quota-bar/releases),
then unzip it and move `QuotaBar.app` to `/Applications`.

- Apple Silicon (M1 or later): download the `arm64` ZIP.
- Intel: download the `x86_64` ZIP.

To check which Mac you have, open **Apple menu → About This Mac**. If the overview shows a **Chip**
such as Apple M1 or M2, choose `arm64`. If it shows an Intel **Processor**, choose `x86_64`.

Each ZIP has a matching `.sha256` file. Download both files, open Terminal in the download folder,
and verify the archive before unzipping it. For example:

```bash
shasum -a 256 -c QuotaBar-1.2.3-macos-arm64.zip.sha256
```

Both the Homebrew cask and the manual ZIP require macOS 14 or later and are ad-hoc signed for this project. They do not have an
Apple Developer ID signature and are not notarized, so macOS may warn the first time you open the app.
After moving the app to `/Applications`, try opening it once, then use
[Apple's approval flow](https://support.apple.com/en-us/102445):

1. Open **System Settings → Privacy & Security**.
2. Click **Open Anyway** next to the QuotaBar warning.
3. Click **Open** to confirm.

If you need a Terminal fallback, run this command only after placing the app in `/Applications`:

```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
```

This removes the quarantine attribute from this app bundle only and bypasses this bundle's quarantine
check. It does not add an Apple signature or notarization.

## Build

```bash
git clone git@github.com:softmaxe/quota-bar.git
cd quota-bar
make app
open build/QuotaBar.app
```

`make app` builds for the current architecture, assembles `build/QuotaBar.app` and ad-hoc signs
it. To install it:

```bash
ditto build/QuotaBar.app /Applications/QuotaBar.app
```

This local build and the release ZIPs use the same ad-hoc signing approach. They can be distributed
without an Apple Developer ID signature or notarization, but macOS may show the first-launch warning
described above.

## Publish a release

For a test package, open the repository's **Actions** tab, select **Build and Release**, then choose
**Run workflow**. The workflow tests and packages both architectures without creating a GitHub
Release. These development artifacts use app version `0.0.0`, include the commit SHA in their file
names and remain available for 14 days.

To publish a version, create and push a three-part version tag:

```bash
git tag v1.2.3
git push origin v1.2.3
```

Both architecture jobs run `make test`, build an ad-hoc-signed app and verify the archive. GitHub
publishes the Release only after both jobs succeed. An existing Release for the same tag is never
overwritten; publish a new version tag instead.

## Sign in

QuotaBar reuses the credentials the official CLIs already created. It has no login flow of its
own.

```bash
codex login   # writes $CODEX_HOME/auth.json, or ~/.codex/auth.json
claude        # complete the CLI's own flow; the token lands in the Keychain
```

Reading the Claude entry goes through Apple's `/usr/bin/security`, which may raise a macOS access
prompt the first time. If a user-initiated `Refresh` receives a 401, QuotaBar may start a
hidden, five-second Claude Code status command so Claude Code can refresh its own credentials. The
app then rereads the Keychain and retries once only when the access token changed. It never writes
the CLI credential item. QuotaBar itself does not call `auth login` or open Terminal or a
browser. Claude Code may still require interactive sign-in; when that happens, recovery stops and
you must open Claude Code yourself. Automatic refreshes fail closed and never start Claude Code.

## Privacy

The app reads local credentials and logs and never writes to the CLI-owned credential stores.
`auth.json` is read-only to it, and a refreshed Codex token stays in memory for that run. A Claude
Code process may update its own credentials only after the user clicks `Refresh`. What QuotaBar
does write lives under its own directories:

```text
~/Library/Application Support/QuotaBar/usage-history.json      quota samples, kept 56 days
~/Library/Application Support/QuotaBar/pricing-overrides.json  manual rates, when set
~/Library/Caches/QuotaBar/cost-usage/cost-usage.sqlite         incremental scan cache
~/Library/Caches/QuotaBar/model-pricing/                       models.dev catalog, 24h TTL
```

The cost cache stores transcript paths, dates, model names, token counts and costs. It never stores
prompt or response text. Settings live in `com.quotabar.app`.

Three hosts get requests: OpenAI's Codex usage endpoint, Anthropic's OAuth usage endpoint, and
`models.dev` for the optional catalog.

## Development

Swift Package Manager, no Xcode project.

```bash
make build              # Debug binary
make run                # Stop any running instance, build, run in the foreground
make test               # 185 assertions plus 12 verifiers that walk the animation curves
make probe              # Check both provider integrations from the terminal
make probe-cost         # Rescan local logs and print cost totals. No credentials, no network
make logs               # Stream os.Logger output for com.quotabar.app
make app                # Release .app bundle
make readme-assets      # Re-render every image in this file. Needs ffmpeg
make clean
```

There is no XCTest without Xcode, so the suite is a plain executable of assertions plus twelve
verifiers that sample the motion curves frame by frame.

The dumps behind `make readme-assets` are flags on the same binary: `--dump-card`, `--dump-icons`,
`--dump-settings`, `--dump-card-celebration`, `--dump-chart-hover`, `--dump-reset-toggle`,
`--dump-tab-switch`, `--dump-disclosure`, `--dump-chart-motion` and `--dump-label-toggle`, each
taking an output directory. Along with the verifiers they are compiled out of a release build, so
the shipped app answers to no flags at all.

Every image above is generated, not captured. The screenshots are offscreen renders of the shipped
views against fixture data, including the pricing pane, which takes made-up model totals and the
built-in rate table rather than reading the machine it runs on. `quota-reset.gif`,
`chart-hover.gif` and `reset-toggle.gif` are frame dumps of the shipped views. `reset-toggle.gif`
is the only one where a dump adds anything: it draws the label hovered, because an offscreen render
has no pointer to hover with. The other four come from `MotionFilmStrip`, which poses stand-in layouts
because a pill driven by two SwiftUI state edges cannot be asked what it looks like 140ms in; the
durations, curves, springs and staggers in those four are read from the same constants the real
controls animate on. `label-toggle.gif` takes its bar heights from the shipped policy as well, so
the rescale in it is the one the chart performs rather than a drawing of it.

`make probe` prints account and usage metadata. Read it before pasting it anywhere.

## Troubleshooting

**A provider says it is not signed in.** Run that CLI's login flow, then choose `Refresh`. `make
probe` shows the credential or endpoint error directly.

**Data is stale, or refreshes return HTTP 429.** The app keeps the last good reading and dims the
icon. Wait out the provider's window, pick a longer interval, and stop forcing refreshes.

**Cost totals are missing.** Confirm the CLI is writing JSONL session logs to the paths above.
Models with no known price appear without one until the catalog or an override supplies it.

## Limitations

- `make app` produces a host-architecture, ad-hoc-signed local build. The release workflow produces
  separate `arm64` and `x86_64` ZIPs rather than a Universal binary. Developer ID signing and
  notarization are not part of the release strategy.
- Claude credential recovery is delegated to Claude Code only after a user-initiated `Refresh` and
  is bounded to one hidden status attempt. Automatic refreshes fail closed, and QuotaBar never
  writes CLI credentials. Claude Code may still require interactive sign-in; if it does, recovery
  stops and you must open Claude Code yourself.
- Cost figures are reconstructed from local logs. They are not billing statements.

## License

AGPL-3.0. The full text is in [LICENSE](LICENSE).

That is the strict end of the copyleft range, and it is the point. Ship a modified build and the
source has to go with it, under the same license. Section 13 covers the case a plain GPL leaves
open: run a modified version as a network service and everyone who talks to that service over the
network can ask you for its source. Keeping a private fork to yourself is still fine.

The parts adapted from CodexBar stay MIT under their own terms. The project as a whole is AGPL-3.0.

## Acknowledgements

Built on ideas and implementation details from CodexBar, Copyright © 2026 Peter Steinberger, under
the MIT License. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
