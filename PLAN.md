# DotBar — macOS menu bar custom text (plan)

Tham khảo: TextBar (richie5um). Mục tiêu: app menu bar cho phép tạo nhiều item, mỗi item hiện text (static hoặc từ script) + tối đa 3 dot màu xếp dọc, font/màu tùy chỉnh, màu theo điều kiện.

## 1. Tech stack
- Swift 5.10+, SwiftUI + AppKit (NSStatusItem cần AppKit), macOS 14+.
- App kiểu agent (`LSUIElement = YES`), không Dock icon.
- Project sinh bằng XcodeGen (`project.yml`) → `xcodebuild`. Fallback: tạo .xcodeproj tay.
- Không dependency ngoài. Persist bằng JSON (Codable).

## 2. Data model
```
Item
  id, name, enabled
  source: .static(text) | .script(command, refreshSeconds, shell="/bin/zsh -lc", timeout=15)
          | .stream(command)   — process chạy liên tục, mỗi block stdout là 1 update (mới)
  font: family, size, weight
  textColor: ColorSpec
  dots: [Dot] (0..3)
  action: .none | .copy | .script(command) | .openURL
  notify: .off | .onTextChange | .onDotColorChange | .onAnyChange   (mới)
  hotkey: Hotkey?  — phím tắt global refresh riêng item (mới)
  hideWhenEmpty: Bool = false  — ẩn hẳn status item khi output rỗng (mới)
Hotkey
  keyCode: UInt32, modifiers: UInt32 (Carbon flags)
Dot
  id, source: .mainValue | .script(command, refreshSeconds)
  color: ColorSpec
ColorSpec
  .fixed(hex) | .rules([Rule], fallback hex)
Rule
  when: .numberInRange(min?, max?) | .regex(pattern) | .contains(text) | .equals(text) | .isEmpty | .scriptFailed
  color: hex
```
- Giá trị số cho rule range: parse số đầu tiên trong output (regex `-?\d+(\.\d+)?`).
- Field mới (`notify`, `hotkey`) decode bằng `decodeIfPresent` → items.json cũ vẫn load được.
- Hotkey "Refresh All" toàn cục lưu ở UserDefaults key `refreshAllHotkey` (JSON của Hotkey).
- Script có thể trả JSON để override: `{"text":"..","color":"#..","dots":["#..","#.."]}`. Nếu output không phải JSON → coi là plain text.

## 3. Kiến trúc
```
App/
  DotBarApp.swift        @main, AppDelegate, no window at launch
  AppState.swift             ObservableObject: items, outputs, timers
Core/
  Models.swift               Item, Dot, ColorSpec, Rule (Codable)
  Store.swift                load/save ~/Library/Application Support/DotBar/items.json
  ScriptRunner.swift         Process + timeout + PATH đầy đủ, async
  RuleEngine.swift           evaluate(ColorSpec, output) -> NSColor
  Scheduler.swift            timer per item / per dot
MenuBar/
  StatusItemController.swift 1 NSStatusItem/item; NSHostingView cho content
  StatusItemView.swift       SwiftUI: HStack { Text(font,color) ; VStack(dots) }
  StatusMenuBuilder.swift    menu: Updated time · Copy · Refresh · Refresh All · Preferences · Launch at Login · Quit
Preferences/
  PreferencesWindow.swift    NavigationSplitView: list items (sidebar) | detail
  ItemEditorView.swift       name, source, script, refresh, font picker, color, dots editor
  RuleEditorView.swift       danh sách rule + preview màu
  FontPicker.swift           NSFontManager list family + size
```

## 4. Phases
1. **Skeleton**: XcodeGen project, agent app, 1 NSStatusItem static text, menu Quit. Build chạy được.
2. **Model + Store**: Codable, load/save, multi item → nhiều NSStatusItem, add/remove.
3. **Script + Scheduler**: ScriptRunner async, refresh interval, "Updated: …" trong menu, Refresh/Refresh All, JSON override.
4. **Render**: font/size/weight, text color, dots dọc 1–3, RuleEngine (range/regex/contains/failed).
5. **Preferences UI**: sidebar + editor, font picker, color picker, dot/rule editor, live preview.
6. **Polish**: Launch at Login (SMAppService), Import/Export JSON, action khi click (copy/script/URL), error state (hiện `⚠︎` khi script fail).
7. (sau) Hotkey refresh, Notifications khi rule đổi, Sparkle update, codesign/notarize.

## 5. Quyết định mặc định
- Click trái = mở menu (giống TextBar). Action riêng để trong menu.
- Dot size 6pt, spacing 2pt, xếp dọc bên phải text (có option bên trái).
- Item bị ẩn nếu output rỗng và không có dot.
- Script fail/timeout → text giữ giá trị cũ + rule `.scriptFailed` (mặc định đỏ nếu có dot).
- Output nhiều dòng: dòng non-empty đầu = text trên bar, các dòng sau vào đầu menu (click = copy dòng đó); dòng `----`/`---` = separator.
- JSON override nhận thêm `menu`, `symbol` (SF Symbol vẽ trước text, tint theo màu text), `refresh` (giây, override interval tới khi output sau không còn key), `action` (`"copy"`/`"menu"`/`{"url":…}`/`{"script":…}`) — action trong output thắng action cấu hình.
- ANSI SGR (`\e[31m`, `\e[1;32m`, `\e[38;5;N m`, `\e[38;2;r;g;b m`, kể cả dạng literal `\e[`/`\033[`/`\x1b[`) → màu/bold từng run; `text` luôn được strip code để rule + parse số không đổi; màu ANSI thắng màu rule ở run đó.
- `maxWidth` (points, 0 = không giới hạn) cắt text bằng ellipsis đuôi để status item không vượt quá bề ngang đó.

## 6. Runtime
- **Env vars** cho mọi script: `DOTBAR_ITEM_NAME`, `DOTBAR_ITEM_ID`, `DOTBAR_APPEARANCE` (`dark`/`light`),
  `DOTBAR_REFRESH_SECONDS`, `DOTBAR_LAST_RUN`, `DOTBAR_LAST_WAKE`, `DOTBAR_VERSION`,
  `DOTBAR_PREVIOUS_TEXT` (≤512 ký tự). Đổi appearance (KVO `NSApp.effectiveAppearance`) → refresh all 1 lần.
- **URL scheme** `dotbar://` (Core/URLCommands.swift): `refresh`, `refresh?name=`/`?id=`, `set?name=&text=`,
  `enable?name=&value=`, `prefs`. Match tên không phân biệt hoa thường.
- **Stagger**: lúc launch, item thứ N chạy lần đầu trễ `N * 0.7s` (tối đa 5s), timer đầu tiên cũng lệch như vậy.
  Refresh/Refresh All thủ công vẫn chạy ngay.
- **Power**: pause timer khi `willSleep`, tạo lại khi wake (trước refresh wake). Low Power Mode
  (`respectLowPowerMode`, UserDefaults, mặc định true) → interval < 60s nhân 3, tối thiểu 30s.
- **Concurrency guard**: không chạy lần mới khi lần trước của cùng item/dot chưa xong.
- **Streaming** (`Source.stream`, Core/StreamRunner.swift): 1 process sống lâu / item, stdout đọc dần
  (`readabilityHandler`, buffer + tách theo `\n`). Dòng đúng bằng `~~~` kết thúc 1 block → `ScriptOutput.parse(block)`.
  Script không bao giờ in `~~~` → mỗi dòng là 1 block. Process tự thoát → restart backoff 2s/4s/…/60s;
  disable/xoá item, sleep hoặc quit thì không restart. "Refresh" = restart. Env DOTBAR_* dùng chung
  `ScriptEnvironment`. Child chạy ở process group riêng (`setpgid`) nên terminate giết cả pipeline.
  Stop hết stream khi `willSleep`, dựng lại sau wake. Stream không có timer (`refreshSeconds` = 0).
- **File watching** (Core/FileWatcher.swift, DispatchSource trên *thư mục* để sống sót atomic replace):
  `items.json` đổi từ bên ngoài (hash nội dung + mtime khác lần ghi cuối) → reload vào AppState
  (debounce 300ms, `suppressPersist` nên không ghi ngược). `~/Library/Application Support/DotBar/scripts/`
  (tự tạo) đổi → refresh mọi item có command trỏ vào thư mục đó (debounce 500ms).
- `hideWhenEmpty`: text rỗng (sau trim) và không có dots override → `statusItem.isVisible = false`.
