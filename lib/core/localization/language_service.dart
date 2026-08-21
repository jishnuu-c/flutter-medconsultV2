import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'translations.dart';

const String _kPrefLangKey = 'preferredLang';

class LanguageNotifier extends StateNotifier<Locale> {
  LanguageNotifier() : super(const Locale('en')) {
    _loadSavedLanguage();
  }

  static String _currentLangCode = 'en';
  static String get currentLanguageCode => _currentLangCode;

  Future<void> _loadSavedLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_kPrefLangKey);
      if (saved != null && (saved == 'en' || saved == 'ar')) {
        _currentLangCode = saved;
        state = Locale(saved);
      }
    } catch (_) {}
  }

  Future<void> setLanguage(String lang) async {
    if (lang != 'en' && lang != 'ar') return;
    _currentLangCode = lang;
    state = Locale(lang);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefLangKey, lang);
    } catch (_) {}
  }

  Future<void> toggleLanguage() async {
    final next = state.languageCode == 'en' ? 'ar' : 'en';
    await setLanguage(next);
  }

  bool get isArabic => state.languageCode == 'ar';

  String instant(String key) {
    if (key.isEmpty) return '';
    final clean = key.trim();
    final langMap = appTranslations[state.languageCode];
    if (langMap != null && langMap.containsKey(clean)) {
      return langMap[clean]!;
    }
    return key;
  }

  T translate<T>(T enValue, T arValue) {
    return isArabic ? arValue : enValue;
  }
}

final languageNotifierProvider =
    StateNotifierProvider<LanguageNotifier, Locale>((ref) {
  return LanguageNotifier();
});

final isArabicProvider = Provider<bool>((ref) {
  return ref.watch(languageNotifierProvider).languageCode == 'ar';
});

class LanguageService {
  static String get currentLanguageCode => LanguageNotifier.currentLanguageCode;
  static bool get isArabic => LanguageNotifier.currentLanguageCode == 'ar';

  static String translateKey(String key, [String? langCode]) {
    if (key.isEmpty) return '';
    final clean = key.trim();
    final lang = langCode ?? currentLanguageCode;
    final langMap = appTranslations[lang];
    if (langMap != null && langMap.containsKey(clean)) {
      return langMap[clean]!;
    }
    return key;
  }

  static T translate<T>(T enValue, T arValue, [bool? isAr]) {
    final ar = isAr ?? isArabic;
    return ar ? arValue : enValue;
  }
}

extension StringTranslationExtension on String {
  /// Translates the string based on active language or provided language code.
  String get tr => LanguageService.translateKey(this);
}

extension BuildContextTranslationExtension on BuildContext {
  bool get isArabic => Directionality.of(this) == TextDirection.rtl;
  String tr(String key) =>
      LanguageService.translateKey(key, isArabic ? 'ar' : 'en');
}
