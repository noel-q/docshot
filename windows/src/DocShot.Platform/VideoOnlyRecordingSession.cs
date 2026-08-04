using DocShot.Core.Models;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.Platform;

public sealed class RecordingSessionFactory(IScreenCaptureService? captureService = null) : IRecordingSessionFactory
{
    private readonly IScreenCaptureService _captureService = captureService ?? new GdiScreenCaptureService();

    public IRecordingSession MakeSession() => new VideoOnlyRecordingSession(_captureService);
}

public sealed class VideoOnlyRecordingSession(IScreenCaptureService captureService) : IRecordingSession
{
    private readonly object _gate = new();
    private CancellationTokenSource? _captureCancellation;
    private Task? _captureTask;
    private RecordingTarget? _target;
    private RecordingOptions? _options;
    private Uri? _outputUrl;
    private DateTimeOffset _startedAt;
    private SizeD _pixelSize;
    private long _framesWritten;
    private bool _stopping;

    public Task Start(RecordingTarget target, RecordingOptions options, Uri outputUrl, CancellationToken cancellationToken = default)
    {
        if (!options.IsVideoOnly)
        {
            throw new NotSupportedException("Audio capture is deferred until W4; use process-exclusive WASAPI loopback as the default audio path when it lands.");
        }

        lock (_gate)
        {
            if (_captureTask is not null) throw new InvalidOperationException("Recording session already started.");

            _target = target;
            _options = options;
            _outputUrl = outputUrl;
            _pixelSize = SizeFor(target);
            _startedAt = DateTimeOffset.UtcNow;
            _captureCancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            _captureTask = Task.Run(() => CaptureLoop(_captureCancellation.Token), CancellationToken.None);
        }

        return Task.CompletedTask;
    }

    public async Task<TemporaryRecording> Stop(CancellationToken cancellationToken = default)
    {
        Task captureTask;
        Uri outputUrl;
        SizeD pixelSize;
        DateTimeOffset startedAt;

        lock (_gate)
        {
            if (_captureTask is null || _captureCancellation is null || _outputUrl is null)
            {
                throw new InvalidOperationException("Recording session has not started.");
            }
            if (_stopping) throw new InvalidOperationException("Recording session is already stopping.");
            _stopping = true;

            captureTask = _captureTask;
            outputUrl = _outputUrl;
            pixelSize = _pixelSize;
            startedAt = _startedAt;
            _captureCancellation.Cancel();
        }

        await captureTask.WaitAsync(cancellationToken).ConfigureAwait(false);
        var duration = Math.Max(1.0 / Math.Max(1, _options?.MaximumFrameRate ?? RecordingOptions.DefaultMaximumFrameRate),
            (DateTimeOffset.UtcNow - startedAt).TotalSeconds);

        return new TemporaryRecording(outputUrl, duration, pixelSize, HasAudio: false, CreatedAt: DateTimeOffset.UtcNow);
    }

    public async Task Cancel()
    {
        Task? captureTask;
        Uri? outputUrl;
        lock (_gate)
        {
            _captureCancellation?.Cancel();
            captureTask = _captureTask;
            outputUrl = _outputUrl;
        }

        if (captureTask is not null)
        {
            try { await captureTask.ConfigureAwait(false); }
            catch (OperationCanceledException) { }
        }

        if (outputUrl is not null)
        {
            var path = outputUrl.IsAbsoluteUri ? outputUrl.LocalPath : outputUrl.ToString();
            if (File.Exists(path)) File.Delete(path);
        }
    }

    private async Task CaptureLoop(CancellationToken cancellationToken)
    {
        var target = _target ?? throw new InvalidOperationException("No recording target.");
        var options = _options ?? throw new InvalidOperationException("No recording options.");
        var outputUrl = _outputUrl ?? throw new InvalidOperationException("No output URL.");
        var fps = Math.Clamp(options.MaximumFrameRate, 1, 60);
        var frameDelay = TimeSpan.FromSeconds(1.0 / fps);

        using var writer = new MediaFoundationVideoWriter(
            outputUrl,
            checked((int)_pixelSize.Width),
            checked((int)_pixelSize.Height),
            fps);

        while (!cancellationToken.IsCancellationRequested)
        {
            var frame = await CaptureFrame(target).ConfigureAwait(false);
            writer.WriteFrame(frame, _framesWritten++);

            try
            {
                await Task.Delay(frameDelay, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                break;
            }
        }

        if (_framesWritten == 0)
        {
            var frame = await CaptureFrame(target).ConfigureAwait(false);
            writer.WriteFrame(frame, _framesWritten++);
        }

        writer.FinalizeFile();
    }

    private Task<CapturedImage> CaptureFrame(RecordingTarget target) => target switch
    {
        RecordingTarget.Window window => captureService.CaptureWindow(window.Id),
        RecordingTarget.Region region => captureService.CaptureRegion(region.DisplayId, region.RectInDisplay),
        _ => throw new ArgumentOutOfRangeException(nameof(target)),
    };

    private static SizeD SizeFor(RecordingTarget target)
    {
        var size = target switch
        {
            RecordingTarget.Window window => window.BoundsInScreen.Size,
            RecordingTarget.Region region => region.OutputSize,
            _ => throw new ArgumentOutOfRangeException(nameof(target)),
        };

        return new SizeD(Math.Max(1, Math.Round(size.Width)), Math.Max(1, Math.Round(size.Height)));
    }
}
