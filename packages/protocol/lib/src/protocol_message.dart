import 'dart:convert';
import 'package:meta/meta.dart';

@immutable
class ProtocolMessage {
  static const int currentVersion = 1;

  final int protocolVersion;
  final String messageType;
  final String requestId;
  final int timestamp;
  final Map<String, dynamic> payload;

  const ProtocolMessage({
    this.protocolVersion = currentVersion,
    required this.messageType,
    required this.requestId,
    required this.timestamp,
    required this.payload,
  });

  factory ProtocolMessage.create({
    required String messageType,
    String? requestId,
    Map<String, dynamic>? payload,
  }) {
    final now = DateTime.now();
    return ProtocolMessage(
      protocolVersion: currentVersion,
      messageType: messageType,
      requestId: requestId ??
          '${now.millisecondsSinceEpoch}_${(now.microsecondsSinceEpoch % 1000).toString().padLeft(3, '0')}',
      timestamp: now.millisecondsSinceEpoch,
      payload: payload ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {
        'protocolVersion': protocolVersion,
        'messageType': messageType,
        'requestId': requestId,
        'timestamp': timestamp,
        'payload': payload,
      };

  String encode() => jsonEncode(toJson());

  factory ProtocolMessage.fromJson(Map<String, dynamic> json) {
    return ProtocolMessage(
      protocolVersion: (json['protocolVersion'] as num?)?.toInt() ?? 1,
      messageType: json['messageType'] as String? ?? 'unknown',
      requestId: json['requestId'] as String? ?? '',
      timestamp: (json['timestamp'] as num?)?.toInt() ?? 0,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
    );
  }

  factory ProtocolMessage.decode(String jsonString) {
    final decoded = jsonDecode(jsonString);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON map for ProtocolMessage');
    }
    return ProtocolMessage.fromJson(decoded);
  }

  @override
  String toString() =>
      'ProtocolMessage(type: $messageType, reqId: $requestId, payload: $payload)';
}
