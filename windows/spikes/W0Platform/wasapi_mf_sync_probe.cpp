#include <windows.h>
#include <audioclient.h>
#include <avrt.h>
#include <d3d11.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mmdeviceapi.h>
#include <wrl/client.h>

#include <atomic>
#include <chrono>
#include <iostream>
#include <mutex>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;
constexpr UINT32 VideoWidth = 640;
constexpr UINT32 VideoHeight = 360;
constexpr UINT32 VideoFps = 30;

static void Check(HRESULT hr, char const* label) {
    if (FAILED(hr)) {
        std::cerr << label << " failed: 0x" << std::hex << hr << "\n";
        ExitProcess(10);
    }
}

static LONGLONG NowHns(LONGLONG qpcBase, LARGE_INTEGER freq) {
    LARGE_INTEGER now{};
    QueryPerformanceCounter(&now);
    return ((now.QuadPart - qpcBase) * 10000000LL) / freq.QuadPart;
}

static ComPtr<IMFSinkWriter> CreateWriter(wchar_t const* path, DWORD& videoStream, DWORD& audioStream, WAVEFORMATEX const* mix) {
    ComPtr<IMFSinkWriter> writer;
    Check(MFCreateSinkWriterFromURL(path, nullptr, nullptr, &writer), "MFCreateSinkWriterFromURL");

    ComPtr<IMFMediaType> videoOut;
    Check(MFCreateMediaType(&videoOut), "MFCreateMediaType videoOut");
    videoOut->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    videoOut->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_H264);
    videoOut->SetUINT32(MF_MT_AVG_BITRATE, 4000000);
    videoOut->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    MFSetAttributeSize(videoOut.Get(), MF_MT_FRAME_SIZE, VideoWidth, VideoHeight);
    MFSetAttributeRatio(videoOut.Get(), MF_MT_FRAME_RATE, VideoFps, 1);
    MFSetAttributeRatio(videoOut.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    Check(writer->AddStream(videoOut.Get(), &videoStream), "AddStream video");

    ComPtr<IMFMediaType> videoIn;
    Check(MFCreateMediaType(&videoIn), "MFCreateMediaType videoIn");
    videoIn->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    videoIn->SetGUID(MF_MT_SUBTYPE, MFVideoFormat_RGB32);
    videoIn->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    MFSetAttributeSize(videoIn.Get(), MF_MT_FRAME_SIZE, VideoWidth, VideoHeight);
    MFSetAttributeRatio(videoIn.Get(), MF_MT_FRAME_RATE, VideoFps, 1);
    MFSetAttributeRatio(videoIn.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    Check(writer->SetInputMediaType(videoStream, videoIn.Get(), nullptr), "SetInputMediaType video");

    ComPtr<IMFMediaType> audioOut;
    Check(MFCreateMediaType(&audioOut), "MFCreateMediaType audioOut");
    audioOut->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    audioOut->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
    audioOut->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, mix->nChannels);
    audioOut->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, mix->nSamplesPerSec);
    audioOut->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    audioOut->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 16000);
    Check(writer->AddStream(audioOut.Get(), &audioStream), "AddStream audio");

    ComPtr<IMFMediaType> audioIn;
    Check(MFCreateMediaType(&audioIn), "MFCreateMediaType audioIn");
    audioIn->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
    audioIn->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
    audioIn->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, mix->nChannels);
    audioIn->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, mix->nSamplesPerSec);
    audioIn->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
    audioIn->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, mix->nChannels * 2);
    audioIn->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, mix->nSamplesPerSec * mix->nChannels * 2);
    Check(writer->SetInputMediaType(audioStream, audioIn.Get(), nullptr), "SetInputMediaType audio");

    Check(writer->BeginWriting(), "BeginWriting");
    return writer;
}

static bool IsFloatMix(WAVEFORMATEX const* mix) {
    if (mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        auto extensible = reinterpret_cast<WAVEFORMATEXTENSIBLE const*>(mix);
        return extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    }
    return false;
}

static std::vector<BYTE> ConvertToPcm16(BYTE const* data, UINT32 frames, WAVEFORMATEX const* mix, DWORD flags) {
    std::vector<BYTE> pcm(static_cast<size_t>(frames) * mix->nChannels * 2);
    auto* out = reinterpret_cast<short*>(pcm.data());
    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) return pcm;

    if (IsFloatMix(mix)) {
        auto* in = reinterpret_cast<float const*>(data);
        for (size_t i = 0; i < static_cast<size_t>(frames) * mix->nChannels; ++i) {
            float v = in[i];
            if (v > 1.0f) v = 1.0f;
            if (v < -1.0f) v = -1.0f;
            out[i] = static_cast<short>(v * 32767.0f);
        }
        return pcm;
    }

    if (mix->wBitsPerSample == 16) {
        memcpy(pcm.data(), data, pcm.size());
        return pcm;
    }

    if (mix->wBitsPerSample == 32) {
        auto* in = reinterpret_cast<int const*>(data);
        for (size_t i = 0; i < static_cast<size_t>(frames) * mix->nChannels; ++i) {
            out[i] = static_cast<short>(in[i] >> 16);
        }
        return pcm;
    }

    return pcm;
}

int wmain(int argc, wchar_t** argv) {
    Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "CoInitializeEx");
    Check(MFStartup(MF_VERSION), "MFStartup");

    ComPtr<IMMDeviceEnumerator> enumerator;
    Check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)), "MMDeviceEnumerator");
    ComPtr<IMMDevice> device;
    Check(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device), "GetDefaultAudioEndpoint");
    ComPtr<IAudioClient> audioClient;
    Check(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(audioClient.GetAddressOf())), "Activate IAudioClient");

    WAVEFORMATEX* mix{};
    Check(audioClient->GetMixFormat(&mix), "GetMixFormat");

    REFERENCE_TIME bufferDuration = 10000000;
    Check(audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK,
        bufferDuration, 0, mix, nullptr), "IAudioClient::Initialize");
    HANDLE eventHandle = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    audioClient->SetEventHandle(eventHandle);
    ComPtr<IAudioCaptureClient> capture;
    Check(audioClient->GetService(IID_PPV_ARGS(&capture)), "IAudioCaptureClient");

    DWORD videoStream{}, audioStream{};
    wchar_t path[MAX_PATH]{};
    GetFullPathNameW(L"windows-spike-wasapi-mf-sync.mp4", MAX_PATH, path, nullptr);
    auto writer = CreateWriter(path, videoStream, audioStream, mix);
    std::mutex writerMutex;

    LARGE_INTEGER freq{}, start{};
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&start);
    std::atomic<bool> running{ true };
    std::atomic<int> audioSamples{ 0 };

    Check(audioClient->Start(), "IAudioClient::Start");
    std::thread audioThread([&] {
        DWORD taskIndex{};
        HANDLE avrt = AvSetMmThreadCharacteristicsW(L"Audio", &taskIndex);
        while (running.load()) {
            WaitForSingleObject(eventHandle, 200);
            UINT32 packetFrames{};
            while (SUCCEEDED(capture->GetNextPacketSize(&packetFrames)) && packetFrames > 0) {
                BYTE* data{};
                DWORD flags{};
                UINT64 devicePosition{}, qpcPosition{};
                if (FAILED(capture->GetBuffer(&data, &packetFrames, &flags, &devicePosition, &qpcPosition))) break;
                auto pcmBytes = ConvertToPcm16(data, packetFrames, mix, flags);
                DWORD bytes = static_cast<DWORD>(pcmBytes.size());
                ComPtr<IMFMediaBuffer> buffer;
                if (SUCCEEDED(MFCreateMemoryBuffer(bytes, &buffer))) {
                    BYTE* dest{};
                    buffer->Lock(&dest, nullptr, nullptr);
                    memcpy(dest, pcmBytes.data(), bytes);
                    buffer->Unlock();
                    buffer->SetCurrentLength(bytes);

                    ComPtr<IMFSample> sample;
                    MFCreateSample(&sample);
                    sample->AddBuffer(buffer.Get());
                    LONGLONG t = NowHns(start.QuadPart, freq);
                    sample->SetSampleTime(t);
                    sample->SetSampleDuration((packetFrames * 10000000LL) / mix->nSamplesPerSec);
                    {
                        std::lock_guard<std::mutex> lock(writerMutex);
                        writer->WriteSample(audioStream, sample.Get());
                    }
                    audioSamples += packetFrames;
                }
                capture->ReleaseBuffer(packetFrames);
            }
        }
        if (avrt) AvRevertMmThreadCharacteristics(avrt);
    });

    BITMAPINFO bmi{};
    bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bmi.bmiHeader.biWidth = VideoWidth;
    bmi.bmiHeader.biHeight = -static_cast<LONG>(VideoHeight);
    bmi.bmiHeader.biPlanes = 1;
    bmi.bmiHeader.biBitCount = 32;
    bmi.bmiHeader.biCompression = BI_RGB;
    std::vector<BYTE> pixels(VideoWidth * VideoHeight * 4);

    int seconds = argc > 1 ? _wtoi(argv[1]) : 60;
    if (seconds <= 0) seconds = 60;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
    int frameIndex = 0;
    while (std::chrono::steady_clock::now() < deadline) {
        for (UINT32 y = 0; y < VideoHeight; ++y) {
            for (UINT32 x = 0; x < VideoWidth; ++x) {
                auto* p = pixels.data() + (y * VideoWidth + x) * 4;
                p[0] = static_cast<BYTE>((x + frameIndex) % 256);
                p[1] = static_cast<BYTE>((y + frameIndex) % 256);
                p[2] = static_cast<BYTE>((x + y) % 256);
                p[3] = 255;
            }
        }

        ComPtr<IMFMediaBuffer> buffer;
        Check(MFCreateMemoryBuffer(static_cast<DWORD>(pixels.size()), &buffer), "MFCreateMemoryBuffer video");
        BYTE* dest{};
        buffer->Lock(&dest, nullptr, nullptr);
        memcpy(dest, pixels.data(), pixels.size());
        buffer->Unlock();
        buffer->SetCurrentLength(static_cast<DWORD>(pixels.size()));

        ComPtr<IMFSample> sample;
        MFCreateSample(&sample);
        sample->AddBuffer(buffer.Get());
        LONGLONG t = NowHns(start.QuadPart, freq);
        sample->SetSampleTime(t);
        sample->SetSampleDuration(333333);
        {
            std::lock_guard<std::mutex> lock(writerMutex);
            Check(writer->WriteSample(videoStream, sample.Get()), "WriteSample video");
        }
        ++frameIndex;
        std::this_thread::sleep_for(std::chrono::milliseconds(33));
    }

    running = false;
    SetEvent(eventHandle);
    audioThread.join();
    audioClient->Stop();
    {
        std::lock_guard<std::mutex> lock(writerMutex);
        Check(writer->Finalize(), "SinkWriter Finalize");
    }
    printf("PASS wrote %ls videoFrames=%d audioFrames=%d sharedClock=QueryPerformanceCounter\n",
        path, frameIndex, audioSamples.load());
    writer.Reset();
    MFShutdown();
    CoTaskMemFree(mix);
    CoUninitialize();
    return 0;
}
