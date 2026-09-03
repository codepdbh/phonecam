#include "phonecam_media_source.h"

#include <ksmedia.h>

PhoneCamMediaSource* PhoneCamMediaSource::s_pGlobalInstance = nullptr;

namespace {
const GUID kIidKsControl = {0x28f54685, 0x06fd, 0x11d2,
                            {0xb2, 0x7a, 0x00, 0xa0, 0xc9, 0x22, 0x31, 0x96}};
HRESULT CreateMediaType(UINT32 width, UINT32 height, UINT32 fps, const GUID& subtype,
                        IMFMediaType** result) {
    if (!result) return E_POINTER;
    ComPtr<IMFMediaType> type; HRESULT hr = MFCreateMediaType(&type); if (FAILED(hr)) return hr;
    if (FAILED(hr = type->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video)) ||
        FAILED(hr = type->SetGUID(MF_MT_SUBTYPE, subtype)) ||
        FAILED(hr = type->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive)) ||
        FAILED(hr = type->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE)) ||
        FAILED(hr = MFSetAttributeSize(type.Get(), MF_MT_FRAME_SIZE, width, height)) ||
        FAILED(hr = MFSetAttributeRatio(type.Get(), MF_MT_FRAME_RATE, fps, 1)) ||
        FAILED(hr = MFSetAttributeRatio(type.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1))) return hr;
    const UINT32 stride = subtype == MFVideoFormat_RGB32 ? width * 4 :
                          subtype == MFVideoFormat_YUY2 ? width * 2 : width;
    type->SetUINT32(MF_MT_DEFAULT_STRIDE, stride);
    type->SetUINT32(MF_MT_SAMPLE_SIZE,
                    subtype == MFVideoFormat_NV12 ? width * height * 3 / 2 : stride * height);
    type->SetUINT32(MF_MT_AVG_BITRATE,
                    (subtype == MFVideoFormat_NV12 ? width * height * 3 / 2 : stride * height) * 8 * fps);
    *result = type.Detach(); return S_OK;
}

bool ConfigFromType(IMFMediaType* type, PhoneCamVideoConfig& config) {
    if (!type) return false;
    UINT32 width = 0, height = 0, numerator = 30, denominator = 1; GUID subtype = GUID_NULL;
    if (FAILED(MFGetAttributeSize(type, MF_MT_FRAME_SIZE, &width, &height)) ||
        FAILED(type->GetGUID(MF_MT_SUBTYPE, &subtype))) return false;
    MFGetAttributeRatio(type, MF_MT_FRAME_RATE, &numerator, &denominator);
    config.width = width; config.height = height;
    config.fps = denominator ? numerator / denominator : numerator;
    if (subtype == MFVideoFormat_NV12) config.format = PhoneCamPixelFormat::NV12;
    else if (subtype == MFVideoFormat_RGB32) config.format = PhoneCamPixelFormat::RGB32;
    else if (subtype == MFVideoFormat_YUY2) config.format = PhoneCamPixelFormat::YUY2;
    else return false;
    return true;
}
}

PhoneCamMediaSource::PhoneCamMediaSource() : m_refCount(1), m_isShutdown(false) {
    PhoneCamComObjectCreated();
    m_config = {1920, 1080, 30, PhoneCamPixelFormat::NV12};
    MFCreateEventQueue(&m_spEventQueue);
    m_diagnostics.Initialize(false);
    MFCreateAttributes(&m_spAttributes, 8);
    MFCreateAttributes(&m_spStreamAttributes, 8);
    if (SUCCEEDED(CreateDescriptors()))
        m_spStream = new PhoneCamMediaStream(this, m_spStreamDesc.Get());
    s_pGlobalInstance = this;
}
PhoneCamMediaSource::~PhoneCamMediaSource() {
    Shutdown(); if (s_pGlobalInstance == this) s_pGlobalInstance = nullptr;
    PhoneCamComObjectDestroyed();
}
PhoneCamMediaSource* PhoneCamMediaSource::GetGlobalInstance() { return s_pGlobalInstance; }

STDMETHODIMP PhoneCamMediaSource::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator ||
        riid == IID_IMFMediaSource || riid == IID_IMFMediaSourceEx) {
        *ppv = static_cast<IMFMediaSourceEx*>(this); AddRef(); return S_OK;
    }
    if (riid == IID_IMFGetService) { *ppv = static_cast<IMFGetService*>(this); AddRef(); return S_OK; }
    if (riid == IID_IMFSampleAllocatorControl) {
        *ppv = static_cast<IMFSampleAllocatorControl*>(this); AddRef(); return S_OK;
    }
    if (riid == kIidKsControl) { *ppv = static_cast<IKsControl*>(this); AddRef(); return S_OK; }
    *ppv = nullptr; return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) PhoneCamMediaSource::AddRef() { return ++m_refCount; }
STDMETHODIMP_(ULONG) PhoneCamMediaSource::Release() {
    const ULONG count = --m_refCount; if (!count) delete this; return count;
}
STDMETHODIMP PhoneCamMediaSource::GetService(REFGUID, REFIID, void** ppv) {
    if (!ppv) return E_POINTER; *ppv = nullptr; return MF_E_UNSUPPORTED_SERVICE;
}

STDMETHODIMP PhoneCamMediaSource::GetSourceAttributes(IMFAttributes** attributes) {
    m_diagnostics.MarkSourceGetAttributes();
    if (!attributes) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    *attributes = m_spAttributes.Get(); if (*attributes) (*attributes)->AddRef();
    return *attributes ? S_OK : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::GetStreamAttributes(DWORD streamIdentifier, IMFAttributes** attributes) {
    m_diagnostics.MarkStreamGetAttributes();
    if (!attributes) return E_POINTER; *attributes = nullptr;
    if (streamIdentifier != 0) return MF_E_INVALIDSTREAMNUMBER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    *attributes = m_spStreamAttributes.Get();
    if (*attributes) (*attributes)->AddRef();
    return *attributes ? S_OK : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::SetD3DManager(IUnknown* manager) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    m_spD3DManager = manager;
    // Samples are explicitly delivered in system memory. Returning E_NOTIMPL
    // tells Frame Server not to expect DXGI surfaces from this source.
    return E_NOTIMPL;
}
STDMETHODIMP PhoneCamMediaSource::SetDefaultAllocator(DWORD outputStreamId,
                                                       IUnknown* allocator) {
    m_diagnostics.MarkAllocatorSet();
    if (!allocator) return E_POINTER;
    if (outputStreamId != 0) return MF_E_INVALIDSTREAMNUMBER;
    ComPtr<IMFVideoSampleAllocator> videoAllocator;
    HRESULT hr = allocator->QueryInterface(IID_PPV_ARGS(&videoAllocator));
    if (FAILED(hr)) return hr;
    ComPtr<PhoneCamMediaStream> stream;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        stream = m_spStream;
    }
    return stream ? stream->SetSampleAllocator(videoAllocator.Get()) : E_UNEXPECTED;
}
STDMETHODIMP PhoneCamMediaSource::GetAllocatorUsage(DWORD outputStreamId,
                                                     DWORD* inputStreamId,
                                                     MFSampleAllocatorUsage* usage) {
    m_diagnostics.MarkAllocatorUsageQuery();
    if (!inputStreamId || !usage) return E_POINTER;
    if (outputStreamId != 0) return MF_E_INVALIDSTREAMNUMBER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    *inputStreamId = outputStreamId;
    *usage = MFSampleAllocatorUsage_UsesProvidedAllocator;
    return S_OK;
}
STDMETHODIMP PhoneCamMediaSource::KsProperty(PKSPROPERTY, ULONG, PVOID, ULONG, ULONG* returned) {
    if (returned) *returned = 0; return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
}
STDMETHODIMP PhoneCamMediaSource::KsMethod(PKSMETHOD, ULONG, PVOID, ULONG, ULONG* returned) {
    if (returned) *returned = 0; return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
}
STDMETHODIMP PhoneCamMediaSource::KsEvent(PKSEVENT, ULONG, PVOID, ULONG, ULONG* returned) {
    if (returned) *returned = 0; return HRESULT_FROM_WIN32(ERROR_SET_NOT_FOUND);
}
STDMETHODIMP PhoneCamMediaSource::BeginGetEvent(IMFAsyncCallback* callback, IUnknown* state) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->BeginGetEvent(callback, state) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::EndGetEvent(IMFAsyncResult* result, IMFMediaEvent** event) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->EndGetEvent(result, event) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::GetEvent(DWORD flags, IMFMediaEvent** event) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->GetEvent(flags, event) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::QueueEvent(MediaEventType type, REFGUID extended,
                                             HRESULT status, const PROPVARIANT* value) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->QueueEventParamVar(type, extended, status, value) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaSource::GetCharacteristics(DWORD* characteristics) {
    if (!characteristics) return E_POINTER; *characteristics = MFMEDIASOURCE_IS_LIVE; return S_OK;
}
STDMETHODIMP PhoneCamMediaSource::CreatePresentationDescriptor(IMFPresentationDescriptor** descriptor) {
    m_diagnostics.MarkPresentationDescriptor();
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!descriptor) return E_POINTER;
    return m_spPresentationDesc ? m_spPresentationDesc->Clone(descriptor) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaSource::Start(IMFPresentationDescriptor* descriptor, const GUID* timeFormat,
                                        const PROPVARIANT* position) {
    m_diagnostics.MarkSourceStart();
    if (!descriptor) return E_POINTER;
    if (timeFormat && *timeFormat != GUID_NULL) return MF_E_UNSUPPORTED_TIME_FORMAT;
    BOOL selected = FALSE; ComPtr<IMFStreamDescriptor> selectedDescriptor;
    HRESULT hr = descriptor->GetStreamDescriptorByIndex(0, &selected, &selectedDescriptor);
    if (FAILED(hr) || !selected) return FAILED(hr) ? hr : MF_E_INVALIDREQUEST;
    ComPtr<IMFMediaTypeHandler> handler; ComPtr<IMFMediaType> type;
    if (FAILED(hr = selectedDescriptor->GetMediaTypeHandler(&handler)) ||
        FAILED(hr = handler->GetCurrentMediaType(&type))) return hr;
    PhoneCamVideoConfig config;
    if (!ConfigFromType(type.Get(), config)) return MF_E_INVALIDMEDIATYPE;

    ComPtr<PhoneCamMediaStream> stream;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        m_config = config;
        stream = m_spStream;
    }
    if (!stream) return E_UNEXPECTED;
    if (FAILED(hr = stream->SetMediaType(type.Get()))) return hr;
    if (!m_streamAnnounced) {
        PROPVARIANT streamValue; PropVariantInit(&streamValue); streamValue.vt = VT_UNKNOWN;
        streamValue.punkVal = stream.Get(); streamValue.punkVal->AddRef();
        hr = QueueEvent(MENewStream, GUID_NULL, S_OK, &streamValue); PropVariantClear(&streamValue);
        if (FAILED(hr)) return hr; m_streamAnnounced = true;
    } else {
        PROPVARIANT streamValue; PropVariantInit(&streamValue); streamValue.vt = VT_UNKNOWN;
        streamValue.punkVal = stream.Get(); streamValue.punkVal->AddRef();
        QueueEvent(MEUpdatedStream, GUID_NULL, S_OK, &streamValue); PropVariantClear(&streamValue);
    }
    PROPVARIANT startTime;
    PropVariantInit(&startTime);
    startTime.vt = VT_I8;
    startTime.hVal.QuadPart = MFGetSystemTime();
    if (FAILED(hr = stream->Start(&startTime))) {
        PropVariantClear(&startTime);
        return hr;
    }
    hr = QueueEvent(MESourceStarted, GUID_NULL, S_OK, &startTime);
    PropVariantClear(&startTime);
    return hr;
}
STDMETHODIMP PhoneCamMediaSource::Stop() {
    ComPtr<PhoneCamMediaStream> stream;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; stream = m_spStream; }
    HRESULT hr = stream ? stream->Stop() : S_OK; if (FAILED(hr)) return hr;
    return QueueEvent(MESourceStopped, GUID_NULL, S_OK, nullptr);
}
STDMETHODIMP PhoneCamMediaSource::Pause() {
    std::lock_guard<std::mutex> lock(m_mutex);
    return m_isShutdown ? MF_E_SHUTDOWN : MF_E_INVALID_STATE_TRANSITION;
}
STDMETHODIMP PhoneCamMediaSource::Shutdown() {
    ComPtr<PhoneCamMediaStream> stream; ComPtr<IMFMediaEventQueue> queue;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return S_OK;
        m_isShutdown = true; stream = m_spStream; m_spStream.Reset(); queue = m_spEventQueue;
    }
    if (stream) stream->Shutdown(); if (queue) queue->Shutdown(); return S_OK;
}
void PhoneCamMediaSource::EnableTestPattern(bool enable) {
    ComPtr<PhoneCamMediaStream> stream;
    { std::lock_guard<std::mutex> lock(m_mutex); stream = m_spStream; }
    if (stream) stream->EnableTestPattern(enable);
}
void PhoneCamMediaSource::SetVideoConfig(const PhoneCamVideoConfig& config) {
    ComPtr<PhoneCamMediaStream> stream;
    { std::lock_guard<std::mutex> lock(m_mutex); m_config = config; stream = m_spStream; }
    if (stream) stream->SetVideoConfig(config);
}

HRESULT PhoneCamMediaSource::CreateDescriptors() {
    if (!m_spAttributes || !m_spStreamAttributes) return E_OUTOFMEMORY;

    // Frame Server queries these attributes through IMFMediaSourceEx before
    // it creates the stream. Missing metadata causes Start() to fail with
    // MF_E_ATTRIBUTENOTFOUND despite successful direct COM activation.
    HRESULT hr = m_spStreamAttributes->SetGUID(
        MF_DEVICESTREAM_STREAM_CATEGORY, PINNAME_VIDEO_CAPTURE);
    if (SUCCEEDED(hr)) hr = m_spStreamAttributes->SetUINT32(MF_DEVICESTREAM_STREAM_ID, 0);
    if (SUCCEEDED(hr)) hr = m_spStreamAttributes->SetUINT32(MF_DEVICESTREAM_FRAMESERVER_SHARED, 1);
    if (SUCCEEDED(hr)) hr = m_spStreamAttributes->SetUINT32(
        MF_DEVICESTREAM_ATTRIBUTE_FRAMESOURCE_TYPES, MFFrameSourceTypes_Color);
    if (FAILED(hr)) return hr;

    // The Legacy profile keeps profile-unaware capture clients, including
    // browser stacks, on a supported 30 fps color stream.
    ComPtr<IMFSensorProfileCollection> profiles;
    ComPtr<IMFSensorProfile> legacyProfile;
    hr = MFCreateSensorProfileCollection(&profiles);
    if (SUCCEEDED(hr)) hr = MFCreateSensorProfile(
        KSCAMERAPROFILE_Legacy, 0, nullptr, &legacyProfile);
    if (SUCCEEDED(hr)) hr = legacyProfile->AddProfileFilter(
        0, L"((RES==;FRT<=30,1;SUT==))");
    if (SUCCEEDED(hr)) hr = profiles->AddProfile(legacyProfile.Get());
    if (SUCCEEDED(hr)) hr = m_spAttributes->SetUnknown(
        MF_DEVICEMFT_SENSORPROFILE_COLLECTION, profiles.Get());
    if (FAILED(hr)) return hr;

    // NV12 is canonical and is offered at several frame rates so consumers
    // that pin a specific FPS (Meet, Zoom, OpenCV's DirectShow/MSMF backends)
    // can actually get something other than a hardcoded 30. Index 0 stays
    // 1920x1080 @ 30 NV12 so anything that blindly picks the first type keeps
    // today's default behavior.
    const UINT32 kFpsChoices[] = {30, 15, 24, 60};
    struct Size { UINT32 width, height; };
    const Size kSizeChoices[] = {{1920, 1080}, {1280, 720}};

    std::vector<IMFMediaType*> types;
    types.reserve(8 + 3);
    for (const auto& size : kSizeChoices) {
        for (const UINT32 fps : kFpsChoices) {
            IMFMediaType* type = nullptr;
            hr = CreateMediaType(size.width, size.height, fps, MFVideoFormat_NV12, &type);
            if (FAILED(hr)) break;
            types.push_back(type);
        }
        if (FAILED(hr)) break;
    }
    // Legacy pixel formats for consumers that cannot decode NV12; fixed at
    // 30 fps to keep the format list bounded.
    if (SUCCEEDED(hr)) {
        IMFMediaType* type = nullptr;
        hr = CreateMediaType(1920, 1080, 30, MFVideoFormat_YUY2, &type);
        if (SUCCEEDED(hr)) types.push_back(type);
    }
    if (SUCCEEDED(hr)) {
        IMFMediaType* type = nullptr;
        hr = CreateMediaType(1920, 1080, 30, MFVideoFormat_RGB32, &type);
        if (SUCCEEDED(hr)) types.push_back(type);
    }
    if (SUCCEEDED(hr)) {
        IMFMediaType* type = nullptr;
        hr = CreateMediaType(1280, 720, 30, MFVideoFormat_RGB32, &type);
        if (SUCCEEDED(hr)) types.push_back(type);
    }
    if (SUCCEEDED(hr))
        hr = MFCreateStreamDescriptor(0, static_cast<DWORD>(types.size()), types.data(), &m_spStreamDesc);
    for (auto* type : types) if (type) type->Release();
    if (FAILED(hr)) return hr;
    ComPtr<IMFAttributes> descriptorAttributes;
    hr = m_spStreamDesc.As(&descriptorAttributes);
    if (SUCCEEDED(hr)) hr = m_spStreamAttributes->CopyAllItems(descriptorAttributes.Get());
    if (FAILED(hr)) return hr;
    ComPtr<IMFMediaTypeHandler> handler; hr = m_spStreamDesc->GetMediaTypeHandler(&handler);
    if (FAILED(hr)) return hr;
    ComPtr<IMFMediaType> defaultType; hr = handler->GetMediaTypeByIndex(0, &defaultType);
    if (SUCCEEDED(hr)) hr = handler->SetCurrentMediaType(defaultType.Get());
    if (FAILED(hr)) return hr;
    IMFStreamDescriptor* descriptors[1] = {m_spStreamDesc.Get()};
    hr = MFCreatePresentationDescriptor(1, descriptors, &m_spPresentationDesc);
    if (SUCCEEDED(hr)) hr = m_spPresentationDesc->SelectStream(0);
    return hr;
}

HRESULT PhoneCamMediaSource::AddMediaType(IMFStreamDescriptor*, UINT32, UINT32, UINT32, const GUID&) {
    return E_NOTIMPL;
}
