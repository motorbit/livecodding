# TaskDetailFeature

Editable pushed child owned by `TaskBoardFeature`. The host creates the view model with a state
initialized from the selected `TaskItem`, embeds `TaskDetailView`, and handles its output events:

- `.dirtyChanged(Bool)` lets the host gate system Back/path changes with its discard confirmation.
- `.updated(TaskItem)` replaces the matching row without popping detail.
- `.deleted(UUID)` removes the row and pops detail after confirmed deletion succeeds.

The feature does not own navigation or present the unsaved-edit confirmation. Update and delete
effects use `TaskClient`, retain the current item and draft on failure, and expose inline retry.
Task text is never logged.
