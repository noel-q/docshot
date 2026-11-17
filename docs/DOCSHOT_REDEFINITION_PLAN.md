# DocShot Redefinition Plan

Date: 13 November 2026. Status: approved, 17 November 2026. The open decisions are settled in section 10.

## 1. What changes

DocShot stops being "a screenshot and recording utility" and becomes Noel's personal capture and clipboard tool: screenshots, screen recording, and clipboard history in one quiet app, on macOS first and Windows second.

Decisions already made (13 November 2026):

| Decision | Outcome |
|---|---|
| Audience | Personal use. No outside testers planned. |
| Apple Developer membership and notarisation | Not needed. The `release/notarised-dmg` work is parked, not deleted. |
| Screen recorder | Stays, on both platforms. |
| Clipboard manager | Built into DocShot as a self-contained module, not a separate app. |
| Password manager | Separate project in its own folder. Not part of DocShot. See the DevVault kickoff prompt. |
| Windows | Full parity, resumed only after macOS reaches the stability bar in section 8. |
| Mobile | Out of scope for DocShot. iOS and Android do not let an app watch the clipboard in the background, and the OS owns screen capture. |

## 2. Product principles, revised

The old brief promised "no history library". A clipboard manager is a history, so that line goes. What replaces it:

1. **Local only.** Nothing leaves the machine. No accounts, sync, uploads or analytics. Unchanged.
2. **Quiet by default.** No Dock icon, no window until asked for. One hotkey or a menu bar click opens the main window; closing it puts the app back out of sight.
3. **History is bounded and yours.** Clipboard history is off until switched on, has hard size and age limits, can be paused, and can be wiped with one action.
4. **Secrets are never recorded.** Anything a password manager marks as concealed is skipped, and excluded apps are never read.
5. **Capture stays explicit.** A screenshot or recording still ends at Copy, Save or Discard. History only ever contains what reached the clipboard or what Noel chose to keep.
6. **Capture must not get worse.** With history off, nothing new is stored, and every v1.0.0 capture flow still ends the same way, at Copy, Save or Discard, with the full editor one click away. (Reworded 17 November 2026 so that Float, an optional editor action that stores nothing, fits; reworded again the same day for the preview thumbnail in section 7, which puts a small window in front of the editor after a screenshot.)

## 3. The main window

One window, opened on demand, three sections:

- **Clipboard:** searchable history, newest first, pinned items at the top. Search field has focus on open. Enter pastes into the previous app, Cmd+C copies only, Escape closes.
- **Captures:** the last 20 screenshots at most (reopen in the editor, copy again, save) and a list of saved recordings by file reference.
- **Settings:** the existing settings, plus the clipboard options in section 5.

The window has its own global shortcut. Defaults for all shortcuts are in section 13.

The app stays a menu bar app (`LSUIElement`). The window is an ordinary window, not a floating overlay, so it behaves predictably with Spaces and full-screen apps.

## 4. Architecture

### 4.1 Module boundary

The clipboard feature is isolated so that a fault in it cannot take capture down by design, and so it can be lifted into its own app later if it outgrows DocShot.

- **`ClipboardKit` (new local Swift package):** pure logic with no AppKit UI. Models, store, retention, de-duplication, exclusion rules, and a reducer for history state. Fully testable with `swift test`.
- **`Sources/DocShot/Clipboard/` (app side):** the pasteboard watcher, the paste action, and the SwiftUI views for the main window.
- **Rule:** nothing under `Capture/`, `Recording/` or `Editor/` imports `ClipboardKit`. The only shared pieces are the shell: `HotkeyService`, the main window, Settings, launch at login.
- **Test parity:** the Xcode test target is hostless and audited by `Scripts/audit-test-parity.sh`. New files must be declared in `Tests/target-parity.json`, and the audit gains a check for the import rule above.

Whether a local package or a plain folder is the better container is the one architecture question for the C0 spike. A package is cleaner but changes how the hand-maintained Xcode project builds.

### 4.2 Data model

```
ClipItem
  id            UUID
  createdAt     Date
  lastUsedAt    Date
  kind          text | richText | image | fileURLs | colour
  contentHash   SHA-256 of the canonical payload (de-duplication key)
  sourceApp     bundle identifier of the frontmost app at copy time, if known
  pinned        Bool
  byteSize      Int
  preview       short plain-text or thumbnail reference for the list
```

- **De-duplication:** copying something already in history moves the existing item to the top instead of adding a second one.
- **Storage:** SQLite through the system library, so the project keeps its zero-dependency policy. Image payloads are stored as files beside the database under `Application Support/DocShot/Clipboard/`.
- **Retention defaults:** 200 items, 30 days, 500 MB, whichever limit is hit first (confirmed 17 November 2026; review after the 14-day soak). Pinned items are exempt from age and count, but count towards the 500 MB cap and are never removed automatically. When the cap is full, a new pin is refused with a message saying why.
- **OCR text:** recognised text for an image item counts towards the 500 MB cap and is deleted with its item.
- **Clear cache:** one action wipes history and cached captures, and what it leaves behind is a setting (decided 13 November 2026): keep the last 5, keep the last 10, keep pinned only, or keep nothing. The default is keep pinned only. The same setting applies to both the Clipboard and Captures sections, and the action is available from the window, the menu bar and a shortcut.
- **At rest:** not separately encrypted in the first version. It relies on FileVault. Revisit if the Mac is ever shared.

### 4.3 Watching the clipboard (macOS)

- `NSPasteboard` offers no change notification, so the watcher polls `changeCount` on a timer (about twice a second) and reads only when it changes.
- Skip any item carrying the community pasteboard markers for concealed, transient or auto-generated content. Password managers set these.
- Skip anything copied while an excluded app is frontmost. Default exclusions: Bitwarden, Passwords, Keychain Access, 1Password.
- Ignore DocShot's own writes, so pasting from history does not create a new entry.
- A Pause control stops reading entirely until resumed.

### 4.4 Pasting into the previous app

1. Remember which app was frontmost when the window opened.
2. Put the chosen item on the pasteboard.
3. Close the window, reactivate that app, and send Cmd+V.

Step 3 needs macOS Accessibility permission, which DocShot has never asked for. Without it, the feature degrades to "copy and close" and the user presses Cmd+V themselves. The permission is requested only when clipboard history is switched on, never at first launch.

### 4.5 Captures in history

- A screenshot the user copies is a clipboard image like any other, so it appears in history automatically.
- The Captures section keeps recent screenshots with their annotation state, so "get the last one back" works. Between clears, captures follow the same 30-day and 500 MB limits as history, with a fixed cap of the 20 most recent screenshots (not a setting). What a Clear leaves behind follows the Clear cache setting in 4.2. This is on only when history is on.
- **Discard in the editor** still means "do not output this capture". With history on, the discarded capture stays in the cache until Clear cache removes it or retention ages it out. With history off, Discard destroys it immediately, as today.
- Recordings are never copied into history storage. Saved recordings appear as file references; temporary recordings keep today's cleanup rules exactly.

## 5. New settings

| Setting | Default |
|---|---|
| Clipboard history | Off |
| Shortcuts | See section 13; every global shortcut is rebindable |
| Keep items for | 30 days |
| Maximum items | 200 |
| Maximum storage | 500 MB |
| Paste directly into the previous app | On, once Accessibility is granted |
| Excluded apps | Bitwarden, Passwords, Keychain Access, 1Password |
| Keep recent screenshots | On when history is on |
| Pause history | Menu bar item and window button |
| Clear cache keeps | Pinned only (options: last 5, last 10, pinned only, nothing) |

Not settings, by decision (17 November 2026): the Captures cap of 20 screenshots is fixed, and OCR has no switch of its own; it runs whenever history is on.

## 6. Milestones

Each milestone is designed, built and verified on its own, the same gate the recording work used. Nothing moves on until the device checks pass and both test toolchains are green.

| ID | Scope | Exit check |
|---|---|---|
| C0 | Spikes. (a) Polling behaviour and any pasteboard privacy prompts on Noel's macOS 26. (b) Accessibility-based paste into another app. (c) Main window focus behaviour from a menu bar app. (d) Package versus folder for `ClipboardKit`. | A throwaway proof for each, and the four questions answered in this document. |
| C1 | `ClipboardKit` core: models, SQLite store, de-duplication, retention, exclusion rules, reducer. No UI. | Unit tests for every rule in 4.2 and 4.3, passing in SwiftPM and Xcode. |
| C0.5 | Shortcut rework from section 13: one rebindable registry for every global shortcut, new defaults, conflict warning in Settings, single-key tool shortcuts in the editor. Ships before any clipboard work because it also fixes today's conflicts. | All global shortcuts rebindable and persisted; old bindings migrated; no default collides with the list in 13.2. |
| C0.6 | Preview thumbnail after a screenshot (section 7). Added 17 November 2026 at Noel's request. Starts only after C0.5 is committed, with its own short plan first. | Copy, Discard, Edit and Save all work from the thumbnail; only Edit opens the full editor; nothing is written to disk before Save; recording flow unchanged. |
| C2 | Watcher, main window with read-only history, copy back to the clipboard, Settings toggle, pause, clear. | History survives relaunch; concealed and excluded copies never appear; capture unchanged with the toggle off. |
| C3 | Paste into the previous app, pinning, search, keyboard navigation. | Paste works in a browser, a terminal and a native text field; degrades cleanly without Accessibility. |
| C4 | Captures section: recent screenshots, recording references. | Reopen, re-copy and save all work; Discard plus Clear leaves nothing on disk. |
| C4a | OCR for history search (section 7). | Image items are found by their text; "Copy text" works; no OCR runs with history off; idle CPU stays flat. |
| C4b | Float on screen (section 7). | Float opens from the editor, Captures and history; works with history off; nothing is written to disk; no float survives quit. |
| Freeze | Feature set frozen in writing once C4a and C4b pass their device checks. Later ideas go to BACKLOG.md for after Windows. | Stability bar point 6. |
| C5 | Hardening and soak. | The stability bar in section 8. |
| W | Windows resumes. | See section 9. |

**Who builds (decided 17 November 2026).** One lane, one unit at a time, no parallel builders. Claude Opus 5.5 at High effort orchestrates and builds every unit; read-only subagents are allowed for large reads. Claude Fable reviews each unit from the diff before it is committed. Codex and Antigravity are not used on the Mac work. This project rule takes precedence over the general model split in the handoff skill.

**Testing rules (decided 17 November 2026).**
1. Automated tests use a private, uniquely named pasteboard and scratch preferences, never the general pasteboard or `com.docshot.app`.
2. An agent tells Noel first before driving the running app against the real clipboard, the real preferences or the system hotkey table.
3. Clipboard device checks are run by Noel.

## 7. Capture features: in or out before the freeze

Windows ports a frozen feature set, so every capture feature added now is one more thing to port. Decided 17 November 2026:

| Feature | Decision | Reason |
|---|---|---|
| OCR (Vision, local) | In, as C4a | Cheap on macOS, and makes image items searchable in history. |
| Preview thumbnail after capture | In, as C0.6 (added 17 November 2026) | Noel's request after using C0.5: most captures only need Copy or Save, so the full editor should not open every time. |
| Float on screen (was "pin to screen") | In, as C4b | Small, and fits the "quiet tool" idea. Renamed so it is not confused with pinned history items. |
| Step counter annotation | Out for now | Nice to have; adds editor and export surface on both platforms. |
| Pixelate redaction | Out for now | Opaque redaction is safer and already shipped. |
| Scrolling capture | Out | Most expensive and least reliable item on the old backlog. |
| Microphone audio | Out for now | Modelled but not implemented; needs a new permission and entitlement. |

**OCR scope.** OCR only feeds history search, plus a "Copy text" action on image items in history. It runs only when history is on, once per image, in the background at low priority, after the image is stored, in the system languages. The image editor gets no OCR button.

**Float scope.** Float starts from the image editor and from an image in Captures or history. Several images can float at once. Each floating window stays above other windows and can be dragged; Cmd+C copies it, and Escape or its close button removes it. Floating writes nothing to disk, floats are gone after quit, and Float works with history off.

**Preview thumbnail scope.** After a screenshot is taken, a small window shows a thumbnail of it with four icon buttons: Copy, Discard, Edit and Save. Only Edit opens the full editor used today; the other three finish the capture from the thumbnail. Decided by Noel, 17 November 2026. Proposed, to be confirmed in the slice's short plan before any build: screenshots only, recordings keep today's flow; the thumbnail stays until one of the four actions is taken, with no timed dismissal, because a silent timeout would be a Discard nobody chose (principle 5); Escape discards, as in the editor; no new global shortcut and no new setting; nothing is written to disk before Save. One more item for Windows to port.

**Preview thumbnail plan (agreed by Noel, 17 November 2026).** The "proposed" items above are confirmed. In addition:
1. A new screenshot while the thumbnail is up asks before discarding it, as the editor does today.
2. Recording stays blocked until the thumbnail is resolved, as with the editor; the capture state stays `editing` while it is up.
3. The thumbnail takes keyboard focus without activating DocShot. Return and Cmd+C copy and close, Cmd+S saves, Escape discards, clicking the image opens the editor. Focus returns to the previous app afterwards.
4. It appears in the bottom-right corner of the display the screenshot came from, clear of the Dock.
5. Copy and Save from the thumbnail use the full captured size; export size options stay in the editor.
6. Built in this session by Opus 5.5 on `feature/c0.6-preview-thumbnail` (cut from `feature/c0.5-shortcuts`); Fable reviews the diff; Noel runs the device checks before any commit.

## 8. Stability bar ("dream stability", written down)

macOS is done, and Windows may start, when all of these hold:

1. Fourteen consecutive days of Noel's daily use with no crash and no hang.
2. No orphaned temporary recording and no stray history file after any of: quit, crash, cancel, Clear all.
3. The clipboard watcher costs no measurable CPU at idle and memory stays flat across a full day.
4. `swift test`, `xcodebuild test` and the parity audit are all green.
5. Every device check in `docs/DEVICE_VERIFICATION.md`, including new clipboard sections, is recorded as passed with the macOS version and hardware noted.
6. The feature set in sections 3 to 7 is frozen in writing.

## 9. Windows, when it resumes

- Merge `windows/core-bootstrap`, `windows/app-dpi-overlay-shell` and `windows/platform-w0-spikes` into `main` now, before any of the above. Nothing under `windows/` is built by the Mac project, and the branches are already 15 commits behind.
- Existing milestones W1 to W7 stand. Add:
  - **Core:** port `ClipboardKit` models and rules to `DocShot.Core`.
  - **Platform:** clipboard change listener (Windows has a real notification, so no polling), respect the Windows "exclude from clipboard history" format, send paste to the previous window.
  - **App:** the same three-section main window, opened from the tray or a hotkey.
- Two known gaps must be fixed, not carried: the HUD Pause button that only pauses the timer, and the Show Cursor setting that has no effect.
- Windows 11 already ships a basic clipboard history on Win+V. The DocShot version has to earn its place through search, pinning and capture integration.

## 10. Decisions for Noel (all settled)

1. ~~Shortcut scheme~~ Decided: three rebindable global shortcuts on Control+Option+Command, plus single-key editor tools. See 13.3.
2. ~~Retention defaults~~ Decided 17 November 2026: 200 items, 30 days, 500 MB, reviewed after the 14-day soak. Pinned items count towards storage; captures share the limits with a fixed cap of 20. See 4.2 and 4.5.
3. ~~Recent screenshots after Discard~~ Decided: a configurable Clear cache (keep last 5, last 10, pinned only, or nothing). See 4.2 and 4.5.
4. ~~OCR and pin-to-screen~~ Decided 17 November 2026: both in, as C4a and C4b; pin-to-screen renamed Float; the other four stay out; the freeze follows C4a and C4b. See sections 6 and 7. Principle 6 reworded in section 2.
5. ~~Name~~ Decided 17 November 2026: keep "DocShot". Changing the bundle ID would likely reset preferences and permissions (assumed, not tested).
6. ~~Who builds what~~ Decided 17 November 2026: a single lane. Opus 5.5 at High effort orchestrates and builds; Fable reviews each unit from the diff. See section 6. DocShot stays Tier C with no due date.

## 11. Documents to update once this is approved

- `docs/PRODUCT_BRIEF.md`: new summary and principles from sections 1 and 2.
- `README.md`: the "Privacy by design" section and the feature list.
- `docs/BACKLOG.md`: replace with section 7.
- `docs/DEVICE_VERIFICATION.md`: add clipboard sections per milestone.
- `windows/docs/PARITY_CHECKLIST.md`: the "no silent history" rule becomes the bounded-history rules in section 2.

## 12. Risks

| Risk | Mitigation |
|---|---|
| A watcher bug destabilises capture | Module boundary, off by default, import rule enforced by the audit script. |
| macOS tightens pasteboard access | C0 spike on the current OS before any build work; polling reads only on change. |
| A secret lands in history | Concealed markers, app exclusions, pause, and tests for each. |
| Accessibility permission is refused or reset | Paste degrades to copy-only; never blocks the rest of the app. |
| Scope creep delays Windows again | Section 7 is the whole list; anything new waits until after the freeze. One exception so far: the preview thumbnail, added by Noel on 17 November 2026. |

## 13. Shortcuts

### 13.1 What exists today (audited from `main`, 13 November 2026)

| Scope | Action | Binding | Rebindable |
|---|---|---|---|
| Global | Screenshot | Cmd+Shift+6 (presets: Cmd+Shift+5, Cmd+Shift+7, Option+Shift+S, or custom) | Yes |
| Global | Start or stop recording | Cmd+Shift+8 | No, hard-coded |
| Global | Cancel a pending capture | Escape (registered only while a capture is pending) | No |
| Capture overlay | Cancel / refresh frozen screen | Escape / R | No |
| Recording confirm | Record / cancel | Return / Escape | No |
| Image editor | Undo, redo, delete, save, copy, discard | Cmd+Z, Shift+Cmd+Z, Delete, Cmd+S, Cmd+C, Escape | No |
| Video editor | Split, play or pause, undo, redo, delete, save, close | Cmd+K, Space, Cmd+Z, Shift+Cmd+Z, Delete, Cmd+S, Escape | No |
| Windows branch | Screenshot | Ctrl+Shift+S | No |

### 13.2 Problems found

1. **The defaults steal shortcuts from other apps.** A global hotkey wins over the frontmost app. Cmd+Shift+7 and Cmd+Shift+8 are numbered and bulleted list in Google Docs, Slack, Notion and others, so recording on Cmd+Shift+8 breaks bullet lists everywhere while DocShot runs.
2. **Cmd+Shift+5 is offered as a preset** but belongs to the macOS screenshot toolbar.
3. **The recording shortcut cannot be changed.** Settings only displays it.
4. **No tool shortcuts in the image editor.** The product brief asked for them; the toolbar only has tooltips. Every tool change needs the mouse.
5. **Escape in the editor discards with no undo.** Once the cache exists this is recoverable, which is another reason to land the cache.
6. **Windows uses Ctrl+Shift+S**, which is "Save As" in most Windows apps.

### 13.3 Decided scope (14 November 2026, Noel delegated the call)

The rule: three global shortcuts, no more. Everything else is a menu item or a key inside a window. Sized to fit in one to two days.

**Global shortcuts (all three rebindable):**

| Action | Default | Replaces |
|---|---|---|
| Screenshot | Control+Option+Command+S | Cmd+Shift+6 |
| Record (start or stop) | Control+Option+Command+R | Cmd+Shift+8 |
| Open DocShot window | Control+Option+Command+V | new; registered only once the window exists (C2) |

Control, Option and Command sit together at the bottom left, so each is a one-hand chord, and almost nothing else uses that family. The Cmd+Shift+number row was rejected because it collides with list formatting; Control+Option+letter because window managers such as Rectangle use it.

**Image editor tool keys** (while the canvas has focus and no text is being edited):

| Key | Tool |
|---|---|
| V | Select / move |
| A | Arrow |
| R | Rectangle |
| O | Ellipse |
| T | Text |
| H | Highlighter |
| X | Redaction |
| C | Crop |
| Return | Copy and close |

**Deliberately cut to keep it light:**

- No global shortcuts for clear cache, pause history or "paste previous item". They are menu bar items and window buttons.
- No preset list. The four presets (including the conflicting Cmd+Shift+5 and Cmd+Shift+7) are removed; each action gets the existing shortcut recorder and a reset-to-default button.
- No known-conflict database. Settings shows the existing "failed to register" error and nothing more.
- Video editor and overlay keys are unchanged.
- Main window keys (search, arrows, Return to paste, Escape) arrive with the window in C2 and C3, not in this slice.

### 13.4 Build notes

- `HotkeyService` currently has one configurable slot and one hard-coded slot. Generalise to a small table keyed by action (screenshot, record, openWindow), each with a default, a saved override in `UserDefaults`, and a handler. `CustomShortcutRecorder` is reused as is.
- Migration: a saved custom screenshot shortcut is kept. A saved preset is kept as a custom binding. Recording moves to the new default because it never had a saved value.
- Tool keys are a key handler on the editor canvas mapped to `AnnotationTool`; tooltips gain the key.
- Tests: default table, override persistence, migration from preset and custom, and the tool key map. `TemporaryEscapeHotkeyTests` must keep passing untouched.
- Windows defaults are decided when Windows resumes. The likely idiom is the Print Screen family, as ShareX uses, not a port of the Mac chords.
