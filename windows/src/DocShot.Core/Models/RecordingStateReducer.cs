namespace DocShot.Core.Models;

/// <summary>
/// The whole recording transition table, as a deterministic value type - a line-for-line port of
/// the macOS <c>RecordingStateReducer</c>.
/// </summary>
/// <remarks>
/// Every rule that matters for correctness lives here rather than in a coordinator: duplicate
/// start and stop requests are refused, late callbacks from an ended session are dropped, and each
/// terminal path emits the cleanup effects that remove temporary media. That keeps those
/// guarantees testable with no capture session, no permission, and no window - see
/// <c>DocShot.Core.Tests/RecordingStateReducerTests.cs</c>, which should stay behaviourally
/// equivalent to the macOS <c>RecordingStateReducerTests</c> suite case-for-case.
/// </remarks>
public sealed class RecordingStateReducer
{
    public RecordingState State { get; private set; }

    /// <summary>The session events must belong to in order to be acted on.</summary>
    public RecordingSessionId Generation { get; private set; }

    /// <summary>Set when Stop arrives while the stream is still opening. Tearing down a half-open
    /// session races the start; instead the stop is honoured the moment the stream reports it started.</summary>
    private bool _stopRequestedWhileStarting;

    /// <summary>Guards against a second save panel while one is already open.</summary>
    private bool _isSavePanelOpen;

    public RecordingStateReducer(RecordingState? state = null, RecordingSessionId? generation = null)
    {
        State = state ?? RecordingState.IdleState;
        Generation = generation ?? RecordingSessionId.Initial;
    }

    public IReadOnlyList<RecordingEffect> Apply(RecordingEvent @event)
    {
        // A callback from a session the user already ended. It must not move the state machine -
        // but anything it produced is still deleted, which is what keeps a late stop from
        // stranding a temporary file.
        if (@event.Session is { } eventSession && eventSession != Generation)
        {
            return @event.TemporaryUrl is { } url
                ? [new RecordingEffect.RemoveTemporary(url)]
                : [];
        }

        switch (@event)
        {
            case RecordingEvent.RequestRecording:
                if (State is not RecordingState.Idle) return [new RecordingEffect.RejectDuplicateRequest()];
                Generation = Generation.Next();
                State = new RecordingState.Selecting();
                return [new RecordingEffect.PreflightPermission(Generation)];

            case RecordingEvent.PermissionResolved e:
            {
                if (State is not RecordingState.Selecting) return [];
                if (!e.Granted)
                {
                    State = new RecordingState.PermissionRequired();
                    return [new RecordingEffect.PresentPermissionRequired()];
                }
                // Overlays are created here and nowhere else, so no selection UI can precede a
                // granted permission.
                return [new RecordingEffect.BeginSelection(Generation)];
            }

            case RecordingEvent.TargetSelected e:
                if (State is not RecordingState.Selecting) return [];
                State = new RecordingState.AwaitingConfirmation(e.Target);
                return [];

            case RecordingEvent.TargetRejected e:
                if (State is not RecordingState.Selecting) return [];
                // Selection stays open: the user retries rather than losing the session.
                return [new RecordingEffect.PresentTargetRejection(e.Rejection)];

            case RecordingEvent.SelectionCancelled:
                switch (State)
                {
                    case RecordingState.Selecting:
                    case RecordingState.AwaitingConfirmation:
                    case RecordingState.PermissionRequired:
                        Generation = Generation.Next();
                        State = RecordingState.IdleState;
                        return [new RecordingEffect.CloseOverlays()];
                    default:
                        return [];
                }

            case RecordingEvent.ConfirmRecord:
            {
                if (State is not RecordingState.AwaitingConfirmation confirming) return [];
                State = new RecordingState.Starting(confirming.Target);
                // Overlays close before the stream opens, so DocShot's own selection UI cannot
                // appear in the recorded pixels.
                return [new RecordingEffect.CloseOverlays(), new RecordingEffect.StartSession(confirming.Target, Generation)];
            }

            case RecordingEvent.ConfirmCancel:
                if (State is not RecordingState.AwaitingConfirmation) return [];
                Generation = Generation.Next();
                State = RecordingState.IdleState;
                // No stream was started and no temporary file was minted: nothing to clean up.
                return [new RecordingEffect.CloseOverlays()];

            case RecordingEvent.SessionStarted e:
            {
                if (State is not RecordingState.Starting starting) return [];
                if (_stopRequestedWhileStarting)
                {
                    _stopRequestedWhileStarting = false;
                    State = new RecordingState.Stopping();
                    return [new RecordingEffect.StopSession(Generation)];
                }
                State = new RecordingState.Recording(starting.Target, e.At);
                return [];
            }

            case RecordingEvent.SessionStartFailed e:
                if (State is not RecordingState.Starting) return [];
                return EndSession(e.Failure, e.Url);

            case RecordingEvent.StopRequested:
                switch (State)
                {
                    case RecordingState.Starting:
                        _stopRequestedWhileStarting = true;
                        return [];
                    case RecordingState.Recording:
                        State = new RecordingState.Stopping();
                        return [new RecordingEffect.StopSession(Generation)];
                    default:
                        // Includes the repeated-Stop case: stopping is single-flight.
                        return [];
                }

            case RecordingEvent.SessionStopped e:
                if (State is not RecordingState.Stopping) return [];
                State = new RecordingState.AwaitingOutput(e.Recording);
                // Nothing is written outside temporary storage until the user chooses.
                return [new RecordingEffect.PresentOutputChoice(e.Recording)];

            case RecordingEvent.SessionStopFailed e:
                if (State is not RecordingState.Stopping) return [];
                return EndSession(e.Failure, e.Url);

            case RecordingEvent.StreamFailed e:
                switch (State)
                {
                    case RecordingState.Starting:
                    case RecordingState.Recording:
                    case RecordingState.Stopping:
                        return EndSession(e.Failure, e.Url);
                    default:
                        // The session is already over; only its media still matters.
                        return e.Url is { } url ? [new RecordingEffect.RemoveTemporary(url)] : [];
                }

            case RecordingEvent.SaveRequested:
            {
                if (State is not RecordingState.AwaitingOutput awaiting || _isSavePanelOpen) return [];
                _isSavePanelOpen = true;
                return [new RecordingEffect.PresentSavePanel(awaiting.Recording)];
            }

            case RecordingEvent.SaveCompleted e:
            {
                _isSavePanelOpen = false;
                if (State is not RecordingState.AwaitingOutput awaiting) return [];
                switch (e.Result)
                {
                    case SaveResult.Saved:
                        Generation = Generation.Next();
                        State = RecordingState.IdleState;
                        // The move already consumed the temporary file; removal is a no-op that
                        // keeps the "every session ends with a removal" invariant true on every path.
                        return [new RecordingEffect.RemoveTemporary(awaiting.Recording.Url)];
                    case SaveResult.Cancelled:
                        // A cancelled panel is not a discard: the recording is still the user's to keep.
                        return [new RecordingEffect.PresentOutputChoice(awaiting.Recording)];
                    case SaveResult.Failed failed:
                        return
                        [
                            new RecordingEffect.PresentFailure(new RecordingFailure.OutputSave(failed.Message)),
                            new RecordingEffect.PresentOutputChoice(awaiting.Recording)
                        ];
                    default:
                        return [];
                }
            }

            case RecordingEvent.DiscardRequested:
            {
                if (State is not RecordingState.AwaitingOutput awaiting) return [];
                Generation = Generation.Next();
                State = RecordingState.IdleState;
                return [new RecordingEffect.RemoveTemporary(awaiting.Recording.Url)];
            }

            case RecordingEvent.FailureAcknowledged:
                if (State is not RecordingState.Failed) return [];
                State = RecordingState.IdleState;
                return [new RecordingEffect.CloseOverlays()];

            case RecordingEvent.AppWillTerminate:
            {
                var ended = Generation;
                Generation = Generation.Next();
                _stopRequestedWhileStarting = false;
                _isSavePanelOpen = false;

                var effects = new List<RecordingEffect>();
                switch (State)
                {
                    case RecordingState.Starting:
                    case RecordingState.Recording:
                    case RecordingState.Stopping:
                        // The live session owns its file; cancelling it removes the media. The
                        // coordinator also sweeps its temporary directory, so a session that never
                        // reported its URL cannot leave an orphan behind.
                        effects.Add(new RecordingEffect.CancelSession(ended));
                        break;
                    case RecordingState.AwaitingOutput awaiting:
                        effects.Add(new RecordingEffect.RemoveTemporary(awaiting.Recording.Url));
                        break;
                    case RecordingState.ExportingGif exporting:
                        effects.Add(new RecordingEffect.RemoveTemporary(exporting.Recording.Url));
                        break;
                }
                effects.Add(new RecordingEffect.CloseOverlays());
                State = RecordingState.IdleState;
                return effects;
            }

            default:
                return [];
        }
    }

    /// <summary>Ends the live session on a failure path: invalidate the generation so nothing it
    /// emits later is honoured, cancel it, delete its media, and report the failure.</summary>
    private List<RecordingEffect> EndSession(RecordingFailure failure, Uri? temporaryUrl)
    {
        var ended = Generation;
        Generation = Generation.Next();
        _stopRequestedWhileStarting = false;
        State = new RecordingState.Failed(failure);

        var effects = new List<RecordingEffect> { new RecordingEffect.CancelSession(ended) };
        if (temporaryUrl is { } url)
        {
            effects.Add(new RecordingEffect.RemoveTemporary(url));
        }
        effects.Add(new RecordingEffect.PresentFailure(failure));
        return effects;
    }
}
