import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import 'sheets.dart';
import 'widgets.dart';

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final ups = upcomingAlerts(ctl.s, 60);
        final groups = <String, List<UpAlert>>{};
        for (final u in ups) {
          groups.putIfAbsent(ymd(DateTime.fromMillisecondsSinceEpoch(u.at)), () => []).add(u);
        }
        final next = (ctl.status['nextAlarm'] as num?)?.toInt() ?? 0;
        return ListView(padding: EdgeInsets.zero, children: [
          const PageTitle('Reminders', 'Every upcoming spoken reminder, in order.'),
          if (next > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                const Icon(Icons.alarm_on, color: kOk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Phone alarm is set for ${fmtDay(DateTime.fromMillisecondsSinceEpoch(next)).toLowerCase()} at ${ctl.fmtT(DateTime.fromMillisecondsSinceEpoch(next))}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: kOk),
                  ),
                ),
              ]),
            ),
          if (groups.isEmpty)
            const Padding(padding: EdgeInsets.only(top: 8), child: EmptyNote('🔕', 'No upcoming reminders.'))
          else
            for (final g in groups.entries) ...[
              SectionTitle(fmtDay(parseLocal(g.key, '12:00'))),
              Panel(
                child: Column(children: [
                  for (final u in g.value)
                    ListTile(
                      onTap: () => openEditor(context, task: u.t),
                      leading: SizedBox(
                        width: 74,
                        child: Text(ctl.fmtT(DateTime.fromMillisecondsSinceEpoch(u.at)),
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                      title: Text('${catOf(u.t.category).emoji} ${u.t.title}', style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(u.snooze
                          ? 'Snoozed reminder'
                          : u.off > 0
                              ? '${u.off} min before ${ctl.fmtT(u.occ)}'
                              : 'At the scheduled time${isRec(u.t) ? ' · ${repeatLabel(u.t)}' : ''}'),
                      trailing: IconButton(
                        tooltip: 'Hear this reminder',
                        icon: const Icon(Icons.volume_up),
                        onPressed: () => previewTask(u.t, occ: u.occ),
                      ),
                    ),
                ]),
              ),
            ],
          if (ctl.s.snoozes.any((z) => z.taskId.isNotEmpty))
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                onPressed: () => ctl.mutate((st) => st.snoozes.removeWhere((z) => z.taskId.isNotEmpty)),
                child: const Text('Clear all snoozed reminders'),
              ),
            ),
          const SizedBox(height: 110),
        ]);
      },
    );
  }
}
