# PhoneCam Developer & Setup Guide

This guide details all prerequisites, toolchains, build steps, and debugging workflows for the PhoneCam codebase.

---

## 1. Prerequisites

- **Operating System**: Windows 11 (Build 22000 or newer)
- **Flutter SDK**: 3.41+ (Dart 3.11+)
- **Android SDK**: Android 7.0+ (API 24+), Android SDK Build-Tools 34.0.0+ / 36.1.0+
- **Visual Studio**: Visual Studio 2022 or 2026 Community / Professional with:
  - *Desktop development with C++* workload
  - *MSVC v143 / v144 C++ x64/x86 build tools*
  - *Windows 10/11 SDK (10.0.22000.0 or 10.0.26100.0 / 10.0.28000.0)*
  - *C++ CMake tools for Windows*

---

## 2. Directory Structure

```
c:\Users\Sistemas\Documents\webcam\
├── apps/
│   ├── mobile/                  # Android Flutter App
│   └── windows/                 # Windows Desktop Flutter App
├── native/
│   └── windows/virtual_camera/  # C++ Media Foundation Virtual Camera DLL & Test Runner
├── packages/
│   ├── shared_models/           # Shared models & typed exceptions
│   ├── protocol/                # JSON protocol message envelopes & commands
│   └── discovery/               # UDP LAN discovery & network analyzer
├── docs/                        # Technical documentation
├── scripts/                     # PowerShell automation scripts
└── README.md                    # Main documentation
```

---

## 3. Build & Verification Commands

### Run Full Test Suite & Build Pipeline
```powershell
.\scripts\build_all.ps1
```

### Test Windows Virtual Camera (Standalone Test Pattern)
```powershell
.\scripts\test_virtual_camera.ps1
```
*Note: This starts "PhoneCam Virtual Camera" with a 1080p30 SMPTE color bars pattern so you can immediately test it in Zoom, Meet, Teams, OBS, or Discord.*

### Run Windows Desktop Studio
```powershell
.\scripts\run_windows.ps1
```

### Run Android Mobile App
```powershell
.\scripts\run_android.ps1
```
