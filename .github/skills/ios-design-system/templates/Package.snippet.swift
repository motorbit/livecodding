// Package.swift additions for DesignSystem. Merge them into the existing manifest.

// 1. Module enum, "UI" group:
    case designSystem = "DesignSystem"

// 2. targets: (a UI module, so MainActor is the default; no tests by default because it's excluded
//    from coverage. Add tests if you add logic.)
        uiModule(.designSystem,
                 // >>> resources
                 resources: [.process("Resources")],   // colors-assets and/or typography-custom
                 // <<< resources
                 tests: false),

// 3. Features that render UI add `.module(.designSystem)` to their dependencies.
