import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Tiny dependency-free i18n, ported from lib/i18n.js.
///
/// English source strings are the keys — `t('Rest day')` — so the app reads as English in the
/// source and nothing is ever shipped as an untranslated placeholder key. Locale packs live in
/// assets and are loaded on demand, so a profile in English never pays for the other eleven.
///
/// Exercise instructions come from separately generated packs (assets/instr/), also loaded on
/// language switch, and fall back to the dataset's English steps where a language has none.

/// UI languages. de/pt have no instruction pack upstream — instructions fall back to English.
const langs = <String, String>{
  'en': 'English',
  'de': 'Deutsch',
  'es': 'Español',
  'fr': 'Français',
  'it': 'Italiano',
  'pt': 'Português',
  'pl': 'Polski',
  'tr': 'Türkçe',
  'ru': 'Русский',
  'zh': '中文',
  'ko': '한국어',
  'hi': 'हिन्दी',
};

const instrLangs = <String>['en', 'es', 'fr', 'it', 'tr', 'ru', 'zh', 'hi', 'pl', 'ko'];

const _dateLocales = <String, String>{
  'en': 'en_GB', 'de': 'de_DE', 'es': 'es_ES', 'fr': 'fr_FR', 'it': 'it_IT', 'pt': 'pt_PT',
  'pl': 'pl_PL', 'tr': 'tr_TR', 'ru': 'ru_RU', 'zh': 'zh_CN', 'ko': 'ko_KR', 'hi': 'hi_IN',
};

class I18n extends ChangeNotifier {
  I18n._();

  static final I18n instance = I18n._();

  String _lang = 'en';
  Map<String, String> _dict = const {};
  Map<String, List<String>> _instr = const {};

  String get lang => _lang;

  /// The locale dates and numbers are formatted in. Numbers follow the UI language just like
  /// dates do — a hardcoded locale put Swiss apostrophes ("7'535 kg") in front of every user,
  /// in every language.
  String get dateLocale => _dateLocales[_lang] ?? 'en_GB';

  Future<void> setLang(String? l) async {
    final next = langs.containsKey(l) ? l! : 'en';
    if (next == _lang && (_dict.isNotEmpty || next == 'en')) return;
    _lang = next;
    try {
      _dict = next == 'en'
          ? const {}
          : Map<String, String>.from(
              jsonDecode(await rootBundle.loadString('assets/i18n/$next.json')) as Map);
      _instr = next == 'en' || !instrLangs.contains(next)
          ? const {}
          : (jsonDecode(await rootBundle.loadString('assets/instr/$next.json')) as Map)
              .map((k, v) => MapEntry(k as String, [for (final s in v as List) s as String]));
    } catch (_) {
      // A missing or malformed pack falls back to English rather than taking the app down.
      _dict = const {};
      _instr = const {};
    }
    notifyListeners();
  }

  /// Translate a source string; `{0}`, `{1}`… are replaced with args — on the English
  /// fallback too, so an untranslated string still reads correctly.
  String translate(String s, [List<Object?> args = const []]) {
    var v = _dict[s] ?? s;
    for (var i = 0; i < args.length; i++) {
      v = v.replaceAll('{$i}', '${args[i]}');
    }
    return v;
  }

  /// Instructions for an exercise in the current language, English steps as the fallback.
  List<String> instrFor(String exId, List<String> englishSteps) =>
      _instr[exId] ?? englishSteps;
}

/// `t('Rest day')`, `t('Hi {0}', name)` — the same call shape as the JavaScript.
String t(String s, [Object? a0, Object? a1, Object? a2, Object? a3]) {
  if (a0 == null) return I18n.instance.translate(s);
  final args = <Object?>[a0];
  if (a1 != null) args.add(a1);
  if (a2 != null) args.add(a2);
  if (a3 != null) args.add(a3);
  return I18n.instance.translate(s, args);
}

/// For a template that arrives already packed with its arguments — `t(...plan.why)` in the
/// source, where the progression engine returns the reason as `[template, ...args]`.
String tList(List<Object?> why) => why.isEmpty
    ? ''
    : I18n.instance.translate(why.first as String, why.skip(1).toList());

String get dateLocale => I18n.instance.dateLocale;
String getLang() => I18n.instance.lang;
