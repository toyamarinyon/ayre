import AppKit
import Foundation
import Sparkle

@MainActor
final class Probe: NSObject, SPUUpdaterDelegate {
    let expected: String
    var updater: SPUUpdater!
    var found = false
    var missing = false

    init(expected: String) {
        self.expected = expected
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found = true
        print("EVENT: update found (\(item.versionString))")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        missing = true
        print("EVENT: no update (code \((error as NSError).code))")
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard updateCheck == .updateInformation else { return }
        let result: String
        if let error {
            let nsError = error as NSError
            result = nsError.domain == "SUSparkleErrorDomain" && nsError.code == 1001 ? "no-update" : "network-error"
            print("EVENT: cycle error (\(nsError.domain) code \(nsError.code))")
        }
        else if found { result = "update-found" }
        else if missing { result = "no-update" }
        else { result = "unexpected" }
        print("RESULT: \(result)")
        fflush(stdout)
        exit(result == expected ? 0 : 1)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let expected: String
    var updater: SPUUpdater?
    var driver: SPUStandardUserDriver?
    var probe: Probe?

    init(expected: String) { self.expected = expected }

    func applicationDidFinishLaunching(_ notification: Notification) {
        driver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
        let probe = Probe(expected: expected)
        let updater = SPUUpdater(hostBundle: Bundle.main, applicationBundle: Bundle.main, userDriver: driver!, delegate: probe)
        probe.updater = updater
        self.updater = updater
        self.probe = probe
        do { try updater.start() }
        catch {
            fputs("RESULT: startup-error \(error)\n", stderr)
            exit(3)
        }
        updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            fputs("RESULT: timeout\n", stderr)
            exit(2)
        }
    }
}

@main
@MainActor
struct SparkleFeedProbe {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard args.count == 1 else { fputs("usage: probe no-update|update-found|network-error\n", stderr); exit(2) }
        NSApplication.shared.setActivationPolicy(.accessory)
        let delegate = AppDelegate(expected: args[0])
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
