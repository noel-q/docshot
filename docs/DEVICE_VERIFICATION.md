# Device Verification Record

This record tracks manual, on-device verification. It supplements automated tests; it does not claim coverage for hardware that was not available.

## 2B Colour Sampling and Capture Behaviour

Environment details (macOS version, hardware, and display configuration) were not recorded. The following checks were reported by the user as working on the available Retina display; no independent measurement values or timings were captured.

| Check | Status | Evidence / expected result |
| --- | --- | --- |
| Retina colour accuracy | User-reported pass | Sampling the reference red, green, blue, and grey swatches matched Digital Color Meter in sRGB mode for Hex, RGB, and HSL readouts. |
| Overlay self-exclusion | User-reported pass | The colour chip read the underlying pixel, rather than the darkened selection overlay. |
| Snapshot refresh | User-reported pass | Sampling stayed frozen until `R` was pressed, then reflected the refreshed screen content. |
| Normal capture flow | User-reported pass | Region/window selection, Escape cancellation, Copy, Save, and Discard continued to behave normally. Copy and Save remained explicit actions; cancellation and Discard did not create output. |
| Escape while snapshots are pending | User-reported pass | Escape cancelled the pre-overlay snapshot phase; no late snapshot result reopened or updated selection UI. |

## R1 Video-Only MP4 Recording

Environment: user-reported manual QA on a Mac mini (Apple M4, 16 GB memory) running macOS
26.5.2 (build 25F84), using a 42-inch 1080p display. The checks below were reported as passed.
The automated tests cannot prove TCC prompts, real stream behaviour, display removal, or how
H.264 handles an odd-dimension region; measured media values remain to be recorded if needed for
future encoder tuning.

| Check | Status | Expected result |
| --- | --- | --- |
| Window recording | User-reported pass | A recorded window plays in QuickTime Player, has finite duration, the expected pixel dimensions, and no audio track. |
| Retina single-display region | User-reported pass | Same, at the exact selected region bounds. |
| Odd-dimension region | User-reported pass | A region whose pixel size is odd on at least one axis records and plays back at that exact size. If the encoder alters it, record the actual dimensions before adding padding or clean-aperture handling. |
| Region spanning two displays | User-reported pass | Refused with an on-overlay explanation; selection stays open; no file is produced. |
| Cancel at selection, and at confirmation | User-reported pass | No stream starts and no temporary file is created. |
| Stop → Discard | User-reported pass | Temporary file removed; clipboard untouched. |
| Stop → Save panel cancelled | User-reported pass | Recording retained and still savable; a later Discard removes it. |
| Repeated Stop | User-reported pass | One file, one transition. |
| Quit while recording | User-reported pass | No orphan file in `DocShot-Recordings`. |
| Screen permission revoked mid-recording | User-reported pass | Recoverable failure reported; temporary media removed. |
| Screenshot workflow after a failed recording | User-reported pass | Capture, hotkey, annotation, Copy, and Save all still work. |
| Temporary directory after every scenario | User-reported pass | `DocShot-Recordings` is empty. |
| Encoder policy | User-reported pass | Encoder policy behaved acceptably. File size, bitrate, and dropped-frame values were not recorded. |

## R2 Recording Interaction and Interruptions

R2 adds a floating DocShot-owned status/control surface for starting, recording, stopping, and
awaiting-output states. Region recording excludes DocShot and window recording uses a
desktop-independent filter; sleep and display-configuration notifications use the existing
single-flight stream-failure cleanup path. The checks below were reported as passed on the R1
device-QA environment.

| Check | Status | Expected result |
| --- | --- | --- |
| Status and Stop controls | User-reported pass | Starting, recording, stopping, and awaiting-output states are visible; Stop is reachable from the floating panel and the menu bar. |
| Control-surface exclusion | User-reported pass | The floating status panel does not appear in a window or region MP4. |
| Sleep/wake interruption | User-reported pass | Sleep stops safely, reports a recoverable error, and removes temporary media. |
| Display-configuration interruption | User-reported pass | Disconnecting/changing the target display stops safely, reports a recoverable error, and removes temporary media. |
| Permission-revocation interruption | User-reported pass | Revoking Screen Recording permission mid-session produces the stream-failure cleanup path and leaves no temporary media. |
| Five-minute 30 fps recording | User-reported pass | The app stayed responsive and completed successfully. Memory and dropped-frame measurements were not recorded. |

## R3 System Audio

System Audio is opt-in and defaults to Off. It is shown in the Record confirmation only after the
user enables the local setting; microphone and combined audio are not part of this slice.

**A defect was found and fixed while preparing this section.** `SCStreamConfiguration.excludesCurrentProcessAudio`
was never set, so DocShot's own process audio — its error beeps and alert sounds — would have been
captured into the system-audio track. Excluding DocShot's *applications* from the content filter
only affects video; system audio is captured globally, for a window target as much as a display
one. The self-audio exclusion check could not have passed before this fix, and any earlier
observation of it would not have been meaningful.

Some of this section is now covered by automated tests that need no device, TCC grant, or audible
source: `RecordingAudioTrackTests` drives `RecordingVideoWriter` with synthesised samples and
inspects the resulting MP4, and `RecordingAudioPolicyTests` covers what the stream is asked to
capture. Both run in **both** toolchains. What those tests cannot do is prove that a real audible
source was captured, that playback is perceptually in sync, or how macOS behaves around TCC — so
the device column below still stands.

| Check | Automated coverage | Device check | Expected result |
| --- | --- | --- | --- |
| Audio off | Covered: the finished MP4 has zero audio tracks, `TemporaryRecording.hasAudio` is false, and stray audio buffers are dropped rather than written | User-reported pass | A saved MP4 has no audio track and no additional audio-related prompt occurs. |
| System Audio enabled | Partial: exactly one AAC track at 48 kHz stereo, and audio and video anchor on the same session clock (start skew measured at 0.0 s, spans within 0.15 s) | User-reported pass | A known audible source is present in the saved MP4 and remains synchronized with video. |
| DocShot self-audio exclusion | Partial: `excludesOwnProcessAudio` is asserted true whenever system audio is on, and is applied to `SCStreamConfiguration` | User-reported pass | DocShot's own sounds are absent from the system-audio track. Trigger a DocShot beep mid-recording — e.g. a refused second capture request — and confirm it is inaudible in the saved clip. |
| Permission deny/revoke | Covered at the writer: cancelling with or without audio leaves no file, cancellation is idempotent, and a session with no frames fails rather than producing a clip. Reducer-level cleanup effects are covered by `RecordingStateReducerTests` | User-reported pass | Failure is explicit, temporary media is removed, and video-only recording remains available. |

Device QA note: the automated sync check measures the writer's timeline bookkeeping, not audible
sync. The device checks above were reported as passed. Exact A/V-offset and file-size measurements
were not recorded; capture them during any later encoder-tuning pass.

## R4 Short GIF Export

The owner-approved GIF profile is 15 seconds maximum, 10 fps, 960 px maximum long edge, and a
10 MB encoded-size guard. The checks below were reported as passed.

| Check | Status | Expected result |
| --- | --- | --- |
| Eligible GIF export | User-reported pass | A supported MP4 becomes a valid animated, silent GIF with expected dimensions and cadence. |
| Duration cutoff | User-reported pass | A clip longer than 15 seconds does not offer GIF and retains the MP4 output path. |
| Size fallback | User-reported pass | A GIF exceeding 10 MB is removed and the MP4 remains available for Save or Discard. |
| Explicit output and cleanup | User-reported pass | No file is saved until Save GIF is confirmed; cancellation and Discard remove temporary GIF/MP4 media. |

## C0.5 Shortcut Rework

All rows passed by 17 November 2026: Noel ran the remaining rows himself on the C0.7 debug build and reported every one passing (user-reported); earlier agent-run evidence is kept below. Automated tests cover the default table, override persistence,
migration, the tool key map and its guards, and (in `HotkeyServiceTableTests`, against the
real system hotkey table over scratch preferences) rebinding, persistence across a new
service, reset, a refused duplicate chord and rollback when the system rejects a chord.
Rows marked "Service logic automated" still need one pass through the Settings UI; the
rest need a real keyboard and the real preferences domain. Build from
`feature/c0.5-shortcuts`.

Known before the first launch on Noel's Mac (read from `com.docshot.app` on 14 November
2026, not yet migrated): the saved screenshot shortcut is preset 2, `⌘⇧7`. Migration will
therefore keep `⇧⌘7` as a custom binding, and it stays in conflict with numbered lists
until Reset is pressed.

Agent-run rows were driven by Claude Code on Noel's Mac mini through the accessibility
API, with key presses posted to the app. That path cannot press a system-wide chord, so
every row about a global shortcut actually firing is still "Not run", as are the export
size fields, `⌘C`, and the video editor and overlay.

Found during the run: the Settings window was shorter than its content, so the header
(icon, title, Guide… button) and the privacy notice were clipped. The content frame was
520 × 570 on `origin/main` as well, so this predates C0.5. Fixed on this branch by
scrolling the content inside a 520 × 620 window; `SettingsLayoutTests` guards the window
size. The fix has not been looked at in the running app.

Noel's own look (17 Nov 2026, fixed debug build launched by Noel): reported "The shortcut
looks good" and that the Settings are pleasingly minimal. No row-by-row results were given,
so the rows below keep their earlier status. Two points raised, both proposed and not yet
decided: the four-key default chords may be too long, and a small preview thumbnail after
capture (Copy, Discard, Edit, Save) is wanted before the full editor opens.

| Check | Status | Expected result |
| --- | --- | --- |
| Migration on this Mac | Agent-run pass (14 Nov 2026, debug build, driven through accessibility). Saved preset 2 became custom `⇧⌘7`; legacy keys removed; Record showed `⌃⌥⌘R`. | Before first launch of the new build, note the old screenshot shortcut. After launch: if it was the old default `⌘⇧6`, Settings shows `⌃⌥⌘S`; if it was a custom shortcut or another preset, that chord is still shown and still works. Recording shows `⌃⌥⌘R`. |
| Old shortcuts released | User-reported pass (17 Nov 2026) | With DocShot running, `⌘⇧8` makes a bulleted list and `⌘⇧7` a numbered list in Google Docs, Slack or Notion; `⌘⇧6` does nothing in DocShot (unless kept by migration). |
| Screenshot default | User-reported pass (17 Nov 2026) | `⌃⌥⌘S` from another frontmost app opens the capture overlay. The menu bar item shows the same chord. |
| Record default | User-reported pass (17 Nov 2026) | `⌃⌥⌘R` starts the recording flow; pressed again during a recording it stops it. The menu bar item shows the same chord. |
| One-hand reach | User-reported pass (17 Nov 2026) | Both chords are comfortable with the left hand alone on the keyboard in use. |
| Open-window shortcut absent | User-reported pass (17 Nov 2026). Earlier: Automated (`testOpenWindowIsNotRegistered`); not run on device | `⌃⌥⌘V` does nothing in DocShot and still reaches the frontmost app. |
| Rebind screenshot | User-reported pass (17 Nov 2026). Earlier: Service logic automated; rebind through the Settings UI agent-run for Record only (below) | Settings > Change… records a new chord, including a three-modifier one. The new chord works at once, the old one stops, and the menu bar title updates. |
| Rebind record | User-reported pass (17 Nov 2026). Earlier: Agent-run pass (14 Nov 2026, debug build, driven through accessibility). Recorder titled "Set Record (start or stop) Shortcut" accepted `⌃⌥⌘G`; row, Reset button and saved override updated. Whether the new chord fires system-wide was not pressed. | Same as above for Record. |
| Persistence | User-reported pass (17 Nov 2026). Earlier: Saved override read back from preferences (agent-run); relaunch covered by `HotkeyServiceTableTests`; an actual quit and relaunch not run | Quit and relaunch: both rebound chords are still shown and still work. |
| Reset to default | Agent-run pass (14 Nov 2026, debug build, driven through accessibility). Reset returned both rows to defaults, cleared the saved overrides and disabled itself. | Reset returns the row to `⌃⌥⌘S` or `⌃⌥⌘R`, the default works again, and Reset is disabled while the default is in use. |
| Chord already in use | User-reported pass (17 Nov 2026). Earlier: Agent-run pass (14 Nov 2026, debug build, driven through accessibility) for the other DocShot action: red line "⌃⌥⌘G is already used by Record (start or stop)", Screenshot unchanged. A chord owned by another app: automated in `HotkeyServiceTableTests` only. | Rebinding to a chord another app has registered globally, or to the other DocShot action's chord, shows the red error line; the previous chord keeps working. |
| Recorder validation | User-reported pass (17 Nov 2026) | A key with no modifier, or with Shift only, is refused with the existing message. |
| Settings window not clipped | User-reported pass (17 Nov 2026) | The header with the Guide… button is visible at the top, and scrolling reaches the privacy notice at the bottom. |
| Onboarding | User-reported pass (17 Nov 2026). Earlier: Agent-run pass (14 Nov 2026, debug build, driven through accessibility) for the first page, which shows the current chord and "changeable in Settings". The settings page of the guide was not opened. | The Guide shows the current screenshot chord as text with "Change in Settings"; there is no preset menu. |
| Tool keys | User-reported pass (17 Nov 2026). Earlier: Agent-run pass (14 Nov 2026, debug build, driven through accessibility) for R, X and T (toolbar highlight followed). V, A, O, H, C covered by `AnnotationToolKeyTests` only. | In the image editor, `V A R O T H X C` select Select, Arrow, Rectangle, Ellipse, Text, Highlighter, Redaction and Crop; the toolbar highlight follows. |
| Tooltips | Agent-run pass (14 Nov 2026, debug build, driven through accessibility). All eight tools expose "Name (Key)" help text. | Hovering each tool shows its name with the key, for example "Arrow (A)". |
| Typing is not hijacked | Agent-run pass (14 Nov 2026, debug build, driven through accessibility). "rcx" went into the text annotation, the tool stayed on Text, and Return committed the text with the editor still open. | While a text annotation is being typed, letters such as `r`, `c`, `x` go into the text and the tool does not change; Return commits the text and does not copy or close. |
| Export size fields | User-reported pass (17 Nov 2026) | While the custom width or height field has the cursor, tool keys type nothing into the canvas and change no tool. Clicking the canvas makes the tool keys work again. |
| Return copies and closes | User-reported pass (17 Nov 2026). Earlier: Agent-run pass (14 Nov 2026, debug build, driven through accessibility) for the success path: PNG on the clipboard and the editor closed. The invalid-size path was not run. | With the canvas focused, Return puts the flattened PNG on the clipboard and closes the editor. With an invalid export size, Return shows the size error and the editor stays open. |
| Existing editor keys | User-reported pass (17 Nov 2026) | `⌘C` copies and keeps the editor open; `⌘S`, `⌘Z`, `⇧⌘Z`, Delete and Escape behave as before. |
| Video editor and overlay unchanged | User-reported pass (17 Nov 2026) | In the video editor `⌘K`, Space, `⌘Z`, Delete, `⌘S`, Escape behave as before and plain letters do nothing. In the capture overlay Escape cancels and `R` refreshes. |
| Escape before the overlay | User-reported pass (17 Nov 2026) | Escape pressed right after the screenshot chord still cancels the pending capture. |

## C0.6 Preview Thumbnail

Run by Noel on 17 November 2026 (debug build from this branch, his Mac); he reported every row as passing. Build from `feature/c0.6-preview-thumbnail`. Automated tests
(`PreviewThumbnailTests`, both toolchains) cover the key map, button order, thumbnail
sizing and placement maths only; the panel, focus, clipboard and save flows are app-only
and need a real run. The Copy, Return and ⌘C, and New capture rows overwrite the clipboard.

| Check | Status | Expected result |
| --- | --- | --- |
| Thumbnail appears | User-reported pass (17 Nov 2026); also seen in Noel's screenshot: thumbnail bottom-right with Copy, Save, Edit and Discard icons. | After ⌃⌥⌘S and a region or window pick, a small preview with Copy, Save, Edit and Discard appears bottom-right of the display the screenshot came from, clear of the Dock. The editor does not open. |
| Focus stays put | User-reported pass (17 Nov 2026) | The app you were in stays frontmost (its name in the menu bar unchanged) while the thumbnail is up. |
| Copy | User-reported pass (17 Nov 2026) | The Copy button puts the full-size PNG on the clipboard and the thumbnail closes. |
| Return and ⌘C | User-reported pass (17 Nov 2026) | Each copies and closes, without clicking the thumbnail first. |
| Save | User-reported pass (17 Nov 2026) | Save button or ⌘S opens the save panel; saving writes a full-size PNG, closes the thumbnail and returns focus to your app. Cancel keeps the thumbnail, and Return still works on it afterwards. |
| Discard | User-reported pass (17 Nov 2026) | Discard button or Escape closes the thumbnail; nothing on the clipboard or disk changes. |
| Edit | User-reported pass (17 Nov 2026) | Edit button or clicking the image opens today's editor with the screenshot; the thumbnail closes; the editor's Copy, Save and Discard behave as before. |
| New capture while up | User-reported pass (17 Nov 2026) | ⌃⌥⌘S with the thumbnail up asks "Discard Current Screenshot?". Cancel keeps the thumbnail (Return still copies, and focus then returns to your app); Start New Capture closes it and opens the overlay. |
| Capture during Save | User-reported pass (17 Nov 2026) | With the thumbnail's save panel open, ⌃⌥⌘S only beeps: no prompt, no overlay. Saving or cancelling then behaves as in the Save row. |
| No stacked prompts | User-reported pass (17 Nov 2026) | With the "Discard Current Screenshot?" prompt up, pressing ⌃⌥⌘S again only beeps; there is never a second prompt. |
| Focus after a beep | User-reported pass (17 Nov 2026) | Thumbnail up: press ⌃⌥⌘S (prompt), press it again (beep only), choose Start New Capture, take a screenshot and Copy it. Focus goes back to the app you started in. |
| Started from the editor | User-reported pass (17 Nov 2026) | Known behaviour, accepted: with the editor open, start a new capture and Copy from the new thumbnail. DocShot stays the active app with no window until you click elsewhere, as the editor flow does today. |
| Started from Settings | User-reported pass (17 Nov 2026) | With DocShot Settings in front, take a screenshot and Copy it: Settings stays in front and no other app is brought forward. |
| Recording while up | User-reported pass (17 Nov 2026) | ⌃⌥⌘R with the thumbnail up does nothing (beep); after the thumbnail is closed it starts recording. |
| Tooltips | User-reported pass (17 Nov 2026) | Hovering each button shows its name and key, for example "Save (⌘S)". |
| Second display | User-reported pass (17 Nov 2026) | A screenshot taken on the second display puts the thumbnail on that display. |
| Full-screen app | User-reported pass (17 Nov 2026) | Over a full-screen app the thumbnail appears on top of it. |
| Recording flow unchanged | User-reported pass (17 Nov 2026) | A recording still goes to the video editor with no thumbnail. |

## C0.7 Colour Themes

Run by Noel on 17 November 2026 (debug build from this branch, his Mac); he reported every row as passing. Build from `feature/c0.7-themes`. Automated tests (`ColorThemeTests`,
both toolchains) cover the palettes, Graphite matching the old values, contrast of the new
themes, saving and loading the choice, and the controller; how the colours actually look and
whether open windows redraw need a real run. Picking a theme saves it in DocShot's own
preferences (`DocShotColorTheme` in `com.docshot.app`); choose Graphite at the end to return
to the default.

| Check | Status | Expected result |
| --- | --- | --- |
| Graphite unchanged | User-reported pass (17 Nov 2026) | With Graphite selected, Settings, the editor, the preview thumbnail and the onboarding guide look as they did before, in dark and in light mode (apart from the thumbnail, which now uses the card colour instead of a frosted background). |
| Appearance section | User-reported pass (17 Nov 2026) | Settings shows Appearance near the top with four swatches: Graphite, Slate, Moss, Ember. The selected one has an accent outline; hovering shows its description. The header and privacy notice are still reachable by scrolling. |
| Applies at once | User-reported pass (17 Nov 2026) | Picking Slate, Moss or Ember changes Settings immediately: background, cards, accent and secondary text. No relaunch. |
| Open editor follows | User-reported pass (17 Nov 2026) | With an image editor open and annotated, change the theme in Settings: the editor's accent and backgrounds change, and its annotations, tool and crop are untouched. |
| Thumbnail follows | User-reported pass (17 Nov 2026) | After a theme change, the next screenshot's thumbnail uses that theme's card colour and border. |
| Light and dark | User-reported pass (17 Nov 2026) | Switching macOS between light and dark (System Settings > Appearance) with a new theme selected swaps between its light and dark colours; the theme never forces a mode. |
| Readable text | User-reported pass (17 Nov 2026) | In each theme and both modes, secondary text and accent controls are easy to read, including the folder path in Settings (Use a default folder) and the "Src:" line on video timeline segments. |
| Saved across relaunch | User-reported pass (17 Nov 2026) | Quit and relaunch: the chosen theme is still applied and selected in Settings. |
| What must not change | User-reported pass (17 Nov 2026) | Annotation colours, copied and saved images, recordings, the DocShot mark, the video player backdrop and the timeline track look the same in every theme. |
| Video editor | User-reported pass (17 Nov 2026) | In the video editor, controls, the scrubber and the selected segment use the theme accent; unselected segments stay graphite. |

## C0 Spikes

Throwaway app `DocShotSpike` (`com.docshot.spike`, signed with the same team as DocShot), built
from the git-ignored `spikes/DocShotSpike` folder on 18 November 2026. It is not DocShot: it
never touches `com.docshot.app`. It logs to `spikes/logs/spike.log`: type names, byte counts,
times, app IDs and permission states, never clipboard content. While it runs it holds the
hotkey ⌃⌥⌘J. Steps marked "overwrites the clipboard" replace what is on it. Part (a) was run
by Noel; at his request the agent ran (c) itself (a self-test build that closes its window
after 3 s, driven with real key presses in TextEdit), and (b) moved to C3.

| Check | Status | Expected result |
| --- | --- | --- |
| Launch | User-reported pass (18 Nov 2026) | `open spikes/DocShotSpike/DocShotSpike.app`: "Spike" appears in the menu bar; no Dock icon, no window. |
| (a) Counter only | User-reported pass, text copies only (18 Nov 2026); no alert; log shows "always allow" | Spike menu > Watch: counter only. Copy some text, an image and a file in Finder. Note whether any system alert appears (expected: none). |
| (a) Full read | User-reported pass, text copies only (18 Nov 2026); no alert; log shows "always allow" before and after each read | Spike menu > Watch: full read. Copy the same three things. Note whether an alert about DocShotSpike reading the clipboard appears, its wording and the button pressed; then whether DocShotSpike now appears in System Settings > Privacy & Security under a paste or clipboard heading, and its setting. Unknown on macOS 26.5.2. |
| (a) Password copy | Not run; moved to C2 | Still on full read, copy a password from Passwords or Bitwarden. Only type names are logged; expected: a concealed marker is present. |
| (a) Idle cost | Not run; moved to C2 | Leave full read on for 3 minutes without copying. Expected: CPU lines in the log near zero. |
| (c) Hotkey opens | Agent-run pass (18 Nov 2026): window key, focus in its field, no Dock icon (log) | In TextEdit, press ⌃⌥⌘J: the spike window comes to the front and typing goes into its field. No Dock icon. |
| (c) Escape returns | Agent-run pass for the return, closed by a 3 s timer not the Escape key (18 Nov 2026); TextEdit in front and took typing again; Escape itself moved to C2 | Press Escape: the window closes and TextEdit is in front again, cursor where it was. |
| (c) Menu opens | Not run; moved to C2 | Spike menu > Open window: same as the hotkey row; Escape returns to the app you were in. |
| (c) Forced activation | Agent-run (18 Nov 2026): same as the current API, so not needed | Tick Forced activation (old API) and repeat the hotkey row. Note any difference. |
| (b) No permission | Not run; moved to C3 by Noel | Overwrites the clipboard. In a TextEdit document, ⌃⌥⌘J then Return: the window closes, TextEdit is in front, nothing is typed; ⌘V then pastes "DocShot spike paste test" with a time. |
| (b) Grant Accessibility | Not run; moved to C3 by Noel | Spike menu > Ask for Accessibility, then turn DocShotSpike on in System Settings > Privacy & Security > Accessibility (Noel's step). |
| (b) Paste in TextEdit | Not run; moved to C3 by Noel | Overwrites the clipboard. ⌃⌥⌘J then Return in TextEdit: the test text appears by itself. |
| (b) Paste in a browser | Not run; moved to C3 by Noel | Overwrites the clipboard. Same in a browser text field. |
| (b) Paste in Terminal | Not run; moved to C3 by Noel | Overwrites the clipboard. Same at a Terminal prompt; the text appears at the prompt. Do not press Return there. |
| Cleanup | Done (23 Nov 2026): spike folder, log, worktree and branch removed; no `com.docshot.spike` preferences existed; the spike was never granted Accessibility and raised no paste alert, so no privacy list holds it | Quit the spike. Noel removes DocShotSpike from Accessibility and from the paste list if it appeared; the agent deletes the build, its log and any `com.docshot.spike` preferences, with Noel's yes. |

## C2 Clipboard History (read-only window)

Debug build from `build/c2-dd` (branch `feature/c2-clipboard-window`, uncommitted), run on
24 November 2026 on macOS 26.5.2 against Noel's real `com.docshot.app` preferences and
general clipboard, with his go (testing rule 3). Screen control cannot see or grant a menu
bar app, so the agent put test content on the clipboard with a scratch helper and read the
store with `sqlite3 -readonly`; the window steps were Noel's. Test content only; previews of
anything Noel copied himself were not printed.

| Check | Status | Expected result |
| --- | --- | --- |
| Turn on, store created | Agent-run pass (24 Nov 2026), switched on through the preference and a relaunch, not the in-app toggle | `~/Library/Application Support/DocShot/Clipboard` and `Images` created as 0700; database files are 0644 inside them. |
| Text, file, colour, PNG | Agent-run pass (24 Nov 2026) | Each copy appears once with its kind, source app and size; images stored as files. |
| TIFF-only image | Agent-run pass (24 Nov 2026): stored as `public.png` | Converted to PNG before storing. |
| Concealed marker skipped | Agent-run pass (24 Nov 2026) | A copy carrying `org.nspasteboard.ConcealedType` is not stored. |
| Excluded app skipped | Agent-run pass (24 Nov 2026), plain text copied while Passwords was in front; a real password entry was not copied | Not stored. |
| Idle CPU | Agent-run pass (24 Nov 2026): 0.05 s CPU in 60 s (about 0.1%) | Near zero while watching. |
| Quit and relaunch | Agent-run pass (24 Nov 2026) | History kept; what was already on the clipboard at launch not recorded; a repeat copy moves to the top without a duplicate. |
| Window by ⌃⌥⌘V, rows and thumbnails | User-reported pass (24 Nov 2026), "nothing looked wrong" | Lists the items newest first; image thumbnails and a colour swatch. |
| Click copies back and closes | User-reported pass (24 Nov 2026); not confirmed in the store, which was cleared next | Window closes, the previous app returns to the front. |
| Escape returns focus | User-reported pass (24 Nov 2026) | Window closes, the previous app returns to the front. Carries the C0 (c) Escape row. |
| Window from the menu | User-reported pass (24 Nov 2026) | Open DocShot Window opens the same window. Carries the C0 (c) menu row. |
| Screenshot copy recorded | User-reported screenshot taken (24 Nov 2026); recording not confirmed, store cleared next | A screenshot copied by DocShot appears in history (C2 decision 6). |
| Clear with confirm | Pass (24 Nov 2026): Noel cleared, the agent read the store | Confirmation shown; with the default "Pinned only" and no pins the store is empty, image files deleted, WAL truncated. |
| Off records nothing | Agent-run pass (24 Nov 2026) | After switching off and relaunching, a copy is not stored and the database is not open. |
| Pause and Resume | Not run in the app; covered by tests only | Copies made while paused are not recorded. |
| Password from a chat app | Observed (24 Nov 2026) | A password-like copy Noel made in WhatsApp during the run was recorded, because WhatsApp sets no concealed marker; the agent deleted it with secure delete and confirmed it is gone from the file. Expected behaviour, noted for C3 planning. |

End state: history off, store folder empty, the C2 debug build left running.

## C3 Paste, Search, Keys, Pins

Debug build from `build/c3-dd` (branch `feature/c3-paste`, uncommitted), 24 November 2026,
macOS 26.5.2, Noel's real `com.docshot.app` preferences and clipboard, with his go. The agent
put test items ("DocShot C3 test: ...") on the clipboard, read the store, and drove the
window through a DEBUG-only hook (`ClipboardDebugHooks`, a distributed notification), checking
results by screenshot of TextEdit. Screen control may not send keystrokes into Chrome or
Terminal and cannot see DocShot, so those pastes were Noel's.

| Check | Status | Expected result |
| --- | --- | --- |
| First Return without Accessibility | User-reported pass (24 Nov 2026) | Copies, closes, TextEdit returns, macOS shows the Accessibility request once; Cmd+V pastes. |
| Search ignores accents | User-reported pass (24 Nov 2026): "cafe" found "café menu" | Matches as you type. |
| Paste into TextEdit | User-reported pass; agent-run pass three times, seen by screenshot (24 Nov 2026) | Return, a click or the hook's choose pastes by itself. |
| Paste into a browser field (Chrome) | User-reported pass on the final build (24 Nov 2026) | Pastes by itself. |
| Paste into the Claude app (Electron) | Failed on the first build (Cmd+V lost); user-reported pass after the fix (24 Nov 2026) | Pastes by itself. Fix: Cmd+V carries the left-Command device bit and is posted at the session tap. |
| Paste at a Terminal prompt | User-reported pass (24 Nov 2026) | Text at the prompt, not run. |
| Pin, delete, Escape | Agent-run pass through the hook, store read (24 Nov 2026); the key bindings themselves are covered by unit tests | Pinned item in its own group at the top; deleted item gone; first Escape clears the search, second closes. |
| Accessibility kept across rebuilds | Agent-run (24 Nov 2026) | The grant stayed with the debug build after rebuilds signed by the same team. |
| Limits and excluded-app editing in Settings | Not run in the app; covered by tests | Pickers apply at once, with a confirmation before removals; list edits take effect. |
| Clean-up | Done (24 Nov 2026) | Test items deleted with secure delete, images removed, history switched off. DocShot stays in Accessibility for the debug build until Noel removes it. |

Incidents during the agent's own tests (24 Nov 2026), recorded so they are not repeated:
two test pastes went to the wrong app. One went to Chrome, which was in front when the
hook opened the window; one went to WhatsApp, which became active while the window was
open and so became the paste target under decision 9. Only Cmd+V was sent, never Return.
The hook now pastes only into the app named in `open:<bundle id>`, refuses if the target
changed or is not in front, and the agent runs paste tests only while Noel is away from
the Mac. The Chrome test tab used first was under the Claude in Chrome extension and
received no outside keystrokes at all, so it could not test paste.

## Quiet Restyle of the Clipboard Window

Debug build from `build/qc-dd` (branch `feature/quiet-clipboard`, uncommitted), 24 November
2026, macOS 26.5.2. The agent ran DocShot with `DOCSHOT_DEBUG_HOOKS=1` and
`DOCSHOT_DEBUG_STORE` set, so sample items went to a scratch store and scratch preferences,
never the real history (which stayed off). The app rendered its own window to PNG in dark and
light; the agent looked at each.

| Check | Status | Expected result |
| --- | --- | --- |
| Layout in dark and light | Agent-run pass from app-rendered snapshots (24 Nov 2026) | Search bar at the top (no empty title band), filter, "..." menu, 300 pt list with groups, preview pane, footer hints. |
| Previews | Agent-run pass (24 Nov 2026) | Code in mono from Terminal; link with its site; colour with hex, RGB and HSL; a 1600 px photo shown sharp with its pixel size; file with icon and path. |
| States | Agent-run pass (24 Nov 2026) | No matches (action hints hidden); paused line with Resume in the accent; history off with a Turn on button and no Return shortcut. |
| Clicks in the merged title-bar zone | User-reported pass (24 Nov 2026) | The filter, the "..." menu and the search field all take clicks. |
| Look | User-reported pass (24 Nov 2026): "Looks good" | Noel says it no longer looks ugly. |
| Clean-up | Done (24 Nov 2026) | Scratch store, scratch preferences and snapshots deleted; normal debug build relaunched; real history still off. |

## Still Unverified

The following require the corresponding connected hardware or display mode and remain unverified:

- 1x external display sampling and capture alignment.
- Negative-origin multi-display layout sampling and capture alignment.
- P3/wide-gamut source comparison, including the expected sRGB-normalised colour result.

## Scope and Privacy

2B colour sampling uses display snapshots during selection and presents a local readout only. It does not automatically write to the clipboard, save captures, retain a history, upload content, use cloud services, create accounts, or collect analytics.
