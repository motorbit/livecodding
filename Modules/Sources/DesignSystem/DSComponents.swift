import SwiftUI

/// Filled, full-width primary action. Usage: `Button(title) { … }.buttonStyle(.dsPrimary)`.
/// Requires the colors, typography and tokens options.
public struct DSPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.dsBodyEmphasized)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
            .padding(.horizontal, .md)
            .background(Color.dsBrandPrimary, in: .rect(cornerRadius: CornerRadius.md))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

public extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}

/// A hairline divider in the border color, with optional horizontal insets.
public struct DSDivider: View {
    private let inset: CGFloat

    public init(inset: CGFloat = 0) {
        self.inset = inset
    }

    public var body: some View {
        Rectangle()
            .fill(Color.dsBorder)
            .frame(height: 1)
            .padding(.horizontal, inset)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: .md) {
        Button("Primary") {}.buttonStyle(.dsPrimary)
        DSDivider(inset: .md)
        Button("Disabled") {}.buttonStyle(.dsPrimary).disabled(true)
    }
    .padding()
}
