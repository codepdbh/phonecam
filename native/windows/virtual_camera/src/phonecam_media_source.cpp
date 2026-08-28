#include "phonecam_media_source.h"

PhoneCamMediaSource* PhoneCamMediaSource::s_pGlobalInstance = nullptr;

PhoneCamMediaSource::PhoneCamMediaSource()
    : m_refCount(1),
      m_isShutdown(false) {
    MFCreateEventQueue(&m_spEventQueue);
    CreateDescriptors();
    s_pGlobalInstance = this;
}

PhoneCamMediaSource::~PhoneCamMediaSource() {
    Shutdown();
    if (s_pGlobalInstance == this) {
        s_pGlobalInstance = nullptr;
    }
}

PhoneCamMediaSource* PhoneCamMediaSource::GetGlobalInstance() {
    return s_pGlobalInstance;
}

STDMETHODIMP PhoneCamMediaSource::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator || riid == IID_IMFMediaSource) {
        *ppv = static_cast<IMFMediaSource*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == IID_IMFGetService) {
        *ppv = static_cast<IMFGetService*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) PhoneCamMediaSource::AddRef() {
    return ++m_refCount;
}

STDMETHODIMP_(ULONG) PhoneCamMediaSource::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

// IMFGetService
STDMETHODIMP PhoneCamMediaSource::GetService(REFGUID guidService, REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    return QueryInterface(riid, ppv);
}

// IMFMediaEventGenerator
STDMETHODIMP PhoneCamMediaSource::BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->BeginGetEvent(pCallback, punkState) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaSource::EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->EndGetEvent(pResult, ppEvent) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaSource::GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) {
    ComPtr<IMFMediaEventQueue> queue;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        queue = m_spEventQueue;
    }
    return queue ? queue->GetEvent(dwFlags, ppEvent) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaSource::QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->QueueEventParamVar(met, guidExtendedType, hrStatus, pvValue) : E_FAIL;
}

// IMFMediaSource
STDMETHODIMP PhoneCamMediaSource::GetCharacteristics(DWORD* pdwCharacteristics) {
    if (!pdwCharacteristics) return E_POINTER;
    *pdwCharacteristics = MFMEDIASOURCE_IS_LIVE;
    return S_OK;
}

STDMETHODIMP PhoneCamMediaSource::CreatePresentationDescriptor(IMFPresentationDescriptor** ppPresentationDescriptor) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!ppPresentationDescriptor) return E_POINTER;
    if (!m_spPresentationDesc) return E_FAIL;

    return m_spPresentationDesc->Clone(ppPresentationDescriptor);
}

STDMETHODIMP PhoneCamMediaSource::Start(IMFPresentationDescriptor* pPresentationDescriptor, const GUID* pguidTimeFormat, const PROPVARIANT* pvarStartPosition) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!pPresentationDescriptor) return E_POINTER;

    if (!m_spStream) {
        m_spStream = new PhoneCamMediaStream(this, m_spStreamDesc.Get());
    }

    m_spStream->SetVideoConfig(m_config);
    m_spStream->Start(pvarStartPosition);

    PROPVARIANT var;
    PropVariantInit(&var);
    if (pvarStartPosition) {
        PropVariantCopy(&var, pvarStartPosition);
    }
    QueueEvent(MESourceStarted, GUID_NULL, S_OK, &var);
    PropVariantClear(&var);

    return S_OK;
}

STDMETHODIMP PhoneCamMediaSource::Stop() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;

    if (m_spStream) {
        m_spStream->Stop();
    }

    QueueEvent(MESourceStopped, GUID_NULL, S_OK, nullptr);
    return S_OK;
}

STDMETHODIMP PhoneCamMediaSource::Pause() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;

    if (m_spStream) {
        m_spStream->Pause();
    }

    QueueEvent(MESourcePaused, GUID_NULL, S_OK, nullptr);
    return S_OK;
}

STDMETHODIMP PhoneCamMediaSource::Shutdown() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return S_OK;

    m_isShutdown = true;

    if (m_spStream) {
        m_spStream->Shutdown();
        m_spStream.Reset();
    }

    if (m_spEventQueue) {
        m_spEventQueue->Shutdown();
    }

    return S_OK;
}

void PhoneCamMediaSource::PushFrame(const uint8_t* pBuffer, size_t size, int64_t timestampHns) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown || !m_spStream) return;
    m_spStream->PushFrame(pBuffer, size, timestampHns);
}

void PhoneCamMediaSource::EnableTestPattern(bool enable) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_spStream) {
        m_spStream->EnableTestPattern(enable);
    }
}

void PhoneCamMediaSource::SetVideoConfig(const PhoneCamVideoConfig& config) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_config = config;
    if (m_spStream) {
        m_spStream->SetVideoConfig(config);
    }
}

static HRESULT CreateMediaType(UINT32 width, UINT32 height, UINT32 fps, const GUID& subType, IMFMediaType** ppMediaType) {
    if (!ppMediaType) return E_POINTER;
    ComPtr<IMFMediaType> spMediaType;
    HRESULT hr = MFCreateMediaType(&spMediaType);
    if (FAILED(hr)) return hr;

    spMediaType->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    spMediaType->SetGUID(MF_MT_SUBTYPE, subType);
    spMediaType->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    spMediaType->SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, TRUE);
    MFSetAttributeSize(spMediaType.Get(), MF_MT_FRAME_SIZE, width, height);
    MFSetAttributeRatio(spMediaType.Get(), MF_MT_FRAME_RATE, fps, 1);
    MFSetAttributeRatio(spMediaType.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);

    if (subType == MFVideoFormat_NV12) {
        spMediaType->SetUINT32(MF_MT_DEFAULT_STRIDE, width);
    } else if (subType == MFVideoFormat_RGB32) {
        spMediaType->SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4);
    }

    *ppMediaType = spMediaType.Detach();
    return S_OK;
}

HRESULT PhoneCamMediaSource::CreateDescriptors() {
    HRESULT hr = S_OK;
    IMFMediaType* pMediaTypeArray[4] = { nullptr };

    CreateMediaType(1920, 1080, 30, MFVideoFormat_NV12, &pMediaTypeArray[0]);
    CreateMediaType(1280, 720, 30, MFVideoFormat_NV12, &pMediaTypeArray[1]);
    CreateMediaType(1920, 1080, 60, MFVideoFormat_NV12, &pMediaTypeArray[2]);
    CreateMediaType(1920, 1080, 30, MFVideoFormat_RGB32, &pMediaTypeArray[3]);

    hr = MFCreateStreamDescriptor(0, 4, pMediaTypeArray, &m_spStreamDesc);

    for (int i = 0; i < 4; i++) {
        if (pMediaTypeArray[i]) pMediaTypeArray[i]->Release();
    }

    if (FAILED(hr)) return hr;

    IMFStreamDescriptor* pStreamDescArray[1] = { m_spStreamDesc.Get() };
    hr = MFCreatePresentationDescriptor(1, pStreamDescArray, &m_spPresentationDesc);
    if (FAILED(hr)) return hr;

    hr = m_spPresentationDesc->SelectStream(0);
    return hr;
}
