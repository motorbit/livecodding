# Logging

`LoggingClient`: the app's only logging API. It's a `@DependencyClient` wrapping `os.Logger`.

## Why

- One place decides privacy: messages are public and metadata is private. User data never reaches the unified log in release builds.
- Tests can assert on log lines by overriding `log`.
- Don't use `print` or `os.Logger` anywhere else, including the app target.

## Usage

```swift
@Dependency(\.logger) private var logger

logger.info("Profile loaded", ["items": "\(items.count)"])
logger.error(error, ["operation": "loadProfile"])
```

Rules:
- Keep `message` a static phrase. Put variable data in `metadata`.
- Never log tokens, passwords, emails or full URLs with query strings. Not even as metadata.
- `debug` is dropped in release builds.
- Diagnostic logging added while investigating a bug is never committed.

## Testing

`testValue` is unimplemented, so an unexpected log call fails the test. Stub it once per suite:

```swift
private func makeDependencies(_ d: inout DependencyValues) {
    d.logger.log = { _, _, _ in }
    d.logger.logError = { _, _ in }
}
```

To assert on log lines, capture them with `LockIsolated<[String]>` in the test override.
