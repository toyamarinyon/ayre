import AppKit
import Darwin
import Foundation
import Sparkle

@MainActor final class Driver: NSObject, SPUUserDriver {
    let marker: URL
    let invalidCase: Bool
    init(marker: URL, invalidCase: Bool) { self.marker = marker; self.invalidCase = invalidCase }
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false)) }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}
    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showUpdateReleaseNotes(with data: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        let nsError = error as NSError
        var chain = [NSError]()
        var current: NSError? = nsError
        while let item = current, !chain.contains(where: { $0 === item }) {
            chain.append(item)
            current = item.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let signatureRejected = chain.contains { item in
            item.domain == "SUSparkleErrorDomain" && (item.code == 3001 || item.code == 3002) &&
                (item.localizedDescription.localizedCaseInsensitiveContains("signature") || item.localizedDescription.localizedCaseInsensitiveContains("eddsa"))
        }
        let result = signatureRejected ? "signature-validation-rejected" : "unexpected-error: \(chain.map { "\($0.domain) \($0.code) \($0.localizedDescription)" }.joined(separator: " <- "))"
        try? Data(result.utf8).write(to: marker.appendingPathComponent(signatureRejected ? "signature-rejection" : "unexpected-error"))
        acknowledgement()
        if invalidCase { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { NSApp.terminate(nil) } }
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {}
    func showDownloadDidReceiveExpectedContentLength(_ length: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() {}
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated terminated: Bool, retryTerminatingApplication: @escaping () -> Void) {}
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() {}
    func dismissUpdateInstallation() {}
}

@MainActor final class Delegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let marker: URL
    let invalidCase: Bool
    var updater: SPUUpdater?
    var driver: Driver?
    init(marker: URL, invalidCase: Bool) { self.marker = marker; self.invalidCase = invalidCase }
    func applicationDidFinishLaunching(_ note: Notification) {
        let executable = Bundle.main.executableURL!.resolvingSymlinksInPath().path
        if Bundle.main.infoDictionary?["CFBundleVersion"] as? String == "2.0" {
            try? Data("\(getpid())\n\(executable)\n".utf8).write(to: marker.appendingPathComponent("relaunch-process"))
            try? Data("2.0".utf8).write(to: marker.appendingPathComponent("relaunched")); NSApp.terminate(nil); return
        }
        try? Data("\(getpid())\n\(executable)\n".utf8).write(to: marker.appendingPathComponent("updater-process"))
        driver = Driver(marker: marker, invalidCase: invalidCase)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver!, delegate: self)
        do { try updater!.start(); updater!.checkForUpdates() } catch { fail("start: \(error)") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 50) { self.fail("timeout") }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {}
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { fail("no update: \(error)") }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {}
    private func fail(_ message: String) { fputs("FIXTURE FAILURE: \(message)\n", stderr); exit(1) }
}

@main @MainActor struct FixtureMain {
    static var delegate: Delegate?
    static func main() {
        let info = Bundle.main.infoDictionary!
        guard let marker = info["FixtureMarker"] as? String, let invalid = info["FixtureInvalidCase"] as? Bool else { exit(2) }
        NSApplication.shared.setActivationPolicy(.accessory)
        delegate = Delegate(marker: URL(fileURLWithPath: marker), invalidCase: invalid)
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
