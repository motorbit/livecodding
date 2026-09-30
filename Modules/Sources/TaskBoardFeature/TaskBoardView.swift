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
            .safeAreaInset(edge: .bottom) {
                if let undo = viewModel.state.undo {
                    undoBanner(undo)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.default, value: viewModel.state.undo)
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
            List {
                ForEach(viewModel.state.rows) { row in
                    TaskBoardRowView(
                        row: row,
                        retryTitle: viewModel.state.retryTitle,
                        openDetailHint: viewModel.state.openDetailHint,
                        onToggle: { viewModel.trigger(.completionToggled(row.id)) },
                        onOpen: { viewModel.trigger(.taskTapped(row.id)) },
                        onRetry: { viewModel.trigger(.rowRetryTapped(row.id)) }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.dsBackground)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.trigger(.deleteSwiped(row.id))
                        } label: {
                            Label(viewModel.state.deleteTitle, systemImage: "trash")
                        }
                        .disabled(row.isInFlight)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
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

    private func undoBanner(_ undo: TaskBoardUndoState) -> some View {
        HStack(spacing: .sm) {
            Text(undo.message)
                .font(.dsBody)
                .foregroundStyle(Color.dsTextPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(viewModel.state.undoTitle) { viewModel.trigger(.undoTapped) }
                .font(.dsBodyEmphasized)
                .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
        }
        .padding(.horizontal, .md)
        .padding(.vertical, .xs)
        .background(Color.dsSurface, in: .rect(cornerRadius: CornerRadius.lg))
        .padding(.horizontal, .md)
        .padding(.bottom, .xs)
        .accessibilityElement(children: .contain)
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
                        if row.isInFlight {
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
                .disabled(row.isInFlight)
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

            if let error = row.errorMessage {
                HStack(spacing: .sm) {
                    Text(error)
                        .font(.dsCaption)
                        .foregroundStyle(Color.dsError)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(.borderless)
                        .font(.dsBodyEmphasized)
                        .frame(minWidth: HitTarget.minimum, minHeight: HitTarget.minimum)
                        .disabled(row.isInFlight)
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
