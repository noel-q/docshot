#include <windows.h>
#include <mmsystem.h>

#include <cmath>
#include <iostream>
#include <vector>

static std::vector<BYTE> MakeWav(double frequency, int seconds, int sampleRate = 48000) {
    int samples = sampleRate * seconds;
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
        out[i] = static_cast<short>(std::sin(2.0 * 3.141592653589793 * frequency * i / sampleRate) * 12000.0);
    }
    return wav;
}

int wmain(int argc, wchar_t** argv) {
    double frequency = argc > 1 ? _wtof(argv[1]) : 440.0;
    int seconds = argc > 2 ? _wtoi(argv[2]) : 12;
    auto wav = MakeWav(frequency, seconds);
    BOOL ok = PlaySoundW(reinterpret_cast<LPCWSTR>(wav.data()), nullptr, SND_MEMORY | SND_SYNC);
    std::wcout << (ok ? L"PASS" : L"FAIL") << L" external_tone_player frequency=" << frequency
               << L" seconds=" << seconds << L"\n";
    return ok ? 0 : 1;
}
