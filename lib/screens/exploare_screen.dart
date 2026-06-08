import 'dart:math' as math;
import 'package:flutter/material.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with TickerProviderStateMixin {

  static const _bg      = Color(0xFF07080F);
  static const _card    = Color(0xFF0E1018);
  static const _card2   = Color(0xFF161824);
  static const _border  = Color(0xFF1C2035);
  static const _teal    = Color(0xFF00C4A0);
  static const _white   = Color(0xFFF0F4FF);
  static const _grey    = Color(0xFF8892AA);
  static const _red     = Color(0xFFFF4D4D);
  static const _amber   = Color(0xFFFFB347);
  static const _glacier = Color(0xFF64B5F6);
  static const _sea     = Color(0xFF4FC3F7);
  static const _forest  = Color(0xFF81C784);
  static const _heat    = Color(0xFFFF8A65);

  String  _category   = 'All';
  String? _selectedId;

  late final AnimationController _rotateCtrl;
  late final AnimationController _pulseCtrl;
  late final Animation<double>   _rotatAnim;
  late final Animation<double>   _pulseAnim;

  static const _regions = [
    {'id':'arctic',   'name':'Arctic Circle',   'cat':'glacier',  'risk':'Critical', 'lat':'78.2', 'lon':'15.6'},
    {'id':'himalaya', 'name':'Himalaya',         'cat':'glacier',  'risk':'High',     'lat':'27.9', 'lon':'86.9'},
    {'id':'amazon',   'name':'Amazon Basin',     'cat':'forest',   'risk':'Critical', 'lat':'-3.4', 'lon':'-62.2'},
    {'id':'pacific',  'name':'Pacific Islands',  'cat':'sealevel', 'risk':'Critical', 'lat':'-8.7', 'lon':'179.0'},
    {'id':'sahara',   'name':'Sahara',           'cat':'heat',     'risk':'High',     'lat':'23.4', 'lon':'25.6'},
    {'id':'maldives', 'name':'Maldives',         'cat':'sealevel', 'risk':'Critical', 'lat':'3.2',  'lon':'73.2'},
  ];

  static const _cats = ['All','Glaciers','Sea Level','Forests','Heat'];

  List<Map<String,String>> get _filtered {
    if (_category == 'All') return _regions;
    final k = switch (_category) {
      'Glaciers'  => 'glacier',
      'Sea Level' => 'sealevel',
      'Forests'   => 'forest',
      'Heat'      => 'heat',
      _           => '',
    };
    return _regions.where((r) => r['cat'] == k).toList();
  }

  Color    _catColor(String c) => switch(c) { 'glacier'=>_glacier, 'sealevel'=>_sea, 'forest'=>_forest, 'heat'=>_heat, _=>_grey };
  IconData _catIcon(String c)  => switch(c) { 'glacier'=>Icons.ac_unit, 'sealevel'=>Icons.water, 'forest'=>Icons.forest, 'heat'=>Icons.thermostat, _=>Icons.place };

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
    _pulseCtrl  = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _rotatAnim  = Tween<double>(begin: 0, end: 2 * math.pi).animate(_rotateCtrl);
    _pulseAnim  = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [

            // ── Globe Hero ─────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildHero()),

            // ── Filter pills ───────────────────────────────────────────
            SliverToBoxAdapter(child: _buildFilters()),

            // ── Legend ────────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildLegend()),

            // ── Section label ─────────────────────────────────────────
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text('REGIONS', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  letterSpacing: 1.2, color: _grey,
                )),
              ),
            ),

            // ── Region cards ──────────────────────────────────────────
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _buildCard(_filtered[i]),
                childCount: _filtered.length,
              ),
            ),

            // ── CTA button ────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildCTA()),
            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }

  // ── Globe Hero ────────────────────────────────────────────────────────────

  Widget _buildHero() {
    return Container(
      height: 280,
      color: const Color(0xFF06090F),
      child: Stack(
        children: [
          // Stars background
          ...List.generate(30, (i) {
            final rng = math.Random(i * 7);
            return Positioned(
              left:  rng.nextDouble() * 400,
              top:   rng.nextDouble() * 280,
              child: Container(
                width:  rng.nextDouble() * 2 + 0.5,
                height: rng.nextDouble() * 2 + 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(rng.nextDouble() * 0.6 + 0.1),
                ),
              ),
            );
          }),

          // Animated globe
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([_rotatAnim, _pulseAnim]),
              builder: (_, __) => Transform.scale(
                scale: _pulseAnim.value,
                child: SizedBox(
                  width: 180, height: 180,
                  child: CustomPaint(
                    painter: _GlobePainter(_rotatAnim.value),
                  ),
                ),
              ),
            ),
          ),

          // Orbit ring
          AnimatedBuilder(
            animation: _rotatAnim,
            builder: (_, __) => Center(
              child: Transform.rotate(
                angle: _rotatAnim.value * 0.3,
                child: Container(
                  width: 220, height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _teal.withOpacity(0.15),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Title at bottom
          Positioned(
            bottom: 16, left: 20, right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Explore', style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700,
                  color: _white, letterSpacing: -0.8,
                )),
                const SizedBox(height: 2),
                Text('Select a region to begin your story',
                  style: TextStyle(fontSize: 13, color: _grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter pills ──────────────────────────────────────────────────────────

  Widget _buildFilters() {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: _cats.map((cat) {
          final active = cat == _category;
          return GestureDetector(
            onTap: () => setState(() { _category = cat; _selectedId = null; }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: active ? _teal.withOpacity(0.15) : _card2,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? _teal : _border),
              ),
              child: Text(cat, style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                color: active ? _teal : _grey,
              )),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Legend ────────────────────────────────────────────────────────────────

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Row(children: [
        _dot(_glacier, 'Glaciers'),  const SizedBox(width: 14),
        _dot(_forest,  'Forests'),   const SizedBox(width: 14),
        _dot(_sea,     'Sea Rise'),  const SizedBox(width: 14),
        _dot(_heat,    'Heat'),
      ]),
    );
  }

  // ── Region card ───────────────────────────────────────────────────────────

  Widget _buildCard(Map<String,String> r) {
    final selected = _selectedId == r['id'];
    final color    = _catColor(r['cat']!);
    return GestureDetector(
      onTap: () => setState(() => _selectedId = r['id']),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? color.withOpacity(0.5) : _border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_catIcon(r['cat']!), color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r['name']!, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: _white)),
              const SizedBox(height: 2),
              Text('${r['lat']}°, ${r['lon']}°',
                style: const TextStyle(fontSize: 12, color: _grey)),
            ],
          )),
          if (r['risk'] != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (r['risk']=='Critical'?_red:_amber).withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (r['risk']=='Critical'?_red:_amber).withOpacity(0.4)),
              ),
              child: Text(r['risk']!, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: r['risk']=='Critical' ? _red : _amber,
              )),
            ),
          ],
        ]),
      ),
    );
  }

  // ── CTA ───────────────────────────────────────────────────────────────────

  Widget _buildCTA() {
    final sel = _selectedId != null
        ? _regions.firstWhere((r) => r['id'] == _selectedId,
            orElse: () => {'name': 'Region'})
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: sel != null ? () {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Connect to LG rig first in Settings'),
              backgroundColor: _card2,
            ));
          } : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: _teal,
            disabledBackgroundColor: _card2,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          icon: Icon(Icons.public, size: 18,
              color: sel != null ? _bg : _grey),
          label: Text(
            sel != null
                ? 'Fly to ${sel['name']} on LG'
                : 'Select a Region Above',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                color: sel != null ? _bg : _grey),
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 8, height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(
          fontSize: 11, color: _grey, letterSpacing: 0.3)),
    ],
  );
}

// ── Globe CustomPainter ───────────────────────────────────────────────────────

class _GlobePainter extends CustomPainter {
  final double angle;
  _GlobePainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = size.width  / 2 - 4;

    // ── Ocean fill ──
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()..color = const Color(0xFF0D1F3C));

    // ── Latitude lines ──
    final latPaint = Paint()
      ..color = const Color(0xFF00C4A0).withOpacity(0.2)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 5; i++) {
      final lat  = (i / 6) * math.pi - math.pi / 2;
      final yr   = cy + r * math.sin(lat);
      final xr   = r * math.cos(lat);
      if (xr > 0) {
        canvas.drawOval(
          Rect.fromCenter(center: Offset(cx, yr),
              width: xr * 2, height: xr * 0.35),
          latPaint,
        );
      }
    }

    // ── Longitude lines (animated) ──
    for (int i = 0; i < 8; i++) {
      final a     = angle + (i / 8) * math.pi * 2;
      final xScale = math.cos(a).abs();
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy),
            width: r * 2 * xScale, height: r * 2),
        Paint()
          ..color = const Color(0xFF00C4A0).withOpacity(0.15 * xScale)
          ..strokeWidth = 0.7
          ..style = PaintingStyle.stroke,
      );
    }

    // ── Continent blobs ──
    final contPaint = Paint()
      ..color = const Color(0xFF1E4060)
      ..style = PaintingStyle.fill;

    // Africa/Europe
    _drawBlob(canvas, cx, cy, r, angle, 0.15, -0.1, 0.22, 0.38, contPaint);
    // Americas
    _drawBlob(canvas, cx, cy, r, angle + math.pi, -0.05, -0.05, 0.18, 0.45, contPaint);
    // Asia
    _drawBlob(canvas, cx, cy, r, angle + 0.8, 0.3, -0.15, 0.28, 0.32, contPaint);

    // ── Globe border ──
    canvas.drawCircle(Offset(cx, cy), r,
      Paint()
        ..color = const Color(0xFF00C4A0).withOpacity(0.5)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke);

    // ── Shine ──
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx - r * 0.2, cy - r * 0.2), radius: r * 0.5),
      -2.5, 1.2, false,
      Paint()
        ..color = Colors.white.withOpacity(0.07)
        ..strokeWidth = 8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // ── Clip to circle ──
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)));
  }

  void _drawBlob(Canvas canvas, double cx, double cy, double r,
      double baseAngle, double latOff, double lonOff,
      double blobW, double blobH, Paint paint) {
    final a      = baseAngle + lonOff;
    final xScale = math.cos(a);
    final bx     = cx + r * xScale * blobW * 2;
    final by     = cy + r * (latOff);
    final rw     = r * blobW * xScale.abs();
    final rh     = r * blobH;
    if (rw > 4) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(bx, by), width: rw * 2, height: rh),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlobePainter old) => old.angle != angle;
}