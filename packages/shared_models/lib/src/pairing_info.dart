import 'package:meta/meta.dart';

enum PairingStatus {
  unpaired,
  pendingPin,
  paired,
  rejected,
  expired;

  static PairingStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'pending':
      case 'pendingpin':
        return PairingStatus.pendingPin;
      case 'paired':
      case 'authorized':
        return PairingStatus.paired;
      case 'rejected':
      case 'denied':
        return PairingStatus.rejected;
      case 'expired':
        return PairingStatus.expired;
      case 'unpaired':
      default:
        return PairingStatus.unpaired;
    }
  }
}

@immutable
class PairingRequest {
  final String clientDeviceId;
  final String clientDeviceName;
  final String pinCode;
  final DateTime timestamp;

  const PairingRequest({
    required this.clientDeviceId,
    required this.clientDeviceName,
    required this.pinCode,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'clientDeviceId': clientDeviceId,
        'clientDeviceName': clientDeviceName,
        'pinCode': pinCode,
        'timestamp': timestamp.toIso8601String(),
      };

  factory PairingRequest.fromJson(Map<String, dynamic> json) {
    return PairingRequest(
      clientDeviceId: json['clientDeviceId'] as String? ?? '',
      clientDeviceName: json['clientDeviceName'] as String? ?? 'Windows PC',
      pinCode: json['pinCode'] as String? ?? '000000',
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

@immutable
class PairingResponse {
  final bool success;
  final String? authToken;
  final String? errorMessage;

  const PairingResponse({
    required this.success,
    this.authToken,
    this.errorMessage,
  });

  Map<String, dynamic> toJson() => {
        'success': success,
        'authToken': authToken,
        'errorMessage': errorMessage,
      };

  factory PairingResponse.fromJson(Map<String, dynamic> json) {
    return PairingResponse(
      success: json['success'] as bool? ?? false,
      authToken: json['authToken'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

@immutable
class TrustedHost {
  final String deviceId;
  final String deviceName;
  final String authToken;
  final DateTime pairedAt;
  final DateTime lastConnectedAt;

  const TrustedHost({
    required this.deviceId,
    required this.deviceName,
    required this.authToken,
    required this.pairedAt,
    required this.lastConnectedAt,
  });

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'authToken': authToken,
        'pairedAt': pairedAt.toIso8601String(),
        'lastConnectedAt': lastConnectedAt.toIso8601String(),
      };

  factory TrustedHost.fromJson(Map<String, dynamic> json) {
    return TrustedHost(
      deviceId: json['deviceId'] as String? ?? '',
      deviceName: json['deviceName'] as String? ?? '',
      authToken: json['authToken'] as String? ?? '',
      pairedAt: json['pairedAt'] != null
          ? DateTime.tryParse(json['pairedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastConnectedAt: json['lastConnectedAt'] != null
          ? DateTime.tryParse(json['lastConnectedAt'] as String) ??
              DateTime.now()
          : DateTime.now(),
    );
  }
}
