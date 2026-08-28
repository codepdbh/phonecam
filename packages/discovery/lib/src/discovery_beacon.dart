import 'dart:convert';
import 'package:shared_models/shared_models.dart';

class DiscoveryBeacon {
  static const String magicHeader = 'PHONECAM_DISCOVERY_V1';

  final String type; // 'announce' or 'query'
  final DeviceInfo device;

  const DiscoveryBeacon({
    required this.type,
    required this.device,
  });

  Map<String, dynamic> toJson() => {
        'magic': magicHeader,
        'type': type,
        'device': device.toJson(),
      };

  List<int> toBytes() {
    return utf8.encode(jsonEncode(toJson()));
  }

  static DiscoveryBeacon? fromBytes(List<int> bytes, String remoteAddress) {
    try {
      final jsonStr = utf8.decode(bytes);
      final map = jsonDecode(jsonStr);
      if (map is! Map<String, dynamic>) return null;
      if (map['magic'] != magicHeader) return null;

      final devJson = map['device'] as Map<String, dynamic>?;
      if (devJson == null) return null;

      // If ipAddress in beacon is empty or 0.0.0.0, use the socket remote address
      if (devJson['ipAddress'] == null ||
          devJson['ipAddress'] == '' ||
          devJson['ipAddress'] == '0.0.0.0') {
        devJson['ipAddress'] = remoteAddress;
      }

      final device = DeviceInfo.fromJson(devJson);
      return DiscoveryBeacon(
        type: map['type'] as String? ?? 'announce',
        device: device,
      );
    } catch (_) {
      return null;
    }
  }
}
