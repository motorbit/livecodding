import AddTaskFeature
import DesignSystem
import SwiftUI
import TaskClient
import TaskDetailFeature

public struct TaskBoardView: View {
    @ObservedObject private var viewModel: TaskBoardViewModel

    public init(viewModel: TaskBoardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack(path: Binding(
            get: { viewModel.state.navigationPath },
            set: { viewModel.trigger(.navigationPathChanged($0)) }
        )) {
            VStack(spacing: 0) {
                if let banner = viewModel.state.reloadErrorMessage {
                    reloadBanner(banner)
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.dsBackground)
            .navigationTitle(viewModel.state.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.trigger(.addTapped)
                    } label: {
                        Image(systemName: "plus")
                            .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                    }
                    .accessibilityLabel(viewModel.state.addTitle)
                }
            }
            .navigationDestination(for: TaskBoardRoute.self) { route in
                switch route {
                case .detail:
                    if let detail = viewModel.detailViewModel {
                        TaskDetailView(viewModel: detail)
                            .navigationBarBackButtonHidden(viewModel.state.isDetailDirty)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    if viewModel.state.isDetailDirty {
                                        Button {
                                            viewModel.trigger(.detailBackTapped)
                                        } label: {
                                            Label(viewModel.state.backTitle, systemImage: "chevron.backward")
                                                .labelStyle(.titleAndIcon)
                                                .frame(minHeight: HitTarget.minimum)
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
        .alert(
            viewModel.state.discardTitle,
            isPresented: Binding(
                get: { viewModel.state.isDiscardConfirmationPresented },
                set: { if !$0 { viewModel.trigger(.discardCancelled) } }
            )
        ) {
            Button(viewModel.state.discardCancelTitle, role: .cancel) {
                viewModel.trigger(.discardCancelled)
            }
            Button(viewModel.state.discardConfirmTitle, role: .destructive) {
                viewModel.trigger(.discardConfirmed)
            }
        } message: {
            Text(viewModel.state.discardMessage)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.addViewModel != nil },
            set: { if !$0 { viewModel.trigger(.addDismissed) } }
        )) {
            if let add = viewModel.addViewModel {
                AddTaskView(viewModel: add)
            }
        }
        .onAppear { viewModel.trigger(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state.phase {
        case .loading:
            ProgressView(viewModel.state.loadingMessage)
                .font(.dsBody)
                .foregroundStyle(Color.dsTextSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed:
            messageView(
                title: viewModel.state.loadErrorMessage,
                message: nil,
                actionTitle: viewModel.state.retryTitle,
                action: .retryTapped
            )
        case .empty:
            ScrollView {
                messageView(
                    title: viewModel.state.emptyTitle,
                    message: viewModel.state.emptyMessage,
                    actionTitle: viewModel.state.addTitle,
                    action: .addTapped
                )
            }
            .refreshable { await viewModel.refresh() }
        case .content:
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.state.rows) { row in
                        TaskBoardRowView(
                            row: row,
                            retryTitle: viewModel.state.retryTitle,
                            openDetailHint: viewModel.state.openDetailHint,
                            onToggle: { viewModel.trigger(.completionToggled(row.id)) },
                            onOpen: { viewModel.trigger(.taskTapped(row.id)) },
                            onRetry: { viewModel.trigger(.completionRetryTapped(row.id)) }
                        )
                        DSDivider(inset: .md)
                    }
                }
            }
            .refreshable { await viewModel.refresh() }
        }
    }

    private func messageView(
        title: String,
        message: String?,
        actionTitle: String,
        action: TaskBoardViewEvent
    ) -> some View {
        VStack(spacing: .md) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(Color.dsTextPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.dsBody)
                    .foregroundStyle(Color.dsTextSecondary)
                    .multilineTextAlignment(.center)
            }
            Button(actionTitle) { viewModel.trigger(action) }
                .buttonStyle(.dsPrimary)
        }
        .padding(.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reloadBanner(_ message: String) -> some View {
        HStack(spacing: .sm) {
            Text(message)
                .font(.dsCaption)
                .foregroundStyle(Color.dsError)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(viewModel.state.retryTitle) { viewModel.trigger(.retryTapped) }
                .font(.dsBodyEmphasized)
                .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
        }
        .padding(.horizontal, .md)
        .background(Color.dsSurface)
    }
}

private struct TaskBoardRowView: View {
    let row: TaskBoardRowState
    let retryTitle: String
    let openDetailHint: String
    let onToggle: () -> Void
    let onOpen: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: .xs) {
            HStack(spacing: .sm) {
                Button(action: onToggle) {
                    ZStack {
                        if row.isCompletionInFlight {
                            ProgressView()
                        } else {
                            Image(systemName: row.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.dsHeadline)
                                .foregroundStyle(row.isComplete ? Color.dsBrandPrimary : Color.dsTextSecondary)
                        }
                    }
                    .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(row.isCompletionInFlight)
                .accessibilityLabel(row.completionAccessibilityLabel)
                .accessibilityValue(row.title)

                Button(action: onOpen) {
                    HStack(spacing: .sm) {
                        Text(row.title)
                            .font(.dsBody)
                            .strikethrough(row.isComplete)
                            .foregroundStyle(row.isComplete ? Color.dsTextSecondary : Color.dsTextPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        PriorityBadge(
                            text: row.priorityText,
                            priority: row.priority,
                            accessibilityLabel: row.priorityAccessibilityLabel
                        )
                        Image(systemName: "chevron.forward")
                            .font(.dsCaption)
                            .foregroundStyle(Color.dsTextSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: HitTarget.minimum)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(openDetailHint)
            }
            .opacity(row.isComplete ? 0.6 : 1)

            if let error = row.completionErrorMessage {
                HStack(spacing: .sm) {
                    Text(error)
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(retryTitle, action: onRetry)
                        .font(.dsBodyEmphasized)
                        .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                        .disabled(row.isCompletionInFlight)
                }
                .padding(.leading, HitTarget.minimum + .sm)
            }
        }
        .padding(.horizontal, .md)
        .padding(.vertical, .xs)
    }
}

private struct PriorityBadge: View {
    let text: String
    let priority: TaskPriority
    let accessibilityLabel: String

    var body: some View {
        Text(text)
            .font(.dsCaption)
            .foregroundStyle(accent)
            .padding(.horizontal, .xs)
            .padding(.vertical, .xxs)
            .background(accent.opacity(0.12), in: .rect(cornerRadius: CornerRadius.sm))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.sm)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
            .fixedSize()
            .accessibilityLabel(accessibilityLabel)
    }

    private var accent: Color {
        switch priority {
        case .low: .dsTextSecondary
        case .medium: .dsBrandPrimary
        case .high: .dsError
        }
    }
}

#Preview("Content") {
    TaskBoardView(viewModel: TaskBoardViewModel())
}
