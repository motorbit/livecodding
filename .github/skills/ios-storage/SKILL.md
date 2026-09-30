---
name: ios-storage
description: Adds a `Storage` client module (swift-dependencies) that groups the local persistence clients you pick. `KeychainClient` stores small secrets as generic-password items with a chosen accessibility class and optional access group. `UserDefaultsClient` stores typed preferences through `UserDefaultsKey<Value>` constants, on standard defaults or an app group suite. `SwiftDataClient` is a local database over a `ModelContainer` with a `@ModelActor`, and exposes Sendable values only. Every client has an in-memory variant for tests and previews. Use when the user says "keychain", "secure storage", "token storage", "save credentials", "UserDefaults", "preferences", "settings persistence", "SwiftData", "local database", "persistence" or "share storage with extension".
---

# iOS storage

## Purpose

This skill creates `Modules/Sources/__Module__/` (default `Storage`): one nonisolated client module holding the local storage clients the user selects. Each client is a `@DependencyClient` struct with a live value, an in-memory variant and an unimplemented `testValue`. Features never call these clients directly. Domain clients (e.g. `SessionClient`, `SettingsClient`) wrap them and own the keys.

The module grows over time. If `__Module__` already exists, add only the new client's files and tests, and don't duplicate the module.

## Inputs / Options

| # | Option | Adds (templates) | Sub-options |
|---|---|---|---|
| 0 | **module** (always) | `Package.snippet.swift`, `README.md` | Module name `__Module__` (default `Storage`, enum case `__module__` = `storage`) |
| 1 | `keychain` → `KeychainClient` | `keychain/*`, `Tests/keychain/*` | Service (default: bundle id + `.keychain`); accessibility; access group |
| 2 | `userDefaults` → `UserDefaultsClient` | `userDefaults/*`, `Tests/userDefaults/*` | Suite: `standard` / app group `group.<id>` |
| 3 | `swiftData` → `SwiftDataClient` | `swiftData/*`, `Tests/swiftData/*` | Model types and their fields; store location: on disk / app group / in-memory only |

Sub-option values:
- **Keychain accessibility:** `whenUnlockedThisDeviceOnly` / `afterFirstUnlockThisDeviceOnly` / `whenPasscodeSetThisDeviceOnly`. **Access group:** none / `"<TeamID>.<group>"`.
- **UserDefaults suite:** `standard` (default) / `"group.<id>"` to share with extensions.
- **SwiftData models:** one `__Model__` per type (UpperCamel singular, e.g. `Note`, with `__Models__` = `Notes`), each with a `String` `id` and its fields. **Location:** `onDisk` (default) / `appGroup("group.<id>")`.

**If the options aren't specified, ask one short multi-choice question:** "Storage: which clients? [keychain] [userDefaults] [swiftData]. Keychain: accessibility [whenUnlocked (foreground only, strictest)] [afterFirstUnlock (background work)] [whenPasscodeSet], access group [no] [yes: id]? UserDefaults suite: [standard] [app group: id]? SwiftData: model types and fields, store [on disk] [app group: id]?" Ask only about the selected clients. Apply only the selected parts.

Guidance for the choices:
- **Keychain.** Choose `afterFirstUnlock…` only if the app reads the item in the background (background refresh, push handling, extensions). Every choice is `…ThisDeviceOnly`, so items don't migrate through backups, which is the right default for tokens. iCloud-synchronizable items are out of scope.
- **UserDefaults.** Use an app group suite only if an extension reads the preferences. Values are plist primitives (`Bool`, `Int`, `Double`, `String`, `Data`, `Date`, stored natively) or small `Codable` values (`.codable`, stored as JSON `Data`).
- **SwiftData.** Use it for structured data that is queried or grows (drafts, caches with relations). Don't use it for a handful of flags (UserDefaults) or for secrets (Keychain). CloudKit sync is out of scope. The configuration sets `cloudKitDatabase: .none` and `groupContainer: .none` explicitly, because the `.automatic` defaults silently pick up a CloudKit or App Group entitlement.

## Steps

1. **Resolve the options.** Check `Package.swift` for an existing `__module__` case and `Modules/Sources/__Module__/` for existing client files. Skip what's already there.
2. **Module (first time only).** Merge `templates/Package.snippet.swift` into `Package.swift`: the enum case and `clientModule(.__module__, dependencies: [.dependencies, .dependenciesMacros])`. Copy `templates/README.md` → `Modules/Sources/__Module__/README.md`.
3. **Each selected client.** Copy `templates/<option>/*` → `Modules/Sources/__Module__/` (flat, no subfolders), and `templates/Tests/<option>/*` → `Modules/Tests/__Module__Tests/`. Replace `__Module__` in the test imports. The first time, add `__Module__Tests` to the test plan with `python3 .github/skills/ios-project-bootstrap/scripts/sync_test_plan.py <Root>/<App>.xctestplan`. If the plan doesn't exist yet, the script says so. Create it with ios-project-bootstrap's `wire_xcode_project.py` (step 9).
4. **keychain.** In `LiveKeychainClient.swift`'s `>>> config` block:
   - Replace `__BundleID__` and `.__accessibility__`.
   - Set `accessGroup` to `"<TeamID>.<group>"`, or keep `nil` and delete the `// or …` comment.
   - Delete the marker lines.
5. **userDefaults.** In `UserDefaultsClient.swift`'s `>>> config` block:
   - Keep `.live(.standard)`, or replace it with `.live(suiteName: "group.<id>")`.
   - Delete the `// or …` comment and the marker lines.
6. **swiftData.**
   - For each model type, copy `swiftData/__Model__.swift` as `<Model>.swift`. Replace `__Model__`, then replace each `>>> fields` block with the model's fields (value struct, entity, `init`, `update(from:)`, `value`) and delete the markers.
   - In `SwiftDataClient.swift`, `StorageModelActor.swift` and `LiveSwiftDataClient.swift`, replace `__Model__`/`__Models__`. For each additional model, duplicate the endpoint group (`fetch…`, `save…`, `delete…`), the actor methods and the `live` wiring, add the entity to `StorageSchema.schema`, and add a `modelContext.delete(model:)` line to `deleteAll()`.
   - In the `>>> config` block, keep `.live(.onDisk)` or use `.live(.appGroup("group.<id>"))`. Delete the `// or …` comment and the markers.
   - Adjust the `fixture` in `Tests/…/SwiftDataClientTests.swift` to the fields, and duplicate the tests per model.
7. **README.** Keep only the selected `option:` rows and sections, fill in every choice with its reason, and delete the HTML comment markers. When extending the module later, add the new rows and sections.
8. **Manual Xcode steps** (agents never edit `*.pbxproj`), only for the options that need them:
   - Keychain access group: App target ▸ Signing & Capabilities ▸ **+ Capability ▸ Keychain Sharing**, then add the group. Do the same in every app/extension that shares it. The runtime value is `<TeamID>.<group>`; Xcode adds the `$(AppIdentifierPrefix)` prefix in the entitlement.
   - App group (UserDefaults suite or SwiftData store): **+ Capability ▸ App Groups**, then add `group.<id>` to every target that shares it.
9. **Consumers.** Create or extend a domain client with **ios-dependency-client** (e.g. `SessionClient.storeToken`, `SettingsClient.sortOrder`) whose live value uses `@Dependency(\.keychainClient)` / `\.userDefaultsClient` / `\.swiftDataClient`. Key names (keychain accounts, `UserDefaultsKey` constants) are declared in that domain client, not as string literals at call sites. VMs depend on the domain client.

## Rules / Checklist

- **Secrets only in Keychain:** tokens, credentials, keys. Never in UserDefaults or SwiftData.
- Keep Keychain items small. Put large or structured data in SwiftData or files.
- Never log stored values. Log only the key name and the `OSStatus` or error.
- `testValue = Self()` (unimplemented) for every client. No no-op test values. Tests use `.inMemory()` or stub single endpoints. `previewValue` is `inMemory()` for every client.
- The module is a `clientModule` (nonisolated). Blocking work runs off the caller's actor: SecItem calls and opening the SwiftData store are `@concurrent`, and `ModelContext` work runs inside the `@ModelActor`.
- **SwiftData isolation.** `ModelContext` and `@Model` objects aren't `Sendable`. They never leave `StorageModelActor`. Endpoints take and return `Sendable` value types.
- Keychain writes are upserts (`SecItemUpdate`, then `SecItemAdd` on `errSecItemNotFound`). Deletes treat "not found" as success.
- A `UserDefaultsKey` read returns the key's default when the value is missing, of another kind, or no longer decodes.
- Call each client's reset (`KeychainClient.deleteAll`, `UserDefaultsClient.remove`, `SwiftDataClient.deleteAll`) as part of the ordered sign-out / environment-reset sequence (coordinator).
- SPM unit tests have no keychain entitlement (`-34018`), so test the query builders and the in-memory client, never the real keychain. UserDefaults tests use a throwaway suite. SwiftData tests use `.inMemory()`.

## Done criteria

- Only the selected clients' files exist. `grep -rnE '__[A-Za-z]+__|>>> |<<< ' Modules/Sources/<Module> Modules/Tests/<Module>Tests Modules/Package.swift` returns nothing.
- `__Module__` is declared once in `Package.swift` with `clientModule`.
- The module README records every choice (clients, accessibility and reason, access group, suite, model types, store location).
- The user got the Keychain Sharing / App Groups steps if a shared group was chosen.
- **Don't run `xcodebuild`** unless asked. Tell the user to build and run `__Module__Tests`.
