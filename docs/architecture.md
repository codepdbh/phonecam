# PhoneCam Architecture

PhoneCam is a high-performance, low-latency system designed to use an Android smartphone as a native Windows 11 physical-like webcam over local Wi-Fi and USB Tethering.

```mermaid
graph TD
    subgraph Android["Android Mobile Device (Flutter + CameraX)"]
        CamX[Camera Hardware / CameraX] -->|Raw Video Frames| WRTC_S[WebRTC Video Track / Encoder]
        DC_S[WebRTC DataChannel] <-->|Commands & Stats| WRTC_S
        SIG_S[Embedded HTTP/WS Server :41236] <-->|Signaling / SDP / ICE| WRTC_S
        DISC_S[UDP Broadcast Beacon :41235]
    end

    subgraph Transport["Local Transport (Zero External Cloud)"]
        LAN_WIFI[Local Wi-Fi Network]
        USB_TETH[USB Tethering / USB Ethernet]
    end

    subgraph Windows["Windows 11 PC (Flutter Desktop + C++ WMF)"]
        DISC_C[UDP Listener :41235 / Subnet Matcher]
        SIG_C[Signaling Client]
        WRTC_R[WebRTC Receiver / Decoder]
        DC_C[WebRTC DataChannel]
        SINK[Native WebRTC Video Sink]
        BROKER[ProgramData Frame Broker]
        WMF_DLL[PhoneCamMediaSource.dll]
        VIRT_CAM[IMFVirtualCamera Device]
        APPS[Zoom / Meet / Teams / Discord / OBS]
    end

    DISC_S -.->|UDP Beacons| DISC_C
    SIG_S <==>|LAN / USB| SIG_C
    WRTC_S ==>|Low-Latency H.264 / VP8 RTP Stream| WRTC_R
    DC_S <==>|Bidirectional Remote Control| DC_C
    WRTC_R -->|Decoded I420 planes| SINK
    SINK -->|Packed NV12 frames| BROKER
    BROKER -->|File-backed mapped pages| WMF_DLL
    WMF_DLL -->|IMFMediaSource / IMFMediaStream| VIRT_CAM
    VIRT_CAM ==>|PhoneCam Virtual Camera| APPS
```

---

## 1. Subsystems Overview

### A. Mobile Application (`apps/mobile`)
- **UI Framework**: Flutter with Riverpod state management.
- **Capture Engine**: `flutter_webrtc` / Camera hardware integration.
- **Embedded Server**: Custom Dart HTTP/WebSocket server listening on port `41236`.
- **Discovery Beacon**: Periodically broadcasts UDP announce packets on port `41235`.
- **Remote Control Receiver**: Receives versioned JSON commands via WebRTC DataChannel for zoom, focus, exposure, torch/flash, resolution, framerate, and camera switching.

### B. Windows Application (`apps/windows`)
- **UI Framework**: Flutter Desktop with modern dark theme and real-time telemetry.
- **Discovery Service**: Listens for UDP beacons on port `41235` and classifies connections by analyzing network adapters (Wi-Fi vs USB Tethering).
- **WebRTC Client**: Initiates local peer connection with Android device over local IP.
- **Virtual Camera Bridge**: Dart FFI controls camera lifetime and exposes diagnostics; decoded planes are published directly by the native WebRTC renderer without a full-frame Dart copy.

### C. Windows Media Foundation Virtual Camera (`native/windows/virtual_camera`)
- **API**: Windows 11 `MFCreateVirtualCamera` API (`IMFVirtualCamera`).
- **COM Interfaces**: Implements `IMFActivate`, `IMFMediaSourceEx`, `IMFMediaStream2`, `IMFSampleAllocatorControl`, `IMFGetService`, and `IKsControl`.
- **Cross-session transport**: Lock-free, double-buffered file mapping under `%ProgramData%\PhoneCam`, accessible to the desktop producer and Windows Camera Frame Server.
- **Pixel Formats**: NV12 broker with negotiated `NV12`, `RGB32`, and `YUY2` output at 720p/1080p30.
- **Synthetic Frame Engine**: Integrated SMPTE color bars + timestamp + moving sync generator for standalone Phase 6 validation.

### D. Shared Packages
- **`packages/shared_models`**: Common data classes (`DeviceInfo`, `DeviceCapabilities`, `CameraInfo`, `ConnectionStats`, `VideoFormat`, `TypedErrors`).
- **`packages/protocol`**: Versioned JSON message envelopes, command builders, serializers, and response envelopes.
- **`packages/discovery`**: UDP broadcast peer discovery and local network adapter analyzer.
