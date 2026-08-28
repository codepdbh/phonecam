abstract class PhoneCamException implements Exception {
  final String message;
  final String? code;
  final dynamic details;

  const PhoneCamException(this.message, {this.code, this.details});

  @override
  String toString() =>
      code != null ? '[$code] $message' : 'PhoneCamException: $message';
}

class CameraUnavailableException extends PhoneCamException {
  const CameraUnavailableException([
    String message = 'Camera is unavailable or in use by another app',
    dynamic details,
  ]) : super(message, code: 'CAMERA_UNAVAILABLE', details: details);
}

class PermissionDeniedException extends PhoneCamException {
  final String permission;
  const PermissionDeniedException({
    this.permission = 'Camera',
    String message = 'Required permission was denied',
    dynamic details,
  }) : super(message, code: 'PERMISSION_DENIED', details: details);
}

class NetworkUnavailableException extends PhoneCamException {
  const NetworkUnavailableException([
    String message = 'Local network is unavailable or disconnected',
    dynamic details,
  ]) : super(message, code: 'NETWORK_UNAVAILABLE', details: details);
}

class PeerDisconnectedException extends PhoneCamException {
  const PeerDisconnectedException([
    String message = 'Remote peer disconnected unexpectedly',
    dynamic details,
  ]) : super(message, code: 'PEER_DISCONNECTED', details: details);
}

class UnsupportedResolutionException extends PhoneCamException {
  final int width;
  final int height;
  UnsupportedResolutionException(this.width, this.height,
      [String message =
          'Selected resolution is not supported by the hardware'])
      : super(message,
            code: 'UNSUPPORTED_RESOLUTION',
            details: {'width': width, 'height': height});
}

class VirtualCameraInitializationFailedException extends PhoneCamException {
  const VirtualCameraInitializationFailedException([
    String message =
        'Failed to initialize Windows Media Foundation Virtual Camera API',
    dynamic details,
  ]) : super(message, code: 'VIRTUAL_CAMERA_INIT_FAILED', details: details);
}

class VirtualCameraRegistrationFailedException extends PhoneCamException {
  const VirtualCameraRegistrationFailedException([
    String message =
        'Failed to register PhoneCam Virtual Camera in Windows device tree',
    dynamic details,
  ]) : super(message, code: 'VIRTUAL_CAMERA_REG_FAILED', details: details);
}

class WebRtcNegotiationException extends PhoneCamException {
  const WebRtcNegotiationException([
    String message = 'WebRTC SDP or ICE candidate negotiation failed',
    dynamic details,
  ]) : super(message, code: 'WEBRTC_NEGOTIATION_FAILED', details: details);
}

class PairingRejectedException extends PhoneCamException {
  const PairingRejectedException([
    String message = 'Pairing was rejected or PIN verification failed',
    dynamic details,
  ]) : super(message, code: 'PAIRING_REJECTED', details: details);
}

class ProtocolVersionMismatchException extends PhoneCamException {
  final int expected;
  final int received;
  ProtocolVersionMismatchException(this.expected, this.received)
      : super(
          'Incompatible protocol version. Expected $expected, got $received',
          code: 'PROTOCOL_VERSION_MISMATCH',
          details: {'expected': expected, 'received': received},
        );
}
