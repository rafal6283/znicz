import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wygląd ikony cmentarza (wybierany w ustawieniach).
enum CemeteryIconStyle { byKind, headstone, cross, gate, candle, graves }

extension CemeteryIconStyleLabel on CemeteryIconStyle {
  String get label => switch (this) {
        CemeteryIconStyle.byKind => 'Według rodzaju',
        CemeteryIconStyle.headstone => 'Nagrobek',
        CemeteryIconStyle.cross => 'Krzyż',
        CemeteryIconStyle.gate => 'Brama',
        CemeteryIconStyle.candle => 'Znicz',
        CemeteryIconStyle.graves => 'Kwatera',
      };
}

/// Wybrany styl – zmiana od razu odświeża wszystkie ikony.
class CemeteryIcons {
  static final style = ValueNotifier<CemeteryIconStyle>(CemeteryIconStyle.byKind);

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final i = p.getInt('cem_icon');
      if (i != null && i >= 0 && i < CemeteryIconStyle.values.length) style.value = CemeteryIconStyle.values[i];
    } catch (_) {}
  }

  static Future<void> set(CemeteryIconStyle s) async {
    style.value = s;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('cem_icon', s.index);
    } catch (_) {}
  }
}

/// Symbol rysowany dla danego rodzaju cmentarza w trybie „Według rodzaju”.
enum CemeteryGlyph { headstone, cross, gate, candle, graves, matzevah, orthodox, military }

CemeteryGlyph glyphFor(CemeteryIconStyle style, String? kind) {
  switch (style) {
    case CemeteryIconStyle.headstone:
      return CemeteryGlyph.headstone;
    case CemeteryIconStyle.cross:
      return CemeteryGlyph.cross;
    case CemeteryIconStyle.gate:
      return CemeteryGlyph.gate;
    case CemeteryIconStyle.candle:
      return CemeteryGlyph.candle;
    case CemeteryIconStyle.graves:
      return CemeteryGlyph.graves;
    case CemeteryIconStyle.byKind:
      return switch (kind) {
        'żydowski' => CemeteryGlyph.matzevah,
        'prawosławny' => CemeteryGlyph.orthodox,
        'wojskowy' => CemeteryGlyph.military,
        _ => CemeteryGlyph.headstone,
      };
  }
}

/// Ikona cmentarza w stylu wybranym przez użytkownika.
class CemeteryIcon extends StatelessWidget {
  final String? kind; // rodzaj cmentarza (parafialny, żydowski, …)
  final double size;
  final Color? color;
  final CemeteryIconStyle? style; // wymuszony styl (podgląd w ustawieniach)
  const CemeteryIcon({super.key, this.kind, this.size = 24, this.color, this.style});

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
    return ValueListenableBuilder<CemeteryIconStyle>(
      valueListenable: CemeteryIcons.style,
      builder: (_, s, __) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: CemeteryGlyphPainter(glyphFor(style ?? s, kind), c)),
      ),
    );
  }
}

/// Rysuje symbol w polu 24×24 (skalowanym). Wycięcia (np. krzyż na nagrobku) są przezroczyste.
class CemeteryGlyphPainter extends CustomPainter {
  final CemeteryGlyph glyph;
  final Color color;
  CemeteryGlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width, size.height) / 24;
    canvas.save();
    canvas.translate((size.width - 24 * k) / 2, (size.height - 24 * k) / 2);
    canvas.scale(k);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 24, 24), Paint());
    final fill = Paint()
      ..color = color
      ..isAntiAlias = true;
    final cut = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    final cutStroke = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (glyph) {
      case CemeteryGlyph.headstone:
        _headstone(canvas, fill, cut);
      case CemeteryGlyph.cross:
        _cross(canvas, fill);
      case CemeteryGlyph.gate:
        _gate(canvas, fill, cut);
      case CemeteryGlyph.candle:
        _candle(canvas, fill, cut);
      case CemeteryGlyph.graves:
        _graves(canvas, fill, cut);
      case CemeteryGlyph.matzevah:
        _matzevah(canvas, fill, cutStroke);
      case CemeteryGlyph.orthodox:
        _orthodox(canvas, fill);
      case CemeteryGlyph.military:
        _military(canvas, fill);
    }
    canvas.restore();
    canvas.restore();
  }

  /// Płyta z zaokrągloną górą, wycięty krzyż, cokół.
  void _headstone(Canvas c, Paint fill, Paint cut) {
    final slab = Path()
      ..moveTo(5, 20)
      ..lineTo(5, 9)
      ..arcToPoint(const Offset(19, 9), radius: const Radius.circular(7))
      ..lineTo(19, 20)
      ..close();
    c.drawPath(slab, fill);
    c.drawRRect(RRect.fromLTRBR(3, 19.5, 21, 22.5, const Radius.circular(1)), fill);
    c.drawRect(const Rect.fromLTWH(11, 6, 2, 9), cut);
    c.drawRect(const Rect.fromLTWH(8.5, 8.2, 7, 2), cut);
  }

  /// Krzyż łaciński na kopczyku.
  void _cross(Canvas c, Paint fill) {
    c.drawRRect(RRect.fromLTRBR(10.6, 1.5, 13.4, 19, const Radius.circular(0.6)), fill);
    c.drawRRect(RRect.fromLTRBR(5.5, 6, 18.5, 8.8, const Radius.circular(0.6)), fill);
    final mound = Path()
      ..moveTo(3, 22.5)
      ..quadraticBezierTo(12, 15.5, 21, 22.5)
      ..close();
    c.drawPath(mound, fill);
  }

  /// Brama cmentarna: dwa filary, łuk z krzyżem, kraty.
  void _gate(Canvas c, Paint fill, Paint cut) {
    c.drawRect(const Rect.fromLTWH(2.5, 8, 4, 14.5), fill);
    c.drawRect(const Rect.fromLTWH(17.5, 8, 4, 14.5), fill);
    c.drawRect(const Rect.fromLTWH(2, 7, 5, 1.6), fill);
    c.drawRect(const Rect.fromLTWH(17, 7, 5, 1.6), fill);
    final arch = Path()
      ..moveTo(6.5, 12)
      ..quadraticBezierTo(12, 5.5, 17.5, 12)
      ..lineTo(17.5, 13.6)
      ..quadraticBezierTo(12, 7.6, 6.5, 13.6)
      ..close();
    c.drawPath(arch, fill);
    for (final x in [8.6, 11.3, 14.0]) {
      c.drawRect(Rect.fromLTWH(x, 11.2, 1.3, 11.3), fill);
    }
    c.drawRect(const Rect.fromLTWH(6.5, 16.5, 11, 1.2), fill);
    c.drawRect(const Rect.fromLTWH(11.3, 1.5, 1.4, 6), fill);
    c.drawRect(const Rect.fromLTWH(9.6, 3, 4.8, 1.4), fill);
  }

  /// Znicz: płomień, pokrywka, klosz z prześwitem.
  void _candle(Canvas c, Paint fill, Paint cut) {
    final flame = Path()
      ..moveTo(12, 1.5)
      ..cubicTo(15.2, 4.8, 14.8, 7.6, 12, 8.6)
      ..cubicTo(9.2, 7.6, 8.8, 4.8, 12, 1.5)
      ..close();
    c.drawPath(flame, fill);
    c.drawRRect(RRect.fromLTRBR(7.5, 9.4, 16.5, 11.2, const Radius.circular(0.8)), fill);
    final glass = Path()
      ..moveTo(8, 11.2)
      ..lineTo(16, 11.2)
      ..lineTo(17.4, 20.5)
      ..lineTo(6.6, 20.5)
      ..close();
    c.drawPath(glass, fill);
    c.drawRRect(RRect.fromLTRBR(5.5, 20.2, 18.5, 22.6, const Radius.circular(0.8)), fill);
    final shine = Path()
      ..moveTo(9.2, 12.6)
      ..lineTo(10.6, 12.6)
      ..lineTo(10.2, 19.2)
      ..lineTo(8.6, 19.2)
      ..close();
    c.drawPath(shine, cut);
  }

  /// Kwatera: trzy nagrobki różnej wysokości.
  void _graves(Canvas c, Paint fill, Paint cut) {
    void stone(double x, double w, double top) {
      final p = Path()
        ..moveTo(x, 20.5)
        ..lineTo(x, top + w / 2)
        ..arcToPoint(Offset(x + w, top + w / 2), radius: Radius.circular(w / 2))
        ..lineTo(x + w, 20.5)
        ..close();
      c.drawPath(p, fill);
    }

    stone(1.5, 6, 9);
    stone(16.5, 6, 9);
    stone(8.2, 7.6, 4);
    c.drawRect(const Rect.fromLTWH(11.4, 7, 1.2, 6), cut);
    c.drawRect(const Rect.fromLTWH(10, 8.4, 4, 1.2), cut);
    c.drawRRect(RRect.fromLTRBR(0.5, 20.5, 23.5, 22.5, const Radius.circular(0.8)), fill);
  }

  /// Macewa z wyrytą gwiazdą Dawida.
  void _matzevah(Canvas c, Paint fill, Paint cutStroke) {
    final slab = Path()
      ..moveTo(5.5, 21)
      ..lineTo(5.5, 7)
      ..lineTo(9, 3.5)
      ..quadraticBezierTo(12, 1.5, 15, 3.5)
      ..lineTo(18.5, 7)
      ..lineTo(18.5, 21)
      ..close();
    c.drawPath(slab, fill);
    c.drawRRect(RRect.fromLTRBR(4, 20.5, 20, 22.8, const Radius.circular(0.8)), fill);
    const cx = 12.0, cy = 10.5, r = 3.6;
    Path tri(double rot) {
      final p = Path();
      for (var i = 0; i < 3; i++) {
        final a = rot + i * 2 * math.pi / 3;
        final pt = Offset(cx + r * math.sin(a), cy - r * math.cos(a));
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      return p..close();
    }

    cutStroke.strokeWidth = 1.05;
    c.drawPath(tri(0), cutStroke);
    c.drawPath(tri(math.pi), cutStroke);
    for (final y in [16.0, 18.0]) {
      c.drawLine(Offset(8.5, y), Offset(15.5, y), cutStroke..strokeWidth = 0.9);
    }
  }

  /// Krzyż prawosławny: tabliczka, belka, skośny suppedaneum.
  void _orthodox(Canvas c, Paint fill) {
    c.drawRRect(RRect.fromLTRBR(10.8, 1, 13.2, 21.5, const Radius.circular(0.5)), fill);
    c.drawRRect(RRect.fromLTRBR(8.6, 4, 15.4, 5.8, const Radius.circular(0.5)), fill);
    c.drawRRect(RRect.fromLTRBR(5.5, 8, 18.5, 10.3, const Radius.circular(0.5)), fill);
    final foot = Path()
      ..moveTo(7.6, 14.2)
      ..lineTo(16.6, 16.6)
      ..lineTo(16.2, 18.4)
      ..lineTo(7.2, 16)
      ..close();
    c.drawPath(foot, fill);
    c.drawRRect(RRect.fromLTRBR(6, 21, 18, 23, const Radius.circular(0.8)), fill);
  }

  /// Cmentarz wojenny: krzyż o rozszerzonych ramionach na postumencie.
  void _military(Canvas c, Paint fill) {
    const cx = 12.0, cy = 9.5;
    final p = Path();
    // cztery ramiona rozszerzające się na końcach
    for (var i = 0; i < 4; i++) {
      final arm = Path()
        ..moveTo(cx - 1.3, cy)
        ..lineTo(cx - 3.6, cy - 7.5)
        ..lineTo(cx + 3.6, cy - 7.5)
        ..lineTo(cx + 1.3, cy)
        ..close();
      final m = Matrix4.identity()
        ..translate(cx, cy)
        ..rotateZ(i * math.pi / 2)
        ..translate(-cx, -cy);
      p.addPath(arm.transform(m.storage), Offset.zero);
    }
    p.addOval(Rect.fromCircle(center: const Offset(cx, cy), radius: 2.2));
    c.drawPath(p, fill);
    c.drawRect(const Rect.fromLTWH(10.8, 17, 2.4, 3), fill);
    c.drawRRect(RRect.fromLTRBR(5, 20, 19, 23, const Radius.circular(0.8)), fill);
  }

  @override
  bool shouldRepaint(CemeteryGlyphPainter o) => o.glyph != glyph || o.color != color;
}

/// Wybór wyglądu ikony cmentarzy (do ustawień).
class CemeteryIconPicker extends StatelessWidget {
  const CemeteryIconPicker({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<CemeteryIconStyle>(
      valueListenable: CemeteryIcons.style,
      builder: (_, current, __) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in CemeteryIconStyle.values)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => CemeteryIcons.set(s),
            child: Container(
              width: 96,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: current == s ? cs.primaryContainer : cs.surfaceContainerHighest,
                border: Border.all(color: current == s ? cs.primary : Colors.transparent, width: 2),
              ),
              child: Column(children: [
                if (s == CemeteryIconStyle.byKind)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final k in ['parafialny', 'żydowski', 'prawosławny', 'wojskowy'])
                      CemeteryIcon(kind: k, size: 20, style: s, color: cs.onSurface),
                  ])
                else
                  CemeteryIcon(size: 32, style: s, color: cs.onSurface),
                const SizedBox(height: 6),
                Text(s.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ),
      ]),
    );
  }
}
