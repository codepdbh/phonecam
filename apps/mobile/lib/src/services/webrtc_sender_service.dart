import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:protocol/protocol.dart';
import 'package:shared_models/shared_models.dart';
import 'camera_capture_service.dart';
import 'signaling_server.dart';

class WebRtcSenderService {
  final CameraCaptureService cameraService;
  final SignalingServer signalingServer;
  final String deviceName;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  Timer? _statsTimer;

  final _connectionStateController =
      StreamController<AppConnectionState>.broadcast();
  final _statsController = StreamController<ConnectionStats>.broadcast();

  Stream<AppConnectionState> get onConnectionStateChanged =>
      _connectionStateController.stream;
  Stream<ConnectionStats> get onStatsUpdated => _statsController.stream;

  AppConnectionState _state = AppConnectionState.idle;
  AppConnectionState get state => _state;

  StreamSubscription? _offerSub;
  StreamSubscription? _candSub;

  WebRtcSenderService({
    required this.cameraService,
    required this.signalingServer,
    required this.deviceName,
  }) {
    _listenToSignaling();
  }

  void _setState(AppConnectionState newState) {
    _state = newState;
    _connectionStateController.add(_state);
  }

  void _listenToSignaling() {
    _offerSub = signalingServer.onOffer.listen((msg) async {
      final sdp = msg['sdp'] as String;
      final offer = RTCSessionDescription(sdp, 'offer');
      await _handleOffer(offer);
    });

    _candSub = signalingServer.onCandidate.listen((msg) async {
      final candData = msg['candidate'] as Map<String, dynamic>?;
      if (candData != null && _peerConnection != null) {
        final candidate = RTCIceCandidate(
          candData['candidate'] as String?,
          candData['sdpMid'] as String?,
          candData['sdpMLineIndex'] as int?,
        );
        await _peerConnection!.addCandidate(candidate);
      }
    });
  }

  Future<void> _handleOffer(RTCSessionDescription offer) async {
    _setState(AppConnectionState.connecting);

    if (_peerConnection != null) {
      try {
        await _peerConnection!.close();
      } catch (_) {}
      _peerConnection = null;
    }

    // Ensure camera stream is active before attaching
    if (cameraService.localStream == null ||
        cameraService.localStream!.getVideoTracks().isEmpty) {
      debugPrint('[WEBRTC_SENDER] Camera stream not active, starting now...');
      await cameraService.startStream();
    }

    final config = <String, dynamic>{
      'iceServers': <Map<String, dynamic>>[],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(config);

    // Attach local camera video track
    if (cameraService.localStream != null) {
      for (final track in cameraService.localStream!.getVideoTracks()) {
        debugPrint('[WEBRTC_SENDER] Attaching track: ${track.id} to peer connection');
        await _peerConnection!.addTrack(track, cameraService.localStream!);
      }
    }

    _peerConnection!.onIceCandidate = (candidate) {
      signalingServer.sendCandidate(
        candidate.candidate ?? '',
        candidate.sdpMid,
        candidate.sdpMLineIndex,
      );
    };

    _peerConnection!.onDataChannel = (channel) {
      debugPrint('[WEBRTC_SENDER] DataChannel received: ${channel.label}');
      _dataChannel = channel;
      _dataChannel!.onMessage = (msg) {
        if (!msg.isBinary) {
          _handleIncomingCommand(msg.text);
        }
      };

      _dataChannel!.onDataChannelState = (state) {
        debugPrint('[WEBRTC_SENDER] DataChannel state: $state');
        if (state == RTCDataChannelState.RTCDataChannelOpen) {
          _sendCapabilities();
        }
      };
    };

    _peerConnection!.onConnectionState = (state) {
      debugPrint('[WEBRTC_SENDER] PeerConnection state: $state');
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

    await _peerConnection!.setRemoteDescription(offer);
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    signalingServer.sendAnswer(answer.sdp ?? '');
  }

  void _handleIncomingCommand(String rawJson) {
    try {
      final msg = ProtocolMessage.decode(rawJson);

      switch (msg.messageType) {
        case CameraCommands.switchCamera:
          cameraService.switchCamera();
          _sendResponse(msg.requestId, {'status': 'ok'});
          break;

        case CameraCommands.selectCamera:
          final id = msg.payload['cameraId'] as String?;
          if (id != null) {
            cameraService.selectCamera(id);
            _sendResponse(msg.requestId, {'status': 'ok', 'cameraId': id});
          }
          break;

        case CameraCommands.zoom:
          final zoom = (msg.payload['zoom'] as num?)?.toDouble() ?? 1.0;
          cameraService.setZoom(zoom);
          _sendResponse(msg.requestId, {'status': 'ok', 'zoom': zoom});
          break;

        case CameraCommands.flash:
          final enable = msg.payload['torch'] as bool? ?? false;
          cameraService.setTorch(enable);
          _sendResponse(msg.requestId, {'status': 'ok', 'torch': enable});
          break;

        case StreamCommands.resolution:
          final res = VideoResolution.fromJson(msg.payload);
          cameraService.startStream(resolution: res);
          _sendResponse(msg.requestId, {'status': 'ok', 'resolution': res.label});
          break;

        case StreamCommands.fps:
          final fps = msg.payload['fps'] as int? ?? 30;
          cameraService.startStream(fps: fps);
          _sendResponse(msg.requestId, {'status': 'ok', 'fps': fps});
          break;

        case SystemCommands.getCapabilities:
          _sendCapabilities();
          break;
      }
    } catch (e) {
      debugPrint('[WEBRTC_SENDER] Error handling command: $e');
    }
  }

  void _sendCapabilities() {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final caps = cameraService.getDeviceCapabilities(deviceName);
      final msg = ProtocolMessage.create(
        messageType: SystemCommands.capabilities,
        payload: caps.toJson(),
      );
      _dataChannel!.send(RTCDataChannelMessage(msg.encode()));
    }
  }

  void _sendResponse(String requestId, Map<String, dynamic> data) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      final resp = ProtocolResponse.success(data).toMessage(requestId);
      _dataChannel!.send(RTCDataChannelMessage(resp.encode()));
    }
  }

  void _startStatsCollector() {
    _statsTimer?.cancel();
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        var bitrate = 6000.0;
        var fps = 30.0;
        var latency = 20;

        for (final report in stats) {
          if (report.type == 'outbound-rtp' && report.values['kind'] == 'video') {
            fps = (report.values['framesPerSecond'] as num?)?.toDouble() ?? 30.0;
          }
        }

        final telemetry = ConnectionStats(
          width: cameraService.currentResolution.width,
          height: cameraService.currentResolution.height,
          fps: fps,
          bitrateKbps: bitrate,
          latencyMs: latency,
          lostFrames: 0,
          transportType: TransportType.wifi,
          timestamp: DateTime.now(),
        );

        _statsController.add(telemetry);

        if (_dataChannel != null &&
            _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
          final msg = ProtocolMessage.create(
            messageType: SystemCommands.connectionStats,
            payload: telemetry.toJson(),
          );
          _dataChannel!.send(RTCDataChannelMessage(msg.encode()));
        }
      } catch (_) {}
    });
  }

  void dispose() {
    _offerSub?.cancel();
    _candSub?.cancel();
    _statsTimer?.cancel();
    _dataChannel?.close();
    _peerConnection?.close();
    _connectionStateController.close();
    _statsController.close();
  }
}
