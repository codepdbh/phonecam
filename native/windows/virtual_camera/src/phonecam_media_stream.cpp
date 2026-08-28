#include "phonecam_media_stream.h"
#include "phonecam_media_source.h"

PhoneCamMediaStream::PhoneCamMediaStream(PhoneCamMediaSource* pSource, IMFStreamDescriptor* pStreamDesc)
    : m_refCount(1),
      m_pSource(pSource),
      m_spStreamDesc(pStreamDesc),
      m_isStreaming(false),
      m_isShutdown(false),
      m_useSyntheticPattern(true),
      m_hasNewFrame(false),
      m_latestTimestampHns(0),
      m_frameCounter(0) {
    MFCreateEventQueue(&m_spEventQueue);
    m_config.width = 1920;
    m_config.height = 1080;
    m_config.fps = 30;
    m_config.format = PhoneCamPixelFormat::NV12;
    m_syntheticGenerator.Configure(m_config);
}

PhoneCamMediaStream::~PhoneCamMediaStream() {
    Shutdown();
}

STDMETHODIMP PhoneCamMediaStream::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator || riid == IID_IMFMediaStream) {
        *ppv = static_cast<IMFMediaStream*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) PhoneCamMediaStream::AddRef() {
    return ++m_refCount;
}

STDMETHODIMP_(ULONG) PhoneCamMediaStream::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

// IMFMediaEventGenerator
STDMETHODIMP PhoneCamMediaStream::BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->BeginGetEvent(pCallback, punkState) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaStream::EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->EndGetEvent(pResult, ppEvent) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaStream::GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) {
    ComPtr<IMFMediaEventQueue> queue;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        queue = m_spEventQueue;
    }
    return queue ? queue->GetEvent(dwFlags, ppEvent) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaStream::QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    return m_spEventQueue ? m_spEventQueue->QueueEventParamVar(met, guidExtendedType, hrStatus, pvValue) : E_FAIL;
}

// IMFMediaStream
STDMETHODIMP PhoneCamMediaStream::GetMediaSource(IMFMediaSource** ppMediaSource) {
    if (!ppMediaSource) return E_POINTER;
    if (!m_pSource) return E_FAIL;
    *ppMediaSource = static_cast<IMFMediaSource*>(m_pSource);
    (*ppMediaSource)->AddRef();
    return S_OK;
}

STDMETHODIMP PhoneCamMediaStream::GetStreamDescriptor(IMFStreamDescriptor** ppStreamDescriptor) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!ppStreamDescriptor) return E_POINTER;
    if (!m_spStreamDesc) return E_FAIL;

    *ppStreamDescriptor = m_spStreamDesc.Get();
    (*ppStreamDescriptor)->AddRef();
    return S_OK;
}

STDMETHODIMP PhoneCamMediaStream::RequestSample(IUnknown* pToken) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!m_isStreaming) return MF_E_INVALIDREQUEST;

    m_sampleRequests.push(pToken);
    m_cv.notify_one();
    return S_OK;
}

HRESULT PhoneCamMediaStream::Start(const PROPVARIANT* pvarStartPosition) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;

    m_isStreaming = true;
    m_frameCounter = 0;

    PROPVARIANT var;
    PropVariantInit(&var);
    if (pvarStartPosition) {
        PropVariantCopy(&var, pvarStartPosition);
    }
    QueueEvent(MEStreamStarted, GUID_NULL, S_OK, &var);
    PropVariantClear(&var);

    if (!m_deliveryThread.joinable()) {
        m_deliveryThread = std::thread(&PhoneCamMediaStream::DeliveryWorkerThread, this);
    }

    m_cv.notify_all();
    return S_OK;
}

HRESULT PhoneCamMediaStream::Stop() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;

    m_isStreaming = false;
    while (!m_sampleRequests.empty()) {
        m_sampleRequests.pop();
    }

    QueueEvent(MEStreamStopped, GUID_NULL, S_OK, nullptr);
    return S_OK;
}

HRESULT PhoneCamMediaStream::Pause() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;

    m_isStreaming = false;
    QueueEvent(MEStreamPaused, GUID_NULL, S_OK, nullptr);
    return S_OK;
}

HRESULT PhoneCamMediaStream::Shutdown() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return S_OK;
        m_isShutdown = true;
        m_isStreaming = false;
        if (m_spEventQueue) {
            m_spEventQueue->Shutdown();
        }
    }

    m_cv.notify_all();
    if (m_deliveryThread.joinable()) {
        m_deliveryThread.join();
    }

    return S_OK;
}

HRESULT PhoneCamMediaStream::SetMediaType(IMFMediaType* pMediaType) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    m_spCurrentMediaType = pMediaType;
    return S_OK;
}

void PhoneCamMediaStream::SetVideoConfig(const PhoneCamVideoConfig& config) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_config = config;
    m_syntheticGenerator.Configure(m_config);
}

void PhoneCamMediaStream::PushFrame(const uint8_t* pBuffer, size_t size, int64_t timestampHns) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown || !pBuffer || size == 0) return;

    m_latestFrameBuffer.assign(pBuffer, pBuffer + size);
    m_latestTimestampHns = timestampHns;
    m_hasNewFrame = true;
    m_useSyntheticPattern = false;
}

void PhoneCamMediaStream::EnableTestPattern(bool enable) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_useSyntheticPattern = enable;
}

void PhoneCamMediaStream::DeliveryWorkerThread() {
    std::vector<uint8_t> frameBuffer;
    auto frameInterval = std::chrono::microseconds(1000000 / (m_config.fps > 0 ? m_config.fps : 30));

    while (true) {
        ComPtr<IUnknown> spToken;
        bool shouldDeliver = false;

        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cv.wait(lock, [this]() {
                return m_isShutdown || (m_isStreaming && !m_sampleRequests.empty());
            });

            if (m_isShutdown) break;
            if (!m_isStreaming || m_sampleRequests.empty()) continue;

            spToken = m_sampleRequests.front();
            m_sampleRequests.pop();
            shouldDeliver = true;

            if (m_useSyntheticPattern || !m_hasNewFrame) {
                m_syntheticGenerator.GenerateNextFrame(frameBuffer, m_frameCounter++);
            } else {
                frameBuffer = m_latestFrameBuffer;
                m_frameCounter++;
            }
        }

        if (shouldDeliver && !frameBuffer.empty()) {
            ComPtr<IMFSample> spSample;
            int64_t timestampHns = m_frameCounter * (10000000 / (m_config.fps > 0 ? m_config.fps : 30));
            HRESULT hr = CreateSampleFromFrame(frameBuffer.data(), frameBuffer.size(), timestampHns, &spSample);

            if (SUCCEEDED(hr) && spSample) {
                if (spToken) {
                    spSample->SetUnknown(MFSampleExtension_Token, spToken.Get());
                }
                PROPVARIANT var;
                PropVariantInit(&var);
                var.vt = VT_UNKNOWN;
                var.punkVal = spSample.Get();
                var.punkVal->AddRef();
                QueueEvent(MEMediaSample, GUID_NULL, S_OK, &var);
                PropVariantClear(&var);
            }
        }

        std::this_thread::sleep_for(frameInterval);
    }
}

HRESULT PhoneCamMediaStream::CreateSampleFromFrame(const uint8_t* pData, size_t size, int64_t timestampHns, IMFSample** ppSample) {
    if (!pData || size == 0 || !ppSample) return E_POINTER;

    ComPtr<IMFSample> spSample;
    HRESULT hr = MFCreateSample(&spSample);
    if (FAILED(hr)) return hr;

    ComPtr<IMFMediaBuffer> spBuffer;
    hr = MFCreateMemoryBuffer(static_cast<DWORD>(size), &spBuffer);
    if (FAILED(hr)) return hr;

    BYTE* pDest = nullptr;
    DWORD maxLen = 0, curLen = 0;
    hr = spBuffer->Lock(&pDest, &maxLen, &curLen);
    if (SUCCEEDED(hr) && pDest) {
        memcpy(pDest, pData, size);
        spBuffer->Unlock();
        spBuffer->SetCurrentLength(static_cast<DWORD>(size));
    }

    hr = spSample->AddBuffer(spBuffer.Get());
    if (FAILED(hr)) return hr;

    int64_t durationHns = 10000000 / (m_config.fps > 0 ? m_config.fps : 30);
    spSample->SetSampleTime(timestampHns);
    spSample->SetSampleDuration(durationHns);

    *ppSample = spSample.Detach();
    return S_OK;
}
