#include <windows.h>
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <avrt.h>
#include <mmdeviceapi.h>
#include <mmsystem.h>
#include <roapi.h>
#include <wrl/client.h>
#include <wrl/implements.h>

#include <atomic>
#include <cmath>
#include <iostream>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;
using Microsoft::WRL::FtmBase;
using Microsoft::WRL::Make;
using Microsoft::WRL::RuntimeClass;
using Microsoft::WRL::RuntimeClassFlags;
using Microsoft::WRL::ClassicCom;

constexpr int ExternalHz = 440;
constexpr int OwnAlertHz = 1200;
constexpr int CaptureSeconds = 8;

static void Check(HRESULT hr, char const* label) {
    if (FAILED(hr)) {
        std::cerr << "FAIL " << label << " hr=0x" << std::hex << hr << "\n";
        ExitProcess(20);
    }
}

class ActivationHandler final
    : public RuntimeClass<RuntimeClassFlags<ClassicCom>, FtmBase, IActivateAudioInterfaceCompletionHandler> {
public:
    ActivationHandler() : event_(CreateEventW(nullptr, FALSE, FALSE, nullptr)) {}
    ~ActivationHandler() override { CloseHandle(event_); }

    HRESULT STDMETHODCALLTYPE ActivateCompleted(IActivateAudioInterfaceAsyncOperation* operation) override {
        HRESULT activateResult{};
        ComPtr<IUnknown> unknown;
        result_ = operation->GetActivateResult(&activateResult, &unknown);
        if (SUCCEEDED(result_)) result_ = activateResult;
        if (unknown) result_ = unknown.As(&audioClient_);
        SetEvent(event_);
        return S_OK;
    }

    ComPtr<IAudioClient> WaitForAudioClient() {
        DWORD wait = WaitForSingleObject(event_, 10000);
        if (wait != WAIT_OBJECT_0) Check(HRESULT_FROM_WIN32(ERROR_TIMEOUT), "ActivateAudioInterfaceAsync timeout");
        Check(result_, "ActivateAudioInterfaceAsync result");
        return audioClient_;
    }

private:
    HANDLE event_{};
    HRESULT result_{ E_PENDING };
    ComPtr<IAudioClient> audioClient_;
};

static ComPtr<IAudioClient> ActivateProcessExcludingLoopback(DWORD processId) {
    AUDIOCLIENT_ACTIVATION_PARAMS params{};
    params.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
    params.ProcessLoopbackParams.TargetProcessId = processId;
    params.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE;

    PROPVARIANT prop{};
    prop.vt = VT_BLOB;
    prop.blob.cbSize = sizeof(params);
    prop.blob.pBlobData = reinterpret_cast<BYTE*>(&params);

    auto handler = Make<ActivationHandler>();
    ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
    HRESULT hr = ActivateAudioInterfaceAsync(
        VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
        __uuidof(IAudioClient),
        &prop,
        handler.Get(),
        &operation);
    if (FAILED(hr)) {
        Check(hr, "ActivateAudioInterfaceAsync");
    }
    auto client = handler->WaitForAudioClient();
    return client;
}

static ComPtr<IAudioClient> ActivateClassicEndpointLoopback() {
    ComPtr<IMMDeviceEnumerator> enumerator;
    Check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)), "MMDeviceEnumerator");
    ComPtr<IMMDevice> device;
    Check(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device), "GetDefaultAudioEndpoint");
    ComPtr<IAudioClient> audioClient;
    Check(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, reinterpret_cast<void**>(audioClient.GetAddressOf())), "Activate classic IAudioClient");
    return audioClient;
}

static bool IsFloatMix(WAVEFORMATEX const* mix) {
    if (mix->wFormatTag == WAVE_FORMAT_IEEE_FLOAT) return true;
    if (mix->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
        auto extensible = reinterpret_cast<WAVEFORMATEXTENSIBLE const*>(mix);
        return extensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
    }
    return false;
}

static void AppendPcm16(std::vector<short>& samples, BYTE const* data, UINT32 frames, WAVEFORMATEX const* mix, DWORD flags) {
    size_t count = static_cast<size_t>(frames) * mix->nChannels;
    if (flags & AUDCLNT_BUFFERFLAGS_SILENT) {
        samples.insert(samples.end(), count, 0);
        return;
    }

    if (IsFloatMix(mix)) {
        auto* in = reinterpret_cast<float const*>(data);
        for (size_t i = 0; i < count; ++i) {
            float v = in[i];
            if (v > 1.0f) v = 1.0f;
            if (v < -1.0f) v = -1.0f;
            samples.push_back(static_cast<short>(v * 32767.0f));
        }
        return;
    }

    if (mix->wBitsPerSample == 16) {
        auto* in = reinterpret_cast<short const*>(data);
        samples.insert(samples.end(), in, in + count);
        return;
    }

    samples.insert(samples.end(), count, 0);
}

static std::vector<BYTE> MakeAlertWav(int sampleRate = 48000) {
    int samples = sampleRate / 2;
    int dataBytes = samples * 2;
    std::vector<BYTE> wav(44 + dataBytes);
    memcpy(wav.data(), "RIFF", 4);
    *reinterpret_cast<DWORD*>(wav.data() + 4) = 36 + dataBytes;
    memcpy(wav.data() + 8, "WAVEfmt ", 8);
    *reinterpret_cast<DWORD*>(wav.data() + 16) = 16;
    *reinterpret_cast<WORD*>(wav.data() + 20) = 1;
    *reinterpret_cast<WORD*>(wav.data() + 22) = 1;
    *reinterpret_cast<DWORD*>(wav.data() + 24) = sampleRate;
    *reinterpret_cast<DWORD*>(wav.data() + 28) = sampleRate * 2;
    *reinterpret_cast<WORD*>(wav.data() + 32) = 2;
    *reinterpret_cast<WORD*>(wav.data() + 34) = 16;
    memcpy(wav.data() + 36, "data", 4);
    *reinterpret_cast<DWORD*>(wav.data() + 40) = dataBytes;
    auto* out = reinterpret_cast<short*>(wav.data() + 44);
    for (int i = 0; i < samples; ++i) {
        out[i] = static_cast<short>(std::sin(2.0 * 3.141592653589793 * OwnAlertHz * i / sampleRate) * 16000.0);
    }
    return wav;
}

static double Goertzel(std::vector<short> const& interleaved, int channels, int sampleRate, int frequency, double startSeconds, double seconds) {
    int startFrame = static_cast<int>(startSeconds * sampleRate);
    int frames = static_cast<int>(seconds * sampleRate);
    if (startFrame < 0) startFrame = 0;
    int availableFrames = static_cast<int>(interleaved.size() / channels);
    if (startFrame + frames > availableFrames) frames = availableFrames - startFrame;
    if (frames <= 0) return 0.0;

    double omega = 2.0 * 3.141592653589793 * frequency / sampleRate;
    double coeff = 2.0 * std::cos(omega);
    double q0 = 0.0, q1 = 0.0, q2 = 0.0;
    for (int i = 0; i < frames; ++i) {
        double mono = 0.0;
        for (int c = 0; c < channels; ++c) mono += interleaved[(startFrame + i) * channels + c];
        mono /= channels;
        q0 = coeff * q1 - q2 + mono;
        q2 = q1;
        q1 = q0;
    }
    return (q1 * q1 + q2 * q2 - q1 * q2 * coeff) / frames;
}

int wmain(int argc, wchar_t** argv) {
    Check(CoInitializeEx(nullptr, COINIT_MULTITHREADED), "CoInitializeEx");
    HRESULT ro = RoInitialize(RO_INIT_MULTITHREADED);
    if (FAILED(ro) && ro != RPC_E_CHANGED_MODE) Check(ro, "RoInitialize");

    DWORD build = 0;
    HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
    if (ntdll) {
        using RtlGetVersionFn = LONG(WINAPI*)(PRTL_OSVERSIONINFOW);
        auto rtlGetVersion = reinterpret_cast<RtlGetVersionFn>(GetProcAddress(ntdll, "RtlGetVersion"));
        if (rtlGetVersion) {
            RTL_OSVERSIONINFOW version{};
            version.dwOSVersionInfoSize = sizeof(version);
            if (rtlGetVersion(&version) == 0) build = version.dwBuildNumber;
        }
    }

    bool classicControl = argc > 1 && wcscmp(argv[1], L"classic") == 0;
    ComPtr<IAudioClient> audioClient = classicControl
        ? ActivateClassicEndpointLoopback()
        : ActivateProcessExcludingLoopback(GetCurrentProcessId());
    WAVEFORMATEX captureFormat{};
    captureFormat.wFormatTag = WAVE_FORMAT_PCM;
    captureFormat.nChannels = 2;
    captureFormat.nSamplesPerSec = 44100;
    captureFormat.wBitsPerSample = 16;
    captureFormat.nBlockAlign = captureFormat.nChannels * captureFormat.wBitsPerSample / 8;
    captureFormat.nAvgBytesPerSec = captureFormat.nSamplesPerSec * captureFormat.nBlockAlign;

    Check(audioClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
        0,
        0,
        &captureFormat,
        nullptr), "IAudioClient::Initialize");

    HANDLE eventHandle = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    Check(audioClient->SetEventHandle(eventHandle), "SetEventHandle");
    ComPtr<IAudioCaptureClient> capture;
    Check(audioClient->GetService(IID_PPV_ARGS(&capture)), "IAudioCaptureClient");

    std::vector<short> captured;
    captured.reserve(static_cast<size_t>(captureFormat.nSamplesPerSec) * CaptureSeconds * captureFormat.nChannels);

    auto alert = MakeAlertWav();
    std::thread alertThread([&] {
        std::this_thread::sleep_for(std::chrono::seconds(3));
        PlaySoundW(reinterpret_cast<LPCWSTR>(alert.data()), nullptr, SND_MEMORY | SND_SYNC);
    });

    Check(audioClient->Start(), "IAudioClient::Start");
    auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(CaptureSeconds);
    DWORD taskIndex{};
    HANDLE avrt = AvSetMmThreadCharacteristicsW(L"Audio", &taskIndex);
    while (std::chrono::steady_clock::now() < deadline) {
        WaitForSingleObject(eventHandle, 200);
        UINT32 packetFrames{};
        while (SUCCEEDED(capture->GetNextPacketSize(&packetFrames)) && packetFrames > 0) {
            BYTE* data{};
            DWORD flags{};
            UINT64 devicePosition{}, qpcPosition{};
            if (FAILED(capture->GetBuffer(&data, &packetFrames, &flags, &devicePosition, &qpcPosition))) break;
            AppendPcm16(captured, data, packetFrames, &captureFormat, flags);
            capture->ReleaseBuffer(packetFrames);
        }
    }
    if (avrt) AvRevertMmThreadCharacteristics(avrt);
    audioClient->Stop();
    alertThread.join();

    double externalPower = Goertzel(captured, captureFormat.nChannels, captureFormat.nSamplesPerSec, ExternalHz, 1.0, 6.0);
    double ownAlertPower = Goertzel(captured, captureFormat.nChannels, captureFormat.nSamplesPerSec, OwnAlertHz, 2.8, 1.0);
    double floorAtAlert = Goertzel(captured, captureFormat.nChannels, captureFormat.nSamplesPerSec, OwnAlertHz + 170, 2.8, 1.0);
    bool externalPresent = externalPower > 1000000.0;
    bool ownAlertAbsent = ownAlertPower < externalPower * 0.02 && ownAlertPower < (floorAtAlert + 100000.0) * 8.0;
    bool pass = classicControl ? (externalPresent && !ownAlertAbsent) : (externalPresent && ownAlertAbsent);

    std::wcout << (pass ? L"PASS " : L"FAIL ")
               << L"mode=" << (classicControl ? L"classic-control" : L"process-exclude") << L" "
               << L"processLoopbackExclude=" << (classicControl ? L"false" : L"true") << L" "
               << L"osBuild=" << build << L" "
               << L"framesCaptured=" << (captured.size() / captureFormat.nChannels) << L" "
               << L"sampleRate=" << captureFormat.nSamplesPerSec << L" "
               << L"external440Power=" << externalPower << L" "
               << L"own1200Power=" << ownAlertPower << L" "
               << L"nearbyFloorPower=" << floorAtAlert << L"\n";

    CloseHandle(eventHandle);
    RoUninitialize();
    CoUninitialize();
    return pass ? 0 : 1;
}
