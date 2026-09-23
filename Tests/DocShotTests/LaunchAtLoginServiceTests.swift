import Testing
import Foundation
@testable import DocShot

@MainActor
@Suite("Launch at Login Tests")
struct LaunchAtLoginServiceTests {
    private final class FakeController: LaunchAtLoginControlling {
        var isEnabled = false
        var registerCalls = 0
        var unregisterCalls = 0
        var registerError: Error?
        var unregisterError: Error?

        func register() throws {
            registerCalls += 1
            if let registerError { throw registerError }
            isEnabled = true
        }

        func unregister() throws {
            unregisterCalls += 1
            if let unregisterError { throw unregisterError }
            isEnabled = false
        }
    }

    private enum TestError: LocalizedError {
        case refused

        var errorDescription: String? { "macOS refused the request" }
    }

    @Test("Initial state is off and does not register a login item")
    func initialStateDoesNotRegister() {
        let controller = FakeController()
        let service = LaunchAtLoginService(controller: controller)

        #expect(service.isEnabled == false)
        #expect(controller.registerCalls == 0)
        #expect(controller.unregisterCalls == 0)
    }

    @Test("Enabling registers exactly once after an explicit setting change")
    func enablingRegisters() {
        let controller = FakeController()
        let service = LaunchAtLoginService(controller: controller)

        service.setEnabled(true)

        #expect(service.isEnabled)
        #expect(service.errorMessage == nil)
        #expect(controller.registerCalls == 1)
        #expect(controller.unregisterCalls == 0)
    }

    @Test("Disabling unregisters and confirms the removed state")
    func disablingUnregisters() {
        let controller = FakeController()
        controller.isEnabled = true
        let service = LaunchAtLoginService(controller: controller)

        service.setEnabled(false)

        #expect(service.isEnabled == false)
        #expect(service.errorMessage == nil)
        #expect(controller.registerCalls == 0)
        #expect(controller.unregisterCalls == 1)
    }

    @Test("A failed removal preserves the system-reported enabled state")
    func failedRemovalReportsActualState() {
        let controller = FakeController()
        controller.isEnabled = true
        controller.unregisterError = TestError.refused
        let service = LaunchAtLoginService(controller: controller)

        service.setEnabled(false)

        #expect(service.isEnabled)
        #expect(service.errorMessage?.contains("could not be removed") == true)
        #expect(controller.unregisterCalls == 1)
    }
}
