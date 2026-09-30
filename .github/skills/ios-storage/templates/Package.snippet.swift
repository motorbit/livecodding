// Package.swift additions for the __Module__ module. Merge them into the existing manifest.
// If `case __module__` already exists, change nothing here: the new client's files go into the
// existing module (SwiftData and Security are system frameworks; no new package dependencies).

// 1. Module enum, "Clients" group:
    case __module__ = "__Module__"

// 2. targets: (client modules keep nonisolated default isolation)
        clientModule(.__module__, dependencies: [.dependencies, .dependenciesMacros]),

// 3. Consumers are domain clients (e.g. `SessionClient`, `SettingsClient`), which add
//    `.module(.__module__)`. Features depend on those domain clients, not on __Module__ directly.
