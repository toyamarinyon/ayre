import AppKit
import Foundation
import Sparkle

@MainActor
@main
struct UpdaterStateProbe {
    static func main() {
        if CommandLine.arguments.dropFirst().first == "invalid-configuration" {
            verifyInvalidConfiguration()
            return
        }
        verifyInsertionInstallDeferral()
        let bundleID = Bundle.main.bundleIdentifier!
        UserDefaults.standard.removePersistentDomain(forName: bundleID)

        let first = makeController()
        precondition(!first.updater.automaticallyChecksForUpdates, "The fixture must begin opted out")
        verifyUpdaterInstallDelegate(first.updater)

        first.updater.automaticallyChecksForUpdates = true
        UserDefaults.standard.synchronize()
        precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == true,
                     "Sparkle must persist the opted-in setting in its standard preference key")

        let second = makeController()
        precondition(second.updater.automaticallyChecksForUpdates,
                     "A new Sparkle updater must read the previously persisted setting")

        second.updater.automaticallyChecksForUpdates = false
        UserDefaults.standard.synchronize()
        precondition(UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") as? Bool == false,
                     "Sparkle must persist the opted-out setting")

        let third = makeController()
        precondition(!third.updater.automaticallyChecksForUpdates,
                     "A new Sparkle updater must read the persisted opt-out")

        print("PASS: Sparkle automatic-check preference persists across updater instances")
        withExtendedLifetime((first, second, third)) {}
    }

    private static func verifyInsertionInstallDeferral() {
        var completions: [String] = []
        IntentInsertionActivity.begin()
        IntentInsertionActivity.whenIdle { completions.append("first") }
        precondition(completions.isEmpty, "Update installation must wait while insertion is active")

        IntentInsertionActivity.begin()
        IntentInsertionActivity.end()
        precondition(completions.isEmpty, "Nested insertion work must keep installation deferred")
        IntentInsertionActivity.end()
        precondition(completions == ["first"], "The deferred install must run when all insertion work ends")

        IntentInsertionActivity.whenIdle { completions.append("immediate") }
        precondition(completions == ["first", "immediate"], "Idle work should run immediately")
    }

    private static func verifyUpdaterInstallDelegate(_ updater: SPUUpdater) {
        let delegate = UpdaterController()
        let item = SUAppcastItem.empty()
        var installCalls = 0

        IntentInsertionActivity.begin()
        let postponed = delegate.updater(updater, shouldPostponeRelaunchForUpdate: item) {
            installCalls += 1
        }
        precondition(postponed, "Sparkle installation must be postponed while insertion is active")
        precondition(installCalls == 0, "The Sparkle install handler must wait for insertion to finish")
        IntentInsertionActivity.end()
        precondition(installCalls == 1, "The Sparkle install handler must run after insertion completes")

        let immediatelyAllowed = delegate.updater(updater, shouldPostponeRelaunchForUpdate: item) {
            installCalls += 1
        }
        precondition(!immediatelyAllowed, "No postponement is needed while insertion is idle")
        precondition(installCalls == 1, "Sparkle owns installation when no insertion is active")
        print("PASS: Sparkle install delegate defers only while insertion is active")
    }

    private static func verifyInvalidConfiguration() {
        let controller = UpdaterController()
        controller.start()
        precondition(controller.updater == nil, "Invalid signing keys must leave Sparkle dormant")
        precondition(controller.configurationError != nil, "Invalid signing keys must explain unavailable updates")
        print("PASS: missing or invalid signing key keeps Sparkle dormant")
    }

    private static func makeController() -> SPUStandardUpdaterController {
        SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    }
}
