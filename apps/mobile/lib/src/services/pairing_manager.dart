import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_models/shared_models.dart';

class PairingManager {
  static final PairingManager instance = PairingManager._();
  PairingManager._();

  final Map<String, TrustedHost> _trustedHosts = {};
  String? _currentPendingPin;
  String? _pendingDeviceId;
  String? _pendingDeviceName;

  String? get currentPendingPin => _currentPendingPin;
  String? get pendingDeviceName => _pendingDeviceName;

  String generateNewPin(String deviceId, String deviceName) {
    final random = Random.secure();
    final pin = (100000 + random.nextInt(900000)).toString();
    _currentPendingPin = pin;
    _pendingDeviceId = deviceId;
    _pendingDeviceName = deviceName;
    debugPrint('[PAIRING] Generated PIN: $pin for device: $deviceName ($deviceId)');
    return pin;
  }

  bool verifyPin(String pin, String deviceId) {
    if (_currentPendingPin == null) return false;
    if (_currentPendingPin == pin && _pendingDeviceId == deviceId) {
      final token = 'tok_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(999999)}';
      _trustedHosts[deviceId] = TrustedHost(
        deviceId: deviceId,
        deviceName: _pendingDeviceName ?? 'Windows PC',
        authToken: token,
        pairedAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
      _currentPendingPin = null;
      _pendingDeviceId = null;
      _pendingDeviceName = null;
      return true;
    }
    return false;
  }

  bool isTrusted(String deviceId, String? authToken) {
    final host = _trustedHosts[deviceId];
    if (host == null) return false;
    if (authToken != null && host.authToken == authToken) {
      _trustedHosts[deviceId] = TrustedHost(
        deviceId: host.deviceId,
        deviceName: host.deviceName,
        authToken: host.authToken,
        pairedAt: host.pairedAt,
        lastConnectedAt: DateTime.now(),
      );
      return true;
    }
    return false;
  }

  void revokeHost(String deviceId) {
    _trustedHosts.remove(deviceId);
  }
}
