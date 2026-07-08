import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import 'package:climate_storyteller/features/lg_connection/lg_rig_state.dart';
import 'package:climate_storyteller/features/explore/kml_cache_screen.dart';
import 'package:climate_storyteller/features/explore/api_setup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text('Settings', style: AppTypography.heading1),
              const SizedBox(height: 24),

              // LG connection
              StreamBuilder<LGRigState>(
                stream: DI.lgService.stateStream,
                initialData: DI.lgService.state,
                builder: (context, snap) {
                  final rig = snap.data!;
                  return Column(children: [
                    LGStatusCard(rigState: rig,
                        onTap: () => _openConnect(context)),
                    const SizedBox(height: 8),
                    if (rig.isConnected)
                      OutlinedButton.icon(
                        onPressed: () async {
                          await DI.lgService.disconnect();
                        },
                        icon: const Icon(Icons.link_off,
                            size: 18, color: AppColors.critical),
                        label: const Text('Disconnect'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.critical,
                          side: const BorderSide(
                              color: AppColors.critical, width: 1),
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: () => _openConnect(context),
                        icon: const Icon(Icons.cable,
                            size: 18, color: AppColors.bg0),
                        label: const Text('Connect to LG Rig'),
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 28),

              const SectionHeader(title: 'Application'),
              _Tile(icon: Icons.language, title: 'Language',
                  subtitle: 'English', onTap: () {}),
              _Tile(icon: Icons.storage_outlined, title: 'Data Sources',
                  subtitle: 'NASA GIBS, NOAA, IPCC AR6, OpenAQ',
                  onTap: () {}),

              // KML Cache
              _Tile(
                icon: Icons.folder_outlined,
                title: 'KML Cache',
                subtitle: 'Download offline KML files for demo day',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(
                        builder: (_) => const KmlCacheScreen())),
              ),
              const SizedBox(height: 20),

              const SectionHeader(title: 'API Keys'),
              _Tile(icon: Icons.vpn_key_outlined, title: 'API Setup',
                  subtitle: 'Gemini API key, Flutter TTS',
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(
                          builder: (_) => const ApiSetupScreen()))),
              const SizedBox(height: 20),

              const SectionHeader(title: 'About'),
              _Tile(icon: Icons.info_outline,
                  title: 'Climate Change Storyteller',
                  subtitle: 'GSoC 2026 · Liquid Galaxy Project · v1.0.0',
                  onTap: () {}),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _openConnect(BuildContext context) {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LGConnectScreen()));
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;

  const _Tile({required this.icon, required this.title,
      required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2235)),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTypography.bodyLarge),
              Text(subtitle, style: AppTypography.bodySmall),
            ],
          )),
          const Icon(Icons.chevron_right,
              color: AppColors.textMuted, size: 20),
        ]),
      ),
    );
  }
}

class LGConnectScreen extends StatefulWidget {
  const LGConnectScreen({super.key});
  @override
  State<LGConnectScreen> createState() => _LGConnectScreenState();
}

class _LGConnectScreenState extends State<LGConnectScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _ipCtrl   = TextEditingController(text: '192.168.56.101');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'lg');
  final _passCtrl = TextEditingController(text: 'lg');
  final _screenCtrl= TextEditingController(text: '3');
  bool _obscurePass  = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _ipCtrl.dispose(); _portCtrl.dispose();
    _userCtrl.dispose(); _passCtrl.dispose();
    _screenCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim().isEmpty ? 'lg' : _userCtrl.text.trim();
    final pass = _passCtrl.text.isEmpty ? 'lg' : _passCtrl.text;
    final screens = int.tryParse(_screenCtrl.text.trim()) ?? 5;

    if (ip.isEmpty) { _showError('Please enter an IP address'); return; }

    setState(() => _isConnecting = true);
    try {
      final ok = await DI.lgService.connect(
        ipAddress: ip, port: port, username: user, password: pass, screenCount: screens);
      if (!mounted) return;
      if (ok) {
        final screens = DI.lgService.state.screenCount;
        final latency = DI.lgService.state.latencyMs;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Connected! $screens screens · ${latency}ms'),
          ]),
          backgroundColor: AppColors.good,
        ));
        Navigator.pop(context);
      } else {
        _showError('Connection refused — check IP, port and credentials');
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  void _onQrScanned(String raw) {
    String ip = raw.trim();
    int port = 22;
    if (ip.startsWith('lg://')) ip = ip.replaceFirst('lg://', '');
    if (ip.contains(':')) {
      final parts = ip.split(':');
      ip = parts[0]; port = int.tryParse(parts[1]) ?? 22;
    }
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (!ipPattern.hasMatch(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invalid IP in QR: $raw'),
        backgroundColor: AppColors.critical));
      return;
    }
    _ipCtrl.text = ip; _portCtrl.text = port.toString();
    _tabs.animateTo(0);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Scanned: $ip:$port'),
      backgroundColor: AppColors.primary.withValues(alpha: 0.9)));
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.critical));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Connect to LG Rig'),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.edit_outlined), text: 'Manual'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR Scan'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _ManualTab(ipCtrl: _ipCtrl, portCtrl: _portCtrl,
          userCtrl: _userCtrl, passCtrl: _passCtrl, screenCtrl: _screenCtrl,
          obscurePass: _obscurePass, isConnecting: _isConnecting,
          onTogglePass: () => setState(() => _obscurePass = !_obscurePass),
          onConnect: _connect),
        _QrTab(onScanned: _onQrScanned),
      ]),
    );
  }
}

class _ManualTab extends StatelessWidget {
  final TextEditingController ipCtrl, portCtrl, userCtrl, passCtrl, screenCtrl;
  final bool obscurePass, isConnecting;
  final VoidCallback onTogglePass, onConnect;

  const _ManualTab({required this.ipCtrl, required this.portCtrl,
      required this.userCtrl, required this.passCtrl, required this.screenCtrl,
      required this.obscurePass, required this.isConnecting,
      required this.onTogglePass, required this.onConnect});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StreamBuilder<LGRigState>(
            stream: DI.lgService.stateStream,
            initialData: DI.lgService.state,
            builder: (_, s) => LGStatusCard(rigState: s.data!)),
          const SizedBox(height: 24),
          const SectionHeader(title: 'LG Rig Address'),
          Row(children: [
            Expanded(flex: 3, child: TextField(controller: ipCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(
                labelText: 'IP Address', hintText: '192.168.x.x'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: portCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: const InputDecoration(labelText: 'Port'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: screenCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Screens'))),
          ]),
          const SizedBox(height: 16),
          const SectionHeader(title: 'SSH Credentials'),
          TextField(controller: userCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(labelText: 'Username')),
          const SizedBox(height: 12),
          TextField(controller: passCtrl, obscureText: obscurePass,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(obscurePass ? Icons.visibility_off
                    : Icons.visibility, size: 18),
                onPressed: onTogglePass))),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: isConnecting ? null : onConnect,
            icon: isConnecting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.bg0))
                : const Icon(Icons.link, size: 18, color: AppColors.bg0),
            label: Text(isConnecting ? 'Connecting…' : 'Connect to LG Rig')),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _QrTab extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrTab({required this.onScanned});
  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanning = false, _hasScanned = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _startScanning() {
    setState(() { _scanning = true; _hasScanned = false; });
    _controller.start();
  }

  void _stopScanning() {
    setState(() => _scanning = false);
    _controller.stop();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_hasScanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _hasScanned = true;
    _stopScanning();
    widget.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 280,
            decoration: BoxDecoration(color: const Color(0xFF080E1A),
              border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.5), width: 2),
              borderRadius: BorderRadius.circular(20)),
            child: _scanning
                ? MobileScanner(controller: _controller,
                    onDetect: _handleDetection)
                : Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.qr_code_2, size: 80,
                          color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      const Text('Tap Start Scan to open camera',
                          style: TextStyle(fontSize: 13,
                              color: AppColors.textSecondary)),
                    ])),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: _scanning ? _stopScanning : _startScanning,
          icon: Icon(_scanning ? Icons.stop : Icons.qr_code_scanner,
              size: 18, color: AppColors.bg0),
          label: Text(_scanning ? 'Stop Scanning' : 'Start Scan'),
          style: _scanning
              ? ElevatedButton.styleFrom(backgroundColor: AppColors.critical)
              : null),
        const SizedBox(height: 32),
      ]),
    );
  }
}
