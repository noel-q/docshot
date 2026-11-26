# DocShot progress log

Dated detail that does not fit on the one-page STATUS.md. Newest first. Each entry keeps
its original evidence label (verified, inherited, assumed, unknown).

## 2026-11-26
- Noel: units 1 to 6 "all look fine"; run the review and freeze. He asked for two features first and chose to build them before the freeze: Copy GIF (a button, not an automatic setting) and update notices from GitHub Releases (with the DMG on the release).
- Copy GIF (c0eacea) and update notices (9e15451), then one Fable review of those and Clear while off: no serious defect; fixed the guide reopening after a manual check, the automatic guide taking the keyboard, a found update lost on relaunch, an unreadable answer read as up to date, no sign when the GIF was ready, a copy failure leaving a stray file and the wrong title, and older copied GIFs in history pasting the newest one (e8f4d1c). 392 tests in both runs.
- Feature freeze written into the plan. C5 starts with the next test build.

## 2026-11-25
- Clear while history is off (07ed1ac, feature/clear-while-off): with history off, DocShot
  counts what is still stored at launch and on switching off, and offers Clear in Settings and
  the menu bar menu. Clear opens the store only if history was ever kept and closes it after;
  it shares the controller's store slot and queue, so switching on meanwhile reuses it. Three
  new tests; swift test 384, xcodebuild test 384. In the app (scratch store): Settings showed
  "History is off. 14 items still stored; this removes 13."; a relaunch read the same count;
  Clear left the pinned item and removed all five screenshot files. Menu item not seen.
  Fable review waits for the next batch.
- Road to C5 agreed: units 1 to 6 back to back, one Fable review at the end, each unit
  committed on its own local branch as it passes Claude's checks (Noel's choice). C5 testing
  may include Noel's two testers.
- Batch review (one Fable review of units 1 to 6, as Noel asked): no data-loss defect. Fixed:
  the newest screenshot is never evicted for storage (history at the cap used to empty
  Captures at once); text reading really runs at background priority, stops on a failed write
  and does not retry an image in the same run; storing a screenshot or text re-checks that
  history is still on, not paused and the same store after each wait; the editor's marks wait
  for their own capture's id; Cmd+E in Captures is refused during a recording; Tab and Return
  leave focused controls alone under keyboard navigation; one accent in the video editor; the
  Float image file is read off the main thread. Left for Noel: with history off, Clear is
  disabled while kept screenshots stay on disk (the inherited "stays until Clear" decision now
  covers screenshots). ClipboardKit 83, swift test 381, xcodebuild test 381, no debug symbols
  in Release. Re-verified in the app (agent): text read and found, Float from Captures, Cmd+E.
- Unit 6, C4b Float, on `feature/c4b-float`: an image in its own borderless window above the
  others, at most 480 points on its long side, cascaded from the centre of the screen in use;
  from the editor (a Float button and Cmd+F, marks drawn in), from Captures (Cmd+F, with marks)
  and from an image in history (Cmd+F); several at once; drag to move; Cmd+C copies; Escape,
  Cmd+W or the close button on hover removes it; held in memory only. swift test 381,
  xcodebuild test 381, Release build has no debug symbols. Verified (agent, scratch store): two
  floats at once, one from Captures through the real key monitor (250x400 with marks), Escape
  removed each, a snapshot, and no new file in the store after floating. Not run: Float from the
  editor and from history in the app, Cmd+C on a float (real clipboard), dragging.
- Unit 5, C4a text in images, on `feature/c4a-ocr`: schema 3 adds the recognised text to image
  items; Vision reads each stored image once, in the background at low priority, only while
  history is on (new images at once, older ones when history turns on); unreadable images are
  marked read so they are not retried; the text counts towards the storage cap and goes with its
  item; search finds images by their text; the preview pane shows "Text in this image" with
  Copy text (Shift+Cmd+C), written as DocShot's own copy so it is not recorded again.
  ClipboardKit 83 tests (2 new), swift test 379, xcodebuild test 379. Verified (agent, scratch
  store): a drawn test image read as "Quarterly invoice 4417 | Café Noir, Leeds"; "cafe invoice"
  and "4417" found it; the preview pane snapshot; the app's CPU at 0.0 to 0.5% once reading
  finished. Not run: Copy text (it would change the real clipboard), a long idle soak.
- Unit 4, C4 Captures, on `feature/c4-captures` (plan "C4 plan" in section 3): schema 2 adds a
  `captures` table and an owner-only `Captures` folder; screenshots are kept when taken (history
  on and not paused) and their marks and crop are saved whenever the editor closes; MP4, edited
  MP4 and GIF saves add a recording reference; limits are 20 screenshots and 20 recordings, the
  age limit, and the shared storage cap (oldest screenshots first); one Clear removes history and
  captures together. The panel gains Clipboard and Captures tabs (Tab switches): a thumbnail grid,
  then recordings (a moved file says so); Return copies with marks and closes, Cmd+C copies,
  Cmd+E reopens in the editor with marks, Cmd+S saves, Cmd+Delete deletes, arrows move.
  ClipboardKit 81 tests (5 new), swift test 378, xcodebuild test 378. Verified (agent, scratch
  store): seeded section snapshots in dark and light; arrows, Cmd+Delete and Cmd+E through the
  real key monitor. Not run: Return, Cmd+C and Cmd+S (they would change the real clipboard or
  open a save panel), a real screenshot and its marks coming back after Discard, a real recording
  save adding a reference.
- Unit 3, video editor in Quiet, on `feature/quiet-video-editor`: the tools, colours and
  widths are one shared bar for both editors (`AnnotationStyleBar`), with shared icon buttons;
  top bar with esc Back, the recording's details, Discard... and Save MP4... as the one accent
  with its key; Split with its key; neutral transport, scrubber and clip cards ("Clip 1",
  Start and End with "To playhead"); nothing under 12 pt; sentence-case alerts. The window
  now follows macOS light or dark (it was always dark) and opens at 1000 pt, at least 960,
  so the drawing bar fits in one row. A DEBUG hook `open-video:<path>` opens it on a test
  clip. swift test 375, xcodebuild test 375. Verified (agent): snapshots in dark and light.
  Not seen: the video picture (the player layer does not draw into snapshots), playing,
  trimming, splitting, drawing on video, saving.
- Unit 2, image editor in Quiet, on `feature/quiet-image-editor`: toolbar and action bar
  on `surface`, canvas on `canvas` with a margin, title bar blended; tool, width and colour
  selection neutral (`selection`, an `ink` ring), annotation colours untouched; Copy the one
  accent with its key, Save with its key, esc Discard; size control and its popover on
  tokens, nothing under 12 pt; every behaviour and shortcut kept. swift test 375,
  xcodebuild test 375. Verified (agent): snapshots in dark and light. Not seen: drawing,
  the size popover, Save and Copy in use.
- Unit 1, permission window in Quiet, on `feature/quiet-permission-window`: compact panel,
  three numbered steps, the accent moves from Open to Restart, Return and Escape, re-check on
  coming back. swift test 375, xcodebuild test 375. Verified (agent): snapshots of both
  states in dark and light through the DEBUG hook. Not seen: the real grant flow (DocShot's
  permission was not removed). Fable review waits for the batch.
- Compact Settings panel committed as d6bd354 with Noel's yes ("Feels right").
- Onboarding guide committed as 6f358c3 with Noel's yes ("Feels right").
- Record shortcut now stops a recording (Noel: "Yes, fix it"), on `fix/record-shortcut-stop`,
  uncommitted. `CaptureActivityPolicy.recordShortcutAction`: stop in `.starting` and
  `.recording` (the same call and condition as the menu's Stop Recording and the Stop
  button), start when idle, otherwise beep. The guide says "Press again to stop" again.
  Fable review: no defects; its test-coverage nit and wording nit applied. swift test 375,
  xcodebuild test 375. Device: Noel started a recording and stopped it with the shortcut
  ("It stopped"). User-reported.
- Onboarding guide in Quiet (plan agreed 25 November: "Yes, build it") built on
  `feature/quiet-onboarding`, uncommitted. A 460x480 borderless panel, centred a little above
  the middle of the screen in use, draggable; five pages (Welcome with the live shortcuts,
  Screenshots with the thumbnail keys, Recording, Clipboard history with its switch, Ready
  with saving and open at login). Next is the one accent button; Return and the right arrow
  go on, the left arrow goes back, Escape skips, Cmd+W closes without marking it done; held
  keys are ignored. The General tab's Saving group became `SavingSettingsGroup`, shared with
  the guide, and it now re-reads the saved choice when it checks the folder. Fable review:
  one defect, kept out of the guide rather than fixed: the record shortcut does not stop a
  recording (DocShotApp.swift beeps unless idle; inherited since 8354868), although
  DEVICE_VERIFICATION records it as a user-reported pass on 17 November. The guide now names
  the Stop button and the menu instead. The other points fixed: reopening during the
  fade-out, quick presses adding up, arrows left to a focused control, a page that outgrows
  the panel scrolls, the hook-only `select` inside `#if DEBUG`, spoken names for the key
  hints. swift test 374, xcodebuild test 374, parity OK, no debug symbols in Release.
  Verified (agent, DEBUG hooks and scratch store): first launch shows it; Return, the arrows
  and Escape through the real key monitor, two quick Returns land on page 3, reopening during
  the fade-out keeps it; snapshots of all five pages in dark and light. Not seen: the slide
  between pages, the Ready page with a folder chosen (would change real preferences), arrows
  with keyboard navigation on.

## 2026-11-24
- Compact clipboard panel committed as 4f5544c with Noel's yes ("Feels right").
- Compact Settings panel (compact panels, point 4) built on `feature/quiet-compact-panels`,
  uncommitted. Settings... opens a 380 pt borderless panel under the menu bar icon with the
  everyday settings (theme dots, clipboard history and pause, the open-history shortcut,
  how saving works, open at login); "All settings" grows it in place to an in-panel tab strip
  with a back arrow and returns to the tab last open; Change... expands to the right tab
  instead of a sheet. It closes on Escape, Cmd+W, the menu item, a click on another DocShot
  window or another app, but stays open while DocShot's own sheet, folder picker or a trip
  to System Settings for a permission is under way. On a short screen the page cap drops so
  the tab strip stays on screen. Fable review: two defects (closing on the trip to System
  Settings; not closing on a click on another DocShot window) and seven smaller points, all
  fixed except one choice kept on purpose: the panel fill stays `canvas` so the `surface`
  groups inside read. Also added Cmd+Y to the Shortcuts tab's window keys, with a test.
  swift test 371, xcodebuild test 371, parity OK, no debug symbols in Release.
  Verified (agent, DEBUG hooks and scratch store): frame traces ease with no jumps (expand
  380x506 to 560x415, switch to Shortcuts 415 to 690, General 276); opening the clipboard
  panel closed Settings; snapshots of compact and Shortcuts in dark and light. Not yet seen:
  Cmd+W, "All settings" returning to the last tab, staying open through System Settings,
  and opening from the real menu bar icon (Noel's look).
- Preview thumbnail committed as bd76322 with Noel's yes.
- Compact panels (six answers agreed): the clipboard part built on
  `feature/quiet-compact-panels`, uncommitted. A borderless rounded panel (420 pt, `surface`,
  system shadow) that rises in, opens in the upper middle of the screen in use, can be
  dragged and remembers its place; Cmd+Y or the footer hint slides the preview pane out to
  780 pt and back. Frame traces found three causes of snapping, all fixed: content that
  forced the window size (`sizingOptions = []`, `minWidth: 0`), a layout change during the
  window animation (content changes first, animation on the next turn), and the pane's
  presence while narrowing (it fades first). Every toggle now eases over about 14 frames.
  The filter became a plain menu (a tinted menu picker was nearly invisible in light mode).
  Found and fixed during the work: the panel's preview choice and place were written to the
  real `com.docshot.app` from debug runs (two new keys, deleted; now through the
  controller's preferences, with a test). Fable review: no contradiction; fixed footer
  overflow without Accessibility, overlapping animations (counter), the place drifting after
  widening near the edge, partly off-screen places, edge-of-screen pointer, surface fill,
  12 pt chevron, curve token, trace commands gated on the scratch store. swift test 367,
  xcodebuild test 367, ClipboardKit 76, parity OK, Release clean. Real history setting found
  on (store empty, unchanged since 11:24), left as Noel's choice.
- Settings committed as b958886 with Noel's yes.
- Quiet pilot step 3, preview thumbnail (six answers agreed) built on
  `feature/quiet-thumbnail`, uncommitted: floating `surface` panel with `radius-lg` and the
  system shadow; Copy is the one accent button labelled with its key; Save, Edit, Discard as
  icons with keys under them; Cmd+E opens the editor; an Edit pill on hover over the image;
  the window rises and fades in over dur-base (fade only with Reduce Motion) and leaves at
  once. Checked from app-rendered snapshots in dark and light (hover pill not seen). Fable
  review: no contradiction; fixed an exit fade that kept the keyboard for 0.16 s, the shadow
  during the rise (now the window itself animates), an overcounted row width (now 232 pt,
  tested against the literal sum), off-step spacing. swift test 358, xcodebuild test 358.
- Noel asked for Settings and the clipboard window to be less in-your-face, like the
  thumbnail: compact floating panels that expand when needed. Sketch given; short plan next.
- Quiet pilot step 2 committed as bd2dd88 with Noel's yes ("Looks right").
- Quiet pilot step 3, Settings (seven answers agreed; Settings stays its own window, the C4
  move into the DocShot window dropped) built on `feature/quiet-settings`, uncommitted:
  toolbar tabs General, Clipboard, Capture, Shortcuts (window title and height follow the
  tab, capped at 640 pt of content so it fits a 13-inch display, then scrolls); groups of
  rows in Quiet panels; switches tinted with the accent, buttons and segmented controls
  neutral; Clear confirms with the exact count in Settings, the clipboard window and the
  menu bar; restyled shortcut recorder. Checked by the agent from app-rendered snapshots of
  every tab in dark and light on scratch data, and the window title and size per tab.
  Fable review: three defects (the Clipboard tab taller than a 13-inch display with no
  scrolling; the layout test blind to it; garbled recorder titles) and six smaller points,
  all fixed; mutation check on the height cap done. Final: swift test 355, xcodebuild test
  355, ClipboardKit 76, parity OK, Release has no debug symbols.
- Noel: the Settings tab switch looked "like a PowerPoint", and the clipboard window's keys
  were missing from Settings. A DEBUG trace of the window height per frame showed the cause:
  NSTabViewController cross-faded for about 0.6 s and then jumped to the new height in one
  frame (tabs measured their height only after drawing). Replaced with a custom Settings
  window controller: preferences toolbar, content swapped at once, the window easing to
  each tab's height over dur-base (ease-out, Reduce Motion respected), tabs sized up front,
  in-tab changes eased too. Re-traced: every switch eases over about 14 frames, no jumps.
  Added an "In the DocShot window" group to Shortcuts listing the seven window keys, with a
  test that each listed key does what it says. swift test 355, xcodebuild test 355, ClipboardKit 76.
- Noel: Settings did not say how to open the clipboard or let it be configured where he
  looked. The shortcut was there but named "Open DocShot window"; renamed "Open clipboard
  history" (menu bar item "Open Clipboard History"), and the Clipboard tab now starts with
  that row: the shortcut, Change... and Reset, shown even with history off.
- Viewfinder icon committed as 3f86759 with Noel's yes.
- Quiet pilot step 2 (plan section 3, five points agreed; Noel chose Tide for Graphite and
  Ember as default) built on `feature/quiet-tokens`, uncommitted: themes Ember (default),
  Tide, Slate, Moss on Quiet neutrals, a saved "graphite" loads as Tide; DesignTokens names
  unchanged. Checked by the agent from app-rendered snapshots of Settings, preview thumbnail,
  image editor, onboarding and permission window in dark and light, plus a live switch from
  Ember to Tide with windows open (scratch preferences, so the real theme stayed Moss).
  Fable review: one defect (white labels on accent at about 2:1 in dark mode) and several
  risks, all fixed: labels on accent use Quiet on-accent while the window is active; Settings
  tints checkboxes only; onboarding step bars use control-edge; debug theme switching only on
  the scratch store; stronger theme tests. Final: swift test 354, xcodebuild test 355,
  ClipboardKit 76, parity OK, Release has no debug symbols. The editors' system dividers draw
  opaque in snapshots; likely a snapshot artifact, not seen in the app (unknown).
- Quiet restyle committed as 9a1120d on `feature/quiet-clipboard` with Noel's yes.
- New app icon "Viewfinder" (Noel's pick from the Quiet icon bake-off; files from
  `~/Documents/quiet-design/icons/docshot/final/`) installed: AppIcon PNGs swapped (same names
  and Contents.json), and a `MenuBarIcon` template image set replaces the "viewfinder" SF
  Symbol in the menu bar. Verified: the built Assets.car holds both, the menu bar image in
  template mode; macOS's own icon for the built app shows Viewfinder; DocShot's status item,
  rendered through the DEBUG hook (`menubar:`), draws black in light and white in dark.
  swift test 352, parity OK. Uncommitted.
- C3 committed as 9ef04d1 on `feature/c3-paste` with Noel's yes, local only.
- Quiet restyle of the clipboard window (plan section 3, "Quiet restyle", eight answers
  agreed) built on `feature/quiet-clipboard`, uncommitted: generated `QuietTokens.swift`
  (Scripts/generate-quiet-tokens.py from Quiet's tokens.json), `Quiet.swift` (accent follows
  the Settings theme), the new layout, type-aware previews, the type filter, Cmd+1 to Cmd+9,
  Pinned/Today/Earlier groups. Checked by the agent from snapshots the app rendered of the
  real window in dark and light (DEBUG hook, scratch store via `DOCSHOT_DEBUG_STORE`, never
  the real history). Fable review: one defect (blurry image previews from a shared thumbnail
  cache) and several risks and nits, all fixed, including Return no longer turning history on
  (not agreed) and debug commands refusing the real store. Tests: swift test 352,
  xcodebuild test 353, ClipboardKit 76, parity OK, Release has no debug symbols.
  Noel looked at it running on sample data: "Looks good", and the filter, the "..." menu
  and the search field all take clicks (user-reported). Scratch data cleaned up.
- C2 committed as b89d700 on `feature/c2-clipboard-window` with Noel's yes, local only.
- C3 plan agreed (nine answers, plan section 3 "C3 plan"); Noel added "No limit" for items
  and asked for the window's look to wait for his new design system. Built on
  `feature/c3-paste`, uncommitted: paste into the previous app via Accessibility and Cmd+V
  with the layout's V key; search (full text, case and accents ignored, store-side index
  released when the window closes); keys; pins group; delete; editable limits with a
  confirmation; editable excluded apps; previous-app tracking. Fable review: two defects
  (keys acting on the list before a pending search settled; Allow button not counting as
  the one-time request) and seven risks, all fixed; re-review confirmed the fixes and five
  smaller follow-ups were fixed too. A crash found in testing: keyboard layout calls off the
  main thread abort, so `PasteKeystroke` is main-actor bound. Tests: swift test 339,
  xcodebuild test 340 (hotkey suites skipped), ClipboardKit 76, parity audit OK; mutation
  check on the settled-selection fix done. Not yet run in the app.
- C3 device checks (table in DEVICE_VERIFICATION.md, "C3 Paste, Search, Keys, Pins"):
  TextEdit, Chrome, the Claude app and Terminal all paste. The Claude app failed first:
  Cmd+V needed the left-Command device bit, and is now posted at the session tap. Added a
  focus wait (Accessibility, up to 400 ms) and a check that the target is still in front
  before the keystroke. Added a DEBUG-only hook so the agent can drive the window itself
  after Noel said many checks could have been agent-run. Two of the agent's test pastes went
  to the wrong app (Chrome, WhatsApp), with Cmd+V only, never Return; the hook now refuses
  any target but the named one. Test history cleared, history off.
- Fable check of the post-review changes: no defect; hardening applied: Accessibility focus
  queries time out after 0.1 s; the hook listens only when launched with
  `DOCSHOT_DEBUG_HOOKS=1`, pastes only into TextEdit, and acts only on "DocShot " test items;
  the paste report exists in debug builds only. Final: swift test 339, xcodebuild test 340,
  ClipboardKit 76, parity audit OK; Release build has no hook or report symbols (nm).

- C2 device checks run with Noel's go; full table in DEVICE_VERIFICATION.md ("C2 Clipboard
  History"). Agent-run passes (verified by reading the store): text, file, colour, PNG,
  TIFF converted to PNG, concealed copy skipped, copy from Passwords skipped, idle CPU about
  0.1%, history kept over a relaunch, off records nothing. Noel's window steps (⌃⌥⌘V,
  click to copy back, Escape, menu, Clear) user-reported as passing; Clear confirmed in the
  store. Pause tested by tests only. Screen control cannot see a menu bar app, so the
  window was not seen by the agent.
- During the run a password-like copy Noel made in WhatsApp was recorded (no concealed
  marker); the agent deleted it with secure delete. Expected behaviour; for C3 planning.
- End state: history off, store empty, C2 debug build running. Nothing committed.
- Noel is happy with C2's behaviour but not its look. He asked how to settle one design
  language and UI/UX system for all his products before more UI work; open question.

## 2026-11-23

- C0 findings committed as 70132a5 on `feature/c0.7-themes`, local only.
- C1 plan agreed by Noel ("Yes to all"), eight answers written into plan section 4.2 ("C1
  rules"). Checked first in a scratch package (deleted): the system SQLite 3.51 and CryptoKit
  build with no dependencies, and a package's tests run under both `swift test` and
  `xcodebuild test` (verified). C1 has no device checks: no UI, no real clipboard. Built on
  `feature/c1-clipboardkit`, cut from 70132a5.
- C1 built on `feature/c1-clipboardkit`, uncommitted: `Packages/ClipboardKit` (standalone,
  not linked into the app) with the item model and fingerprint, recording rules (markers,
  excluded apps, own writes, pause, history off), retention and clear rules, a pure reducer,
  and an SQLite store (one transaction per change, images as files, owner-only folders, schema
  version 1, secure delete, log checkpoint after removals). The audit gains the import rule
  (nothing under Capture, Recording or Editor may import ClipboardKit); the handoff checks gain
  `swift test --package-path Packages/ClipboardKit`.
- Fable reviewed C1: rules 1-5 proven; found defects in the store (text with NUL cut short,
  a newer database switched to WAL before refusal, existing folders not tightened, unreadable
  rows blocking re-recording and losing their image, failed limit changes half-applied,
  deleted clips left in the write-ahead log) and gaps in the import regex. All fixed, with 7
  new tests; the NUL and deleted-text tests were mutation-checked (each fails with its fix
  undone). Fable re-reviewed: all fixed, no new defects. Two nits also fixed (a stale comment,
  `@_spi` imports). My first import-rule probes were confounded by the parity check failing on
  the probe file; re-probed against the rule's own message: 9 forms caught, comments and
  look-alike names pass.
- Known, not fixed: the rollback test fails before any row changes, so undoing a partial
  change is shown by code reading, not by a test; the setLimits test covers only success;
  `.added` is reported even if retention removes the new item, possible only with a
  200-item limit of 0; once history is full, each copy also runs a log checkpoint.
- After the fixes: ClipboardKit `swift test` 68 and its `xcodebuild test` 68, all passing;
  app `swift test` 290 with the hotkey suites skipped, unchanged; parity audit OK. Verified
  (tests only). No device checks: C1 has no UI and no real clipboard.
- C1 committed as ff490d2 on `feature/c1-clipboardkit`, local only.
- C2 plan agreed by Noel ("Yes to all"), seven answers written into plan section 3 ("C2
  plan"); testing rule 3 changed at his request: the agent runs clipboard device checks with
  screen control, after telling him. Built on `feature/c2-clipboard-window`, cut from ff490d2.
- C2 built, uncommitted: ClipboardKit linked into the app and, by hand, the Xcode project
  (both targets); `Sources/DocShot/Clipboard/` with settings, the pasteboard reader (files,
  then text, then image, then colour; TIFF-only converted to PNG off the main thread), the
  history controller (polls twice a second only while on and not paused; skip rules before
  any read; own copy-backs ignored; store work queued in order), the DocShot window
  (Control+Option+Command+V now registered, Escape returns focus, click copies back and
  closes), menu bar Open/Pause/Clear, and a Clipboard History section in Settings. ClipboardKit
  gained `imageFileURL(for:)`. 19 new app tests on private pasteboards, scratch defaults and
  temporary folders.
- Fable reviewed C2: history off does nothing and capture code is untouched (proven). Defects
  found and fixed: an image beat the text it accompanied (spreadsheet and word-processor
  copies); switching off and on while saving could open a second store; the copy-back test
  could not tell an ignored own write from de-duplication; TIFF conversion dropped DPI; the
  new Xcode object IDs were 23 characters. Re-review: all fixed; one new edge (empty text or
  the inline-picture placeholder beating an image), also fixed with tests. Own-write, store
  reuse and DPI tests mutation-checked. Nits left: a stale app may be refocused if the user
  switched apps while the window stayed open; a failed store open at launch switches history
  off for later launches.
- After the fixes: app `swift test` 316 and `xcodebuild test` 317 with the hotkey suites
  skipped; ClipboardKit 69 in SwiftPM; parity audit OK. Verified (tests only). Not yet run in
  the app.
- Spike cleanup with Noel's yes: `spikes/` (app, build, log), the `spike/c0d-package`
  worktree and branch removed. No `com.docshot.spike` preferences existed; nothing for Noel
  to remove from System Settings. Other old worktrees left untouched. Verified (git, ls).

## 2026-11-18

- C0 spikes plan agreed by Noel ("Yes to all"), seven answers: one throwaway menu bar app
  `DocShotSpike` (`com.docshot.spike`) in a git-ignored `spikes/` folder, separate from DocShot,
  with menu entries for (a) polling and the privacy prompt, (b) paste into another app and
  (c) main window focus; Noel runs (a)-(c) from a checklist, the agent builds and reads the
  log; the log holds type names, sizes, times, app names and permission states, never
  clipboard content; if no alert appears, (a) is repeated with the pasteboard privacy preview
  set on the spike's own ID only; answers go into the plan and DEVICE_VERIFICATION.md, spike
  code and the (d) branch are not committed; Noel removes the spike from Accessibility and the
  pasteboard list, the agent deletes the build, the spike prefs and the (d) branch with his yes.
  (d) package versus folder is a build-only spike in a throwaway worktree.
- Found while planning (verified from the macOS 26.6 SDK header `NSPasteboard.h`): the general
  pasteboard's default access behaviour is to ask on programmatic access; user-started paste is
  exempt. Whether macOS 26.5.2 enforces it: unknown until spike (a). `/Applications/DocShot.app`
  and the debug builds share `com.docshot.app`; builds are signed with team DVV9Z7Q7B9.
- Spike (d) package versus folder, run in a throwaway worktree on branch
  `spike/c0d-package` (not committed): a local package `Packages/ClipboardKit` (one type, one
  test) wired into `Package.swift` and, by hand, into the Xcode project using the pre-Xcode-15
  form (folder reference plus `XCSwiftPackageProductDependency`), so `objectVersion` stays 56.
  Both the app and the hostless test target link it; an app file importing `ClipboardKit` is
  also compiled into the test target. Results: `swift test` 291 (290 + 1 link test), the
  package's own `swift test` 1, `xcodebuild test` 292 (291 + 1), all passing with the hotkey
  suites skipped; parity audit OK; the package links statically. Verified (tests only).
  One cost: the root `swift test` does not run the package's own tests, so they need
  `swift test --package-path Packages/ClipboardKit` as a second command (or a test file in
  `Tests/DocShotTests`). Recommendation: package.
- `DocShotSpike` built for (a)-(c) in `spikes/DocShotSpike` (git-ignored), signed with the
  same team. Not launched; Noel runs it from the "C0 Spikes" rows in DEVICE_VERIFICATION.md.
- Noel ran part (a): no alert with counter-only or full-read polling; the log shows
  `accessBehavior` "always allow" from launch and three text copies read (types and sizes
  only). Image, file, password and idle-CPU steps were not run. Noel found the manual
  checklist too heavy for a spike: (b) moved to C3, password marker, idle CPU, menu opening
  and the Escape key moved to C2, and the agent ran (c) itself.
- (c) agent-run with full-screen control approved by Noel: a self-test build (window closes
  after 3 s, alternating activation method) opened by real ⌃⌥⌘J presses in TextEdit. Both
  `NSApp.activate()` and the old forced call made the window key with focus in its field;
  closing returned TextEdit to the front and typing continued there; activation policy stayed
  accessory. Verified (log, TextEdit text). The test document was discarded unsaved and the
  spike quit.
- C0 answers written into the plan: section 4.1 (package decided), 4.3 (privacy note),
  a "C0 findings" subsection in section 6, and the carried checks added to the C2 row.

## 2026-11-17

- C0.6 preview thumbnail built by this session (Opus 5.5) on
  `feature/c0.6-preview-thumbnail`, cut from `feature/c0.5-shortcuts` at c7389af.
  Uncommitted. New: `Models/PreviewThumbnail.swift` (key map, button order, layout;
  in both test targets), `Capture/PreviewThumbnailController.swift` (non-activating
  panel; app-only), `PreviewThumbnailTests` (11 tests). `CaptureCoordinator` now shows
  the thumbnail instead of the editor and keeps the state `editing` until it is resolved.
  Tests: `swift test` 278 and `xcodebuild test` 279 passed with
  `HotkeyServiceTableTests`, `TemporaryEscapeHotkeyTests` and
  `CaptureCoordinatorEscapeLifecycleTests` skipped, because they register real system
  hotkeys. Parity audit OK. Not run in the app. Verified (tests only).
- Fable reviewed the C0.6 diff (read-only subagent, review-against-diff). Proven in code:
  checks 1-6, 9, 10 (tests not run by the reviewer); not proven until a device run: 7 (focus)
  and 8 (placement); contradicted: none. Four defects found, all confirmed in the code and
  fixed: a capture hotkey during the thumbnail's save panel could let the old save finish the
  new capture (now beeps); the discard prompt could stack (now beeps); a stale focus target
  when DocShot itself was in front (now cleared); Cancel on the prompt left DocShot in front
  (now hands focus back). After the fixes: `swift test` 278 and `xcodebuild test` 279 pass
  with the hotkey suites skipped; parity audit OK. The fixes themselves are not re-reviewed.
- Fable re-reviewed the four fixes: all four fixed. It found two new defects, both
  confirmed and fixed: a blocked (beeping) capture press could wipe the app focus returns
  to (now recorded only on paths that start a capture or show the prompt); the error alert
  did not count as busy (now it does). A third finding is accepted as known behaviour: a
  capture started from the editor leaves DocShot active after Copy, as today's editor flow
  does. After these fixes: `swift test` 278 and `xcodebuild test` 279 pass with the hotkey
  suites skipped; parity audit OK. These last two fixes are not re-reviewed.
- Noel ran the 18 C0.6 device checks on the debug build and reported all passing
  (user-reported; one screenshot shows the thumbnail in place). He then asked for a few
  colour themes besides the default; not yet scoped.
- C0.6 committed as bc269ce on `feature/c0.6-preview-thumbnail`, local only.
- Colour themes agreed as C0.7 (six answers): after C0.6 and before the C0 spikes;
  four themes (Graphite default, Slate, Moss, Ember); interface colours only; light and
  dark mode following macOS; chosen in a new Appearance section in Settings; second
  exception to the freeze rule; Windows must match. Written into plan sections 6, 7, 9
  and 12. Proposed colour values shown to Noel as swatches; not yet confirmed.
- C0.7 colour themes built on `feature/c0.7-themes` (cut from bc269ce), uncommitted.
  New: `Models/ColorTheme.swift` (palettes, contrast maths, store), `Design/ThemeController.swift`
  (current theme; a lock-guarded copy read by the dynamic colours), `ColorThemeTests`
  (25 cases). The five interface tokens in `DesignTokens` now follow theme and mode; Graphite
  resolves to the old values. Eleven views observe the controller, plus the preview thumbnail,
  whose background moved from a frosted material to the theme card colour. Settings has an
  Appearance section with four swatches.
- Fable reviewed C0.7: checks 1, 4, 6, 7 proven in code; 2 and 5 proven in code but need a look
  on device; 3 partly questioned because the scrubber and selected segment follow the accent,
  which matches decision 5 (only media backdrops and the track stay neutral). One defect,
  confirmed and fixed: themed grey text on fixed graphite tiles lost contrast in light mode
  (Settings and onboarding folder path, timeline "Src:" line); those now use a fixed text
  colour, with a test. Noted, not fixed: a test writes the process-wide current theme (it
  restores it); unselected timeline segments already used standard text colours on the dark
  tile before C0.7, which is low-contrast in light mode.
- After the fix: `swift test` 290 and `xcodebuild test` 291 pass with the hotkey suites
  skipped; parity audit OK. The fix itself is not re-reviewed. Not run in the app.
- Noel ran the 10 C0.7 device checks on the debug build and reported all passing
  (user-reported).
- C0.7 committed as 5fb8e7f on `feature/c0.7-themes`, local only.
- Noel ran the 18 remaining C0.5 device checks on the C0.7 debug build: all pass
  (user-reported). Every C0.5 row is now passed.
- A Fable session also wrote here this morning (commits e5288d4 and c7389af, plus an
  uncommitted STATUS.md line). Noel made this session the only writer.

- Commit 1 made on `feature/c0.5-shortcuts`: f3be4d4, handoff files, plan and this log.
  Local only, not pushed. Verified (git log).
- Plan approved after two grilling rounds; all section 10 decisions settled and written
  into plan sections 2, 4.2, 4.5, 5, 6, 7 and 10. Verified in session. In short:
  - Retention stays 200 items / 30 days / 500 MB. Pinned items count towards storage
    and are never removed automatically. Captures share the limits, capped at 20.
  - OCR (C4a) feeds history search and "Copy text" only, with history on.
    Pin-to-screen renamed Float (C4b) and works with history off. Principle 6
    reworded to allow it. The freeze follows C4a and C4b.
  - Name stays DocShot. Tier stays C, no due date.
  - One lane: Opus 5.5 at High effort orchestrates and builds; Fable reviews each unit
    from the diff. Codex and Antigravity are not used on the Mac work. Noel changed this
    from the proposed Sonnet/Opus split with Codex review; it overrides the general
    split in the handoff skill for this project.
  - Testing rules: private pasteboard and scratch preferences in tests; warn Noel
    before driving the app against real clipboard, preferences or hotkeys; clipboard
    device checks are Noel's.

## 2026-11-16

- STATUS.md cut to one page; the detail below moved here from it. Verified in session.
- State check found: local `main` at 32c1f8d is 2 ahead of and 4 behind `origin/main`
  (291a4a4); three prunable `/tmp/docshot-v1-*` worktrees; two Codex worktrees still hold
  `codex/launch-at-login-opt-in` and `codex/opaque-redaction`. Verified (git rev-list,
  git worktree list). Whether anything is active in them: unknown.
- `handoff.config.json` runs `pytest`, which does not apply to this Swift project.
  `swift test` is not a safe swap because `HotkeyServiceTableTests` touches the real
  system hotkey table; `Scripts/audit-test-parity.sh` proposed instead. Not changed.
- STATUS.md recorded `swift test` as both 291 and 292 tests. Which is current: unknown
  (292 likely, after `SettingsLayoutTests`).

## 2026-11-14

### Redefinition plan
Saved to docs/DOCSHOT_REDEFINITION_PLAN.md (also in the DocShot Claude project). Decided
by Noel: personal use only; no Apple Developer membership or notarisation; recorder
stays; clipboard manager built into DocShot as its own module; password manager is a
separate project (DevVault); Windows full parity after macOS is stable; configurable
Clear cache (keep last 5, last 10, pinned only, nothing); three rebindable global
shortcuts on Control+Option+Command plus single-key editor tools. Verified in session.

### GitHub review
`origin/main` is at 291a4a4, tagged macos-v1.0.0 (23 Sep), with launch-at-login (PR #11)
and opaque redaction merged. Three `windows/*` branches unmerged since 29 Jul. Verified
from a fresh clone; PR numbers inherited.

### Notarised release script
Release script and CI workflow drafted in a cloud sandbox, never run, not committed.
Parked because distribution is no longer a goal. Unverified.

### C0.5 shortcut rework
Built on `feature/c0.5-shortcuts` (cut from `origin/main` 291a4a4), uncommitted.

- Scope: one table of three actions (screenshot ⌃⌥⌘S, record ⌃⌥⌘R, openWindow ⌃⌥⌘V
  defined but unregistered); recorder plus reset per action in Settings; preset list
  removed; legacy migration; image editor tool keys; Return to copy and close.
- Tests: `swift test` (291, later 292), `xcodebuild test` (280) and
  `Scripts/audit-test-parity.sh` all pass, including `HotkeyServiceTableTests`, which
  rebinds, resets and rolls back against the real system hotkey table over scratch
  preferences. Inherited.
- In-app run: Noel launched the debug build and Claude Code drove it through
  accessibility. Passed: migration of the real preferences (preset 2 kept as ⇧⌘7),
  Settings rows, three-modifier rebind, duplicate-chord error, reset, onboarding text,
  tool keys R/X/T, tooltips, the typing guard and Return. Not verified: any global chord
  actually firing, export size fields, ⌘C, video editor and overlay. Row-by-row detail in
  docs/DEVICE_VERIFICATION.md ("C0.5 Shortcut Rework"). Inherited.
- Side effects of that run: both shortcuts are now on the new defaults in
  `com.docshot.app` (the ⇧⌘7 binding was reset as part of the check), and the clipboard
  was overwritten by the Return check.
- Settings window clipping (header and privacy notice cut off, same on `origin/main`)
  fixed on this branch by scrolling the content in a 520 × 620 window, approved by Noel.
  Verified by tests only; not yet seen in the running app.

- 2026-11-17: Noel launched the fixed build and reported "The shortcut looks good" and
  that the minimal Settings are liked. No row-by-row device results given. Inherited from
  Noel's message.
- 2026-11-17, proposed by Noel, not decided: (a) the four-key defaults (⌃⌥⌘S, ⌃⌥⌘R) may be
  too long; plan 13.3 chose that family to avoid the ⌘⇧number and ⌃⌥letter collisions, and
  both actions are already rebindable. (b) A preview thumbnail after capture: a small
  window with icon buttons for Copy, Discard, Edit and Save, where only Edit opens the full
  editor. Not in plan section 7, and plan section 12 says anything new waits until after
  the freeze, so it needs Noel's scope decision before any build.

- 2026-11-17: Noel approved the preview thumbnail ("Yes, add it"). Plan amended: principle
  2.6 reworded, C0.6 added to section 6, feature and scope added to section 7, exception
  noted in section 12. Details beyond the four buttons and "only Edit opens the editor"
  are marked proposed in the plan. Nothing built. The chord-length question is still open.

### Departures from plan section 13 (approved by Noel in session)
1. The recorder allows three modifiers and takes a title.
2. Saved preset 0 (old default ⌘⇧6) migrates to the new default, because launch always
   wrote a preset ID.
3. The onboarding preset picker is replaced by a read-only display.
4. Return copies then closes only on success.

### Handoff files
The handoff commits (cbf9581, cf4fa3f) also exist on `codex/launch-at-login`. Their
AGENTS.md, CLAUDE.md, tools/handoff.mjs and handoff.config.json are byte-identical to the
working-tree copies on `feature/c0.5-shortcuts` (verified by diff, 2026-11-16).
