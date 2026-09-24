import Foundation

/// Ready-made items the user can drop into the menu bar from Preferences.
/// Every command is verified against /bin/zsh -c with ScriptRunner's PATH.
enum Recipes {

    /// Fresh UUIDs on every call, so a recipe can be added more than once.
    /// Mac App Store build runs inside the App Sandbox: `top`, `ps`, `ping`, `ipconfig getifaddr`, `git` are denied there.
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// CPU % : `iostat` over one second outside the sandbox (≈0.01 s CPU per run; `top -l 1`
    /// cost ≈0.75 s, run every few seconds by several recipes), 1-minute load average / core
    /// count inside it.
    static var cpuPercentCommand: String {
        isSandboxed
            ? #"awk -v l="$(sysctl -n vm.loadavg | awk '{print $2}')" -v n="$(sysctl -n hw.ncpu)" 'BEGIN{p=l/n*100; if(p>100)p=100; printf "%.0f", p}'"#
            : #"iostat -c 2 -w 1 | tail -1 | awk '{printf "%.0f", 100 - $(NF-3)}'"#
    }
    /// Menu lines listing the top 5 processes by CPU (`pcpu`) or memory (`rss`); `ps` is denied in the sandbox.
    static func topProcesses(byMemory: Bool) -> String {
        guard !isSandboxed else { return "" }
        return byMemory
            ? #"; echo "Top memory | disabled=true"; ps -Aceo rss=,comm= -m | head -5 | awk '{m=$1; $1=""; printf "%.0f MB  %s\n", m/1024, substr($0,2)}'"#
            : #"; echo "Top CPU | disabled=true"; ps -Aceo pcpu=,comm= -r | head -5 | awk '{p=$1; $1=""; printf "%.1f%%  %s\n", p, substr($0,2)}'"#
    }
    static var localIPCommand: String {
        isSandboxed ? #"ifconfig en0 | awk '/inet /{print $2}'"# : #"ipconfig getifaddr en0"#
    }

    /// Recipes whose commands the App Sandbox denies (ping raw sockets, git via xcrun, ipconfig SSID).
    private static let sandboxUnavailable: Set<String> = ["AI Usage Icon (Claude)", "AI Usage Icon (Codex)", "Now Playing", "Ping 1.1.1.1", "Ping stream", "Git Branch", "Wi-Fi SSID",
                                                          "Network Throughput", "VPN", "Time Machine", "Displays", "Bluetooth Battery"]

    /// Every preset, sorted A→Z by name (the Preferences "+" menu and `dotbar recipes` list them
    /// in this order). Grouped below only to keep the source readable.
    static func all() -> [Item] {
        [// System
         cpuUsage, cpuLoad, memoryUsed, swapUsed, loadAverage, battery, batteryWithLoadDots, diskFree, uptime, caffeinate, darkMode, displays, bluetoothBattery, timeMachine,
         // Network
         publicIP, localIP, wifiSSID, vpn, networkThroughput, ping,
         // Finance
         btcPrice, btc3Digits, ethPrice, stockQuote, exchangeRates, goldPrice,
         // Weather & time
         weather, airQuality, clock, calendarIcon, worldClock, countdown, pomodoro,
         // Media & AI
         nowPlaying, aiUsage, codexUsage,
         // Dev & streaming
         gitBranch, pingStream, logTail]
            .filter { !isSandboxed || !sandboxUnavailable.contains($0.name) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Recipes

    private static var cpuLoad: Item {
        var i = Item(name: "CPU Load",
                     source: .script(command: #"uptime | sed -E 's/.*load averages?: ([0-9.,]+).*/\1/'"#,
                                     refreshSeconds: 10))
        i.dots = [dot(ranges: [(nil, 2, green), (2, 6, orange), (6, nil, red)])]
        return i
    }

    private static var memoryUsed: Item {
        let cmd = #"vm_stat | awk '/Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",f);gsub(/[^0-9]/,"",a);gsub(/[^0-9]/,"",i);gsub(/[^0-9]/,"",s);gsub(/[^0-9]/,"",w);gsub(/[^0-9]/,"",c); t=f+a+i+s+w+c; if (t>0) printf "%.0f%%", (a+w+c)*100/t}'"#
        var i = Item(name: "Memory Used", source: .script(command: cmd + "; echo" + topProcesses(byMemory: true), refreshSeconds: 15))
        i.dots = [dot(ranges: [(nil, 70, green), (70, 88, orange), (88, nil, red)])]
        i.sparkline = 30
        return i
    }

    /// Upright battery icon only (saves width); % and state are in the menu. Hidden without a battery.
    private static var batteryIcon: Item {   // base of batteryWithLoadDots
        var i = Item(name: "Battery Icon",
                     source: .script(command: #"lp=$(pmset -g | awk '/lowpowermode/{print $2}'); pmset -g batt | awk -F'\t' -v lp="$lp" '/AC Power/{ac=1} /InternalBattery/{split($2,a,"; "); p=a[1]+0; s=a[2]; t=a[3]; sub(/ *present.*/,"",t); c=(s=="charging"||s=="finishing charge")?":charging":(ac?":plugged":""); if (lp==1) c=c ":lowpower"; m="\"" p "% — " s "\""; if (t!="" && t !~ /^0:00/ && t !~ /no estimate/) m=m ",\"" t "\""; if (lp==1) m=m ",\"Low Power Mode on\""; printf "{\"text\":\"\",\"symbol\":\"battery:%d%s\",\"menu\":[%s]}\n", p, c, m}'"#, refreshSeconds: 60))
        i.hideWhenEmpty = true
        i.paddingLeft = 0; i.paddingRight = 0
        // Health details only when the menu opens (cached, refreshed in the background).
        i.menuCommand = #"ioreg -rn AppleSmartBattery | awk '/"CycleCount" =/{cc=$NF} /"ExternalConnected" =/{ext=$NF} /"IsCharging" =/{chg=$NF} /"FullyCharged" =/{full=$NF} /"BatteryData" =/{ if (match($0, /"DesignCapacity"=[0-9]+/)) d=substr($0, RSTART+17, RLENGTH-17); if (match($0, /"NominalChargeCapacity"=[0-9]+/)) n=substr($0, RSTART+24, RLENGTH-24) } END{ if (cc == "") exit; if (d > 0) { h=int(n*100/d+0.5); printf "Maximum capacity: %d%%%s\n", h, (h < 80 ? " — Service Recommended" : "") } printf "Cycle count: %d\n", cc; if (ext == "Yes" && chg == "No" && full == "No") print "Charging on hold" }'"#
        return i
    }

    /// CPU % with a 30-sample sparkline; the menu lists the top processes.
    private static var cpuUsage: Item {
        var i = Item(name: "CPU Usage",
                     source: .script(command: #"echo "$("# + cpuPercentCommand + #")%""# + topProcesses(byMemory: false),
                                     refreshSeconds: 5))
        i.dots = [dot(ranges: [(nil, 50, green), (50, 80, orange), (80, nil, red)])]
        i.sparkline = 30
        return i
    }

    private static var battery: Item {
        var i = Item(name: "Battery Text",
                     source: .script(command: #"pmset -g batt | grep -Eo '[0-9]+%' | head -1"#,
                                     refreshSeconds: 60))
        i.dots = [dot(ranges: [(nil, 20, red), (20, 50, orange), (50, nil, green)])]
        return i
    }

    private static var publicIP: Item {
        Item(name: "Public IP",
             source: .script(command: #"curl -s4 --max-time 8 ifconfig.me"#, refreshSeconds: 300))
    }

    private static var localIP: Item {
        Item(name: "Local IP",
             source: .script(command: localIPCommand + #" || echo "—""#, refreshSeconds: 60))
    }

    private static var wifiSSID: Item {
        Item(name: "Wi-Fi SSID",
             source: .script(command: #"ipconfig getsummary en0 | awk -F ' SSID : ' '/ SSID : / {print $2; exit}'"#,
                             refreshSeconds: 60))
    }

    private static var btcPrice: Item {
        // No jq on a stock macOS: pull "amount":"12345.67" out with sed alone.
        let cmd = #"curl -s --max-time 8 https://api.coinbase.com/v2/prices/BTC-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/$\1/'"#
        return Item(name: "BTC/USD", source: .script(command: cmd, refreshSeconds: 60))
    }

    private static var btc3Digits: Item {
        // Leading 3 digits only (e.g. 80574 -> "805"): compact, still tells you where BTC is.
        let cmd = #"curl -s --max-time 8 https://api.coinbase.com/v2/prices/BTC-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/\1/' | cut -c1-3"#
        var i = Item(name: "BTC 3 digits", source: .script(command: cmd, refreshSeconds: 60))
        i.font.monospacedDigits = true
        // Menu: full price and the 24h change in $ and %, fetched only when the menu opens.
        i.menuCommand = #"curl -s --max-time 8 https://api.exchange.coinbase.com/products/BTC-USD/stats | tr ',' '\n' | sed -nE 's/.*"(open|last)":"([0-9.]+)".*/\1 \2/p' | awk 'function fmt(v,  s,ip,fp,out){ s=sprintf("%.2f", v); ip=substr(s, 1, index(s, ".")-1); fp=substr(s, index(s, ".")); out=""; while (length(ip) > 3) { out="," substr(ip, length(ip)-2) out; ip=substr(ip, 1, length(ip)-3) } return ip out fp } {v[$1]=$2} END{ if (v["last"] == "" || v["open"] == 0) { print "—"; exit } d=v["last"]-v["open"]; p=d*100/v["open"]; printf "BTC/USD  $%s\n", fmt(v["last"]); printf "24h  %s $%s  (%s%.2f%%) | color=%s\n", (d >= 0 ? "▲" : "▼"), fmt(d < 0 ? -d : d), (d >= 0 ? "+" : "−"), (p < 0 ? -p : p), (d >= 0 ? "green" : "red") }'"#
        return i
    }

    /// First 3 digits of the BTC price as text; dot 1 fades transparent -> red with CPU %, dot 2 transparent -> yellow with RAM %.
    /// Battery icon with CPU (C) and RAM (M) dots that fade in above 40 % / 50 %.
    static var batteryWithLoadDots: Item {
        let ram = #"vm_stat | awk '/Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",f);gsub(/[^0-9]/,"",a);gsub(/[^0-9]/,"",i);gsub(/[^0-9]/,"",s);gsub(/[^0-9]/,"",w);gsub(/[^0-9]/,"",c); t=f+a+i+s+w+c; if (t>0) printf "%.0f", (a+w+c)*100/t}'"#
        var i = batteryIcon
        i.name = "Battery + CPU/RAM dots"
        // Menu adds CPU and RAM (share of physical memory, as Activity Monitor's "Memory Used").
        // Hovering either opens a submenu with its top 10 processes and a "Copy list" row
        // (not in the sandbox: `ps` is denied there).
        let cpuTop = isSandboxed ? "" : #"; ps -Aceo pcpu=,comm= -r | head -10 | awk '{p=$1; $1=""; printf "--%5.1f%%  %s\n", p, substr($0,2)}'; echo "-----"; echo "--Copy list | bash=/bin/zsh param1=-c param2='ps -Aceo pcpu,comm -r | head -11 | pbcopy'""#
        let ramTop = isSandboxed ? "" : #"; ps -Aceo rss=,comm= -m | head -10 | awk '{m=$1; $1=""; printf "--%6.0f MB  %s\n", m/1024, substr($0,2)}'; echo "-----"; echo "--Copy list | bash=/bin/zsh param1=-c param2='{ echo \"    MB  COMMAND\"; ps -Aceo rss=,comm= -m | head -10 | while read k c; do printf \"%6d  %s\\\\n\" \$((k/1024)) \"\$c\"; done; } | pbcopy'""#
        let ramLine = #"vm_stat | awk -v total="$(sysctl -n hw.memsize)" '/page size of/{ps=$8} /Pages active/{a=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",a); gsub(/[^0-9]/,"",w); gsub(/[^0-9]/,"",c); u=(a+w+c)*ps; printf "RAM %.0f%%  (%.1f / %.0f GB)", u*100/total, u/1073741824, total/1073741824}'"#
        i.menuCommand += #"; echo "CPU $("# + cpuPercentCommand + #")%""# + cpuTop + #"; echo "$("# + ramLine + #")""# + ramTop
        i.hideWhenEmpty = false          // no battery: the icon is simply absent, the dots stay
        i.dots = [
            Dot(source: .script(command: cpuPercentCommand, refreshSeconds: 10),
                color: .gradient(min: 40, max: 100, from: "#FF453A00", to: "#FF453A"), label: "C"),
            Dot(source: .script(command: ram, refreshSeconds: 15),
                color: .gradient(min: 50, max: 100, from: "#FFD60A00", to: "#FFD60A"), label: "M"),
        ]
        i.dotSize = 7
        return i
    }

    private static var diskFree: Item {
        var i = Item(name: "Disk Free",
                     source: .script(command: #"df -Pk / | awk 'NR==2{printf "%d%%", $4*100/($3+$4)}'"#,
                                     refreshSeconds: 300))
        i.dots = [dot(ranges: [(nil, 10, red), (10, 25, orange), (25, nil, green)])]
        return i
    }

    private static var uptime: Item {
        Item(name: "Uptime",
             source: .script(command: #"uptime | sed -E 's/^.*up +([^,]*(, [0-9]+ (hours?|mins?))?),.*$/\1/'"#,
                             refreshSeconds: 300))
    }

    private static var gitBranch: Item {
        // Edit the path to your own repo.
        let cmd = #"git -C "$HOME/Projects/my-repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "—""#
        return Item(name: "Git Branch", source: .script(command: cmd, refreshSeconds: 30))
    }

    private static var ping: Item {
        var i = Item(name: "Ping 1.1.1.1",
                     source: .script(command: #"ping -c1 -W2000 1.1.1.1 | sed -nE 's/.*time=([0-9.]+).*/\1 ms/p' || echo "—""#,
                                     refreshSeconds: 30))
        i.dots = [dot(ranges: [(nil, 50, green), (50, 150, orange), (150, nil, red)])]
        return i
    }

    private static var clock: Item {
        Item(name: "Clock",
             source: .script(command: #"date +"%a %d %H:%M""#, refreshSeconds: 30))
    }

    // MARK: - Streaming recipes

    /// Streaming: one long-lived `ping`, one update per reply (`~~~` closes each block).
    private static var pingStream: Item {
        let cmd = #"ping 1.1.1.1 | while read l; do echo "$l" | sed -nE 's/.*time=([0-9.]+).*/\1 ms/p'; echo '~~~'; done"#
        var i = Item(name: "Ping stream", source: .stream(command: cmd))
        i.dots = [dot(ranges: [(nil, 50, green), (50, 150, orange), (150, nil, red)])]
        return i
    }

    /// Streaming: last line of a growing log file. Point it at a log you actually have.
    private static var logTail: Item {
        let cmd = #"tail -F "$HOME/Library/Logs/example.log" | while read l; do echo "${l:0:40}"; echo '~~~'; done"#
        return Item(name: "Log tail", source: .stream(command: cmd))
    }


    // MARK: - System (added 0.1.14)

    private static var swapUsed: Item {
        var i = Item(name: "Swap Used",
                     source: .script(command: #"sysctl vm.swapusage | sed -n 's/.*used = \([0-9.]*\)M.*/\1/p' | awk '{printf "%.0f MB", $1}'"#,
                                     refreshSeconds: 30))
        i.dots = [dot(ranges: [(nil, 1024, green), (1024, 4096, orange), (4096, nil, red)])]
        return i
    }

    private static var loadAverage: Item {
        var i = Item(name: "Load Average",
                     source: .script(command: #"sysctl -n vm.loadavg | awk '{print $2}'"#, refreshSeconds: 10))
        i.dots = [Dot(color: .gradient(min: 2, max: 12, from: "#34C759", to: "#FF453A"))]
        return i
    }

    /// "On" while something holds a PreventUserIdleSystemSleep assertion (caffeinate, a video call, …).
    private static var caffeinate: Item {
        var i = Item(name: "Prevent Sleep",
                     source: .script(command: #"pmset -g assertions | grep -Eq 'PreventUserIdleSystemSleep +1' && echo "☕︎ On" || echo "Off""#,
                                     refreshSeconds: 30))
        i.dots = [Dot(color: .rules([Rule(condition: .contains(text: "On"), color: orange)], fallback: "#8E8E93"))]
        return i
    }

    private static var darkMode: Item {
        Item(name: "Appearance",
             source: .script(command: #"defaults read -g AppleInterfaceStyle 2>/dev/null || echo Light"#, refreshSeconds: 60))
    }

    private static var displays: Item {
        Item(name: "Displays",
             source: .script(command: #"system_profiler SPDisplaysDataType 2>/dev/null | grep -c Resolution | sed 's/$/ 🖥/'"#,
                             refreshSeconds: 120))
    }

    /// First Bluetooth device reporting a battery level (AirPods, Magic Mouse, …). system_profiler is slow: keep the interval long.
    private static var bluetoothBattery: Item {
        var i = Item(name: "Bluetooth Battery",
                     source: .script(command: #"system_profiler SPBluetoothDataType 2>/dev/null | awk '/Battery Level/{print $NF; exit}'"#,
                                     refreshSeconds: 300))
        i.dots = [dot(ranges: [(nil, 20, red), (20, 50, orange), (50, nil, green)])]
        i.symbol = "headphones"
        return i
    }

    private static var timeMachine: Item {
        Item(name: "Time Machine",
             source: .script(command: #"tmutil latestbackup 2>/dev/null | sed -E 's/.*\/([0-9]{4}-[0-9]{2}-[0-9]{2})-([0-9]{2})([0-9]{2}).*/\1 \2:\3/' | grep . || echo "no backup""#,
                             refreshSeconds: 600))
    }

    // MARK: - Network (added 0.1.14)

    private static var vpn: Item {
        var i = Item(name: "VPN",
                     source: .script(command: #"n=$(scutil --nc list | grep -c '(Connected)'); [ "$n" -gt 0 ] && echo "VPN on" || echo "VPN off""#,
                                     refreshSeconds: 30))
        i.dots = [Dot(color: .rules([Rule(condition: .contains(text: "on"), color: green)], fallback: "#8E8E93"))]
        return i
    }

    /// Download rate on en0: two netstat samples one second apart.
    private static var networkThroughput: Item {
        var i = Item(name: "Network Throughput",
                     source: .script(command: #"a=$(netstat -ib | awk '/en0/{print $7; exit}'); sleep 1; b=$(netstat -ib | awk '/en0/{print $7; exit}'); kb=$(( (b-a)/1024 )); [ $kb -ge 1024 ] && printf "↓ %.1f MB/s" $(echo "$kb/1024" | bc -l) || echo "↓ $kb KB/s""#,
                                     refreshSeconds: 3))
        i.dots = [Dot(color: .gradient(min: 0, max: 5000, from: "#34C75940", to: "#0A84FF"))]
        return i
    }

    // MARK: - Finance (added 0.1.14)

    private static var ethPrice: Item {
        Item(name: "ETH/USD",
             source: .script(command: #"curl -s --max-time 8 https://api.coinbase.com/v2/prices/ETH-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/$\1/'"#,
                             refreshSeconds: 60))
    }

    /// Change AAPL to any Yahoo Finance ticker (VNM, NVDA, ^GSPC, VN30F1M.VN …).
    private static var stockQuote: Item {
        Item(name: "Stock Quote (AAPL)",
             source: .script(command: #"curl -s --max-time 8 -A "Mozilla/5.0" "https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=1d" | sed -n 's/.*"regularMarketPrice":\([0-9.]*\).*/\1/p' | head -1 | awk '{printf "AAPL %.2f", $1}'"#,
                             refreshSeconds: 300))
    }

    /// Bar: the B/Q pair set at the start of the command (edit B= and Q=). Menu: one submenu per base currency with all 8 cross rates → 72 pairs.
    private static var exchangeRates: Item {
        let cmd = #"B=EUR; Q=USD; curl -s --max-time 8 "https://open.er-api.com/v6/latest/USD" | tr ',' '\n' | sed -nE 's/.*"(USD|VND|EUR|CNY|JPY|SGD|GBP|CAD|AUD)":([0-9.]+).*/\1 \2/p' | awk -v b="$B" -v q="$Q" 'function f(v){ if (v>=1000) return sprintf("%\047.0f",v); if (v>=10) return sprintf("%.2f",v); if (v>=0.01) return sprintf("%.4f",v); return sprintf("%.6f",v) } {r[$1]=$2} END{ if (r[b]==0||r[q]==0) {print "—"; exit} n=split("USD EUR GBP AUD CNY JPY SGD CAD VND",c," "); printf "%s/%s %s\n", b, q, f(r[q]/r[b]); for(i=1;i<=n;i++){ x=c[i]; printf "%s →\n", x; for(j=1;j<=n;j++){ y=c[j]; if (y==x) continue; printf "--%s/%s  %s\n", x, y, f(r[y]/r[x]) } } }'"#
        var i = Item(name: "Exchange Rates", source: .script(command: cmd, refreshSeconds: 3600))
        i.font.monospacedDigits = true
        return i
    }

    private static var goldPrice: Item {
        Item(name: "Gold XAU/USD",
             source: .script(command: #"curl -s --max-time 8 https://api.gold-api.com/price/XAU | sed -n 's/.*"price":\([0-9.]*\).*/\1/p' | awk '{printf "Au $%\047.0f", $1}'"#,
                             refreshSeconds: 900))
    }

    // MARK: - Weather & time (added 0.1.14)

    /// wttr.in picks your location from the IP. Append a city: wttr.in/Hanoi?format=…
    private static var weather: Item {
        Item(name: "Weather",
             source: .script(command: #"curl -s --max-time 8 "wttr.in/?format=%t+%C" | sed 's/^+//' || echo "—""#,
                             refreshSeconds: 900))
    }

    /// Replace the coordinates with yours (default: Ho Chi Minh City).
    private static var airQuality: Item {
        var i = Item(name: "Air Quality (US AQI)",
                     source: .script(command: #"curl -s --max-time 8 "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=10.82&longitude=106.63&current=us_aqi" | sed -n 's/.*"us_aqi":\([0-9]*\).*/AQI \1/p'"#,
                                     refreshSeconds: 1800))
        i.dots = [dot(ranges: [(nil, 50, green), (50, 100, "#FFD60A"), (100, 150, orange), (150, nil, red)])]
        return i
    }

    /// Single calendar page: weekday in the header, day number below.
    /// C= header colour: red, blue, any name or #hex; empty = subtle monochrome.
    static var calendarIcon: Item {
        var i = Item(name: "Calendar Icon",
                     source: .script(command: #"C=black; date +'{"text":"","symbol":"calendar:%-d:%a:'"$C"'"}'"#, refreshSeconds: 60))
        i.action = .calendar
        i.paddingLeft = 0; i.paddingRight = 0
        return i
    }

    private static var worldClock: Item {
        Item(name: "World Clock (New York)",
             source: .script(command: #"TZ="America/New_York" date +"NY %H:%M""#, refreshSeconds: 30))
    }

    /// Days left until a date. Edit the date.
    /// Claude session (5 h) and weekly usage as two bars; the menu has % and reset times.
    /// Reads Claude Code's own sign-in (Keychain, or ~/.claude/.credentials.json) and calls the
    /// usage endpoint Claude Code uses. Every 3 min: usage moves slowly.
    static var aiUsage: Item {
        var i = Item(name: "AI Usage Icon (Claude)",
                     source: .script(command: #"c=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || cat "$HOME/.claude/.credentials.json" 2>/dev/null); t=$(printf %s "$c" | plutil -extract claudeAiOauth.accessToken raw -o - - 2>/dev/null); [ -z "$t" ] && { echo '{"text":"","symbol":"usage:0:0:Claude","menu":["Sign in to Claude Code to see usage | disabled=true"]}'; exit 0; }; j=$(curl -s --max-time 8 https://api.anthropic.com/api/oauth/usage -H "Authorization: Bearer $t" -H "anthropic-beta: oauth-2025-04-20"); g() { printf %s "$j" | plutil -extract "$1" raw -o - - 2>/dev/null; }; s=$(g five_hour.utilization); w=$(g seven_day.utilization); [ -z "$s$w" ] && { echo '{"text":"","symbol":"usage:0:0:Claude","menu":["Usage unavailable — open Claude Code to refresh the sign-in | disabled=true"]}'; exit 0; }; at() { d=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${1%%.*}" +%s 2>/dev/null) && date -r "$d" "$2"; }; left() { d=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${1%%.*}" +%s 2>/dev/null) || return; m=$(( (d - $(date +%s)) / 60 )); [ $m -lt 0 ] && m=0; printf "%dh %02dm" $((m / 60)) $((m % 60)); }; sr=$(g five_hour.resets_at); wr=$(g seven_day.resets_at); printf '{"text":"","symbol":"usage:%.0f:%.0f:Claude","menu":["Session %.0f%%  ·  resets in %s","Weekly %.0f%%  ·  resets %s","---","Open usage page | href=https://claude.ai/settings/usage"]}\n' "$s" "$w" "$s" "$(left "$sr")" "$w" "$(at "$wr" "+%a %H:%M")""#, refreshSeconds: 180))
        i.paddingLeft = 0; i.paddingRight = 0
        return i
    }

    /// Codex (ChatGPT plan) session (5 h) and weekly usage, same two bars. Reads Codex CLI's
    /// sign-in (~/.codex/auth.json) and the usage endpoint behind its /status.
    static var codexUsage: Item {
        var i = Item(name: "AI Usage Icon (Codex)",
                     source: .script(command: #"f="$HOME/.codex/auth.json"; t=$(plutil -extract tokens.access_token raw -o - "$f" 2>/dev/null); a=$(plutil -extract tokens.account_id raw -o - "$f" 2>/dev/null); [ -z "$t" ] && { echo '{"text":"","symbol":"usage:0:0:Codex","menu":["Sign in to Codex CLI to see usage | disabled=true"]}'; exit 0; }; j=$(curl -s --max-time 8 https://chatgpt.com/backend-api/wham/usage -H "Authorization: Bearer $t" -H "ChatGPT-Account-Id: $a" -H "User-Agent: codex_cli_rs"); g() { printf %s "$j" | plutil -extract "$1" raw -o - - 2>/dev/null; }; s=$(g rate_limit.primary_window.used_percent); w=$(g rate_limit.secondary_window.used_percent); [ -z "$s$w" ] && { echo '{"text":"","symbol":"usage:0:0:Codex","menu":["Usage unavailable — run codex once to refresh the sign-in | disabled=true"]}'; exit 0; }; sr=$(g rate_limit.primary_window.reset_after_seconds); wr=$(g rate_limit.secondary_window.reset_at); m=$(( ${sr:-0} / 60 )); printf '{"text":"","symbol":"usage:%.0f:%.0f:Codex","menu":["Session %.0f%%  ·  resets in %dh %02dm","Weekly %.0f%%  ·  resets %s","---","Open usage page | href=https://chatgpt.com/codex/settings/usage"]}\n' "${s:-0}" "${w:-0}" "${s:-0}" $((m / 60)) $((m % 60)) "${w:-0}" "$( [ -n "$wr" ] && date -r "$wr" "+%a %H:%M")""#, refreshSeconds: 180))
        i.paddingLeft = 0; i.paddingRight = 0
        return i
    }

    /// 25-minute focus timer: click to start / stop. State is one file holding the end time.
    private static var pomodoro: Item {
        let f = #"f="$HOME/.dotbar-pomodoro"; "#
        var i = Item(name: "Pomodoro",
                     source: .script(command: f + #"if [ -f "$f" ]; then r=$(( $(cat "$f") - $(date +%s) )); if [ $r -gt 0 ]; then echo "🍅 $(( (r + 59) / 60 ))m"; else echo "🍅 Break"; fi; else echo "🍅"; fi"#,
                                     refreshSeconds: 15))
        i.action = .script(command: f + #"if [ -f "$f" ]; then rm "$f"; else echo $(( $(date +%s) + 25 * 60 )) > "$f"; fi"#)
        return i
    }

    /// Track playing in Music or Spotify; hidden when nothing plays. Click = play / pause.
    /// Never launches either app (`is running` guard). Needs Automation permission once.
    private static var nowPlaying: Item {
        let track = #"if player state is playing then return "♫ " & name of current track & " — " & artist of current track"#
        var i = Item(name: "Now Playing",
                     source: .script(command: #"osascript -e 'if application "Music" is running then tell application "Music" to "# + track + #"' -e 'if application "Spotify" is running then tell application "Spotify" to "# + track + #"' -e 'return ""'"#,
                                     refreshSeconds: 5))
        i.action = .script(command: #"osascript -e 'if application "Spotify" is running then tell application "Spotify" to playpause' -e 'if application "Music" is running then tell application "Music" to playpause'"#)
        i.hideWhenEmpty = true
        i.maxWidth = 200
        return i
    }

    private static var countdown: Item {
        var i = Item(name: "Countdown",
                     source: .script(command: #"d=$(date -j -f "%Y-%m-%d" "2026-12-25" +%s); echo "$(( (d - $(date +%s)) / 86400 ))d""#,
                                     refreshSeconds: 3600))
        i.dots = [dot(ranges: [(nil, 7, red), (7, 30, orange), (30, nil, green)])]
        return i
    }

    // MARK: - Helpers

    private static let green = "#34C759"
    private static let orange = "#FF9F0A"
    private static let red = "#FF453A"
    private static let grey = "#8E8E93"

    private static func dot(ranges: [(Double?, Double?, HexColor)]) -> Dot {
        var rules = ranges.map { Rule(condition: .numberInRange(min: $0.0, max: $0.1), color: $0.2) }
        rules.append(Rule(condition: .scriptFailed, color: red))
        return Dot(source: .mainValue, color: .rules(rules, fallback: grey))
    }
}
