import BootstrapFeature
import HomeFeature

/// The screen currently shown, carrying its live ViewModel. The VM's lifetime is the screen's
/// lifetime: navigating away drops the VM.
public enum AppScreen {
    case bootstrap(BootstrapViewModel)
    case home(HomeViewModel)
}
