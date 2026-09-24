# Mac App Store checklist

Bundle ID `uk.trinh.DotBar` is registered; provisioning profile "DotBar Mac App Store" is installed.
Build: `scripts/appstore.sh <version> export` (pkg in dist/appstore) or `scripts/appstore.sh <version> upload`.

## One-time, in App Store Connect (web only, no API)
1. My Apps → + → New App: platform macOS, name **DotBar: AI Stats Menu**, primary language English, bundle ID uk.trinh.DotBar, SKU `dotbar-mac`.
2. Then `scripts/appstore.sh <version> upload` pushes the build.

## Metadata draft
- **Name**: DotBar: AI Stats Menu
- **Subtitle** (30 max): Claude & Codex usage limits
- **Category**: Utilities (secondary: Developer Tools)
- **Price**: Free (or your choice)
- **Privacy policy URL**: https://github.com/ptrinh/DotBar/blob/main/PRIVACY.md
- **Support URL**: https://github.com/ptrinh/DotBar
- **Keywords** (no words from name/subtitle, max 100): anthropic,openai,chatgpt,quota,limit,tokens,monitor,cpu,ram,battery,calendar,xbar,swiftbar
- **Promotional text** (170 max, editable without review): Never get cut off mid-task again: see how much of your Claude or Codex session and weekly limit is left, right in the menu bar.
- **Description**:
  Know where you stand with your AI limits at a glance. DotBar shows your Claude and Codex usage as two tiny bars in the menu bar: the top bar is your current 5-hour session, the bottom bar your weekly limit. It turns red from 90 %, so a limit never surprises you in the middle of a task.

  Click the icon for the exact numbers: session and weekly percentage, when each resets, and a link to your usage page.

  PRIVATE BY DESIGN
  • DotBar uses the sign-in Claude Code or Codex CLI already has on your Mac. Nothing to paste, no account to create.
  • You allow access once; your sign-in never leaves your Mac, and DotBar sends it only to Anthropic or OpenAI to read your usage.
  • No analytics, no tracking.

  MORE THAN AI
  DotBar is a tiny, flexible menu bar companion with ready-made presets:
  • Battery in the macOS 27 style, with health and cycle count
  • Calendar icon with a month popover and today's events
  • CPU and memory with sparklines, network, disk, uptime
  • Bitcoin, Ethereum, gold, stock and exchange rates, weather, air quality, world clock, Pomodoro
  • Or your own: static text or any shell script, with up to three colored status dots that follow your rules

  Minimal by design: under 1 MB, about 15 MB of memory, near-zero CPU.

  Claude is a trademark of Anthropic. Codex and ChatGPT are trademarks of OpenAI. DotBar is not affiliated with either.
- **Screenshots** (2880×1800, from `marketing/make-screenshots.sh` → dist/screenshots): 01 hero (AI usage in the menu bar), 02 AI usage close-up, 03 Preferences, 04 menu + presets.
- **App Review notes**: DotBar runs user-provided shell commands via /bin/zsh inside the App Sandbox; it ships with example recipes (uptime, vm_stat, pmset, df, curl to api.coinbase.com). The network.client entitlement is only used by those user scripts (e.g. curl for prices, weather). The calendar entitlement is used only when the user adds the Calendar recipe. The optional AI usage items read Codex CLI's sign-in file only after the user picks it in an open panel (security-scoped bookmark), and for Claude install a Claude Code hook only after the user picks ~/.claude and confirms; that hook, run by Claude Code, saves just the usage numbers to a file DotBar reads. No private APIs, no analytics.
- **Screenshots**: 2880×1800 or 1440×900 PNG, at least one. Suggested: menu bar close-up with the BTC + C/M dots item, the dropdown menu, and the Preferences window.

## Sandbox limits (App Store build only)
Denied inside the sandbox: `top`, `ps`, `ping`, `ipconfig getifaddr`, `git`. Recipes adapt automatically
(CPU % from load average / core count, local IP via `ifconfig`); Ping, Git Branch and Wi‑Fi SSID recipes are hidden.
The Homebrew build is not sandboxed and has no such limits.
