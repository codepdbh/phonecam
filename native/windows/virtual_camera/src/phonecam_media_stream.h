#pragma once

#include "phonecam_virtual_cam.h"
#include "synthetic_frame_generator.h"
#include <queue>
#include <thread>
#include <condition_variable>

class PhoneCamMediaSource;

class PhoneCamMediaStream : public IMFMediaStream {
public:
    PhoneCamMediaStream(PhoneCamMediaSource* pSource, IMFStreamDescriptor* pStreamDesc);
    virtual ~PhoneCamMediaStream();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // IMFMediaEventGenerator
    STDMETHODIMP BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) override;
    STDMETHODIMP EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) override;
    STDMETHODIMP GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) override;
    STDMETHODIMP QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) override;

    // IMFMediaStream
    STDMETHODIMP GetMediaSource(IMFMediaSource** ppMediaSource) override;
    STDMETHODIMP GetStreamDescriptor(IMFStreamDescriptor** ppStreamDescriptor) override;
    STDMETHODIMP RequestSample(IUnknown* pToken) override;

    // Internal Control
    HRESULT Start(const PROPVARIANT* pvarStartPosition);
    HRESULT Stop();
    HRESULT Pause();
    HRESULT Shutdown();
    HRESULT SetMediaType(IMFMediaType* pMediaType);

    // Frame push
    void PushFrame(const uint8_t* pBuffer, size_t size, int64_t timestampHns);
    void EnableTestPattern(bool enable);
    void SetVideoConfig(const PhoneCamVideoConfig& config);

private:
    void DeliveryWorkerThread();
    HRESULT CreateSampleFromFrame(const uint8_t* pData, size_t size, int64_t timestampHns, IMFSample** ppSample);

    std::atomic<ULONG> m_refCount;
    std::mutex m_mutex;
    std::condition_variable m_cv;

    PhoneCamMediaSource* m_pSource;
    ComPtr<IMFStreamDescriptor> m_spStreamDesc;
    ComPtr<IMFMediaEventQueue> m_spEventQueue;
    ComPtr<IMFMediaType> m_spCurrentMediaType;

    PhoneCamVideoConfig m_config;
    bool m_isStreaming;
    bool m_isShutdown;
    bool m_useSyntheticPattern;

    SyntheticFrameGenerator m_syntheticGenerator;
    std::vector<uint8_t> m_latestFrameBuffer;
    bool m_hasNewFrame;
    int64_t m_latestTimestampHns;
    uint64_t m_frameCounter;

    std::queue<ComPtr<IUnknown>> m_sampleRequests;
    std::thread m_deliveryThread;
};
