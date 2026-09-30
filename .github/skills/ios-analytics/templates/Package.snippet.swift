// Package.swift additions for Analytics. Merge them into the existing manifest.

// 1. Module enum, "Clients" group:
    case analytics = "Analytics"

// 2. targets:
        clientModule(.analytics, dependencies: [
            .dependencies,
            .dependenciesMacros,
            .module(.logging),
            // >>> option:vendor
            // .product(name: "<VendorSDK>", package: "<vendor-package>"),
            // <<< option:vendor
        ]),

// 3. Features that track events add `.module(.analytics)` to dependencies and testDependencies.
//    Features own their tracking; the coordinator only needs it for app-level events.
