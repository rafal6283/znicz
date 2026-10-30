import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:znicz/ui/cemetery_icon.dart';

/// Renderuje wszystkie symbole cmentarzy do build/icons_preview.png (podgląd w CI).
void main() {
  testWidgets('podgląd ikon cmentarzy', (tester) async {
    final key = GlobalKey();
    const glyphs = CemeteryGlyph.values;
    await tester.binding.setSurfaceSize(const Size(900, 330));
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Row(children: [
              for (final g in glyphs)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(width: 88, height: 88, child: CustomPaint(painter: CemeteryGlyphPainter(g, const Color(0xFF3A3A3A)))),
                ),
            ]),
            Row(children: [
              for (final g in glyphs)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(color: Color(0xFF8E5A1B), shape: BoxShape.circle),
                    padding: const EdgeInsets.all(20),
                    child: CustomPaint(painter: CemeteryGlyphPainter(g, Colors.white)),
                  ),
                ),
            ]),
            Row(children: [
              for (final g in glyphs)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(width: 88, height: 88, child: Center(child: SizedBox(width: 24, height: 24, child: CustomPaint(painter: CemeteryGlyphPainter(g, Colors.black))))),
                ),
            ]),
          ]),
        ),
      ),
    ));
    await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory('build').createSync(recursive: true);
      File('build/icons_preview.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    expect(glyphForTest(), isNotEmpty);
  });
}

List<CemeteryGlyph> glyphForTest() => [
      glyphFor(CemeteryIconStyle.byKind, 'żydowski'),
      glyphFor(CemeteryIconStyle.byKind, 'parafialny'),
      glyphFor(CemeteryIconStyle.gate, 'żydowski'),
    ];
