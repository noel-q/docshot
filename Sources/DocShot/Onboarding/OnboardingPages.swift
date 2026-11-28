import CoreGraphics

/// The guide's five pages, in order (onboarding plan, agreed 25 November 2026). Pure, so the
/// order, the button words and the keys can be tested without a window.
enum OnboardingPage: Int, CaseIterable, Sendable {
    case welcome, screenshots, recording, clipboard, ready

    var title: String {
        switch self {
        case .welcome: return "Welcome to DocShot"
        case .screenshots: return "Take a screenshot"
        case .recording: return "Record the screen"
        case .clipboard: return "Keep what you copy"
        case .ready: return "Last, how saving works"
        }
    }

    /// The one accent button's words.
    var nextTitle: String { isLast ? "Start using DocShot" : "Next" }

    var isLast: Bool { self == Self.allCases.last }
    var next: OnboardingPage? { OnboardingPage(rawValue: rawValue + 1) }
    var previous: OnboardingPage? { OnboardingPage(rawValue: rawValue - 1) }

    /// "2 of 5", for the progress and VoiceOver.
    var progressText: String { "\(rawValue + 1) of \(Self.allCases.count)" }
}

/// What a key press does in the guide: Return goes on, Escape skips, the arrows move between
/// pages. Keys with Command, Option or Control are left alone.
enum OnboardingKey: Equatable, Sendable {
    case next, back, skip

    static let returnKeyCode: UInt16 = 36
    static let keypadEnterKeyCode: UInt16 = 76
    static let escapeKeyCode: UInt16 = 53
    static let leftArrowKeyCode: UInt16 = 123
    static let rightArrowKeyCode: UInt16 = 124

    static func action(keyCode: UInt16, hasCommandOptionOrControl: Bool) -> OnboardingKey? {
        guard !hasCommandOptionOrControl else { return nil }
        switch keyCode {
        case returnKeyCode, keypadEnterKeyCode, rightArrowKeyCode: return .next
        case leftArrowKeyCode: return .back
        case escapeKeyCode: return .skip
        default: return nil
        }
    }
}

/// The guide's size and place, in Cocoa screen coordinates.
enum OnboardingLayout {
    static let width: CGFloat = 460
    static let height: CGFloat = 480

    /// Centred on `visible`, a little above the middle, and kept inside it.
    static func frame(within visible: CGRect) -> CGRect {
        let width = min(Self.width, visible.width)
        let height = min(Self.height, visible.height)
        let x = visible.midX - width / 2
        // A third of the spare height above, two thirds below: the eye's centre, not the maths'.
        let y = visible.minY + (visible.height - height) * 2 / 3
        return CGRect(x: x.rounded(), y: y.rounded(), width: width, height: height)
    }
}
