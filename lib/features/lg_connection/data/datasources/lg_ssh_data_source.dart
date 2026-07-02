import 'dart:async';
import 'package:dartssh2/dartssh2.dart';

abstract class LgSshDataSource {
  Future<SSHClient> connect({
    required String ipAddress,
    required int port,
    required String username,
    required String password,
  });
  Future<String> execute(SSHClient client, String command);
  Future<void> disconnect(SSHClient? client);
}

class LgSshDataSourceImpl implements LgSshDataSource {
  @override
  Future<SSHClient> connect({
    required String ipAddress,
    required int port,
    required String username,
    required String password,
  }) async {
    final socket = await SSHSocket.connect(
      ipAddress,
      port,
      timeout: const Duration(seconds: 10),
    );
    final client = SSHClient(
      socket,
      username: username,
      onPasswordRequest: () => password,
    );
    await client.authenticated;
    return client;
  }

  @override
  Future<String> execute(SSHClient client, String command) async {
    final result = await client.run(command);
    return String.fromCharCodes(result);
  }

  @override
  Future<void> disconnect(SSHClient? client) async {
    client?.close();
  }
}
