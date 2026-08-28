#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <cstdint>
#include <vector>
#include <mutex>

#define PHONECAM_SHMEM_NAME L"Local\\PhoneCam_VirtualCam_SharedMem_v2"
#define PHONECAM_MUTEX_NAME L"Local\\PhoneCam_VirtualCam_Mutex_v2"
#define PHONECAM_MAGIC 0x50484E43 // "PHNC"
#define PHONECAM_MAX_PAYLOAD (1920 * 1080 * 4 + 4096) // Max 1080p RGB32 + header

#pragma pack(push, 1)
struct PhoneCamSharedHeader {
    uint32_t magic;         // PHONECAM_MAGIC
    uint32_t width;
    uint32_t height;
    uint32_t fps;
    uint32_t format;        // 0=NV12, 1=I420, 2=RGB32, 3=RGB24
    uint64_t frameIndex;
    uint64_t timestampUs;
    uint32_t dataSize;
    uint32_t isConnected;   // 1 = active phone stream, 0 = test pattern
};
#pragma pack(pop)

class PhoneCamSharedMemory {
public:
    PhoneCamSharedMemory() 
        : m_hMapFile(nullptr), 
          m_pBuf(nullptr), 
          m_hMutex(nullptr),
          m_isWriter(false) {}

    ~PhoneCamSharedMemory() {
        Close();
    }

    bool Initialize(bool isWriter) {
        m_isWriter = isWriter;
        size_t totalSize = sizeof(PhoneCamSharedHeader) + PHONECAM_MAX_PAYLOAD;

        m_hMutex = CreateMutexW(nullptr, FALSE, PHONECAM_MUTEX_NAME);

        if (isWriter) {
            m_hMapFile = CreateFileMappingW(
                INVALID_HANDLE_VALUE,
                nullptr,
                PAGE_READWRITE,
                0,
                static_cast<DWORD>(totalSize),
                PHONECAM_SHMEM_NAME
            );
        } else {
            m_hMapFile = OpenFileMappingW(
                FILE_MAP_READ | FILE_MAP_WRITE,
                FALSE,
                PHONECAM_SHMEM_NAME
            );
            if (!m_hMapFile) {
                // If writer not yet opened, create it as reader/fallback
                m_hMapFile = CreateFileMappingW(
                    INVALID_HANDLE_VALUE,
                    nullptr,
                    PAGE_READWRITE,
                    0,
                    static_cast<DWORD>(totalSize),
                    PHONECAM_SHMEM_NAME
                );
            }
        }

        if (!m_hMapFile) {
            return false;
        }

        m_pBuf = (uint8_t*)MapViewOfFile(
            m_hMapFile,
            FILE_MAP_ALL_ACCESS,
            0,
            0,
            totalSize
        );

        if (!m_pBuf) {
            return false;
        }

        if (isWriter) {
            PhoneCamSharedHeader* header = (PhoneCamSharedHeader*)m_pBuf;
            header->magic = PHONECAM_MAGIC;
            header->width = 1920;
            header->height = 1080;
            header->fps = 30;
            header->format = 0; // NV12
            header->frameIndex = 0;
            header->timestampUs = 0;
            header->dataSize = 0;
            header->isConnected = 0;
        }

        return true;
    }

    void Close() {
        if (m_pBuf) {
            UnmapViewOfFile(m_pBuf);
            m_pBuf = nullptr;
        }
        if (m_hMapFile) {
            CloseHandle(m_hMapFile);
            m_hMapFile = nullptr;
        }
        if (m_hMutex) {
            CloseHandle(m_hMutex);
            m_hMutex = nullptr;
        }
    }

    bool WriteFrame(uint32_t width, uint32_t height, uint32_t fps, uint32_t format, const uint8_t* pData, size_t size, uint64_t timestampUs) {
        if (!m_pBuf || !pData || size == 0 || size > PHONECAM_MAX_PAYLOAD) return false;

        if (m_hMutex) {
            WaitForSingleObject(m_hMutex, 50);
        }

        PhoneCamSharedHeader* header = (PhoneCamSharedHeader*)m_pBuf;
        header->magic = PHONECAM_MAGIC;
        header->width = width;
        header->height = height;
        header->fps = fps;
        header->format = format;
        header->frameIndex++;
        header->timestampUs = timestampUs;
        header->dataSize = static_cast<uint32_t>(size);
        header->isConnected = 1;

        uint8_t* payload = m_pBuf + sizeof(PhoneCamSharedHeader);
        memcpy(payload, pData, size);

        if (m_hMutex) {
            ReleaseMutex(m_hMutex);
        }

        return true;
    }

    bool ReadLatestFrame(PhoneCamSharedHeader& outHeader, std::vector<uint8_t>& outBuffer) {
        if (!m_pBuf) {
            if (!Initialize(false)) return false;
        }

        if (m_hMutex) {
            WaitForSingleObject(m_hMutex, 20);
        }

        PhoneCamSharedHeader* header = (PhoneCamSharedHeader*)m_pBuf;
        if (header->magic != PHONECAM_MAGIC || header->dataSize == 0 || header->dataSize > PHONECAM_MAX_PAYLOAD) {
            if (m_hMutex) ReleaseMutex(m_hMutex);
            return false;
        }

        outHeader = *header;
        outBuffer.resize(header->dataSize);
        uint8_t* payload = m_pBuf + sizeof(PhoneCamSharedHeader);
        memcpy(outBuffer.data(), payload, header->dataSize);

        if (m_hMutex) {
            ReleaseMutex(m_hMutex);
        }

        return true;
    }

private:
    HANDLE m_hMapFile;
    uint8_t* m_pBuf;
    HANDLE m_hMutex;
    bool m_isWriter;
};
