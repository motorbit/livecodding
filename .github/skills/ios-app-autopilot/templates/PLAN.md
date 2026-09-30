# <App> — Implementation plan (from docs/SPEC.md, <date>)

## Modules

| Module | Kind | Depends on | Skill | Options |
|---|---|---|---|---|
| AppCoordinator | UI | all top-level features | ios-project-bootstrap | — |
| Logging, L10n | leaf | — | ios-project-bootstrap | — |
| NetworkClient | client | Logging | ios-network-client | json, endpoint, … |
| <Domain>Client | client | NetworkClient | ios-dependency-client | endpoints below |
| <Feature>Feature | UI | <Domain>Client, DesignSystem, L10n | ios-feature-module | effect: yes, StateMaker: no, placement: route |

## Client contracts

### <Domain>Client (module `<Domain>Client`)
```swift
public struct <Item>: Equatable, Sendable, Codable { … }            // DTOs
@DependencyClient public struct <Domain>Client: Sendable {
    public var fetchItems: @Sendable () async throws -> [<Item>]
}
// previewValue: 3 fake items; liveValue: GET /items (phase 5)
```

## Routes

| Route | Feature | Outputs → |
|---|---|---|
| `.home` | HomeFeature | `.itemSelected(id)` → `.detail(id:)` |

## Waves

| Wave | Tasks (parallel) | Needs |
|---|---|---|
| 3 bootstrap | — (sequential) | spec |
| 4 contracts | — (sequential) | bootstrap |
| 5A | <Domain>Client live impl | contracts |
| 5B | <Feature>Feature, … | contracts |
| 5C | features that embed 5B features | 5B |
| 6 integrate | — (sequential) | 5A–5C |

## Worker assignments

| Worker | Allowed paths | Skill |
|---|---|---|
| <feature>-worker | `Modules/Sources/<Feature>Feature/**`, `Modules/Tests/<Feature>FeatureTests/**`, `Modules/Sources/L10n/L10n+<Feature>.swift` | ios-feature-module |
