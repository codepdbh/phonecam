#include "phonecam_media_source.h"

#include <iostream>
#include <ksmedia.h>

int main() {
    HRESULT hr = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (FAILED(hr)) return 1;
    hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) return 2;

    const GUID mediaSourceClsid = {0xe4d8a9f1, 0x3142, 0x4a2d,
        {0xa4, 0x83, 0xe1, 0x8f, 0x54, 0x68, 0x77, 0x91}};
    HMODULE module = LoadLibraryW(L"PhoneCamMediaSource_v7.dll");
    using GetClassObjectFn = HRESULT(STDAPICALLTYPE*)(REFCLSID, REFIID, void**);
    auto getClassObject = module ? reinterpret_cast<GetClassObjectFn>(
        GetProcAddress(module, "DllGetClassObject")) : nullptr;
    ComPtr<IClassFactory> factory;
    hr = getClassObject ? getClassObject(mediaSourceClsid, IID_PPV_ARGS(&factory))
                        : HRESULT_FROM_WIN32(GetLastError());
    ComPtr<IUnknown> object;
    if (SUCCEEDED(hr)) hr = factory->CreateInstance(nullptr, IID_PPV_ARGS(&object));
    ComPtr<IMFActivate> activate;
    if (SUCCEEDED(hr)) hr = object.As(&activate);
    if (SUCCEEDED(hr)) hr = activate->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    ComPtr<IMFMediaSourceEx> source;
    if (SUCCEEDED(hr)) hr = activate->ActivateObject(IID_PPV_ARGS(&source));
    ComPtr<IMFGetService> service;
    if (SUCCEEDED(hr)) hr = source.As(&service);
    ComPtr<IMFSampleAllocatorControl> allocatorControl;
    if (SUCCEEDED(hr)) hr = source.As(&allocatorControl);
    DWORD allocatorInputStream = UINT32_MAX;
    MFSampleAllocatorUsage allocatorUsage = MFSampleAllocatorUsage_DoesNotAllocate;
    if (SUCCEEDED(hr)) hr = allocatorControl->GetAllocatorUsage(
        0, &allocatorInputStream, &allocatorUsage);
    if (SUCCEEDED(hr) && (allocatorInputStream != 0 ||
        allocatorUsage != MFSampleAllocatorUsage_UsesProvidedAllocator)) hr = E_FAIL;
    if (FAILED(hr)) {
        std::cerr << "Required source interface failed: 0x" << std::hex << hr << "\n";
        return 3;
    }

    ComPtr<IMFAttributes> attributes;
    hr = source->GetSourceAttributes(&attributes);
    ComPtr<IMFAttributes> streamAttributes;
    if (SUCCEEDED(hr)) hr = source->GetStreamAttributes(0, &streamAttributes);
    GUID streamCategory = GUID_NULL;
    UINT32 streamId = UINT32_MAX;
    UINT32 shared = 0;
    UINT32 frameSourceTypes = 0;
    if (SUCCEEDED(hr)) hr = streamAttributes->GetGUID(
        MF_DEVICESTREAM_STREAM_CATEGORY, &streamCategory);
    if (SUCCEEDED(hr) && streamCategory != PINNAME_VIDEO_CAPTURE) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = streamAttributes->GetUINT32(
        MF_DEVICESTREAM_STREAM_ID, &streamId);
    if (SUCCEEDED(hr) && streamId != 0) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = streamAttributes->GetUINT32(
        MF_DEVICESTREAM_FRAMESERVER_SHARED, &shared);
    if (SUCCEEDED(hr) && !shared) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = streamAttributes->GetUINT32(
        MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, &frameSourceTypes);
    if (SUCCEEDED(hr) && !(frameSourceTypes & MFFrameSourceTypes_Color)) hr = E_FAIL;
    ComPtr<IMFPresentationDescriptor> descriptor;
    if (SUCCEEDED(hr)) hr = source->CreatePresentationDescriptor(&descriptor);
    DWORD count = 0;
    if (SUCCEEDED(hr)) hr = descriptor->GetStreamDescriptorCount(&count);
    if (SUCCEEDED(hr) && count != 1) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = source->Start(descriptor.Get(), nullptr, nullptr);

    ComPtr<IMFMediaEvent> event;
    if (SUCCEEDED(hr)) hr = source->GetEvent(MF_EVENT_FLAG_NO_WAIT, &event);
    MediaEventType eventType = MEUnknown;
    if (SUCCEEDED(hr)) hr = event->GetType(&eventType);
    if (SUCCEEDED(hr) && eventType != MENewStream) hr = E_FAIL;
    PROPVARIANT value; PropVariantInit(&value);
    if (SUCCEEDED(hr)) hr = event->GetValue(&value);
    ComPtr<IMFMediaStream2> stream;
    if (SUCCEEDED(hr) && value.vt == VT_UNKNOWN) hr = value.punkVal->QueryInterface(IID_PPV_ARGS(&stream));
    else if (SUCCEEDED(hr)) hr = E_NOINTERFACE;
    PropVariantClear(&value);

    ComPtr<IMFMediaEvent> streamEvent;
    if (SUCCEEDED(hr)) hr = stream->GetEvent(0, &streamEvent);
    if (SUCCEEDED(hr)) hr = streamEvent->GetType(&eventType);
    if (SUCCEEDED(hr) && eventType != MEStreamStarted) hr = E_FAIL;
    if (SUCCEEDED(hr)) hr = stream->RequestSample(nullptr);
    streamEvent.Reset();
    if (SUCCEEDED(hr)) hr = stream->GetEvent(0, &streamEvent);
    if (SUCCEEDED(hr)) hr = streamEvent->GetType(&eventType);
    if (SUCCEEDED(hr) && eventType != MEMediaSample) hr = E_FAIL;
    PropVariantInit(&value);
    if (SUCCEEDED(hr)) hr = streamEvent->GetValue(&value);
    ComPtr<IMFSample> producedSample;
    if (SUCCEEDED(hr) && value.vt == VT_UNKNOWN)
        hr = value.punkVal->QueryInterface(IID_PPV_ARGS(&producedSample));
    else if (SUCCEEDED(hr))
        hr = E_NOINTERFACE;
    PropVariantClear(&value);
    LONGLONG sampleTime = 0;
    if (SUCCEEDED(hr)) hr = producedSample->GetSampleTime(&sampleTime);
    if (SUCCEEDED(hr) && sampleTime <= 0) hr = E_FAIL;

    if (source) source->Shutdown();
    // Keep the in-proc server loaded until process exit; COM references are
    // released by their RAII wrappers after this scope.
    // Process exit follows immediately; leaving MF/COM initialized ensures all
    // smart-pointer releases still execute against a live runtime.
    if (FAILED(hr)) {
        std::cerr << "Media source contract failed: 0x" << std::hex << hr << "\n";
        return 4;
    }
    std::cout << "Media Foundation source contract: PASS\n";
    return 0;
}
