# AddTaskFeature

Sheet child owned by `TaskBoardFeature`. `AddTaskViewModel` submits a normalized
`TaskDraft` through `TaskClient.createTask(_:)`, emits `.created(TaskItem)` only
after success, and emits `.closeRequested` for Cancel. Failed submissions keep
the form draft and expose Retry.

The host creates the view model with its inherited dependencies and routes the
output events to append the new task or dismiss the sheet.
