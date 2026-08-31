#include "phonecam_frame_converter.h"

#include <iostream>

int main() {
    constexpr uint32_t width = 4, height = 2;
    std::vector<uint8_t> nv12(width * height * 3 / 2, 128);
    PhoneCamSharedMemory writer, reader;
    if (!writer.Initialize(true) || !reader.Initialize(false)) {
        std::cerr << "Broker initialization failed\n"; return 1;
    }
    if (!writer.WriteFrame(width, height, 30, 0, width, width,
                           nv12.data(), nv12.size(), 1234)) {
        std::cerr << "Broker write failed\n"; return 2;
    }
    PhoneCamFrameMetadata metadata{}; std::vector<uint8_t> read;
    if (!reader.ReadLatestFrame(metadata, read) || read != nv12 ||
        metadata.width != width || metadata.height != height) {
        std::cerr << "Broker snapshot mismatch\n"; return 3;
    }
    PhoneCamVideoConfig rgb{width, height, 30, PhoneCamPixelFormat::RGB32};
    std::vector<uint8_t> converted;
    if (!PhoneCamConvertFrame(metadata, read, rgb, converted) ||
        converted.size() != width * height * 4) {
        std::cerr << "NV12 conversion failed\n"; return 4;
    }
    auto stats = writer.GetStats();
    if (stats.publishedFrames != 1 || stats.rejectedFrames != 0 || !stats.frameFresh) {
        std::cerr << "Broker diagnostics mismatch\n"; return 5;
    }
    std::cout << "Frame broker and conversion: PASS\n";
    return 0;
}
