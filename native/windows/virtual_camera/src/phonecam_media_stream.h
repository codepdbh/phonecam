#pragma once

#include "phonecam_virtual_cam.h"
#include "synthetic_frame_generator.h"
#include "phonecam_shared_memory.h"
#include <queue>
#include <thread>
#include <condition_variable>

class PhoneCamMediaSource;

class PhoneCamMediaStream : public IMFMediaStream2 {
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

    // IMFMediaStream2 (required by Windows Camera Frame Server)
    STDMETHODIMP SetStreamState(MF_STREAM_STATE value) override;
    STDMETHODIMP GetStreamState(MF_STREAM_STATE* value) override;

    // Internal Control
    HRESULT Start(const PROPVARIANT* pvarStartPosition);
    HRESULT Stop();
    HRESULT Pause();
    HRESULT Shutdown();
    HRESULT SetMediaType(IMFMediaType* pMediaType);
    HRESULT SetSampleAllocator(IMFVideoSampleAllocator* allocator);

    // The stream reads frames from the cross-process broker. These controls
    // only affect fallback behavior and the negotiated output format.
    void EnableTestPattern(bool enable);
    void SetVideoConfig(const PhoneCamVideoConfig& config);

private:
    void DeliveryWorkerThread();
    HRESULT CreateSampleFromFrame(const uint8_t* pData, size_t size,
                                  int64_t timestampHns,
                                  const PhoneCamVideoConfig& config,
                                  IMFSample** ppSample);
    // Maps the broker's source-clock frame timestamps onto the QPC-based
    // timeline Media Foundation expects, so real inter-frame spacing (not
    // just "now" on every pull) reaches consumers. See phonecam_media_stream.cpp.
    int64_t ComputeSampleTimestamp(bool realFrame, uint64_t frameIndex, uint64_t sourceTimestampUs);

    std::mutex m_timelineMutex;
    int64_t m_qpcBaseline = 0;
    uint64_t m_sourceBaselineUs = 0;
    uint64_t m_lastFrameIndexSeen = 0;
    int64_t m_lastSampleTimestamp = 0;

    std::atomic<ULONG> m_refCount;
    std::mutex m_mutex;
    std::condition_variable m_cv;

    PhoneCamMediaSource* m_pSource;
    ComPtr<IMFStreamDescriptor> m_spStreamDesc;
    ComPtr<IMFMediaEventQueue> m_spEventQueue;
    ComPtr<IMFMediaType> m_spCurrentMediaType;
    ComPtr<IMFVideoSampleAllocator> m_spSampleAllocator;

    PhoneCamVideoConfig m_config;
    bool m_isStreaming;
    bool m_isShutdown;
    bool m_useSyntheticPattern;
    MF_STREAM_STATE m_streamState = MF_STREAM_STATE_STOPPED;

    SyntheticFrameGenerator m_syntheticGenerator;
    PhoneCamSharedMemory m_frameBroker;
    uint64_t m_frameCounter;

    std::queue<ComPtr<IUnknown>> m_sampleRequests;
    std::thread m_deliveryThread;
};
