const _sentinel = Object();

enum LGConnectionStatus { disconnected, connecting, connected, error }

class LGRigState {
  final LGConnectionStatus status;
  final String? ipAddress;
  final int port;
  final int screenCount;
  final int webPort;
  final int? latencyMs;
  final String? currentKml;
  final String? errorMessage;

  const LGRigState({
    this.status = LGConnectionStatus.disconnected,
    this.ipAddress,
    this.port = 22,
    this.screenCount = 5,
    this.webPort = 81,
    this.latencyMs,
    this.currentKml,
    this.errorMessage,
  });

  bool get isConnected => status == LGConnectionStatus.connected;

  LGRigState copyWith({
    LGConnectionStatus? status,
    String? ipAddress,
    int? port,
    int? screenCount,
    int? webPort,
    int? latencyMs,
    Object? currentKml = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return LGRigState(
      status: status ?? this.status,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      screenCount: screenCount ?? this.screenCount,
      webPort: webPort ?? this.webPort,
      latencyMs: latencyMs ?? this.latencyMs,
      currentKml: currentKml == _sentinel ? this.currentKml : currentKml as String?,
      errorMessage: errorMessage == _sentinel ? this.errorMessage : errorMessage as String?,
    );
  }

  @override
  String toString() =>
      'LGRigState(status: $status, ip: $ipAddress:$port, screens: $screenCount, webPort: $webPort)';
}
