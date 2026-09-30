import DesignSystem
import SwiftUI

/// Presentation only: renders `viewModel.state` and forwards input via `trigger`.
/// No logic, no `Task`, no dependency access, no string lookups.
public struct HomeView: View {
    private let viewModel: HomeViewModel

    public init(viewModel: HomeViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let state = viewModel.state
        VStack(spacing: .md) {
            Text(state.title)
                .font(.dsTitle)
                .foregroundStyle(Color.dsTextPrimary)
            Button(state.closeTitle) { viewModel.trigger(.closeTapped) }
                .buttonStyle(.dsPrimary)
        }
        .padding(.md)
    }
}

// Previews use static state. Clients resolve to `previewValue` (or `liveValue` if there isn't one).
#Preview("Default") {
    HomeView(viewModel: HomeViewModel())
}

