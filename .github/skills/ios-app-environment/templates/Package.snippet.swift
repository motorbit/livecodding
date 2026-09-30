// Package.swift additions for AppEnvironment. Merge them into the existing manifest.

// 1. Module enum, "Clients" group:
    case appEnvironment = "AppEnvironment"

// 2. targets:
        clientModule(.appEnvironment, dependencies: [.dependencies, .dependenciesMacros]),

// 3. Consumers: API clients (base URL), the coordinator (environment-switch reset), and any
//    debug-menu feature.
