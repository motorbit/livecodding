import DesignSystem
import SwiftUI
import TaskClient

public struct AddTaskView: View {
    @ObservedObject private var viewModel: AddTaskViewModel

    public init(viewModel: AddTaskViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .lg) {
                Text(viewModel.state.title)
                    .font(.dsTitle)
                    .foregroundStyle(Color.dsTextPrimary)

                VStack(alignment: .leading, spacing: .md) {
                    TextField(
                        viewModel.state.titlePlaceholder,
                        text: Binding(
                            get: { viewModel.state.taskTitle },
                            set: { viewModel.trigger(.titleChanged($0)) }
                        )
                    )
                    .font(.dsBody)
                    .padding(.md)
                    .background(Color.dsSurface, in: .rect(cornerRadius: CornerRadius.md))
                    .accessibilityLabel(viewModel.state.titleLabel)

                    TextField(
                        viewModel.state.notesPlaceholder,
                        text: Binding(
                            get: { viewModel.state.notes },
                            set: { viewModel.trigger(.notesChanged($0)) }
                        ),
                        axis: .vertical
                    )
                    .font(.dsBody)
                    .lineLimit(3 ... 6)
                    .padding(.md)
                    .background(Color.dsSurface, in: .rect(cornerRadius: CornerRadius.md))
                    .accessibilityLabel(viewModel.state.notesLabel)

                    Picker(
                        viewModel.state.priorityLabel,
                        selection: Binding(
                            get: { viewModel.state.priority },
                            set: { viewModel.trigger(.priorityChanged($0)) }
                        )
                    ) {
                        Text(viewModel.state.lowPriorityLabel).tag(TaskPriority.low)
                        Text(viewModel.state.mediumPriorityLabel).tag(TaskPriority.medium)
                        Text(viewModel.state.highPriorityLabel).tag(TaskPriority.high)
                    }
                    .pickerStyle(.segmented)
                }

                if let errorMessage = viewModel.state.errorMessage {
                    VStack(alignment: .leading, spacing: .xs) {
                        Text(errorMessage)
                            .font(.dsBody)
                            .foregroundStyle(Color.dsError)

                        if viewModel.state.canRetry {
                            Button(viewModel.state.retryLabel) {
                                viewModel.trigger(.retryTapped)
                            }
                            .font(.dsBodyEmphasized)
                            .disabled(viewModel.state.isSaving)
                        }
                    }
                }

                HStack(spacing: .md) {
                    Button(viewModel.state.cancelLabel) {
                        viewModel.trigger(.cancelTapped)
                    }
                    .frame(maxWidth: .infinity, minHeight: HitTarget.minimum)
                    .disabled(viewModel.state.isSaving)

                    Button(viewModel.state.saveLabel) {
                        viewModel.trigger(.saveTapped)
                    }
                    .buttonStyle(.dsPrimary)
                    .disabled(viewModel.state.isSaving)
                }
            }
            .padding(.md)
        }
        .background(Color.dsBackground)
        .disabled(viewModel.state.isSaving)
    }
}
