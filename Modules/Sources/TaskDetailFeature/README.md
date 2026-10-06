# TaskDetailFeature

Editable pushed child owned by `TaskBoardFeature`. The host creates the view model with a state
initialized from the selected `TaskItem`, embeds `TaskDetailView`, and handles its output events:

- `.dirtyChanged(Bool)` lets the host gate system Back/path changes with its discard confirmation.
- `.updated(TaskItem)` replaces the matching row without popping detail.
- `.deleted(UUID)` removes the row and pops detail after confirmed deletion succeeds.

The feature does not own navigation or present the unsaved-edit confirmation. Update and delete
effects use `TaskClient`, retain the current item and draft on failure, and expose inline retry.
Task text is never logged.

## Due date

A "Due date" toggle reveals a date-only `DatePicker` shown in `DueDay.timeZone` (UTC), so the
state holds the canonical 00:00 UTC day with no time-zone conversion. Turning it on defaults to the
local today (`DueDay.day(containing: \.date.now, in: \.calendar)`); turning it off clears the date.
Turning it back on restores the saved date, else the local today. Dirty checking and the saved
`TaskItem` include `dueDate`.
