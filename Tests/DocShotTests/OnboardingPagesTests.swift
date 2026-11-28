import CoreGraphics
import Testing
@testable import DocShot

@Suite("Onboarding pages")
struct OnboardingPagesTests {
    @Test("Five pages in the agreed order; only the last finishes")
    func order() {
        #expect(OnboardingPage.allCases == [.welcome, .screenshots, .recording, .clipboard, .ready])
        #expect(OnboardingPage.welcome.previous == nil)
        #expect(OnboardingPage.welcome.next == .screenshots)
        #expect(OnboardingPage.ready.next == nil)
        #expect(OnboardingPage.ready.isLast && !OnboardingPage.clipboard.isLast)
        #expect(OnboardingPage.allCases.dropLast().allSatisfy { $0.nextTitle == "Next" })
        #expect(OnboardingPage.ready.nextTitle == "Start using DocShot")
        #expect(OnboardingPage.recording.progressText == "3 of 5")
    }

    @Test("Return and the right arrow go on, the left arrow goes back, Escape skips; Command keys are left alone")
    func keys() {
        #expect(OnboardingKey.action(keyCode: 36, hasCommandOptionOrControl: false) == .next)
        #expect(OnboardingKey.action(keyCode: 76, hasCommandOptionOrControl: false) == .next)
        #expect(OnboardingKey.action(keyCode: 124, hasCommandOptionOrControl: false) == .next)
        #expect(OnboardingKey.action(keyCode: 123, hasCommandOptionOrControl: false) == .back)
        #expect(OnboardingKey.action(keyCode: 53, hasCommandOptionOrControl: false) == .skip)
        #expect(OnboardingKey.action(keyCode: 36, hasCommandOptionOrControl: true) == nil)
        #expect(OnboardingKey.action(keyCode: 0, hasCommandOptionOrControl: false) == nil)
    }

    @Test("The panel is centred a little above the middle and never larger than the screen")
    func frame() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let frame = OnboardingLayout.frame(within: screen)
        #expect(frame.size == CGSize(width: OnboardingLayout.width, height: OnboardingLayout.height))
        #expect(abs(frame.midX - screen.midX) <= 1)
        #expect(frame.midY > screen.midY)
        #expect(screen.contains(frame))
        let small = CGRect(x: 100, y: 50, width: 400, height: 300)
        #expect(small.contains(OnboardingLayout.frame(within: small)))
    }
}
