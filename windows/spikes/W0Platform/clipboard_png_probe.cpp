#include <windows.h>
#include <wincodec.h>
#include <objbase.h>

#include <iostream>
#include <vector>

static std::vector<unsigned char> MakeDib(int width, int height) {
    BITMAPINFOHEADER header{};
    header.biSize = sizeof(BITMAPINFOHEADER);
    header.biWidth = width;
    header.biHeight = -height;
    header.biPlanes = 1;
    header.biBitCount = 32;
    header.biCompression = BI_RGB;

    std::vector<unsigned char> dib(sizeof(BITMAPINFOHEADER) + width * height * 4);
    memcpy(dib.data(), &header, sizeof(header));
    auto* px = dib.data() + sizeof(BITMAPINFOHEADER);
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            auto* p = px + (y * width + x) * 4;
            p[0] = static_cast<unsigned char>(255 - x * 2);
            p[1] = static_cast<unsigned char>(y * 2);
            p[2] = 48;
            p[3] = static_cast<unsigned char>((x + y) % 256);
        }
    }
    return dib;
}

static std::vector<unsigned char> EncodePngFromDib(std::vector<unsigned char> const& dib) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IWICImagingFactory* factory{};
    CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&factory));
    IStream* stream{};
    CreateStreamOnHGlobal(nullptr, TRUE, &stream);
    IWICBitmapEncoder* encoder{};
    factory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &encoder);
    encoder->Initialize(stream, WICBitmapEncoderNoCache);
    IWICBitmapFrameEncode* frame{};
    encoder->CreateNewFrame(&frame, nullptr);
    frame->Initialize(nullptr);

    auto* header = reinterpret_cast<BITMAPINFOHEADER const*>(dib.data());
    UINT width = static_cast<UINT>(header->biWidth);
    UINT height = static_cast<UINT>(-header->biHeight);
    frame->SetSize(width, height);
    WICPixelFormatGUID format = GUID_WICPixelFormat32bppBGRA;
    frame->SetPixelFormat(&format);
    frame->WritePixels(height, width * 4, width * height * 4,
        const_cast<BYTE*>(dib.data() + sizeof(BITMAPINFOHEADER)));
    frame->Commit();
    encoder->Commit();

    HGLOBAL global{};
    GetHGlobalFromStream(stream, &global);
    SIZE_T size = GlobalSize(global);
    std::vector<unsigned char> png(size);
    void* locked = GlobalLock(global);
    memcpy(png.data(), locked, size);
    GlobalUnlock(global);

    frame->Release();
    encoder->Release();
    stream->Release();
    factory->Release();
    CoUninitialize();
    return png;
}

static HANDLE MoveToClipboard(std::vector<unsigned char> const& bytes) {
    HGLOBAL handle = GlobalAlloc(GMEM_MOVEABLE, bytes.size());
    void* locked = GlobalLock(handle);
    memcpy(locked, bytes.data(), bytes.size());
    GlobalUnlock(handle);
    return handle;
}

int wmain() {
    UINT pngFormat = RegisterClipboardFormatW(L"PNG");
    if (pngFormat == 0) {
        std::wcerr << L"RegisterClipboardFormat(\"PNG\") failed.\n";
        return 2;
    }

    auto dib = MakeDib(127, 95);
    auto png = EncodePngFromDib(dib);

    if (!OpenClipboard(nullptr)) {
        std::wcerr << L"OpenClipboard failed.\n";
        return 3;
    }
    EmptyClipboard();
    SetClipboardData(pngFormat, MoveToClipboard(png));
    SetClipboardData(CF_DIB, MoveToClipboard(dib));
    CloseClipboard();

    if (!OpenClipboard(nullptr)) return 4;
    bool hasPng = IsClipboardFormatAvailable(pngFormat);
    bool hasDib = IsClipboardFormatAvailable(CF_DIB);
    HANDLE pngHandle = GetClipboardData(pngFormat);
    HANDLE dibHandle = GetClipboardData(CF_DIB);
    SIZE_T pngSize = pngHandle ? GlobalSize(pngHandle) : 0;
    SIZE_T dibSize = dibHandle ? GlobalSize(dibHandle) : 0;
    CloseClipboard();

    std::wcout << (hasPng && hasDib ? L"PASS " : L"FAIL ")
               << L"registeredPngFormat=" << pngFormat
               << L" pngBytes=" << pngSize
               << L" cfDibBytes=" << dibSize
               << L" alphaTestImage=127x95\n";

    return hasPng && hasDib && pngSize > 0 && dibSize > 0 ? 0 : 1;
}
