import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingClient {
  WebSocket? _socket;
  final String host;
  final int port;

  final _onMessageController =
      StreamController<Map<String, dynamic>>.broadcast();
  final _onStateChangeController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _onMessageController.stream;
  Stream<bool> get onStateChange => _onStateChangeController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  SignalingClient({required this.host, this.port = 41236});

  Future<bool> connect() async {
    disconnect();
    try {
      final wsUrl = 'ws://$host:$port/ws';
      debugPrint('[SIGNALING] Connecting to $wsUrl');
      _socket =
          await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 4));
      _isConnected = true;
      _onStateChangeController.add(true);

      _socket?.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String) as Map<String, dynamic>;
            _onMessageController.add(decoded);
          } catch (e) {
            debugPrint('[SIGNALING] JSON Parse error: $e');
          }
        },
        onError: (err) {
          debugPrint('[SIGNALING] Socket error: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('[SIGNALING] Socket closed');
          _handleDisconnect();
        },
      );

      return true;
    } catch (e) {
      debugPrint('[SIGNALING] Connection failed: $e');
      _handleDisconnect();
      return false;
    }
  }

  void send(Map<String, dynamic> message) {
    if (_socket != null && _isConnected) {
      _socket?.add(jsonEncode(message));
    }
  }

  void sendOffer(RTCSessionDescription offer) {
    send({
      'type': 'offer',
      'sdp': offer.sdp,
      'sdpType': offer.type,
    });
  }

  void sendAnswer(RTCSessionDescription answer) {
    send({
      'type': 'answer',
      'sdp': answer.sdp,
      'sdpType': answer.type,
    });
  }

  void sendCandidate(RTCIceCandidate candidate) {
    send({
      'type': 'candidate',
      'candidate': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      }
    });
  }

  void _handleDisconnect() {
    _isConnected = false;
    _onStateChangeController.add(false);
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
    _handleDisconnect();
  }

  void dispose() {
    disconnect();
    _onMessageController.close();
    _onStateChangeController.close();
  }
}
