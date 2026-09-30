/// Output from `HomeViewModel` to its parent (coordinator or host feature), delivered through
/// `onEvent`. Name cases by intent (`closeRequested`, `itemSelected(id:)`), not by UI gesture.
///
/// `Equatable` so tests can compare collected events. Add `Sendable` only if a value of this type
/// actually crosses an isolation boundary.
public enum HomeViewModelEvent: Equatable {
    case closeRequested
}
