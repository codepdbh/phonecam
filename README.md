# 📱 PhoneCam - Android Camera as Windows 11 Virtual Webcam

**PhoneCam** turns your Android phone into a high-quality, ultra-low-latency physical-like webcam on **Windows 11** over **local Wi-Fi and USB** (USB Tethering / USB Ethernet), integrating directly with the modern **Windows Media Foundation Virtual Camera API** (`MFCreateVirtualCamera`).

The camera appears in Windows 11 as a hardware-like webcam named:

> **`PhoneCam Virtual Camera`**

Compatible with **Google Meet, Zoom, Microsoft Teams, Discord, OBS Studio, Telegram Desktop**, and all standard Windows webcam-compatible applications.

---

## 🌟 Key Features

- ⚡ **Ultra Low Latency**: 20–70ms typical end-to-end latency on stable LAN via hardware-accelerated WebRTC.
- 🔌 **Dual Transport**: Works seamlessly over **Local Wi-Fi** or **USB Cable** (via USB Tethering without requiring ADB or Developer Options).
- 🎥 **Windows 11 Native Virtual Camera**: Uses `MFCreateVirtualCamera`, `IMFVirtualCamera`, `IMFMediaSource`, and `IMFMediaStream` without third-party drivers (no OBS/DroidCam/Iriun/NDI/ffmpeg required).
- 🎛️ **Remote Control (DataChannel)**: Control phone camera zoom, focus, exposure, torch, camera selection, 720p/1080p output and frame rate from Windows.
- 📡 **Zero External Cloud / 100% Local**: Works offline without internet; local UDP discovery on port `41235` and embedded local signaling on port `41236`.
- 🔐 **6-Digit PIN Pairing**: Security handshake with persistent authorization token store.
- 🧪 **Standalone Test Pattern Generator**: Built-in 1080p30 SMPTE color bar generator for independent testing before streaming from a mobile device.

---

## 🏗️ Repository Structure

```
phonecam/
│
├── apps/
│   ├── mobile/                  # Android Flutter Application (CameraX, WebRTC Sender, UI)
│   └── windows/                 # Windows 11 Desktop Flutter Application (WebRTC Receiver, UI, FFI Bridge)
│
├── native/
│   └── windows/
│       └── virtual_camera/      # C++ Windows Media Foundation Virtual Camera COM DLL & Test Runner
│
├── packages/
│   ├── shared_models/           # Shared Dart data models, error types & serialization
│   ├── protocol/                # Versioned JSON communication protocol for DataChannel & signaling
│   └── discovery/               # UDP Broadcast / mDNS discovery & Network Interface Analyzer (Wi-Fi vs USB)
│
├── docs/
│   ├── architecture.md          # Complete system architecture and sequence diagrams
│   ├── protocol.md              # DataChannel and signaling JSON specifications
│   ├── windows-camera.md        # Media Foundation Virtual Camera implementation details
│   ├── network.md               # LAN discovery, USB Tethering and network configuration
│   ├── security.md              # 6-Digit PIN pairing and trusted host persistence
│   └── development.md           # Developer environment setup & build instructions
│
├── scripts/
│   ├── build_all.ps1            # Automated build script for all packages, DLLs & apps
│   ├── run_windows.ps1          # Launch Windows Desktop Studio
│   ├── run_android.ps1          # Launch Android Mobile App
│   └── test_virtual_camera.ps1  # Test standalone virtual camera in Zoom/Meet/OBS with test pattern
│
└── README.md
```

---

## 🛠️ Prerequisites

| Tool / SDK | Minimum Version | Notes |
| :--- | :--- | :--- |
| **Operating System** | Windows 11 (Build 22000+) | Required for `MFCreateVirtualCamera` API |
| **Flutter SDK** | 3.41.0+ (Dart 3.11+) | Mobile & Desktop app framework |
| **Android SDK** | Android 7.0+ (API 24+) | Android SDK Platform 34/36 |
| **Visual Studio** | Visual Studio 2022 / 2026 Community | With *Desktop development with C++* & Windows SDK |
| **Windows SDK** | 10.0.22000.0 or 10.0.26100.0+ | Contains `mfvirtualcamera.h` and MF libraries |

---

## 🚀 Quick Start & Build

### 1. Build and Test All Packages
Run the automated build script from PowerShell:
```powershell
.\scripts\build_all.ps1
```

### 2. Test the Virtual Camera Standalone (Phase 6 Verification)
Before connecting a phone, verify that **`PhoneCam Virtual Camera`** appears in Windows and renders video:
```powershell
.\scripts\install_virtual_camera.ps1
.\scripts\test_virtual_camera.ps1
```
Open **Windows Camera App, Google Meet, Zoom, OBS Studio, or Discord**, select **`PhoneCam Virtual Camera`**, and you will see the animated SMPTE color bars test pattern running smoothly at 1080p @ 30 FPS.

### 3. Run the Windows Desktop Studio
```powershell
.\scripts\run_windows.ps1
```

### 4. Run the Android Mobile Application
```powershell
.\scripts\run_android.ps1
```

---

## 📡 Connecting Phone to Windows

### Option A: Local Wi-Fi (Automatic Discovery)
1. Ensure both your Android phone and Windows PC are connected to the same Wi-Fi network.
2. Open **PhoneCam** on Android and Windows.
3. Your phone will appear in the **DEVICES** list on Windows with a green `Wi-Fi` badge.
4. Click **Connect**.
5. Click **Activate Virtual Camera** to make the phone feed available to Zoom/Meet/OBS.

### Option B: USB Cable (USB Tethering)
1. Connect your Android phone to your PC with a USB-C cable.
2. In Android Settings, turn on **USB Tethering** (*Settings > Network & Internet > Hotspot & Tethering > USB Tethering*).
3. The phone will appear in the **DEVICES** list with a purple `USB` badge.
4. Click **Connect** for maximum throughput and minimal latency.

### Option C: Manual IP Connect (Fallback)
If your router uses client isolation:
1. Note the IP shown on your Android phone's top HUD pill (e.g. `192.168.1.45`).
2. Click **Manual IP Connect** on Windows, enter the IP, and click **Connect**.

---

## 📚 Technical Documentation

- [System Architecture](file:///c:/Users/Sistemas/Documents/webcam/docs/architecture.md)
- [Protocol Specification](file:///c:/Users/Sistemas/Documents/webcam/docs/protocol.md)
- [Media Foundation Virtual Camera Design](file:///c:/Users/Sistemas/Documents/webcam/docs/windows-camera.md)
- [Network & USB Transport](file:///c:/Users/Sistemas/Documents/webcam/docs/network.md)
- [Pairing & Security](file:///c:/Users/Sistemas/Documents/webcam/docs/security.md)
- [Developer Setup Guide](file:///c:/Users/Sistemas/Documents/webcam/docs/development.md)
