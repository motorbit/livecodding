# NetworkClient

The app's HTTP transport client. It provides a single `URLSession` transport, typed JSON decoding and a request builder. Feature modules should call domain API clients built on top of this module rather than using `NetworkClient` directly.

## Included

- `NetworkClient.send(_:)` for raw HTTP exchanges.
- `NetworkClient.decode(_:for:)` and `sendChecked(_:)` for typed status handling and JSON decoding.
- `Endpoint<Response>` for method, path, query, headers and request-body construction.
- `NetworkError` with sanitized, typed failure cases.
- `NetworkMiddleware.logging(logger:)`: one sanitized log line per wire attempt.
- `NetworkMonitorClient` (`\.networkMonitorClient`): `isOnlineUpdates()` streams whether the device has a usable network path (`NWPathMonitor`): the current value first, then every change. A path doesn't prove a server is reachable; use it as a hint to retry. `previewValue` reports online once; `testValue` is unimplemented.

Only `LiveNetworkClient.urlSessionTransport(_:)` touches `URLSession`. `decode(_:for:)` and `sendChecked(_:)` are `@concurrent`: the whole exchange (middlewares, transport, status check, decoding) runs off the caller's actor, and the caller resumes on its own actor with the result. Raw `send(_:)` stays on the caller's actor; prefer the two checked entry points. Tests use closure-backed clients and stub `HTTPURLResponse` values; they never access the network.

## Middleware and privacy

Composed in `LiveNetworkClient.liveComposed()`, outer → inner: **logging → transport**, so each wire
attempt is logged. Add future middlewares (correlation → retry → auth) outside logging.

`logging` (`\.logger`) writes `method`, `url`, `status` and `durationMs` on success. On failure it
logs the mapped `NetworkError` (never the raw error: `URLError.userInfo` holds the full URL) with
`method`, `url` and `durationMs`; cancellation is logged at `.debug`, not as an error. The URL drops user, password and fragment, and
every query value becomes `<redacted>`. Headers (tokens, cookies) and request/response bodies are
never logged.
