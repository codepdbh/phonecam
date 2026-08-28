#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <dshow.h>
#include <dvdmedia.h>
#include <wrl/client.h>
#include <algorithm>
#include <atomic>
#include <thread>
#include <mutex>
#include <vector>
#include "phonecam_shared_memory.h"
#include "synthetic_frame_generator.h"

using Microsoft::WRL::ComPtr;

class PhoneCamDShowPin;

class PhoneCamDShowFilter : public IBaseFilter, public IAMFilterMiscFlags {
public:
    PhoneCamDShowFilter();
    virtual ~PhoneCamDShowFilter();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // IPersist
    STDMETHODIMP GetClassID(CLSID* pClassID) override;

    // IMediaFilter
    STDMETHODIMP Stop() override;
    STDMETHODIMP Pause() override;
    STDMETHODIMP Run(REFERENCE_TIME tStart) override;
    STDMETHODIMP GetState(DWORD dwMilliSecsTimeout, FILTER_STATE* State) override;
    STDMETHODIMP SetSyncSource(IReferenceClock* pClock) override;
    STDMETHODIMP GetSyncSource(IReferenceClock** ppClock) override;

    // IBaseFilter
    STDMETHODIMP EnumPins(IEnumPins** ppEnum) override;
    STDMETHODIMP FindPin(LPCWSTR Id, IPin** ppPin) override;
    STDMETHODIMP QueryFilterInfo(FILTER_INFO* pInfo) override;
    STDMETHODIMP JoinFilterGraph(IFilterGraph* pGraph, LPCWSTR pName) override;
    STDMETHODIMP QueryVendorInfo(LPWSTR* pVendorInfo) override;

    // IAMFilterMiscFlags
    STDMETHODIMP_(ULONG) GetMiscFlags() override;

    FILTER_STATE GetCurrentState() const { return m_state; }
    IFilterGraph* GetFilterGraph() const { return m_pGraph; }

private:
    std::atomic<ULONG> m_refCount;
    std::mutex m_mutex;
    FILTER_STATE m_state;
    IFilterGraph* m_pGraph;
    IReferenceClock* m_pClock;
    std::wstring m_name;
    ComPtr<PhoneCamDShowPin> m_spPin;
};

class PhoneCamDShowPin : public IPin, public IKsPropertySet, public IAMStreamConfig {
public:
    PhoneCamDShowPin(PhoneCamDShowFilter* pFilter);
    virtual ~PhoneCamDShowPin();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // IPin
    STDMETHODIMP Connect(IPin* pReceivePin, const AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP ReceiveConnection(IPin* pConnector, const AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP Disconnect() override;
    STDMETHODIMP ConnectedTo(IPin** pPin) override;
    STDMETHODIMP ConnectionMediaType(AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP QueryPinInfo(PIN_INFO* pInfo) override;
    STDMETHODIMP QueryDirection(PIN_DIRECTION* pPinDir) override;
    STDMETHODIMP QueryId(LPWSTR* Id) override;
    STDMETHODIMP QueryAccept(const AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP EnumMediaTypes(IEnumMediaTypes** ppEnum) override;
    STDMETHODIMP QueryInternalConnections(IPin** apPin, ULONG* nPin) override;
    STDMETHODIMP EndOfStream() override;
    STDMETHODIMP BeginFlush() override;
    STDMETHODIMP EndFlush() override;
    STDMETHODIMP NewSegment(REFERENCE_TIME tStart, REFERENCE_TIME tStop, double dRate) override;

    // IKsPropertySet
    STDMETHODIMP Set(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData) override;
    STDMETHODIMP Get(REFGUID guidPropSet, DWORD dwPropID, LPVOID pInstanceData, DWORD cbInstanceData, LPVOID pPropData, DWORD cbPropData, DWORD* pcbReturned) override;
    STDMETHODIMP QuerySupported(REFGUID guidPropSet, DWORD dwPropID, DWORD* pTypeSupport) override;

    // IAMStreamConfig
    STDMETHODIMP SetFormat(AM_MEDIA_TYPE* pmt) override;
    STDMETHODIMP GetFormat(AM_MEDIA_TYPE** ppmt) override;
    STDMETHODIMP GetNumberOfCapabilities(int* piCount, int* piSize) override;
    STDMETHODIMP GetStreamCaps(int iIndex, AM_MEDIA_TYPE** ppmt, BYTE* pSCC) override;

    // Streaming Thread Control
    void StartStreaming();
    void StopStreaming();

private:
    void StreamingThreadWorker();
    HRESULT CreateDefaultMediaType(AM_MEDIA_TYPE* pmt, int width, int height, int fps, bool isRGB24);

    std::atomic<ULONG> m_refCount;
    std::mutex m_mutex;
    PhoneCamDShowFilter* m_pFilter;

    ComPtr<IPin> m_spConnectedPin;
    ComPtr<IMemInputPin> m_spMemInputPin;
    ComPtr<IMemAllocator> m_spAllocator;
    AM_MEDIA_TYPE m_currentMediaType;
    bool m_hasMediaType;

    std::atomic<bool> m_isStreaming;
    std::thread m_streamThread;

    PhoneCamSharedMemory m_shmem;
    SyntheticFrameGenerator m_syntheticGenerator;
    uint64_t m_frameIndex;
};
