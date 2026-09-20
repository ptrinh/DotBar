import Foundation

/// Ready-made items the user can drop into the menu bar from Preferences.
/// Every command is verified against /bin/zsh -c with ScriptRunner's PATH.
enum Recipes {

    /// Fresh UUIDs on every call, so a recipe can be added more than once.
    static func all() -> [Item] {
        [cpuLoad, memoryUsed, battery, publicIP, localIP, wifiSSID,
         btcPrice, btc3Digits, btcWithLoadDots, diskFree, uptime, gitBranch, ping, clock,
         pingStream, logTail]
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
             source: .script(command: #"ipconfig getifaddr en0 || echo "—""#, refreshSeconds: 60))
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
        let cpu = #"top -l 1 -n 0 | awk '/CPU usage/ {printf "%.0f", $3+$5}'"#
        let ram = #"vm_stat | awk '/Pages free/{f=$3} /Pages active/{a=$3} /Pages inactive/{i=$3} /Pages speculative/{s=$3} /Pages wired down/{w=$4} /Pages occupied by compressor/{c=$5} END{gsub(/[^0-9]/,"",f);gsub(/[^0-9]/,"",a);gsub(/[^0-9]/,"",i);gsub(/[^0-9]/,"",s);gsub(/[^0-9]/,"",w);gsub(/[^0-9]/,"",c); t=f+a+i+s+w+c; if (t>0) printf "%.0f", (a+w+c)*100/t}'"#
        var i = Item(name: "BTC 3 digits + CPU/RAM dots", source: .script(command: btc, refreshSeconds: 60))
        i.dots = [
            Dot(source: .script(command: cpu, refreshSeconds: 10),
                color: .gradient(min: 0, max: 100, from: "#FF453A00", to: "#FF453A"), label: "C"),
            Dot(source: .script(command: ram, refreshSeconds: 15),
                color: .gradient(min: 0, max: 100, from: "#FFD60A00", to: "#FFD60A"), label: "M"),
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
