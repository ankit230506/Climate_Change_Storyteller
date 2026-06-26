import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '/core/theme/app_theme.dart';
import '/features/local data/ipcc_data.dart';

class DataInsightsScreen extends StatefulWidget {
  const DataInsightsScreen({super.key});
  @override
  State<DataInsightsScreen> createState() => _DataInsightsScreenState();
}

class _DataInsightsScreenState extends State<DataInsightsScreen> {
  int _selectedChart = 0;
  static const _charts = ['Temperature', 'Ice Extent', 'Sea Level'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg0,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Data Insights', style: AppTypography.heading1),
                  Text('IPCC AR6 · 1900 → 2100',
                      style: AppTypography.bodySmall),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Chart selector tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: List.generate(_charts.length, (i) {
                  final active = i == _selectedChart;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedChart = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: EdgeInsets.only(
                            right: i < _charts.length - 1 ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: active
                              ? AppColors.primary.withOpacity(0.15)
                              : AppColors.bg2,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: active
                                ? AppColors.primary
                                : const Color(0xFF1E2235),
                          ),
                        ),
                        child: Text(
                          _charts[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: active
                                ? FontWeight.w700 : FontWeight.w400,
                            color: active
                                ? AppColors.primary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 20),

            // Chart
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildChart(_selectedChart),
              ),
            ),

            // Era reference row
            _buildEraReference(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(int index) => switch (index) {
    0 => _TemperatureChart(key: const ValueKey('temp')),
    1 => _IceExtentChart(key: const ValueKey('ice')),
    2 => _SeaLevelChart(key: const ValueKey('sea')),
    _ => const SizedBox.shrink(),
  };

  Widget _buildEraReference() {
    final data = switch (_selectedChart) {
      0 => kTemperatureAnomaly,
      1 => kArcticIceExtent,
      2 => kSeaLevelRise,
      _ => <int, double>{},
    };
    final unit    = switch (_selectedChart) { 0=>'°C', 1=>'M km²', 2=>'mm', _=>'' };
    final divisor = _selectedChart == 1 ? 1e6 : 1.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [1900, 2026, 2100].map((year) {
          final value   = (data[year] ?? 0) / divisor;
          final color   = switch (year) {
            1900 => AppColors.glacier,
            2026 => AppColors.primary,
            2100 => AppColors.critical,
            _    => AppColors.textSecondary,
          };
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: year != 2100 ? 8 : 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Column(children: [
                Text('$year', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: color, letterSpacing: 0.5)),
                const SizedBox(height: 4),
                Text('${value.toStringAsFixed(1)}$unit',
                  style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Chart 1: Temperature ──────────────────────────────────────────────────────
class _TemperatureChart extends StatelessWidget {
  const _TemperatureChart({super.key});

  @override
  Widget build(BuildContext context) {
    final spots = kTemperatureAnomaly.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()..sort((a, b) => a.x.compareTo(b.x));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartTitle('Global Temperature Anomaly',
              '°C above 1900 baseline', Icons.thermostat, AppColors.heat),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(LineChartData(
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: const Color(0xFF1C2035), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 40,
                  getTitlesWidget: (v, _) => Text('+${v.toStringAsFixed(1)}°',
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textSecondary)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, interval: 50,
                  getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textSecondary)),
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(
                spots: spots, isCurved: true,
                color: AppColors.heat, barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (s, _) =>
                      [1900.0, 2026.0, 2100.0].contains(s.x),
                  getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 5,
                    color: s.x == 2026.0
                        ? AppColors.primary : AppColors.heat,
                    strokeWidth: 2, strokeColor: AppColors.bg0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [AppColors.heat.withOpacity(0.3),
                             AppColors.heat.withOpacity(0.0)],
                  ),
                ),
              )],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.bg2,
                  getTooltipItems: (s) => s.map((sp) => LineTooltipItem(
                    '${sp.x.toInt()}\n+${sp.y.toStringAsFixed(1)}°C',
                    const TextStyle(color: AppColors.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w600),
                  )).toList(),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }
}

// ── Chart 2: Ice Extent ───────────────────────────────────────────────────────
class _IceExtentChart extends StatelessWidget {
  const _IceExtentChart({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = kArcticIceExtent.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final barWidth = entries.length > 15 ? 10.0 : 18.0;

    final groups = entries.asMap().entries.map((e) {
      final t     = entries.length > 1 ? e.key / (entries.length - 1) : 0.0;
      final color = Color.lerp(AppColors.glacier, AppColors.critical, t)!;
      return BarChartGroupData(x: e.key, barRods: [
        BarChartRodData(
          toY: e.value.value, color: color,
          width: barWidth,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        ),
      ]);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartTitle('Arctic Sea Ice Extent',
              'Million km² · Blue=full ice · Red=near ice-free',
              Icons.ac_unit, AppColors.glacier),
          const SizedBox(height: 16),
          Expanded(
            child: BarChart(BarChartData(
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: const Color(0xFF1C2035), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 36,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}M',
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textSecondary)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= entries.length) return const SizedBox.shrink();
                    final year = entries[i].key;
                    if (![1900, 1950, 2000, 2026, 2050, 2100].contains(year)) {
                      return const SizedBox.shrink();
                    }
                    return Transform.rotate(angle: -0.5,
                      child: Text(year.toString(),
                        style: const TextStyle(fontSize: 9,
                            color: AppColors.textSecondary)));
                  },
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              barGroups: groups,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.bg2,
                  getTooltipItem: (group, _, rod, __) {
                    if (group.x < 0 || group.x >= entries.length) return null;
                    final year = entries[group.x].key;
                    return BarTooltipItem(
                      '$year\n${rod.toY.toStringAsFixed(1)}M km²',
                      const TextStyle(color: AppColors.textPrimary,
                          fontSize: 12, fontWeight: FontWeight.w600));
                  },
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }
}

// ── Chart 3: Sea Level ────────────────────────────────────────────────────────
class _SeaLevelChart extends StatelessWidget {
  const _SeaLevelChart({super.key});

  @override
  Widget build(BuildContext context) {
    final spots = kSeaLevelRise.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value))
        .toList()..sort((a, b) => a.x.compareTo(b.x));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chartTitle('Global Mean Sea Level Rise',
              'mm above 1900 baseline · IPCC AR6 SSP5-8.5',
              Icons.water, AppColors.seaLevel),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(LineChartData(
              gridData: FlGridData(
                show: true, drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: const Color(0xFF1C2035), strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 44,
                  getTitlesWidget: (v, _) => Text('${v.toInt()}mm',
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textSecondary)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, interval: 50,
                  getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                    style: const TextStyle(fontSize: 10,
                        color: AppColors.textSecondary)),
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [LineChartBarData(
                spots: spots, isCurved: true,
                color: AppColors.seaLevel, barWidth: 2.5,
                isStrokeCapRound: true,
                dotData: FlDotData(
                  show: true,
                  checkToShowDot: (s, _) =>
                      [1900.0, 2026.0, 2100.0].contains(s.x),
                  getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                    radius: 5,
                    color: s.x == 2026.0
                        ? AppColors.primary : AppColors.seaLevel,
                    strokeWidth: 2, strokeColor: AppColors.bg0,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [AppColors.seaLevel.withOpacity(0.3),
                             AppColors.seaLevel.withOpacity(0.0)],
                  ),
                ),
              )],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.bg2,
                  getTooltipItems: (s) => s.map((sp) => LineTooltipItem(
                    '${sp.x.toInt()}\n${sp.y.toStringAsFixed(0)}mm',
                    const TextStyle(color: AppColors.textPrimary,
                        fontSize: 12, fontWeight: FontWeight.w600),
                  )).toList(),
                ),
              ),
            )),
          ),
        ],
      ),
    );
  }
}

Widget _chartTitle(String title, String subtitle,
    IconData icon, Color color) {
  return Row(children: [
    Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 18),
    ),
    const SizedBox(width: 12),
    Expanded(child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 14,
            fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(subtitle, style: const TextStyle(fontSize: 11,
            color: AppColors.textSecondary)),
      ],
    )),
  ]);
}