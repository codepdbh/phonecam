#pragma once

#ifndef NOMINMAX
#define NOMINMAX
#endif

#include <windows.h>
#include <strsafe.h>
#include <cstdint>
#include <cstring>
#include <vector>

// Lock-free, double-buffered broker. The producer writes the inactive slot and
// publishes it atomically, so consumers never observe partial frames.
#define PHONECAM_SHMEM_NAME L"Local\\PhoneCam_VirtualCam_FrameBroker_v4"
#define PHONECAM_MAGIC 0x50484E43u
#define PHONECAM_BROKER_VERSION 4u
#define PHONECAM_SLOT_COUNT 2u
#define PHONECAM_MAX_WIDTH 3840u
#define PHONECAM_MAX_HEIGHT 2160u
#define PHONECAM_MAX_PAYLOAD ((PHONECAM_MAX_WIDTH * PHONECAM_MAX_HEIGHT * 3u) / 2u)

enum class PhoneCamBrokerFormat : uint32_t { NV12 = 0, I420 = 1, RGB32 = 2, YUY2 = 3 };

struct PhoneCamFrameMetadata {
    uint32_t width;
    uint32_t height;
    uint32_t fps;
    uint32_t format;
    uint32_t strideY;
    uint32_t strideUV;
    uint32_t dataSize;
    uint32_t reserved;
    uint64_t frameIndex;
    uint64_t timestampUs;
    uint64_t heartbeatTickMs;
};

struct PhoneCamBrokerHeader {
    uint32_t magic;
    uint32_t version;
    uint32_t headerSize;
    uint32_t slotSize;
    volatile LONG publishedSlot;
    volatile LONG producerConnected;
    volatile LONG producerPid;
    volatile LONG testPatternEnabled;
    volatile LONG64 publishedFrames;
    volatile LONG64 rejectedFrames;
    volatile LONG64 sampleRequests;
    volatile LONG64 samplesProduced;
    volatile LONG64 streamStarts;
    volatile LONG64 streamStateChanges;
    volatile LONG64 streamConstructed;
    volatile LONG64 sourceGetAttributes;
    volatile LONG64 streamGetAttributes;
    volatile LONG64 presentationDescriptors;
    volatile LONG64 allocatorUsageQueries;
    volatile LONG64 allocatorsSet;
    volatile LONG64 sourceStarts;
};

struct PhoneCamSlotHeader {
    volatile LONG sequence; // odd while writing, even when stable
    uint32_t reserved;
    PhoneCamFrameMetadata metadata;
};

struct PhoneCamBrokerStats {
    bool producerConnected = false;
    bool frameFresh = false;
    uint32_t producerPid = 0;
    uint64_t publishedFrames = 0;
    uint64_t rejectedFrames = 0;
    uint64_t sampleRequests = 0;
    uint64_t samplesProduced = 0;
    uint64_t streamStarts = 0;
    uint64_t streamStateChanges = 0;
    uint64_t streamConstructed = 0;
    uint64_t sourceGetAttributes = 0;
    uint64_t streamGetAttributes = 0;
    uint64_t presentationDescriptors = 0;
    uint64_t allocatorUsageQueries = 0;
    uint64_t allocatorsSet = 0;
    uint64_t sourceStarts = 0;
    uint64_t lastFrameIndex = 0;
    uint64_t lastHeartbeatTickMs = 0;
};

class PhoneCamSharedMemory {
public:
    PhoneCamSharedMemory() = default;
    ~PhoneCamSharedMemory() { Close(); }
    PhoneCamSharedMemory(const PhoneCamSharedMemory&) = delete;
    PhoneCamSharedMemory& operator=(const PhoneCamSharedMemory&) = delete;

    bool Initialize(bool isWriter) {
        Close();
        m_isWriter = isWriter;
        wchar_t programData[MAX_PATH]{};
        const DWORD programDataLength = GetEnvironmentVariableW(
            L"ProgramData", programData, ARRAYSIZE(programData));
        if (programDataLength > 0 && programDataLength < ARRAYSIZE(programData)) {
            wchar_t brokerPath[MAX_PATH]{};
            if (SUCCEEDED(StringCchPrintfW(
                    brokerPath, ARRAYSIZE(brokerPath),
                    L"%s\\PhoneCam\\frame-broker-v4.bin", programData))) {
                m_hBackingFile = CreateFileW(
                    brokerPath, GENERIC_READ | GENERIC_WRITE,
                    FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                    isWriter ? OPEN_ALWAYS : OPEN_EXISTING,
                    FILE_ATTRIBUTE_NORMAL, nullptr);
                if (m_hBackingFile != INVALID_HANDLE_VALUE && isWriter) {
                    LARGE_INTEGER size{};
                    size.QuadPart = static_cast<LONGLONG>(BrokerSize());
                    if (!SetFilePointerEx(m_hBackingFile, size, nullptr, FILE_BEGIN) ||
                        !SetEndOfFile(m_hBackingFile)) {
                        CloseHandle(m_hBackingFile);
                        m_hBackingFile = INVALID_HANDLE_VALUE;
                    }
                }
                if (m_hBackingFile != INVALID_HANDLE_VALUE) {
                    m_hMapFile = CreateFileMappingW(
                        m_hBackingFile, nullptr, PAGE_READWRITE, 0,
                        static_cast<DWORD>(BrokerSize()), nullptr);
                }
            }
        }

        // Unit tests and unpackaged development runs retain a same-session
        // fallback. Installed camera operation uses the ProgramData mapping so
        // the user app and Frame Server/LOCAL SERVICE see identical pages.
        if (!m_hMapFile) {
            if (m_hBackingFile != INVALID_HANDLE_VALUE) {
                CloseHandle(m_hBackingFile);
                m_hBackingFile = INVALID_HANDLE_VALUE;
            }
            if (isWriter) {
                m_hMapFile = CreateFileMappingW(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE,
                                                0, static_cast<DWORD>(BrokerSize()),
                                                PHONECAM_SHMEM_NAME);
            } else {
                m_hMapFile = OpenFileMappingW(
                    FILE_MAP_READ | FILE_MAP_WRITE, FALSE, PHONECAM_SHMEM_NAME);
            }
        }
        if (!m_hMapFile) return false;
        m_pBuf = static_cast<uint8_t*>(MapViewOfFile(
            m_hMapFile, FILE_MAP_ALL_ACCESS,
            0, 0, BrokerSize()));
        if (!m_pBuf) {
            CloseHandle(m_hMapFile);
            m_hMapFile = nullptr;
            return false;
        }
        auto* header = Header();
        if (isWriter) {
            std::memset(m_pBuf, 0, BrokerSize());
            header->magic = PHONECAM_MAGIC;
            header->version = PHONECAM_BROKER_VERSION;
            header->headerSize = sizeof(PhoneCamBrokerHeader);
            header->slotSize = static_cast<uint32_t>(SlotSize());
            header->publishedSlot = -1;
            header->producerPid = static_cast<LONG>(GetCurrentProcessId());
            header->producerConnected = 1;
            header->testPatternEnabled = 1;
        } else if (!ValidateHeader()) {
            Close();
            return false;
        }
        return true;
    }

    void Close() {
        if (m_pBuf && m_isWriter && ValidateHeader()) {
            InterlockedExchange(&Header()->producerConnected, 0);
            InterlockedExchange(&Header()->producerPid, 0);
        }
        if (m_pBuf) UnmapViewOfFile(m_pBuf);
        if (m_hMapFile) CloseHandle(m_hMapFile);
        if (m_hBackingFile != INVALID_HANDLE_VALUE) CloseHandle(m_hBackingFile);
        m_pBuf = nullptr;
        m_hMapFile = nullptr;
        m_hBackingFile = INVALID_HANDLE_VALUE;
        m_isWriter = false;
    }

    bool WriteFrame(uint32_t width, uint32_t height, uint32_t fps,
                    uint32_t format, uint32_t strideY, uint32_t strideUV,
                    const uint8_t* data, size_t size, uint64_t timestampUs) {
        if (!m_pBuf || !m_isWriter || !ValidateFrame(width, height, format, data, size)) {
            if (m_pBuf && ValidateHeader()) InterlockedIncrement64(&Header()->rejectedFrames);
            return false;
        }
        auto* header = Header();
        const LONG current = InterlockedCompareExchange(&header->publishedSlot, 0, 0);
        const uint32_t target = current == 0 ? 1u : 0u;
        auto* slot = Slot(target);
        LONG sequence = InterlockedIncrement(&slot->sequence);
        if ((sequence & 1) == 0) InterlockedIncrement(&slot->sequence);
        slot->metadata = {width, height, fps ? fps : 30, format, strideY, strideUV,
                          static_cast<uint32_t>(size), 0,
                          static_cast<uint64_t>(InterlockedIncrement64(&header->publishedFrames)),
                          timestampUs, GetTickCount64()};
        std::memcpy(Payload(slot), data, size);
        MemoryBarrier();
        InterlockedIncrement(&slot->sequence);
        InterlockedExchange(&header->producerConnected, 1);
        InterlockedExchange(&header->producerPid, static_cast<LONG>(GetCurrentProcessId()));
        InterlockedExchange(&header->testPatternEnabled, 0);
        InterlockedExchange(&header->publishedSlot, static_cast<LONG>(target));
        return true;
    }

    bool ReadLatestFrame(PhoneCamFrameMetadata& metadata, std::vector<uint8_t>& buffer) {
        if (!EnsureReader() || !ValidateHeader()) return false;
        auto* header = Header();
        if (InterlockedCompareExchange(&header->producerConnected, 0, 0) == 0) return false;
        for (int attempt = 0; attempt < 3; ++attempt) {
            const LONG index = InterlockedCompareExchange(&header->publishedSlot, 0, 0);
            if (index < 0 || index >= static_cast<LONG>(PHONECAM_SLOT_COUNT)) return false;
            auto* slot = Slot(static_cast<uint32_t>(index));
            const LONG before = InterlockedCompareExchange(&slot->sequence, 0, 0);
            if (before & 1) continue;
            const PhoneCamFrameMetadata candidate = slot->metadata;
            if (!ValidateMetadata(candidate)) return false;
            buffer.resize(candidate.dataSize);
            std::memcpy(buffer.data(), Payload(slot), candidate.dataSize);
            MemoryBarrier();
            const LONG after = InterlockedCompareExchange(&slot->sequence, 0, 0);
            if (before == after && !(after & 1)) {
                metadata = candidate;
                return GetTickCount64() - metadata.heartbeatTickMs <= 2000;
            }
        }
        return false;
    }

    PhoneCamBrokerStats GetStats() {
        PhoneCamBrokerStats stats;
        if (!EnsureReader() || !ValidateHeader()) return stats;
        auto* header = Header();
        stats.producerConnected = InterlockedCompareExchange(&header->producerConnected, 0, 0) != 0;
        stats.producerPid = static_cast<uint32_t>(InterlockedCompareExchange(&header->producerPid, 0, 0));
        stats.publishedFrames = static_cast<uint64_t>(InterlockedCompareExchange64(&header->publishedFrames, 0, 0));
        stats.rejectedFrames = static_cast<uint64_t>(InterlockedCompareExchange64(&header->rejectedFrames, 0, 0));
        stats.sampleRequests = static_cast<uint64_t>(InterlockedCompareExchange64(&header->sampleRequests, 0, 0));
        stats.samplesProduced = static_cast<uint64_t>(InterlockedCompareExchange64(&header->samplesProduced, 0, 0));
        stats.streamStarts = static_cast<uint64_t>(InterlockedCompareExchange64(&header->streamStarts, 0, 0));
        stats.streamStateChanges = static_cast<uint64_t>(InterlockedCompareExchange64(&header->streamStateChanges, 0, 0));
        stats.streamConstructed = static_cast<uint64_t>(InterlockedCompareExchange64(&header->streamConstructed, 0, 0));
        stats.sourceGetAttributes = static_cast<uint64_t>(InterlockedCompareExchange64(&header->sourceGetAttributes, 0, 0));
        stats.streamGetAttributes = static_cast<uint64_t>(InterlockedCompareExchange64(&header->streamGetAttributes, 0, 0));
        stats.presentationDescriptors = static_cast<uint64_t>(InterlockedCompareExchange64(&header->presentationDescriptors, 0, 0));
        stats.allocatorUsageQueries = static_cast<uint64_t>(InterlockedCompareExchange64(&header->allocatorUsageQueries, 0, 0));
        stats.allocatorsSet = static_cast<uint64_t>(InterlockedCompareExchange64(&header->allocatorsSet, 0, 0));
        stats.sourceStarts = static_cast<uint64_t>(InterlockedCompareExchange64(&header->sourceStarts, 0, 0));
        const LONG index = InterlockedCompareExchange(&header->publishedSlot, 0, 0);
        if (index >= 0 && index < static_cast<LONG>(PHONECAM_SLOT_COUNT)) {
            const auto metadata = Slot(static_cast<uint32_t>(index))->metadata;
            stats.lastFrameIndex = metadata.frameIndex;
            stats.lastHeartbeatTickMs = metadata.heartbeatTickMs;
            stats.frameFresh = stats.producerConnected && GetTickCount64() - metadata.heartbeatTickMs <= 2000;
        }
        return stats;
    }

    void SetTestPatternEnabled(bool enabled) {
        if (m_pBuf && ValidateHeader()) InterlockedExchange(&Header()->testPatternEnabled, enabled ? 1 : 0);
    }

    void MarkSampleRequest() {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&Header()->sampleRequests);
    }

    void MarkSampleProduced() {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&Header()->samplesProduced);
    }

    void MarkStreamStart() {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&Header()->streamStarts);
    }

    void MarkStreamStateChange() {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&Header()->streamStateChanges);
    }

    void MarkStreamConstructed() {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&Header()->streamConstructed);
    }

    void MarkSourceGetAttributes() { Increment(&PhoneCamBrokerHeader::sourceGetAttributes); }
    void MarkStreamGetAttributes() { Increment(&PhoneCamBrokerHeader::streamGetAttributes); }
    void MarkPresentationDescriptor() { Increment(&PhoneCamBrokerHeader::presentationDescriptors); }
    void MarkAllocatorUsageQuery() { Increment(&PhoneCamBrokerHeader::allocatorUsageQueries); }
    void MarkAllocatorSet() { Increment(&PhoneCamBrokerHeader::allocatorsSet); }
    void MarkSourceStart() { Increment(&PhoneCamBrokerHeader::sourceStarts); }

private:
    void Increment(volatile LONG64 PhoneCamBrokerHeader::*field) {
        if (EnsureReader() && ValidateHeader())
            InterlockedIncrement64(&(Header()->*field));
    }
    static constexpr size_t Align64(size_t value) { return (value + 63u) & ~size_t(63u); }
    static constexpr size_t SlotSize() { return Align64(sizeof(PhoneCamSlotHeader)) + PHONECAM_MAX_PAYLOAD; }
    static constexpr size_t BrokerSize() { return Align64(sizeof(PhoneCamBrokerHeader)) + PHONECAM_SLOT_COUNT * SlotSize(); }
    PhoneCamBrokerHeader* Header() const { return reinterpret_cast<PhoneCamBrokerHeader*>(m_pBuf); }
    PhoneCamSlotHeader* Slot(uint32_t index) const {
        return reinterpret_cast<PhoneCamSlotHeader*>(m_pBuf + Align64(sizeof(PhoneCamBrokerHeader)) + index * SlotSize());
    }
    static uint8_t* Payload(PhoneCamSlotHeader* slot) {
        return reinterpret_cast<uint8_t*>(slot) + Align64(sizeof(PhoneCamSlotHeader));
    }
    bool EnsureReader() { return m_pBuf != nullptr || Initialize(false); }
    bool ValidateHeader() const {
        if (!m_pBuf) return false;
        const auto* h = Header();
        return h->magic == PHONECAM_MAGIC && h->version == PHONECAM_BROKER_VERSION &&
               h->headerSize == sizeof(PhoneCamBrokerHeader) && h->slotSize == SlotSize();
    }
    static bool ValidateMetadata(const PhoneCamFrameMetadata& m) {
        return m.width > 0 && m.width <= PHONECAM_MAX_WIDTH && m.height > 0 &&
               m.height <= PHONECAM_MAX_HEIGHT && m.dataSize > 0 &&
               m.dataSize <= PHONECAM_MAX_PAYLOAD &&
               m.format <= static_cast<uint32_t>(PhoneCamBrokerFormat::YUY2);
    }
    static bool ValidateFrame(uint32_t width, uint32_t height, uint32_t format,
                              const uint8_t* data, size_t size) {
        if (!data || width == 0 || height == 0 || width > PHONECAM_MAX_WIDTH ||
            height > PHONECAM_MAX_HEIGHT || size == 0 || size > PHONECAM_MAX_PAYLOAD) return false;
        size_t expected = 0;
        if (format == 0 || format == 1) expected = static_cast<size_t>(width) * height * 3 / 2;
        else if (format == 2) expected = static_cast<size_t>(width) * height * 4;
        else if (format == 3) expected = static_cast<size_t>(width) * height * 2;
        else return false;
        return size == expected;
    }

    HANDLE m_hMapFile = nullptr;
    HANDLE m_hBackingFile = INVALID_HANDLE_VALUE;
    uint8_t* m_pBuf = nullptr;
    bool m_isWriter = false;
};
