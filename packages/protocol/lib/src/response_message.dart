import 'package:meta/meta.dart';
import 'protocol_message.dart';

enum ResponseStatus {
  success,
  error,
  unsupported;

  static ResponseStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'error':
        return ResponseStatus.error;
      case 'unsupported':
        return ResponseStatus.unsupported;
      case 'success':
      default:
        return ResponseStatus.success;
    }
  }
}

@immutable
class ProtocolResponse {
  final ResponseStatus status;
  final String? errorMessage;
  final String? errorCode;
  final Map<String, dynamic> data;

  const ProtocolResponse({
    this.status = ResponseStatus.success,
    this.errorMessage,
    this.errorCode,
    this.data = const {},
  });

  bool get isSuccess => status == ResponseStatus.success;

  ProtocolMessage toMessage(String requestId) {
    return ProtocolMessage.create(
      messageType: 'response.${status.name}',
      requestId: requestId,
      payload: {
        'status': status.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (errorCode != null) 'errorCode': errorCode,
        'data': data,
      },
    );
  }

  factory ProtocolResponse.success([Map<String, dynamic> data = const {}]) {
    return ProtocolResponse(
      status: ResponseStatus.success,
      data: data,
    );
  }

  factory ProtocolResponse.error(String message, [String? code, Map<String, dynamic> data = const {}]) {
    return ProtocolResponse(
      status: ResponseStatus.error,
      errorMessage: message,
      errorCode: code,
      data: data,
    );
  }

  factory ProtocolResponse.unsupported([String feature = 'Feature not supported by device']) {
    return ProtocolResponse(
      status: ResponseStatus.unsupported,
      errorMessage: feature,
      errorCode: 'UNSUPPORTED_FEATURE',
    );
  }

  factory ProtocolResponse.fromMessage(ProtocolMessage msg) {
    final payload = msg.payload;
    final statusStr = payload['status'] as String? ?? 'success';
    return ProtocolResponse(
      status: ResponseStatus.fromString(statusStr),
      errorMessage: payload['errorMessage'] as String?,
      errorCode: payload['errorCode'] as String?,
      data: (payload['data'] as Map<String, dynamic>?) ?? {},
    );
  }
}
