// Checks the pieces that decide WHEN a reminder speaks: sentence understanding and repeat rules.
import 'package:flutter_test/flutter_test.dart';
import 'package:talking_reminder/core.dart';
import 'package:talking_reminder/nl_parser.dart';

void main() {
  // Thursday 5 November 2026, 23:08
  final now = DateTime(2026, 11, 5, 23, 8);

  group('Understands plain sentences', () {
    test('call Ahmed tomorrow at 3 PM', () {
      final r = parseNL('Remind me to call Ahmed tomorrow at 3 PM', now);
      expect(r.title, 'Call Ahmed');
      expect(r.date, '2026-11-06');
      expect(r.time, '15:00');
      expect(r.repeat.type, 'none');
    });
    test('every day at 8:30 am', () {
      final r = parseNL('Take medicine every day at 8:30 am', now);
      expect(r.title, 'Take medicine');
      expect(r.time, '08:30');
      expect(r.repeat.type, 'daily');
    });
    test('specific date', () {
      final r = parseNL('Meeting with Sara on 10 November at 10am', now);
      expect(r.title, 'Meeting with Sara');
      expect(r.date, '2026-11-10');
      expect(r.time, '10:00');
    });
    test('evening walk keeps its title', () {
      final r = parseNL('Take your evening walk every evening', now);
      expect(r.title, 'Take your evening walk');
      expect(r.time, '18:00');
      expect(r.repeat.type, 'daily');
    });
    test('relative minutes', () {
      final r = parseNL('in 30 minutes check the oven', now);
      expect(r.title, 'Check the oven');
      expect(r.date, '2026-11-05');
      expect(r.time, '23:38');
    });
    test('weekly on Sunday', () {
      final r = parseNL('Call mom every sunday at 7 pm', now);
      expect(r.title, 'Call mom');
      expect(r.repeat.type, 'weekly');
      expect(r.repeat.days, [0]);
      expect(r.date, '2026-11-08');
      expect(r.time, '19:00');
    });
    test('on monday is a date, not a repeat', () {
      final r = parseNL('Dentist on monday at 5', now);
      expect(r.title, 'Dentist');
      expect(r.repeat.type, 'none');
      expect(r.date, '2026-11-09');
      expect(r.time, '17:00');
    });
    test('weekdays', () {
      final r = parseNL('Gym on weekdays at 6', now);
      expect(r.title, 'Gym');
      expect(r.repeat.days..sort(), [1, 2, 3, 4, 5]);
      expect(r.time, '18:00');
    });
    test('every 3 days', () {
      final r = parseNL('Water plants every 3 days at 7 pm', now);
      expect(r.repeat.type, 'custom');
      expect(r.repeat.every, 3);
      expect(r.repeat.unit, 'day');
    });
  });

  group('Repeat rules', () {
    test('monthly on the 31st falls back to the last day of short months', () {
      final t = Task(id: 'm', date: '2026-01-31', time: '09:00', repeat: RepeatRule(type: 'monthly'));
      var o = nextOcc(t, DateTime(2026, 2, 1))!;
      expect(ymd(o), '2026-02-28');
      o = nextOcc(t, o.add(const Duration(minutes: 1)))!;
      expect(ymd(o), '2026-03-31');
    });
    test('every 2 weeks on Mon & Thu', () {
      final t = Task(
          id: 'w', date: '2026-11-05', time: '18:00', repeat: RepeatRule(type: 'custom', unit: 'week', every: 2, days: [1, 4]));
      final got = <String>[];
      var o = nextOcc(t, DateTime(2026, 11, 5));
      for (var i = 0; i < 4; i++) {
        got.add(ymd(o!));
        o = nextOcc(t, o.add(const Duration(minutes: 1)));
      }
      expect(got, ['2026-11-05', '2026-11-16', '2026-11-19', '2026-11-30']);
    });
    test('done recurring task moves to the next day', () {
      final t = Task(id: 'd', date: '2026-11-01', time: '18:00', repeat: RepeatRule(type: 'daily'));
      final p = pendingOcc(t, now)!;
      expect(ymd(p), '2026-11-05'); // today's walk was missed
      t.cursor = p.millisecondsSinceEpoch + 60000; // mark done
      expect(ymd(pendingOcc(t, now)!), '2026-11-06');
    });
    test('repeat stops after the end date', () {
      final t = Task(id: 'u', date: '2026-11-01', time: '08:00', repeat: RepeatRule(type: 'daily', until: '2026-11-03'));
      expect(nextOcc(t, DateTime(2026, 11, 4)), isNull);
    });
  });
}
