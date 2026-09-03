# Windows virtual camera

PhoneCam registers two COM sources at once: a Media Foundation Frame Server
source (`CLSID_PhoneCamMediaSource`) and a DirectShow source
(`CLSID_PhoneCamDShowSource`), both backed by the same frame broker. The
Frame Server source needs `MFCreateVirtualCamera`, exported by
`mfsensorgroup.dll`, which only exists on **Windows 11 22H2 and newer**. The
DirectShow source has no such requirement and works standalone on any
Windows version — `PhoneCam_StartVirtualCamera()` degrades to DirectShow-only
instead of failing outright when Frame Server isn't available (see
`PhoneCam_IsFrameServerAvailable()` / `PhoneCam_ProbeFrameServerSupport()` in
`phonecam_ffi_exports.h`). Zoom, OBS, classic Chromium camera pickers and
OpenCV's `cv2.VideoCapture(..., cv2.CAP_DSHOW)` all discover it either way;
only apps that exclusively enumerate cameras through the modern Windows 11
camera stack need the Frame Server path. The desktop app checks
`PhoneCam_IsRegistered()` on startup and shows a banner explaining which mode
is active, or prompting to install the driver if it isn't registered at all.

The source is loaded by Windows Camera Frame Server, so its COM registration must be
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

## Orientation

Decoded WebRTC frames carry the display rotation as separate metadata
(`RTCVideoFrame::rotation()`), not baked into the pixel buffer — neither
Flutter's `Texture` widget nor a DirectShow/MF sample has a channel for that
metadata, so both `FlutterVideoRenderer::CopyPixelBuffer()` (on-screen
preview) and `PublishPhoneCamFrame()` (virtual camera) physically rotate the
Y/U/V (or ARGB) planes to match before handing them off. See
`RotatedSourceCoord()` in
`packages/flutter_webrtc_phonecam/common/cpp/src/flutter_video_renderer.cc`.

## Packaging a release

```powershell
.\scripts\package_release.ps1 -Zip
```

Builds the native DLL, the Windows app and the Android APK (in that order —
the native DLL must exist before the Windows app's CMake project is first
configured, or its `install()` step has nothing to bundle next to the exe)
and assembles `dist/PhoneCam-Windows/` (exe + DLL + installer scripts) and
`dist/PhoneCam-Android.apk`, ready to zip and hand to someone else. They only
need to run `windows.exe`; the app detects on startup whether the driver is
registered and offers a one-click (UAC-elevated) install if not.

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
