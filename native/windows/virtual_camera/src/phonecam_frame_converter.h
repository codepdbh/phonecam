#pragma once

#include "phonecam_shared_memory.h"
#include "phonecam_virtual_cam.h"

bool PhoneCamConvertFrame(const PhoneCamFrameMetadata& source,
                          const std::vector<uint8_t>& input,
                          const PhoneCamVideoConfig& destination,
                          std::vector<uint8_t>& output);
