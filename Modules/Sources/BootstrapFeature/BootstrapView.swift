import DesignSystem
import SwiftUI

/// The first screen: a full-screen progress indicator shown while `BootstrapViewModel` runs
/// start-up work. Presentation only.
public struct BootstrapView: View {
    @ObservedObject private var viewModel: BootstrapViewModel

    public init(viewModel: BootstrapViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ProgressView()
            .controlSize(.large)
            .tint(Color.dsBrandPrimary)
            .accessibilityLabel(viewModel.state.loadingLabel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
            .onAppear { viewModel.trigger(.onAppear) }
    }
}

#Preview {
    BootstrapView(viewModel: BootstrapViewModel())
}
