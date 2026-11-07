import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import 'sheets.dart';
import 'widgets.dart';

class _Ev {
  final Task t;
  final DateTime o;
  final String st; // pending | done | overdue | missed
  _Ev(this.t, this.o, this.st);
}

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  String mode = 'month';
  DateTime cursor = dayStart(DateTime.now());
  DateTime sel = dayStart(DateTime.now());

  Map<String, List<_Ev>> _items(DateTime from, DateTime to) {
    final map = <String, List<_Ev>>{};
    final now = DateTime.now();
    for (final t in ctl.s.tasks) {
      final pend = t.completed ? null : pendingOcc(t, now);
      for (final o in occurrencesInRange(t, from, to)) {
        var st = 'pending';
        final om = o.millisecondsSinceEpoch;
        if (t.completed) {
          st = 'done';
        } else if (isRec(t) && ctl.s.history.any((h) => h.taskId == t.id && h.occ == om)) {
          st = 'done';
        } else if (isRec(t) && pend != null && o.isBefore(pend)) {
          st = 'missed';
        } else if (o.isBefore(now.subtract(const Duration(minutes: 1)))) {
          st = 'overdue';
        }
        map.putIfAbsent(ymd(o), () => []).add(_Ev(t, o, st));
      }
    }
    for (final l in map.values) {
      l.sort((a, b) => a.o.compareTo(b.o));
    }
    return map;
  }

  Widget _evRow(BuildContext context, _Ev e) {
    final cat = catOf(e.t.category);
    final muted = mutedColor(context);
    return InkWell(
      onTap: () => openEditor(context, task: e.t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(children: [
          Container(width: 4, height: 32, decoration: BoxDecoration(color: priColor(e.t.priority), borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 10),
          SizedBox(width: 76, child: Text(ctl.fmtT(e.o), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          Expanded(
            child: Text('${cat.emoji} ${e.t.title}',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    decoration: e.st == 'done' ? TextDecoration.lineThrough : null,
                    color: e.st == 'done' ? muted : null)),
          ),
          if (e.st == 'done') const Badge2('Done', kOk),
          if (e.st == 'overdue') const Badge2('Overdue', kBad),
          if (e.st == 'missed') const Badge2('Missed', kWarn),
          if (e.st == 'pending' && isRec(e.t)) Icon(Icons.repeat, size: 18, color: muted),
        ]),
      ),
    );
  }

  void _nav(int dir) => setState(() {
        if (mode == 'month') {
          cursor = DateTime(cursor.year, cursor.month + dir, 1);
        } else {
          cursor = addDays(cursor, dir * (mode == 'week' ? 7 : 1));
          sel = cursor;
        }
      });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final today = dayStart(DateTime.now());
        String title;
        Widget body;
        if (mode == 'month') {
          final first = DateTime(cursor.year, cursor.month, 1);
          final startOff = (first.weekday + 6) % 7; // Monday first
          final gStart = addDays(first, -startOff);
          final m = _items(gStart, addDays(gStart, 42));
          title = '${monLong[first.month - 1]} ${first.year}';
          final selItems = m[ymd(sel)] ?? _items(sel, addDays(sel, 1))[ymd(sel)] ?? [];
          final muted = mutedColor(context);
          final primary = Theme.of(context).colorScheme.primary;
          body = Column(children: [
            Panel(
              padding: const EdgeInsets.all(10),
              child: Column(children: [
                Row(children: [
                  for (final d in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                    Expanded(
                        child: Center(
                            child: Text(d, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: muted)))),
                ]),
                const SizedBox(height: 6),
                for (var w = 0; w < 6; w++)
                  Row(children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(child: () {
                        final d = addDays(gStart, w * 7 + i);
                        final it = m[ymd(d)] ?? const <_Ev>[];
                        final isSel = sameDay(d, sel), isToday = sameDay(d, today);
                        final out = d.month != first.month;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => setState(() => sel = d),
                          child: Container(
                            height: 52,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isSel ? primary : isToday ? softPrimary(context) : null,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text('${d.day}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: isSel
                                        ? Colors.white
                                        : isToday
                                            ? primary
                                            : out
                                                ? muted.withValues(alpha: 0.5)
                                                : null,
                                  )),
                              const SizedBox(height: 3),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                for (final e in it.take(3))
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle, color: isSel ? Colors.white : priColor(e.t.priority)),
                                  ),
                              ]),
                            ]),
                          ),
                        );
                      }()),
                  ]),
              ]),
            ),
            SectionTitle('${wdLong[jsDow(sel)]}, ${sel.day} ${monLong[sel.month - 1]}',
                trailing: TextButton.icon(
                    onPressed: () => openEditor(context, preset: Task(id: '', date: ymd(sel), time: '09:00', advance: [10])),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'))),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: selItems.isEmpty
                  ? const Padding(padding: EdgeInsets.all(18), child: Center(child: Text('No tasks on this day.')))
                  : Column(children: [for (final e in selItems) _evRow(context, e)]),
            ),
          ]);
        } else if (mode == 'week') {
          final ws = addDays(dayStart(cursor), -((cursor.weekday + 6) % 7));
          final m = _items(ws, addDays(ws, 7));
          final we = addDays(ws, 6);
          title = '${ws.day} ${monShort[ws.month - 1]} – ${we.day} ${monShort[we.month - 1]}';
          body = Panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: [
              for (var i = 0; i < 7; i++)
                () {
                  final d = addDays(ws, i);
                  final it = m[ymd(d)] ?? const <_Ev>[];
                  final isToday = sameDay(d, today);
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                        border: i < 6 ? Border(bottom: BorderSide(color: mutedColor(context).withValues(alpha: 0.15))) : null),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${wdLong[jsDow(d)]}, ${d.day} ${monShort[d.month - 1]}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w800, color: isToday ? Theme.of(context).colorScheme.primary : null)),
                        ),
                        InkWell(
                          onTap: () => openEditor(context, preset: Task(id: '', date: ymd(d), time: '09:00', advance: [10])),
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add_circle_outline, size: 20)),
                        ),
                      ]),
                      if (it.isEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text('Free', style: TextStyle(color: mutedColor(context))))
                      else
                        for (final e in it) _evRow(context, e),
                    ]),
                  );
                }(),
            ]),
          );
        } else {
          final m = _items(dayStart(cursor), addDays(dayStart(cursor), 1));
          final it = m[ymd(cursor)] ?? const <_Ev>[];
          title = '${wdShort[jsDow(cursor)]}, ${cursor.day} ${monLong[cursor.month - 1]}';
          body = Column(children: [
            it.isEmpty
                ? const EmptyNote('🌤️', 'No tasks scheduled.')
                : Panel(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    child: Column(children: [for (final e in it) _evRow(context, e)])),
            Padding(
              padding: const EdgeInsets.all(16),
              child: BigButton('Add task on this day',
                  icon: Icons.add,
                  bg: softPrimary(context),
                  fg: Theme.of(context).colorScheme.primary,
                  onPressed: () => openEditor(context, preset: Task(id: '', date: ymd(cursor), time: '09:00', advance: [10]))),
            ),
          ]);
        }
        return ListView(padding: EdgeInsets.zero, children: [
          const PageTitle('Calendar', 'Your schedule at a glance.'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('Day')),
                ButtonSegment(value: 'week', label: Text('Week')),
                ButtonSegment(value: 'month', label: Text('Month')),
              ],
              selected: {mode},
              onSelectionChanged: (v) => setState(() {
                mode = v.first;
                cursor = sel;
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
            child: Row(children: [
              IconButton(onPressed: () => _nav(-1), icon: const Icon(Icons.chevron_left, size: 30), tooltip: 'Previous'),
              Expanded(
                  child: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
              TextButton(
                  onPressed: () => setState(() {
                        cursor = dayStart(DateTime.now());
                        sel = cursor;
                      }),
                  child: const Text('Today')),
              IconButton(onPressed: () => _nav(1), icon: const Icon(Icons.chevron_right, size: 30), tooltip: 'Next'),
            ]),
          ),
          body,
          const SizedBox(height: 110),
        ]);
      },
    );
  }
}
