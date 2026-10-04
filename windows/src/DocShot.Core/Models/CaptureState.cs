namespace DocShot.Core.Models;

/// <summary>
/// The screenshot capture state machine's states.
/// </summary>
/// <remarks>
/// Ported as-is including <see cref="PermissionRequired"/>, even though Windows has no TCC-style
/// screen-capture permission gate for a desktop app targeting a known window/monitor - see the
/// platform mapping table in <c>docs/WINDOWS_PORT_PLAN.md</c>. Keeping the case means the
/// eventual Windows coordinator's shape matches macOS's exactly; the effect that produces it may
/// simply never fire in practice (e.g. only reachable on pre-1903 Windows falling back to a
/// picker-gated capture path). Decide that in <c>DocShot.Platform</c>, not by deleting the case
/// here.
/// </remarks>
public enum CaptureState
{
    Idle,
    PermissionRequired,
    Selecting,
    Capturing,
    Editing,
    Cancelled
}
