import DesignSystem
import L10n
import SwiftUI

/// What `DebugMenuButton` renders. Plain data, strings already localized.
public struct DebugMenuButtonState: Equatable {
    public var accessibilityLabel: String

    public init(accessibilityLabel: String = L10n.DebugMenu.title) {
        self.accessibilityLabel = accessibilityLabel
    }
}

/// Floating button that opens the debug menu. `CoordinatorView` layers it above every screen in
/// debug and non-prod builds. Presentation only.
public struct DebugMenuButton: View {
    private let state: DebugMenuButtonState
    private let action: () -> Void

    public init(state: DebugMenuButtonState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "ladybug.fill")
                .font(.dsHeadline)
                .foregroundStyle(Color.white)
                .frame(width: HitTarget.minimum, height: HitTarget.minimum)
                .background(Circle().fill(Color.dsBrandPrimary.opacity(0.85)))
                .shadow(radius: 3)
        }
        .accessibilityLabel(state.accessibilityLabel)
    }
}

#Preview {
    DebugMenuButton(state: DebugMenuButtonState()) {}
}
