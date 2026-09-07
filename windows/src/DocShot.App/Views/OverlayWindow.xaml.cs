using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using DocShot.App.Services;
using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Microsoft.Win32;

namespace DocShot.App.Views;

public partial class OverlayWindow : Window
{
    public DisplayMonitorInfo MonitorInfo { get; }

    private readonly List<WindowInfo> _discoveredWindows = new();
    private WindowInfo? _hoveredWindow;

    private Point _startPoint;
    private bool _isDragging;

    // Selection & Capture State
    private bool _hasSelectedRegion;
    private RectD _selectedDipRect;
    private BitmapSource? _capturedBitmap;

    // Annotation Canvas Engine
    private AnnotationTool _currentTool = AnnotationTool.Arrow;
    private RgbaColor _currentColor = RgbaColor.Red;
    private double _currentStrokeWidth = 3.0;

    private readonly List<AnnotationItem> _annotations = new();
    private readonly Stack<List<AnnotationItem>> _undoStack = new();
    private readonly Stack<List<AnnotationItem>> _redoStack = new();

    private AnnotationItem? _selectedItemForMove;
    private Point _moveStartPoint;
    private List<PointD> _activeHighlighterPoints = new();

    public RectD LastSelectedDipRect => _selectedDipRect;
    public RectD LastSelectedPhysicalRect { get; private set; }

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
        FakesTag.Visibility = AppServices.IsUsingFakes ? Visibility.Visible : Visibility.Collapsed;
        BadgeDetails.Text = $"Physical: {monitorInfo.PhysicalBounds.Width}x{monitorInfo.PhysicalBounds.Height} | DIPs: {monitorInfo.DipBounds.Width:F0}x{monitorInfo.DipBounds.Height:F0} | Scale: {monitorInfo.ScaleFactor * 100:F0}% ({monitorInfo.DpiX} DPI)";

        LoadDiscoveredWindows();
    }

    private void LoadDiscoveredWindows()
    {
        try
        {
            var windows = AppServices.WindowDiscovery.GetEligibleWindows();
            _discoveredWindows.Clear();
            _discoveredWindows.AddRange(windows);
        }
        catch
        {
            // Fallback if window discovery fails
        }
    }

    private void OverlayCanvas_MouseDown(object sender, MouseButtonEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;

        Point mousePos = e.GetPosition(OverlayCanvas);

        if (!_hasSelectedRegion)
        {
            // Phase 1: Window or Region Selection
            if (_hoveredWindow != null)
            {
                // Select exact hovered window bounds
                SelectWindowTarget(_hoveredWindow);
                return;
            }

            _startPoint = mousePos;
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
        else
        {
            // Phase 2: Drawing Annotations on Selected Region
            SaveUndoSnapshot();

            _startPoint = mousePos;
            _isDragging = true;

            if (_currentTool == AnnotationTool.Select)
            {
                // Check if user clicked an existing annotation to move it
                var hit = _annotations.LastOrDefault(a => a.BoundingBox.Contains(new PointD(mousePos.X, mousePos.Y)));
                if (hit != null)
                {
                    _selectedItemForMove = hit;
                    _moveStartPoint = mousePos;
                }
            }
            else if (_currentTool == AnnotationTool.Highlighter)
            {
                _activeHighlighterPoints = new List<PointD> { new PointD(mousePos.X, mousePos.Y) };
            }

            OverlayCanvas.CaptureMouse();
        }
    }

    private void OverlayCanvas_MouseMove(object sender, MouseEventArgs e)
    {
        Point mousePos = e.GetPosition(OverlayCanvas);

        if (!_hasSelectedRegion)
        {
            // Window Discovery Hover Detection
            if (!_isDragging)
            {
                WindowInfo? hovered = _discoveredWindows.FirstOrDefault(w =>
                    w.BoundsInScreen.Contains(new PointD(mousePos.X + MonitorInfo.PhysicalBounds.X, mousePos.Y + MonitorInfo.PhysicalBounds.Y)) ||
                    (w.BoundsInScreen.X <= mousePos.X && mousePos.X <= w.BoundsInScreen.X + w.BoundsInScreen.Width &&
                     w.BoundsInScreen.Y <= mousePos.Y && mousePos.Y <= w.BoundsInScreen.Y + w.BoundsInScreen.Height));

                if (hovered != _hoveredWindow)
                {
                    _hoveredWindow = hovered;
                    if (hovered != null)
                    {
                        double dipX = hovered.BoundsInScreen.X;
                        double dipY = hovered.BoundsInScreen.Y;
                        double dipW = hovered.BoundsInScreen.Width;
                        double dipH = hovered.BoundsInScreen.Height;

                        Canvas.SetLeft(WindowHighlightBox, dipX);
                        Canvas.SetTop(WindowHighlightBox, dipY);
                        WindowHighlightBox.Width = dipW;
                        WindowHighlightBox.Height = dipH;
                        WindowHighlightBox.Visibility = Visibility.Visible;

                        Canvas.SetLeft(WindowHoverBadge, dipX);
                        Canvas.SetTop(WindowHoverBadge, Math.Max(10, dipY - 35));
                        HoverTitleText.Text = hovered.Title;
                        HoverProcessText.Text = $"({hovered.OwnerName})";
                        WindowHoverBadge.Visibility = Visibility.Visible;
                    }
                    else
                    {
                        WindowHighlightBox.Visibility = Visibility.Collapsed;
                        WindowHoverBadge.Visibility = Visibility.Collapsed;
                    }
                }
            }
            else
            {
                // Drag Region Selection
                double x = Math.Min(_startPoint.X, mousePos.X);
                double y = Math.Min(_startPoint.Y, mousePos.Y);
                double w = Math.Abs(_startPoint.X - mousePos.X);
                double h = Math.Abs(_startPoint.Y - mousePos.Y);

                Canvas.SetLeft(SelectionBox, x);
                Canvas.SetTop(SelectionBox, y);
                SelectionBox.Width = w;
                SelectionBox.Height = h;

                Canvas.SetLeft(DimensionBadge, x);
                Canvas.SetTop(DimensionBadge, Math.Max(10, y - 50));

                var dipRect = new RectD(x, y, w, h);
                var physRect = MonitorInfo.DipToPhysical(dipRect);

                DipDimText.Text = $"DIPs: {w:F0} x {h:F0} (Offset: {x:F0}, {y:F0})";
                PhysDimText.Text = $"Source Pixels: {physRect.Width:F0} x {physRect.Height:F0} px (Offset: {physRect.X:F0}, {physRect.Y:F0})";
            }
        }
        else
        {
            // Drawing Annotations Live Preview
            if (!_isDragging) return;

            if (_currentTool == AnnotationTool.Select && _selectedItemForMove != null)
            {
                double deltaX = mousePos.X - _moveStartPoint.X;
                double deltaY = mousePos.Y - _moveStartPoint.Y;
                _moveStartPoint = mousePos;

                int idx = _annotations.IndexOf(_selectedItemForMove);
                if (idx >= 0)
                {
                    _selectedItemForMove = _selectedItemForMove.Translated(new SizeD(deltaX, deltaY));
                    _annotations[idx] = _selectedItemForMove;
                    RedrawAnnotations();
                }
            }
            else if (_currentTool == AnnotationTool.Highlighter)
            {
                _activeHighlighterPoints.Add(new PointD(mousePos.X, mousePos.Y));
                RedrawAnnotations();
            }
            else
            {
                // Live preview of shape being drawn
                double x = Math.Min(_startPoint.X, mousePos.X);
                double y = Math.Min(_startPoint.Y, mousePos.Y);
                double w = Math.Abs(_startPoint.X - mousePos.X);
                double h = Math.Abs(_startPoint.Y - mousePos.Y);

                // Temporary preview item
                var previewShape = BuildShape(_currentTool, _startPoint, mousePos, x, y, w, h);
                if (previewShape != null)
                {
                    RedrawAnnotations();
                    CanvasExporter.RenderAnnotationItem(new DrawingVisual().RenderOpen(), new AnnotationItem(previewShape, _currentColor, _currentStrokeWidth));
                }
            }
        }
    }

    private void OverlayCanvas_MouseUp(object sender, MouseButtonEventArgs e)
    {
        if (!_isDragging) return;

        _isDragging = false;
        OverlayCanvas.ReleaseMouseCapture();

        Point endPoint = e.GetPosition(OverlayCanvas);

        if (!_hasSelectedRegion)
        {
            double x = Math.Min(_startPoint.X, endPoint.X);
            double y = Math.Min(_startPoint.Y, endPoint.Y);
            double w = Math.Abs(_startPoint.X - endPoint.X);
            double h = Math.Abs(_startPoint.Y - endPoint.Y);

            if (w < 10 || h < 10)
            {
                SelectionBox.Visibility = Visibility.Collapsed;
                DimensionBadge.Visibility = Visibility.Collapsed;
                return;
            }

            _selectedDipRect = new RectD(x, y, w, h);
            LastSelectedPhysicalRect = MonitorInfo.DipToPhysical(_selectedDipRect);

            // Execute capture and activate annotation canvas
            _ = ActivateSelectionRegionAsync(_selectedDipRect);
        }
        else
        {
            if (_selectedItemForMove != null)
            {
                _selectedItemForMove = null;
                return;
            }

            double x = Math.Min(_startPoint.X, endPoint.X);
            double y = Math.Min(_startPoint.Y, endPoint.Y);
            double w = Math.Abs(_startPoint.X - endPoint.X);
            double h = Math.Abs(_startPoint.Y - endPoint.Y);

            AnnotationShape? shape = null;
            if (_currentTool == AnnotationTool.Highlighter)
            {
                if (_activeHighlighterPoints.Count > 1)
                {
                    shape = new AnnotationShape.Highlighter(_activeHighlighterPoints.ToList());
                }
            }
            else
            {
                shape = BuildShape(_currentTool, _startPoint, endPoint, x, y, w, h);
            }

            if (shape != null)
            {
                var newItem = new AnnotationItem(shape, _currentColor, _currentStrokeWidth);
                _annotations.Add(newItem);
                RedrawAnnotations();
            }
        }
    }

    private AnnotationShape? BuildShape(AnnotationTool tool, Point start, Point end, double x, double y, double w, double h)
    {
        return tool switch
        {
            AnnotationTool.Arrow => new AnnotationShape.Arrow(new PointD(start.X, start.Y), new PointD(end.X, end.Y)),
            AnnotationTool.Rectangle => new AnnotationShape.Rectangle(new RectD(x, y, Math.Max(w, 5), Math.Max(h, 5)), false),
            AnnotationTool.Ellipse => new AnnotationShape.Ellipse(new RectD(x, y, Math.Max(w, 5), Math.Max(h, 5)), false),
            AnnotationTool.Text => new AnnotationShape.Text(new RectD(start.X, start.Y, Math.Max(w, 100), Math.Max(h, 30)), "Text Annotation", 16.0),
            AnnotationTool.Redaction => new AnnotationShape.Redaction(new RectD(x, y, Math.Max(w, 10), Math.Max(h, 10)), RedactionStyle.Blur),
            _ => null
        };
    }

    private void SelectWindowTarget(WindowInfo window)
    {
        double x = window.BoundsInScreen.X;
        double y = window.BoundsInScreen.Y;
        double w = window.BoundsInScreen.Width;
        double h = window.BoundsInScreen.Height;

        _selectedDipRect = new RectD(x, y, w, h);
        LastSelectedPhysicalRect = MonitorInfo.DipToPhysical(_selectedDipRect);

        WindowHighlightBox.Visibility = Visibility.Collapsed;
        WindowHoverBadge.Visibility = Visibility.Collapsed;

        _ = ActivateSelectionRegionAsync(_selectedDipRect);
    }

    private async Task ActivateSelectionRegionAsync(RectD region)
    {
        _hasSelectedRegion = true;

        // Perform screen capture via IScreenCaptureService
        var capturedImage = await AppServices.ScreenCapture.CaptureRegion(1, region);
        _capturedBitmap = CanvasExporter.ToBitmapSource(capturedImage);

        CapturedBackgroundImage.Source = _capturedBitmap;
        Canvas.SetLeft(CapturedBackgroundImage, region.X);
        Canvas.SetTop(CapturedBackgroundImage, region.Y);
        CapturedBackgroundImage.Width = region.Width;
        CapturedBackgroundImage.Height = region.Height;
        CapturedBackgroundImage.Visibility = Visibility.Visible;

        SelectionBox.Visibility = Visibility.Collapsed;
        DimensionBadge.Visibility = Visibility.Collapsed;
        MonitorBadge.Visibility = Visibility.Collapsed;

        // Show floating Annotation Toolbar
        AnnotationToolbar.Visibility = Visibility.Visible;
    }

    private void RedrawAnnotations()
    {
        // Clear previous annotation UI elements from canvas
        var toRemove = OverlayCanvas.Children.OfType<FrameworkElement>()
            .Where(f => f.Tag?.ToString() == "AnnotationElement")
            .ToList();

        foreach (var el in toRemove)
        {
            OverlayCanvas.Children.Remove(el);
        }

        // Render all annotation items
        var visual = new DrawingVisual();
        using (var dc = visual.RenderOpen())
        {
            foreach (var item in _annotations)
            {
                CanvasExporter.RenderAnnotationItem(dc, item);
            }
        }

        // Draw visual to canvas image
        var rtb = new RenderTargetBitmap(
            Math.Max(1, (int)Width),
            Math.Max(1, (int)Height),
            96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);

        var img = new Image
        {
            Source = rtb,
            Width = Width,
            Height = Height,
            Tag = "AnnotationElement"
        };
        Canvas.SetLeft(img, 0);
        Canvas.SetTop(img, 0);
        OverlayCanvas.Children.Add(img);
    }

    // --- Toolbar & Action Button Handlers ---

    private void Tool_Click(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton rb && rb.Tag != null)
        {
            if (Enum.TryParse<AnnotationTool>(rb.Tag.ToString(), out var tool))
            {
                _currentTool = tool;
            }
        }
    }

    private void Color_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button btn && btn.Tag != null)
        {
            _currentColor = btn.Tag.ToString() switch
            {
                "Red" => RgbaColor.Red,
                "Green" => RgbaColor.Green,
                "Blue" => RgbaColor.Blue,
                "Yellow" => RgbaColor.Yellow,
                "White" => RgbaColor.White,
                _ => RgbaColor.Red
            };
        }
    }

    private void SaveUndoSnapshot()
    {
        _undoStack.Push(_annotations.Select(a => a).ToList());
        _redoStack.Clear();
    }

    private void Undo_Click(object sender, RoutedEventArgs e)
    {
        if (_undoStack.Count > 0)
        {
            _redoStack.Push(_annotations.Select(a => a).ToList());
            _annotations.Clear();
            _annotations.AddRange(_undoStack.Pop());
            RedrawAnnotations();
        }
    }

    private void Redo_Click(object sender, RoutedEventArgs e)
    {
        if (_redoStack.Count > 0)
        {
            _undoStack.Push(_annotations.Select(a => a).ToList());
            _annotations.Clear();
            _annotations.AddRange(_redoStack.Pop());
            RedrawAnnotations();
        }
    }

    private void CopyPng_Click(object sender, RoutedEventArgs e)
    {
        if (_capturedBitmap == null) return;

        byte[] pngBytes = CanvasExporter.ExportToPngBytes(_capturedBitmap, _annotations, _selectedDipRect, MonitorInfo.ScaleFactor);
        bool success = AppServices.Pasteboard.WritePng(pngBytes);

        ShowToast(success ? "Copied PNG to Clipboard!" : "Failed to Copy PNG");
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (_capturedBitmap == null) return;

        var saveDialog = new SaveFileDialog
        {
            Filter = "PNG Image (*.png)|*.png|All Files (*.*)|*.*",
            DefaultExt = "png",
            FileName = $"DocShot_{DateTime.Now:yyyyMMdd_HHmmss}.png"
        };

        if (saveDialog.ShowDialog() == true)
        {
            byte[] pngBytes = CanvasExporter.ExportToPngBytes(_capturedBitmap, _annotations, _selectedDipRect, MonitorInfo.ScaleFactor);
            AppServices.FileWriter.Write(pngBytes, new Uri(saveDialog.FileName));
            ShowToast("Saved Screenshot!");
        }
    }

    private void Discard_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }

    private void ShowToast(string message)
    {
        ToastText.Text = message;
        ToastNotification.Visibility = Visibility.Visible;

        Task.Delay(2000).ContinueWith(_ =>
        {
            Dispatcher.Invoke(() => ToastNotification.Visibility = Visibility.Collapsed);
        });
    }

    private void Window_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Close();
        }
        else if (e.Key == Key.Z && (Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            Undo_Click(sender, e);
        }
        else if (e.Key == Key.Y && (Keyboard.Modifiers & ModifierKeys.Control) != 0)
        {
            Redo_Click(sender, e);
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
