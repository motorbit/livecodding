import AppCoordinator
import SwiftUI

/// Thin shell: owns the root coordinator and renders it. No logic, no dependencies, no logging.
/// Everything else lives in the `Modules` package (ADR 0001).
@main
struct LivecoddingApp: App {
    // Uncomment only if the app must receive UIApplicationDelegate callbacks; add a forwarding AppDelegate here if needed.
    // @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            CoordinatorView(coordinator: coordinator)
        }
    }
}
