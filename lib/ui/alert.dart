import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import '../native.dart';
import 'widgets.dart';

final Set<String> _openAlerts = {};

/// Opens the full-screen reminder (from a notification tap, or when a reminder fires while the app is open).
void showAlertJson(String json) {
  Map<String, dynamic> a;
  try {
    a = Map<String, dynamic>.from(jsonDecode(json) as Map);
  } catch (_) {
    return;
  }
  final key = '${a['key'] ?? ''}';
  if (_openAlerts.contains(key)) return;
  final nav = navKey.currentState;
  if (nav == null) return;
  _openAlerts.add(key);
  nav
      .push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => AlertScreen(alert: a)))
      .whenComplete(() => _openAlerts.remove(key));
}

class AlertScreen extends StatefulWidget {
  final Map<String, dynamic> alert;
  const AlertScreen({super.key, required this.alert});
  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> with SingleTickerProviderStateMixin {
  late final AnimationController ring =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  Map<String, dynamic> get a => widget.alert;
  String get key => '${a['key'] ?? ''}';
  String get taskId => '${a['taskId'] ?? ''}';
  int get occ => (a['occ'] as num?)?.toInt() ?? 0;
  String get kind => '${a['kind'] ?? 'due'}';
  String get text => '${a['text'] ?? ''}';

  @override
  void dispose() {
    ring.dispose();
    super.dispose();
  }

  Future<void> _act(String act, {int minutes = 0, int at = 0}) async {
    await Native.alertAction(act, taskId: taskId, occ: occ, key: key, minutes: minutes, at: at);
    await ctl.reload();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _later() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: now, firstDate: dayStart(now), lastDate: DateTime(2100), helpText: 'Remind me on');
    if (d == null || !mounted) return;
    final base = DateTime.fromMillisecondsSinceEpoch(occ);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: ctl.h24), child: child ?? const SizedBox()),
    );
    if (t == null) return;
    final when = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (!when.isAfter(DateTime.now())) {
      toast('Please choose a time in the future');
      return;
    }
    await _act('later', at: when.millisecondsSinceEpoch);
    toast('I\'ll remind you ${fmtDay(when).toLowerCase()} at ${ctl.fmtT(when)}');
  }

  @override
  Widget build(BuildContext context) {
    final occD = DateTime.fromMillisecondsSinceEpoch(occ);
    final task = ctl.s.task(taskId);
    final cat = task != null ? catOf(task.category) : null;
    final primary = Theme.of(context).colorScheme.primary;
    final kindLabel = kind == 'advance'
        ? 'COMING UP IN ${a['offset']} MIN'
        : kind == 'snooze'
            ? 'SNOOZED REMINDER'
            : kind == 'test'
                ? 'TEST REMINDER'
                : 'REMINDER · NOW';
    final snoozeDef = ctl.s.settings.snooze;
    return Scaffold(
      backgroundColor: const Color(0xFF2A1F7A),
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(0, -0.6), radius: 1.2, colors: [Color(0xFF5B4BDB), Color(0xFF140C3C)]),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(28)),
                child: Column(children: [
                  AnimatedBuilder(
                    animation: ring,
                    builder: (c, child) {
                      final v = ring.value;
                      final angle = v < 0.5 ? 0.25 * (1 - v * 2) * (v * 20 % 2 < 1 ? 1 : -1) : 0.0;
                      return Transform.rotate(angle: angle, child: child);
                    },
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(color: softPrimary(context), shape: BoxShape.circle),
                      child: Icon(Icons.notifications_active, size: 44, color: primary),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(kindLabel, style: TextStyle(color: primary, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                  const SizedBox(height: 6),
                  Text('${cat != null ? '${cat.emoji} ' : ''}${a['title'] ?? ''}',
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                  Text('${fmtDay(occD)} · ${ctl.fmtT(occD)}${task != null && isRec(task) ? ' · ${repeatLabel(task)}' : ''}',
                      style: TextStyle(color: mutedColor(context), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: softPrimary(context), borderRadius: BorderRadius.circular(16)),
                    child: Text('"$text"', style: const TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
                  ),
                  const SizedBox(height: 12),
                  BigButton('Repeat voice',
                      icon: Icons.volume_up,
                      bg: softPrimary(context),
                      fg: primary,
                      onPressed: () => Native.speak(text, ctl.settingsJson, sound: true)),
                  const SizedBox(height: 10),
                  BigButton(kind == 'test' ? 'OK, it works!' : 'DONE',
                      icon: Icons.check,
                      bg: kOk,
                      fg: Colors.white,
                      onPressed: () => _act(kind == 'test' ? 'dismiss' : 'done')),
                  if (kind != 'test') ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      Icon(Icons.snooze, color: mutedColor(context)),
                      const SizedBox(width: 6),
                      Text('SNOOZE', style: TextStyle(fontWeight: FontWeight.w800, color: mutedColor(context))),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      for (final m in const [5, 10, 15]) ...[
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              side: BorderSide(color: m == snoozeDef ? primary : mutedColor(context).withValues(alpha: 0.4), width: m == snoozeDef ? 2 : 1),
                            ),
                            onPressed: () async {
                              await _act('snooze', minutes: m);
                              toast('Snoozed for $m minutes');
                            },
                            child: Text('$m min', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                          ),
                        ),
                        if (m != 15) const SizedBox(width: 8),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _later,
                        icon: const Icon(Icons.schedule),
                        label: const Text('REMIND LATER', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  BigButton('DISMISS', icon: Icons.close, bg: kBad.withValues(alpha: 0.12), fg: kBad, onPressed: () => _act('dismiss')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
