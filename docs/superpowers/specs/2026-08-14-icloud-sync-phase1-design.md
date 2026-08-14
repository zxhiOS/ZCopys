# iCloud Sync Phase 1 (Categories + Links)

Date: 2026-08-14

## Scope

- macOS only, Apple ID / iCloud account
- Sync: custom categories + Useful Links / category items
- Not in phase 1: clipboard history, images

## Stack

- CloudKit **Private** database
- Container: `iCloud.$(BUNDLE_IDENTIFIER)` (default `iCloud.com.local.zcopys`)
- Record types: `ZCategory`, `ZLinkItem`

## Merge

- Local upsert on change (debounced)
- Pull on launch / manual “Sync Now”
- Conflict: higher `updatedAt` wins; same id merges fields

## Requirements

- App ID must enable iCloud + CloudKit for the signed bundle id
- Codesign with entitlements listing the iCloud container
