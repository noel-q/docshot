using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using DocShot.App.Services;
using DocShot.Core.Primitives;

namespace DocShot.App.Views;

public partial class OverlayWindow : Window
{
    public DisplayMonitorInfo MonitorInfo { get; }

    private Point _startPoint;
    private bool _isDragging;
    public RectD LastSelectedDipRect { get; private set; }
    public RectD LastSelectedPhysicalRect { get; private set; }
    public bool LastVerificationPassed { get; private set; }

    public OverlayWindow(DisplayMonitorInfo monitorInfo)
    {
        InitializeComponent();
        MonitorInfo = monitorInfo;

        // Position window to cover monitor's DIP bounds exactly
        Left = monitorInfo.DipBounds.X;
        Top = monitorInfo.DipBounds.Y;
        Width = monitorInfo.DipBounds.Width;
        Height = monitorInfo.DipBounds.Height;

        BadgeTitle.Text = monitorInfo.DeviceName.ToUpperInvariant();
        PrimaryTag.Visibility = monitorInfo.IsPrimary ? Visibility.Visible : Visibility.Collapsed;
        BadgeDetails.Text = $"Physical: {monitorInfo.PhysicalBounds.Width}x{monitorInfo.PhysicalBounds.Height} | DIPs: {monitorInfo.DipBounds.Width:F0}x{monitorInfo.DipBounds.Height:F0} | Scale: {monitorInfo.ScaleFactor * 100:F0}% ({monitorInfo.DpiX} DPI)";
    }

    private void OverlayCanvas_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed)
        {
            _startPoint = e.GetPosition(OverlayCanvas);
            _isDragging = true;

            Canvas.SetLeft(SelectionBox, _startPoint.X);
            Canvas.SetTop(SelectionBox, _startPoint.Y);
            SelectionBox.Width = 0;
            SelectionBox.Height = 0;
            SelectionBox.Visibility = Visibility.Visible;

            DimensionBadge.Visibility = Visibility.Visible;
            ResultCard.Visibility = Visibility.Collapsed;

            OverlayCanvas.CaptureMouse();
        }
    }

    private void OverlayCanvas_MouseMove(object sender, MouseEventArgs e)
    {
        if (!_isDragging) return;

        Point currentPoint = e.GetPosition(OverlayCanvas);

        double x = Math.Min(_startPoint.X, currentPoint.X);
        double y = Math.Min(_startPoint.Y, currentPoint.Y);
        double w = Math.Abs(_startPoint.X - currentPoint.X);
        double h = Math.Abs(_startPoint.Y - currentPoint.Y);

        Canvas.SetLeft(SelectionBox, x);
        Canvas.SetTop(SelectionBox, y);
        SelectionBox.Width = w;
        SelectionBox.Height = h;

        // Position Dimension Badge near top-left of selection box
        Canvas.SetLeft(DimensionBadge, x);
        Canvas.SetTop(DimensionBadge, Math.Max(10, y - 50));

        var dipRect = new RectD(x, y, w, h);
        var physRect = MonitorInfo.DipToPhysical(dipRect);

        DipDimText.Text = $"DIPs: {w:F0} x {h:F0} (Offset: {x:F0}, {y:F0})";
        PhysDimText.Text = $"Source Pixels: {physRect.Width:F0} x {physRect.Height:F0} px (Offset: {physRect.X:F0}, {physRect.Y:F0})";
    }

    private void OverlayCanvas_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_isDragging) return;

        _isDragging = false;
        OverlayCanvas.ReleaseMouseCapture();

        Point endPoint = e.GetPosition(OverlayCanvas);

        double x = Math.Min(_startPoint.X, endPoint.X);
        double y = Math.Min(_startPoint.Y, endPoint.Y);
        double w = Math.Abs(_startPoint.X - endPoint.X);
        double h = Math.Abs(_startPoint.Y - endPoint.Y);

        if (w < 5 || h < 5)
        {
            SelectionBox.Visibility = Visibility.Collapsed;
            DimensionBadge.Visibility = Visibility.Collapsed;
            return;
        }

        var dipRect = new RectD(x, y, w, h);
        LastSelectedDipRect = dipRect;
        LastSelectedPhysicalRect = MonitorInfo.DipToPhysical(dipRect);

        bool passed = MonitorInfo.VerifyRoundTrip(LastSelectedPhysicalRect, out var rtPhys, out var rtDip);
        LastVerificationPassed = passed;

        ResultStatusText.Text = passed ? " PASS (0.00px Error)" : " FAIL";
        ResultStatusText.Foreground = passed ? new SolidColorBrush(Color.FromRgb(166, 227, 161)) : new SolidColorBrush(Color.FromRgb(243, 139, 168));

        ResultDetailsText.Text =
            $"Monitor: {MonitorInfo.DeviceName} (Scale {MonitorInfo.ScaleFactor * 100}%)\n" +
            $"1. Drag Selected (DIPs):      ({dipRect.X:F2}, {dipRect.Y:F2}, {dipRect.Width:F2}, {dipRect.Height:F2})\n" +
            $"2. Converted Physical Pixels: ({LastSelectedPhysicalRect.X:F0}, {LastSelectedPhysicalRect.Y:F0}, {LastSelectedPhysicalRect.Width:F0}, {LastSelectedPhysicalRect.Height:F0}) px\n" +
            $"3. Round-Tripped DIPs:        ({rtDip.X:F2}, {rtDip.Y:F2}, {rtDip.Width:F2}, {rtDip.Height:F2})\n" +
            $"4. Round-Tripped Physical:    ({rtPhys.X:F0}, {rtPhys.Y:F0}, {rtPhys.Width:F0}, {rtPhys.Height:F0}) px";

        ResultCard.Visibility = Visibility.Visible;
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
