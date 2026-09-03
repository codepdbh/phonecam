#pragma once

#include <windows.h>
#include <cstdint>
#include <cstddef>

#ifdef PHONECAM_VIRTUAL_CAM_EXPORTS
#define PHONECAM_API extern "C" __declspec(dllexport)
#else
#define PHONECAM_API extern "C" __declspec(dllimport)
#endif

// COM DLL standard entrypoints
extern "C" {
    PHONECAM_API HRESULT STDAPICALLTYPE DllGetClassObject(REFCLSID rclsid, REFIID riid, void** ppv);
    PHONECAM_API HRESULT STDAPICALLTYPE DllCanUnloadNow();
    PHONECAM_API HRESULT STDAPICALLTYPE DllRegisterServer();
    PHONECAM_API HRESULT STDAPICALLTYPE DllUnregisterServer();
}

// Status Codes
#define PHONECAM_STATUS_OK 0
#define PHONECAM_STATUS_NOT_INITIALIZED -1
#define PHONECAM_STATUS_ALREADY_INITIALIZED -2
#define PHONECAM_STATUS_REGISTRATION_FAILED -3
#define PHONECAM_STATUS_INVALID_PARAM -4
#define PHONECAM_STATUS_WIN32_ERROR -5

PHONECAM_API int PhoneCam_InitializeVirtualCamera();
// Capability probe: 1 if this Windows install can host the Media Foundation
// Frame Server virtual camera (mfsensorgroup.dll present, Windows 11 22H2+),
// 0 otherwise. Safe to call before Initialize/Start — does not create or
// register anything, so the desktop app can show accurate "what will this
// look like on your Windows version" messaging up front.
PHONECAM_API int PhoneCam_ProbeFrameServerSupport();
PHONECAM_API int PhoneCam_StartVirtualCamera();
PHONECAM_API int PhoneCam_StopVirtualCamera();
PHONECAM_API int PhoneCam_DisposeVirtualCamera();
PHONECAM_API int PhoneCam_SetVideoFormat(int width, int height, int fps, int fourcc);
PHONECAM_API int PhoneCam_PushVideoFrame(const uint8_t* pBuffer, size_t size, int64_t timestampUs);
PHONECAM_API int PhoneCam_PushNV12Frame(int width, int height, int fps, const uint8_t* pBuffer, size_t size, int64_t timestampUs);
PHONECAM_API int PhoneCam_EnableTestPattern(int enable);
// Last FPS applied via PhoneCam_SetVideoFormat (defaults to 30 before the
// first call). Lets frame producers stamp real per-frame metadata instead of
// hardcoding a value that may not match what the user actually selected.
PHONECAM_API int PhoneCam_GetConfiguredFps();
PHONECAM_API int PhoneCam_GetStatus();
// 1 if the Media Foundation Frame Server virtual camera (Windows 11 22H2+)
// is active; 0 when running in DirectShow-only mode (Windows 10, or older
// Windows 11) or before Start() has run. The DirectShow source still works
// either way — this only tells the caller which discovery paths will see it.
PHONECAM_API int PhoneCam_IsFrameServerAvailable();
// 1 if the driver's COM classes are registered machine-wide (i.e. the
// installer has run), 0 otherwise.
PHONECAM_API int PhoneCam_IsRegistered();
PHONECAM_API int64_t PhoneCam_GetLastHResult();
PHONECAM_API int PhoneCam_GetLastErrorStage();
PHONECAM_API uint64_t PhoneCam_GetPublishedFrameCount();
PHONECAM_API uint64_t PhoneCam_GetRejectedFrameCount();
