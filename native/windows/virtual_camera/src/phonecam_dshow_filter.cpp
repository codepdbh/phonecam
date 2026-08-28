#include "phonecam_dshow_filter.h"
#include <initguid.h>
#include <ks.h>
#include <ksmedia.h>

// Forward declarations of Enumerators
class EnumPinsImpl : public IEnumPins {
public:
    EnumPinsImpl(IPin* pPin) : m_refCount(1), m_pPin(pPin), m_pos(0) {
        if (m_pPin) m_pPin->AddRef();
    }
    virtual ~EnumPinsImpl() {
        if (m_pPin) m_pPin->Release();
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IEnumPins) {
            *ppv = static_cast<IEnumPins*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_refCount; }
    STDMETHODIMP_(ULONG) Release() override {
        ULONG count = --m_refCount;
        if (count == 0) delete this;
        return count;
    }

    STDMETHODIMP Next(ULONG cPins, IPin** ppPins, ULONG* pcFetched) override {
        if (!ppPins) return E_POINTER;
        ULONG fetched = 0;
        if (m_pos == 0 && cPins > 0 && m_pPin) {
            ppPins[0] = m_pPin;
            m_pPin->AddRef();
            fetched = 1;
            m_pos = 1;
        }
        if (pcFetched) *pcFetched = fetched;
        return (fetched == cPins) ? S_OK : S_FALSE;
    }
    STDMETHODIMP Skip(ULONG cPins) override {
        m_pos += cPins;
        return S_OK;
    }
    STDMETHODIMP Reset() override {
        m_pos = 0;
        return S_OK;
    }
    STDMETHODIMP Clone(IEnumPins** ppEnum) override {
        if (!ppEnum) return E_POINTER;
        *ppEnum = new EnumPinsImpl(m_pPin);
        return S_OK;
    }

private:
    std::atomic<ULONG> m_refCount;
    IPin* m_pPin;
    ULONG m_pos;
};

class EnumMediaTypesImpl : public IEnumMediaTypes {
public:
    EnumMediaTypesImpl(PhoneCamDShowPin* pPin) : m_refCount(1), m_pPin(pPin), m_pos(0) {
        if (m_pPin) m_pPin->AddRef();
    }
    virtual ~EnumMediaTypesImpl() {
        if (m_pPin) m_pPin->Release();
    }

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IEnumMediaTypes) {
            *ppv = static_cast<IEnumMediaTypes*>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++m_refCount; }
    STDMETHODIMP_(ULONG) Release() override {
        ULONG count = --m_refCount;
        if (count == 0) delete this;
        return count;
    }

    STDMETHODIMP Next(ULONG cMediaTypes, AM_MEDIA_TYPE** ppMediaTypes, ULONG* pcFetched) override;
    STDMETHODIMP Skip(ULONG cMediaTypes) override {
        m_pos += cMediaTypes;
        return S_OK;
    }
    STDMETHODIMP Reset() override {
        m_pos = 0;
        return S_OK;
    }
    STDMETHODIMP Clone(IEnumMediaTypes** ppEnum) override {
        if (!ppEnum) return E_POINTER;
        *ppEnum = new EnumMediaTypesImpl(m_pPin);
        return S_OK;
    }

private:
    std::atomic<ULONG> m_refCount;
    PhoneCamDShowPin* m_pPin;
    ULONG m_pos;
};

// ==========================================
// PhoneCamDShowFilter Implementation
// ==========================================
PhoneCamDShowFilter::PhoneCamDShowFilter()
    : m_refCount(1),
      m_state(State_Stopped),
      m_pGraph(nullptr),
      m_pClock(nullptr),
      m_name(L"PhoneCam Virtual Camera") {
    m_spPin = new PhoneCamDShowPin(this);
}

PhoneCamDShowFilter::~PhoneCamDShowFilter() {
    Stop();
}

STDMETHODIMP PhoneCamDShowFilter::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IPersist || riid == IID_IMediaFilter || riid == IID_IBaseFilter) {
        *ppv = static_cast<IBaseFilter*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == IID_IAMFilterMiscFlags) {
        *ppv = static_cast<IAMFilterMiscFlags*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) PhoneCamDShowFilter::AddRef() {
    return ++m_refCount;
}

STDMETHODIMP_(ULONG) PhoneCamDShowFilter::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

STDMETHODIMP PhoneCamDShowFilter::GetClassID(CLSID* pClassID) {
    if (!pClassID) return E_POINTER;
    *pClassID = CLSID_PhoneCamMediaSource;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::Stop() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_state = State_Stopped;
    if (m_spPin) {
        m_spPin->StopStreaming();
    }
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::Pause() {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_state = State_Paused;
    if (m_spPin) {
        m_spPin->StartStreaming();
    }
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::Run(REFERENCE_TIME tStart) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_state = State_Running;
    if (m_spPin) {
        m_spPin->StartStreaming();
    }
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::GetState(DWORD dwMilliSecsTimeout, FILTER_STATE* State) {
    if (!State) return E_POINTER;
    *State = m_state;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::SetSyncSource(IReferenceClock* pClock) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pClock = pClock;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::GetSyncSource(IReferenceClock** ppClock) {
    if (!ppClock) return E_POINTER;
    *ppClock = m_pClock;
    if (m_pClock) m_pClock->AddRef();
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::EnumPins(IEnumPins** ppEnum) {
    if (!ppEnum) return E_POINTER;
    *ppEnum = new EnumPinsImpl(m_spPin.Get());
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::FindPin(LPCWSTR Id, IPin** ppPin) {
    if (!ppPin) return E_POINTER;
    if (Id && wcscmp(Id, L"Output") == 0) {
        *ppPin = m_spPin.Get();
        if (*ppPin) (*ppPin)->AddRef();
        return S_OK;
    }
    *ppPin = nullptr;
    return VFW_E_NOT_FOUND;
}

STDMETHODIMP PhoneCamDShowFilter::QueryFilterInfo(FILTER_INFO* pInfo) {
    if (!pInfo) return E_POINTER;
    wcsncpy_s(pInfo->achName, m_name.c_str(), MAX_FILTER_NAME);
    pInfo->pGraph = m_pGraph;
    if (m_pGraph) m_pGraph->AddRef();
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::JoinFilterGraph(IFilterGraph* pGraph, LPCWSTR pName) {
    std::lock_guard<std::mutex> lock(m_mutex);
    m_pGraph = pGraph;
    if (pName) m_name = pName;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowFilter::QueryVendorInfo(LPWSTR* pVendorInfo) {
    if (!pVendorInfo) return E_POINTER;
    const wchar_t* vendor = L"PhoneCam Systems";
    size_t len = (wcslen(vendor) + 1) * sizeof(wchar_t);
    *pVendorInfo = (LPWSTR)CoTaskMemAlloc(len);
    if (*pVendorInfo) {
        memcpy(*pVendorInfo, vendor, len);
        return S_OK;
    }
    return E_OUTOFMEMORY;
}

STDMETHODIMP_(ULONG) PhoneCamDShowFilter::GetMiscFlags() {
    return AM_FILTER_MISC_FLAGS_IS_SOURCE;
}

// ==========================================
// PhoneCamDShowPin Implementation
// ==========================================
PhoneCamDShowPin::PhoneCamDShowPin(PhoneCamDShowFilter* pFilter)
    : m_refCount(1),
      m_pFilter(pFilter),
      m_hasMediaType(false),
      m_isStreaming(false),
      m_frameIndex(0) {
    memset(&m_currentMediaType, 0, sizeof(m_currentMediaType));
    m_shmem.Initialize(false);
    PhoneCamVideoConfig cfg;
    cfg.width = 1920;
    cfg.height = 1080;
    cfg.fps = 30;
    cfg.format = PhoneCamPixelFormat::RGB32;
    m_syntheticGenerator.Configure(cfg);
}

PhoneCamDShowPin::~PhoneCamDShowPin() {
    StopStreaming();
    if (m_currentMediaType.pbFormat) {
        CoTaskMemFree(m_currentMediaType.pbFormat);
    }
}

STDMETHODIMP PhoneCamDShowPin::QueryInterface(REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER;
    if (riid == IID_IUnknown || riid == IID_IPin) {
        *ppv = static_cast<IPin*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == IID_IKsPropertySet) {
        *ppv = static_cast<IKsPropertySet*>(this);
        AddRef();
        return S_OK;
    }
    if (riid == IID_IAMStreamConfig) {
        *ppv = static_cast<IAMStreamConfig*>(this);
        AddRef();
        return S_OK;
    }
    *ppv = nullptr;
    return E_NOINTERFACE;
}

STDMETHODIMP_(ULONG) PhoneCamDShowPin::AddRef() {
    return ++m_refCount;
}

STDMETHODIMP_(ULONG) PhoneCamDShowPin::Release() {
    ULONG count = --m_refCount;
    if (count == 0) {
        delete this;
    }
    return count;
}

HRESULT PhoneCamDShowPin::CreateDefaultMediaType(AM_MEDIA_TYPE* pmt, int width, int height, int fps, bool isRGB24) {
    if (!pmt) return E_POINTER;
    memset(pmt, 0, sizeof(AM_MEDIA_TYPE));
    pmt->majortype = MEDIATYPE_Video;
    pmt->subtype = isRGB24 ? MEDIASUBTYPE_RGB24 : MEDIASUBTYPE_RGB32;
    pmt->bFixedSizeSamples = TRUE;
    pmt->bTemporalCompression = FALSE;
    pmt->lSampleSize = width * height * (isRGB24 ? 3 : 4);
    pmt->formattype = FORMAT_VideoInfo;

    VIDEOINFOHEADER* pvih = (VIDEOINFOHEADER*)CoTaskMemAlloc(sizeof(VIDEOINFOHEADER));
    if (!pvih) return E_OUTOFMEMORY;
    memset(pvih, 0, sizeof(VIDEOINFOHEADER));
    pvih->rcSource = { 0, 0, width, height };
    pvih->rcTarget = { 0, 0, width, height };
    pvih->AvgTimePerFrame = 10000000LL / (fps > 0 ? fps : 30);
    pvih->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    pvih->bmiHeader.biWidth = width;
    pvih->bmiHeader.biHeight = height;
    pvih->bmiHeader.biPlanes = 1;
    pvih->bmiHeader.biBitCount = isRGB24 ? 24 : 32;
    pvih->bmiHeader.biCompression = BI_RGB;
    pvih->bmiHeader.biSizeImage = pmt->lSampleSize;

    pmt->cbFormat = sizeof(VIDEOINFOHEADER);
    pmt->pbFormat = (BYTE*)pvih;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::Connect(IPin* pReceivePin, const AM_MEDIA_TYPE* pmt) {
    if (!pReceivePin) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_spConnectedPin) return VFW_E_ALREADY_CONNECTED;

    AM_MEDIA_TYPE mt;
    if (pmt) {
        mt = *pmt;
    } else {
        CreateDefaultMediaType(&mt, 1920, 1080, 30, false);
    }

    HRESULT hr = pReceivePin->ReceiveConnection(this, &mt);
    if (SUCCEEDED(hr)) {
        m_spConnectedPin = pReceivePin;
        m_currentMediaType = mt;
        m_hasMediaType = true;
        pReceivePin->QueryInterface(IID_IMemInputPin, (void**)&m_spMemInputPin);
    }
    return hr;
}

STDMETHODIMP PhoneCamDShowPin::ReceiveConnection(IPin* pConnector, const AM_MEDIA_TYPE* pmt) {
    return E_UNEXPECTED;
}

STDMETHODIMP PhoneCamDShowPin::Disconnect() {
    std::lock_guard<std::mutex> lock(m_mutex);
    StopStreaming();
    m_spConnectedPin.Reset();
    m_spMemInputPin.Reset();
    m_spAllocator.Reset();
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::ConnectedTo(IPin** pPin) {
    if (!pPin) return E_POINTER;
    *pPin = m_spConnectedPin.Get();
    if (*pPin) (*pPin)->AddRef();
    return *pPin ? S_OK : VFW_E_NOT_CONNECTED;
}

STDMETHODIMP PhoneCamDShowPin::ConnectionMediaType(AM_MEDIA_TYPE* pmt) {
    if (!pmt) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (!m_hasMediaType) return VFW_E_NOT_CONNECTED;

    *pmt = m_currentMediaType;
    if (m_currentMediaType.cbFormat > 0 && m_currentMediaType.pbFormat) {
        pmt->pbFormat = (BYTE*)CoTaskMemAlloc(m_currentMediaType.cbFormat);
        memcpy(pmt->pbFormat, m_currentMediaType.pbFormat, m_currentMediaType.cbFormat);
    }
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::QueryPinInfo(PIN_INFO* pInfo) {
    if (!pInfo) return E_POINTER;
    pInfo->pFilter = m_pFilter;
    if (m_pFilter) m_pFilter->AddRef();
    pInfo->dir = PINDIR_OUTPUT;
    wcscpy_s(pInfo->achName, L"Capture");
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::QueryDirection(PIN_DIRECTION* pPinDir) {
    if (!pPinDir) return E_POINTER;
    *pPinDir = PINDIR_OUTPUT;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::QueryId(LPWSTR* Id) {
    if (!Id) return E_POINTER;
    const wchar_t* pinId = L"Output";
    size_t len = (wcslen(pinId) + 1) * sizeof(wchar_t);
    *Id = (LPWSTR)CoTaskMemAlloc(len);
    if (*Id) {
        memcpy(*Id, pinId, len);
        return S_OK;
    }
    return E_OUTOFMEMORY;
}

STDMETHODIMP PhoneCamDShowPin::QueryAccept(const AM_MEDIA_TYPE* pmt) {
    if (!pmt) return E_POINTER;
    if (pmt->majortype == MEDIATYPE_Video &&
        (pmt->subtype == MEDIASUBTYPE_RGB24 || pmt->subtype == MEDIASUBTYPE_RGB32 || pmt->subtype == MEDIASUBTYPE_NV12)) {
        return S_OK;
    }
    return S_FALSE;
}

STDMETHODIMP PhoneCamDShowPin::EnumMediaTypes(IEnumMediaTypes** ppEnum) {
    if (!ppEnum) return E_POINTER;
    *ppEnum = new EnumMediaTypesImpl(this);
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::QueryInternalConnections(IPin** apPin, ULONG* nPin) {
    return E_NOTIMPL;
}

STDMETHODIMP PhoneCamDShowPin::EndOfStream() { return S_OK; }
STDMETHODIMP PhoneCamDShowPin::BeginFlush() { return S_OK; }
STDMETHODIMP PhoneCamDShowPin::EndFlush() { return S_OK; }
STDMETHODIMP PhoneCamDShowPin::NewSegment(REFERENCE_TIME tStart, REFERENCE_TIME tStop, double dRate) { return S_OK; }

// IKsPropertySet for PIN_CATEGORY_CAPTURE
STDMETHODIMP PhoneCamDShowPin::Set(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData) {
    return E_NOTIMPL;
}

STDMETHODIMP PhoneCamDShowPin::Get(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData, DWORD* pcbReturned) {
    if (guidPropSet == AMPROPSETID_Pin && dwPropID == AMPROPERTY_PIN_CATEGORY) {
        if (!pPropData || cbPropData < sizeof(GUID)) return E_POINTER;
        *(GUID*)pPropData = PIN_CATEGORY_CAPTURE;
        if (pcbReturned) *pcbReturned = sizeof(GUID);
        return S_OK;
    }
    return E_PROP_SET_UNSUPPORTED;
}

STDMETHODIMP PhoneCamDShowPin::QuerySupported(REFGUID guidPropSet, DWORD dwPropID, DWORD* pTypeSupport) {
    if (guidPropSet == AMPROPSETID_Pin && dwPropID == AMPROPERTY_PIN_CATEGORY) {
        if (pTypeSupport) *pTypeSupport = KSPROPERTY_SUPPORT_GET;
        return S_OK;
    }
    return E_PROP_SET_UNSUPPORTED;
}

// IAMStreamConfig
STDMETHODIMP PhoneCamDShowPin::SetFormat(AM_MEDIA_TYPE* pmt) {
    if (!pmt) return E_POINTER;
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_currentMediaType.pbFormat) {
        CoTaskMemFree(m_currentMediaType.pbFormat);
    }
    m_currentMediaType = *pmt;
    if (pmt->cbFormat > 0 && pmt->pbFormat) {
        m_currentMediaType.pbFormat = (BYTE*)CoTaskMemAlloc(pmt->cbFormat);
        memcpy(m_currentMediaType.pbFormat, pmt->pbFormat, pmt->cbFormat);
    }
    m_hasMediaType = true;
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::GetFormat(AM_MEDIA_TYPE** ppmt) {
    if (!ppmt) return E_POINTER;
    *ppmt = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
    if (!*ppmt) return E_OUTOFMEMORY;
    return ConnectionMediaType(*ppmt);
}

STDMETHODIMP PhoneCamDShowPin::GetNumberOfCapabilities(int* piCount, int* piSize) {
    if (!piCount || !piSize) return E_POINTER;
    *piCount = 4; // 1080p RGB32, 1080p RGB24, 720p RGB32, 720p RGB24
    *piSize = sizeof(VIDEO_STREAM_CONFIG_CAPS);
    return S_OK;
}

STDMETHODIMP PhoneCamDShowPin::GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pSCC) {
    if (!ppmt || !pSCC) return E_POINTER;
    *ppmt = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
    if (!*ppmt) return E_OUTOFMEMORY;

    int width = 1920, height = 1080;
    bool isRGB24 = false;
    if (iIndex == 0) { width = 1920; height = 1080; isRGB24 = false; }
    else if (iIndex == 1) { width = 1920; height = 1080; isRGB24 = true; }
    else if (iIndex == 2) { width = 1280; height = 720; isRGB24 = false; }
    else if (iIndex == 3) { width = 1280; height = 720; isRGB24 = true; }

    CreateDefaultMediaType(*ppmt, width, height, 30, isRGB24);

    VIDEO_STREAM_CONFIG_CAPS* caps = (VIDEO_STREAM_CONFIG_CAPS*)pSCC;
    memset(caps, 0, sizeof(VIDEO_STREAM_CONFIG_CAPS));
    caps->guid = FORMAT_VideoInfo;
    caps->VideoStandard = 0;
    caps->InputSize = { (LONG)width, (LONG)height };
    caps->MinCroppingSize = { 160, 120 };
    caps->MaxCroppingSize = { (LONG)width, (LONG)height };
    caps->CropGranularityX = 1;
    caps->CropGranularityY = 1;
    caps->CropAlignX = 1;
    caps->CropAlignY = 1;
    caps->MinOutputSize = { 160, 120 };
    caps->MaxOutputSize = { (LONG)width, (LONG)height };
    caps->OutputGranularityX = 1;
    caps->OutputGranularityY = 1;
    caps->MinFrameInterval = 10000000 / 60;
    caps->MaxFrameInterval = 10000000 / 15;
    caps->MinBitsPerSecond = (width * height * 24 * 15);
    caps->MaxBitsPerSecond = (width * height * 24 * 60);

    return S_OK;
}

// Next implementation for EnumMediaTypesImpl
STDMETHODIMP EnumMediaTypesImpl::Next(ULONG cMediaTypes, AM_MEDIA_TYPE** ppMediaTypes, ULONG* pcFetched) {
    if (!ppMediaTypes) return E_POINTER;
    ULONG fetched = 0;
    while (fetched < cMediaTypes && m_pos < 4) {
        ppMediaTypes[fetched] = (AM_MEDIA_TYPE*)CoTaskMemAlloc(sizeof(AM_MEDIA_TYPE));
        BYTE scc[sizeof(VIDEO_STREAM_CONFIG_CAPS)];
        if (m_pPin->GetStreamCaps(m_pos, &ppMediaTypes[fetched], scc) == S_OK) {
            fetched++;
            m_pos++;
        } else {
            break;
        }
    }
    if (pcFetched) *pcFetched = fetched;
    return (fetched == cMediaTypes) ? S_OK : S_FALSE;
}

// ==========================================
// Streaming Thread Worker
// ==========================================
void PhoneCamDShowPin::StartStreaming() {
    std::lock_guard<std::mutex> lock(m_mutex);
    if (m_isStreaming) return;

    if (!m_spMemInputPin && m_spConnectedPin) {
        m_spConnectedPin->QueryInterface(IID_IMemInputPin, (void**)&m_spMemInputPin);
    }

    if (m_spMemInputPin) {
        if (!m_spAllocator) {
            HRESULT hr = m_spMemInputPin->GetAllocator(&m_spAllocator);
            if (FAILED(hr) || !m_spAllocator) {
                CoCreateInstance(CLSID_MemoryAllocator, nullptr, CLSCTX_INPROC_SERVER, IID_IMemAllocator, (void**)&m_spAllocator);
                if (m_spAllocator) {
                    m_spMemInputPin->NotifyAllocator(m_spAllocator.Get(), FALSE);
                }
            }
        }

        if (m_spAllocator) {
            ALLOCATOR_PROPERTIES prop = { 0 };
            prop.cBuffers = 4;
            prop.cbBuffer = 1920 * 1080 * 4;
            prop.cbAlign = 1;
            ALLOCATOR_PROPERTIES actual = { 0 };
            m_spAllocator->SetProperties(&prop, &actual);
            m_spAllocator->Commit();
        }
    }

    m_isStreaming = true;
    m_streamThread = std::thread(&PhoneCamDShowPin::StreamingThreadWorker, this);
}

void PhoneCamDShowPin::StopStreaming() {
    m_isStreaming = false;
    if (m_spAllocator) {
        m_spAllocator->Decommit();
    }
    if (m_streamThread.joinable()) {
        m_streamThread.join();
    }
}

void PhoneCamDShowPin::StreamingThreadWorker() {
    auto frameDuration = std::chrono::milliseconds(33);
    std::vector<uint8_t> frameBuffer;

    while (m_isStreaming) {
        auto start = std::chrono::steady_clock::now();

        // Dynamically ensure allocator and mem input pin are resolved
        if (!m_spMemInputPin && m_spConnectedPin) {
            m_spConnectedPin->QueryInterface(IID_IMemInputPin, (void**)&m_spMemInputPin);
        }

        if (m_spMemInputPin && !m_spAllocator) {
            m_spMemInputPin->GetAllocator(&m_spAllocator);
            if (!m_spAllocator) {
                CoCreateInstance(CLSID_MemoryAllocator, nullptr, CLSCTX_INPROC_SERVER, IID_IMemAllocator, (void**)&m_spAllocator);
                if (m_spAllocator) {
                    m_spMemInputPin->NotifyAllocator(m_spAllocator.Get(), FALSE);
                }
            }
            if (m_spAllocator) {
                ALLOCATOR_PROPERTIES prop = { 0 };
                prop.cBuffers = 4;
                prop.cbBuffer = 1920 * 1080 * 4;
                prop.cbAlign = 1;
                ALLOCATOR_PROPERTIES actual = { 0 };
                m_spAllocator->SetProperties(&prop, &actual);
                m_spAllocator->Commit();
            }
        }

        if (m_spAllocator && m_spMemInputPin) {
            IMediaSample* pSample = nullptr;
            HRESULT hr = m_spAllocator->GetBuffer(&pSample, nullptr, nullptr, 0);
            if (SUCCEEDED(hr) && pSample) {
                BYTE* pData = nullptr;
                pSample->GetPointer(&pData);
                long maxLen = pSample->GetSize();

                PhoneCamSharedHeader header;
                bool hasFrame = m_shmem.ReadLatestFrame(header, frameBuffer);

                if (hasFrame && !frameBuffer.empty() && pData) {
                    size_t copySize = (std::min)((size_t)maxLen, frameBuffer.size());
                    memcpy(pData, frameBuffer.data(), copySize);
                    pSample->SetActualDataLength((long)copySize);
                } else if (pData) {
                    // Generate synthetic test pattern if not streaming
                    m_syntheticGenerator.GenerateNextFrame(frameBuffer, m_frameIndex++);
                    size_t copySize = (std::min)((size_t)maxLen, frameBuffer.size());
                    memcpy(pData, frameBuffer.data(), copySize);
                    pSample->SetActualDataLength((long)copySize);
                }

                REFERENCE_TIME rtStart = m_frameIndex * 333333LL;
                REFERENCE_TIME rtEnd = rtStart + 333333LL;
                pSample->SetTime(&rtStart, &rtEnd);
                pSample->SetSyncPoint(TRUE);

                m_spMemInputPin->Receive(pSample);
                pSample->Release();
            }
        }

        auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - start);
        if (elapsed < frameDuration) {
            std::this_thread::sleep_for(frameDuration - elapsed);
        }
    }
}
