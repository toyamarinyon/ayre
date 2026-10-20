import AppKit
import CoreServices

/// Exercises the real Foundation Apple Event bridge without launching UI or registering login items.
@main
@MainActor
struct LifecycleAdapterSmoke {
    static func event(_ id: AEEventID = AEEventID(kAEReopenApplication)) -> NSAppleEventDescriptor {
        NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: id,
                               targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                               transactionID: AETransactionID(kAnyTransactionID))
    }

    static func main() {
        let foreground = event()
        foreground.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: kAEApplicationActivationExpected)
        precondition(AppLifecycle.activationExpected(in: foreground) == true)

        let background = event()
        background.setParam(NSAppleEventDescriptor(boolean: false), forKeyword: kAEApplicationActivationExpected)
        precondition(AppLifecycle.activationExpected(in: background) == false)
        precondition(AppLifecycle.activationExpected(in: event()) == nil)
        precondition(AppLifecycle.activationExpected(in: nil) == nil)

        let attribute = event()
        attribute.setAttribute(NSAppleEventDescriptor(boolean: true), forKeyword: kAEApplicationActivationExpected)
        precondition(AppLifecycle.activationExpected(in: attribute) == true)

        for (marker, expected) in [(keyAELaunchedAsLogInItem, InitialOpenApplicationKind.loginItem),
                                   (keyAELaunchedAsServiceItem, InitialOpenApplicationKind.serviceItem)] {
            let launch = event(AEEventID(kAEOpenApplication))
            launch.setParam(NSAppleEventDescriptor(enumCode: marker), forKeyword: keyAEPropData)
            precondition(AppLifecycle.initialOpenApplicationKind(from: launch) == expected)
        }
        precondition(AppLifecycle.initialOpenApplicationKind(from: event(AEEventID(kAEOpenApplication))) == .ordinaryOpen)
        precondition(AppLifecycle.initialOpenApplicationKind(from: event()) == .unknown)
        print("PASS: Foundation Apple Event parameters, attributes, foreground/background flags, and login/service launch markers")
    }
}
