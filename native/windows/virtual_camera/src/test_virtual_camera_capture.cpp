#include "phonecam_virtual_cam.h"

#include <iostream>

int wmain() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    const bool uninitializeCom = SUCCEEDED(hr);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE) return 1;
    hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) return 2;

    ComPtr<IMFAttributes> enumerationAttributes;
    hr = MFCreateAttributes(&enumerationAttributes, 1);
    if (SUCCEEDED(hr)) hr = enumerationAttributes->SetGUID(
        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE,
        MF_DEVSOURCE_ATTRIBUTE_SOURCE_TYPE_VIDCAP_GUID);

    IMFActivate** devices = nullptr;
    UINT32 deviceCount = 0;
    if (SUCCEEDED(hr)) hr = MFEnumDeviceSources(
        enumerationAttributes.Get(), &devices, &deviceCount);

    ComPtr<IMFActivate> phoneCam;
    for (UINT32 i = 0; SUCCEEDED(hr) && i < deviceCount; ++i) {
        WCHAR* name = nullptr;
        UINT32 nameLength = 0;
        if (SUCCEEDED(devices[i]->GetAllocatedString(
                MF_DEVSOURCE_ATTRIBUTE_FRIENDLY_NAME, &name, &nameLength))) {
            if (name && wcsstr(name, L"PhoneCam Virtual Camera")) phoneCam = devices[i];
            CoTaskMemFree(name);
        }
        devices[i]->Release();
    }
    CoTaskMemFree(devices);
    if (FAILED(hr) || !phoneCam) {
        std::cerr << "PhoneCam capture device was not enumerated.\n";
        MFShutdown();
        if (uninitializeCom) CoUninitialize();
        return 3;
    }
    std::cerr << "[capture] device enumerated\n";

    ComPtr<IMFMediaSource> source;
    hr = phoneCam->ActivateObject(IID_PPV_ARGS(&source));
    std::cerr << "[capture] ActivateObject: 0x" << std::hex
              << static_cast<unsigned long>(hr) << "\n";
    ComPtr<IMFSourceReader> reader;
    if (SUCCEEDED(hr)) hr = MFCreateSourceReaderFromMediaSource(
        source.Get(), nullptr, &reader);
    std::cerr << "[capture] CreateSourceReader: 0x" << std::hex
              << static_cast<unsigned long>(hr) << "\n";
    if (SUCCEEDED(hr)) hr = reader->SetStreamSelection(MF_SOURCE_READER_ALL_STREAMS, FALSE);
    if (SUCCEEDED(hr)) hr = reader->SetStreamSelection(MF_SOURCE_READER_FIRST_VIDEO_STREAM, TRUE);
    ComPtr<IMFMediaType> captureType;
    if (SUCCEEDED(hr)) hr = reader->GetNativeMediaType(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0, &captureType);
    if (SUCCEEDED(hr)) hr = reader->SetCurrentMediaType(
        MF_SOURCE_READER_FIRST_VIDEO_STREAM, nullptr, captureType.Get());
    std::cerr << "[capture] ConfigureStream: 0x" << std::hex
              << static_cast<unsigned long>(hr) << "\n";

    ComPtr<IMFSample> sample;
    DWORD actualStream = 0;
    DWORD flags = 0;
    LONGLONG timestamp = 0;
    for (int attempt = 0; SUCCEEDED(hr) && attempt < 10 && !sample; ++attempt) {
        std::cerr << "[capture] waiting for sample " << std::dec << attempt + 1 << "\n";
        hr = reader->ReadSample(MF_SOURCE_READER_FIRST_VIDEO_STREAM, 0,
                                &actualStream, &flags, &timestamp, &sample);
        std::cerr << "[capture] result=0x" << std::hex
                  << static_cast<unsigned long>(hr) << " flags=0x" << flags
                  << " sample=" << (sample ? "yes" : "no") << "\n";
        if (flags & MF_SOURCE_READERF_ERROR) hr = E_FAIL;
    }

    DWORD bytes = 0;
    BYTE firstLuma = 0;
    if (SUCCEEDED(hr) && sample) {
        ComPtr<IMFMediaBuffer> buffer;
        hr = sample->ConvertToContiguousBuffer(&buffer);
        if (SUCCEEDED(hr)) hr = buffer->GetCurrentLength(&bytes);
        if (SUCCEEDED(hr) && bytes == 0) hr = E_FAIL;
        BYTE* data = nullptr;
        DWORD capacity = 0;
        DWORD current = 0;
        if (SUCCEEDED(hr)) hr = buffer->Lock(&data, &capacity, &current);
        if (SUCCEEDED(hr) && current > 0) firstLuma = data[0];
        if (data) buffer->Unlock();
    } else if (SUCCEEDED(hr)) {
        hr = E_FAIL;
    }

    sample.Reset();
    captureType.Reset();
    reader.Reset();
    if (source) source->Shutdown();
    source.Reset();
    phoneCam->ShutdownObject();
    phoneCam.Reset();
    enumerationAttributes.Reset();
    MFShutdown();
    if (uninitializeCom) CoUninitialize();

    if (FAILED(hr)) {
        std::cerr << "Virtual camera sample capture failed: 0x"
                  << std::hex << static_cast<unsigned long>(hr) << "\n";
        return 4;
    }
    std::cout << "Virtual camera sample capture: PASS (" << bytes
              << " bytes, timestamp " << timestamp
              << ", first luma " << static_cast<unsigned>(firstLuma) << ")\n";
    return 0;
}
