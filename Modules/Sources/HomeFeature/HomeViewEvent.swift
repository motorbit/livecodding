/// Input from `HomeView` to `HomeViewModel`. Only the View sends these; parents
/// never call `trigger` on a child. Delete any case the View doesn't send.
public enum HomeViewEvent {
    case closeTapped
}
