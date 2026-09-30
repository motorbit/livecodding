# __Module__

Local storage clients, grouped in one nonisolated client module. Features never call these
directly: domain clients (e.g. `SessionClient`, `SettingsClient`) wrap them and own the keys.

## Clients

| Client | Key path | Stores | Live backing |
|---|---|---|---|
<!-- >>> option:keychain -->
| `KeychainClient` | `\.keychainClient` | Small secrets (tokens, credentials) | `SecItem*` generic-password items, `@concurrent` |
<!-- <<< option:keychain -->
<!-- >>> option:userDefaults -->
| `UserDefaultsClient` | `\.userDefaultsClient` | Small non-secret preferences | `UserDefaults` |
<!-- <<< option:userDefaults -->
<!-- >>> option:swiftData -->
| `SwiftDataClient` | `\.swiftDataClient` | Structured local data | SwiftData `ModelContainer` + `@ModelActor` |
<!-- <<< option:swiftData -->

## Choices

<!-- >>> option:keychain -->
### Keychain

- Service: `__BundleID__.keychain`
- Accessibility: `__accessibility__`. Reason: __AccessibilityReason__
- Access group: __AccessGroupChoice__
<!-- <<< option:keychain -->
<!-- >>> option:userDefaults -->
### UserDefaults

- Suite: __SuiteChoice__
- Keys are `UserDefaultsKey<Value>` constants declared by the consuming domain client.
<!-- <<< option:userDefaults -->
<!-- >>> option:swiftData -->
### SwiftData

- Model types: __ModelTypes__
- Store location: __StoreLocationChoice__
- `@Model` entities stay inside `StorageModelActor`. Endpoints take and return `Sendable` values.
<!-- <<< option:swiftData -->

## Values

- `liveValue`: the real backing store, configured above.
- `previewValue`: `inMemory()` for every client. Previews never touch real storage.
- `testValue`: unimplemented. Tests use `.inMemory()` or stub single endpoints.

## Rules

- Secrets go only in `KeychainClient`, never in UserDefaults or SwiftData.
- Stored values are never logged. Log only the key name and the error/status.
- Call each client's reset (`deleteAll`, `remove`) from the ordered sign-out sequence.
