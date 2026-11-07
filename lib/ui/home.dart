import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import 'sheets.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  final void Function(int tab) goTo;
  const HomePage({super.key, required this.goTo});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String tab = 'today';
  final quick = TextEditingController();

  @override
  void dispose() {
    quick.dispose();
    super.dispose();
  }

  String _greeting(DateTime d) {
    final h = d.hour;
    return h < 5 ? 'Good night' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctl,
      builder: (context, _) {
        final now = DateTime.now();
        final b = buckets(ctl.s, now);
        final pending = ctl.s.tasks.where((t) => !t.completed).length;
        final ups = upcomingAlerts(ctl.s, 4, now);
        final list = b.of(tab);
        final problems = ctl.setupProblems;
        const empties = {
          'today': ['☀️', 'Nothing else for today. Enjoy!'],
          'upcoming': ['🗓️', 'No upcoming tasks yet.'],
          'overdue': ['🎉', 'No overdue tasks — great job!'],
          'completed': ['✅', 'Completed tasks will appear here.'],
        };
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _header(context, now, ups.isEmpty ? null : ups.first)),
          SliverToBoxAdapter(
            child: Transform.translate(
              offset: const Offset(0, -34),
              child: Column(children: [
                _quickAdd(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
                  child: Text('Type or speak naturally — e.g. "Take medicine every day at 8 am", "Pay bill next Friday".',
                      style: TextStyle(color: mutedColor(context), fontSize: 13)),
                ),
                if (problems.isNotEmpty) _setupWarning(context, problems.length),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Row(children: [
                    _stat(context, '${ctl.s.tasks.length}', 'Total', Theme.of(context).colorScheme.primary, 'upcoming'),
                    _stat(context, '$pending', 'Pending', kWarn, 'today'),
                    _stat(context, '${b.completed.length}', 'Done', kOk, 'completed'),
                    _stat(context, '${b.overdue.length}', 'Overdue', kBad, 'overdue'),
                  ]),
                ),
                SectionTitle('Upcoming reminders',
                    trailing: TextButton(onPressed: () => widget.goTo(2), child: const Text('See all'))),
                Panel(
                  child: ups.isEmpty
                      ? const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No reminders coming up.')))
                      : Column(children: [
                          for (final u in ups) _upRow(context, u),
                        ]),
                ),
                const SectionTitle('My tasks'),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    for (final k in const ['today', 'upcoming', 'overdue', 'completed'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${k[0].toUpperCase()}${k.substring(1)}  ${b.of(k).length}',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                          selected: tab == k,
                          onSelected: (_) => setState(() => tab = k),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: list.isEmpty
                      ? Padding(
                          padding: EdgeInsets.zero,
                          child: EmptyNote(empties[tab]![0], empties[tab]![1]),
                        )
                      : Column(children: [
                          for (final it in list.take(80))
                            TaskCard(
                              item: it,
                              done: tab == 'completed',
                              onCheck: () async {
                                if (tab == 'completed') {
                                  if (it.h == null && it.t.id.isNotEmpty) {
                                    await ctl.restore(it.t);
                                    toast('Task restored');
                                  }
                                } else {
                                  toast(await ctl.complete(it.t));
                                }
                              },
                              onTap: it.t.id.isEmpty ? null : () => openEditor(context, task: it.t),
                              onMore: it.t.id.isEmpty ? null : () => openTaskMenu(context, it.t),
                            ),
                        ]),
                ),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _header(BuildContext context, DateTime now, UpAlert? next) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 16, 20, 60),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [kPrimary, kPrimary2]),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_greeting(now)} 👋', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Colors.white70)),
                Text(fmtLongDate(now), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ]),
            ),
          ]),
          const SizedBox(height: 6),
          const _Clock(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: next == null
                    ? const Text('No reminders scheduled. Tap Add Task to create one.', style: TextStyle(color: Colors.white))
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(next.t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: Colors.white)),
                        Text(
                            '${next.snooze ? 'Snoozed · ' : next.off > 0 ? '${next.off} min early · ' : ''}${fmtDay(DateTime.fromMillisecondsSinceEpoch(next.at))} at ${ctl.fmtT(DateTime.fromMillisecondsSinceEpoch(next.at))}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13.5)),
                      ]),
              ),
              if (next != null) _Countdown(at: next.at),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _quickAdd(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Panel(
      padding: const EdgeInsets.all(8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: quick,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: 'Remind me to call Ahmed tomorrow at 3 PM',
              filled: false,
              border: InputBorder.none,
            ),
            onSubmitted: (v) {
              if (v.trim().isNotEmpty) openNLConfirm(context, v.trim(), onCreated: quick.clear);
            },
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Speak your task',
          onPressed: () => listenAndParse(context, into: quick),
          icon: const Icon(Icons.mic),
          iconSize: 26,
        ),
        const SizedBox(width: 4),
        IconButton.filled(
          tooltip: 'Create',
          style: IconButton.styleFrom(backgroundColor: primary),
          onPressed: () {
            final v = quick.text.trim();
            if (v.isNotEmpty) openNLConfirm(context, v, onCreated: quick.clear);
          },
          icon: const Icon(Icons.arrow_forward),
          iconSize: 26,
        ),
      ]),
    );
  }

  Widget _setupWarning(BuildContext context, int n) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Material(
          color: kWarn.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => widget.goTo(3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const Text('⚠️', style: TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                      'Reminders may not ring on time. $n phone setting${n > 1 ? 's need' : ' needs'} your OK — tap to fix.',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        ),
      );

  Widget _stat(BuildContext context, String n, String label, Color c, String target) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Material(
            color: cardColor(context),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => setState(() => tab = target),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: tab == target && label != 'Total' ? c : Colors.transparent, width: 2),
                ),
                child: Column(children: [
                  Text(n, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c)),
                  Text(label, style: TextStyle(fontSize: 12.5, color: mutedColor(context), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ),
      );

  Widget _upRow(BuildContext context, UpAlert u) {
    final at = DateTime.fromMillisecondsSinceEpoch(u.at);
    return InkWell(
      onTap: () => openEditor(context, task: u.t),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          SizedBox(
            width: 82,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ctl.fmtT(at), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              Text(fmtDay(at), style: TextStyle(color: mutedColor(context), fontSize: 12)),
            ]),
          ),
          Expanded(
            child: Text('${catOf(u.t.category).emoji} ${u.t.title}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          const SizedBox(width: 6),
          u.snooze
              ? const Badge2('Snoozed', kWarn)
              : u.off > 0
                  ? Badge2('${u.off} min before', Theme.of(context).colorScheme.primary)
                  : const Badge2('On time', kOk),
        ]),
      ),
    );
  }
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = DateTime.now();
    final h24 = ctl.h24;
    final h = h24 ? pad2(n.hour) : '${n.hour % 12 == 0 ? 12 : n.hour % 12}';
    return Text.rich(TextSpan(children: [
      TextSpan(text: '$h:${pad2(n.minute)}', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -1.5)),
      TextSpan(text: ':${pad2(n.second)}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Colors.white54)),
      if (!h24) TextSpan(text: n.hour < 12 ? '  AM' : '  PM', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ]), style: const TextStyle(color: Colors.white, fontFeatures: [FontFeature.tabularFigures()]));
  }
}

class _Countdown extends StatefulWidget {
  final int at;
  const _Countdown({required this.at});
  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? t;
  @override
  void initState() {
    super.initState();
    t = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
      if (DateTime.now().millisecondsSinceEpoch > widget.at) ctl.reload();
    });
  }

  @override
  void dispose() {
    t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        fmtDur(DateTime.fromMillisecondsSinceEpoch(widget.at).difference(DateTime.now())),
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
      );
}
