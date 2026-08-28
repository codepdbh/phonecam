import 'package:meta/meta.dart';
import 'package:shared_models/shared_models.dart';
import 'protocol_message.dart';

@immutable
class SystemCommands {
  static const String getDeviceInfo = 'device.getInfo';
  static const String deviceInfo = 'device.info';
  static const String getCapabilities = 'device.getCapabilities';
  static const String capabilities = 'device.capabilities';
  static const String connectionStats = 'connection.stats';
  static const String ping = 'heartbeat.ping';
  static const String pong = 'heartbeat.pong';
  static const String pairingRequest = 'pairing.request';
  static const String pairingConfirm = 'pairing.confirm';
  static const String pairingResponse = 'pairing.response';

  static ProtocolMessage createGetDeviceInfo() {
    return ProtocolMessage.create(
      messageType: getDeviceInfo,
    );
  }

  static ProtocolMessage createDeviceInfo(DeviceInfo info) {
    return ProtocolMessage.create(
      messageType: deviceInfo,
      payload: info.toJson(),
    );
  }

  static ProtocolMessage createGetCapabilities() {
    return ProtocolMessage.create(
      messageType: getCapabilities,
    );
  }

  static ProtocolMessage createCapabilities(DeviceCapabilities caps) {
    return ProtocolMessage.create(
      messageType: capabilities,
      payload: caps.toJson(),
    );
  }

  static ProtocolMessage createStats(ConnectionStats stats) {
    return ProtocolMessage.create(
      messageType: connectionStats,
      payload: stats.toJson(),
    );
  }

  static ProtocolMessage createPing([int? sequence]) {
    return ProtocolMessage.create(
      messageType: ping,
      payload: {'seq': sequence ?? 0},
    );
  }

  static ProtocolMessage createPong([int? sequence]) {
    return ProtocolMessage.create(
      messageType: pong,
      payload: {'seq': sequence ?? 0},
    );
  }

  static ProtocolMessage createPairingRequest(PairingRequest request) {
    return ProtocolMessage.create(
      messageType: pairingRequest,
      payload: request.toJson(),
    );
  }

  static ProtocolMessage createPairingConfirm({
    required String pinCode,
    required bool accepted,
    String? token,
  }) {
    return ProtocolMessage.create(
      messageType: pairingConfirm,
      payload: {
        'pinCode': pinCode,
        'accepted': accepted,
        if (token != null) 'authToken': token,
      },
    );
  }
}
