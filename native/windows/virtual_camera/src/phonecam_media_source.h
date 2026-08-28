#pragma once

#include "phonecam_virtual_cam.h"
#include "phonecam_media_stream.h"
#include <mfidl.h>

class PhoneCamMediaSource : public IMFMediaSource, public IMFGetService {
public:
    PhoneCamMediaSource();
    virtual ~PhoneCamMediaSource();

    // IUnknown
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    // IMFMediaEventGenerator
    STDMETHODIMP BeginGetEvent(IMFAsyncCallback* pCallback, IUnknown* punkState) override;
    STDMETHODIMP EndGetEvent(IMFAsyncResult* pResult, IMFMediaEvent** ppEvent) override;
    STDMETHODIMP GetEvent(DWORD dwFlags, IMFMediaEvent** ppEvent) override;
    STDMETHODIMP QueueEvent(MediaEventType met, REFGUID guidExtendedType, HRESULT hrStatus, const PROPVARIANT* pvValue) override;

    // IMFMediaSource
    STDMETHODIMP GetCharacteristics(DWORD* pdwCharacteristics) override;
    STDMETHODIMP CreatePresentationDescriptor(IMFPresentationDescriptor** ppPresentationDescriptor) override;
    STDMETHODIMP Start(IMFPresentationDescriptor* pPresentationDescriptor, const GUID* pguidTimeFormat, const PROPVARIANT* pvarStartPosition) override;
    STDMETHODIMP Stop() override;
    STDMETHODIMP Pause() override;
    STDMETHODIMP Shutdown() override;

    // IMFGetService
    STDMETHODIMP GetService(REFGUID guidService, REFIID riid, void** ppv) override;

    // Stream frame push
    void PushFrame(const uint8_t* pBuffer, size_t size, int64_t timestampHns);
    void EnableTestPattern(bool enable);
    void SetVideoConfig(const PhoneCamVideoConfig& config);

    static PhoneCamMediaSource* GetGlobalInstance();

private:
    HRESULT CreateDescriptors();
    HRESULT AddMediaType(IMFStreamDescriptor* pStreamDesc, UINT32 width, UINT32 height, UINT32 fps, const GUID& subType);

    std::atomic<ULONG> m_refCount;
    std::mutex m_mutex;

    ComPtr<IMFMediaEventQueue> m_spEventQueue;
    ComPtr<IMFPresentationDescriptor> m_spPresentationDesc;
    ComPtr<IMFStreamDescriptor> m_spStreamDesc;
    ComPtr<PhoneCamMediaStream> m_spStream;

    bool m_isShutdown;
    PhoneCamVideoConfig m_config;

    static PhoneCamMediaSource* s_pGlobalInstance;
};
