enum AppConnectionState {
  idle,
  discovering,
  connecting,
  pairing,
  connected,
  streaming,
  reconnecting,
  disconnected,
  error;

  String get label {
    switch (this) {
      case AppConnectionState.idle:
        return 'Idle';
      case AppConnectionState.discovering:
        return 'Discovering';
      case AppConnectionState.connecting:
        return 'Connecting...';
      case AppConnectionState.pairing:
        return 'Pairing...';
      case AppConnectionState.connected:
        return 'Connected';
      case AppConnectionState.streaming:
        return 'Streaming';
      case AppConnectionState.reconnecting:
        return 'Reconnecting...';
      case AppConnectionState.disconnected:
        return 'Disconnected';
      case AppConnectionState.error:
        return 'Error';
    }
  }

  bool get isConnectedOrStreaming =>
      this == AppConnectionState.connected || this == AppConnectionState.streaming;

  bool get isConnectingOrPairing =>
      this == AppConnectionState.connecting ||
      this == AppConnectionState.pairing ||
      this == AppConnectionState.reconnecting;
}
