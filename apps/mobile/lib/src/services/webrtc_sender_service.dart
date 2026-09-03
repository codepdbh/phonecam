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

  int? _lastBytesSent;
  DateTime? _lastStatsTimestamp;

  WebRtcSenderService({
    required this.cameraService,
    required this.signalingServer,
    required this.deviceName,
  }) {
    _listenToSignaling();
    cameraService.onVideoTrackReplaced = _handleVideoTrackReplaced;
  }

  /// Target bitrate for a given resolution. Mirrors the defaults in
  /// [VideoFormat] so the encoder is actually pinned to a sane ceiling
  /// instead of relying purely on WebRTC's default bandwidth estimation,
  /// which tends to under- or over-shoot on variable WiFi links.
  int _bitrateKbpsForResolution(VideoResolution res) {
    final pixels = res.totalPixels;
    if (pixels <= VideoResolution.r720p.totalPixels) return 3500;
    if (pixels <= VideoResolution.r1080p.totalPixels) return 6000;
    if (pixels <= VideoResolution.r1440p.totalPixels) return 10000;
    return 16000;
  }

  Future<void> _applyEncodingParameters(RTCRtpSender sender) async {
    try {
      final maxBitrateBps =
          _bitrateKbpsForResolution(cameraService.currentResolution) * 1000;
      final current = sender.parameters;
      final encodings = (current.encodings != null && current.encodings!.isNotEmpty)
          ? current.encodings!
          : [RTCRtpEncoding()];
      for (final encoding in encodings) {
        encoding.active = true;
        encoding.maxBitrate = maxBitrateBps;
        encoding.maxFramerate = cameraService.currentFps;
      }
      await sender.setParameters(RTCRtpParameters(
        encodings: encodings,
        degradationPreference: current.degradationPreference,
      ));
    } catch (e) {
      debugPrint('[WEBRTC_SENDER] Failed to apply encoding parameters: $e');
    }
  }

  Future<RTCRtpSender?> _findVideoSender() async {
    if (_peerConnection == null) return null;
    final senders = await _peerConnection!.getSenders();
    for (final sender in senders) {
      if (sender.track?.kind == 'video') return sender;
    }
    return null;
  }

  Future<void> _handleVideoTrackReplaced(MediaStreamTrack track) async {
    final sender = await _findVideoSender();
    if (sender == null) return;
    try {
      await sender.replaceTrack(track);
      await _applyEncodingParameters(sender);
      debugPrint('[WEBRTC_SENDER] Replaced outgoing video track: ${track.id}');
    } catch (e) {
      debugPrint('[WEBRTC_SENDER] Failed to replace video track: $e');
    }
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
        final sender =
            await _peerConnection!.addTrack(track, cameraService.localStream!);
        await _applyEncodingParameters(sender);
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
    _lastBytesSent = null;
    _lastStatsTimestamp = null;
    _statsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (_peerConnection == null) return;
      try {
        final stats = await _peerConnection!.getStats();
        var bitrate = 0.0;
        var fps = 0.0;
        var latency = 0;
        final now = DateTime.now();

        for (final report in stats) {
          if (report.type == 'outbound-rtp' && report.values['kind'] == 'video') {
            fps = (report.values['framesPerSecond'] as num?)?.toDouble() ?? 0.0;
            final bytes = (report.values['bytesSent'] as num?)?.toInt();
            if (bytes != null &&
                _lastBytesSent != null &&
                _lastStatsTimestamp != null) {
              final seconds =
                  now.difference(_lastStatsTimestamp!).inMilliseconds / 1000;
              if (seconds > 0) {
                bitrate = (bytes - _lastBytesSent!) * 8 / seconds / 1000;
              }
            }
            _lastBytesSent = bytes;
          } else if (report.type == 'candidate-pair' &&
              report.values['state'] == 'succeeded') {
            final rtt =
                (report.values['currentRoundTripTime'] as num?)?.toDouble();
            if (rtt != null) latency = (rtt * 1000).toInt();
          }
        }
        _lastStatsTimestamp = now;

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
