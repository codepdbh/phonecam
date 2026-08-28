#include "synthetic_frame_generator.h"
#include <cstring>
#include <algorithm>

SyntheticFrameGenerator::SyntheticFrameGenerator() {
    m_config = PhoneCamVideoConfig();
}

SyntheticFrameGenerator::~SyntheticFrameGenerator() {}

void SyntheticFrameGenerator::Configure(const PhoneCamVideoConfig& config) {
    m_config = config;
}

void SyntheticFrameGenerator::GenerateNextFrame(std::vector<uint8_t>& outBuffer, uint64_t frameIndex) {
    uint32_t frameSize = m_config.GetFrameSizeBytes();
    if (outBuffer.size() != frameSize) {
        outBuffer.resize(frameSize);
    }

    if (m_config.format == PhoneCamPixelFormat::RGB32) {
        GenerateColorBarsRGB32(outBuffer, frameIndex);
    } else {
        GenerateColorBarsNV12(outBuffer, frameIndex);
    }
}

void SyntheticFrameGenerator::GenerateColorBarsNV12(std::vector<uint8_t>& outBuffer, uint64_t frameIndex) {
    uint32_t w = m_config.width;
    uint32_t h = m_config.height;

    // Y plane size: w * h
    // UV plane size: w * (h / 2)
    uint8_t* yPlane = outBuffer.data();
    uint8_t* uvPlane = outBuffer.data() + (w * h);

    // 8 Color Bars (Y, U, V)
    static const struct { uint8_t y, u, v; } kBars[8] = {
        { 235, 128, 128 }, // 100% White
        { 210,  16, 146 }, // Yellow
        { 170, 166,  16 }, // Cyan
        { 145,  54,  34 }, // Green
        { 106, 202, 222 }, // Magenta
        {  81,  90, 240 }, // Red
        {  41, 240, 110 }, // Blue
        {  16, 128, 128 }  // Black
    };

    uint32_t barWidth = w / 8;
    uint32_t topBarsHeight = (h * 3) / 4; // Top 75% for bars

    // Moving indicator position (bouncing bar)
    uint32_t indicatorWidth = w / 16;
    uint32_t indicatorSpeed = 6;
    uint32_t indicatorX = (uint32_t)((frameIndex * indicatorSpeed) % (w - indicatorWidth));

    // 1. Fill Y plane
    for (uint32_t y = 0; y < h; ++y) {
        uint8_t* row = yPlane + (y * w);
        if (y < topBarsHeight) {
            for (uint32_t x = 0; x < w; ++x) {
                uint32_t barIdx = std::min(x / barWidth, 7u);
                row[x] = kBars[barIdx].y;
            }
        } else {
            // Bottom 25%: Dark gray bar with animated moving highlight box
            for (uint32_t x = 0; x < w; ++x) {
                if (x >= indicatorX && x < indicatorX + indicatorWidth) {
                    row[x] = 220; // Bright moving indicator
                } else {
                    row[x] = 40;  // Dark background
                }
            }
        }
    }

    // 2. Fill UV plane (interleaved U, V)
    uint32_t uvHeight = h / 2;
    uint32_t topBarsUvHeight = topBarsHeight / 2;

    for (uint32_t y = 0; y < uvHeight; ++y) {
        uint8_t* uvRow = uvPlane + (y * w);
        if (y < topBarsUvHeight) {
            for (uint32_t x = 0; x < w / 2; ++x) {
                uint32_t origX = x * 2;
                uint32_t barIdx = std::min(origX / barWidth, 7u);
                uvRow[x * 2] = kBars[barIdx].u;
                uvRow[x * 2 + 1] = kBars[barIdx].v;
            }
        } else {
            for (uint32_t x = 0; x < w / 2; ++x) {
                uint32_t origX = x * 2;
                if (origX >= indicatorX && origX < indicatorX + indicatorWidth) {
                    uvRow[x * 2] = 128;
                    uvRow[x * 2 + 1] = 240; // Red tint for moving indicator
                } else {
                    uvRow[x * 2] = 128;
                    uvRow[x * 2 + 1] = 128;
                }
            }
        }
    }
}

void SyntheticFrameGenerator::GenerateColorBarsRGB32(std::vector<uint8_t>& outBuffer, uint64_t frameIndex) {
    uint32_t w = m_config.width;
    uint32_t h = m_config.height;
    uint8_t* ptr = outBuffer.data();

    static const uint32_t kRgbBars[8] = {
        0xFFFFFFFF, // White
        0xFFFFFF00, // Yellow
        0xFF00FFFF, // Cyan
        0xFF00FF00, // Green
        0xFFFF00FF, // Magenta
        0xFFFF0000, // Red
        0xFF0000FF, // Blue
        0xFF000000  // Black
    };

    uint32_t barWidth = w / 8;
    uint32_t topBarsHeight = (h * 3) / 4;
    uint32_t indicatorWidth = w / 16;
    uint32_t indicatorSpeed = 6;
    uint32_t indicatorX = (uint32_t)((frameIndex * indicatorSpeed) % (w - indicatorWidth));

    for (uint32_t y = 0; y < h; ++y) {
        uint32_t* row = reinterpret_cast<uint32_t*>(ptr + y * (w * 4));
        if (y < topBarsHeight) {
            for (uint32_t x = 0; x < w; ++x) {
                uint32_t barIdx = std::min(x / barWidth, 7u);
                row[x] = kRgbBars[barIdx];
            }
        } else {
            for (uint32_t x = 0; x < w; ++x) {
                if (x >= indicatorX && x < indicatorX + indicatorWidth) {
                    row[x] = 0xFFFF3333; // Bright cyan/red indicator
                } else {
                    row[x] = 0xFF222222; // Dark background
                }
            }
        }
    }
}
