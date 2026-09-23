# Mac App Store checklist

Bundle ID `uk.trinh.DotBar` is registered; provisioning profile "DotBar Mac App Store" is installed.
Build: `scripts/appstore.sh <version> export` (pkg in dist/appstore) or `scripts/appstore.sh <version> upload`.

## One-time, in App Store Connect (web only, no API)
1. My Apps → + → New App: platform macOS, name **DotBar: Menu Bar Stats**, primary language English, bundle ID uk.trinh.DotBar, SKU `dotbar-mac`.
2. Then `scripts/appstore.sh <version> upload` pushes the build.

## Metadata draft
- **Name**: DotBar: Menu Bar Stats
- **Subtitle**: Custom text, scripts & dots
- **Category**: Utilities
- **Price**: Free (or your choice)
- **Privacy policy URL**: https://github.com/ptrinh/DotBar/blob/main/PRIVACY.md
- **Support URL**: https://github.com/ptrinh/DotBar
- **Keywords** (no words from name/subtitle, max 100): status,monitor,cpu,ram,battery,bitcoin,xbar,swiftbar,textbar,widget,shell,clock,calendar
- **Description**:
  DotBar puts your own text in the macOS menu bar: static labels or the output of any shell script, refreshed on a schedule or streamed live.
  Next to the text, up to three tiny colored dots show status at a glance. Each dot follows rules you define: number ranges, regex, gradients that fade from transparent to a color as a value rises.
  • Fonts, sizes and colors per item • xbar/SwiftBar-compatible output (colors, links, submenus) • Ready-made recipes: CPU, memory, battery, disk, IPs, Bitcoin price, clock • Notifications when a value or color changes • Hotkeys, launch at login, URL scheme for automation • Combine all items into one compact menu bar slot
  Minimal by design: under 1 MB, ~15 MB of memory, near-zero CPU.
- **App Review notes**: DotBar runs user-provided shell commands via /bin/zsh inside the App Sandbox; it ships with example recipes (uptime, vm_stat, pmset, df, curl to api.coinbase.com). The network.client entitlement is only used by those user scripts (e.g. curl for prices, weather). The calendar entitlement is used only when the user adds the Calendar recipe. No private APIs, no analytics.
- **Screenshots**: 2880×1800 or 1440×900 PNG, at least one. Suggested: menu bar close-up with the BTC + C/M dots item, the dropdown menu, and the Preferences window.

## Sandbox limits (App Store build only)
Denied inside the sandbox: `top`, `ps`, `ping`, `ipconfig getifaddr`, `git`. Recipes adapt automatically
(CPU % from load average / core count, local IP via `ifconfig`); Ping, Git Branch and Wi‑Fi SSID recipes are hidden.
The Homebrew build is not sandboxed and has no such limits.
