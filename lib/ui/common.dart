import 'dart:io';

import 'package:flutter/material.dart';

import '../data/db.dart';
import '../data/models.dart';
import '../logic/dates_pl.dart';
import 'dictation.dart';

const seed = Color(0xFFB4690E); // płomień znicza

String fmtDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

const _monthsGen = ['stycznia', 'lutego', 'marca', 'kwietnia', 'maja', 'czerwca', 'lipca', 'sierpnia', 'września', 'października', 'listopada', 'grudnia'];
const _weekdays = ['poniedziałek', 'wtorek', 'środa', 'czwartek', 'piątek', 'sobota', 'niedziela'];

String fmtDayMonth(DateTime d) => '${d.day} ${_monthsGen[d.month - 1]}';
String fmtLong(DateTime d) => '${d.day} ${_monthsGen[d.month - 1]} ${d.year}';
String weekday(DateTime d) => _weekdays[d.weekday - 1];

String fmtPartialLong(PartialDate d) {
  if (d.month == null) return '${d.year}';
  if (d.day == null) return '${['styczeń', 'luty', 'marzec', 'kwiecień', 'maj', 'czerwiec', 'lipiec', 'sierpień', 'wrzesień', 'październik', 'listopad', 'grudzień'][d.month! - 1]} ${d.year}';
  return '${d.day} ${_monthsGen[d.month! - 1]} ${d.year}';
}

String relativeDays(int days) {
  if (days == 0) return 'dziś';
  if (days == 1) return 'jutro';
  if (days == 2) return 'pojutrze';
  if (days < 0) return days == -1 ? 'wczoraj' : '${-days} dni temu';
  return 'za $days dni';
}

String agoText(DateTime d) {
  final days = DateTime.now().difference(d).inDays;
  if (days < 1) return 'dziś';
  if (days == 1) return 'wczoraj';
  if (days < 31) return '$days dni temu';
  if (days < 365) return '${(days / 30).floor()} mies. temu';
  final y = (days / 365).floor();
  return y == 1 ? 'rok temu' : (y < 5 ? '$y lata temu' : '$y lat temu');
}

/// „lata” / „lat” itd.
String yearsWord(int n) {
  if (n == 1) return 'rok';
  final l = n % 10, ll = n % 100;
  if (l >= 2 && l <= 4 && (ll < 12 || ll > 14)) return 'lata';
  return 'lat';
}

void snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

Future<bool> confirm(BuildContext context, String title, String body, {String ok = 'Usuń', bool destructive = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Anuluj')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error, foregroundColor: Theme.of(c).colorScheme.onError) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

class PhotoThumb extends StatelessWidget {
  final GravePhoto? photo;
  final double size;
  final double radius;
  final IconData fallback;
  const PhotoThumb(this.photo, {super.key, this.size = 56, this.radius = 12, this.fallback = Icons.local_fire_department_outlined});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget child;
    if (photo == null) {
      child = Container(color: cs.secondaryContainer, child: Icon(fallback, color: cs.onSecondaryContainer, size: size * 0.45));
    } else {
      child = Image.file(
        File(AppDb.I.absPath(photo!.path)),
        fit: BoxFit.cover,
        cacheWidth: (size * 3).round(),
        errorBuilder: (_, __, ___) => Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image_outlined)),
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: SizedBox(width: size, height: size, child: child));
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 6),
      child: Row(children: [
        Expanded(child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600))),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, required this.body, this.action});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 64, color: cs.primary),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(body, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 24), action!],
        ]),
      ),
    );
  }
}

/// Pole tekstowe z przyciskiem mikrofonu (dyktowanie do pola).
class VoiceField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboard;
  final TextCapitalization caps;
  final bool append; // dyktowanie dopisuje do istniejącego tekstu
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final Widget? prefixIcon;

  const VoiceField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.keyboard,
    this.caps = TextCapitalization.sentences,
    this.append = false,
    this.onChanged,
    this.validator,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: 1,
      maxLines: maxLines,
      keyboardType: keyboard ?? (maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      textCapitalization: caps,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: IconButton(
          tooltip: 'Podyktuj',
          icon: const Icon(Icons.mic_none),
          onPressed: () async {
            final t = await dictate(context, title: label, initial: append ? '' : controller.text);
            if (t == null) return;
            var v = t.trim();
            if (caps == TextCapitalization.words) v = v.split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
            if (caps == TextCapitalization.sentences && v.isNotEmpty) v = v[0].toUpperCase() + v.substring(1);
            controller.text = append && controller.text.trim().isNotEmpty ? '${controller.text.trim()}\n$v' : v;
            onChanged?.call(controller.text);
          },
        ),
      ),
    );
  }
}

/// Pole daty niepełnej: „12.03.1932”, „03.1932”, „1932”, „12 marca 1932”.
class PartialDateField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  const PartialDateField({super.key, required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'dd.mm.rrrr lub sam rok',
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            tooltip: 'Podyktuj datę',
            icon: const Icon(Icons.mic_none),
            onPressed: () async {
              final t = await dictate(context, title: label, hint: 'np. „12 marca 1932” albo „1932”');
              if (t == null) return;
              final d = parseLooseDate(t);
              controller.text = d?.format() ?? t;
            },
          ),
          IconButton(
            tooltip: 'Kalendarz',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final cur = parseLooseDate(controller.text);
              final picked = await showDatePicker(
                context: context,
                initialDate: cur?.toDateTime() ?? DateTime.now(),
                firstDate: DateTime(1700),
                lastDate: DateTime(2150),
                locale: const Locale('pl'),
              );
              if (picked != null) controller.text = PartialDate(picked.year, picked.month, picked.day).format();
            },
          ),
        ]),
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        return parseLooseDate(v) == null ? 'Nie rozpoznano daty' : null;
      },
    );
  }
}
