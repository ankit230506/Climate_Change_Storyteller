import 'package:flutter/material.dart';
import '/core/theme/app_theme.dart';
import '../models/app_models.dart';
import '../widgets/shared_widgets.dart';
import '../services/lg_ssh_service.dart';
import '/core/storage/secure_storage_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// REGION DETAIL SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

class RegionDetailScreen extends StatefulWidget {
  final ClimateRegion region;

  const RegionDetailScreen({super.key, required this.region});

  @override
  State<RegionDetailScreen> createState() => _RegionDetailScreenState();
}

class _RegionDetailScreenState extends State<RegionDetailScreen> {
  static const _layers = [
    _KmlLayer(name: 'Glacier Extent', icon: Icons.ac_unit, status: 'loaded'),
    _KmlLayer(name: 'Sea Level Rise', icon: Icons.water, status: 'ready'),
    _KmlLayer(name: 'KML Placemarks', icon: Icons.place, status: 'loading'),
  ];

  Future<void> _flyToRegion() async {
    final ssh = LGSSHService.instance;
    if (!ssh.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Not connected to LG Rig'),
            backgroundColor: AppColors.bg2),
      );
      return;
    }
    await ssh.flyTo(
      latitude: widget.region.latitude,
      longitude: widget.region.longitude,
      altitude: widget.region.altitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: Text(widget.region.name),
        backgroundColor: AppColors.bg0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Region badges
              Row(
                children: [
                  if (widget.region.riskLevel != null)
                    StatusPill(
                      label: widget.region.riskLevel!,
                      color: widget.region.riskLevel == 'Critical'
                          ? AppColors.critical
                          : AppColors.warning,
                    ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label: _categoryLabel(widget.region.category),
                    color: AppColors.secondary,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Map stub
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1830),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1A2035)),
                ),
                child: Center(
                  child: Text(
                    'Region Map\n(google_maps_flutter)',
                    style: AppTypography.caption.copyWith(letterSpacing: 0),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // KML Layers
              const SectionHeader(title: 'KML Layers'),
              ..._layers.map((l) => _KmlLayerTile(layer: l)),
              const SizedBox(height: 24),

              // Fly to CTA
              ElevatedButton.icon(
                onPressed: _flyToRegion,
                icon: const Icon(Icons.public, size: 18, color: AppColors.bg0),
                label: Text('Fly to ${widget.region.name} on LG'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _categoryLabel(String cat) => switch (cat) {
        'glacier' => 'Glacier',
        'sealevel' => 'Sea Level',
        'forest' => 'Forest',
        'heat' => 'Heat',
        _ => cat,
      };
}

class _KmlLayer {
  final String name;
  final IconData icon;
  final String status; // loaded | ready | loading

  const _KmlLayer({required this.name, required this.icon, required this.status});
}

class _KmlLayerTile extends StatelessWidget {
  final _KmlLayer layer;

  const _KmlLayerTile({required this.layer});

  @override
  Widget build(BuildContext context) {
    final pill = switch (layer.status) {
      'loaded' => StatusPill.loaded(),
      'ready' => StatusPill.ready(),
      'loading' => StatusPill.loading(),
      _ => StatusPill(label: layer.status, color: AppColors.textMuted),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Row(
        children: [
          Icon(layer.icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(layer.name, style: AppTypography.bodyLarge),
          ),
          pill,
        ],
      ),
    );
  }
}

// LGConnectScreen lives in settings_screen.dart

// ═══════════════════════════════════════════════════════════════════════════════
// API SETUP SCREEN
// ═══════════════════════════════════════════════════════════════════════════════

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
  void dispose() {
    _geminiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(title: const Text('API Setup')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: const Icon(Icons.key_rounded,
                    color: AppColors.warning, size: 30),
              ),
              const SizedBox(height: 16),
              Text('API Setup', style: AppTypography.heading2),
              Text(
                'Encrypted via flutter_secure_storage',
                style: AppTypography.bodySmall,
              ),
              const SizedBox(height: 28),

              // Required section
              Align(
                alignment: Alignment.centerLeft,
                child: Text('REQUIRED', style: AppTypography.label),
              ),
              const SizedBox(height: 12),
              _ApiKeyTile(
                icon: Icons.star,
                iconColor: AppColors.primary,
                title: 'Gemini API Key',
                subtitle: 'Google AI Studio',
                isSet: _geminiSet,
                controller: _geminiCtrl,
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
                onChanged: (v) => setState(() => _geminiSet = v.length > 8),
              ),
              const SizedBox(height: 24),

              // Free section
              Align(
                alignment: Alignment.centerLeft,
                child: Text('FREE & OPEN SOURCE', style: AppTypography.label),
              ),
              const SizedBox(height: 12),
              _FreeApiTile(
                icon: Icons.volume_up_outlined,
                iconColor: AppColors.good,
                title: 'Flutter TTS',
                subtitle: 'On-device · No API key',
              ),
              const SizedBox(height: 8),
              _FreeApiTile(
                icon: Icons.language,
                iconColor: AppColors.secondary,
                title: 'gTTS (Google)',
                subtitle: 'Free tier · 38+ languages',
              ),
              const SizedBox(height: 16),

              // Note
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bg3,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lock_outline,
                        color: AppColors.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keys encrypted on-device. Never stored in plain text.',
                        style: AppTypography.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _geminiSet
                    ? () async {
                        await SecureStorageService.instance.saveGeminiKey(_geminiCtrl.text);
                        if (!mounted) return;
                        Navigator.pop(context);
                      }
                    : null,
                child: const Text('Save & Continue'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Skip Optional Keys'),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApiKeyTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isSet;
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final ValueChanged<String> onChanged;

  const _ApiKeyTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.isSet,
    required this.controller,
    required this.obscure,
    required this.onToggleObscure,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.bodyLarge),
                    Text(subtitle, style: AppTypography.bodySmall),
                  ],
                ),
              ),
              if (isSet)
                StatusPill.active()
              else
                const SizedBox.shrink(),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            onChanged: onChanged,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: AppColors.textPrimary,
              letterSpacing: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'AIza••••••••••••',
              suffixIcon: IconButton(
                icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.textMuted, size: 18),
                onPressed: onToggleObscure,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreeApiTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _FreeApiTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E2235)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyLarge),
                Text(subtitle, style: AppTypography.bodySmall),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.good.withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('Free',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.good)),
          ),
        ],
      ),
    );
  }
}