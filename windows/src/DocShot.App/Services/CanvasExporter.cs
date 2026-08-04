using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using DocShot.Core.Models;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.App.Services;

public static class CanvasExporter
{
    /// <summary>
    /// Converts a BGRA32 CapturedImage into a WPF BitmapSource.
    /// </summary>
    public static BitmapSource ToBitmapSource(CapturedImage capturedImage)
    {
        return BitmapSource.Create(
            capturedImage.PixelWidth,
            capturedImage.PixelHeight,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            capturedImage.Bgra32Pixels,
            capturedImage.PixelWidth * 4);
    }

    /// <summary>
    /// Renders a background image and a list of AnnotationItems into a flattened PNG byte array.
    /// </summary>
    public static byte[] ExportToPngBytes(BitmapSource background, IReadOnlyList<AnnotationItem> annotations, RectD targetRegionDip, double scaleFactor = 1.0)
    {
        int widthPx = Math.Max(1, (int)Math.Round(targetRegionDip.Width * scaleFactor));
        int heightPx = Math.Max(1, (int)Math.Round(targetRegionDip.Height * scaleFactor));

        var drawingVisual = new DrawingVisual();
        using (var dc = drawingVisual.RenderOpen())
        {
            // Draw background image
            dc.DrawImage(background, new Rect(0, 0, targetRegionDip.Width, targetRegionDip.Height));

            // Render each annotation item
            foreach (var item in annotations)
            {
                RenderAnnotationItem(dc, item);
            }
        }

        var renderTarget = new RenderTargetBitmap(
            widthPx,
            heightPx,
            96 * scaleFactor,
            96 * scaleFactor,
            PixelFormats.Pbgra32);

        renderTarget.Render(drawingVisual);

        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(renderTarget));

        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }

    public static void RenderAnnotationItem(DrawingContext dc, AnnotationItem item)
    {
        var strokeColor = Color.FromArgb(
            (byte)Math.Round(item.Color.A * 255),
            (byte)Math.Round(item.Color.R * 255),
            (byte)Math.Round(item.Color.G * 255),
            (byte)Math.Round(item.Color.B * 255));

        var pen = new Pen(new SolidColorBrush(strokeColor), item.StrokeWidth);

        switch (item.Shape)
        {
            case AnnotationShape.Arrow arrow:
                RenderArrow(dc, arrow, pen);
                break;

            case AnnotationShape.Rectangle rect:
                Brush rectBrush = rect.IsFilled ? new SolidColorBrush(Color.FromArgb(100, strokeColor.R, strokeColor.G, strokeColor.B)) : Brushes.Transparent;
                dc.DrawRectangle(rectBrush, pen, new Rect(rect.Rect.X, rect.Rect.Y, rect.Rect.Width, rect.Rect.Height));
                break;

            case AnnotationShape.Ellipse ellipse:
                Brush ellipseBrush = ellipse.IsFilled ? new SolidColorBrush(Color.FromArgb(100, strokeColor.R, strokeColor.G, strokeColor.B)) : Brushes.Transparent;
                double radiusX = ellipse.Rect.Width / 2.0;
                double radiusY = ellipse.Rect.Height / 2.0;
                var center = new Point(ellipse.Rect.X + radiusX, ellipse.Rect.Y + radiusY);
                dc.DrawEllipse(ellipseBrush, pen, center, radiusX, radiusY);
                break;

            case AnnotationShape.Text text:
                var formattedText = new FormattedText(
                    text.TextValue,
                    System.Globalization.CultureInfo.CurrentCulture,
                    FlowDirection.LeftToRight,
                    new Typeface("Segoe UI"),
                    text.FontSize,
                    new SolidColorBrush(strokeColor),
                    1.0);
                dc.DrawText(formattedText, new Point(text.Rect.X, text.Rect.Y));
                break;

            case AnnotationShape.Highlighter highlighter:
                if (highlighter.Points.Count > 1)
                {
                    var hlBrush = new SolidColorBrush(Color.FromArgb(100, strokeColor.R, strokeColor.G, strokeColor.B));
                    var hlPen = new Pen(hlBrush, item.StrokeWidth * 3.0) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
                    for (int i = 0; i < highlighter.Points.Count - 1; i++)
                    {
                        dc.DrawLine(hlPen, new Point(highlighter.Points[i].X, highlighter.Points[i].Y), new Point(highlighter.Points[i + 1].X, highlighter.Points[i + 1].Y));
                    }
                }
                break;

            case AnnotationShape.Redaction redaction:
                // Render redaction overlay
                Brush redactionBrush = redaction.Style == RedactionStyle.Blur
                    ? new SolidColorBrush(Color.FromArgb(180, 100, 100, 100))
                    : new SolidColorBrush(Color.FromArgb(220, 40, 40, 40));
                dc.DrawRectangle(redactionBrush, new Pen(Brushes.DarkGray, 1), new Rect(redaction.Rect.X, redaction.Rect.Y, redaction.Rect.Width, redaction.Rect.Height));
                break;
        }
    }

    private static void RenderArrow(DrawingContext dc, AnnotationShape.Arrow arrow, Pen pen)
    {
        var start = new Point(arrow.Start.X, arrow.Start.Y);
        var end = new Point(arrow.End.X, arrow.End.Y);
        dc.DrawLine(pen, start, end);

        // Arrowhead calculation
        Vector dir = end - start;
        if (dir.Length > 2)
        {
            dir.Normalize();
            Vector normal = new Vector(-dir.Y, dir.X);
            double headLength = Math.Max(12, pen.Thickness * 3.5);
            double headWidth = headLength * 0.5;

            Point arrowP1 = end - dir * headLength + normal * headWidth;
            Point arrowP2 = end - dir * headLength - normal * headWidth;

            dc.DrawLine(pen, end, arrowP1);
            dc.DrawLine(pen, end, arrowP2);
        }
    }
}
