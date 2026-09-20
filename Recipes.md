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

For the number-range rules, DotBar parses the **first number** in the output — so `"14%"`,
`"15.7 ms"` and `"$80574"` all work directly.

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

## Using a script file

In the item editor's **Script** section, the **…** button opens a file picker. The chosen path is
inserted quoted; if the file is not executable it is prefixed with `/bin/zsh `, so both
`chmod +x` scripts and plain `.sh` files work without further editing.

## Writing your own

- Keep it fast — it runs on every refresh. Prefer a longer interval over a heavy command.
- Print one short line; DotBar trims surrounding whitespace.
- A non-zero exit or a timeout (15s) keeps the previous text and fires the **Script failed** rule.
- No `jq` on a stock Mac: use `sed -E`, `grep -o` or `awk` to pull a field out of JSON.
