using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

/// <summary>
/// The recording transition table, including cancel, failure, and late-callback cleanup paths.
/// Mirrors the macOS <c>RecordingStateReducerTests</c> suite scenario-for-scenario so the two
/// reducers can be checked against each other by inspection.
/// </summary>
public class RecordingStateReducerTests
{
    private static readonly RecordingTarget WindowTarget =
        new RecordingTarget.Window(42, new RectD(10, 20, 400, 300));

    private static TemporaryRecording MakeRecording(string name = "clip", double duration = 3) =>
        new(
            new Uri($"file:///tmp/DocShot-Recordings/{name}.mp4"),
            duration,
            new SizeD(400, 300),
            HasAudio: false,
            CreatedAt: DateTimeOffset.FromUnixTimeSeconds(0));

    /// <summary>Drives a reducer to <see cref="RecordingState.Recording"/>, returning the live session.</summary>
    private static RecordingSessionId AdvanceToRecording(RecordingStateReducer reducer, RecordingTarget? target = null)
    {
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;
        reducer.Apply(new RecordingEvent.PermissionResolved(true, session));
        reducer.Apply(new RecordingEvent.TargetSelected(target ?? WindowTarget, session));
        reducer.Apply(new RecordingEvent.ConfirmRecord());
        reducer.Apply(new RecordingEvent.SessionStarted(DateTimeOffset.FromUnixTimeSeconds(100), session));
        return session;
    }

    [Fact]
    public void A_recording_request_preflights_permission_and_creates_no_selection_ui_yet()
    {
        var reducer = new RecordingStateReducer();

        var effects = reducer.Apply(new RecordingEvent.RequestRecording());

        Assert.IsType<RecordingState.Selecting>(reducer.State);
        Assert.Equal(new RecordingEffect[] { new RecordingEffect.PreflightPermission(reducer.Generation) }, effects);
    }

    [Fact]
    public void Selection_overlays_are_created_only_after_permission_is_granted()
    {
        var reducer = new RecordingStateReducer();
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;

        var effects = reducer.Apply(new RecordingEvent.PermissionResolved(true, session));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.BeginSelection(session) }, effects);
        Assert.IsType<RecordingState.Selecting>(reducer.State);
    }

    [Fact]
    public void Denied_permission_never_begins_a_selection()
    {
        var reducer = new RecordingStateReducer();
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;

        var effects = reducer.Apply(new RecordingEvent.PermissionResolved(false, session));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.PresentPermissionRequired() }, effects);
        Assert.IsType<RecordingState.PermissionRequired>(reducer.State);
    }

    [Fact]
    public void A_second_request_while_one_is_already_active_is_refused()
    {
        var reducer = new RecordingStateReducer();
        AdvanceToRecording(reducer);

        var effects = reducer.Apply(new RecordingEvent.RequestRecording());

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.RejectDuplicateRequest() }, effects);
        Assert.IsType<RecordingState.Recording>(reducer.State);
    }

    [Fact]
    public void Confirming_closes_overlays_before_starting_the_session()
    {
        var reducer = new RecordingStateReducer();
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;
        reducer.Apply(new RecordingEvent.PermissionResolved(true, session));
        reducer.Apply(new RecordingEvent.TargetSelected(WindowTarget, session));

        var effects = reducer.Apply(new RecordingEvent.ConfirmRecord());

        Assert.Equal(
            new RecordingEffect[] { new RecordingEffect.CloseOverlays(), new RecordingEffect.StartSession(WindowTarget, session) },
            effects);
        Assert.IsType<RecordingState.Starting>(reducer.State);
    }

    [Fact]
    public void Cancel_before_start_creates_no_session_and_no_cleanup_effect()
    {
        var reducer = new RecordingStateReducer();
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;
        reducer.Apply(new RecordingEvent.PermissionResolved(true, session));
        reducer.Apply(new RecordingEvent.TargetSelected(WindowTarget, session));

        var effects = reducer.Apply(new RecordingEvent.ConfirmCancel());

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.CloseOverlays() }, effects);
        Assert.IsType<RecordingState.Idle>(reducer.State);
    }

    [Fact]
    public void Stop_while_starting_is_deferred_until_the_session_reports_started()
    {
        var reducer = new RecordingStateReducer();
        reducer.Apply(new RecordingEvent.RequestRecording());
        var session = reducer.Generation;
        reducer.Apply(new RecordingEvent.PermissionResolved(true, session));
        reducer.Apply(new RecordingEvent.TargetSelected(WindowTarget, session));
        reducer.Apply(new RecordingEvent.ConfirmRecord());

        var stopEffects = reducer.Apply(new RecordingEvent.StopRequested());
        Assert.Empty(stopEffects);
        Assert.IsType<RecordingState.Starting>(reducer.State);

        var startedEffects = reducer.Apply(new RecordingEvent.SessionStarted(DateTimeOffset.UtcNow, session));
        Assert.Equal(new RecordingEffect[] { new RecordingEffect.StopSession(session) }, startedEffects);
        Assert.IsType<RecordingState.Stopping>(reducer.State);
    }

    [Fact]
    public void Repeated_stop_is_single_flight()
    {
        var reducer = new RecordingStateReducer();
        AdvanceToRecording(reducer);

        var first = reducer.Apply(new RecordingEvent.StopRequested());
        Assert.Single(first);
        Assert.IsType<RecordingState.Stopping>(reducer.State);

        var second = reducer.Apply(new RecordingEvent.StopRequested());
        Assert.Empty(second);
    }

    [Fact]
    public void Stopping_presents_an_output_choice_and_writes_nothing_by_itself()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        var recording = MakeRecording();

        var effects = reducer.Apply(new RecordingEvent.SessionStopped(recording, session));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.PresentOutputChoice(recording) }, effects);
        Assert.IsType<RecordingState.AwaitingOutput>(reducer.State);
    }

    [Fact]
    public void Discard_removes_the_temporary_file_and_returns_to_idle()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        var recording = MakeRecording();
        reducer.Apply(new RecordingEvent.SessionStopped(recording, session));

        var effects = reducer.Apply(new RecordingEvent.DiscardRequested());

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.RemoveTemporary(recording.Url) }, effects);
        Assert.IsType<RecordingState.Idle>(reducer.State);
    }

    [Fact]
    public void Save_success_removes_the_temporary_reference_because_the_move_already_consumed_it()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        var recording = MakeRecording();
        reducer.Apply(new RecordingEvent.SessionStopped(recording, session));
        reducer.Apply(new RecordingEvent.SaveRequested());

        var effects = reducer.Apply(new RecordingEvent.SaveCompleted(
            new SaveResult.Saved(new Uri("file:///Users/noel/Desktop/clip.mp4"))));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.RemoveTemporary(recording.Url) }, effects);
        Assert.IsType<RecordingState.Idle>(reducer.State);
    }

    [Fact]
    public void A_cancelled_save_panel_keeps_the_recording_awaiting_output_not_discarded()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        var recording = MakeRecording();
        reducer.Apply(new RecordingEvent.SessionStopped(recording, session));
        reducer.Apply(new RecordingEvent.SaveRequested());

        var effects = reducer.Apply(new RecordingEvent.SaveCompleted(new SaveResult.Cancelled()));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.PresentOutputChoice(recording) }, effects);
        Assert.IsType<RecordingState.AwaitingOutput>(reducer.State);
    }

    [Fact]
    public void A_second_save_request_is_ignored_while_a_panel_is_already_open()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        reducer.Apply(new RecordingEvent.SessionStopped(MakeRecording(), session));

        reducer.Apply(new RecordingEvent.SaveRequested());
        var second = reducer.Apply(new RecordingEvent.SaveRequested());

        Assert.Empty(second);
    }

    [Fact]
    public void A_late_stream_failure_from_a_superseded_session_only_removes_its_media()
    {
        var reducer = new RecordingStateReducer();
        var staleSession = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        reducer.Apply(new RecordingEvent.SessionStopped(MakeRecording(), staleSession));
        reducer.Apply(new RecordingEvent.DiscardRequested()); // ends the session, bumps the generation

        var staleRecording = MakeRecording("stale");
        var effects = reducer.Apply(new RecordingEvent.StreamFailed(
            new RecordingFailure.StreamInterrupted("late callback"), staleRecording.Url, staleSession));

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.RemoveTemporary(staleRecording.Url) }, effects);
        Assert.IsType<RecordingState.Idle>(reducer.State); // untouched by the stale event
    }

    [Fact]
    public void A_stream_failure_while_recording_ends_the_session_and_deletes_its_media()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        var url = new Uri("file:///tmp/DocShot-Recordings/failed.mp4");

        var effects = reducer.Apply(new RecordingEvent.StreamFailed(
            new RecordingFailure.StreamInterrupted("display disconnected"), url, session));

        Assert.Equal(
            new RecordingEffect[]
            {
                new RecordingEffect.CancelSession(session),
                new RecordingEffect.RemoveTemporary(url),
                new RecordingEffect.PresentFailure(new RecordingFailure.StreamInterrupted("display disconnected"))
            },
            effects);
        Assert.IsType<RecordingState.Failed>(reducer.State);
        // The generation was bumped, so a callback still in flight for the old session is now stale.
        Assert.NotEqual(session, reducer.Generation);
    }

    [Fact]
    public void Acknowledging_a_failure_returns_to_idle()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StreamFailed(new RecordingFailure.Writer("boom"), null, session));

        var effects = reducer.Apply(new RecordingEvent.FailureAcknowledged());

        Assert.Equal(new RecordingEffect[] { new RecordingEffect.CloseOverlays() }, effects);
        Assert.IsType<RecordingState.Idle>(reducer.State);
    }

    [Fact]
    public void App_termination_while_recording_cancels_the_session_rather_than_leaving_it_orphaned()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);

        var effects = reducer.Apply(new RecordingEvent.AppWillTerminate());

        Assert.Equal(
            new RecordingEffect[] { new RecordingEffect.CancelSession(session), new RecordingEffect.CloseOverlays() },
            effects);
        Assert.IsType<RecordingState.Idle>(reducer.State);
    }

    [Fact]
    public void App_termination_while_awaiting_output_removes_the_still_unsaved_temporary_file()
    {
        var reducer = new RecordingStateReducer();
        var session = AdvanceToRecording(reducer);
        reducer.Apply(new RecordingEvent.StopRequested());
        var recording = MakeRecording();
        reducer.Apply(new RecordingEvent.SessionStopped(recording, session));

        var effects = reducer.Apply(new RecordingEvent.AppWillTerminate());

        Assert.Equal(
            new RecordingEffect[] { new RecordingEffect.RemoveTemporary(recording.Url), new RecordingEffect.CloseOverlays() },
            effects);
    }

    [Fact]
    public void App_termination_while_idle_only_closes_overlays()
    {
        var reducer = new RecordingStateReducer();
        var effects = reducer.Apply(new RecordingEvent.AppWillTerminate());
        Assert.Equal(new RecordingEffect[] { new RecordingEffect.CloseOverlays() }, effects);
    }
}
