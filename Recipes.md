# DotBar Recipes

Ready-made menu bar items. In Preferences, click the ✨ button next to **+ / −** and pick one —
it is appended to your list and selected for editing. Every command below is plain
`/bin/zsh -c`, needs no extra tools (no `jq`), and was verified on macOS 26.

## Output convention

A script's stdout is used as the item's text. If the output starts with `{` it is parsed as JSON
and may override text, text color and dot colors:

```json
{"text": "42%", "color": "#FF9F0A", "dots": ["#34C759", "#FF453A"]}
```

All three keys are optional. `color` and each entry of `dots` is a `#RRGGBB` or `#RRGGBBAA` hex
string. Anything that is not JSON is treated as plain text, and dot colors then come from the
rules you set in the editor (range / regex / contains / equals / empty / script failed).

Three more keys control how the item is drawn for that update:

| Key | Effect |
|---|---|
| `mode` | `textAndDots` (default), `dotsOnly`, `textOnly` or `symbolOnly` — wins over the item's **Display → Show** setting for this update |
| `badge` | string or number, max 3 characters — small pill at the top-right of the item. Omit or leave empty for no badge |
| `badgeColor` | `#RRGGBB` fill for the badge (default: system red) |

```json
{"text": "Inbox", "symbol": "tray.fill", "mode": "symbolOnly", "badge": 12, "badgeColor": "#FF9F0A"}
```

For the number-range rules, DotBar parses the **first number** in the output — so `"14%"`,
`"15.7 ms"` and `"$80574"` all work directly.

## xbar-compatible line params

Every output line — the bar line and each menu line — may end with ` | key=value` pairs, exactly
like an [xbar](https://xbarapp.com) / SwiftBar plugin. Values with spaces go in quotes.
Unknown keys are ignored, so existing xbar plugins keep working.

| Key | Effect |
|---|---|
| `color=` | `red`, `green`, `blue`, `orange`, `yellow`, `purple`, `pink`, `teal`, `gray`, `white`, `black`, `#RRGGBB`, or a `light,dark` pair like `black,white` |
| `font=` / `size=` | font family name / point size for that line |
| `href=` | clicking the line opens the URL |
| `bash=` + `param1=…paramN=` | clicking runs the command with those arguments |
| `terminal=true` | run `bash=` visibly in Terminal.app (default: silently) |
| `refresh=true` | refresh the item after the action ran |
| `length=N` | truncate the text to N characters with `…` |
| `trim=false` | keep leading/trailing whitespace |
| `emojize=false` | leave `:smile:` shortcodes alone (default: replaced, ~60 common codes) |
| `sfimage=` | SF Symbol shown before the line, e.g. `sfimage=bolt.fill` |
| `alternate=true` | this line replaces the previous one while ⌥ is held |
| `dropdown=false` | line is not shown in the menu |
| `tooltip=` | hover tooltip |
| `checked=true` | show a checkmark |
| `disabled=true` | greyed out, not clickable |
| `md=false`, `symbolize=false` | accepted and ignored |

On the **bar line**, `color=` sets the text colour (ANSI runs still win, the rule colour loses),
`sfimage=` sets the symbol, `length=` caps the width and `href=`/`bash=` override the left-click
action. Menu lines with neither `href=` nor `bash=` copy their plain text on click (params, ANSI
codes stripped).

**Submenus:** a menu line starting with `--` nests under the previous line; `----` nests one level
deeper, and so on. A line of `---` is a separator; `-----` is a separator inside a submenu.

---

## Recipes

### CPU Load — every 10s
Dots: green < 2, orange 2–6, red > 6.
```sh
uptime | sed -E 's/.*load averages?: ([0-9.,]+).*/\1/'
```

### Memory Used % — every 15s
Active + wired + compressed as a share of all pages. Dots: green < 70, orange 70–88, red > 88.
```sh
vm_stat | awk '/Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",f);gsub(/[^0-9]/,"",a);gsub(/[^0-9]/,"",i);gsub(/[^0-9]/,"",s);gsub(/[^0-9]/,"",w);gsub(/[^0-9]/,"",c); t=f+a+i+s+w+c; if (t>0) printf "%.0f%%", (a+w+c)*100/t}'
```

### Battery % — every 60s
Dots: red < 20, orange 20–50, green > 50.
```sh
pmset -g batt | grep -Eo '[0-9]+%' | head -1
```

### Public IP — every 300s
`-s4` forces IPv4; drop it if you want whichever address the route picks.
```sh
curl -s4 --max-time 8 ifconfig.me
```

### Local IP — every 60s
Change `en0` to `en1` etc. for a different interface.
```sh
ipconfig getifaddr en0 || echo "—"
```

### Wi-Fi SSID — every 60s
`airport -I` was removed in recent macOS; `ipconfig getsummary` still reports the SSID.
```sh
ipconfig getsummary en0 | awk -F ' SSID : ' '/ SSID : / {print $2; exit}'
```

### BTC / USD — every 60s
Coinbase spot price, extracted with `sed` only (no `jq`), truncated to whole dollars.
```sh
curl -s --max-time 8 https://api.coinbase.com/v2/prices/BTC-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/$\1/'
```
Swap `BTC-USD` for `ETH-USD`, `SOL-USD`, … for other pairs.

### BTC 3 digits + CPU/RAM dots
Text = first 3 digits of the BTC price. Dot 1 fades from transparent (≤40 %) to red (100 %) with CPU, dot 2 from transparent (≤50 %) to yellow with RAM. Uses the **Gradient** color mode: pick "Gradient", set the value range (40 → 100 / 50 → 100) and the two end colors; alpha is interpolated, so a `#RRGGBB00` start fades in.
```sh
# dot 1 (own script, every 10s)
top -l 1 -n 0 | awk '/CPU usage/ {printf "%.0f", $3+$5}'
# dot 2 (own script, every 15s): see "Memory used %" above, without the trailing %
```

### BTC 3 digits — every 60s
Only the first three digits of the price (`80574` → `805`). Compact, no `jq`.
```sh
curl -s --max-time 8 https://api.coinbase.com/v2/prices/BTC-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/\1/' | cut -c1-3
```

### Disk Free % — every 300s
Free space on `/` as a percentage. Dots: red < 10, orange 10–25, green > 25.
```sh
df -Pk / | awk 'NR==2{printf "%d%%", $4*100/($3+$4)}'
```

### Uptime — every 300s
```sh
uptime | sed -E 's/^.*up +([^,]*(, [0-9]+ (hours?|mins?))?),.*$/\1/'
```

### Git Branch — every 30s
**Edit the path** to point at your own repository.
```sh
git -C "$HOME/Projects/my-repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "—"
```

### Ping 1.1.1.1 — every 30s
Dots: green < 50 ms, orange 50–150 ms, red > 150 ms.
```sh
ping -c1 -W2000 1.1.1.1 | sed -nE 's/.*time=([0-9.]+).*/\1 ms/p' || echo "—"
```

### Clock — every 30s
Any `strftime` format works; see `man strftime`.
```sh
date +"%a %d %H:%M"
```

### Swap Used — every 30s
```sh
sysctl vm.swapusage | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | awk '{printf "%.0f MB", $1}'
```

### Load Average — every 10s (gradient dot 2 → 12)
```sh
sysctl -n vm.loadavg | awk '{print $2}'
```

### Prevent Sleep — every 30s
"On" while any process holds a sleep assertion (caffeinate, video calls).
```sh
pmset -g assertions | grep -Eq 'PreventUserIdleSystemSleep +1' && echo "☕︎ On" || echo "Off"
```

### Appearance — every 60s
```sh
defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light
```

### Displays — every 120s (Homebrew build)
```sh
system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution
```

### Bluetooth Battery — every 300s (Homebrew build)
First device that reports a battery level. `system_profiler` takes a few seconds, keep the interval long.
```sh
system_profiler SPBluetoothDataType 2>/dev/null | awk '/Battery Level/{print $NF; exit}'
```

### Time Machine — every 600s (Homebrew build)
```sh
tmutil latestbackup 2>/dev/null | sed -E 's/.*\/([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2}).*/\1 \2:\3/' | grep . || echo "no backup"
```

### VPN — every 30s (Homebrew build)
```sh
n=$(scutil --nc list | grep -c '(Connected)'); [ "$n" -gt 0 ] && echo "VPN on" || echo "VPN off"
```

### Network Throughput — every 3s (Homebrew build)
Download rate on en0 from two `netstat` samples.
```sh
a=$(netstat -ib | awk '/en0/{print $7; exit}'); sleep 1; b=$(netstat -ib | awk '/en0/{print $7; exit}'); echo "↓ $(( (b-a)/1024 )) KB/s"
```

### ETH / USD — every 60s
```sh
curl -s --max-time 8 https://api.coinbase.com/v2/prices/ETH-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/$\1/'
```

### Stock Quote — every 300s
Replace `AAPL` with any Yahoo Finance ticker.
```sh
curl -s --max-time 8 -A "Mozilla/5.0" "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=1d" | sed -n 's/.*"regularMarketPrice":\([0-9.]*\).*/\1/p' | head -1
```

### Exchange Rates — every 3600s
Bar shows 1 USD in VND. The dropdown has one submenu per base currency (USD, EUR, GBP, AUD, CNY, JPY, SGD, CAD, VND), each listing its 8 cross rates: 72 pairs from one request to open.er-api.com.
```sh
curl -s --max-time 8 "https://open.er-api.com/v6/latest/USD" | tr ',' '\n' | sed -nE 's/.*"(USD|VND|EUR|CNY|JPY|SGD|GBP|CAD|AUD)":([0-9.]+).*/\1 \2/p' | awk 'function f(v){ if (v>=1000) return sprintf("%\047.0f",v); if (v>=10) return sprintf("%.2f",v); if (v>=0.01) return sprintf("%.4f",v); return sprintf("%.6f",v) } {r[$1]=$2} END{ if (r["VND"]==0||r["USD"]==0) {print "—"; exit} n=split("USD EUR GBP AUD CNY JPY SGD CAD VND",c," "); printf "$ %s ₫\n", f(r["VND"]); for(i=1;i<=n;i++){ b=c[i]; printf "%s →\n", b; for(j=1;j<=n;j++){ q=c[j]; if (q==b) continue; printf "--%s/%s  %s\n", b, q, f(r[q]/r[b]) } } }'
```

### Gold XAU / USD — every 900s
```sh
curl -s --max-time 8 https://api.gold-api.com/price/XAU | sed -n 's/.*"price":\([0-9.]*\).*/\1/p'
```

### Weather — every 900s
Location from your IP; or `wttr.in/Hanoi?format=%t+%C`.
```sh
curl -s --max-time 8 "wttr.in/?format=%t+%C" || echo "—"
```

### Air Quality — every 1800s
US AQI from Open-Meteo, no key. Replace the coordinates.
```sh
curl -s --max-time 8 "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=10.82&longitude=106.63&current=us_aqi" | sed -n 's/.*"us_aqi":\([0-9]*\).*/\1/p'
```

### World Clock — every 30s
```sh
TZ="America/New_York" date +"NY %H:%M"
```

### Countdown — every 3600s
```sh
d=$(date -j -f "%Y-%m-%d" "2026-12-25" +%s); echo "$(( (d - $(date +%s)) / 86400 ))d"
```

## Recipes that need a third-party CLI (not built in)
```sh
gh api notifications 2>/dev/null | grep -c '"unread":true'          # GitHub unread notifications (gh)
brew outdated 2>/dev/null | wc -l | tr -d ' '                         # Homebrew outdated formulae
docker ps -q 2>/dev/null | wc -l | tr -d ' '                          # running Docker containers
osascript -e 'tell application "Music" to if player state is playing then get artist of current track & " – " & name of current track' 2>/dev/null
osascript -e 'tell application "Mail" to get unread count of inbox' 2>/dev/null
# GitHub Actions last run (needs a token; works in the sandbox because it is plain curl)
curl -s --max-time 8 -H "Authorization: token $GITHUB_TOKEN" "https://api.github.com/repos/OWNER/REPO/actions/runs?per_page=1" | sed -n 's/.*"conclusion":"\([a-z_]*\)".*/\1/p' | head -1
```

### Docker-ish Status Panel — every 30s (params + submenus)
Shows how inline params and `--` submenus fit together: a coloured bar line with an SF Symbol, a
submenu of actions, an ⌥ alternate line and a hidden line.
```sh
n=$(ls -1 "$HOME" | wc -l | tr -d ' ')
echo "Home: $n | color=green,white sfimage=folder length=14"
echo "---"
echo "Open Home | bash=\"open $HOME\" refresh=true"
echo "Open Home in Terminal | bash=\"cd $HOME && ls -la\" terminal=true alternate=true"
echo "Tools | sfimage=wrench"
echo "--Disk usage :bar_chart: | bash=\"du -sh $HOME\" terminal=true"
echo "--Docs on the web | href=https://xbarapp.com/docs/"
echo "-----"
echo "--Danger zone | color=red disabled=true"
echo "Bar only, never in the menu | dropdown=false"
```

### Ping stream — streaming
Turn on **Streaming** in the Source section: the command runs once and stays running, and every
`~~~` line closes an update block. Dots: green < 50 ms, orange 50–150 ms, red > 150 ms.
```sh
ping 1.1.1.1 | while read l; do echo "$l" | sed -nE 's/.*time=([0-9.]+).*/\1 ms/p'; echo '~~~'; done
```

### Log tail — streaming
**Edit the path** to a log file you actually have; `tail -F` keeps following it across rotations.
```sh
tail -F "$HOME/Library/Logs/example.log" | while read l; do echo "${l:0:40}"; echo '~~~'; done
```

---

## Streaming items

A streaming item launches its command **once** and keeps it running, instead of re-running it on a
timer. Every block of output replaces the item's text, so updates arrive the moment the script
prints them.

- End each update block with a line that is exactly `~~~`.
- A script that never prints `~~~` still works: each line is then one update, so
  `while true; do date; sleep 1; done` ticks once a second.
- A block is parsed exactly like normal script output — plain text, JSON, xbar params, menu lines.
- If the process exits on its own, DotBar restarts it with a growing delay (2s, 4s, … up to 60s).
- **Refresh** (menu or hotkey) restarts the process. Disabling the item, sleep and quitting stop it
  for good — nothing is left running behind the app.
- There is no refresh interval for a streaming item, and the sidebar shows **Stream**.

---

## Environment

Every script runs with these variables set:

| Variable | Value |
| --- | --- |
| `DOTBAR_ITEM_NAME` | The item's name |
| `DOTBAR_ITEM_ID` | The item's UUID |
| `DOTBAR_APPEARANCE` | `dark` or `light` |
| `DOTBAR_REFRESH_SECONDS` | Current refresh interval |
| `DOTBAR_LAST_RUN` | Unix seconds of the previous run, empty on the first |
| `DOTBAR_LAST_WAKE` | Unix seconds of the last system wake, empty if none yet |
| `DOTBAR_VERSION` | DotBar version |
| `DOTBAR_PREVIOUS_TEXT` | Previous bar text (max 512 chars) |

```sh
[ "$DOTBAR_APPEARANCE" = dark ] && echo '{"text":"OK","color":"#8AE234"}' || echo '{"text":"OK","color":"#2E7D32"}'
```

All items re-run once whenever the system appearance flips.

## Control from outside

DotBar registers the `dotbar://` URL scheme, so any script, Shortcut or app can drive it:

```sh
open "dotbar://refresh"                          # every item
open "dotbar://refresh?name=CPU%20Load"          # one item, by name (case-insensitive)
open "dotbar://refresh?id=<uuid>"                # one item, by id
open "dotbar://set?name=Build&text=passing"      # push text in, as if the script printed it
open "dotbar://set?name=Build&text=%7B%22text%22%3A%22FAIL%22%2C%22color%22%3A%22%23FF453A%22%7D"
open "dotbar://enable?name=Build&value=false"    # disable (value=true to re-enable)
open "dotbar://prefs"                            # open Preferences
```

`set` accepts the same JSON as script output when the text starts with `{` (URL-encode it).

## Power and scheduling

- At launch each item's first run is offset by 0.7s per item (max 5s) so scripts do not all fork at once.
- Timers pause while the Mac sleeps and are re-created on wake, just before the catch-up refresh.
- In Low Power Mode, intervals under a minute run 3x slower (at least 30s). Turn this off in the gear
  popover in Preferences.
- A new run never starts while the previous run of the same item (or dot) is still going.

## The scripts folder

Drop scripts in `~/Library/Application Support/DotBar/scripts` and DotBar re-runs items using them
when they change. The folder is created at launch; any item whose command mentions a path inside it
is refreshed (streams are restarted) about half a second after you save the file, so editing a
script is enough to see the new output.

`items.json` in the same folder is watched too: edit it with another editor, or have a script
rewrite it, and DotBar reloads the items without you restarting the app.


## Using a script file

In the item editor's **Script** section, the **…** button opens a file picker. The chosen path is
inserted quoted; if the file is not executable it is prefixed with `/bin/zsh `, so both
`chmod +x` scripts and plain `.sh` files work without further editing.

## Writing your own

- Keep it fast — it runs on every refresh. Prefer a longer interval over a heavy command.
- Print one short line; DotBar trims surrounding whitespace.
- A non-zero exit or a timeout (15s) keeps the previous text and fires the **Script failed** rule.
- No `jq` on a stock Mac: use `sed -E`, `grep -o` or `awk` to pull a field out of JSON.
