/// Input from `__Feature__View` to `__Feature__ViewModel`. Only the View sends these; parents
/// never call `trigger` on a child. Delete any case the View doesn't send.
public enum __Feature__ViewEvent {
    // >>> effect
    case onAppear
    case retryTapped
    // <<< effect
    case closeTapped
}
