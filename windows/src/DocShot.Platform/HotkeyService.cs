using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Threading;
using DocShot.Core.Services;

namespace DocShot.Platform;

public sealed class HotkeyService : IHotkeyService, IDisposable
{
    private const int WM_HOTKEY = 0x0312;
    private const int WM_QUIT = 0x0012;

    private readonly BlockingCollection<Action<nint>> _actions = [];
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _ready = new();
    private nint _hwnd;
    private bool _disposed;

    public HotkeyService()
    {
        _thread = new Thread(MessageThread)
        {
            IsBackground = true,
            Name = "DocShot hotkey message thread",
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        _ready.Wait();
    }

    public bool Register(int id, uint modifiers, uint virtualKeyCode)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        return Invoke(hwnd => NativeMethods.RegisterHotKey(hwnd, id, modifiers, virtualKeyCode));
    }

    public void Unregister(int id)
    {
        if (_disposed) return;
        _ = Invoke(hwnd => NativeMethods.UnregisterHotKey(hwnd, id));
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_hwnd != nint.Zero)
        {
            NativeMethods.PostMessage(_hwnd, WM_QUIT, nint.Zero, nint.Zero);
        }
        _actions.CompleteAdding();
        _thread.Join(TimeSpan.FromSeconds(2));
        _actions.Dispose();
        _ready.Dispose();
    }

    private bool Invoke(Func<nint, bool> action)
    {
        var completion = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _actions.Add(hwnd =>
        {
            try
            {
                completion.SetResult(action(hwnd));
            }
            catch (Exception ex)
            {
                completion.SetException(ex);
            }
        });
        NativeMethods.PostMessage(_hwnd, NativeMethods.WM_APP_DISPATCH, nint.Zero, nint.Zero);
        return completion.Task.GetAwaiter().GetResult();
    }

    private void MessageThread()
    {
        var className = $"DocShotHotkeyMessageWindow-{Guid.NewGuid():N}";
        var wndProc = new NativeMethods.WndProc(WindowProc);
        var wc = new NativeMethods.WndClass
        {
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(wndProc),
            lpszClassName = className,
        };

        _ = NativeMethods.RegisterClass(ref wc);
        _hwnd = NativeMethods.CreateWindowEx(
            0,
            className,
            string.Empty,
            0,
            0,
            0,
            0,
            0,
            NativeMethods.HWND_MESSAGE,
            nint.Zero,
            nint.Zero,
            nint.Zero);

        _ready.Set();

        while (NativeMethods.GetMessage(out var message, nint.Zero, 0, 0) > 0)
        {
            NativeMethods.TranslateMessage(ref message);
            NativeMethods.DispatchMessage(ref message);
        }

        if (_hwnd != nint.Zero)
        {
            NativeMethods.DestroyWindow(_hwnd);
            _hwnd = nint.Zero;
        }

        GC.KeepAlive(wndProc);
    }

    private nint WindowProc(nint hwnd, uint message, nint wParam, nint lParam)
    {
        if (message == NativeMethods.WM_APP_DISPATCH)
        {
            while (_actions.TryTake(out var action))
            {
                action(hwnd);
            }
            return nint.Zero;
        }

        if (message == WM_HOTKEY)
        {
            return nint.Zero;
        }

        if (message == WM_QUIT)
        {
            NativeMethods.PostQuitMessage(0);
            return nint.Zero;
        }

        return NativeMethods.DefWindowProc(hwnd, message, wParam, lParam);
    }
}

internal static partial class NativeMethods
{
    internal const uint WM_APP_DISPATCH = 0x8000 + 1;
    internal static readonly nint HWND_MESSAGE = new(-3);

    internal delegate nint WndProc(nint hwnd, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct WndClass
    {
        internal uint style;
        internal nint lpfnWndProc;
        internal int cbClsExtra;
        internal int cbWndExtra;
        internal nint hInstance;
        internal nint hIcon;
        internal nint hCursor;
        internal nint hbrBackground;
        internal string? lpszMenuName;
        internal string lpszClassName;
    }

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern ushort RegisterClass(ref WndClass wndClass);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern nint CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        nint parent,
        nint menu,
        nint instance,
        nint param);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DestroyWindow(nint hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint virtualKeyCode);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool UnregisterHotKey(nint hwnd, int id);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool PostMessage(nint hwnd, uint message, nint wParam, nint lParam);

    [DllImport("user32.dll")]
    internal static extern void PostQuitMessage(int exitCode);

    [DllImport("user32.dll")]
    internal static extern int GetMessage(out Message message, nint hwnd, uint messageFilterMin, uint messageFilterMax);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool TranslateMessage(ref Message message);

    [DllImport("user32.dll")]
    internal static extern nint DispatchMessage(ref Message message);

    [DllImport("user32.dll")]
    internal static extern nint DefWindowProc(nint hwnd, uint message, nint wParam, nint lParam);

    [StructLayout(LayoutKind.Sequential)]
    internal struct Message
    {
        internal nint hwnd;
        internal uint message;
        internal nint wParam;
        internal nint lParam;
        internal uint time;
        internal int ptX;
        internal int ptY;
    }
}
