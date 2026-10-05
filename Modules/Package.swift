// swift-tools-version: 6.2
import PackageDescription

// MARK: - Modules
//
// One case per source module. The test target name is derived (`<Name>Tests`).
// Keep cases grouped by layer; imports only flow downwards (see AGENTS.md, ADR 0001):
//   leaves (L10n, DesignSystem) → clients (Logging, …Client, Analytics, AppEnvironment)
//   → *Feature → AppCoordinator (composition root; nothing imports it).

enum Module: String, CaseIterable {
    // Composition root
    case appCoordinator = "AppCoordinator"

    // Features (UI, MainActor by default)
    case taskBoardFeature = "TaskBoardFeature"
    case addTaskFeature = "AddTaskFeature"
    case taskDetailFeature = "TaskDetailFeature"
    case bootstrapFeature = "BootstrapFeature"
    case debugMenuFeature = "DebugMenuFeature"

    // Clients / infrastructure (nonisolated by default)
    case taskClient = "TaskClient"
    case logging = "Logging"
    case networkClient = "NetworkClient"
    case appEnvironment = "AppEnvironment"

    // Leaves
    case designSystem = "DesignSystem"   // always present (AGENTS.md R15); a UI module
    case l10n = "L10n"

    // [bootstrap-option hooks] Optional skills add their cases here, e.g.:
    // case networkClient = "NetworkClient"      // ios-network-client
    // case storage = "Storage"                  // ios-storage
    // case analytics = "Analytics"              // ios-analytics

    var name: String { rawValue }
    var testsName: String { rawValue + "Tests" }
}

// MARK: - Concurrency settings (ADR 0005)
//
// Every target: Swift 6 language mode (implied by tools 6.2) plus the two upcoming features that
// Xcode 26 calls "Approachable Concurrency":
//   - NonisolatedNonsendingByDefault (SE-0461): nonisolated async functions run on the caller's
//     actor; use `@concurrent` for work that must leave the main actor.
//   - InferIsolatedConformances (SE-0470): conformances of MainActor types are MainActor-isolated,
//     which SE-0470 recommends whenever default MainActor isolation is on.
// UI modules additionally default to MainActor isolation (SE-0466).

let approachableConcurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let uiSettings: [SwiftSetting] = [.defaultIsolation(MainActor.self)] + approachableConcurrency
let clientSettings: [SwiftSetting] = approachableConcurrency

// MARK: - Package

let package = Package(
    name: "Modules",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: Module.allCases.map { .library(name: $0.name, targets: [$0.name]) },
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        // Composition root: the only module that imports every feature.
        uiModule(.appCoordinator, dependencies: [
            .module(.bootstrapFeature),
            .module(.taskBoardFeature),
            .module(.debugMenuFeature),
            .module(.appEnvironment),
            .module(.taskClient),
            .module(.logging),
            .dependencies,
        ], testDependencies: [
            .module(.bootstrapFeature),
            .module(.taskBoardFeature),
            .module(.debugMenuFeature),
            .module(.appEnvironment),
            .module(.taskClient),
            .module(.logging),
        ]),

        // Features
        uiModule(.bootstrapFeature, dependencies: [
            .module(.designSystem),
            .module(.l10n),
            .module(.logging),
            .dependencies,
        ], testDependencies: [.module(.logging)]),
        uiModule(.debugMenuFeature, dependencies: [
            .module(.appEnvironment),
            .module(.designSystem),
            .module(.l10n),
            .module(.logging),
            .dependencies,
        ], testDependencies: [
            .module(.appEnvironment),
            .module(.logging),
        ]),
        uiModule(.taskBoardFeature, dependencies: [
            .module(.taskClient),
            .module(.addTaskFeature),
            .module(.taskDetailFeature),
            .module(.designSystem),
            .module(.l10n),
            .module(.logging),
            .dependencies,
        ], testDependencies: [
            .module(.taskClient),
            .module(.addTaskFeature),
            .module(.taskDetailFeature),
            .module(.logging),
        ]),
        uiModule(.addTaskFeature, dependencies: [
            .module(.taskClient),
            .module(.designSystem),
            .module(.l10n),
            .module(.logging),
            .dependencies,
        ], testDependencies: [
            .module(.taskClient),
            .module(.logging),
        ]),
        uiModule(.taskDetailFeature, dependencies: [
            .module(.taskClient),
            .module(.designSystem),
            .module(.l10n),
            .module(.logging),
            .dependencies,
        ], testDependencies: [
            .module(.taskClient),
            .module(.logging),
        ]),

        // Clients
        clientModule(.logging, dependencies: [.dependencies, .dependenciesMacros]),
        clientModule(.taskClient, dependencies: [
            .module(.appEnvironment),
            .module(.networkClient),
            .module(.logging),
            .dependencies,
            .dependenciesMacros,
            .grdb,
        ], resources: [.process("Resources")], testDependencies: [
            .module(.appEnvironment),
            .module(.networkClient),
            .module(.logging),
        ]),
        clientModule(.networkClient, dependencies: [
            .dependencies,
            .dependenciesMacros,
            .module(.logging),
        ], testDependencies: [
            .module(.logging),
        ]),
        clientModule(.appEnvironment, dependencies: [.dependencies, .dependenciesMacros]),

        // Leaves
        // DesignSystem: no tests by default (tokens only). Drop `resources:` if it has no
        // `Resources/` folder (colors in code and system typography).
        uiModule(.designSystem, resources: [.process("Resources")], tests: false),
        clientModule(.l10n, resources: [.process("Resources")], tests: false),
    ].flatMap { $0 }
)

// MARK: - Helpers

/// A MainActor-by-default module (features, coordinator, DesignSystem) plus its test target.
func uiModule(
    _ module: Module,
    dependencies: [Target.Dependency] = [],
    resources: [Resource]? = nil,
    testDependencies: [Target.Dependency] = [],
    tests: Bool = true
) -> [Target] {
    makeTargets(
        module,
        dependencies: dependencies,
        resources: resources,
        testDependencies: testDependencies,
        settings: uiSettings,
        tests: tests
    )
}

/// A nonisolated-by-default module (clients, infrastructure, leaves) plus its test target.
func clientModule(
    _ module: Module,
    dependencies: [Target.Dependency] = [],
    resources: [Resource]? = nil,
    testDependencies: [Target.Dependency] = [],
    tests: Bool = true
) -> [Target] {
    makeTargets(
        module,
        dependencies: dependencies,
        resources: resources,
        testDependencies: testDependencies,
        settings: clientSettings,
        tests: tests
    )
}

func makeTargets(
    _ module: Module,
    dependencies: [Target.Dependency],
    resources: [Resource]?,
    testDependencies: [Target.Dependency],
    settings: [SwiftSetting],
    tests: Bool
) -> [Target] {
    var targets: [Target] = [
        .target(
            name: module.name,
            dependencies: dependencies,
            exclude: ["README.md"],  // every module documents itself in a README
            resources: resources,
            swiftSettings: settings
        ),
    ]
    if tests {
        targets.append(
            .testTarget(
                name: module.testsName,
                dependencies: [.module(module), .dependencies] + testDependencies,
                swiftSettings: settings
            )
        )
    }
    return targets
}

extension Target.Dependency {
    static func module(_ module: Module) -> Target.Dependency {
        .target(name: module.name)
    }

    static var dependencies: Target.Dependency {
        .product(name: "Dependencies", package: "swift-dependencies")
    }

    static var dependenciesMacros: Target.Dependency {
        .product(name: "DependenciesMacros", package: "swift-dependencies")
    }

    static var grdb: Target.Dependency {
        .product(name: "GRDB", package: "GRDB.swift")
    }
}
