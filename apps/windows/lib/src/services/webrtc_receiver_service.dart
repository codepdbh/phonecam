import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol/protocol.dart';
import 'package:shared_models/shared_models.dart';
import '../native/virtual_camera_bridge.dart';
import 'signaling_client.dart';

class WebRtcReceiverService {
  final RTCVideoRenderer renderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  SignalingClient? _signalingClient;
  Timer? _statsTimer;
  int? _lastBytesReceived;
  DateTime? _lastStatsTimestamp;

  final _connectionStateController =
      StreamController<AppConnectionState>.broadcast();
  final _statsController = StreamController<ConnectionStats>.broadcast();
  final _capabilitiesController =
      StreamController<DeviceCapabilities>.broadcast();
  final _videoStreamReadyController = StreamController<bool>.broadcast();

  Stream<AppConnectionState> get onConnectionStateChanged =>
      _connectionStateController.stream;
  Stream<ConnectionStats> get onStatsUpdated => _statsController.stream;
  Stream<DeviceCapabilities> get onCapabilitiesReceived =>
      _capabilitiesController.stream;
  Stream<bool> get onVideoStreamReady => _videoStreamReadyController.stream;

  AppConnectionState _state = AppConnectionState.idle;
  AppConnectionState get state => _state;

  DeviceInfo? _currentDevice;
  DeviceInfo? get currentDevice => _currentDevice;

  DeviceCapabilities? _deviceCapabilities;
  DeviceCapabilities? get deviceCapabilities => _deviceCapabilities;

  bool _isVirtualCameraActive = false;
  bool get isVirtualCameraActive => _isVirtualCameraActive;
  String _virtualCameraError = '';
  String get virtualCameraError => _virtualCameraError;
  int get publishedVirtualCameraFrames =>
      VirtualCameraBridge.instance.publishedFrameCount;
  int get rejectedVirtualCameraFrames =>
      VirtualCameraBridge.instance.rejectedFrameCount;

  bool _isInitialized = false;
  bool _hasVideoStream = false;
  bool get hasVideoStream => _hasVideoStream;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await renderer.initialize();
      final bridge = VirtualCameraBridge.instance;
      if (bridge.isLoaded) {
        final result = bridge.initialize();
        if (result != 0) {
          debugPrint(
              '[VIRTUAL_CAMERA] Initialization failed: status=$result hr=0x${bridge.lastHResult.toRadixString(16)}');
        }
      }
      _isInitialized = true;
    } catch (e) {
      debugPrint('[WEBRTC] Renderer initialize error: $e');
    }
  }

  void _setState(AppConnectionState newState) {
    _state = newState;
    if (!_connectionStateController.isClosed) {
      _connectionStateController.add(_state);
    }
  }

  Future<bool> connect(DeviceInfo device) async {
    await initialize();
    _currentDevice = device;
    _hasVideoStream = false;
    _setState(AppConnectionState.connecting);

    _signalingClient = SignalingClient(
      host: device.ipAddress,
      port: device.port,
    );

    final connected = await _signalingClient!.connect();
    if (!connected) {
      _setState(AppConnectionState.error);
      return false;
    }

    _signalingClient!.onMessage.listen((msg) {
      _handleSignalingMessage(msg);
    });

    _signalingClient!.onStateChange.listen((isConnected) {
      if (!isConnected && _state.isConnectedOrStreaming) {
        _setState(AppConnectionState.disconnected);
      }
    });

    await _setupPeerConnection();
    return true;
  }

  Future<void> _setupPeerConnection() async {
    final configuration = <String, dynamic>{
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);

    _peerConnection!.onIceCandidate = (candidate) {
      _signalingClient?.sendCandidate(candidate);
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WEBRTC] PeerConnection state: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(AppConnectionState.streaming);
        _startStatsCollector();
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setState(AppConnectionState.reconnecting);
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setState(AppConnectionState.error);
      }
    };

    _peerConnection!.onTrack = (event) async {
      if (event.track.kind == 'video') {
        debugPrint(
            '[WEBRTC] Received video track: ${event.track.id}, streams count: ${event.streams.length}');
        if (_isInitialized) {
          try {
            if (event.streams.isNotEmpty) {
              renderer.srcObject = event.streams.first;
            } else {
              final remoteStream = await createLocalMediaStream(
                  'remote_stream_${DateTime.now().millisecondsSinceEpoch}');
              await remoteStream.addTrack(event.track);
              renderer.srcObject = remoteStream;
            }
            _hasVideoStream = true;
            if (!_videoStreamReadyController.isClosed) {
              _videoStreamReadyController.add(true);
            }
            debugPrint(
                '[WEBRTC] Video stream successfully attached to renderer');
          } catch (e) {
            debugPrint('[WEBRTC] Error attaching video track: $e');
          }
        }
      }
    };

    // Explicitly add Video Transceiver with RecvOnly direction for Unified-Plan
    try {
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
    } catch (_) {}

    // Create DataChannel for low latency commands
    final dcInit = RTCDataChannelInit()..ordered = true;
    _dataChannel =
        await _peerConnection!.createDataChannel('phonecam-control', dcInit);

    _dataChannel!.onDataChannelState = (state) {
      debugPrint('[WEBRTC] DataChannel state: $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        sendCommand(SystemCommands.createGetCapabilities());
      }
    };

    _dataChannel!.onMessage = (data) {
      if (data.isBinary) return;
      _handleDataChannelMessage(data.text);
    };

    // Create SDP Offer
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 0,
    });
    await _peerConnection!.setLocalDescription(offer);
    _signalingClient?.sendOffer(offer);
  }

  Future<void> _handleSignalingMessage(Map<String, dynamic> msg) async {
    final type = msg['type'] as String?;
    if (type == 'answer') {
      final sdp = msg['sdp'] as String;
      final answer = RTCSessionDescription(sdp, 'answer');
      await _peerConnection?.setRemoteDescription(answer);
    } else if (type == 'candidate') {
      final candData = msg['candidate'] as Map<String, dynamic>?;
      if (candData != null) {
        final candidate = RTCIceCandidate(
          candData['candidate'] as String?,
          candData['sdpMid'] as String?,
          candData['sdpMLineIndex'] as int?,
        );
        await _peerConnection?.addCandidate(candidate);
      }
    } else if (type == 'pairing_required') {
      _setState(AppConnectionState.pairing);
    }
  }

  void _handleDataChannelMessage(String text) {
    try {
      final msg = ProtocolMessage.decode(text);
      if (msg.messageType == SystemCommands.capabilities) {
        _deviceCapabilities = DeviceCapabilities.fromJson(msg.payload);
        if (!_capabilitiesController.isClosed) {
          _capabilitiesController.add(_deviceCapabilities!);
        }
      } else if (msg.messageType == SystemCommands.connectionStats) {
        final stats = ConnectionStats.fromJson(msg.payload);
        if (!_statsController.isClosed) {
          _statsController.add(stats);
        }
      }
    } catch (e) {
      debugPrint('[DATACHANNEL] Error processing message: $e');
    }
  }

  void sendCommand(ProtocolMessage message) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(message.encode()));
    }
  }

  // Camera control helpers
  void switchCamera() => sendCommand(CameraCommands.createSwitch());
  void selectCamera(String id) => sendCommand(CameraCommands.createSelect(id));
  void setZoom(double zoom) => sendCommand(CameraCommands.createZoom(zoom));
  void setFocus({double? x, double? y, bool auto = true}) =>
      sendCommand(CameraCommands.createFocus(x: x, y: y, auto: auto));
  void setExposure(double offset) =>
      sendCommand(CameraCommands.createExposure(offset));
  void setTorch(bool enable) => sendCommand(CameraCommands.createFlash(enable));
  void setResolution(VideoResolution res) =>
      sendCommand(StreamCommands.createResolution(res));
  void setFps(int fps) => sendCommand(StreamCommands.createFps(fps));

  // Virtual Camera management
  bool toggleVirtualCamera(bool enable) {
    final bridge = VirtualCameraBridge.instance;
    if (enable) {
      bridge.initialize();
      // Decoded WebRTC planes are published natively as NV12. The camera
      // source converts only when a consumer explicitly negotiates RGB32/YUY2.
      bridge.setVideoFormat(1920, 1080, 30, 0);
      final res = bridge.start();
      _isVirtualCameraActive = (res == 0);
      _virtualCameraError = '';
      if (!_isVirtualCameraActive) {
        _virtualCameraError =
            'status=$res, stage=${bridge.lastErrorStage}, HRESULT=0x${bridge.lastHResult.toRadixString(16)}';
        debugPrint(
            '[VIRTUAL_CAMERA] Start failed: status=$res hr=0x${bridge.lastHResult.toRadixString(16)}');
      }
    } else {
      bridge.stop();
      _isVirtualCameraActive = false;
      _virtualCameraError = '';
    }
    return _isVirtualCameraActive;
  }

  void _startStatsCollector() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        var bitrate = 0.0;
        var fps = 0.0;
        var latency = 0;
        var lost = 0;
        var received = 0;
        var width = renderer.videoWidth > 0 ? renderer.videoWidth : 1920;
        var height = renderer.videoHeight > 0 ? renderer.videoHeight : 1080;
        var jitterMs = 0.0;
        String? codecId;
        var codec = VideoCodec.h264;
        final now = DateTime.now();

        for (final report in stats) {
          if (report.type == 'inbound-rtp' &&
              report.values['kind'] == 'video') {
            fps = (report.values['framesPerSecond'] as num?)?.toDouble() ?? 0.0;
            lost = (report.values['packetsLost'] as num?)?.toInt() ?? 0;
            received = (report.values['packetsReceived'] as num?)?.toInt() ?? 0;
            width = (report.values['frameWidth'] as num?)?.toInt() ?? width;
            height = (report.values['frameHeight'] as num?)?.toInt() ?? height;
            jitterMs =
                ((report.values['jitter'] as num?)?.toDouble() ?? 0) * 1000;
            codecId = report.values['codecId'] as String?;
            final bytes = (report.values['bytesReceived'] as num?)?.toInt();
            if (bytes != null &&
                _lastBytesReceived != null &&
                _lastStatsTimestamp != null) {
              final seconds =
                  now.difference(_lastStatsTimestamp!).inMilliseconds / 1000;
              if (seconds > 0) {
                bitrate = (bytes - _lastBytesReceived!) * 8 / seconds / 1000;
              }
            }
            _lastBytesReceived = bytes;
          } else if (report.type == 'candidate-pair' &&
              report.values['state'] == 'succeeded') {
            final rtt =
                (report.values['currentRoundTripTime'] as num?)?.toDouble();
            if (rtt != null) latency = (rtt * 1000).toInt();
          }
        }
        if (codecId != null) {
          for (final report in stats) {
            if (report.id == codecId && report.type == 'codec') {
              final mimeType = report.values['mimeType'] as String?;
              if (mimeType != null) {
                codec = VideoCodec.fromString(mimeType.split('/').last);
              }
            }
          }
        }
        _lastStatsTimestamp = now;
        final totalPackets = received + lost;
        final lossPercentage =
            totalPackets > 0 ? lost * 100 / totalPackets : 0.0;

        final telemetry = ConnectionStats(
          width: width,
          height: height,
          fps: fps,
          bitrateKbps: bitrate,
          latencyMs: latency,
          lostFrames: lost,
          packetLossPercentage: lossPercentage,
          jitterMs: jitterMs,
          codec: codec,
          transportType: _currentDevice?.transportType ?? TransportType.wifi,
          timestamp: DateTime.now(),
        );

        if (!_statsController.isClosed) {
          _statsController.add(telemetry);
        }
      } catch (_) {}
    });
  }

  void disconnect() {
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastBytesReceived = null;
    _lastStatsTimestamp = null;
    _dataChannel?.close();
    _dataChannel = null;
    _peerConnection?.close();
    _peerConnection = null;
    _signalingClient?.disconnect();
    _signalingClient = null;
    _hasVideoStream = false;
    if (_isInitialized) {
      try {
        renderer.srcObject = null;
      } catch (_) {}
    }
    _setState(AppConnectionState.disconnected);
  }

  void dispose() {
    disconnect();
    if (_isInitialized) {
      try {
        renderer.dispose();
      } catch (_) {}
    }
    _connectionStateController.close();
    _statsController.close();
    _capabilitiesController.close();
    _videoStreamReadyController.close();
  }
}
