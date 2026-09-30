# AddTaskFeature

Sheet child owned by `TaskBoardFeature`. `AddTaskViewModel` submits a normalized
`TaskDraft` through `TaskClient.createTask(_:)`, emits `.created(TaskItem)` only
after success, and emits `.closeRequested` for Cancel. Failed submissions keep
the form draft and expose Retry.

The host creates the view model with its inherited dependencies and routes the
output events to append the new task or dismiss the sheet.

## Due date

An "Add due date" toggle reveals a date-only `DatePicker` shown in `DueDay.timeZone` (UTC), so the
state holds the canonical 00:00 UTC day with no time-zone conversion. Turning it on defaults to the
local today (`DueDay.day(containing: \.date.now, in: \.calendar)`); turning it off clears the date.
The draft carries `dueDate`.
