import AppKit
import Sparkle

/// Keeps update installation from interrupting an App Intent while it is writing to another app.
@MainActor
enum IntentInsertionActivity {
    private(set) static var activeCount = 0
    private static var idleHandlers: [() -> Void] = []

    static func begin() {
        activeCount += 1
    }

    static func whenIdle(_ handler: @escaping () -> Void) {
        if activeCount == 0 {
            handler()
        } else {
            idleHandlers.append(handler)
        }
    }

    static func end() {
        guard activeCount > 0 else { return }
        activeCount -= 1
        guard activeCount == 0 else { return }
        let handlers = idleHandlers
        idleHandlers.removeAll()
        handlers.forEach { $0() }
    }
}

@MainActor
final class UpdaterController: NSObject, SPUUpdaterDelegate {
    private var sparkleController: SPUStandardUpdaterController?
    private var canCheckForUpdatesObservation: NSKeyValueObservation?
    private(set) var configurationError: String?
    private(set) var scheduledUpdateAvailable: String?
    var onScheduledUpdateAvailable: (() -> Void)?
    var onCanCheckForUpdatesChange: (() -> Void)?

    var updater: SPUUpdater? { sparkleController?.updater }
    var canCheckForUpdates: Bool {
        scheduledUpdateAvailable != nil || (updater?.canCheckForUpdates ?? false)
    }

    func start() {
        guard sparkleController == nil else { return }
        let info = Bundle.main.infoDictionary ?? [:]
        let publicKey = (info["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let feedURL = (info["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let decodedPublicKey = Data(base64Encoded: publicKey)
        guard decodedPublicKey?.count == 32, URL(string: feedURL)?.scheme == "https" else {
            configurationError = "Updates are unavailable because the signing key or update feed is missing or invalid in this build."
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        sparkleController = controller
        canCheckForUpdatesObservation = controller.updater.observe(\SPUUpdater.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.onCanCheckForUpdatesChange?() }
        }
        controller.startUpdater()
    }

    func checkForUpdates(_ sender: Any?) {
        sparkleController?.checkForUpdates(sender)
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        updater?.automaticallyChecksForUpdates = enabled
    }

    func automaticallyChecksForUpdates() -> Bool {
        updater?.automaticallyChecksForUpdates ?? false
    }

    func updater(
        _ updater: SPUUpdater,
        shouldPostponeRelaunchForUpdate item: SUAppcastItem,
        untilInvokingBlock installHandler: @escaping () -> Void
    ) -> Bool {
        guard IntentInsertionActivity.activeCount > 0 else { return false }
        IntentInsertionActivity.whenIdle(installHandler)
        return true
    }
}

extension UpdaterController: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Scheduled checks stay silent so a Spotlight or Shortcuts launch never steals focus.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        scheduledUpdateAvailable = update.displayVersionString
        onScheduledUpdateAvailable?()
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        scheduledUpdateAvailable = nil
        onScheduledUpdateAvailable?()
    }

    func standardUserDriverWillFinishUpdateSession() {
        scheduledUpdateAvailable = nil
        onScheduledUpdateAvailable?()
    }
}
