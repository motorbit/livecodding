// Package.swift additions for NetworkClient. Merge them into the existing manifest.

// 1. Module enum, "Clients" group:
    case networkClient = "NetworkClient"

// 2. targets:
        clientModule(.networkClient, dependencies: [
            .dependencies,
            .dependenciesMacros,
            // >>> option:logging
            .module(.logging),
            // <<< option:logging
        ], testDependencies: [
            // >>> option:logging
            .module(.logging),
            // <<< option:logging
        ]),

// 3. API clients (e.g. `ProfileClient`) depend on `.module(.networkClient)`. Features depend on
//    those API clients, not on NetworkClient directly.
