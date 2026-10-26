import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Rozpoznawanie mowy (systemowe – Google na Androidzie, Apple na iPhonie), po polsku.
class Speech {
  static final SpeechToText _stt = SpeechToText();
  static bool _ready = false;
  static String? _locale;
  static String? lastError;

  static bool get isListening => _stt.isListening;

  static Future<bool> init() async {
    if (_ready) return true;
    try {
      _ready = await _stt.initialize(
        onError: (e) => lastError = e.errorMsg,
        onStatus: (_) {},
      );
      if (_ready) {
        final locales = await _stt.locales();
        final pl = locales.where((l) => l.localeId.toLowerCase().startsWith('pl')).toList();
        _locale = pl.isNotEmpty ? pl.first.localeId : 'pl_PL';
      }
    } catch (e) {
      lastError = '$e';
      _ready = false;
    }
    return _ready;
  }

  static Future<void> listen({required void Function(String text, bool isFinal) onResult, void Function()? onDone}) async {
    if (!await init()) return;
    lastError = null;
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) {
        onResult(r.recognizedWords, r.finalResult);
        if (r.finalResult) onDone?.call();
      },
      listenOptions: SpeechListenOptions(
        localeId: _locale,
        listenFor: const Duration(seconds: 90),
        pauseFor: const Duration(seconds: 5),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  static Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }

  static Future<void> cancel() async {
    try {
      await _stt.cancel();
    } catch (_) {}
  }
}
