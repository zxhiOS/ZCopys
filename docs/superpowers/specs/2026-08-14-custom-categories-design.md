# Custom Categories (Panel Types)

Date: 2026-08-14

## Goal

Add a persistent `+` control next to Useful Links to create custom category tabs (同级于 Clipboard / Useful Links). No per-category icons.

## Behavior

- Built-in tabs: **Clipboard** (history), **Useful Links** (manual links) — not deletable.
- Custom tabs: create via `+`, rename / delete / move left-right via context menu.
- Custom tab items reuse Useful Links item model (title + url/text), scoped by `categoryId`.
- Selected custom tab shows an item `+` to add entries.
- Deleting a category removes its items.

## Data

- `~/Library/Application Support/Zcopys/categories.json`
- Useful links file gains optional `categoryId` (`null` = Useful Links tab).

## Out of scope

- Custom icons
- Drag-and-drop reorder (use move left/right)
- Clipboard history sub-categories
