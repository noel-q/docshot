# README media capture

Capture media from a local Debug build on a desktop that has already granted DocShot Screen
Recording permission. Keep personal notifications and other people's data out of frame.

## Assets

Approved assets live in `docs/media/`, each in light and dark so the README follows the reader's
GitHub theme. Captured 26 November 2026 from a Debug build of version 1.1 on a scratch store, with
made-up content only (a drawn "Release checklist" image and neutral clipboard items):

| File | Content | How it was made |
| --- | --- | --- |
| `docshot-icon.png` | The app icon. | Copied from the app's icon set. |
| `clipboard-light.png`, `clipboard-dark.png` | Clipboard history with an image selected and its text in the preview. | The app's own rendering of its window. |
| `editor-light.png`, `editor-dark.png` | The screenshot editor with a box, an arrow and a note. | The app's own rendering of its window. |
| `video-editor-light.png`, `video-editor-dark.png` | The video editor with a made-up eight-second clip. | The app's own rendering of its window, with the clip's first frame drawn into the player area afterwards, because window rendering cannot capture the video layer. |
| `docshot-demo.mp4` | Optional 20–30 second silent walkthrough. | Not made yet. |

## Capture checklist

1. Run **DocShot** from Xcode on My Mac and open **Settings** from the menu bar.
2. Show `⌘⇧8`, **System audio** (off), **Include cursor in recordings**, and **30 fps** in one
   clean frame. Do not show system notifications, credentials, or other applications' data.
3. Capture one synthetic screenshot (for example, a simple local document), annotate it, and
   take a screenshot of the editor before saving.
4. Record a short synthetic window, stop it, choose **Edit Recording…**, add a single annotation,
   and capture the editor plus timeline.
5. Record the walkthrough with macOS screen recording or a separate recorder. Review it for
   notifications and audio before committing.
6. Optimise stills as PNG and use H.264 MP4 for the video. Update the README's Demo media
   section with the approved paths.

The files in `docs/media/` are product evidence, not generated artwork: do not substitute
mockups or screenshots containing private data.
