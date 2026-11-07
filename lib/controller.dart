import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'core.dart';
import 'native.dart';

/// Holds the app state. Every change is: reload the latest data → apply → save.
/// Saving also tells Android to set the next alarm.
class AppCtl extends ChangeNotifier {
  AppState s = AppState.empty();
  Map<String, dynamic> status = {};
  List<Map<String, dynamic>> voices = [];
  String defaultVoiceLang = '';
  bool loaded = false;
  bool voicesLoaded = false;

  bool get h24 => s.settings.timeFormat == '24';
  String fmtT(DateTime d) => fmtTime(d, h24);

  Future<void> init() async {
    Native.onStateChanged = () => reload();
    await reload();
    if (!s.seeded) await _seed();
    await refreshStatus();
  }

  Future<void> reload() async {
    final j = await Native.load();
    try {
      s = AppState.fromJson(jsonDecode(j));
    } catch (_) {}
    loaded = true;
    notifyListeners();
  }

  Future<void> mutate(void Function(AppState st) fn) async {
    try {
      s = AppState.fromJson(jsonDecode(await Native.load()));
    } catch (_) {}
    fn(s);
    notifyListeners();
    await Native.save(jsonEncode(s.toJson()));
    refreshStatus();
  }

  Future<void> refreshStatus() async {
    status = await Native.status();
    notifyListeners();
  }

  Future<void> loadVoices() async {
    final v = await Native.voices();
    voices = ((v['voices'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    defaultVoiceLang = '${v['default'] ?? ''}';
    voicesLoaded = true;
    notifyListeners();
  }

  /// Problems that can stop reminders from ringing on time.
  List<String> get setupProblems {
    if (status.isEmpty) return const [];
    final p = <String>[];
    if (status['notifications'] != true) p.add('notifications');
    if (status['exactAlarms'] != true) p.add('exact');
    if (status['battery'] != true) p.add('battery');
    if (status['fullScreen'] != true) p.add('fullscreen');
    return p;
  }

  String get settingsJson => jsonEncode(s.settings.toJson());

  // ---------- task actions ----------
  Future<void> saveTask(Task e, {required bool isNew}) async {
    await mutate((st) {
      final now = DateTime.now();
      Task t;
      if (isNew) {
        t = e.copy()
          ..id = newId()
          ..createdAt = now.millisecondsSinceEpoch;
        st.tasks.add(t);
      } else {
        final i = st.tasks.indexWhere((x) => x.id == e.id);
        if (i < 0) return;
        t = e.copy();
        st.tasks[i] = t;
      }
      if (isRec(t)) {
        t.cursor = now.millisecondsSinceEpoch - 30000;
        t.completed = false;
      } else {
        t.cursor = 0;
        final s0 = startOf(t);
        if (s0.isBefore(now)) {
          // Already in the past: don't announce it as "missed".
          for (final off in [0, ...t.advance]) {
            st.fired['${t.id}|${s0.millisecondsSinceEpoch}|$off'] = now.millisecondsSinceEpoch;
          }
        } else if (t.completed) {
          t.completed = false;
          t.completedAt = 0;
        }
      }
      st.snoozes.removeWhere((z) => z.taskId == t.id);
    });
  }

  /// Returns a short confirmation for the user.
  Future<String> complete(Task task, [int? occMs]) async {
    var msg = 'Task completed ✓';
    await mutate((st) {
      final t = st.task(task.id);
      if (t == null) return;
      final now = DateTime.now();
      if (isRec(t)) {
        final o = occMs != null && occMs > 0 ? occMs : pendingOcc(t, now)?.millisecondsSinceEpoch;
        if (o == null) return;
        st.history.insert(0, HistoryEntry(newId(), t.id, t.title, t.category, o, now.millisecondsSinceEpoch));
        if (st.history.length > 400) st.history = st.history.sublist(0, 400);
        if (t.cursor < o + 60000) t.cursor = o + 60000;
        final n = pendingOcc(t, now);
        msg = n != null ? 'Done! Next: ${fmtDay(n)} at ${fmtT(n)}' : 'Done! That was the last one.';
      } else {
        t.completed = true;
        t.completedAt = now.millisecondsSinceEpoch;
      }
      st.snoozes.removeWhere((z) => z.taskId == t.id);
    });
    return msg;
  }

  Future<void> restore(Task task) async {
    await mutate((st) {
      final t = st.task(task.id);
      if (t == null) return;
      t.completed = false;
      t.completedAt = 0;
      final s0 = startOf(t);
      if (s0.isBefore(DateTime.now())) {
        for (final off in [0, ...t.advance]) {
          st.fired['${t.id}|${s0.millisecondsSinceEpoch}|$off'] = DateTime.now().millisecondsSinceEpoch;
        }
      }
    });
  }

  Future<void> delete(Task task) async {
    await mutate((st) {
      st.tasks.removeWhere((t) => t.id == task.id);
      st.snoozes.removeWhere((z) => z.taskId == task.id);
    });
  }

  /// Postpone by [minutes], or to tomorrow at the same time.
  Future<String> postpone(Task task, {int minutes = 0, bool tomorrow = false}) async {
    var msg = '';
    await mutate((st) {
      final t = st.task(task.id);
      if (t == null) return;
      final now = DateTime.now();
      final s0 = startOf(t);
      if (isRec(t)) {
        final o = pendingOcc(t, now) ?? s0;
        final at = tomorrow
            ? DateTime(now.year, now.month, now.day + 1, s0.hour, s0.minute)
            : now.add(Duration(minutes: minutes));
        st.snoozes.add(Snooze(newId(), t.id, o.millisecondsSinceEpoch, at.millisecondsSinceEpoch));
        msg = 'Extra reminder set for ${fmtDay(at).toLowerCase()} at ${fmtT(at)}';
        return;
      }
      final base = s0.isAfter(now) ? s0 : now;
      final n = tomorrow
          ? DateTime(base.year, base.month, base.day + 1, s0.hour, s0.minute)
          : base.add(Duration(minutes: minutes));
      t.date = ymd(n);
      t.time = hm(n);
      st.snoozes.removeWhere((z) => z.taskId == t.id);
      msg = 'Moved to ${fmtDay(n).toLowerCase()} at ${fmtT(n)}';
    });
    return msg;
  }

  Future<void> clearMissed() async => mutate((st) => st.missed.clear());

  Future<void> updateSettings(void Function(Settings x) fn) async => mutate((st) => fn(st.settings));

  Future<void> deleteAll() async => mutate((st) {
        st.tasks.clear();
        st.history.clear();
        st.snoozes.clear();
        st.fired.clear();
        st.missed.clear();
      });

  String backupJson() => jsonEncode({
        'app': 'talking-reminder',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'tasks': s.tasks.map((e) => e.toJson()).toList(),
        'history': s.history.map((e) => e.toJson()).toList(),
        'settings': s.settings.toJson(),
      });

  /// Returns number of restored tasks, or -1 if the text isn't a backup.
  Future<int> restoreBackup(String text) async {
    try {
      final d = jsonDecode(text);
      if (d is! Map || d['tasks'] is! List) return -1;
      final b = AppState.fromJson(d);
      await mutate((st) {
        final now = DateTime.now();
        st.tasks = b.tasks;
        st.history = b.history;
        st.settings = Settings.fromJson(d['settings']);
        st.snoozes = [];
        st.fired = {};
        st.missed = [];
        for (final t in st.tasks) {
          if (isRec(t)) {
            if (t.cursor < now.millisecondsSinceEpoch - 30000) t.cursor = now.millisecondsSinceEpoch - 30000;
          } else {
            final s0 = startOf(t);
            if (s0.isBefore(now)) {
              for (final off in [0, ...t.advance]) {
                st.fired['${t.id}|${s0.millisecondsSinceEpoch}|$off'] = now.millisecondsSinceEpoch;
              }
            }
          }
        }
      });
      return b.tasks.length;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _seed() async {
    await mutate((st) {
      if (st.seeded) return;
      st.seeded = true;
      final now = DateTime.now();
      final tm = addDays(now, 1);
      final nowMs = now.millisecondsSinceEpoch;
      st.tasks.addAll([
        Task(
          id: newId(),
          createdAt: nowMs,
          title: 'Attend a business meeting',
          date: ymd(tm),
          time: '10:00',
          category: 'Work',
          priority: 'high',
          advance: [15],
          message: 'Hello! This is your reminder. You have a business meeting scheduled for {date} at {time}. Please get ready.',
        ),
        Task(
          id: '${newId()}w',
          createdAt: nowMs,
          title: 'Take your evening walk',
          date: ymd(now),
          time: '18:00',
          category: 'Health',
          repeat: RepeatRule(type: 'daily'),
          message: "Hello! It is time for your evening walk. Don't forget to take care of your health.",
          cursor: nowMs - 30000,
        ),
        Task(
          id: '${newId()}a',
          createdAt: nowMs,
          title: 'Call Ahmed',
          date: ymd(tm),
          time: '15:00',
          category: 'Personal',
          advance: [10],
        ),
      ]);
    });
  }
}

final ctl = AppCtl();
