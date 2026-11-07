// Data model, recurrence engine and date helpers.
// The recurrence rules mirror android/.../Rec.kt exactly, so the screens and the
// background alarms always agree on when a reminder is due.

// ---------------- date helpers ----------------
String pad2(int n) => n.toString().padLeft(2, '0');
String ymd(DateTime d) => '${d.year}-${pad2(d.month)}-${pad2(d.day)}';
String hm(DateTime d) => '${pad2(d.hour)}:${pad2(d.minute)}';

DateTime parseLocal(String ds, String ts) {
  final p = ds.split('-').map((e) => int.tryParse(e.trim()) ?? 1).toList();
  final t = ts.split(':').map((e) => int.tryParse(e.trim()) ?? 0).toList();
  return DateTime(p[0], p.length > 1 ? p[1] : 1, p.length > 2 ? p[2] : 1, t.isNotEmpty ? t[0] : 9, t.length > 1 ? t[1] : 0);
}

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n, d.hour, d.minute);
int dayDiff(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;
bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// 0 = Sunday … 6 = Saturday
int jsDow(DateTime d) => d.weekday % 7;

DateTime monthAdd(DateTime s, int n) {
  final y = s.year, m = s.month + n;
  final dim = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, s.day < dim ? s.day : dim, s.hour, s.minute);
}

int _i(dynamic v, [int d = 0]) => v is num ? v.toInt() : (int.tryParse('$v') ?? d);
double _d(dynamic v, double d) => v is num ? v.toDouble() : (double.tryParse('$v') ?? d);
String _s(dynamic v, [String d = '']) => v == null ? d : '$v';

// ---------------- model ----------------
class RepeatRule {
  String type; // none | daily | weekly | monthly | custom
  int every;
  String unit; // day | week | month
  List<int> days; // 0 = Sun
  String until; // yyyy-mm-dd or ''

  RepeatRule({this.type = 'none', this.every = 1, this.unit = 'day', List<int>? days, this.until = ''})
      : days = days ?? <int>[];

  factory RepeatRule.fromJson(dynamic j) {
    if (j is! Map) return RepeatRule();
    return RepeatRule(
      type: _s(j['type'], 'none'),
      every: _i(j['every'], 1),
      unit: _s(j['unit'], 'day'),
      days: ((j['days'] as List?) ?? const []).map((e) => _i(e)).toList(),
      until: _s(j['until']),
    );
  }

  Map<String, dynamic> toJson() => {'type': type, 'every': every, 'unit': unit, 'days': days, 'until': until};
  RepeatRule copy() => RepeatRule.fromJson(toJson());
}

class Task {
  String id, title, description, notes, date, time, category, priority, message;
  RepeatRule repeat;
  List<int> advance;
  bool completed;
  int completedAt, cursor, createdAt;

  Task({
    required this.id,
    this.title = '',
    this.description = '',
    this.notes = '',
    required this.date,
    required this.time,
    this.category = 'Personal',
    this.priority = 'medium',
    this.message = '',
    RepeatRule? repeat,
    List<int>? advance,
    this.completed = false,
    this.completedAt = 0,
    this.cursor = 0,
    this.createdAt = 0,
  })  : repeat = repeat ?? RepeatRule(),
        advance = advance ?? <int>[];

  factory Task.fromJson(Map j) => Task(
        id: _s(j['id']),
        title: _s(j['title']),
        description: _s(j['description']),
        notes: _s(j['notes']),
        date: _s(j['date'], ymd(DateTime.now())),
        time: _s(j['time'], '09:00'),
        category: _s(j['category'], 'Personal'),
        priority: _s(j['priority'], 'medium'),
        message: _s(j['message']),
        repeat: RepeatRule.fromJson(j['repeat']),
        advance: ((j['advance'] as List?) ?? const []).map((e) => _i(e)).toList(),
        completed: j['completed'] == true,
        completedAt: _i(j['completedAt']),
        cursor: _i(j['cursor']),
        createdAt: _i(j['createdAt']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'notes': notes,
        'date': date,
        'time': time,
        'category': category,
        'priority': priority,
        'message': message,
        'repeat': repeat.toJson(),
        'advance': advance,
        'completed': completed,
        'completedAt': completedAt,
        'cursor': cursor,
        'createdAt': createdAt,
      };

  Task copy() => Task.fromJson(toJson());
}

class HistoryEntry {
  String id, taskId, title, category;
  int occ, at;
  HistoryEntry(this.id, this.taskId, this.title, this.category, this.occ, this.at);
  factory HistoryEntry.fromJson(Map j) =>
      HistoryEntry(_s(j['id']), _s(j['taskId']), _s(j['title']), _s(j['category'], 'Other'), _i(j['occ']), _i(j['at']));
  Map<String, dynamic> toJson() =>
      {'id': id, 'taskId': taskId, 'title': title, 'category': category, 'occ': occ, 'at': at};
}

class Snooze {
  String id, taskId;
  int occ, at;
  bool test;
  Snooze(this.id, this.taskId, this.occ, this.at, {this.test = false});
  factory Snooze.fromJson(Map j) =>
      Snooze(_s(j['id']), _s(j['taskId']), _i(j['occ']), _i(j['at']), test: j['test'] == true);
  Map<String, dynamic> toJson() => {
        'id': id,
        if (taskId.isNotEmpty) 'taskId': taskId,
        'occ': occ,
        'at': at,
        if (test) 'test': true,
      };
}

class Settings {
  String voiceName, voiceLang, lang, sound, timeFormat, theme, sample;
  double rate, pitch, volume;
  int snooze;
  bool repeatSpeak;

  Settings({
    this.voiceName = '',
    this.voiceLang = '',
    this.lang = '',
    this.sound = 'chime',
    this.timeFormat = '12',
    this.theme = 'system',
    this.sample = defaultSample,
    this.rate = 0.95,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.snooze = 10,
    this.repeatSpeak = true,
  });

  static const defaultSample =
      'Hello! This is your reminder. You have a business meeting scheduled for today at 10 AM. Please get ready.';

  factory Settings.fromJson(dynamic j) {
    if (j is! Map) return Settings();
    return Settings(
      voiceName: _s(j['voiceName']),
      voiceLang: _s(j['voiceLang']),
      lang: _s(j['lang']),
      sound: _s(j['sound'], 'chime'),
      timeFormat: _s(j['timeFormat'], '12'),
      theme: _s(j['theme'], 'system'),
      sample: _s(j['sample'], defaultSample),
      rate: _d(j['rate'], 0.95),
      pitch: _d(j['pitch'], 1.0),
      volume: _d(j['volume'], 1.0),
      snooze: _i(j['snooze'], 10),
      repeatSpeak: j['repeatSpeak'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'voiceName': voiceName,
        'voiceLang': voiceLang,
        'lang': lang,
        'sound': sound,
        'timeFormat': timeFormat,
        'theme': theme,
        'sample': sample,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'snooze': snooze,
        'repeatSpeak': repeatSpeak,
      };
}

class AppState {
  List<Task> tasks;
  List<HistoryEntry> history;
  List<Snooze> snoozes;
  Map<String, int> fired;
  Settings settings;
  List<Map<String, dynamic>> missed;
  bool seeded;

  AppState({
    required this.tasks,
    required this.history,
    required this.snoozes,
    required this.fired,
    required this.settings,
    required this.missed,
    this.seeded = false,
  });

  factory AppState.empty() => AppState(
      tasks: [], history: [], snoozes: [], fired: {}, settings: Settings(), missed: [], seeded: false);

  factory AppState.fromJson(dynamic j) {
    if (j is! Map) return AppState.empty();
    List<Map> list(String k) => ((j[k] as List?) ?? const []).whereType<Map>().toList();
    final f = <String, int>{};
    final fj = j['fired'];
    if (fj is Map) fj.forEach((k, v) => f['$k'] = _i(v));
    return AppState(
      tasks: list('tasks').map((e) => Task.fromJson(e)).toList(),
      history: list('history').map((e) => HistoryEntry.fromJson(e)).toList(),
      snoozes: list('snoozes').map((e) => Snooze.fromJson(e)).toList(),
      fired: f,
      settings: Settings.fromJson(j['settings']),
      missed: list('missed').map((e) => Map<String, dynamic>.from(e)).toList(),
      seeded: j['seeded'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'tasks': tasks.map((e) => e.toJson()).toList(),
        'history': history.map((e) => e.toJson()).toList(),
        'snoozes': snoozes.map((e) => e.toJson()).toList(),
        'fired': fired,
        'settings': settings.toJson(),
        'missed': missed,
        'seeded': seeded,
      };

  Task? task(String id) {
    for (final t in tasks) {
      if (t.id == id) return t;
    }
    return null;
  }
}

String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) + (DateTime.now().hashCode & 0xffff).toRadixString(36);

// ---------------- recurrence ----------------
bool isRec(Task t) => t.repeat.type.isNotEmpty && t.repeat.type != 'none';
DateTime startOf(Task t) => parseLocal(t.date, t.time);

class _Rule {
  final String unit;
  final int every;
  final List<int> days;
  _Rule(this.unit, this.every, this.days);
}

_Rule? _rule(Task t) {
  final r = t.repeat;
  final sd = [jsDow(startOf(t))];
  switch (r.type) {
    case 'daily':
      return _Rule('day', 1, sd);
    case 'weekly':
      return _Rule('week', 1, r.days.isEmpty ? sd : r.days);
    case 'monthly':
      return _Rule('month', 1, sd);
    case 'custom':
      return _Rule(r.unit.isEmpty ? 'day' : r.unit, r.every < 1 ? 1 : r.every, r.days.isEmpty ? sd : r.days);
    default:
      return null;
  }
}

DateTime? _until(Task t) => t.repeat.until.isEmpty ? null : parseLocal(t.repeat.until, '23:59');

/// First occurrence at or after [after].
DateTime? nextOcc(Task t, DateTime after) {
  final s = startOf(t);
  final r = _rule(t);
  if (r == null) return s.isBefore(after) ? null : s;
  final base = after.isAfter(s) ? after : s;
  DateTime? c;
  if (r.unit == 'day') {
    var k = dayDiff(s, base) ~/ r.every;
    if (k < 0) k = 0;
    for (var i = 0; i < 4; i++, k++) {
      final x = DateTime(s.year, s.month, s.day + k * r.every, s.hour, s.minute);
      if (!x.isBefore(after)) {
        c = x;
        break;
      }
    }
  } else if (r.unit == 'week') {
    final ws = DateTime(s.year, s.month, s.day - jsDow(s));
    final b = dayStart(base);
    for (var i = 0; i < 7 * r.every + 8; i++) {
      final d = DateTime(b.year, b.month, b.day + i, s.hour, s.minute);
      final wk = (dayDiff(ws, d) / 7).floor();
      if (wk % r.every == 0 && r.days.contains(jsDow(d)) && !d.isBefore(after) && !d.isBefore(s)) {
        c = d;
        break;
      }
    }
  } else {
    var k = ((base.year - s.year) * 12 + base.month - s.month) ~/ r.every - 1;
    if (k < 0) k = 0;
    for (var i = 0; i < 5; i++, k++) {
      final x = monthAdd(s, k * r.every);
      if (!x.isBefore(after) && !x.isBefore(s)) {
        c = x;
        break;
      }
    }
  }
  final u = _until(t);
  if (c != null && u != null && c.isAfter(u)) return null;
  return c;
}

/// The occurrence the user currently has to deal with.
DateTime? pendingOcc(Task t, [DateTime? now]) {
  now ??= DateTime.now();
  if (!isRec(t)) return t.completed ? null : startOf(t);
  var o = nextOcc(t, DateTime.fromMillisecondsSinceEpoch(t.cursor));
  if (o == null) return null;
  for (var g = 0; g < 3000; g++) {
    final n = nextOcc(t, o!.add(const Duration(minutes: 1)));
    if (n != null && !n.isAfter(now)) {
      o = n;
    } else {
      break;
    }
  }
  return o;
}

List<DateTime> occurrencesInRange(Task t, DateTime from, DateTime to) {
  final out = <DateTime>[];
  if (!isRec(t)) {
    final s = startOf(t);
    if (!s.isBefore(from) && s.isBefore(to)) out.add(s);
    return out;
  }
  var o = nextOcc(t, from);
  while (o != null && o.isBefore(to) && out.length < 62) {
    out.add(o);
    o = nextOcc(t, o.add(const Duration(minutes: 1)));
  }
  return out;
}

const wdShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const wdLong = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const monShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const monLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];

String repeatLabel(Task t) {
  if (!isRec(t)) return '';
  final r = t.repeat;
  final ds = (r.days.isEmpty ? [jsDow(startOf(t))] : ([...r.days]..sort())).map((d) => wdShort[d]).join(', ');
  switch (r.type) {
    case 'daily':
      return 'Daily';
    case 'weekly':
      final wk = r.days.length == 5 && !r.days.contains(0) && !r.days.contains(6);
      return wk ? 'Weekdays' : 'Weekly · $ds';
    case 'monthly':
      return 'Monthly';
  }
  final n = r.every < 1 ? 1 : r.every;
  final u = r.unit.isEmpty ? 'day' : r.unit;
  return 'Every ${n > 1 ? '$n ' : ''}$u${n > 1 ? 's' : ''}${u == 'week' ? ' · $ds' : ''}';
}

bool isOverdue(Task t, [DateTime? now]) {
  now ??= DateTime.now();
  if (t.completed) return false;
  final o = pendingOcc(t, now);
  return o != null && o.isBefore(now.subtract(const Duration(minutes: 1)));
}

// ---------------- formatting ----------------
String fmtTime(DateTime d, bool h24) {
  if (h24) return hm(d);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${pad2(d.minute)} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDay(DateTime d, [DateTime? now]) {
  final t = dayStart(now ?? DateTime.now());
  final diff = dayDiff(t, d);
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  final y = d.year != t.year ? ' ${d.year}' : '';
  return '${wdShort[jsDow(d)]}, ${d.day} ${monShort[d.month - 1]}$y';
}

String fmtLongDate(DateTime d) => '${wdLong[jsDow(d)]}, ${d.day} ${monLong[d.month - 1]} ${d.year}';

String fmtDur(Duration dd) {
  final m = (dd.inSeconds / 60).round();
  if (m < 1) return 'now';
  if (m < 60) return 'in $m min';
  final h = m ~/ 60, r = m % 60;
  if (h < 24) return 'in ${h}h${r > 0 ? ' ${r}m' : ''}';
  final d = h ~/ 24;
  return 'in $d day${d > 1 ? 's' : ''}';
}

// ---------------- dashboard helpers ----------------
class Item {
  final Task t;
  final DateTime o;
  final HistoryEntry? h;
  final int at;
  Item(this.t, this.o, {this.h, this.at = 0});
}

class Buckets {
  final List<Item> today, upcoming, overdue, completed;
  Buckets(this.today, this.upcoming, this.overdue, this.completed);
  List<Item> of(String k) =>
      k == 'today' ? today : k == 'upcoming' ? upcoming : k == 'overdue' ? overdue : completed;
}

Buckets buckets(AppState s, [DateTime? now]) {
  now ??= DateTime.now();
  final today = <Item>[], up = <Item>[], od = <Item>[];
  final lim = now.subtract(const Duration(minutes: 1));
  for (final t in s.tasks) {
    if (t.completed) continue;
    final o = pendingOcc(t, now);
    if (o == null) continue;
    if (o.isBefore(lim)) {
      od.add(Item(t, o));
    } else if (sameDay(o, now)) {
      today.add(Item(t, o));
    } else {
      up.add(Item(t, o));
    }
  }
  int byO(Item a, Item b) => a.o.compareTo(b.o);
  today.sort(byO);
  up.sort(byO);
  od.sort(byO);
  final done = <Item>[
    ...s.tasks.where((t) => t.completed).map((t) => Item(t, startOf(t), at: t.completedAt)),
    ...s.history.map((h) {
      final t = s.task(h.taskId) ??
          Task(id: '', title: h.title, category: h.category, date: ymd(DateTime.now()), time: '00:00');
      return Item(t, DateTime.fromMillisecondsSinceEpoch(h.occ), h: h, at: h.at);
    }),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return Buckets(today, up, od, done);
}

class UpAlert {
  final Task t;
  final DateTime occ;
  final int at;
  final int off;
  final bool snooze;
  UpAlert(this.t, this.occ, this.at, {this.off = 0, this.snooze = false});
}

List<UpAlert> upcomingAlerts(AppState s, int limit, [DateTime? now]) {
  now ??= DateTime.now();
  final out = <UpAlert>[];
  final nowMs = now.millisecondsSinceEpoch;
  for (final t in s.tasks) {
    if (t.completed) continue;
    var o = pendingOcc(t, now);
    if (o == null) continue;
    if (!o.isAfter(now) && isRec(t)) {
      final n = nextOcc(t, o.add(const Duration(minutes: 1)));
      if (n == null) continue;
      o = n;
    }
    for (final off in [0, ...t.advance]) {
      final at = o.millisecondsSinceEpoch - off * 60000;
      if (at > nowMs) out.add(UpAlert(t, o, at, off: off));
    }
  }
  for (final z in s.snoozes) {
    final t = s.task(z.taskId);
    if (t != null && z.at > nowMs) {
      out.add(UpAlert(t, DateTime.fromMillisecondsSinceEpoch(z.occ), z.at, snooze: true));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out.length > limit ? out.sublist(0, limit) : out;
}

String guessCategory(String s) {
  s = s.toLowerCase();
  bool has(String p) => RegExp(p).hasMatch(s);
  if (has(r'meeting|office|client|report|email|presentation|work|boss|deadline')) return 'Work';
  if (has(r'medicine|medication|pill|tablet|doctor|walk|exercise|gym|water|yoga|health|\brun\b|dentist|namaz|prayer'))
    return 'Health';
  if (has(r'mom|mother|dad|father|wife|husband|son|daughter|family|ammi|abbu|brother|sister|grand')) return 'Family';
  if (has(r'buy|shop|grocer|market|pick up|bazaar')) return 'Shopping';
  if (has(r'pay|bill|bank|rent|salary|tax|fee|pension')) return 'Finance';
  if (has(r'study|class|exam|homework|read|lesson|course')) return 'Study';
  return 'Personal';
}
