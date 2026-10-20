/// The result of evaluating an app's first open-application event.
public enum InitialWindowDecision: Equatable, Sendable {
    case showSettings
    case remainInBackground
}

public enum InitialOpenApplicationKind: Equatable, Sendable {
    case ordinaryOpen
    case loginItem
    case serviceItem
    case unknown
}

/// Collects launch evidence in either AppKit callback order and presents Settings once the
/// app is ready, but only for a known manual open-application launch.
public struct StartupWindowPresentation {
    public private(set) var isDefaultLaunch: Bool?
    public private(set) var openApplicationKind: InitialOpenApplicationKind?
    public private(set) var windowIsReady = false
    public private(set) var hasPresented = false

    public init() {}

    @discardableResult
    public mutating func recordDefaultLaunch(_ value: Bool?) -> Bool {
        if let value { isDefaultLaunch = value }
        return decideIfReadyToPresent()
    }

    @discardableResult
    public mutating func recordOpenApplicationEvent(_ kind: InitialOpenApplicationKind) -> Bool {
        openApplicationKind = kind
        return decideIfReadyToPresent()
    }

    @discardableResult
    public mutating func markWindowReady() -> Bool {
        windowIsReady = true
        return decideIfReadyToPresent()
    }

    public var decision: InitialWindowDecision {
        guard isDefaultLaunch == true, openApplicationKind == .ordinaryOpen else {
            return .remainInBackground
        }
        return .showSettings
    }

    private mutating func decideIfReadyToPresent() -> Bool {
        guard !hasPresented, windowIsReady, decision == .showSettings else { return false }
        hasPresented = true
        return true
    }
}

/// The system-reported state of SMAppService.mainApp plus any last action error.
public struct LoginItemSnapshot: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
        case unknown(Int)
    }

    public let status: Status
    public let operationError: String?

    public init(status: Status, operationError: String? = nil) {
        self.status = status
        self.operationError = operationError
    }

    public var isToggleOn: Bool {
        status == .enabled || status == .requiresApproval
    }

    public var summary: String {
        let currentStatus: String
        switch status {
        case .notRegistered:
            currentStatus = "Not enabled"
        case .enabled:
            currentStatus = "Enabled"
        case .requiresApproval:
            currentStatus = "Waiting for approval in System Settings"
        case .notFound:
            currentStatus = "Ayre could not be found as a login item"
        case .unknown(let rawValue):
            currentStatus = "Unknown login item status (\(rawValue))"
        }
        guard let operationError else { return currentStatus }
        return "\(currentStatus). Could not update the setting: \(operationError)"
    }
}
