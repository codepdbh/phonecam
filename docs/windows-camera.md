# Windows virtual camera

PhoneCam uses the Windows 11 Media Foundation virtual-camera API. The source is
loaded by Windows Camera Frame Server, so its COM registration must be
machine-wide even though the virtual camera uses `CurrentUser` access.

## Installation

```powershell
.\scripts\install_virtual_camera.ps1
```

The script requests elevation, installs the versioned source at
`%ProgramFiles%\PhoneCam\PhoneCamMediaSource_v7.dll`, registers Media Foundation
and DirectShow with distinct CLSIDs, and refreshes Camera Frame Server. Use
`.\scripts\uninstall_virtual_camera.ps1` for complete removal.

During an update the installer stops both `FrameServerMonitor` and
`FrameServer`, because either service can retain an older in-process DLL. It
also creates `%ProgramData%\PhoneCam` with Modify access for desktop users and
`LOCAL SERVICE`.

## Frame path

```text
Android camera -> WebRTC decoder -> native flutter_webrtc video sink
               -> I420-to-NV12 packing -> double-buffered shared broker
               -> PhoneCamMediaSource_v7.dll in Frame Server
               -> NV12/RGB32/YUY2 sample -> browser or desktop client
```

Decoded planes stay in native code. The broker is the file-backed mapping
`%ProgramData%\PhoneCam\frame-broker-v4.bin`; unlike a `Local\` named mapping,
it is visible to both the desktop session and Windows Camera Frame Server. It
publishes an inactive slot atomically and includes frame counters, producer
PID, timestamps, heartbeat, strides, diagnostics and rejected-frame count.
Consumers show animated color bars when the producer is absent or a frame is
stale for more than two seconds.

## COM identities

- Media Foundation: `{E4D8A9F1-3142-4A2D-A483-E18F54687791}`
- DirectShow: `{E4D8A9F3-3142-4A2D-A483-E18F54687791}`

The Media Foundation source implements `IMFActivate`, `IMFMediaSourceEx`,
`IMFMediaStream2`, `IMFSampleAllocatorControl`, `IMFGetService`, `IKsControl`
and their inherited interfaces. The DirectShow fallback is a separate filter
and consumes the same broker.

## Formats

- 1280x720 at 30 FPS: NV12 and RGB32.
- 1920x1080 at 30 FPS: NV12, RGB32 and YUY2.

NV12 is canonical. Scaling and RGB32/YUY2 conversion occur only when required
by the consumer.

## Verification

```powershell
.\scripts\build_all.ps1
.\native\windows\virtual_camera\build\Release\PhoneCamContractTest.exe
.\native\windows\virtual_camera\build\Release\PhoneCamFrameBrokerTest.exe
.\scripts\test_virtual_camera.ps1
```

For a full producer-to-client check, keep `PhoneCamTestRunner.exe` open in one
terminal and run `PhoneCamCaptureTest.exe` in another. A passing result reports
3,110,400 bytes for 1080p NV12 and the luma value published by the producer.
