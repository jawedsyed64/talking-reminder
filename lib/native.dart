// Bridge to the Android code in android/app/src/main/kotlin (alarms, speech, storage).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Native {
  static const _ch = MethodChannel('talking_reminder/native');
  static void Function(String alertJson)? onShowAlert;
  static void Function()? onStateChanged;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'showAlert' && call.arguments is String) onShowAlert?.call(call.arguments as String);
      if (call.method == 'stateChanged') onStateChanged?.call();
      return null;
    });
  }

  static Future<T?> _call<T>(String m, [Object? args]) async {
    try {
      return await _ch.invokeMethod<T>(m, args);
    } catch (e) {
      debugPrint('native $m failed: $e');
      return null;
    }
  }

  static Future<String> load() async => await _call<String>('load') ?? '{}';
  static Future<void> save(String json) async {
    await _call('save', json);
  }
  static Future<Map<String, dynamic>> status() async =>
      Map<String, dynamic>.from(await _call<Map>('status') ?? const {});
  static Future<Map<String, dynamic>> voices() async =>
      Map<String, dynamic>.from(await _call<Map>('voices') ?? const {});
  static Future<bool> speak(String text, String settingsJson, {bool sound = false}) async =>
      await _call<bool>('speak', {'text': text, 'settings': settingsJson, 'sound': sound}) ?? false;
  static Future<void> stopSpeaking() async {
    await _call('stopSpeaking');
  }
  static Future<void> playSound(String sound) async {
    await _call('playSound', {'sound': sound});
  }
  static Future<String> buildMessage(String taskJson, int occ, String kind, int offset, String settingsJson) async =>
      await _call<String>('buildMessage',
          {'task': taskJson, 'occ': occ, 'kind': kind, 'offset': offset, 'settings': settingsJson}) ??
      '';
  static Future<void> alertAction(String act,
      {String taskId = '', int occ = 0, String key = '', int minutes = 0, int at = 0}) async {
    await _call('alertAction', {'act': act, 'taskId': taskId, 'occ': occ, 'key': key, 'minutes': minutes, 'at': at});
  }
  static Future<String?> takeLaunchAlert() async => _call<String>('takeLaunchAlert');
  static Future<void> testIn(int seconds) async {
    await _call('testIn', {'seconds': seconds});
  }
  static Future<bool?> requestNotifications() async => _call<bool>('requestNotifications');
  static Future<void> openSettings(String which) async {
    await _call('openSettings', {'which': which});
  }
  static Future<void> share(String text) async {
    await _call('share', {'text': text});
  }

  /// Opens the phone's speech-input popup. Returns the recognised text, or null.
  static Future<String?> listen(String lang) async {
    try {
      return await _ch.invokeMethod<String>('listen', {'lang': lang});
    } on PlatformException catch (e) {
      throw Exception(e.message ?? 'Speech input is not available.');
    } on MissingPluginException {
      return null;
    }
  }
}
