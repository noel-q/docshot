#include <windows.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>

#include <algorithm>
#include <chrono>
#include <psapi.h>
#include <iostream>
#include <string>
#include <thread>
#include <vector>

namespace wgc = winrt::Windows::Graphics::Capture;
namespace wdx = winrt::Windows::Graphics::DirectX;
namespace wd3d = winrt::Windows::Graphics::DirectX::Direct3D11;

extern "C" HRESULT __stdcall CreateDirect3D11DeviceFromDXGIDevice(::IDXGIDevice* dxgiDevice, ::IInspectable** graphicsDevice);

struct com_init {
    com_init() { winrt::init_apartment(winrt::apartment_type::multi_threaded); }
    ~com_init() { winrt::uninit_apartment(); }
};

struct WindowCandidate {
    HWND hwnd{};
    std::wstring title;
    std::wstring process;
    RECT rect{};
};

static std::wstring ProcessNameForWindow(HWND hwnd) {
    DWORD pid{};
    GetWindowThreadProcessId(hwnd, &pid);
    HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!process) return L"unknown";
    wchar_t path[MAX_PATH]{};
    DWORD size = MAX_PATH;
    std::wstring name = L"unknown";
    if (QueryFullProcessImageNameW(process, 0, path, &size)) {
        wchar_t* slash = wcsrchr(path, L'\\');
        name = slash ? slash + 1 : path;
    }
    CloseHandle(process);
    return name;
}

static BOOL CALLBACK EnumWindowProc(HWND hwnd, LPARAM lparam) {
    if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return TRUE;
    wchar_t title[256]{};
    GetWindowTextW(hwnd, title, 256);
    if (wcslen(title) == 0) return TRUE;

    RECT r{};
    if (!GetWindowRect(hwnd, &r)) return TRUE;
    if ((r.right - r.left) < 180 || (r.bottom - r.top) < 140) return TRUE;

    auto windows = reinterpret_cast<std::vector<WindowCandidate>*>(lparam);
    windows->push_back({ hwnd, title, ProcessNameForWindow(hwnd), r });
    return TRUE;
}

static std::vector<WindowCandidate> FindWindows() {
    std::vector<WindowCandidate> all;
    EnumWindows(EnumWindowProc, reinterpret_cast<LPARAM>(&all));

    std::vector<std::wstring> needles = { L"Edge", L"Chrome", L"Firefox", L"Calculator", L"Notepad", L"Terminal" };
    std::vector<WindowCandidate> picked;
    for (auto const& needle : needles) {
        auto it = std::find_if(all.begin(), all.end(), [&](auto const& w) {
            return w.title.find(needle) != std::wstring::npos;
        });
        if (it != all.end()) picked.push_back(*it);
        if (picked.size() >= 4) break;
    }
    if (picked.empty() && !all.empty()) picked.push_back(all.front());
    return picked;
}

static wd3d::IDirect3DDevice CreateWinRtDevice(winrt::com_ptr<ID3D11Device> const& d3dDevice) {
    winrt::com_ptr<IDXGIDevice> dxgiDevice;
    winrt::check_hresult(d3dDevice->QueryInterface(dxgiDevice.put()));
    winrt::com_ptr<::IInspectable> inspectable;
    winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice.get(), inspectable.put()));
    return inspectable.as<wd3d::IDirect3DDevice>();
}

static wgc::GraphicsCaptureItem CreateItemForWindow(HWND hwnd) {
    auto factory = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
    wgc::GraphicsCaptureItem item{ nullptr };
    winrt::check_hresult(factory->CreateForWindow(hwnd, winrt::guid_of<wgc::GraphicsCaptureItem>(), winrt::put_abi(item)));
    return item;
}

static winrt::com_ptr<ID3D11Texture2D> TextureFromSurface(wd3d::IDirect3DSurface const& surface) {
    auto access = surface.as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
    winrt::com_ptr<ID3D11Texture2D> texture;
    winrt::check_hresult(access->GetInterface(__uuidof(ID3D11Texture2D), texture.put_void()));
    return texture;
}

static bool IsMostlyBlack(ID3D11DeviceContext* context, ID3D11Texture2D* texture, int width, int height) {
    D3D11_TEXTURE2D_DESC desc{};
    texture->GetDesc(&desc);
    desc.Width = width;
    desc.Height = height;
    desc.BindFlags = 0;
    desc.MiscFlags = 0;
    desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    desc.Usage = D3D11_USAGE_STAGING;

    winrt::com_ptr<ID3D11Device> device;
    context->GetDevice(device.put());
    winrt::com_ptr<ID3D11Texture2D> staging;
    winrt::check_hresult(device->CreateTexture2D(&desc, nullptr, staging.put()));

    D3D11_BOX box{ 0, 0, 0, static_cast<UINT>(width), static_cast<UINT>(height), 1 };
    context->CopySubresourceRegion(staging.get(), 0, 0, 0, 0, texture, 0, &box);

    D3D11_MAPPED_SUBRESOURCE mapped{};
    winrt::check_hresult(context->Map(staging.get(), 0, D3D11_MAP_READ, 0, &mapped));
    auto* bytes = static_cast<unsigned char*>(mapped.pData);
    size_t nonBlack = 0;
    size_t pixels = static_cast<size_t>(width) * static_cast<size_t>(height);
    for (int y = 0; y < height; ++y) {
        auto* row = bytes + static_cast<size_t>(mapped.RowPitch) * y;
        for (int x = 0; x < width; ++x) {
            auto* p = row + x * 4;
            if (p[0] > 8 || p[1] > 8 || p[2] > 8) ++nonBlack;
        }
    }
    context->Unmap(staging.get(), 0);
    return nonBlack < pixels / 100;
}

int wmain() {
    com_init apartment;
    if (!wgc::GraphicsCaptureSession::IsSupported()) {
        std::wcerr << L"Windows Graphics Capture is not supported on this OS.\n";
        return 2;
    }

    winrt::com_ptr<ID3D11Device> d3dDevice;
    winrt::com_ptr<ID3D11DeviceContext> context;
    winrt::check_hresult(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
        nullptr, 0, D3D11_SDK_VERSION, d3dDevice.put(), nullptr, context.put()));
    auto winrtDevice = CreateWinRtDevice(d3dDevice);

    auto windows = FindWindows();
    if (windows.empty()) {
        std::wcerr << L"No suitable visible windows found.\n";
        return 3;
    }

    bool failed = false;
    bool sawStreamingTarget = false;
    for (auto const& target : windows) {
        auto item = CreateItemForWindow(target.hwnd);
        auto size = item.Size();
        auto pool = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(
            winrtDevice, wdx::DirectXPixelFormat::B8G8R8A8UIntNormalized, 2, size);
        auto session = pool.CreateCaptureSession(item);
        session.IsCursorCaptureEnabled(false);
        session.StartCapture();

        wgc::Direct3D11CaptureFrame frame{ nullptr };
        int streamFrames = 0;
        bool streamBlack = false;
        bool streamDimensionsOk = true;
        for (int i = 0; i < 60; ++i) {
            std::this_thread::sleep_for(std::chrono::milliseconds(50));
            auto next = pool.TryGetNextFrame();
            if (!next) continue;
            if (!frame) frame = next;
            auto nextSize = next.ContentSize();
            auto nextTexture = TextureFromSurface(next.Surface());
            int nextOddWidth = std::min(nextSize.Width, 101);
            int nextOddHeight = std::min(nextSize.Height, 99);
            if ((nextOddWidth % 2) == 0) --nextOddWidth;
            if ((nextOddHeight % 2) == 0) --nextOddHeight;
            streamBlack = streamBlack || IsMostlyBlack(context.get(), nextTexture.get(), nextOddWidth, nextOddHeight);
            streamDimensionsOk = streamDimensionsOk && nextOddWidth > 0 && nextOddHeight > 0
                && (nextOddWidth % 2) == 1 && (nextOddHeight % 2) == 1;
            ++streamFrames;
            if (streamFrames >= 12) break;
        }
        if (!frame) {
            std::wcout << L"FAIL no frame: " << target.title << L"\n";
            failed = true;
            continue;
        }

        auto texture = TextureFromSurface(frame.Surface());
        auto contentSize = frame.ContentSize();
        int oddWidth = std::min(contentSize.Width, 101);
        int oddHeight = std::min(contentSize.Height, 99);
        if ((oddWidth % 2) == 0) --oddWidth;
        if ((oddHeight % 2) == 0) --oddHeight;
        bool black = IsMostlyBlack(context.get(), texture.get(), oddWidth, oddHeight);
        bool dimensionsOk = oddWidth == 101 || contentSize.Width < 101;
        dimensionsOk = dimensionsOk && (oddHeight == 99 || contentSize.Height < 99);

        bool stillOk = !black && dimensionsOk;
        bool streamOk = streamFrames >= 2 && !streamBlack && streamDimensionsOk;
        sawStreamingTarget = sawStreamingTarget || streamOk;
        std::wcout << (stillOk && (streamOk || streamFrames == 1) ? L"PASS " : L"FAIL ")
                   << L"process=" << target.process << L" "
                   << L"frame=" << contentSize.Width << L"x" << contentSize.Height << L" "
                   << L"oddCrop=" << oddWidth << L"x" << oddHeight << L" "
                   << L"mostlyBlack=" << (black ? L"true" : L"false") << L" "
                   << L"streamFrames=" << streamFrames << L" "
                   << L"streamBlack=" << (streamBlack ? L"true" : L"false") << L" "
                   << L"streaming=" << (streamOk ? L"active" : L"static") << L"\n";
        failed = failed || !stillOk || streamBlack || !streamDimensionsOk;
        session.Close();
        pool.Close();
    }

    if (!sawStreamingTarget) {
        std::wcout << L"FAIL no actively repainting target produced a multi-frame stream\n";
        failed = true;
    }
    return failed ? 1 : 0;
}
