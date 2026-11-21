import Foundation

if CommandLine.arguments.contains("--watchdog-ensure") {
    WatchdogService.runHeadlessEnsureCheck()
    exit(0)
}

MainActor.assumeIsolated {
    AppDelegate.runApp()
}
