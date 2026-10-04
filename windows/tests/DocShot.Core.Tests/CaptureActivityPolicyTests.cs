using DocShot.Core.Models;
using Xunit;

namespace DocShot.Core.Tests;

public class CaptureActivityPolicyTests
{
    [Fact]
    public void When_both_coordinators_are_idle_everything_is_allowed_except_stop()
    {
        var policy = CaptureActivityPolicy.Evaluate(CaptureState.Idle, RecordingState.IdleState);

        Assert.True(policy.AllowsScreenshotCapture);
        Assert.True(policy.AllowsRecordingCapture);
        Assert.False(policy.AllowsStopRecording);
    }

    [Fact]
    public void A_live_recording_blocks_screenshot_capture_from_starting()
    {
        var recording = new RecordingState.Recording(
            new RecordingTarget.Window(1, new DocShot.Core.Primitives.RectD(0, 0, 100, 100)),
            DateTimeOffset.UtcNow);

        var policy = CaptureActivityPolicy.Evaluate(CaptureState.Idle, recording);

        Assert.False(policy.AllowsScreenshotCapture);
        Assert.False(policy.AllowsRecordingCapture);
        Assert.True(policy.AllowsStopRecording);
    }

    [Fact]
    public void An_active_screenshot_capture_blocks_a_new_recording_from_starting()
    {
        var policy = CaptureActivityPolicy.Evaluate(CaptureState.Selecting, RecordingState.IdleState);

        Assert.False(policy.AllowsRecordingCapture);
        // Screenshot capture owns its own state guards; this policy does not additionally block it.
        Assert.True(policy.AllowsScreenshotCapture);
    }

    [Fact]
    public void Stop_is_only_allowed_while_starting_or_recording()
    {
        var target = new RecordingTarget.Window(1, new DocShot.Core.Primitives.RectD(0, 0, 100, 100));

        Assert.True(CaptureActivityPolicy.Evaluate(CaptureState.Idle, new RecordingState.Starting(target)).AllowsStopRecording);
        Assert.True(CaptureActivityPolicy.Evaluate(CaptureState.Idle, new RecordingState.Recording(target, DateTimeOffset.UtcNow)).AllowsStopRecording);
        Assert.False(CaptureActivityPolicy.Evaluate(CaptureState.Idle, new RecordingState.Stopping()).AllowsStopRecording);
        Assert.False(CaptureActivityPolicy.Evaluate(CaptureState.Idle, RecordingState.IdleState).AllowsStopRecording);
    }

    [Fact]
    public void Cancelled_capture_state_counts_as_idle_for_allowing_a_new_recording()
    {
        var policy = CaptureActivityPolicy.Evaluate(CaptureState.Cancelled, RecordingState.IdleState);
        Assert.True(policy.AllowsRecordingCapture);
    }
}
