#define PHONECAM_VIRTUAL_CAM_EXPORTS
#include "phonecam_ffi_exports.h"
#include "phonecam_dshow_filter.h"
#include "phonecam_media_source.h"
#include "phonecam_media_source_activate.h"
#include "phonecam_shared_memory.h"
#include "phonecam_virtual_cam.h"

#include <mfvirtualcamera.h>
#include <initguid.h>
#include <atomic>
#include <shlwapi.h>

// Media Foundation source: {E4D8A9F1-3142-4A2D-A483-E18F54687791}
DEFINE_GUID(CLSID_PhoneCamMediaSource, 0xe4d8a9f1, 0x3142, 0x4a2d, 0xa4, 0x83, 0xe1, 0x8f, 0x54, 0x68, 0x77, 0x91);
// DirectShow source: {E4D8A9F3-3142-4A2D-A483-E18F54687791}
DEFINE_GUID(CLSID_PhoneCamDShowSource, 0xe4d8a9f3, 0x3142, 0x4a2d, 0xa4, 0x83, 0xe1, 0x8f, 0x54, 0x68, 0x77, 0x91);
DEFINE_GUID(GUID_PhoneCamVirtualCameraCategory, 0xe4d8a9f2, 0x3142, 0x4a2d, 0xa4, 0x83, 0xe1, 0x8f, 0x54, 0x68, 0x77, 0x91);

namespace {
std::atomic<bool> g_initialized{false};
std::atomic<bool> g_started{false};
std::atomic<HRESULT> g_lastError{S_OK};
std::atomic<int> g_lastStage{0};
std::atomic<LONG> g_serverLocks{0};
std::atomic<LONG> g_comObjects{0};
ComPtr<IMFVirtualCamera> g_virtualCamera;
PhoneCamSharedMemory g_writer;
PhoneCamVideoConfig g_config{1920, 1080, 30, PhoneCamPixelFormat::NV12};
HMODULE g_module = nullptr;

using MFCreateVirtualCameraFn = HRESULT(STDAPICALLTYPE*)(
    MFVirtualCameraType, MFVirtualCameraLifetime, MFVirtualCameraAccess,
    LPCWSTR, LPCWSTR, const GUID*, ULONG, IMFVirtualCamera**);

HRESULT SetStringValue(HKEY key, const wchar_t* name, const wchar_t* value) {
    return HRESULT_FROM_WIN32(RegSetValueExW(key, name, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(value),
        static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t))));
}

HRESULT RegisterClsid(HKEY root, const GUID& clsid, const wchar_t* name, const wchar_t* dllPath) {
    wchar_t id[64]{}; StringFromGUID2(clsid, id, 64);
    wchar_t path[256]{}; swprintf_s(path, L"Software\\Classes\\CLSID\\%s", id);
    HKEY clsidKey = nullptr;
    LONG result = RegCreateKeyExW(root, path, 0, nullptr, 0, KEY_WRITE, nullptr, &clsidKey, nullptr);
    if (result != ERROR_SUCCESS) return HRESULT_FROM_WIN32(result);
    HRESULT hr = SetStringValue(clsidKey, nullptr, name);
    HKEY serverKey = nullptr;
    if (SUCCEEDED(hr)) {
        result = RegCreateKeyExW(clsidKey, L"InprocServer32", 0, nullptr, 0, KEY_WRITE, nullptr, &serverKey, nullptr);
        hr = HRESULT_FROM_WIN32(result);
    }
    if (SUCCEEDED(hr)) hr = SetStringValue(serverKey, nullptr, dllPath);
    if (SUCCEEDED(hr)) hr = SetStringValue(serverKey, L"ThreadingModel", L"Both");
    if (serverKey) RegCloseKey(serverKey); RegCloseKey(clsidKey); return hr;
}

HRESULT RegisterComServer(HKEY root) {
    wchar_t dllPath[MAX_PATH]{};
    if (!g_module || !GetModuleFileNameW(g_module, dllPath, MAX_PATH)) return HRESULT_FROM_WIN32(GetLastError());
    HRESULT hr = RegisterClsid(root, CLSID_PhoneCamMediaSource, L"PhoneCam Media Foundation Source", dllPath);
    if (FAILED(hr)) return hr;
    hr = RegisterClsid(root, CLSID_PhoneCamDShowSource, L"PhoneCam DirectShow Source", dllPath);
    if (FAILED(hr)) return hr;

    REGPINTYPES pinType{&MEDIATYPE_Video, &MEDIASUBTYPE_NULL};
    REGFILTERPINS2 pin{}; pin.dwFlags = REG_PINFLAG_B_OUTPUT;
    pin.nMediaTypes = 1; pin.lpMediaType = &pinType;
    REGFILTER2 filter{}; filter.dwVersion = 2; filter.dwMerit = MERIT_DO_NOT_USE;
    filter.cPins2 = 1; filter.rgPins2 = &pin;
    ComPtr<IFilterMapper2> mapper;
    hr = CoCreateInstance(CLSID_FilterMapper2, nullptr, CLSCTX_INPROC_SERVER,
                          IID_PPV_ARGS(&mapper));
    if (SUCCEEDED(hr)) {
        hr = mapper->RegisterFilter(CLSID_PhoneCamDShowSource,
            L"PhoneCam Virtual Camera (DirectShow)", nullptr,
            &CLSID_VideoInputDeviceCategory, nullptr, &filter);
    }

    // Remove the legacy ambiguous DirectShow registration that used the MF CLSID.
    wchar_t path[384]{};
    wchar_t legacyId[64]{}; StringFromGUID2(CLSID_PhoneCamMediaSource, legacyId, 64);
    swprintf_s(path, L"Software\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", legacyId);
    RegDeleteTreeW(root, path);
    return hr;
}

HRESULT UnregisterComServer(HKEY root) {
    wchar_t id[64]{}, path[384]{};
    for (const GUID* clsid : {&CLSID_PhoneCamMediaSource, &CLSID_PhoneCamDShowSource}) {
        StringFromGUID2(*clsid, id, 64);
        swprintf_s(path, L"Software\\Classes\\CLSID\\%s", id); RegDeleteTreeW(root, path);
        swprintf_s(path, L"Software\\Classes\\CLSID\\{860BB310-5D01-11d0-BD3B-00A0C911CE86}\\Instance\\%s", id);
        RegDeleteTreeW(root, path);
    }
    ComPtr<IFilterMapper2> mapper;
    if (SUCCEEDED(CoCreateInstance(CLSID_FilterMapper2, nullptr, CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&mapper)))) {
        mapper->UnregisterFilter(&CLSID_VideoInputDeviceCategory, nullptr,
                                 CLSID_PhoneCamDShowSource);
    }
    return S_OK;
}

int StoreError(HRESULT hr, int status = PHONECAM_STATUS_WIN32_ERROR) {
    g_lastError = hr; return SUCCEEDED(hr) ? PHONECAM_STATUS_OK : status;
}

bool IsMachineRegistered() {
    wchar_t id[64]{}, path[256]{}; StringFromGUID2(CLSID_PhoneCamMediaSource, id, 64);
    swprintf_s(path, L"Software\\Classes\\CLSID\\%s\\InprocServer32", id);
    HKEY key = nullptr; const LONG result = RegOpenKeyExW(HKEY_LOCAL_MACHINE, path, 0, KEY_READ, &key);
    if (key) RegCloseKey(key); return result == ERROR_SUCCESS;
}

enum class ComClass { MediaFoundation, DirectShow };
class PhoneCamClassFactory final : public IClassFactory {
public:
    explicit PhoneCamClassFactory(ComClass type) : type_(type) { PhoneCamComObjectCreated(); }
    ~PhoneCamClassFactory() { PhoneCamComObjectDestroyed(); }
    STDMETHODIMP QueryInterface(REFIID riid, void** ppv) override {
        if (!ppv) return E_POINTER; *ppv = nullptr;
        if (riid == IID_IUnknown || riid == IID_IClassFactory) { *ppv = static_cast<IClassFactory*>(this); AddRef(); return S_OK; }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { ULONG count = --refs_; if (!count) delete this; return count; }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID riid, void** ppv) override {
        if (outer) return CLASS_E_NOAGGREGATION; if (!ppv) return E_POINTER;
        if (type_ == ComClass::MediaFoundation) {
            auto* activate = new PhoneCamMediaSourceActivate(); HRESULT hr = activate->QueryInterface(riid, ppv); activate->Release(); return hr;
        }
        auto* filter = new PhoneCamDShowFilter(); HRESULT hr = filter->QueryInterface(riid, ppv); filter->Release(); return hr;
    }
    STDMETHODIMP LockServer(BOOL lock) override { if (lock) ++g_serverLocks; else --g_serverLocks; return S_OK; }
private:
    std::atomic<ULONG> refs_{1}; ComClass type_;
};
}

void PhoneCamComObjectCreated() { ++g_comObjects; }
void PhoneCamComObjectDestroyed() { --g_comObjects; }

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) { g_module = module; DisableThreadLibraryCalls(module); }
    return TRUE;
}

PHONECAM_API int PhoneCam_InitializeVirtualCamera() {
    if (g_initialized) return PHONECAM_STATUS_OK;
    HRESULT hr = MFStartup(MF_VERSION); if (FAILED(hr)) return StoreError(hr);
    if (!IsMachineRegistered()) {
        MFShutdown();
        return StoreError(HRESULT_FROM_WIN32(ERROR_ELEVATION_REQUIRED),
                          PHONECAM_STATUS_REGISTRATION_FAILED);
    }
    if (!g_writer.Initialize(true)) { hr = HRESULT_FROM_WIN32(GetLastError()); MFShutdown(); return StoreError(hr); }
    g_initialized = true; g_lastError = S_OK; return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_StartVirtualCamera() {
    int status = PhoneCam_InitializeVirtualCamera(); if (status != PHONECAM_STATUS_OK) return status;
    if (g_started) return PHONECAM_STATUS_OK;
    // MFCreateVirtualCamera is exported by mfsensorgroup.dll on current
    // Windows 11 builds (not mfplat.dll as older prototypes assumed).
    HMODULE mf = GetModuleHandleW(L"mfsensorgroup.dll");
    if (!mf) mf = LoadLibraryW(L"mfsensorgroup.dll");
    if (!mf) return StoreError(HRESULT_FROM_WIN32(GetLastError()));
    auto create = reinterpret_cast<MFCreateVirtualCameraFn>(GetProcAddress(mf, "MFCreateVirtualCamera"));
    if (!create) return StoreError(HRESULT_FROM_WIN32(ERROR_PROC_NOT_FOUND));
    wchar_t sourceId[64]{}; StringFromGUID2(CLSID_PhoneCamMediaSource, sourceId, 64);
    HRESULT hr = create(MFVirtualCameraType_SoftwareCameraSource, MFVirtualCameraLifetime_Session,
                        MFVirtualCameraAccess_CurrentUser, L"PhoneCam Virtual Camera", sourceId,
                        nullptr, 0, &g_virtualCamera);
    if (FAILED(hr)) { g_lastStage = 1; return StoreError(hr); }
    hr = g_virtualCamera->Start(nullptr);
    if (FAILED(hr)) { g_lastStage = 2; g_virtualCamera->Shutdown(); g_virtualCamera.Reset(); return StoreError(hr); }
    g_started = true; g_lastError = S_OK; g_lastStage = 0; return PHONECAM_STATUS_OK;
}

PHONECAM_API int PhoneCam_StopVirtualCamera() {
    if (!g_started) return PHONECAM_STATUS_OK;
    HRESULT hr = g_virtualCamera ? g_virtualCamera->Stop() : S_OK;
    g_started = false; return StoreError(hr);
}
PHONECAM_API int PhoneCam_DisposeVirtualCamera() {
    PhoneCam_StopVirtualCamera();
    if (g_virtualCamera) { g_virtualCamera->Shutdown(); g_virtualCamera.Reset(); }
    g_writer.Close();
    if (g_initialized) { MFShutdown(); g_initialized = false; }
    return PHONECAM_STATUS_OK;
}
PHONECAM_API int PhoneCam_SetVideoFormat(int width, int height, int fps, int fourcc) {
    if (width <= 0 || height <= 0 || width > static_cast<int>(PHONECAM_MAX_WIDTH) ||
        height > static_cast<int>(PHONECAM_MAX_HEIGHT) || fps <= 0) return PHONECAM_STATUS_INVALID_PARAM;
    g_config.width = width; g_config.height = height; g_config.fps = fps;
    if (fourcc == 0) g_config.format = PhoneCamPixelFormat::NV12;
    else if (fourcc == 1) g_config.format = PhoneCamPixelFormat::I420;
    else if (fourcc == 2) g_config.format = PhoneCamPixelFormat::RGB32;
    else if (fourcc == 3) g_config.format = PhoneCamPixelFormat::YUY2;
    else return PHONECAM_STATUS_INVALID_PARAM;
    return PHONECAM_STATUS_OK;
}
PHONECAM_API int PhoneCam_PushVideoFrame(const uint8_t* buffer, size_t size, int64_t timestampUs) {
    if (!g_initialized || !buffer || !size) return PHONECAM_STATUS_INVALID_PARAM;
    const uint32_t strideY = g_config.format == PhoneCamPixelFormat::RGB32 ? g_config.width * 4 :
                             g_config.format == PhoneCamPixelFormat::YUY2 ? g_config.width * 2 : g_config.width;
    const uint32_t strideUV = g_config.format == PhoneCamPixelFormat::NV12 ? g_config.width : 0;
    const bool ok = g_writer.WriteFrame(g_config.width, g_config.height, g_config.fps,
        static_cast<uint32_t>(g_config.format), strideY, strideUV, buffer, size, timestampUs);
    return ok ? PHONECAM_STATUS_OK : PHONECAM_STATUS_INVALID_PARAM;
}
PHONECAM_API int PhoneCam_PushNV12Frame(int width, int height, int fps,
                                        const uint8_t* buffer, size_t size, int64_t timestampUs) {
    if (!g_initialized) { const int result = PhoneCam_InitializeVirtualCamera(); if (result != 0) return result; }
    const size_t expected = static_cast<size_t>(width) * height * 3 / 2;
    if (!buffer || size != expected) return PHONECAM_STATUS_INVALID_PARAM;
    return g_writer.WriteFrame(width, height, fps, 0, width, width, buffer, size, timestampUs)
        ? PHONECAM_STATUS_OK : PHONECAM_STATUS_INVALID_PARAM;
}
PHONECAM_API int PhoneCam_EnableTestPattern(int enable) {
    if (!g_initialized) return PHONECAM_STATUS_NOT_INITIALIZED;
    g_writer.SetTestPatternEnabled(enable != 0); return PHONECAM_STATUS_OK;
}
PHONECAM_API int PhoneCam_GetStatus() {
    if (!g_initialized) return PHONECAM_STATUS_NOT_INITIALIZED; return g_started ? 1 : 0;
}
PHONECAM_API int64_t PhoneCam_GetLastHResult() { return static_cast<int64_t>(g_lastError.load()); }
PHONECAM_API int PhoneCam_GetLastErrorStage() { return g_lastStage.load(); }
PHONECAM_API uint64_t PhoneCam_GetPublishedFrameCount() { return g_writer.GetStats().publishedFrames; }
PHONECAM_API uint64_t PhoneCam_GetRejectedFrameCount() { return g_writer.GetStats().rejectedFrames; }

STDAPI DllGetClassObject(REFCLSID clsid, REFIID riid, void** ppv) {
    if (!ppv) return E_POINTER; *ppv = nullptr;
    ComClass type;
    if (clsid == CLSID_PhoneCamMediaSource) type = ComClass::MediaFoundation;
    else if (clsid == CLSID_PhoneCamDShowSource) type = ComClass::DirectShow;
    else return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new PhoneCamClassFactory(type); HRESULT hr = factory->QueryInterface(riid, ppv); factory->Release(); return hr;
}
STDAPI DllCanUnloadNow() {
    return g_comObjects.load() == 0 && g_serverLocks.load() == 0 && !g_started.load()
        ? S_OK : S_FALSE;
}
STDAPI DllRegisterServer() {
    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    // Remove development-era per-user registrations before publishing the
    // machine-wide source used by Frame Server.
    UnregisterComServer(HKEY_CURRENT_USER);
    HRESULT hr = RegisterComServer(HKEY_LOCAL_MACHINE); g_lastError = hr;
    if (init == S_OK) CoUninitialize(); return hr;
}
STDAPI DllUnregisterServer() {
    HRESULT init = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    UnregisterComServer(HKEY_CURRENT_USER); HRESULT hr = UnregisterComServer(HKEY_LOCAL_MACHINE);
    if (init == S_OK) CoUninitialize(); return hr;
}
