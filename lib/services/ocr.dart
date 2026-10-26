import 'dart:io';

import 'package:exif/exif.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Odczyt napisu z nagrobka (ML Kit, działa bez internetu).
class Ocr {
  static Future<String> readImage(String path) async {
    final rec = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final res = await rec.processImage(InputImage.fromFilePath(path));
      // bloki od góry do dołu, linie w bloku od lewej
      final lines = <(double, double, String)>[];
      for (final b in res.blocks) {
        for (final l in b.lines) {
          lines.add((l.boundingBox.top, l.boundingBox.left, l.text));
        }
      }
      lines.sort((a, b) {
        // linie w tym samym „wierszu” (różnica < 12 px) – od lewej
        if ((a.$1 - b.$1).abs() < 12) return a.$2.compareTo(b.$2);
        return a.$1.compareTo(b.$1);
      });
      return lines.map((e) => e.$3).join('\n');
    } finally {
      await rec.close();
    }
  }
}

class PhotoMeta {
  final double? lat;
  final double? lng;
  final DateTime? taken;
  PhotoMeta(this.lat, this.lng, this.taken);
}

/// Pozycja GPS i data z EXIF zdjęcia (np. zdjęcie grobu zrobione wcześniej aparatem).
Future<PhotoMeta> readPhotoMeta(String path) async {
  try {
    final tags = await readExifFromBytes(await File(path).readAsBytes());
    double? coord(String key, String refKey) {
      final t = tags[key];
      if (t == null) return null;
      final vals = t.values.toList();
      if (vals.length < 3) return null;
      double r(dynamic v) {
        if (v is Ratio) return v.numerator / (v.denominator == 0 ? 1 : v.denominator);
        return (v as num).toDouble();
      }

      var d = r(vals[0]) + r(vals[1]) / 60 + r(vals[2]) / 3600;
      final ref = tags[refKey]?.printable.trim().toUpperCase() ?? '';
      if (ref == 'S' || ref == 'W') d = -d;
      return d;
    }

    final lat = coord('GPS GPSLatitude', 'GPS GPSLatitudeRef');
    final lng = coord('GPS GPSLongitude', 'GPS GPSLongitudeRef');
    DateTime? taken;
    final dt = tags['EXIF DateTimeOriginal']?.printable ?? tags['Image DateTime']?.printable;
    if (dt != null) {
      final m = RegExp(r'(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(dt);
      if (m != null) {
        taken = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!), int.parse(m[6]!));
      }
    }
    final valid = lat != null && lng != null && !(lat == 0 && lng == 0) && lat.abs() <= 90 && lng.abs() <= 180;
    return PhotoMeta(valid ? lat : null, valid ? lng : null, taken);
  } catch (_) {
    return PhotoMeta(null, null, null);
  }
}
