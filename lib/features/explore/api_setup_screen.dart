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
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.bg0,
      appBar: AppBar(
        title: const Text('API Setup'),
        backgroundColor: colors.bg1,
        foregroundColor: colors.textPrimary,
        elevation: 0,
      ),
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
                  color: colors.bg2,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.cardBorder),
                ),
                child: const Icon(Icons.key_rounded,
                    color: AppColors.warning, size: 30),
              ),
              const SizedBox(height: 16),
              Text('API Setup', style: AppTypography.heading2.copyWith(color: colors.textPrimary)),
              Text(
                'Encrypted via flutter_secure_storage',
                style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: 28),

              // Required section
              Align(
                alignment: Alignment.centerLeft,
                child: Text('REQUIRED', style: AppTypography.label.copyWith(color: colors.textMuted)),
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
                onClear: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await SecureStorageService.instance.deleteGeminiKey();
                  if (!mounted) return;
                  setState(() {
                    _geminiCtrl.clear();
                    _geminiSet = false;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Gemini API Key deleted successfully'),
                      backgroundColor: AppColors.good,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),

              // Free section
              Align(
                alignment: Alignment.centerLeft,
                child: Text('FREE & OPEN SOURCE', style: AppTypography.label.copyWith(color: colors.textMuted)),
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
                  color: colors.bg3,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        color: colors.textMuted, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keys encrypted on-device. Never stored in plain text.',
                        style: AppTypography.bodySmall.copyWith(color: colors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              ElevatedButton(
                onPressed: _geminiSet
                    ? () async {
                        final navigator = Navigator.of(context);
                        final messenger = ScaffoldMessenger.of(context);
                        await SecureStorageService.instance.saveGeminiKey(_geminiCtrl.text);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Gemini API key saved successfully!'),
                            backgroundColor: AppColors.good,
                            duration: Duration(seconds: 2),
                          ),
                        );
                        navigator.pop(true);
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
  final VoidCallback? onClear;

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
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
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
                    Text(title, style: AppTypography.bodyLarge.copyWith(color: colors.textPrimary)),
                    Text(subtitle, style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
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
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              color: colors.textPrimary,
              letterSpacing: 1.5,
            ),
            decoration: InputDecoration(
              hintText: 'AIza••••••••••••',
              hintStyle: TextStyle(color: colors.textMuted),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
                        color: colors.textMuted, size: 18),
                    onPressed: onToggleObscure,
                  ),
                  if (controller.text.isNotEmpty && onClear != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.critical, size: 18),
                      onPressed: onClear,
                    ),
                ],
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
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.bodyLarge.copyWith(color: colors.textPrimary)),
                Text(subtitle, style: AppTypography.bodySmall.copyWith(color: colors.textSecondary)),
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
