#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <strsafe.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <wrl/client.h>
#include <cstdint>
#include <string>
#include <vector>
#include <mutex>
#include <atomic>

using Microsoft::WRL::ComPtr;

// GUID for PhoneCam Virtual Camera Media Source
// {E4D8A9F1-3142-4A2D-A483-E18F54687791}
EXTERN_C const GUID CLSID_PhoneCamMediaSource;

// {E4D8A9F3-3142-4A2D-A483-E18F54687791}. DirectShow intentionally uses a
// different COM identity so activation through IUnknown is deterministic.
EXTERN_C const GUID CLSID_PhoneCamDShowSource;

// {E4D8A9F2-3142-4A2D-A483-E18F54687791}
EXTERN_C const GUID GUID_PhoneCamVirtualCameraCategory;

void PhoneCamComObjectCreated();
void PhoneCamComObjectDestroyed();

enum class PhoneCamPixelFormat {
    NV12,
    I420,
    RGB32,
    YUY2
};

struct PhoneCamVideoConfig {
    uint32_t width = 1920;
    uint32_t height = 1080;
    uint32_t fps = 30;
    PhoneCamPixelFormat format = PhoneCamPixelFormat::NV12;

    uint32_t GetFrameSizeBytes() const {
        switch (format) {
            case PhoneCamPixelFormat::NV12:
            case PhoneCamPixelFormat::I420:
                return (width * height * 3) / 2;
            case PhoneCamPixelFormat::RGB32:
                return width * height * 4;
            case PhoneCamPixelFormat::YUY2:
                return width * height * 2;
        }
        return (width * height * 3) / 2;
    }

    uint64_t GetFrameDurationHns() const {
        return 10000000ULL / (fps > 0 ? fps : 30);
    }
};
