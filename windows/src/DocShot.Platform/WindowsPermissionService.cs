using DocShot.Core.Services;

namespace DocShot.Platform;

/// <summary>
/// Windows desktop capture has no persistent TCC-style permission gate for windows/monitors the
/// app already has handles for. Keep this service so coordinators can share the macOS shape.
/// </summary>
public sealed class WindowsPermissionService : IPermissionService
{
    public bool HasScreenCaptureAccess() => true;

    public Task<bool> RequestScreenCaptureAccess() => Task.FromResult(true);
}
