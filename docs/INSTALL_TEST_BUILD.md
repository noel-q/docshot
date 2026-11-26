# Installing a DocShot test build

For Noel and his testers. This is a test build: it is signed with Noel's Apple Development certificate but not notarised by Apple, so macOS asks once before opening it.

**Needs:** macOS 14 or later. It runs on Apple silicon and Intel Macs.

## Before you start (work laptops)

- A work laptop may be managed by your employer. Its rules can block apps that are not notarised, or the screen recording permission. If a step below is missing or greyed out, that is why, and only your IT team can change it.
- Check that installing your own apps is allowed on that laptop.
- Clipboard history is off until you switch it on. On a work laptop, think about whether you want it to keep what you copy. It stays on that Mac only, but it is still a record of work text and images.

## Install

1. Open `DocShot-macos-development.dmg`.
2. Drag **DocShot** onto **Applications**, then eject the disk image.
3. Open **Applications** and double-click **DocShot**. macOS says it cannot check it for malicious software. Choose **Done**, not Move to Bin.
4. Open **System Settings → Privacy & Security**. Scroll down to the line about DocShot and choose **Open Anyway**. Confirm with your password or Touch ID. You only do this once.
5. DocShot appears in the menu bar (the viewfinder icon), and the short guide opens.

## Permissions it asks for

- **Screen & System Audio Recording:** needed to take screenshots and recordings. DocShot shows the three steps when it needs it; turn DocShot on in the list, then choose Restart.
- **Accessibility** (only if you switch on clipboard history and want Return to paste for you): Settings → Clipboard → Pasting → Allow.

DocShot also adds itself to Open at login. You can switch that off in its Settings.

## Quick things to try

| Try | How |
| --- | --- |
| Screenshot | ⌃⌥⌘S, click a window or drag an area, then ↵ to copy |
| Record | ⌃⌥⌘R, pick an area, ↵ to start, ⌃⌥⌘R again to stop |
| Copy GIF | Record something up to 15 seconds, stop, then choose Copy GIF and paste into Messages, Slack or Mail |
| Clipboard history | Switch it on in Settings, copy a few things, then ⌃⌥⌘V |
| Captures | In the clipboard panel press Tab: recent screenshots and recordings |
| Float | ⌘F on a screenshot or image; Escape removes it |

## Removing it

Quit DocShot from its menu, drag it from Applications to the Bin, and delete `~/Library/Application Support/DocShot` to remove its history and captures, and `~/Library/Caches/DocShot` for the last copied GIF.

## Reporting a problem

Note what you did, what you expected, and what happened, with the macOS version (Apple menu → About This Mac). A screenshot helps.
