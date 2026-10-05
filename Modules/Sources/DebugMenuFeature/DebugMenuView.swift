import DesignSystem
import SwiftUI

/// Sheet with developer tools. Presentation only.
public struct DebugMenuView: View {
    @ObservedObject private var viewModel: DebugMenuViewModel

    public init(viewModel: DebugMenuViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.state.environments) { row in
                        Button {
                            viewModel.trigger(.environmentSelected(row.id))
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: .xxs) {
                                    Text(row.name)
                                        .foregroundStyle(Color.dsTextPrimary)
                                    Text(row.detail)
                                        .font(.dsCaption)
                                        .foregroundStyle(Color.dsTextSecondary)
                                }
                                Spacer()
                                if row.isSelected {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.dsBrandPrimary)
                                }
                            }
                        }
                        .accessibilityAddTraits(row.isSelected ? .isSelected : [])
                    }
                } header: {
                    Text(viewModel.state.environmentHeader)
                } footer: {
                    Text(viewModel.state.environmentFooter)
                }
            }
            .navigationTitle(viewModel.state.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.state.closeTitle) { viewModel.trigger(.closeTapped) }
                }
            }
        }
        .onAppear { viewModel.trigger(.onAppear) }
    }
}

#Preview {
    DebugMenuView(viewModel: DebugMenuViewModel())
}
