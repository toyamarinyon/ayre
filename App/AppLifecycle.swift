import AppKit
import CoreServices
import Foundation

/// Reads AppKit's launch metadata without presenting a window during app initialization.
@MainActor
enum AppLifecycle {
    static func isDefaultLaunch(_ notification: Notification) -> Bool? {
        guard let launchInfo = notification.userInfo,
              let value = launchInfo[NSApplication.launchIsDefaultUserInfoKey] as? NSNumber else {
            return nil
        }
        return value.boolValue
    }

    /// Launch Services marks foreground reopen requests with the public 'aapd' Boolean.
    /// Background App Intent opens must not be turned into foreground settings requests.
    static func activationExpected(in event: NSAppleEventDescriptor?) -> Bool? {
        let value = event?.paramDescriptor(forKeyword: kAEApplicationActivationExpected)
            ?? event?.attributeDescriptor(forKeyword: kAEApplicationActivationExpected)
        return value?.booleanValue
    }

    static func initialOpenApplicationKind(from event: NSAppleEventDescriptor?) -> InitialOpenApplicationKind {
        guard let event,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else {
            return .unknown
        }
        let launchMarker = event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        if launchMarker == keyAELaunchedAsLogInItem { return .loginItem }
        if launchMarker == keyAELaunchedAsServiceItem { return .serviceItem }
        return .ordinaryOpen
    }
}
