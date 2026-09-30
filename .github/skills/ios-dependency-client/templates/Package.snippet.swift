// Package.swift additions for __Name__Client. Merge them into the existing manifest.

// 1. Module enum, "Clients" group:
    case __name__Client = "__Name__Client"

// 2. targets: (client modules keep nonisolated default isolation)
        clientModule(.__name__Client, dependencies: [
            // .module(.logging),            // only if the live implementation logs
            .dependencies,
            .dependenciesMacros,
        ]),

// 3. Each consumer (feature or client) adds `.module(.__name__Client)` to `dependencies`, and to
//    `testDependencies` if its tests override the client.
