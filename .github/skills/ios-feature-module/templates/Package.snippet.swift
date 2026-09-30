// Package.swift additions for __Feature__Feature. Merge them into the existing manifest; this
// isn't a standalone file.

// 1. Module enum, "Features" group:
    case __feature__Feature = "__Feature__Feature"

// 2. targets: (feature modules are UI modules, so MainActor is the default)
        uiModule(.__feature__Feature, dependencies: [
            .module(.l10n),
            .module(.logging),
            // >>> effect
            .module(.__client__),          // the client module(s) this feature calls
            // <<< effect
            .module(.designSystem),        // always present; Views use its tokens
            // .module(.childFeature),     // ONLY if this feature embeds that child (ADR 0001)
            .dependencies,
        ], testDependencies: [
            .module(.logging),
            // >>> effect
            .module(.__client__),
            // <<< effect
        ]),

// 3. AppCoordinator target: if the feature is a top-level route, add `.module(.__feature__Feature)`
//    to its dependencies (see the ios-coordinator-route skill). If it's embedded, add it to the
//    host feature's dependencies instead.
