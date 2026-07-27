# LinkedIn post draft

I’ve been building **DocShot**: a native macOS capture utility for screenshots, screen recordings and lightweight annotation.

The interesting part for me was not simply getting pixels onto disk. It was making the capture flow trustworthy:

- everything stays local
- nothing is saved until you explicitly choose to save or copy
- temporary recordings are cleaned up on cancel, failure and quit
- system audio is opt-in
- screenshots and recordings have separate global shortcuts and cannot conflict

The current build includes screenshot annotation, H.264 MP4 recording, short GIF export and a post-stop video editor for trimming, splitting and annotation.

Built with Swift 6, SwiftUI, AppKit, ScreenCaptureKit and AVFoundation. The project has separate SwiftPM and Xcode test paths covering the recording state machine, cleanup, audio policy, export bounds and editor timing.

I’m now turning the implementation into a cleaner public project with a walkthrough and product screenshots.

GitHub: https://github.com/noel-q/docshot

#Swift #macOS #SwiftUI #ScreenCaptureKit #AVFoundation #BuildInPublic

---

Before publishing: add the final PR/release link only after the branch is merged, and attach the reviewed 20–30 second product demo. Do not claim notarisation, public distribution, or a shipped installer.
