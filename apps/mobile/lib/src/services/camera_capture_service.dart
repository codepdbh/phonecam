import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_models/shared_models.dart';

class CameraCaptureService {
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  MediaStream? get localStream => _localStream;

  /// Invoked with the new video track whenever [startStream] replaces the
  /// active stream (camera switch, resolution or FPS change). The WebRTC
  /// sender must call `RTCRtpSender.replaceTrack` with it so the already
  /// negotiated peer connection keeps sending frames instead of silently
  /// holding on to a stopped track.
  void Function(MediaStreamTrack track)? onVideoTrackReplaced;

  List<MediaDeviceInfo> _devices = [];
  List<CameraInfo> _availableCameras = [];
  List<CameraInfo> get availableCameras => _availableCameras;

  CameraInfo? _currentCamera;
  CameraInfo? get currentCamera => _currentCamera;

  VideoResolution _currentResolution = VideoResolution.r1080p;
  VideoResolution get currentResolution => _currentResolution;

  int _currentFps = 30;
  int get currentFps => _currentFps;

  double _currentZoom = 1.0;
  double get currentZoom => _currentZoom;

  bool _isTorchOn = false;
  bool get isTorchOn => _isTorchOn;

  bool _isInitialized = false;
  bool _isStreamActive = false;
  bool get isStreamActive => _isStreamActive;

  Future<void> initialize() async {
    if (_isInitialized) return;
    await localRenderer.initialize();
    await _enumerateCameras();
    _isInitialized = true;
  }

  Future<void> _enumerateCameras() async {
    try {
      _devices = await navigator.mediaDevices.enumerateDevices();
      final videoDevices = _devices.where((d) => d.kind == 'videoinput').toList();

      final list = <CameraInfo>[];
      for (int i = 0; i < videoDevices.length; i++) {
        final d = videoDevices[i];
        final label = d.label.toLowerCase();
        CameraFacing facing = CameraFacing.backMain;

        if (label.contains('front') || label.contains('user')) {
          facing = CameraFacing.front;
        } else if (label.contains('wide') || label.contains('ultra')) {
          facing = CameraFacing.ultraWide;
        } else if (label.contains('tele')) {
          facing = CameraFacing.telephoto;
        } else if (i == 1) {
          facing = CameraFacing.front;
        }

        list.add(
          CameraInfo(
            id: d.deviceId,
            name: d.label.isNotEmpty ? d.label : facing.label,
            facing: facing,
            hasTorch: facing != CameraFacing.front,
            zoomMin: 1.0,
            zoomMax: 8.0,
          ),
        );
      }

      if (list.isEmpty) {
        list.add(
          const CameraInfo(
            id: '0',
            name: 'Main Camera',
            facing: CameraFacing.backMain,
            hasTorch: true,
          ),
        );
      }

      _availableCameras = list;
      _currentCamera = _availableCameras.first;
    } catch (e) {
      debugPrint('[CAMERA] Enumeration failed: $e');
    }
  }

  Future<bool> startStream({
    CameraInfo? camera,
    VideoResolution? resolution,
    int? fps,
  }) async {
    await initialize();

    if (camera != null) _currentCamera = camera;
    if (resolution != null) _currentResolution = resolution;
    if (fps != null) _currentFps = fps;

    final isFront = _currentCamera?.facing == CameraFacing.front;

    // Clean constraints for Camera2 / WebRTC on Android
    final constraints = <String, dynamic>{
      'audio': false,
      'video': {
        'mandatory': {
          'minWidth': '${_currentResolution.width}',
          'minHeight': '${_currentResolution.height}',
          'minFrameRate': '$_currentFps',
        },
        'facingMode': isFront ? 'user' : 'environment',
        'optional': <Map<String, dynamic>>[],
      },
    };

    final previousStream = _localStream;
    final isReplacement = previousStream != null;

    // The underlying camera hardware only allows one open session per
    // device: releasing it has to happen BEFORE requesting the new
    // constraints, or getUserMedia() fails silently on Android ("camera in
    // use") and the resolution/fps change is a no-op. This plugin's
    // MediaStreamTrack.applyConstraints() is a stub for video, so
    // stop-then-reacquire is the only way to actually change format.
    if (previousStream != null) {
      for (final track in previousStream.getTracks()) {
        await track.stop();
      }
      await previousStream.dispose();
      _localStream = null;
    }

    try {
      final newStream = await navigator.mediaDevices.getUserMedia(constraints);
      _localStream = newStream;
      if (_isInitialized) {
        localRenderer.srcObject = _localStream;
      }
      _isStreamActive = true;
      _currentZoom = 1.0;
      _isTorchOn = false;
      debugPrint('[CAMERA] Stream started successfully at ${_currentResolution.label} @ ${_currentFps}fps');

      if (isReplacement && onVideoTrackReplaced != null) {
        final newTrack = newStream.getVideoTracks().isNotEmpty
            ? newStream.getVideoTracks().first
            : null;
        if (newTrack != null) onVideoTrackReplaced!(newTrack);
      }
      return true;
    } catch (e) {
      debugPrint('[CAMERA] Failed to get user media: $e');
      _isStreamActive = false;
      return false;
    }
  }

  Future<void> switchCamera() async {
    if (_availableCameras.length <= 1) return;
    final currentIdx = _availableCameras.indexWhere((c) => c.id == _currentCamera?.id);
    final nextIdx = (currentIdx + 1) % _availableCameras.length;
    await startStream(camera: _availableCameras[nextIdx]);
  }

  Future<void> selectCamera(String cameraId) async {
    final target = _availableCameras.firstWhere(
      (c) => c.id == cameraId,
      orElse: () => _availableCameras.first,
    );
    await startStream(camera: target);
  }

  Future<void> setZoom(double zoom) async {
    _currentZoom = zoom.clamp(1.0, 8.0);
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      try {
        await Helper.setZoom(track, _currentZoom);
      } catch (_) {}
    }
  }

  Future<void> toggleTorch() async {
    _isTorchOn = !_isTorchOn;
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      try {
        await track.setTorch(_isTorchOn);
      } catch (_) {}
    }
  }

  Future<void> setTorch(bool enable) async {
    _isTorchOn = enable;
    if (_localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
      final track = _localStream!.getVideoTracks().first;
      try {
        await track.setTorch(_isTorchOn);
      } catch (_) {}
    }
  }

  DeviceCapabilities getDeviceCapabilities(String deviceName) {
    return DeviceCapabilities(
      deviceName: deviceName,
      platform: 'Android',
      cameras: _availableCameras,
      supportedCodecs: const [VideoCodec.h264, VideoCodec.vp8],
      maxResolution: VideoResolution.r1080p,
      maxFps: 60,
    );
  }

  Future<void> dispose() async {
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      await _localStream!.dispose();
      _localStream = null;
    }
    _isStreamActive = false;
    if (_isInitialized) {
      try {
        localRenderer.srcObject = null;
        await localRenderer.dispose();
      } catch (_) {}
    }
  }
}
