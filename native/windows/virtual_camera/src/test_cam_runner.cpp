#include <iostream>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <thread>
#include <vector>
#include <windows.h>
#include "phonecam_ffi_exports.h"

int main() {
    std::cout << "=======================================================\n";
    std::cout << "   PhoneCam Virtual Camera - Standalone Test Runner    \n";
    std::cout << "=======================================================\n\n";

    std::cout << "[1/4] Initializing Media Foundation Virtual Camera...\n";
    int initRes = PhoneCam_InitializeVirtualCamera();
    std::cout << "      Initialize Result: " << initRes << "\n";

    std::cout << "[2/4] Setting Video Format: 1920x1080 @ 30 FPS (NV12)...\n";
    int formatRes = PhoneCam_SetVideoFormat(1920, 1080, 30, 0);
    std::cout << "      Set Format Result: " << formatRes << "\n";

    std::cout << "[3/4] Enabling Synthetic Test Pattern (SMPTE Color Bars + Sync)...\n";
    PhoneCam_EnableTestPattern(1);

    std::cout << "[4/4] Starting Virtual Camera ('PhoneCam Virtual Camera')...\n";
    int startRes = PhoneCam_StartVirtualCamera();
    std::cout << "      Start Result: " << startRes << "\n\n";
    if (startRes != PHONECAM_STATUS_OK) {
        std::cout << "      HRESULT: 0x" << std::hex << PhoneCam_GetLastHResult() << std::dec << "\n";
        std::cout << "      Stage: " << PhoneCam_GetLastErrorStage() << " (1=create, 2=start)\n";
        PhoneCam_DisposeVirtualCamera();
        return 1;
    }

    std::cout << ">>> PhoneCam Virtual Camera is now active! <<<\n";
    std::cout << ">>> Open Zoom, MS Teams, Google Meet, OBS or Discord to verify <<<\n";
    std::cout << ">>> Press ENTER to stop and exit... <<<\n";

    std::vector<uint8_t> frame(1920 * 1080 * 3 / 2, 128);
    std::fill(frame.begin(), frame.begin() + 1920 * 1080, 90);
    std::atomic<bool> publish{true};
    std::thread publisher([&] {
        while (publish) {
            const auto timestampUs = std::chrono::duration_cast<std::chrono::microseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
            PhoneCam_PushNV12Frame(1920, 1080, 30, frame.data(), frame.size(), timestampUs);
            std::this_thread::sleep_for(std::chrono::milliseconds(33));
        }
    });

    std::cin.get();
    publish = false;
    publisher.join();

    std::cout << "Stopping Virtual Camera...\n";
    PhoneCam_StopVirtualCamera();
    PhoneCam_DisposeVirtualCamera();
    std::cout << "Done.\n";
    return 0;
}
