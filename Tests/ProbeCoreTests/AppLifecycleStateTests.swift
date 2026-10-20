import XCTest
@testable import ProbeCore

final class AppLifecycleStateTests: XCTestCase {
    func testManualLaunchEventBeforeWindowAndLaunchFlagIsDeferredUntilReady() {
        var state = StartupWindowPresentation()
        XCTAssertFalse(state.recordOpenApplicationEvent(.ordinaryOpen))
        XCTAssertFalse(state.recordDefaultLaunch(true))
        XCTAssertFalse(state.hasPresented)
        XCTAssertTrue(state.markWindowReady())
        XCTAssertTrue(state.hasPresented)
    }

    func testManualLaunchEventAfterWindowAndLaunchFlagPresentsImmediately() {
        var state = StartupWindowPresentation()
        XCTAssertFalse(state.recordDefaultLaunch(true))
        XCTAssertFalse(state.markWindowReady())
        XCTAssertTrue(state.recordOpenApplicationEvent(.ordinaryOpen))
    }

    func testUnknownAndBackgroundLaunchesRemainWindowless() {
        var unknownDefault = StartupWindowPresentation()
        unknownDefault.recordDefaultLaunch(nil)
        unknownDefault.markWindowReady()
        XCTAssertFalse(unknownDefault.recordOpenApplicationEvent(.ordinaryOpen))

        var unknownEvent = StartupWindowPresentation()
        unknownEvent.recordDefaultLaunch(true)
        unknownEvent.markWindowReady()
        XCTAssertFalse(unknownEvent.recordOpenApplicationEvent(.unknown))

        var background = StartupWindowPresentation()
        background.recordDefaultLaunch(false)
        background.markWindowReady()
        XCTAssertFalse(background.recordOpenApplicationEvent(.ordinaryOpen))
    }

    func testLoginAndServiceLaunchesStayWindowlessEvenWhenDefaultFlagIsTrue() {
        for kind in [InitialOpenApplicationKind.loginItem, .serviceItem] {
            var state = StartupWindowPresentation()
            state.recordDefaultLaunch(true)
            state.markWindowReady()
            XCTAssertFalse(state.recordOpenApplicationEvent(kind))
            XCTAssertFalse(state.hasPresented)
        }
    }

    func testPresentationOccursOnlyOnce() {
        var state = StartupWindowPresentation()
        state.recordDefaultLaunch(true)
        state.recordOpenApplicationEvent(.ordinaryOpen)
        XCTAssertTrue(state.markWindowReady())
        XCTAssertFalse(state.recordOpenApplicationEvent(.ordinaryOpen))
        XCTAssertTrue(state.hasPresented)
    }

    func testForegroundReopenIsDistinctFromBackgroundAutomation() {
        XCTAssertTrue(ReopenWindowPolicy.shouldPresentSettings(isReopenApplicationEvent: true, activationExpected: true))
        XCTAssertFalse(ReopenWindowPolicy.shouldPresentSettings(isReopenApplicationEvent: true, activationExpected: false))
        XCTAssertFalse(ReopenWindowPolicy.shouldPresentSettings(isReopenApplicationEvent: true, activationExpected: nil))
        XCTAssertFalse(ReopenWindowPolicy.shouldPresentSettings(isReopenApplicationEvent: false, activationExpected: true))
    }

    func testLoginItemStateAndErrorsRemainTruthful() {
        XCTAssertFalse(LoginItemSnapshot(status: .notRegistered).isToggleOn)
        XCTAssertTrue(LoginItemSnapshot(status: .enabled).isToggleOn)
        XCTAssertTrue(LoginItemSnapshot(status: .requiresApproval).isToggleOn)
        XCTAssertFalse(LoginItemSnapshot(status: .notFound).isToggleOn)
        XCTAssertEqual(
            LoginItemSnapshot(status: .enabled, operationError: "registration failed").summary,
            "Enabled. Could not update the setting: registration failed"
        )
        XCTAssertEqual(LoginItemSnapshot(status: .notFound).summary, "Ayre could not be found as a login item")
    }
}
