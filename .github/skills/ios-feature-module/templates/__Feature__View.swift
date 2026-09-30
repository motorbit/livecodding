import DesignSystem
import SwiftUI

/// Presentation only: renders `viewModel.state` and forwards input via `trigger`.
/// No logic, no `Task`, no dependency access, no string lookups.
public struct __Feature__View: View {
    private let viewModel: __Feature__ViewModel

    public init(viewModel: __Feature__ViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        let state = viewModel.state
        VStack(spacing: .md) {
            Text(state.title)
                .font(.dsTitle)
                .foregroundStyle(Color.dsTextPrimary)
            // >>> effect
            if state.isLoading {
                ProgressView()
            } else if let errorMessage = state.errorMessage {
                Text(errorMessage)
                Button(state.retryTitle) { viewModel.trigger(.retryTapped) }
            } else if let content = state.content {
                Text(content)
            }
            // <<< effect
            Button(state.closeTitle) { viewModel.trigger(.closeTapped) }
                .buttonStyle(.dsPrimary)
        }
        .padding(.md)
        // >>> effect
        .onAppear { viewModel.trigger(.onAppear) }
        // <<< effect
    }
}

// Previews use static state. Clients resolve to `previewValue` (or `liveValue` if there isn't one).
#Preview("Default") {
    __Feature__View(viewModel: __Feature__ViewModel())
}

// >>> effect
#Preview("Error") {
    __Feature__View(viewModel: __Feature__ViewModel(state: __Feature__ViewState(errorMessage: "Preview error")))
}
// <<< effect
