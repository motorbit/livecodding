import DesignSystem
import SwiftUI
import TaskClient

public struct TaskDetailView: View {
    @ObservedObject private var viewModel: TaskDetailViewModel

    public init(viewModel: TaskDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                TextField(
                    viewModel.state.titleFieldLabel,
                    text: Binding(
                        get: { viewModel.state.title },
                        set: { viewModel.trigger(.titleChanged($0)) }
                    )
                )
                .accessibilityLabel(viewModel.state.titleFieldLabel)

                if let validationMessage = viewModel.state.titleValidationMessage {
                    Text(validationMessage)
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsError)
                }

                Text(viewModel.state.notesFieldLabel)
                    .font(.dsBodyEmphasized)
                    .foregroundStyle(Color.dsTextPrimary)
                TextEditor(
                    text: Binding(
                        get: { viewModel.state.notes },
                        set: { viewModel.trigger(.notesChanged($0)) }
                    )
                )
                .frame(minHeight: 100)
                .accessibilityLabel(viewModel.state.notesFieldLabel)

                Menu {
                    Button(viewModel.state.lowPriorityLabel) {
                        viewModel.trigger(.priorityChanged(.low))
                    }
                    Button(viewModel.state.mediumPriorityLabel) {
                        viewModel.trigger(.priorityChanged(.medium))
                    }
                    Button(viewModel.state.highPriorityLabel) {
                        viewModel.trigger(.priorityChanged(.high))
                    }
                } label: {
                    HStack {
                        Text(viewModel.state.priorityFieldLabel)
                            .foregroundStyle(Color.dsTextPrimary)
                        Spacer()
                        Text(viewModel.state.selectedPriorityLabel)
                            .foregroundStyle(Color.dsTextSecondary)
                    }
                }
            }
            .disabled(!viewModel.state.canEditFields)

            if let errorMessage = viewModel.state.inlineErrorMessage {
                Section {
                    Text(errorMessage)
                        .font(.dsBody)
                        .foregroundStyle(Color.dsError)
                    Button(viewModel.state.retryButtonTitle) {
                        viewModel.trigger(.retryTapped)
                    }
                    .disabled(!viewModel.state.canRetry)
                }
            }

            Section {
                Button(viewModel.state.saveButtonTitle) {
                    viewModel.trigger(.saveTapped)
                }
                .buttonStyle(.dsPrimary)
                .disabled(!viewModel.state.canSave)

                Button(viewModel.state.deleteButtonTitle, role: .destructive) {
                    viewModel.trigger(.deleteTapped)
                }
                .frame(minHeight: HitTarget.minimum)
                .foregroundStyle(Color.dsError)
                .disabled(!viewModel.state.canDelete)
            }
        }
        .navigationTitle(viewModel.state.navigationTitle)
        .alert(
            viewModel.state.deleteConfirmationTitle,
            isPresented: Binding(
                get: { viewModel.state.isDeleteConfirmationPresented },
                set: { isPresented in
                    if !isPresented { viewModel.trigger(.deleteCancelled) }
                }
            )
        ) {
            Button(viewModel.state.cancelButtonTitle, role: .cancel) {
                viewModel.trigger(.deleteCancelled)
            }
            Button(viewModel.state.confirmDeleteButtonTitle, role: .destructive) {
                viewModel.trigger(.deleteConfirmed)
            }
        } message: {
            Text(viewModel.state.deleteConfirmationMessage)
        }
    }
}
