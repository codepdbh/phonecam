#include <iostream>
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

    std::cout << ">>> PhoneCam Virtual Camera is now active! <<<\n";
    std::cout << ">>> Open Zoom, MS Teams, Google Meet, OBS or Discord to verify <<<\n";
    std::cout << ">>> Press ENTER to stop and exit... <<<\n";

    std::cin.get();

    std::cout << "Stopping Virtual Camera...\n";
    PhoneCam_StopVirtualCamera();
    PhoneCam_DisposeVirtualCamera();
    std::cout << "Done.\n";
    return 0;
}
