# Clipboard Panel UI Redesign

**Date:** 2026-07-29  
**Status:** Approved for planning  
**Approach:** Rewrite `ContentView` + add `UsefulLinksStore`

## Goal

Replace the current vertical list popup with the glassmorphism horizontal-card UI from the design mockup, and add a fully editable **Useful Links** tab (manual add + favorite from clipboard history).

## Non-goals

- Auto-update / Sparkle
- iCloud sync
- Changes to packaging/notarization scripts
- Simulating ⌘V auto-paste after copy-back

## Layout & Visual

### Panel

- Borderless floating `NSPanel`, glass / `.ultraThinMaterial` background
- Size approximately **1100 × 420**, corner radius ~28
- Centered near top of the screen that contains the mouse (existing centering logic, updated size)

### Top bar (centered)

| Control | Behavior |
|---------|----------|
| Magnifying glass | Tap expands an inline search field; filters the **current tab** only. Collapse when cleared / Esc while searching |
| **Clipboard** | Selected = dark pill + clock icon |
| **Useful Links** | Unselected text; red status dot when the store is non-empty |
| **+** | On Useful Links: open add form. On Clipboard: hidden |
| **⋯** | Menu: clear current tab; accessibility hint / request permission when needed |

### Cards

- Horizontal `ScrollView` of vertical cards (~**200 × 280**)
- Structure:
  1. **Colored header:** kind label (`Text` / `URL` / `File` / `Image` / `Link`), relative time (`yesterday`, `2 days ago`, etc.), trailing icon
  2. **White body:** primary content (`value` or link title + preview)
  3. **Footer:** character count (left), list icon + 1-based index (right)
- Header colors by kind:
  - `text` → blue
  - `url` → cyan
  - `file` → dark gray
  - `image` → purple
  - Useful Link → teal/green family
  - Heuristic for `text` only: if trimmed value matches `^(sudo\s+)?[\w.-]+(\s|$)` and first token is in a small allowlist (`tl`, `git`, `npm`, `yarn`, `pnpm`, `flutter`, `dart`, `swift`, `cd`, `ls`, `rm`, `cp`, `mv`, `curl`, `ssh`) OR contains ` | `, header uses red; kind stays `text`
- Selected card: visible selection stroke / highlight
- Empty state: centered unavailable message per tab

## Data

### Clipboard (existing)

- Keep `ClipboardStore` and `clipboard-history.json`
- Card shows `value`; payload used for copy-back
- Context menu: Copy, Pin/Unpin, Delete, **Add to Useful Links**
  - New link title = truncated `value`
  - New link body = `payload` (or `value` if same)

### Useful Links (new)

Model `UsefulLink`:

| Field | Type | Notes |
|-------|------|--------|
| `id` | `UUID` | |
| `title` | `String` | Display title |
| `urlOrText` | `String` | URL or arbitrary text |
| `createdAt` | `Date` | |
| `lastUsedAt` | `Date` | Updated on open/copy |
| `isPinned` | `Bool` | Pinned sort first |

`UsefulLinksStore`:

- CRUD, toggle pin, clear, filtered search (title + urlOrText)
- Persist to `~/Library/Application Support/mac_tool/useful-links.json`
- Deduplicate on equal `urlOrText` (update `lastUsedAt` instead of inserting)

### AppState additions

- `selectedTab`: `.clipboard` | `.usefulLinks`
- `isSearchExpanded: Bool`
- `searchText` already exists — applies only to current tab
- Hold / create `usefulLinksStore`
- `addClipboardItemToUsefulLinks(_:)`
- Selection sync and `moveSelection` operate on the active tab’s filtered list
- Keyboard: **left/right** (and Shift-Tab/Tab) move selection; Return activates; Esc clears search or closes panel

### Activation rules

| Tab | Click / Return |
|-----|----------------|
| Clipboard | Copy item to pasteboard and close panel (existing) |
| Useful Links | If value looks like `http(s)://`, open in default browser and bump `lastUsedAt`; else copy to pasteboard and close |

### Add / edit Useful Link

- `+` presents a compact overlay/sheet inside the panel: Title + URL/Text fields, Save / Cancel
- Edit from context menu reuses the same form
- Validation: both fields non-empty after trim (or title optional defaulting to urlOrText) — **explicit:** title may be empty and defaults to truncated `urlOrText`; `urlOrText` is required

## Keyboard (panel)

Update `ClipboardPanelController`:

- Panel frame **1100 × 420**
- Key codes: left (123) / right (124) instead of up/down for selection
- Keep Return, Esc, Tab/Shift-Tab
- While search field focused and composing (IME), do not intercept arrows used by the text system when composition is active (existing `hasMarkedText` guard)

## File changes

| File | Change |
|------|--------|
| `Sources/mac_tool/ContentView.swift` | Rewrite: chrome, tabs, horizontal cards, search expand, add/edit overlay |
| `Sources/mac_tool/ClipboardItem.swift` | Display helpers (relative time, header color, character count, kind label) — prefer extensions here or a small `ClipboardCardStyle` helper in the same module |
| `Sources/mac_tool/UsefulLink.swift` | **New** model |
| `Sources/mac_tool/UsefulLinksStore.swift` | **New** store |
| `Sources/mac_tool/AppState.swift` | Tab, search expand, useful links wiring, selection for both lists |
| `Sources/mac_tool/ClipboardPanelController.swift` | Size + left/right keys |
| `Tests/mac_toolTests/...` | UsefulLinksStore tests; AppState tab/filter/selection tests as needed |

## Testing

- Useful Links: add, dedupe, pin order, clear, filter
- Add from clipboard item creates expected title/body
- Sensitive clipboard items remain unrecorded (existing); favoring them into Useful Links is allowed only if the item already exists in history (no change to sensitive skip on monitor)
- Selection moves left/right within filtered list; does not crash on empty list

## Success criteria

1. Popup visually matches the mockup: glass panel, centered top chrome, horizontal colored cards with footer meta
2. Clipboard tab retains search (via expand), pin, delete, copy-back
3. Useful Links tab supports manual add, edit, delete, pin, open/copy, and “Add to Useful Links” from clipboard
4. `swift test` passes; app builds with `swift build`
