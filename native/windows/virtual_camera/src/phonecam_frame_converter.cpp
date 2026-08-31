#include "phonecam_frame_converter.h"

#include <algorithm>

namespace {
uint8_t Clamp(int value) { return static_cast<uint8_t>((std::max)(0, (std::min)(255, value))); }
void Nv12Pixel(uint8_t y, uint8_t u, uint8_t v, uint8_t& b, uint8_t& g, uint8_t& r) {
    const int c = static_cast<int>(y) - 16;
    const int d = static_cast<int>(u) - 128;
    const int e = static_cast<int>(v) - 128;
    b = Clamp((298 * c + 516 * d + 128) >> 8);
    g = Clamp((298 * c - 100 * d - 208 * e + 128) >> 8);
    r = Clamp((298 * c + 409 * e + 128) >> 8);
}
}

bool PhoneCamConvertFrame(const PhoneCamFrameMetadata& source,
                          const std::vector<uint8_t>& input,
                          const PhoneCamVideoConfig& destination,
                          std::vector<uint8_t>& output) {
    if (input.size() != source.dataSize || !destination.width || !destination.height ||
        (destination.width & 1) || (destination.height & 1)) return false;
    const auto srcFormat = static_cast<PhoneCamBrokerFormat>(source.format);
    if (srcFormat != PhoneCamBrokerFormat::NV12) return false;
    const size_t sourcePixels = static_cast<size_t>(source.width) * source.height;
    if (input.size() != sourcePixels * 3 / 2) return false;

    std::vector<uint8_t> scaled;
    const std::vector<uint8_t>* nv12 = &input;
    if (source.width != destination.width || source.height != destination.height) {
        const size_t destinationPixels = static_cast<size_t>(destination.width) * destination.height;
        scaled.resize(destinationPixels * 3 / 2);
        const uint8_t* sourceY = input.data();
        const uint8_t* sourceUV = input.data() + sourcePixels;
        for (uint32_t row = 0; row < destination.height; ++row) {
            const uint32_t sourceRow = row * source.height / destination.height;
            for (uint32_t col = 0; col < destination.width; ++col) {
                const uint32_t sourceCol = col * source.width / destination.width;
                scaled[static_cast<size_t>(row) * destination.width + col] =
                    sourceY[static_cast<size_t>(sourceRow) * source.width + sourceCol];
            }
        }
        uint8_t* destinationUV = scaled.data() + destinationPixels;
        for (uint32_t row = 0; row < destination.height / 2; ++row) {
            const uint32_t sourceRow = row * (source.height / 2) / (destination.height / 2);
            for (uint32_t col = 0; col < destination.width; col += 2) {
                const uint32_t sourcePair = (col / 2) * (source.width / 2) / (destination.width / 2);
                const size_t src = static_cast<size_t>(sourceRow) * source.width + sourcePair * 2;
                const size_t dst = static_cast<size_t>(row) * destination.width + col;
                destinationUV[dst] = sourceUV[src]; destinationUV[dst + 1] = sourceUV[src + 1];
            }
        }
        nv12 = &scaled;
    }
    if (destination.format == PhoneCamPixelFormat::NV12) { output = *nv12; return true; }
    const size_t pixels = static_cast<size_t>(destination.width) * destination.height;
    const uint8_t* yPlane = nv12->data();
    const uint8_t* uvPlane = nv12->data() + pixels;
    if (destination.format == PhoneCamPixelFormat::RGB32) {
        output.resize(pixels * 4);
        for (uint32_t row = 0; row < destination.height; ++row) {
            for (uint32_t col = 0; col < destination.width; ++col) {
                const size_t yIndex = static_cast<size_t>(row) * destination.width + col;
                const size_t uvIndex = static_cast<size_t>(row / 2) * destination.width + (col & ~1u);
                uint8_t b, g, r;
                Nv12Pixel(yPlane[yIndex], uvPlane[uvIndex], uvPlane[uvIndex + 1], b, g, r);
                const size_t dst = yIndex * 4;
                output[dst] = b; output[dst + 1] = g; output[dst + 2] = r; output[dst + 3] = 255;
            }
        }
        return true;
    }
    if (destination.format == PhoneCamPixelFormat::YUY2) {
        output.resize(pixels * 2);
        for (uint32_t row = 0; row < destination.height; ++row) {
            for (uint32_t col = 0; col < destination.width; col += 2) {
                const size_t yIndex = static_cast<size_t>(row) * destination.width + col;
                const size_t uvIndex = static_cast<size_t>(row / 2) * destination.width + col;
                const size_t dst = yIndex * 2;
                output[dst] = yPlane[yIndex]; output[dst + 1] = uvPlane[uvIndex];
                output[dst + 2] = yPlane[yIndex + 1]; output[dst + 3] = uvPlane[uvIndex + 1];
            }
        }
        return true;
    }
    return false;
}
