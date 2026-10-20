import ServiceManagement

@MainActor
final class LoginItemController {
    private let service = SMAppService.mainApp

    func snapshot(operationError: String? = nil) -> LoginItemSnapshot {
        let status: LoginItemSnapshot.Status
        switch service.status {
        case .notRegistered:
            status = .notRegistered
        case .enabled:
            status = .enabled
        case .requiresApproval:
            status = .requiresApproval
        case .notFound:
            status = .notFound
        @unknown default:
            status = .unknown(service.status.rawValue)
        }
        return LoginItemSnapshot(status: status, operationError: operationError)
    }

    func setEnabled(_ enabled: Bool) -> LoginItemSnapshot {
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            return snapshot()
        } catch {
            return snapshot(operationError: error.localizedDescription)
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
