import AppEnvironment

/// Input from `DebugMenuView` to `DebugMenuViewModel`. Only the View sends these.
public enum DebugMenuViewEvent {
    case onAppear
    case environmentSelected(AppEnvironment)
    case closeTapped
}
