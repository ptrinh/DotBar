import Foundation

/// Ready-made items the user can drop into the menu bar from Preferences.
/// Every command is verified against /bin/zsh -c with ScriptRunner's PATH.
enum Recipes {

    /// Fresh UUIDs on every call, so a recipe can be added more than once.
    /// Mac App Store build runs inside the App Sandbox: `top`, `ps`, `ping`, `ipconfig getifaddr`, `git` are denied there.
    static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    /// CPU % : `top` outside the sandbox, 1-minute load average / core count inside it.
    static var cpuPercentCommand: String {
        isSandboxed
            ? #"awk -v l="$(sysctl -n vm.loadavg | awk '{print $2}')" -v n="$(sysctl -n hw.ncpu)" 'BEGIN{p=l/n*100; if(p>100)p=100; printf "%.0f", p}'"#
            : #"top -l 1 -n 0 | awk '/CPU usage/ {printf "%.0f", $3+$5}'"#
    }
    static var localIPCommand: String {
        isSandboxed ? #"ifconfig en0 | awk '/inet /{print $2}'"# : #"ipconfig getifaddr en0"#
    }

    /// Recipes whose commands the App Sandbox denies (ping raw sockets, git via xcrun, ipconfig SSID).
    private static let sandboxUnavailable: Set<String> = ["Ping 1.1.1.1", "Ping stream", "Git Branch", "Wi-Fi SSID",
                                                          "Network Throughput", "VPN", "Time Machine", "Displays", "Bluetooth Battery"]

    static func all() -> [Item] {
        [// System
         cpuLoad, memoryUsed, swapUsed, loadAverage, battery, diskFree, uptime, caffeinate, darkMode, displays, bluetoothBattery, timeMachine,
         // Network
         publicIP, localIP, wifiSSID, vpn, networkThroughput, ping,
         // Finance
         btcPrice, btc3Digits, btcWithLoadDots, ethPrice, stockQuote, exchangeRates, goldPrice,
         // Weather & time
         weather, airQuality, clock, calendarIcon, worldClock, countdown,
         // Dev & streaming
         gitBranch, pingStream, logTail]
            .filter { !isSandboxed || !sandboxUnavailable.contains($0.name) }
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
        var i = Item(name: "Memory Used", source: .script(command: cmd, refreshSeconds: 15))
        i.dots = [dot(ranges: [(nil, 70, green), (70, 88, orange), (88, nil, red)])]
        return i
    }

    private static var battery: Item {
        var i = Item(name: "Battery",
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
        return i
    }

    /// First 3 digits of the BTC price as text; dot 1 fades transparent -> red with CPU %, dot 2 transparent -> yellow with RAM %.
    private static var btcWithLoadDots: Item {
        let btc = #"curl -s --max-time 8 https://api.coinbase.com/v2/prices/BTC-USD/spot | sed -E 's/.*"amount":"([0-9]+)[."].*/\1/' | cut -c1-3"#
        let cpu = cpuPercentCommand
        let ram = #"vm_stat | awk '/Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",f);gsub(/[^0-9]/,"",a);gsub(/[^0-9]/,"",i);gsub(/[^0-9]/,"",s);gsub(/[^0-9]/,"",w);gsub(/[^0-9]/,"",c); t=f+a+i+s+w+c; if (t>0) printf "%.0f", (a+w+c)*100/t}'"#
        var i = Item(name: "BTC 3 digits + CPU/RAM dots", source: .script(command: btc, refreshSeconds: 60))
        i.dots = [
            Dot(source: .script(command: cpu, refreshSeconds: 10),
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
    private static var calendarIcon: Item {
        var i = Item(name: "Calendar Icon",
                     source: .script(command: #"C=black; date +'{"text":"","symbol":"calendar:%-d:%a:'"$C"'"}'"#, refreshSeconds: 60))
        i.action = .calendar
        return i
    }

    private static var worldClock: Item {
        Item(name: "World Clock (New York)",
             source: .script(command: #"TZ="America/New_York" date +"NY %H:%M""#, refreshSeconds: 30))
    }

    /// Days left until a date. Edit the date.
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
