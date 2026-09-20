import Combine
import ServiceManagement

/// The only boundary that changes the process's Login Items registration.
///
/// Registration is deliberately driven from Settings, never from app launch. The observable
/// value reflects the system service rather than a copied preference, so turning the setting off
/// can be confirmed against the current login-item state.
public protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func register() throws
    func unregister() throws
}

public final class MainAppLaunchAtLoginController: LaunchAtLoginControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func register() throws {
        try SMAppService.mainApp.register()
    }

    public func unregister() throws {
        try SMAppService.mainApp.unregister()
    }
}

@MainActor
public final class LaunchAtLoginService: ObservableObject {
    public static let shared = LaunchAtLoginService()

    @Published public private(set) var isEnabled: Bool
    @Published public private(set) var errorMessage: String?

    private let controller: any LaunchAtLoginControlling

    public init(controller: any LaunchAtLoginControlling = MainAppLaunchAtLoginController()) {
        self.controller = controller
        self.isEnabled = controller.isEnabled
    }

    public func refresh() {
        isEnabled = controller.isEnabled
    }

    /// Applies an explicit user choice. A failed operation leaves the displayed state aligned with
    /// the operating system rather than pretending the requested state took effect.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != controller.isEnabled else {
            isEnabled = controller.isEnabled
            errorMessage = nil
            return
        }

        do {
            if enabled {
                try controller.register()
            } else {
                try controller.unregister()
            }
        } catch {
            isEnabled = controller.isEnabled
            errorMessage = enabled
                ? "DocShot could not be added to Login Items: \(error.localizedDescription)"
                : "DocShot could not be removed from Login Items: \(error.localizedDescription)"
            return
        }

        isEnabled = controller.isEnabled
        if isEnabled != enabled {
            errorMessage = enabled
                ? "macOS did not confirm DocShot in Login Items. Check System Settings."
                : "macOS did not confirm that DocShot was removed from Login Items. Check System Settings."
        } else {
            errorMessage = nil
        }
    }
}
