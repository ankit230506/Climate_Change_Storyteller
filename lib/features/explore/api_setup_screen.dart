import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/constant/app_theme.dart';
import 'package:climate_storyteller/core/storage/secure_storage_service.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';

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
  void initState() {
    super.initState();
    _loadKey();
  }

  Future<void> _loadKey() async {
    final key = await SecureStorageService.instance.getGeminiKey();
    if (key != null && key.isNotEmpty) {
      if (mounted) {
        setState(() {
          _geminiCtrl.text = key;
          _geminiSet = true;
        });
      }
    }
  }

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
              const _FreeApiTile(
                icon: Icons.volume_up_outlined,
                iconColor: AppColors.good,
                title: 'Flutter TTS',
                subtitle: 'On-device · No API key',
              ),
              const SizedBox(height: 8),
              const _FreeApiTile(
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
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline,
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
              color: AppColors.good.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Free',
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
