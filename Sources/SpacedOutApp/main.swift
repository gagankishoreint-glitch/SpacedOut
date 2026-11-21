import Foundation

if CommandLine.arguments.contains("--watchdog-ensure") {
    WatchdogService.runHeadlessEnsureCheck()
    exit(0)
}

SpacedOutApp.main()
