import 'package:meta/meta.dart';
import 'package:shared_models/shared_models.dart';
import 'protocol_message.dart';

@immutable
class StreamCommands {
  static const String start = 'stream.start';
  static const String stop = 'stream.stop';
  static const String resolution = 'stream.resolution';
  static const String fps = 'stream.fps';
  static const String bitrate = 'stream.bitrate';
  static const String orientation = 'stream.orientation';
  static const String mirror = 'stream.mirror';
  static const String codec = 'stream.codec';

  static ProtocolMessage createStart([VideoFormat? format]) {
    return ProtocolMessage.create(
      messageType: start,
      payload: format != null ? {'format': format.toJson()} : {},
    );
  }

  static ProtocolMessage createStop() {
    return ProtocolMessage.create(
      messageType: stop,
    );
  }

  static ProtocolMessage createResolution(VideoResolution res) {
    return ProtocolMessage.create(
      messageType: resolution,
      payload: res.toJson(),
    );
  }

  static ProtocolMessage createFps(int fps) {
    return ProtocolMessage.create(
      messageType: StreamCommands.fps,
      payload: {'fps': fps},
    );
  }

  static ProtocolMessage createBitrate(int bitrateKbps) {
    return ProtocolMessage.create(
      messageType: bitrate,
      payload: {'bitrateKbps': bitrateKbps},
    );
  }

  static ProtocolMessage createOrientation(int rotationDegrees) {
    return ProtocolMessage.create(
      messageType: orientation,
      payload: {'rotationDegrees': rotationDegrees},
    );
  }

  static ProtocolMessage createMirror(bool mirror) {
    return ProtocolMessage.create(
      messageType: StreamCommands.mirror,
      payload: {'mirror': mirror},
    );
  }

  static ProtocolMessage createCodec(VideoCodec codec) {
    return ProtocolMessage.create(
      messageType: StreamCommands.codec,
      payload: {'codec': codec.name},
    );
  }
}
