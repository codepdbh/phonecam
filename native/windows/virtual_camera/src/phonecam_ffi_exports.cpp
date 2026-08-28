#define PHONECAM_VIRTUAL_CAM_EXPORTS
#include "phonecam_ffi_exports.h"
#include "phonecam_virtual_cam.h"
#include "phonecam_media_source.h"
#include "phonecam_dshow_filter.h"
#include "phonecam_shared_memory.h"
#include <mfvirtualcamera.h>
#include <initguid.h>
#include <atomic>
#include <iostream>
#include <shlwapi.h>

#pragma comment(lib, "shlwapi.lib")

// {E4D8A9F1-3142-4A2D-A483-E18F54687791}
DEFINE_GUID(CLSID_PhoneCamMediaSource,
    0xe4d8a9f1, 0x3142, 0x4a2d, 0xa4, 0x83, 0xe1, 0x8f, 0x54, 0x68, 0x77, 0x91);

// {860BB310-5D01-11d0-BD3B-00A0C911CE86} - CLSID_VideoInputDeviceCategory (DirectShow)
DEFINE_GUID(CLSID_VideoInputDeviceCategory_GUID,
    0x860bb310, 0x5d01, 0x11d0, 0xbd, 0x3b, 0x00, 0xa0, 0xc9, 0x11, 0xce, 0x86);

static std::atomic<bool> s_isInitialized(false);
static std::atomic<bool> s_isStarted(false);
static ComPtr<IMFVirtualCamera> s_spVirtualCamera;
static ComPtr<PhoneCamMediaSource> s_spMediaSource;
static HMODULE s_hModule = nullptr;
static PhoneCamSharedMemory s_writerShmem;
static PhoneCamVideoConfig s_currentConfig;

// Dynamically resolve MFCreateVirtualCamera
typedef HRESULT (STDAPICALLTYPE *MFCreateVirtualCameraFn)(
    MFVirtualCameraType type,
    MFVirtualCameraLifetime lifetime,
    MFVirtualCameraAccess access,
    LPCWSTR pszFriendlyName,
    LPCWSTR pszDeviceID,
    const GUID *pCategories,
    ULONG cCategoryCount,
    IMFVirtualCamera **ppVirtualCamera
);

static HRESULT RegisterComServer() {
    WCHAR dllPath[MAX_PATH] = { 0 };
    if (!s_hModule) {
        s_hModule = GetModuleHandleW(L"PhoneCamMediaSource.dll");
    }
    if (!s_hModule || !GetModuleFileNameW(s_hModule, dllPath, MAX_PATH)) {
        return E_FAIL;
    }

    WCHAR clsidStr[64] = { 0 };
    StringFromGUID2(CLSID_PhoneCamMediaSource, clsidStr, 64);

    // 1. Register InprocServer32 in HKCU\Software\Classes\CLSID\{CLSID}
    WCHAR subKey[256];
    wsprintfW(subKey, L"Software\\Classes\\CLSID\\%s", clsidStr);

    HKEY hKey = nullptr;
    LONG res = RegCreateKeyExW(HKEY_CURRENT_USER, subKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hKey, nullptr);
    if (res == ERROR_SUCCESS) {
        const wchar_t* friendlyName = L"PhoneCam Virtual Camera";
        RegSetValueExW(hKey, nullptr, 0, REG_SZ, (const BYTE*)friendlyName, (DWORD)((wcslen(friendlyName) + 1) * sizeof(wchar_t)));

        HKEY hSubKey = nullptr;
        res = RegCreateKeyExW(hKey, L"InprocServer32", 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hSubKey, nullptr);
        if (res == ERROR_SUCCESS) {
            RegSetValueExW(hSubKey, nullptr, 0, REG_SZ, (const BYTE*)dllPath, (DWORD)((wcslen(dllPath) + 1) * sizeof(wchar_t)));
            const wchar_t* threading = L"Both";
            RegSetValueExW(hSubKey, L"ThreadingModel", 0, REG_SZ, (const BYTE*)threading, (DWORD)((wcslen(threading) + 1) * sizeof(wchar_t)));
            RegCloseKey(hSubKey);
        }
        RegCloseKey(hKey);
    }

    // DirectShow Video Capture Source FilterData binary signature
    static const uint8_t filterData[] = {
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x30, 0x70, 0x69, 0x6e, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x30, 0x74, 0x79, 0x70, 0x00, 0x00, 0x00, 0x00, 0x76, 0x69, 0x64, 0x73,
        0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xaa, 0x00, 0x38, 0x9b, 0x71, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };

    // 2. Register in DirectShow Video Input Category so Chrome, Meet, Zoom, OBS list it immediately
    WCHAR dshowKey[384];
    wsprintfW(dshowKey, L"Software\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", clsidStr);
    HKEY hDshow = nullptr;
    res = RegCreateKeyExW(HKEY_CURRENT_USER, dshowKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hDshow, nullptr);
    if (res == ERROR_SUCCESS) {
        const wchar_t* cameraName = L"PhoneCam Virtual Camera";
        RegSetValueExW(hDshow, L"FriendlyName", 0, REG_SZ, (const BYTE*)cameraName, (DWORD)((wcslen(cameraName) + 1) * sizeof(wchar_t)));
        RegSetValueExW(hDshow, L"CLSID", 0, REG_SZ, (const BYTE*)clsidStr, (DWORD)((wcslen(clsidStr) + 1) * sizeof(wchar_t)));
        const wchar_t* devPath = L"\\\\?\\phonecam#virtualcamera#0001";
        RegSetValueExW(hDshow, L"DevicePath", 0, REG_SZ, (const BYTE*)devPath, (DWORD)((wcslen(devPath) + 1) * sizeof(wchar_t)));
        RegSetValueExW(hDshow, L"FilterData", 0, REG_BINARY, filterData, (DWORD)sizeof(filterData));
        RegCloseKey(hDshow);
    }

    // 3. Also register 32-bit WoW6432Node
    WCHAR wowDshowKey[384];
    wsprintfW(wowDshowKey, L"Software\\Classes\\WOW6432Node\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", clsidStr);
    HKEY hWowDshow = nullptr;
    res = RegCreateKeyExW(HKEY_CURRENT_USER, wowDshowKey, 0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &hWowDshow, nullptr);
    if (res == ERROR_SUCCESS) {
        const wchar_t* cameraName = L"PhoneCam Virtual Camera";
        RegSetValueExW(hWowDshow, L"FriendlyName", 0, REG_SZ, (const BYTE*)cameraName, (DWORD)((wcslen(cameraName) + 1) * sizeof(wchar_t)));
        RegSetValueExW(hWowDshow, L"CLSID", 0, REG_SZ, (const BYTE*)clsidStr, (DWORD)((wcslen(clsidStr) + 1) * sizeof(wchar_t)));
        const wchar_t* devPath = L"\\\\?\\phonecam#virtualcamera#0001";
        RegSetValueExW(hWowDshow, L"DevicePath", 0, REG_SZ, (const BYTE*)devPath, (DWORD)((wcslen(devPath) + 1) * sizeof(wchar_t)));
        RegSetValueExW(hWowDshow, L"FilterData", 0, REG_BINARY, filterData, (DWORD)sizeof(filterData));
        RegCloseKey(hWowDshow);
    }

    return S_OK;
}

static HRESULT UnregisterComServer() {
    WCHAR clsidStr[64] = { 0 };
    StringFromGUID2(CLSID_PhoneCamMediaSource, clsidStr, 64);

    WCHAR subKey[256];
    wsprintfW(subKey, L"Software\\Classes\\CLSID\\%s", clsidStr);
    RegDeleteTreeW(HKEY_CURRENT_USER, subKey);

    WCHAR dshowKey[384];
    wsprintfW(dshowKey, L"Software\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", clsidStr);
    RegDeleteTreeW(HKEY_CURRENT_USER, dshowKey);

    return S_OK;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
        case DLL_PROCESS_ATTACH:
            s_hModule = hModule;
            DisableThreadLibraryCalls(hModule);
            RegisterComServer();
            break;
        case DLL_PROCESS_DETACH:
            PhoneCam_DisposeVirtualCamera();
            break;
    }
    return TRUE;
}

PHONECAM_API int PhoneCam_InitializeVirtualCamera() {
    if (s_isInitialized) {
        return PHONECAM_STATUS_OK;
    }

    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) {
        return PHONECAM_STATUS_WIN32_ERROR;
    }

    RegisterComServer();
    s_writerShmem.Initialize(true);

    s_currentConfig.width = 1920;
    s_currentConfig.height = 1080;
    s_currentConfig.fps = 30;
    s_currentConfig.format = PhoneCamPixelFormat::NV12;

    try {
        s_spMediaSource = new PhoneCamMediaSource();
        s_isInitialized = true;
        return PHONECAM_STATUS_OK;
    } catch (...) {
        return PHONECAM_STATUS_WIN32_ERROR;
    }
}

PHONECAM_API int PhoneCam_StartVirtualCamera() {
    if (!s_isInitialized) {
        int initRes = PhoneCam_InitializeVirtualCamera();
        if (initRes != PHONECAM_STATUS_OK) {
            return initRes;
        }
    }

    if (s_isStarted) {
        return PHONECAM_STATUS_OK;
    }

    RegisterComServer();

    if (s_spMediaSource) {
        try {
            ComPtr<IMFPresentationDescriptor> spPD;
            s_spMediaSource->CreatePresentationDescriptor(&spPD);
            if (spPD) {
                s_spMediaSource->Start(spPD.Get(), nullptr, nullptr);
            }
        } catch (...) {}
    }

    s_isStarted = true;
    return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_StopVirtualCamera() {
    if (!s_isStarted) {
        return PHONECAM_STATUS_OK;
    }

    try {
        if (s_spVirtualCamera) {
            s_spVirtualCamera->Stop();
        }

        if (s_spMediaSource) {
            s_spMediaSource->Stop();
        }
    } catch (...) {}

    s_isStarted = false;
    return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_DisposeVirtualCamera() {
    PhoneCam_StopVirtualCamera();

    try {
        if (s_spVirtualCamera) {
            s_spVirtualCamera->Shutdown();
            s_spVirtualCamera.Reset();
        }

        if (s_spMediaSource) {
            s_spMediaSource->Shutdown();
            s_spMediaSource.Reset();
        }

        if (s_isInitialized) {
            MFShutdown();
            s_isInitialized = false;
        }

        s_writerShmem.Close();
    } catch (...) {}

    return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_SetVideoFormat(int width, int height, int fps, int fourcc) {
    s_currentConfig.width = width > 0 ? width : 1920;
    s_currentConfig.height = height > 0 ? height : 1080;
    s_currentConfig.fps = fps > 0 ? fps : 30;

    switch (fourcc) {
        case 1:
            s_currentConfig.format = PhoneCamPixelFormat::I420;
            break;
        case 2:
            s_currentConfig.format = PhoneCamPixelFormat::RGB32;
            break;
        case 3:
            s_currentConfig.format = PhoneCamPixelFormat::YUY2;
            break;
        case 0:
        default:
            s_currentConfig.format = PhoneCamPixelFormat::NV12;
            break;
    }

    if (s_spMediaSource) {
        s_spMediaSource->SetVideoConfig(s_currentConfig);
    }
    return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_PushVideoFrame(const uint8_t* pBuffer, size_t size, int64_t timestampUs) {
    if (!pBuffer || size == 0) {
        return PHONECAM_STATUS_INVALID_PARAM;
    }

    // 1. Push to cross-process shared memory for DirectShow apps (Meet, Zoom, OBS, etc.)
    uint32_t fmt = static_cast<uint32_t>(s_currentConfig.format);
    s_writerShmem.WriteFrame(s_currentConfig.width, s_currentConfig.height, s_currentConfig.fps, fmt, pBuffer, size, timestampUs);

    // 2. Push to local Media Foundation Media Source
    if (s_spMediaSource) {
        int64_t timestampHns = timestampUs * 10;
        s_spMediaSource->PushFrame(pBuffer, size, timestampHns);
        return PHONECAM_STATUS_OK;
    }

    return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_EnableTestPattern(int enable) {
    if (s_spMediaSource) {
        s_spMediaSource->EnableTestPattern(enable != 0);
        return PHONECAM_STATUS_OK;
    }
    return PHONECAM_STATUS_NOT_INITIALIZED;
}

PHONECAM_API int PhoneCam_GetStatus() {
    if (!s_isInitialized) return PHONECAM_STATUS_NOT_INITIALIZED;
    if (s_isStarted) return 1;
    return 0;
}

// Dual COM Class Factory (Supports DirectShow IBaseFilter & Media Foundation IMFMediaSource)
class PhoneCamClassFactory : public IClassFactory {
public:
    PhoneCamClassFactory() : m_refCount(1) {}

    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) {
            *ppv = static_cast<IClassFactory*>(this);
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

    STDMETHODIMP CreateInstance(IUnknown* pUnkOuter, REFIID riid, void** ppv) override {
        if (pUnkOuter != nullptr) return CLASS_E_NOAGGREGATION;
        if (!ppv) return E_POINTER;

        // Check if caller requests DirectShow filter interfaces
        if (riid == IID_IBaseFilter || riid == IID_IMediaFilter || riid == IID_IPersist || riid == IID_IAMFilterMiscFlags) {
            PhoneCamDShowFilter* pFilter = new PhoneCamDShowFilter();
            return pFilter->QueryInterface(riid, ppv);
        }

        // Check if caller requests Media Foundation interfaces
        if (riid == IID_IMFMediaSource || riid == IID_IMFMediaEventGenerator || riid == IID_IMFGetService) {
            PhoneCamMediaSource* pSource = PhoneCamMediaSource::GetGlobalInstance();
            if (!pSource) {
                pSource = new PhoneCamMediaSource();
            }
            return pSource->QueryInterface(riid, ppv);
        }

        // Default to DirectShow IBaseFilter (most common for Chrome / OBS / Zoom)
        PhoneCamDShowFilter* pFilter = new PhoneCamDShowFilter();
        HRESULT hr = pFilter->QueryInterface(riid, ppv);
        if (SUCCEEDED(hr)) return hr;

        PhoneCamMediaSource* pSource = PhoneCamMediaSource::GetGlobalInstance();
        if (!pSource) {
            pSource = new PhoneCamMediaSource();
        }
        return pSource->QueryInterface(riid, ppv);
    }

    STDMETHODIMP LockServer(BOOL fLock) override { return S_OK; }

private:
    std::atomic<ULONG> m_refCount;
};

STDAPI DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv) {
    if (IsEqualCLSID(rclsid, CLSID_PhoneCamMediaSource)) {
        ComPtr<PhoneCamClassFactory> spFactory = new PhoneCamClassFactory();
        return spFactory->QueryInterface(riid, ppv);
    }
    return CLASS_E_CLASSNOTAVAILABLE;
}

STDAPI DllRegisterServer() {
    return RegisterComServer();
}

STDAPI DllUnregisterServer() {
    return UnregisterComServer();
}

STDAPI DllCanUnloadNow() {
    return (s_isStarted || s_isInitialized) ? S_FALSE : S_OK;
}
