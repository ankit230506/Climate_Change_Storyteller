import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Single access point for all securely stored credentials.
/// Keys are encrypted on-device via flutter_secure_storage —
/// never stored in plain text, never sent to third-party servers.
class SecureStorageService {
  SecureStorageService._();
  static final SecureStorageService instance = SecureStorageService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ── Key names ────────────────────────────────────────────────────────────
  static const _kGeminiKey = 'gemini_api_key';
  static const _kNoaaKey   = 'noaa_api_key';
  static const _kLgIp      = 'lg_ip';
  static const _kLgPort    = 'lg_port';
  static const _kLgUser    = 'lg_username';
  static const _kLgPass    = 'lg_password';

  // ── Gemini API key (required) ────────────────────────────────────────────
  Future<void> saveGeminiKey(String key) =>
      _storage.write(key: _kGeminiKey, value: key.trim());

  Future<String?> getGeminiKey() => _storage.read(key: _kGeminiKey);

  Future<bool> hasGeminiKey() async {
    final k = await getGeminiKey();
    return k != null && k.isNotEmpty;
  }

  // ── NOAA API key (optional — free, register at ncei.noaa.gov) ───────────
  Future<void> saveNoaaKey(String key) =>
      _storage.write(key: _kNoaaKey, value: key.trim());

  Future<String?> getNoaaKey() => _storage.read(key: _kNoaaKey);

  // ── LG rig connection details ────────────────────────────────────────────
  Future<void> saveLgCredentials({
    required String ip,
    required int port,
    required String username,
    required String password,
  }) async {
    await Future.wait([
      _storage.write(key: _kLgIp,   value: ip),
      _storage.write(key: _kLgPort, value: port.toString()),
      _storage.write(key: _kLgUser, value: username),
      _storage.write(key: _kLgPass, value: password),
    ]);
  }

  Future<Map<String, String?>> getLgCredentials() async {
    final results = await Future.wait([
      _storage.read(key: _kLgIp),
      _storage.read(key: _kLgPort),
      _storage.read(key: _kLgUser),
      _storage.read(key: _kLgPass),
    ]);
    return {
      'ip':       results[0],
      'port':     results[1],
      'username': results[2],
      'password': results[3],
    };
  }

  Future<void> clearAll() => _storage.deleteAll();
}