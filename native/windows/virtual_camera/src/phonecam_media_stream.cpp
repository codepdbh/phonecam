#include "phonecam_media_stream.h"
#include "phonecam_frame_converter.h"
#include "phonecam_media_source.h"

#include <chrono>

PhoneCamMediaStream::PhoneCamMediaStream(PhoneCamMediaSource* source, IMFStreamDescriptor* descriptor)
    : m_refCount(1), m_pSource(source), m_spStreamDesc(descriptor),
      m_isStreaming(false), m_isShutdown(false), m_useSyntheticPattern(false),
      m_frameCounter(0) {
    PhoneCamComObjectCreated();
    MFCreateEventQueue(&m_spEventQueue);
    m_config = {1920, 1080, 30, PhoneCamPixelFormat::NV12};
    m_syntheticGenerator.Configure(m_config);
    m_frameBroker.Initialize(false);
    m_frameBroker.MarkStreamConstructed();
}

PhoneCamMediaStream::~PhoneCamMediaStream() { Shutdown(); PhoneCamComObjectDestroyed(); }

STDMETHODIMP PhoneCamMediaStream::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IMFMediaEventGenerator ||
        riid == IID_IMFMediaStream || riid == IID_IMFMediaStream2) {
        *ppv = static_cast<IMFMediaStream2*>(this); AddRef(); return S_OK;
    }
    *ppv = nullptr; return E_NOINTERFACE;
}
STDMETHODIMP_(ULONG) PhoneCamMediaStream::AddRef() { return ++m_refCount; }
STDMETHODIMP_(ULONG) PhoneCamMediaStream::Release() {
    const ULONG count = --m_refCount; if (!count) delete this; return count;
}

STDMETHODIMP PhoneCamMediaStream::BeginGetEvent(IMFAsyncCallback* callback, IUnknown* state) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->BeginGetEvent(callback, state) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaStream::EndGetEvent(IMFAsyncResult* result, IMFMediaEvent** event) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->EndGetEvent(result, event) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaStream::GetEvent(DWORD flags, IMFMediaEvent** event) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->GetEvent(flags, event) : E_FAIL;
}
STDMETHODIMP PhoneCamMediaStream::QueueEvent(MediaEventType type, REFGUID extended,
                                             HRESULT status, const PROPVARIANT* value) {
    ComPtr<IMFMediaEventQueue> queue;
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; queue = m_spEventQueue; }
    return queue ? queue->QueueEventParamVar(type, extended, status, value) : E_FAIL;
}

STDMETHODIMP PhoneCamMediaStream::GetMediaSource(IMFMediaSource** source) {
    if (!source) return E_POINTER;
    if (!m_pSource) return E_FAIL;
    *source = static_cast<IMFMediaSource*>(m_pSource); (*source)->AddRef(); return S_OK;
}
STDMETHODIMP PhoneCamMediaStream::GetStreamDescriptor(IMFStreamDescriptor** descriptor) {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (!descriptor || !m_spStreamDesc) return descriptor ? E_FAIL : E_POINTER;
    *descriptor = m_spStreamDesc.Get(); (*descriptor)->AddRef(); return S_OK;
}
STDMETHODIMP PhoneCamMediaStream::RequestSample(IUnknown* token) {
    m_frameBroker.MarkSampleRequest();
    PhoneCamVideoConfig config;
    bool forcePattern = false;
    uint64_t frameIndex = 0;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        if (!m_isStreaming) return MF_E_INVALIDREQUEST;
        config = m_config;
        forcePattern = m_useSyntheticPattern;
        frameIndex = m_frameCounter++;
    }

    // Produce the requested sample synchronously, as required by the Frame
    // Server media-stream pull contract. Deferring it to an unmanaged worker
    // can leave the proxy waiting indefinitely and emitting stream ticks.
    std::vector<uint8_t> brokerFrame;
    std::vector<uint8_t> outputFrame;
    bool realFrame = false;
    if (!forcePattern) {
        PhoneCamFrameMetadata metadata{};
        if (m_frameBroker.ReadLatestFrame(metadata, brokerFrame))
            realFrame = PhoneCamConvertFrame(metadata, brokerFrame, config, outputFrame);
    }
    if (!realFrame) {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_syntheticGenerator.GenerateNextFrame(outputFrame, frameIndex);
    }

    ComPtr<IMFSample> sample;
    HRESULT hr = CreateSampleFromFrame(outputFrame.data(), outputFrame.size(),
                                       MFGetSystemTime(), config, &sample);
    if (FAILED(hr)) return hr;
    if (token) {
        hr = sample->SetUnknown(MFSampleExtension_Token, token);
        if (FAILED(hr)) return hr;
    }
    hr = m_spEventQueue
        ? m_spEventQueue->QueueEventParamUnk(MEMediaSample, GUID_NULL, S_OK, sample.Get())
        : E_FAIL;
    if (SUCCEEDED(hr)) m_frameBroker.MarkSampleProduced();
    return hr;
}

STDMETHODIMP PhoneCamMediaStream::SetStreamState(MF_STREAM_STATE value) {
    m_frameBroker.MarkStreamStateChange();
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    m_streamState = value;
    m_isStreaming = value == MF_STREAM_STATE_RUNNING;
    if (value == MF_STREAM_STATE_STOPPED) while (!m_sampleRequests.empty()) m_sampleRequests.pop();
    m_cv.notify_all();
    return S_OK;
}
STDMETHODIMP PhoneCamMediaStream::GetStreamState(MF_STREAM_STATE* value) {
    if (!value) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    *value = m_streamState; return S_OK;
}

HRESULT PhoneCamMediaStream::Start(const PROPVARIANT* position) {
    m_frameBroker.MarkStreamStart();
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        m_isStreaming = true;
        m_streamState = MF_STREAM_STATE_RUNNING;
        m_frameCounter = 0;
    }
    PROPVARIANT value; PropVariantInit(&value);
    if (position) PropVariantCopy(&value, position);
    const HRESULT hr = QueueEvent(MEStreamStarted, GUID_NULL, S_OK, &value);
    PropVariantClear(&value); m_cv.notify_all(); return hr;
}
HRESULT PhoneCamMediaStream::Stop() {
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return MF_E_SHUTDOWN;
        m_isStreaming = false;
        m_streamState = MF_STREAM_STATE_STOPPED;
        while (!m_sampleRequests.empty()) m_sampleRequests.pop();
    }
    return QueueEvent(MEStreamStopped, GUID_NULL, S_OK, nullptr);
}
HRESULT PhoneCamMediaStream::Pause() {
    { std::lock_guard<std::mutex> lock(m_mutex); if (m_isShutdown) return MF_E_SHUTDOWN; m_isStreaming = false; m_streamState = MF_STREAM_STATE_PAUSED; }
    return QueueEvent(MEStreamPaused, GUID_NULL, S_OK, nullptr);
}
HRESULT PhoneCamMediaStream::Shutdown() {
    ComPtr<IMFMediaEventQueue> queue;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        if (m_isShutdown) return S_OK;
        m_isShutdown = true; m_isStreaming = false; queue = m_spEventQueue;
    }
    m_cv.notify_all();
    if (m_deliveryThread.joinable()) m_deliveryThread.join();
    if (queue) queue->Shutdown();
    m_frameBroker.Close();
    return S_OK;
}

HRESULT PhoneCamMediaStream::SetMediaType(IMFMediaType* type) {
    if (!type) return E_POINTER;
    UINT32 width = 0, height = 0, numerator = 30, denominator = 1;
    GUID subtype = GUID_NULL;
    HRESULT hr = MFGetAttributeSize(type, MF_MT_FRAME_SIZE, &width, &height);
    if (FAILED(hr)) return hr;
    MFGetAttributeRatio(type, MF_MT_FRAME_RATE, &numerator, &denominator);
    hr = type->GetGUID(MF_MT_SUBTYPE, &subtype); if (FAILED(hr)) return hr;
    PhoneCamVideoConfig config;
    config.width = width; config.height = height;
    config.fps = denominator ? numerator / denominator : numerator;
    if (subtype == MFVideoFormat_NV12) config.format = PhoneCamPixelFormat::NV12;
    else if (subtype == MFVideoFormat_RGB32) config.format = PhoneCamPixelFormat::RGB32;
    else if (subtype == MFVideoFormat_YUY2) config.format = PhoneCamPixelFormat::YUY2;
    else return MF_E_INVALIDMEDIATYPE;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (m_spSampleAllocator) {
        hr = m_spSampleAllocator->InitializeSampleAllocator(10, type);
        if (FAILED(hr)) return hr;
    }
    m_spCurrentMediaType = type;
    m_config = config;
    m_syntheticGenerator.Configure(config);
    return S_OK;
}
HRESULT PhoneCamMediaStream::SetSampleAllocator(IMFVideoSampleAllocator* allocator) {
    if (!allocator) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isShutdown) return MF_E_SHUTDOWN;
    if (m_isStreaming) return MF_E_INVALIDREQUEST;
    m_spSampleAllocator = allocator;
    return S_OK;
}
void PhoneCamMediaStream::SetVideoConfig(const PhoneCamVideoConfig& config) {
    std::lock_guard<std::mutex> lock(m_mutex); m_config = config; m_syntheticGenerator.Configure(config);
}
void PhoneCamMediaStream::EnableTestPattern(bool enable) {
    std::lock_guard<std::mutex> lock(m_mutex); m_useSyntheticPattern = enable;
}

void PhoneCamMediaStream::DeliveryWorkerThread() {
    std::vector<uint8_t> brokerFrame, outputFrame;
    while (true) {
        ComPtr<IUnknown> token;
        PhoneCamVideoConfig config;
        bool forcePattern = false;
        {
            std::unique_lock<std::mutex> lock(m_mutex);
            m_cv.wait(lock, [this] { return m_isShutdown || (m_isStreaming && !m_sampleRequests.empty()); });
            if (m_isShutdown) break;
            if (!m_isStreaming || m_sampleRequests.empty()) continue;
            token = m_sampleRequests.front(); m_sampleRequests.pop();
            config = m_config; forcePattern = m_useSyntheticPattern;
        }

        bool realFrame = false;
        if (!forcePattern) {
            PhoneCamFrameMetadata metadata{};
            if (m_frameBroker.ReadLatestFrame(metadata, brokerFrame))
                realFrame = PhoneCamConvertFrame(metadata, brokerFrame, config, outputFrame);
        }
        if (!realFrame) {
            std::lock_guard<std::mutex> lock(m_mutex);
            m_syntheticGenerator.GenerateNextFrame(outputFrame, m_frameCounter);
        }
        // Frame Server requires timestamps correlated to the system QPC clock.
        // A stream-relative timestamp starting at zero is treated as stale and
        // its frames may be silently dropped by browser/capture pipelines.
        const int64_t timestamp = MFGetSystemTime();
        ++m_frameCounter;
        ComPtr<IMFSample> sample;
        HRESULT hr = CreateSampleFromFrame(outputFrame.data(), outputFrame.size(),
                                           timestamp, config, &sample);
        if (SUCCEEDED(hr) && sample) {
            if (token) sample->SetUnknown(MFSampleExtension_Token, token.Get());
            PROPVARIANT value; PropVariantInit(&value); value.vt = VT_UNKNOWN;
            value.punkVal = sample.Get(); value.punkVal->AddRef();
            QueueEvent(MEMediaSample, GUID_NULL, S_OK, &value); PropVariantClear(&value);
        } else {
            QueueEvent(MEError, GUID_NULL, hr, nullptr);
        }
    }
}

HRESULT PhoneCamMediaStream::CreateSampleFromFrame(const uint8_t* data, size_t size,
                                                   int64_t timestamp,
                                                   const PhoneCamVideoConfig& config,
                                                   IMFSample** result) {
    if (!data || !size || !result) return E_POINTER;
    if (size != config.GetFrameSizeBytes()) return MF_E_BUFFERTOOSMALL;
    ComPtr<IMFVideoSampleAllocator> allocator;
    {
        std::lock_guard<std::mutex> lock(m_mutex);
        allocator = m_spSampleAllocator;
    }
    ComPtr<IMFSample> sample;
    HRESULT hr = allocator ? allocator->AllocateSample(&sample)
                           : MFCreateSample(&sample);
    if (FAILED(hr)) return hr;
    const DWORD fourcc = config.format == PhoneCamPixelFormat::RGB32
        ? MFVideoFormat_RGB32.Data1
        : config.format == PhoneCamPixelFormat::YUY2
            ? MFVideoFormat_YUY2.Data1
            : MFVideoFormat_NV12.Data1;
    ComPtr<IMFMediaBuffer> buffer;
    if (allocator)
        hr = sample->GetBufferByIndex(0, &buffer);
    else
        hr = MFCreate2DMediaBuffer(config.width, config.height, fourcc, FALSE, &buffer);
    if (FAILED(hr)) return hr;
    ComPtr<IMF2DBuffer2> buffer2D;
    hr = buffer.As(&buffer2D);
    if (FAILED(hr)) return hr;
    BYTE* firstRow = nullptr;
    BYTE* bufferStart = nullptr;
    LONG pitch = 0;
    DWORD capacity = 0;
    hr = buffer2D->Lock2DSize(MF2DBuffer_LockFlags_Write, &firstRow, &pitch,
                              &bufferStart, &capacity);
    if (FAILED(hr)) return hr;
    const DWORD rowBytes = config.format == PhoneCamPixelFormat::RGB32
        ? config.width * 4
        : config.format == PhoneCamPixelFormat::YUY2
            ? config.width * 2
            : config.width;
    hr = MFCopyImage(firstRow, pitch, data, rowBytes, rowBytes, config.height);
    if (SUCCEEDED(hr) && config.format == PhoneCamPixelFormat::NV12) {
        hr = MFCopyImage(firstRow + static_cast<size_t>(pitch) * config.height,
                         pitch,
                         data + static_cast<size_t>(config.width) * config.height,
                         config.width, config.width, config.height / 2);
    }
    const HRESULT unlockHr = buffer2D->Unlock2D();
    if (FAILED(hr)) return hr;
    if (FAILED(unlockHr)) return unlockHr;
    hr = buffer->SetCurrentLength(static_cast<DWORD>(size));
    if (FAILED(hr)) return hr;
    if (!allocator) {
        hr = sample->AddBuffer(buffer.Get());
        if (FAILED(hr)) return hr;
    }
    sample->SetSampleTime(timestamp);
    sample->SetSampleDuration(static_cast<LONGLONG>(config.GetFrameDurationHns()));
    sample->SetUINT32(MFSampleExtension_CleanPoint, TRUE);
    *result = sample.Detach(); return S_OK;
}
