# README media capture

Capture media from a local Debug build on a desktop that has already granted DocShot Screen
Recording permission. Keep personal notifications and other people's data out of frame.

## Assets

Save approved assets below `docs/media/` using these names:

| File | Content | Target |
| --- | --- | --- |
| `menu-and-settings.png` | Menu-bar menu and Recording settings: `⌘⇧8`, audio toggle, cursor toggle, 30 fps. | 1600 × 1000 or wider |
| `screenshot-editor.png` | Screenshot editor with a deliberately non-sensitive example and two annotations. | 1600 × 1000 or wider |
| `video-editor.png` | Completed recording in the post-stop editor with timeline and one annotation visible. | 1600 × 1000 or wider |
| `docshot-demo.mp4` | 20–30 second silent walkthrough: launch → select → annotate → save/discard → record → edit. | 1440p or lower |

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
