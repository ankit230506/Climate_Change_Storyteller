import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';

/// FEATURE: Settings Screen + LG Connect with real QR scanner
///
/// PURPOSE:
/// Settings tab shows LG connection status + link to API setup.
/// LGConnectScreen has 2 tabs: Manual IP entry + QR Scanner.
///
/// QR SCANNER:
/// Uses mobile_scanner package — works on Android camera AND
/// Chrome web (browser camera permission).
/// Expected QR format on LG rig: "lg://192.168.x.x:22"
///   or just plain IP "192.168.x.x"
///
/// HOW IT WORKS:
///   1. User taps QR Scan tab
///   2. Camera opens via MobileScanner widget
///   3. onDetect callback fires when QR is found
///   4. We parse the string → extract IP + port
///   5. Auto-fill the Manual tab fields
///   6. Switch to Manual tab so user can verify before connecting
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

              // ── LG Rig connection card ──────────────
              StreamBuilder<LGRigState>(
                stream: LGSSHService.instance.stateStream,
                initialData: LGSSHService.instance.state,
                builder: (context, snap) {
                  final rig = snap.data!;
                  return Column(
                    children: [
                      LGStatusCard(
                        rigState: rig,
                        onTap: () => _openConnect(context),
                      ),
                      const SizedBox(height: 8),
                      if (rig.isConnected)
                        OutlinedButton.icon(
                          onPressed: () async {
                            await LGSSHService.instance.disconnect();
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
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),

              const SectionHeader(title: 'Application'),
              _Tile(icon: Icons.language, title: 'Language',
                  subtitle: 'English', onTap: () {}),
              _Tile(icon: Icons.storage_outlined, title: 'Data Sources',
                  subtitle: 'NASA GIBS, NOAA, IPCC AR6', onTap: () {}),
              _Tile(icon: Icons.folder_outlined, title: 'KML Cache',
                  subtitle: 'Manage offline layers', onTap: () {}),
              const SizedBox(height: 20),

              const SectionHeader(title: 'API Keys'),
              _Tile(icon: Icons.vpn_key_outlined, title: 'API Setup',
                  subtitle: 'Gemini, Google TTS, credentials',
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
  final String title;
  final String subtitle;
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

// ═══════════════════════════════════════════════════════════════════════════
// LG CONNECT SCREEN — Manual + QR tabs
// ═══════════════════════════════════════════════════════════════════════════

class LGConnectScreen extends StatefulWidget {
  const LGConnectScreen({super.key});

  @override
  State<LGConnectScreen> createState() => _LGConnectScreenState();
}

class _LGConnectScreenState extends State<LGConnectScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _ipCtrl   = TextEditingController(text: '192.168.29.124');
  final _portCtrl = TextEditingController(text: '22');
  final _userCtrl = TextEditingController(text: 'lg');
  final _passCtrl = TextEditingController(text: 'lq');
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
    _ipCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final ip   = _ipCtrl.text.trim();
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    final user = _userCtrl.text.trim().isEmpty ? 'lg' : _userCtrl.text.trim();
    final pass = _passCtrl.text.isEmpty ? 'lq' : _passCtrl.text;

    if (ip.isEmpty) { _showError('Please enter an IP address'); return; }

    setState(() => _isConnecting = true);
    try {
      final ok = await LGSSHService.instance.connect(
        ipAddress: ip, port: port, username: user, password: pass);

      if (!mounted) return;

      if (ok) {
        final screens = LGSSHService.instance.state.screenCount;
        final latency = LGSSHService.instance.state.latencyMs;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Connected! $screens screens · ${latency}ms'),
          ]),
          backgroundColor: AppColors.good,
          duration: const Duration(seconds: 3),
        ));
        Navigator.pop(context);
      } else {
        _showError('Connection refused — check IP, port and credentials');
      }
    } catch (e) {
      _showError(e.toString());
      debugPrint('[Connect] Full error: $e');
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  /// ── QR SCAN RESULT HANDLER ────────────────────────────────────────────
  /// Called by mobile_scanner when a QR code is detected.
  /// Parses formats:
  ///   "lg://192.168.29.124:22"
  ///   "192.168.29.124:22"
  ///   "192.168.29.124"  (defaults port to 22)
  void _onQrScanned(String raw) {
    String ip = raw.trim();
    int port = 22;

    if (ip.startsWith('lg://')) ip = ip.replaceFirst('lg://', '');
    if (ip.contains(':')) {
      final parts = ip.split(':');
      ip   = parts[0];
      port = int.tryParse(parts[1]) ?? 22;
    }

    // Basic validation — must look like an IP
    final ipPattern = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');
    if (!ipPattern.hasMatch(ip)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('QR code doesn\'t contain a valid IP: $raw'),
        backgroundColor: AppColors.critical,
      ));
      return;
    }

    _ipCtrl.text   = ip;
    _portCtrl.text = port.toString();

    // Switch to Manual tab so user can verify before connecting
    _tabs.animateTo(0);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✓ Scanned: $ip:$port — tap Connect to proceed'),
      backgroundColor: AppColors.primary.withOpacity(0.9),
    ));
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
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(Icons.edit_outlined), text: 'Manual'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'QR Scan'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ManualTab(
            ipCtrl: _ipCtrl, portCtrl: _portCtrl,
            userCtrl: _userCtrl, passCtrl: _passCtrl,
            obscurePass: _obscurePass, isConnecting: _isConnecting,
            onTogglePass: () =>
                setState(() => _obscurePass = !_obscurePass),
            onConnect: _connect,
          ),
          _QrTab(onScanned: _onQrScanned),
        ],
      ),
    );
  }
}

// ── Manual tab ────────────────────────────────────────────────────────────────
class _ManualTab extends StatelessWidget {
  final TextEditingController ipCtrl, portCtrl, userCtrl, passCtrl;
  final bool obscurePass, isConnecting;
  final VoidCallback onTogglePass, onConnect;

  const _ManualTab({
    required this.ipCtrl, required this.portCtrl,
    required this.userCtrl, required this.passCtrl,
    required this.obscurePass, required this.isConnecting,
    required this.onTogglePass, required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          StreamBuilder<LGRigState>(
            stream: LGSSHService.instance.stateStream,
            initialData: LGSSHService.instance.state,
            builder: (_, s) => LGStatusCard(rigState: s.data!),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'LG Rig Address'),
          Row(children: [
            Expanded(flex: 3, child: TextField(
              controller: ipCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'IP Address', hintText: '192.168.x.x',
                prefixIcon: Icon(Icons.computer_outlined,
                    color: AppColors.textMuted, size: 20),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: TextField(
              controller: portCtrl,
              style: const TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            )),
          ]),
          const SizedBox(height: 16),

          const SectionHeader(title: 'SSH Credentials'),
          TextField(
            controller: userCtrl,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Username', hintText: 'lg',
              prefixIcon: Icon(Icons.person_outline,
                  color: AppColors.textMuted, size: 20)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: passCtrl,
            obscureText: obscurePass,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Password', hintText: 'lq',
              prefixIcon: const Icon(Icons.lock_outline,
                  color: AppColors.textMuted, size: 20),
              suffixIcon: IconButton(
                icon: Icon(obscurePass
                    ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textMuted, size: 18),
                onPressed: onTogglePass,
              ),
            ),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.bg3,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.textMuted, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Uses SSH over local Wi-Fi — same protocol as lg-web.\n'
                  'No cloud relay needed. Default LG credentials: lg / lq',
                  style: AppTypography.bodySmall,
                )),
              ]),
          ),
          const SizedBox(height: 28),

          ElevatedButton.icon(
            onPressed: isConnecting ? null : onConnect,
            icon: isConnecting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.bg0))
                : const Icon(Icons.link, size: 18, color: AppColors.bg0),
            label: Text(isConnecting ? 'Connecting…' : 'Connect to LG Rig'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// QR SCANNER TAB — REAL mobile_scanner implementation
// ════════════════════════════════════════════════════════════════════════════

class _QrTab extends StatefulWidget {
  final ValueChanged<String> onScanned;
  const _QrTab({required this.onScanned});

  @override
  State<_QrTab> createState() => _QrTabState();
}

class _QrTabState extends State<_QrTab> {
  // MobileScannerController controls the camera + torch + facing
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _scanning   = false;
  bool _hasScanned = false; // prevent multiple triggers from one scan
  String? _errorMsg;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startScanning() {
    setState(() {
      _scanning   = true;
      _hasScanned = false;
      _errorMsg   = null;
    });
    _controller.start();
  }

  void _stopScanning() {
    setState(() => _scanning = false);
    _controller.stop();
  }

  /// Called every time MobileScanner detects ANY barcode/QR
  void _handleDetection(BarcodeCapture capture) {
    if (_hasScanned) return; // ignore repeat triggers

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    // Mark as scanned to prevent duplicate callbacks
    _hasScanned = true;
    _stopScanning();

    // Pass result up to parent (LGConnectScreen)
    widget.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        const SizedBox(height: 4),

        // ── Camera viewfinder ─────────────────────────────────────────
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Container(
            height: 280,
            decoration: BoxDecoration(
              color: const Color(0xFF080E1A),
              border: Border.all(
                color: AppColors.primary.withOpacity(0.5),
                width: 2,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: _scanning
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Real camera feed ──
                      MobileScanner(
                        controller: _controller,
                        onDetect: _handleDetection,
                        errorBuilder: (context, error, child) {
                          // Camera permission denied or unavailable
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.videocam_off,
                                      size: 48,
                                      color: AppColors.critical),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Camera error:\n${error.errorCode}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.critical),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Allow camera permission and try again',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),

                      // Corner brackets overlay
                      ..._corners(),

                      // Scanning hint text
                      Positioned(
                        bottom: 16, left: 0, right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Point camera at QR code on LG screen',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2, size: 80,
                            color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        const Text(
                          'Tap Start Scan to open camera',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),

        // ── Instructions ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E2235)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.info_outline,
                    color: AppColors.secondary, size: 18),
                const SizedBox(width: 8),
                Text('How to use', style: AppTypography.bodyLarge
                    .copyWith(color: AppColors.secondary)),
              ]),
              const SizedBox(height: 10),
              _step('1', 'On the LG rig master, open the LG connection page'),
              _step('2', 'A QR code with the rig IP will appear on screen'),
              _step('3', 'Tap Start Scan below and point your camera at it'),
              _step('4', 'IP and port auto-fill — switches to Manual tab'),
            ]),
        ),
        const SizedBox(height: 24),

        // ── Scan / Stop button ────────────────────────────────────────
        ElevatedButton.icon(
          onPressed: _scanning ? _stopScanning : _startScanning,
          icon: Icon(_scanning ? Icons.stop : Icons.qr_code_scanner,
              size: 18, color: AppColors.bg0),
          label: Text(_scanning ? 'Stop Scanning' : 'Start Scan'),
          style: _scanning
              ? ElevatedButton.styleFrom(
                  backgroundColor: AppColors.critical)
              : null,
        ),

        // Torch toggle — only show while scanning
        if (_scanning) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(Icons.flash_on, size: 18),
            label: const Text('Toggle Flashlight'),
          ),
        ],

        const SizedBox(height: 12),
        Text('QR format: lg://192.168.x.x:22 or plain IP',
            style: AppTypography.caption, textAlign: TextAlign.center),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _step(String num, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 20, height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withOpacity(0.15)),
        child: Center(child: Text(num, style: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.primary))),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: AppTypography.bodySmall)),
    ]),
  );

  List<Widget> _corners() {
    const size = 24.0, thick = 3.0, color = AppColors.primary, r = 4.0;
    return [
      Positioned(top: 16, left: 16,
          child: _Corner(size: size, thick: thick, color: color, r: r,
              top: true, left: true)),
      Positioned(top: 16, right: 16,
          child: _Corner(size: size, thick: thick, color: color, r: r,
              top: true, left: false)),
      Positioned(bottom: 16, left: 16,
          child: _Corner(size: size, thick: thick, color: color, r: r,
              top: false, left: true)),
      Positioned(bottom: 16, right: 16,
          child: _Corner(size: size, thick: thick, color: color, r: r,
              top: false, left: false)),
    ];
  }
}

class _Corner extends StatelessWidget {
  final double size, thick, r;
  final Color color;
  final bool top, left;

  const _Corner({required this.size, required this.thick, required this.r,
      required this.color, required this.top, required this.left});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size, height: size,
    child: CustomPaint(painter:
        _CornerPainter(thick: thick, color: color, r: r,
            top: top, left: left)),
  );
}

class _CornerPainter extends CustomPainter {
  final double thick, r;
  final Color color;
  final bool top, left;

  _CornerPainter({required this.thick, required this.r,
      required this.color, required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color..strokeWidth = thick
      ..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    final w = size.width, h = size.height;

    if (top && left) {
      path.moveTo(0, h); path.lineTo(0, r);
      path.arcToPoint(Offset(r, 0), radius: Radius.circular(r));
      path.lineTo(w, 0);
    } else if (top && !left) {
      path.moveTo(0, 0); path.lineTo(w - r, 0);
      path.arcToPoint(Offset(w, r), radius: Radius.circular(r));
      path.lineTo(w, h);
    } else if (!top && left) {
      path.moveTo(0, 0); path.lineTo(0, h - r);
      path.arcToPoint(Offset(r, h), radius: Radius.circular(r));
      path.lineTo(w, h);
    } else {
      path.moveTo(0, h); path.lineTo(w - r, h);
      path.arcToPoint(Offset(w, h - r), radius: Radius.circular(r));
      path.lineTo(w, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ════════════════════════════════════════════════════════════════════════════
// API SETUP SCREEN (unchanged from before — kept for completeness)
// ════════════════════════════════════════════════════════════════════════════

class ApiSetupScreen extends StatefulWidget {
  const ApiSetupScreen({super.key});
  @override
  State<ApiSetupScreen> createState() => _ApiSetupScreenState();
}

class _ApiSetupScreenState extends State<ApiSetupScreen> {
  final _geminiCtrl = TextEditingController();
  bool _geminiSet = false;
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(title: const Text('API Setup')),
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Container(width: 64, height: 64,
            decoration: BoxDecoration(color: AppColors.bg2,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF1E2235))),
            child: const Icon(Icons.key_rounded,
                color: AppColors.warning, size: 30)),
          const SizedBox(height: 16),
          Text('API Setup', style: AppTypography.heading2),
          Text('Encrypted via flutter_secure_storage',
              style: AppTypography.bodySmall),
          const SizedBox(height: 28),

          Align(alignment: Alignment.centerLeft,
            child: Text('REQUIRED', style: AppTypography.label)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.bg2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2235))),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.star, color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gemini API Key', style: AppTypography.bodyLarge),
                    Text('Google AI Studio', style: AppTypography.bodySmall),
                  ])),
                if (_geminiSet) StatusPill.active(),
              ]),
              const SizedBox(height: 10),
              TextFormField(
                controller: _geminiCtrl,
                obscureText: _obscure,
                onChanged: (v) => setState(() => _geminiSet = v.length > 8),
                style: const TextStyle(fontFamily: 'monospace',
                    fontSize: 13, color: AppColors.textPrimary,
                    letterSpacing: 1.5),
                decoration: InputDecoration(
                  hintText: 'AIza••••••••••••',
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off
                        : Icons.visibility,
                        color: AppColors.textMuted, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 28),

          ElevatedButton(
            onPressed: _geminiSet ? () => Navigator.pop(context) : null,
            child: const Text('Save & Continue'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip Optional Keys'),
          ),
          const SizedBox(height: 32),
        ]),
      )),
    );
  }
}