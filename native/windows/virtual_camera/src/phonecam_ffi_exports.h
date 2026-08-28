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
PHONECAM_API int PhoneCam_StartVirtualCamera();
PHONECAM_API int PhoneCam_StopVirtualCamera();
PHONECAM_API int PhoneCam_DisposeVirtualCamera();
PHONECAM_API int PhoneCam_SetVideoFormat(int width, int height, int fps, int fourcc);
PHONECAM_API int PhoneCam_PushVideoFrame(const uint8_t* pBuffer, size_t size, int64_t timestampUs);
PHONECAM_API int PhoneCam_EnableTestPattern(int enable);
PHONECAM_API int PhoneCam_GetStatus();
