#pragma once

#include "phonecam_virtual_cam.h"
#include <vector>
#include <cstdint>

class SyntheticFrameGenerator {
public:
    SyntheticFrameGenerator();
    ~SyntheticFrameGenerator();

    void Configure(const PhoneCamVideoConfig& config);
    void GenerateNextFrame(std::vector<uint8_t>& outBuffer, uint64_t frameIndex);

private:
    void GenerateColorBarsNV12(std::vector<uint8_t>& outBuffer, uint64_t frameIndex);
    void GenerateColorBarsRGB32(std::vector<uint8_t>& outBuffer, uint64_t frameIndex);

    PhoneCamVideoConfig m_config;
};
