import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class SignalingServer {
  HttpServer? _server;
  final List<WebSocket> _clients = [];
  final int port;

  final _onOfferController = StreamController<Map<String, dynamic>>.broadcast();
  final _onCandidateController = StreamController<Map<String, dynamic>>.broadcast();
  final _onClientConnectedController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get onOffer => _onOfferController.stream;
  Stream<Map<String, dynamic>> get onCandidate => _onCandidateController.stream;
  Stream<bool> get onClientConnected => _onClientConnectedController.stream;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  SignalingServer({this.port = 41236});

  Future<bool> start() async {
    if (_isRunning) return true;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
      _isRunning = true;
      debugPrint('[SIGNALING_SERVER] Listening on 0.0.0.0:$port');

      _server!.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleClient(socket);
          }).catchError((err) {
            debugPrint('[SIGNALING_SERVER] Upgrade error: $err');
          });
        } else if (request.uri.path == '/ping') {
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(jsonEncode({'status': 'ok', 'app': 'phonecam'}))
            ..close();
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..close();
        }
      });

      return true;
    } catch (e) {
      debugPrint('[SIGNALING_SERVER] Failed to start server: $e');
      return false;
    }
  }

  void _handleClient(WebSocket socket) {
    debugPrint('[SIGNALING_SERVER] Client connected via WebSocket');
    _clients.add(socket);
    _onClientConnectedController.add(true);

    socket.listen(
      (data) {
        try {
          final decoded = jsonDecode(data as String) as Map<String, dynamic>;
          final type = decoded['type'] as String?;

          if (type == 'offer') {
            _onOfferController.add(decoded);
          } else if (type == 'candidate') {
            _onCandidateController.add(decoded);
          }
        } catch (e) {
          debugPrint('[SIGNALING_SERVER] Message parsing error: $e');
        }
      },
      onError: (err) {
        debugPrint('[SIGNALING_SERVER] Client socket error: $err');
        _removeClient(socket);
      },
      onDone: () {
        debugPrint('[SIGNALING_SERVER] Client socket closed');
        _removeClient(socket);
      },
    );
  }

  void _removeClient(WebSocket socket) {
    _clients.remove(socket);
    if (_clients.isEmpty) {
      _onClientConnectedController.add(false);
    }
  }

  void sendAnswer(String sdp) {
    _broadcast({
      'type': 'answer',
      'sdp': sdp,
      'sdpType': 'answer',
    });
  }

  void sendCandidate(String candidate, String? sdpMid, int? sdpMLineIndex) {
    _broadcast({
      'type': 'candidate',
      'candidate': {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      }
    });
  }

  void sendPairingRequired(String pin) {
    _broadcast({
      'type': 'pairing_required',
      'pin': pin,
    });
  }

  void _broadcast(Map<String, dynamic> msg) {
    final str = jsonEncode(msg);
    for (final client in _clients) {
      try {
        client.add(str);
      } catch (_) {}
    }
  }

  Future<void> stop() async {
    for (final client in _clients) {
      await client.close();
    }
    _clients.clear();
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
  }

  void dispose() {
    stop();
    _onOfferController.close();
    _onCandidateController.close();
    _onClientConnectedController.close();
  }
}
