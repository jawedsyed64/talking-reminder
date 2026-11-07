import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import '../native.dart';
import '../nl_parser.dart';
import 'editor.dart';
import 'widgets.dart';

/// Speaks the reminder for [t] exactly as it will sound when due.
Future<void> previewTask(Task t, {DateTime? occ}) async {
  final o = occ ?? pendingOcc(t) ?? startOf(t);
  final msg = await Native.buildMessage(jsonEncode(t.toJson()), o.millisecondsSinceEpoch, 'due', 0, ctl.settingsJson);
  if (msg.isEmpty) return;
  final ok = await Native.speak(msg, ctl.settingsJson, sound: true);
  toast(ok ? '🔊 $msg' : 'Voice is still starting up — try again in a moment.');
}

Future<void> openEditor(BuildContext context, {Task? task, Task? preset}) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TaskEditor(task: task, preset: preset)));
}

Future<void> listenAndParse(BuildContext context, {TextEditingController? into}) async {
  try {
    final lang = ctl.s.settings.lang.isNotEmpty
        ? ctl.s.settings.lang
        : (ctl.s.settings.voiceLang.isNotEmpty ? ctl.s.settings.voiceLang : '');
    final text = await Native.listen(lang);
    if (text == null || text.trim().isEmpty) return;
    into?.text = text;
    if (context.mounted) openNLConfirm(context, text.trim(), onCreated: () => into?.clear());
  } catch (e) {
    toast('$e'.replaceFirst('Exception: ', ''));
  }
}

void openNLConfirm(BuildContext context, String text, {VoidCallback? onCreated}) {
  final p = parseNL(text);
  if (p.title.isEmpty) {
    toast('I couldn\'t find the task. Try: "Remind me to call Ahmed tomorrow at 3 PM"');
    return;
  }
  final when = parseLocal(p.date, p.time);
  final task = Task(
    id: '',
    title: p.title,
    date: p.date,
    time: p.time,
    repeat: p.repeat,
    category: guessCategory(p.title),
  );
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final muted = mutedColor(c);
      Widget row(String k, String v, [bool assumed = false]) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 80, child: Text(k, style: TextStyle(color: muted, fontWeight: FontWeight.w700))),
              Expanded(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              if (assumed) const Badge2('assumed', kWarn),
            ]),
          );
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(c).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Create this reminder?', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('"$text"', style: TextStyle(color: muted)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: softPrimary(c), borderRadius: BorderRadius.circular(16)),
            child: Column(children: [
              row('Task', p.title),
              row('Date', fmtDay(when), p.assumedDate),
              row('Time', ctl.fmtT(when), p.assumedTime),
              row('Repeat', isRec(task) ? repeatLabel(task) : 'No'),
            ]),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () {
                  Navigator.pop(c);
                  openEditor(context, preset: task);
                },
                child: const Text('Edit details', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: () async {
                  Navigator.pop(c);
                  await ctl.saveTask(task, isNew: true);
                  onCreated?.call();
                  final saved = ctl.s.tasks.isNotEmpty ? ctl.s.tasks.last : task;
                  final o = pendingOcc(saved) ?? when;
                  toast('Done — I\'ll remind you ${fmtDay(o).toLowerCase()} at ${ctl.fmtT(o)}');
                },
                icon: const Icon(Icons.check),
                label: const Text('Create reminder', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ]),
        ]),
      );
    },
  );
}

void openTaskMenu(BuildContext context, Task t) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (c) {
      Widget item(IconData i, String label, VoidCallback fn, {Color? color}) => ListTile(
            leading: Icon(i, color: color),
            title: Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
            onTap: () {
              Navigator.pop(c);
              fn();
            },
          );
      final rec = isRec(t);
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(t.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          item(Icons.volume_up, 'Hear the reminder now', () => previewTask(t)),
          item(Icons.edit, 'Edit task', () => openEditor(context, task: t)),
          if (!t.completed) ...[
            item(Icons.check_circle_outline, 'Mark as completed', () async => toast(await ctl.complete(t))),
            item(Icons.snooze, rec ? 'Remind me again in 1 hour' : 'Postpone by 1 hour',
                () async => toast(await ctl.postpone(t, minutes: 60))),
            item(Icons.event, rec ? 'Remind me again tomorrow' : 'Move to tomorrow',
                () async => toast(await ctl.postpone(t, tomorrow: true))),
          ],
          item(Icons.delete_outline, 'Delete task', () async {
            if (await confirm(context, 'Delete "${t.title}"?', ok: 'Delete', danger: true)) {
              await ctl.delete(t);
              toast('Task deleted');
            }
          }, color: kBad),
          const SizedBox(height: 8),
        ]),
      );
    },
  );
}

bool _missedOpen = false;

void showMissedSheet(BuildContext context) {
  if (_missedOpen || ctl.s.missed.isEmpty) return;
  _missedOpen = true;
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) => ListenableBuilder(
      listenable: ctl,
      builder: (c, _) {
        final items = ctl.s.missed
            .map((m) => (m: m, t: ctl.s.task('${m['taskId'] ?? ''}')))
            .where((x) => x.t != null && !x.t!.completed)
            .toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('⏰ Missed reminders', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            Text('These came due while the phone was off or the reminder couldn\'t play.',
                style: TextStyle(color: mutedColor(c))),
            const SizedBox(height: 12),
            if (items.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('All handled 👍')),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final x in items)
                  Card(
                    child: ListTile(
                      title: Text(x.t!.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(() {
                        final d = DateTime.fromMillisecondsSinceEpoch((x.m['occ'] as num?)?.toInt() ?? 0);
                        return '${fmtDay(d)} · ${ctl.fmtT(d)}';
                      }()),
                      trailing: Wrap(children: [
                        IconButton(
                          tooltip: 'Done',
                          icon: const Icon(Icons.check_circle, color: kOk),
                          onPressed: () async {
                            final occ = (x.m['occ'] as num?)?.toInt();
                            toast(await ctl.complete(x.t!, occ));
                            await ctl.mutate((st) => st.missed.removeWhere((m) => '${m['taskId']}' == x.t!.id && m['occ'] == x.m['occ']));
                          },
                        ),
                        IconButton(
                          tooltip: 'Reschedule',
                          icon: const Icon(Icons.edit_calendar),
                          onPressed: () {
                            Navigator.pop(c);
                            openEditor(context, task: x.t);
                          },
                        ),
                      ]),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            BigButton('Close', icon: Icons.close, bg: softPrimary(c), fg: Theme.of(c).colorScheme.primary, onPressed: () => Navigator.pop(c)),
          ]),
        );
      },
    ),
  ).whenComplete(() {
    _missedOpen = false;
    ctl.clearMissed();
  });
}
