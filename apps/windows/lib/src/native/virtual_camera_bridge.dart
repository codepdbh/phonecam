import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

typedef _InitFn = Int32 Function();
typedef _InitDart = int Function();

typedef _StartFn = Int32 Function();
typedef _StartDart = int Function();

typedef _StopFn = Int32 Function();
typedef _StopDart = int Function();

typedef _DisposeFn = Int32 Function();
typedef _DisposeDart = int Function();

typedef _SetFormatFn = Int32 Function(
    Int32 width, Int32 height, Int32 fps, Int32 fourcc);
typedef _SetFormatDart = int Function(
    int width, int height, int fps, int fourcc);

typedef _PushFrameFn = Int32 Function(
    Pointer<Uint8> pBuffer, IntPtr size, Int64 timestampUs);
typedef _PushFrameDart = int Function(
    Pointer<Uint8> pBuffer, int size, int timestampUs);

typedef _EnableTestPatternFn = Int32 Function(Int32 enable);
typedef _EnableTestPatternDart = int Function(int enable);

typedef _GetStatusFn = Int32 Function();
typedef _GetStatusDart = int Function();

typedef _GetInt64Fn = Int64 Function();
typedef _GetInt64Dart = int Function();

typedef _GetUint64Fn = Uint64 Function();
typedef _GetUint64Dart = int Function();

class VirtualCameraBridge {
  static VirtualCameraBridge? _instance;
  static VirtualCameraBridge get instance =>
      _instance ??= VirtualCameraBridge._();

  DynamicLibrary? _dylib;

  _InitDart? _initialize;
  _StartDart? _start;
  _StopDart? _stop;
  _DisposeDart? _dispose;
  _SetFormatDart? _setFormat;
  _PushFrameDart? _pushFrame;
  _EnableTestPatternDart? _enableTestPattern;
  _GetStatusDart? _getStatus;
  _GetInt64Dart? _getLastHResult;
  _GetStatusDart? _getLastErrorStage;
  _GetUint64Dart? _getPublishedFrameCount;
  _GetUint64Dart? _getRejectedFrameCount;
  _GetStatusDart? _isFrameServerAvailable;
  _GetStatusDart? _isRegistered;
  _GetStatusDart? _probeFrameServerSupport;

  bool _isLoaded = false;
  bool get isLoaded => _isLoaded;

  VirtualCameraBridge._() {
    _loadLibrary();
  }

  void _loadLibrary() {
    if (!Platform.isWindows) return;

    final possiblePaths = [
      'PhoneCamMediaSource_v7.dll',
      r'..\..\native\windows\virtual_camera\build\Release\PhoneCamMediaSource_v7.dll',
      r'native\windows\virtual_camera\build\Release\PhoneCamMediaSource_v7.dll',
    ];

    for (final path in possiblePaths) {
      try {
        _dylib = DynamicLibrary.open(path);
        debugPrint('[VIRTUAL_CAMERA] Loaded native library from $path');
        break;
      } catch (_) {}
    }

    if (_dylib == null) {
      try {
        _dylib = DynamicLibrary.process();
      } catch (e) {
        debugPrint('[VIRTUAL_CAMERA] Failed to open dynamic library: $e');
        return;
      }
    }

    try {
      _initialize = _dylib!.lookupFunction<_InitFn, _InitDart>(
          'PhoneCam_InitializeVirtualCamera');
      _start = _dylib!
          .lookupFunction<_StartFn, _StartDart>('PhoneCam_StartVirtualCamera');
      _stop = _dylib!
          .lookupFunction<_StopFn, _StopDart>('PhoneCam_StopVirtualCamera');
      _dispose = _dylib!.lookupFunction<_DisposeFn, _DisposeDart>(
          'PhoneCam_DisposeVirtualCamera');
      _setFormat = _dylib!.lookupFunction<_SetFormatFn, _SetFormatDart>(
          'PhoneCam_SetVideoFormat');
      _pushFrame = _dylib!.lookupFunction<_PushFrameFn, _PushFrameDart>(
          'PhoneCam_PushVideoFrame');
      _enableTestPattern = _dylib!
          .lookupFunction<_EnableTestPatternFn, _EnableTestPatternDart>(
              'PhoneCam_EnableTestPattern');
      _getStatus = _dylib!
          .lookupFunction<_GetStatusFn, _GetStatusDart>('PhoneCam_GetStatus');
      _getLastHResult = _dylib!.lookupFunction<_GetInt64Fn, _GetInt64Dart>(
          'PhoneCam_GetLastHResult');
      _getLastErrorStage = _dylib!.lookupFunction<_GetStatusFn, _GetStatusDart>(
          'PhoneCam_GetLastErrorStage');
      _getPublishedFrameCount = _dylib!
          .lookupFunction<_GetUint64Fn, _GetUint64Dart>(
              'PhoneCam_GetPublishedFrameCount');
      _getRejectedFrameCount = _dylib!
          .lookupFunction<_GetUint64Fn, _GetUint64Dart>(
              'PhoneCam_GetRejectedFrameCount');
      _isFrameServerAvailable = _dylib!
          .lookupFunction<_GetStatusFn, _GetStatusDart>(
              'PhoneCam_IsFrameServerAvailable');
      _isRegistered = _dylib!
          .lookupFunction<_GetStatusFn, _GetStatusDart>('PhoneCam_IsRegistered');
      _probeFrameServerSupport = _dylib!
          .lookupFunction<_GetStatusFn, _GetStatusDart>(
              'PhoneCam_ProbeFrameServerSupport');

      _isLoaded = true;
      debugPrint('[VIRTUAL_CAMERA] Native functions successfully bound');
    } catch (e) {
      debugPrint('[VIRTUAL_CAMERA] Binding error: $e');
    }
  }

  int initialize() => _initialize?.call() ?? -1;
  int start() => _start?.call() ?? -1;
  int stop() => _stop?.call() ?? -1;
  int dispose() => _dispose?.call() ?? -1;
  int setVideoFormat(int width, int height, int fps, int fourcc) =>
      _setFormat?.call(width, height, fps, fourcc) ?? -1;

  int pushVideoFrame(Uint8List bytes, int timestampUs) {
    if (_pushFrame == null) return -1;
    final ptr = malloc.allocate<Uint8>(bytes.length);
    try {
      final nativeList = ptr.asTypedList(bytes.length);
      nativeList.setAll(0, bytes);
      return _pushFrame!(ptr, bytes.length, timestampUs);
    } finally {
      malloc.free(ptr);
    }
  }

  int enableTestPattern(bool enable) =>
      _enableTestPattern?.call(enable ? 1 : 0) ?? -1;

  int getStatus() => _getStatus?.call() ?? -1;
  int get lastHResult => _getLastHResult?.call() ?? -1;
  int get lastErrorStage => _getLastErrorStage?.call() ?? -1;
  int get publishedFrameCount => _getPublishedFrameCount?.call() ?? 0;
  int get rejectedFrameCount => _getRejectedFrameCount?.call() ?? 0;

  /// True once the Media Foundation Frame Server virtual camera (Windows 11
  /// 22H2+) is actually running. False on Windows 10 / older Windows 11 —
  /// the DirectShow source still works there, this only tells apart which
  /// discovery paths will see it.
  bool get isFrameServerAvailable => (_isFrameServerAvailable?.call() ?? 0) != 0;

  /// True once the native driver's COM classes are registered machine-wide
  /// (i.e. install_virtual_camera.ps1 has been run at least once).
  bool get isRegistered => (_isRegistered?.call() ?? 0) != 0;

  /// Whether this Windows install can host the Frame Server virtual camera
  /// (Windows 11 22H2+) at all, independent of whether the camera has been
  /// started yet. Safe to call for up-front "what to expect" messaging.
  bool get supportsFrameServer => (_probeFrameServerSupport?.call() ?? 0) != 0;
}
