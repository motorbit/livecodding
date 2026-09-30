# NetworkClient

The app's HTTP transport client. It provides a single `URLSession` transport, typed JSON decoding and a request builder. Feature modules should call domain API clients built on top of this module rather than using `NetworkClient` directly.

## Included

- `NetworkClient.send(_:)` for raw HTTP exchanges.
- `NetworkClient.decode(_:for:)` and `sendChecked(_:)` for typed status handling and JSON decoding.
- `Endpoint<Response>` for method, path, query, headers and request-body construction.
- `NetworkError` with sanitized, typed failure cases.

Only `LiveNetworkClient.urlSessionTransport(_:)` touches `URLSession`. Decoding runs through `@concurrent decodeOffMain`. Tests use closure-backed clients and stub `HTTPURLResponse` values; they never access the network.

## Middleware and privacy

No optional middleware is enabled yet. If adding middleware, compose it around the transport in `LiveNetworkClient` and document the order here. Never log request or response bodies, headers, tokens, or query values.
