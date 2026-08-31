#pragma once

#include <unknwn.h>
#include <ks.h>
#include <ksproxy.h>
#include "phonecam_virtual_cam.h"
#include "phonecam_media_stream.h"
#include <mfidl.h>

class PhoneCamMediaSource : public IMFMediaSourceEx,
                            public IMFGetService,
                            public IKsControl,
                            public IMFSampleAllocatorControl {
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

    // IMFMediaSourceEx (required by Windows Camera Frame Server)
    STDMETHODIMP GetSourceAttributes(IMFAttributes** ppAttributes) override;
    STDMETHODIMP GetStreamAttributes(DWORD streamIdentifier, IMFAttributes** ppAttributes) override;
    STDMETHODIMP SetD3DManager(IUnknown* manager) override;

    // IMFSampleAllocatorControl
    STDMETHODIMP SetDefaultAllocator(DWORD outputStreamId, IUnknown* allocator) override;
    STDMETHODIMP GetAllocatorUsage(DWORD outputStreamId, DWORD* inputStreamId,
                                   MFSampleAllocatorUsage* usage) override;

    // IMFGetService
    STDMETHODIMP GetService(REFGUID guidService, REFIID riid, void** ppv) override;

    // IKsControl is mandatory even when no custom controls are exposed.
    STDMETHODIMP KsProperty(PKSPROPERTY property, ULONG propertyLength,
                            PVOID data, ULONG dataLength, ULONG* bytesReturned) override;
    STDMETHODIMP KsMethod(PKSMETHOD method, ULONG methodLength,
                          PVOID data, ULONG dataLength, ULONG* bytesReturned) override;
    STDMETHODIMP KsEvent(PKSEVENT event, ULONG eventLength,
                         PVOID data, ULONG dataLength, ULONG* bytesReturned) override;

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
    ComPtr<IMFAttributes> m_spAttributes;
    ComPtr<IMFAttributes> m_spStreamAttributes;
    ComPtr<IUnknown> m_spD3DManager;
    PhoneCamSharedMemory m_diagnostics;

    bool m_isShutdown;
    bool m_streamAnnounced = false;
    PhoneCamVideoConfig m_config;

    static PhoneCamMediaSource* s_pGlobalInstance;
};
