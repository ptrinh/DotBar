# DotBar for AI agents

How to add or change a user's DotBar menu bar items. For work on DotBar's own source code,
read the code and `README.md` instead; this file is about **configuring** it.

## Use the `dotbar` CLI

Installed with the Homebrew cask. Otherwise link it once:
`ln -s /Applications/DotBar.app/Contents/MacOS/DotBar /usr/local/bin/dotbar`

```sh
dotbar list [--json]                 # items in bar order
dotbar get <item>                    # one item as JSON
dotbar recipes                       # built-in presets
dotbar add --recipe "CPU Usage"      # add a preset
dotbar add --json '{"name":"Hi","source":{"static":{"text":"Hi"}}}'
dotbar update <item> --json '{"sparkline":30}'   # JSON merge patch
dotbar enable|disable|remove <item>
dotbar test <item|command> [--json]  # run it, show how DotBar reads the output
dotbar schema                        # JSON Schema of items.json
```

- `<item>` is a name (case-insensitive) or an id prefix.
- Writes are validated, back up the old file to `items.json.bak`, and apply to a running
  DotBar immediately (it watches the file). Prefer the CLI over editing `items.json` by hand.
- **Always `dotbar test` a command before adding it**, and check the `bar` / `menu` it reports.

Workflow for "add an item that shows X": write the command → `dotbar test '<command>'` until
the bar text and menu look right → `dotbar add --json …` → `dotbar test <name>`.

## items.json

Location: `dotbar path` (`~/Library/Application Support/DotBar/items.json`; the Mac App Store
build keeps it in its sandbox container). Full schema: `dotbar schema` or
[`DotBar/Resources/items.schema.json`](DotBar/Resources/items.schema.json).

Enums are Swift Codable objects with one key: `{"script": {"command": "…", "refreshSeconds": 60}}`,
`{"menu": {}}`, `{"calendar": {}}`. Unnamed values use `_0`: `{"fixed": {"_0": "#FF453A"}}`,
`{"rules": {"_0": [ … ], "fallback": "#8E8E93"}}`. Omitted fields take their defaults.

Key fields: `source` (static / script / stream), `dots` (0–3, each with its own `source` and
`color`), `textColor`, `action` / `altAction` / `middleAction`, `menuCommand`, `sparkline`,
`displayMode`, `hideWhenEmpty`, `paddingLeft` / `paddingRight`.

## Output a command can print

Commands run with `/bin/zsh -c`. See [`Recipes.md`](Recipes.md) for the full reference and
many working examples.

- **Plain text**: first non-empty line is the bar; later lines are the menu.
- **xbar line params** after ` | `: `color=red`, `href=…`, `bash=/path param1=… param2='…'`,
  `refresh=true`, `sfimage=…`, `length=20`, `tooltip='…'`, `disabled=true`.
  `--` prefixes nest submenus, `---` is a separator (`-----` inside a submenu).
  A menu line with no action copies its text when clicked.
- **JSON object**: `{"text","color","dots":["#hex",…],"symbol","menu":[…],"badge","mode","refresh","action"}`.
  `text` may contain `\n` for two small stacked lines.
- **Drawn symbols**: `"symbol":"calendar:<day>[:<label>[:<color>]]"`,
  `"symbol":"battery:<percent>[:charging|:plugged][:lowpower]"`,
  `"symbol":"usage:<top>:<bottom>[:<label>]"` (two progress bars, 0–100, optional label above).

## AI usage

`dotbar usage claude|codex` prints the two-bar JSON (`usage:<session>:<weekly>:<label>`); an item
whose command is exactly that runs it in-process, so it also works in the sandboxed build.

## `menuCommand`

Extra menu lines from a separate command that runs only at launch and whenever the menu opens
(cached; the open menu updates in place). Put costly details here (health data, process
lists, API calls) instead of in the refresh-timer command.

## Keep it light

DotBar idles at ~0% CPU; a command on a timer is where cost comes from.

- Pick the longest `refreshSeconds` that still feels live; 0 = manual.
- Avoid `top -l 1` (≈0.75 s CPU per run); CPU % via
  `iostat -c 2 -w 1 | tail -1 | awk '{printf "%.0f", 100 - $(NF-3)}'`.
- `ps`, `osascript`, `ipconfig`, `git` are denied in the Mac App Store (sandboxed) build.
- Never launch apps from a timer command (guard AppleScript with `if application "X" is running`).
