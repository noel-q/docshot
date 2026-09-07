using System;
using System.Windows;
using System.Windows.Threading;
using DocShot.Core.Services;

namespace DocShot.App.Views;

public partial class RecordingStatusHud : Window
{
    private readonly IRecordingSession? _session;
    private readonly DispatcherTimer _timer = new();
    private TimeSpan _elapsed = TimeSpan.Zero;
    private bool _isPaused;

    public event EventHandler? RecordingStopped;
    public event EventHandler? RecordingDiscarded;

    public RecordingStatusHud(IRecordingSession? session = null, bool systemAudioEnabled = false)
    {
        InitializeComponent();
        _session = session;

        AudioStatusText.Text = systemAudioEnabled ? "System Audio" : "Audio Off";

        // Position HUD at top-center of primary screen
        Left = (SystemParameters.PrimaryScreenWidth - Width) / 2;
        Top = 30;

        _timer.Interval = TimeSpan.FromSeconds(1);
        _timer.Tick += (s, e) =>
        {
            if (!_isPaused)
            {
                _elapsed = _elapsed.Add(TimeSpan.FromSeconds(1));
                TimerText.Text = _elapsed.ToString(@"mm\:ss");
            }
        };
        _timer.Start();
    }

    private void PauseBtn_Click(object sender, RoutedEventArgs e)
    {
        _isPaused = !_isPaused;
        PauseBtn.Content = _isPaused ? "▶" : "⏸";
    }

    private async void StopBtn_Click(object sender, RoutedEventArgs e)
    {
        _timer.Stop();
        if (_session != null)
        {
            await _session.Stop();
        }
        RecordingStopped?.Invoke(this, EventArgs.Empty);
        Close();
    }

    private async void DiscardBtn_Click(object sender, RoutedEventArgs e)
    {
        _timer.Stop();
        if (_session != null)
        {
            await _session.Cancel();
        }
        RecordingDiscarded?.Invoke(this, EventArgs.Empty);
        Close();
    }
}
