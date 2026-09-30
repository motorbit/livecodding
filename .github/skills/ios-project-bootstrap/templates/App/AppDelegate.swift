import UIKit

/// OPTIONAL. Add only when a system callback has no SwiftUI equivalent (APNs token, some SDK
/// redirect URLs). Each method forwards the callback to a DI client in `Modules` and returns;
/// no branching, no logging, no state here. The receiving client/coordinator logs and decides.
///
/// Example (after creating the client with the ios-dependency-client skill):
///
///     import Dependencies
///     import PushClient
///
///     @Dependency(\.pushClient) private var pushClient
///
///     func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
///         pushClient.didRegister(token)
///     }
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        true
    }
}
