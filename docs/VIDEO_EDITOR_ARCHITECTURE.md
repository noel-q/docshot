# Video Editor Core

The non-destructive editing core for a post-R4 video editor: a model for one completed temporary
MP4, and a service that renders it. There is no UI in this slice, and nothing here touches the
screenshot editor or the recording capture pipeline.

## What exists

```text
Models
  VideoTimeRange          half-open [start, start + duration) in seconds
  VideoSegment            a range into the source asset, placed on the timeline
  VideoAnnotation         an AnnotationItem plus the source range it is visible for
  VideoProject            segments + annotations + validated mutations
  VideoProjectHistory     snapshot undo/redo
  VideoProjectError       why an edit was refused
Services
  VideoProjectExporting             protocol
  AVFoundationVideoProjectExporter  composition, overlay pass, export
  VideoAnnotationOverlayRenderer    annotations → transparent frame overlay, redactions → CIFilter
```

## Model decisions

**Segments are ranges, never media.** A segment is a `VideoTimeRange` into the one source MP4.
Trim moves that range; split produces two ranges; delete drops one; reorder permutes them. The
source file is opened read-only and is never rewritten, which is what makes the editor
non-destructive by construction rather than by discipline.

**Annotations are anchored in source time, not timeline time.** This is the decision the rest of
the model follows from. An arrow points at something on screen, so it has to stay attached to the
frames it was drawn over when those frames move. Trimming a clip's head shifts its content earlier
on the timeline, and the overlay shifts with it; reordering clips carries overlays along. Anchoring
in timeline time would have left annotations sitting over whatever content slid underneath them.

**Annotations are also scoped to a segment.** `segmentID` decides ownership: deleting a clip
deletes its annotations, and the same source frames appearing twice on the timeline do not silently
share overlays. On a split, an annotation goes to whichever half contains the frame it *starts* on
and is clipped to that half — one predictable rule, rather than duplicating it under a new identity.

**Derived clipping may go below the authoring minimum.** `VideoTimeRange.minimumDuration` (0.05 s)
guards what a user asks for. A trim or split that clips an existing overlay to a shorter window
keeps it: silently deleting an annotation the user never asked to remove would be worse.

**Mutations are all-or-nothing.** Every `mutating func` validates first and throws
`VideoProjectError` without touching the project, so a rejected edit cannot leave a half-applied
timeline. `VideoProjectHistory` records a snapshot only when a mutation both succeeded and changed
something.

**Undo is snapshots, not inverse operations.** `VideoProject` is an `Equatable` value, so the
cheapest correct history is a bounded stack of whole projects — there are no inverse operations to
get wrong.

## Export contract

- Export runs only when the caller asks. Editing writes nothing at all: no directory, no
  scratch file, no history entry.
- Segments are rendered in timeline order into an `AVMutableComposition`. Audio is inserted only
  when the source has an audio track; a silent recording never gains an invented one.
- Annotation overlays are composited per frame through
  `AVMutableVideoComposition(asset:applyingCIFiltersWithHandler:)`. Redactions are Core Image
  filters applied to the frame beneath; vector annotations are drawn into a transparent overlay
  and composited on top, using the screenshot editor's coordinate convention.
- Output goes to `TemporaryRecordingStore` first and comes back as a `TemporaryRecording`, so the
  existing save panel handles the user's explicit Save with no new output path.
- A failure or cancellation removes the partial export and leaves the original recording exactly
  as it was.
- GIF export stays where it is. `GIFExportService` consumes a finished MP4 and is untouched by
  this feature.

## Toolchain placement

All five production files are compiled into **both** test targets. They are Foundation,
AVFoundation, CoreImage, and AppKit only — no `SCStream`, no coordinator, no window — so the
hostless Xcode bundle can drive a real export end to end, as it already does for
`RecordingVideoWriter`. No new `#if SWIFT_PACKAGE` suite; the declared delta stays at three tests.

## Known risks

- **Frame accuracy.** Times are seconds, converted once to `CMTime` at timescale 600. Cuts land on
  the composition tick nearest the requested second, not on a source frame boundary. Frame-accurate
  trimming needs the source's frame timing and a UI that snaps to it.
- **Overlay drawing is duplicated.** `VideoAnnotationOverlayRenderer` mirrors `ImageRenderer`'s
  drawing conventions rather than sharing them, deliberately: this feature must not be able to
  change the screenshot export path. Extracting a shared drawing type is a follow-up.
- **Preset-driven encoding.** Export uses `AVAssetExportPresetHighestQuality`, so the output's
  bitrate and dimensions are chosen by AVFoundation rather than by the recording encoder policy.
  Matching them is an open decision.
- **No device QA.** Everything here is verified by automated tests against synthesised media. Real
  recordings, long timelines, and export performance are unverified.
