# __Name__Client

<!-- One paragraph: what capability this wraps (system API, SDK, storage) and why it's a client. -->

## Endpoints

| Endpoint | Signature | Notes |
|---|---|---|
| `load` | `() async throws -> String` | `@concurrent` in live; caches the result |
| `cachedValue` | `() -> String?` | Sync; returns the last loaded value |
| `clear` | `() async -> Void` | Clears the cache and storage |

## Values

- `liveValue`: `__Name__Client.live()`, backed by `Live__Name__Storage`.
- `previewValue`: canned values for previews.
- `testValue`: unimplemented. Tests must stub every endpoint they reach.

## Consumers

<!-- Which modules use it. If only one feature uses it, that's fine: it still lives here. -->
