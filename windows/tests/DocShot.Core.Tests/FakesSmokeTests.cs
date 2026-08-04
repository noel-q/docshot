using DocShot.Core.Fakes;
using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

/// <summary>
/// Not a test of production behaviour - DocShot.Core.Fakes exists to unblock DocShot.App's UI
/// work (see windows/docs/WORKSTREAMS.md "Parallelization"), so these just confirm the fakes
/// behave plausibly enough to be useful: a broken fake should fail here, not surface as a
/// confusing bug three layers up in App.
/// </summary>
public sealed class FakesSmokeTests
{
    [Fact]
    public void FakeWindowDiscoveryService_ReturnsWindows_AndRespectsExclusions()
    {
        var service = new FakeWindowDiscoveryService();
        var all = service.GetEligibleWindows();
        Assert.NotEmpty(all);

        var excluded = new HashSet<nint> { all[0].Id };
        var filtered = service.GetEligibleWindows(excluded);
        Assert.DoesNotContain(filtered, w => w.Id == all[0].Id);
        Assert.Equal(all.Count - 1, filtered.Count);
    }

    [Fact]
    public async Task FakeScreenCaptureService_CaptureRegion_MatchesRequestedDimensionsExactly()
    {
        var service = new FakeScreenCaptureService();
        var rect = new RectD(0, 0, 101, 99); // deliberately odd, matching PR #6's real-capture finding
        var image = await service.CaptureRegion(displayId: 1, rect);

        Assert.Equal(101, image.PixelWidth);
        Assert.Equal(99, image.PixelHeight);
        Assert.Equal(101 * 99 * 4, image.Bgra32Pixels.Length);
    }

    [Fact]
    public async Task FakePermissionService_AlwaysGranted()
    {
        var service = new FakePermissionService();
        Assert.True(service.HasScreenCaptureAccess());
        Assert.True(await service.RequestScreenCaptureAccess());
    }

    [Fact]
    public void FakeHotkeyService_SimulatesConflict_WhenConfigured()
    {
        var service = new FakeHotkeyService { SimulateConflictForId = 42 };

        Assert.True(service.Register(id: 1, modifiers: 0, virtualKeyCode: 0x41));
        Assert.False(service.Register(id: 42, modifiers: 0, virtualKeyCode: 0x42));
        Assert.True(service.IsRegistered(1));
        Assert.False(service.IsRegistered(42));
    }

    [Fact]
    public void FakeHotkeyService_RaisesHotkeyPressed_OnlyForRegisteredIds()
    {
        var service = new FakeHotkeyService();
        var pressedIds = new List<int>();
        service.HotkeyPressed += id => pressedIds.Add(id);

        service.Register(id: 1, modifiers: 0, virtualKeyCode: 0x41);
        service.SimulateHotkeyPress(1);
        service.SimulateHotkeyPress(99); // never registered - should not raise

        Assert.Equal([1], pressedIds);
    }

    [Fact]
    public async Task FakeRecordingSession_StartThenStop_ProducesPlayableRecording()
    {
        var session = new FakeRecordingSession();
        var target = new RecordingTarget.Region(DisplayId: 1, RectInDisplay: new RectD(0, 0, 640, 480), OutputSize: new SizeD(640, 480));
        var options = RecordingOptions.VideoOnly(showsCursor: true);
        var outputUrl = new Uri(System.IO.Path.Combine(System.IO.Path.GetTempPath(), $"{Guid.NewGuid():N}.mp4"));

        await session.Start(target, options, outputUrl);
        var recording = await session.Stop();

        Assert.True(recording.IsPlayable);
        Assert.False(recording.HasAudio);
        Assert.Equal(new SizeD(640, 480), recording.PixelSize);
    }

    [Fact]
    public async Task FakeMovieSaving_CanSimulateCancelAndFailure()
    {
        var recording = new TemporaryRecording(
            new Uri(System.IO.Path.Combine(System.IO.Path.GetTempPath(), "fake.mp4")),
            Duration: 5,
            PixelSize: new SizeD(640, 480),
            HasAudio: false,
            DateTimeOffset.UtcNow);

        var cancelling = new FakeMovieSaving { AlwaysCancel = true };
        Assert.IsType<SaveResult.Cancelled>(await cancelling.Save(recording));

        var failing = new FakeMovieSaving { AlwaysFail = true };
        Assert.IsType<SaveResult.Failed>(await failing.Save(recording));
    }

    [Fact]
    public void FakePasteboardWriter_CapturesLastWrittenBytes()
    {
        var writer = new FakePasteboardWriter();
        var bytes = new byte[] { 1, 2, 3 };

        Assert.True(writer.WritePng(bytes));
        Assert.Equal(bytes, writer.LastWritten);

        writer.AlwaysFail = true;
        Assert.False(writer.WritePng(bytes));
    }
}
