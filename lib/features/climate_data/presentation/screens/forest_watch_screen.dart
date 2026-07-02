import 'package:flutter/material.dart';
import 'package:climate_storyteller/core/theme/app_theme.dart';
import 'package:climate_storyteller/core/di/injection_container.dart';
import 'package:climate_storyteller/widgets/shared_widgets.dart';
import '../../../lg_connection/domain/entities/lg_rig_state.dart';

class ForestWatchScreen extends StatefulWidget {
  const ForestWatchScreen({super.key});

  @override
  State<ForestWatchScreen> createState() => _ForestWatchScreenState();
}

class _ForestWatchScreenState extends State<ForestWatchScreen> {

  String _selectedRegion = 'amazon';
  int    _selectedYear   = 2023;
  bool   _isSending      = false;
  bool   _showComparison = false;
  String? _statusMsg;

  static const _regions = [
    {'id': 'amazon',   'name': 'Amazon Basin',  'icon': '🌿',
     'desc': 'World\'s largest tropical rainforest. 25% lost since 1900.'},
    {'id': 'congo',    'name': 'Congo Basin',    'icon': '🌴',
     'desc': 'Africa\'s largest rainforest. Second only to Amazon in size.'},
    {'id': 'borneo',   'name': 'Borneo',         'icon': '🦧',
     'desc': 'Half of Borneo\'s forests cleared in the past 50 years.'},
    {'id': 'himalaya', 'name': 'Himalaya',       'icon': '🏔️',
     'desc': 'Mountain forests crucial for watershed protection.'},
  ];

  static const _years = [2005, 2010, 2015, 2018, 2020, 2022, 2023];

  Future<void> _sendToLG() async {
    final lg = DI.lgRepository;
    if (!lg.state.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Connect to LG rig first — go to Settings'),
        backgroundColor: AppColors.bg2,
      ));
      return;
    }

    setState(() { _isSending = true; _statusMsg = 'Building KML…'; });

    try {
      if (_showComparison) {
        setState(() => _statusMsg = 'Building comparison view…');
        final kml = DI.forestRepository.buildComparisonKml(
          regionId: _selectedRegion,
        );
        final filename = 'forest_compare_$_selectedRegion.kml';
        await DI.sendKmlToLg(filename, kmlContent: kml);
      } else {
        setState(() => _statusMsg =
            'Sending GFW data to LG ($_selectedYear)…');
        await DI.getForestData.sendToLG(
          regionId: _selectedRegion,
          year:     _selectedYear,
        );
      }

      if (mounted) {
        setState(() => _statusMsg = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            const Text('Forest layer loaded on LG!'),
          ]),
          backgroundColor: AppColors.forest,
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusMsg = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.critical,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      appBar: AppBar(
        title: const Text('Forest Watch'),
        backgroundColor: AppColors.bg0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.forest.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.forest.withValues(alpha: 0.3)),
                ),
                child: Row(children: [
                  const Text('🌲', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Global Forest Watch',
                        style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                      Text(
                        'Real deforestation data at 30m resolution.\n'
                        'Source: Hansen/UMD/Google/USGS/NASA · Free',
                        style: AppTypography.bodySmall),
                    ],
                  )),
                ]),
              ),
              const SizedBox(height: 24),

              const SectionHeader(title: 'Select Forest Region'),
              ..._regions.map((r) {
                final selected = r['id'] == _selectedRegion;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRegion = r['id']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.forest.withValues(alpha: 0.08)
                          : AppColors.bg2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppColors.forest.withValues(alpha: 0.5)
                            : const Color(0xFF1E2235),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(children: [
                      Text(r['icon']!,
                          style: const TextStyle(fontSize: 28)),
                      const SizedBox(width: 14),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r['name']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            )),
                          const SizedBox(height: 2),
                          Text(r['desc']!,
                              style: AppTypography.bodySmall),
                        ],
                      )),
                      if (selected)
                        const Icon(Icons.check_circle,
                            color: AppColors.forest, size: 20),
                    ]),
                  ),
                );
              }),
              const SizedBox(height: 24),

              const SectionHeader(title: 'Year'),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _years.map((year) {
                    final active = year == _selectedYear;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedYear = year),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.forest.withValues(alpha: 0.15)
                              : AppColors.bg3,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: active
                                ? AppColors.forest
                                : const Color(0xFF252840),
                          ),
                        ),
                        child: Text(
                          year.toString(),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700 : FontWeight.w400,
                            color: active
                                ? AppColors.forest
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              const SectionHeader(title: 'View Mode'),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showComparison = false),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !_showComparison
                            ? AppColors.forest.withValues(alpha: 0.15)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: !_showComparison
                              ? AppColors.forest
                              : const Color(0xFF252840),
                        ),
                      ),
                      child: Column(children: [
                        const Text('📅', style: TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text('Single Year',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: !_showComparison
                                ? FontWeight.w700 : FontWeight.w400,
                            color: !_showComparison
                                ? AppColors.forest
                                : AppColors.textSecondary,
                          )),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _showComparison = true),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: _showComparison
                            ? AppColors.forest.withValues(alpha: 0.15)
                            : AppColors.bg3,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _showComparison
                              ? AppColors.forest
                              : const Color(0xFF252840),
                        ),
                      ),
                      child: Column(children: [
                        const Text('↔️', style: TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text('2000 vs $_selectedYear',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _showComparison
                                ? FontWeight.w700 : FontWeight.w400,
                            color: _showComparison
                                ? AppColors.forest
                                : AppColors.textSecondary,
                          )),
                      ]),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 24),

              StreamBuilder<LGRigState>(
                stream: DI.lgRepository.stateStream,
                initialData: DI.lgRepository.state,
                builder: (_, snap) =>
                    LGStatusCard(rigState: snap.data!),
              ),
              const SizedBox(height: 12),

              if (_statusMsg != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.forest.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.forest.withValues(alpha: 0.3)),
                  ),
                  child: Row(children: [
                    const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.forest)),
                    const SizedBox(width: 10),
                    Text(_statusMsg!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.forest)),
                  ]),
                ),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bg2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1E2235)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ON LG SCREENS', style: AppTypography.label),
                    const SizedBox(height: 10),
                    _infoRow('🟢', 'Green areas',
                        'Existing tree cover (2000 baseline)'),
                    _infoRow('🔴', 'Red areas',
                        'Forest lost since 2000 to $_selectedYear'),
                    _infoRow('📍', 'Centre pin',
                        'Region stats and GFW data source'),
                    if (_showComparison)
                      _infoRow('⚪', 'White line',
                          'Divides 2000 (left) vs $_selectedYear (right)'),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              ElevatedButton.icon(
                onPressed: _isSending ? null : _sendToLG,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.forest,
                  disabledBackgroundColor: AppColors.bg2,
                ),
                icon: _isSending
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.forest,
                        size: 18, color: Colors.white),
                label: Text(
                  _isSending
                      ? 'Sending…'
                      : _showComparison
                          ? 'Show 2000 vs $_selectedYear on LG'
                          : 'Show $_selectedYear Deforestation on LG',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String emoji, String label, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(child: RichText(
          text: TextSpan(
            style: AppTypography.bodySmall,
            children: [
              TextSpan(text: '$label — ',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
              TextSpan(text: desc),
            ],
          ),
        )),
      ]),
    );
  }
}
