import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'shell_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardPage(
      icon: Icons.public,
      title: 'Climate Change\nStory Visualizer',
      subtitle:
          'Experience Earth\'s climate history across 1900, 2026, and 2100 on the Liquid Galaxy multi-screen platform.',
      features: [],
    ),
    _OnboardPage(
      icon: Icons.calendar_month,
      title: 'Time-Travel Through\nEarth\'s History',
      subtitle:
          'Slide to journey between 1900, today, and 2100. The Liquid Galaxy updates live.',
      features: [
        _Feature(
          icon: Icons.layers,
          title: 'Live KML Updates',
          subtitle: 'Glacier layers refresh instantly',
        ),
        _Feature(
          icon: Icons.desktop_windows_outlined,
          title: '5-Screen Sync',
          subtitle: 'All LG screens update simultaneously',
        ),
        _Feature(
          icon: Icons.record_voice_over,
          title: 'AI Narration',
          subtitle: 'Gemini generates the story live',
        ),
      ],
    ),
    _OnboardPage(
      icon: Icons.record_voice_over,
      title: 'AI Narrator\nTells the Story',
      subtitle:
          'Choose Natural, Poetic, or Scientific voice styles. Gemini crafts region-specific narratives.',
      features: [],
    ),
    _OnboardPage(
      icon: Icons.link,
      title: 'Connect to\nLiquid Galaxy',
      subtitle:
          'Enter the rig IP or scan a QR code to connect. Uses SSH over local Wi-Fi — no cloud relay.',
      features: [],
    ),
  ];

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ShellScreen()),
      );
    }
  }

  void _back() {
    if (_page > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: List.generate(_pages.length, (i) {
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i < _pages.length - 1 ? 6 : 0),
                      height: 3,
                      decoration: BoxDecoration(
                        color: i <= _page ? AppColors.primary : AppColors.bg3,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ),

            // Step indicator
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Step ${_page + 1} of ${_pages.length}',
                  style: AppTypography.caption,
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (context, i) =>
                    _OnboardPageWidget(page: _pages[i]),
              ),
            ),

            // Navigation buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Row(
                children: [
                  if (_page > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _back,
                        child: const Text('← Back'),
                      ),
                    ),
                  if (_page > 0) const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _next,
                      child: Text(
                        _page < _pages.length - 1 ? 'Next →' : 'Get Started',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<_Feature> features;

  const _OnboardPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.features,
  });
}

class _Feature {
  final IconData icon;
  final String title;
  final String subtitle;

  const _Feature(
      {required this.icon, required this.title, required this.subtitle});
}

class _OnboardPageWidget extends StatelessWidget {
  final _OnboardPage page;

  const _OnboardPageWidget({required this.page});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon card
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.12),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(page.icon, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 32),

          Text(
            page.title,
            style: AppTypography.heading1.copyWith(fontSize: 30),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            page.subtitle,
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textSecondary,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),

          if (page.features.isNotEmpty) ...[
            const SizedBox(height: 32),
            ...page.features.map(
              (f) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(f.icon, color: AppColors.primary, size: 18),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(f.title, style: AppTypography.bodyLarge),
                          Text(f.subtitle, style: AppTypography.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}