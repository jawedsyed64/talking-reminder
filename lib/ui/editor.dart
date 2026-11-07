import 'dart:convert';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import '../native.dart';
import 'widgets.dart';

/// Add / edit a task.
class TaskEditor extends StatefulWidget {
  final Task? task; // editing
  final Task? preset; // new task with some fields filled in
  const TaskEditor({super.key, this.task, this.preset});
  @override
  State<TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<TaskEditor> {
  late Task e;
  late bool isNew;
  final title = TextEditingController();
  final desc = TextEditingController();
  final msg = TextEditingController();
  final notes = TextEditingController();
  final every = TextEditingController();

  @override
  void initState() {
    super.initState();
    isNew = widget.task == null;
    if (!isNew) {
      e = widget.task!.copy();
    } else {
      final d = DateTime.now().add(const Duration(hours: 1));
      final rounded = DateTime(d.year, d.month, d.day, d.hour, ((d.minute + 14) ~/ 15) * 15);
      e = widget.preset?.copy() ?? Task(id: '', date: ymd(rounded), time: hm(rounded), advance: [10]);
      e.id = '';
    }
    title.text = e.title;
    desc.text = e.description;
    msg.text = e.message;
    notes.text = e.notes;
    every.text = '${e.repeat.every < 1 ? 2 : e.repeat.every}';
  }

  @override
  void dispose() {
    for (final c in [title, desc, msg, notes, every]) {
      c.dispose();
    }
    super.dispose();
  }

  void _read() {
    e.title = title.text.trim();
    e.description = desc.text.trim();
    e.message = msg.text.trim();
    e.notes = notes.text.trim();
    if (e.repeat.type == 'custom') e.repeat.every = int.tryParse(every.text) ?? 1;
  }

  Future<void> _pickDate() async {
    final cur = parseLocal(e.date, e.time);
    final d = await showDatePicker(
      context: context,
      initialDate: cur,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => e.date = ymd(d));
  }

  Future<void> _pickTime() async {
    final cur = parseLocal(e.date, e.time);
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: cur.hour, minute: cur.minute),
      builder: (c, child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: ctl.h24), child: child ?? const SizedBox()),
    );
    if (t != null) setState(() => e.time = '${pad2(t.hour)}:${pad2(t.minute)}');
  }

  Future<void> _pickUntil() async {
    final d = await showDatePicker(
      context: context,
      initialDate: e.repeat.until.isNotEmpty ? parseLocal(e.repeat.until, '12:00') : addDays(DateTime.now(), 30),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Repeat until',
    );
    if (d != null) setState(() => e.repeat.until = ymd(d));
  }

  Future<void> _preview() async {
    _read();
    final t = e.copy();
    if (t.title.isEmpty) t.title = 'your task';
    final text = await Native.buildMessage(
        jsonEncode(t.toJson()), parseLocal(e.date, e.time).millisecondsSinceEpoch, 'due', 0, ctl.settingsJson);
    if (text.isEmpty) return;
    await Native.speak(text, ctl.settingsJson, sound: true);
    toast('🔊 $text');
  }

  Future<void> _save() async {
    _read();
    if (e.title.isEmpty) {
      toast('Please enter a task title');
      return;
    }
    if (e.repeat.type == 'none') e.repeat = RepeatRule();
    await ctl.saveTask(e, isNew: isNew);
    if (!mounted) return;
    Navigator.pop(context);
    final saved = isNew ? (ctl.s.tasks.isNotEmpty ? ctl.s.tasks.last : e) : (ctl.s.task(e.id) ?? e);
    final o = pendingOcc(saved);
    toast(o != null && o.isAfter(DateTime.now())
        ? 'Saved — I\'ll speak to you ${fmtDay(o).toLowerCase()} at ${ctl.fmtT(o)}'
        : 'Saved');
  }

  Future<void> _delete() async {
    if (!await confirm(context, 'Delete "${e.title}"?', ok: 'Delete', danger: true)) return;
    await ctl.delete(e);
    if (mounted) Navigator.pop(context);
    toast('Task deleted');
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6, top: 14),
        child: Text(s, style: TextStyle(fontWeight: FontWeight.w700, color: mutedColor(context), fontSize: 14)),
      );

  Widget _dayChips() {
    final sel = e.repeat.days.isEmpty ? [jsDow(parseLocal(e.date, e.time))] : e.repeat.days;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final d in [1, 2, 3, 4, 5, 6, 0])
          FilterChip(
            label: Text(wdShort[d]),
            selected: sel.contains(d),
            onSelected: (v) => setState(() {
              final days = [...sel];
              if (days.contains(d)) {
                days.remove(d);
              } else {
                days.add(d);
              }
              e.repeat.days = days.isEmpty ? [d] : days;
            }),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final when = parseLocal(e.date, e.time);
    final past = e.repeat.type == 'none' && when.isBefore(DateTime.now());
    return Scaffold(
      appBar: AppBar(
        title: Text(isNew ? 'New task' : 'Edit task', style: const TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          if (!isNew) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline, color: kBad), tooltip: 'Delete'),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 30), children: [
          _label('Task title *'),
          TextField(
            controller: title,
            autofocus: isNew && e.title.isEmpty,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 17),
            decoration: const InputDecoration(hintText: 'e.g. Attend a business meeting'),
          ),
          _label('Description'),
          TextField(
            controller: desc,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Details you want to hear in the reminder'),
          ),
          _label('Date and time'),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today),
                label: Text(fmtDay(when), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule),
                label: Text(ctl.fmtT(when), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
          if (past)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: kWarn.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(14)),
              child: const Text('⚠️ This time has already passed, so no reminder will play. Choose a future time to hear it.'),
            ),
          _label('Category'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final k in cats.keys)
              ChoiceChip(
                label: Text('${cats[k]!.emoji} $k'),
                selected: e.category == k,
                onSelected: (_) => setState(() => e.category = k),
              ),
          ]),
          _label('Priority'),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'low', label: Text('Low')),
              ButtonSegment(value: 'medium', label: Text('Medium')),
              ButtonSegment(value: 'high', label: Text('High')),
            ],
            selected: {e.priority},
            onSelectionChanged: (v) => setState(() => e.priority = v.first),
          ),
          _label('Repeat'),
          DropdownButton<String>(
            isExpanded: true,
            value: e.repeat.type.isEmpty ? 'none' : e.repeat.type,
            items: const [
              DropdownMenuItem(value: 'none', child: Text('Does not repeat')),
              DropdownMenuItem(value: 'daily', child: Text('Every day')),
              DropdownMenuItem(value: 'weekly', child: Text('Every week (choose days)')),
              DropdownMenuItem(value: 'monthly', child: Text('Every month')),
              DropdownMenuItem(value: 'custom', child: Text('Custom…')),
            ],
            onChanged: (v) => setState(() => e.repeat.type = v ?? 'none'),
          ),
          if (e.repeat.type == 'weekly') _dayChips(),
          if (e.repeat.type == 'custom') ...[
            Row(children: [
              const Text('Every  ', style: TextStyle(fontSize: 16)),
              SizedBox(
                width: 70,
                child: TextField(controller: every, keyboardType: TextInputType.number, textAlign: TextAlign.center),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: e.repeat.unit.isEmpty ? 'day' : e.repeat.unit,
                items: const [
                  DropdownMenuItem(value: 'day', child: Text('days')),
                  DropdownMenuItem(value: 'week', child: Text('weeks')),
                  DropdownMenuItem(value: 'month', child: Text('months')),
                ],
                onChanged: (v) => setState(() => e.repeat.unit = v ?? 'day'),
              ),
            ]),
            if (e.repeat.unit == 'week') _dayChips(),
          ],
          if (e.repeat.type != 'none')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickUntil,
                    icon: const Icon(Icons.event_busy),
                    label: Text(e.repeat.until.isEmpty
                        ? 'Ends: never (tap to set)'
                        : 'Ends on ${fmtDay(parseLocal(e.repeat.until, '12:00'))}'),
                  ),
                ),
                if (e.repeat.until.isNotEmpty)
                  IconButton(onPressed: () => setState(() => e.repeat.until = ''), icon: const Icon(Icons.close)),
              ]),
            ),
          _label('Reminders'),
          Text('🔔 Always at the scheduled time. Add early reminders:', style: TextStyle(color: mutedColor(context))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in const [5, 10, 15, 30, 60])
              FilterChip(
                label: Text(m < 60 ? '$m min before' : '1 hour before'),
                selected: e.advance.contains(m),
                onSelected: (v) => setState(() {
                  if (e.advance.contains(m)) {
                    e.advance.remove(m);
                  } else {
                    e.advance.add(m);
                    e.advance.sort();
                  }
                }),
              ),
          ]),
          _label('What should the reminder say? (optional)'),
          TextField(
            controller: msg,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                hintText: "Hello! It is time for your evening walk. Don't forget to take care of your health."),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Leave empty for an automatic message. You can use {title}, {time} and {date}.',
                style: TextStyle(color: mutedColor(context), fontSize: 13)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(onPressed: _preview, icon: const Icon(Icons.volume_up), label: const Text('Hear it')),
          ),
          _label('Notes'),
          TextField(
            controller: notes,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Bring the contract'),
          ),
          const SizedBox(height: 22),
          BigButton(isNew ? 'Save task' : 'Save changes',
              icon: Icons.check, bg: Theme.of(context).colorScheme.primary, fg: Colors.white, onPressed: _save),
        ]),
      ),
    );
  }
}
