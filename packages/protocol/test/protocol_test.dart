import 'package:flutter_test/flutter_test.dart';
import 'package:protocol/protocol.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  group('Protocol Tests', () {
    test('ProtocolMessage encode & decode', () {
      final msg = CameraCommands.createZoom(2.5);
      final jsonStr = msg.encode();
      final decoded = ProtocolMessage.decode(jsonStr);

      expect(decoded.protocolVersion, 1);
      expect(decoded.messageType, CameraCommands.zoom);
      expect(decoded.payload['zoom'], 2.5);
    });

    test('ProtocolResponse success & error generation', () {
      final success = ProtocolResponse.success({'status': 'ok'});
      final successMsg = success.toMessage('req_1');
      final parsedSuccess = ProtocolResponse.fromMessage(successMsg);

      expect(parsedSuccess.isSuccess, true);
      expect(parsedSuccess.data['status'], 'ok');

      final err = ProtocolResponse.error('Flash failed', 'HARDWARE_ERR');
      final errMsg = err.toMessage('req_2');
      final parsedErr = ProtocolResponse.fromMessage(errMsg);

      expect(parsedErr.isSuccess, false);
      expect(parsedErr.errorMessage, 'Flash failed');
      expect(parsedErr.errorCode, 'HARDWARE_ERR');
    });

    test('Stream commands encoding', () {
      final resMsg = StreamCommands.createResolution(VideoResolution.r1080p);
      expect(resMsg.messageType, StreamCommands.resolution);
      expect(resMsg.payload['width'], 1920);

      final fpsMsg = StreamCommands.createFps(60);
      expect(fpsMsg.messageType, StreamCommands.fps);
      expect(fpsMsg.payload['fps'], 60);
    });
  });
}
