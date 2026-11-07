// Understands sentences like "Remind me to call Ahmed tomorrow at 3 PM".
import 'core.dart';

class ParseResult {
  String title = '';
  String date = '';
  String time = '';
  RepeatRule repeat = RepeatRule();
  bool assumedDate = false;
  bool assumedTime = false;
}

const Map<String, int> _wdMap = {
  'sun': 0, 'sunday': 0, 'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2,
  'wed': 3, 'wednesday': 3, 'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
  'fri': 5, 'friday': 5, 'sat': 6, 'saturday': 6,
};
const String _wdAlt = 'sunday|monday|tuesday|wednesday|thursday|friday|saturday|sun|mon|tues|tue|wed|thurs|thur|thu|fri|sat';
const Map<String, int> _monMap = {
  'jan': 0, 'january': 0, 'feb': 1, 'february': 1, 'mar': 2, 'march': 2, 'apr': 3, 'april': 3,
  'may': 4, 'jun': 5, 'june': 5, 'jul': 6, 'july': 6, 'aug': 7, 'august': 7, 'sep': 8, 'sept': 8,
  'september': 8, 'oct': 9, 'october': 9, 'nov': 10, 'november': 10, 'dec': 11, 'december': 11,
};
const String _monAlt =
    'january|february|march|april|may|june|july|august|september|october|november|december|jan|feb|mar|apr|jun|jul|aug|sept|sep|oct|nov|dec';
const Map<String, double> _numW = {
  'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4, 'five': 5, 'six': 6, 'seven': 7,
  'eight': 8, 'nine': 9, 'ten': 10, 'fifteen': 15, 'twenty': 20, 'thirty': 30, 'forty-five': 45,
};

int? _wd(String w) {
  w = w.toLowerCase().trim();
  return _wdMap[w] ?? (w.endsWith('s') ? _wdMap[w.substring(0, w.length - 1)] : null);
}

ParseResult parseNL(String input, [DateTime? nowArg]) {
  final now = nowArg ?? DateTime.now();
  var s = ' ${input.trim().replaceAll(RegExp(r'[.!?۔]+$'), '')} ';
  final r = ParseResult();
  String? hint; // am | pm
  String? dpTime;

  /// Finds [pattern]; if [fn] doesn't return false, removes the match (or replaces it with
  /// the String [fn] returned).
  bool cut(String pattern, Object? Function(RegExpMatch m) fn) {
    final m = RegExp(pattern, caseSensitive: false).firstMatch(s);
    if (m == null) return false;
    final keep = fn(m);
    if (keep == false) return false;
    s = '${s.substring(0, m.start)} ${keep is String ? keep : ''} ${s.substring(m.end)}';
    return true;
  }

  s = s.replaceFirst(
      RegExp(
          r"^\s*(please\s+)?(remind me (to|about|that)|remind me|set (a )?reminder (to|for)|reminder (to|for)|don'?t (let me )?forget to|i need to|i have to|i must|i want to)\s+",
          caseSensitive: false),
      ' ');

  // relative: in 20 minutes / in 2 hours / in 3 days
  cut(r'\bin\s+(\d+(?:\.\d+)?|' + _numW.keys.join('|') + r')\s*(minutes?|mins?|hours?|hrs?|days?|weeks?)\b', (m) {
    final w = m.group(1)!.toLowerCase();
    final n = double.tryParse(w) ?? _numW[w] ?? 1;
    final u = m.group(2)!.toLowerCase();
    if (u.startsWith('m')) {
      final d = now.add(Duration(seconds: (n * 60).round()));
      r.date = ymd(d);
      r.time = hm(d);
    } else if (u.startsWith('h')) {
      final d = now.add(Duration(minutes: (n * 60).round()));
      r.date = ymd(d);
      r.time = hm(d);
    } else if (u.startsWith('d')) {
      r.date = ymd(addDays(now, n.round()));
    } else {
      r.date = ymd(addDays(now, (n * 7).round()));
    }
    return null;
  });
  cut(r'\bin\s+half\s+an?\s+hour\b', (m) {
    final d = now.add(const Duration(minutes: 30));
    r.date = ymd(d);
    r.time = hm(d);
    return null;
  });

  // recurrence
  cut(r'\b(every\s*week\s*days?|every\s+weekday|on\s+weekdays|weekdays)\b', (m) {
    r.repeat = RepeatRule(type: 'weekly', days: [1, 2, 3, 4, 5]);
    return null;
  });
  cut(r'\b(?:every|each|on)\s+((?:' + _wdAlt + r')s?(?:\s*(?:,|and|&)\s*(?:' + _wdAlt + r')s?)*)\b', (m) {
    final g = m.group(1)!;
    // "on monday" is a date (handled below); "on mondays" means every Monday
    if (m.group(0)!.toLowerCase().trim().startsWith('on') && !RegExp(r's\b', caseSensitive: false).hasMatch(g)) {
      return false;
    }
    final days = <int>{};
    for (final w in g.toLowerCase().split(RegExp(r'\s*(?:,|and|&)\s*'))) {
      final d = _wd(w);
      if (d != null) days.add(d);
    }
    if (days.isEmpty) return false;
    r.repeat = RepeatRule(type: 'weekly', days: days.toList());
    return null;
  });
  cut(r'\bevery\s+(\d+)\s+(days?|weeks?|months?)\b', (m) {
    var u = m.group(2)!.toLowerCase();
    if (u.endsWith('s')) u = u.substring(0, u.length - 1);
    r.repeat = RepeatRule(type: 'custom', every: int.parse(m.group(1)!), unit: u);
    return null;
  });
  cut(r'\b(?:every|each)\s+(morning|afternoon|evening|night)\b', (m) {
    r.repeat = RepeatRule(type: 'daily');
    return 'in the ${m.group(1)}';
  });
  cut(r'\b(every\s*day|everyday|each day|daily|har roz)\b', (m) {
    r.repeat = RepeatRule(type: 'daily');
    return null;
  });
  cut(r'\b(every\s+week|each week|weekly)\b', (m) {
    r.repeat = RepeatRule(type: 'weekly');
    return null;
  });
  cut(r'\b(every\s+month|each month|monthly)\b', (m) {
    r.repeat = RepeatRule(type: 'monthly');
    return null;
  });

  // day parts — only when clearly about time, so "evening walk" stays in the title
  const dp = {
    'morning': ['09:00', 'am'],
    'afternoon': ['14:00', 'pm'],
    'evening': ['18:00', 'pm'],
    'night': ['21:00', 'pm'],
  };
  cut(r'\b(in the|this|tomorrow|today|at)\s+(morning|afternoon|evening|night)\b', (m) {
    final p = dp[m.group(2)!.toLowerCase()]!;
    hint = p[1];
    dpTime = p[0];
    final w = m.group(1)!.toLowerCase();
    return (w == 'tomorrow' || w == 'today') ? w : '';
  });
  cut(r'\btonight\b', (m) {
    hint = 'pm';
    dpTime = '20:00';
    if (r.date.isEmpty) r.date = ymd(now);
    return null;
  });

  // explicit times
  Object? setT(String hs, String? ms, String? ap) {
    var h = int.parse(hs);
    final mi = int.tryParse(ms ?? '0') ?? 0;
    final a = ap?.toLowerCase().replaceAll('.', '');
    if (h > 23 || mi > 59) return false;
    if (a == 'pm' && h < 12) {
      h += 12;
    } else if (a == 'am' && h == 12) {
      h = 0;
    } else if (a == null && h <= 12) {
      if (hint == 'pm' && h < 12) {
        h += 12;
      } else if (hint == null && h >= 1 && h < 7) {
        h += 12;
      }
    }
    r.time = '${pad2(h)}:${pad2(mi)}';
    return null;
  }

  final monLook = r'(?!\s*(?:' + _monAlt + r'|st\b|nd\b|rd\b|th\b|minutes?|mins?|hours?|days?|weeks?|months?))';
  final _ = cut(r'\b(?:at\s+|by\s+|@\s*)?(\d{1,2})[:.](\d{2})\s*(a\.?m\.?|p\.?m\.?)?(?![\w])', (m) => setT(m.group(1)!, m.group(2), m.group(3))) ||
      cut(r'\b(?:at\s+|by\s+|@\s*)?(\d{1,2})\s*(a\.?m\.?|p\.?m\.?)(?![\w])', (m) => setT(m.group(1)!, '0', m.group(2))) ||
      cut(r'\b(?:at|by|@)\s*(\d{1,2})(?:\s*o' "'" r'?clock)?\b' + monLook, (m) => setT(m.group(1)!, '0', null)) ||
      cut(r'\b(?:at\s+)?(noon|midday)\b', (m) {
        r.time = '12:00';
        return null;
      }) ||
      cut(r'\b(?:at\s+)?midnight\b', (m) {
        r.time = '23:59';
        return null;
      });
  if (r.time.isEmpty && dpTime != null) r.time = dpTime!;

  // dates
  cut(r'\b(?:the\s+)?day after tomorrow\b', (m) {
    r.date = ymd(addDays(now, 2));
    return null;
  });
  cut(r'\b(tomorrow|tmrw|tmr)\b', (m) {
    r.date = ymd(addDays(now, 1));
    return null;
  });
  cut(r'\btoday\b', (m) {
    r.date = ymd(now);
    return null;
  });
  cut(r'\bnext\s+week\b', (m) {
    r.date = ymd(addDays(now, 7));
    return null;
  });
  cut(r'\bnext\s+month\b', (m) {
    r.date = ymd(monthAdd(dayStart(now), 1));
    return null;
  });
  cut(r'\b(?:on\s+)?(?:(next|this|coming)\s+)?(' + _wdAlt + r')\b', (m) {
    final wd = _wd(m.group(2)!)!;
    var diff = (wd - jsDow(now) + 7) % 7;
    if (diff == 0) {
      final tt = r.time.isNotEmpty ? parseLocal(ymd(now), r.time) : null;
      if (m.group(1) != null || tt == null || !tt.isAfter(now)) diff = 7;
    }
    if (r.repeat.type == 'weekly' && r.repeat.days.isEmpty) r.repeat.days = [wd];
    r.date = ymd(addDays(dayStart(now), diff));
    return null;
  });
  String mkDate(String d, int mo, String? y) {
    var x = DateTime(y != null ? int.parse(y) : now.year, mo + 1, int.parse(d));
    if (y == null && x.isBefore(dayStart(now))) x = DateTime(now.year + 1, mo + 1, int.parse(d));
    return ymd(x);
  }

  final __ = cut(
          r'\b(?:on\s+)?(?:the\s+)?(\d{1,2})(?:st|nd|rd|th)?\s+(?:of\s+)?(' + _monAlt + r')\b\.?(?:,?\s*(\d{4}))?', (m) {
        r.date = mkDate(m.group(1)!, _monMap[m.group(2)!.toLowerCase()]!, m.group(3));
        return null;
      }) ||
      cut(r'\b(?:on\s+)?(' + _monAlt + r')\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s*(\d{4}))?', (m) {
        r.date = mkDate(m.group(2)!, _monMap[m.group(1)!.toLowerCase()]!, m.group(3));
        return null;
      }) ||
      cut(r'\bon\s+the\s+(\d{1,2})(?:st|nd|rd|th)\b', (m) {
        final d = int.parse(m.group(1)!);
        var x = DateTime(now.year, now.month, d);
        if (x.isBefore(dayStart(now))) x = DateTime(now.year, now.month + 1, d);
        r.date = ymd(x);
        return null;
      });

  // title
  var t = s.replaceAll(RegExp(r'\s+'), ' ').replaceAllMapped(RegExp(r'\s+([,;])'), (m) => m.group(1)!).trim();
  for (var i = 0; i < 4; i++) {
    t = t
        .replaceFirst(RegExp(r'^(to|about|that|and|,)\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'[\s,;]+(on|at|by|for|in|the|this|next|of|and|from)$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'[,;\s]+$'), '')
        .trim();
  }
  r.title = t.isEmpty ? '' : t[0].toUpperCase() + t.substring(1);

  // defaults
  if (r.time.isEmpty) {
    r.assumedTime = true;
    if (r.date.isNotEmpty && r.date != ymd(now)) {
      r.time = '09:00';
    } else {
      var d = now.add(const Duration(hours: 1));
      final mins = ((d.minute + 14) ~/ 15) * 15;
      d = DateTime(d.year, d.month, d.day, d.hour, mins);
      r.time = hm(d);
      if (r.date.isEmpty) r.date = ymd(d);
    }
  }
  if (r.date.isEmpty) {
    r.assumedDate = true;
    r.date = parseLocal(ymd(now), r.time).isAfter(now) ? ymd(now) : ymd(addDays(now, 1));
  }
  if (r.repeat.type == 'weekly' && r.repeat.days.isNotEmpty) {
    for (var i = 0; i < 8; i++) {
      final d = addDays(dayStart(now), i);
      final c = parseLocal(ymd(d), r.time);
      if (r.repeat.days.contains(jsDow(d)) && c.isAfter(now)) {
        if (r.assumedDate || ymd(d).compareTo(r.date) > 0) r.date = ymd(d);
        r.assumedDate = false;
        break;
      }
    }
  }
  return r;
}
