import 'package:meta/meta.dart';
import 'protocol_message.dart';

@immutable
class CameraCommands {
  static const String switchCamera = 'camera.switch';
  static const String selectCamera = 'camera.select';
  static const String zoom = 'camera.zoom';
  static const String focus = 'camera.focus';
  static const String exposure = 'camera.exposure';
  static const String flash = 'camera.flash';

  static ProtocolMessage createSwitch() {
    return ProtocolMessage.create(
      messageType: CameraCommands.switchCamera,
    );
  }

  static ProtocolMessage createSelect(String cameraId) {
    return ProtocolMessage.create(
      messageType: CameraCommands.selectCamera,
      payload: {'cameraId': cameraId},
    );
  }

  static ProtocolMessage createZoom(double zoomFactor) {
    return ProtocolMessage.create(
      messageType: CameraCommands.zoom,
      payload: {'zoom': zoomFactor},
    );
  }

  static ProtocolMessage createFocus({double? x, double? y, bool auto = true}) {
    return ProtocolMessage.create(
      messageType: CameraCommands.focus,
      payload: {
        'auto': auto,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
      },
    );
  }

  static ProtocolMessage createExposure(double exposureOffset) {
    return ProtocolMessage.create(
      messageType: CameraCommands.exposure,
      payload: {'exposureOffset': exposureOffset},
    );
  }

  static ProtocolMessage createFlash(bool enable) {
    return ProtocolMessage.create(
      messageType: CameraCommands.flash,
      payload: {'torch': enable},
    );
  }
}
